###############################################################################
# BOOTSTRAP STACK — run ONCE, manually, from your laptop with admin credentials.
#
# Creates the things every environment shares and that CI/CD needs before it
# can do anything:
#   1. S3 bucket for Terraform remote state (versioned, encrypted, private)
#   2. ECR repositories for the backend & frontend images (build once, deploy
#      the SAME image to staging and then prod)
#   3. GitHub OIDC provider + 3 IAM roles, so GitHub Actions gets short-lived
#      AWS credentials — no long-lived access keys stored in GitHub.
#
# Its own state is kept locally (terraform.tfstate in this folder). Back it up,
# or migrate it into the bucket afterwards (see README, Phase 3).
###############################################################################

terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  state_bucket = "${var.project}-tfstate-${local.account_id}"
  repo         = "${var.github_owner}/${var.github_repo}"

  # GitHub's OIDC "sub" claim starts with "repo:<owner>/<repo>" by default, or
  # "repo:<owner>@<owner_id>/<repo>@<repo_id>" when the repo uses immutable subjects.
  # Check yours: gh api repos/OWNER/REPO/actions/oidc/customization/sub
  sub_prefix = (
    var.github_owner_id != null && var.github_repo_id != null
    ? "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}"
    : "repo:${local.repo}"
  )
}

# --------------------------------------------------------------------------
# 1. Terraform state bucket
# --------------------------------------------------------------------------
resource "aws_s3_bucket" "tfstate" {
  bucket = local.state_bucket

  lifecycle {
    prevent_destroy = true # losing state = Terraform forgets your infrastructure
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled" # lets you roll back a corrupted state file
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --------------------------------------------------------------------------
# 2. ECR repositories (shared by all environments)
# --------------------------------------------------------------------------
resource "aws_ecr_repository" "app" {
  for_each             = toset(["backend", "frontend"])
  name                 = "${var.project}/${each.key}"
  image_tag_mutability = "IMMUTABLE" # a tag (git SHA) can never be overwritten

  image_scanning_configuration {
    scan_on_push = true # free basic CVE scan on every push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = aws_ecr_repository.app
  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the last 30 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 30
      }
      action = { type = "expire" }
    }]
  })
}

# --------------------------------------------------------------------------
# 3. GitHub Actions OIDC federation
# --------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"] # AWS no longer checks this for GitHub, but the field is required
}

# Helper: build a trust policy that only lets *this repo* assume the role,
# optionally only from specific branches / GitHub environments.
data "aws_iam_policy_document" "trust" {
  for_each = {
    plan   = ["${local.sub_prefix}:pull_request", "${local.sub_prefix}:ref:refs/heads/main"]
    apply  = ["${local.sub_prefix}:environment:staging", "${local.sub_prefix}:environment:production"]
    deploy = ["${local.sub_prefix}:environment:staging", "${local.sub_prefix}:environment:production", "${local.sub_prefix}:ref:refs/heads/main"]
  }

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = each.value
    }
  }
}

# --- Role A: terraform plan (read-only, used on pull requests) ---
resource "aws_iam_role" "tf_plan" {
  name               = "${var.project}-gha-terraform-plan"
  assume_role_policy = data.aws_iam_policy_document.trust["plan"].json
}

resource "aws_iam_role_policy_attachment" "tf_plan_readonly" {
  role       = aws_iam_role.tf_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ReadOnlyAccess can't write the state lock file, so allow exactly that.
resource "aws_iam_role_policy" "tf_plan_state" {
  name = "state-lock"
  role = aws_iam_role.tf_plan.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.tfstate.arn}/*.tflock"
      },
      {
        # Plan has to read the generated DB password secret to diff it
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${local.account_id}:secret:${var.project}-*"
      }
    ]
  })
}

# --- Role B: terraform apply (admin, ONLY from protected GitHub environments) ---
resource "aws_iam_role" "tf_apply" {
  name               = "${var.project}-gha-terraform-apply"
  assume_role_policy = data.aws_iam_policy_document.trust["apply"].json
}

resource "aws_iam_role_policy_attachment" "tf_apply_admin" {
  role       = aws_iam_role.tf_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# --- Role C: application deploy (least privilege: push images + roll ECS) ---
resource "aws_iam_role" "deploy" {
  name               = "${var.project}-gha-deploy"
  assume_role_policy = data.aws_iam_policy_document.trust["deploy"].json
}

resource "aws_iam_role_policy" "deploy" {
  name = "deploy"
  role = aws_iam_role.deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "EcrPushPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:CompleteLayerUpload",
          "ecr:DescribeImages", "ecr:GetDownloadUrlForLayer", "ecr:InitiateLayerUpload",
          "ecr:PutImage", "ecr:UploadLayerPart"
        ]
        Resource = [for r in aws_ecr_repository.app : r.arn]
      },
      {
        Sid    = "EcsDeploy"
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices", "ecs:DescribeTaskDefinition", "ecs:DescribeTasks",
          "ecs:RegisterTaskDefinition", "ecs:UpdateService", "ecs:RunTask", "ecs:ListTasks",
          "ecs:TagResource"
        ]
        Resource = "*"
      },
      {
        Sid      = "PassTaskRoles"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = "arn:aws:iam::${local.account_id}:role/${var.project}-*"
        Condition = {
          StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
      },
      {
        Sid      = "ReadMigrationLogs"
        Effect   = "Allow"
        Action   = ["logs:GetLogEvents", "logs:FilterLogEvents"]
        Resource = "*"
      },
      {
        Sid      = "ReadStackOutputs"
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:DescribeLoadBalancers"]
        Resource = "*"
      }
    ]
  })
}

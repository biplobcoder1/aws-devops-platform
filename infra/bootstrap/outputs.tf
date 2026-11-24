output "state_bucket" {
  description = "Put this in infra/terraform/envs/*.backend.hcl"
  value       = aws_s3_bucket.tfstate.bucket
}

output "ecr_repositories" {
  value = { for k, r in aws_ecr_repository.app : k => r.repository_url }
}

output "ecr_registry" {
  value = split("/", aws_ecr_repository.app["backend"].repository_url)[0]
}

output "github_role_arns" {
  description = "Add these as GitHub repository variables (see README Phase 5)"
  value = {
    AWS_TF_PLAN_ROLE_ARN  = aws_iam_role.tf_plan.arn
    AWS_TF_APPLY_ROLE_ARN = aws_iam_role.tf_apply.arn
    AWS_DEPLOY_ROLE_ARN   = aws_iam_role.deploy.arn
  }
}

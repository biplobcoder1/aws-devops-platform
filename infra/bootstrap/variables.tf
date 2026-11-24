variable "project" {
  description = "Short project name, used as a prefix for every resource"
  type        = string
  default     = "taskflow"
}

variable "aws_region" {
  description = "AWS region (us-west-2 = Oregon)"
  type        = string
  default     = "us-west-2"
}

variable "github_owner" {
  description = "GitHub user or organization that owns the repo, e.g. mkmahmud"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name, e.g. aws-devops-platform"
  type        = string
}

variable "github_owner_id" {
  description = "Numeric GitHub owner ID. Set it (with github_repo_id) when the repo uses immutable OIDC subjects."
  type        = string
  default     = null
}

variable "github_repo_id" {
  description = "Numeric GitHub repository ID. Set it (with github_owner_id) when the repo uses immutable OIDC subjects."
  type        = string
  default     = null
}

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

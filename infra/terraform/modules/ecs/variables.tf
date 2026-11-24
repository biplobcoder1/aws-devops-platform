variable "name" {
  type = string
}

variable "environment" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "backend_image_repo" {
  description = "ECR repository URL (without tag) for the backend"
  type        = string
}

variable "frontend_image_repo" {
  description = "ECR repository URL (without tag) for the frontend"
  type        = string
}

variable "image_tag" {
  description = "Image tag used when Terraform first creates the task definitions. CI/CD changes it afterwards."
  type        = string
}

variable "backend_target_group_arn" {
  type = string
}

variable "frontend_target_group_arn" {
  type = string
}

variable "db_host" {
  type = string
}

variable "db_port" {
  type = number
}

variable "db_name" {
  type = string
}

variable "db_secret_arn" {
  type = string
}

variable "backend_cpu" {
  type    = number
  default = 256
}

variable "backend_memory" {
  type    = number
  default = 512
}

variable "backend_min_count" {
  type    = number
  default = 1
}

variable "backend_max_count" {
  type    = number
  default = 3
}

variable "frontend_cpu" {
  type    = number
  default = 256
}

variable "frontend_memory" {
  type    = number
  default = 512
}

variable "frontend_min_count" {
  type    = number
  default = 1
}

variable "frontend_max_count" {
  type    = number
  default = 3
}

variable "use_fargate_spot" {
  description = "Run on Spot capacity (~70% cheaper, can be interrupted). Good for staging."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  type    = number
  default = 14
}

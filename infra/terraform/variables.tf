variable "project" {
  type    = string
  default = "taskflow"
}

variable "environment" {
  description = "staging | prod"
  type        = string
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be staging or prod"
  }
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

# ---------- Network ----------
variable "vpc_cidr" {
  type = string
}

variable "az_count" {
  type    = number
  default = 2
}

variable "single_nat_gateway" {
  type    = bool
  default = true
}

# ---------- Images ----------
variable "image_tag" {
  description = "Image tag for the FIRST apply only (afterwards CI/CD sets the running version)"
  type        = string
  default     = "initial"
}

# ---------- Database ----------
variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "db_multi_az" {
  type    = bool
  default = false
}

variable "deletion_protection" {
  type    = bool
  default = false
}

# ---------- Compute ----------
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
  type    = bool
  default = false
}

# ---------- DNS / alerts ----------
variable "domain_name" {
  description = "Optional, e.g. staging.example.com. Empty = use the ALB URL over HTTP."
  type        = string
  default     = ""
}

variable "route53_zone_name" {
  type    = string
  default = ""
}

variable "alert_email" {
  type    = string
  default = ""
}

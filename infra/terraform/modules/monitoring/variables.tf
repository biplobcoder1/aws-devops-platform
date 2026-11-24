variable "name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "alert_email" {
  type    = string
  default = ""
}

variable "alb_arn_suffix" {
  type = string
}

variable "target_group_arn_suffixes" {
  type = map(string)
}

variable "ecs_cluster_name" {
  type = string
}

variable "ecs_service_names" {
  type = map(string)
}

variable "rds_instance_id" {
  type = string
}

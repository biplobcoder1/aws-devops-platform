variable "name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "az_count" {
  type    = number
  default = 2
}

variable "single_nat_gateway" {
  description = "true = 1 NAT for all AZs (cheaper, staging). false = 1 NAT per AZ (HA, prod)"
  type        = bool
  default     = true
}

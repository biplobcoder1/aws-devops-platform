variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "domain_name" {
  description = "e.g. app.example.com. Leave empty to use the plain ALB DNS name over HTTP."
  type        = string
  default     = ""
}

variable "route53_zone_name" {
  description = "Hosted zone that owns domain_name, e.g. example.com"
  type        = string
  default     = ""
}

variable "deletion_protection" {
  type    = bool
  default = false
}

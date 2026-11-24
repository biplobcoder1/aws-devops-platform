output "alb_arn_suffix" {
  value = aws_lb.this.arn_suffix
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "app_url" {
  value = var.domain_name != "" ? "https://${var.domain_name}" : "http://${aws_lb.this.dns_name}"
}

output "frontend_target_group_arn" {
  value = aws_lb_target_group.frontend.arn
}

output "backend_target_group_arn" {
  value = aws_lb_target_group.backend.arn
}

output "frontend_target_group_arn_suffix" {
  value = aws_lb_target_group.frontend.arn_suffix
}

output "backend_target_group_arn_suffix" {
  value = aws_lb_target_group.backend.arn_suffix
}

# The ECS services must wait until the listener rules exist
output "listener_arns" {
  value = compact([aws_lb_listener.http.arn, try(aws_lb_listener.https[0].arn, "")])
}

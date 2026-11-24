output "app_url" {
  description = "Open this in your browser"
  value       = module.alb.app_url
}

output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "ecs_cluster" {
  value = module.ecs.cluster_name
}

output "ecs_services" {
  value = module.ecs.service_names
}

output "rds_endpoint" {
  value = module.rds.endpoint
}

output "db_secret_arn" {
  value = module.rds.secret_arn
}

output "cloudwatch_dashboard" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${module.monitoring.dashboard_name}"
}

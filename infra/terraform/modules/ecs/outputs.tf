output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "service_names" {
  value = { for k, s in aws_ecs_service.svc : k => s.name }
}

output "task_definition_families" {
  value = { for k, t in aws_ecs_task_definition.svc : k => t.family }
}

output "log_groups" {
  value = { for k, g in aws_cloudwatch_log_group.svc : k => g.name }
}

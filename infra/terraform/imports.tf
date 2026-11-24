# One-off recovery: a cancelled apply created the staging RDS instance in AWS
# but never recorded it in state. This adopts it on the next apply.
# Scoped to staging so prod (where no such instance exists yet) is unaffected.
# Safe to delete once the staging apply has succeeded.
import {
  for_each = var.environment == "staging" ? toset(["taskflow-staging"]) : toset([])
  to       = module.rds.aws_db_instance.this
  id       = each.value
}

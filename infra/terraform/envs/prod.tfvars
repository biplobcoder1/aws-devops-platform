# PRODUCTION: highly available (NAT + DB in multiple AZs), on-demand capacity,
# protected against accidental deletion.
project     = "taskflow"
environment = "prod"
aws_region  = "us-west-2"

vpc_cidr           = "10.20.0.0/16"
az_count           = 2
single_nat_gateway = false

db_instance_class    = "db.t4g.small"
db_allocated_storage = 20
db_multi_az          = true
deletion_protection  = true

backend_cpu        = 512
backend_memory     = 1024
backend_min_count  = 2
backend_max_count  = 6
frontend_min_count = 2
frontend_max_count = 4
use_fargate_spot   = false

domain_name       = ""
route53_zone_name = ""

alert_email = "mkmahmud.dev2@gmail.com"

# STAGING: cheap, single NAT, Spot capacity, no deletion protection.
project     = "taskflow"
environment = "staging"
aws_region  = "us-west-2"

vpc_cidr           = "10.10.0.0/16"
az_count           = 2
single_nat_gateway = true

db_instance_class    = "db.t4g.micro"
db_allocated_storage = 20
db_multi_az          = false
deletion_protection  = false

backend_min_count  = 1
backend_max_count  = 2
frontend_min_count = 1
frontend_max_count = 2
use_fargate_spot   = true

# Optional: real domain with HTTPS (requires a Route 53 hosted zone you own)
domain_name       = ""
route53_zone_name = ""

alert_email = "mkmahmud.dev2@gmail.com"

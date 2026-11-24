###############################################################################
# Environment stack (staging or prod). Same code, different .tfvars.
#
#   terraform init  -backend-config=envs/staging.backend.hcl
#   terraform plan  -var-file=envs/staging.tfvars
###############################################################################

locals {
  name = "${var.project}-${var.environment}"
}

data "aws_ecr_repository" "backend" {
  name = "${var.project}/backend"
}

data "aws_ecr_repository" "frontend" {
  name = "${var.project}/frontend"
}

module "network" {
  source             = "./modules/network"
  name               = local.name
  aws_region         = var.aws_region
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  single_nat_gateway = var.single_nat_gateway
}

module "rds" {
  source              = "./modules/rds"
  name                = local.name
  subnet_ids          = module.network.private_subnet_ids
  security_group_id   = aws_security_group.db.id
  instance_class      = var.db_instance_class
  allocated_storage   = var.db_allocated_storage
  multi_az            = var.db_multi_az
  deletion_protection = var.deletion_protection
}

module "alb" {
  source              = "./modules/alb"
  name                = local.name
  vpc_id              = module.network.vpc_id
  public_subnet_ids   = module.network.public_subnet_ids
  security_group_id   = aws_security_group.alb.id
  domain_name         = var.domain_name
  route53_zone_name   = var.route53_zone_name
  deletion_protection = var.deletion_protection
}

module "ecs" {
  source              = "./modules/ecs"
  name                = local.name
  environment         = var.environment
  private_subnet_ids  = module.network.private_subnet_ids
  security_group_id   = aws_security_group.app.id
  backend_image_repo  = data.aws_ecr_repository.backend.repository_url
  frontend_image_repo = data.aws_ecr_repository.frontend.repository_url
  image_tag           = var.image_tag

  backend_target_group_arn  = module.alb.backend_target_group_arn
  frontend_target_group_arn = module.alb.frontend_target_group_arn

  db_host       = module.rds.endpoint
  db_port       = module.rds.port
  db_name       = module.rds.db_name
  db_secret_arn = module.rds.secret_arn

  backend_cpu        = var.backend_cpu
  backend_memory     = var.backend_memory
  backend_min_count  = var.backend_min_count
  backend_max_count  = var.backend_max_count
  frontend_cpu       = var.frontend_cpu
  frontend_memory    = var.frontend_memory
  frontend_min_count = var.frontend_min_count
  frontend_max_count = var.frontend_max_count
  use_fargate_spot   = var.use_fargate_spot
  log_retention_days = var.environment == "prod" ? 30 : 14

  # Target groups must be attached to a listener before ECS can register tasks
  depends_on = [module.alb]
}

module "monitoring" {
  source         = "./modules/monitoring"
  name           = local.name
  aws_region     = var.aws_region
  alert_email    = var.alert_email
  alb_arn_suffix = module.alb.alb_arn_suffix
  target_group_arn_suffixes = {
    backend  = module.alb.backend_target_group_arn_suffix
    frontend = module.alb.frontend_target_group_arn_suffix
  }
  ecs_cluster_name  = module.ecs.cluster_name
  ecs_service_names = module.ecs.service_names
  rds_instance_id   = module.rds.instance_id
}

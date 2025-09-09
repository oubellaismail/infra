# Single shared VPC
resource "digitalocean_vpc" "main" {
  name   = "devsecops-vpc"
  region = var.region
}

# STAGING stack
module "staging" {
  source            = "./modules/stack"
  env_name          = "staging"
  region            = var.region
  vpc_uuid          = digitalocean_vpc.main.id
  ssh_key_ids       = var.ssh_key_ids
  allowed_admin_cidrs = var.allowed_admin_cidrs
  app_port          = var.app_port

  bastion_size      = var.bastion_size
  frontend_size     = var.staging_frontend_size
  backend_size      = var.staging_backend_size

  db_engine         = var.db_engine
  db_version        = var.db_version
}

# PRODUCTION stack
module "production" {
  source            = "./modules/stack"
  env_name          = "production"
  region            = var.region
  vpc_uuid          = digitalocean_vpc.main.id
  ssh_key_ids       = var.ssh_key_ids
  allowed_admin_cidrs = var.allowed_admin_cidrs
  app_port          = var.app_port

  bastion_size      = var.bastion_size
  frontend_size     = var.production_frontend_size
  backend_size      = var.production_backend_size

  db_engine         = var.db_engine
  db_version        = var.db_version
}

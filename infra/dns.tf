# Root domain linked to DO
resource "digitalocean_domain" "main" {
  name       = "3assasa.software"
  ip_address = module.production.frontend_public_ip
}

################################
# Production Public DNS
################################
resource "digitalocean_record" "production_frontend_public" {
  domain = digitalocean_domain.main.name
  type   = "A"
  name   = "@"
  value  = module.production.frontend_public_ip
}

resource "digitalocean_record" "production_bastion" {
  domain = digitalocean_domain.main.name
  type   = "A"
  name   = "bastion.production"
  value  = module.production.bastion_public_ip
}

################################
# Staging Public DNS
################################
resource "digitalocean_record" "staging_frontend_public" {
  domain = digitalocean_domain.main.name
  type   = "A"
  name   = "staging"
  value  = module.staging.frontend_public_ip
}

resource "digitalocean_record" "staging_bastion" {
  domain = digitalocean_domain.main.name
  type   = "A"
  name   = "bastion.staging"
  value  = module.staging.bastion_public_ip
}

################################
# Production Private DNS (internal)
################################
resource "digitalocean_record" "production_backend_private" {
  domain = digitalocean_domain.main.name
  type   = "A"
  name   = "backend-private.production"
  value  = module.production.backend_private_ip
}

resource "digitalocean_record" "production_frontend_private" {
  domain = digitalocean_domain.main.name
  type   = "A"
  name   = "frontend-private.production"
  value  = module.production.frontend_private_ip
}

################################
# Staging Private DNS (internal)
################################
resource "digitalocean_record" "staging_backend_private" {
  domain = digitalocean_domain.main.name
  type   = "A"
  name   = "backend-private.staging"
  value  = module.staging.backend_private_ip
}

resource "digitalocean_record" "staging_frontend_private" {
  domain = digitalocean_domain.main.name
  type   = "A"
  name   = "frontend-private.staging"
  value  = module.staging.frontend_private_ip
}

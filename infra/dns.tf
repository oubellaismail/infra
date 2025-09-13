# This resource links your domain to your DigitalOcean account for DNS management
resource "digitalocean_domain" "main" {
  name = "3assasa.software"
  ip_address = module.production.frontend_public_ip
}

# Staging subdomains
resource "digitalocean_record" "staging_frontend" {
  domain = digitalocean_domain.main.name
  type   = "A"
  name   = "staging"
  value  = module.staging.frontend_public_ip
}

# Production subdomains
resource "digitalocean_record" "production_frontend" {
  domain = digitalocean_domain.main.name
  type   = "A"
  name   = "@"
  value  = module.production.frontend_public_ip
}

# We do not create public DNS records for the backend droplets as they are private
# and should not be accessible from the public internet.
# If you need to access the backend services, consider using a VPN or SSH tunneling.
# Alternatively, you can set up internal DNS records if your infrastructure supports it.
# Staging
output "staging_bastion_ip" {
  value       = module.staging.bastion_public_ip
  description = "Staging bastion public IPv4"
}
output "staging_frontend_ip" {
  value       = module.staging.frontend_public_ip
  description = "Staging frontend public IPv4"
}
output "staging_backend_private_ip" {
  value       = module.staging.backend_private_ip
  description = "Staging backend private IPv4"
}
output "staging_db_host" {
  value       = module.staging.db_host
  description = "Staging DB host (prefers private host)"
}

# Production
output "production_bastion_ip" {
  value       = module.production.bastion_public_ip
  description = "Production bastion public IPv4"
}
output "production_frontend_ip" {
  value       = module.production.frontend_public_ip
  description = "Production frontend public IPv4"
}
output "production_backend_private_ip" {
  value       = module.production.backend_private_ip
  description = "Production backend private IPv4"
}
output "production_db_host" {
  value       = module.production.db_host
  description = "Production DB host (prefers private host)"
}

output "staging_frontend_hostname" {
  value       = digitalocean_record.staging_frontend.fqdn
  description = "The FQDN for the staging frontend"
}

output "production_frontend_hostname" {
  value       = digitalocean_domain.main.name
  description = "The FQDN for the production frontend"
}
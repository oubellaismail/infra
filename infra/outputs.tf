######################################
# Staging DNS Outputs
######################################

output "staging_bastion_dns" {
  value       = digitalocean_record.staging_bastion.fqdn
  description = "Staging bastion DNS hostname"
}

output "staging_frontend_public_dns" {
  value       = digitalocean_record.staging_frontend_public.fqdn
  description = "Staging frontend public DNS hostname"
}

output "staging_frontend_private_dns" {
  value       = digitalocean_record.staging_frontend_private.fqdn
  description = "Staging frontend private DNS hostname"
}

output "staging_backend_private_dns" {
  value       = digitalocean_record.staging_backend_private.fqdn
  description = "Staging backend private DNS hostname"
}

# Database host (still provided by DO cluster, not DNS-managed)
output "staging_db_host" {
  value       = module.staging.db_host
  description = "Staging DB host (prefers private host)"
}

######################################
# Production DNS Outputs
######################################

output "production_bastion_dns" {
  value       = digitalocean_record.production_bastion.fqdn
  description = "Production bastion DNS hostname"
}

output "production_frontend_public_dns" {
  value       = digitalocean_record.production_frontend_public.fqdn
  description = "Production frontend public DNS hostname"
}

output "production_frontend_private_dns" {
  value       = digitalocean_record.production_frontend_private.fqdn
  description = "Production frontend private DNS hostname"
}

output "production_backend_private_dns" {
  value       = digitalocean_record.production_backend_private.fqdn
  description = "Production backend private DNS hostname"
}

# Database host (still provided by DO cluster, not DNS-managed)
output "production_db_host" {
  value       = module.production.db_host
  description = "Production DB host (prefers private host)"
}

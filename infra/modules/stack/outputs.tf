output "bastion_public_ip" {
  value       = digitalocean_droplet.bastion.ipv4_address
  description = "Bastion public IPv4"
}

output "frontend_public_ip" {
  value       = digitalocean_droplet.frontend.ipv4_address
  description = "Frontend public IPv4"
}

output "backend_private_ip" {
  value       = digitalocean_droplet.backend.ipv4_address_private
  description = "Backend private IPv4 (VPC)"
}

output "db_host" {
  value       = digitalocean_database_cluster.db.private_host != "" ? digitalocean_database_cluster.db.private_host : digitalocean_database_cluster.db.host
  description = "DB host (prefers private host)"
}

output "frontend_private_ip" {
  value       = digitalocean_droplet.frontend.ipv4_address_private
  description = "Frontend private IPv4 (VPC)"
}
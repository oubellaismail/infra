package terraform.security

# --- Policy 1: Enforce Bastion Host as the only public SSH entry ---
# Deny any Droplet firewall from exposing port 22 to the public internet
# unless it is explicitly tagged as a bastion host.
deny[msg] {
  some rc in input.resource_changes
  rc.type == "digitalocean_firewall"
  rc.change.after.droplet_ids[_] == digitalocean_droplet.frontend.id
  inbound := rc.change.after.inbound_rule[_]
  inbound.protocol == "tcp"
  inbound.port_range == "22"
  inbound.source_addresses[_] == "0.0.0.0/0"
  msg := sprintf("Public SSH access is forbidden on the frontend firewall (%s). Use a bastion host.", [rc.address])
}

deny[msg] {
  some rc in input.resource_changes
  rc.type == "digitalocean_firewall"
  rc.change.after.droplet_ids[_] == digitalocean_droplet.backend.id
  inbound := rc.change.after.inbound_rule[_]
  inbound.protocol == "tcp"
  inbound.port_range == "22"
  inbound.source_addresses[_] == "0.0.0.0/0"
  msg := sprintf("Public SSH access is forbidden on the backend firewall (%s). Use a bastion host.", [rc.address])
}

# --- Policy 2: Enforce strict SSH source IP restrictions on the bastion ---
# Deny any bastion firewall from allowing SSH from the public internet.
deny[msg] {
  some rc in input.resource_changes
  rc.type == "digitalocean_firewall"
  startswith(rc.change.after.name, "bastion")
  rule := rc.change.after.inbound_rule[_]
  rule.protocol == "tcp"
  rule.port_range == "22"
  count(rule.source_addresses) == 0
  msg := sprintf("Bastion firewall %s must have a source IP CIDR for SSH access.", [rc.change.after.name])
}

package terraform.security

# --- Policy 3: Enforce the use of approved images ---
# Deny any Droplet from being created with an image that is not on the approved list.
deny[msg] {
  some rc in input.resource_changes
  rc.type == "digitalocean_droplet"
  allowed_images := {"ubuntu-22-04-x64", "debian-12-x64"}
  not allowed_images[rc.change.after.image]
  msg := sprintf("Droplet %s uses a disallowed image %s. Approved images are: %s.", [rc.change.after.name, rc.change.after.image, concat(", ", [allowed_images])])
}

# --- Policy 4: Enforce SSH key-based authentication ---
# Deny any Droplet without an SSH key.
deny[msg] {
  some rc in input.resource_changes
  rc.type == "digitalocean_droplet"
  count(rc.change.after.ssh_keys) == 0
  msg := sprintf("Droplet %s must have at least one SSH key configured.", [rc.change.after.name])
}

# --- Policy 5: Ensure fail2ban is installed on the bastion host ---
# This policy checks the user_data content for the 'fail2ban' package name.
deny[msg] {
  some rc in input.resource_changes
  rc.type == "digitalocean_droplet"
  startswith(rc.change.after.name, "bastion")
  user_data := rc.change.after.user_data
  not contains(user_data, "fail2ban")
  msg := sprintf("Bastion host %s must have fail2ban installed via user_data for security.", [rc.change.after.name])
}

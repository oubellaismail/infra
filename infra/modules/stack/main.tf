terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.43"
    }
  }
}

locals {
  # Consistent tags per environment
  tag_env        = "env:${var.env_name}"
  tag_bastion    = "role:bastion-${var.env_name}"
  tag_frontend   = "role:frontend-${var.env_name}"
  tag_backend    = "role:backend-${var.env_name}"
  tag_db         = "role:db-${var.env_name}"

  # --- IDEAL ---
  # A single, minimal cloud-init for ALL droplets.
  # Its only job is to update the package cache so Ansible can run reliably.
  # Ansible will handle all software installation and configuration.
  cloud_init_minimal = <<-EOF
  #cloud-config
  package_update: true
  package_upgrade: true
  EOF
}

# --- Droplets ---

resource "digitalocean_droplet" "bastion" {
  name       = "${var.env_name}-bastion"
  region     = var.region
  size       = var.bastion_size
  image      = var.image
  vpc_uuid   = var.vpc_uuid
  ssh_keys   = var.ssh_key_ids
  user_data  = local.cloud_init_minimal
  monitoring = true
  tags       = [local.tag_env, local.tag_bastion]
}

resource "digitalocean_droplet" "frontend" {
  name       = "${var.env_name}-frontend"
  region     = var.region
  size       = var.frontend_size
  image      = var.image
  vpc_uuid   = var.vpc_uuid
  ssh_keys   = var.ssh_key_ids
  user_data  = local.cloud_init_minimal
  monitoring = true
  tags       = [local.tag_env, local.tag_frontend, "app:frontend"]
}

resource "digitalocean_droplet" "backend" {
  name       = "${var.env_name}-backend"
  region     = var.region
  size       = var.backend_size
  image      = var.image
  vpc_uuid   = var.vpc_uuid
  ssh_keys   = var.ssh_key_ids
  user_data  = local.cloud_init_minimal
  monitoring = true
  tags       = [local.tag_env, local.tag_backend, "app:backend"]
}

# --- Firewalls ---

# Bastion: allow SSH only from admin CIDRs
resource "digitalocean_firewall" "bastion_fw" {
  name        = "${var.env_name}-bastion-fw"
  droplet_ids = [digitalocean_droplet.bastion.id]

  # SSH from trusted sources only
  dynamic "inbound_rule" {
    for_each = var.allowed_admin_cidrs
    content {
      protocol         = "tcp"
      port_range       = "22"
      source_addresses = [inbound_rule.value]
    }
  }

  # Optional: outbound open (tighten if you wish)
  outbound_rule {
    protocol              = "tcp"
    port_range            = "all"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
  outbound_rule {
    protocol              = "udp"
    port_range            = "all"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

# Frontend: public 80/443, SSH only from bastion
resource "digitalocean_firewall" "frontend_fw" {
  name        = "${var.env_name}-frontend-fw"
  droplet_ids = [digitalocean_droplet.frontend.id]

  # SSH only from bastion tag (env-scoped)
  inbound_rule {
    protocol    = "tcp"
    port_range  = "22"
    source_tags = [local.tag_bastion]
  }

  # Public HTTP/HTTPS
  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }
  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "all"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
  outbound_rule {
    protocol              = "udp"
    port_range            = "all"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

# Backend: SSH only via bastion; app port only from frontend
resource "digitalocean_firewall" "backend_fw" {
  name        = "${var.env_name}-backend-fw"
  droplet_ids = [digitalocean_droplet.backend.id]

  # SSH only from bastion
  inbound_rule {
    protocol    = "tcp"
    port_range  = "22"
    source_tags = [local.tag_bastion]
  }

  # FE -> BE on app_port
  inbound_rule {
    protocol    = "tcp"
    port_range  = tostring(var.app_port)
    source_tags = [local.tag_frontend]
  }

  # No public inbound to backend otherwise

  outbound_rule {
    protocol              = "tcp"
    port_range            = "all"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
  outbound_rule {
    protocol              = "udp"
    port_range            = "all"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

# --- Managed DB, isolated per env ---

resource "digitalocean_database_cluster" "db" {
  name                 = "${var.env_name}-db"
  engine               = var.db_engine
  version              = var.db_version
  size                 = "db-s-1vcpu-1gb"
  region               = var.region
  node_count           = 1
  private_network_uuid = var.vpc_uuid
  tags                 = [local.tag_env, local.tag_db]

  maintenance_window {
    day  = "monday"
    hour = "03:00"
  }
}

# Only allow the backend droplet to talk to this DB
resource "digitalocean_database_firewall" "db_fw" {
  cluster_id = digitalocean_database_cluster.db.id

  rule {
    type  = "droplet"
    value = digitalocean_droplet.backend.id
  }
}

resource "digitalocean_database_db" "db_name" {
  cluster_id = digitalocean_database_cluster.db.id
  name       = "delivery_tracker_${var.env_name}"
}

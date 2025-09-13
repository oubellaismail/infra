variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "DigitalOcean region"
  type        = string
  default     = "fra1"
}

variable "ssh_key_ids" {
  description = "List of DO SSH key IDs to install on droplets"
  type        = list(string)
}

variable "allowed_admin_cidrs" {
  description = "CIDRs allowed for SSH to bastion (e.g., your office IPs). Never 0.0.0.0/0."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for c in var.allowed_admin_cidrs : c != "0.0.0.0/0"])
    error_message = "Do not allow SSH from 0.0.0.0/0."
  }
}

variable "app_port" {
  description = "Private port used by frontend to reach backend"
  type        = number
  default     = 8080
}

# Sizes per env/role
variable "bastion_size" {
  type    = string
  default = "s-1vcpu-1gb"
}
variable "staging_frontend_size" {
  type    = string
  default = "s-1vcpu-2gb"
}
variable "staging_backend_size" {
  type    = string
  default = "s-2vcpu-2gb"
}
variable "production_frontend_size" {
  type    = string
  default = "s-2vcpu-4gb"
}
variable "production_backend_size" {
  type    = string
  default = "s-4vcpu-8gb"
}

# DB
variable "db_engine" {
  type    = string
  default = "pg"
}
variable "db_version" {
  type    = string
  default = "16"
}

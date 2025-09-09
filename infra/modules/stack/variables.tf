variable "env_name" {
  type        = string
  description = "Name of the environment (staging or production)"
}

variable "region" {
  type        = string
  description = "DigitalOcean region"
}

variable "vpc_uuid" {
  type        = string
  description = "The ID of the VPC to attach droplets to"
}

variable "ssh_key_ids" {
  type        = list(string)
  description = "List of SSH key IDs to provision on droplets"
}

variable "allowed_admin_cidrs" {
  type        = list(string)
  default     = []
  description = "CIDRs allowed to SSH into the bastion host"
}

variable "app_port" {
  type        = number
  default     = 8080
  description = "Private port used by frontend to reach backend"
}

variable "bastion_size" {
  type        = string
  description = "Droplet size for the bastion host"
}

variable "frontend_size" {
  type        = string
  description = "Droplet size for the frontend"
}

variable "backend_size" {
  type        = string
  description = "Droplet size for the backend"
}

variable "db_engine" {
  type        = string
  default     = "pg"
  description = "Database engine for the managed database"
}

variable "db_version" {
  type        = string
  default     = "16"
  description = "Database version"
}

variable "image" {
  type        = string
  default     = "ubuntu-22-04-x64"
  description = "Droplet base image"
}

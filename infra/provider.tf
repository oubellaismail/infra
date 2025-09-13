terraform {
  required_version = ">= 1.5.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.43"
    }
  }

  # Use Terraform Cloud/Enterprise for secure, locked state + drift UI
  backend "remote" {
    organization = "3assasa"
    workspaces {
      name = "devsecops-infra" # or use one workspace per env
    }
  }
}

provider "digitalocean" {
  token = var.do_token
}

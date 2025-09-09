# DevSecOps Ansible Configuration

This Ansible configuration automates the deployment and management of your DevSecOps infrastructure on DigitalOcean, including staging and production environments with bastion hosts, frontend (Angular), backend (Spring Boot), and managed PostgreSQL databases.

## Architecture Overview

A visual representation of the infrastructure showing Internet traffic flow through Frontend and Bastion hosts to a private Backend and managed PostgreSQL database for both Staging and Production environments.

## Directory Structure

```
ansible/
├── inventories/
│   └── terraform.yml           # Dynamic inventory configuration
├── group_vars/
│   ├── all.yml                 # Global variables
│   ├── bastion.yml             # Bastion-specific variables
│   ├── staging.yml             # Staging environment variables
│   └── prod.yml                # Production environment variables
├── roles/
│   ├── common/                 # Basic system setup
│   ├── ssh_hardening/          # SSH security configuration
│   ├── firewall/               # UFW firewall setup
│   ├── fail2ban/               # Intrusion prevention
│   ├── docker_runtime/         # Docker installation and config
│   ├── nginx_tls/              # Nginx with SSL/TLS
│   ├── app_backend/            # Spring Boot backend deployment
│   ├── app_frontend/           # Angular frontend deployment
│   ├── observability/          # Monitoring and logging
│   └── verify/                 # System verification checks
├── playbooks/
│   ├── bootstrap.yml           # Initial infrastructure setup
│   └── deploy.yml              # Application deployment
├── scripts/
│   ├── generate_inventory.py   # Dynamic inventory generator
│   ├── deploy.sh               # Deployment automation script
│   └── backup-system.sh        # System backup script
├── Makefile                    # Deployment automation
└── ansible.cfg                 # Ansible configuration
```

## Prerequisites

- **Terraform Infrastructure**: Ensure your Terraform configuration is deployed.
- **SSH Access**: SSH key configured for DigitalOcean droplets.
- **Ansible Installation**:
  ```bash
  pip install ansible ansible-lint
  ```

**Required Environment Variables:**

```bash
export DO_REGISTRY_TOKEN="your_do_registry_token"
export SLACK_WEBHOOK_URL="your_slack_webhook" # Optional
```

## Quick Start

### Generate Dynamic Inventory

```bash
make inventory
```

### Bootstrap Infrastructure (First Time Setup)

```bash
# Staging
make bootstrap ENV=staging

# Production
make bootstrap ENV=production
```

### Deploy Applications

```bash
# Staging
make deploy ENV=staging

# Production
make deploy ENV=production
```

## Deployment Commands

- `make check-syntax`: Validate playbook syntax.
- `make lint`: Run ansible-lint for best practices.
- `make verify ENV=staging`: Run health and configuration checks.
- `make db-migrate ENV=production`: Run database migrations.
- `make maintenance-on ENV=production`: Enable maintenance mode.
- `make security-update ENV=staging`: Apply security patches.
- `make renew-ssl ENV=production`: Renew Let's Encrypt certificates.

## Security Features

- **SSH Hardening**: Key-based auth only, hardened config.
- **Firewall**: UFW with a default-deny policy.
- **Fail2ban**: Brute-force protection for SSH and Nginx.
- **SSL/TLS**: Automated certificate management with Let's Encrypt.
- **Security Headers**: CSP, HSTS, and other headers to protect against web vulnerabilities.

## Monitoring and Observability

- **Metrics**: Prometheus Node Exporter for system metrics.
- **Health Checks**: Application-level health endpoints are monitored.
- **Logging**: Centralized application and system logs with rotation.
- **Alerting**: Slack integration for deployment and health status alerts.

## Backup Strategy

- Automated daily backups of configurations, logs, and application data.
- Backups are stored locally in `/opt/backups/` with a 30-day retention policy.

## Troubleshooting

- Check logs at `/var/log/ansible-deploy.log` on the control node.
- Run `make verify ENV=<environment>` to diagnose common issues.
- Use `make deploy VERBOSE=-vvv` for detailed deployment output.

---

## Inventories

### inventories/terraform.yml

```yaml
plugin: advanced_host_list
compose:
  ansible_host: ansible_host | default(inventory_hostname)
keyed_groups:
  - prefix: env
    key: env_name
  - prefix: role
    key: role
groups:
  bastion: "'bastion' in role"
  frontend: "'frontend' in role"
  backend: "'backend' in role"
  staging: "env_name == 'staging'"
  production: "env_name == 'production'"
  app_servers: "'frontend' in role or 'backend' in role"

# This file tells Ansible how to parse the dynamic inventory generated
# by the `scripts/generate_inventory.py` script. The actual host data
# will be sourced from `inventories/dynamic_hosts.yml`, which is
# created by the `make inventory` command.
```
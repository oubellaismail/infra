.PHONY: help bootstrap deploy verify clean check-syntax lint staging production inventory ssh-test

# Default variables
ENV ?= staging
TAGS ?= all
LIMIT ?= all
VERBOSE ?=
ANSIBLE_ARGS ?=

# Help target
help:
	@echo "Available targets:"
	@echo "  inventory      - Generate inventory from Terraform outputs"
	@echo "  ssh-test       - Test SSH connectivity for all environments"
	@echo "  bootstrap      - Run initial server setup (steps 1-12)"
	@echo "  deploy         - Deploy applications (steps 13-16)"
	@echo "  verify         - Run verification checks"
	@echo "  staging        - Deploy to staging environment"
	@echo "  production     - Deploy to production environment"
	@echo "  check-syntax   - Check playbook syntax"
	@echo "  lint           - Run ansible-lint"
	@echo "  clean          - Clean temporary files"
	@echo ""
	@echo "Environment variables:"
	@echo "  ENV=staging|production  - Target environment"
	@echo "  TAGS=tag1,tag2          - Run specific tags"
	@echo "  LIMIT=host1,host2       - Limit to specific hosts"
	@echo "  VERBOSE=-v|-vv|-vvv     - Verbosity level"

# Generate inventory from Terraform and test SSH connectivity
inventory:
	@echo "🔄 Generating inventory from Terraform..."
	@if [ -d "../infra" ]; then \
		cd ../infra && terraform output -json > ../ansible/terraform_outputs.json; \
		cd ../ansible && python3 scripts/generate_inventory.py; \
		echo "🔍 Testing SSH connectivity..."; \
		chmod +x scripts/dynamic-ssh-agent-test.sh; \
		./scripts/dynamic-ssh-agent-test.sh all; \
	else \
		echo "❌ Error: ../infra directory not found. Make sure Terraform is deployed first."; \
		exit 1; \
	fi

# Test SSH connectivity only (without regenerating inventory)
ssh-test:
	@echo "🔍 Testing SSH connectivity..."
	@chmod +x scripts/dynamic-ssh-agent-test.sh
	@./scripts/dynamic-ssh-agent-test.sh $(ENV)

# Test SSH connectivity for specific environment
ssh-test-staging:
	@$(MAKE) ssh-test ENV=staging

ssh-test-production:
	@$(MAKE) ssh-test ENV=production

# Test inventory
test-inventory:
	@echo "Testing inventory configuration..."
	@ansible-inventory --list -i inventories/from_terraform.yml

# Syntax checking
check-syntax:
	@echo "Checking Ansible playbook syntax..."
	@ansible-playbook playbooks/bootstrap.yml --syntax-check
	@ansible-playbook playbooks/deploy.yml --syntax-check

# Linting
lint:
	@echo "Running ansible-lint..."
	@ansible-lint playbooks/ roles/ --exclude=.github/

# Bootstrap infrastructure with SSH test first
bootstrap: ssh-test-$(ENV) check-syntax
	@echo "🚀 Bootstrapping $(ENV) environment..."
	ansible-playbook playbooks/bootstrap.yml \
		-i inventories/from_terraform.yml \
		-l $(ENV) \
		$(if $(TAGS),--tags $(TAGS)) \
		$(if $(LIMIT),--limit $(LIMIT)) \
		$(VERBOSE) $(ANSIBLE_ARGS)

# Deploy applications with SSH test first
deploy: ssh-test-$(ENV) check-syntax
	@echo "🚀 Deploying to $(ENV) environment..."
	ansible-playbook playbooks/deploy.yml \
		-i inventories/from_terraform.yml \
		-l $(ENV) \
		$(if $(TAGS),--tags $(TAGS)) \
		$(if $(LIMIT),--limit $(LIMIT)) \
		$(VERBOSE) $(ANSIBLE_ARGS)

# Full deployment (inventory + bootstrap + deploy)
full-deploy: inventory bootstrap deploy

# Verification
verify:
	@echo "Running verification checks on $(ENV)..."
	ansible-playbook playbooks/bootstrap.yml \
		-i inventories/from_terraform.yml \
		-l $(ENV) \
		--tags verify \
		$(VERBOSE)

# Environment-specific targets
staging:
	@$(MAKE) full-deploy ENV=staging

production:
	@$(MAKE) full-deploy ENV=production ANSIBLE_ARGS="--ask-vault-pass"

# Quick deployment (deploy only) with SSH test
quick-deploy: ssh-test-$(ENV)
	@$(MAKE) deploy ENV=$(ENV) TAGS=deploy

# Rollback (redeploy previous version)
rollback:
	@echo "Rolling back $(ENV) environment..."
	@$(MAKE) deploy ENV=$(ENV) ANSIBLE_ARGS="-e deploy_version=previous"

# Database operations
db-migrate:
	@echo "Running database migrations on $(ENV)..."
	ansible-playbook playbooks/deploy.yml \
		-i inventories/from_terraform.yml \
		-l $(ENV):&backend \
		--tags database,migrations \
		$(VERBOSE)

# Backup operations
backup:
	@echo "Running backup on $(ENV)..."
	ansible all -i inventories/from_terraform.yml \
		-l $(ENV) \
		-m shell -a "/opt/delivery-tracker/backup-{{ '{{' }} role {{ '}}' }}.sh" \
		$(VERBOSE)

# Health checks
health-check:
	@echo "Performing health checks on $(ENV)..."
	ansible all -i inventories/from_terraform.yml \
		-l $(ENV) \
		-m uri -a "url=http://localhost/health method=GET" \
		$(VERBOSE)

# SSL certificate renewal
renew-ssl:
	@echo "Renewing SSL certificates on $(ENV) frontend servers..."
	ansible-playbook -i inventories/from_terraform.yml \
		-l $(ENV):&frontend \
		-m command -a "certbot renew --nginx" \
		$(VERBOSE)

# Clean temporary files
clean:
	@echo "Cleaning temporary files..."
	@rm -rf retry/
	@rm -f *.retry
	@rm -f terraform_outputs.json
	@find . -name "*.pyc" -delete
	@find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

# Emergency maintenance mode
maintenance-on:
	@echo "Enabling maintenance mode on $(ENV)..."
	ansible frontend -i inventories/from_terraform.yml \
		-l $(ENV) \
		-m replace -a "dest=/etc/nginx/sites-enabled/* regexp='try_files.*' replace='return 503;'" \
		$(VERBOSE)
	ansible frontend -i inventories/from_terraform.yml \
		-l $(ENV) \
		-m service -a "name=nginx state=reloaded" \
		$(VERBOSE)

maintenance-off:
	@echo "Disabling maintenance mode on $(ENV)..."
	@$(MAKE) deploy ENV=$(ENV) TAGS=nginx

# Monitor logs
logs:
	@echo "Tailing logs from $(ENV) environment..."
	ansible all -i inventories/from_terraform.yml \
		-l $(ENV) \
		-m shell -a "tail -f /var/log/delivery-tracker/*.log" \
		$(VERBOSE)

# Security updates
security-update:
	@echo "Applying security updates to $(ENV)..."
	ansible all -i inventories/from_terraform.yml \
		-l $(ENV) \
		-m apt -a "upgrade=safe update_cache=yes" \
		-b $(VERBOSE)

# Ping test with automatic SSH connectivity test first
ping: ssh-test-$(ENV)
	@echo "Testing Ansible connectivity to $(ENV) hosts..."
	ansible all -i inventories/from_terraform.yml \
		-l $(ENV) \
		-m ping $(VERBOSE)

# Comprehensive infrastructure test
infra-test: inventory
	@echo "🧪 Running comprehensive infrastructure tests..."
	@echo "1. Testing SSH connectivity..."
	@./scripts/dynamic-ssh-agent-test.sh all
	@echo "2. Testing Ansible connectivity..."
	@ansible all -i inventories/from_terraform.yml -m ping $(VERBOSE)
	@echo "3. Checking droplet status..."
	@ansible all -i inventories/from_terraform.yml -m setup -a "filter=ansible_uptime_seconds" $(VERBOSE)
	@echo "✅ Infrastructure test complete!"

# SSH troubleshooting
ssh-troubleshoot:
	@echo "🔧 SSH Troubleshooting for $(ENV)..."
	@echo "1. Checking SSH agent..."
	@ssh-add -l || (echo "No SSH keys loaded. Loading..."; ssh-add ~/.ssh/digitalocean)
	@echo "2. Testing SSH connectivity..."
	@./scripts/dynamic-ssh-agent-test.sh $(ENV)
	@echo "3. Showing ansible SSH configuration..."
	@grep -A 10 "\[ssh_connection\]" ansible.cfg
	@echo "4. Testing direct ansible ping..."
	@ansible $(ENV) -i inventories/from_terraform.yml -m ping -vv || echo "❌ Ansible ping failed"
.PHONY: help inventory bootstrap deploy verify ssh-test clean lint check-syntax

# -------- Settings --------
ENV ?= staging                             # staging | production
ALLOWED_ENVS := staging production
INVENTORY := inventories/from_terraform.yml
VAULT_PASS ?= .vault_pass
SSH_KEY ?= ~/.ssh/digitalocean
ANSIBLE ?= ansible
ANSIBLE_PLAYBOOK ?= ansible-playbook
TAGS ?=
LIMIT ?=
VERBOSE ?=

# -------- Helpers --------
define assert_env
	@echo "Using ENV=$(ENV)"; \
	if ! echo "$(ALLOWED_ENVS)" | tr ' ' '\n' | grep -qx "$(ENV)"; then \
	  echo "❌ ENV must be one of: $(ALLOWED_ENVS)"; exit 1; \
	fi
endef

# -------- Help --------
help:
	@echo "Targets:"
	@echo "  inventory        Generate $(INVENTORY) from Terraform outputs"
	@echo "  verify           Ping and basic checks on hosts in ENV"
	@echo "  bootstrap        Run initial server setup (uses group_vars auto-loading)"
	@echo "  deploy           Deploy application to hosts in ENV"
	@echo "  ssh-test         Quick SSH agent / ProxyJump test for ENV"
	@echo "  lint             Run ansible-lint (if installed)"
	@echo "  clean            Remove logs and retry files"
	@echo ""
	@echo "Examples:"
	@echo "  make inventory"
	@echo "  make verify ENV=staging"
	@echo "  make bootstrap ENV=production"
	@echo "  make deploy ENV=staging TAGS=app_frontend"
	@echo ""

# -------- Inventory generation --------
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

# -------- Verify --------
verify: 
	$(call assert_env)
	@echo "🔍 Verifying connectivity to $(ENV) hosts..."
	@$(ANSIBLE) $(ENV) -i $(INVENTORY) -m ping $(VERBOSE) --vault-password-file .vault_pass
	@echo "ℹ️  Uptime sample:"
	@$(ANSIBLE) $(ENV) -i $(INVENTORY) -m setup -a 'filter=ansible_uptime_seconds' $(VERBOSE) --vault-password-file .vault_pass || true
	@echo "✅ Verify complete."

# -------- Bootstrap (server setup, security, docker, etc.) --------
bootstrap:
	$(call assert_env)
	@echo "🚀 Bootstrapping $(ENV) hosts..."
	@if grep -q "ansible_user: root" $(INVENTORY) 2>/dev/null || [ ! -f $(INVENTORY) ]; then \
		echo "🔄 Running initial bootstrap as root..."; \
		$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) playbooks/bootstrap.yml \
		  -l $(ENV) \
		  --vault-password-file $(VAULT_PASS) \
		  -u root \
		  $(if $(TAGS),--tags $(TAGS)) \
		  $(if $(LIMIT),--limit $(LIMIT)) \
		  $(VERBOSE); \
	else \
		echo "🔄 Running bootstrap as ansible user..."; \
		$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) playbooks/bootstrap.yml \
		  -l $(ENV) \
		  --vault-password-file $(VAULT_PASS) \
		  $(if $(TAGS),--tags $(TAGS)) \
		  $(if $(LIMIT),--limit $(LIMIT)) \
		  $(VERBOSE); \
	fi
	@echo "✅ Bootstrap done."

# -------- Deploy app --------
deploy:
	$(call assert_env)
	@echo "🚀 Deploying to $(ENV)..."
	@$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) playbooks/deploy.yml \
	  -l $(ENV) \
	  --vault-password-file $(VAULT_PASS) \
	  $(if $(TAGS),--tags $(TAGS)) \
	  $(if $(LIMIT),--limit $(LIMIT)) \
	  $(VERBOSE)
	@echo "✅ Deploy done."

# -------- SSH quick test --------
ssh-test:
	$(call assert_env)
	@echo "🔑 Checking ssh-agent keys..."
	@ssh-add -l || (echo "No keys in agent; loading $(SSH_KEY)" && ssh-add $(SSH_KEY))
	@echo "🌐 Testing SSH (with bastion and agent forwarding) for $(ENV)"
	@./scripts/dynamic-ssh-agent-test.sh $(ENV) || true

# -------- Lint / Syntax --------
lint:
	@command -v ansible-lint >/dev/null 2>&1 && ansible-lint || echo "ansible-lint not installed; skipping."

check-syntax:
	@$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) playbooks/bootstrap.yml --syntax-check
	@$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) playbooks/deploy.yml --syntax-check

# -------- Housekeeping --------
clean:
	@rm -rf ansible.log retry || true
	@echo "🧹 Cleaned logs and retry files."

migrate-to-ansible-user:
	$(call assert_env)
	@echo "🔄 Migrating $(ENV) from root user to ansible service user..."
	@$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) playbooks/migrate-to-ansible-user.yml \
	  -l $(ENV) \
	  --vault-password-file $(VAULT_PASS) \
	  -u root \
	  $(VERBOSE)
	@echo "✅ Migration complete. Update your inventory and re-run bootstrap."
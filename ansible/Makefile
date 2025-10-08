.PHONY: help inventory bootstrap deploy verify ssh-test clean lint check-syntax migrate-to-ansible-user

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

# -------- Auto-detect ansible user --------
MARKER_FILE := .ansible_user_enabled
ifeq ($(wildcard $(MARKER_FILE)),)
  USE_ANSIBLE_USER ?= false   # marker not found → still root
else
  USE_ANSIBLE_USER ?= true    # marker exists → default to ansible
endif

# -------- Helpers --------
define assert_env
	@echo "Using ENV=$(ENV) (user: $$( [ $(USE_ANSIBLE_USER) = true ] && echo ansible || echo root ))"; \
	if ! echo "$(ALLOWED_ENVS)" | tr ' ' '\n' | grep -qx "$(ENV)"; then \
	  echo "❌ ENV must be one of: $(ALLOWED_ENVS)"; exit 1; \
	fi
endef

# -------- Help --------
help:
	@echo "Targets:"
	@echo "  inventory        Generate $(INVENTORY) from Terraform outputs"
	@echo "  verify           Ping and basic checks on hosts in ENV"
	@echo "  bootstrap        Run initial server setup (root, creates ansible user)"
	@echo "  migrate-to-ansible-user  Switch from root to ansible service user"
	@echo "  deploy           Deploy application to hosts in ENV"
	@echo "  ssh-test         Quick SSH agent / ProxyJump test for ENV"
	@echo "  lint             Run ansible-lint (if installed)"
	@echo "  clean            Remove logs and retry files"
	@echo ""
	@echo "Examples:"
	@echo "  make bootstrap ENV=staging"
	@echo "  make migrate-to-ansible-user ENV=staging"
	@echo "  make inventory ENV=staging   # auto-uses ansible after migration"
	@echo ""

# -------- Inventory generation --------
inventory:
	@echo "🔄 Generating inventory from Terraform..."
	@if [ -d "../infra" ]; then \
		cd ../infra && terraform output -json > ../ansible/terraform_outputs.json; \
		cd ../ansible && USE_ANSIBLE_USER=$(USE_ANSIBLE_USER) python3 scripts/generate_inventory.py; \
		echo "🔍 Testing SSH connectivity..."; \
		chmod +x scripts/dynamic-ssh-agent-test.sh; \
		USE_ANSIBLE_USER=$(USE_ANSIBLE_USER) ./scripts/dynamic-ssh-agent-test.sh all; \
	else \
		echo "❌ Error: ../infra directory not found. Make sure Terraform is deployed first."; \
		exit 1; \
	fi

# -------- Verify --------
verify: 
	$(call assert_env)
	@echo "🔍 Verifying connectivity to $(ENV) hosts..."
	@USE_ANSIBLE_USER=$(USE_ANSIBLE_USER) $(ANSIBLE) $(ENV) -i $(INVENTORY) -m ping $(VERBOSE) --vault-password-file $(VAULT_PASS)
	@echo "ℹ️  Uptime sample:"
	@USE_ANSIBLE_USER=$(USE_ANSIBLE_USER) $(ANSIBLE) $(ENV) -i $(INVENTORY) -m setup -a 'filter=ansible_uptime_seconds' $(VERBOSE) --vault-password-file $(VAULT_PASS) || true
	@echo "✅ Verify complete."

# -------- Bootstrap (root only, creates ansible user) --------
bootstrap:
	$(call assert_env)
	@echo "🚀 Bootstrapping $(ENV) hosts..."
	# --- Phase 1: create ansible service user (root only) ---
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) playbooks/bootstrap.yml \
	  -l $(ENV) \
	  --vault-password-file $(VAULT_PASS) \
	  -u root \
	  -e ansible_user=root \
	  -e ansible_ssh_user=root \
	  --tags ansible_user \
	  $(if $(LIMIT),--limit $(LIMIT)) \
	  $(VERBOSE)
	@echo "✅ Phase 1 complete: ansible user created"
	@echo "🔁 Switching inventory to ansible user before continuing"
	@touch $(MARKER_FILE)
	@USE_ANSIBLE_USER=1 $(MAKE) inventory

	# --- Phase 2+: switch to ansible user for rest of bootstrap ---
	USE_ANSIBLE_USER=1 $(ANSIBLE_PLAYBOOK) -i $(INVENTORY) playbooks/bootstrap.yml \
	  -l $(ENV) \
	  --vault-password-file $(VAULT_PASS) \
	  --skip-tags ansible_user \
	  $(if $(TAGS),--tags $(TAGS)) \
	  $(if $(LIMIT),--limit $(LIMIT)) \
	  $(VERBOSE)
	@echo "✅ Phase 2+ complete: system hardened and services bootstrapped"

# -------- Deploy app --------
deploy:
	$(call assert_env)
	@echo "🚀 Deploying to $(ENV)..."
	@USE_ANSIBLE_USER=$(USE_ANSIBLE_USER) $(ANSIBLE_PLAYBOOK) -i $(INVENTORY) playbooks/deploy.yml \
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
	@echo "🌐 Testing SSH (with bastion and agent forwarding) for $(ENV) (user mode: $(USE_ANSIBLE_USER))"
	@USE_ANSIBLE_USER=$(USE_ANSIBLE_USER) ./scripts/dynamic-ssh-agent-test.sh $(ENV) || true

# -------- Lint / Syntax --------
lint:
	@command -v ansible-lint >/dev/null 2>&1 && ansible-lint || echo "ansible-lint not installed; skipping."

check-syntax:
	@$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) playbooks/bootstrap.yml --syntax-check
	@$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) playbooks/deploy.yml --syntax-check

# -------- Housekeeping --------
clean:
	@rm -rf ansible.log retry $(MARKER_FILE) || true
	@echo "🧹 Cleaned logs, retry files, and migration marker."

# -------- Migration --------
migrate-to-ansible-user:
	$(call assert_env)
	@echo "🔄 Migrating $(ENV) from root user to ansible service user..."
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) playbooks/migrate-to-ansible-user.yml \
	  -l $(ENV) \
	  --vault-password-file $(VAULT_PASS) \
	  -u root \
	  -e ansible_user=root \
	  -e ansible_ssh_user=root \
	  $(VERBOSE)
	@touch $(MARKER_FILE)   # <--- marker gets created here
	@echo "✅ Migration complete. All future runs will default to ansible user."

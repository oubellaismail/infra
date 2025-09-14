#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "$(date '+%H:%M:%S') - $1"
}

log "${BLUE}🔧 Testing SSH Fix for Port 65535 Error${NC}"
log "=========================================="

# Get IPs from current terraform outputs
if [ ! -f "terraform_outputs.json" ]; then
    log "${RED}❌ terraform_outputs.json not found. Run 'make inventory' first.${NC}"
    exit 1
fi

STAGING_BASTION=$(python3 -c "import json; print(json.load(open('terraform_outputs.json'))['staging_bastion_ip']['value'])")
STAGING_FRONTEND=$(python3 -c "import json; print(json.load(open('terraform_outputs.json'))['staging_frontend_private_ip']['value'])")
STAGING_BACKEND=$(python3 -c "import json; print(json.load(open('terraform_outputs.json'))['staging_backend_private_ip']['value'])")

PRODUCTION_BASTION=$(python3 -c "import json; print(json.load(open('terraform_outputs.json'))['production_bastion_ip']['value'])")
PRODUCTION_FRONTEND=$(python3 -c "import json; print(json.load(open('terraform_outputs.json'))['production_frontend_private_ip']['value'])")
PRODUCTION_BACKEND=$(python3 -c "import json; print(json.load(open('terraform_outputs.json'))['production_backend_private_ip']['value'])")

log "Current Infrastructure IPs:"
log "Staging: Bastion=$STAGING_BASTION, Frontend=$STAGING_FRONTEND, Backend=$STAGING_BACKEND"
log "Production: Bastion=$PRODUCTION_BASTION, Frontend=$PRODUCTION_FRONTEND, Backend=$PRODUCTION_BACKEND"
echo

# Check SSH agent
log "${BLUE}1. Checking SSH Agent${NC}"
if ssh-add -l &>/dev/null; then
    log "${GREEN}✅ SSH agent is running with keys loaded${NC}"
    ssh-add -l
else
    log "${RED}❌ SSH agent not running or no keys loaded${NC}"
    log "Starting SSH agent and loading key..."
    eval "$(ssh-agent -s)"
    ssh-add ~/.ssh/digitalocean
    log "${GREEN}✅ SSH agent started and key added${NC}"
fi
echo

# Test ProxyJump method (the fix)
log "${BLUE}2. Testing ProxyJump Method (The Fix)${NC}"

log "Testing staging frontend via ProxyJump:"
if timeout 15 ssh -o ConnectTimeout=10 \
   -o ProxyJump=root@$STAGING_BASTION \
   -o ForwardAgent=yes -o StrictHostKeyChecking=no \
   -i ~/.ssh/digitalocean root@$STAGING_FRONTEND \
   'echo "ProxyJump to staging frontend successful"' 2>/dev/null; then
    log "${GREEN}✅ ProxyJump to staging frontend works${NC}"
else
    log "${RED}❌ ProxyJump to staging frontend failed${NC}"
fi

log "Testing staging backend via ProxyJump:"
if timeout 15 ssh -o ConnectTimeout=10 \
   -o ProxyJump=root@$STAGING_BASTION \
   -o ForwardAgent=yes -o StrictHostKeyChecking=no \
   -i ~/.ssh/digitalocean root@$STAGING_BACKEND \
   'echo "ProxyJump to staging backend successful"' 2>/dev/null; then
    log "${GREEN}✅ ProxyJump to staging backend works${NC}"
else
    log "${RED}❌ ProxyJump to staging backend failed${NC}"
fi

log "Testing production frontend via ProxyJump:"
if timeout 15 ssh -o ConnectTimeout=10 \
   -o ProxyJump=root@$PRODUCTION_BASTION \
   -o ForwardAgent=yes -o StrictHostKeyChecking=no \
   -i ~/.ssh/digitalocean root@$PRODUCTION_FRONTEND \
   'echo "ProxyJump to production frontend successful"' 2>/dev/null; then
    log "${GREEN}✅ ProxyJump to production frontend works${NC}"
else
    log "${RED}❌ ProxyJump to production frontend failed${NC}"
fi

log "Testing production backend via ProxyJump:"
if timeout 15 ssh -o ConnectTimeout=10 \
   -o ProxyJump=root@$PRODUCTION_BASTION \
   -o ForwardAgent=yes -o StrictHostKeyChecking=no \
   -i ~/.ssh/digitalocean root@$PRODUCTION_BACKEND \
   'echo "ProxyJump to production backend successful"' 2>/dev/null; then
    log "${GREEN}✅ ProxyJump to production backend works${NC}"
else
    log "${RED}❌ ProxyJump to production backend failed${NC}"
fi
echo

# Apply the fixes
log "${BLUE}3. Applying SSH Fixes${NC}"

log "Backing up current configuration..."
cp ansible.cfg ansible.cfg.backup || true
cp scripts/generate_inventory.py scripts/generate_inventory.py.backup || true

log "${YELLOW}To apply the fixes:${NC}"
log "1. Replace your ansible.cfg with the fixed version"
log "2. Replace your scripts/generate_inventory.py with the fixed version"
log "3. Run 'make inventory' to regenerate with ProxyJump"
log "4. Test with 'ansible all -m ping'"

echo
log "${BLUE}4. Quick Fix Commands${NC}"
log "===================="
log "Run these commands to apply the fix:"
echo
echo "# Apply fixed ansible.cfg"
echo "cat > ansible.cfg << 'EOF'"
echo "[defaults]"
echo "inventory = inventories/from_terraform.yml"
echo "remote_user = root"
echo "private_key_file = ~/.ssh/digitalocean"
echo "host_key_checking = False"
echo "timeout = 30"
echo "forks = 5"
echo ""
echo "[ssh_connection]"
echo "# FIXED: No SSH multiplexing to avoid port 65535 error"
echo "ssh_args = -o ForwardAgent=yes -o StrictHostKeyChecking=no"
echo "control_path = none"
echo "pipelining = False"
echo "scp_if_ssh = True"
echo "EOF"
echo
echo "# Regenerate inventory with ProxyJump fix"
echo "make inventory"
echo
echo "# Test the fix"
echo "ansible all -m ping"

echo
log "${YELLOW}💡 The Key Fix:${NC}"
log "================"
log "1. Changed from ProxyCommand to ProxyJump"
log "2. Disabled SSH multiplexing (control_path = none)"
log "3. Disabled pipelining to avoid connection issues"
log "4. This should eliminate the 'port 65535' error completely"
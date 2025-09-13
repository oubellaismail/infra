#!/bin/bash
set -euo pipefail

# Production-specific diagnostic for port 65535 issue

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "$(date '+%H:%M:%S') - $1"
}

# Get IPs from terraform output
STAGING_BASTION=$(python3 -c "
import json
with open('terraform_outputs.json') as f:
    data = json.load(f)
    print(data['staging_bastion_ip']['value'])
")

PRODUCTION_BASTION=$(python3 -c "
import json
with open('terraform_outputs.json') as f:
    data = json.load(f)
    print(data['production_bastion_ip']['value'])
")

PRODUCTION_FRONTEND_PRIVATE=$(python3 -c "
import json
with open('terraform_outputs.json') as f:
    data = json.load(f)
    print(data['production_frontend_private_ip']['value'])
")

PRODUCTION_BACKEND_PRIVATE=$(python3 -c "
import json
with open('terraform_outputs.json') as f:
    data = json.load(f)
    print(data['production_backend_private_ip']['value'])
")

log "${BLUE}🔍 Production Environment SSH Diagnostic${NC}"
log "=========================================="
log "Staging Bastion: $STAGING_BASTION (✅ Working)"
log "Production Bastion: $PRODUCTION_BASTION (✅ Working)"
log "Production Frontend Private: $PRODUCTION_FRONTEND_PRIVATE (❌ Failing)"
log "Production Backend Private: $PRODUCTION_BACKEND_PRIVATE (❌ Failing)"
echo

# Test bastion connectivity first
log "${BLUE}1. Testing Production Bastion Connectivity${NC}"
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/digitalocean root@$PRODUCTION_BASTION 'echo "Production bastion SSH test successful"' 2>/dev/null; then
    log "${GREEN}✅ Production bastion SSH works${NC}"
else
    log "${RED}❌ Production bastion SSH failed${NC}"
    exit 1
fi

# Test SSH agent forwarding on production bastion
log "${BLUE}2. Testing SSH Agent Forwarding on Production Bastion${NC}"
if ssh -A -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/digitalocean root@$PRODUCTION_BASTION 'ssh-add -l' 2>/dev/null; then
    log "${GREEN}✅ SSH agent forwarding works on production bastion${NC}"
else
    log "${YELLOW}⚠️  SSH agent forwarding issue on production bastion${NC}"
fi

# Test if private servers are reachable from production bastion
log "${BLUE}3. Testing Private Server Reachability from Production Bastion${NC}"

# Test frontend
log "Testing production frontend ($PRODUCTION_FRONTEND_PRIVATE) from bastion:"
if ssh -A -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/digitalocean root@$PRODUCTION_BASTION \
   "ping -c 1 -W 3 $PRODUCTION_FRONTEND_PRIVATE && echo 'Ping successful'" 2>/dev/null; then
    log "${GREEN}✅ Production frontend is reachable from bastion${NC}"
else
    log "${RED}❌ Production frontend is NOT reachable from bastion${NC}"
fi

# Test backend
log "Testing production backend ($PRODUCTION_BACKEND_PRIVATE) from bastion:"
if ssh -A -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/digitalocean root@$PRODUCTION_BASTION \
   "ping -c 1 -W 3 $PRODUCTION_BACKEND_PRIVATE && echo 'Ping successful'" 2>/dev/null; then
    log "${GREEN}✅ Production backend is reachable from bastion${NC}"
else
    log "${RED}❌ Production backend is NOT reachable from bastion${NC}"
fi

# Test SSH to private servers from bastion
log "${BLUE}4. Testing SSH from Production Bastion to Private Servers${NC}"

# Frontend SSH test
log "Testing SSH to production frontend:"
if ssh -A -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/digitalocean root@$PRODUCTION_BASTION \
   "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@$PRODUCTION_FRONTEND_PRIVATE 'echo \"Frontend SSH successful\"'" 2>/dev/null; then
    log "${GREEN}✅ SSH to production frontend works from bastion${NC}"
else
    log "${RED}❌ SSH to production frontend FAILED from bastion${NC}"
fi

# Backend SSH test
log "Testing SSH to production backend:"
if ssh -A -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/digitalocean root@$PRODUCTION_BASTION \
   "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@$PRODUCTION_BACKEND_PRIVATE 'echo \"Backend SSH successful\"'" 2>/dev/null; then
    log "${GREEN}✅ SSH to production backend works from bastion${NC}"
else
    log "${RED}❌ SSH to production backend FAILED from bastion${NC}"
fi

# Test ProxyCommand directly (same as inventory)
log "${BLUE}5. Testing Direct ProxyCommand (same as Ansible inventory)${NC}"

# Frontend ProxyCommand test
log "Testing ProxyCommand to production frontend:"
if ssh -o ProxyCommand="ssh -W %h:%p -q root@$PRODUCTION_BASTION" \
   -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/digitalocean \
   root@$PRODUCTION_FRONTEND_PRIVATE 'echo "ProxyCommand frontend test successful"' 2>/dev/null; then
    log "${GREEN}✅ ProxyCommand to production frontend works${NC}"
else
    log "${RED}❌ ProxyCommand to production frontend FAILED${NC}"
    log "${YELLOW}   This is the same method Ansible uses!${NC}"
fi

# Backend ProxyCommand test
log "Testing ProxyCommand to production backend:"
if ssh -o ProxyCommand="ssh -W %h:%p -q root@$PRODUCTION_BASTION" \
   -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/digitalocean \
   root@$PRODUCTION_BACKEND_PRIVATE 'echo "ProxyCommand backend test successful"' 2>/dev/null; then
    log "${GREEN}✅ ProxyCommand to production backend works${NC}"
else
    log "${RED}❌ ProxyCommand to production backend FAILED${NC}"
    log "${YELLOW}   This is the same method Ansible uses!${NC}"
fi

# Check if production droplets are running
log "${BLUE}6. Checking Production Droplet Status${NC}"
log "${YELLOW}Manual check required:${NC}"
log "1. Login to DigitalOcean console: https://cloud.digitalocean.com/droplets"
log "2. Verify these droplets are 'Active':"
log "   - production-frontend"
log "   - production-backend"
log "3. Check droplet console logs for SSH errors"

# Compare inventory configurations
log "${BLUE}7. Comparing Staging vs Production Inventory Config${NC}"
echo "Staging frontend config:"
grep -A 4 "staging-frontend:" inventories/from_terraform.yml
echo
echo "Production frontend config:"
grep -A 4 "production-frontend:" inventories/from_terraform.yml

echo
log "${YELLOW}💡 Common Causes for Production-Only Issues:${NC}"
log "============================================="
log "1. ${YELLOW}Production droplets are down/stopped${NC}"
log "2. ${YELLOW}Different SSH keys on production servers${NC}"
log "3. ${YELLOW}Different firewall rules between environments${NC}"
log "4. ${YELLOW}Network routing issues in production VPC${NC}"
log "5. ${YELLOW}SSH keys not properly deployed to production droplets${NC}"

echo
log "${BLUE}🔧 Next Steps:${NC}"
log "=============="
log "1. Check DigitalOcean console for droplet status"
log "2. If droplets are down, restart them"
log "3. If SSH keys are missing, redeploy with Terraform"
log "4. Check production firewall rules"
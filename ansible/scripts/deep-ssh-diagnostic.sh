#!/bin/bash
set -euo pipefail

# Deep diagnostic to find the exact SSH difference between staging and production

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "$(date '+%H:%M:%S') - $1"
}

log "${BLUE}🔬 Deep SSH Authentication Diagnostic${NC}"
log "====================================="

# Test the exact same SSH method Ansible uses
STAGING_BASTION="159.89.110.78"
PRODUCTION_BASTION="104.248.142.13"
STAGING_FRONTEND="10.114.16.4"
PRODUCTION_FRONTEND="10.19.0.7"

log "${BLUE}1. Testing SSH Agent State${NC}"
ssh-add -l | head -3

log "${BLUE}2. Comparing SSH ProxyCommand Methods${NC}"

# Test staging (works)
log "Testing staging ProxyCommand (should work):"
timeout 10 ssh -vvv \
  -o ProxyCommand="ssh -W %h:%p -q root@$STAGING_BASTION" \
  -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/digitalocean \
  root@$STAGING_FRONTEND 'echo "Staging ProxyCommand successful"' 2>&1 | \
  grep -E "(Authenticated|debug1|Connection established)" | head -5 || log "Failed"

echo
# Test production (fails)
log "Testing production ProxyCommand (fails):"
timeout 10 ssh -vvv \
  -o ProxyCommand="ssh -W %h:%p -q root@$PRODUCTION_BASTION" \
  -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/digitalocean \
  root@$PRODUCTION_FRONTEND 'echo "Production ProxyCommand successful"' 2>&1 | \
  grep -E "(Authenticated|debug1|Connection.*closed|port 65535)" | head -5 || log "Failed"

echo
log "${BLUE}3. Testing SSH Agent Forwarding Difference${NC}"

# Check if SSH keys are properly forwarded to each bastion
log "SSH agent forwarding to staging bastion:"
ssh -A -o StrictHostKeyChecking=no -i ~/.ssh/digitalocean root@$STAGING_BASTION \
  'ssh-add -l | wc -l' 2>/dev/null || log "Failed"

log "SSH agent forwarding to production bastion:"  
ssh -A -o StrictHostKeyChecking=no -i ~/.ssh/digitalocean root@$PRODUCTION_BASTION \
  'ssh-add -l | wc -l' 2>/dev/null || log "Failed"

log "${BLUE}4. Testing Direct SSH from Each Bastion${NC}"

# Test from staging bastion to staging frontend (works)
log "From staging bastion to staging frontend:"
ssh -A -o StrictHostKeyChecking=no -i ~/.ssh/digitalocean root@$STAGING_BASTION \
  "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@$STAGING_FRONTEND 'echo SUCCESS'" 2>/dev/null || log "Failed"

# Test from production bastion to production frontend (likely fails)
log "From production bastion to production frontend:"
ssh -A -o StrictHostKeyChecking=no -i ~/.ssh/digitalocean root@$PRODUCTION_BASTION \
  "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@$PRODUCTION_FRONTEND 'echo SUCCESS'" 2>/dev/null || log "Failed"

log "${BLUE}5. SSH Key Comparison${NC}"

# Check if the same SSH keys exist on both environments
log "SSH keys on staging frontend:"
ssh -A -o StrictHostKeyChecking=no -i ~/.ssh/digitalocean root@$STAGING_BASTION \
  "ssh -o StrictHostKeyChecking=no root@$STAGING_FRONTEND 'ls -la ~/.ssh/'" 2>/dev/null | grep authorized || log "Failed to check"

log "SSH keys on production frontend:"
ssh -A -o StrictHostKeyChecking=no -i ~/.ssh/digitalocean root@$PRODUCTION_BASTION \
  "ssh -o StrictHostKeyChecking=no root@$PRODUCTION_FRONTEND 'ls -la ~/.ssh/'" 2>/dev/null | grep authorized || log "Failed to check"

log "${BLUE}6. Network Interface Comparison${NC}"

# Check if network interfaces are different
log "Staging frontend network setup:"
ssh -A -o StrictHostKeyChecking=no -i ~/.ssh/digitalocean root@$STAGING_BASTION \
  "ssh -o StrictHostKeyChecking=no root@$STAGING_FRONTEND 'ip addr show | grep eth0 -A 2'" 2>/dev/null | head -3 || log "Failed to check"

log "Production frontend network setup:"
ssh -A -o StrictHostKeyChecking=no -i ~/.ssh/digitalocean root@$PRODUCTION_BASTION \
  "ssh -o StrictHostKeyChecking=no root@$PRODUCTION_FRONTEND 'ip addr show | grep eth0 -A 2'" 2>/dev/null | head -3 || log "Failed to check"

log "${BLUE}7. Alternative Fix: Bypass SSH Agent Forwarding${NC}"

# Test without SSH agent forwarding (direct key)
log "Testing production without SSH agent forwarding:"
timeout 10 ssh \
  -o ProxyCommand="ssh -i ~/.ssh/digitalocean -W %h:%p -q root@$PRODUCTION_BASTION" \
  -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/digitalocean \
  root@$PRODUCTION_FRONTEND 'echo "Direct key method successful"' 2>/dev/null || log "Direct key method also failed"

echo
log "${YELLOW}💡 Potential Solutions:${NC}"
log "========================"
log "1. Copy SSH private key to production bastion (less secure)"
log "2. Regenerate SSH keys on production droplets" 
log "3. Use different SSH connection method for production"
log "4. Rebuild production infrastructure with proper SSH key deployment"

echo
log "${BLUE}🔧 Try This Quick Fix:${NC}"
log "======================="
log "If SSH agent forwarding is the issue, test this:"
log 'export ANSIBLE_SSH_ARGS="-o ProxyCommand=\"ssh -i ~/.ssh/digitalocean -W %h:%p -q root@167.71.49.220\""'
log "ansible production-frontend -m ping"
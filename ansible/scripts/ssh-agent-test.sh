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

log "${BLUE}🔐 Testing SSH Agent Forwarding${NC}"
log "================================"

# Verify SSH agent has keys loaded
log "${BLUE}1. Checking SSH Agent Keys${NC}"
if ssh-add -l; then
    log "${GREEN}✅ SSH agent has keys loaded${NC}"
else
    log "${RED}❌ No SSH keys in agent${NC}"
    log "Run: ssh-add ~/.ssh/digitalocean"
    exit 1
fi

# Test SSH agent forwarding to staging bastion
STAGING_BASTION="164.92.207.122"
STAGING_FRONTEND="10.114.16.5"
STAGING_BACKEND="10.114.16.2"

log "${BLUE}2. Testing Staging Environment${NC}"
log "Testing SSH agent forwarding to staging bastion..."

if ssh -A -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
   root@$STAGING_BASTION 'echo "Keys available on bastion:" && ssh-add -l' 2>/dev/null; then
    log "${GREEN}✅ SSH agent forwarding works on staging bastion${NC}"
    
    # Test connection to staging frontend from bastion
    log "Testing connection to staging frontend from bastion..."
    if ssh -A -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
       root@$STAGING_BASTION \
       "ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$STAGING_FRONTEND 'echo \"Frontend connection successful\"'" 2>/dev/null; then
        log "${GREEN}✅ Can connect to staging frontend through bastion${NC}"
    else
        log "${RED}❌ Cannot connect to staging frontend through bastion${NC}"
    fi
    
    # Test connection to staging backend from bastion
    log "Testing connection to staging backend from bastion..."
    if ssh -A -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
       root@$STAGING_BASTION \
       "ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$STAGING_BACKEND 'echo \"Backend connection successful\"'" 2>/dev/null; then
        log "${GREEN}✅ Can connect to staging backend through bastion${NC}"
    else
        log "${RED}❌ Cannot connect to staging backend through bastion${NC}"
    fi
else
    log "${RED}❌ SSH agent forwarding failed on staging bastion${NC}"
fi

# Test SSH agent forwarding to production bastion
PRODUCTION_BASTION="209.38.213.110"
PRODUCTION_FRONTEND="10.114.16.6"
PRODUCTION_BACKEND="10.114.16.3"

log "${BLUE}3. Testing Production Environment${NC}"
log "Testing SSH agent forwarding to production bastion..."

if ssh -A -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
   root@$PRODUCTION_BASTION 'echo "Keys available on bastion:" && ssh-add -l' 2>/dev/null; then
    log "${GREEN}✅ SSH agent forwarding works on production bastion${NC}"
    
    # Test connection to production frontend from bastion
    log "Testing connection to production frontend from bastion..."
    if ssh -A -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
       root@$PRODUCTION_BASTION \
       "ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$PRODUCTION_FRONTEND 'echo \"Frontend connection successful\"'" 2>/dev/null; then
        log "${GREEN}✅ Can connect to production frontend through bastion${NC}"
    else
        log "${RED}❌ Cannot connect to production frontend through bastion${NC}"
    fi
    
    # Test connection to production backend from bastion
    log "Testing connection to production backend from bastion..."
    if ssh -A -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
       root@$PRODUCTION_BASTION \
       "ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$PRODUCTION_BACKEND 'echo \"Backend connection successful\"'" 2>/dev/null; then
        log "${GREEN}✅ Can connect to production backend through bastion${NC}"
    else
        log "${RED}❌ Cannot connect to production backend through bastion${NC}"
    fi
else
    log "${RED}❌ SSH agent forwarding failed on production bastion${NC}"
fi

# Test direct ProxyCommand method (what Ansible uses)
log "${BLUE}4. Testing ProxyCommand Method (Ansible's Method)${NC}"

log "Testing staging frontend with ProxyCommand..."
if ssh -o ProxyCommand="ssh -A -W %h:%p -q root@$STAGING_BASTION" \
   -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
   root@$STAGING_FRONTEND 'echo "ProxyCommand staging frontend works"' 2>/dev/null; then
    log "${GREEN}✅ ProxyCommand to staging frontend works${NC}"
else
    log "${RED}❌ ProxyCommand to staging frontend failed${NC}"
fi

log "Testing production frontend with ProxyCommand..."
if ssh -o ProxyCommand="ssh -A -W %h:%p -q root@$PRODUCTION_BASTION" \
   -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
   root@$PRODUCTION_FRONTEND 'echo "ProxyCommand production frontend works"' 2>/dev/null; then
    log "${GREEN}✅ ProxyCommand to production frontend works${NC}"
else
    log "${RED}❌ ProxyCommand to production frontend failed${NC}"
    log "${YELLOW}💡 This is the exact method Ansible uses - this explains the failure!${NC}"
fi

log "${BLUE}5. Summary${NC}"
log "=========="
log "${YELLOW}Key Findings:${NC}"
log "• SSH agent forwarding requires the -A flag"
log "• ProxyCommand needs to include -A for agent forwarding"
log "• Current Ansible inventory may be missing -A in ProxyCommand"

log "${YELLOW}💡 Next Steps:${NC}"
log "1. Update ansible inventory to use: ProxyCommand='ssh -A -W %h:%p -q root@bastion_ip'"
log "2. Test with: ansible production-frontend -m ping"
log "3. Deploy with fixed configuration"
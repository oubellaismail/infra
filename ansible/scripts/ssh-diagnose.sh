#!/bin/bash
set -euo pipefail

# SSH Diagnostic Script for DevSecOps Ansible Setup
# This script tests SSH connections to identify and fix the port 65535 error

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Test SSH agent
test_ssh_agent() {
    log "${BLUE}🔐 Testing SSH Agent${NC}"
    
    if ssh-add -l &>/dev/null; then
        log "${GREEN}✅ SSH agent is running with keys loaded${NC}"
        ssh-add -l
    else
        log "${RED}❌ SSH agent not running or no keys loaded${NC}"
        log "Starting SSH agent..."
        eval "$(ssh-agent -s)"
        ssh-add ~/.ssh/digitalocean
        log "${GREEN}✅ SSH agent started and key added${NC}"
    fi
}

# Test bastion connectivity
test_bastion_connection() {
    local env=$1
    local bastion_ip
    
    log "${BLUE}🏰 Testing bastion connection for ${env}${NC}"
    
    # Get bastion IP from terraform outputs
    if [ -f "terraform_outputs.json" ]; then
        bastion_ip=$(python3 -c "
import json
with open('terraform_outputs.json') as f:
    data = json.load(f)
    print(data['${env}_bastion_ip']['value'])
")
    else
        log "${RED}❌ terraform_outputs.json not found${NC}"
        return 1
    fi
    
    log "Testing SSH to bastion: $bastion_ip"
    
    # Test direct SSH to bastion
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i ~/.ssh/digitalocean root@$bastion_ip 'echo "Bastion SSH test successful"' 2>/dev/null; then
        log "${GREEN}✅ Direct SSH to bastion works${NC}"
    else
        log "${RED}❌ Direct SSH to bastion failed${NC}"
        return 1
    fi
    
    # Test SSH agent forwarding to bastion
    if ssh -A -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i ~/.ssh/digitalocean root@$bastion_ip 'ssh-add -l' 2>/dev/null; then
        log "${GREEN}✅ SSH agent forwarding to bastion works${NC}"
    else
        log "${YELLOW}⚠️  SSH agent forwarding to bastion may have issues${NC}"
    fi
}

# Test private server connection through bastion
test_private_connection() {
    local env=$1
    local server_type=$2  # frontend or backend
    
    log "${BLUE}🔗 Testing ${server_type} connection for ${env} (via bastion)${NC}"
    
    local bastion_ip private_ip
    
    # Get IPs from terraform outputs
    bastion_ip=$(python3 -c "
import json
with open('terraform_outputs.json') as f:
    data = json.load(f)
    print(data['${env}_bastion_ip']['value'])
")
    
    private_ip=$(python3 -c "
import json
with open('terraform_outputs.json') as f:
    data = json.load(f)
    print(data['${env}_${server_type}_private_ip']['value'])
")
    
    log "Testing connection: bastion $bastion_ip -> ${server_type} $private_ip"
    
    # Test connection using ProxyCommand (same as inventory)
    local proxy_cmd="ssh -W %h:%p -q root@$bastion_ip"
    
    if ssh -o ProxyCommand="$proxy_cmd" -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i ~/.ssh/digitalocean root@$private_ip 'echo "Private server SSH test successful"' 2>/dev/null; then
        log "${GREEN}✅ ProxyCommand SSH to ${server_type} works${NC}"
    else
        log "${RED}❌ ProxyCommand SSH to ${server_type} failed${NC}"
        
        # Try alternative connection method
        log "${YELLOW}🔄 Trying alternative connection method...${NC}"
        if ssh -A -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i ~/.ssh/digitalocean root@$bastion_ip "ssh -o StrictHostKeyChecking=no root@$private_ip 'echo \"Alternative SSH test successful\"'" 2>/dev/null; then
            log "${GREEN}✅ Alternative SSH method works${NC}"
        else
            log "${RED}❌ All SSH methods failed for ${server_type}${NC}"
        fi
    fi
}

# Test Ansible connectivity
test_ansible_connection() {
    local env=$1
    
    log "${BLUE}🤖 Testing Ansible connectivity to ${env}${NC}"
    
    # Test bastion
    if ansible ${env}-bastion -m ping -i inventories/from_terraform.yml 2>/dev/null | grep -q "SUCCESS"; then
        log "${GREEN}✅ Ansible ping to ${env}-bastion successful${NC}"
    else
        log "${RED}❌ Ansible ping to ${env}-bastion failed${NC}"
    fi
    
    # Test frontend
    if ansible ${env}-frontend -m ping -i inventories/from_terraform.yml 2>/dev/null | grep -q "SUCCESS"; then
        log "${GREEN}✅ Ansible ping to ${env}-frontend successful${NC}"
    else
        log "${RED}❌ Ansible ping to ${env}-frontend failed${NC}"
        log "${YELLOW}💡 This is likely the port 65535 issue - check SSH configuration${NC}"
    fi
    
    # Test backend
    if ansible ${env}-backend -m ping -i inventories/from_terraform.yml 2>/dev/null | grep -q "SUCCESS"; then
        log "${GREEN}✅ Ansible ping to ${env}-backend successful${NC}"
    else
        log "${RED}❌ Ansible ping to ${env}-backend failed${NC}"
        log "${YELLOW}💡 This is likely the port 65535 issue - check SSH configuration${NC}"
    fi
}

# Main diagnostic function
main() {
    local env="${1:-staging}"
    
    log "${BLUE}🔍 DevSecOps SSH Diagnostic for ${env} environment${NC}"
    log "========================================================="
    
    # Check if we're in the right directory
    if [ ! -f "ansible.cfg" ]; then
        log "${RED}❌ Not in Ansible project root directory${NC}"
        exit 1
    fi
    
    # Generate fresh inventory
    log "${BLUE}📋 Generating fresh inventory${NC}"
    if make inventory; then
        log "${GREEN}✅ Inventory generated successfully${NC}"
    else
        log "${RED}❌ Inventory generation failed${NC}"
        exit 1
    fi
    
    # Run tests
    test_ssh_agent
    test_bastion_connection "$env"
    test_private_connection "$env" "frontend"
    test_private_connection "$env" "backend"
    test_ansible_connection "$env"
    
    log "${BLUE}🏁 Diagnostic complete${NC}"
    log "========================================================="
    
    # Recommendations
    log "${YELLOW}💡 Recommendations:${NC}"
    log "1. If ProxyCommand SSH works but Ansible fails:"
    log "   - The issue is in ansible.cfg SSH configuration"
    log "   - Try the fixed ansible.cfg provided"
    log ""
    log "2. If all SSH methods fail:"
    log "   - Check firewall rules in DigitalOcean"
    log "   - Verify SSH keys are properly deployed"
    log ""
    log "3. If bastion works but private servers don't:"
    log "   - Check if SSH agent forwarding is working"
    log "   - Verify private IPs are correct in inventory"
}

# Usage
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat << EOF
SSH Diagnostic Script for DevSecOps Ansible Setup

Usage: $0 [ENVIRONMENT]

ENVIRONMENT:
  staging     Test staging environment (default)
  production  Test production environment

This script tests SSH connectivity through the bastion hosts
and helps diagnose the port 65535 error with Ansible.

Examples:
  $0                    # Test staging environment
  $0 production         # Test production environment

EOF
    exit 0
fi

main "${1:-staging}"
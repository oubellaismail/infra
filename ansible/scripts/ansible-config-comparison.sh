#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "$1"
}

log "${BLUE}🔍 Ansible Configuration Analysis${NC}"
log "=================================="

# Show current ansible.cfg
log "${YELLOW}📄 Current ansible.cfg SSH settings:${NC}"
if [ -f "ansible.cfg" ]; then
    log "SSH connection settings:"
    grep -A 10 "\[ssh_connection\]" ansible.cfg | head -15
    echo
else
    log "${RED}❌ ansible.cfg not found${NC}"
fi

# Show inventory format
log "${YELLOW}📋 Current inventory SSH configuration:${NC}"
if [ -f "inventories/from_terraform.yml" ]; then
    log "Sample host configuration:"
    grep -A 5 "staging-frontend:" inventories/from_terraform.yml
    echo
else
    log "${RED}❌ Inventory not found${NC}"
fi

# Test different SSH connection methods
log "${YELLOW}🧪 Testing different SSH methods:${NC}"

BASTION_IP="206.81.18.176"
FRONTEND_IP="10.114.16.6"

# Method 1: Direct ansible with current config
log "1. Current Ansible method (what's failing):"
timeout 10 ansible staging-frontend -m ping -vvv 2>&1 | grep -E "(SSH|ProxyCommand|port|ESTABLISH)" | head -5 || log "${RED}   Failed/Timeout${NC}"
echo

# Method 2: Test with explicit ProxyCommand
log "2. Test with explicit ProxyCommand override:"
timeout 10 ansible staging-frontend -m ping \
    --ssh-extra-args="-o ProxyCommand='ssh -W %h:%p -q root@${BASTION_IP}'" \
    -vv 2>&1 | grep -E "(SUCCESS|UNREACHABLE|ssh|proxy)" | head -3 || log "${RED}   Failed/Timeout${NC}"
echo

# Method 3: Test with no pipelining
log "3. Test with pipelining disabled:"
ANSIBLE_PIPELINING=False timeout 10 ansible staging-frontend -m ping \
    -vv 2>&1 | grep -E "(SUCCESS|UNREACHABLE)" | head -1 || log "${RED}   Failed/Timeout${NC}"
echo

# Method 4: Test with different SSH multiplexing
log "4. Test with disabled SSH multiplexing:"
timeout 10 ansible staging-frontend -m ping \
    --ssh-extra-args="-o ControlMaster=no" \
    -vv 2>&1 | grep -E "(SUCCESS|UNREACHABLE)" | head -1 || log "${RED}   Failed/Timeout${NC}"
echo

# Show what the diagnostic script used (it worked!)
log "${GREEN}✅ What the diagnostic script used (this worked):${NC}"
log "ansible staging-frontend -m ping -i inventories/from_terraform.yml"
log "With these settings in ansible.cfg:"
log "- pipelining = False"
log "- use_sftp = False"
log "- ProxyCommand in inventory"
echo

log "${YELLOW}💡 Key Differences to Check:${NC}"
log "=================================="
log "1. Check if you have multiple ansible.cfg files"
log "2. Check if environment variables are overriding settings"
log "3. Check if there's a difference in how commands are run"

# Check for multiple ansible.cfg files
log "${BLUE}🔍 Checking for multiple ansible.cfg files:${NC}"
find ~ -name "ansible.cfg" -type f 2>/dev/null | head -5 || log "None found in home directory"
find /etc -name "ansible.cfg" -type f 2>/dev/null | head -5 || log "None found in /etc"
echo

# Check environment variables
log "${BLUE}🔍 Ansible environment variables:${NC}"
env | grep ANSIBLE || log "None set"
echo

# Show ansible configuration that's actually being used
log "${BLUE}🔍 Ansible configuration being used:${NC}"
ansible-config dump --only-changed || log "Could not get config"
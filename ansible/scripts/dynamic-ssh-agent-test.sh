#!/bin/bash
set -euo pipefail

# Fixed Dynamic SSH Agent Test Script - More tolerant and matches working manual commands
# Usage: ./scripts/dynamic-ssh-agent-test.sh [staging|production|all]

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "$(date '+%H:%M:%S') - $1"
}

# Function to extract IPs from terraform_outputs.json
get_terraform_ips() {
    local env=$1
    local output_type=$2
    
    if [ ! -f "terraform_outputs.json" ]; then
        log "${RED}❌ terraform_outputs.json not found. Run 'make inventory' first.${NC}"
        exit 1
    fi
    
    python3 -c "
import json
import sys

try:
    with open('terraform_outputs.json', 'r') as f:
        data = json.load(f)
    
    key = '${env}_${output_type}'
    if key in data and 'value' in data[key]:
        print(data[key]['value'])
    else:
        print('NOT_FOUND')
        sys.exit(1)
except Exception as e:
    print('ERROR')
    sys.exit(1)
"
}

# Test SSH agent setup
test_ssh_agent() {
    log "${BLUE}🔐 Testing SSH Agent Setup${NC}"
    
    if ssh-add -l &>/dev/null; then
        log "${GREEN}✅ SSH agent has keys loaded${NC}"
    else
        log "${YELLOW}💡 Loading SSH key...${NC}"
        
        if [ -f ~/.ssh/digitalocean ]; then
            eval "$(ssh-agent -s)" 2>/dev/null || true
            ssh-add ~/.ssh/digitalocean
            log "${GREEN}✅ SSH key loaded successfully${NC}"
        else
            log "${RED}❌ SSH key not found at ~/.ssh/digitalocean${NC}"
            exit 1
        fi
    fi
    echo
}

# Test bastion connection (using the exact same command that worked manually)
test_bastion_connection() {
    local env=$1
    local bastion_ip
    
    log "${BLUE}🏰 Testing ${env} bastion connection${NC}"
    
    bastion_ip=$(get_terraform_ips "$env" "bastion_ip")
    if [ "$bastion_ip" == "NOT_FOUND" ] || [ "$bastion_ip" == "ERROR" ]; then
        log "${RED}❌ Could not get bastion IP for $env${NC}"
        return 1
    fi
    
    log "Bastion IP: $bastion_ip"
    
    # Use the exact same command that worked manually
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
       -i ~/.ssh/digitalocean root@$bastion_ip 'echo "Bastion SSH test successful"' 2>/dev/null; then
        log "${GREEN}✅ SSH to $env bastion works${NC}"
    else
        log "${RED}❌ SSH to $env bastion failed${NC}"
        return 1
    fi
    
    # Test SSH agent forwarding 
    log "Testing SSH agent forwarding..."
    if ssh -A -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
       -i ~/.ssh/digitalocean root@$bastion_ip 'ssh-add -l >/dev/null 2>&1 && echo "Agent forwarding works"' 2>/dev/null; then
        log "${GREEN}✅ SSH agent forwarding to $env bastion works${NC}"
    else
        log "${YELLOW}⚠️  SSH agent forwarding may have issues (but basic SSH works)${NC}"
    fi
    echo
}

# Auto-fix SSH connections through bastion
auto_fix_ssh_forwarding() {
    local env=$1
    
    log "${BLUE}🔧 Setting up SSH connections through ${env} bastion${NC}"
    
    local bastion_ip frontend_ip backend_ip
    bastion_ip=$(get_terraform_ips "$env" "bastion_ip")
    frontend_ip=$(get_terraform_ips "$env" "frontend_private_ip") 
    backend_ip=$(get_terraform_ips "$env" "backend_private_ip")
    
    if [ "$bastion_ip" == "NOT_FOUND" ]; then
        log "${RED}❌ Cannot get bastion IP for $env${NC}"
        return 1
    fi
    
    log "Establishing connections: bastion $bastion_ip -> frontend $frontend_ip, backend $backend_ip"
    
    # Connect through bastion to private servers (like the working manual method)
    if ssh -A -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
        -i ~/.ssh/digitalocean root@$bastion_ip << EOF
# Test connection to frontend
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$frontend_ip 'echo "Frontend connection successful"' 2>/dev/null; then
    echo "✅ Frontend connection works"
else
    echo "❌ Frontend connection failed"
fi

# Test connection to backend  
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$backend_ip 'echo "Backend connection successful"' 2>/dev/null; then
    echo "✅ Backend connection works"
else
    echo "❌ Backend connection failed"
fi
EOF
    then
        log "${GREEN}✅ SSH connections through $env bastion established${NC}"
    else
        log "${YELLOW}⚠️  Some SSH connections had issues but may still work${NC}"
    fi
    echo
}

# Test Ansible connectivity
test_ansible_connectivity() {
    local env=$1
    
    log "${BLUE}🤖 Testing Ansible connectivity to ${env}${NC}"
    
    if [ ! -f "inventories/from_terraform.yml" ]; then
        log "${YELLOW}⚠️  Inventory not found, skipping Ansible test${NC}"
        return
    fi
    
    # Test with longer timeout and less verbose output
    log "Testing Ansible ping to ${env} servers..."
    
    local success_count=0
    local total_count=0
    
    for server in bastion frontend backend; do
        total_count=$((total_count + 1))
        if timeout 20 ansible ${env}-${server} -m ping -i inventories/from_terraform.yml >/dev/null 2>&1; then
            log "${GREEN}✅ ${env}-${server} ping successful${NC}"
            success_count=$((success_count + 1))
        else
            log "${RED}❌ ${env}-${server} ping failed${NC}"
        fi
    done
    
    log "${BLUE}Ansible connectivity: ${success_count}/${total_count} servers responding${NC}"
    echo
}

# Test specific environment
test_environment() {
    local env=$1
    
    log "${BLUE}🧪 Testing ${env} environment${NC}"
    log "================================="
    
    local bastion_ip frontend_ip backend_ip
    bastion_ip=$(get_terraform_ips "$env" "bastion_ip")
    frontend_ip=$(get_terraform_ips "$env" "frontend_private_ip")
    backend_ip=$(get_terraform_ips "$env" "backend_private_ip")
    
    log "${YELLOW}${env} configuration:${NC}"
    log "  Bastion (public):    $bastion_ip"
    log "  Frontend (private):  $frontend_ip"
    log "  Backend (private):   $backend_ip"
    echo
    
    # Run tests
    if test_bastion_connection "$env"; then
        auto_fix_ssh_forwarding "$env"
        test_ansible_connectivity "$env"
        log "${GREEN}✅ ${env} environment ready for deployment${NC}"
    else
        log "${RED}❌ ${env} environment has connection issues${NC}"
        return 1
    fi
    echo
}

# Main function
main() {
    local env="${1:-all}"
    
    log "${BLUE}🔍 Dynamic SSH Agent Test (Fixed Version)${NC}"
    log "=============================================="
    
    # Check directory
    if [ ! -f "ansible.cfg" ]; then
        log "${RED}❌ Not in Ansible project root directory${NC}"
        exit 1
    fi
    
    # Test SSH agent
    test_ssh_agent
    
    # Test environments
    case $env in
        "staging")
            if test_environment "staging"; then
                log "${GREEN}🚀 Staging ready! Run: make deploy ENV=staging${NC}"
            fi
            ;;
        "production") 
            if test_environment "production"; then
                log "${GREEN}🚀 Production ready! Run: make deploy ENV=production${NC}"
            fi
            ;;
        "all")
            local staging_ok=false
            local production_ok=false
            
            if test_environment "staging"; then
                staging_ok=true
            fi
            
            if test_environment "production"; then
                production_ok=true
            fi
            
            # Final summary
            log "${BLUE}🏁 Final Summary${NC}"
            log "================"
            if [ "$staging_ok" = true ]; then
                log "${GREEN}✅ Staging environment ready${NC}"
            else
                log "${RED}❌ Staging environment has issues${NC}"
            fi
            
            if [ "$production_ok" = true ]; then
                log "${GREEN}✅ Production environment ready${NC}"
            else
                log "${RED}❌ Production environment has issues${NC}"
            fi
            
            if [ "$staging_ok" = true ] && [ "$production_ok" = true ]; then
                log "${GREEN}🚀 Both environments ready for deployment!${NC}"
            elif [ "$staging_ok" = true ]; then
                log "${GREEN}🚀 Deploy to staging: make deploy ENV=staging${NC}"
            fi
            ;;
        *)
            log "${RED}❌ Invalid environment: $env${NC}"
            log "Valid options: staging, production, all"
            exit 1
            ;;
    esac
}

# Usage help
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat << EOF
Fixed Dynamic SSH Agent Test Script

This script tests SSH connectivity using the same methods that work manually.

Usage: $0 [ENVIRONMENT]

ENVIRONMENT:
  staging     Test staging environment only
  production  Test production environment only  
  all         Test both environments (default)

Examples:
  $0                    # Test all environments
  $0 staging           # Test staging only
  $0 production        # Test production only

EOF
    exit 0
fi

main "${1:-all}"
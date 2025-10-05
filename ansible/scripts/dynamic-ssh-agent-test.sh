#!/bin/bash
set -euo pipefail

SSH_KEY_PATH="${ANSIBLE_SSH_KEY_PATH:-${DO_SSH_KEY_PATH:-$HOME/.ssh/digitalocean}}"
SSH_OPTS="-o ForwardAgent=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes"

VAULT_FILE="--vault-password-file .vault_pass"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

MARKER_FILE=".ansible_user_enabled"

# 🔑 Decide which user to use automatically
if [[ -f "$MARKER_FILE" ]]; then
    DEFAULT_USER="ansible"
else
    DEFAULT_USER="root"
fi

log() {
    echo -e "$(date '+%H:%M:%S') - $1"
}

# -------- Terraform DNS lookup --------
get_terraform_dns() {
    local env=$1
    local output_type=$2
    
    if [ ! -f "terraform_outputs.json" ]; then
        log "${RED}❌ terraform_outputs.json not found. Run 'make inventory' first.${NC}"
        exit 1
    fi
    
    python3 -c "
import json,sys
with open('terraform_outputs.json','r') as f:
    data=json.load(f)
key='${env}_${output_type}'
if key in data and 'value' in data[key]:
    print(data[key]['value'])
else:
    print('NOT_FOUND')
    sys.exit(1)
"
}

# -------- SSH Agent setup --------
test_ssh_agent() {
    log "${BLUE}🔐 Testing SSH Agent Setup${NC}"
    log "Using SSH key: $SSH_KEY_PATH"

    if ssh-add -l &>/dev/null; then
        log "${GREEN}✅ SSH agent has keys loaded${NC}"
    else
        log "${YELLOW}💡 Loading SSH key...${NC}"
        
        if [ -f "$SSH_KEY_PATH" ]; then
            eval "$(ssh-agent -s)" 2>/dev/null || true
            ssh-add "$SSH_KEY_PATH"
            log "${GREEN}✅ SSH key loaded successfully${NC}"
        else
            log "${RED}❌ SSH key not found at $SSH_KEY_PATH${NC}"
            exit 1
        fi
    fi
    echo
}

# -------- Bastion connection --------
test_bastion_connection() {
    local env=$1
    local bastion_dns
    
    log "${BLUE}🏰 Testing ${env} bastion connection (user: $DEFAULT_USER)${NC}"
    
    bastion_dns=$(get_terraform_dns "$env" "bastion_dns")
    if [ "$bastion_dns" == "NOT_FOUND" ]; then
        log "${RED}❌ Could not get bastion DNS for $env${NC}"
        return 1
    fi
    
    log "Bastion DNS: $bastion_dns"
    
    if ssh $SSH_OPTS -i "$SSH_KEY_PATH" ${DEFAULT_USER}@$bastion_dns 'echo "Bastion SSH test successful"' 2>/dev/null; then
        log "${GREEN}✅ SSH to $env bastion works${NC}"
    else
        log "${RED}❌ SSH to $env bastion failed${NC}"
        return 1
    fi
    
    log "Testing SSH agent forwarding..."
    if ssh -A $SSH_OPTS -i "$SSH_KEY_PATH" ${DEFAULT_USER}@$bastion_dns 'ssh-add -l >/dev/null 2>&1 && echo "Agent forwarding works"' 2>/dev/null; then
        log "${GREEN}✅ SSH agent forwarding to $env bastion works${NC}"
    else
        log "${YELLOW}⚠️  SSH agent forwarding may have issues (but basic SSH works)${NC}"
    fi
    echo
}

# -------- Proxy jump to private nodes --------
auto_fix_ssh_forwarding() {
    local env=$1
    local bastion_dns frontend_dns backend_dns
    
    bastion_dns=$(get_terraform_dns "$env" "bastion_dns")
    frontend_dns=$(get_terraform_dns "$env" "frontend_private_dns")
    backend_dns=$(get_terraform_dns "$env" "backend_private_dns")

    log "${BLUE}🔧 Testing private connections via $env bastion (user: $DEFAULT_USER)${NC}"
    log "  bastion:  $bastion_dns"
    log "  frontend: $frontend_dns"
    log "  backend:  $backend_dns"
    
    ssh -A $SSH_OPTS -i "$SSH_KEY_PATH" ${DEFAULT_USER}@$bastion_dns << EOF
if ssh $SSH_OPTS -o ConnectTimeout=5 ${DEFAULT_USER}@$frontend_dns 'echo "Frontend connection OK"' 2>/dev/null; then
    echo "✅ Frontend connection works"
else
    echo "❌ Frontend connection failed"
fi

if ssh $SSH_OPTS -o ConnectTimeout=5 ${DEFAULT_USER}@$backend_dns 'echo "Backend connection OK"' 2>/dev/null; then
    echo "✅ Backend connection works"
else
    echo "❌ Backend connection failed"
fi
EOF
}

# -------- Ansible connectivity test --------
test_ansible_connectivity() {
    local env=$1
    
    log "${BLUE}🤖 Testing Ansible connectivity to ${env}${NC}"
    
    if [ ! -f "inventories/from_terraform.yml" ]; then
        log "${YELLOW}⚠️  Inventory not found, skipping Ansible test${NC}"
        return
    fi
    
    for server in bastion frontend backend; do
        if timeout 20 ansible ${env}-${server} -m ping -i inventories/from_terraform.yml $VAULT_FILE >/dev/null 2>&1; then
            log "${GREEN}✅ ${env}-${server} ping successful${NC}"
        else
            log "${RED}❌ ${env}-${server} ping failed${NC}"
        fi
    done
    echo
}

# -------- Run per-environment test --------
test_environment() {
    local env=$1
    
    log "${BLUE}🧪 Testing ${env} environment (user: $DEFAULT_USER)${NC}"
    echo
    
    if test_bastion_connection "$env"; then
        auto_fix_ssh_forwarding "$env"
        test_ansible_connectivity "$env"
        log "${GREEN}✅ ${env} environment ready${NC}"
    else
        log "${RED}❌ ${env} environment has issues${NC}"
    fi
    echo
}

# -------- Main --------
main() {
    local env="${1:-all}"
    
    log "${BLUE}🔍 Dynamic SSH Agent Test${NC}"
    log "=============================================="
    log "Current default SSH user: ${DEFAULT_USER}"
    echo
    
    test_ssh_agent
    
    case $env in
        "staging") test_environment "staging" ;;
        "production") test_environment "production" ;;
        "all") 
            test_environment "staging"
            test_environment "production"
            ;;
        *) 
            log "${RED}❌ Invalid environment: $env${NC}"
            exit 1 ;;
    esac
}

main "${1:-all}"

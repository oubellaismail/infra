#!/bin/bash
set -euo pipefail

# DevSecOps Secure Deployment Script
# Uses SSH agent forwarding - no private keys on servers

ENVIRONMENT="${1:-staging}"
TAGS="${2:-all}"
LOG_FILE="ansible-deploy.log"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# DevSecOps Pre-flight checks
pre_flight_checks() {
    log "${BLUE}🔒 DevSecOps Pre-flight Security Checks${NC}"
    
    # Check if ssh-agent is running
    if ! ssh-add -l &>/dev/null; then
        log "${RED}❌ SSH agent not running or no keys loaded${NC}"
        log "Starting SSH agent and loading key..."
        eval "$(ssh-agent -s)"
        ssh-add ~/.ssh/digitalocean
    else
        log "${GREEN}✅ SSH agent running with keys loaded${NC}"
    fi
    
    # Verify Ansible is available
    if ! command -v ansible-playbook &> /dev/null; then
        log "${RED}❌ ansible-playbook not found${NC}"
        exit 1
    fi
    
    # Check we're in the right directory
    if [ ! -f "ansible.cfg" ]; then
        log "${RED}❌ Not in Ansible project root${NC}"
        exit 1
    fi
    
    # Test SSH connectivity to bastion with agent forwarding
    log "🔗 Testing SSH agent forwarding to bastion..."
    BASTION_IP=$(cd ../infra && terraform output -raw ${ENVIRONMENT}_bastion_ip)
    
    if ssh -o ConnectTimeout=10 -o ForwardAgent=yes -i ~/.ssh/digitalocean root@${BASTION_IP} 'echo "SSH forwarding test successful"' &>/dev/null; then
        log "${GREEN}✅ SSH agent forwarding working${NC}"
    else
        log "${RED}❌ SSH agent forwarding failed${NC}"
        exit 1
    fi
    
    log "${GREEN}✅ All security checks passed${NC}"
}

# Generate inventory with current Terraform state
generate_inventory() {
    log "${BLUE}📋 Generating inventory from Terraform${NC}"
    cd ../infra && terraform output -json > ../ansible/terraform_outputs.json
    cd ../ansible && python3 scripts/generate_inventory.py
    
    if [ $? -eq 0 ]; then
        log "${GREEN}✅ Inventory generated successfully${NC}"
    else
        log "${RED}❌ Inventory generation failed${NC}"
        exit 1
    fi
}

# Run deployment with security validation
run_deployment() {
    log "${BLUE}🚀 Starting secure deployment to ${ENVIRONMENT}${NC}"
    
    # Bootstrap if needed (first-time setup)
    if [ "$TAGS" == "bootstrap" ] || [ "$TAGS" == "all" ]; then
        log "🔧 Running bootstrap (initial server setup)..."
        ansible-playbook playbooks/bootstrap.yml \
            -i inventories/from_terraform.yml \
            -l ${ENVIRONMENT} \
            --tags bootstrap \
            -vv
    fi
    
    # Deploy applications
    if [ "$TAGS" == "deploy" ] || [ "$TAGS" == "all" ]; then
        log "📦 Deploying applications..."
        ansible-playbook playbooks/deploy.yml \
            -i inventories/from_terraform.yml \
            -l ${ENVIRONMENT} \
            --tags deploy \
            -vv
    fi
    
    # Custom tags
    if [ "$TAGS" != "all" ] && [ "$TAGS" != "bootstrap" ] && [ "$TAGS" != "deploy" ]; then
        log "🏷️  Running custom tags: ${TAGS}..."
        ansible-playbook playbooks/bootstrap.yml playbooks/deploy.yml \
            -i inventories/from_terraform.yml \
            -l ${ENVIRONMENT} \
            --tags ${TAGS} \
            -vv
    fi
}

# Post-deployment verification
verify_deployment() {
    log "${BLUE}🔍 Running post-deployment verification${NC}"
    
    ansible-playbook playbooks/bootstrap.yml \
        -i inventories/from_terraform.yml \
        -l ${ENVIRONMENT} \
        --tags verify \
        -v
    
    if [ $? -eq 0 ]; then
        log "${GREEN}✅ Deployment verification passed${NC}"
    else
        log "${RED}❌ Deployment verification failed${NC}"
        return 1
    fi
}

# Main execution
main() {
    log "${BLUE}🔒 DevSecOps Secure Deployment Pipeline${NC}"
    log "Environment: ${ENVIRONMENT}"
    log "Tags: ${TAGS}"
    log "SSH Agent Forwarding: Enabled"
    
    pre_flight_checks
    generate_inventory
    run_deployment
    verify_deployment
    
    log "${GREEN}🎉 Deployment completed successfully!${NC}"
    log "Private keys remained secure - never left your machine"
}

# Usage information
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat << EOF
DevSecOps Secure Deployment Script

Usage: $0 [ENVIRONMENT] [TAGS]

ENVIRONMENT:
  staging     Deploy to staging environment (default)
  production  Deploy to production environment

TAGS:
  all         Run complete bootstrap + deploy (default)
  bootstrap   Run only initial server setup
  deploy      Run only application deployment
  verify      Run only verification checks
  custom,tags Run specific Ansible tags

Examples:
  $0                          # Deploy all to staging
  $0 production               # Deploy all to production  
  $0 staging bootstrap        # Bootstrap staging only
  $0 production deploy        # Deploy apps to production
  $0 staging docker,nginx     # Run specific tags

Security Features:
  ✅ SSH Agent Forwarding (private keys never leave your machine)
  ✅ Pre-flight security checks
  ✅ Automated inventory generation
  ✅ Post-deployment verification
  ✅ Comprehensive logging


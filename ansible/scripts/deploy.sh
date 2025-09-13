#!/bin/bash
set -euo pipefail

# Configuration
ENVIRONMENT="${1:-staging}"
TAGS="${2:-all}"
LOG_FILE="ansible-deploy.log"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

usage() {
    echo "Usage: $0 [staging|production] [tags]"
    echo "Example: $0 production deploy"
    exit 1
}

# Pre-flight checks
pre_flight_checks() {
    log "Running pre-flight checks..."
    if ! command -v ansible-playbook &> /dev/null; then
        log "${RED}ERROR: ansible-playbook not found. Please install Ansible.${NC}"
        exit 1
    fi
    if [ ! -f "ansible.cfg" ]; then
        log "${RED}ERROR: Not in the root of the Ansible project. Exiting.${NC}"
        exit 1
    fi
    log "${GREEN}Pre-flight checks passed.${NC}"
}

# Main execution
main() {
    if [[ "$#" -eq 0 ]]; then
        usage
    fi

    log "Starting deployment to ${ENVIRONMENT} with tags: ${TAGS}"

    # Generate inventory
    log "Generating inventory from Terraform..."
    make inventory || { log "${RED}Inventory generation failed.${NC}"; exit 1; }

    # Run deployment
    log "Executing deployment playbook..."
    if ! make deploy ENV="$ENVIRONMENT" TAGS="$TAGS"; then
        log "${RED}Deployment failed. Check ansible.log for details.${NC}"
        exit 1
    fi

    # Run verification
    log "Running post-deployment verification..."
    if ! make verify ENV="$ENVIRONMENT"; then
        log "${RED}Verification failed. The deployment might be unstable.${NC}"
        exit 1
    fi

    log "${GREEN}Deployment to ${ENVIRONMENT} completed successfully!${NC}"
}

pre_flight_checks
main "$@"
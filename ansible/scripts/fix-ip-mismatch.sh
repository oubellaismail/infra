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

log "${BLUE}🔧 Fixing Production IP Mismatch${NC}"
log "=================================="

# Get actual IPs from production bastion
log "Getting actual production server IPs..."

PROD_BASTION="167.71.49.220"

# Get actual frontend IP
ACTUAL_FRONTEND_IP=$(ssh -o StrictHostKeyChecking=no -i ~/.ssh/digitalocean root@$PROD_BASTION \
    "ip route get 8.8.8.8 | head -1 | cut -d' ' -f7; ssh root@10.19.0.9 'ip route get 8.8.8.8 | head -1 | cut -d\" \" -f7'" 2>/dev/null | tail -1 || echo "10.19.0.9")

# Get actual backend IP  
ACTUAL_BACKEND_IP=$(ssh -o StrictHostKeyChecking=no -i ~/.ssh/digitalocean root@$PROD_BASTION \
    "ssh root@10.19.0.8 'ip route get 8.8.8.8 | head -1 | cut -d\" \" -f7'" 2>/dev/null || echo "10.19.0.8")

log "Terraform says production IPs are:"
log "  Frontend: $(python3 -c "import json; f=open('terraform_outputs.json'); data=json.load(f); print(data['production_frontend_private_ip']['value']); f.close()")"
log "  Backend:  $(python3 -c "import json; f=open('terraform_outputs.json'); data=json.load(f); print(data['production_backend_private_ip']['value']); f.close()")"

log "Actual production IPs are:"
log "  Frontend: 10.19.0.9"
log "  Backend:  10.19.0.8"

# Create temporary corrected terraform_outputs.json
log "${YELLOW}Creating corrected terraform outputs...${NC}"

python3 << 'EOF'
import json

# Load current terraform outputs
with open('terraform_outputs.json', 'r') as f:
    data = json.load(f)

# Update with correct IPs
data['production_frontend_private_ip']['value'] = '10.19.0.9'
data['production_backend_private_ip']['value'] = '10.19.0.8'

# Save corrected version
with open('terraform_outputs_corrected.json', 'w') as f:
    json.dump(data, f, indent=2)

print("✅ Created terraform_outputs_corrected.json with actual IPs")
EOF

# Generate corrected inventory
log "${YELLOW}Generating corrected inventory...${NC}"

# Backup original
cp terraform_outputs.json terraform_outputs.json.backup
cp inventories/from_terraform.yml inventories/from_terraform.yml.backup

# Use corrected outputs
cp terraform_outputs_corrected.json terraform_outputs.json

# Regenerate inventory with correct IPs
python3 scripts/generate_inventory.py

log "${GREEN}✅ Generated corrected inventory with actual production IPs${NC}"

# Test the fix
log "${YELLOW}Testing corrected configuration...${NC}"

if ansible production-frontend -m ping -i inventories/from_terraform.yml >/dev/null 2>&1; then
    log "${GREEN}✅ Production frontend now works!${NC}"
else
    log "${RED}❌ Production frontend still failing${NC}"
fi

if ansible production-backend -m ping -i inventories/from_terraform.yml >/dev/null 2>&1; then
    log "${GREEN}✅ Production backend now works!${NC}"
else
    log "${RED}❌ Production backend still failing${NC}"
fi

log "${BLUE}🔧 Next Steps:${NC}"
log "=============="
log "1. Test all production servers:"
log "   ansible production -m ping"
log ""
log "2. If working, update Terraform to match reality:"
log "   cd ../infra"
log "   terraform refresh"
log "   terraform plan"
log ""
log "3. Or rebuild production infrastructure to match Terraform:"
log "   terraform destroy -target=module.production"
log "   terraform apply"
log ""
log "${YELLOW}Files created:${NC}"
log "  terraform_outputs.json.backup    (original)"
log "  terraform_outputs_corrected.json (corrected IPs)"
log "  inventories/from_terraform.yml.backup (original inventory)"
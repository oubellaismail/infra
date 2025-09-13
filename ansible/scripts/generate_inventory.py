#!/usr/bin/env python3
import json
import yaml
import sys
import os
from datetime import datetime

def load_terraform_outputs(filepath='terraform_outputs.json'):
    """Load Terraform outputs from JSON file."""
    try:
        with open(filepath, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"❌ {filepath} not found. Run 'make inventory' first.", file=sys.stderr)
        sys.exit(1)

def main():
    """Generate inventory with FIXED SSH configuration for Ansible."""
    tf_outputs = load_terraform_outputs()
    
    # Build hosts
    all_hosts = {}
    staging_hosts = {}
    production_hosts = {}
    bastion_hosts = {}
    frontend_hosts = {}
    backend_hosts = {}
    app_server_hosts = {}

    for env in ['staging', 'production']:
        bastion_ip = tf_outputs.get(f'{env}_bastion_ip', {}).get('value')
        frontend_private_ip = tf_outputs.get(f'{env}_frontend_private_ip', {}).get('value')
        backend_private_ip = tf_outputs.get(f'{env}_backend_private_ip', {}).get('value')

        # Bastion - direct connection
        if bastion_ip:
            host_key = f"{env}-bastion"
            host_config = {
                'ansible_host': bastion_ip,
                'role': 'bastion',
                'env_name': env
            }
            all_hosts[host_key] = host_config
            bastion_hosts[host_key] = host_config
            
            if env == 'staging':
                staging_hosts[host_key] = host_config
            else:
                production_hosts[host_key] = host_config

        # CRITICAL FIX: Use ansible_ssh_common_args with ProxyCommand (not ProxyJump)
        # This avoids the port 65535 error that occurs with ProxyJump in certain Ansible versions
        proxy_command = f'-o ProxyCommand="ssh -W %h:%p -q root@{bastion_ip}"'
        
        # Frontend - FIXED SSH configuration
        if frontend_private_ip and bastion_ip:
            host_key = f"{env}-frontend"
            host_config = {
                'ansible_host': frontend_private_ip,
                'role': 'frontend',
                'env_name': env,
                # CRITICAL FIX: Use ProxyCommand instead of ProxyJump
                'ansible_ssh_common_args': proxy_command
            }
            all_hosts[host_key] = host_config
            frontend_hosts[host_key] = host_config
            app_server_hosts[host_key] = host_config
            
            if env == 'staging':
                staging_hosts[host_key] = host_config
            else:
                production_hosts[host_key] = host_config
        
        # Backend - Same fix
        if backend_private_ip and bastion_ip:
            host_key = f"{env}-backend"
            host_config = {
                'ansible_host': backend_private_ip,
                'role': 'backend',
                'env_name': env,
                # CRITICAL FIX: Use ProxyCommand instead of ProxyJump
                'ansible_ssh_common_args': proxy_command
            }
            all_hosts[host_key] = host_config
            backend_hosts[host_key] = host_config
            app_server_hosts[host_key] = host_config
            
            if env == 'staging':
                staging_hosts[host_key] = host_config
            else:
                production_hosts[host_key] = host_config

    # Create structured inventory
    inventory = {
        'all': {
            'hosts': all_hosts
        },
        'staging': {
            'hosts': staging_hosts
        },
        'production': {
            'hosts': production_hosts
        },
        'bastion': {
            'hosts': bastion_hosts
        },
        'frontend': {
            'hosts': frontend_hosts
        },
        'backend': {
            'hosts': backend_hosts
        },
        'app_servers': {
            'hosts': app_server_hosts
        }
    }

    # Write inventory
    output_path = 'inventories/from_terraform.yml'
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    
    with open(output_path, 'w') as f:
        f.write(f"""# 🤖 AUTO-GENERATED INVENTORY - DO NOT EDIT
# Generated: {datetime.now().isoformat()}
# Source: terraform_outputs.json
# SSH Strategy: Uses PRIVATE IPs for frontend/backend (DevSecOps compliant)
#
""")
        yaml.dump(inventory, f, default_flow_style=False, indent=2)

    print(f"✅ Inventory generated: {output_path}")
    print(f"🔧 SSH Strategy: ProxyCommand used for reliable Ansible connections")
    
    # Show structure
    print("\n📋 Generated groups:")
    for group, config in inventory.items():
        if group != 'all' and 'hosts' in config:
            hosts = list(config['hosts'].keys())
            print(f"  {group}: {hosts}")
    
    # Show critical IPs being used
    print(f"\n🔍 SSH Connection Strategy:")
    for host_key, host_config in all_hosts.items():
        ip = host_config['ansible_host']
        role = host_config['role']
        if 'ansible_ssh_common_args' in host_config:
            print(f"  {host_key}: {ip} (via SSH proxy tunnel)")
        else:
            print(f"  {host_key}: {ip} (direct connection)")

if __name__ == '__main__':
    main()
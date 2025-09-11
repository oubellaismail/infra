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
    """Generate inventory with proper groups."""
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
        frontend_hostname = tf_outputs.get(f'{env}_frontend_hostname', {}).get('value')
        backend_private_ip = tf_outputs.get(f'{env}_backend_private_ip', {}).get('value')

        # Bastion
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

        # Frontend
        if frontend_hostname:
            host_key = f"{env}-frontend"
            host_config = {
                'ansible_host': frontend_hostname,
                'role': 'frontend',
                'env_name': env,
                'ansible_ssh_common_args': f'-o ProxyJump=root@{bastion_ip}'  # Add this!
            }
            all_hosts[host_key] = host_config
            frontend_hosts[host_key] = host_config
            app_server_hosts[host_key] = host_config
            
            if env == 'staging':
                staging_hosts[host_key] = host_config
            else:
                production_hosts[host_key] = host_config
        
        # Backend
        if backend_private_ip and bastion_ip:
            host_key = f"{env}-backend"
            host_config = {
                'ansible_host': backend_private_ip,
                'role': 'backend',
                'env_name': env,
                'ansible_ssh_common_args': f'-o ProxyJump=root@{bastion_ip}'
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
#
""")
        yaml.dump(inventory, f, default_flow_style=False, indent=2)

    print(f"✅ Inventory generated: {output_path}")
    
    # Show structure
    print("\n📋 Generated groups:")
    for group, config in inventory.items():
        if group != 'all' and 'hosts' in config:
            hosts = list(config['hosts'].keys())
            print(f"  {group}: {hosts}")

if __name__ == '__main__':
    main()
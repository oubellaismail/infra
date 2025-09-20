#!/usr/bin/env python3
import json
import yaml
import sys
import os
from datetime import datetime
from pathlib import Path

def load_terraform_outputs(filepath='terraform_outputs.json'):
    """Load Terraform outputs from JSON file."""
    try:
        with open(filepath, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"❌ {filepath} not found. Run 'make inventory' first.", file=sys.stderr)
        sys.exit(1)

def main():
    """Generate inventory with WORKING SSH Agent Forwarding + ProxyJump."""
    tf_outputs = load_terraform_outputs()
    
    key_override = os.environ.get("ANSIBLE_SSH_KEY_PATH") or os.environ.get("DO_SSH_KEY_PATH")
    key_path = Path(key_override).expanduser() if key_override else Path.home() / ".ssh" / "digitalocean"
    if not key_path.exists():
        print(f"❌ Expected SSH key not found at {key_path}.", file=sys.stderr)
        print("   Ensure your DigitalOcean deployment key is available before running Ansible.", file=sys.stderr)
        sys.exit(1)

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
                'ansible_user': 'root',
                'ansible_ssh_private_key_file': str(key_path),
                'role': 'bastion',
                'env_name': env
            }
            all_hosts[host_key] = host_config
            bastion_hosts[host_key] = host_config
            
            if env == 'staging':
                staging_hosts[host_key] = host_config
            else:
                production_hosts[host_key] = host_config

        # FINAL FIX: ProxyJump with SSH Agent Forwarding
        # This is the correct way to handle SSH keys securely through bastion
        
        # Frontend - WORKING SSH configuration
        if frontend_private_ip and bastion_ip:
            host_key = f"{env}-frontend"
            ssh_common_args = (
                f"-o ProxyJump=root@{bastion_ip} "
                "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
                "-o ForwardAgent=yes -o IdentitiesOnly=yes"
            )
            host_config = {
                'ansible_host': frontend_private_ip,
                'ansible_user': 'root',
                'ansible_ssh_private_key_file': str(key_path),
                'ansible_ssh_common_args': ssh_common_args,
                'role': 'frontend',
                'env_name': env
            }
            all_hosts[host_key] = host_config
            frontend_hosts[host_key] = host_config
            app_server_hosts[host_key] = host_config
            
            if env == 'staging':
                staging_hosts[host_key] = host_config
            else:
                production_hosts[host_key] = host_config
        
        # Backend - Same working configuration
        if backend_private_ip and bastion_ip:
            host_key = f"{env}-backend"
            ssh_common_args = (
                f"-o ProxyJump=root@{bastion_ip} "
                "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
                "-o ForwardAgent=yes -o IdentitiesOnly=yes"
            )
            host_config = {
                'ansible_host': backend_private_ip,
                'ansible_user': 'root',
                'ansible_ssh_private_key_file': str(key_path),
                'ansible_ssh_common_args': ssh_common_args,
                'role': 'backend',
                'env_name': env
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
# SSH Strategy: ProxyJump + SSH Agent Forwarding
# FINAL FIX: Uses SSH agent forwarding so private keys stay on your machine
#
""")
        yaml.dump(inventory, f, default_flow_style=False, indent=2)

    print(f"✅ Inventory generated: {output_path}")
    print(f"🔧 SSH Strategy: ProxyJump + SSH Agent Forwarding")
    print(f"🔑 Using SSH key: {key_path}")
    
    # Show structure
    print("\n📋 Generated groups:")
    for group, config in inventory.items():
        if group != 'all' and 'hosts' in config:
            hosts = list(config['hosts'].keys())
            print(f"  {group}: {hosts}")
    
    # Show critical SSH configuration being used
    print(f"\n🔍 SSH Configuration:")
    for host_key, host_config in all_hosts.items():
        ip = host_config['ansible_host']
        role = host_config['role']
        if 'ansible_ssh_common_args' in host_config:
            print(f"  {host_key}: {ip} (ProxyJump + Agent Forwarding)")
        else:
            print(f"  {host_key}: {ip} (direct connection)")
    
    print(f"\n🔐 SECURE: SSH Agent Forwarding keeps private keys on your machine")
    print(f"   Bastion hosts can use your local SSH keys without storing them")

if __name__ == '__main__':
    main()
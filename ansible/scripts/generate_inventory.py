#!/usr/bin/env python3
import argparse
import json
from datetime import datetime
from pathlib import Path
import os
import yaml

HEADER = """# 🤖 AUTO-GENERATED INVENTORY - DO NOT EDIT
# Generated: {ts}
# Source: {src}
# SSH Strategy: ProxyJump + SSH Agent Forwarding + Ansible User
# SECURE: Uses ansible service user instead of root (after migration)
#
"""

def parse_args():
    p = argparse.ArgumentParser(description="Generate Ansible inventory from terraform outputs.")
    p.add_argument("--outputs", default="terraform_outputs.json", help="Path to terraform outputs JSON")
    p.add_argument("--inventory", default="inventories/from_terraform.yml", help="Path to write inventory YAML")
    p.add_argument("--ssh-key", default="~/.ssh/digitalocean", help="Default SSH key path")
    return p.parse_args()

def load_terraform_outputs(filepath):
    try:
        with open(filepath, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"❌ {filepath} not found. Run 'make inventory' first.")
        exit(1)

def main():
    args = parse_args()
    tf_outputs = load_terraform_outputs(args.outputs)

    # 🔑 Detect which user should be used
    # If marker file exists, use ansible. Else, root.
    marker = Path(".ansible_user_enabled")
    if marker.exists():
        default_user = "ansible"
    else:
        default_user = "root"

    # SSH key
    key_override = os.environ.get("ANSIBLE_SSH_KEY_PATH") or os.environ.get("DO_SSH_KEY_PATH")
    key_path = Path(key_override).expanduser() if key_override else Path(args.ssh_key).expanduser()
    if not key_path.exists():
        print(f"❌ Expected SSH key not found at {key_path}.")
        exit(1)

    # Build host groups
    all_hosts, staging_hosts, production_hosts = {}, {}, {}
    bastion_hosts, frontend_hosts, backend_hosts, app_server_hosts = {}, {}, {}, {}

    for env in ["staging", "production"]:
        bastion_dns = tf_outputs.get(f"{env}_bastion_dns", {}).get("value")
        frontend_dns = tf_outputs.get(f"{env}_frontend_private_dns", {}).get("value")
        backend_dns = tf_outputs.get(f"{env}_backend_private_dns", {}).get("value")

        # Bastion
        if bastion_dns:
            key = f"{env}-bastion"
            host_config = {
                "ansible_host": bastion_dns,
                "ansible_user": default_user,
                "ansible_ssh_private_key_file": str(key_path),
                "role": "bastion",
                "env_name": env,
            }
            all_hosts[key] = host_config
            bastion_hosts[key] = host_config
            (staging_hosts if env == "staging" else production_hosts)[key] = host_config

        # Frontend
        if frontend_dns and bastion_dns:
            key = f"{env}-frontend"
            ssh_common_args = (
                f"-o ProxyJump={default_user}@{bastion_dns} "
                "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
                "-o ForwardAgent=yes -o IdentitiesOnly=yes"
            )
            host_config = {
                "ansible_host": frontend_dns,
                "ansible_user": default_user,
                "ansible_ssh_private_key_file": str(key_path),
                "ansible_ssh_common_args": ssh_common_args,
                "role": "frontend",
                "env_name": env,
            }
            all_hosts[key] = host_config
            frontend_hosts[key] = host_config
            app_server_hosts[key] = host_config
            (staging_hosts if env == "staging" else production_hosts)[key] = host_config

        # Backend
        if backend_dns and bastion_dns:
            key = f"{env}-backend"
            ssh_common_args = (
                f"-o ProxyJump={default_user}@{bastion_dns} "
                "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
                "-o ForwardAgent=yes -o IdentitiesOnly=yes"
            )
            host_config = {
                "ansible_host": backend_dns,
                "ansible_user": default_user,
                "ansible_ssh_private_key_file": str(key_path),
                "ansible_ssh_common_args": ssh_common_args,
                "role": "backend",
                "env_name": env,
            }
            all_hosts[key] = host_config
            backend_hosts[key] = host_config
            app_server_hosts[key] = host_config
            (staging_hosts if env == "staging" else production_hosts)[key] = host_config

    # Structured inventory
    inventory = {
        "all": {"hosts": all_hosts},
        "staging": {"hosts": staging_hosts},
        "production": {"hosts": production_hosts},
        "bastion": {"hosts": bastion_hosts},
        "frontend": {"hosts": frontend_hosts},
        "backend": {"hosts": backend_hosts},
        "app_servers": {"hosts": app_server_hosts},
    }

    # Write inventory
    ts = datetime.now().isoformat()
    inventory_path = Path(args.inventory)
    inventory_path.parent.mkdir(parents=True, exist_ok=True)

    with open(inventory_path, "w") as f:
        f.write(HEADER.format(ts=ts, src=args.outputs))
        yaml.dump(inventory, f, default_flow_style=False, indent=2)

    print(f"✅ Inventory generated: {inventory_path}")
    print(f"🔧 SSH Strategy: ProxyJump + SSH Agent Forwarding")
    print(f"🔑 Using SSH key: {key_path}")
    print(f"👤 Using user: {default_user}")

if __name__ == "__main__":
    main()

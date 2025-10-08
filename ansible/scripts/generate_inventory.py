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

def get_output_value(outputs, key):
    value = outputs.get(key, {}).get("value")
    if value in (None, ""):
        return None
    return value


def main():
    args = parse_args()
    tf_outputs = load_terraform_outputs(args.outputs)

    # 🔑 Detect which user should be used for direct connections
    marker = Path(".ansible_user_enabled")
    default_user = "ansible" if marker.exists() else "root"

    # Always prefer the service account for ProxyJump to enforce hardened SSH
    proxyjump_user = "ansible"

    # SSH key
    key_override = os.environ.get("ANSIBLE_SSH_KEY_PATH") or os.environ.get("DO_SSH_KEY_PATH")
    key_path = Path(key_override).expanduser() if key_override else Path(args.ssh_key).expanduser()
    if not key_path.exists():
        print(f"❌ Expected SSH key not found at {key_path}.")
        exit(1)

    # Build host groups
    all_hosts, staging_hosts, production_hosts = {}, {}, {}
    bastion_hosts, frontend_hosts, backend_hosts, app_server_hosts = {}, {}, {}, {}

    db_hosts = {
        "staging_db_host": get_output_value(tf_outputs, "staging_db_host"),
        "production_db_host": get_output_value(tf_outputs, "production_db_host"),
    }

    for env in ["staging", "production"]:
        bastion_dns = get_output_value(tf_outputs, f"{env}_bastion_dns")
        frontend_dns = get_output_value(tf_outputs, f"{env}_frontend_private_dns")
        backend_dns = get_output_value(tf_outputs, f"{env}_backend_private_dns")

        # Bastion
        if bastion_dns:
            key = f"{env}-bastion"
            host_config = {
                "ansible_host": bastion_dns,
                "ansible_user": default_user,
                "ansible_ssh_private_key_file": str(key_path),
                "role": "bastion",
                "env_name": env,
                "private_ip": bastion_dns,
            }
            all_hosts[key] = host_config
            bastion_hosts[key] = host_config
            (staging_hosts if env == "staging" else production_hosts)[key] = host_config

        # Frontend
        if frontend_dns and bastion_dns:
            key = f"{env}-frontend"
            ssh_common_args = (
                f"-o ProxyJump={proxyjump_user}@{bastion_dns} "
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
                "private_ip": frontend_dns,
            }
            all_hosts[key] = host_config
            frontend_hosts[key] = host_config
            app_server_hosts[key] = host_config
            (staging_hosts if env == "staging" else production_hosts)[key] = host_config

        # Backend
        if backend_dns and bastion_dns:
            key = f"{env}-backend"
            ssh_common_args = (
                f"-o ProxyJump={proxyjump_user}@{bastion_dns} "
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
                "private_ip": backend_dns,
            }
            all_hosts[key] = host_config
            backend_hosts[key] = host_config
            app_server_hosts[key] = host_config
            (staging_hosts if env == "staging" else production_hosts)[key] = host_config

    # Structured inventory with database host vars
    base_all = {"hosts": all_hosts}
    # Inject DB hosts only when available
    db_vars = {k: v for k, v in db_hosts.items() if v}
    if db_vars:
        base_all["vars"] = db_vars

    inventory = {
        "all": base_all,
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
        yaml.dump(inventory, f, default_flow_style=False, indent=2, sort_keys=False)

    print(f"✅ Inventory generated: {inventory_path}")
    print(f"🔧 SSH Strategy: ProxyJump + SSH Agent Forwarding")
    print(f"🔑 Using SSH key: {key_path}")
    print(f"👤 Direct user: {default_user} | ProxyJump user: {proxyjump_user}")

if __name__ == "__main__":
    main()

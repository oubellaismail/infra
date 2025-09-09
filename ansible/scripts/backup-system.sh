#!/bin/bash
set -euo pipefail

BACKUP_DIR="/opt/backups"
DATE=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname)
RETENTION_DAYS=30

mkdir -p "$BACKUP_DIR"
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log "Starting backup on $HOSTNAME"

# Backup key configuration files
tar -czf "$BACKUP_DIR/config-$HOSTNAME-$DATE.tar.gz" \
    /etc/nginx \
    /etc/ssh/sshd_config \
    /etc/fail2ban \
    /opt/{{ app.name }} \
    --exclude /opt/{{ app.name }}/logs \
    --exclude /opt/{{ app.name }}/data

# Backup application logs
tar -czf "$BACKUP_DIR/logs-$HOSTNAME-$DATE.tar.gz" /var/log/{{ app.name }}

log "Backup completed successfully."

# Cleanup old backups
find "$BACKUP_DIR" -type f -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete
log "Old backups cleaned up."
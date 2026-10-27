#!/bin/bash
# Run once as root on the VM (idempotent): service user, directories, env file, units, Caddy site block.
set -euo pipefail
HOST="${1:-qread.forfine.me}"
id qread >/dev/null 2>&1 || useradd --system --home /var/lib/qread --shell /usr/sbin/nologin qread
install -d -o qread -g qread -m 750 /var/lib/qread
install -d -o root -g root -m 755 /srv/qread/releases
install -d -o root -g qread -m 750 /etc/qread
if [ ! -f /etc/qread/qread.env ]; then
  cat > /etc/qread/qread.env <<ENV
QREAD_HOST=127.0.0.1
QREAD_PORT=8920
QREAD_DATA_DIR=/var/lib/qread
QREAD_BASE_URL=https://${HOST}
QREAD_REGISTER=invite
QREAD_MAIL=off
ENV
  chown root:qread /etc/qread/qread.env; chmod 640 /etc/qread/qread.env
fi
install -m 644 /tmp/qread-deploy/qread-server.service /etc/systemd/system/qread-server.service
install -m 644 /tmp/qread-deploy/qread-backup.service /etc/systemd/system/qread-backup.service
install -m 644 /tmp/qread-deploy/qread-backup.timer /etc/systemd/system/qread-backup.timer
install -m 755 /tmp/qread-deploy/qread-admin.sh /usr/local/bin/qread-admin
systemctl daemon-reload

# Caddy: add the site block through an import so the td2 block is never rewritten
install -d /etc/caddy/conf.d
cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak-qread
if ! grep -q 'import /etc/caddy/conf.d/\*.caddy' /etc/caddy/Caddyfile; then
  printf '\nimport /etc/caddy/conf.d/*.caddy\n' >> /etc/caddy/Caddyfile
fi
sed "s/qread\.forfine\.me/${HOST}/" /tmp/qread-deploy/Caddyfile.qread > /etc/caddy/conf.d/qread.caddy
if caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1; then
  echo "caddy config valid"
else
  echo "caddy config INVALID, restoring" >&2
  cp /etc/caddy/Caddyfile.bak-qread /etc/caddy/Caddyfile; rm -f /etc/caddy/conf.d/qread.caddy
  exit 1
fi

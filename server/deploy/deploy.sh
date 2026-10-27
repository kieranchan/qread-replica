#!/bin/bash
# Deploy the server to the Korean VM (run from Git Bash):  deploy/deploy.sh [--bootstrap] [--rollback]
# Needs: ssh key ~/.ssh/id_ed25519_td2, node on the VM (/opt/node). Keeps the 3 newest releases, rolls back on a failed health check.
set -euo pipefail
cd "$(dirname "$0")/.."
SSH_KEY="${QREAD_SSH_KEY:-$HOME/.ssh/id_ed25519_td2}"
# the VM address is not kept in the repository: export QREAD_SSH_TARGET=user@host or put it in deploy/target.env (git-ignored)
[ -f deploy/target.env ] && . deploy/target.env
TARGET="${QREAD_SSH_TARGET:-}"
[ -n "$TARGET" ] || { echo "set QREAD_SSH_TARGET=user@host (or deploy/target.env)" >&2; exit 2; }
SSH=(ssh -i "$SSH_KEY" -o BatchMode=yes -o LogLevel=ERROR "$TARGET")
SCP=(scp -i "$SSH_KEY" -o BatchMode=yes -o LogLevel=ERROR)
TS=$(date -u +%Y%m%d-%H%M%S)

if [ "${1:-}" = "--rollback" ]; then
  "${SSH[@]}" 'set -e; cd /srv/qread/releases; cur=$(basename "$(readlink -f /srv/qread/current)"); prev=$(ls -1 | sort | grep -B1 -x "$cur" | head -1); [ "$prev" != "$cur" ] || { echo "no older release"; exit 1; }; sudo ln -sfn /srv/qread/releases/$prev /srv/qread/current; sudo systemctl restart qread-server; echo "rolled back to $prev"'
  exit 0
fi

tar -czf "/tmp/qread-$TS.tgz" package.json src
"${SSH[@]}" 'rm -rf /tmp/qread-deploy && mkdir -p /tmp/qread-deploy'
"${SCP[@]}" "/tmp/qread-$TS.tgz" "$TARGET:/tmp/qread-deploy/release.tgz"
"${SCP[@]}" deploy/qread-server.service deploy/qread-backup.service deploy/qread-backup.timer deploy/qread-admin.sh deploy/Caddyfile.qread deploy/bootstrap-qread.sh "$TARGET:/tmp/qread-deploy/"
if [ "${1:-}" = "--bootstrap" ]; then
  "${SSH[@]}" 'sudo bash /tmp/qread-deploy/bootstrap-qread.sh'
fi
"${SSH[@]}" "TS=$TS bash -s" <<'REMOTE'
set -euo pipefail
sudo install -d /srv/qread/releases/$TS
sudo tar -xzf /tmp/qread-deploy/release.tgz -C /srv/qread/releases/$TS
sudo chown -R root:root /srv/qread/releases/$TS
prev=$(readlink -f /srv/qread/current 2>/dev/null || true)
sudo ln -sfn /srv/qread/releases/$TS /srv/qread/current
sudo systemctl enable qread-server qread-backup.timer >/dev/null 2>&1
sudo systemctl restart qread-server
ok=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS http://127.0.0.1:8920/healthz >/dev/null 2>&1; then ok=1; break; fi
  sleep 1
done
if [ "$ok" != 1 ]; then
  echo "health check failed, rolling back" >&2
  sudo journalctl -u qread-server -n 20 --no-pager >&2 || true
  if [ -n "$prev" ]; then sudo ln -sfn "$prev" /srv/qread/current; sudo systemctl restart qread-server; fi
  exit 1
fi
sudo systemctl start qread-backup.timer
sudo systemctl reload caddy || true
# keep the 3 newest releases
cd /srv/qread/releases && ls -1 | sort | head -n -3 | xargs -r -I{} sudo rm -rf /srv/qread/releases/{}
echo "deployed $TS"
curl -fsS http://127.0.0.1:8920/healthz; echo
REMOTE
rm -f "/tmp/qread-$TS.tgz"

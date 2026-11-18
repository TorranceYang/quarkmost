#!/bin/bash
# Run ON THE SERVER as root, from a folder containing: router.py, the two .service files,
# mattermost-push-proxy.json (filled in) and your AuthKey_*.p8.
# Installs both services listening on localhost only. It does NOT change Mattermost's settings;
# that last step is done by hand in the System Console (see README).
set -euo pipefail
DIR=/opt/quarkmost-push
[ -f mattermost-push-proxy.json ] || { echo "mattermost-push-proxy.json is missing"; exit 1; }
ls AuthKey_*.p8 >/dev/null 2>&1 || { echo "AuthKey_*.p8 is missing"; exit 1; }
case "$(uname -m)" in x86_64) ARCH=amd64 ;; aarch64) ARCH=arm64 ;; *) echo "unsupported CPU"; exit 1 ;; esac
mkdir -p "$DIR"
cp router.py "$DIR/"
if [ ! -x "$DIR/mattermost-push-proxy/bin/mattermost-push-proxy" ]; then
  curl -fsSL "https://github.com/mattermost/mattermost-push-proxy/releases/latest/download/mattermost-push-proxy-linux-$ARCH.tar.gz" | tar xz -C "$DIR"
  # The archive unpacks to a folder named after the CPU type; give it a stable name.
  rm -rf "$DIR/mattermost-push-proxy"
  mv "$DIR/mattermost-push-proxy-linux-$ARCH" "$DIR/mattermost-push-proxy"
fi
cp mattermost-push-proxy.json AuthKey_*.p8 "$DIR/mattermost-push-proxy/config/"
chown -R mattermost:mattermost "$DIR"
chmod 600 "$DIR"/mattermost-push-proxy/config/AuthKey_*.p8
cp push-proxy.service push-router.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now push-proxy push-router
sleep 2
curl -fsS http://127.0.0.1:8067/healthz && echo " <- router is up"
systemctl --no-pager --lines=5 status push-proxy | tail -6
echo "Next: System Console > Environment > Push Notification Server > http://127.0.0.1:8067"

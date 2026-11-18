# Push router and proxy setup

These files set up push notifications for Quarkmost on your Mattermost server:

- `router.py`
- `install.sh`
- the two `.service` files
- `push-proxy.example.json`

The full guide is [docs/NOTIFICATIONS.md](../../docs/NOTIFICATIONS.md).

In short:

1. `cp push-proxy.example.json mattermost-push-proxy.json` and fill it in. This file is gitignored. Never
   commit it, or your `.p8` key.
2. Copy this folder plus your `AuthKey_*.p8` to the server, then run `sudo ./install.sh`.
3. Point *System Console → Environment → Push Notification Server* at one of:
   - `http://127.0.0.1:8067` (the router), or
   - `http://127.0.0.1:8066` (the proxy directly), if nobody on the server uses the official app.

Logs: `journalctl -u push-router -f` and `journalctl -u push-proxy -f`.

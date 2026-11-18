#!/bin/zsh
# Sends a fake push notification to the app in a booted simulator, so you can test what happens
# when you tap a notification (the keyboard bug). No server or Apple push key needed.
#
#   scripts/test-push.sh                 # your own DM, on the iPhone 17 simulator
#   (the bundle ID is read from Config/Local.xcconfig; or set QM_BUNDLE_ID=... in the environment)
#   scripts/test-push.sh "iPhone Duo"    # another simulator
#   scripts/test-push.sh "iPhone 17" "Town Square"  # a channel by name
#
# Try it in each state: app closed, app in the background with the keyboard open, phone locked.
set -e
DEVICE="${1:-iPhone 17}"
CHANNEL_NAME="${2:-}"
BUNDLE="${QM_BUNDLE_ID:-$(sed -n 's/^QM_BUNDLE_ID *= *//p' "$(dirname "$0")/../Config/Local.xcconfig" 2>/dev/null | tail -1)}"
BUNDLE="${BUNDLE:-com.example.quarkmost}"
DATA=$(xcrun simctl get_app_container "$DEVICE" $BUNDLE data)
CACHE="$DATA/Library/Caches/store/sidebar.json"
[ -f "$CACHE" ] || { echo "Open the app and log in on \"$DEVICE\" first."; exit 1; }
CHANNEL_ID=$(python3 -I - "$CACHE" "$CHANNEL_NAME" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); want = sys.argv[2].lower(); me = d["me"]["id"]
for c in d["channels"]:
    if (want and c["displayName"].lower() == want) or (not want and c["type"] == "D" and c["name"] == me + "__" + me):
        print(c["id"]); break
PY
)
[ -n "$CHANNEL_ID" ] || { echo "Couldn't find that channel in the app's cache."; exit 1; }
PAYLOAD=$(mktemp -t push).json
cat > "$PAYLOAD" <<JSON
{"aps":{"alert":{"title":"Test sender","body":"Tap me to open the conversation"},"sound":"default","category":"CAN_REPLY","mutable-content":1},
 "type":"message","channel_id":"$CHANNEL_ID","post_id":"simulatedpost0000000000000","root_id":"","sender_name":"Test sender","channel_name":"$CHANNEL_NAME"}
JSON
xcrun simctl push "$DEVICE" $BUNDLE "$PAYLOAD"
echo "Sent. Tap the banner on \"$DEVICE\" (or pull down Notification Center)."

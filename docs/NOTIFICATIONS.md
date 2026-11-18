# Push notifications

You need to own the Mattermost server, or have its admin's help, to set this up. It takes about 20 minutes.

## Why there's setup

A Mattermost server doesn't talk to Apple directly. It sends each push to a **push proxy**, configured under
*System Console → Environment → Push Notification Server*. The proxy then hands the push to Apple (APNs)
using the Apple key of the app it's for.

The push services Mattermost runs (`push-test.mattermost.com`, and `push.mattermost.com` for licensed
servers) hold the keys for the **official** apps only. Your Quarkmost build has its own bundle ID, so Apple
will only accept pushes for it that are signed with **your** key. That means you run your own copy of
[mattermost-push-proxy](https://github.com/mattermost/mattermost-push-proxy) with your key.

A server can only have one push proxy. If some people on the server still use the official app, put the
small **router** in this repo in front, so each push goes to the right place:

```
                        ┌─ platform "apple" (Quarkmost) ──► your push-proxy ──► APNs (your key)
Mattermost ──► router ──┤
                        └─ anything else (official apps) ──► the push service you used before
```

| Your situation | Set *Push Notification Server* to |
|---|---|
| Some people still use the official app | the router: `http://127.0.0.1:8067` |
| Everyone uses Quarkmost | your push-proxy directly: `http://127.0.0.1:8066` (skip the router) |

The router is a single Python file with no dependencies. It forwards message contents unchanged and never logs
them.

## 1. Make an Apple push key

1. Go to [developer.apple.com → Keys](https://developer.apple.com/account/resources/authkeys/list) and click **+**.
2. Enable **Apple Push Notifications service (APNs)**. Set the environment to **Sandbox & Production**.
3. Download the `AuthKey_XXXXXXXXXX.p8` file. Apple only lets you download it once, so keep it safe and
   **never commit it**. `*.p8` is already gitignored.
4. Note the **Key ID**. You'll also need your **Team ID**.

## 2. Configure the proxy

In `server/push-router/`, copy `push-proxy.example.json` to `mattermost-push-proxy.json`. That file is
gitignored. Fill in:

| Field | Value |
|---|---|
| `ApplePushTopic` | your `QM_BUNDLE_ID` (from `Config/Local.xcconfig`) |
| `AppleAuthKeyFile` | `./config/AuthKey_XXXXXXXXXX.p8` |
| `AppleAuthKeyID` / `AppleTeamID` | from step 1 |
| `ApplePushUseDevelopment` | `true` for builds run from Xcode, `false` for TestFlight builds |
| `Type` | leave it as `apple`. The app registers its devices as `apple:<token>`. |

## 3. Install on the server

`install.sh` assumes a Linux server where Mattermost runs under systemd as the `mattermost` user, with
`python3` available. If your setup is different (Docker, for example), read the script and adapt it. It
only does a few things.

1. Copy the `server/push-router/` folder and your `.p8` to the server.
2. If you're using the router, edit `DEFAULT_UPSTREAM` in `push-router.service` to whatever *Push
   Notification Server* is set to today:
   - `https://push-test.mattermost.com` (the default), or
   - `https://push.mattermost.com` (licensed servers).
3. Run `sudo ./install.sh`. It does the following:
   - installs the push-proxy on `127.0.0.1:8066` and the router on `127.0.0.1:8067`, as two systemd services
   - listens on localhost only
   - doesn't change any Mattermost settings
4. In *System Console → Environment → Push Notification Server*, choose *Manually enter Push Notification
   Service location* and enter the address from the table above. Save.
5. In *System Console → Site Configuration → Notifications*, set *Push Notification Contents* to either:
   - **Full message content sent in the notification payload**, or
   - a generic option.

   *Full message content fetched from the server on receipt* (ID-only) isn't supported: you'd see
   placeholder text instead of the message.

## 4. Check it

1. Open Quarkmost on your phone and allow notifications. The app registers your device with the server when
   it starts.
2. Have someone mention you, or DM you, while the app is in the background.
3. Watch the logs:

```
journalctl -u push-router -f   # "platform=apple -> app 200" for Quarkmost, "-> default 200" for official apps
journalctl -u push-proxy -f    # Apple's response for each push to Quarkmost
```

Notifications show the channel name, the sender's profile picture, and the message, the way the official app
shows them. You can reply straight from the notification.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `BadDeviceToken` | `ApplePushUseDevelopment` doesn't match the build: `true` for Xcode, `false` for TestFlight. |
| `BadEnvironmentKeyInToken` | The key was made for only one environment. Make one for *Sandbox & Production*. |
| `DeviceTokenNotForTopic` / `TopicDisallowed` | `ApplePushTopic` doesn't match your bundle ID. |
| Nothing in the router log | Mattermost isn't pointed at the router, or the person was active on another device. Mattermost skips pushes for people who are online elsewhere, depending on their notification settings. |
| App icon and generic text instead of the sender's picture | The notification extension couldn't read your session. Open the app once after installing or updating. |

## Undo

1. Set *Push Notification Server* back to its old value.
2. Run `sudo systemctl disable --now push-router push-proxy` to stop both services.

## Testing without a server

`scripts/test-push.sh` sends a simulated push to a booted iOS Simulator. Use it to check what happens when you
tap a notification. It needs no Apple key.

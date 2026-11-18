# Deploying Quarkmost for yourself

Quarkmost isn't distributed anywhere. You build it, sign it with your own Apple developer account, and put it
on your own phone or your own TestFlight. This guide covers that, plus what the licenses ask of you.

## What you need

- A Mac with **Xcode 26** or newer. The app targets iOS 18+.
- A **paid Apple Developer Program** membership if you want push notifications or TestFlight.
  - A free Apple ID can still run the app on your own phone, for 7 days at a time and without notifications.
  - To do that, delete the `aps-environment` and `com.apple.developer.usernotifications.communication`
    entries from `Config/Quarkmost.entitlements`.
- An account on a Mattermost server, version 9.11 or newer, that accepts username/email and password.

## 1. Configure your copy

All personal settings live in one file that isn't committed. Create `Config/Local.xcconfig`:

```
DEVELOPMENT_TEAM = ABCDE12345
QM_BUNDLE_ID = com.yourname.quarkmost
QM_DISPLAY_NAME = Quarkmost
QM_DEFAULT_SERVER_URL = https:/$()/chat.example.com
```

| Setting | What it is |
|---|---|
| `DEVELOPMENT_TEAM` | Your Team ID: [developer.apple.com/account](https://developer.apple.com/account) → Membership details. |
| `QM_BUNDLE_ID` | Any reverse-DNS ID that's yours. The notification extension becomes `<id>.NotificationService`. |
| `QM_DISPLAY_NAME` | The name under the home-screen icon. **Don't** use "Mattermost" in it (see [Licensing](#licensing-checklist)). |
| `QM_DEFAULT_SERVER_URL` | Optional. It pre-fills the server field on the login screen. Write `https:/$()/` instead of `https://`, because xcconfig treats `//` as the start of a comment. |

Everything else (the keychain group shared with the notification extension, the push topic) is derived from
`QM_BUNDLE_ID`.

## 2. Run it on your iPhone

1. Open `Quarkmost.xcodeproj` and select the **Quarkmost** scheme and your iPhone.
2. Under *Signing & Capabilities*, leave **Automatically manage signing** on. On the first build, Xcode
   registers both App IDs with these capabilities:
   - Push Notifications
   - Communication Notifications
   - Keychain Sharing
3. Press Run. On the login screen, enter your server address, username and password.

If Xcode reports a missing capability, add it to that App ID at
[developer.apple.com → Identifiers](https://developer.apple.com/account/resources/identifiers/list), then
build again.

## 3. TestFlight (optional, for friends)

1. In [App Store Connect](https://appstoreconnect.apple.com), create a new app with your bundle ID. The app
   name has to be unique across the App Store, so pick your own, and keep it free of "Mattermost".
2. In Xcode, choose **Product → Archive**, then **Distribute App → App Store Connect → Upload**.
3. **Internal testers** (people on your App Store Connect team) can install the build right away.
   **External testers** need Apple's one-time Beta App Review, which usually takes about a day.
4. Builds expire after 90 days, so upload a new one before then.

For push notifications on TestFlight builds, see [NOTIFICATIONS.md](NOTIFICATIONS.md).
`ApplePushUseDevelopment` must be `false` for TestFlight builds.

Publishing to the public App Store is not something this project supports or recommends.

## 4. Updating

Run `git pull` and build again. `Config/Local.xcconfig` isn't tracked, so your settings survive updates.

## Licensing checklist

Quarkmost is Apache-2.0 and derived from Mattermost Mobile, which is also Apache-2.0. Installing builds on
other people's phones, through TestFlight or any other way, counts as distribution. So:

1. **Keep the notices.** Ship with `LICENSE`, `NOTICE` and `ThirdParty/` unchanged. Keep the attribution
   text in the app's *Settings → About* screen.
2. **Say what you changed.** If you modify files and share your version, mark them as changed
   (Apache-2.0 §4(b)). Adding a line to `NOTICE` is enough.
3. **Don't use Mattermost's brand.**
   - Keep "Mattermost" and its logo out of your app's name, icon, display name and any store listing.
   - Don't suggest the app is official. The Apache license grants no trademark rights (§6), and
     [Mattermost's trademark policy](https://mattermost.com/trademark-standards-of-use/) needs their written
     approval for that.
   - Describing it as "a client for Mattermost servers" is fine.
4. **Fonts.**
   - Metropolis is under the SIL Open Font License: keep `ThirdParty/fonts/OFL-Metropolis.txt`, and don't
     sell the font on its own.
   - Open Sans and the Compass Icons font are Apache-2.0, already covered by points 1 and 2.
5. **Your own icon** is welcome. Replace `Quarkmost/Assets.xcassets/AppIcon.appiconset/icon-1024.png`
   with a 1024×1024 PNG that has no transparency.

This checklist is a good-faith summary, not legal advice.

# iPhone app blocking and daily limits

Version 1.4 implements individual Screen Time authorization, Apple's private app/category/website picker, immediate blocking, and one combined daily usage allowance. The feature requires iOS 17.4 or later. The tracker itself still supports iOS 16.

The allowance counts selected activity already recorded in the current daily interval. DeviceActivity callbacks may arrive after a delay and occur when the device is used. A new allowance begins in the next daily interval. This is self-control: the owner can stop restrictions or revoke access in Settings.

## Signing requirement

Adding an entitlement to source code does not grant it. A correctly provisioned physical iPhone build is required for real authorization and enforcement.

| Component | Registered identifier |
| --- | --- |
| Main app | `com.yassine.habitcounter` |
| Device Activity monitor | `com.yassine.habitcounter.focusmonitor` |
| Shared App Group | `group.com.yassine.habitcounter` |

Both the app and monitor extension need provisioning profiles that authorize:

- `com.apple.developer.family-controls = true`
- `com.apple.security.application-groups` containing `group.com.yassine.habitcounter`

The signer must sign both bundles using the same developer team and preserve `PlugIns/HabitFocusMonitor.appex`. Do not remove the extension. Changing the app's bundle ID or App Group requires corresponding source/profile changes, rather than only rewriting the signature.

An Apple Developer team can configure Family Controls development profiles for a registered test device. Distribution requires the relevant Apple capability approval for the app and its Screen Time extension. See [Apple: configuring Family Controls](https://developer.apple.com/documentation/xcode/configuring-family-controls) and [Apple: requesting the entitlement](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement).

## Third-party signing

Ask the signing provider whether it can provision both explicit App IDs above with Family Controls and the same registered App Group, and sign the embedded Device Activity extension without removing it.

## Build and inspect

Unsigned build:

```sh
bash scripts/build-ios.sh --unsigned
```

Find the unsigned package at `releases/Habit-Counter-iPhone-v1.4-ScreenTime-unsigned.ipa`.

For a team already authorized and configured in Xcode:

```sh
bash scripts/build-ios.sh --signed YOUR_TEAM_ID
```

The signed build runs a profile/signature check before packaging. To check a signed app independently:

```sh
python3 scripts/verify-screen-time-signing.py '/path/to/signed/Habit Counter.app'
```

This checks signature validity, matching explicit App IDs, profile expiry, team consistency, the shared group, the Family Controls entitlement in both signature and profile, and the embedded monitoring extension. It does not prove the threshold/reset behavior works on a particular device.

## State and recovery

The app picker returns opaque tokens, kept in the signed App Group container. These tokens never enter the web UI or habit backups. Configuration and a per-day reached marker are stored in a small atomic JSON file. A cross-process file lock protects the read/check/shield update, and each monitor generation rejects callbacks for superseded rules. Reopening the view preserves a reached daily limit. Unknown process-local authorization is not treated as revocation. Explicit denial clears invalidated selections. Stop writes a disabled generation and clears this app's named ManagedSettings store.

If state cannot be read, the screen reports the status as unverified. The explicit Stop action attempts recovery, and the owner can revoke Screen Time access in iPhone Settings.

## Verified and still pending

- iPhoneOS app and monitor extension compile and package successfully.
- iPhone 16 Pro Max simulator check opens the native App Limits screen, verifies authorization is unavailable in the simulator, dismisses it, and confirms the tracker remains usable.
- Existing 23 JavaScript checks pass; habit data format is unchanged.
- A correctly provisioned physical iPhone is still required to verify authorization, actual shielding, past-usage accounting, operation with the app terminated, stopping restrictions, and the next-day reset.

For immediate limits without a compatible third-party signing profile, use iPhone **Settings → Screen Time → App Limits → Add Limit**. [Apple's instructions](https://support.apple.com/en-nz/guide/iphone/iphb0c7313c9/ios).

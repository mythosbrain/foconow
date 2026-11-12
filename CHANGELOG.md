# Changelog

## 1.18.0 — 2026-11-12

### Notifications that fit your day
- Audible focus and break notifications, with distinct bundled chimes. Both breaks share the break sound. macOS delivers scheduled alerts even after quitting; the running app plays the alarm itself when timer notifications are off.
- A completion card inside the app with Start break / Start focus and Dismiss, without stealing keyboard focus.
- Optional unfinished-task reminders every 60, 90, 120, or 180 minutes, plus one check-in during a long focus session.
- Configurable quiet hours, idle/sleep suppression, and a one-hour snooze action. Task reminders stay quiet during running or paused timers.
- A Notifications & sounds panel with a test alert, sound previews, and a shortcut to macOS notification settings. Morning and evening reminders now support sound.
- Restoring an expired timer settles its history without replaying its alarm.

New nudges are opt-in. Notification text never includes task titles or notes. Everything is scheduled locally; there is no push service, account, analytics, or server. macOS Focus and notification settings can silence alerts, and alarms do not wake a sleeping Mac.

### Install and verify
Apple silicon · macOS 13+ · Widgets require macOS 14+. Ad hoc signed, not notarized. Existing data and bundle identity are unchanged.

Validated with the 45 JavaScript tests, native reminder-policy and Pomodoro checks, a real WebKit notification-settings round trip, and the packaged app’s 17 launch/background checks. Notification delivery and audibility remain subject to the user’s macOS settings.

## 1.17.0 — 2026-11-11

FocoNow 1.17.0 brings a glass interface and a clearer path from planning to focused work.

### What’s new
- Glass panels, floating navigation, refined controls, and light/dark themes.
- **Plan at a glance** shows estimated focus time left after subtracting tracked work, including carried tasks.
- **Focus next** starts the first unfinished priority, then follows your task order. An active session is protected from accidental replacement.
- **Distraction-free focus** uses the same native timer as the main app and menu bar. Pause, resume, or press Escape to return without losing your session.
- A tighter task layout, refreshed screenshots, and a reproducible branded DMG build.

### Install
Download **FocoNow-Mac-v1.17.0.dmg** below, open it, and drag FocoNow into Applications. Quit the old app before replacing it.

Apple silicon · macOS 13+ · Desktop widgets need macOS 14+.
This preview is locally signed, not Apple notarized. macOS may require approval in Privacy & Security. No new app permissions are introduced.

### Verification
45 JavaScript checks, 51 native interface checks, and 17 packaged-app startup checks passed. The DMG’s app signature, embedded assets, checksum, and Finder installation layout were verified. Screenshots use sample data.

Existing data locations and the bundle identifier are unchanged. Focus history remains separate from the JSON planner backup; this update does not migrate or erase your records.

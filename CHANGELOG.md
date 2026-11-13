# Changelog

## 1.19.0 — 2026-11-13

### Complete backups and clearer planning
- One portable JSON backup includes planner records, deadlines, journals, bad habits, focus sessions/spans, timer settings, portable app preferences, and imported iPhone Screen Time reports.
- Preview before restoring. Keep a complete safety copy in Recovery copies and roll back a failed or interrupted restore. Exporting leaves a live timer running; restoring brings it back paused.
- Older planner-only backups still work without replacing focus history or native preferences. macOS permissions, login registration, window placement, and system-owned Screen Time data are not copied.
- Optional task deadlines with local times, overdue badges/filter, and opt-in local notifications. Carried copies share one alert; finishing the latest copy cancels it. The nearest 32 future alerts are scheduled and refreshed while the app runs.
- A redesigned date control and calendar with month navigation, Today/Tomorrow shortcuts, arrow keys, and Page Up/Down. Supports light and dark themes.

Backup files stay local and are not encrypted. Deadline notifications respect macOS authorization, Focus, and sound settings. Ad hoc signed, not notarized. Existing app identity and storage locations are preserved.


Validated with 49 JavaScript tests, native complete-backup failure/recovery and Pomodoro checks, a real WebKit backup/deadline/calendar round trip, and the packaged app’s 17 launch/background checks.

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

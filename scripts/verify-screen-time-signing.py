#!/usr/bin/env python3
"""Check a signed .app without printing certificates, device lists, or profile contents."""
import datetime
import pathlib
import plistlib
import subprocess
import sys

GROUP = 'group.com.yassine.habitcounter'
CAPABILITY = 'com.apple.developer.family-controls'

def plist(path):
    with path.open('rb') as handle:
        return plistlib.load(handle)

def inspect(bundle):
    info = plist(bundle / 'Info.plist')
    identifier = info['CFBundleIdentifier']
    profile_path = bundle / 'embedded.mobileprovision'
    if not profile_path.exists():
        raise ValueError(f'{identifier}: no embedded provisioning profile. This build cannot be verified for Screen Time.')
    result = subprocess.run(['security', 'cms', '-D', '-i', str(profile_path)], capture_output=True, check=False)
    if result.returncode:
        raise ValueError(f'{identifier}: provisioning profile could not be decoded.')
    profile = plistlib.loads(result.stdout)
    expiry = profile.get('ExpirationDate')
    if not isinstance(expiry, datetime.datetime) or expiry.replace(tzinfo=datetime.timezone.utc) <= datetime.datetime.now(datetime.timezone.utc):
        raise ValueError(f'{identifier}: provisioning profile is expired or has no expiry.')
    result = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(bundle)], capture_output=True, check=False)
    try:
        signed = plistlib.loads(result.stdout)
    except Exception:
        raise ValueError(f'{identifier}: no readable code-signing entitlements.')
    allowed = profile.get('Entitlements', {})
    for origin, values in [('profile', allowed), ('signature', signed)]:
        if values.get(CAPABILITY) is not True:
            raise ValueError(f'{identifier}: Family Controls is missing from its {origin}.')
        if GROUP not in values.get('com.apple.security.application-groups', []):
            raise ValueError(f'{identifier}: the shared Screen Time App Group is missing from its {origin}.')
        app_id = values.get('application-identifier', '')
        if not app_id.endswith('.' + identifier):
            raise ValueError(f'{identifier}: its {origin} is not for this explicit App ID.')
    if signed.get('application-identifier') != allowed.get('application-identifier'):
        raise ValueError(f'{identifier}: signature and profile App IDs differ.')
    teams = profile.get('TeamIdentifier', [])
    if not teams or signed.get('com.apple.developer.team-identifier') != teams[0]:
        raise ValueError(f'{identifier}: signature and provisioning team do not match.')
    print(f'OK: {identifier} has matching Family Controls and App Group rights.')
    return teams[0], info

def main():
    if len(sys.argv) != 2:
        raise ValueError('Usage: python3 scripts/verify-screen-time-signing.py /absolute/path/to/signed/Habit Counter.app')
    app = pathlib.Path(sys.argv[1]).resolve()
    verify = subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], capture_output=True, check=False)
    if verify.returncode:
        raise ValueError('The app or an embedded extension has no valid signature.')
    main_team, main_info = inspect(app)
    monitor = app / 'PlugIns' / 'HabitFocusMonitor.appex'
    if not monitor.is_dir():
        raise ValueError('The Device Activity monitoring extension is missing. The signer must preserve it.')
    extension_team, extension_info = inspect(monitor)
    if extension_team != main_team:
        raise ValueError('The app and monitoring extension use different developer teams.')
    if extension_info.get('CFBundleIdentifier') != main_info['CFBundleIdentifier'] + '.focusmonitor':
        raise ValueError('The monitoring extension is not registered under this app identifier.')
    if extension_info.get('NSExtension', {}).get('NSExtensionPointIdentifier') != 'com.apple.deviceactivity.monitor-extension':
        raise ValueError('The embedded extension is not a Device Activity monitor.')
    print('Signing checks passed. Actual authorization, blocking, usage thresholds and daily reset still require testing on the provisioned physical iPhone.')

if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(f'Screen Time signing check failed: {error}', file=sys.stderr)
        sys.exit(1)

#!/usr/bin/env python3
"""Provision an explicit iOS 18.5 test device instead of assuming runner devices."""
import json
import pathlib
import subprocess


def run(*command):
    return subprocess.run(command, check=True, capture_output=True, text=True).stdout


def runtime():
    entries = json.loads(run('xcrun', 'simctl', 'list', 'runtimes', '--json'))['runtimes']
    return next((item['identifier'] for item in entries
                 if item.get('isAvailable') and item.get('version') == '18.5'
                 and item['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-')), None)


selected = runtime()
if selected is None:
    subprocess.run(['xcodebuild', '-downloadPlatform', 'iOS', '-buildVersion', '18.5',
                    '-architectureVariant', 'universal'], check=True)
    selected = runtime()
if selected is None:
    raise RuntimeError('iOS 18.5 simulator runtime unavailable after installation')
devices = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '--json'))['devices']
existing = next((item for item in devices.get(selected, [])
                 if item.get('isAvailable') and item.get('name') == 'iPhone 16'), None)
device = existing['udid'] if existing else run(
    'xcrun', 'simctl', 'create', 'GameLingo-CI',
    'com.apple.CoreSimulator.SimDeviceType.iPhone-16', selected).strip()
# CoreSimulator launches long-lived child services. Keep their inherited output
# away from the shell's tee pipe, so a timed-out boot cannot hold the CI step open.
log = pathlib.Path('build/logs/simulator-boot.log')
log.parent.mkdir(parents=True, exist_ok=True)
print(f'Preparing simulator {device} / {selected}', flush=True)
try:
    with log.open('w') as output:
        if not existing or existing.get('state') != 'Booted':
            subprocess.run(['xcrun', 'simctl', 'boot', device], check=True,
                           stdout=output, stderr=subprocess.STDOUT, timeout=120)
        subprocess.run(['xcrun', 'simctl', 'bootstatus', device, '-b'], check=True,
                       stdout=output, stderr=subprocess.STDOUT, timeout=600)
finally:
    print(log.read_text(errors='replace')[-6000:], flush=True)
destination = f'platform=iOS Simulator,id={device},arch={run("uname", "-m").strip()}'
pathlib.Path('build/simulator-destination.txt').write_text(destination)
print(f'Test destination: {destination} / {selected}')

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
device = run('xcrun', 'simctl', 'create', 'GameLingo-CI',
             'com.apple.CoreSimulator.SimDeviceType.iPhone-16', selected).strip()
subprocess.run(['xcrun', 'simctl', 'boot', device], check=True)
subprocess.run(['xcrun', 'simctl', 'bootstatus', device, '-b'], check=True, timeout=300)
destination = f'platform=iOS Simulator,id={device},arch={run("uname", "-m").strip()}'
pathlib.Path('build/simulator-destination.txt').write_text(destination)
print(f'Test destination: {destination} / {selected}')

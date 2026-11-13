#!/usr/bin/env python3
"""Test the packaging validator using explicitly synthetic files, never label them a built app."""
import importlib.util
import pathlib
import plistlib
import struct
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ipa_validator', ROOT / 'Scripts/validate-ipa.py')
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class PackagingTests(unittest.TestCase):
    def package(self, path, extra=None, executable=None):
        prefix = 'Payload/GameLingo.app/'
        items = {
            prefix + 'Info.plist': plistlib.dumps({'CFBundleExecutable': 'GameLingo', 'CFBundleIdentifier': 'dev.gamelingo.ios', 'CFBundlePackageType': 'APPL'}),
            prefix + 'GameLingo': executable or struct.pack('<IIIIIIII', 0xfeedfacf, 0x0100000C, 0, 2, 0, 0, 0, 0),
            prefix + 'tv-display-schema.json': b'{}', prefix + 'ThirdPartyNotices.txt': b'Synthetic test only',
        }
        items.update(extra or {})
        with zipfile.ZipFile(path, 'w') as archive:
            for name, data in items.items():
                archive.writestr(name, data)

    def test_structural_synthetic_fixture(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / 'fixture.zip'
            self.package(path)
            self.assertTrue(validator.validate(path))

    def test_rejects_provisioning_and_traversal(self):
        for name in ('Payload/GameLingo.app/embedded.mobileprovision', 'Payload/../evil'):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as tmp:
                path = pathlib.Path(tmp) / 'fixture.zip'
                self.package(path, {name: b'bad'})
                with self.assertRaises(ValueError):
                    validator.validate(path)

    def test_rejects_simulator_and_signed_executables(self):
        for binary in (struct.pack('<IIIIIIII', 0xfeedfacf, 0x01000007, 0, 2, 0, 0, 0, 0), struct.pack('<IIIIIIIIII', 0xfeedfacf, 0x0100000C, 0, 2, 1, 8, 0, 0, 0x1D, 8)):
            with tempfile.TemporaryDirectory() as tmp:
                path = pathlib.Path(tmp) / 'fixture.zip'
                self.package(path, executable=binary)
                with self.assertRaises(ValueError):
                    validator.validate(path)


if __name__ == '__main__':
    unittest.main(verbosity=2)

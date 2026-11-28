#!/usr/bin/env python3
import pathlib
import plistlib
import struct
import sys
import zipfile


def png_dimensions(data):
    if not data.startswith(b'\x89PNG\r\n\x1a\n'):
        return None
    offset = 8
    # Apple's optimized PNG may put a CgBI chunk before IHDR.
    for _ in range(2):
        if offset + 12 > len(data):
            return None
        size, kind = struct.unpack_from('>I4s', data, offset)
        if offset + size + 12 > len(data):
            return None
        if kind == b'IHDR' and size == 13:
            return struct.unpack_from('>II', data, offset + 8)
        if kind != b'CgBI':
            return None
        offset += size + 12
    return None


def validate(path):
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise ValueError('Corrupted IPA ZIP')
        names = archive.namelist()
        prefix = 'Payload/GameLingo.app/'
        if any(not name.startswith('Payload/') or '..' in pathlib.PurePosixPath(name).parts for name in names):
            raise ValueError('Unexpected IPA path')
        required = [prefix + file for file in ('Info.plist', 'GameLingo', 'tv-display-schema.json', 'ThirdPartyNotices.txt', 'PrivacyInfo.xcprivacy')]
        if any(file not in names for file in required):
            raise ValueError('Missing executable or required resource')
        if any(name.endswith(('.p12', '.pfx', '.pem', '.key', '.mobileprovision')) or '/_CodeSignature/' in name for name in names):
            raise ValueError('Signing material must not be packaged in unsigned IPA')
        if any(name.endswith(('.argosmodel', '/model.bin', '.gguf', '.npz', '.safetensors', '.glpack', '.sqlite', '.gxt2', '.jsonl')) for name in names):
            raise ValueError('Test-only model weights must not be included in release IPA')
        info = plistlib.loads(archive.read(prefix + 'Info.plist'))
        if info.get('CFBundleExecutable') != 'GameLingo' or info.get('CFBundleIdentifier') != 'dev.gamelingo.ios':
            raise ValueError('Unexpected app identity')
        if info.get('CFBundlePackageType') != 'APPL':
            raise ValueError('Invalid application bundle')
        primary = info.get('CFBundleIcons', {}).get('CFBundlePrimaryIcon', {})
        icons = primary.get('CFBundleIconFiles', [])
        if primary.get('CFBundleIconName') != 'AppIcon' or not icons or prefix+'Assets.car' not in names:
            raise ValueError('Missing compiled app-icon metadata/catalog')
        phone_icons = [prefix + stem + '@3x.png' for stem in icons]
        if not any(n in names and png_dimensions(archive.read(n)) == (180, 180) for n in phone_icons):
            raise ValueError('Missing explicit 60pt @3x iPhone app icon')
        control = prefix+'PlugIns/GameLingoControls.appex/'
        if control+'Info.plist' not in names or control+'GameLingoControls' not in names:
            raise ValueError('Missing embedded control extension')
        extension = plistlib.loads(archive.read(control+'Info.plist'))
        if extension.get('CFBundleVersion') != info.get('CFBundleVersion') or extension.get('NSExtension', {}).get('NSExtensionPointIdentifier') != 'com.apple.widgetkit-extension':
            raise ValueError('Mismatched control build or extension point')
        executable = archive.read(prefix + 'GameLingo')
        # Archive targets a physical arm64 iPhone: require a 64-bit little-endian Mach-O.
        if len(executable) < 32 or executable[:4] != b'\xcf\xfa\xed\xfe' or struct.unpack_from('<I', executable, 4)[0] != 0x0100000C:
            raise ValueError('Executable is not an arm64 iPhone Mach-O')
        file_type, commands, commands_size = struct.unpack_from('<III', executable, 12)
        if file_type != 2:
            raise ValueError('Mach-O is not an executable')
        offset = 32
        ios_platform = False
        if offset + commands_size > len(executable):
            raise ValueError('Truncated Mach-O commands')
        for _ in range(commands):
            command, size = struct.unpack_from('<II', executable, offset)
            if size < 8 or offset + size > len(executable):
                raise ValueError('Invalid Mach-O command')
            if command == 0x1D:
                raise ValueError('Unexpected embedded code signature')
            if command == 0x32:
                if size < 24 or struct.unpack_from('<I', executable, offset + 8)[0] != 2:
                    raise ValueError('Mach-O build platform is not a physical iPhone')
                ios_platform = True
            if command == 0x25:
                ios_platform = True
            offset += size
        if not ios_platform:
            raise ValueError('Missing iPhone platform load command')
    return True


if __name__ == '__main__':
    validate(pathlib.Path(sys.argv[1]))
    print('Validated unsigned arm64 IPA structure and resources')

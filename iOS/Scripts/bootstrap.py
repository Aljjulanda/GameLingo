#!/usr/bin/env python3
"""Fetch immutable sources and apply explicit, reviewable iOS build adjustments."""
import argparse
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCES = ROOT / '.build' / 'sources'
LOCK = {
    'pylux': ('https://github.com/ForWard-Technologies-LLC/Pylux.git', 'ca87a49a12bab071948f565ca53ffdad790775d3'),
    'ctranslate2': ('https://github.com/OpenNMT/CTranslate2.git', '617405f4b050e994e829d527da6caa0e0030afe7'),
    'sentencepiece': ('https://github.com/google/sentencepiece.git', '31646a467d2051eb904e0b45de3a73e91fe1c1e3'),
    'openssl': ('https://github.com/openssl/openssl.git', '45e844fa2a14ec92d146bd8f5778ac130b6625fb'),
}


def run(*args, cwd=None):
    subprocess.run(args, cwd=cwd, check=True)


def fetch(name, url, commit):
    destination = SOURCES / name
    if not (destination / '.git').exists():
        destination.mkdir(parents=True, exist_ok=True)
        run('git', 'init', str(destination))
        run('git', 'remote', 'add', 'origin', url, cwd=destination)
    actual_url = subprocess.check_output(['git', 'remote', 'get-url', 'origin'], cwd=destination, text=True).strip()
    if actual_url != url:
        raise RuntimeError(f'Unexpected dependency remote for {name}')
    head = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=destination, text=True, capture_output=True)
    if head.returncode or head.stdout.strip() != commit:
        run('git', 'fetch', '--depth', '1', 'origin', commit, cwd=destination)
        run('git', 'checkout', '--detach', commit, cwd=destination)
    if name == 'pylux':
        run('git', 'submodule', 'update', '--init', '--depth', '1', '--',
            'third-party/nanopb', 'third-party/jerasure', 'third-party/gf-complete', 'third-party/curl', cwd=destination)
    elif name == 'ctranslate2':
        run('git', 'submodule', 'update', '--init', '--recursive', '--depth', '1', '--',
            'third_party/spdlog', 'third_party/cpu_features', 'third_party/ruy', cwd=destination)
    return destination


def replace_exact(text, before, after):
    if text.count(before) != 1:
        raise RuntimeError(f'Pinned dependency patch no longer applies: {before[:80]}')
    return text.replace(before, after, 1)


def patch_pylux(path):
    # Always derive from the pinned Git object, never from previously patched contents.
    text = subprocess.check_output(['git', 'show', 'HEAD:CMakeLists.txt'], cwd=path, text=True)
    text = replace_exact(text, '\tset(CHIAKI_LIB_ENABLE_MBEDTLS ON CACHE BOOL "" FORCE)', '\tset(CHIAKI_LIB_ENABLE_MBEDTLS OFF CACHE BOOL "" FORCE)')
    text = replace_exact(text, '\tset(CHIAKI_LIB_MBEDTLS_EXTERNAL_PROJECT ON CACHE BOOL "" FORCE)', '\tset(CHIAKI_LIB_MBEDTLS_EXTERNAL_PROJECT OFF CACHE BOOL "" FORCE)')
    text = replace_exact(text, 'if(APPLE)\n', 'if(APPLE AND NOT IOS)\n')
    text = text.replace('iOS build: lib only, mbedTLS, RUDP enabled', 'iOS build: lib only, external OpenSSL, RUDP enabled')
    text = replace_exact(text, 'add_subdirectory(lib)', 'add_subdirectory(lib)\ntarget_sources(chiaki-lib PRIVATE "${GAMELINGO_BRIDGE}")')
    (path / 'CMakeLists.txt').write_text(text, encoding='utf-8', newline='\n')
    third_party = subprocess.check_output(['git', 'show', 'HEAD:third-party/CMakeLists.txt'], cwd=path, text=True)
    third_party = replace_exact(third_party, 'GIT_TAG json-c-0.17-20230812', 'GIT_TAG b4c371fa0cbc4dcbaccc359ce9e957a22988fb34')
    third_party = replace_exact(third_party, 'GIT_TAG miniupnpc_2_2_8', 'GIT_TAG b55145ec095652289a59c33603f3abafee898273')
    # FetchContent cannot shallow-clone an arbitrary pinned SHA reliably.
    third_party = third_party.replace('GIT_SHALLOW TRUE', 'GIT_SHALLOW FALSE')
    third_party = replace_exact(third_party, '\t# Configure opus build options before fetching', '\tif(CHIAKI_LIB_ENABLE_OPUS)\n\t# Configure opus build options before fetching')
    third_party = replace_exact(third_party, '\tadd_library(Opus::opus ALIAS opus)', '\tadd_library(Opus::opus ALIAS opus)\n\tendif()')
    (path / 'third-party/CMakeLists.txt').write_text(third_party, encoding='utf-8', newline='\n')
    for name in ('audioreceiver.c', 'audiosender.c'):
        source = subprocess.check_output(['git', 'show', f'HEAD:lib/src/{name}'], cwd=path, text=True)
        source = replace_exact(source, '#ifdef CHIAKI_LIB_ENABLE_OPUS', '#if CHIAKI_LIB_ENABLE_OPUS')
        (path / 'lib' / 'src' / name).write_text(source, encoding='utf-8', newline='\n')


def patch_ct2(path):
    text = subprocess.check_output(['git', 'show', 'HEAD:CMakeLists.txt'], cwd=path, text=True)
    text = replace_exact(text, 'if(APPLE)\n  set(CMAKE_OSX_DEPLOYMENT_TARGET 10.13)', 'if(APPLE AND NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")\n  set(CMAKE_OSX_DEPLOYMENT_TARGET 10.13)')
    (path / 'CMakeLists.txt').write_text(text, encoding='utf-8', newline='\n')


def patch_sentencepiece(path):
    text = subprocess.check_output(['git', 'show', 'HEAD:src/CMakeLists.txt'], cwd=path, text=True)
    text = replace_exact(text, 'if (CMAKE_SYSTEM_NAME STREQUAL "iOS")\n  set_xcode_property',
                         'if (CMAKE_SYSTEM_NAME STREQUAL "iOS" AND COMMAND set_xcode_property)\n  set_xcode_property')
    (path / 'src/CMakeLists.txt').write_text(text, encoding='utf-8', newline='\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--patch-only', action='store_true')
    args = parser.parse_args()
    if not args.patch_only:
        for name, (url, commit) in LOCK.items():
            fetch(name, url, commit)
    patch_pylux(SOURCES / 'pylux')
    patch_ct2(SOURCES / 'ctranslate2')
    patch_sentencepiece(SOURCES / 'sentencepiece')
    manifest = {name: {'url': url, 'commit': commit} for name, (url, commit) in LOCK.items()}
    manifest['json-c'] = {'url': 'https://github.com/json-c/json-c.git', 'commit': 'b4c371fa0cbc4dcbaccc359ce9e957a22988fb34'}
    manifest['miniupnpc'] = {'url': 'https://github.com/miniupnp/miniupnp.git', 'commit': 'b55145ec095652289a59c33603f3abafee898273'}
    (ROOT / '.build' / 'dependency-sources.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()

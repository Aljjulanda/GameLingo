#!/usr/bin/env python3
"""Exercise the real shell runner with stub tools, NOT Apple/model validation."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

IOS = Path(__file__).resolve().parents[1]


class TestOrchestration(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='gamelingo-runner-')
        self.root = Path(self.temporary.name).resolve()
        assert self.root.parent == Path(tempfile.gettempdir()).resolve()
        assert self.root.name.startswith('gamelingo-runner-')
        self.addCleanup(self.temporary.cleanup)
        self.bin = self.root / 'bin'
        for folder in (self.bin, self.root / 'Scripts', self.root / 'Integration', self.root / '.build/python/bin'):
            folder.mkdir(parents=True)
        (self.root / 'Scripts/test.sh').write_bytes((IOS / 'Scripts/test.sh').read_bytes().replace(b'\r\n', b'\n'))
        (self.root / '.build/python/bin/activate').write_text('')
        (self.root / 'Scripts/build-native.sh').write_text('exit 0\n', newline='\n')
        self.tool('curl', 'exit 0')
        self.tool('xcrun', 'exit 0')
        self.tool('python3', 'if [[ "$1" == Integration/okhttp-bridge.py ]]; then exec sleep 30; fi\nexit 0')
        self.tool('xcodebuild', '''printf '%s\\0' "$@" >> "$TRACE"
printf '\\0' >> "$TRACE"
if [[ "$1" == test-without-building ]]; then
  if [[ "$MODE" == failure ]]; then exit 65; fi
  mkdir -p build/GameLingoTests.xcresult
  if [[ "$MODE" != empty ]]; then echo 'Executed 2 tests, with 0 failures'; fi
fi
exit 0''')
        if os.name == 'nt':
            self.bash = str(Path(shutil.which('git')).parent.parent / 'bin/bash.exe')
        else:
            self.bash = shutil.which('bash')
        self.assertTrue(self.bash and Path(self.bash).exists(), 'Bash is required for orchestration tests')

    def tool(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/bash\n' + body + '\n', encoding='utf-8', newline='\n')
        path.chmod(0o755)

    def run_script(self, mode='success', filters=''):
        env = os.environ.copy()
        env.pop('BASH_ENV', None)
        env.update(PATH=str(self.bin)+os.pathsep+env['PATH'], MODE=mode, TRACE=(self.root/'trace').as_posix(),
                   SKIP_CORE_TESTS='1', IOS_TEST_DESTINATION='platform=iOS Simulator,id=synthetic', IOS_TEST_FILTERS=filters)
        # Git Bash translates Windows PATH at startup; prefix inside the shell so
        # fake tools win on Windows as well as on the CI runner.
        result = subprocess.run([self.bash, '-c', 'export PATH="$PWD/bin:$PATH"; exec /bin/bash Scripts/test.sh'], cwd=self.root, env=env,
                                capture_output=True, text=True, timeout=25)
        trace = self.root/'trace'
        calls = [block.decode().split('\0') for block in trace.read_bytes().split(b'\0\0') if block] if trace.exists() else []
        return result, calls

    def test_unfiltered_route_invokes_all_tests(self):
        result, calls = self.run_script()
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        run = next(call for call in calls if call[0] == 'test-without-building')
        self.assertIn('-resultBundlePath', run)
        self.assertFalse(any(arg.startswith('-only-testing:') for arg in run))

    def test_zero_exit_without_executed_tests_is_a_failure(self):
        result, _ = self.run_script(mode='empty')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('No native XCTest cases executed', result.stdout+result.stderr)

    def test_actual_test_failure_cannot_be_hidden_by_tee_or_cleanup(self):
        result, _ = self.run_script(mode='failure')
        self.assertNotEqual(result.returncode, 0)

    def test_filters_are_forwarded_and_malformed_identifiers_rejected(self):
        filters = 'GameLingoTests/NamesIntegrationTests\nGameLingoTests/AppleIntegrationTests/testVisionDialogue'
        result, calls = self.run_script(filters=filters)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        run = next(call for call in calls if call[0] == 'test-without-building')
        self.assertEqual([arg for arg in run if arg.startswith('-only-testing:')],
                         ['-only-testing:'+value for value in filters.splitlines()])
        (self.root/'trace').unlink()
        result, calls = self.run_script(filters='OtherTarget/NotAllowed')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[0] == 'test-without-building' for call in calls))


if __name__ == '__main__':
    unittest.main()

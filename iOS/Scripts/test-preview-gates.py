#!/usr/bin/env python3
"""Test release-gate rejection behavior with synthetic logs, never runtime evidence."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('preview', Path(__file__).with_name('preview-tests.py'))
preview = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview)


class PreviewGateTests(unittest.TestCase):
    def setUp(self):
        self.value = preview.manifest()

    def log(self, outcomes=None):
        outcomes = outcomes or {}
        return '\n'.join("Test Case '-[GameLingoTests.%s %s]' %s (0.1 seconds)." %
                         (identifier.split('/')[1], identifier.split('/')[2], outcomes.get(identifier, 'passed'))
                         for identifier in self.value['selected'])

    def test_complete_results_and_explicit_hardware_skips(self):
        result = preview.verify(self.log({k: 'skipped' for k in self.value['allowed_skips']}), self.value)
        self.assertEqual(len(result['skipped']), 2)
        self.assertEqual(result['passed'], len(self.value['selected']) - 2)

    def test_missing_failure_retry_and_unapproved_skip_are_rejected(self):
        identifier = self.value['selected'][0]
        cases = [self.log().split('\n', 1)[1], self.log({identifier: 'failed'}),
                 self.log({identifier: 'skipped'}), self.log() + '\n' + self.log().splitlines()[0]]
        for log in cases:
            with self.subTest(log=log[:80]), self.assertRaises(AssertionError):
                preview.verify(log, self.value)

    def test_crash_or_failed_session_cannot_be_hidden_by_later_passes(self):
        for marker in ['Restarting after unexpected exit, crash, or test timeout', '** TEST EXECUTE FAILED **']:
            with self.subTest(marker=marker), self.assertRaises(AssertionError):
                preview.verify(marker+'\n'+self.log(), self.value)

    def test_production_has_no_typewriter_integration(self):
        for name in ['VideoProcessing/FramePipeline.swift', 'App/AppModel.swift']:
            source = (preview.IOS / 'GameLingo' / name).read_text(encoding='utf-8')
            # Only these two integration files use this simple research conditional.
            active, stack, result = True, [], []
            for line in source.splitlines():
                stripped = line.strip()
                if stripped == '#if GAMELINGO_TYPEWRITER_RESEARCH':
                    stack.append(active)
                    active = False
                elif stack and stripped == '#else':
                    active = stack[-1]
                elif stack and stripped == '#endif':
                    active = stack.pop()
                elif active:
                    result.append(line)
            self.assertFalse(stack)
            text = '\n'.join(result)
            for token in ['TypewriterPublication', '.typewriter', 'heldPublication', 'onTypewriterDetected']:
                self.assertNotIn(token, text)
        ui = (preview.IOS / 'GameLingo/Views/QualitySettingsView.swift').read_text(encoding='utf-8')
        self.assertNotIn('.typewriter', ui)


if __name__ == '__main__':
    unittest.main()

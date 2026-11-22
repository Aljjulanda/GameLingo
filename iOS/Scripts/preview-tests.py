#!/usr/bin/env python3
"""Explicit approved preview selection; never treat missing/deferred cases as pass."""
import json
from pathlib import Path
import re
import sys

IOS = Path(__file__).resolve().parents[1]


def manifest():
    value = json.loads((IOS / 'Scripts/preview-tests.json').read_text())
    selected = value['selected']
    assert selected and len(selected) == len(set(selected))
    assert not set(selected) & set(value['deferred'])
    assert set(value['allowed_skips']) <= set(selected)
    assert set(value.get('isolated', [])) <= set(selected)
    assert len(value.get('isolated', [])) == len(set(value.get('isolated', [])))
    for identifier in selected + value['deferred']:
        target, cls, method = identifier.split('/')
        assert target == 'GameLingoTests'
        source = (IOS / 'GameLingoTests' / (cls + '.swift')).read_text(encoding='utf-8')
        assert re.search(r'func\s+' + re.escape(method) + r'\(', source), identifier
    # No build configuration enables deferred production integration.
    project = (IOS / 'GameLingo.xcodeproj/project.pbxproj').read_text()
    assert 'GAMELINGO_TYPEWRITER_RESEARCH' not in project
    return value


def verify(log, value):
    assert 'Restarting after unexpected exit' not in log, 'Unexpected test process restart'
    assert '** TEST EXECUTE FAILED **' not in log, 'Failed native test session'
    outcomes = {}
    for cls, method, outcome in re.findall(
        r"Test Case '-\[GameLingoTests\.([A-Za-z0-9_]+) ([A-Za-z0-9_]+)\]' (passed|failed|skipped)", log
    ):
        identifier = 'GameLingoTests/' + cls + '/' + method
        assert identifier not in outcomes, 'Unexpected retry: ' + identifier
        outcomes[identifier] = outcome
    assert set(outcomes) == set(value['selected']), 'Missing/unexpected preview outcomes: ' + str(set(outcomes) ^ set(value['selected']))
    for identifier, outcome in outcomes.items():
        assert outcome == 'passed' or (outcome == 'skipped' and identifier in value['allowed_skips']), identifier + ': ' + outcome
    result = dict(profile=value['profile'], selected=len(outcomes), passed=sum(x == 'passed' for x in outcomes.values()),
                  skipped=[k for k, v in outcomes.items() if v == 'skipped'], deferred=value['deferred'],
                  files_ui='deferred to physical iPhone', typewriter='excluded from production', outcomes=outcomes)
    return result


if __name__ == '__main__':
    value = manifest()
    if sys.argv[1] == 'filters':
        print('\n'.join(value['selected']))
    elif sys.argv[1] == 'isolated':
        print('\n'.join(value.get('isolated', [])))
    elif sys.argv[1] == 'verify':
        path = Path(sys.argv[2])
        result = verify(path.read_text(), value)
        path.with_name('preview-acceptance.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result))
    else:
        raise ValueError('Expected filters or verify')

#!/usr/bin/env bash
# verify.sh [branch] — run every lane against the running SUT and assert the finding this
# branch is expected to produce (expected.json). Exit 1 on any mismatch.
set -euo pipefail
cd "$(dirname "$0")"
BR="${1:-$(git rev-parse --abbrev-ref HEAD)}"

DECK="$(./drive.sh)"
CONTRACT="$(./contract.sh)"
LIVE="$(./live.sh)"
WALK="$(./walk.sh)"

DECK="$DECK" CONTRACT="$CONTRACT" LIVE="$LIVE" WALK="$WALK" BR="$BR" python3 - <<'PY'
import json, os, sys

def payload(name):
    return json.loads(os.environ[name])['payload']

deck, contract, live, walk = (payload(n) for n in ('DECK', 'CONTRACT', 'LIVE', 'WALK'))
br = os.environ['BR']
want = json.load(open('expected.json'))
if br not in want:
    sys.exit('no expectation for branch ' + br)
want = want[br]

got = {
    'deckRows': deck['rows'],
    'deckDiverged': deck['diverged'],
    'deckReasonOnly': deck['reasonOnly'],
    'contractProbes': contract['probes'],
    'contractViolations': contract['violations'],
    'livePass': live['summary']['PASS'],
    'liveFail': live['summary']['FAIL'],
    'liveFailing': sorted(s['id'] for s in live['sequences'] if s['kind'] == 'FAIL'),
    'walkStates': walk['states'],
    'walkTransitions': walk['transitions'],
    'walkRefusals': walk['refusals'],
    'walkInvariantsFailed': walk['invariants']['failed'],
}
shrink = {s['id']: s['shrink'] for s in live['sequences'] if s.get('shrink')}
if 'shrinkSteps' in want:
    seq = want['liveFailing'][0]
    got['shrinkSteps'] = len(shrink[seq]['steps'])
    got['shrinkVerified'] = shrink[seq]['verified']

bad = {k: (v, got.get(k)) for k, v in want.items() if got.get(k) != v}
width = max(len(k) for k in got)
for k in got:
    flag = '  <-- expected %r' % (want[k],) if k in bad else ''
    print('%-*s  %s%s' % (width, k, got[k], flag))
if bad:
    sys.exit('\n%s: %d expectation(s) not met' % (br, len(bad)))
print('\n%s: every expectation met' % br)
PY

#!/usr/bin/env bash
# verify.sh [branch] [live|mock] — run every lane against the running system and assert the
# finding this branch is expected to produce (expected.json). Exit 1 on any mismatch.
set -euo pipefail
cd "$(dirname "$0")"
BR="${1:-$(git rev-parse --abbrev-ref HEAD)}"
AGAINST="${2:-live}"

DECK="$(./drive.sh)"
CONTRACT="$(./contract.sh)"
LIVE="$(./live.sh "$AGAINST")"
WALK="$(./walk.sh)"

DECK="$DECK" CONTRACT="$CONTRACT" LIVE="$LIVE" WALK="$WALK" BR="$BR" python3 - <<'PY'
import json, os, sys

deck, contract, live, walk = (json.loads(os.environ[n]) for n in ('DECK', 'CONTRACT', 'LIVE', 'WALK'))
br = os.environ['BR']
want = json.load(open('expected.json'))
if br not in want:
    sys.exit('no expectation for branch ' + br)
want = want[br]

got = {
    'deckRows': deck['rows'],
    'deckDiverged': deck['diverged'],
    'deckReasonOnly': deck['reasonOnly'],
    'deckSetupFailed': deck['setupFailed'],
    'deckAccounted': deck['agreed'] + deck['diverged'] == deck['rows'],
    'deckOutOfDomain': deck['outOfDomain'],
    'deckDomainAxes': deck['domainAxes'],
    'contractProbes': contract['probes'],
    'contractViolations': contract['violations'],
    'livePass': live['summary']['PASS'],
    'liveFail': live['summary']['FAIL'],
    'liveFailing': sorted(s['id'] for s in live['sequences'] if s['kind'] == 'FAIL'),
    'walkStates': walk['states'],
    'walkTransitions': walk['transitions'],
    'walkRefusals': walk['refusals'],
    'walkInvariantsFailed': walk['invariants']['failed'],
    'walkCeiling': walk['ceiling'],
    'walkFrontier': walk['frontier'],
    'walkCounterexamples': walk['counterexamples'],
    'walkTransitionPairs': walk['transitionPairs'],
    'walkTransitionPairGaps': walk['transitionPairGaps'],
}
shrink = {s['id']: s['shrink'] for s in live['sequences'] if s.get('shrink')}
if 'shrinkSteps' in want:
    seq = want['liveFailing'][0]
    got['shrinkSteps'] = len(shrink[seq]['steps'])
    got['shrinkVerified'] = shrink[seq]['verified']

# the jqwik* keys are jqwik-check.sh's expectations, not a lane's
bad = {k: v for k, v in want.items() if not k.startswith('jqwik') and got.get(k) != v}
width = max(len(k) for k in got)
for k in got:
    flag = '  <-- expected %r' % (want[k],) if k in bad else ''
    print('%-*s  %s%s' % (width, k, got[k], flag))
if bad:
    sys.exit('\n%s: %d expectation(s) not met' % (br, len(bad)))
print('\n%s: every expectation met' % br)
PY

#!/usr/bin/env bash
# verify.sh [branch] [live|mock] — run every lane against the running system and assert the
# finding this branch is expected to produce (expected.json). Exit 1 on any mismatch.
set -euo pipefail
cd "$(dirname "$0")"
BR="${1:-$(git rev-parse --abbrev-ref HEAD)}"
AGAINST="${2:-live}"

# Which jar produced these numbers. Never an asserted key — the sha changes with every build —
# but printed beside them, so numbers that disagree with expected.json have somewhere to look.
ENGINE="$(./engine.sh 2>&1 >/dev/null | sed -n 's/^engine: //p' | tail -1 || true)"

DECK="$(./drive.sh)"
CONTRACT="$(./contract.sh)"
LIVE="$(./live.sh "$AGAINST")"
WALK="$(./walk.sh)"
MUTATE="$(./mutate.sh)"

DECK="$DECK" CONTRACT="$CONTRACT" LIVE="$LIVE" WALK="$WALK" MUTATE="$MUTATE" BR="$BR" \
ENGINE="$ENGINE" python3 - <<'PY'
import json, os, sys

deck, contract, live, walk, mutate = (json.loads(os.environ[n])
                                      for n in ('DECK', 'CONTRACT', 'LIVE', 'WALK', 'MUTATE'))
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
    'mutateCatalog': mutate['catalog'],
    'mutateGraded': mutate['graded'],
    'mutateExcluded': mutate['excluded'],
    'mutateNotRun': mutate['notRun'],
    'mutateTimeouts': mutate['timeouts'],
    'mutateSequences': mutate['sequences'],
    'mutateCheckedByAny': mutate['checkedByAny'],
    'mutateKilledByAny': mutate['killedByAny'],
    'mutateWorklist': mutate['worklist'],
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
print('%-*s  %s' % (width, 'engine', os.environ.get('ENGINE') or 'unresolved'))
if bad:
    sys.exit('\n%s: %d expectation(s) not met' % (br, len(bad)))
print('\n%s: every expectation met' % br)
PY

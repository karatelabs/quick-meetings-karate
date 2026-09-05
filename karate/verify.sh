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
WITNESS="$(./witness.sh "$AGAINST")"
MUTATE="$(./mutate.sh)"

DECK="$DECK" CONTRACT="$CONTRACT" LIVE="$LIVE" WALK="$WALK" WITNESS="$WITNESS" MUTATE="$MUTATE" \
BR="$BR" ENGINE="$ENGINE" python3 - <<'PY'
import json, os, sys

deck, contract, live, walk, witness, mutate = (json.loads(os.environ[n])
                                               for n in ('DECK', 'CONTRACT', 'LIVE', 'WALK',
                                                         'WITNESS', 'MUTATE'))
br = os.environ['BR']
want = json.load(open('expected.json'))
if br not in want:
    sys.exit('no expectation for branch ' + br)
want = want[br]

# a witness population reads as witnessed-of-owed; refuted and blocked are summed across the three,
# so a single asserted number says whether any obligation went ungraded
POPULATIONS = ('transitions', 'pairs', 'refusals')
def fold(p):
    return '%s/%s' % (p['witnessed'], p['of'])

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
    'witnessTransitions': fold(witness['transitions']),
    'witnessPairs': fold(witness['pairs']),
    'witnessRefusals': fold(witness['refusals']),
    'witnessRefuted': sum(witness[p]['refuted'] for p in POPULATIONS),
    'witnessBlocked': sum(witness[p]['blocked'] for p in POPULATIONS),
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
# a witness number only says how many; the obligations behind it say which, and this is the only
# place they reach the log
for o in witness['notWitnessed'][:10]:
    print('%-*s  %s %s %s' % (width, 'witness ' + o['credit'], o['kind'], o['key'], o['why']))
if len(witness['notWitnessed']) > 10:
    print('%-*s  %d more' % (width, 'witness', len(witness['notWitnessed']) - 10))
if bad:
    sys.exit('\n%s: %d expectation(s) not met' % (br, len(bad)))
print('\n%s: every expectation met' % br)
PY

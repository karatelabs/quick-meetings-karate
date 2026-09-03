#!/usr/bin/env bash
# jqwik-check.sh [branch] — run the author's own detection and assert its shape.
#
# On main the whole suite must pass. On a defect branch ./tests-being-demoed.sh must FALSIFY the
# property expected.json names for that branch — a non-zero exit is not proof on its own, so the
# surefire XML is read: that property must carry a <failure> or an <error>, and no OTHER testcase
# may carry either. A run that ends any other way (no report, a compile break, the wrong test) is
# reported here as what it actually was.
set -euo pipefail
cd "$(dirname "$0")/.."
BR="${1:-$(git rev-parse --abbrev-ref HEAD)}"
mkdir -p karate/target

if [ "$BR" = main ]; then
  mvn -q clean test
  echo "main: the whole jqwik suite passes"
  exit 0
fi

./tests-being-demoed.sh > karate/target/jqwik.log 2>&1 && RC=0 || RC=$?

BR="$BR" RC="$RC" python3 - <<'PY'
import glob, json, os, sys, xml.etree.ElementTree as ET

br, rc = os.environ['BR'], os.environ['RC']
want = json.load(open('karate/expected.json'))[br]['jqwikProperty']
cls, method = want.split('#')

files = glob.glob('target/surefire-reports/*.xml')
if not files:
    sys.exit('%s: tests-being-demoed.sh exited %s and wrote no surefire report — the run never '
             'reached %s (see karate/target/jqwik.log)' % (br, rc, want))

cases = []
for f in files:
    for tc in ET.parse(f).getroot().iter('testcase'):
        kind = next((c.tag for c in tc if c.tag in ('failure', 'error', 'skipped')), 'passed')
        cases.append((tc.get('classname'), tc.get('name'), kind))

seen = ', '.join('%s#%s(%s)' % c for c in cases) or 'nothing'
target = [c for c in cases if c[0] == cls and c[1] == method]
others = [c for c in cases if (c[0], c[1]) != (cls, method) and c[2] in ('failure', 'error')]

if not target:
    sys.exit('%s: %s did not run — surefire reported %s' % (br, want, seen))
if target[0][2] not in ('failure', 'error'):
    sys.exit('%s: %s reported %s — the seeded defect no longer falsifies it'
             % (br, want, target[0][2]))
if others:
    sys.exit('%s: %s falsified, but %s also broke — that is not a clean single detection'
             % (br, want, ', '.join('%s#%s(%s)' % c for c in others)))

print('%s: %s falsified (<%s>), nothing else broke' % (br, want, target[0][2]))
PY

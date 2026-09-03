#!/usr/bin/env bash
# jqwik-check.sh [branch] — run the author's own detection and assert its shape.
#
# On main the whole suite must pass. On a defect branch ./tests-being-demoed.sh must FALSIFY the
# property expected.json names for that branch. An exit code is not proof, and neither is any red
# testcase, so the surefire XML is read: the named property must carry a <failure> — or, where
# expected.json declares jqwikErrorType, an <error> of exactly that type — no other testcase may be
# red, and maven must have exited non-zero. A run that ends any other way (a stopped database, a
# compile break, the wrong test) is reported here as what it actually was.
#
# The parse is exercised against real reports: see REPORTS below.
#   REPORTS=<dir> ./jqwik-check.sh <branch>   grade that saved surefire dir instead of running maven
set -euo pipefail
cd "$(dirname "$0")/.."
BR="${1:-$(git rev-parse --abbrev-ref HEAD)}"
mkdir -p karate/target

if [ "$BR" = main ]; then
  mvn -q clean test
  echo "main: the whole jqwik suite passes"
  exit 0
fi

if [ -n "${REPORTS:-}" ]; then
  DIR="$REPORTS"; RC="${REPORTS_RC:-1}"
else
  DIR=target/surefire-reports
  ./tests-being-demoed.sh > karate/target/jqwik.log 2>&1 && RC=0 || RC=$?
fi

BR="$BR" RC="$RC" DIR="$DIR" python3 - <<'PY'
import glob, json, os, sys, xml.etree.ElementTree as ET

def die(msg):
    print('::error title=the author\'s detection did not have the expected shape::' + msg)
    sys.exit(1)

br, rc, d = os.environ['BR'], os.environ['RC'], os.environ['DIR']
want = json.load(open('karate/expected.json'))[br]
cls, method = want['jqwikProperty'].split('#')
want_error = want.get('jqwikErrorType')
named = want['jqwikProperty']

if rc == '0':
    die('%s: tests-being-demoed.sh exited 0 on %s — the seeded defect did not falsify anything'
        % (br, br))

files = glob.glob(os.path.join(d, '*.xml'))
if not files:
    die('%s: tests-being-demoed.sh exited %s and wrote no surefire report — the run never reached '
        '%s (see karate/target/jqwik.log)' % (br, rc, named))

cases = []
for f in files:
    for tc in ET.parse(f).getroot().iter('testcase'):
        red = next((c for c in tc if c.tag in ('failure', 'error')), None)
        kind = red.tag if red is not None else \
            ('skipped' if any(c.tag == 'skipped' for c in tc) else 'passed')
        etype = red.get('type') if red is not None else None
        cases.append((tc.get('classname'), tc.get('name'), kind, etype))

def label(c):
    return '%s#%s(%s%s)' % (c[0], c[1], c[2], ' ' + c[3] if c[3] else '')

target = [c for c in cases if (c[0], c[1]) == (cls, method)]
others = [c for c in cases if (c[0], c[1]) != (cls, method) and c[2] in ('failure', 'error')]

if not target:
    die('%s: %s did not run — surefire reported %s'
        % (br, named, ', '.join(label(c) for c in cases) or 'nothing'))
kind, etype = target[0][2], target[0][3]
if kind == 'error':
    if not want_error:
        die('%s: %s errored with %s — this branch expects a falsified property, not an exception'
            % (br, named, etype))
    if etype != want_error:
        die('%s: %s errored with %s, not the expected %s' % (br, named, etype, want_error))
elif kind != 'failure':
    die('%s: %s reported %s — the seeded defect no longer falsifies it' % (br, named, kind))
if others:
    die('%s: %s was red as expected, but so was %s — that is not a clean single detection'
        % (br, named, ', '.join(label(c) for c in others)))

print('%s: %s falsified (<%s>%s), nothing else broke'
      % (br, named, kind, ' ' + etype if etype else ''))
PY

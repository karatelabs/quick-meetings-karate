#!/usr/bin/env bash
# witness.sh [live|mock] — replay the walk's own witnesses against the running system. The walk's
# numbers are statements about the model; these say which of them the system confirmed. One
# sequence per obligation — every landed transition, every transition pair the pinned deck leaves
# uncovered, every refusal class — each with its own reset, so the denominators are the walk's own.
# A scope guard rides scope[] and owes no witness: no request can put the system in the world it
# rejects.
set -euo pipefail
cd "$(dirname "$0")"
AGAINST="${1:-live}"
case "$AGAINST" in
  live) RESET=./reset-sut.sh ;;
  mock) RESET=./reset-mock.sh ;;
  *) echo "usage: ./witness.sh [live|mock]" >&2; exit 2 ;;
esac
# thousands of sequences in one call, past ka.sh's own default
export KA_TIMEOUT="${KA_TIMEOUT:-3600}"
./ka.sh "
var r = Twin.witness('meetings', {baseUrl: '${QM_URL:-http://localhost:9981}', against: '$AGAINST',
                                  reset: {command: ['$RESET']}, timeoutMs: 10000});
({transitions: r.transitions, pairs: r.pairs,
  refusals: {witnessed: r.refusals.witnessed, compatible: r.refusals.compatible,
             missed: r.refusals.missed, refuted: r.refusals.refuted, blocked: r.refusals.blocked,
             of: r.refusals.of, scope: r.refusals.scope},
  capturedCollapsed: r.capturedCollapsed, selection: r.selection,
  notWitnessed: r.obligations.filter(function (o) { return o.credit !== 'witnessed'; })
    .map(function (o) {
      return {credit: o.credit, kind: o.kind, key: o.key, steps: o.steps,
              why: o.reason ? o.reason : o.mismatch};
    })})"

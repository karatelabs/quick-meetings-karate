#!/usr/bin/env bash
# live.sh [live|mock] — replay every pinned twin sequence against the running system. Neither
# face has a reset endpoint the twin could declare, so the root world is restored by the
# engine's own reset hook between sequences; a failing sequence is delta-debugged by shrink.
set -euo pipefail
cd "$(dirname "$0")"
AGAINST="${1:-live}"
case "$AGAINST" in
  live) RESET=./reset-sut.sh ;;
  mock) RESET=./reset-mock.sh ;;
  *) echo "usage: ./live.sh [live|mock]" >&2; exit 2 ;;
esac
./ka.sh "
var r = Twin.live('meetings', {baseUrl: '${QM_URL:-http://localhost:9981}', against: '$AGAINST',
                               reset: {command: ['$RESET']}, shrink: true});
({summary: r.summary, sequences: r.sequences.map(function (s) {
  return {id: s.sequenceId, kind: s.disposition.kind, at: s.disposition.at,
          code: s.disposition.code, mismatch: s.disposition.mismatch, shrink: s.shrink};
})})"

#!/usr/bin/env bash
# live.sh — replay every pinned twin sequence against the running SUT. The API has no reset
# endpoint, so the root world is restored by the engine's own reset hook between sequences;
# a failing sequence is delta-debugged by shrink.
set -euo pipefail
cd "$(dirname "$0")"
./ka.sh "
var r = Twin.live('meetings', {baseUrl: '${QM_URL:-http://localhost:9981}', against: 'live',
                               reset: {command: ['./reset-sut.sh']}, shrink: true});
({summary: r.summary, hook: r.hook, sequences: r.sequences.map(function (s) {
  return {id: s.sequenceId, kind: s.disposition.kind, at: s.disposition.at,
          code: s.disposition.code, mismatch: s.disposition.mismatch, shrink: s.shrink};
})})"

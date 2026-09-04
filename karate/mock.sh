#!/usr/bin/env bash
# mock.sh — stand the rules-backed mock up on the SUT's port, so the deck, contract and
# sequence lanes run with no app and no database. [up|down|reset]
# It is served over openapi.yaml, the app's own spec: the same handler file Twin.mutate
# starts in memory, so what the lanes exercise is what the mutants are graded against.
set -euo pipefail
cd "$(dirname "$0")"
case "${1:-up}" in
  up)
    ./ka.sh "
      if (typeof qmMock !== 'undefined' && qmMock !== null) { 'already up — ' + qmMock.url; } else {
        qmMock = Http.mock({openapi: '/openapi.yaml', port: ${QM_MOCK_PORT:-9981},
                            crud: false, validate: false,
                            handlers: File.call('/mock/handlers.js')});
        'ready — ' + qmMock.url;
      }" ;;
  down)
    ./ka.sh "if (typeof qmMock !== 'undefined' && qmMock !== null) { qmMock.stop(); qmMock = null; 'stopped.'; } else { 'not running'; }" ;;
  reset)
    ./ka.sh "qmMock.reset(); 'reset'" ;;
  *) echo "usage: ./mock.sh [up|down|reset]" >&2; exit 2 ;;
esac

#!/usr/bin/env bash
# mock.sh — stand the rules-backed mock up on the SUT's port, so the deck, contract and
# sequence lanes run with no app and no database. [up|down|reset]
set -euo pipefail
cd "$(dirname "$0")"
case "${1:-up}" in
  up)
    ./ka.sh "
      if (typeof qmMock !== 'undefined' && qmMock !== null) { 'already up — ' + qmMock.url; } else {
        qmMock = Http.mock({file: 'mock/quick-meetings.js', port: ${QM_MOCK_PORT:-9981},
                            arg: {Z: File.call('/checks/zones.js', {}),
                                  calc: function (row) { return Rule.execute('meetings', row); }}});
        'ready — ' + qmMock.url;
      }" ;;
  down)
    ./ka.sh "if (typeof qmMock !== 'undefined' && qmMock !== null) { qmMock.stop(); qmMock = null; 'stopped.'; } else { 'not running'; }" ;;
  reset)
    ./ka.sh "qmMock.reset()" ;;
  *) echo "usage: ./mock.sh [up|down|reset]" >&2; exit 2 ;;
esac

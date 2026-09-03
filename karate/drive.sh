#!/usr/bin/env bash
# drive.sh — run the deterministic deck through the live SUT with calc.js as the oracle.
set -euo pipefail
cd "$(dirname "$0")"
./ka.sh "
var deck = JSON.parse(File.read('deck.json'));
var r = File.call('/checks/deck-live.js', {rows: deck, baseUrl: '${QM_URL:-http://localhost:9981}'});
({rows:r.rows, agreed:r.agreed, diverged:r.diverged.length, setupFailed:r.setupFailed.length,
  reasonOnly:r.diverged.filter(function(d){return d.oracle === d.live;}).length,
  byRelation:r.byRelation, divergences:r.diverged.slice(0,10), setup:r.setupFailed.slice(0,5)})"

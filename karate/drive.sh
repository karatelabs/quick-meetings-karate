#!/usr/bin/env bash
# drive.sh — run the deterministic deck through the live SUT with calc.js as the oracle.
# The deck is frozen, so the declared domain is read over it rather than enforced on it:
# Schema.validate says which rows left the domain, Rule.check rolls them up per axis.
# The domain read runs BEFORE the drive: a rulebook-analysis verb in the same eval
# after it loses the worker, so the order is load-bearing, not cosmetic.
set -euo pipefail
cd "$(dirname "$0")"
./ka.sh "
var deck = JSON.parse(File.read('deck.json'));
var outside = 0;
for (var i = 0; i < deck.length; i++) { if (!Schema.validate('meetings', deck[i]).pass) { outside++; } }
var axes = (Rule.check('meetings').outOfDomain || []).map(function (a) {
  return a.axis + ' [' + a.lo + ',' + a.hi + '] ' + a.rows + ' rows (' + a.sources.join(',') + ')';
});
var r = File.call('/checks/deck-live.js', {rows: deck, baseUrl: '${QM_URL:-http://localhost:9981}'});
({rows:r.rows, agreed:r.agreed, diverged:r.diverged.length,
  reasonOnly:r.diverged.filter(function(d){return d.oracle === d.live;}).length,
  setupFailed:r.setupFailed.length, byRelation:r.byRelation,
  outOfDomain: outside, domainAxes: axes,
  divergences:r.diverged.slice(0,10), setup:r.setupFailed.slice(0,5)})"

#!/usr/bin/env bash
# mutate.sh — how much of the mock would the pinned sequences notice breaking? Twin.mutate
# spells first-order mutants over mock/handlers.js's guards, serves each from memory, and
# replays the sequences against it. Nothing here touches the app: the lane reads the same on
# every branch.
#
# One Twin.mutate call per sequence, not one call for all ten. The engine starts a fresh mock
# per BATCH and replays a batch's sequences back to back with no reset between them, so a deck
# whose every sequence starts from the empty calendar can only be graded one sequence per batch
# (all ten together read INVALID_BASELINE, correctly: the second sequence starts on the first
# one's meetings). Each row below is therefore a whole engine verdict for that sequence. They
# are NOT summed - the only thing read across them is set membership: which mutants some
# sequence killed, and which none did.
set -euo pipefail
cd "$(dirname "$0")"
./ka.sh "
var ids = JSON.parse(File.read('rulebooks/meetings/sequences.json')).sequences.map(function (s) { return s._id; });
var runs = [], killed = {}, checked = {}, last = null;
for (var i = 0; i < ids.length; i++) {
  var r = Twin.mutate('meetings', {handlers: '/mock/handlers.js', candidates: false, sequences: [ids[i]]});
  if (r.error) { throw 'Twin.mutate ' + ids[i] + ': ' + r.code + ' ' + r.error; }
  last = r;
  for (var m = 0; m < r.mutants.length; m++) {
    var mu = r.mutants[m];
    if (mu.status === 'KILLED') { killed[mu.id] = true; checked[mu.id] = true; }
    else if (mu.status === 'SURVIVED') { checked[mu.id] = true; }
  }
  runs.push(ids[i] + ' K' + r.counts.KILLED + ' S' + r.counts.SURVIVED
            + ' N' + r.counts.NOTCOVERED + ' SC' + r.counts.SCREENED
            + ' I' + r.counts.INVALID + ' T' + r.counts.TIMEOUT
            + ' den' + r.denominator + ' deck' + r.deckKillRate
            + ' order' + r.orderKillRate + ' raw' + r.rawKillRate);
}
var undefended = [];
for (var k in checked) { if (!killed[k]) { undefended.push(k); } }
undefended.sort();
var killedAny = 0;
for (var j in killed) { killedAny = killedAny + 1; }
var checkedAny = 0;
for (var c in checked) { checkedAny = checkedAny + 1; }
({catalog: last.provenance.catalogBefore, graded: last.provenance.catalogAfter,
  excluded: last.excluded.length, notRun: last.notRun.length, timeouts: last.timeouts,
  sequences: runs, checkedByAny: checkedAny, killedByAny: killedAny, worklist: undefended})"

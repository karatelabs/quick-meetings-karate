#!/usr/bin/env bash
# cut-deck.sh [strength] — rebuild deck.json from the rulebook. The deck is a frozen artifact,
# so this is run deliberately and the result committed; no lane calls it.
#
# The recipe: the saved scenarios, the boundary-value deck, and the t-way deck, deduplicated,
# keeping only rows inside the domain schema.js declares. Default strength is 3.
#
# Two rows are the same test when they send the same request and set up the same world. When a row
# has no existing meeting, checks/deck-live.js creates none and calc.js reads neither relStartMins
# nor existingDurationMins, so those two axes are canonicalised away before the dedup. Without that
# the strength-3 deck is 13,109 rows of which 12,674 are the same free-slot booking.
set -euo pipefail
cd "$(dirname "$0")"
STRENGTH="${1:-3}"
./ka.sh "
function canon(inp) {
  var none = !inp.hasExisting || inp.existingDurationMins === 0;
  return {zone: inp.zone, date: inp.date, time: inp.time, durationMins: inp.durationMins,
          hasExisting: none ? false : true,
          relStartMins: none ? 0 : inp.relStartMins,
          existingDurationMins: none ? 0 : inp.existingDurationMins};
}
function keyOf(r) {
  return JSON.stringify([r.zone, r.date, r.time, r.durationMins,
                         r.hasExisting, r.relStartMins, r.existingDurationMins]);
}
var lists = [JSON.parse(File.read('rulebooks/meetings/scenarios.json')),
             Rule.explore('meetings', {suite: 'boundary'}).suite,
             Rule.explore('meetings', {suite: 'pairwise', strength: $STRENGTH}).suite];
var seen = {}, deck = [];
for (var i = 0; i < lists.length; i++) {
  for (var j = 0; j < lists[i].length; j++) {
    var r = lists[i][j];
    if (r.domain === 'out') { continue; }              // the explorer already said so
    var inp = r.input || r;
    if (!r.input && !Schema.validate('meetings', inp).pass) { continue; }   // a saved row that left it
    var row = canon(inp);
    var k = keyOf(row);
    if (!seen[k]) { seen[k] = 1; deck.push(row); }
  }
}
File.write('deck.json', JSON.stringify(deck));
'deck.json: ' + deck.length + ' rows at strength $STRENGTH';"

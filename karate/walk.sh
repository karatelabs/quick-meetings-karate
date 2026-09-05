#!/usr/bin/env bash
# walk.sh — the bounded walk over the twin: states, transitions, guard refusals, invariants,
# and whether the frontier was exhausted rather than cut off by a ceiling. Twin.check grades the
# pinned sequences over the same walk, so the transition-pair denominator is the walk's own.
# The plan lives in plan.json, not here: witness.sh replays this walk and must be given the same
# plan, and a plan stated twice is two walks the moment one of them is edited.
set -euo pipefail
cd "$(dirname "$0")"
./ka.sh "
var PLAN = JSON.parse(File.read('plan.json'));
var r = Twin.explore('meetings', {plan: PLAN});
var c = Twin.check('meetings', {plan: PLAN});
({states: r.states.reached.length + '/' + (r.states.reached.length + r.states.notReached.length),
  transitions: r.transitions.observed.length + '/' + (r.transitions.observed.length + r.transitions.notObserved.length),
  refusals: r.stats.refusals, nodes: r.stats.nodes, edges: r.stats.edges,
  invariants: r.fidelity.invariants,
  ceiling: r.ceilings.hit, frontier: r.ceilings.frontier,
  counterexamples: r.counterexamples.length,
  transitionPairs: c.transitionPairs.covered + '/' + c.transitionPairs.of,
  transitionPairGaps: c.findings.transitionPairGaps.length})"

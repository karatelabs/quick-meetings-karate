#!/usr/bin/env bash
# walk.sh — the bounded walk over the twin: states, transitions, guard refusals, invariants,
# and whether the frontier was exhausted rather than cut off by a ceiling.
set -euo pipefail
cd "$(dirname "$0")"
./ka.sh "
var PLAN = {depth: {default: 3},
            levels: {'create.slot': ['A','B','D','E'], 'invite.user': [1,3],
                     'accept.user': [1,3], 'reject.user': [1,3]}};
var r = Twin.explore('meetings', {plan: PLAN});
({states: r.states.reached.length + '/' + (r.states.reached.length + r.states.notReached.length),
  transitions: r.transitions.observed.length + '/' + (r.transitions.observed.length + r.transitions.notObserved.length),
  refusals: r.stats.refusals, nodes: r.stats.nodes, edges: r.stats.edges,
  invariants: r.fidelity.invariants,
  ceiling: r.ceilings.hit, frontier: r.ceilings.frontier,
  counterexamples: r.counterexamples.length})"

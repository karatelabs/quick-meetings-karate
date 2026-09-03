# quick-meetings, re-tested with a rulebook and a twin

## Attribution

The application in this repository is **[quick-meetings](https://github.com/mourjo/quick-meetings)
by Mourjo Sen**, the sample app for his InfoQ article
**[Beyond Accidental Quality: Finding Hidden Bugs with Generative
Testing](https://www.infoq.com/articles/generative-testing/)**. It is reused and redistributed here
**with the author's written permission**; when the upstream project adopts a licence, that licence
will be carried here verbatim. The app, its `pom.xml` and its jqwik test suite are **byte-for-byte
upstream** — nothing outside `karate/` is ours, and the author's own README is kept as
[`UPSTREAM.md`](UPSTREAM.md).

Everything under [`karate/`](karate) is Karate Labs' and is MIT-licensed
([`karate/LICENSE`](karate/LICENSE)).

## What this proves

The article seeds five bugs into a Spring Boot meeting scheduler and lets jqwik discover them by
generating random actions. Here the same five bugs are re-found by an **LLM-authored rulebook** (the
booking rules as an executable oracle) and a **twin** (the lifecycle as a behaviour model) —
deterministically, from a deck and a set of pinned sequences that are the same on every run. Where
jqwik samples randomly on a fresh seed and shrinks whatever it happens to falsify, every finding
below is reproducible by construction, and the failing sequence is minimised by replay rather than
by search. The concession runs the other way too: jqwik will shrink an *arbitrary* failing chain
that nobody anticipated, and unbounded random interleavings can wander past any modelled ceiling.

## The five bugs, both ways

The article's bug, the branch, the jqwik property that finds it upstream, and the Karate lane that
re-finds it. Every number in the last column is measured — see [Findings](#findings).

| Article bug | Branch | jqwik property (`src/test/java/me/mourjo/quickmeetings/generativetests/`) | Karate lane and finding |
| --- | --- | --- | --- |
| The API server does not always return valid JSON | `demo-1-server-never-returns-5xx` | `RequestResponseGenTests.responsesAreAlwaysValidJson` | contract — **60 of 168** probes answer a 5xx or a non-JSON body |
| A valid date range is rejected across a DST gap | `demo-2-invalid-date-range` | `MeetingCreationGenTests.validMeetingRangeShouldReturn2xx` | deck — **16 of 574** rows diverge; 8 of them only in the refusal *reason* (`rulebooks/meetings/calc.js`, `QM-003/1`) |
| The overlap SQL misses containment | `demo-3-meeting-creation-scenarios` | `OverlappingMeetingsGenTest.overlappingMeetingsCannotBeCreated` | deck — **1 of 574** rows diverges (the `contains` relation, `calc.js` `QM-002/1`) · sequences — `seq-containment-refused` FAILs |
| Accepting an invitation double-books a person | `demo-4-meeting-acceptations` | `OperationsGenTests.noOperationCausesAnOverlap` | sequences — `seq-accept-would-overlap` FAILs at step 3 (`rulebooks/meetings/twin.js`, `QM-006/1`) |
| An owner can reject their own meeting, emptying it | `demo-5-empty-meetings` | `OperationsGenTests.noOperationCausesEmptyMeetings` | sequences — `seq-owner-cannot-reject` FAILs at step 1 (`twin.js`, `QM-007/1`) |

Two things to notice. The **deck** varies values and the **twin** varies order, and neither
substitutes for the other: a row-depth deck carries no state axis, so no value of any input reaches
"accept an invitation you were sent before you double-booked yourself". And the deck compares the
refusal **reason**, not just the verdict — half of demo-2's divergences are two 400s that disagree
about *why*, which a status-code diff cannot see.

Each branch here is this repository's `main` plus **exactly one commit**, the author's, carrying
only that bug — so a lane's finding has one cause. (Upstream the branches also lag `main` on
unrelated fixes; see [Findings](#findings).) The jqwik column names the property **as the author's
own branch carries it**: the branches tag it `test-being-demoed`, and `./tests-being-demoed.sh` is
how the article runs it. Here the branches carry `main`'s copy of the suite instead, untagged — and
for `demo-2` `main`'s copy of `validMeetingRangeShouldReturn2xx` accepts the DST-gap message, so it
is the branch's tightened variant, not this one, that falsifies.

## Prerequisites

- Java 21, Maven, Docker.
- A Karate licence, as `karate/.karate/karate.lic` or in `KARATE_LICENSE_TEXT`.
- `psql` on the PATH is used to reset the database; without it the scripts fall back to
  `docker exec postgres_quick_meetings psql`.

The engine jar is never committed. `karate/engine.sh` fetches it into `karate/lib/` — from
`KARATE_AGENT_JAR` if you set it, else the pinned release asset, else by extracting it from
`ghcr.io/karatelabs/karate-agent:<version>`. The version lives in one place,
[`karate/engine.version`](karate/engine.version), and every script and the workflow read it.

## First act: the whole suite, with no application

The rulebook is the oracle *and* the mock. `karate/mock/quick-meetings.js` answers the same five
endpoints and delegates every booking decision back to `Rule.execute('meetings', …)` — it holds no
copy of the rules, so it cannot disagree with them. Nothing else changes: the same deck, the same
probes, the same sequences.

```bash
cd karate
./serve.sh up            # the console, on :8099
./mock.sh up             # the rules-backed stand-in, on :9981
./verify.sh main mock    # every lane, asserted
```

```
deckRows              574
deckDiverged          0
deckReasonOnly        0
contractProbes        168
contractViolations    0
livePass              10
liveFail              0
liveFailing           []
walkStates            5/5
walkTransitions       17/17
walkRefusals          3086
walkInvariantsFailed  0

main: every expectation met
```

Green against the mock is green **by construction** — the mock computes its answers from the same
rulebook the lanes grade against. That is what it is for: it proves the suite is wired, before the
application exists or while it is down. The findings come from pointing the same lanes at the app.

## Second act: the same lanes, against the real application

```bash
docker compose up -d     # Postgres on :5432
cd karate
./mock.sh down
./app.sh up              # quick-meetings on :9981
./reset-sut.sh           # no meetings, users 1/2/3 — the twin's root world
./verify.sh              # every lane, asserted against expected.json
```

```
deckRows              574
deckDiverged          0
deckReasonOnly        0
contractProbes        168
contractViolations    0
livePass              10
liveFail              0
liveFailing           []
walkStates            5/5
walkTransitions       17/17
walkRefusals          3086
walkInvariantsFailed  0

main: every expectation met
```

The lanes individually:

| script | what it does |
| --- | --- |
| `./drive.sh` | 574 deterministic rows (saved scenarios + boundary + pairwise) through the API, `calc.js` as the oracle |
| `./contract.sh` | 168 transport probes — every path × Accept × malformed body — asserting JSON and no 5xx |
| `./live.sh` | the 10 pinned sequences replayed through the API, the database reset between them, failures shrunk |
| `./walk.sh` | the bounded walk over the twin: states, transitions, guard refusals, invariants |
| `./verify.sh` | all four, checked against this branch's row in `expected.json` |

The walk is what says the model has been explored rather than sampled. Under the plan the twin
declares it **exhausts** its frontier rather than tripping a ceiling: 5 of 5 states and 17 of 17
transitions reached over 219 nodes and 1,294 edges, 3,086 guard refusals censused, and the two
invariants checked 438 times between them without a failure. The ten rows in
`rulebooks/meetings/sequences.json` are authored against that walk — one per required transition and
rejection in `required.json` — and pinned, so every run replays the same ten.

The API has no reset endpoint, so the twin declares no in-model reset and the root world is restored
out of band. `live.sh` hands that to the engine as a reset hook — `reset: {command: ['./reset-sut.sh']}` —
which runs before every sequence, and a world that could not be prepared is recorded as INVALID
rather than as a finding about behaviour.

## Third act: the defect branches

```bash
cd karate
./switch-sut.sh demo-3-meeting-creation-scenarios
./verify.sh demo-3-meeting-creation-scenarios
```

```
deckRows              574
deckDiverged          1
deckReasonOnly        0
contractProbes        168
contractViolations    0
livePass              9
liveFail              1
liveFailing           ['seq-containment-refused']
walkStates            5/5
walkTransitions       17/17
walkRefusals          3086
walkInvariantsFailed  0
shrinkSteps           2
shrinkVerified        CONFIRMED

demo-3-meeting-creation-scenarios: every expectation met
```

`switch-sut.sh` checks the branch out and restarts the app; `verify.sh` asserts that branch's
expected finding, so a defect that stops reproducing fails the run.

### Findings

Measured against engine `2.1.3.RC3`, from a clean database, every lane driven by the scripts above.

| branch | deck (574 rows) | reason-only | contract (168 probes) | sequences (10) | shrink |
| --- | --- | --- | --- | --- | --- |
| `main` | 0 diverged | — | 0 violations | 10 PASS | — |
| `demo-1-server-never-returns-5xx` | 0 diverged | — | **60 violations** | 10 PASS | — |
| `demo-2-invalid-date-range` | **16 diverged** | **8** | 0 violations | 10 PASS | — |
| `demo-3-meeting-creation-scenarios` | **1 diverged** | 0 | 0 violations | **`seq-containment-refused` FAIL** | 2 → 2 steps, CONFIRMED |
| `demo-4-meeting-acceptations` | 0 diverged | — | 0 violations | **`seq-accept-would-overlap` FAIL** | 4 → 4 steps, CONFIRMED |
| `demo-5-empty-meetings` | 0 diverged | — | 0 violations | **`seq-owner-cannot-reject` FAIL** | 2 → 2 steps, CONFIRMED |

The walk is model-only, so it reads the same on every branch: 5/5 states, 17/17 transitions, 3,086
guard refusals, 438 invariant checks, 0 failures.

Each shrink result reads `from == to`: the pinned sequences are already minimal, and the engine
confirms that by replaying the minimum it found. That is the deliberate contrast with random
generation — there was nothing to delta-debug, because nothing was generated at random.

Two numbers here are lower than the same measurement taken against the **upstream** branch tips,
and the reason is this repository's branch shape. Upstream, each defect branch was cut before
`main` gained request-body validation, so it carries that regression too. Measured against the
upstream `demo-1` tip the contract lane reports 70 violations rather than 60, and the extra 10 are
the missing validation, not the missing exception handlers. The `demo-2` deck reads 16 divergences
on both.

## Continuous integration

[`.github/workflows/verify.yml`](.github/workflows/verify.yml) runs the whole thing on every push to
`main`: one job per branch, each standing the app up against a Postgres 16.4 service with the
compose file's credentials and schema, fetching the engine jar from GHCR, and running `verify.sh`
for that branch. A defect that stops reproducing, or a `main` that stops being clean, is a red run.

The engine tag is probed first by [`engine-gate.yml`](.github/workflows/engine-gate.yml): a version
whose image is not published yet skips the lanes grey with a warning rather than failing them red.
The licence comes from the `KARATE_LICENSE` repository secret. No jar and no licence is ever
committed.

## Layout

```
src/ pom.xml docker-compose.yml     the application and its jqwik suite, byte-for-byte upstream
UPSTREAM.md                         the author's own README
karate/
  rulebooks/meetings/
    schema.js        the meeting-creation input shape
    calc.js          the ORACLE: duration, DST resolution, Allen's thirteen interval relations
    generator.js     the declared input domain — levels reaching every relation and both DST days
    scenarios.json   the worked rows, one per interval relation plus the two DST days
    twin.js          the lifecycle: three users, create / invite / accept / reject
    sequences.json   the ten pinned sequences, one per required transition and rejection
  checks/
    deck-live.js     drives a deck through the API with calc.js as the oracle
    contract-live.js the transport probes
    zones.js         the wall-clock/instant arithmetic, shared by the driver and the mock
  mock/quick-meetings.js   the rules-backed stand-in
  deck.json          the deterministic deck (saved + boundary + pairwise), engine-built
  required.json      the required-row manifest the twin is graded against
  expected.json      the finding each branch must produce
  engine.version     the pinned engine, read by every script and the workflow
  *.sh               engine · serve · ka · app · mock · reset · drive · contract · live · walk · verify · switch-sut
```

## The interval convention is closed

Two meetings that merely touch — one ends exactly when the next begins — share an instant and
conflict. That is the application's own convention: its SQL predicate is
`from_ts <= :to AND to_ts >= :from` and its jqwik oracle asserts the same, so the rulebook adopts it
rather than the half-open reading a scheduler usually takes. `duration.to` is likewise a
**wall-clock** time, not an instant: across a DST fold a wall-clock range and a real duration are
different intervals, and the wire's reading is the contract.

# quick-meetings, tested with a rulebook and a twin

This repository takes the sample app from an InfoQ article about generative testing and tests it a
second way. The article finds five seeded bugs with jqwik, a property-based testing library. Here a
rulebook and a twin find the same five bugs. Both approaches sit side by side, so you can compare
them on the same code.

## Credits

The app is [quick-meetings](https://github.com/mourjo/quick-meetings) by **Mourjo Sen**. He wrote it
for his InfoQ article [Beyond Accidental Quality: Finding Hidden Bugs with Generative
Testing](https://www.infoq.com/articles/generative-testing/). Read the article first. It explains the
app, the five bugs, and how jqwik finds them.

The app is here under the author's [MIT licence](LICENSE), with his written permission. His code, his
`pom.xml` and his jqwik tests are unchanged. His README is kept as [`UPSTREAM.md`](UPSTREAM.md).

Everything from Karate Labs is in the [`karate/`](karate) directory, plus this README, the CI
workflows, [`NOTICE.md`](NOTICE.md) and [`SECURITY.md`](SECURITY.md). This material is MIT too, see
[`karate/LICENSE`](karate/LICENSE). `NOTICE.md` has the full attribution.

## What this shows

The article seeds five bugs into a Spring Boot meeting scheduler. jqwik finds them by generating
random actions. Every run uses a fresh random seed.

Here the same five bugs are found by two things an LLM wrote:

- A **rulebook**: the booking rules as executable code. It computes the correct answer for any input.
- A **twin**: the meeting lifecycle as a state model. It knows which actions are allowed in each state.

Both are deterministic. The rulebook drives a fixed deck of 974 rows. The twin replays ten fixed
sequences of actions. Every run gives the same result, and every finding reproduces on the first try.

To be fair to jqwik: it can shrink a failing chain of actions that nobody planned for. Our sequences
are planned, so shrinking only confirms that they are already minimal. And random actions can reach
states that a model does not include.

## The five bugs, both ways

Each row is one bug from the article. The jqwik column names the test that finds it. The Karate
column names the lane that finds it and the result. All numbers are measured, see
[Results](#results).

| Bug from the article | Branch | jqwik test (`src/test/java/me/mourjo/quickmeetings/generativetests/`) | Karate lane and result |
| --- | --- | --- | --- |
| The server does not always return valid JSON | `demo-1-server-never-returns-5xx` | `RequestResponseGenTests.responsesAreAlwaysValidJson` | contract: **60 of 168** probes get a 5xx or a body that is not JSON |
| A valid date range is rejected across a DST gap | `demo-2-invalid-date-range` | `MeetingCreationGenTests.validMeetingRangeShouldReturn2xx` | deck: **233 of 974** rows differ. 158 of them differ only in the refusal reason. Rule `QM-003/1` in `rulebooks/meetings/calc.js` |
| The overlap SQL misses one meeting inside another | `demo-3-meeting-creation-scenarios` | `OverlappingMeetingsGenTest.overlappingMeetingsCannotBeCreated` | deck: **1 of 974** rows differs, the `contains` case. Rule `QM-002/1` in `calc.js`. Sequence `seq-containment-refused` fails |
| Accepting an invitation double-books a person | `demo-4-meeting-acceptations` | `OperationsGenTests.noOperationCausesAnOverlap` | sequence `seq-accept-would-overlap` fails at step 3. Rule `QM-006/1` in `rulebooks/meetings/twin.js` |
| An owner can reject their own meeting and empty it | `demo-5-empty-meetings` | `OperationsGenTests.noOperationCausesEmptyMeetings` | sequence `seq-owner-cannot-reject` fails at step 1. Rule `QM-007/1` in `twin.js` |

Two things are worth a look.

The **deck** changes values. The **twin** changes the order of actions. Neither one replaces the
other. No input value can reach "accept an invitation after you double-booked yourself". Only a
sequence of actions can.

The deck compares the **reason** for a refusal, not only the status code. Half of the demo-2 rows are
two `400` responses that disagree about why. A status-code comparison cannot see that.

## How the branches are built

Each `demo` branch is this repository's `main` plus the author's own commits:

1. The commit that introduces the bug. This is the only change to `src/main`, so each result has
   exactly one cause.
2. The jqwik test that shows the bug, tagged `test-being-demoed` as in the article.

So both detections run on one checkout. `./tests-being-demoed.sh` runs the jqwik test the way the
article does. `karate/verify.sh` checks the Karate result.

The bug commits are real `git cherry-pick -x` picks of the upstream commits. `demo-1` picks two
(`575d8d3`, `69dae75`). The others pick one each (`586be6c`, `7cb6fc9`, `6910be3`, `42db256`). The
lines each pick adds and removes are identical to the upstream commit. Only the surrounding lines
differ, because this `main` is newer than the commit's parent. One pick needed a manual merge: the
first `demo-1` pick had a conflict in its import block. Its commit message explains the fix.

The test commits are **adapted replays**, not cherry-picks. Upstream, each test reaches its final
form over 5 to 25 commits mixed with other work. Each branch here holds one commit with that one test
file, exactly as the upstream branch has it. The commit message names the upstream commits.

## Before you start

You need:

- Java 21, Maven and Docker.
- A Karate licence. Put it at `karate/.karate/karate.lic`, or set `KARATE_LICENSE_TEXT`.
- `psql` on your PATH, if possible. The scripts use it to reset the database. Without it, they use
  `docker exec` into the Postgres container instead.

The engine is a jar named `karate-agent`. It is never committed. `karate/engine.sh` downloads it into
`karate/lib/`. It tries three sources in order: the `KARATE_AGENT_JAR` variable, the pinned release
asset, then the container image `ghcr.io/karatelabs/karate-agent`. The version is in one file,
[`karate/engine.version`](karate/engine.version). Every script and the CI workflow read it. Both
`engine.sh` and `verify.sh` print the resolved jar and its sha256, so a run always says which engine
produced its numbers — one version string can name two different jars.

## Step 1: run everything against the mock

You do not need the app for this step. The rulebook is also the mock. `karate/mock/handlers.js`
serves the same five operations as the app, over the app's own OpenAPI spec. For every booking
decision it calls `Rule.execute('meetings', ...)`. It holds no copy of the rules, so it cannot
disagree with them. `Twin.mutate` starts that same file in memory, so what the lanes exercise is
what the mutants are graded against.

```bash
cd karate
./serve.sh up            # start the engine console on port 8099
./mock.sh up             # start the mock on port 9981
./verify.sh main mock    # run every lane and check the results
```

```
deckRows                974
deckDiverged            0
deckReasonOnly          0
deckSetupFailed         0
deckAccounted           True
deckOutOfDomain         0
deckDomainAxes          ['durationMins [1,600] 434 rows (suite)', 'existingDurationMins [0,480] 725 rows (suite,witness)']
contractProbes          168
contractViolations      0
livePass                10
liveFail                0
liveFailing             []
walkStates              5/5
walkTransitions         17/17
walkRefusals            3086
walkInvariantsFailed    0
walkCeiling             exhausted
walkFrontier            0
walkCounterexamples     0
walkTransitionPairs     7/602
walkTransitionPairGaps  595
mutateCatalog           77
mutateGraded            77
mutateExcluded          0
mutateNotRun            0
mutateTimeouts          0
mutateSequences         ['seq-clean-two-meetings K4 S5 N55 SC12 I1 T0 den9 deck0.4444 order0.4444 raw0.4444', 'seq-containment-refused K16 S0 N55 SC5 I1 T0 den16 deck1 order1 raw1', 'seq-during-refused K16 S0 N55 SC5 I1 T0 den16 deck1 order1 raw1', 'seq-touching-refused K16 S0 N55 SC5 I1 T0 den16 deck1 order1 raw1', 'seq-overlap-refused K16 S0 N55 SC5 I1 T0 den16 deck1 order1 raw1', 'seq-invite-conflict-refused K30 S0 N33 SC13 I1 T0 den30 deck1 order1 raw1', 'seq-accept-would-overlap K37 S0 N20 SC19 I1 T0 den37 deck1 order1 raw1', 'seq-owner-cannot-reject K6 S8 N46 SC16 I1 T0 den14 deck0.4286 order0.4286 raw0.4286', 'seq-accept-clean K26 S1 N24 SC25 I1 T0 den27 deck0.963 order0.963 raw0.963', 'seq-reject-invite K27 S1 N26 SC22 I1 T0 den28 deck0.9643 order0.9643 raw0.9643']
mutateCheckedByAny      48
mutateKilledByAny       48
mutateWorklist          []

main: every expectation met
```

A green run against the mock is green by construction. The mock gets its answers from the same
rulebook that grades them. This step proves that the whole suite is wired up before the app exists,
or while the app is down. The real findings come from the next step.

## Step 2: run the same lanes against the app

```bash
docker compose up -d     # start Postgres on port 5432
cd karate
./mock.sh down
./app.sh up              # start quick-meetings on port 9981
./reset-sut.sh           # empty the meetings, create users 1, 2 and 3
./verify.sh              # run every lane and check against expected.json
./jqwik-check.sh         # run the author's own test suite
```

The output is the same as in step 1, and ends with `main: every expectation met`. On `main` the app
has no bugs, so every lane agrees with the rulebook and the twin.

Each script runs one lane:

| Script | What it does |
| --- | --- |
| `./drive.sh` | Sends 974 rows through the API. The rows come from saved scenarios, boundary values and pairwise combinations. `calc.js` computes the expected answer for each row. Also reads the declared input domain over the deck. |
| `./contract.sh` | Sends 168 probes: every path, with every `Accept` header, with each of eight malformed bodies. Each response must be JSON and must not be a 5xx. |
| `./live.sh` | Replays the ten sequences through the API. Resets the database before each one. Shrinks any sequence that fails. |
| `./walk.sh` | Explores the twin: states, transitions, transition pairs, refused actions and invariants. |
| `./mutate.sh` | Grades the pinned sequences against mutants of the mock's guards. Touches no app. |
| `./verify.sh` | Runs all five lanes and checks the numbers against this branch's row in `expected.json`. |
| `./jqwik-check.sh` | Runs the author's tests. On `main` the whole suite must pass. On a demo branch the tagged test must fail, and nothing else may break. It reads the surefire XML report to decide. |

### How the deck is cut

`cut-deck.sh` builds `deck.json`: the saved scenarios, the boundary-value deck, and the t-way deck
from `Rule.explore`, deduplicated, keeping only rows inside the declared domain. It is run
deliberately and the result is committed; no lane calls it. Before, there was no script - the deck
was a committed file with the recipe only in someone's head.

The deck is cut at **strength 3**. All-pairs guarantees that every pair of input values appears
together somewhere; strength 3 does the same for every triple. That matters here because the
interval relation is not an input, it is a function of three of them - the proposed duration, the
existing meeting's offset, and its duration.

Two rows are the same test when they send the same request and set up the same world. When a row has
no existing meeting, `deck-live.js` creates none and `calc.js` reads neither `relStartMins` nor
`existingDurationMins`, so `cut-deck.sh` canonicalises those two axes away before deduplicating.
Without that step the strength-3 deck is 13,109 rows, of which 12,674 are the same free-slot booking.
With it, **974**.

What that buys, counted by the relation each row lands in:

| Relation | Strength 2 (574 rows) | Strength 3 (974 rows) |
| --- | --- | --- |
| `before` | 2 | 55 |
| `after` | 1 | 51 |
| `overlaps` | 1 | 23 |
| `overlappedBy` | 1 | 30 |
| `during` | 2 | 13 |
| `contains` | 1 | **1** |
| `equals` | 1 | 3 |
| `meets` / `metBy` | 1 / 1 | 5 / 3 |
| `starts` / `startedBy` | 1 / 1 | 7 / 2 |
| `finishes` / `finishedBy` | 1 / 1 | 7 / 2 |

Most relations go from one incidental row to a dozen or more. `contains` does not. It is still
carried by exactly one row, and that row is a hand-written scenario, not something the covering array
produced.

That is worth saying rather than hiding, because `contains` is the relation `demo-3`'s bug lives in.
A t-way covering array covers t-tuples of declared *levels*. It does not cover a predicate derived
from several numeric axes at once: for the proposed meeting to strictly contain the existing one, the
offset must be positive and the offset plus the existing duration must be under the proposed
duration, all at the same time. No amount of raising `t` guarantees that region gets hit; it only
makes it more likely. Raising the strength improved the odds everywhere else and left this one cell
where it was.

So the honest reading is that the deck's reach on containment is still owed to a person who thought
about interval algebra and wrote the row down. The generator earns the other twelve relations.

### The declared domain

A coverage number only means something over a stated input universe. Here `schema.js` states it,
next to the shape:

```js
durationMins: '#int[1,]',            // a meeting must end after it starts. no maximum
existingDurationMins: '#int[0,]',    // 0 means there is no existing meeting
```

`calc.js` is where those come from: `duration.minMins` is 1, and the schedule declares no maximum
length. The app agrees. It rejects a meeting only when the end is not after the start, and it accepts
a nine-hour one.

`generator.js` may narrow that domain and may never widen it. It used to run `durationMins` from 0 to
600 with a comment claiming a bound of 1 to 480. Both were wrong: 480 is in no source file of the app,
and 0 is below the declared floor. The engine refuses the widening by name rather than intersecting it
quietly:

```
generator.js: 'durationMins' declares lo 0, outside the schema's #int[1,]
  - schema.js declares the domain, the generator may only narrow it
```

So the generator now runs 1 to 600. The engine still probes one below each floor, and reports what it
did instead of clamping it. That is where the two rollup lines come from: 434 generated rows sit below
`durationMins` 1, and 725 sit below `existingDurationMins` 0.

`deck.json` is frozen between cuts, so the domain is read over it rather than enforced on it, and
`deckOutOfDomain` says how many of its rows left the domain. The declaration was made against the
old 574-row deck first, and 60 of those rows were outside it - every one a zero-length meeting.
They ran, they were disclosed, and they were not counted as violations. The current deck was cut
after the declaration, and `cut-deck.sh` keeps only in-domain rows, so the count is now **0 of 974**
by construction. The number is still pinned, because a deck that drifts out of its own domain should
show up as a change rather than as nothing.

One thing follows that is worth stating plainly. Once the floor is 1, the arm in `calc.js` that
refuses a zero-length meeting can only be reached by input the domain excludes. `Rule.check` reports
it as `robustness.coverageOnly`: a defensive guard, not a business rule over the declared domain. The
saved scenario that used to claim a zero-length meeting was a valid row now says what it actually is,
`_expect: "schema-reject"`, and the check grades it `REFUSED` - which is the claim that matters, and
the one the old deck rows only ever made by accident.

The walk shows that the model was explored, not sampled. It reaches all 5 states and all 17
transitions over 219 nodes and 1,294 edges. It counts 3,086 refused actions. It checks the two
invariants 438 times with no failure. It stops because there is nothing left to explore, not because
it hit a limit. The ten sequences in `rulebooks/meetings/sequences.json` were written against this
walk, one for each required transition and rejection in `required.json`. Every run replays the same
ten.

The walk also reports **transition pairs: 7 of 602**, and 595 gaps. A pair is one transition followed
by another, in that order, from the same world. Reaching every transition once says nothing about
what happens after it; a pair says the second one was reached *with the first already applied*. That
is where the last two bugs live, and it is the coverage the deck cannot buy at any number of rows.

The denominator is the walk's, not a guess. 602 is the number of ordered pairs the walk actually
composed, so every one of them is known to be feasible. Counting 17 transitions two deep would give
289, which includes pairs no world admits, and squaring the wrong thing is how a made-up denominator
flatters a low number. The ten pinned sequences cover 7. The gap list is not a failure — CI does not
read it — it is the worklist. Each gap carries a shortest witness, and pinning one is one call:

```js
Rule.sequence.create('meetings', { steps: row.candidate.steps })
```

### Mutation: would the sequences notice the mock breaking?

Every number above says the suite agrees with the model. None of them says the suite would
*disagree* if the code changed. `./mutate.sh` asks that. `Twin.mutate` spells first-order mutants
over the guards in `mock/handlers.js` - negate a condition, move a boundary by one, remove an arm,
inline a constant - serves each one from memory, and replays a pinned sequence against it. A mutant
that a sequence turns from pass to fail is **killed**. One that survives names a change nothing in
the deck would notice.

The catalog is **77 mutants**. **48** of them some sequence puts a verdict on, and **all 48 are
killed**. The worklist is empty. The other 29 are never distinguished: one is `INVALID`, and the rest
are either unreached by any sequence or return the same bytes as the original.

| Sequence | Killed of denominator | Not covered | Screened |
| --- | --- | --- | --- |
| `seq-clean-two-meetings` | 4 of 9 | 55 | 12 |
| `seq-containment-refused` | 16 of 16 | 55 | 5 |
| `seq-during-refused` | 16 of 16 | 55 | 5 |
| `seq-touching-refused` | 16 of 16 | 55 | 5 |
| `seq-overlap-refused` | 16 of 16 | 55 | 5 |
| `seq-invite-conflict-refused` | 30 of 30 | 33 | 13 |
| `seq-accept-would-overlap` | 37 of 37 | 20 | 19 |
| `seq-owner-cannot-reject` | 6 of 14 | 46 | 16 |
| `seq-accept-clean` | 26 of 27 | 24 | 25 |
| `seq-reject-invite` | 27 of 28 | 26 | 22 |

The denominator is killed plus survived, and nothing else. `NOTCOVERED`, `SCREENED`, `INVALID` and
`TIMEOUT` sit outside it, so they can neither flatter a rate nor cap it. Read the last two columns as
one number: their sum is fixed per sequence, and where the line between them falls has been seen to
move with the state of the engine process, while the killed count and the denominator did not. Start
the console fresh - CI does, one per job - and take the split as the softer of the numbers here. The rows are not added up.
The only thing read across them is set membership: 48 mutants got a verdict somewhere, 48 were
killed somewhere, none survived everywhere.

`deckKillRate`, `orderKillRate` and `rawKillRate` are meant to be two different readings that are
never blended - the independent one, and the inclusive one. Here they are equal on every row, and
that is worth saying rather than showing three identical columns. The split is defined by whether a
kill moved a field named `premium`, which is the shared-oracle guard for a pricing domain. A meeting
has no premium, so every kill here counts as independent and the pair carries no information in this
kit.

**Seven bounds on what these numbers mean.**

1. *The read-back window.* A kill is only visible in what the sequence reads back - here a status
   code and a message. A mutant that changes something neither one shows cannot be killed.
2. *A hit is not a kill opportunity.* Reaching the mutated line is necessary, not sufficient; the
   change still has to reach the wire.
3. *Per-batch isolation.* The engine starts a fresh mock per batch and replays a batch's sequences
   back to back with no reset between them. Every sequence here starts from an empty calendar, so
   the batch is one sequence, and the deck is graded ten times rather than once.
4. *A syntactic frame.* The catalog is an enumeration of source edits, not a sample of the faults a
   real change would introduce. 77 is the size of that enumeration and nothing more.
5. *First order, operator biased.* One edit at a time, from four operators. A fault that needs two
   simultaneous changes is not in the population.
6. *A shared oracle.* The mock decides through the same rulebook that grades it. So a mutant in a
   *booking decision* is a mutant in one caller of the oracle, not in the oracle - these numbers
   grade the lifecycle wiring, never the booking rules.
7. *`SCREENED` is observational equivalence, not correctness.* A screened mutant produced the same
   bytes as the original on the sequences run. It is undetectable here, not harmless.

The honest reading beside jqwik: the article's argument is volume. Generate action chains at random,
a fresh seed each run, enough of them that a bad order eventually turns up. That argument buys reach
this one does not - a random chain can compose actions no author thought to write down, which is
exactly point 3's cost. What it does not buy is a bound. It cannot tell you which changes to the code
its tests would fail to notice, because it has no enumeration to measure against. Ten fixed sequences
and 77 enumerated mutants can, over a small, stated frame. Neither result contains the other, and
adding them together would be the mistake.

The API has no reset endpoint. So `live.sh` gives the engine a reset command,
`reset: {command: ['./reset-sut.sh']}`, and the engine runs it before each sequence. If the reset
fails, the sequence is marked `INVALID`. It is not counted as a finding about the app.

## Step 3: run a defect branch

```bash
cd karate
./switch-sut.sh demo-3-meeting-creation-scenarios
./jqwik-check.sh demo-3-meeting-creation-scenarios
./verify.sh demo-3-meeting-creation-scenarios
```

```
demo-3-meeting-creation-scenarios: me.mourjo.quickmeetings.generativetests.OverlappingMeetingsGenTest#overlappingMeetingsCannotBeCreated falsified (<failure>), nothing else broke
```

```
deckRows                974
deckDiverged            1
deckReasonOnly          0
deckSetupFailed         0
deckAccounted           True
deckOutOfDomain         0
deckDomainAxes          ['durationMins [1,600] 434 rows (suite)', 'existingDurationMins [0,480] 725 rows (suite,witness)']
contractProbes          168
contractViolations      0
livePass                9
liveFail                1
liveFailing             ['seq-containment-refused']
walkStates              5/5
walkTransitions         17/17
walkRefusals            3086
walkInvariantsFailed    0
walkCeiling             exhausted
walkFrontier            0
walkCounterexamples     0
walkTransitionPairs     7/602
walkTransitionPairGaps  595
mutateCatalog           77
mutateGraded            77
mutateExcluded          0
mutateNotRun            0
mutateTimeouts          0
mutateSequences         ['seq-clean-two-meetings K4 S5 N55 SC12 I1 T0 den9 deck0.4444 order0.4444 raw0.4444', 'seq-containment-refused K16 S0 N55 SC5 I1 T0 den16 deck1 order1 raw1', 'seq-during-refused K16 S0 N55 SC5 I1 T0 den16 deck1 order1 raw1', 'seq-touching-refused K16 S0 N55 SC5 I1 T0 den16 deck1 order1 raw1', 'seq-overlap-refused K16 S0 N55 SC5 I1 T0 den16 deck1 order1 raw1', 'seq-invite-conflict-refused K30 S0 N33 SC13 I1 T0 den30 deck1 order1 raw1', 'seq-accept-would-overlap K37 S0 N20 SC19 I1 T0 den37 deck1 order1 raw1', 'seq-owner-cannot-reject K6 S8 N46 SC16 I1 T0 den14 deck0.4286 order0.4286 raw0.4286', 'seq-accept-clean K26 S1 N24 SC25 I1 T0 den27 deck0.963 order0.963 raw0.963', 'seq-reject-invite K27 S1 N26 SC22 I1 T0 den28 deck0.9643 order0.9643 raw0.9643']
mutateCheckedByAny      48
mutateKilledByAny       48
mutateWorklist          []
shrinkSteps             2
shrinkVerified          CONFIRMED

demo-3-meeting-creation-scenarios: every expectation met
```

`switch-sut.sh` checks out the branch, restarts the app and resets the database. `jqwik-check.sh`
checks that the author's test fails and nothing else breaks. `verify.sh` checks that the Karate lanes
find what `expected.json` says they must. If a bug stops reproducing, both checks fail.

## Results

Measured with engine `2.1.3.RC3`, from an empty database, with the scripts above.

| Branch | Deck (974 rows) | Reason only | Contract (168 probes) | Sequences (10) | Shrink |
| --- | --- | --- | --- | --- | --- |
| `main` | 0 differ | 0 | 0 violations | 10 pass | none |
| `demo-1-server-never-returns-5xx` | 0 differ | 0 | **60 violations** | 10 pass | none |
| `demo-2-invalid-date-range` | **233 differ** | **158** | 0 violations | 10 pass | none |
| `demo-3-meeting-creation-scenarios` | **1 differs** | 0 | 0 violations | **`seq-containment-refused` fails** | 2 steps, confirmed |
| `demo-4-meeting-acceptations` | 0 differ | 0 | 0 violations | **`seq-accept-would-overlap` fails** | 4 steps, confirmed |
| `demo-5-empty-meetings` | 0 differ | 0 | 0 violations | **`seq-owner-cannot-reject` fails** | 2 steps, confirmed |

The deck was cut at strength 3. For the record, the strength-2 deck it replaces had 574 rows and read
`demo-2` as 16 differing rows of which 8 were reason-only, and `demo-3` as the same single `contains`
row. Which bug each branch's deck catches did not change; only how many rows catch it did.

The walk, the mutation lane and the declared-domain rollup all read the rulebook and the model only,
so their numbers are the same on every branch.

Each shrink result keeps the same number of steps. The ten sequences are already as short as
possible. The engine confirms this by replaying the shortest version it finds. Nothing was random, so
there was nothing to cut.

One number is lower here than against the upstream branches. Upstream, each demo branch was cut
before `main` got request-body validation, so those branches carry that older behaviour too. Against
the upstream `demo-1` branch, the contract lane reports 70 violations instead of 60. The extra 10
come from the missing validation, not from the bug. The `demo-2` deck reports 16 differing rows on
both.

## Continuous integration

[`verify.yml`](.github/workflows/verify.yml) runs on every push to `main`. It runs one job per
branch. Each job starts Postgres 16.4 with the schema and credentials from the compose file, starts
the app, downloads the engine from GHCR, and runs `jqwik-check.sh` and `verify.sh` for that branch.
The run is red if a bug stops reproducing, or if `main` stops being clean.

[`engine-gate.yml`](.github/workflows/engine-gate.yml) runs first. It checks that the pinned engine
image exists. If the image is not published yet, the lanes are skipped with a warning. They are not
marked as failed.

The licence comes from the `KARATE_LICENSE` repository secret. No jar and no licence is ever
committed.

## Files

```
src/ pom.xml docker-compose.yml     the app and its jqwik tests, unchanged from upstream
UPSTREAM.md                         the author's README
NOTICE.md SECURITY.md               attribution and licences; how to report a problem
karate/
  rulebooks/meetings/
    schema.js        the shape of a meeting request, and its declared input domain
    calc.js          the rules: duration, DST, and the thirteen ways two intervals can relate
    generator.js     values that reach every relation and both DST days. narrows the domain, never widens it
    scenarios.json   one saved row per interval relation, plus the two DST days
    twin.js          the lifecycle: three users; create, invite, accept, reject
    sequences.json   the ten sequences, one per required transition and rejection
  checks/
    deck-live.js     sends the deck through the API and compares with calc.js
    contract-live.js the 168 probes
    zones.js         reads the wall-clock and instant arithmetic back out of the mock
  mock/handlers.js   the mock that answers from the rulebook, and the guards Twin.mutate mutates
  openapi.yaml       the app's own spec, as served by /v3/api-docs, plus the mock-only /__reset
  deck.json          the deck rows, built by cut-deck.sh
  required.json      the states, transitions and rejections the twin must cover
  expected.json      the result each branch must produce
  engine.version     the engine version, read by every script and the CI workflow
  *.sh               engine, serve, ka, app, mock, reset, drive, contract, live, walk, mutate,
                     verify, cut-deck, jqwik-check, switch-sut
```

## A note on intervals

In this app, two meetings that only touch still conflict. If one ends at the exact moment the next
starts, they share that instant. This is the app's own convention. Its SQL predicate is
`from_ts <= :to AND to_ts >= :from`, and its jqwik test asserts the same. So the rulebook uses the same
convention, instead of the half-open intervals most schedulers use.

Also, `duration.to` is a wall-clock time, not an instant. Across a DST change, a wall-clock range and
a real duration are different intervals. The rulebook follows what the API sends.

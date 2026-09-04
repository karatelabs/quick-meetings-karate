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

Both are deterministic. The rulebook drives a fixed deck of 574 rows. The twin replays ten fixed
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
| A valid date range is rejected across a DST gap | `demo-2-invalid-date-range` | `MeetingCreationGenTests.validMeetingRangeShouldReturn2xx` | deck: **16 of 574** rows differ. 8 of them differ only in the refusal reason. Rule `QM-003/1` in `rulebooks/meetings/calc.js` |
| The overlap SQL misses one meeting inside another | `demo-3-meeting-creation-scenarios` | `OverlappingMeetingsGenTest.overlappingMeetingsCannotBeCreated` | deck: **1 of 574** rows differs, the `contains` case. Rule `QM-002/1` in `calc.js`. Sequence `seq-containment-refused` fails |
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
[`karate/engine.version`](karate/engine.version). Every script and the CI workflow read it.

## Step 1: run everything against the mock

You do not need the app for this step. The rulebook is also the mock. `karate/mock/quick-meetings.js`
serves the same five endpoints as the app. For every booking decision it calls
`Rule.execute('meetings', ...)`. It holds no copy of the rules, so it cannot disagree with them.

```bash
cd karate
./serve.sh up            # start the engine console on port 8099
./mock.sh up             # start the mock on port 9981
./verify.sh main mock    # run every lane and check the results
```

```
deckRows                574
deckDiverged            0
deckReasonOnly          0
deckSetupFailed         0
deckAccounted           True
deckOutOfDomain         60
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
| `./drive.sh` | Sends 574 rows through the API. The rows come from saved scenarios, boundary values and pairwise combinations. `calc.js` computes the expected answer for each row. Also reads the declared input domain over the deck. |
| `./contract.sh` | Sends 168 probes: every path, with every `Accept` header, with each of eight malformed bodies. Each response must be JSON and must not be a 5xx. |
| `./live.sh` | Replays the ten sequences through the API. Resets the database before each one. Shrinks any sequence that fails. |
| `./walk.sh` | Explores the twin: states, transitions, transition pairs, refused actions and invariants. |
| `./verify.sh` | Runs all four lanes and checks the numbers against this branch's row in `expected.json`. |
| `./jqwik-check.sh` | Runs the author's tests. On `main` the whole suite must pass. On a demo branch the tagged test must fail, and nothing else may break. It reads the surefire XML report to decide. |

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

`deck.json` is frozen, so the domain is read over it rather than enforced on it. **60 of the 574 rows
are out of the declared domain** - every one of them a zero-length meeting. They are declared, they
still run, and they are not counted as violations. Nothing is deleted to make a number look better.

One thing follows that is worth stating plainly. Once the floor is 1, the arm in `calc.js` that
refuses a zero-length meeting can only be reached by input the domain excludes. `Rule.check` reports
it as `robustness.coverageOnly`: a defensive guard, not a business rule over the declared domain. The
saved scenario that used to claim a zero-length meeting was a valid row now says what it actually is,
`_expect: "schema-reject"`, and the check grades it `REFUSED`. The 60 deck rows still prove the app
refuses one on the wire.

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
deckRows                574
deckDiverged            1
deckReasonOnly          0
deckSetupFailed         0
deckAccounted           True
deckOutOfDomain         60
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
shrinkSteps             2
shrinkVerified          CONFIRMED

demo-3-meeting-creation-scenarios: every expectation met
```

`switch-sut.sh` checks out the branch, restarts the app and resets the database. `jqwik-check.sh`
checks that the author's test fails and nothing else breaks. `verify.sh` checks that the Karate lanes
find what `expected.json` says they must. If a bug stops reproducing, both checks fail.

## Results

Measured with engine `2.1.3.RC3`, from an empty database, with the scripts above.

| Branch | Deck (574 rows) | Reason only | Contract (168 probes) | Sequences (10) | Shrink |
| --- | --- | --- | --- | --- | --- |
| `main` | 0 differ | 0 | 0 violations | 10 pass | none |
| `demo-1-server-never-returns-5xx` | 0 differ | 0 | **60 violations** | 10 pass | none |
| `demo-2-invalid-date-range` | **16 differ** | **8** | 0 violations | 10 pass | none |
| `demo-3-meeting-creation-scenarios` | **1 differs** | 0 | 0 violations | **`seq-containment-refused` fails** | 2 steps, confirmed |
| `demo-4-meeting-acceptations` | 0 differ | 0 | 0 violations | **`seq-accept-would-overlap` fails** | 4 steps, confirmed |
| `demo-5-empty-meetings` | 0 differ | 0 | 0 violations | **`seq-owner-cannot-reject` fails** | 2 steps, confirmed |

The walk explores the model only, so its numbers are the same on every branch.

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
    zones.js         wall-clock and instant arithmetic, shared by the checks and the mock
  mock/quick-meetings.js   the mock that answers from the rulebook
  deck.json          the 574 rows, built by the engine
  required.json      the states, transitions and rejections the twin must cover
  expected.json      the result each branch must produce
  engine.version     the engine version, read by every script and the CI workflow
  *.sh               engine, serve, ka, app, mock, reset, drive, contract, live, walk,
                     verify, jqwik-check, switch-sut
```

## A note on intervals

In this app, two meetings that only touch still conflict. If one ends at the exact moment the next
starts, they share that instant. This is the app's own convention. Its SQL predicate is
`from_ts <= :to AND to_ts >= :from`, and its jqwik test asserts the same. So the rulebook uses the same
convention, instead of the half-open intervals most schedulers use.

Also, `duration.to` is a wall-clock time, not an instant. Across a DST change, a wall-clock range and
a real duration are different intervals. The rulebook follows what the API sends.

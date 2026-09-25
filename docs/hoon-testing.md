# Hoon testing — a test desk and a headless runner

Written 2026-09-25, while building it for auspex. **The tooling has since
moved into [nisfeb/hoon-test-kit](https://github.com/nisfeb/hoon-test-kit)**
(vendored at `scripts/hoon-test-kit/`, configured by `hoon-test.conf`), and
its general procedure into that repo's `PLAYBOOK.md`. This file is the auspex
case study: what the runs found here, and how the method was learned.

## The problem it solves

The suites used to live on the app's own desk (`%grubbery` on `~wex`), run by
typing `-test` into the dojo. Each `|commit %grubbery` rebuilt the whole of
grubbery and held the dojo for **about two minutes**. At that price nobody
runs the suites after a small change, mutation testing is out of the
question, and CI cannot run them at all, because the only runner is a person
at a terminal.

## What we built

1. **A desk that holds only what the tests build.** `%auspex-test`: the two
   libs under test, the three suites, the vectors JSON, and — copied from the
   ship's own `%base` — `lib/test.hoon` and the marks the suites need. No
   agents, no app, nothing else to rebuild. A commit plus all 156 tests takes
   **about 7 seconds**.
2. **`hoon-test.sh`**, which drives it over the pier's `conn.sock` rather
   than the dojo: rsync the repo files into the mount, commit if anything
   changed, run `%test`, and exit 0 or 1. Requirements and the config are in
   the kit's README.

```
# once per ship, in its dojo:
|new-desk %auspex-test
|mount %auspex-test
# then, from the repo:
scripts/hoon-test-kit/hoon-test.sh <pier> setup           # copy test.hoon + marks from %base
scripts/hoon-test-kit/hoon-test.sh <pier>                 # every suite
scripts/hoon-test-kit/hoon-test.sh <pier> auspex-chain    # one suite
```

The per-test `OK` / `FAILED` lines go to the **ship's terminal**, not the
socket: `%test` slogs them and returns only a flag. The script says which
happened; the terminal says which test.

## Why it works: the libs are import-free

This is the precondition, and the reason the desk can be this small. The auspex
libs import nothing (see `overlay-notes.md`), so a test build reaches only the
lib, `lib/test.hoon`, and whatever marks a `/*` needs. **A lib that imports
the app's `sur/`, or other app libs, drags them onto the test desk too** — still
workable, just list them in `sync()`. A lib that imports the *agent* cannot be
tested this way at all; that logic has to be pulled out into a lib first. That
is the path for `app.hoon`, which has no automated tests.

## Things we learned the hard way

- **`%json` needs `%mime`.** A new desk has `noun`, `hoon`, `txt` and `kelvin`
  marks. `mar/json.hoon` declares `++grad %mime`, so building the json mark
  (which any `/*  x  %json  /path` does) needs `mar/mime.hoon` too. Without it
  the failure is `[%error-building-mark %json]` and the whole *file* fails as
  `FAILED … (build)` — one line, easy to miss among the OKs.
- **Copy support files from `%base`, don't vendor them.** `lib/test.hoon` and
  the marks are kelvin-bound. Setup scries them from the ship's own `%base`
  and writes them with a clay `%info`, so they always match the ship. It skips
  any file already there, so setup can be rerun.
- **khan-eval takes the hoon as one cord.** Newlines have to go, and
  **every newline must become two spaces**: one space is not a gap, and
  the parse fails with `syntax error {1 N}`, where N is a column in the
  joined line. The cord also cannot contain `'`.
- **In a heredoc, escape `$(` as `\$(`** (hoon's `$(…)` recursion) or bash runs
  it. Backticks likewise.
- **The commit is asynchronous to the poke.** `kiln-commit` acks before the
  change lands, so the script polls `/cz/<desk>` until the hash moves — and
  skips the commit when rsync changed nothing, or it would wait forever.
- **A failed thread's tang comes back as `[%leaf <bytes> 0]`.** The script
  turns those into text with a perl one-liner, so a syntax error is readable.
- **`~[ x]` with a leading space is a syntax error.** Mind generated lists.

## Proving a test is worth having: mutation checks

With a 7-second loop, "does this test fail when the code is wrong?" is cheap
to answer, and it's the only proof that a test guards anything. Break the
code on purpose, run the suite, restore it:

| mutation | what failed |
|---|---|
| `+ref-ok` stops checking `mime` | `test-refs-ok-checks-all-but-size`, and nothing else |
| `+de-archive` reads `archive` instead of `archived` | `test-de-archive`, and nothing else |

"And nothing else" is the finding: before those tests, neither mutation
failed anything. Name-based arm counts (125 of 161 chain arms named in a
test) overstate coverage; mutations measure it.

### The mutation script, and what its first run found

`scripts/hoon-test-kit/hoon-mutate.py <pier> [--ops OP,...] [--only ARM,...] [--list]` automates the
table above. It writes each mutant into the test desk's mount (never the
repo), runs the suites with `NOSYNC=1`, and syncs the clean libs back
however the run ends. It sorts every mutant as `killed`, `SURVIVED`,
`no-build` (the runner builds the libs first, so a mutant that does not
compile is never counted as killed), or `timeout` (it sends SIGINT to the
ship's king, the same as ^C in its dojo). About 10 s per mutant.

The menu, by `--ops` name:

| op | mutation | sites (2026-09-25) |
|---|---|---|
| `boundary` | `lte`↔`lth`, `gte`↔`gth` | 51 |
| `conjunct` | one condition of a tall `?&`/`?\|` replaced by `&`/`\|` | 47 |
| `branch` | `?:`↔`?.` (tall and wide) | 43 |
| `equal` | `=(`↔`!=(` as a comparison, never `?=(` or a rune's `=(` | 29 |
| `flag` | `%.y`↔`%.n` | 7 |

The default is `boundary,conjunct`: they cost least per real finding, because
they aim at caps and guards. `--list` sizes a run before it costs any commits;
plan on about 10 s and one commit per mutant.

The pilot menu was the two cheapest, highest-value operators: `lte`↔`lth` /
`gte`↔`gth`, and one condition of a tall `?&`/`?|` replaced by its identity.
**98 mutants on 2026-09-25: 64 killed, 32 survived, 2 no-build.** The
survivors were:

| kind | count | what it means |
|---|---|---|
| a whole check no test reaches | 5 | `settings-ok`'s two `max-listed` caps, `draft-ok`'s recipient cap, `rule-ok`'s subject length, and `in-inbox`'s "sent by someone else" clause. Each can be deleted and every test still passes. |
| a boundary no test sits on | 14 | the check is tested, but never at exactly the limit: `text-ok` at byte 0x1f, `shed-for` at exactly the budget, `auto-fetch`'s share, the caps in `settings-ok`, `draft-ok`, `rule-ok` and `peer-cap-error` |
| equivalent: same output | 12 | `prune` at exactly `max-copies` (the shedding path keeps all N and re-sorts), `shed-for`'s fast path (the loop repeats its check), sort comparators behind a `?.  =(…)` guard (`merge`, `unreferenced`), running maxima (`last-sent`, `max-ancestry`), and `proto-ok`'s two `scag` bounds, which exist to bound the *cost* of a walk. That is a property output can't show. |
| defensive only | 1 | `mark-for`'s range check, reachable only by a proto that skipped `proto-ok` |

Lessons from the run:

- **"A test exists" is not "the check is tested."** `test-settings-ok-bounds`
  and `test-draft-ok-applies-the-send-caps` look complete. Neither touches
  a list cap, and deleting that cap passes both.
- **Negative-only cap tests miss the boundary.** "cap + 1 is refused" does
  not fail when `lte` becomes `lth`. You need "exactly the cap is accepted"
  too. Write caps as a pair.
- **Equivalent mutants need a written reason.** A reviewed survivor should
  go on a list with *why*, or every run re-reports it.
- **Re-trace a survivor before writing its test.** Three that looked like
  gaps were equivalent: a fast path that repeats a check the loop makes
  anyway, and a shedding path that keeps everything at exactly the cap.
  A test for those would have been written against code that cannot fail.
- **The site finder is text, not a parser.** It split a tall `%+` child of
  `?&` across two lines into two "conditions"; both halves failed to build
  and were discarded, which is safe but means that condition went untested.

### The rest of the menu: `flag`, `branch`, `equal`

Run on 2026-09-25 as `--ops flag,branch,equal`, on a `~wex` that had not
been melded since its restart. It ran for 30 minutes and did not crash.

| op | killed | survived | no-build |
|---|---|---|---|
| `flag` | 0 | 7 | 0 |
| `branch` | 31 | 3 | 9 |
| `equal` | 27 | 2 | 0 |

Of the 12 survivors, 7 were real gaps, all closed the same day:
- `*meta`'s `archived` and `direct` defaults: the nexus bunts a meta for
  every new thread;
- `last-sent`, the time on every inbox row, which had no test at all;
- `chain-matches` never tested with a query that misses;
- `merge`'s tie-break for two copies of one message.

The other 5 were the older `meta-N` shapes' defaults, which are only ever
clammed with `;;` and never bunted. Rerunning the four fixed arms killed
all 10 of their mutants.

What it taught:

- **A high no-build rate is the site finder, not the code.** The first
  `equal` regex also matched the `=(` inside `|=(` gates: 66 of 87 mutants
  did not build, so most of the op never ran. Check no-build per op after
  every run; above a handful, fix the regex and rerun that op alone.
- **Some no-builds are real and expected.** Swapping `?.`↔`?:` after a
  `?=` test breaks the type narrowing the other branch relies on, so 9
  `branch` mutants cannot compile. Those are correctly discarded.
- **A mold's `$~` default matters only where the mold is bunted.** To
  classify a surviving default, grep the app for `*<mold>`: bunted means
  a real contract (test the bunt), only clammed means equivalent.
- **Sort tie-breaks: test the promise, not the key.** Which field breaks
  a tie is arbitrary; that every ship gets the same order is not. Test
  "same output for both arrival orders" and any total order passes it,
  while an order that leaves two elements unordered fails it.
- **Label sites by `+$` and `+*` too.** The finder named the nearest `++`
  arm, so defaults inside `+$  meta` were credited to the arm below it.

### Closing the gaps

Each missing check went into the test that already owns the rule, as a
pair where it is a cap: `(ships max-listed)` accepted, `(ships
+(max-listed))` refused. A test that needs n distinct ships builds them as
`(sy (turn (gulf 1 n) |=(i=@ `@p`i)))`. Then rerun **only** those arms:

```
scripts/hoon-test-kit/hoon-mutate.py <pier> --only text-ok,shed-for,settings-ok,draft-ok
```

Every survivor there must now be killed, or be re-traced and moved to
equivalent.

On 2026-09-25 that closed all 19 real gaps: the rerun over the eight arms
killed every mutant except `shed-for`'s fast path (equivalent, above). The
libs' remaining survivors are the 12 equivalent mutants and `mark-for`'s
defensive check, and nothing else.

### Look after the ship

Every mutant is a commit, and a commit costs loom. On 2026-09-25 `~wex`
died mid-run with `loom: external fault`, about 150 test-desk commits into
the day, while another session rebuilt a nexus in `%grubbery` on the same
ship. Two rules came out of it:

- **No answer is not a verdict.** Before the fix, a dead ship made every
  later mutant "killed" in 0 s. Now `hoon-test.sh` exits **4** when the
  ship does not answer, and `hoon-mutate.py` stops and marks the rest void.
  A run of implausibly fast results means the ship, not the tests.
- **A clean mount is not a clean desk.** After the crash the mount held
  the clean libs but clay still held the last committed mutant, and since
  rsync saw nothing to copy it never committed: the first run after the
  restart failed on a mutant. `NOSYNC=1 scripts/hoon-test-kit/hoon-test.sh <pier>`
  commits the mount as it stands and settles it; `hoon-mutate.py` now
  restores that way itself.
- **Only the owner restarts a pier.** A crash is stop-and-report. A long
  mutation run belongs on a ship nothing else is building on, and one that
  has been `|meld`ed recently. See lattice `/project/fake-ships/wex-loom-full`.

## Reaching the nexus

`nex/auspex/app.hoon` (4.5k lines) had no automated tests. Of its 188 arms,
74 do not use the fiber monad at all; 114 do. The plan, in order:

1. move the pure arms into a lib `-test` can build;
2. a route script that drives the HTTP API on a live ship;
3. a fiber harness that runs a fiber against scripted inputs (in the kit).

### Step 1: the pure arms, 2026-09-25

**Find what can move.** A script split the core into arms, marked each one
that uses `;<`, `bind:m`, `pure:m` or `form:m` as a fiber, marked the ones
naming grubbery's own types (`tarball`, `nexus`, `rail`, `dart`, `bowl`),
and kept only arms whose every callee also qualified: a closed set. 42
arms qualified. 28 carry logic, and they moved: the JSON renderers
(`msg-json`, `thread-json`, `entry-json`, `inbox-json` and the rest),
`in-view`, `arg-ud`, `want-slots`, `group-ids`, `refusal-line`,
`best-copy`, the `row` mold. Path constants stayed: only the roads use them.

**Move without touching callers.** Each moved arm left a one-line alias in
the nexus, `++  msg-json  msg-json:uc`, so no call site changed. That
matters: renaming call sites would have hit faces like `slot` and `arg`,
which the nexus also uses as names. The lib is import-free, so the moved
code only needed its `:uc` qualifiers dropped. The moved arms went into
`auspex-chain.hoon`, beside its other JSON helpers.

**Prove the nexus still behaves.** With the kit's suites passing, the new
code went onto `~wex`'s auspex desk by `write-text` (lib first, then app;
`?info=1` shows `bang: null` when it builds). A script captured 50 read
routes (every view, searches, paging, each label, every thread, drafts,
rules, lists, settings). Then the release-17 code went back on, the same
capture ran again, and **all 50 responses were byte-identical**. Then the
refactor went back on.

**Then test and mutate.** 12 new tests pin the API's JSON by field name,
each view's admission rule, the unread counts, `arg-ud`'s plain decimals,
and the storage layout `want-slots` writes. Mutation over the moved arms:
25 killed, 4 no-build, 3 survived. `sorted-dirs` was equivalent: ties are
directories of equal depth. The other two were real: a thread with no
forgery was never checked for `forged: false`, and `known-proto` had no
test. Both are closed.

Lessons:

- **Aliases make a move safe to review.** The nexus diff is deletions plus
  one line per arm, and the API capture is the proof it changed nothing.
- **Capture the API before and after on the same ship.** Unit tests on the
  moved arms can't show that the nexus still calls them the same way; 50
  identical responses do.
- **`?=(%a -.(expr))` and `*mold(field x)` are syntax errors.** `?=` needs
  a wing and a bunt can't take changes: bind the value with `=/` first.
- **`~wex` moved ports on restart.** It answers on 8080 now and `~feb` on
  8081; `curl localhost:<port>/~/host` says which ship is which.

**Web-lib mutation verdicts are void.** `calendar-df` found that
`hoon-mutate.py` left the previous lib's last mutant on the desk when a run
moved to the next lib, so every `auspex-web` mutant ran against two breaks.
The chain lib is mutated first, so its verdicts stand; the web lib's "no
survivors" must be rerun once the kit's fix lands.

## Porting to another app

Use the kit: its README covers installing and configuring it, and its
`PLAYBOOK.md` gives the rollout order. Auspex's `hoon-test.conf` is a worked
example of a config.

## Not done yet

- **CI.** The runner needs no dojo, so a fake ship booted in Actions can run
  it; tlon-apps' `backend/run-tests.sh` boots one from a pier archive the same
  way.
- **An allowlist file for reviewed equivalent mutants**, keyed by arm and
  op, so a reviewed survivor stops being re-reported.

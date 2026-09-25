# Playbook

How to put a Hoon app's tests on the kit, find what they miss, and close it.
Every rule here comes from something that went wrong at least once on auspex
(2026-09-25). Keep it current: when a run teaches something new, add it
here in the same change.

## Rolling out to an app

Do these in order. Each step has a condition for moving on.

1. **Make the libs reachable.** A test build reaches only what is on the
   test desk. Libs that import nothing are easiest. A lib that imports
   other libs or a `sur/` file works if those are listed in `LIBS` or
   `FILES` too. Logic inside the agent or nexus cannot be tested this way
   at all: move it into a lib first. *Done when* every lib you want tested
   builds on the desk.
2. **Set up the kit and run a baseline.** Vendor the kit, write
   `hoon-test.conf`, then `|new-desk` and `|mount` the test desk, run
   `setup`, then run the suites. *Done when* `hoon-test.sh <pier>` exits 0
   and the count of distinct `OK` lines in the ship's terminal matches the
   number of `++  test-` arms in the files. Count them with `sort -u`: the
   scrollback keeps earlier runs, and `tmux clear-history` does not clear
   what is still on the screen.
3. **Run the cheap mutation pass.** `hoon-mutate.py <pier> --list`, then
   the default ops (`boundary,conjunct`). They aim at caps and guards, and
   give the most real findings per commit. *Done when* every survivor is
   triaged (below).
4. **Close the real gaps**, then rerun only the arms you fixed with
   `--only`. *Done when* every mutant there is killed or has been moved to
   equivalent with a reason.
5. **Run the rest of the menu**: `--ops branch,equal,flag`. Check the
   no-build rate per op first (below). Triage, close, and recheck as
   before.
6. **Write down what the run found**: in the app's own docs, what
   survived and why each equivalent is equivalent. Anything new about the
   *method* goes in this file.

## Reading a mutation run

Each mutant ends in one of four ways:

| verdict | meaning |
|---|---|
| `killed` | some test failed. Good. |
| `SURVIVED` | every test passed with the code broken: a gap, or a mutant that changes nothing |
| `no-build` | the mutant does not compile, and is discarded |
| `timeout` | it ran past the limit; the kit sends ^C to the ship (SIGINT to the king process) |

**Check the run's health before reading survivors:**

- **Implausibly fast results (0 s) mean the ship, not the tests.** A dead
  ship used to make every later mutant "killed". Now the runner exits 4
  and the rest of the run is void.
- **A high no-build rate for one op means the site finder is wrong.** The
  first `equal` regex matched the `=(` inside `|=(` gates: 66 of its 87
  mutants never compiled, so most of that op silently never ran. Above a
  handful of no-builds, fix the pattern and rerun that op alone.
- **A verdict that changes between `--only <arm>` and the full run means
  the run is contaminated.** Until 2026-09-25 the runner left each lib's
  last mutant on the desk when it moved on to the next lib, so every later
  mutant ran against two breaks: on the calendar, `rules`' last mutant
  "killed" every `rrule` mutant, and `rrule`'s last one (which did not
  build) made every later mutant a no-build. Fixed: the previous lib is
  restored before each mutant. **Rerun any multi-lib pass made before the
  fix** (auspex's included): its killed counts are too high.
- **Some no-builds are expected.** Swapping `?.`/`?:` after a `?=` test
  breaks the type narrowing the other branch relies on, so those mutants
  can't compile. That is correct. The same goes for a tall `?&` condition
  that spans lines: the text-based finder splits it, and both halves fail
  to build.

## Triaging a survivor

**Re-trace every survivor before writing a test for it.** Read the arm and
its callers, and ask whether the mutant can change any output. On auspex,
17 of 44 survivors turned out to be equivalent. A test written for one of
those is written against code that cannot fail.

These kinds of mutant are equivalent, with no output that could differ:

- **A fast path that repeats a check** the loop makes anyway.
- **A comparator behind an equality guard.** `?.  =(a b)  (lth a b)` can
  never compare equal values, so `lth` and `lte` agree there.
- **A running maximum or minimum**: `gth` and `gte` pick the same value
  on a tie.
- **A path that gives the same result at the boundary**, such as shedding
  down to N when there are exactly N.
- **A bound that limits cost, not the answer**, like a `scag` before a
  walk. It is real, but output can't show it.
- **A spelling the rest of the code cannot reach.** On orrery,
  `(gth (lent w) 3)` → `gte` before stripping a plural `s` only changes
  three-letter words, and no two-letter weekday name exists to match.
- **A `$~` default on a mold that is never bunted.** Grep the app for
  `*<mold>`. If the mold is bunted, the default is a real contract, so
  test the bunt. If it is only ever clammed with `;;`, the mutant is
  equivalent.

What is left is a real gap, usually one of these:

- **A whole check no test reaches.** A test that looks complete, such as a
  "bounds" test, may never touch one of the bounds: delete it and every
  test still passes.
- **A boundary only tested from one side.** "cap + 1 is refused" does not
  fail when `lte` becomes `lth`.
- **A branch only tested one way**, such as a search tested with a query
  that hits but never with one that misses.
- **An arm with no test at all.** Mutation finds these even when a
  coverage count says the lib is well covered.

A check that is only defensive, reachable only if some earlier validation
was skipped, can stay untested. Say so in the triage notes.

Some survivors are real but not worth a test. Record them as **accepted**
with the reason, never as equivalent, since output can differ:

- **An exact-instant comparison against now in a pass that reruns every
  few minutes**, such as `(lte r.occ now)`. At the one instant of equality
  the pass decides one way, and the next pass decides the same as either
  spelling would.
- **A sort comparator on ties the output never promises to order.**

On orrery's first `--since` run, 44 of 51 mutants survived: 20 real gaps,
20 accepted and 4 equivalent. Code written in a
fix pass arrives without its boundary tests, so run `--since <rev>` right
after the change.

## Writing tests: traps

- **`weld`/`zing` over literal tapes can `fuse-loop`** the type checker
  (`;:  weld  "a"  x  "b"  ==` did, and so did `(zing (reap n "é"))`
  inside a `weld`). Cast: `` `tape`(zing `(list tape)`(reap n "é")) ``.
- **`%+  expect  !>` is wrong**: `expect` takes one vase. Write
  `(expect !>(…))`.
- **`*mold(field x)` does not parse**: a bunt takes no changes. Bind it
  with `=/` first, then change the face. (`?=` needing a wing is under
  "Writing the missing test".)
- **`roll` or `weld` over an untyped literal list mull-grows.** Cast it
  (`` `(list entry)`~[…] ``) or weld through a dry gate.
- **Before trusting a count, check what a structure really holds.** A
  day span puts both its edges in the calendar's index, so a year of
  dates is two keys, not one. The first run of a new suite is as likely to
  find a test's wrong assumption as a bug; read the expected/actual.
- **A new suite can find real bugs before any mutant runs.** The
  calendar's first run found `FREQ=weekly` refused (RFC 5545 values are
  case-insensitive).

## Writing the missing test

- **Put it in the test that already owns the rule.** Add a new test only
  when nothing owns it.
- **One case per clause of a `?|` or `?&`.** A fixture that meets every
  clause at once kills none of the `conjunct` mutants. Orrery's one
  "ship's own" calendar event carried all three marks (an `orrery` meta
  key, an `orrery-` id and an `orrery` tag), so dropping any one survived.
  Test an event with each mark alone.
- **A window has two edges and each has two sides.** Something ending
  exactly as the window opens is outside, and so is something starting
  exactly as it closes. An all-day event ends at exactly the next
  midnight, so this edge is the common case, not a corner.
- **Build cap-sized values in place.** Use `(crip (reap 64 'a'))` for a
  string of exactly the cap, and `(turn (gulf 1 n) f)` for n items.
- **`?=` takes a wing, not an expression.** For a unit an arm answers,
  test `!=(~ (f x))` or bind it first with `=/`.
- **Test caps as a pair**: exactly the cap is accepted, and one past it is
  refused.
- **For ordering, test the promise, not the key.** Which field breaks a
  tie is arbitrary; that every ship gets the same order is not. "Same
  output for both arrival orders" passes for any total order and fails
  for one that leaves two elements unordered.
- **For n distinct ships**: `(sy (turn (gulf 1 n) |=(i=@ `@p`i)))`.
- **Prove it with the mutant.** Run the suite on the real code (it must
  pass), then `hoon-mutate.py --only <arm>`: the mutant must now be
  killed. A test that never failed proves nothing.

## Look after the ship

Every mutant is a commit, and every commit costs loom. A full menu on one
app is a couple of hundred commits.

- **Use a ship nothing else is building on**, ideally one kept only for
  tests, and `|meld` it before a long run. `~wex` died mid-run at
  `--loom 33` with `loom: external fault`, about 150 test-desk commits
  into a day, while another session rebuilt a nexus on the same ship.
- **A crash is stop-and-report.** Only the ship's owner restarts a pier.
  Believe the runner when it says the ship stopped answering. On
  2026-09-25, `~nec`'s vere process was still listed while the ship was
  dying, and an agent read it as slow. The runner now names the mutant
  that was running.
- **A crash is not always a full loom.** `~wex` (`--loom 33`) and `~nec`
  (the default 2 GB) both died during kit runs with `loom: external
  fault: 0`, a fault at address 0, outside the loom. After `~nec`'s
  restart, `|mass` showed 617 MB marked of 2 GB, and three commits of a
  6,200-line lib added only about 16 MB. The mutant running at the time
  only flipped a comparison. The cause is open. To size the risk on your
  ship, read `total marked:` from `|mass` before and after a few
  mutants.

- **Never type into a dojo someone may be using.** `|new-desk` and `|mount`
  are the owner's to run: if the pane shows input you did not send (a
  `|pack`, a half-typed line), stop and ask.
- **In a shell tool, `rm` may be `rm -i`** and wait forever on a prompt,
  and `pkill -f <pattern>` kills the tool's own shell when the pattern is
  in its command line. Use `rm -f`, and put a `pkill` in a script file.
- **A clean mount is not a clean desk.** After a crash the mount can hold
  clean files while clay still holds the last mutant. rsync then sees no
  change and never commits. `NOSYNC=1 hoon-test.sh <pier>` commits the
  mount as it stands and settles it. `hoon-mutate.py` restores this way
  itself when a run ends.

## Testing nexus code

A grubbery nexus mixes code that touches the tree with code that doesn't,
and `-test` can build neither while it sits in the nexus. Three steps, in
order of value per hour. Auspex took the first two on 2026-09-25
(`auspex/docs/hoon-testing.md`, "Reaching the nexus").

1. **Move the pure arms into a lib.** Split the nexus core into arms. An arm
   is a fiber if it uses `;<`, `bind:m`, `pure:m` or `form:m`, and it
   touches grubbery if it names `tarball`, `nexus`, `rail`, `dart` or
   `bowl`. Keep the arms that are neither and whose every callee also
   qualifies, so you have a closed set. Move the ones that carry logic,
   usually the HTTP JSON, view and filter rules, query parsing and storage
   layout, into a lib the kit already builds.
   - **Leave a one-line alias** in the nexus for each (`++  x  x:uc`), so
     no call site changes. Renaming call sites collides with faces that
     share an arm's name.
   - **Prove the nexus unchanged on a ship.** Capture every read route's
     JSON, put the old code back, capture again, and diff. Auspex: 50
     routes, byte-identical.
   - Then test the moved arms and mutate them like any lib.
   - **Count `+$` molds as arms** when you pick the closed set. A mold
     between two arms is otherwise swallowed into the arm above it, stays
     behind, and the lib fails `-find.<mold>`. Molds are pure: move them
     and alias them too (`+$  x  x:uc`).
   - **Make the route diff mean something.** Seed varied data first; a
     ship with two items proves little. Capture twice with the old code
     and check those two agree before comparing old with new, strip
     any time-dependent field, and include the refusals. Calendar: 58
     routes; auspex: 50, both byte-identical.
   - **A grubbery build error is not on the console**, which says only
     "did not compile". It's on the file: `GET /grubbery/ball/<desk>/code/
     lib/x.hoon?info=1`, field `build.detail`.
   - A moved arm may use a lib from grubbery's own subject (`sut` in
     `app/grubbery.hoon`: `json-utils`, `html-utils`, ...). Put it in
     `PRELUDE` and fetch the real one with `SHIP_FILES`.
2. **A route script on a live dev ship.** Drive every route the clients
   use, the way they use them, including every refusal the API promises.
   This is the only layer that sees wiring: a route pointed at the wrong
   handler, a missing grant, a mark the nexus doesn't hold. Tag everything
   it creates and delete it all in a `finally`, restore any settings, and
   poll after writes, since the writer applies them after the route
   answers. **Prove it bites**: rename one route on the ship, and exactly
   that check must fail.
   - Log in with `ship-cookie.sh <pier> <base-url> <cookie-jar>`. It
     fetches `+code` over `conn.sock`, posts it on stdin (never in argv,
     never printed), keeps only the cookie, and refuses when the port
     answers as a different ship. Fake ships move ports on restart.
3. **Drive the fibers** with `hoon/fiber-test.hoon` (README, "Driving a
   nexus's fibers"). A fiber is `$-(input output)`, so a test can run one
   exactly as the runtime does. To get there:
   - **Build the nexus on the test desk.** Put it in `LIBS` with
     `DIALECT=grubbery`; put the faces grubbery gives every nexus that it
     uses in `PRELUDE` (count them: auspex needed `tarball nexus loader
     io=fiberio http-utils`), and the libs behind them in `SHIP_FILES`
     from `%grubbery`. Its web-client files arrive as relative `/<`
     imports, and those need their marks (`html js json svg`).
   - **Enter through `+on-file`**, like grubbery: `((on-file:app rail blot)
     ~)` is the grub's process, and its starting state is whatever that
     grub holds. For a request grub that is `[src inbound-request]`, which
     `+request` builds.
   - **Assert what the fiber did:** the pokes it sent (the writer's actions,
     by mark) and the response it gave. How it did it is not the contract.
   - **Answer like grubbery answers.** Every bowl read gets a reply *and*
     an ack; answering with only the reply leaves `take-bowl` waiting
     forever for the ack, and the run stops `%wait` after one dart. When a
     run stalls, print each step's input kind and verb: the stall is the
     step whose input it wanted and never got.
   - **An asset or read route stops at its peek.** The harness leaves
     peeks unanswered, and that is enough: assert which grub the route
     read (`+peeks`). Auspex's router went from 11 surviving mutants to
     none with one table test over its five asset routes and one for
     `whoami`.
   - Mutating the nexus rebuilds it per mutant (about 20 s each on
     auspex), so mutate by arm with `--only`: the route handlers you
     tested, and the router, whose survivors are exactly the routes no
     fiber test reaches yet.

## Traps in building the runner

These are already handled in the scripts. They are here for anyone
changing them.

- **khan-eval takes the hoon as one cord.** Every newline must become
  *two* spaces: one space is not a gap, and the parse fails with
  `syntax error {1 N}`. The cord cannot contain `'`.
- **In a bash heredoc, escape Hoon's `$(` as `\$(`** (and backticks), or
  bash runs it.
- **`~[ x]` with a leading space is a syntax error, and so is `~[]`.**
  An empty generated list must be written `~`.
- **A backslash escape in the thread's hoon is read by the outer cord.**
  `"\0a"` arrives as a raw newline inside a tape, and the parse fails.
  Write `(trip 10)`.
- **A product that is itself `[%leaf tape]` arrives bare** (`%leaf 79 75 …
  0`, no brackets), unlike a failed thread's leaf. The report decodes both.
- **The commit lands after the poke acks.** The runner polls `/cz/<desk>`
  until the hash moves, and skips the commit when nothing changed, or it
  would wait forever.
- **`%json` needs `%mime`.** `mar/json.hoon` declares `++grad %mime`.
  Without it, any `/*` of a json file fails its whole test file as
  `FAILED … (build)`: one line, easy to miss among the OKs.
- **Copy support files from `%base`, never vendor them.** `lib/test.hoon`
  and the marks are tied to the ship's kelvin.
- **`%test` returns only a flag.** Per-test lines go to the ship's
  terminal. A failed thread's tang comes back as `[%leaf <bytes> 0]`; the
  runner decodes it into text.
- **Name sites by `+$` and `+*` as well as `++`**, or a default inside a
  mold is credited to the next arm.

## Not built yet

- **CI.** The runner needs no dojo, so a fake ship booted in Actions can
  run it. tlon-apps' `backend/run-tests.sh` boots one from a pier archive.
- **An allowlist of reviewed equivalent mutants**, keyed by arm and op,
  so they stop being re-reported.
- **More operators**: arithmetic, list operations, a deleted line.
- **Wide conjunctions.** `conjunct` only reads a tall `?&` or `?|`. The
  wide `&(a b)` and `|(a b)`, which orrery uses for most guards, are not
  mutated yet.

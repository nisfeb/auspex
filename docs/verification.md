# urmail — verification record

This is a record of what was actually run and actually observed while building
`urmail`, not a summary of the design. For the design itself, read
`docs/superpowers/specs/2026-09-07-urmail-design.md`. For the task-by-task
narrative and every controller ruling behind the decisions below, read
`.superpowers/sdd/2026-09-07-urmail/progress.md` and the `task-N-report.md`
files it links.

Where a report's verbatim dojo transcript and the ledger's summary of it
disagree in wording, this document follows the transcript. No disagreement
in substance was found between the two while writing this — see "Sourcing
notes" at the end.

## The headline gap: no agent-test harness exists

**Update, 2026-09-08 (final fix round).** The gap this section describes is
substantially closed, but not by building an agent harness — by moving the
logic out of the agent. `+prune`, `+thread-key`, the verdict-freeze fold
and the four input caps were pure functions of their arguments sitting in
the agent by placement, not necessity. They now live in
`desk/lib/urmail.hoon` (still free of `.^`, confirmed by `grep`), the agent
keeps thin call sites, and the suite grew from 19 tests to **31**, green on
both `~wex` and `~feb`. What follows describes why no `desk/tests/app/`
exists and remains accurate; the "zero automated coverage" consequence
below is superseded by "What the library tests now cover", further down.

`desk/tests/` contains exactly one file: `lib/urmail.hoon`, 31 tests, all
passing (`-test /=urmail=/tests` → `ok=%.y`). There is no
`desk/tests/app/`.

That's not an oversight. `desk/tests/app/urmail.hoon` was written once, in
Task 5, and could not be made to build. `/+  *test-agent` — the vendored
harness every agent-level test needs to import — fails to compile on this
desk with a kernel-level `nest-fail`:

```
-need.?(%~ [i=/ t=it(/)])
-have.[it(/) @p /]
nest-fail
```

The Task 5 implementer bisected this to the file itself, not to anything in
`urmail`: a minimal `tests/app/` file containing only `/+  *test-agent` and a
dummy arm fails identically, regardless of filename or directory
(`tests/app/` vs `tests/lib/`), which rules out a name collision or a
directory-specific code path. The controller independently reproduced the
same failure via `-build-file /=urmail=/lib/test-agent/hoon` on `~wex`, and
checked every other copy of `test-agent.hoon` reachable in the environment:
`feb/mcp`'s copy is byte-identical to this desk's, but `feb/mcp` never
imports it, so it's never actually built there either. **There is no
408-compatible copy of `test-agent.hoon` anywhere in this environment.**
Both dev ships (`~wex`, `~feb`) run `%base` at `[%zuse 408]`; the vendored
harness needs 409. Bumping the dev ships was rejected — the user confirmed
mid-project that 408 support is required — and patching a 453-line
kernel-adjacent vendored file was judged disproportionate.

The ruling was to delete `desk/tests/app/urmail.hoon` rather than keep a
permanently-red file in the suite (a red file that can never go green trains
people to stop reading red, which is worse than having no test at all), and
to replace what coverage it would have given with live dojo evidence
instead. That live evidence exists — see below — but it is **live evidence,
not a regression test**. Nothing will catch a future regression in it
automatically.

**Consequence as of Task 8, now largely superseded:** every
security-relevant property fixed in Task 5 — the `+thread-key` identity
fix, the distinct-id and per-copy caps, the thread-count cap, the
`%unverified`→`%verified`/`%forged` upgrade path, and the `+prune`
shed-not-reject behavior — had zero automated test coverage. The final fix
round moved all of those except the thread-count cap into
`desk/lib/urmail.hoon` and covered them; see below.

**What still has no automated coverage**, because it genuinely needs a
bowl or a live agent: the jael scry wrappers (`+our-life`, `+our-ring`,
`+fake-ship`, `+peer-pass`, `+key-map`), the signing step in `+send`, the
card emission, the `%urmail-update` fact, the `on-poke` source gate
(`=(our.bowl src.bowl)`), the JSON encoders, the thread-count cap, and the
sequencing of `+receive` itself. Those remain backed by live dojo evidence
only.

## What the library tests now cover

All 31 live in `desk/tests/lib/urmail.hoon` and exercise only pure code
(`desk/lib/urmail.hoon` — no `.^`, confirmed by `grep`). They cover, in
summary (see the file itself for exact assertions):

- Sign/verify round-trip, wrong-key rejection, wrong-message rejection
  (Task 1).
- `+digest` is exactly `(shaf %urmail (sham u))`, and is domain-separated
  from an unsalted `(sham u)` and from a `%ames`-salted equivalent (Task 1
  fix round).
- `msg-id` covers every field of `unsigned`, including `prev` specifically
  (Task 2) — the reviewer showed this is the one field not already implied
  by the digest tests.
- `+root`, `+participants`, `+merge` (dedupe within `new`, dedupe against
  `old`, ordering by `sent`, keeping both copies of a signature-collision),
  `+verify-chain` (missing key → `%unverified`, tampered body → `%forged`,
  tampered `life` → `%unverified` not `%forged`, correct verdict under a
  genuinely rotated life, verdict keyed on `[id sig]` not `id` alone), and
  **the marquee test**, `test-third-party-verifies-forwarded-chain`: a
  message signed by `~sampel-palnet` and a chain forwarded to
  `~marbud-marbud`, who has never spoken to `~sampel-palnet`, verifies
  correctly using only the `(map [ship @ud] (unit pass))` `+all-keys`
  builds — no network, no second ship, no agent (Task 3).

The opus review of Task 3 confirmed this suite is not vacuously green: a
hard-coded `%verified` passes the marquee test but fails both tamper tests,
and vice versa, so the suite is mutually non-vacuous.

Twelve more were added in the final fix round, against the logic moved out
of the agent:

- `+prune`: sheds rather than rejects; never sheds a `%verified` copy;
  ranks `%unverified` above `%forged` in the fill bucket; and the full
  three-way ranking. Each ranking assertion is made in **both input
  orders**, because `+add:ja` prepends and a single-order fixture passes
  the broken code by luck — the first draft of these tests did exactly
  that. Confirmed discriminating by reverting the fill to the old
  `(skip ms verified)` form on `~wex` and watching two of them go red,
  then restoring it and watching them go green.
- `+thread-key`: identity from content rather than list order; identity
  ignoring the attacker-chosen `sent` field; an established thread's
  identity immutable against a poke carrying a fresh `prev=~` message;
  and first contact tolerating a shadowed (junk-signed) root.
- `+freeze`: a `%verified` or `%forged` verdict is never overwritten;
  an `%unverified` one can still be upgraded.
- The input caps as predicates, and `+distinct-ids` counting ids rather
  than signed copies.

**These tests still do not touch `desk/app/urmail.hoon`.** They cover the
arms that used to live there. `+receive`'s sequencing, the thread-count
cap, the scry wrappers and the JSON encoders remain agent-layer and
uncovered.

## The three-ship provenance test: not run

Task 8's brief asked for a booted third fake ship (`~c`), with a
`~wex → ~feb → ~c` forward, so that `~c` — a ship with no prior contact with
`~wex` — could be shown verifying `~wex`'s message. **This was not done.**
The user was asked and had not started a third pier, and per standing
constraint no agent boots or kills piers in the user's tmux. This step is
skipped, not attempted-and-failed.

What stands in its place, and why it's not merely "the same thing with fewer
moving parts":

**Pure coverage (no network at all).** `test-third-party-verifies-forwarded-chain`
(Task 3, still passing as of the current 19-test suite) proves the
verification *logic* is sound for a genuine third party: `~marbud-marbud`
verifies `~sampel-palnet`'s signature on a forwarded message using only a
key map, never having exchanged a single byte with `~sampel-palnet`. This
is the fallback the Task 8 brief itself names for a declined third ship, and
it was already in place before Task 8 began.

**Live coverage (real ships, real Ames, no automated test).** Task 5's fix
round 2 produced something stronger for the live side: a chain whose
`unsigned` payload names `from=~sampel-palnet` and `to={~palnet-sampel}` was
signed using the fake-ship deterministic key derivation (`fake-ring:urmail`
— the same mechanism `%deed` uses for fake ships, and the same mechanism the
pure tests use; `~sampel-palnet` and `~palnet-sampel` were never booted
piers, only cryptographic identities derived and used offline), then poked
directly into `~wex` from `~feb`'s dojo using dojo's remote-sink syntax:

```
~feb:dojo> =urm -build-file /=urmail=/lib/urmail/hoon
~feb:dojo> =u [~sampel-palnet 1 (sy ~[~palnet-sampel]) 'remote-boundary' 'stranger, remote' ~2026.1.2 ~]
~feb:dojo> =m [u (sign-with:urm (fake-ring:urm ~sampel-palnet) (digest:urm u))]
~feb:dojo> :~wex/urmail &urmail-chain ~[m]
>=
```

`src.bowl` on that poke was `~feb` — a real, running, remote ship, over real
Ames — and `~feb` is neither the message's sender, its recipient, nor `~wex`
itself. `:urmail &dbug [%state '']` on `~wex` afterward showed the chain
stored, `~sampel-palnet`'s message reading `%verified`,
`participants={~sampel-palnet ~palnet-sampel}`, and `~wex` present in
neither `participants` nor anywhere else in the chain. `~wex` accepted and
correctly verified a message from a ship it has never had any relationship
with, delivered by a courier that also has no relationship with the
message's author or recipient.

**What this proves and what it doesn't.** It proves: (a) signature
verification is authoritative regardless of who delivers a chain — the
courier is not checked and is not a participant, exactly the design's
central claim; (b) this holds over real Ames between two genuinely
independent, currently-running ships, not just inside one VM's pure test
runner. It does **not** prove a chain traveling through *three sequential
live hops* (author ship → forwarder ship → final ship, each a real running
pier that must itself verify, re-sign nothing, and re-transmit correctly)
behaves the same way, because `~sampel-palnet` and `~palnet-sampel` never
ran as piers — only `~wex` and `~feb` did. A third booted pier would add
one more real relay in the chain of custody; this configuration substitutes
a cryptographically genuine but unbooted third identity instead. The
controller's judgment, recorded in `progress.md`, is that this is a
stronger demonstration of the property the design cares about (courier
identity is irrelevant to verification) even though it is a different
topology than the brief originally asked for. This document states both
the judgment and the gap it doesn't close, rather than letting the stronger
framing imply the untested topology also ran.

## What else was verified live, and how

All of the following comes from verbatim dojo transcripts in the named
task reports; several were independently reproduced by the controller
rather than accepted from the implementer's report alone (noted where true).

**Task 1 — the `%vein` scry gate (the project's go/no-go check).**
`(met 3 .^(@ %j /(scot %p our)/vein/...))` on `~wex` returned `65` — the
byte length of a real suite-b ring, confirming userspace can reach a ship's
own signing key before any `urmail` code was written.

**Task 4 — the agent goes live and signs its first real message.**
After two blocked rounds (kelvin-list vs. kelvin-pin, then a 16-arm agent
core that built but wouldn't install — both controller misreadings of the
brief, both caught and fixed rather than worked around), `%urmail` reached
`app status: running` on `~wex` and `:urmail &urmail-action [%send ...]`
produced a stored, `%verified` message. The controller independently
confirmed `+vats` showed `running` with kelvin `[%zuse 408] [%zuse 409]`,
and independently confirmed that `~wex`'s ship-wide `+dbug` breakage (used
throughout the project as `&dbug [%state '']` instead) is not a `urmail`
defect — `:grubbery +dbug` fails identically on a known-good, unrelated app
on the same ship.

**Task 5 — cross-ship send, reply, and 5-message dedup.** `~wex` sent to
`~feb`; `~feb` replied via `prev` (the first live exercise of reply
resolution — it worked on the first attempt); three more alternating
replies produced a 5-message chain, `%verified` on both sides, with
**identical thread-ids independently computed by both ships** from the same
root message, and no growth beyond 5 despite each send re-shipping the
entire accumulated chain both directions.

**Task 5 — non-participant courier acceptance, twice, closing a real gap
between the two.** Round 1 poked a `~sampel-palnet → ~palnet-sampel` chain
into `~wex` from `~wex`'s own dojo — this ruled out a missing
participant-membership check but left `src.bowl` local (`~wex` itself),
so it could not rule out the much more plausible regression
`?>  =(our.bowl src.bowl)` (present nearby in the same code, gating a
different poke type) accidentally firing here too. The controller caught
this gap on review. Round 2 closed it by repeating the poke **from `~feb`'s
dojo into `~wex`** (the transcript quoted above), which is genuinely remote
and non-participant at once.

**Task 5 — oversized-chain rejection, distinct-copy cap, and the shed fix.**
A 1,001-message chain against `max-chain=1,000` was rejected with the
chain-length guard firing, and state was byte-identical before and after
(reject, not partial-write). A round-2 fix introduced a *reject*-based
per-message-id copy cap (`max-copies=4`), which the round-3 adversarial
review found made the censorship attack from the design's own "deliberate
limits" section *worse*, not better: landing four forged copies of a
never-seen root at `max-copies` would permanently reject the genuine
message when it later arrived, for the cost of four junk signatures instead
of the thousand the raw length cap required. This was fixed by having
`+prune` **shed** excess copies (never a `%verified` one) instead of
rejecting the whole poke, and the exact freeze scenario was re-run live to
confirm the fix: four forged copies landed first, then the genuine message
was poked and **was accepted and read `%verified`**, with one of the forged
copies silently shed to make room. `-test /=urmail=/tests` stayed green
(`ok=%.y`, 19 `OK`) after every round on both ships, confirmed by the
controller independently on `~wex`, not only from the implementer's report.

**Task 6 — the anti-shadowing property, visible in the JSON the UI
consumes.** The controller ran `.^(json %gx /.../inbox/json)` and
`/x/thread/<id>` scries directly against `~wex`'s live state, independent
of the implementer's own report, and confirmed a four-copy thread (one
genuine message plus three signature-tampered copies sharing its id)
renders **one `verified` and three `forged` verdicts**, keyed on `[msg-id
sig]` rather than collapsing to a single shared verdict for the id. The
Task 5/6 fix work exists specifically so this does not collapse; this is
the strongest single piece of end-to-end evidence in the project that it
doesn't. `%fact` push (`%urmail-update`) was independently verified firing
on both send and receive over a real eyre `/~/channel` subscription, not
just by code inspection.

**Task 7 — the same property, rendered on screen.** Driving a real headless
Chromium against `vite dev` proxying to `~wex`, the "shed-test" thread
rendered as exactly 4 `<article>` elements: one green "verified" pill and
three red, bold, ring-outlined "FORGED" pills, all sharing one message id
and identical body text. A compose sent through the UI from `~wex` to
`~feb` arrived on `~feb`'s own state with `"verdict":"verified"`, confirmed
via a scry against `~feb` directly — a real signed delivery, not a local
echo. The `/updates` push path was verified live end-to-end after a fix
round: a thread left open in the UI against `~wex`, with no reload, went
from 1 to 2 messages within about a second of a reply poked directly into
`~feb`, both the open thread and the inbox list updating correctly off the
same push. A stale-thread race (clicking thread A then B before A's slow
scry resolved could render A's content under B's header) was found in
review, "fixed" once ineffectively, and the second fix was confirmed with
an actual reproduction — the broken code shown failing the race, the fixed
code shown passing it, three runs — rather than by code-reading alone,
per the coordinator's explicit instruction not to trust reasoning-only
evidence here again.

## What was checked only by inspection, not live reproduction

Recorded honestly by the Task 5 implementer and left as unclosed gaps, all
in `desk/app/urmail.hoon` code, none with automated coverage:

- The thread-count cap (`max-threads=10,000`) and the two capacity guards
  guarding message-count and thread-count were never triggered live —
  doing so would require creating on the order of 1,000–10,000 messages or
  threads by hand through the dojo, judged impractical. They were verified
  as simple, structurally identical arithmetic guards to the ones that
  *were* live-tested (`max-chain`, `max-body`, `max-subj`, `max-to`).
- The `%unverified`-can-upgrade-to-`%verified`/`%forged` fix was verified
  by inspection only — reproducing it live would require controlling
  jael's public-key snapshot mid-session (poke once before a key is known,
  again after), which isn't stageable from a dojo session.
- Two specific exploits named by the Task 5 Critical finding — a poke that
  reorders a chain to duplicate a conversation under a fresh thread-id, and
  a poke with a backdated signed `sent` that migrates an established thread
  to a new id — were not reproduced as standalone adversarial pokes. The
  fix (`+thread-key`, resolving identity by `[id sig]` content-membership
  rather than list position or `sent`) was verified by tracing that no
  remaining code path reads position or `sent` for identity, and by the
  live copy-cap tests exercising the same "multiple roots in one poke"
  shape as one of the two exploits, but not the exploits themselves,
  byte-for-byte.
- Moon and comet provenance is out of scope for v1 per the spec (both read
  `%unverified` regardless of signature validity) and was not exercised at
  all, live or otherwise — there is no moon or comet identity anywhere in
  this project's dojo transcripts.

## Deliberate limitations still open on this branch

These are recorded in the spec and sharpened by later reviews; none of them
are secret and none of them were fixed in this project:

- **The distinct-id cap can still freeze a thread permanently with one
  poke and no valid signatures.** Anyone who holds even one `[id sig]` pair
  from a thread (a legitimate former participant, or anyone a chain was
  ever forwarded to) can self-sign arbitrary additional distinct messages
  into that thread — forged messages are stored and counted, no real
  signature is required to inflate the count — up to the per-thread
  distinct-id cap, after which the *reject*-based guard (kept as a reject,
  by explicit ruling, because shedding a distinct non-root id would orphan
  later `prev` pointers) rejects every further legitimate message forever.
  The fix, named but not built, is a per-source quota rather than a global
  per-thread cap.
- **`+thread-key`'s lookup scans every stored message.** It resolves a
  poke's thread by scanning for `[id sig]` membership across everything the
  ship holds, with a `sham` per candidate — O(total stored messages) on the
  only externally reachable poke. The upgrade path named is a
  `[msg-id sig] → thread-id` index.
- **A chain touching two existing threads gets conflated.** If a poked
  chain's messages match content already stored under two distinct
  thread-ids, `+thread-key` files everything under whichever match it finds
  first rather than detecting or resolving the collision.
- ~~**`+prune`'s fill bucket doesn't rank `%unverified` above
  `%forged`.**~~ Fixed in the final fix round: the fill is now strictly
  `%verified`, then `%unverified`, then `%forged`, with tests in both
  input orders.

Two further items, smaller and outside authenticity: `+merge`'s and
`+prune`'s sort runs twice per poke (once in each), and shed `[id sig]`
verdict entries are never garbage-collected from the `verdicts` map, so a
single poke of junk-signature copies grows `verdicts` even though the
stored chain itself stays bounded — inside the spec's stated "storage is
unbounded" allowance, but worth knowing. `%delete-thread` does clear the
`verdicts` and `read` entries for the thread it removes, so the residue is
now bounded by whatever the user chooses to keep.

Every capacity limit above is now *recoverable* rather than permanent:
`[%delete-thread =thread-id]`, added in the final fix round and gated on
`=(our.bowl src.bowl)`, removes a thread, its inbox entry, its verdicts
and its read marks. A user whose thread is frozen at the distinct-id cap,
or whose state is at `max-threads`, no longer has `|nuke` as the only
remedy.

## Sourcing notes

Every dojo transcript and live-verification claim above is drawn directly
from the report for the task that produced it (`task-1-report.md` through
`task-7-report.md`), preferring the report's verbatim output over
`progress.md`'s prose summary wherever the two could be compared. No
substantive disagreement between a report and the ledger's summary of it
was found. The one place the two differ is narrative framing, not fact:
`progress.md`'s Task 8 ruling (recorded in full at the end of the ledger)
describes the Task 5 non-participant proof as "on real ships... with a
remote non-participant courier," which is accurate for the courier
(`~feb`, a real running ship) but could be misread as claiming
`~sampel-palnet` and `~palnet-sampel` also ran as piers. They did not — see
"The three-ship provenance test: not run" above, which states this
explicitly rather than let the stronger framing carry through unqualified.

One test-count fact worth confirming rather than assuming: task-3-report.md
records the suite growing from 14 to 19 tests across three in-task fix
rounds, and task-4, task-5, and task-6 reports each independently confirm
19 `OK` lines with no further growth or shrinkage for the remainder of the
project. The current repository state matches: `desk/tests/lib/urmail.hoon`
contains 19 `++  test-*` arms as of this writing.

## Final fix round, 2026-09-08

Seven review findings were closed on this branch after the document above
was written. Full detail is in
`.superpowers/sdd/2026-09-07-urmail/final-fix-report.md`; the live evidence
is summarized here so this file stays the single record of what was run.

- **Suite: 19 → 31 tests**, `ok=%.y` on `~wex` and on `~feb`.
  `+vats %urmail` shows `app status: running` with matching `%cz` hashes
  (`d4k4o`) on both ships.
- **Reply audience is user-editable.** Driven live in headless Chromium
  against `vite dev` proxying to `~wex`: the composer rendered the chips
  `~palnet-sampel` and `~sampel-palnet`, `~sampel-palnet` was removed with
  its × control, a reply was sent, and a scry of the thread on `~wex`
  showed the new message's `to` as exactly `~[~palnet-sampel]`. The
  removed ship did not receive the chain.
- **The inbox list carries a verdict.** The same session rendered rows as
  e.g. `~sampel-palnet | verified | + forged | 2 copies | post-refactor`,
  drawn from the newest non-`%forged` copy, with `+ forged` flagging a
  thread that also holds a signature-failed copy.
- **`+send` enforces the receive-side limits.** A 100,001-byte body poked
  through the dojo on `~wex` nacked with `urmail-body-too-long`; a normal
  send in the same session succeeded.
- **`%delete-thread` works from both the dojo and the UI.** Dojo: inbox
  13 entries → 12, subject gone. UI: 13 rows → 12, selection cleared, the
  deleted subject absent from the page.
- **Compose still delivers cross-ship.** A message composed in the UI on
  `~wex` arrived on `~feb` and scried there as `verdict: verified`.
- **`+receive` still accepts a stranger's chain after the refactor.** A
  `~sampel-palnet → ~palnet-sampel` chain carrying one genuine and one
  junk-signed copy of the same message was poked into `~wex`; it filed
  under a content-derived thread id, the summary was drawn from the
  `verified` copy, and the row flagged `forged: true`.

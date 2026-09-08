# urmail — verification record

Date: 2026-09-08. Subject: **the grubbery nexus**, which is the only urmail
there is. The Gall build this file used to describe was deleted in `a0d82ca`;
nothing here refers to it.

This records what was actually run and actually observed. For the design, read
`docs/superpowers/specs/2026-09-07-urmail-design.md`; for the release gates,
`docs/release-plan.md`.

## The standard of evidence, and how to read this file

Every claim below is filed under one of three headings, and the heading is the
claim being made about the claim:

- **Live** — run on a ship and observed. A dojo transcript, a scry of the real
  ball, or a browser driven against the ship.
- **Inspected** — read off source (arvo, grubbery, or this repo) and reasoned
  about. Not run. A reading is not evidence, and this project has already
  shipped a test that passed the bug it existed to catch.
- **Unevidenced** — stated somewhere as fact with nothing behind it here.

**Everything is treated as unverified until it appears under Live.** That
includes claims made confidently in the slice reports: this file re-files them
by what the report actually shows, not by what it concludes.

**Sourcing.** The underlying transcripts are in the slice reports under
`.superpowers/sdd/2026-09-07-urmail/` — `port-slice-1`, `nexus-slice-2`,
`attachments-slice-3`, `branching-slice` and `ui-slice`. That directory is
**gitignored**: it exists on this machine and in no clone. If it is lost, this
file is what survives, which is why the entries below name what was seen rather
than only where to look.

**Ships.** `~wex` (pier `/home/sneagan/software/wex`, HTTP 8081) and `~feb`
(`/home/sneagan/software/feb`, 8080), both fake, both running the overlay synced
from this repo into their own `%grubbery` desk. `~ricsul-bilwyt` was never
touched. No pier was booted, killed or reset for any of this.

---

## Live

### The core mail loop

- **Compose signs and stores.** A `%send` on `~wex` wrote one copy at the
  expected path with `verdict: verified`, and `/tr/last` recorded the thread id.
- **Reply and forward are one action.** Both resolved `prev` to its containing
  thread and filed into it; a forward addressed elsewhere carried the chain.
- **Delivery verifies before storing.** A chain sent `~feb` → `~wex` arrived,
  was verified on ingest, and was stored with per-copy verdicts.
- **The third-party property, on the nexus, over real Ames.** A chain authored
  by a ship neither party had spoken to, couriered by `~feb`, verified on
  `~wex`. This is the claim the whole design exists to make and it is the one
  most worth re-running after any change to the signing or key path.
- **`[id sig]` anti-shadowing is the storage layout.** Two copies of one message
  differing only in signature were both stored, at two slots under one node,
  with two different verdicts. Neither overwrote the other.
- **Redelivery is a no-op.** Re-poking a chain already held wrote nothing and
  did not move the beacon.
- **A foreign `%urmail-action` is refused**, while a chain from the same foreign
  ship is accepted — the source check and the public poke grant doing exactly
  what they are supposed to.
- **The writer survives a rejection** and applies the next poke.
- **`%read` touches `meta` and nothing else.** `%delete-thread` reclaims
  capacity.
- **Reload safety.** `|suspend` / `|revive` with mail, blobs and threads present
  loses nothing; the `%fall` rows cover every dynamic path.

### Branching, and the leak that is now closed

- **The migration ran on live mail on both ships.** Threads stored flat under
  `msg/<slot>` were re-placed under their ancestry; zero flat files afterwards,
  every thread present, nothing refused. Read from `peek/tree`, which reflects
  live grubs — `peek/kids` and `peek/subd` list tombstones and were not used for
  any absence claim.
- **The migration is idempotent.** A second full bounce wrote nothing: the
  writer's trace still carried the outcome from before it, same tree, same
  thread count (17 on `~wex`).
- **A sibling branch does not travel.** The negative proof: a thread branched on
  `~wex`, one branch forwarded to `~feb`, and the other branch's node is
  *absent* from `~feb`'s tree. Re-proved after the seven review fixes, with a
  new side message added to the unforwarded branch: still absent.
- **The forwarded path verifies end to end** on the receiving ship.

### The malformed-dart vector, and its reversal

- **A malformed `%urmail-chain` used to destroy the next good message.** With
  the wire marcs typed, grubbery's `+hydrate` failed the writer process before
  any nexus code ran and `+rise-wait` consumed the following poke. Reproduced,
  including `strange restart mark` once per malformed poke.
- **It no longer does.** With the marcs as noun passthroughs and the clam in
  `+apply` under `mule`: locally, the malformed poke is refused and the very
  next poke applies; **remotely** — a foreign ship poking the public-granted
  `/main.sig` — the message sent immediately after a malformed noun was applied
  and stored. Zero `strange restart mark`. The remote case is the actual attack
  and it is the one that was run.
- A malformed `%urmail-action` behaves the same: refused, and a following
  `%read` and `%send` both apply.

### Attachments

- **Metadata inside the signature does not break the signature.** A message with
  an attachment delivered `~wex` → `~feb` and rendered `verdict: verified` with
  its `attachments` array present, both read out of the same `unsigned` the
  verdict was computed over.
- **The chain carries no bytes.** `~feb` held the message and an empty
  `mail/blob`.
- **The keen fetch works cross-ship**, answered from `~wex`'s farm at case 1.
- **A blob whose bytes do not hash to the address is discarded.**
- **Farm bindings survive `|suspend` / `|revive`.** `~feb` culled its copy of a
  blob `~wex` had grown before two bounce cycles, then re-fetched it
  successfully. `+republish-all` is insurance against a lost yoke, not routine
  repair — and it does not raise a case by running again.
- **Publishing an already-public blob bricks it, and the gate that prevents that
  was verified** — the case-ladder behaviour was measured on the live pier, not
  inferred from the kernel.
- **Restriction withdraws.** After `%restrict-blob`, a keen for the blob misses.
  The **grant** half did not run: no usergroup exists for it, and the writer
  logged `withdrawn but ungranted` rather than attempting a `make` that would
  crash it. That is the designed behaviour and the limit is real.

### The format refusal — for the pre-branching layout only

- `~feb` was rolled back to the slice-2 overlay, wrote a genuine `%0` grub, and
  was carrying a `%1` grub from an earlier deploy. The frozen (`%2`) code was
  deployed over both.
- **Both grubs survived on disk, both rendered `unreadable`, neither was
  labelled, rejected, counted or relabelled `%forged`.** The reload said nothing
  about either: `/tr/last` still named the pre-upgrade send.
- **Dropped before verification, proven rather than asserted:** a reply naming
  either old message was refused `unknown prev` on both ships — the reader never
  returns them, so their ids cannot resolve.
- **A version-0 `$meta` upgraded in place** in the same reload, which is the
  contrast the design rests on: local state migrates, signed state cannot.

**This transcript predates the branching slice and was produced against the flat
`msg/<slot>` layout.** An old grub met by `+migrate-flat` is not exercised by it,
and that is Gate 4's remaining debt. See `docs/release-plan.md`.

### The web surface

Driven from a real headless browser over CDP against the ships, in the UI slice:

- The inbox lists the real threads on the ship.
- Per-message verdict badges render, including `%forged`.
- Compose, reply and forward work through the UI; a message sent from `~feb`
  appears on `~wex`.
- **The beacon is live and silent on a read-mark** — the loop the design
  refuses to build was checked for, not assumed.
- The served assets are byte-identical to the committed build, and
  `/apps/urmail/` with a trailing slash serves the same shell.
- Unauthenticated, `/apps/urmail` and `/apps/lattice` both answer 403 on both
  ships, while an unbound app answers eyre's own 307 — so the 403s are real
  bindings and not a catch-all.

### Neighbours and health

- **Lattice is unharmed** on both ships throughout: it answers authenticated on
  its own routes, its SPA included, after every urmail deploy.
- CPU after the final round: `~wex` 7.9%, `~feb` 2.9% over multi-day uptimes —
  no crashed-fiber respawn loop, which is the failure mode an absolute-road
  mistake produces.
- Deployed files byte-identical to `HEAD` on both ships, marcs included.

### Tests

`ok=%.y` on both ships, after the final round:

```
-test /=grubbery=/tests/lib/urmail-chain ~     56 OK
-test /=grubbery=/tests/lib/urmail-web   ~     15 OK
```

71 total. Both libs are import-free, which is the only reason `-test` can reach
them at all — see the spec's overlay import rule.

---

## Inspected

- **Jael answers scries only at exactly `now`**, and **`%puby` has no fake-ship

**Live, 2026-09-08, `~martyr-sanryg` (real planet), by the user in the dojo:**

```
> .^(@ud %j /=life=/~zod)
6
> .^((unit [@ud @]) %j /=puby=/~zod/6)
[~ [1 2.224.943.983…]]
```

The `%puby` scry returns a key on a real ship; the annotation `(unit
[crypto-suite=@ud =pass])` matches a live return; crypto-suite `1` is suite
`%b`, the same suite the fake-ship derivation uses, so `com:nu:cric:crypto`
handles real and fake keys identically. **And then the remaining link, same ship, same session:**

```
> .^(@ud %j /=life=/~martyr-sanryg)
1
> =ring .^(@ %j /=vein=/1)
> =pas +:(need .^((unit [@ud @]) %j /=puby=/~martyr-sanryg/1))
> =msg (shaf %urmail (sham 'test'))
> =sig (sigh:as:(nol:nu:cric:crypto ring) msg)
> (safe:as:(com:nu:cric:crypto pas) sig msg)
%.y
```

A real planet's own `%vein` ring signed a `%urmail`-salted digest and the
`pass` from its own Azimuth snapshot verified it, through the same arms
`+sign-with` and `+verify-with` use. **The real-key path is proven end to
end.** This is the single result the fake dev ships could not produce, and it
was the last untested link between a fake-ship `verified` and a network one.

Still true and unchanged: the nexus's own `+peer-pass` `%puby` branch has not
executed inside urmail on a real ship — that happens the first time a real ship
runs the nexus. The crypto beneath it is now known good.

  branch**. Both read off `pkg/arvo/sys/vane/jael.hoon`. The consequences are
  designed around rather than tested: the crypto split into pure gates and thin
  wrappers, and the fake-ship key derivation that mirrors `%deed`.
- **The `%puby` branch itself has never executed.** It is unreachable on a fake
  ship, and every verdict observed anywhere in this record went through the
  fake-ship derivation instead. **Verification against a real Azimuth key has
  not been run on any ship.** This is the largest single gap in the record: it
  is the production path for every verdict this product renders.
- **A nexus cannot create a usergroup.** Read off `lib/nexus.hoon`'s
  `$registry-action`, which carries `%register`, `%deregister`, `%how` and `%gc`
  and no group-lifecycle op; the `%how` refusal for a group with no `who.ships`
  grub *was* observed live, but the conclusion that no op exists is a reading.
- **The JSON renderers after the branching change.** `+serve-thread` and
  `+serve-inbox` were verified by reading rather than running in that slice: the
  authenticated surface needs a login cookie the session could not obtain. They
  share `+collect-slots` / `+collect-node` with the writer, which *was* exercised
  end to end, and the renderers never look at a map's key. The pre-branching
  versions of the same routes were driven live in the UI slice. **A reviewer
  with a web code should load `/apps/urmail` and open a branched thread on both
  ships before this is called done.**
- **The unreadable-count row.** `+collect-unreadable` and the placeholder listing
  row were added in the second review round, and no transcript in this record
  shows one rendered in a browser. That caution turned out to be the right one:
  the count arm answered **structurally zero for every thread on every ship**,
  because its recursion restarted the accumulator at each level, so the
  placeholder row was unreachable and a thread whose every copy is unreadable
  took the 404 branch meant for a thread that is not there. Found and fixed in
  the round this file was written in. **A count that is always zero is worse
  than no count, because every surface above it reads it as good news** — and
  nothing above it was ever driven to notice.
- **`+deadline` is copied from lattice** rather than calling `with-timeout:io`,
  because the signature differs across grubbery generations in this fleet. Read,
  not measured.

---

## Unevidenced

- **The fresh-ship bootstrap.** The spec states that
  `create_folder {path:'/apps', name:'urmail.urmail_app', nexus:'/urmail/app'}`
  over the grubbery MCP installs the nexus, and names two specific failure modes
  for the wrong arguments — an empty node for a bad `nexus`, `inert: no handler`
  for a bad `name`. **No slice report shows either.** Every install in this
  record went through the `lib/root.hoon` row instead. Treat the bootstrap
  paragraph as a hypothesis until someone runs it on a fresh ship.
- **Gate 4 for the shipping build.** See above.
- **Attachments on the web surface.** No route exposes any blob action, so
  nothing about the attachment UX has been verified, because none exists. Being
  built now.
- **The ten unbuilt mail-client features.** Labels, folders, archive,
  mark-unread, sent, drafts, filters, search, pagination, recipient validation:
  specified, not written, not verified.

---

## Known costs, verified as costs

These are not defects to be found later; they were measured and accepted, and
the spec states each one.

- **Depth is quadratic and is not off the read path.** Measured: 200 messages at
  depth 200 cost ~1.8x the same 200 at depth 2. `max-depth` is 64 because of it,
  and a thread genuinely deeper than that accepts nothing further.
- **Writes queue behind the writer, including its fan-out.** Observed: a send
  issued while the writer was fanning out to an unreachable ship took ~8s to
  return. Reads never touch the writer.
- **`+thread-key` and `+serve-inbox` are O(total stored messages).** The same
  scan the design records; the upgrade path in both cases is an index grub.
- **`+ancestor-map` is O(n²) map lookups** on a chain of *n* distinct ids,
  recomputed per delivery. Bounded by `max-chain`.
- **Empty node directories are not reaped.** A cull that empties a node leaves
  the directory; nothing reads it and nothing is lost.
- **The distinct-id cap rejects rather than sheds**, which is a per-thread
  censorship vector requiring no crypto. Deferred deliberately, not overlooked.

---

## Re-running any of this

```
scripts/sync-overlay.sh /home/sneagan/software/wex/grubbery
|commit %grubbery
|suspend %grubbery
|revive %grubbery
-test /=grubbery=/tests/lib/urmail-chain ~
-test /=grubbery=/tests/lib/urmail-web ~
```

The bounce is not optional — a deploy recompiles the nexus but does not respawn
long-lived fibers, which keep running old code silently. Never hotfix one file
through the mount: it commits wholesale from a stale snapshot.

## Staleness rule

This file is rewritten, never patched incrementally. A half-updated record reads
as authoritative and is worse than none, which this project has already learned
once — the version of this file that described the Gall build outlived that
build by three slices.

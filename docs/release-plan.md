# Releasing urmail

How urmail gets from "runs on two fake ships" to "installable from
~ricsul-bilwyt alongside lattice". No production changes are proposed here;
this is the sequence and the gates.

Current as of 2026-09-08, after the branching slice and the final fix round.

## Where it actually stands

**Done and proven.** The signed-chain core: signing with the ship key,
per-message `%verified` / `%unverified` / `%forged`, `[id sig]` anti-shadowing,
content-derived thread identity, the caps, `+prune`, and the tree arms that
make a thread branch. **71 tests** in two import-free overlay libs — 56 on the
chain, 15 on the web decoders — green on both dev ships. The nexus stores and
serves chains, verifies before storing, and accepts a chain from any ship
because signatures are the authority. Attachments are inside the signature and
fetched by keen with no permission needed — the property the migration was for.
Cross-ship delivery works, including the three-party case: a chain authored by
a ship neither party has spoken to still verifies. A forward ships the
root-to-leaf path and **not** the sibling branch, demonstrated negatively on
two ships. The React client runs on the nexus, live over the change beacon.

**Not done.** None of the ten remaining mail-client features — labels, folders,
archive, mark-unread, sent, drafts, filters, search, pagination, recipient
validation — exist on the nexus. The web API cannot express attachments at all:
the writer implements `%fetch-blob`, `%restrict-blob`, `%publish-blob` and files
on `%send`, and no route reaches any of them, so a message carrying a file
renders with no sign of it. **That gap is being closed now, in parallel with
this document.**

**The honest summary:** the hard, unusual part is finished and well tested. The
ordinary mail-client part is mostly unbuilt. That is the opposite of how most
projects arrive at a release, and it means the remaining work is largely
predictable rather than risky.

## Gates

Each must be true before the next phase starts. None is a formality.

### Gate 1 — the format is frozen — DONE

`unsigned` is closed at nine fields: `from`, `life`, `to`, `subj`, `body`,
`body-mime`, `sent`, `prev`, `attachments`. Reply-to, expiry, multi-parent and
a signed BCC set were each considered and rejected, with the reasoning in the
spec rather than in a commit message.

**It broke twice getting there**, and both breaks are recorded as breaks:

1. `%0` → `%1`, when `attachments` went inside the signature.
2. `%1` → `%2`, when `body-mime` did.

`$stored-msg` is at version 2 and versions 0 and 1 are **refused, not
migrated**. There is no migration for a signed format: `msg-id` and the
signature both cover the shape, so rewriting an old message into the new shape
produces a message whose signature no longer matches its own contents, and every
peer reads that as forged. Manufacturing forgeries out of genuine mail is the
worst failure this system has, so an old grub is dropped before verification and
renders `unreadable` instead.

Both breaks cost nothing because the only mail in those formats was ours. **A
third break after anyone real uses this would cost them everything**, which is
what the freeze exists to prevent. Nothing after this may change `unsigned`.

### Gate 2 — feature parity with what a mail client is

The ten remaining features, all of which are tree walks on this architecture
rather than the hand-rolled maps the old design was going to need. The designs
are in the spec, under `# Specified but unbuilt`.

| Feature | Shape on the tree |
|---|---|
| Labels | `meta` carries them; a label view is a walk |
| Folders | views over labels, not a second taxonomy |
| Archive | `meta` flag, already present and defaulted; new mail un-archives, or mail vanishes |
| Mark unread | inverse of the existing read action |
| Sent | threads containing a message we authored |
| Drafts | `/mail/draft/<id>`, unsigned, never renderable as a message |
| Filters | `/mail/rule/<id>`, applied after verification, may label and archive, may not delete or mark read |
| Search | linear sweep, includes forged messages, labels them |
| Pagination | bounded tree listing plus a total |
| Recipient validation | `@p` parse in the UI; the nexus keeps its own |

Attachments are done on the ship. Attachments are **not** done on the web
surface — see Gate 3.

### Gate 3 — a UI on the nexus — DONE, with one gap

Two routes were open, and lattice runs both:

- **Serve the React app as grubs**, the way lattice serves `ui-app/`.
- **Server-rendered views with per-request fibers**, the way lattice serves
  `/ui/views/page.html`. More native, no client build, but discards working
  code.

The first was taken, as recommended: the client already renders per-message
verdict badges, honest copy counts, editable reply recipients and forward, all
of which took review rounds to get right and none of which was worth rebuilding
to be idiomatic. What changed was the transport under it. The route surface is
in the spec, under `# The web surface`; live updates ride grubbery's keep-SSE
over the nexus's change beacon rather than polling.

This gate covers the five things a client cannot work without — listing, thread,
send, mark-read, delete — and those are live and driven from a browser against
both ships.

**The gap: the API cannot express attachments.** `POST /api/send` sends
`files=~` unconditionally and there is no route for fetch, restrict or publish.
The nexus half has been working since the attachments slice; the surface over it
does not exist. Being fixed in parallel with this document, and this gate is not
finished until it is.

### Gate 4 — the format refusal is demonstrated on the shipping build

**Partly paid, and not for the build that would ship.**

What exists: during the attachments follow-up round, `~feb` was rolled back to
the slice-2 overlay, made to write a genuine `%0` grub, and then upgraded to the
frozen code over it, while still carrying a `%1` grub from an earlier deploy.
Both rendered `unreadable`, neither was labelled or rejected or counted, a reply
naming either was refused with `unknown prev`, and a version-0 `$meta` upgraded
in place in the same reload. That transcript is real and it is the strongest
evidence this project has for the most consequential behavior in the build.

What it does not cover: it was produced **before the branching slice**, against
the flat `msg/<slot>` layout. The shipping build stores a message under its
ancestry and runs `+migrate-flat` at writer rise. The migration was demonstrated
separately, on live threads on both ships, and it is idempotent — but *an old
grub met by the migration* is a case neither transcript exercises, and it is
exactly where the two mechanisms interact: `+migrate-flat` re-places what
`+read-stored` returned, and `+read-stored` returns nothing for a `%0` or `%1`
grub.

What it would take, and it is an afternoon: roll one dev ship back to `c1b7ccf`
or earlier, write a `%0` and a `%1` grub with the code that produced them,
deploy the current overlay over the top, and record — verbatim — the writer's
trace at rise, the tree after migration, both grubs still present and both
rendering `unreadable`, the inbox listing's unreadable count, and a reply naming
each refused with `unknown prev`. A reading is not evidence, and this project has
already shipped a test that passed the bug it existed to catch.

### Gate 5 — the distribution change

**Status, 2026-09-08.** Rehearsed on `~feb`: launcher back (`/apps/grubbery`,
14 tiles, lattice among them from its own `tile.json`), docket reads Grubbery
1.1.0, lattice and urmail both still bound, memory store reads. Commit
`5ea5700` on **`dist/launcher-restore`**, deliberately not `dist/lattice-only`,
because another session is committing to that branch with production as its
next step. Merge `--ff-only` when the launcher is meant to ship.

Two things the rehearsal did **not** prove:

- **`~feb` is the wrong shape.** It runs full upstream `7117ae1` plus urmail —
  the app tier present, no lattice row in `root.hoon`. Production has the app
  tier *absent*. `~wex` carries the dist-shaped `root.hoon`, so the rehearsal
  that matters is on `~wex`, after the features work there lands.
- `tiles.hoon` came from upstream `d839ede`, the last pre-split revision — at
  `7117ae1` the file is a data store and the launcher UI is `shell.hoon`, eleven
  files needing deleted dependencies. Pre-split tiles is one self-contained file
  that already reads app-advertised `tile.json`. Its notifications bell hits
  nexuses the dist desk deleted: permanently grey on production, invisible on
  `~feb`. ~60 lines to strip; decision pending.

Still open under this gate: urmail's sources and `root.hoon` row are not
vendored into the dist desk. The docket's `base` also changed
`lattice` → `grubbery`, which was not in the four listed changes and is correct.

Untouched. urmail cannot ship until grubbery's launcher comes back, because
today `~ricsul-bilwyt` distributes a grubbery whose app tier was deliberately
stripped: lattice is the only app and it *is* the product, with the docket
pointing Landscape straight at `/apps/lattice`.

Four changes on `dist/lattice-only`:

1. Restore `gub/nex/tiles.hoon` from upstream `7117ae1` — deleted in `1ad7a5e`.
2. Restore its `%fall` row in `root.hoon`.
3. Give urmail a `tile.json` in `on-load`; lattice already writes one, and its
   own comment notes the launcher lists only apps that carry one.
4. Rewrite the docket: title Lattice → Grubbery, `site` from `/apps/lattice`
   to the launcher.

Step 4 is visible on every installed ship. The Landscape tile stops saying
Lattice, which is a change to lattice's users, not just ours.

There is a fifth thing this gate has to answer that is not on the list:
**urmail's own install row lives in grubbery's `lib/root.hoon`, outside this
repo, and a grubbery pull reverts it.** `sync-overlay.sh` greps for the row and
prints it when it is missing; that is a check, not a fix. Whatever carries
lattice's row through a distribution has to carry urmail's.

## The real-key path — proven

Every `verified` verdict produced during development came from the fake-ship
key derivation, because both dev ships are fake and `+peer-pass` short-circuits
before the `%puby` scry on a fake ship. The whole-product review called this
the largest gap in the product: the path that verifies a *real* planet had
never executed.

Closed on 2026-09-08 on `~martyr-sanryg`, by the user in the dojo:

- `%puby` returns a key on a real ship (`~zod`, life 6, crypto-suite 1 = `%b`,
  the same suite the fake derivation uses). The annotation read off jael's
  source matches a live return.
- The ship's own `%vein` ring signed a `%urmail`-salted digest and the pass from
  its own Azimuth snapshot verified it, through the same arms `+sign-with` and
  `+verify-with` use. `%.y`.

Transcripts in `docs/verification.md`. What remains is not a gate: the nexus's
own `+peer-pass` `%puby` branch executes for the first time on the first real
ship that runs urmail. The crypto beneath it is now known good.

## Sequence

1. ~~Finish the attachment fix wave.~~ Done.
2. ~~Freeze `unsigned`.~~ Done. Nothing after this may change it.
3. ~~Repoint the client at the nexus.~~ Done.
4. Close the attachment gap in the web API (in flight).
5. Produce the format-refusal transcript against the shipping build (Gate 4).
6. Build the ten features on the tree (Gate 2).
7. Rehearse the distribution change on `~wex`, then `~feb` (Gate 5).
8. Release.

Steps 5 and 6 are independent of 7 and can run in parallel.

## Releasing to ~ricsul-bilwyt

Production, the shared memory store, and a public publisher that
`~martyr-sanryg` tracks through kiln sync — so a bad desk propagates to a real
planet without anyone acting. Every step is gated on an explicit go.

- Back up the mount first. The 2026-09-02 deploy did; the July ball reset is
  why.
- Rehearse the whole change on `~wex`, then `~feb`, before ricsul sees it.
- Deletions from ricsul's mount never reach clay. Any file removal needs a
  hood `%info` line pasted into the dojo by hand, one commit per line.
- `|public %grubbery` is not a listing toggle; without it a fresh installer
  hangs with no error.
- A desk update does not respawn long-lived fibers. Bounce with
  `|suspend %grubbery` then `|revive %grubbery` — never `|exit`.

Rollback is `git revert` on the dist branch plus a redeploy: the docket and the
`root.hoon` rows are the whole change, and neither touches stored mail. Mail
already delivered stays readable, because nothing in the distribution change
alters the chain format.

## What could still go wrong

**The format is wrong and we find out late.** Gate 1 is closed, which means this
is now a decision that has been made rather than a risk being managed. There is
no migration path for a signed format. If something else turns out to belong
inside a signature, the answer is a new application, not a new version.

**The refusal misbehaves on a real upgrade.** Gate 4 is why. The failure mode is
not subtle — mail that reads `unreadable` when it should read, or worse, mail
relabelled — but it has not been exercised against the layout that would ship.

**Restriction is misunderstood.** Restricting an attachment withdraws our copy;
it does not recall bytes anyone already fetched, and it never will. If the UI
presents it as permission, users will trust it for something it cannot do. The
attachment surface being built now is the first place that lie can be told.

**A restricted blob is withdrawn but ungranted.** A nexus cannot create a
usergroup, so the peek grant that would serve named ships is skipped, loudly,
when the group does not exist. Restriction currently means withdrawal and
nothing more.

**Two ships on different grubbery generations.** `~wex` and `~feb` already
print delivery timeouts on correct deliveries for this reason. Installers on
older grubbery will do the same.

**The launcher change lands on lattice's users.** They installed something
called Lattice and will find something called Grubbery with Lattice inside it.
That is the intent, but it is worth saying out loud before it ships rather than
after.

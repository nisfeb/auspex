# Releasing urmail

How urmail gets from "runs on two fake ships" to "installable from
~ricsul-bilwyt alongside lattice". No production changes are proposed here;
this is the sequence and the gates.

## Where it actually stands

**Done and proven.** The signed-chain core: signing with the ship key,
per-message `%verified` / `%unverified` / `%forged`, `[id sig]` anti-shadowing,
content-derived thread identity, the caps, `+prune`. 39 tests, green on both
ships. The nexus stores and serves chains, verifies before storing, and accepts
a chain from any ship because signatures are the authority. Attachments are
inside the signature, fetched by keen with no permission needed — the property
the migration was for. Cross-ship delivery works, including the three-party
case: a chain authored by a ship neither party has spoken to still verifies.

**Not done.** There is no UI on the nexus. The React client that exists talks
to the Gall agent's scries and would have to be repointed. None of the eleven
mail-client features — labels, folders, archive, mark-unread, drafts, filters,
search, pagination, sent, recipient validation — exist on the nexus. The
attachment fix wave is in flight. The chain format has broken once already.

**The honest summary:** the hard, unusual part is finished and well tested.
The ordinary mail-client part is mostly unbuilt. That is the opposite of how
most projects arrive at a release, and it means the remaining work is largely
predictable rather than risky.

## Gates

Each must be true before the next phase starts. None is a formality.

### Gate 1 — the format is frozen

The chain format broke when attachments were added: `unsigned` gained a field,
every prior signature died, and old grubs are refused as unreadable. That was
the correct handling and it cost nothing, because the only mail in that format
was ours.

**It cannot happen again after anyone real uses this.** A format break is not a
migration you can write, because a signature covers a shape; rewriting the
shape produces a message whose signature no longer matches, and every peer
reads that as forged. Manufacturing forgeries out of genuine mail is the worst
failure this system has.

So: freeze `unsigned` before release, or accept that early adopters lose
everything on the next change. Freezing means deciding now whether anything
else belongs inside the signature — read receipts, expiry, a reply-to, a
thread subject distinct from the message subject. Adding any of them later is
a break.

### Gate 2 — feature parity with what a mail client is

The eleven features, all of which are tree walks on this architecture rather
than the hand-rolled maps the Gall design was going to need:

| Feature | Shape on the tree |
|---|---|
| Labels | `meta` carries them; a label view is a walk |
| Folders | views over labels, not a second taxonomy |
| Archive | `meta` flag; new mail un-archives, or mail vanishes |
| Mark unread | inverse of the existing read action |
| Sent | threads containing a message we authored |
| Drafts | `/mail/draft/<id>`, unsigned, never renderable as a message |
| Filters | applied after verification, may label and archive, may not delete or mark read |
| Search | linear sweep, includes forged messages, labels them |
| Pagination | bounded tree listing plus a total |
| Recipient validation | `@p` parse in the UI; the nexus keeps its own |
| Attachments | done |

### Gate 3 — a UI on the nexus

The largest unbuilt piece. Two routes, and lattice runs both:

- **Serve the React app as grubs**, the way lattice serves `ui-app/`. The
  client exists, works, and has been reviewed; it would be repointed from the
  Gall scries to the nexus routes. Fastest, and keeps the reviewed UI.
- **Server-rendered views with per-request fibers**, the way lattice serves
  `/ui/views/page.html`. More native, no client build, but discards working
  code.

Recommendation: repoint the existing client. It already renders per-message
verdict badges, honest copy counts, editable reply recipients and forward —
all of which took review rounds to get right and none of which is worth
rebuilding to be idiomatic.

### Gate 4 — the format refusal is demonstrated, not read

The refusal of old-format grubs is the most consequential behavior in the
current build and it has never been exercised on a live ship: the old grubs
were deleted before the deploy that would have tested them. A reading is not
evidence, and this project has already shipped a test that passed the bug it
existed to catch. Produce the transcript before release.

### Gate 5 — the distribution change

urmail cannot ship until grubbery's launcher comes back, because today
`~ricsul-bilwyt` distributes a grubbery whose app tier was deliberately
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

## Sequence

1. Finish the attachment fix wave and produce the format-refusal transcript.
2. Freeze `unsigned`. Decide what else belongs inside a signature; add it now
   or never.
3. Build the eleven features on the tree.
4. Repoint the client at the nexus.
5. Rehearse the distribution change on `~wex`, then `~feb`.
6. Release.

Phases 2 and 3 are independent of 5 and can run in parallel. Nothing after
step 2 may change `unsigned`.

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

**The format is wrong and we find out late.** Mitigated only by gate 1. There
is no migration path for a signed format, so this is a decision, not a risk to
manage.

**Restriction is misunderstood.** Restricting an attachment withdraws our copy;
it does not recall bytes anyone already fetched, and it never will. If the UI
presents it as permission, users will trust it for something it cannot do.

**Two ships on different grubbery generations.** `~wex` and `~feb` already
print delivery timeouts on correct deliveries for this reason. Installers on
older grubbery will do the same.

**The launcher change lands on lattice's users.** They installed something
called Lattice and will find something called Grubbery with Lattice inside it.
That is the intent, but it is worth saying out loud before it ships rather than
after.

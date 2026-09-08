# urmail — design

Date: 2026-09-07
Status: approved, ready for implementation planning

## What this is

An Urbit-native mail application. It gives you the UX of email — an inbox,
threads, compose, reply, forward — without SMTP, IMAP, MIME, or any of the
machinery that makes email what it is.

It does not bridge to internet email. Both ends run `%urmail`.

## Why it is not a chat app

The unit of the system is a **signed chain**: an append-only list of messages,
each one signed by the ship that wrote it. A chain is self-contained and
portable. You can hand it to a ship that was never part of the conversation and
that ship can verify, on its own, who wrote every message in it.

Forwarding is therefore not quoting. Forwarding transfers evidence.

## Data model

The chain is the mark. One file, `mar/urmail/chain.hoon`, is the entire wire
format and the entire portable artifact.

```hoon
+$  msg-id  @uv                       ::  (sham unsigned)
::
+$  unsigned
  $:  from=ship
      life=@ud                        ::  key life the signature was made under
      to=(set ship)
      subj=@t
      body=@t
      sent=@da
      prev=(unit msg-id)              ::  parent message in this chain
  ==
::
+$  msg    [=unsigned sig=@ux]
+$  chain  (list msg)                 ::  root first, append only
```

`msg-id` is `(sham unsigned)`. It covers every field a signature covers, so an
id and a signature agree by construction.

`life` travels with the message because signatures must outlive key rotation. A
message signed under life 3 stays verifiable after the sender rotates to life 4,
because the verifier looks up the key for the life the message names.

`prev` is what makes a flat list a chain. A reply points at the message it
answers; a forward points into the chain it carries.

### Marks

- `mar/urmail/chain.hoon` — `+grab` from `%noun` and `%json`, `+grow` to
  `%json`, `+noun`.
- `mar/urmail/action.hoon` — the poke the frontend sends.

The JSON forms exist so the web UI can read chains without a second
representation. The noun form is what crosses Ames.

## Signing

Userspace can sign with the ship's real networking key. Confirmed against
`pkg/arvo/sys/vane/jael.hoon` in the arvo source.

```hoon
::  our private key ring for a given life
=/  ring  .^(ring %j /(scot %p our.bowl)/vein/(scot %da now.bowl)/(scot %ud life))
=/  cor   (nol:nu:cric:crypto ring)
=/  sig   (sigh:as:cor (shaf %urmail (sham unsigned)))
```

The `%vein` scry is gated on the requesting ship being `our`, which a local Gall
agent always is.

### Domain separation is mandatory

The signature is over `(shaf %urmail (sham unsigned))`, never over raw message
bytes. The ship's networking key also signs Ames packets and attestations. A
signature produced over attacker-chosen bytes with that key is a forgery
primitive if the byte space overlaps. The `%urmail` tag makes the preimage space
disjoint from every other use of the key.

This is not optional and it is not a performance question.

## Verification

```hoon
=/  pub  .^(  (unit [crypto-suite=@ud =pass])
              %j
              /(scot %p our.bowl)/puby/(scot %da now.bowl)/(scot %p from)/(scot %ud life)
          ==)
?~  pub  %unverified
?:  (safe:as:(com:nu:cric:crypto pass.u.pub) sig (shaf %urmail (sham unsigned)))
  %verified
%forged
```

`%puby` is the unitized public-key scry. It returns `~` for a ship absent from
the local Azimuth snapshot rather than blocking. A blocking scry inside a Gall
agent stalls the agent, so the unitized variant is the only safe choice here.
Do not reach for `%deed`.

The product type follows `keys=(map life [crypto-suite=@ud =pass])` in `+point`
(`sys/lull.hoon`). It is read off the source and has not been run.

### Two constraints the jael source imposes

**Jael answers scries only at exactly `now`.** Its scry arm opens with
`?.  &(=(lot [%$ %da now]) =([~ ~] lyc))  ~` — a request at any other date
returns `~`, which blocks. Nothing may scry jael with a stored or hardcoded
date, and no test can scry jael at all, since a test arm has no bowl.

Therefore the crypto splits in two: **pure gates** that take keys as arguments
and do all the signing, verifying, and digesting, and **thin scry wrappers**
that only the agent calls, with a live `now`. Everything worth testing lives on
the pure side.

**Jael's `%puby` has no fake-ship branch.** `%deed` special-cases fake ships by
deriving a keypair from the `@p` — `(pit:nu:cric:crypto 512 who %b ~)` — but
`%puby` reads `pos.zim` directly and returns `~` for any ship the fake ship has
no Azimuth snapshot of, which on a fake ship is essentially every ship. Left
alone, every message in development would read `%unverified` and the dev loop
would never exercise verification.

The key lookup therefore checks `.^(? %j /(scot %p our)/fake/(scot %da now))`
first and, on a fake ship, derives the peer's key the same way `%deed` does.
This mirrors jael's own behavior rather than inventing a development mode.

It also makes the strongest test cheap: on a fake ship every ship's keypair is
derivable from its `@p`, so a test can forge a genuine signature as
`~sampel-palnet`, put it in a chain, and verify it — the third-party forward
case, with no network and no second ship.

### Verification labels, it does not reject

Every message carries one of three verdicts:

- `%verified` — signature checks against the sender's registered key.
- `%unverified` — no key available for that ship. Moons and comets land here.
- `%forged` — a key was available and the signature failed against it.

`%forged` messages are stored and displayed as forged. They are evidence, and
deleting evidence is the wrong instinct. They are never counted as unread and
never sort into the normal inbox flow.

### The moon and comet gap

Third parties cannot verify moons or comets, and this is a property of Azimuth,
not a gap in this design.

`%earl` hands out a moon's key only to that moon's parent. `%deed` handles
comets only when the comet is asking about itself. So mail from
`~mister-botter-dozzod-nisfeb` verifies for `~nisfeb` and for nobody else.

v1 labels these `%unverified` and moves on. Signing still happens with whatever
key the ship holds, so the signatures are already sitting in the chain the day
either fix lands:

- Comets are self-signing addresses — the `@p` is a hash of the key — so a
  comet's signature is verifiable with no lookup at all, given the code to
  derive it.
- Moons need their parent's attestation to travel inside the chain.

Neither changes the mark. Both are strictly additive.

## Agent state

```hoon
+$  thread
  $:  =chain
      participants=(set ship)         ::  union of from and to across the chain
      last=@da                        ::  sent of the newest message
  ==
::
+$  state-0
  $:  %0
      threads=(map thread-id thread)  ::  thread-id is the root msg-id
      inbox=(list thread-id)          ::  newest first
      read=(set msg-id)
  ==
```

A thread is identified by the `msg-id` of its root. Two ships holding the same
conversation agree on the thread id without coordinating, because the root
message is byte-identical for both.

`inbox` is a maintained ordering rather than a sort at read time. It is the
only thing the inbox view needs and it is cheap to keep correct on insert.

## Wire protocol

One poke covers composing, replying, and forwarding:

```hoon
[%send to=(set ship) subj=@t body=@t prev=(unit msg-id)]
```

- **Compose** — `prev` is `~`. A new chain begins.
- **Reply** — `prev` points at a message in a chain you hold. `to` is usually
  the existing participants.
- **Forward** — `prev` points at a message in a chain you hold. `to` is someone
  new. There is no separate forward path; a forward is a reply addressed
  elsewhere, and the chain it carries is the payload.

`prev` names a message, not a thread, and that is sufficient: `msg-id` is a hash
over the message's full contents, so it identifies exactly one message and
therefore exactly one chain. The agent resolves `prev` to its containing thread
by lookup. A `prev` the agent does not hold is rejected.

On `%send` the agent builds the `unsigned`, signs it, appends to the local
thread, and pokes each recipient's `%urmail` with:

```hoon
[%urmail-chain =chain]
```

The **whole chain** ships, not just the new message. That is the entire point of
the design. A recipient added at message forty receives messages one through
forty, each independently verifiable.

### Receiving

On `%deliver` the agent:

1. Verifies every message in the chain and records a verdict per message.
2. Finds the root `msg-id` and merges into `threads` under that key.
3. Deduplicates by `msg-id`. Receiving the same chain twice is a no-op.
4. Reorders `inbox` if the thread's `last` advanced.

`src.bowl` is deliberately **not** required to be a participant. Anyone may hand
you a chain. The signatures are the authority, not the courier. This is what
makes chains portable, and it is the property that separates this from every
chat app.

There are no subscriptions between ships. Delivery is one poke per recipient.
Ames handles retry and ordering.

### Trust boundary

`%deliver` is the only externally reachable poke and it accepts input from any
ship on the network. It must:

- Verify every signature before storing anything.
- Cap chain length and body size on the **incoming** chain, and reject rather
  than truncate. A malformed or oversized input is not partially trustworthy.

  This rule governs input validation only. It must **not** be applied to
  state-capacity pruning of the merged result, where the excess may come
  entirely from previously stored attacker junk while the incoming chain is
  wholly legitimate. Rejecting there is a censorship primitive: an attacker who
  lands a few forged copies of a message first makes every later legitimate
  poke exceed the bound and be rejected forever, which reinstates at the state
  layer exactly the shadowing `+merge` exists to prevent. Merged-state bounds
  shed the excess instead, and never shed a `%verified` copy — anti-shadowing
  enforced where the verdicts are known.

  One merged-state bound still rejects rather than sheds: the cap on distinct
  message ids per thread. Shedding there is genuinely harder, because dropping
  a non-root id orphans the `prev` pointers of later messages. The cost of that
  exemption is real and is not hidden: anyone who knows a thread's root content
  can poke enough distinct junk messages — **no signatures required**, since
  forged messages are stored and counted — to pin the thread at the cap, after
  which every legitimate message is rejected. One poke, no crypto, permanent
  per-thread censorship. The fix is to shed distinct ids too, preferring
  `%verified`, and it is deferred rather than justified.
- Never let an incoming chain overwrite messages already held under the same
  `msg-id`, since identical ids imply identical bytes and a conflict means an
  attack.

Storage is unbounded by design in v1 — see Deliberate limits.

## Frontend

React, TypeScript, Vite, Tailwind. Three panes, Gmail's layout: thread list,
thread view, compose.

- `GET /x/inbox` — thread ids, subjects, participants, unread flags, `last`.
- `GET /x/thread/<id>` — a full chain with per-message verdicts.
- SSE on the agent's update path for live inbox changes.
- Sends go through `/~/channel` as `%urmail-action` pokes.

Verification state is rendered per message, not per thread. A thread with one
`%unverified` message in it is not an unverified thread.

## Testing

Desk tests, covering the logic that can actually be wrong:

1. Sign then verify round-trips for our own ship.
2. A forward preserves every prior signature — verify the whole carried chain
   after a forward, not just the new message.
3. A tampered body fails verification. Mutate `body` in a stored `msg` and
   confirm the verdict flips to `%forged`.
4. A tampered `life` fails verification.
5. Double delivery of the same chain leaves state unchanged.
6. A chain arriving from a non-participant ship is accepted and verifies.

Tests 2, 3, and 6 are the ones that matter. They are the three claims the design
makes that a chat app cannot make.

## Development

Fake `~zod` at `/home/sneagan/software/zod`. The loop is mount the desk,
`command cp -f` the sources onto the mounted path, commit. Committing an
installed desk reloads the agent.

Never `~ricsul-bilwyt`. That ship is the memory store.

Fake ships derive deterministic keys, so signing and verification are
self-consistent on `~zod` and the dev loop exercises the real crypto path.

## Deliberate limits

**Every send ships the full chain.** A two-hundred message thread costs two
hundred messages of bytes on every reply. Acceptable for text. The upgrade, when
it is needed, is a `have=(set msg-id)` handshake so the sender transmits only
the difference. Not v1.

**Storage is unbounded.** Nothing prunes, nothing expires, and a hostile ship
can grow your state by poking you chains. v1 caps individual chain and body size
and otherwise accepts this. Rate limiting per source ship is the next step if it
becomes real.

**No delivery receipts.** A send that Ames cannot deliver fails silently from
the UI's point of view.

## Out of scope for v1

Labels, archive, search, attachments, drafts, contacts, filters, spam handling,
Thunderbird integration, and any bridge to internet email.

Thunderbird in particular is explicitly not designed for. If it happens it is an
adapter written against whatever API exists then.

---

# v2 — the mail client around the provenance layer

v1 proved the hard part: signed chains, portable provenance, per-message
verdicts. What it did not do is behave like a mail client. This section
specifies eleven additions. None of them may weaken the v1 guarantees, and
two of them touch signed data and therefore get the same care as the crypto.

## The rule that governs all of it

**Nothing here changes what is signed except attachments, and attachments are
signed.** `unsigned` gains one field, `attachments`, carrying metadata and a
content hash. Everything else — labels, archive state, read state, drafts,
filters — is *local* state about a message, never part of it. Two ships can
disagree about whether a thread is archived; they can never disagree about
who signed it.

## Attachments

The chain travels whole on every send, so bytes must not live in the chain.

```hoon
+$  attachment
  $:  name=@t          ::  original filename
      size=@ud         ::  bytes
      mime=@t          ::  content type
      hash=@uv         ::  (sham contents)
  ==
```

`attachments=(list attachment)` goes **inside `unsigned`**, so it is covered by
the signature and by `msg-id`. Swapping a file breaks the signature. The bytes
live in a separate store:

```hoon
blobs=(map @uv @)    ::  hash to contents
```

- Sending stores the bytes locally, puts the hash in the message, signs, ships
  the chain as before. The chain grows by ~100 bytes per attachment regardless
  of file size.
- Receiving stores the chain immediately. Bytes are **not** pushed.
- Opening a message with an attachment the ship lacks pokes the sender with
  `[%want-blob hash=@uv]`; they answer with `[%blob hash=@uv data=@]`.
- **A received blob is accepted only if `(sham data)` equals the hash it was
  requested under.** A ship that answers with different bytes is ignored. This
  is the same discipline as message verification: the hash is the authority,
  not the sender.
- `max-blob` caps a single attachment. `max-blobs` caps total blob storage;
  when full, the oldest unreferenced blobs are evicted. Blobs are a cache —
  losing one loses a file, never a message or a signature.
- A blob request is answerable by **anyone holding the bytes**, not only the
  author, exactly as chains are forwardable by anyone. The hash makes the
  courier irrelevant.

## Labels, and folders as views over them

Labels are local, per-thread, and never travel:

```hoon
labels=(map thread-id (set @tas))
```

A **folder** is not a separate concept. The sidebar shows views:

| View | Definition |
|---|---|
| Inbox | not archived, and we are a participant |
| Sent | any message in the thread is authored by us |
| Archived | in `archived` |
| Drafts | from `drafts` |
| `<label>` | has that label |

That is Gmail's model and it avoids a second taxonomy that would inevitably
disagree with the first.

## Archive

```hoon
archived=(set thread-id)
```

Archiving removes a thread from the Inbox view only. It is not deletion, it
does not touch the chain, and a new message arriving in an archived thread
**un-archives it** — otherwise mail silently disappears.

## Read and unread

`read` already exists. v2 adds the inverse action so a user can mark a thread
unread again. Forged messages continue never to count toward unread.

## Drafts

```hoon
+$  draft  [id=@uv to=(set ship) subj=@t body=@t prev=(unit msg-id) at=@da]
drafts=(map @uv draft)
```

Drafts are local and unsigned — a draft is not a message and must never be
mistaken for one. Sending a draft signs it at that moment and deletes the
draft. The UI saves on a debounce and on close.

## Filters

```hoon
+$  rule
  $:  id=@uv
      from=(unit ship)      ::  match sender
      subject=(unit @t)     ::  substring match
      add=(set @tas)        ::  labels to apply
      archive=?             ::  skip the inbox
  ==
rules=(list rule)
```

Applied in `+receive` **after verification**, never before — a filter must not
be able to suppress a `%forged` message, since that would let an attacker who
learns your rules hide evidence. Filters may add labels and archive; they may
not delete, and they may not mark read.

## Search

Substring match over subject, body and sender across stored threads, computed
on demand. No index in v1: state is capped at `max-threads`, and a linear scan
over that is acceptable and honest. Search covers `%forged` messages too and
labels them in results — hiding them would be the same mistake as filtering
them.

## Pagination

`/x/inbox` takes an offset and a limit. The agent returns a page plus a total,
so the UI can render controls without fetching everything. Views other than
Inbox paginate identically.

## Recipient validation

`@p` parsing happens in the UI before the poke, so a typo is caught at the
keystroke rather than surfacing as a mark-parse failure with no explanation.
The agent keeps its own validation — the UI is a convenience, not the boundary.

## What v2 still does not do

Rich text, threading collapse, keyboard shortcuts, contacts, spam
classification, delivery receipts, and any bridge to internet email.

---

# v3 — urmail as a grubbery nexus

v1 and v2 assume a Gall agent. This section replaces that assumption. urmail
becomes a **grubbery nexus** distributed as an overlay into the `%grubbery`
desk, the same way lattice is. The signed-chain guarantees do not change; where
they are stated above, they still bind.

## Why the tree, and what it replaces

v2 specified labels as `(map thread-id (set @tas))`, archive as a `(set
thread-id)`, drafts as a `(map @uv draft)`, and a bespoke `%want-blob` /
`%blob` poke protocol for attachments. Every one of those is a tree hand-rolled
inside a map, or a platform feature reinvented.

Lattice's own header states the principle: *"pub and know are the SAME kind of
grub. They differ only in permission... The public/private split is a weir
concern, not a schema split."* The same holds here. A label is not a field on a
thread; it is where the thread is. An attachment is not a payload; it is a
grub with a weir on it.

## The tree

```
/main.sig                       the write fiber; serialises every mutation
/mail/thread/<tid>/msg/<n>      one signed message per grub (noun marc)
/mail/thread/<tid>/meta         local state: read, archived, labels
/mail/blob/<hash>               attachment bytes, weir-gated
/mail/draft/<id>                unsigned drafts
/mail/rule/<id>                 filters
/mail/idx                       derived: inbox order, search terms
/ui/main.sig                    binds /apps/urmail
/ui/requests/<id>               one ephemeral fiber per HTTP request
/ui/views/*.html                server-rendered pages
```

Views are walks over this tree, not stored sets: Inbox is `meta` without
`archived`, Sent is threads containing a message we authored, a label is the
threads whose `meta` carries it. Pagination is a bounded tree listing. Search
is a sweep, the same honest linear scan v2 specified.

## Attachments over mesa

`/mail/blob/<hash>` holds the bytes. The message carries only `name`, `size`,
`mime` and `hash`, inside `unsigned`, therefore signed.

The fetch is **keen**, not a poke protocol. Per the mesa work already done on
lattice, the keen is the kernel scry farm and is the *only permissionless
channel* — peeks and keeps are both weir-gated, and a cross-ship peek between
un-granted peers hangs rather than failing. That asymmetry is exactly what
urmail wants:

- **Blobs the author has made public** are keenable by anyone holding the hash,
  which matches "the hash is the authority, the courier is irrelevant." Any
  ship holding the bytes can serve them; the hash proves them.
- **Blobs the author has restricted** are weir-gated, granting named ships. This
  is per-attachment permission, which v2 had no answer for at all.

A blob whose contents do not hash to the path it was fetched from is discarded
without comment. Blobs remain a cache: losing one loses a file, never a message
and never a signature.

## Constraints this platform imposes

These are not style notes. Each has cost real debugging time on lattice and is
silent at the point of failure.

1. **Every blot needs a marc.** A poke to a blot with no marc parks its dart
   silently and hangs the poking fiber forever, printing nothing. Every path
   above ships a marc under `mar/urmail/`.
2. **Persistent-state marcs are noun passthroughs.** A marc written as
   `|_ x=type:lib` re-validates every stored grub against the live type on
   read, so changing the type booms every persisted grub and readers fall to
   bunt defaults. Message grubs carry a version and the reader upgrades in
   place. This is not optional for mail.
3. **Every persistent path needs a covering `%fall` row in `on-load`.** `spin`
   rebuilds the bole from scratch and drops anything uncovered. An uncovered
   path is lost mail.
4. **Long-lived fibers use absolute roads.** A depth-relative road called from
   the wrong depth climbs past the nexus root and crashes the fiber; crashed
   sig fibers respawn, so one bad road becomes an infinite crash loop at 100%
   CPU.
5. **No `$` with arguments inside a `;<` continuation** — it cannot find the
   trap. Recurse by arm name.
6. **Deploys bounce.** Pushing source recompiles the nexus but does not respawn
   long-lived fibers; they keep running old code silently. Every deploy is
   `|suspend %grubbery` then `|revive %grubbery`.
7. **Never hotfix a single file through the mount.** The mount is a stale
   snapshot and commits wholesale, reverting every file changed since the last
   sync. Deploy the full overlay or nothing.

## The writer, and the change beacon

`/main.sig` is a single long-lived fiber that serialises every mutation, the
shape lattice uses to avoid index races: rise, then loop on `take-poke`, apply,
bump, recurse. Every write goes through it. Nothing else mutates the tree.

After each applied action the writer bumps a change beacon so open readers live-
reload. **Marking a message read must not bump it.** Lattice learned this with
page history: every view recorded a visit, every visit bumped the beacon, and
every open reader reloaded — a reload storm produced by nothing a reader could
see. Read state is not content. In urmail the beacon bumps for new mail, sends,
deletes, label and archive changes; never for read-marks.

## Which overlay libs may import, and what it costs

The overlay's `lib/` is rsynced to **both** `gub/lib` and the desk's `/lib`.
Those two build with different runes — the nexus side uses `/<`, ford on the
desk side does not understand it — so a lib's imports decide where it can be
built:

- **Import-free libs build in both**, and are therefore the only ones
  `-test /=grubbery=/tests/lib/... ~` can reach. Lattice's own libs are mostly
  import-free for exactly this reason.
- **Libs using `/<` build only from the nexus.** They are still copied to the
  desk `/lib` but never built there, so nothing complains. They cannot be unit
  tested.

The rule that follows: **anything worth testing goes in an import-free lib, and
the nexus glue may import freely.** That is the same discipline that kept the
v1 core free of scries and made this port cheap — logic in testable pure files,
platform coupling in a thin layer above it. Keep it.

`lib/urmail-chain.hoon` is import-free and carries all 31 tests. It stays that
way.

## What ports unchanged

`lib/urmail.hoon` and `sur/urmail.hoon` have no Gall dependency — 944 lines
including the 31 tests, carrying every reviewed property: signing, verification,
`[id sig]` anti-shadowing, `+merge`, `+prune`, `+thread-key`, `+freeze`, the
caps. They become `lib/urmail-chain.hoon` and friends under the overlay's
`lib/`, tested exactly as before with `-test /=grubbery=/tests/lib/... ~`.

`gub/lib` is shared with grubbery's own libraries, so every file takes an
`urmail-` prefix to avoid shadowing.

What is rewritten is `app/urmail.hoon` — 382 lines of Gall — as a nexus.

## What this does not change

The signed chain, the three verdicts, verification before storage, forged
messages kept as evidence, the caps, and every guarantee stated in the v1
sections above. A grubbery port that weakened any of those would be a
regression, not a migration.

# urmail — design

Date: 2026-09-07, rewritten 2026-09-08
Status: current. This describes the shipping build — a grubbery nexus — and
nothing else. Where it states a limit or a cost, that limit is in the code.

urmail was first built as a Gall agent. That build is gone; see `## History`
at the end for what it was and where it lives now. Nothing in this document
describes it.

## What this is

An Urbit-native mail application. It gives you the UX of email — an inbox,
threads, compose, reply, forward, attachments — without SMTP, IMAP, MIME, or
any of the machinery that makes email what it is.

It does not bridge to internet email. Both ends run urmail.

It ships as a **grubbery nexus**: an overlay distributed into the `%grubbery`
desk, the same way lattice is, owning a subtree of grubbery's ball and serving
its own HTTP surface under `/apps/urmail`.

## Why it is not a chat app

The unit of the system is a **signed chain**: a root-to-leaf path of messages,
each one signed by the ship that wrote it. A chain is self-contained and
portable. You can hand it to a ship that was never part of the conversation and
that ship can verify, on its own, who wrote every message in it.

Forwarding is therefore not quoting. Forwarding transfers evidence.

---

# The signed chain

## What a chain is

**A chain is a root-to-leaf path, not a whole thread.** `prev` makes a thread
branch — two people replying to one message are siblings, and mail threads
branch constantly — so a thread is a tree and a chain is one path through it:
the conversation leading to a message, which is exactly what a recipient needs
to verify that message and exactly what `prev` already describes.

A path is a valid chain on its own: every `prev` in it resolves inside it, it
contains the unique `prev=~` root, so a recipient files it under the same
thread id and every message in it still verifies independently.

## Signing

Userspace can sign with the ship's real networking key. Confirmed against
`pkg/arvo/sys/vane/jael.hoon` in the arvo source, and exercised live on `~wex`
and `~feb`.

```hoon
::  our private key ring for a given life
=/  ring  .^(ring %j /(scot %p our)/vein/(scot %da now)/(scot %ud life))
=/  cor   (nol:nu:cric:crypto ring)
=/  sig   (sigh:as:cor (shaf %urmail (sham unsigned)))
```

The `%vein` scry is gated on the requesting ship being `our`, which the nexus
always is.

### Domain separation is mandatory

The signature is over `(shaf %urmail (sham unsigned))`, never over raw message
bytes — `+digest` in `lib/urmail-chain.hoon`. The ship's networking key also
signs Ames packets and attestations. A signature produced over attacker-chosen
bytes with that key is a forgery primitive if the byte space overlaps. The
`%urmail` salt makes the preimage space disjoint from every other use of the
key.

This is not optional and it is not a performance question.

## Verification

```hoon
=/  pub  .^(  (unit [crypto-suite=@ud =pass])
              %j
              /(scot %p our)/puby/(scot %da now)/(scot %p from)/(scot %ud life)
          ==)
?~  pub  %unverified
?:  (safe:as:(com:nu:cric:crypto pass.u.pub) sig (shaf %urmail (sham unsigned)))
  %verified
%forged
```

`%puby` is the unitized public-key scry. It returns `~` for a ship absent from
the local Azimuth snapshot rather than blocking, and a blocking scry inside a
fiber stalls the fiber. Do not reach for `%deed`.

### Two constraints the jael source imposes

**Jael answers scries only at exactly `now`.** Its scry arm opens with
`?.  &(=(lot [%$ %da now]) =([~ ~] lyc))  ~` — a request at any other date
returns `~`, which blocks. Nothing may scry jael with a stored or hardcoded
date, and no test can scry jael at all, since a test arm has no bowl.

Therefore the crypto splits in two: **pure gates** that take keys as arguments
and do all the signing, verifying and digesting, and **thin wrappers** that
only the nexus calls, with a live `now`. Everything worth testing lives on the
pure side, in `lib/urmail-chain.hoon`, which scries nothing. This split is what
made the port to a nexus cheap, and it is the same discipline the overlay
import rule enforces below.

**Jael's `%puby` has no fake-ship branch.** `%deed` special-cases fake ships by
deriving a keypair from the `@p` — `(pit:nu:cric:crypto 512 who %b ~)` — but
`%puby` reads `pos.zim` directly and returns `~` for any ship the fake ship has
no Azimuth snapshot of, which on a fake ship is essentially every ship. Left
alone, every message in development would read `%unverified`.

The key lookup therefore checks `.^(? %j /(scot %p our)/fake/(scot %da now))`
first and, on a fake ship, derives the peer's key the same way `%deed` does
(`+fake-pass`). This mirrors jael's own behavior rather than inventing a
development mode, and it makes the strongest test cheap: on a fake ship every
ship's keypair is derivable from its `@p`, so a test can forge a genuine
signature as a third ship, put it in a chain and verify it — the third-party
forward case, with no network and no second ship.

## Verification labels, it does not reject

Every stored copy carries one of three verdicts:

- `%verified` — signature checks against the sender's registered key.
- `%unverified` — no key available for that ship. Moons and comets land here,
  and so does a message whose `life` names a life we do not hold.
- `%forged` — a key was available and the signature failed against it.

A ship/life pair missing from the key map is `%unverified`, **never**
`%forged`: absence of a key is not a finding about a signature.

`%forged` messages are stored and displayed as forged. They are evidence, and
deleting evidence is the wrong instinct. They are never counted as unread and
never sort into the normal inbox flow. The verdict is rendered **per message,
never per thread**: a thread holding one unverified message is not an
unverified thread.

The verdict is keyed on `[id sig]`, not on the id — see the anti-shadowing rule
under `+merge`, `+prune` and the storage layout.

## The moon and comet gap

Third parties cannot verify moons or comets, and this is a property of Azimuth,
not a gap in this design.

`%earl` hands out a moon's key only to that moon's parent. `%deed` handles
comets only when the comet is asking about itself. So mail from
`~mister-botter-dozzod-nisfeb` verifies for `~nisfeb` and for nobody else.

**The cost is real and it is not small.** An entire class of sender — every
moon and every comet — reads `%unverified` on every other ship, forever, under
this build. `+prune` ranks `%unverified` above `%forged` for exactly this
reason: an unranked fill would let forged copies evict the one genuine copy of
a moon's message, leaving a user holding only forgeries of a message that was
never forged.

Signing still happens with whatever key the ship holds, so the signatures are
already sitting in the chain the day either fix lands:

- Comets are self-signing addresses — the `@p` is a hash of the key — so a
  comet's signature is verifiable with no lookup at all, given the code to
  derive it.
- Moons need their parent's attestation to travel inside the chain.

Neither changes the format. Both are strictly additive.

---

# The frozen format

`unsigned` is **closed**. Nothing may be added to it, because a signature
covers a shape and rewriting the shape produces messages every peer reads as
forged.

```hoon
+$  msg-id  @uv                       ::  (sham unsigned)
::
+$  unsigned
  $:  from=ship
      life=@ud
      to=(set ship)
      subj=@t
      body=@t
      body-mime=@t
      sent=@da
      prev=(unit msg-id)
      attachments=(list attachment)
  ==
::
+$  msg    [=unsigned sig=@ux]
+$  chain  (list msg)
```

Nine fields, and each is there for a reason:

- **`from`** — who signed it. The key looked up for verification.
- **`life`** — the key life the signature was made under. It travels because
  signatures must outlive key rotation: a message signed under life 3 stays
  verifiable after the sender rotates to life 4, because the verifier looks up
  the key for the life the message names. One ship therefore has several live
  keys, which is why the key map is keyed `[ship life]`.
- **`to`** — the visible recipients. Signed, so a relay cannot rewrite the
  audience a message claimed. BCC is deliberately *not* here; see below.
- **`subj`**, **`body`** — the message.
- **`body-mime`** — how to read `body`. Empty means `text/plain`, so a sender
  that does not care writes nothing and a reader that does not care ignores it.
  It is signed because the rendering instruction is part of the message: one
  that says "render me as HTML" and one that says "render me as plain text" are
  different messages, and an intermediary must not be able to change which one
  you read. This is the same argument that puts the attachment hash inside the
  signature.
- **`sent`** — the author's clock. Display and ordering only: an attacker
  controls it, so nothing about identity or filing may derive from it.
- **`prev`** — the parent message. This is what makes a flat list a chain and
  a thread a tree. A reply points at the message it answers; a forward points
  into the path it carries. `prev` names a *message*, not a thread, and that is
  sufficient: `msg-id` is a hash over the message's full contents, so it
  identifies exactly one message and therefore exactly one thread.
- **`attachments`** — metadata and a content hash, never bytes. Inside
  `unsigned`, so swapping a file breaks the signature.

`msg-id` is `(sham unsigned)`. It covers every field a signature covers, so an
id and a signature agree by construction.

## The attachment

```hoon
+$  attachment
  $:  name=@t          ::  original filename
      size=@ud         ::  bytes
      mime=@t          ::  content type
      hash=@uv         ::  (sham octs) over the contents
  ==
```

`hash` is over `octs`, not over the bare atom. An atom loses leading zero
bytes, so two files differing only in leading zeros would share an address;
`octs` carries the length, so they do not. It also binds `size` into the
address: a lie about the size is a lie about the content address.

The chain grows by ~100 bytes per attachment whatever the file weighs.

## body-mime, name and mime are hostile input

All three are **attacker-supplied and arrive pre-signed**. A signature proves
the author *chose* a value, never that it is safe, and a recipient cannot
repair a signed field without destroying the signature that makes the message
evidence. So they are refused at the boundary — length-capped and control-byte
free (`+text-ok`) — rather than escaped by whichever consumer remembers to.
`mime` in particular is headed for a `Content-Type`, where a CR or LF is a
header-injection primitive.

At the render boundary the rule is stricter still: match `body-mime` against a
fixed allow-list, fall back to plain text for anything else, and never pass the
value into a header. The shipping client renders every body as plain text and
says so when the message asked for something else.

## Decided: BCC needs no signed field

The chain proves **authorship, not delivery**. Who handed you a chain is
answered by Ames and by nothing in the message — which is precisely why a
forwarded chain works at all. BCC is therefore a delivery concern, and putting
it in the signature would be answering the wrong question.

- The sender delivers the chain to the blind-copied ships as well. Nothing in
  the chain names them; `to` lists only the visible recipients.
- The sender's own ship records who it BCC'd as **local state** (`meta`'s
  `bcc`, keyed by message id), so its Sent view is accurate. That record never
  travels.
- A BCC'd recipient receives the same canonical chain as everyone else — same
  bytes, same `msg-id`, same thread — and sees the visible recipients, which is
  what BCC means.
- Replying reveals them, because their reply is signed and lists its own `to`.
  That is BCC's behavior everywhere.

**The one consequence that needed code:** the Inbox view is threads we
participate in, and a BCC'd recipient is in neither `from` nor `to`. Their mail
would be invisible. So `meta` carries a local `direct=?`, set when a chain
arrives through a delivery poke, and Inbox is *participant **or** direct*.

A BCC'd recipient cannot prove the message was addressed to them. Neither can
anyone a chain was forwarded to, and the system already treats that as normal.

**Rejected, deliberately:** signing the BCC set, and signing a hashed
commitment to it. A signed list is not BCC. A hashed commitment leaks that a
BCC exists and is testable against any guessed ship, so it would offer privacy
it cannot deliver — the same class of overstatement as calling blob restriction
access control.

Reply-to, expiry and multi-parent were considered and rejected on the same
terms: each is either local, or answerable from `prev`, or not worth a break.

## The two breaks, and why an old message is refused

`unsigned` broke twice before it was frozen:

1. **`%0` → `%1`**: `attachments` added.
2. **`%1` → `%2`**: `body-mime` added.

A stored copy is `[%2 =msg =verdict]`. Versions 0 and 1 are **refused, not
migrated**, in `+read-stored`, and there is no branch for them.

A signed message cannot be migrated. `msg-id` and the signature both cover the
shape, so rewriting an old message into the new shape produces a message whose
signature no longer matches its own contents, which every peer then reads as
`%forged`. **Turning genuine mail into apparent forgeries is worse than
refusing it.** The version is bumped rather than reused precisely so a `%1`
grub is refused as cleanly as a `%0` one instead of clamming into the new shape
by accident.

Three consequences for a ship carrying old mail, none of them hidden:

- Old messages render `unreadable`. A refused grub is dropped before
  verification, so it is never labelled, never counted toward unread, and never
  `%forged`. A thread reports how many copies this build could not read, so a
  thread that renders short says why.
- **Ghost threads.** A thread whose every message is an old grub still has a
  directory, still appears in `/mail/idx`, and still counts against
  `max-threads`.
- **Old grubs cannot be culled by the writer.** `+sync-slots` builds its cull
  list from what the reader returned, and it returned nothing for them.
  `%delete-thread` is the only way out.

The contrast with local state is the whole point of keeping local state out of
`unsigned`: `$meta` and `$stored-blob` are versioned too, and their version 0
**upgrades in place**, because nothing in them is covered by a signature, so
supplying a default misrepresents nothing.

---

# The nexus

## The tree

```
/main.sig                                 the writer; serialises every mutation
/mail/thread/<tid>/msg/<id>/<id>/…/<slot> one signed copy per grub
/mail/thread/<tid>/meta                   local state: read, archived, labels,
                                          direct, bcc
/mail/blob/<hash>                         attachment bytes
/mail/blobvis                             per-blob visibility
/mail/idx                                 derived: inbox order, newest first
/fetch/<id>                               one ephemeral fiber per blob fetch
/tr/last                                  the last writer outcome, as json
/app/index.html                           the built client: one shell,
/app/app.js                               css inlined, and one script
/ui/main.sig                              binds /apps/urmail
/ui/requests/<id>                         one ephemeral fiber per HTTP request
/beacon/rev                               the change beacon; nested, never at
                                          the nexus root
```

**A message's path is its ancestry.** Each message id is a directory and its
replies are subdirectories keyed by their own ids, so two branches are two
sibling directories and reading a chain is walking one path rather than sorting
a set and chasing pointers through it. This is lattice's fixed-leaf trick — a
node that is both an entry and a parent — with a leaf per copy rather than one.

**`<slot>` is `(sham [id sig])`, never a position.** A position would have to be
renumbered on every insert (a chain is ordered by `sent`, and mail arrives out
of order) and, worse, would make the storage key something other than
`[id sig]`. Deriving the name from `[id sig]` makes the anti-shadowing key and
the storage key the same thing by construction: two copies of one message
differing in signature are two grubs with two verdicts at one node, neither can
overwrite the other, a redelivery of a chain we already hold is a no-op, and
`+prune` sheds a copy by culling exactly one grub.

Files and subdirectories are separate maps in a ball, so a node carries both its
copies and its replies with no collision possible.

Views are walks over this tree, not stored sets. Inbox is `meta` without
`archived`; Sent is threads containing a message we authored; a label is the
threads whose `meta` carries it; pagination is a bounded tree listing; search is
a sweep.

## The writer, and the change beacon

`/main.sig` is a single long-lived fiber that serialises every mutation — the
shape lattice uses to avoid index races: rise, then loop on `take-poke`, apply,
bump, recurse. **Nothing else mutates the tree.** Reads happen on their own
ephemeral fibers and never touch it.

`/main.sig` is granted a **poke road** to the `public` usergroup, so any ship
may hand us a chain. `src` is deliberately not checked against the participants
on delivery: the signatures are the authority, not the courier. The grant is a
road, not a mark, so a peer that can deliver a chain can also address the local
action marc at the writer — the writer's source check on `%urmail-action` and
`%urmail-blob-in` is what makes that harmless.

**THE WRITER MUST NOT CRASH.** `+rise-wait` restarts a failed process by
*consuming the next poke without processing it*, so a crash on bad input eats
the next legitimate message. Every rejection is a branch that returns cleanly
with a `~|` label, never a `?>` or a `!!`. The one arm that can crash on hostile
input, `+thread-key`, is called under `mule`. Refusals are written to
`/tr/last`, because fiber prints go to the raw console and are invisible to
every tool that can reach the ship.

The writer bumps `/beacon/rev` after each applied action, and open readers
stream it. Three rules, each bought with a bug:

- **The beacon must be nested.** Grubbery's keep-SSE does not stream a grub at
  the nexus root, and a beacon that never streams is a UI that looks live and
  is not.
- **A read-mark must not bump it.** Lattice learned this with page history: a
  reload storm produced by nothing a reader could see. Here it is worse than a
  storm — an open reader answers a bump by refetching the thread it is showing,
  and that refetch marks the thread read again. A loop, not a burst.
- **A poke that changed nothing must not bump it.** `+apply` answers whether the
  tree actually changed, and that answer gates the bump. Delivery is public, so
  a bump on a refusal or on a redelivery of a chain we already hold would be
  free remote amplification: one bump costs every open client a full inbox
  listing plus a thread refetch.

`%send` bumps from **inside** `+do-send`, before its fan-out, and then answers
"unchanged" so the loop does not bump twice. Bumping after the fan-out made one
unreachable recipient delay every open tab by up to `send-timeout` (~s20) each,
for a change that had already landed locally.

## Marcs

Every path ships a marc. Persisted, under `mar/urmail/`: `msg`, `meta`, `idx`,
`draft`, `rule`, `blob`, `blobvis`, `fetchreq`, `blob-in`. Wire, at the top level of `gub/mar/`:
`urmail-chain` (a whole signed chain, poked by any ship) and `urmail-action`
(the local action). A wire marc must be top-level, because a blot with a path
prefix is unreachable from the two surfaces a peer actually uses — the
`%grub-cmd` agent surface flattens a blot to its bare name, and a dojo poke
names a bare mark. The `urmail-` prefix keeps a top-level file in a shared tree
from shadowing grubbery's own.

**Every marc is `|_ n=*` with `++ grab ++ noun *` — wire marcs included.** Two
different hazards, one rule.

*Persisted* grubs: a marc written `|_ x=type:lib` re-validates every stored grub
against the live type on read, so changing the type booms every persisted grub
and readers fall to bunt defaults. For mail that is data loss. The shape check
lives in the nexus as a `;;` ladder under `mule`, newest shape first.

*Wire* payloads: this originally went the other way. The two delivery marcs were
**typed**, so a malformed chain would fail validation at the boundary rather
than reach the writer as an unchecked noun. That was sound reasoning about the
wrong risk, and it was **reversed** after the branching slice measured what it
actually did.

Grubbery validates a poke in `+hydrate`, **before any nexus code runs**. A
validation failure there fails the writer *process*, and `+rise-wait` restarts a
failed process by consuming the next poke without processing it. So a typed wire
marc never rejected a bad chain: it destroyed the **next good one**, silently,
with no crash visible and nothing written anywhere. `/main.sig` is granted to
the `public` usergroup by design, so any ship on the network could do that for
the price of one malformed noun, and repeating it was a denial of delivery
against a mail application.

**Validation you cannot catch is not validation, it is a fuse.** The clam lives
in `+apply` under `mule` with a `~|` label, where a malformed payload is refused
the way every other cap is refused — a branch that returns cleanly, with the
writer still standing and the next poke still its own. Do not restore a typed
wire marc for the argument that first justified it.

Dropping the type also drops the marc's import of the chain lib, which stops
every stored grub revalidating each time that lib changes.

## Constraints this platform imposes

Not style notes. Each cost real debugging time and is silent at the point of
failure.

1. **Every blot needs a marc.** A poke to a blot with no marc parks its dart
   silently and hangs the poking fiber forever, printing nothing.
2. **Every marc is a noun passthrough**, per the rule above.
3. **Every persistent path needs a covering `%fall` row in `+on-load`.** `spin`
   rebuilds the bole from scratch and drops anything uncovered. An uncovered
   path is lost mail. `/mail` takes a `%fall %|` so the whole dynamic subtree
   survives; `/app` takes `%over` so a redeploy actually replaces the client
   rather than leaving every ship on the build it first loaded.
4. **Long-lived fibers use absolute roads.** A depth-relative road called from
   the wrong depth climbs past the nexus root and crashes the fiber; crashed sig
   fibers respawn, so one bad road becomes an infinite crash loop at 100% CPU.
5. **No `$` with arguments inside a `;<` continuation** — it cannot find the
   trap. Recurse by arm name.
6. **Deploys bounce.** Pushing source recompiles the nexus but does not respawn
   long-lived fibers; they keep running old code silently. Every deploy is
   `|suspend %grubbery` then `|revive %grubbery`.
7. **Never hotfix a single file through the mount.** The mount is a stale
   snapshot and commits wholesale, reverting every file changed since the last
   sync. Deploy the full overlay or nothing.

## Installing the nexus

A nexus cannot install itself: a directory's neck is fixed at creation and no
runtime surface can set one — grubbery's HTTP `PUT /dir` and `sur/grub`'s
`%make-dir` both lay `[~ ~ %.n ~]`. Two paths, and both are needed:

- **The durable one** is a covering row in grubbery's own `lib/root.hoon`:
  `[%fall %| /apps/'urmail.urmail_app' [`[`[/urmail %app] ~ %.n ~] ~]]`.
  Lattice's row sits beside it and this is the established pattern for an
  overlay distribution. That file is outside this repo, so **a grubbery pull
  reverts it** — a cost urmail shares with lattice. `sync-overlay.sh`
  deliberately does not write it (an overlay that silently edits its host's
  sources is how the `obelisk-ast` clobber happened); it greps for the row and
  prints the line to add. The check is the mitigation, not a fix.
- **The fresh-ship bootstrap** is `create_folder {path:'/apps',
  name:'urmail.urmail_app', nexus:'/urmail/app'}` over the grubbery MCP. Both
  arguments are load-bearing and each is wrong in a different way: a `nexus` of
  `/urmail` yields the neck `[~ %urmail]`, which looks for a flat
  `/nex/urmail.hoon` that does not exist, the build fails, and `make` banks an
  **empty node** — scries return nothing and no writer spawns. A `name` of
  `urmail` rather than the compound `urmail.urmail_app` keys the node where
  nothing looks for it, and writer pokes crash with `inert: no handler` even
  though the tree seeded fine.

Editing the source afterwards does **not** re-seed a wrong-neck node; reload
gates on neck-match. A bad install has to be removed and redone.

`%register`'s overlap pruning is safe against lattice: `is-prefix` between
`/apps/urmail.urmail_app` and `/apps/lattice.lattice_app` is false in both
directions, so registering urmail cannot evict lattice's registration.

## Which overlay libs may import, and what it costs

The overlay's `lib/` is rsynced to **both** `gub/lib` and the desk's `/lib`.
Those two build with different runes — the nexus side uses `/<`, ford on the
desk side does not understand it — so a lib's imports decide where it can be
built:

- **Import-free libs build in both**, and are therefore the only ones
  `-test /=grubbery=/tests/lib/… ~` can reach.
- **Libs using `/<` build only from the nexus.** They are still copied to the
  desk `/lib` but never built there, so nothing complains. They cannot be unit
  tested.

The rule that follows: **anything worth testing goes in an import-free lib, and
the nexus glue may import freely.** `lib/urmail-chain.hoon` and
`lib/urmail-web.hoon` are both import-free and carry all 71 tests between them.
They stay that way. Types live in the same core as the logic rather than in a
`sur/`, because an overlay has no `sur/`.

`gub/lib` is shared with grubbery's own libraries, so every file takes an
`urmail-` prefix to avoid shadowing.

---

# Attachments

The chain travels whole on every send, so bytes must not live in the chain. The
message carries `name`, `size`, `mime` and `hash` inside `unsigned`, therefore
signed; the bytes live at `/mail/blob/<hash>` and are published into gall's
remote-scry farm at `/urmail/blob/<hash>`.

- Sending stores the bytes locally, puts the hash in the message, signs, ships
  the path as before. Bytes are stored and published **before** the chain goes
  out: a recipient that fetches the instant the chain lands must find the blob
  bound, and a keen at an unbound spur *parks* rather than failing.
- Receiving stores the chain immediately. **Bytes are not pushed.**
- A ship that wants an attachment it lacks fetches it with a `%keen`.
- **A blob whose contents do not hash to the address it was fetched under is
  discarded without comment.** The hash is the authority, not the sender.
- Blobs are a cache. Losing one loses a file, never a message and never a
  signature.

## Bytes across the HTTP surface

The nexus half of attachments was complete a slice before any of it was
reachable: a message could carry a signed `[name size mime hash]`, the bytes
could sit at `/mail/blob/<hash>`, and no route moved a single byte between the
browser and the ship.

**Upload rides base64 inside the JSON `/api/send` already takes.** The
alternative was multipart and it is out twice over. The desk's `lib/multipart`
is not in `gub/lib`, so a nexus cannot import it; and its `$part` carries
`body=@t`, a bare atom with **no declared length**, which silently drops a
file's trailing zero bytes — and the content hash is then taken over the
truncation, so the loss is invisible twice. Writing a second multipart decoder
in the import-free lib was the previous attempt at this slice and it is what
broke the build.

### What the transport actually costs

The first version of this section justified that choice with a JSON benchmark:
eyre hands a request fiber the whole body, `+de:json:html` is jetted, a **32MB
JSON body round-trips in ~1.3s** on `~wex`, and `max-attach` files at
`max-blob` is 5.5MB — two orders inside the ceiling. Every one of those numbers
is real and **not one of them is this code's number.** `+de:json` is jetted.
`+b64-digits` is not: it is an interpreted loop that runs once per character of
the encoding — ~350K times for one `max-blob` file, up to sixteen of those in a
send — on the request fiber holding the connection open. Benchmarking the
jetted half and shipping the interpreted half is how a measurement comes to
justify code nobody ran.

So it was measured on the code that was written, at the live route on `~wex`
(`POST /apps/urmail/api/send`, `curl -w '%{time_total}'`, warm, one request at
a time). Two of the rows are diagnostics rather than user paths: a file whose
encoded length is one quantum over the cap is refused before any base64 is
decoded, which isolates the JSON parse, and a file with an over-long `name` is
fully decoded and then refused by `+files-ok`, which isolates the decode. The
difference between them is the decoder and nothing else.

| at `/api/send`, 256K files | before | after |
| --- | --- | --- |
| no attachment, sent | 1.79s | 1.85s |
| 1 file, refused on length (JSON parse only) | 0.41s | 0.40s |
| 1 file, decoded then refused (parse + decode) | 3.48s | 1.42s |
| **1 file, sent — end to end** | **5.13s** | **3.96s** |
| 16 files, refused on length (parse of a 5.5MB body) | 0.57s | 0.54s |
| 16 files, decoded then refused | 27.5s | 17.2s |
| **16 files, sent — end to end** | **32.6s** | **18.7s** |

Reading down: **the JSON parse is not the cost.** 5.5MB of body parses in half
a second, exactly as the original benchmark said it would. The decode of a
single `max-blob` file was **~3.0s** and the sixteen-file case held a
connection open for **over half a minute**.

The decoder was rewritten and re-measured, and the same table carries the
after: **~1.0s** per file, **18.7s** for the worst case a client can produce.
What changed is in `+de-b64`, and none of it is the reduction — the arithmetic
is still zuse's. The per-character `?:` ladder of five range comparisons behind
a gate call is one `+cut` into `+b64-table`, an atom indexed by the character
whose stored value is the digit **plus one**, so the zero `+cut` answers for
anything outside the alphabet is the validation too. Around that loop the first
shape walked the same 350K list six more times — `+lent` for the character
count, two `+snag`s for the padding, a `+scag` to drop it, a second `+lent` for
the digit count, and two `+flop`s that between them rebuilt the list the loop
had already produced in the order `+rep` wanted. Those are now `+met`,
subtraction, `+cut` and `+end`, all of them jetted, and the character loop is
the only walk left.

**18.7s is still not fast, and the honest statement of the limit is this:** the
sixteen-file case is the largest send urmail accepts, it costs about twenty
seconds of a request fiber, and there is no partial progress to show for it —
the browser sees one POST that takes twenty seconds or fails. What remains is
the loop itself, and shrinking it further means either a jet or a chunked
upload route, both of which are their own slice. The caps are what bound it:
`max-blob` at 256K and `max-attach` at 16 are the reason the worst case is
twenty seconds rather than unbounded, and the client refuses an oversized file
at the moment it is picked so the common way to hit this limit is deliberate.
`+de-files` refuses on the **encoded length before decoding anything**, so an
oversized upload costs a `+met` and not a decode; that gate is exactly
`4·⌈cap/3⌉`, the encoded length of a cap-sized file, because the rounding is
the padding and there is nothing to add for it.

**The base64 decoder is urmail's own** (`+de-b64`), not
`+de:base64:mimes:html`, which is `(rush a parse)` — a parser-combinator sweep
that turns the payload into a tape and matches it character by character. That
is precisely the shape grubbery's `lib/multipart` was rewritten away from after
it OOMed on large uploads. `+de-b64` does the same arithmetic over jetted atom
ops: one `+rip` in, one `+rep`, one `+swp` out. The reduction is zuse's,
because it is the easy part to get subtly wrong — base64 is big-endian within
each 24-bit group and an urbit atom is little-endian. What is *not* zuse's is
everything around it; see *What the transport actually costs* for what that is
and what it measured. `len`
comes from the **digit count and never from `+met`**, and the result is trimmed
to `len`, which is what makes a file that begins or ends in a zero byte
survive and hash the same on both ships.

**Download is `GET /api/blob/<hash>`**, owner-gated, and it answers **409 `not
fetched`** rather than 404 for a blob this ship does not hold — see the route
table. It serves only bytes that re-derive to the hash in the path.

### `name` and `mime` at the header boundary

Both are **signed and hostile**. A signature proves the author chose the value,
never that it is safe, and the chain carrying it is delivered by whoever felt
like it. `+text-ok` refuses control bytes on the way *in*, but a blob on disk
may have been signed and stored by a build that did not, and a recipient cannot
repair a signed field without destroying the evidence. So the download header
gets its own guard and it does not care where the value came from.

- **`mime` never reaches a header raw.** A fixed **allow-list** (`+ok-mimes`),
  else `application/octet-stream`. An allow-list because the failure being
  prevented is not a bad type but a **CR or LF in the value**, which splits the
  response and lets a pre-signed string write headers of its own; no blocklist
  can close that, and a list of exact cords closes it without parsing anything.
  `text/html` and `image/svg+xml` are deliberately absent.
- **`Content-Disposition: attachment`, always**, plus `nosniff`. A hostile HTML
  or SVG rendered inline is XSS in the owner's session with their cookie
  attached. Two independent reasons not to render one is the right number.
- **`name` is sanitized** (`+safe-name`): separators, quotes, backslashes,
  semicolons, every control byte and every byte above ASCII are *dropped*
  rather than escaped, capped at 128 bytes, and a name that survives as nothing
  — or as nothing but dots — becomes the hash. The stated cost: a filename in a
  non-Latin script downloads as its content address. RFC 6266's `filename*=` is
  the fix and it is not here.

`name` and `mime` reach the route in the **query string**, out of the signed
`$attachment` the client just rendered, because a blob grub is bytes and an
arrival time and nothing else — recovering the metadata server-side would mean
walking every thread on the ship per download. That makes them client-supplied,
which changes nothing: they were hostile already, and the two guards above
refuse them identically whichever way they arrived.

### A blob arrival does not move the beacon

`+take-blob` answers `%.n` on success. `+apply`'s answer is what moves
`/beacon/rev`, and a blob arriving is not message content: no message appeared,
none changed, and no listing row reads differently for it. A bump would cost
every open tab a full inbox listing — `O(total stored messages)` — plus a
thread refetch, for bytes only the tab that asked is waiting on.

It is also the read-mark amplification argument with a sharper edge.
`%fetch-blob` is a local action, but the **answer arrives from a peer**, so a
bump here would let whoever serves the bytes decide when this ship refetches
its whole mailbox. The waiting tab polls `GET /api/blob` instead, which is one
peek per retry against a route it was going to call anyway.

**Attachments do not survive a draft.** A draft grub has no files field and
`%save-draft` carries none, so a composer with a file attached takes the direct
`/api/send` path and never save-then-`%send-draft`. Routing an attached send
through the draft path would drop every attachment silently and report success.

**And the composer says so, while the files are attached.** The autosave runs
on a 1.5s debounce and again on close; both write a draft without the files,
and a resumed draft comes back with none. That is a limit of the draft store
and it is allowed to be one — what would make it a data-loss bug is a user who
does not know, so a composer holding files carries one line saying they are not
saved with drafts. A line and not a confirm dialog: it is true from the moment
a file is picked, not only on the way out, and the thing to do about it is to
press Send.

## The fetch is a keen, not a poke protocol

Per the mesa work done on lattice, the keen is the kernel scry farm and is the
*only permissionless channel* — peeks and keeps are both weir-gated, and a
cross-ship peek between un-granted peers hangs rather than failing. That
asymmetry is exactly what urmail wants: any ship holding the bytes can serve
them, and the hash proves them.

Two details the namespace forces:

- The keen path must mirror `+blob-spur` exactly or every read misses forever,
  and it is built by cons because it contains **the empty segment**, which a
  path literal cannot spell and nobody notices is missing: `/g/x/<case>/<agent>/
  ''/1/urmail/blob/<hash>`, where `<agent>` is `%grubbery` — the yoke, not the
  nexus.
- There is **no revision segment**. A blob's bytes are fixed by its name, so a
  content-addressed spur binds at case 1 and a re-grow of the same bytes leaves
  it bound and correct. That is why this fetch needs no rev-discovery channel,
  and rev-discovery is the weir-gated part.

The fetch runs on **its own ephemeral fiber** under `/fetch/<id>`, never on the
writer: a keen is a network round trip, and a fetch on the writer would queue
every send, every inbound chain and every read-mark behind it. Ephemeral is not
incidental either — a timed-out keen leaves a late response and a stray `%veto`
behind, and a long-lived fiber that `%skip`s those piles them into its skip
queue to be re-offered on every later take. That debris lands on a process about
to be culled instead of on the ship's single serialisation point for mail.

`+max-case-probe` (3) exists for the one operation that burns a case: a restrict
culls the spur, and gall parks the culled case as a high-water mark, so a blob
restricted and later re-published answers at case 2 permanently. Probing a few
cases up is the fetcher's whole defence, and it costs one timeout per miss, paid
only by a blob that has actually been restricted.

**Publishing an already-public blob is gated, and the gate is load-bearing.**
`+grow` assigns `las+1` on a non-empty fan, so an idempotent-*looking* "make
public" pushes the binding one case higher every press. Three presses put it
past `+max-case-probe` and the attachment is unfetchable by every peer, forever,
with no error — the fetcher just reports a miss. Cases only go up, so there is
no recovery. Nothing may `%grow` a spur it has not first established is unbound.

## Restriction is withdrawal, not access control

`%public` is the default: a chain is forwardable to anyone by construction, and
an attachment only the original recipients could read would make every forward
carry an unreadable file. `%restricted` withdraws the blob from our farm and
records the named ships so a weir grant can serve them a peek instead.

**A fetcher republishes what it accepted**, because it is now one of the ships
holding the bytes. So the first successful fetch creates a second, independent,
un-revocable source. **Restriction is therefore withdrawal of our own copy, not
access control, and it means something only before anyone has opened the
attachment.** Anything that presents it as revocable permission is lying to the
user. The same reasoning that makes a chain portable makes a blob unrecallable;
that is the trade this design took deliberately when it chose the hash as the
authority.

**The grant half is not complete, and the reason is a platform limit.** A nexus
cannot create a usergroup: the registry action carries `%register`,
`%deregister`, `%how` and `%gc` and no group-lifecycle op, `%how` refuses
outright for a group with no `who.ships` grub, and laying that grub by hand
means a `+make` under `/sys/ames/usergroups` — where every `make` variant turns
a `%veto` into a failure that crashes the writer, which is the one thing the
writer must never do. So the grant is attempted and skipped **loudly**: a
restricted blob with no group is *withdrawn but ungranted*, and the trace says
so. Creating the group is out-of-band today.

## The caps

```
max-blob        262.144      bytes in one attachment
max-attach      16           attachments per message
max-name        256          bytes of filename
max-mime        128          bytes of content type
max-blobs       1.000        blobs this ship will store
max-blob-bytes  33.554.432   bytes the blob store will hold
```

`max-blob` is 256K rather than something round and large because a blob is
answered over remote scry, which fragments the response into Ames packets, and a
multi-megabyte keen is a lot of packets for a fetch with no partial-progress
story. Raise it when the fetch has one.

`max-blobs` alone is not a storage bound — a thousand quarter-megabyte blobs is
256MB — so `max-blob-bytes` bounds the weight independently, and eviction takes
both at once because a store can be under the count and over the bytes or the
reverse.

Eviction sheds the **oldest unreferenced** blobs: a blob referenced by any stored
message is never evicted however old, and `%delete-thread` culls messages
without culling their blobs, so unreferenced blobs genuinely accumulate. Ties on
arrival time fall back to the hash, so the order is total and two runs shed the
same blob. When the store cannot be made to fit, the send is **refused** rather
than partially evicted for nothing.

Neither bound can be weaponised: bytes only ever enter through a **local**
action, never through a delivered chain, which carries metadata alone. What a
delivered chain *can* do is bounded separately — `+fits-attachments` caps the
count per message and checks each claimed `size` against `max-blob`, because an
attachment claiming a gigabyte is a claim we would never honour and rejecting it
at the boundary is cheaper than discovering it at fetch time.

---

# Threads branch, and the tree says so

## What a forward ships

`+do-send` ships `+path-chain`: the path from the thread root to the message
being replied to or forwarded, and nothing else.

Shipping the whole thread instead was a **leak**, not an inelegance. Two
participants have a side exchange on one branch; one of them forwards a message
on a different branch onward; the third party receives the side exchange —
signed, permanent, attributable, and nobody asked for it.

**Every copy at each node travels**, not one per node. Choosing which of two
copies of one message to forward would be exactly the shadowing `+merge` exists
to prevent, decided by the forwarder.

`+with-root` covers the one case a path alone breaks: an **orphan** branch,
whose walk never reaches a `prev=~` message. A chain with no root is refused by
`+thread-key` at the far end, so the send would look successful here and be
dropped there. The root is a message every participant already holds and is what
the thread's identity is derived from, so adding it discloses nothing.

## Merge, prune, and identity

**`+merge` dedupes on `[id sig]`, never on the id.** Two copies can share an id
and carry different signatures — one genuine, one forged. Deduping on the id
alone would let whichever arrived first shadow the other, which on a forwarded
chain lets a malicious forwarder frame a third party as a forger. Both copies
are kept; verification labels them; the reader decides what to show.

**`+prune` sheds, it does not reject.** The per-id copy bound is enforced by
shedding in strict verdict order — `%verified` first, then `%unverified`, then
`%forged`. Rejecting the merged result would be a censorship primitive: an
attacker who lands `max-copies` forged copies of a chain's genuine root at a
ship that has never seen the thread mints that thread under the genuine
content-derived id, holding it full of junk; when the real chain arrives the
count is over the bound, a reject would nack it, and because every send ships
the whole path, every subsequent message in that thread would be rejected
forever, for the cost of a few junk-signed messages.

That is the general rule: **input validation rejects; merged-state capacity
sheds.** Rejecting on merged state punishes a legitimate poke for excess that
may be entirely attacker junk already on disk.

**`+thread-key` derives identity from content, never from order or `sent`.** An
attacker controls both, so either would let one poke duplicate a conversation or
migrate an established thread onto a new id. An established thread's identity is
immutable once set; a first-contact chain is anchored on the message with
`prev=~`, and the root is deduped by id rather than counted by message, so a
relay forwarding the genuine root alongside a tampered copy does not get a
legitimate first contact rejected.

**`+freeze`** folds new verdicts into the stored ones, definitive labels first.
`%unverified` freezes only against another `%unverified`: it is not a finding
about the signature, only that the key was absent from our snapshot at that
instant, and a later poke may arrive after we have fetched the key. `%verified`
and `%forged` are definitive for a fixed `[id sig]` and can never disagree.

## Depth is not off the read path

A message is stored under its ancestry, so its road carries one ~34-byte segment
per ancestor, and the nexus rebuilds those keys on every peek of the mail tree —
which is every send, every read-mark, every delivery and every inbox listing.
Cost is quadratic in depth. `max-chain` alone would let one hostile linear chain
pin a thread at depth 1.000 permanently: measured, 200 messages at depth 200
already cost ~1.8x the same 200 at depth 2, and 1.000 extrapolates to minutes of
writer time per read, forever, until the thread is deleted.

`max-depth` is 64 — far above any real conversation and far below where the
quadratic bites. It is checked on a single poke *and* on the merged result, since
two chains each inside the cap can compose past it.

**The cost, stated plainly:** a thread genuinely deeper than 64 accepts no
further messages, exactly as the distinct-id cap already behaves and for the
same reason.

## The input caps

```
max-chain    1.000     distinct messages per chain
max-body     100.000   bytes per body
max-subj     1.000     bytes per subject
max-to       100       recipients per message
max-copies   4         copies (same id, distinct sig) per message
max-threads  10.000    distinct threads this ship will hold
max-depth    64        ancestors from root to leaf
```

Incoming chains are **rejected, never truncated**: a chain that violates a limit
is not partially trustworthy, and trimming a signed field would forge. An
*existing* thread always accepts a new message — only a brand-new thread id is
capped — because a reply must never be refused because some unrelated thread
filled the store.

The same bounds are enforced at compose time, from the same lib arms, because
every send ships the path it replies into: one oversized compose would poison a
thread permanently, with every later message on that path rejected by every
recipient, silently. Failing at compose is the only point where a human can
still do something about it. And a send the ship refuses must say so — the web
route checks the request-only caps itself and answers 400, because answering
`ok` while the writer discarded the message is a composed message destroyed with
no draft to recover it.

---

# The web surface

Every route is owner-gated. urmail has no unauthenticated surface at all — no
clearweb view, no public form, no unauthenticated asset — and every response,
errors included, is JSON, so the client has one shape to parse. Eyre's
authentication flag carries the shell and the script; every API route compares
the source ship as well, because a surface that mutates the tree resting on one
flag from one vane is thinner than it needs to be. `our` is not in hand — it
costs a bowl round trip, ~0.2s per request — which is why the two asset routes,
where there is nothing to mutate, keep the flag alone.

| Method | Route | |
|---|---|---|
| GET | `/apps/urmail` | the shell |
| GET | `/apps/urmail/app.js` | the script |
| GET | `/apps/urmail/api/whoami` | our own `@p` |
| GET | `/apps/urmail/api/inbox` | the listing |
| GET | `/apps/urmail/api/thread/<id>` | one thread, every copy with its verdict |
| GET | `/apps/urmail/icon.svg` | the launcher tile's icon |
| GET | `/apps/urmail/api/blob/<hash>` | one attachment's bytes |
| POST | `/apps/urmail/api/send` | compose, reply and forward, with files |
| POST | `/apps/urmail/api/read` | mark a set of messages read |
| POST | `/apps/urmail/api/fetch-blob` | pull an attachment's bytes from a peer |
| POST | `/apps/urmail/api/delete-thread` | remove a thread from this ship |

The mail-client writes are the same shape and are listed in
`+handle-request`: `unread`, `label`, `archive`, `draft`, `draft-delete`,
`draft-send`, `rule`, `rule-delete`, plus `GET /api/drafts` and `GET
/api/rules`.

A trailing slash is a trailing empty knot and is stripped, because a bookmark is
exactly where one comes from.

**A read peeks the tree from its own request fiber. A write pokes the writer and
answers.** That split is what the per-request fibers are for: a send fans out to
every recipient with a deadline each, and a render or a round trip placed on the
writer would queue every other mutation on the ship behind it.

The client is **two grubs**, laid down by `+on-load` and served under the app's
own route: a shell with its CSS inlined and one script. Assets carried in cords
wedge every request fiber, which is why lattice ships one document plus one
script and why this does too — the build refuses to emit a third file. They are
served `no-cache`: the two grubs are replaced wholesale by a reload, and a cached
shell pointing at a script that no longer matches it is a blank page with nothing
in the console.

`whoami` exists because the reply composer drops us from its own default
recipient list, and the client is no longer configured with a ship name — it is
served by the ship it talks to and asks that ship who it is. The old `VITE_SHIP`
default was silent: aimed at one ship and authenticating as another, with nothing
obviously wrong until every call failed.

**Live updates are the beacon, not polling.** The client streams
`/grubbery/api/keep/apps/urmail.urmail_app/beacon/rev` and, on a change, refetches
the listing and whatever thread it is showing. The beacon says *that* the tree
changed, not which thread changed, so one event costs one thread refetch rather
than one per thread. Polling was the fallback and is not needed: a poll interval
short enough to feel live would be a request every second or two against a
serialized pier, where a single request already costs a fiber.

**`count` on a listing row is stored copies, not distinct messages**, and the
client labels it that way. Up to `max-copies` copies of one message that differ
in signature are kept deliberately — one genuine, the rest forged — so a forged
copy cannot shadow a real one. A thread showing four may be one message and three
forgeries. Calling that a message count would be a lie told by the safety
mechanism.

A listing row draws its sender and subject from the newest non-`%forged` copy and
carries that copy's verdict, so provenance is visible before the thread is
opened; the row also flags separately whether the thread holds a forged copy at
all, and how many copies this build cannot read.

`%read` takes a **set**. Opening a thread marks every unread message in it at
once, and one id per poke meant one writer event and one full mailbox scan per
message — forty messages, forty serialised scans, to record something no peer
will ever see. Ids naming nothing are skipped rather than refused: a set is a
client reporting what it just rendered, and a thread deleted in another tab
between render and poke would otherwise fail the whole batch.

**`/api/blob/<hash>` is the only route that answers anything but JSON**, and
the only one whose body is not something this nexus wrote. It is owner-gated
like every other data read, it re-derives the hash from the bytes before
answering, and it answers **409 `not fetched`** — never 404 — for a blob this
ship does not hold. Bytes are never pushed, so *unfetched* is the ordinary
state of an inbound attachment; 404 would say the file does not exist when what
it means is "ask for it". The client turns the 409 into a Fetch control that
pokes `%fetch-blob` and then retries this route.

`%restrict-blob` and `%publish-blob` still have no route. They are writer
actions with no UI behind them, and per-attachment visibility is a slice of its
own — see *Restriction is withdrawal*, whose grant half is incomplete for a
platform reason.

---

# Local versus signed

**Nothing local is ever signed, and nothing signed is ever local.**

| Signed, travels | Local, never travels |
|---|---|
| `from`, `life`, `to`, `subj`, `body`, `body-mime`, `sent`, `prev`, `attachments` | read marks, archive, labels, `direct`, the BCC record, blob visibility, blob arrival time, inbox order, the verdict |

Two ships can disagree about every column on the right; they can never disagree
about who signed what. That is what makes `unsigned` freezable at all — every
mail-client feature that follows is a decision about the right-hand column.

The verdict is local by necessity: it is *our* reading of a signature against
*our* Azimuth snapshot at one instant. It rides with the copy it labels rather
than in a side map, because a verdict names one signed copy.

---

# Deliberate limits, with their costs

**Every send ships the full path.** A two-hundred-message path costs two hundred
messages of bytes on every reply. Acceptable for text. The upgrade, when needed,
is a `have=(set msg-id)` handshake so the sender transmits only the difference.

**Storage is unbounded within the caps.** Nothing expires, and a hostile ship can
grow your state by poking you chains up to `max-threads` × `max-chain` ×
`max-copies`. Rate limiting per source ship is the next step if it becomes real.
`%delete-thread` exists because every capacity limit here is otherwise permanent
and unrecoverable.

**The distinct-id cap rejects rather than sheds, and that is a censorship
vector.** Shedding a non-root id would orphan the `prev` pointers of later
messages, which is genuinely harder, so the cap on distinct message ids per
thread refuses. The cost, not hidden: anyone who knows a thread's root content
can poke enough distinct junk messages — **no signatures required**, since forged
messages are stored and counted — to pin the thread at the cap, after which every
legitimate message is rejected. One poke, no crypto, permanent per-thread
censorship. The fix is to shed distinct ids too, preferring `%verified`, and it is
deferred rather than justified.

**Moons and comets are unverifiable to third parties.** See above. An entire
class of sender reads `%unverified` forever under this build.

**Restriction is withdrawal, not revocation.** See above. If the UI ever presents
it as permission, users will trust it for something it cannot do.

**Writes queue behind the writer, including its fan-out.** A poke returns when
the writer takes it, so a send issued while the writer is fanning out to an
unreachable ship waits — ~8s observed, and up to `send-timeout` (~s20) per
unreachable recipient. Reads never touch the writer, so the UI stays usable, but
this is the first thing that will look like a hang to a user. It is the
architecture, not a defect.

**Reads are O(total stored messages).** `+thread-key`'s scan walks every stored
message with a `sham` per message, on the only externally reachable poke; the
inbox listing is one deep peek of `/mail/thread` walked twice. Bounded by
`max-threads` × `max-chain`, but large. The upgrade path is the same in both
cases: an index grub — a `(map [msg-id @ux] thread-id)` for the first, a summary
row per thread for the second. This is a performance concern, not an authenticity
one.

**A chain touching two existing threads conflates them.** `+thread-key` picks
whichever comes first in map-traversal order. The upgrade path is to reject
chains whose keys match more than one thread rather than silently picking one.
Availability and correctness of filing, not authenticity — a wrongly-filed
message is exactly as verified or forged as it was.

**No delivery receipts.** A send Ames cannot deliver fails silently from the
UI's point of view. This is about *remote* delivery only: a send the local ship
itself refuses answers 400.

**The `root.hoon` row is outside version control.** A grubbery pull reverts the
install. `sync-overlay.sh` checks and prints; it does not write.

**A restricted blob may be ungranted.** See the platform limit above.

---

# Testing

71 tests, in two import-free overlay libs, run with
`-test /=grubbery=/tests/lib/urmail-chain ~` and
`-test /=grubbery=/tests/lib/urmail-web ~`:

- **`tests/lib/urmail-chain.hoon` — 56 tests.** Signing and verification
  round-trips, tamper detection on every signed field including `life` and
  `body-mime`, the three verdicts, `[id sig]` anti-shadowing through `+merge`,
  `+prune`'s verdict ordering and its refusal to shed a `%verified` copy,
  `+thread-key`'s identity rules, `+freeze`, the caps, the attachment
  predicates, blob eviction, and the tree arms — `+ancestors` on orphans and
  cycles, `+path-chain`, `+with-root`, and the path algebra the storage layer
  uses.
- **`tests/lib/urmail-web.hoon` — 15 tests.** The JSON request decoders: the one
  part of the HTTP path no Hoon type has checked, most of them on what a
  malformed body does.

The tests that matter most are the ones a chat app cannot pass: a forward
preserves every prior signature; a tampered body flips to `%forged`; a chain
arriving from a non-participant is accepted and verifies; a forged copy does not
shadow a genuine one; a sibling branch does not travel.

Anything requiring a bowl — every jael scry — is untestable by construction and
is verified live instead. See `docs/verification.md`.

# Development

Two fake ships, `~wex` (pier `/home/sneagan/software/wex`, HTTP 8081) and `~feb`
(`/home/sneagan/software/feb`, 8080). Both run the overlay synced from this repo
into their own `%grubbery` desk.

The loop is `scripts/sync-overlay.sh <pier>/grubbery`, `|commit %grubbery`, then
`|suspend %grubbery` and `|revive %grubbery` — the bounce is not optional
(constraint 6). Never hotfix a single file through the mount (constraint 7).

Never `~ricsul-bilwyt`. That ship is the memory store.

Fake ships derive deterministic keys, so signing and verification are
self-consistent and the dev loop exercises the real crypto path — including
third-party verification, since any fake ship's key is derivable from its `@p`.

---

# The mail client

Everything in this section **was** the "Specified but unbuilt" list and is
now on the nexus. It was always a set of views and `meta` fields rather than
a change to anything signed: not one line of it touches `unsigned`, none of
it can hide a `%forged` message, and every ship may disagree with every
other about all of it.

Two rules run through the whole layer:

- **None of it moves the change beacon.** A label, an archive flag, an
  unread mark, a draft and a rule change a thread in ways no other ship can
  see, and a bump costs every open tab a full inbox listing plus a thread
  refetch for a change it cannot observe. That is the read-mark storm again,
  wearing a different hat. The tab that made the change refreshes itself.
- **Every view is a predicate over the one tree walk the listing already
  pays.** There are no stored view sets, so two views cannot disagree about
  where a thread is.

## Labels, and folders as views over them

Labels are local, per-thread, and never travel — `meta`'s
`labels=(set @tas)`, which nothing read until this slice. A **folder** is
not a separate concept. The sidebar shows views:

| View | Definition |
|---|---|
| Inbox | not archived, and we are a participant **or** the chain arrived direct |
| Sent | any message in the thread is authored by us |
| Archived | `meta`'s `archived` |
| All mail | everything stored |
| Drafts | from `/mail/draft/` |
| `<label>` | `meta` carries that label |

That is Gmail's model and it avoids a second taxonomy that would inevitably
disagree with the first.

The Inbox clause is the first thing that ever read `direct`. It was set on
delivery from the BCC slice onward and no view consulted it, so a
blind-copied recipient — who is in neither `from` nor `to` of any message in
the chain they were handed — had mail that no view could reach.

`%label` carries **one label and a direction**, not a set: a set-valued
action is last-write-wins over whatever another tab did, and for local state
nothing can reconcile that is a silent loss.

A label is a `@tas` a human typed, so `+label-ok` refuses anything that is
not one, at the HTTP boundary and again at the writer. A cord holding a
space or a capital sits in a `(set @tas)` perfectly happily and then crashes
`scot %tas` on a request fiber, which is an HTTP connection that never
answers.

## Archive

`meta`'s `archived`, which already defaulted to `%.n` explicitly — a bare
`?` bunts to `%.y`, so every thread would be born archived and the inbox
would show nothing.

Archiving removes a thread from the Inbox view only. It is not deletion, it
does not touch the chain, and **a new message arriving in an archived thread
un-archives it** — otherwise mail silently disappears, which is the failure
mode a mail client may least afford. `+file-arrival` does this, gated on
`+sync-slots` having actually written something, so a redelivery of a chain
we already hold — which any ship may poke at us, since delivery is public —
un-archives nothing.

## Mark unread

The inverse of the read action, over the same grouping pass (`+group-ids`)
and the same single meta rewrite, so the two cannot disagree about what a
set of ids names. Forged messages continue never to count toward unread, and
no branch says so: that rule lives in how unread is *computed* in
`+entry-json`, and a second copy of it here would be a second place for it to
drift.

The client leaves the thread after marking it unread. Staying would re-run
the effect that marks a thread read on open, and the user would watch their
own mark undo itself.

## Sent

A walk: threads containing a message we authored, asked of the chain rather
than recorded beside it — authorship is a signed field, so a second record of
it could only ever disagree with the first. The BCC record in `meta` is what
makes this view accurate about who a message actually went to.

## Drafts

```hoon
+$  draft
  $:  %0
      id=@uv
      to=(set ship)
      subj=@t
      body=@t
      prev=(unit msg-id)
      at=@da
  ==
```

One grub per draft at `/mail/draft/<id>`. Drafts are local and unsigned —
**a draft is not a message and must never be renderable as one** — and two
things enforce that structurally rather than by care: a draft is stored
outside `/mail/thread`, so no walk that produces messages can reach it, and
its shape shares no prefix with `$stored-msg` (`%0` against `%2`), so the
ladder that reads a stored copy refuses a draft noun outright.

The version head is this design's one addition to the shape the earlier spec
wrote: every persisted grub here is read back through a `;;` ladder, and a
shape with no version cannot be laddered later without booming what is
already on disk.

Sending signs it at that moment and deletes it, in one writer action
(`%send-draft`). **The delete is gated on the send having happened.**
`+do-send` answers whether it sent, and a refused send — a body over the
cap, an unknown `prev`, a full blob store — leaves the draft exactly where
it was. Deleting unconditionally would destroy the composed message at the
one moment the ship is telling the user it will not carry it.

The id is minted by the **client**. A draft id is local, means nothing on
any other ship and never appears in a signature; the route answers as soon
as the writer takes the poke, so a server-minted id could never be told to
the client that needs it to save the same draft again. The UI saves on a
debounce and again on close.

## Filters

```hoon
+$  rule
  $:  %0
      id=@uv
      from=(unit ship)      ::  match sender
      subject=(unit @t)     ::  substring match, case-insensitive
      add=(set @tas)        ::  labels to apply
      archive=?             ::  skip the inbox
  ==
```

One grub per rule at `/mail/rule/<id>`, applied on delivery **after
verification and after the chain is stored**, never before. A filter must
not be able to suppress a `%forged` message: rules are a standing
instruction and subject lines are guessable, so an attacker who learns your
rules could otherwise aim a forgery at one and have the evidence of it filed
somewhere you never look.

**The shape is what enforces that**, not a comment. A rule may add labels
and it may archive, and there is no field for deleting, rejecting or marking
read. By the time `+file-arrival` runs, every verdict is set and every copy
is on disk; all a rule can reach is a label and a flag.

A rule with **neither** a sender nor a subject matches every delivered chain,
and with `archive` set would empty the inbox permanently and silently. It is
refused, at the route and at the writer.

Order inside `+file-arrival`: the un-archive is the **default**, and the
matching rules are applied over it — so an archived thread comes back when
someone replies, and a rule that says "skip the inbox" still wins for the
mail that just arrived. The label cap refuses the *addition*, never the
delivery: nacking a chain because the user's own rule would overflow a cap
would turn a rule into a way for a sender to get their own mail rejected.

## Search

Substring match over subject, body and the rendered sender across stored
threads, computed on demand, case-insensitively. No index: state is capped,
and a linear sweep over that is acceptable and honest — it is the same sweep
the inbox listing already pays. It runs on a **request fiber**, never on the
writer: a search is a read, and a sweep placed on the writer would queue
every send and every delivery behind whatever someone typed into a box.

Search covers `%forged` messages, and **a result row is drawn from the
message that matched** rather than from the newest non-forged copy. That
rule is right for an ordinary listing and wrong for a search: answering a
search for a forgery with a row labelled `verified`, naming a ship that did
not write the thing that matched, would be the safety mechanism lying about
the result it was asked to find.

## Pagination

The listing takes an `offset` and a `limit` and returns a page plus a
`total`, so the UI can render controls without fetching everything. Applied
*after* the view predicate, so a page of the inbox is a page of the inbox
and not the inbox-shaped subset of the first fifty threads. Views other than
Inbox paginate identically. An absent `limit` defaults to 50 and is capped
at `max-page` (200); a `limit` of 0 is an empty page, literally.

Query arguments are parsed with `dim:ag` and not `dem:ag`. `dem` is the
**dot-grouped** decimal parser — it reads `9.999` and refuses `9999`, and
`+rush` wants the whole cord consumed — so every offset of four digits or
more fell back to 0 and handed the client page one while it believed it was
on page five hundred.

## Recipient validation

`@p` parsing in the UI before the poke, in the composer, in the reply chips
and in the filter editor, so a typo is caught at the keystroke rather than
surfacing as a refusal with no explanation. Structural rather than a
syllable dictionary: the client does not carry the syllable tables, and a
name that is shaped wrong is the mistake people actually make. The nexus
keeps its own validation — the UI is a convenience, not the boundary — and a
half-typed ship is kept out of a *saved draft's* recipient list, or autosave
would stop the moment someone started typing a name.

## The launcher tile

`/tile.json` and `/icon.svg`, both `%over` rows in `+on-load`, exactly as
lattice lays its own. The launcher lists only apps that carry a tile;
without it urmail is installed, running, serving and invisible from the
grubbery home screen, which reads as "not installed" to everyone but the
person who types the route by hand. `image` names the app **slug** — the
name before the first dot in `/apps/urmail.urmail_app` — not the folder.

The icon is a **nexus-root grub with a route of its own**, `GET
/apps/urmail/icon.svg`, owner-gated like everything else on this surface. It
needs one because `+serve-ui` otherwise looks under `/app`, where the client's
four files live and the icon does not — the tiles nexus reads it from the root.
Until that arm existed the path the `+on-load` comment named answered 404, and
the web manifest worked around it by carrying the icon inline as a `data:` URI.
It points at the route now.

## What none of this does

Rich text, threading collapse, keyboard shortcuts, contacts, spam
classification, delivery receipts, Thunderbird integration, and any bridge to
internet email.

Thunderbird in particular is explicitly not designed for. If it happens it is
an adapter written against whatever API exists then.

---


# History

urmail was first built as a **Gall agent** on its own `%urmail` desk: a
`sur/urmail.hoon`, a `lib/urmail.hoon`, a 382-line `app/urmail.hoon`, three
urmail marks and 37 library tests. It established everything this document still
claims — signing with the ship key, the three verdicts, `[id sig]`
anti-shadowing, `+merge`, `+prune`, `+thread-key`, `+freeze`, the caps — and it
was the reference the nexus was ported against, arm by arm.

It carried the **seven-field** `unsigned`, two format breaks behind the frozen
shape, so it shares no message with the shipping product: a chain from that
build reaches the nexus as a `%0` grub and is refused. Its 37 tests were a
strict subset of the overlay's 71. Keeping a working implementation of an
incompatible protocol in the tree was a liability, not a reference, so `desk/`,
its `deploy.sh` and the Gall implementation plan under `docs/superpowers/plans/`
were **removed in `a0d82ca`**. The last commit carrying them is **`db44982`**;
`git log -- desk` finds the whole history and `git show db44982:desk/app/urmail.hoon`
the agent itself.

The port itself, and the arguments it settled, are recorded in the slice reports
under `.superpowers/sdd/2026-09-07-urmail/` — which is **gitignored**, so those
reports live on this machine and nowhere else. `docs/verification.md` carries
what they proved.

---

# The client, second pass — compact, dark, responsive, installable

Six changes from the user after using it. All client; none touches the nexus
except a manifest and service worker served as grubs.

1. **Density.** Too much whitespace. Gmail's density: tight rows, one line per
   thread in the list, small type, no decorative padding. Compact is the
   default; there is no "comfortable" toggle.
2. **Dark mode.** Follows `prefers-color-scheme`, with a manual override that
   persists in `localStorage`. Every colour is a token; both palettes complete.
   `forged` must stay alarming in both — red on dark is not automatically
   legible.
3. **The verdict badge is too big.** `verified` becomes a small check mark with
   a tooltip on hover naming what it means ("signed by ~ship, signature
   verified against their key"). `unverified` a hollow mark, `forged` stays a
   visible red mark with the word — it is the one that must not shrink into
   ambiguity. Per message, as before; never per thread.
4. **Buttons.** Small, square-cornered, text-weight. Gmail's, not a toy's. One
   primary per surface; the rest are quiet.
5. **Responsive and installable.** Works on a phone: the three panes collapse
   to one with navigation between them; touch targets sized for fingers; no
   horizontal scroll ever. A full PWA: manifest, icons, a service worker that
   caches the shell so the app opens offline and shows cached mail, with a
   clear "offline" state and no false "sent". Install prompt on supported
   browsers. Served from the nexus as grubs like the shell and script.
6. **"All mail" leaves the sidebar.** The `all` view stays as an API primitive
   — search uses it to escape the current pane, and label discovery reads it —
   but it is not a place a user navigates to.

What does not change: per-message verdicts, honest copy counts, editable reply
recipients, the blast-radius line, and every rule under `## The web surface`
about what the client may and may not trust.

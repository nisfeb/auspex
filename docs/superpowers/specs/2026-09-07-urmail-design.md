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
=/  pub  .^(  (unit [suite=@ud =pass])
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

The exact product type of `%puby` should be confirmed against `keys` in the
jael state at implementation time; the shape above is read off the scry body but
has not been run.

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
[%deliver =chain]
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
- Cap chain length and body size, and reject rather than truncate.
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

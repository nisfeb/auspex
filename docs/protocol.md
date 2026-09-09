# The Auspex protocol, version 1

Auspex is mail on Urbit. Every message is signed by its author's ship; a reply
or a forward ships the root-to-parent path of signed messages alongside the new
one; a recipient verifies each message independently against the author's key
and stores a verdict per signed copy.

This document is the wire protocol. It is written for an implementer who has an
Urbit ship, jael, and no grubbery. The reference implementation is a grubbery
nexus, and nothing about grubbery is normative except the one transport
described in [§6](#6-transport).

**The code is the protocol.** Where this document and
`grubbery-overlay/lib/auspex-chain.hoon` disagree, the library wins and the
disagreement is a bug in this document. Where this document and
`docs/superpowers/specs/2026-09-07-auspex-design.md` disagree, see
[Appendix A: Discrepancies](#appendix-a-discrepancies).

The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are used as in
RFC 2119.

---

## 1. Scope and versioning

### 1.1 The version is the mark

**The protocol version is the wire mark name.** `%auspex-chain` is version 1.
There is no version field inside the payload and there MUST NOT be one: a
version field is covered by `msg-id` and by the signature, so bumping it would
invalidate every message ever signed.

A breaking change is a **new mark name**. An implementation that changes the
format MUST publish it under a different mark (`%auspex-chain-2`, say) and MUST
leave `%auspex-chain` meaning exactly what it means here.

### 1.2 What "breaking" means

A change is breaking if it changes either of:

- the shape of `$unsigned` — the number, order or type of its nine fields; or
- how `msg-id` or `digest` are computed from an `$unsigned`.

Both are breaking for the same reason: `msg-id` is `(sham unsigned)` and the
signature covers `(shaf %auspex (sham unsigned))`, so `sham` runs over the noun
itself. **Cell order matters.** A message signed against a different shape has a
different id and a signature that verifies against nothing, and it cannot be
migrated: rewriting a stored message into a new shape produces a message whose
signature no longer matches its own contents, which every peer then reads as
`%forged`. Turning genuine mail into apparent forgeries is worse than refusing
it.

This is stated in the library itself, in the comment above `$unsigned`:

```
::  AND THAT IS THE WHOLE OF IT. $unsigned is FROZEN. Nothing may be
::  added without breaking every message in existence, because a
::  signature covers a shape and rewriting the shape produces messages
::  every peer reads as forged.
```

Additions that are **not** breaking, because they touch nothing a signature
covers: new verdicts, new local state, new transports, new caps (a cap only ever
refuses; it never rewrites), and any change to how an implementation stores or
renders what it received.

### 1.3 Unknown marks

A receiver MUST nack a poke carrying a mark it does not implement, and MUST NOT
coerce the payload into `%auspex-chain`. A noun that arrived under an unknown
name is not a chain that failed to parse; it is a message for a protocol this
implementation does not speak, and guessing at it is how a v2 message becomes a
v1 forgery.

The reference implementation ignores an unrecognised blot rather than crashing
(`+apply`, `nex/auspex/app.hoon`: `::  an unknown blot. Ignore it rather than
crash`), because its writer must never fail — see [§6.4](#64-ack-and-nack).

---

## 2. The message

### 2.1 `$unsigned` — everything a signature covers

```hoon
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
```

As a noun: a **right-nested nine-tuple**, i.e.
`[from [life [to [subj [body [body-mime [sent [prev attachments]]]]]]]]`. There
is no header, no version and no padding. `sham` and therefore `msg-id` are
computed over exactly this noun, so **the order of the nine fields is part of
the protocol** and an implementation that builds the cell in any other order
produces a different id and an unverifiable signature.

The nine fields, in order:

| # | field | type | noun shape | meaning |
|---|---|---|---|---|
| 1 | `from` | `@p` (`ship`) | atom | the ship that signed. The key looked up for verification. |
| 2 | `life` | `@ud` | atom | the key life the signature was made under. |
| 3 | `to` | `(set ship)` | an `nlr` treap, or `~` when empty — see [§2.1.1](#211-the-noun-of-to-exactly) | the **visible** recipients. |
| 4 | `subj` | `@t` | atom (UTF-8 cord) | the subject. |
| 5 | `body` | `@t` | atom (UTF-8 cord) | the message body. |
| 6 | `body-mime` | `@t` | atom (UTF-8 cord) | how to read `body`. `''` means `text/plain`. |
| 7 | `sent` | `@da` | atom (Urbit date) | the **author's** clock. |
| 8 | `prev` | `(unit msg-id)` | `~`, or `[~ id]` | the parent message's id, or `~` for a thread root. |
| 9 | `attachments` | `(list attachment)` | `~`, or `[a rest]` | attachment **metadata**, never bytes. |

Field-by-field semantics and limits:

**`from`.** Who signed. A verifier MUST look up the key for `[from life]` and
MUST NOT look it up for any other ship — a message whose `from` names a ship
that did not sign it is exactly what a forgery is, and the mismatch is what the
verifier is there to find.

**`life`.** Travels with the message because signatures must outlive key
rotation: a message signed under life 3 stays verifiable after the sender
rotates to life 4, because the verifier looks up the key for the life the
message names. One ship therefore has several live keys, which is why the key
map is keyed `[ship life]` and never on the ship alone. `life` is
attacker-controlled: a tampered `life` names a key the verifier does not hold,
and the result is `%unverified`, never `%forged` — see
[§3.4](#34-the-three-verdicts).

**`to`.** The visible recipients, signed, so a relay cannot rewrite the audience
a message claimed. Capped at **100** per message (`max-to`, enforced by
`+fits-recipients`). BCC is deliberately absent: the chain proves authorship,
not delivery. A blind-copied recipient gets the same canonical bytes, the same
`msg-id` and the same thread as everyone else and sees the visible recipients,
which is what BCC means; nothing about the blind copy is signed, and no hashed
commitment to it is signed either.

**`subj`.** Capped at **1.000** bytes (`max-subj`, `+fits-subjects`, measured
`(met 3 subj)`).

**`body`.** Capped at **100.000** bytes (`max-body`, `+fits-bodies`, measured
`(met 3 body)`).

**`body-mime`.** Says how to read `body`; `''` means `text/plain`, so a sender
that does not care writes nothing. It is **signed** because the rendering
instruction is part of the message: one that says "render me as HTML" and one
that says "render me as plain text" are different messages, and an intermediary
MUST NOT be able to change which one is read. Capped at **128** bytes and
refused if it contains control bytes (`max-mime`, `+fits-body-mimes`, which
calls `+text-ok`). See [§2.2](#22-hostile-fields).

**`sent`.** The author's clock. **Display and ordering only.** An attacker
controls it completely, so nothing about identity, thread membership or filing
may derive from it. A receiver MUST NOT derive thread identity from `sent` (see
`+thread-key`, [§4.2](#42-thread-identity)) and MUST NOT reject a message for
being backdated or postdated.

**`prev`.** What makes a flat list a chain and a thread a tree. A reply points at
the message it answers; a forward points into the path it carries. `prev` names
a **message**, not a thread, and that is sufficient: `msg-id` is a hash over the
message's full contents, so it identifies exactly one message and therefore
exactly one thread. `prev=~` marks a thread root.

**`attachments`.** Metadata and a content hash, never bytes — see
[§5](#5-attachments). It sits **inside** `unsigned`, so it is covered by the
signature and by `msg-id`: swapping a file breaks the signature. Capped at **16**
per message (`max-attach`), each entry checked by `+attach-ok`.

### 2.1.1 The noun of `to`, exactly

`to` is a `(set ship)`, and **`sham` hashes the treap**. A `msg-id` for a
multi-recipient message is therefore not reproducible from a list of ships: it
depends on a tree shape, and an implementation that builds that shape any other
way computes a different id and a signature nobody can verify. This subsection
is normative.

**The mold.** A `(set ship)` is `nlr` — the null-or-right-recursive treap in
`hoon.hoon`, not `nl` — which is

```hoon
+$  nlr  $@(~ [n=ship l=nlr r=nlr])
```

Empty is the atom `~` (0). A node is the right-nested triple `[n [l r]]`: the
item, the left subtree, the right subtree.

**The two orders.** The tree is a treap, so it has both:

- **Vertically, by `mor`** — a max-heap on a double-`mug`:
  `(mor a b)` is `(lth (mug (mug a)) (mug (mug b)))` broken by comparing the
  atoms. Every node's `n` outranks both its children's.
- **Horizontally, by `gor`** — `(gor a b)` compares `(mug a)` against `(mug b)`
  and falls back to `dor` (raw atom/cell order) on a tie. Everything in `l`
  precedes `n`; everything in `r` follows it.

**Construction.** Build it exactly as `+put:in` does — insert each ship,
rotating to restore the heap — which is what `+sy` and `+gas:in` do. The result
is **canonical**: a set built from the same ships in any order is the same noun,
so two ships that typed their recipients in different orders compute the same
`msg-id`. An implementation MUST reproduce this noun; it MUST NOT substitute a
sorted list, a map, or a differently-balanced tree.

**Worked example.** `(sy ~[~zod ~nec ~bud])`:

| ship | `@p` | `mug` |
|---|---|---|
| `~zod` | 0 | 2.046.756.072 |
| `~nec` | 1 | 1.901.865.568 |
| `~bud` | 2 | 1.904.972.904 |

`~zod` has the largest `mug`, so it is the root; `~bud` outranks `~nec`, so it
is `~zod`'s left child and `~nec` is `~bud`'s. Both right subtrees are empty.
The noun is

```
[0 [2 [1 0 0] 0] 0]
```

— that is, `[n=~zod l=[n=~bud l=[n=~nec l=~ r=~] r=~] r=~]`. Its `jam` is
`0w5.kUIxp` (`0x1.54e2.c859`); the empty set's `jam` is `0w2`.

The `three-recipients` case in `protocol/vectors/v1.json` pins this: its `to` is
those three ships, and its `jam`, `msg_id`, `digest` and `sig` are what an
implementation that builds the treap correctly will produce. Every other signed
case in the file names **one** recipient and therefore pins nothing about the
shape.

### 2.2 Hostile fields

Three fields are **attacker-supplied and arrive pre-signed**: `body-mime`, and
each attachment's `name` and `mime`.

A signature proves the author **chose** a value. It proves nothing about whether
the value is safe, and the value arrives inside a chain any ship on the network
may deliver. A recipient cannot repair a signed field without destroying the
signature that makes the message evidence, so the only place to refuse one is
the boundary, before it is stored.

- A receiver MUST refuse a chain in which any `body-mime`, attachment `name` or
  attachment `mime` exceeds its length cap or contains a byte `≤ 0x1f` or
  `0x7f`. The predicate is `+text-ok`:

  ```hoon
  ++  text-ok
    |=  [t=@t m=@ud]
    ^-  ?
    ?&  (lte (met 3 t) m)
        %+  levy  (trip t)
        |=(c=@tD &((gth c 0x1f) !=(c 0x7f)))
    ==
  ```

  `mime` in particular is headed for a `Content-Type` header, where a CR or an
  LF is a header-injection primitive; `name` is headed for a filename.

- A renderer MUST NOT obey `body-mime`. It MUST match the value against a fixed
  allow-list, fall back to `text/plain` for anything else, and MUST NOT pass the
  value into any header or `Content-Type`. **`body-mime` is reported, never
  obeyed.** The reference client renders every body as plain text and says so
  when the message asked for something else.

- An attachment `name` MUST be sanitised before it reaches a
  `Content-Disposition` header or a filesystem path, in addition to the
  boundary check above.

`sent` is hostile in a different way: it is well-formed by construction and
still entirely a lie if the author wants it to be. It is safe to display and
unsafe to decide anything with.

### 2.3 `msg-id`

```hoon
++  id
  |=  u=unsigned
  ^-  msg-id
  (sham u)
```

`msg-id` is `@uv`. It is `(sham unsigned)` — the `sham` of the whole nine-tuple
noun, with no salt and no wrapping. It covers exactly what a signature covers,
so an id and a signature agree by construction, and two ships that hold the same
message compute the same id without coordinating.

An implementation MUST NOT compute a message id any other way, and MUST NOT
include `sig` in it: two copies of one message that differ only in signature
share an id, and that is load-bearing — see [§4.4](#44-merge-and-the-id-sig-key).

### 2.4 `digest`

```hoon
++  digest
  |=  u=unsigned
  ^-  @
  (shaf %auspex (sham u))
```

The digest is `(shaf %auspex (sham unsigned))`. **The domain-separation tag is
the term `%auspex`**, passed as `shaf`'s salt.

This is mandatory, not a nicety. The same ship key signs Ames packets and
attestations. A signature produced with that key over attacker-chosen bytes is a
forgery primitive if the byte spaces overlap; the `%auspex` salt keeps the
auspex preimage space disjoint from every other use of the key, so an auspex
signature can never be replayed as one of those and vice versa.

An implementation MUST use `shaf` with the salt `%auspex` and MUST NOT sign a
bare `sham`, a raw body, or any other preimage.

> Historical note: the real-planet transcript in `docs/verification.md` was run
> when the app was called urmail and shows the salt `%urmail`. The salt is
> `%auspex` in this version and messages salted `%urmail` are not version-1
> auspex messages.

### 2.5 `$msg` and the signature field

```hoon
+$  msg    [=unsigned sig=@ux]
+$  chain  (list msg)
```

A `$msg` is the pair `[unsigned sig]` — `unsigned` in the head, the signature
atom in the tail. `sig` is **outside** `unsigned` and is therefore covered by
neither `msg-id` nor the signature, which is what allows two signed copies of one
message to exist and be told apart.

---

## 3. Signing and verification

### 3.1 Signing

```hoon
++  sign-with
  |=  [=ring msg=@]
  ^-  @ux
  (sigh:as:(nol:nu:cric:crypto ring) msg)
```

To sign, an author:

1. builds the nine-field `$unsigned`;
2. computes `(digest unsigned)` = `(shaf %auspex (sham unsigned))`;
3. reads its own current life — jael `%life`, scry path
   `/j/life/(scot %p our)`, in dojo form `.^(@ud %j /=life=/(scot %p our))`;
4. reads its **networking private key ring at that life** — jael `%vein`, scry
   path `/j/vein/(scot %ud life)`, in dojo form `.^(ring %j /=vein=/1)`. The
   `%vein` scry is gated on the requesting ship being `our`;
5. signs: `(sigh:as:(nol:nu:cric:crypto ring) digest)`;
6. sets `life` in the `$unsigned` to the life it just used — **before** step 2,
   since `life` is one of the nine signed fields.

The signature MUST be made with the ship named in `from`, at the life named in
`life`. A signature made with any other key is a forgery, and it is a forgery
that a verifier can and will detect.

### 3.2 Verification

```hoon
++  verify-with
  |=  [=pass sig=@ux msg=@]
  ^-  ?
  (safe:as:(com:nu:cric:crypto pass) sig msg)
```

To verify one message, a verifier:

1. computes `(digest unsigned)` from the message's own `unsigned`;
2. obtains the public key for `[from.unsigned life.unsigned]`
   ([§3.3](#33-obtaining-a-key));
3. if no key: the verdict is `%unverified`, and verification stops;
4. otherwise `(safe:as:(com:nu:cric:crypto pass) sig digest)` — `%verified` on
   `%.y`, `%forged` on `%.n`.

**Verification is per message, never per chain.** One chain routinely yields
several different verdicts: a forwarded chain whose forwarder we know and whose
original author we do not yields `%verified` for one message and `%unverified`
for another. An implementation MUST NOT compute a single verdict for a chain,
MUST NOT let one message's verdict influence another's, and MUST NOT render a
thread-level verdict. A thread holding one unverified message is not an
unverified thread.

### 3.3 Obtaining a key

The public key for `[who life]` comes from jael's **`%puby`** scry, the unitized
public-key read:

```
.^((unit [crypto-suite=@ud =pass]) %j /=puby=/(scot %p who)/(scot %ud life))
```

`%puby` returns `~` for a ship absent from the local Azimuth snapshot rather
than blocking. An implementation SHOULD use `%puby` and SHOULD NOT use `%deed`:
`%deed` blocks, and a blocking scry stalls whatever runs it.

The ship's **current** life comes from `%life`:

```
.^(@ud %j /=life=/(scot %p who))
```

Live transcript, `~martyr-sanryg`, a real planet, 2026-09-08:

```
> .^(@ud %j /=life=/~zod)
6
> .^((unit [@ud @]) %j /=puby=/~zod/6)
[~ [1 2.224.943.983…]]
```

crypto-suite `1` is suite `%b`, the same suite the fake-ship derivation uses, so
`com:nu:cric:crypto` handles real and fake keys identically.

**Jael answers scries only at exactly `now`.** Its scry arm opens with
`?.  &(=(lot [%$ %da now]) =([~ ~] lyc))  ~`, so a request at any other date
returns `~`, which blocks. An implementation MUST scry jael only with the
current `now`, MUST NOT cache a jael answer against a stored date and MUST NOT
scry jael from any context that lacks a live `now`. This is the whole reason the
reference implementation splits into **pure gates** that take keys as arguments
and do all the signing, verifying and digesting, and **thin wrappers** that only
the live agent calls. Every arm quoted in this document is on the pure side and
scries nothing.

An implementation SHOULD perform **one key lookup per distinct `[ship life]`**
appearing in a chain, not one per message — see `max-signers` in
[§4.6](#46-the-caps).

### 3.4 The three verdicts

```hoon
+$  verdict  ?(%verified %unverified %forged)
```

| verdict | rule |
|---|---|
| `%verified` | a key was found for `[from life]` **and** the signature checks against it. |
| `%forged` | a key was found for `[from life]` **and** the signature fails against it. |
| `%unverified` | **no key** was found for `[from life]`. |

The exact arm:

```hoon
=/  k  (~(get by keys) [from.unsigned.m life.unsigned.m])
?~  k  %unverified
?~  u.k  %unverified
?:  (verify-with u.u.k sig.m (digest unsigned.m))
  %verified
%forged
```

**A missing key MUST NOT produce `%forged`.** Absence of a key is not a finding
about a signature. It is indistinguishable, from the verifier's side, between an
honest ship whose key at that life we simply never fetched and a tampered `life`
field pointing at a life we do not hold — and accusing a ship of forgery on a
key we never had is exactly the false-accusation failure the verdict scheme
exists to avoid.

**`%forged` messages MUST be stored and displayed as forged.** They are
evidence, and deleting evidence is the wrong instinct. A receiver MUST NOT drop,
hide or filter a `%forged` message: a filter that could suppress one would let
an attacker who learns your rules hide the evidence of their own forgery. A
receiver SHOULD exclude `%forged` messages from unread counts and from the
normal inbox ordering, and MUST still return them from search, labelled.

The verdict is **local state**. It is one ship's reading of one signature against
that ship's Azimuth snapshot at one instant. It never travels ([§7](#7-local-state-is-not-protocol)).

### 3.5 Moons and comets

Third parties cannot verify moons or comets under this version, and that is a
property of Azimuth rather than a gap in the format. `%earl` hands out a moon's
key only to that moon's parent; `%deed` handles comets only when the comet asks
about itself. So mail from `~mister-botter-dozzod-nisfeb` verifies for `~nisfeb`
and for nobody else, and **an entire class of sender reads `%unverified` on
every other ship**.

This is why `%unverified` outranks `%forged` in `+prune`
([§4.5](#45-prune)): an unranked fill would let junk copies evict the one
genuine copy of a moon's message, leaving a user holding only forgeries of a
message that was never forged.

Signatures are already in the chain the day either fix lands. Comets are
self-signing addresses, so a comet's signature is verifiable with no lookup at
all given the code to derive it; moons need their parent's attestation to travel
inside the chain. Neither changes the format; both are strictly additive.

### 3.6 Fake ships

Jael derives every keypair on a fake ship from the `@p`, so on a fake ship any
ship's keys are computable:

```hoon
++  fake-core  |=(who=ship (pit:nu:cric:crypto 512 who %b ~))
++  fake-ring  |=(who=ship `ring`sec:ex:(fake-core who))
++  fake-pass  |=(who=ship `pass`pub:ex:(fake-core who))
```

**How a verifier tells a fake ship from a real one:** it asks jael.

```
.^(? %j /=fake=)
```

— jael's `%fake` scry, path `/j/fake`, answering a loobean.

`%puby` has **no fake-ship branch** the way `%deed` does: it reads `pos.zim`
directly and returns `~` for any ship the fake ship has no Azimuth snapshot of,
which on a fake ship is essentially every ship. Left alone, every message in
development would read `%unverified`.

A verifier therefore MUST check `%fake` first and, when it answers `%.y`, derive
the peer's public key with `(pit:nu:cric:crypto 512 who %b ~)` instead of
scrying `%puby`. This mirrors what `%deed` does for fake ships rather than
inventing a development mode. The reference implementation is `+peer-pass`:

```hoon
?:  fake  (pure:m `(fake-pass:uc who))
```

Consequences an implementer must accept:

- On a fake ship, `life` is effectively ignored by the key lookup: `+fake-pass`
  takes only the `@p`, so **every** life of a fake ship resolves to the same
  key. A message claiming `life=99` from a fake ship therefore verifies on
  another fake ship. To produce `%unverified` deterministically on a fake ship,
  a vector must name a ship the verifier deliberately omits from its key map —
  see [§8](#8-conformance).
- The fake-ship derivation is what makes the strongest test cheap: a test can
  forge a genuine signature as a third ship, put it in a chain and verify it —
  the third-party forward case, with no network and no second ship.

---

## 4. The chain, the thread, the path

### 4.1 `$chain`

```hoon
+$  chain  (list msg)
```

A chain is a **list of `$msg`**, and nothing more. It carries no header, no
thread id, no sender field and no ordering guarantee: order is chosen by whoever
sent it, and whoever sent it may be hostile.

A chain is a **root-to-leaf path**, not a whole thread. `prev` makes a thread
branch — two people replying to one message are siblings, and mail threads
branch constantly — so a thread is a tree and a chain is one path through it:
the conversation leading to a message, which is exactly what a recipient needs
to verify that message.

### 4.2 Thread identity

```hoon
++  thread-key
  |=  [threads=(map thread-id thread) c=chain]
  ^-  thread-id
```

Thread identity is derived by `+thread-key` and by nothing else. The rules:

1. **An established thread's identity is immutable.** If any `[id sig]` in the
   incoming chain matches a copy already stored in some thread, the chain files
   into **that** thread, whatever else it contains. This is what stops a poke
   carrying one message we already hold plus a brand-new `prev=~` message from
   migrating an established conversation onto an attacker-chosen id.

2. **Otherwise, first contact anchors on the unique `prev=~` root.** The roots
   are deduped **by id**, not counted by message:

   ```hoon
   =/  roots  (skim c |=(m=msg ?=(~ prev.unsigned.m)))
   =/  root-ids
     (~(gas in *(set msg-id)) (turn roots |=(m=msg (id unsigned.m))))
   ?.  =(1 ~(wyt in root-ids))  ~|(%auspex-no-unique-root !!)
   (snag 0 ~(tap in root-ids))
   ```

   Deduping by id is required: a hostile relay can forward the genuine root
   alongside a copy with a tampered signature, and both copies carry `prev=~`
   because `prev` is part of the signed payload they share. Counting messages
   would reject that otherwise-legitimate first contact.

3. **A chain with no root, or with more than one distinct root id, MUST be
   refused.** The library crashes with `%auspex-no-unique-root`; a receiver MUST
   call it defensively (the reference nexus wraps it in `mule`) and nack.

4. Identity MUST NOT be derived from the incoming list's order, and MUST NOT be
   derived from `sent`. An attacker controls both, so either would let one poke
   duplicate an existing conversation under a fresh id, or migrate an
   established thread onto a new one. `+root` (which returns the head
   as-supplied) is a convenience for a chain the local ship built and MUST NOT
   be used on an incoming one.

`$thread-id` is a `$msg-id`: the id of the thread's root message. Two ships
holding the same conversation agree on it without coordinating, because the
root message is byte-identical for both.

### 4.3 What a send ships: `+path-chain` and `+with-root`

```hoon
++  path-chain
  |=  [c=chain i=msg-id]
  ^-  chain
  =/  keep=(set msg-id)  (~(gas in *(set msg-id)) (ancestors (prev-map c) i))
  (merge ~ (skim c |=(m=msg (~(has in keep) (id unsigned.m)))))
```

A sender MUST ship the **path from the thread root down to the message being
replied to or forwarded, plus the new message**, and nothing else.

- The ancestry is computed by walking `prev` upward (`+ancestors`), which
  terminates on `prev=~` (a root), on an unresolvable `prev` (an orphan — see
  [§4.7](#47-orphans-and-cycles)), or on a bound equal to the number of distinct
  ids (a cycle guard).
- **Every stored copy at each node travels**, not one copy per node. Choosing
  which of two copies of one message to forward would be exactly the shadowing
  `+merge` exists to prevent, decided by the forwarder.
- **Sibling branches MUST NOT travel.** Shipping the whole thread instead is a
  **leak**: two participants have a side exchange on one branch, one of them
  forwards a message on a different branch onward, and the third party receives
  the side exchange — signed, permanent, attributable, and nobody asked for it.

The result is a valid chain on its own: every `prev` in it resolves inside it,
it holds the unique `prev=~` root, so the recipient's `+thread-key` files it
under the same thread id and every message still verifies independently.

`+with-root` covers the one case a path alone breaks:

```hoon
++  with-root
  |=  [c=chain p=chain]
  ^-  chain
  ?:  (lien p |=(m=msg ?=(~ prev.unsigned.m)))  p
  (merge p (skim c |=(m=msg ?=(~ prev.unsigned.m))))
```

A well-formed path already ends at `prev=~` and this is a no-op. It fires only
for an **orphan** branch, where shipping the path alone would hand the recipient
a chain with no `prev=~` message at all — which `+thread-key` refuses outright,
so the send would look successful at the sender and be dropped at the far end.
The root is a message every participant already holds and is what the thread's
identity is derived from, so adding it discloses nothing.

A sender MUST apply the same caps to its outgoing chain that a receiver will
apply on arrival ([§4.6](#46-the-caps)). Every send ships the path it replies
into, so one oversized compose poisons a thread permanently: every later message
on that path is rejected by every recipient, silently, forever. Failing at
compose time is the only point where a human can still do something about it.

### 4.4 `+merge` and the `[id sig]` key

```hoon
++  merge
  |=  [old=chain new=chain]
  ^-  chain
  =/  key  |=(m=msg [(id unsigned.m) sig.m])
```

**`+merge` deduplicates on `[id sig]`, never on the id alone.** A message is a
duplicate only when its contents **and** its signature match.

The reason is a concrete attack. `+id` covers `unsigned` alone, so two messages
can share an id and carry different signatures — one genuine, one forged.
Deduping on the id alone would let whichever arrived first **shadow** the other,
which on a forwarded chain lets a malicious forwarder frame a third party as a
forger: deliver the forged copy first, and the genuine one is discarded as a
duplicate, leaving the recipient holding a `%forged` message attributed to an
innocent ship. Both copies are kept here; verification labels them separately;
the reader decides what to show.

The same key is used everywhere a signed copy is named:

- verdicts are keyed `[msg-id @ux]` (`+verify-chain`, `+freeze`) — keying a
  verdict on the id alone would collapse `%verified` and `%forged` into
  whichever was written first, reinstating the shadowing attack at the state
  layer;
- storage keys a copy by `[id sig]`;
- `+thread-key`'s "do we already hold this?" scan matches on `[id sig]`.

`+prev-map` is the deliberate exception: it is keyed by **id**, because `prev`
sits inside `unsigned` so every copy of one id carries the same `prev` by
construction. Two copies differing in signature are **one node** of the tree
carrying two grubs.

`+merge` also dedupes `new` against itself, not only against `old`, since a
peer-supplied chain may repeat a message and `old` is empty on first contact.
The result is sorted by `sent`, then by id, then by `sig` — a total order, so
two ships merging the same messages produce the same list.

### 4.5 `+prune`

```hoon
++  prune
  |=  [c=chain vs=(map [msg-id @ux] verdict) max-copies=@ud]
  ^-  chain
```

`+prune` enforces the per-id copy bound (`max-copies`, **4**) by **shedding**,
never by rejecting.

- It MUST NOT reject. Rejecting the merged result is a **censorship primitive**:
  an attacker who lands `max-copies` forged copies of a chain's genuine root at
  a ship that has never seen the thread mints that thread under the genuine,
  content-derived id, holding it full of junk. When the real chain later arrives
  from any participant the count is `max-copies+1`, a reject would nack it, and
  because every send ships the whole path, **every subsequent message in that
  thread would be rejected forever** — for the cost of a few junk-signed
  messages. It also reinstates, at the state layer, precisely the shadowing
  `+merge` exists to prevent.
- It sheds in **strict verdict order**: `%verified` first, then `%unverified`,
  then `%forged`. A `%verified` copy MUST NOT be shed while any copy of a lower
  rank remains.
- The `%unverified` rank is not a nicety: every moon and comet message is
  `%unverified` in version 1, so an unranked fill lets `max-copies` junk copies
  evict the one genuine copy of a moon's message.
- A verdict missing from the map defaults to `%unverified`
  (`(~(gut by vs) [i sig.m] %unverified)`).

This is the general rule, and an implementation MUST follow it:
**input validation rejects; merged-state capacity sheds.** Rejecting on merged
state punishes a legitimate poke for excess that may be entirely attacker junk
already on disk.

`+freeze` folds a poke's verdicts into the stored ones, definitive labels first:

```hoon
?:  ?=(?(%verified %forged) (~(gut by acc) -.i.new %unverified))
  $(new t.new)
```

`%verified` and `%forged` are definitive for a fixed `[id sig]` — the digest and
the key are both fixed — so they can never disagree with each other and MUST NOT
be overwritten. `%unverified` is not a finding about the signature, only that
the key was absent from our snapshot at that instant, so it MUST remain
upgradable by a later poke arriving after the key was fetched.

### 4.6 The caps

Every cap is a number, defined as an arm in `lib/auspex-chain.hoon`. A receiver
MUST enforce each of these on an incoming chain, and MUST reject the chain whole
rather than truncating it: a chain that violates a limit is not partially
trustworthy, and trimming a signed field would forge.

| cap | value | predicate | what it bounds |
|---|---|---|---|
| `max-chain` | 1.000 | `+fits-length` (incoming), `+distinct-ids` (merged) | messages per chain / distinct ids per thread |
| `max-body` | 100.000 | `+fits-bodies` | bytes per body |
| `max-subj` | 1.000 | `+fits-subjects` | bytes per subject |
| `max-to` | 100 | `+fits-recipients` | recipients per message |
| `max-mime` | 128 | `+fits-body-mimes` (→ `+text-ok`) | bytes of `body-mime`, and of an attachment `mime` |
| `max-attach` | 16 | `+fits-attachments` (→ `+attach-ok`) | attachments per message |
| `max-blob` | 262.144 | `+attach-ok` | claimed bytes of one attachment |
| `max-name` | 256 | `+attach-ok` (→ `+text-ok`) | bytes of an attachment filename |
| `max-depth` | 64 | `+fits-depth` (→ `+max-ancestry`) | ancestors from root to leaf |
| `max-signers` | 128 | `+fits-signers` (→ `+signers`) | distinct `[ship life]` pairs per chain |
| `max-copies` | 4 | `+prune` | signed copies of one id (**shed**, not rejected) |
| `max-threads` | 10.000 | receiver's own check | distinct threads this ship will hold |

Two caps deserve their reasoning stated, because an implementer will otherwise
pick different numbers:

**`max-depth` (64).** Depth is not off the read path. A message is stored under
its ancestry, so its key carries one ~34-byte segment per ancestor, and a
receiver rebuilds those keys on every read of the mail tree. Cost is quadratic
in depth, and `max-chain` alone would let one hostile linear chain pin a thread
at depth 1.000 permanently: measured, 200 messages at depth 200 already cost
~1.8× the same 200 at depth 2. It is checked on the single poke **and** on the
merged result, since two chains each inside the cap can compose past it. The
cost, stated plainly: a thread genuinely deeper than 64 accepts no further
messages.

**`max-signers` (128).** The one cap that bounds work **off** this ship. Every
other limit bounds bytes or nodes; this one bounds **round trips**, because a
key comes from one scry per distinct `[ship life]`. Unbounded, one junk chain
could name a thousand distinct signers and buy a thousand sequential lookups
plus a thousand ed25519 verifies — and a forged signature costs exactly what a
real one does. The number is chosen against `max-to`, not against what a
conversation looks like: one message may already name 100 recipients, so a
thread in which every named recipient replies once is 100 signers and is
legitimate; 128 clears that with room for the key rotations that make one ship
two entries, since a signer is `[ship life]` and not a ship. This caps **one
poke, not a sender**: a peer willing to send a thousand pokes still buys a
thousand times this, and a per-source rate budget is the real answer and is not
built.

The blob-store caps (`max-blobs` 1.000, `max-blob-bytes` 33.554.432) bound a
receiver's own storage and are not protocol: bytes only ever enter through a
**local** action, never through a delivered chain, which carries metadata alone.

### 4.7 Orphans and cycles

An **orphan** is a message whose `prev` names an id not present in the chain.
`+ancestors` stops there and the message is **placed as a root of its own**
rather than dropped: only hostile input makes an orphan — a forwarded path is
complete by construction and `+prune` never sheds the last copy of an id — and
refusing to store a message is worse than filing it shallow. An orphan later
joined to its parent simply moves.

A `prev` **cycle** is impossible in practice (it needs a hash preimage loop) but
`+ancestors` runs on attacker-supplied input, so the walk is bounded by the
number of distinct ids and MUST terminate. An implementation MUST bound this
walk.

Note the interaction with `+thread-key`: an orphan is placed, but a chain that
contains **no** `prev=~` message at all is still refused
([§4.2](#42-thread-identity) rule 3), because thread identity has nothing to
anchor on.

### 4.8 The receiver's order of operations

`+deliver` in `nex/auspex/app.hoon` is the reference receiver. The order is
load-bearing and an implementation MUST follow it: **cap, then verify, then
resolve identity, then merge, then prune, then store, then the beacon.**
Nothing is written before every signature in the incoming chain has a verdict.

1. **Decode.** Clam the poked noun into `$chain` inside a `mule`. A malformed
   payload MUST be refused as a clean branch, not as a crash — see
   [§6.4](#64-ack-and-nack). An empty chain is a silent no-op.

2. **Cap checks, in this order**, each a whole-chain refusal:
   `+fits-length` (`max-chain`), `+fits-bodies` (`max-body`), `+fits-subjects`
   (`max-subj`), `+fits-recipients` (`max-to`), `+fits-attachments`
   (`max-attach`), `+fits-body-mimes` (`max-mime`), `+fits-depth`
   (`max-depth`), `+fits-signers` (`max-signers`).

   `+fits-signers` is checked **last among the caps and before any key lookup**,
   deliberately: the two steps below are exactly the cost it bounds.

3. **Build the key map.** One lookup per distinct `[ship life]` in
   `(signers c)`. Check `%fake` once; on a fake ship derive with `+fake-pass`,
   otherwise scry `%puby`.

4. **Verify every message.** `+verify-chain` produces one
   `[[msg-id sig] verdict]` per message. Never one verdict for the chain.

5. **Resolve thread identity.** `+thread-key` against the threads already held,
   defensively (the reference wraps it in `mule`). A chain with no unique root
   is refused here.

6. **Merge.** `+merge` the stored chain for that thread with the incoming one,
   on `[id sig]` ([§4.4](#44-merge-and-the-id-sig-key)).

7. **Merged-state caps**, which are a different question with a different
   answer for two of them:
   - `(distinct-ids new)` against `max-chain` — **rejects**. Shedding a distinct
     non-root id would orphan the `prev` pointers of later messages. This is a
     known censorship vector; see [Appendix B](#appendix-b-known-costs).
   - `+fits-depth` on the merged chain against `max-depth` — rejects.
   - `max-threads`, **only for a brand-new thread id**. An existing thread
     always accepts: a reply MUST NOT be refused because some unrelated thread
     filled the cap.

8. **Freeze verdicts, then prune.** `+freeze` folds this poke's verdicts into
   the stored ones **before** pruning, because `+prune` needs a verdict for
   every message in the merged chain, including ones stored by an earlier poke
   that this one did not carry. Then `+prune` at `max-copies`.

9. **Store.** Write the pruned chain, one grub per `[id sig]`, each carrying its
   own verdict. A redelivery that writes nothing MUST be reported as no change.

10. **Local filing, after storage and after every verdict is set.** New mail
    un-archives the thread; then the receiver's own filters may add labels and
    archive it again. Nothing at this stage can suppress a message, because by
    this point the chain is on disk with its verdicts.

11. **The change beacon.** Bump a local change signal **only if the tree
    actually changed**. A bump on a refusal, or on a redelivery that wrote
    nothing, is free remote amplification: delivery is open to any ship, and
    one bump costs every open client a full listing.

**Which refusals nack and which are silent.** In the reference implementation
every refusal in `+deliver` is a clean return that records a reason to a local
trace grub; the poke is **acked** and the chain is dropped. Only a malformed
noun that fails to clam, or a transport-level failure, produces a nack. This is
a deliberate consequence of the writer-must-not-crash rule
([§6.4](#64-ack-and-nack)) and it means **a sender cannot distinguish a refused
chain from an accepted one over the wire.** An implementation MAY nack a
refusal instead; it MUST NOT crash on one.

---

## 5. Attachments

### 5.1 `$attachment`

```hoon
+$  attachment
  $:  name=@t          ::  original filename
      size=@ud         ::  bytes
      mime=@t          ::  content type
      hash=@uv         ::  (sham octs) over the contents
  ==
```

A right-nested four-tuple `[name [size [mime hash]]]`, living in
`attachments.unsigned` and therefore **inside the signature and inside
`msg-id`**. Swapping a file breaks the signature. That placement costs the chain
about 100 bytes per attachment whatever the file weighs, which is the point: the
chain travels whole on every send, so bytes must not live in it.

### 5.2 The content address

```hoon
++  blob-hash
  |=  =octs
  ^-  @uv
  (sham octs)
```

`hash` is `(sham octs)` over the content — **over the `octs`, not over the bare
atom**. An atom loses leading zero bytes, so two files differing only in leading
zeros would share an address; `octs` (`[p=@ud q=@]`, length then atom) carries
the length, so they do not. It also ties `size` into the address: **a lie about
the size is a lie about the content address.**

Acceptance is one line:

```hoon
++  blob-ok
  |=  [=octs h=@uv]
  ^-  ?
  =(h (blob-hash octs))
```

### 5.3 Caps

| cap | value | applies to |
|---|---|---|
| `max-blob` | 262.144 | bytes in one attachment |
| `max-attach` | 16 | attachments per message |
| `max-name` | 256 | bytes of `name` |
| `max-mime` | 128 | bytes of `mime` |

`max-blob` is 256K rather than something round and large because a blob is
answered over remote scry, which fragments the response into Ames packets, and a
multi-megabyte fetch is a lot of packets for an operation with no
partial-progress story.

The incoming predicate is `+fits-attachments`, which applies `+attach-ok` per
attachment:

```hoon
++  attach-ok
  |=  a=attachment
  ^-  ?
  ?&  (lte size.a max-blob)
      (text-ok name.a max-name)
      (text-ok mime.a max-mime)
  ==
```

**A receiver MUST NOT trust `size` beyond the cap.** `size` is checked against
`max-blob` at the boundary because an attachment claiming a gigabyte is a claim
we would never honour and rejecting it there is cheaper than discovering it at
fetch time. It is **not** evidence of what the bytes weigh: the authority is the
hash, and the bytes are re-measured and re-hashed on arrival regardless of what
`size` said.

### 5.4 Fetching bytes

Bytes are **never pushed**. Receiving a chain stores the chain immediately; a
ship that wants an attachment it lacks fetches it **on demand, by hash**.

This MUST be an explicit action, not something delivery triggers: a chain from a
stranger naming a hundred attachments must not make a ship go fetch them.

The fetch is a **`%keen`** over the remote-scry namespace — the kernel scry
farm, which is the only permissionless channel; peeks and keeps are both
weir-gated and a cross-ship peek between un-granted peers hangs rather than
failing. That asymmetry is what auspex wants: any ship holding the bytes can
serve them, and the hash proves them.

A publisher binds each blob in its own gall farm at:

```hoon
++  blob-spur
  |=  h=@uv
  ^-  path
  /auspex/blob/[(scot %uv h)]
```

A fetcher constructs the ames spar path, which MUST mirror `+blob-spur` exactly:

```hoon
++  blob-keen-path
  |=  [agent=@ta h=@uv case=@ud]
  ^-  path
  %+  weld  `path`[%g %x (scot %ud case) agent %$ %'1' ~]
  (blob-spur h)
```

Rendered: `/g/x/<case>/<agent>/''/1/auspex/blob/<hash>`, where

- `g` is gall and `x` is the value care;
- `<case>` is the gall case. A spur never grown and never culled binds at
  **case 1**, so case 1 is the answer for a content-addressed blob and a re-grow
  of the same bytes leaves it bound and correct;
- `<agent>` is the **yoke** whose farm is read — the gall agent, `%grubbery` in
  the reference implementation, not the nexus. An implementation on a plain gall
  agent names its own agent here;
- `''` is **the empty segment, and it is load-bearing**: the publisher's ames
  takes the head of the spur as the beam's desk slot and the tail as `s.bem`,
  and gall's `+scry` sends anything not starting with the empty knot to the
  agent's `+on-peek` instead of to the vane's scry farm. A path literal cannot
  spell it, so the path is built by cons;
- `1` is the namespace version marker gall's `+scry` requires.

There is **no revision segment**. A blob's bytes are fixed by its name, so a
content-addressed spur needs no rev-discovery channel — and rev-discovery is the
weir-gated part.

The answer is a `$page` — `[mark=@tas noun]` — whose mark MUST be
**`%auspex-blob`** (`+blob-page-mark`) and whose noun MUST be an `$octs`. A
fetcher MUST discard anything else.

**Case probing.** Case 1 covers every ordinary blob. The one operation that
burns a case is restriction: culling a spur parks the culled case as a
high-water mark, so a blob restricted and later re-published answers at case 2
permanently. The reference fetcher probes up to `+max-case-probe` = **3**,
costing one timeout per miss, paid only by a blob that has actually been
restricted. Relatedly: a publisher MUST NOT `%grow` a spur it has not first
established is unbound — `+grow` assigns `las+1` on a non-empty fan, so three
idempotent-looking "make public" presses push a binding past the probe ceiling
and the attachment becomes unfetchable by every peer, forever, with no error.

**On arrival, the bytes MUST be re-hashed.** The reference receiver, in order:

```
?~  res.b                              → discard: the fetch missed
?.  (lte p.u.res.b max-blob:uc)        → discard: 'blob too large'
?.  (gte p.u.res.b (met 3 q.u.res.b))  → discard: 'blob malformed'
?.  (blob-ok:uc u.res.b hash.b)        → discard: 'blob hash mismatch'
```

**A blob whose contents do not hash to the address it was fetched under MUST be
discarded**, without comment and without being held against the sender. The ship
named in a fetch request is a **hint about where to look and confers nothing**;
the hash is what proves the bytes. Blobs are a cache: losing one loses a file,
never a message and never a signature.

**A fetcher republishes what it accepted**, because it is now one of the ships
holding the bytes.

### 5.5 Restriction is withdrawal, not access control

`%public` is the default. A chain is forwardable to anyone by construction, and
an attachment only the original recipients could read would make every forward
carry an unreadable file.

Restriction withdraws **our own copy** from our farm. Because a fetcher
republishes, the first successful fetch creates a second, independent,
un-revocable source, and withdrawing ours after that stops nobody.

**What restriction buys is exactly this:** bytes we have not yet served cannot
be pulled from us, and a hash is not a capability we hand out by default once we
have said no. An implementation MUST present it as unpublishing and MUST NOT
present it as revoking or as permission. Anything that presents it as revocable
permission is lying to the user, and the same reasoning that makes a chain
portable makes a blob unrecallable — that is the trade this design took
deliberately when it chose the hash as the authority.

Blob visibility is **local state** and never travels ([§7](#7-local-state-is-not-protocol)).

> The HTTP-side blob routes (`POST /api/blob`, `GET /api/blob`) are a property of
> the reference client's web surface, not of the protocol, and are out of scope
> here.

---

## 6. Transport and discovery

### 6.1 The transport is the grubbery nexus

**The transport is a poke of mark `%auspex-chain` to the recipient's Auspex
nexus writer, through grubbery's `%grub-cmd` surface.** A conformant peer runs
grubbery with the Auspex nexus installed. There is no second endpoint and none
is planned: the nexus *is* the protocol's endpoint, and an implementation
conforms by speaking to it.

A sender delivers a chain by **poking the recipient's auspex writer** with mark
`%auspex-chain` and the chain as the payload noun.

The writer is the grub `main.sig` at the auspex nexus root, and the blot is:

```
[/ %auspex-chain]
```

— a **top-level** mark with an `auspex-` name prefix, not a path-prefixed blot.
That is forced: the `%grub-cmd` agent surface flattens a blot to its bare name
(`mark=@tas`), and a dojo poke names a bare mark too, so a delivery blot with a
path prefix is unaddressable by a foreign ship. The `auspex-` prefix is what
keeps a top-level file in a shared tree from shadowing grubbery's own.

`+send-one` is the sender:

```hoon
++  send-one
  |=  [root=path c=chain:uc who=ship]
  =/  rd=road:tarball  (remote-road [%& %& root %'main.sig'] who)
  ;<  res=(unit (unit tang))  bind:m
    ((deadline ,(unit tang)) send-timeout (poke-soft:io rd [[/ %auspex-chain] c]))
```

`+remote-road` rewrites the local absolute road into the peer's `/sys/ames`
mirror, `/sys/ames/ships/<who>/root/<path>`, so the dart routes to that ship;
the peer's auspex sits at the same absolute path its own root nexus gave it,
`/apps/auspex.auspex_app`.

**The exact noun a sending agent pokes.** Poke the recipient's `%grubbery`
agent with mark **`%grub-cmd`** and the noun:

```hoon
:-  chan=@ta                          ::  your return channel id
:^  %poke
  path=/apps/'auspex.auspex_app'      ::  the nexus root
  name=%'main.sig'                    ::  the writer grub
:-  mark=%auspex-chain
noun=<the chain>
```

i.e. `[chan [%poke /apps/'auspex.auspex_app' %'main.sig' %auspex-chain chain]]`.
Subscribe to `/client/<chan>` first; the outcome arrives as a `%grub-fact`
carrying `[%ack err=(unit tang)]`.

From a dojo, the same delivery is a poke of the bare mark `%auspex-chain` at the
writer's road.

**Delivery is open.** The nexus grants a **poke road** to `/main.sig`
in the `public` usergroup, so **any ship may hand us a chain** — the courier is
deliberately not checked against the participants, because the signatures are
the authority and the courier is irrelevant. That is what makes chains portable
and what separates this from a chat app. A receiver MUST NOT require the sender
to be a participant.

The grant is a **road, not a mark**, so a peer that can reach the writer can
also address the local-only marks at it. The source check is what makes that
harmless: a local-only action MUST be refused unless the poke's source is our
own ship, read **off the transport and never off the payload**.

### 6.2 A conformant peer runs the nexus

Stated plainly and without hedging: **a conformant peer runs grubbery with the
Auspex nexus.** That is the endpoint, that is the whole transport, and there is
no alternative one to discover, negotiate or fall back to. A ship not running
the nexus cannot receive auspex mail.

An implementation therefore conforms at two levels, and they are independent:

- **The format** — [§2](#2-the-message) through [§5](#5-attachments). Anything
  that can build the nine-field noun, hash it, sign it and verify it is
  format-conformant, and the vectors in [§8](#8-conformance) are the test.
- **The transport** — this section. A sender must be able to issue the
  `%grub-cmd` poke above; a receiver must be a grubbery nexus that accepts
  `%auspex-chain` at its writer.

Nothing in the format depends on grubbery: no grubbery type crosses the wire,
and the payload is a bare `(list msg)`. The chain is the chain.

### 6.3 Discovery

A poke of a mark the far end does not carry **parks**. A blot with no marc never
acks, so the sender's fiber sits on its deadline and reports a timeout — which
is also what a ship that is merely offline looks like, and what a ship running a
different Auspex looks like. Three different facts, one indistinguishable
symptom, none of them actionable.

So a nexus **publishes what it speaks** and a sender **asks before it pokes**.

#### 6.3.1 The published noun

Every nexus MUST publish one grub at `/proto` relative to its nexus root, whose
noun is:

```hoon
+$  proto-caps
  $:  max-blob=@ud
      max-attach=@ud
      max-chain=@ud
      max-body=@ud
      max-subj=@ud
      max-to=@ud
      max-depth=@ud
      max-signers=@ud
      max-mime=@ud
      max-name=@ud
  ==
::
+$  proto  [%auspex versions=(list @ud) marks=(list @tas) caps=proto-caps]
```

As a noun: `[%auspex [versions [marks caps]]]`, where `caps` is a right-nested
ten-tuple of atoms **in the order written above**. A version-1 nexus publishes

```
[%auspex ~[1] ~[%auspex-chain] [262.144 16 1.000 100.000 1.000 100 64 128 128 256]]
```

- **The head is `%auspex`** and not a version number. Versioning lives in
  `versions`; the head is what tells a reader that the noun it keened out of a
  namespace shared with every other nexus is ours at all. A reader MUST check it.
- **`versions` and `marks` are parallel.** The mark for version N is the entry at
  N's index in `marks`. A reader MUST refuse a publication whose lists differ in
  length, and MUST refuse one whose `versions` is empty; both are treated as
  silence ([§6.3.4](#634-the-compatibility-rule)). Two lists rather than a map
  because this noun is read by an implementation that may not be this one, and a
  list is a shape anything can walk.
- **`caps` are the publisher's own enforced limits**, the same numbers as
  [§4.6](#46-the-caps). A publisher MUST NOT publish a cap it does not enforce:
  a published cap that disagreed with the enforced one is worse than publishing
  nothing, because it makes a sender confident about a send the receiver then
  drops. A publisher MUST re-publish when the numbers change, and the window in
  which the two can disagree is therefore **one deploy** — see
  [§6.3.2](#632-where-a-peer-reads-it).
- **`versions` and `marks` are each bounded at 64 entries**, and a reader MUST
  refuse a publication that exceeds it. The bound MUST be checked before the
  lists are walked whole: this noun is published by a stranger into a namespace
  anyone may write to, so an unbounded length walk is work an attacker chooses
  the size of. A protocol that has had sixty-four incompatible versions has a
  different problem than this bound.

The marc is a noun passthrough (`mar/auspex/proto.hoon`). A typed marc would
re-validate the stored grub against the live type on every read, so adding a
field to `$proto` would boom the grub already on disk — the one thing a
compatibility mechanism must not do.

#### 6.3.2 Where a peer reads it

The grub is bound in gall's remote-scry farm at

```hoon
++  proto-spur  ^-(path /auspex/proto)
```

and read by `%keen` at the spar path

```hoon
++  proto-keen-path
  |=  [agent=@ta case=@ud]
  ^-  path
  %+  weld  `path`[%g %x (scot %ud case) agent %$ %'1' ~]
  proto-spur
```

Rendered: `/g/x/<case>/<agent>/''/1/auspex/proto`. Every segment means what the
same segment means in [§5.4](#54-fetching-bytes), including the **empty
segment**, which a path literal cannot spell and which MUST be built by cons.
The page's mark MUST be **`%auspex-proto`**; a reader MUST discard anything else.

This is the **same permissionless read** an attachment's bytes get, for the same
reason: the keen is the only channel that answers an un-granted peer, and there
is nothing here worth checking a reader for.

**Case, and republishing.** A spur never grown and never culled binds at
**case 1**. A publisher MUST NOT `%grow` unconditionally: `+grow` assigns
`las+1` on a non-empty fan, so a grow per deploy pushes `/proto` past the probe
ceiling and it becomes unreadable by every peer, forever, with no error.

A reader SHOULD probe **cases 1 through 8**, with a deadline of **4 seconds**
each. That is a wider ladder than a blob fetch uses and a shorter deadline, and
both halves are deliberate: a blob is immutable, so its spur moves only when a
restrict culls it, while `/proto` moves one case every time a ship changes its
version ladder or its caps — a normal thing for a deployed protocol to do, and
two changes are enough to reach the three-case blob ceiling. A namespace read is
answered from a cache or from the publisher's kernel with no agent in the loop,
so a keen that is slow is a keen that is not coming; 8 × 4s is 32 seconds for a
total miss, against the 30 the three-case blob ladder already costs, and those
seconds hold queued mail on first contact — which is why the total, and not the
per-case number, is what was held fixed.

So a publisher **reads back what is bound** — through the same keen a peer uses
— and acts on the difference:

| bound value | action |
|---|---|
| nothing bound | grow. Binds at case 1. |
| bound, and equal to what we now publish | **nothing.** A redeploy of unchanged content is free, which is what keeps this inside the probe ceiling. |
| bound, and different | **cull, then grow.** Cull first: a reader takes the FIRST hit walking up from case 1, so an unculled case 1 would answer with the old noun forever and the new one would be unreachable behind it. |
| bound, and unreadable | **nothing**, and say so. Growing on a read that failed burns a case for no information, which is how the ceiling is reached by accident. |

That is one grow per protocol change rather than per deploy, and it is why the
publish/enforce window in [§6.3.1](#631-the-published-noun) is one deploy.

**What a reader learns, and why that is accepted.** `/proto` is the first read
this nexus exposes at a **guessable** path. A blob is content-addressed, so
asking for one means already knowing its hash; `/proto` sits at a fixed spur, so
any ship on the network can keen it, unlogged and unanswerable-to, and learn two
things: **that this ship runs Auspex at all**, and a **capability fingerprint** —
the version ladder and ten cap numbers, which together identify a build.

That is accepted, and the reason is structural rather than comfortable: a sender
needs this **before its first poke**, from a ship it has never spoken to, and
the only channel that answers an un-granted peer is the keen. Gating it would
mean a grant, a grant means a prior relationship, and a prior relationship is
exactly what first contact does not have. The alternative is not privacy; it is
the silent hang this section exists to remove. Nothing here is per-user, nothing
here is mail, and the same fingerprint is inferable from a peer's behaviour by
anyone willing to send it a message.

#### 6.3.3 The sender's algorithm

**A sender MUST NOT poke a peer it has no answer for.** Sending version 1 while
the probe is still in flight makes outcome 2 below unreachable on **first
contact** — which is the send most likely to reach a ship running something
else, because a ship never asked about is a ship never spoken to. The chain
waits until the answer arrives.

A sender resolves the recipient's `$proto` and then:

1. **Answer with a common version** → poke the mark for the **highest** common
   version. Highest and not first: a sender that took the first common entry
   would be pinned to whatever order the peer published, and the peer chooses
   that order.
2. **Answer with no common version** → **MUST NOT poke.** The send fails with

   ```
   no common protocol version: ~ship speaks <their versions>, this ship speaks <ours>
   ```

3. **Answer present, but the send exceeds the peer's published caps** →
   **MUST NOT poke**, and the message names the **peer's** number:

   ```
   ~ship accepts at most N attachments
   ```

   and likewise for an attachment's size, chain length, recipients, subject,
   body, body mime, depth and distinct signers. The check MUST read the peer's
   caps and MUST NOT read the sender's.
4. **The discovery read itself came back empty** — a timeout, no such grub, a
   wrong page mark, or a noun that is not a well-formed `$proto` → **one
   version-1 attempt**, because silence is version 1
   ([§6.3.4](#634-the-compatibility-rule)). Say so before the poke, not after
   it fails:

   ```
   ~ship has not answered discovery; sent as version 1
   ```

   Present perfect, deliberately: the ship has not answered *yet*. This outcome
   MUST be reached only from the **probe's own empty result**, never from a
   cache entry that merely happens to be absent — those are different findings
   and a sender that conflates them reports a failure it has not observed.

**And when the poke itself is not acked**, at either 1 or 4:

```
~ship did not ack within 20s; it may still arrive
```

**Not** "did not ack the send". A deadline bounds how long the sender waits and
says nothing about what the far end did: measured between two live ships, a
chain has arrived, verified and been stored while the sender's deadline had
already fired. A nack is its own line (`~ship nacked the send`), and both drop
the cached record so the next send re-asks.

**Timeouts, as numbers.** The discovery keen is bounded at **4 seconds per
case** and probes cases 1 through 8, so a fully unreachable peer costs at most
**32 seconds** of the probe's own time — never the writer's. The poke's deadline
is **20 seconds** per recipient.

**Where each step runs.** The discovery read MUST NOT run on the ship's write
path. A keen is a network round trip, and a timed-out keen leaves a late
response and a stray `%veto` behind that a long-lived fiber would pile into its
skip queue to be re-offered on every later take. The reference implementation:

- reads the cache on the writer — a peek of its own tree — and, for a peer with
  no fresh answer, **queues the chain** and starts one **ephemeral** fiber;
- that fiber keens, then applies exactly the four outcomes above and pokes (or
  refuses) from there;
- two sends to the same unknown peer before the answer arrives are both
  delivered, **in the order they were written**. A queue that drained backwards
  would deliver a reply before the message it answers, and every recipient files
  by `prev` regardless, so nothing would report it.

**Caching.** A sender SHOULD cache the answer per ship. Two TTLs, and the
asymmetry is deliberate:

| record | TTL | why |
|---|---|---|
| lets mail through (a shared version, or a remembered silence) | **1 day** (`+proto-ttl`) | checked by the send itself — a nack or a timeout drops it, so a wrong answer corrects on first use. |
| **refuses** (no shared version) | **1 hour** (`+proto-refusal-ttl`) | never checked by anything, because the poke is never sent. A self-sealing cache needs a shorter fuse. |

A cached **miss** SHOULD be recorded as such rather than left absent, so a peer
running a build without discovery costs one probe rather than one per send.

A **cap** refusal is not derivable from the record alone — it depends on the
message — so it keeps the ordinary TTL, and an implementation SHOULD offer a way
to drop a record on demand. The reference implementation is the `%forget-peer`
action and `POST /api/forget-peer {"ship": "~sampel-palnet"}`; it drops the
cached answer and leaves any queued mail alone, because forgetting what a peer
said must not throw away what a person wrote.

**Per recipient, never per send.** A refusal MUST apply to the recipient it
names and MUST NOT block the others. One peer publishing `max-chain 0` inside a
hundred-recipient `to` would otherwise kill the whole send. `to` itself MUST NOT
be trimmed — it is a signed field naming the audience the author chose, and
rewriting it would sign a different message than the one composed. Delivery
skips the refused recipients; the message does not.

**Two caps a pre-check cannot see.** A sender that screens a send before signing
it works from a one-message stand-in, so the peer's **`max-chain`** and
**`max-depth`** — which describe the whole path the message is joining — are
checkable only at the point of sending. And two of the published caps are not a
sender's business at all: **`max-threads`** is a receiver-side store bound that
no chain can be measured against, and **`max-name`** is published for
completeness but is enforced at the receiver's boundary rather than screened by
the sender. Both are published because a cap a peer enforces is worth knowing;
neither changes what a sender may send.

#### 6.3.4 The compatibility rule

**A peer that publishes no `/proto` is treated as version 1.** Auspex shipped
before discovery did, so silence is not "unknown"; it is the only thing it can
be. A silent peer's caps are version 1's caps — the numbers in
[§4.6](#46-the-caps) — so a send to a silent peer is still checked, not waved
past.

This is what makes discovery **additive**: a sender that speaks it and a
receiver that does not interoperate unchanged, in both directions.

#### 6.3.5 The receiver is unchanged

A receiver accepts every mark it lists in `marks` and nothing else. A foreign
mark still parks; that is grubbery's behaviour and not this protocol's, and
[§6.4](#64-ack-and-nack) says why the receiver must not be made to crash on it
instead.

### 6.4 Ack and nack

Observed behaviour of the reference receiver, and the constraint behind it:

- **A malformed payload is refused as a clean branch.** The wire marks are
  **noun passthroughs** (`++ grab ++ noun *`) and the clam happens inside the
  handler, under `mule`. This is the reversal of an earlier, stricter-looking
  decision and it is worth stating rather than quietly undoing: grubbery
  validates a poke *before* any nexus code runs, a validation failure there
  fails the **writer process**, and the restart consumes the next poke without
  processing it. So a typed wire mark never rejected a bad chain — **it
  destroyed the next good one, silently**, and delivery is open to every ship on
  the network. Reproduced, including `strange restart mark` once per malformed
  poke; then reproduced fixed, remotely, with the message sent immediately after
  a malformed noun applied and stored.

  **Validation you cannot catch is not validation, it is a fuse.** An
  implementation whose transport treats a payload-validation failure as a
  process failure MUST NOT type its wire mark.

- **The writer MUST NOT crash.** Every rejection is a branch that returns
  cleanly, never an assertion. The one arm that can crash on hostile input,
  `+thread-key`, is called under `mule`.

- Consequently, a refusal for a cap violation, an unknown root, or a full store
  is **acked** and recorded locally; only a transport failure or an
  un-clammable noun is visible to the sender. A sender therefore gets **no
  delivery receipt**: a send Ames cannot deliver fails silently from the
  sender's point of view. This is about *remote* delivery only — a send the
  local ship itself refuses is refused locally, where a human can see it.

- The sender bounds each recipient with a deadline (`send-timeout` = `~s20` in
  the reference) and treats a timeout or a nack as soft: an unreachable
  recipient MUST NOT wedge the sender, and a nack from a peer running a
  different auspex MUST NOT crash it.

---

## 7. Local state is not protocol

**Nothing local is ever signed, and nothing signed is ever local.**

| Signed, travels | Local, never travels |
|---|---|
| `from`, `life`, `to`, `subj`, `body`, `body-mime`, `sent`, `prev`, `attachments` | read marks, labels, archive, drafts, filters, mailing lists, blob visibility, blob arrival time, inbox order, the `direct` flag, the BCC record, **the verdict**, **the discovery cache** |

A client MUST NOT infer any right-hand-column value from a chain, MUST NOT
serialise one into a message, and MUST NOT treat a disagreement about one as an
error. Two ships can disagree about every item on the right; they can never
disagree about who signed what. That is what makes `unsigned` freezable at all.

Specifically:

- **The verdict is local by necessity.** It is one ship's reading of one
  signature against that ship's Azimuth snapshot at one instant. A verdict MUST
  NOT travel, and a receiver MUST NOT accept a verdict from a peer.
- **Read marks, labels and archive** are per-ship. A message read on one ship is
  unread on another and neither is wrong.
- **Drafts are not messages.** A draft carries no `from`, no `life`, no `sent`
  and no signature, because there is nothing to sign yet: signing happens at the
  moment of send, once, over the fields as they stand then. A client MUST NOT
  render a draft as a message beside signed ones, and SHOULD enforce that
  structurally — the reference stores drafts outside the message tree and gives
  them a shape the stored-message decoder refuses outright.
- **Filters are applied after verification, never before**, and a filter may
  only **add labels** and **archive**. There is no field for delete, reject or
  mark-read, and there MUST NOT be one: a filter that could suppress a message
  would let an attacker who learns your rules hide the evidence of their own
  forgery. Archiving is not suppression — an archived thread is one view away,
  still counted, still searchable, and new mail un-archives it.
- **A mailing list name never travels.** The name is a local key; what a
  recipient sees in `to` is ships, always, exactly as if they had been typed one
  at a time.
- **BCC is a local record on the sender** — who we blind-copied, keyed by the
  message we sent, so our own Sent view is accurate. It is not signed and it
  does not travel.
- **The discovery cache is local.** `$proto` itself is published and read over
  the namespace ([§6.3](#63-discovery)); what a ship *remembers* about a peer —
  the record, its `asked` time, a remembered silence — is one ship's snapshot at
  one instant. It never travels, it MUST NOT be accepted from a peer (a peer
  that could write your discovery cache could claim a version it does not speak
  or caps it does not enforce, and either turns a send into a message that
  vanishes), and two ships may hold different records for the same third ship
  without either being wrong.

---

## 8. Conformance

### 8.1 The vectors

`protocol/vectors/v1.json` holds deterministic fixtures a second implementation
must reproduce byte-for-byte. Every ship named in them is a **fake ship**, whose
keypair derives from its `@p` ([§3.6](#36-fake-ships)), so the fixtures are
reproducible anywhere with no network and no Azimuth snapshot.

The file is a JSON object:

```
{ "version": 1,
  "digest_tag": "auspex",
  "caps":  { … every cap as a number … },
  "cases": [ … ] }
```

Each case carries:

| key | meaning |
|---|---|
| `name` | the case's identifier |
| `kind` | `message`, `chain`, or `cap` |
| `unsigned` | the nine fields, rendered |
| `jam` | `(jam unsigned)` printed as `@uw` — byte-compare this first |
| `msg_id` | `(sham unsigned)` as `@ux` |
| `digest` | `(shaf %auspex (sham unsigned))` as `@ux` |
| `sig` | the signature as `@ux` |
| `signer` | the ship whose ring signed (may differ from `from` — that is a forgery) |
| `verdict` | the verdict a verifier holding fake keys for the listed `known` ships must produce |

The file also carries a top-level **`set_noun`** object — the three ships of the
`three-recipients` case with their `mug`s, the `jam` of the set they form and of
the empty set — which is what makes [§2.1.1](#211-the-noun-of-to-exactly)
checkable rather than merely described. Each `cap` case carries the `jam` of the
offending message's `unsigned` and the offending chain's length, or, where that
jam would be larger than the fixture it sits in, a `sample_recipe` naming
exactly how to rebuild the input.

And a top-level **`proto`** object: the exact noun a version-1
nexus publishes ([§6.3.1](#631-the-published-noun)) as `jam` (`@uw`) and
`jam_ux`, its spur, its page mark, the keen path at case 1 with the empty
segment rendered `//`, the caps, the TTL, and the compatibility rule as
`silent_peer_is_version: 1`. **Byte-compare that jam:** `$proto` is the one
noun in this protocol that crosses the wire un-hashed, so its bytes are the
contract, and a field added to it or a cap reordered inside `$proto-caps`
changes them without changing any id or digest anywhere.

An implementation conforms if, for every case, it computes the same `jam`, the
same `msg_id`, the same `digest`, the same `sig` from the same signer's ring,
and the same `verdict` from the stated key map.

**Byte-compare `jam` first.** It is the whole `unsigned` noun, so a mismatch
there localises the failure to field order or field type before any hashing or
crypto is involved.

### 8.2 Generating them

The vectors are produced by a `%say` generator in the overlay,
`grubbery-overlay/gen/auspex-vectors.hoon`, which imports the library with
`/+  auspex-chain`. Sync it into a grubbery desk with
`scripts/sync-overlay.sh <desk-root>` (which maps `gen/` → `gen/`), then in the
dojo:

```
|commit %grubbery                 ::  wait for "build-code: done"
=dir /~<ship>/grubbery/<rev>      ::  the revision the commit just printed
+auspex-vectors
```

It answers a `%txt` of 72-character chunks of **one** JSON document. Rejoining
the printed lines with **no separator** — strip the dojo's two-space indent and
concatenate — restores the document byte for byte; `*%/protocol/vectors/v1/txt
+auspex-vectors` writes the same lines into clay as a file.

Two dojo facts that will otherwise cost an hour:

- **`+<desk>!<gen>` resolves the generator against the dojo's *current case*,
  not the desk head.** With `=dir` left at an earlier case, the dojo cheerfully
  rebuilds an older copy of the generator and reports its errors; with `=dir` at
  a date before the file existed, clay answers `read-at-tako fail`. Pin `=dir`
  to the revision number the `|commit` printed.
- **`|commit` issued while `=dir` points into `%grubbery` at a pinned case
  hangs**, because the hood generator it builds cannot be found at that case.
  It produces no output at all — not even the `>=` ack. Move `=dir` back to a
  live `%base` path before committing. (Backspace cancels a hung dojo command;
  the trace reads `! cancel /hand/gen/hood/commit`.)

### 8.3 The conformance test

`grubbery-overlay/tests/lib/auspex-vectors.hoon` **reads
`protocol/vectors/v1.json` itself**, with a `/*` clay import, and asserts the
library reproduces what is in it — every `jam`, `msg_id`, `digest`, `sig` and
verdict, the caps block, the cap cases' refusals, the set noun and the `proto`
fixture. It also asserts the document's own prose: `version`, `mark`,
`digest_tag`, `msg_id_rule`, `digest_rule`.

That last part is not decoration. The file was previously a dojo transcript
reassembled by hand, and had lost two characters to a terminal that strips
trailing whitespace — `(shaf%auspex` for `(shaf %auspex`, `theroot` for
`the root` — while the suite passed, because it carried its own copies of the
values and never read the file. **A test that regenerates its own expectations
proves nothing about the artifact an implementer downloads.** The file is now
written by the generator straight into clay and copied out of the mount byte for
byte, and a character lost anywhere in it fails a test on the ship that produced
it.

**15 tests.** Run it with `-test`, alongside the main suite:

```
-test /=grubbery=/tests/lib/auspex-chain ~     ::  87 tests
-test /=grubbery=/tests/lib/auspex-web ~       ::  48 tests
-test /=grubbery=/tests/lib/auspex-vectors ~   ::  15 tests
```

### 8.4 Rule → test

Every test in `grubbery-overlay/tests/lib/auspex-chain.hoon` is a rule this
specification states. The table below pairs them so the spec and the suite can
be diffed; **87 tests** — the last twelve are discovery
([§6.3](#63-discovery)).

| rule | test |
|---|---|
| A signature made with a ship's key verifies against that ship's key. | `test-sign-verify-roundtrip` |
| A signature does not verify against a different ship's key. | `test-sign-wrong-key-fails` |
| A signature does not verify against a different message. | `test-sign-wrong-message-fails` |
| The digest is `(shaf %auspex (sham unsigned))`, computed directly and not reimplemented by callers. | `test-digest-is-salted-sham` |
| The digest is domain-separated: it differs from the unsalted `sham` and from the same noun salted for another protocol. | `test-digest-domain-separated` |
| `msg-id` covers every one of the nine signed fields, `attachments` and `body-mime` included. | `test-msg-id-covers-every-field` |
| A third party who has never spoken to the author verifies the author's signature out of a forwarded chain. | `test-third-party-verifies-forwarded-chain` |
| A tampered body is `%forged`, not `%unverified`. | `test-tampered-body-is-forged` |
| A tampered `life` is `%unverified`, not `%forged`. | `test-tampered-life-is-unverified` |
| No key available is `%unverified`, never `%forged`. Moons land here. | `test-missing-key-is-unverified` |
| Merging the same chain twice is a no-op; double delivery must not duplicate. | `test-merge-dedupes` |
| `+merge` orders by `sent` regardless of arrival order. | `test-merge-orders-by-sent` |
| The thread root is the id of the root message, and every ship computes the same one. | `test-root-is-first-message-id` |
| Participants are the union of `from` and `to` across the chain, so a forward's recipient is a participant. | `test-participants-includes-forward-recipient` |
| Two copies sharing an id and differing in signature both survive `+merge`. | `test-merge-keeps-both-copies-on-sig-collision` |
| A peer-supplied chain that repeats a message is deduped against itself. | `test-merge-dedupes-within-new` |
| One chain yields different verdicts per message. | `test-mixed-verdicts-per-message` |
| A message signed under life 2 verifies against that ship's life-2 key. | `test-verifies-under-rotated-life` |
| The verdict is keyed on `[id sig]`, so two copies of one id are labelled separately. | `test-verdict-keyed-on-id-and-sig` |
| `+prune` sheds the excess rather than rejecting the chain. | `test-prune-sheds-excess-rather-than-rejecting` |
| `+prune` never sheds a `%verified` copy, in either input order. | `test-prune-never-sheds-a-verified` |
| The fill bucket ranks `%unverified` above `%forged`, in either input order. | `test-prune-prefers-unverified-over-forged` |
| The whole ranking: `%verified`, then `%unverified`, then `%forged`. | `test-prune-ranks-verified-then-unverified-then-forged` |
| Thread identity comes from content, never from the order of the supplied list. | `test-thread-key-from-content-not-list-order` |
| Thread identity never derives from `sent`; a backdated reply still resolves to its root. | `test-thread-key-ignores-sent` |
| An established thread's id is immutable; a new `prev=~` message cannot migrate it. | `test-thread-key-established-thread-is-immutable` |
| A shadowed root (genuine plus tampered copy, same id) still resolves on first contact. | `test-thread-key-tolerates-a-shadowed-root` |
| `+freeze` never overwrites a definitive verdict. | `test-freeze-keeps-a-definitive-verdict` |
| `+freeze` lets a later poke upgrade an `%unverified`. | `test-freeze-upgrades-an-unverified` |
| The input caps reject rather than truncate, and one bad message condemns the chain. | `test-input-caps-reject-on-any-message` |
| The capacity bound counts distinct ids, not copies. | `test-distinct-ids-counts-ids-not-copies` |
| The content address covers the length as well as the atom. | `test-blob-hash-covers-length` |
| A blob is accepted only if its bytes hash to the address it was fetched under. | `test-blob-ok-rejects-wrong-bytes` |
| `+describe`'s size and hash agree with the bytes it was built from. | `test-describe-matches-its-bytes` |
| A file whose declared length is below its measured bytes is malformed. | `test-file-ok-rejects-malformed-octs` |
| `+attach-ok` enforces the same caps as `+file-ok` without the bytes. | `test-attach-ok-enforces-the-same-caps` |
| The attachment count cap is `max-attach` and not a number of its own. | `test-attaches-ok-caps-the-count` |
| `name` and `mime` refuse control bytes at the boundary. | `test-text-ok-refuses-control-bytes` |
| Eviction takes unreferenced blobs, oldest first; a referenced blob is never evicted. | `test-unreferenced-is-oldest-first` |
| `+shed-for` refuses rather than half-evicting when the store cannot be made to fit. | `test-shed-for-refuses-rather-than-half-evicting` |
| Swapping an attachment breaks the signature. | `test-swapped-attachment-is-forged` |
| The incoming attachment bound applies per message and rejects the chain whole. | `test-incoming-attachment-caps` |
| `+chain-hashes` collects every content address a chain refers to. | `test-chain-hashes-collects-every-address` |
| The blob spur and keen path are content-addressed, with no revision segment and with the empty knot present. | `test-blob-paths-are-content-addressed` |
| A message's ancestry is the ids from the root down to it, root first, inclusive. | `test-ancestors-are-root-first` |
| `+prev-map` is keyed by id, not by signature: two copies are one node. | `test-prev-map-is-keyed-by-id-not-signature` |
| A forward ships the path and not the sibling branch. | `test-path-chain-omits-the-sibling-branch` |
| The forwarded branch travels whole when it is what was forwarded. | `test-path-chain-carries-the-whole-path` |
| A forwarded path is a fileable chain: unique root, every `prev` resolves, same thread id. | `test-path-chain-is-a-fileable-chain` |
| Every copy at a node on the path travels, not one chosen copy. | `test-path-chain-keeps-both-copies-of-a-node` |
| An orphan is placed as its own root rather than dropped. | `test-orphan-is-its-own-root` |
| A `prev` cycle terminates. | `test-ancestors-survives-a-cycle` |
| `+with-root` adds the root only when the path lacks one. | `test-with-root-only-adds-when-the-root-is-missing` |
| Two branches are two sibling directories under the message they answer. | `test-ancestor-map-places-siblings-side-by-side` |
| Directories are made shallowest first. | `test-prefixes-are-shortest-first` |
| A copy path is `<ancestry>/<slot>`; a one-segment path needs no directory. | `test-node-dirs-drops-the-slot-and-keeps-the-ancestry` |
| Only the shallowest stale directories are culled, and nothing inside one is culled again. | `test-minimal-dirs-and-under-any` |
| The depth cap measures the deepest root-to-leaf path, not the message count. | `test-max-ancestry-is-the-deepest-path` |
| The signer cap counts the distinct `[ship life]` set, not the messages. | `test-signer-cap-counts-keys-not-messages` |
| A label must be a real `@tas`, checked at the boundary. | `test-label-ok-rejects-a-non-term` |
| The label set is bounded per thread. | `test-labels-ok-bounds-the-set` |
| Substring search is case-insensitive, and an empty needle matches everything. | `test-has-sub-is-case-insensitive` |
| Search covers subject, body and the rendered sender. | `test-search-covers-subject-body-and-sender` |
| Search finds a forged message and names it, drawing the row from the message that matched. | `test-search-finds-and-names-the-forged-message` |
| An empty query has no newest match. | `test-newest-match-is-empty-without-a-query` |
| Inbox is participant **or** direct, and not archived. | `test-inbox-is-participant-or-direct` |
| Sent is the threads we authored, walked from the chain rather than stored. | `test-sent-is-threads-we-authored` |
| Pagination slices without losing the total. | `test-page-slices-without-losing-the-total` |
| A draft is not a stored message and the decoder refuses one outright. | `test-a-draft-is-not-a-stored-message` |
| A draft is checked against the same send caps, at save time. | `test-draft-ok-applies-the-send-caps` |
| A rule with no condition is refused. | `test-rule-needs-a-condition` |
| An empty subject is not a condition. | `test-an-empty-subject-is-not-a-condition` |
| A rule ANDs across the conditions it actually sets. | `test-rule-matches-and-across-its-conditions` |
| Rules compose additively: labels union, archive ORs, nothing is removed. | `test-apply-rules-composes-additively` |
| A filter cannot suppress a forged message. | `test-a-filter-cannot-hide-a-forgery` |
| A sender picks the **highest** common version, not the first. | `test-common-version-picks-the-highest` |
| Nothing in common answers `~`, and `~` is a refusal rather than a fallback. | `test-common-version-answers-none` |
| A peer that publishes no `/proto` is version 1, and its caps are version 1's. | `test-a-peer-with-no-proto-is-version-1` |
| `versions` and `marks` are parallel; a version with no mark answers `~`, and a publication whose lists disagree is refused whole. | `test-mark-for-follows-the-parallel-lists` |
| The cap pre-check reads the **peer's** caps and never ours, for both the count and the size. | `test-peer-cap-check-uses-the-peers-caps-not-ours` |
| What a nexus publishes is what it enforces. | `test-published-caps-are-the-enforced-caps` |
| A cached discovery answer is believed for a day, and a record from the future is not fresh. | `test-a-peer-record-expires` |
| The two version refusals name the ship first, one line each. | `test-the-discovery-refusals-name-the-ship-first` |
| The proto spur and its keen path mirror each other, empty segment included. | `test-proto-paths-mirror-each-other` |
| The pending queue appends, never dedupes, and drains oldest first; the remainder keeps its order. | `test-the-pending-queue-drains-in-order` |
| A record that refuses expires in an hour, not a day; a remembered silence is not a refusal. | `test-a-refusing-record-expires-sooner` |
| `+proto-ok` bounds its walk before measuring, and refuses lists that disagree in length. | `test-proto-ok-bounds-the-walk` |

---

## Appendix A: Discrepancies

Where the code and `docs/superpowers/specs/2026-09-07-auspex-design.md` disagree,
this document followed the **code**. The disagreements, for the controller:

**A.1 — Test counts are stale in the design doc.** The design's `# Testing`
section claims "71 tests… `tests/lib/auspex-chain.hoon` — 56 tests…
`tests/lib/auspex-web.hoon` — 15 tests." The actual counts are **75** and **48**
(123 total). The design doc's numbers were correct for an earlier slice and were
not updated. Nothing about behaviour differs; only the counts.

**A.2 — The design's `## The input caps` table omits `max-signers` and
`max-mime`.** It lists seven caps (`max-chain`, `max-body`, `max-subj`,
`max-to`, `max-copies`, `max-threads`, `max-depth`). `max-signers` (128) is
documented in the design's own prose and in the library, and `max-mime` (128) is
applied to `body-mime` by `+fits-body-mimes` on every incoming chain — which
makes it an input cap, not only an attachment cap. This document lists all of
them in [§4.6](#46-the-caps).

**A.3 — The design shows verification as a direct `.^` scry.** Its `## Verification`
block writes `.^((unit [crypto-suite=@ud =pass]) %j /(scot %p our)/puby/…)`.
The nexus cannot `.^` and routes every jael read through a scry service instead
(`+peer-pass`, `+our-life`, `+our-ring`, `+fake-ship`). The scry **paths** and
the returned shapes are identical, so this is a difference in how the read is
issued, not in what is read. This document gives the paths and notes the
constraint.

**A.4 — The salt in the live real-planet transcript is `%urmail`.**
`docs/verification.md` records the one end-to-end real-key proof
(`~martyr-sanryg`, 2026-09-08) using `(shaf %urmail (sham 'test'))`, because the
app was called urmail when it was run. The protocol's tag is **`%auspex`**. The
transcript still proves what it was cited for — that a real planet's `%vein`
ring signs a salted digest and its `%puby` `pass` verifies it — but a reader
must not take `%urmail` for the wire tag.

**A.5 — The `%puby` branch has never executed inside auspex.** Recorded in
`docs/verification.md` and repeated here because it bears on conformance: every
verdict observed anywhere in this project went through the **fake-ship
derivation**. Verification against a real Azimuth key has been proven at the
crypto level ([§3.3](#33-obtaining-a-key)) and **not** through the nexus's own
`+peer-pass`. That happens the first time a real ship runs it.

**A.6 — The delivery blot is `[/ %auspex-chain]`, not `[/auspex %chain]`.**
The latter form circulates in project notes and reads naturally, and it is
wrong: it would put the mark under a path prefix, and a path-prefixed blot is
**unaddressable** from both surfaces a peer actually uses — `%grub-cmd` flattens
a blot to its bare `mark=@tas`, and a dojo poke names a bare mark too. The code
is unambiguous in two places: `mar-gub/auspex-chain.hoon` sits at the top level
of `gub/mar` (its own header says "The delivery blot has to be
`[/ %auspex-chain]` or a foreign ship cannot address it at all"), and `+apply`
dispatches on `?:  =([/ %auspex-chain] p.sage)`. An implementation that pokes
`[/auspex %chain]` will not be received. See [§6.1](#61-the-transport-is-the-grubbery-nexus).

**A.7 — Nothing else disagreed.** The nine fields, the digest tag, the three
verdicts and the missing-key rule, `[id sig]` merging, `+prune`'s shed-and-rank,
`+thread-key`'s identity rules, `+freeze`, `+path-chain`/`+with-root`, the
attachment shape and hashing rule, the keen path, the caps' values, and
`+deliver`'s order of operations all match the design document exactly.

---

## Appendix B: Known costs

Carried forward from the design's `# Deliberate limits` and stated here because
an implementer inherits them:

- **Every send ships the full path.** A two-hundred-message path costs two
  hundred messages of bytes on every reply. The upgrade is a
  `have=(set msg-id)` handshake so the sender transmits only the difference.
- **The distinct-id cap rejects rather than sheds, and that is a censorship
  vector.** Anyone who knows a thread's root content can poke enough distinct
  junk messages — **no signatures required**, since forged messages are stored
  and counted — to pin the thread at `max-chain`, after which every legitimate
  message is rejected. One poke, no crypto, permanent per-thread censorship. The
  fix is to shed distinct ids too, preferring `%verified`; it is deferred rather
  than justified.
- **Moons and comets are unverifiable to third parties.** See
  [§3.5](#35-moons-and-comets).
- **Restriction is withdrawal, not revocation.** See
  [§5.5](#55-restriction-is-withdrawal-not-access-control).
- **`max-signers` caps one poke, not a sender.** A peer willing to send a
  thousand pokes still buys a thousand times the work. The real answer is a
  per-source rate budget.
- **A chain touching two existing threads conflates them.** `+thread-key` picks
  whichever comes first in map-traversal order. This is availability and
  correctness of filing, not authenticity — a wrongly-filed message is exactly
  as verified or forged as it was.
- **No delivery receipts.** See [§6.4](#64-ack-and-nack).

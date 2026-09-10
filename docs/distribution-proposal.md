# App distribution: a proposal

For the grubbery meeting, 2026-09-10. Written against `develop` at
`68ca752` (36 commits past the base our fork sits on) and the chat about
`/sys/name`.

**The short version.** I think most of what we need already exists on
`develop` — the `desk` nexus and the shell's alias book — and that the
right move is to make Auspex the first non-lattice app distributed that
way, rather than to deepen my fork of the grubbery desk. Four things
have to be answered before that can work, and one of them (signing) is a
question about grubbery's permission model, not about my app.

---

## 1. Where I am

Two apps, both grubbery nexuses, both developed as **overlays** — a tree
of `lib/ nex/<app>/ mar/<app>/` copied into a desk by a script, never
edited in place:

| | lattice | auspex |
|---|---|---|
| shipped | yes, `~ricsul-bilwyt` since 2026-09-02 | no — beta-ready |
| overlay | `nisfeb/lattice` `grubbery-overlay/` | `nisfeb/auspex` `grubbery-overlay/` |
| distribution | vendored into my fork of the grubbery desk | nothing yet |

The fork (`nisfeb/grubbery`, `dist/lattice-only`) is `develop@7117ae1`
plus: the app tier stripped and its sources deleted, the lattice overlay
vendored in, a `%3 → %1` state downgrade, the poke-ack marc fix, and a
**77-file ball trim** — which exists only because a fresh install's
~1,300-result ball build killed a small-loom ship. Kiln syncs the whole
desk, so everything in it lands on everyone.

That last sentence is the problem, and it is why I am not enthusiastic
about my own runbook. To ship Auspex the way I shipped lattice I would
push ~40 files into a desk that every lattice user syncs, and every one
of their balls would compile a mail nexus they did not ask for.

## 2. What I read of your plan

From the chat, and from `develop`:

- **`desk` nexus** (`gub/nex/desk.hoon`): mirrors a code directory from
  anywhere in the namespace — `~nec/apps/counter/desk/code`, or a
  checked-out repo — assuming nothing about its internal shape.
  Version-gated by an opaque `version.*` tag on the host; snapshots both
  `/code` and `/data` before new code lands. Guests resolve marcs against
  `/desk/code` and **distribute every marc they use**, content-addressed.
- **shell** (`gub/nex/shell.hoon`): the permission *manager* — reads each
  nexus's `alias.json` and `weir.json`, surfaces them, records consent,
  writes weirs; the kernel enforces. Also the launcher grid, the bell,
  `public.json`, mirrored peer directories, and the peer-desk storefront
  that is the "add apps" browser.
- **the alias book** (`/book` in the shell): one grub per alias holding
  *current claimants and their locations*, with `permit/share.json`
  giving per-alias visibility. This looks like `/sys/name` already built:
  several claimants per name, each with a location, discoverable.

If I have that right, then three things I currently maintain stop being
mine:

1. **The ball trim.** Guest isolation means an installed app carries its
   own code and shared marcs dedupe. The trim exists because the desk
   model ships everything to everyone; that reason goes away.
2. **The launcher.** I have a restoration of pre-split `tiles.hoon`
   (629 lines, upstream `d839ede`) staged on a branch, and a docket
   rewrite, purely so a second app has somewhere to appear. The shell
   owns the launcher now. **I would rather throw this away than ship
   it** — see §5.
3. **My fork of the desk at all.** Which is the thing you offered, and I
   want it.

## 3. What Auspex is, in one paragraph

Mail with no IMAP or SMTP. Each message is signed by its author's ship;
a reply or forward ships the root-to-parent path of signed messages, so a
third party who never spoke to the author can verify every one against
that author's key. Three verdicts, `verified` / `unverified` / `forged`,
per message and never per thread; a missing key is never a forgery.
Attachments are content-addressed and fetched on demand by hash over
keen. The wire format is frozen and specified independently of my
implementation (`docs/protocol.md`, with conformance vectors a second
implementation must reproduce). It is a protocol as much as an app, which
is why §6 matters to me.

## 4. The four questions

Ranked by how much they block me.

### 4.1 Signing — the one that is really about grubbery

Auspex signs every message with the ship's networking key. Today it does
this:

```hoon
::  nex/auspex/app.hoon +our-ring
;<  n=noun  bind:m  (typed-scry:io noun %noun ~[%j %vein (scot %ud lyf)])
```

It reads `%vein` — the ship's **private ring** — and signs in app code.
That is fine while it lives in `/apps`, the trusted tier where instances
default to no weir. It is not fine as a desk-installed guest, and I do
not think it should be: "this app may read your private key" is not a
permission a user can meaningfully consent to, and it is unbounded — an
app with the ring can sign anything, as you, for ever.

**Proposal: a signing service.** Grubbery offers "sign this digest as
me"; the shell approves it per app the way it approves any other road;
the key never enters app code. The reason this is safe rather than a
different unbounded capability is **domain separation**, which Auspex
already does:

```
digest = (shaf %auspex (sham unsigned))
```

A signature obtained under one app's domain tag cannot verify under
another's. So the service's contract is: *you name your domain, I sign
`(shaf <your-domain> <your-hash>)`, and I will not sign a bare hash for
anyone.* That bounds the grant to "may sign things that only your own
verifier accepts", which is a permission a user can actually reason
about — and it is the difference between "Auspex can send mail as you"
and "Auspex can be you".

If the answer is "stay in `/apps` for now", that is workable and I will
take it, but I would rather build against the service if it is coming.

### 4.2 Outbound roads

Auspex talks to other ships two ways:

- **remote keen** to an arbitrary ship for a blob by hash and for the
  peer's protocol descriptor;
- **remote poke** to an arbitrary ship's auspex blot to deliver a chain.

Weir, as I understand it, describes make/poke/peek road sets — who may
reach *my* paths. Can it express the outbound direction: *this app may
poke and keen any ship, at this path shape*? If not, what is the
intended model — is outbound simply unrestricted for an installed app,
or is there something to declare?

### 4.3 Publishing to ships that have not installed anything

Auspex publishes two things readable by **any** ship, unauthenticated:

- `/mail/blob/<hash>` — attachment bytes, content-addressed, so you must
  already hold the hash (which means holding a message that names it);
- `/proto` — what protocol versions and marks this ship speaks, at a
  fixed, guessable path.

A recipient who cannot fetch an attachment has a broken feature, and the
sender cannot know in advance which ships will need it. With
`permit/share.json` defaulting to private, how does an app publish
something permissionlessly? Is that a grant the app requests, or a thing
the user turns on per alias, or is it not expressible?

(I am aware `/proto` is an enumeration surface — any ship can ask "do you
run Auspex, and which build". I decided that was an acceptable trade and
wrote the argument down rather than waving it away; happy to be told
otherwise.)

### 4.4 The floor, and who publishes

- What grubbery revision must an **installer** be on for the `desk`
  nexus and the shell? That is the real gate on my beta.
- If a moon distributes grubbery, do I publish apps from `~ricsul-bilwyt`
  or from a moon of it? Ricsul is also my memory store and a live lattice
  install, so I would rather publishing not require it to be on a
  bleeding edge it uses in anger.
- Does the storefront read a published code dir from a ship that is not
  the publisher of grubbery itself?

## 5. What I want to do, and my fallback

**Preferred: make Auspex the first non-lattice app on the code-nexus
path.** My overlay is already the shape a code namespace wants —
`lib/ nex/ mar/`, no in-place edits, one script that maps it — so I
believe the work on my side is: add `bill.json`, add an `alias.json` and
a `weir.json` to the nexus's `on-load` beside the `tile.json` it already
writes, and publish `grubbery-overlay/` as a code dir with a
`version.txt`. Concretely:

```hoon
::  beside the tile.json row auspex already writes in +on-load
[%over %& [/ %'alias.json'] [[/ %json] (pairs:enjs:format ~[['name' s+'auspex'] ['description' s+'Signed mail']])]]
```

If standing that up is more than about a week — and you are away part of
next week — then:

**Fallback: a beta with the smallest possible fork.** I add *only*
auspex's own sources to the dist desk. **No launcher restoration, no
docket rewrite.** Auspex is reachable at `/apps/auspex`, lattice's tile
and URL do not change, and existing lattice users see nothing move. The
throwaway work stays unwritten, and the migration afterwards is the
directory re-map I would have done anyway. I would still rather not push
a mail nexus into everyone's ball, so if there is a way to make it
opt-in on 7117ae1 that I have missed, I would take that instead.

## 6. Something I can offer: the other half of the alias book

The book answers **where** an app is. It does not answer **what it
speaks**, and for anything that is a protocol rather than only an app,
that is the harder half. I built it for Auspex last week and it is
running on two ships:

- Every nexus publishes `/proto`, readable over keen:
  `[%auspex versions=~[1] marks=~[%auspex-chain] caps=[…]]` — versions
  and marks parallel, so a version *is* a mark name; caps are the
  receiver's limits.
- Before first contact, a sender probes the peer's `/proto` on an
  ephemeral fiber, picks the **highest common version**, and pokes that
  mark. No common version → a refusal naming both sides' versions, per
  recipient, before anything is signed. Over a peer's declared caps → the
  same. No answer → treated as version 1, which is the compatibility
  rule. Answers are cached per ship (a day; an hour after a refusal;
  a `forget-peer` action to force a re-probe).
- A poke timeout is **not** treated as failure — grubbery's ack is not
  observable from a nexus fiber, and the mail lands. Discovery is the
  liveness signal instead; only a nack is a failure.

Two things in that I think generalise:

1. **Name resolution and version negotiation are different questions and
   want different answers.** `/sys/name` (or the book) gives a location;
   a descriptor at that location gives the terms. Composing them means a
   sender does one cheap read and knows whether it can talk at all.
2. **It answers your stale-pointer worry** from the chat — "you could
   look in the old place, but who knows what's there now". Don't check
   the location, check what is *there*: a descriptor is self-identifying,
   so a stale path is one cheap read away from being detected, and the
   fallback to the book is unambiguous rather than a guess.

And on the destination question from yesterday, I think you were right
and I was wrong: a protocol should not name a handler. It names a message
shape and a way to find the destination. For a non-grubbery ship that
resolves to `%agent` + a clay mark; for a grubbery ship, to a path + the
marc governing it. If the book's entries could carry that — what I speak,
not just where I am — the same discovery works across both, and I would
drop the thin gall agent I was going to write.

Happy to be told the shape is wrong. It is one grub and a probe; the
value is that it exists and has been wrong a few times already.

## 7. What I need from the meeting

1. The answer to §4.1 — signing — even if the answer is "trusted tier for
   now".
2. Yes or no on Auspex as the first code-nexus app, and roughly when.
3. The installer floor (§4.4), which decides whether my beta waits.
4. Whether the `/proto` idea is worth folding into the book, or whether
   you would rather it stay mine.

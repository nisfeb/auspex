# App distribution: a proposal

For the grubbery meeting, 2026-09-10. Written against `develop` at
`68ca752` (36 commits past the base our fork sits on) and the chat about
`/sys/name`.

**The short version.** I think most of what we need already exists on
`develop` — the `desk` nexus and the shell's alias book — and that the
right move is to make Auspex the first non-lattice app distributed that
way, rather than to deepen my fork of the grubbery desk. Four things
have to be answered before that can work. None of them blocks me; the
first (§4.1, signing) is a question about grubbery's permission model
that I think I am about to be the first app to raise.

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

## 4. The questions

The first four ranked by how much they block me; the fifth is not a
question so much as an opinion about the shell, offered because I have
just had to write the strings a user would be shown.

### 4.1 Signing — a granularity gap, not a blocker

Auspex signs every message with the ship's networking key. Today it does
this:

```hoon
::  nex/auspex/app.hoon +our-ring
;<  n=noun  bind:m  (typed-scry:io noun %noun ~[%j %vein (scot %ud lyf)])
```

It reads `%vein` — the ship's **private ring** — and signs in app code.
I want to state the mechanics correctly, because I had them wrong at
first and the real shape is more interesting than what I assumed.

`typed-scry` is not a special power. It is an ordinary poke to
`/sys/scry`'s `main.sig` (`lib/fiberio.hoon`), so it is weir-gated like
any other `/sys` reach — your own comment beside `+grow` says it: *"a
sandboxed grub (whose weir does not grant /sys) is vetoed by default, and
no special-case gating exists anywhere."* And `handle-typed-scry` in
`app/grubbery.hoon` passes the vane path straight through; nothing
inspects which vane or care is being asked for.

So, concretely:

- A guest whose weir does **not** grant `/sys/scry` cannot scry arvo at
  all — it cannot even *verify* a signature, because verification needs
  `%puby` and `%life`.
- A guest whose weir **does** grant it can scry anything any vane will
  answer — including `%vein`.

That is one road, and it is strictly more powerful than what any mail
app needs. The sharp version: **every** Auspex install needs scry access,
because every recipient must fetch the author's public key to verify. So
a user who only ever *reads* mail must still grant the road that also
lets the app sign as them, for ever. There is no way today to say "this
app may read public keys" without also saying "this app may be me."

Nothing else in grubbery reads `%vein` — I grepped `develop`, zero hits.
So Auspex would be the first, and I would rather not be the precedent
that makes `/sys/scry` a routine grant for third-party apps.

Three ways out, and they compose:

1. **A signing service.** Grubbery signs on request: you hand it a domain
   tag and a hash, it returns `(sigh (shaf <domain> <hash>))`. No app
   needs `/sys/scry` to sign. What bounds the grant is **domain
   separation**, which Auspex already does — our digest is
   `(shaf %auspex (sham unsigned))` — so a signature obtained under one
   app's tag can never verify under another's, and the service refuses to
   sign a bare hash for anyone. "May sign things only your own verifier
   accepts" is a permission a user can reason about; "may read your
   private key" is not.
2. **Finer roads under `/sys/scry`** — per-vane, or per-vane-and-care, so
   `%j /puby` is grantable without `%vein`. This is the one that helps
   every future app, not just mine, and it is what makes a read-only mail
   client expressible. Harder, because vane paths are open-ended.
3. **Leave Auspex in `/apps`.** Works today, costs nothing, and does not
   scale to apps you did not write.

I am not blocked on any of this — (3) is available and I will take it for
a beta. I am raising it because I think I am about to be the first app
that makes the gap load-bearing, and because (1) is small and (2) is the
one you would want anyway.

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

### 4.5 How the shell should ask — a prompt is a scarce resource

Here is Auspex's whole `weir.json`, which I wrote this morning:

| road | why |
|---|---|
| `/sys/bowl.sig` | read the clock and the name of this ship |
| `/sys/behn/` | give up on a delivery that is not coming |
| `/sys/eyre/` | serve the mail client at `/apps/auspex` |
| `/sys/scry/` | verify signatures, sign your mail, fetch attachments |

Ask which of those a user could rationally deny. The clock? Timers?
Binding its own route? Deny any one and the app does not run; there is
no world in which "no" is a considered answer. **Three of the four are
not decisions. They are the definition of a running app.** Exactly one
is a real decision, and only because it is coarse enough to matter.

So the problem with a wall of toggles is not that it is tedious. It is
that it is **camouflage**: put the one consequential grant in a list of
three inevitable ones and you have trained the user to click through the
consequential one. A prompt that is never rationally denied is worse
than no prompt, because it teaches the reflex that defeats the prompt
that matters.

Three suggestions, in dependency order:

1. **Ambient vs consequential.** Let the shell classify roads and grant
   the ambient set by the act of installing. Bowl, behn, and eyre-for-
   your-own-route are ambient. This alone takes Auspex from four prompts
   to one.
2. **Finer `/sys/scry` roads** — §4.1 arriving from the other direction.
   You cannot safely auto-grant a road that means "anything any vane will
   answer", so granularity is the thing that makes automation possible:
   `%j /puby` is ambient for any app that verifies anything, and "sign as
   me" is the one grant worth a sentence of the user's attention. Today
   they are the same road, so the coarse one must be asked, and asked
   scarily.
3. **Prompt on the delta, not on install.** The declaration is a contract
   the kernel already enforces. Grant the declared set at install and
   surface only what an *update* adds. "Auspex 1.4 wants a road 1.3 did
   not" is real signal; "Auspex wants four roads" on first install is
   noise.

One half of this is mine, not yours, and I am building it: **a denied
road should produce a comprehensible app, not an error.** If `/sys/scry`
is refused, Auspex should still open, show every message as
`unverified` — which the format already allows, since a missing key is
never a forgery — and refuse to *send* with a plain reason, rather than
failing to start. That is the precondition for contextual consent ever
working: you can only ask at the moment of need if the app has a sane
state before the answer.

### 4.6 Bootstrap: how anyone finds my apps at all

First, the mechanism as I read it, so we are talking about the same
thing. There is no index and no push — it is follow-a-ship:

- Someone pokes their shell's `peers.json` with `{"add": "~ricsul-bilwyt"}`
  (`shell.hoon:184-201`).
- That makes one grub, `/peers/~ricsul-bilwyt.json`, whose fiber opens a
  `keep` on
  `/sys/ames/ships/~ricsul-bilwyt/root/apps/shell.shell/share/public`,
  grub `desks.json` (`+peer-pub-road`). Live: what I publish later shows
  up without them acting again. Each mirror owns its own traffic, so an
  unreachable ship blocks nobody.
- On my side the road is readable because it is in the `public.grp`
  usergroup's weir, and `public.json` is *derived from the live grants*,
  so the listing cannot advertise something I did not actually share.
- `+gather-peers` then renders the cards the "add apps" browser shows.

Two consequences, one of which I think is a blocker for the migration.

**The lesser one: a stranger's only path to my software is a dojo poke.**
Reach is exactly the set of ships that have typed my @p. That is fine as
a trust model and I am not asking you to build a store — but "open the
dojo and poke this" is a wall in front of every person who is not
already comfortable, and it is the single step between someone hearing
about Lattice and having it. If there is an intended path from a *link*
to that poke, I would like to know what it is; if there is not, I think
it is worth one.

**The greater one: every current user of mine already has this
relationship, and the migration would silently drop it.** People running
Lattice today installed `%grubbery` from `~ricsul-bilwyt`, and kiln syncs
my whole desk to them. That *is* a software-source relationship — a
broader one than peering, since kiln puts my files in their ball
wholesale. If the migration does not carry it across, they do not merely
lose discovery: they stop receiving Lattice updates, silently, and the
only fix is to tell every one of them to type a poke they have never
heard of. That is exactly the perceivable change the migration exists to
avoid.

**So: the ship you got grubbery from should be a peer by default.**

I want to be clear that I am not asking for a favour to my ship. It is
true by construction for anyone who distributes grubbery, it *encodes a
relationship that already exists* rather than creating one, and it grants
strictly less than what that relationship already grants — a keep on one
public listing, against kiln syncing an entire desk. A user who does not
want it removes the peer, which is a thing the shell already supports.

If you would rather not make that the rule, the fallback is mine to own:
I ship a one-time migration that pokes the shell once and records that it
did. I would rather it were the rule, because every distributor is going
to hit this the first time they move an installed base, and a silent loss
of updates is a bad failure for a user to discover months later.

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

1. §4.1 — whether a signing service or finer `/sys/scry` roads are worth
   doing, or whether the trusted tier is the answer for now. I am not
   blocked either way; I think I am just the first app to make it matter.
2. Yes or no on Auspex as the first code-nexus app, and roughly when.
3. The installer floor (§4.4), which decides whether my beta waits.
4. Whether the `/proto` idea is worth folding into the book, or whether
   you would rather it stay mine.
5. §4.5 — whether "ambient vs consequential" is a distinction the shell
   wants to draw. I will build the graceful-degradation half either way.
6. §4.6 — whether the ship you got grubbery from is a peer by default.
   This is the one I think blocks a clean migration of an installed
   base, and it is not specific to me.

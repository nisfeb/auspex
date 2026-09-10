# App distribution: a proposal

**From:** `~ricsul-bilwyt` (nisfeb) — lattice, auspex
**For:** the grubbery meeting, 2026-09-10
**Written against:** `develop@68ca752`, and the `/sys/name` discussion

---

## The short version

Most of what a second app needs already exists on `develop`: the `desk`
nexus, the shell's permission manager, and the alias book. I have merged
my fork up to it and run the result, so this is not a guess about the
mechanism — it is a report from a ship that has it.

What I want is for **Auspex to be the first non-lattice app distributed
that way**, instead of deepening my fork of the grubbery desk.

Seven questions stand between here and there. One of them — §4.1,
migrating an installed app without moving its data — blocks a clean
migration of lattice's existing users. One of them (§4.3) I suspect I
have been answering wrongly on my own side, and want checking. The rest are answerable in either
direction and I have a path under each answer.

---

## 1. Where I am

Two apps, both grubbery nexuses, both developed as **overlays**: a tree
of `lib/ nex/<app>/ mar/<app>/` copied into a desk by a script, never
edited in place.

| | lattice | auspex |
|---|---|---|
| shipped | yes, `~ricsul-bilwyt`, since 2026-09-02 | not yet — v0.1.0 tagged, bundles built |
| overlay | `nisfeb/lattice` `grubbery-overlay/` | `nisfeb/auspex` `grubbery-overlay/` |
| reaches users by | vendored into my fork of the grubbery desk | nothing yet |

The fork is `nisfeb/grubbery`. Until this week it was `develop@7117ae1`
plus the app tier stripped, the lattice overlay vendored in, a `%3 → %1`
state downgrade, the poke-ack marc fix, and a **77-file ball trim** —
which exists only because a fresh install's ~1,300-result ball build
killed a small-loom ship.

**Kiln syncs the whole desk.** Everything in it lands on everyone.

That is the problem this proposal is about. Shipping Auspex the way I
shipped lattice means pushing ~40 files into a desk that every lattice
user syncs, and every one of their balls compiling a mail nexus they did
not ask for. I would rather not do that, and the code-namespace path on
`develop` is the reason I do not have to.

## 2. What I read of your plan, and what happened when I ran it

From the chat and from `develop`:

- **`desk` nexus** (`gub/nex/desk.hoon`) mirrors a code directory from
  anywhere in the namespace — `~nec/apps/counter/desk/code`, or a
  checked-out repo — assuming nothing about its internal shape.
  Version-gated by an opaque `version.*` tag on the host; snapshots both
  `/code` and `/data` before new code lands. Guests resolve marcs against
  their own `/desk/code` and distribute every marc they use,
  content-addressed.
- **shell** (`gub/nex/shell.hoon`) is the permission *manager*: it reads
  each nexus's `alias.json` and `weir.json`, surfaces them, records
  consent, and writes weirs — the kernel enforces. It also owns the
  launcher grid, the bell, `public.json`, the mirrored peer directories,
  and the peer-desk storefront that is the "add apps" browser.
- **the alias book** (`/book` in the shell) holds one grub per alias with
  the current claimants and their locations, and `permit/share.json`
  gives per-alias visibility. That is `/sys/name` already built: several
  claimants per name, each with a location, discoverable.

**I have merged to it.** `nisfeb/grubbery` `dist/develop-merge` is our
26 commits rebased onto `develop`, deployed to a stateful pier and
running: kernel merged clean, both apps serving, launcher grid correct,
zero bangs. The merge was smaller than I expected — 49 colliding files,
44 of which we had deleted and upstream merely changed, so they resolve
as "stay deleted". `app/grubbery.hoon` never conflicted.

Three things I currently maintain stop being mine if this lands:

1. **The ball trim.** Guest isolation means an installed app carries its
   own code and shared marcs dedupe. The trim exists because the desk
   model ships everything to everyone; that reason goes away.
2. **The launcher.** I have a restoration of pre-split `tiles.hoon`
   (629 lines, upstream `d839ede`) plus a docket rewrite staged on a
   branch, purely so a second app has somewhere to appear. The shell owns
   the launcher now, and I would rather throw that branch away than ship
   it.
3. **My fork of the desk at all** — which is what you offered.

One correction to my own earlier reading, since it changed what I carry:
**explorer is not an app-tier extra, it is load-bearing for the shell.**
`shell.hoon` builds every storefront app icon as
`/grubbery/ball{…}/desk/code/{icon}?raw=1`, and `/grubbery/ball` is bound
by explorer and nothing else. A distribution that trims explorer has a
storefront with no icons. It is back in mine, with upstream's `root.hoon`
row unchanged.

## 3. What Auspex is, in one paragraph

Mail with no IMAP and no SMTP. Each message is signed by its author's
ship; a reply or forward carries the root-to-parent path of signed
messages, so a third party who never spoke to the author can verify every
one of them against that author's key. Three verdicts —
`verified` / `unverified` / `forged` — per message and never per thread,
and a missing key is never a forgery. Attachments are content-addressed
and fetched on demand by hash over keen. The wire format is frozen and
specified independently of my implementation (`docs/protocol.md`, with
conformance vectors a second implementation must reproduce). It is a
protocol as much as an app, which is why §6 matters to me.

## 4. The questions

Ordered by how much they block me. The first is the only one I cannot
route around; §4.7 is less a question than an opinion about the shell,
offered because I have had to write the strings a user would be shown.

### 4.1 Migrating an installed app without moving its data

This is the blocker.

`bill.json` creates an instance at `/desk/data/<name>`, sandboxed with an
empty weir. Point it at lattice on a ship that already runs lattice and
the user gets a **second, empty lattice**, while every page they ever
wrote stays in the old instance at `/apps/lattice.lattice_app`. The URL
survives either way — both apps bind their route by name from
`ui/main.sig` — so the data is the whole risk, and it is the entire risk.

The alternative I can see is governing the existing instance's code in
place: a `/code` namespace at `/apps/lattice.lattice_app/code`, which
keeps instance, data and URL exactly where they are. That works today and
has no update path — nothing mirrors into it the way `desk.hoon` mirrors
into a guest.

So the question is: **can a desk nexus adopt an existing instance**, or
is there an intended migration shape I have not found? Without one, the
choice is a guest that strands the data or an in-place namespace that
never updates, and neither is something I can ship to people who are
using lattice in anger.

I would rather not invent a third thing here. If the answer is "not yet",
I will hold lattice on the desk route and move only Auspex, which has no
installed base to strand — but then two apps of mine are distributed two
different ways for as long as that lasts.

### 4.2 Bootstrap: the ship you got grubbery from should be a peer

First the mechanism as I read it, so we are talking about the same thing.
There is no index and no push — it is follow-a-ship:

- Someone pokes their shell's `peers.json` with
  `{"add": "~ricsul-bilwyt"}` (`shell.hoon:235-242`).
- That makes one grub, `/peers/~ricsul-bilwyt.json`, whose fiber opens a
  `keep` on
  `/sys/ames/ships/~ricsul-bilwyt/root/apps/shell.shell/share/public`,
  grub `desks.json` (`+peer-pub-road`). It is live: what I publish later
  shows up without them acting again, and each mirror owns its own
  traffic, so an unreachable ship blocks nobody.
- On my side the road is readable because it is in the `public.grp`
  usergroup's weir, and `public.json` is derived from the live grants —
  so the listing cannot advertise something I did not actually share.
- `+gather-peers` renders the cards the "add apps" browser shows.

Two consequences.

**The lesser: a stranger's only path to my software is a dojo poke.**
Reach is exactly the set of ships that have typed my `@p`. That is a fine
trust model and I am not asking for a store — but "open the dojo and poke
this" is a wall in front of everyone who is not already comfortable, and
it is the single step between hearing about lattice and having it. If
there is an intended path from a *link* to that poke I would like to know
it; if there is not, I think it is worth one.

**The greater: every current user of mine already has this relationship,
and the migration would silently drop it.** People running lattice today
installed `%grubbery` from `~ricsul-bilwyt`, and kiln syncs my whole desk
to them. That *is* a software-source relationship, and a broader one than
peering — kiln puts my files in their ball wholesale. If the migration
does not carry it across they do not merely lose discovery: they stop
receiving lattice updates, silently, and the only fix is telling every
one of them to type a poke they have never heard of. That is exactly the
perceivable change the migration exists to avoid.

**So: the ship you got grubbery from should be a peer by default.**

This is not a favour to my ship. It is true by construction for anyone
who distributes grubbery; it encodes a relationship that already exists
rather than creating one; and it grants strictly less than that
relationship already grants — a keep on one public listing, against kiln
syncing an entire desk. A user who does not want it removes the peer,
which the shell already supports.

If you would rather not make it the rule, the fallback is mine to own: a
one-time migration that pokes the shell once and records that it did,
guarded on "this ship got grubbery from ricsul" rather than on "this ship
is not ricsul" — someone who took grubbery from the moon and lattice by
another route should not have me inserted into their sources. I would
rather it were the rule, because every distributor hits this the first
time they move an installed base, and a silent loss of updates is a bad
thing for a user to discover months later.

### 4.3 Signing: I think I am using the wrong door

Auspex signs every message with the ship's networking key:

```hoon
::  nex/auspex/app.hoon +our-ring
;<  n=noun  bind:m  (typed-scry:io noun %noun ~[%j %vein (scot %ud lyf)])
```

That reads `%vein` — the ship's private ring — through `/sys/scry`. And
`/sys/scry` is one road: `typed-scry` is not a special power, it is an
ordinary poke to `/sys/scry`'s `main.sig` (`lib/fiberio.hoon:876`), so it
is weir-gated like any other `/sys` reach — your own comment beside
`+grow` says exactly that, *"a sandboxed grub (whose weir does not grant
/sys) is vetoed by default, and no special-case gating exists anywhere"*
(`lib/fiberio.hoon:889`) — and `handle-typed-scry` passes the vane path
straight through without inspecting which vane or care is being asked
for.

So on that road, a guest that can verify a signature can also produce
one. Every Auspex install needs to verify, because every recipient must
fetch the author's public key. A user who only ever *reads* mail would
still be granting the road that lets the app sign as them, for ever.

**But I do not think that road is the one I should be on.** `+sync-jael`
(`app/grubbery.hoon:5862`) already mirrors both key sets into the tree as
two separate grubs, and on a live ship `/sys/jael` holds exactly:

```
public-keys.jael-public-keys-result     <- what verifying needs
private-keys.jael-private-keys          <- what signing needs
```

Weir roads name single grubs — Auspex's own weir already names
`/sys/bowl.sig`. So "may verify, may not sign" looks **expressible
today**: a road to `public-keys.jael-public-keys-result` and not to its
sibling. The granularity I was going to ask you to build appears to
already exist; I am reaching for the keys through the coarse door, which
is my bug rather than grubbery's gap.

Two things I want to confirm before I change it:

1. **Is `/sys/jael` the intended app-facing surface**, or a kernel-
   internal mirror I should not depend on? Nothing else reads it — the
   only other `%vein` references in the tree are the kernel writing those
   grubs and the marc that types them, and no nexus but Auspex touches
   it.
2. **Will the shell actually grant a road to one grub under `/sys`**, or
   does consent work at directory granularity in practice? If the latter,
   the split exists in the tree but not in the thing a user is asked, and
   the useful change is in the shell rather than the kernel.

If both answers are yes, Auspex drops `%vein` scrying, keeps `/sys/scry`
only for the remote-scry farm that carries attachment blobs, and a
read-only mail client becomes something a user can actually choose.

If `/sys/jael` is off-limits, then the original ask stands and there are
two ways to close it, which compose:

- **A signing service.** Grubbery signs on request: hand it a domain tag
  and a hash, get back `(sigh (shaf <domain> <hash>))`. What bounds the
  grant is **domain separation**, which Auspex already does — the digest
  is `(shaf %auspex (sham unsigned))` — so a signature obtained under one
  app's tag can never verify under another's, and the service refuses to
  sign a bare hash for anyone. *"May sign things only your own verifier
  accepts"* is a permission a user can reason about; *"may read your
  private key"* is not.
- **Finer roads under `/sys/scry`**, per-vane or per-vane-and-care, so
  `%j /puby` is grantable without `%vein`. Harder, because vane paths are
  open-ended — which is part of why reading the grubs looks better than
  filtering the scry.

I am not blocked either way: leaving Auspex in `/apps` works today. I
raise it because I am the first app in the tree to want either door, and
because whichever answer you give sets the precedent for every app that
verifies anything.

### 4.4 Outbound roads

Auspex talks to other ships two ways: a **remote keen** to an arbitrary
ship for a blob by hash and for that ship's protocol descriptor, and a
**remote poke** to an arbitrary ship's auspex blot to deliver a chain.

Weir, as I read it, describes make/poke/peek road sets — who may reach
*my* paths. Can it express the outbound direction: *this app may poke and
keen any ship, at this path shape*? If not, what is the intended model —
is outbound simply unrestricted for an installed app, or is there
something to declare?

### 4.5 Publishing to ships that have installed nothing

Auspex publishes two things readable by **any** ship, unauthenticated:

- `/mail/blob/<hash>` — attachment bytes, content-addressed, so a reader
  must already hold the hash, which means holding a message that names
  it;
- `/proto` — which protocol versions and marks this ship speaks, at a
  fixed, guessable path.

A recipient who cannot fetch an attachment has a broken feature, and the
sender cannot know in advance which ships will need it. With
`permit/share.json` defaulting to private, how does an app publish
something permissionlessly? Is that a grant the app requests, a thing the
user turns on per alias, or not expressible?

`/proto` is an enumeration surface — any ship can ask "do you run Auspex,
and which build". I decided that was an acceptable trade and wrote the
argument down rather than waving it away; I am happy to be told
otherwise.

### 4.6 The floor, and who publishes

- What grubbery revision must an **installer** be on for the `desk` nexus
  and the shell? That is the real gate on my beta.
- If a moon distributes grubbery, do I publish apps from
  `~ricsul-bilwyt` or from a moon of it? Ricsul is also my memory store
  and a live lattice install, so I would rather publishing did not
  require it to sit on a bleeding edge it uses in anger.
- Does the storefront read a published code dir from a ship that is not
  the publisher of grubbery itself?

One thing I would add to the floor question, because it caught me: **a
code namespace is hermetic for source.** `+find-code-ns` returns `~`
rather than falling back to a parent — *"Lower namespaces must include
marks/libs they need"* (`app/grubbery.hoon:1815`) — while marks and nexuses go through
`+resolve-built`, which does walk ancestors. That asymmetry is correct
and it is also easy to violate: an app that leans on the publisher's desk
`lib/` compiles for the publisher and for nobody else, silently, because
a nexus that will not compile is skipped rather than reported. I now gate
every published code dir on resolving its own imports, and both of mine
are clean. It may be worth saying out loud in whatever documents the
code-dir shape, because I do not think I will be the last to hit it.

A smaller one in the same family: `+get-app-mcp-paths` scans
`/apps/<app>/desk/code/lib/tools`, so an installed app can ship its own
MCP tools — but that path is hermetic too, and it is a different layout
from the `lib/tool-bundle/tools/` the desk shape uses. If that is the
intended surface for app-shipped tools I will move lattice's eleven onto
it; right now I ship them only in the desk shape and omit them from the
code dir rather than publish files that cannot compile.

### 4.7 How the shell should ask — a prompt is a scarce resource

Here is Auspex's whole `weir.json`:

| road | why |
|---|---|
| `/sys/bowl.sig` | read the clock and the name of this ship |
| `/sys/behn/` | give up on a delivery that is not coming |
| `/sys/eyre/` | serve the mail client at `/apps/auspex` |
| `/sys/scry/` | verify signatures, sign your mail, fetch attachments |

Which of those could a user rationally deny? The clock? Timers? Binding
its own route? Deny any one and the app does not run, so "no" is never a
considered answer. **Three of the four are not decisions — they are the
definition of a running app.** Exactly one is a real decision, and only
because it is coarse enough to matter (§4.3).

The problem with a wall of toggles is not that it is tedious. It is that
it is **camouflage**: put the one consequential grant in a list of three
inevitable ones and you have trained the user to click through the
consequential one. A prompt that is never rationally denied is worse than
no prompt, because it teaches the reflex that defeats the prompt that
matters.

Three suggestions, in dependency order:

1. **Ambient vs consequential.** Let the shell classify roads and grant
   the ambient set by the act of installing. Bowl, behn, and
   eyre-for-your-own-route are ambient. This alone takes Auspex from four
   prompts to one.
2. **Grant at grub granularity, not directory granularity** — §4.3
   arriving from the other direction. You cannot safely auto-grant a road
   meaning "anything any vane will answer", so the split is what makes
   automation possible: reading the public-keys grub is ambient for any
   app that verifies anything, and reading its private-keys sibling is
   the one grant worth a sentence of the user's attention. The tree
   already separates them. If consent is offered per directory, they
   collapse back into one road and the coarse one has to be asked, and
   asked scarily.
3. **Prompt on the delta, not on install.** The declaration is a contract
   the kernel already enforces. Grant the declared set at install and
   surface only what an *update* adds. "Auspex 1.4 wants a road 1.3 did
   not" is real signal; "Auspex wants four roads" on first install is
   noise.

One half of this is mine rather than yours, and it is built: **a denied
road produces a comprehensible app, not an error.** Auspex carries a
`/caps` grub, default-denied and upgraded by an ephemeral probe at
startup. With `/sys/scry` refused it still opens, shows every message as
`unverified` — which the format allows, since a missing key is never a
forgery — and refuses to *send* with a plain reason, rather than failing
to start. `/api/whoami` reports what it can currently do. That is the
precondition for contextual consent ever working: you can only ask at the
moment of need if the app has a sane state before the answer.

## 5. What I want to do, and my fallback

**Preferred: Auspex is the first non-lattice app on the code-nexus
path.** The work on my side is done and verified rather than estimated.
The overlay was already the shape a code namespace wants —
`lib/ nex/ mar/`, no in-place edits, one script that maps it — and both
apps now declare themselves the way the shell expects:

```hoon
::  beside the tile.json row auspex already writes in +on-load
[%over %& [/ %'alias.json'] [[/ %json] (pairs:enjs:format ~[['name' s+'auspex'] ['description' s+'Signed mail']])]]
[%over %& [/ %'weir.json'] [[/ %json] weir-json]]
```

Both produce a code directory — `nex/ lib/ mar/` plus a `bill.json` and
an opaque `version.txt` — and both resolve every source import inside
themselves. What is left is on your side: a floor to build against
(§4.6), and an answer on migration (§4.1) before lattice can follow.

The release I would ship, in the order each step becomes invisible on its
own:

1. Grubbery catches up to `develop`. Done and rehearsed; it ships alone,
   because a kernel merge into a desk a real planet tracks unattended is
   the genuinely risky step and should not travel with anything else.
2. The restructure: `alias.json`, `weir.json`, the code namespace. Done,
   and inert until something reads it.
3. Peering, per §4.2.
4. Lattice migrates, per §4.1.
5. Auspex becomes **discoverable, not installed** — one click in the
   storefront. Installing it for everyone means a new tile, new state and
   a mail nexus compiling in the ball of people who wanted a notes app.
   That is a perceivable change and it is what the permission model
   exists to prevent.

**Fallback, if standing this up is more than about a week:** a beta with
the smallest possible fork. I add only auspex's own sources to the dist
desk. No launcher restoration, no docket rewrite. Auspex is reachable at
`/apps/auspex`, lattice's tile and URL do not move, existing users see
nothing change, and the throwaway work stays unwritten. The migration
afterwards is the directory re-map I would have done anyway. I would
still rather not push a mail nexus into everyone's ball, so if there is a
way to make it opt-in on the old base that I have missed, I would take
that instead.

## 6. Something I can offer: the other half of the alias book

The book answers **where** an app is. It does not answer **what it
speaks**, and for anything that is a protocol rather than only an app,
that is the harder half. I built it for Auspex and it is running on two
ships:

- Every nexus publishes `/proto`, readable over keen:
  `[%auspex versions=~[1] marks=~[%auspex-chain] caps=[…]]` — versions
  and marks parallel, so a version *is* a mark name; caps are the
  receiver's limits.
- Before first contact a sender probes the peer's `/proto` on an
  ephemeral fiber, picks the **highest common version**, and pokes that
  mark. No common version produces a refusal naming both sides' versions,
  per recipient, before anything is signed. Over a peer's declared caps
  does the same. No answer at all is treated as version 1, which is the
  compatibility rule. Answers are cached per ship — a day, an hour after
  a refusal, with a `forget-peer` action to force a re-probe.
- A poke timeout is **not** treated as failure: grubbery's ack is not
  observable from a nexus fiber, and the mail lands. Discovery is the
  liveness signal instead, and only a nack is a failure.

Two things in that I think generalise:

1. **Name resolution and version negotiation are different questions and
   want different answers.** `/sys/name` — or the book — gives a
   location; a descriptor at that location gives the terms. Compose them
   and a sender does one cheap read to learn whether it can talk at all.
2. **It answers the stale-pointer worry** from the chat: *"you could look
   in the old place, but who knows what's there now."* Don't check the
   location, check what is *there*. A descriptor is self-identifying, so
   a stale path is one cheap read away from being detected, and the
   fallback to the book is unambiguous rather than a guess.

On the destination question: I now think a protocol should not name a
handler. It names a message shape and a way to find the destination. For
a non-grubbery ship that resolves to `%agent` plus a clay mark; for a
grubbery ship, to a path plus the marc governing it. If the book's
entries could carry that — what I speak, not only where I am — the same
discovery works across both, and I would drop the thin gall agent I had
planned.

Happy to be told the shape is wrong. It is one grub and a probe, and the
value is that it exists and has already been wrong a few times.

## 7. What I am asking for

1. **§4.1** — whether a desk nexus can adopt an existing instance, or
   what the intended migration shape is. This is the one that blocks a
   clean migration of lattice's installed base.
2. **§4.2** — whether the ship you got grubbery from is a peer by
   default. Not specific to me; every distributor hits it the first time
   they move an installed base.
3. **§4.6** — the installer floor, which decides whether my beta waits.
4. Yes or no on **Auspex as the first code-nexus app**, and roughly when.
5. **§4.3** — whether `/sys/jael` is the surface an app should read keys
   from, and whether the shell will grant a road to one grub under
   `/sys`. If yes, the read/sign split already exists and I am on the
   wrong road; if no, whether a signing service is worth doing.
6. **§4.7** — whether "ambient vs consequential" is a distinction the
   shell wants to draw. I will build the graceful-degradation half
   regardless; it is already built.
7. Whether the **`/proto`** idea is worth folding into the book, or you
   would rather it stayed mine.

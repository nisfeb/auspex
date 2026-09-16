# Retiring the fork: the state-version collision, and options

**From:** `~ricsul-bilwyt` (nisfeb) — lattice, auspex, calendar
**For:** the grubbery meeting
**Written against:** `develop@d0158d9` and `nisfeb/grubbery@dist/single-release` (tip `50740a0`), 2026-09-16

---

## The short version

We run a fork of the grubbery desk — `dist/single-release` — for one reason:
**we find and fix things faster than they get merged upstream.** 15 of our PRs
are open against `develop` right now. The fork is how ricsul and its
subscribers get those fixes today. **We want to stop needing it.**

I tried to merge `develop` into the fork this week to close the gap. The
mechanical part is easy: 8 files auto-merge, and of the 11 conflict hunks in
`app/grubbery.hoon`, **9 are `~? > dbg` trace lines** from our PR #70 against
your own tracing work.

The blocker is one thing: **our fork and `develop` both define `state-1`,
`state-2` and `state-3`, and they mean different things.** A merged
`versioned-state` can only hold one definition of each tag, and `on-load` can
only route one way. That is not a conflict I can resolve by picking a side — it
needs a decision about whose numbering wins and what happens to piers on ours.

I have four options below (§4) and a recommendation. I need about twenty
minutes of your time on §3 and §4; everything else is context you can skim.

---

## 1. Why the fork exists

Not because we wanted to diverge. Every fix we make goes to two places: the
fork, so ricsul's users get it now, and a PR against `develop`, so the fork can
eventually be deleted. The fork is a waiting room, not a product.

Current open PRs, all ours, oldest first:

| PR | branch | what |
|---|---|---|
| #49 | `perf/conns-in-agent-state` | bound HTTP requests stop getting slower for ever |
| #58 | `fix/farm-top-ledger` | `+farm-top` keeps its own ledger instead of scrying the farm |
| #60 | `fix/stock-desk-provisioning-hangs` | stock desk provisioning hangs on a lost git fetch |
| #61 | `fix/registry-nested-registrations` | nested registrants coexist and keep their grants |
| #62 | `fix/apply-bill-tolerates-unknown-keys` | one unreadable bill entry no longer loses the whole install |
| #63 | `fix/desk-source-retries` | a desk retries its source instead of parking for ever |
| #66 | `fix/permits-ui-responsiveness` | the permissions page answers before it works |
| #67 | `fix/registry-resolves-relative` → **#61** | the registry resolves a sandboxed sender's relative rail |
| #68 | `fix/quiet-bang-file` | a banged nexus prints once, not once per grub |
| #69 | `fix/explorer-traces-off` | explorer per-request traces off unless `dbg` |
| #70 | `fix/quiet-traces` | routine traces off unless `dbg` |
| #71 | `fix/remote-drop-fell` | a fiber dropping a remote subscription gets its `%fell` |
| #72 | `fix/stock-repos-poll` | stock mirrors poll github |
| #73 | `fix/code-nexus-repair` | a neck-less `/desk/code` wedges an app for ever |
| #74 | `fix/silo-refcount-and-traces` | a remote file peek leaks a ject ref; silo traces bury warnings |

#67 is stacked on #61's branch, so it cannot merge before #61.

**#73 and #74 are from this week and are the ones I would most like looked at**,
because they are both "an app is silently dead and the desk page says it is
fine" bugs that cost a real subscriber hours of downtime. Details in §5.

---

## 2. What the merge actually looks like

`dist/single-release` is **17 behind / 88 ahead** of `origin/develop`.

Trial merge (`git merge --no-commit --no-ff origin/develop`):

- **8 files auto-merge**, including `gub/nex/desk.hoon`, `lib/migrations.hoon`
  and `lib/nexus.hoon`.
- **5 content conflicts:** `app/grubbery.hoon` (11 hunks), `explorer.hoon` (1),
  `mcp.hoon` (1), `lib/fiberio.hoon` (1), `lib/root.hoon` (1).
- **8 modify/delete conflicts:** `anthropic.*`, `claw/agent.hoon`,
  `itinerary.*` — files our ball trim deleted that `develop` has since modified.

Of the 11 `app/grubbery.hoon` hunks, **9 are `~? > dbg` trace lines** — our #70
versus your tracing. Trivial. `lib/root.hoon` is a **pure addition** (`develop`
adds `geocode.geocode` and `places.places` rows). `explorer`, `mcp` and
`fiberio` are one small hunk each.

**Hunks 1 and 2 are the whole problem**, and they are §3.

---

## 3. The blocker: two meanings for the same state numbers

### 3a. `state-1` is not the same type on both sides

```
ours:     +$  state-1   pool=pool:nexus    code=code:nexus     (live types)
develop:  +$  state-1   pool=pool-1        code=code-2         (frozen types)
```

`state-0` differs the same way (`code=code:nexus` vs `code=code-2`).

So a `%1` written by our fork holds **live** `pool` and `code`, while your
`state-1-to-2` expects **frozen** `pool-1`/`code-2` and calls
`pool-1-to-pool` / `code-2-to-4` on them.

### 3b. Our `%2`/`%3` are a different lineage from yours

Ours, quoted from our `migrations.hoon`:

> state-2 and state-3 are the perf lineage (perf/conns-in-agent-state) that
> `~ricsul-bilwyt` ran. %2 carried the open eyre conns in agent state, %3 was a
> one-time born sweep with no shape change. Neither exists on develop. They are
> here only so such a pier can come back down to %1.

Ours carry a `conns=(map @ta binding:eyre)` field. Yours are `%tag`→`%tags`
(`%2`), subject-as-dependency (`%3`), `%font` removal (`%4`), lode loses `refs`
(`%5`).

**That lineage is PR #49, which is still open.** Our `%2`/`%3` exist because we
shipped it before it merged, and then `fed08b3` walked ricsul back down to `%1`.

### 3c. Why that blocks the merge

`versioned-state` is a `$%` — one definition per tag. `on-load` reads the stored
version and picks an arm. The two `on-load` gates are mutually exclusive:

```
ours:     %0 %2 %3  ->  down to %1   ("transient conns and continue as %1")
develop:  %0 %1 %2 %3  ->  up through to-4, then state-4-to-5
```

If the surviving definition mis-describes what our fork wrote, the agent either
fails to compile — which clay rejects, safely — or **compiles and misreads live
state**. The second is unrecoverable, and ricsul holds a shared memory store.

### 3d. Also worth flagging: the migration is not free even when correct

Your `state-2-to-3` says so itself:

> The old ckeys were computed with the subject hash folded in explicitly rather
> than via dep-keys, so they will not match new keys on the next build — one
> full recompile per namespace, then steady state. Correct and loud.

So any ship taking this pays a full recompile of every code namespace. Fine, but
it should be an announced release rather than a surprise.

---

## 4. Options

### Option A — merge our open PRs, we rebase, fork dies

**You merge some or all of §1; we drop our equivalents and rebase onto
`develop`.** The state collision evaporates for anything that lands, because
your numbering becomes the only numbering.

- **Best outcome**, and the only one that actually retires the fork.
- Costs your review time, which is the scarce thing — that is why the fork
  exists in the first place.
- #49 is the highest-leverage one: landing it makes the conns lineage *yours*
  and deletes the collision at its source.

### Option B — we renumber our perf states out of collision

We move our `%2`/`%3` to something that cannot collide (`%100`/`%101`), keep
their downgrade arms, and take your `%1`-`%5` verbatim.

- Unblocks us unilaterally, today.
- Permanent wart in our `migrations.hoon`, and a reader has to be told why.
- Needs care that `on-load` tries our tags before yours.

### Option C — we delete our `%2`/`%3` entirely

If no pier is still on the perf lineage, those arms are dead weight.

- Cleanest of the unilateral options.
- **Requires confirming no live pier is on `%2`/`%3`.** Ricsul was walked down
  to `%1`; I have not audited other piers and cannot audit yours.
- If a pier *is* on `%2`, deleting the arm bricks its load.

### Option D — stop merging `develop`

Stay where we are; take upstream fixes by cherry-pick only.

- Zero risk today, and the reason I am raising this at all: every week we do
  this the gap grows. 17 commits now, and `develop` has five commits of
  `itinerary` work plus `geocode`/`places` that we do not carry.
- I do not want this, but it is the honest default if nothing else happens.

**My recommendation: A for #49 specifically, then C if the pier audit is clean,
otherwise B.** A alone is the only path that ends with us not maintaining a
fork of your kernel.

---

## 5. The two fixes from this week I would most like reviewed

Both are "silently dead app, desk page says fine" bugs. Both were measured on a
real subscriber planet, not reasoned about.

### #73 — a neck-less `/desk/code` wedges an app for ever

A `/desk/code` created as a plain directory has no `[/ %code]` neck, so it is
not a code namespace and `build-code` never runs over it. Files land with the
right marks and nothing compiles them. `+apply-bill` cannot help: it MAKES
missing instances and SKIPS existing ones, and these exist.

`+ensure-code-nexus` repairs it, but only ran on the desk nexus's **rise** —
which a subscriber never does by itself. The PR calls it from `+sync-release`
too, so an arriving release repairs it.

Measured: lattice on a subscriber took a version bump, mirrored the tree,
reported itself up to date, and its route hung past 30s. It recovered only when
the desk nexus was reloaded by hand.

### #74 — a remote file peek leaks a ject ref

In `+discharge-peeks` the `%file` branch is written **twice** — `6d3d5e10` added
`%ball` and `%file`, then `08699d44` added the explaining comment plus a `%file`
bump that already existed. Every discharged remote file peek nets +1 against
`+hydrate`'s single drop, so those jects are never collected and the silo grows
for the life of the ship.

The same PR gates the four silo refcount traces on a per-file `+dbg`. They were
unconditional `~& >>>`; one ship logged **3,041 identical lines for a single
lobe** in one burst — and that lobe did not appear in `+audit-silo`'s report at
all, i.e. it was already fully collected with nothing referencing it. The
warnings were not reporting damage.

---

## 6. Two questions that are yours, not mine

### 6a. Is the ball still all-or-nothing per installer?

Our ball trim exists because **kiln syncs the whole desk, so every lattice user
receives every nexus in `gub/` and their ball compiles apps they did not
install.** That is why we deleted `anthropic`, `claw` and `itinerary` — and why
8 of the 13 merge conflicts are modify/delete on exactly those files.

If nexuses become optional per installer, the trim disappears and so do those
conflicts. The desk/code-namespace work looks like it is heading there. Is it?

(`geocode.hoon` and `places.hoon` have no imports at all, so they are cheap for
us to carry if the answer is "not yet" — this is not a complaint about those
two.)

### 6b. Where should refcount damage be reported?

`+audit-silo` finds **6,254 distinct referenced-but-absent jects** on one of our
test ships and 14,286 referencing versions on ricsul — **all historical, zero on
a latest version**, so nothing is booming. Origin undetermined: we ruled out
eight theories and could not reproduce it.

The best unproven candidate is the cross-ship transfer merge, whose own comment
admits the hole:

> Nothing ready but work remains: refs point outside this transfer and are
> absent — **insert anyway** rather than loop.

That stores a tree naming children that are not present, which is exactly the
shape of the damage, and fits the all-`%ject`/no-`%noun` signature. Its trace
`%data-merge-unresolved-children` fired zero times on three ships, so we have no
positive evidence — the damage predates every log we can reach.

Do you already know the cause? If not, is that fallback intended to be
reachable, and would you take a PR that makes it loud rather than silent?

---

## 7. What I am asking for

1. **Twenty minutes on §3 and §4** — specifically whether Option A is possible
   for #49, since it dissolves the collision rather than working around it.
2. **A yes/no on whether any pier you know of is on our `%2`/`%3`**, which
   decides between Option B and Option C.
3. **A read of #73 and #74** when you have time. They are small and they fix
   silent death.
4. **An answer to 6a** — because if the ball is going to stay all-or-nothing, we
   keep the trim and accept permanent divergence on those files, and I would
   rather plan for that than keep re-resolving the same eight conflicts.

The merge is sitting uncommitted on a throwaway branch on my side. Nothing is
staged to ricsul, and I am not going to resolve §3 unilaterally before this
conversation.

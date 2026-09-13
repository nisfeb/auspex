# Distributing Auspex — the structure today, the structure after, and the runbook

Written 2026-09-09. Every fact here was read off a ship, a branch, or a
script on that date; where something is a decision still to be made it says
so. The production ship is `~ricsul-bilwyt`. **Nothing in this document is
executed on it until an explicit go, one step at a time.**

---

## 0. Read this first — 2026-09-10

**This route is now the fallback, not the plan.** Reading grubbery
`develop@68ca752` (36 commits past the base this fork sits on) turned up
the distribution mechanism this runbook works around, already built:

- `gub/nex/desk.hoon` mirrors a **code directory** from anywhere in the
  namespace (`~ship/apps/foo/desk/code`, or a checked-out repo), gated by
  an opaque `version.*` tag, snapshotting `/code` and `/data` before new
  code lands. Guests resolve marcs against their own `/desk/code` and
  distribute the marcs they use, content-addressed.
- `gub/nex/shell.hoon` is the permission manager: it reads each nexus's
  `alias.json` and `weir.json`, records consent, writes weirs. It also
  owns the launcher grid, and its `/book` — one grub per alias holding
  the current claimants and their locations — is the `/sys/name` idea
  already standing up.

Two consequences for what follows:

1. **The launcher restoration in §2 and §4 should not ship.** It is 629
   lines of pre-split `tiles.hoon` plus a docket rewrite visible to every
   existing lattice user, carried so a second app has somewhere to
   appear — and the shell owns that now. Ship auspex reachable at
   `/apps/auspex` with lattice's docket untouched, or wait for the shell.
2. **The ball trim exists because the desk model ships everything to
   everyone.** Guest isolation removes the reason for it.

The proposal taken to the grubbery meeting on 2026-09-10 is
`docs/distribution-proposal.md`; **the plan that supersedes this runbook
is §9 below**. Use §1–§8 only if the code-namespace path is more than
about a week out — and then use the **minimum-surface variant** in §5.0.

## 1. How lattice reaches users today

### 1.1 Grubbery, in one paragraph

Grubbery is one desk (`%grubbery`) and one Gall agent. The agent builds a
tree of *nexuses* — Hoon cores with fibers, each living at a path — from the
desk's `gub/` directory: `gub/nex/` (nexus sources), `gub/lib/`, `gub/mar/`
(the "marcs" that validate every blot), plus a hard-coded root nexus
(`lib/root.hoon`) whose `%fall` rows say which nexus instances exist at boot.
That built tree is "the ball". The desk-level `lib/`, `tests/`, `gen/` are
ordinary clay files, compiled only on demand (`-test`, a generator) — they are
not in the ball. Kiln syncs the whole desk to every installer, so *the desk is
the distribution unit*: what is in `gub/` on the publisher is what runs on
every ship that installed from it.

### 1.2 The three repositories

| repo | branch | what it holds |
|---|---|---|
| `gwbtc/grubbery` | `develop` (base `7117ae1`) | upstream: the agent, the full app tier (forge, feeds, calendar, shell, tiles…), the MCP nexus |
| `nisfeb/lattice` | `main` | the lattice **overlay**: `grubbery-overlay/{lib,mar,mar-clay,mar-core,nex/lattice,tests}`; `scripts/sync-overlay.sh <desk-root>` copies it into a desk tree; `scripts/deploy-ricsul.sh` rsyncs the same mappings straight to ricsul's mount and stops before the commit |
| `nisfeb/grubbery` (local `~/software/groundwire/grubbery`) | `dist/lattice-only` | **the distribution desk**: upstream `develop@7117ae1` + a short stack of commits (below). This is what ricsul publishes. |

`dist/lattice-only`, top to bottom:

1. `lib/root.hoon` stripped to two app rows — `/apps/lattice.lattice_app` and
   `/apps/mcp.mcp` — and the app-tier nexus **sources deleted** (forge, claw,
   feeds, calendar, pad, guestbook, shell, tiles, …). The *instances* those
   sources had already created still exist in every ball that ever ran them;
   without source they are BANGed (inert, but present).
2. The lattice overlay **vendored** into `desk/gub/` (libs into both
   `desk/gub/lib` and `desk/lib`; nex, marcs, clay-marcs, tests).
3. Fixes upstream lacks: a `%2/%3 → %1` agent-state downgrade, the corrected
   poke-ack marc, obelisk auto-install, the mobile scroll fix, display names,
   the render cache, the navy-and-amber icons.
4. The **ball trim**: 77 `gub/` files no root reaches (`tools/desk-reach.py`
   computes the reachable set from the roots `app/*`, `lib/root.hoon`,
   `gub/nex/lattice/**`, `gub/nex/mcp(.hoon,/**)`, `gub/nex/port.hoon`, all
   marcs; `tools/trim-lattice-only.sh` git-rms the rest). Motivation: a
   1,300-result cold build killed a small-loom installer.
5. `desk.docket-0`: title **Lattice**, `site+/apps/lattice`, version `[1 0 0]`.
   Landscape shows a Lattice tile that opens lattice directly. There is no
   launcher.

### 1.3 The publisher

- `~ricsul-bilwyt` (asimov, mount `/home/sneagan/ricsul-bilwyt/_data/ricsul-bilwyt/grubbery`,
  ssh `-p 4141`) runs `dist/lattice-only` at `a902d7e` **minus the trim** — the
  three `|pass [%c %info …]` deletion lines are staged, not yet pasted.
  Clay rev 248 on 2026-09-08.
- It is `|public %grubbery`. Users run `|install ~ricsul-bilwyt %grubbery`.
- `~martyr-sanryg` (a real planet) tracks it through kiln and picks up every
  revision within minutes. **A bad desk on ricsul reaches a real planet with
  nobody acting.**
- Ricsul is also the memory store this session's own recall runs on. A broken
  deploy is felt immediately and personally.

### 1.4 How a lattice change flows

lattice repo → `sync-overlay.sh` into the dist branch's `desk/` → commit on
`dist/lattice-only` → push `fork` → rsync the changed files to ricsul's mount
(never `--delete`) → `|commit %grubbery` in ricsul's dojo (or the MCP `commit`
tool, which times out and is judged by `check_bin`) → bounce
(`|suspend %grubbery`, `|revive %grubbery`) when fiber code changed.
Deletions never reach clay from the mount; they need `%info` lines pasted by a
human, one per line, ~35 entries each, and clay refuses a line atomically if a
kept file imports a deleted one.

### 1.5 Where auspex is today

The auspex repo (`nisfeb/auspex`) mirrors lattice's shape:
`grubbery-overlay/{lib,mar,mar-gub,mar-core,nex/auspex,gen,tests}` +
`protocol/vectors/`, and `scripts/sync-overlay.sh <desk-root>` (additive,
refuses to overwrite any non-`auspex-` file, syncs `gen/` and
`protocol/vectors/` too). Its root row —

```
[%fall %| /apps/'auspex.auspex_app' [`[`[/auspex %app] ~ %.n ~] ~]]
```

— lives **outside the repo**, hand-added to each dev ship's `lib/root.hoon`.
Auspex runs on `~wex` (dist-shaped root.hoon, the production-shaped
rehearsal ship) and `~feb` (full upstream + overlays). It is in no
distribution.

## 2. The structure after

One desk, one launcher, two apps.

```
desk/                                  nisfeb/grubbery, branch dist/lattice-only (rename optional, §5.6)
  desk.docket-0                        title Grubbery, site /apps/grubbery, version [1 1 0]
  lib/root.hoon                        upstream rows + tiles row + lattice row + mcp row + AUSPEX row
  gub/nex/tiles.hoon                   the launcher: upstream d839ede, pre-split, self-contained, UNMODIFIED
  gub/nex/lattice/**   gub/lib/lattice-*.hoon   gub/mar/lattice/*   gub/mar/clay/**     (as today)
  gub/nex/auspex/**    gub/lib/auspex-*.hoon    gub/mar/auspex/*    gub/mar/auspex-chain.hoon  gub/mar/auspex-action.hoon
  lib/lattice-*.hoon   lib/auspex-*.hoon        (desk-level copies, so /tests can import them)
  tests/lib/{lattice-*,auspex-chain,auspex-web,auspex-vectors}.hoon
  gen/auspex-vectors.hoon              protocol/vectors/v1.json
  tools/desk-reach.py                  roots now include gub/nex/auspex/** and gub/nex/tiles.hoon
```

What a user sees: Landscape tile **Grubbery** → `/apps/grubbery`, the
launcher, listing **Lattice** and **Auspex**, each from the `tile.json` its
own nexus writes in `on-load`. `/apps/lattice` and `/apps/auspex` keep
working as direct URLs; lattice's desktop app keeps connecting to
`/apps/lattice`. Install command unchanged.

What does not change: the `%grubbery` desk and agent names; lattice's
state version; the chain format; every URL either app serves. The launcher
is upstream code and stays upstream's — decided: **not modified**, grey bell
included.

Already done toward this, on branch `dist/launcher-restore` (`5ea5700`, on
top of `a902d7e`): `tiles.hoon` restored, its root row, the docket rewritten
to Grubbery `[1 1 0]`. Rehearsed on `~feb` and on `~wex` (production shape):
both apps listed, both icons, both click-throughs; mount files byte-identical
after the ball round-trip. **Auspex is not vendored into it yet.**

## 3. Preconditions — all must be true before §5 starts

- [ ] Auspex release gates: Gate 4 (format-refusal transcript against the
      shipping build) closed, or explicitly waived by sneagan. Gates 1–3, 5
      are closed (`docs/release-plan.md`).
- [ ] Auspex `master` is what ships: protocol v1, discovery, Thunderbird and
      desktop unaffected by this change. Pin the commit in the vendoring
      commit message.
- [ ] Lattice `main` and the dist branch agree (the other session's lattice
      work on `dist/lattice-only` is merged, nothing pending there).
- [ ] The ricsul **trim** (`ricsul-trim-pass-v3.txt`, three `%info` lines) is
      either applied first or folded into this release — decide in §5.3. Do
      not leave it half-applied across the release.
- [ ] A fresh mount backup exists on asimov (§5.3 step 1) — the July ball
      reset is why.
- [ ] `~martyr-sanryg` is reachable and its operator knows a desk update is
      coming (it will rebuild for ~1 minute).
- [ ] Decision recorded: **ghost tiles** — clear the dead app-tier instances
      on ricsul before the launcher shows them, or ship with dead tiles
      (§5.5). This is the one production *ball write* the release may need.

## 4. Vendoring auspex into the dist desk (one-time, then repeatable)

Add `tools/vendor-auspex.sh` to the dist repo, mirroring the lattice step:

```bash
#!/usr/bin/env bash
# Vendor the auspex overlay into desk/. Idempotent; never deletes.
set -euo pipefail
AUSPEX="${AUSPEX:-$HOME/software/personal/urmail}"       # the auspex checkout
DESK="$(cd "$(dirname "$0")/../desk" && pwd)"
"$AUSPEX/scripts/sync-overlay.sh" "$DESK"                  # libs → gub/lib + lib, nex, marcs, wire marcs, gen, tests, protocol/vectors
# the row auspex's sync script only CHECKS for:
grep -q "auspex.auspex_app" "$DESK/lib/root.hoon" || {
  echo "root.hoon has no auspex row — add it under the lattice row:" >&2
  echo "  [%fall %| /apps/'auspex.auspex_app' [\`[\`[/auspex %app] ~ %.n ~] ~]]" >&2
  exit 70
}
echo "vendored auspex @ $(git -C "$AUSPEX" rev-parse --short HEAD)"
```

Then, once:

1. `git checkout dist/lattice-only && git merge --ff-only dist/launcher-restore`
   (it is a fast-forward today; if lattice work landed since, rebase
   `dist/launcher-restore` first).
2. Add the auspex row to `desk/lib/root.hoon` directly under lattice's, with
   the same comment style ("auspex: the signed-chain mail nexus, distributed
   as an overlay from nisfeb/auspex").
3. `tools/vendor-auspex.sh`.
4. `tools/desk-reach.py`: add `gub/nex/auspex/` and `gub/nex/tiles.hoon` to
   `is_root`. Re-run `tools/trim-lattice-only.sh` — it must delete **nothing
   new** (auspex reaches only its own libs; if it proposes deleting anything,
   stop and read why).
5. Docket: `info+` mentions both apps; `version+[1 1 0]` stays (the launcher
   is the 1.1 change; auspex's arrival is 1.2 → bump to `[1 2 0]` at the
   release commit so kiln users see a version they can name).
6. Commit as one change: "dist: the launcher, and auspex beside lattice"
   with the auspex commit hash in the body. Push to `fork`.

Repeatable afterwards: an auspex change = `tools/vendor-auspex.sh`, commit,
deploy (§5.4). A lattice change = the existing lattice step. An upstream
merge = merge `origin/develop`, re-run the trim, re-vendor both, re-check
the roots.

## 5. The runbook

Each step ends with a check. A failed check means stop, not improvise.

### 5.0 The minimum-surface variant — prefer this

If this runbook runs at all, run it without the throwaway parts:

- **Skip** the `tiles.hoon` restoration, its `root.hoon` row, and the
  docket rewrite. `dist/launcher-restore` stays unmerged.
- **Vendor only auspex's own sources** and its one `root.hoon` row.
- Lattice's tile, URL and docket do not change; existing users see
  nothing move. Auspex is reachable at `/apps/auspex`.
- Everything else below applies unchanged, minus the launcher checks.

What this costs: no launcher, so two URLs to remember. What it buys: the
fork gains only the files that later become the published code dir, so
the migration is the directory re-map `sync-overlay.sh` already does.

The one cost it does NOT avoid: kiln syncs the whole desk, so every
lattice user receives auspex's ~40 files and their ball compiles a mail
nexus they did not install. That is the strongest argument for waiting
for the code-nexus path, and it is why §0 calls this the fallback.

### 5.1 Rehearse on `~wex` (production-shaped root.hoon)

```
# on foundation
cd ~/software/groundwire/grubbery && git checkout dist/lattice-only
rsync -a --exclude .git desk/ ~/software/wex/grubbery/          # never --delete
# files the branch dropped since wex last synced: remove by hand from the mount
#   (diff -rq desk/ ~/software/wex/grubbery | grep 'Only in /home' — expect wex's own leftover app-tier sources; leave those)
```
In `~wex`'s dojo (tmux `0:0.0`), one command, verify the echo:
```
=dir /=base=                       :: never leave =dir pinned (it steers |commit, |mount, +gen)
|commit %grubbery                  :: read "build-code: done"; a "dep failed" line stops here
|suspend %grubbery
|revive %grubbery                  :: 000 → 503 → 403 takes 20–200s; wait on the condition
```
Checks (all must pass):
- `curl -s -o /dev/null -w '%{http_code}' localhost:8081/apps/grubbery` → 403 anon; logged in: the launcher HTML.
- Logged in, `/grubbery/tiles` lists **Lattice** and **Auspex**, icons served (`/grubbery/tiles/icon/auspex` and lattice's).
- `/apps/lattice` and `/apps/auspex` → 403 anon, 200 logged in.
- Tests at the explicit rev: `-test /~wex/grubbery/<rev>/tests/lib/auspex-chain ~` (87), `…/auspex-web ~` (48), `…/auspex-vectors ~` (15), lattice's suites as their README lists.
- Cross-ship: send `~wex → ~feb` with an attachment; on `~feb` it is `verified`, the blob fetches; reply back `verified`. Discovery trace: `discovery: ~feb speaks 1`.
- Lattice smoke: a page renders, the MCP tool count is 12 (`check_bin` or the MCP list).
- Note the ghost-tile count (wex showed 12 tiles, 4 live). This is the number
  §5.5 has to clear on ricsul if the decision is "clear".

### 5.2 Rehearse on `~feb` (full upstream shape)

Same steps against `~/software/feb/grubbery` and pane `0:3.0`, port 8080.
Passing here proves the change is safe *with* the app tier present, which
production does not have; failing here is still a stop.

### 5.3 Production: stage on `~ricsul-bilwyt`

Every command below is typed by a human. Read the ship's console (asimov,
tmux `0:2`) after each.

1. **Backup the mount.** On asimov:
   `tar czf ~/ricsul-grubbery-mount-backup-$(date +%Y%m%d-%H%M%S).tgz -C /home/sneagan/ricsul-bilwyt/_data/ricsul-bilwyt grubbery`
   Record the filename in this document's log (§7).
2. **Decide the trim.** Either paste the three pending `%info` lines now (one
   at a time, wait for the `- /~ricsul-bilwyt/grubbery/<rev>/…` prints on
   each) and confirm `~martyr-sanryg` rebuilt clean, **or** leave the trim
   for a later release. Do not do it in the same commit as the launcher: a
   trim line that clay refuses would mask a launcher problem.
3. **Stage the files** from foundation, one rsync per mapping, no `--delete`
   (the SSH multiplexing in lattice's `deploy-ricsul.sh` is the pattern —
   copy its `SSH=` line):
   ```
   RDESK=/home/sneagan/ricsul-bilwyt/_data/ricsul-bilwyt/grubbery
   rsync -a -e "$SSH" desk/gub/nex/tiles.hoon      sneagan@45.33.75.69:$RDESK/gub/nex/tiles.hoon
   rsync -a -e "$SSH" desk/gub/nex/auspex/         sneagan@45.33.75.69:$RDESK/gub/nex/auspex/
   rsync -a -e "$SSH" desk/gub/lib/auspex-*.hoon   sneagan@45.33.75.69:$RDESK/gub/lib/
   rsync -a -e "$SSH" desk/lib/auspex-*.hoon       sneagan@45.33.75.69:$RDESK/lib/
   rsync -a -e "$SSH" desk/gub/mar/auspex/         sneagan@45.33.75.69:$RDESK/gub/mar/auspex/
   rsync -a -e "$SSH" desk/gub/mar/auspex-*.hoon   sneagan@45.33.75.69:$RDESK/gub/mar/
   rsync -a -e "$SSH" desk/tests/lib/auspex-*.hoon sneagan@45.33.75.69:$RDESK/tests/lib/
   rsync -a -e "$SSH" desk/gen/auspex-vectors.hoon sneagan@45.33.75.69:$RDESK/gen/
   rsync -a -e "$SSH" desk/protocol/               sneagan@45.33.75.69:$RDESK/protocol/
   rsync -a -e "$SSH" desk/lib/root.hoon           sneagan@45.33.75.69:$RDESK/lib/root.hoon
   rsync -a -e "$SSH" desk/desk.docket-0           sneagan@45.33.75.69:$RDESK/desk.docket-0
   ```
   Staging is inert: grubbery loads nothing until the commit.
4. **Verify the staging** before committing: `ssh … "cd $RDESK && sha256sum lib/root.hoon desk.docket-0 gub/nex/tiles.hoon gub/nex/auspex/app.hoon"` and compare with the branch. `diff -rq` the whole tree against `desk/` and read every line — "Only in ricsul" must be exactly the known untracked `catalog*.hoon` files and the trim's not-yet-deleted files.

### 5.4 Production: commit and bounce

In ricsul's dojo, one line at a time:
```
=dir /=base=
|commit %grubbery
```
Watch for `build-code: done` and `reload-changed-nexuses` naming `/lattice/app`, `/auspex/app`, `/tiles`. A `dep failed` or `mint-vain` stops the release: the desk is rejected by clay and nothing changed on installers — go back to §5.1 with the failure text. The ship answers 503 / "%grubbery not running" for a minute while the agent rebuilds; every MCP call times out during it.

Then the bounce (a desk update does not respawn long-lived fibers — the
launcher's and auspex's would otherwise run old code):
```
|suspend %grubbery
|revive %grubbery
```
Wait on the condition, not a clock: `curl -s -o /dev/null -w '%{http_code}' https://urbit.sneagan.com/apps/auspex` until 403.

Checks, in this order (the memory store first, because everything else in
this workflow depends on it):
1. `lattice-list` through the ricsul MCP answers. If it does not within
   five minutes of 403 appearing, the session cookie may have expired on the
   bounce — that is a cookie refresh, not a rollback.
2. `/apps/grubbery` logged in shows the launcher with Lattice and Auspex.
3. `/apps/lattice` renders a page; `check_bin path=/nex/lattice name=app` OK; `check_bin path=/nex/auspex name=app` OK.
4. `/apps/auspex` logged in shows an empty inbox; `GET /apps/auspex/api/whoami` → `~ricsul-bilwyt`.
5. Send a message from ricsul to `~martyr-sanryg` **after** step 6, not before.
6. `~martyr-sanryg`: within minutes its clay rev matches ricsul's; its console shows the same `build-code: done`; its Landscape tile reads Grubbery; `/apps/auspex` answers. Then step 5's message arrives there `verified` — the first real-planet `%puby` verification of the nexus's own `+peer-pass` branch (the crypto beneath it was proven on 2026-09-08; the branch itself has never executed on a real ship).
7. Discovery: ricsul's `/proto` readable from martyr over keen (`discovery: ~ricsul-bilwyt speaks 1` in martyr's trace on its first send).

### 5.5 Ghost tiles (decision point, production ball write)

The launcher lists every `/apps/*` instance carrying a `tile.json`. Ricsul's
ball holds BANGed app-tier instances from before the strip (forge, pad,
guestbook, …). On `~wex` that produced 12 tiles for 4 apps, three of which
hang when clicked.

Options, in order of preference:
1. **Clear them first** (one poke per instance, the shape the discovery
   work used on `~feb`):
   `:grubbery &grub-cmd [%clean2 [%cull /apps/'pad.pad_app' ~]]` — enumerate
   the instances from the launcher's own list on ricsul *before* the release
   (read `/grubbery/tiles` logged in at §5.3), rehearse the exact list on
   `~wex` first, and confirm each cull removes the tile and nothing else. This
   is destructive to those instances' data; forge's git repos are the ones to
   think about — export anything wanted before culling.
2. **Ship with dead tiles** and clear them in a follow-up. Ugly for a day;
   zero risk to the release itself.

Whichever is chosen is written into §7 before §5.4 runs.

### 5.6 After

- Tag the dist branch: `git tag dist-v1.2.0 && git push fork dist-v1.2.0`.
  Optional rename `dist/lattice-only → dist/main` now that the name is
  false; if renamed, update lattice's `deploy-ricsul.sh` comment and the
  lattice memory `[[/project/lattice/dist-branch]]`.
- Auspex repo: `docs/release-plan.md` Gate 5 → done, the ricsul revision and
  date in `docs/verification.md`.
- Publish the auspex desktop `v0.1.0` draft; the Thunderbird zip is already
  distributed by hand.
- Announce: install command unchanged; existing users see a Grubbery tile
  and a launcher on their next visit; lattice's URL unchanged.

## 6. Rollback

The whole production change is five things: `tiles.hoon`, the root rows,
the docket, and auspex's `gub/` + `lib/` trees. `git revert` the release
commit on the dist branch, then:

- **Edits and adds** roll back by rsyncing the reverted files and committing.
- **Deletions** (removing auspex's and tiles' sources) need `%info` lines —
  or simply leave the sources in place and revert only `root.hoon` and the
  docket: with no row, the auspex instance keeps its data BANGed-but-present
  and the launcher stops binding `/apps/grubbery`. That is the fast rollback
  and it loses nothing.
- Mail already delivered stays readable in either case: nothing here touches
  the chain format or stored grubs.
- Bounce after the rollback commit, same as §5.4.

## 7. Log

| when | step | who | result / backup filename |
|---|---|---|---|
| | | | |

## 8. What this does not solve

Kiln syncs the *desk*, so a user who later points their `%grubbery` at an
official gwbtc release loses both apps' sources (instances and data persist in
the ball, BANGed until code returns). The parked plan for that was code in the
ball's app-local namespace, waiting on upstream's `tools-nexus-refactor`.

**That wait is over** — `develop` now has the `desk` nexus that mirrors a
code directory and the shell that manages the permissions around it. See
§0 and `docs/distribution-proposal.md`. The desk route below is the route
that exists on the revision `~ricsul-bilwyt` runs *today*, and nothing
more than that.


---

## 9. The next release, as planned — 2026-09-10

The shape agreed after reading `develop`. Each step is invisible to a
user and shippable alone; that is the requirement, not a nicety. An
architecture migration bundled with features is one you cannot roll back
and cannot blame.

### 9.1 The sequence, and what gates what

1. **Grubbery catches up to `develop`.** Everything below needs a shell,
   and the shell is `develop`-only — so this comes first, and *today it
   comes from us*, because we are still the distributor. This is the
   genuinely risky step in the whole plan: a kernel merge into a desk
   that a real planet tracks unattended. It ships alone.
2. **Restructure**: `alias.json`, `weir.json` (both written, inert), and
   the code namespace.
3. **Peer**: `~ricsul-bilwyt` added as a software peer for everyone who
   got grubbery from us.
4. **Lattice migrates in place**, its code coming from the peer rather
   than from our desk.
5. **Auspex becomes discoverable** — one click in their storefront.

### 9.2 Three decisions, with their reasons

**Auto-peering is a one-time migration step, not app code.** If lattice
pokes the shell's `peers.json` itself, lattice needs a standing road to
`/apps/shell.shell` — a road that means *may rewrite your software
sources*, held for ever, for something that happens once. That is exactly
the coarse grant §4.5 of the proposal objects to, and we should not be
the first to take it. The poke belongs in the upgrade we ship: runs once,
auditable, no permanent capability. Better still is the upstream rule
(proposal §4.6), which makes it nobody's code.

The guard is **"they got grubbery from ricsul"**, not "this ship is not
ricsul". Someone who took grubbery from the moon and lattice by another
route should not have us inserted into their sources.

**Lattice migrates in place; the guest world would strand its data.**
`bill.json` creates instances at `/desk/data/<name>`. Point that at
lattice and the user gets a second, empty lattice while every page they
wrote stays in the old instance. The URL survives either way (both apps
bind their route by name from `ui/main.sig`), so the data is the whole
risk. In-place code-namespace governance keeps instance, data and URL
exactly where they are — but has no update path today, which is the open
question for the meeting.

**Auspex is discoverable, not installed.** Installing it for everyone
means a new tile, new state and a mail nexus compiling in the ball of
people who asked for a notes app. That is a perceivable change, it is
what the permission model exists to prevent, and it is the same objection
that made us stop shipping auspex through the shared desk. Once ricsul is
a peer it is one click away, and that is enough.

### 9.3 The develop merge, measured

Assessed 2026-09-10 in a worktree on branch `dist/develop-merge`. The
numbers below are the assessment; **the merge has since been done and
rehearsed end to end on `~wex`** — see §9.4 for where it stands and §10
for what it taught.

- Our stack is **26 commits** on `7117ae1`; upstream is **36 ahead**.
- 49 files collide. **44 of them we deleted** (the app-tier strip and the
  ball trim) and upstream merely changed — they resolve as "stay
  deleted".
- **The kernel merged clean.** `desk/app/grubbery.hoon` and
  `desk/gub/mar/poke-ack.hoon` are not in the conflict list at all, so
  the `%3 → %1` state downgrade and our poke-ack fix (filed as
  gwbtc/grubbery#56) did not collide — most likely because the fix went
  upstream.
- Genuine conflicts: `desk/lib/root.hoon` (our stripped rows vs theirs)
  and `desk/gub/mar/clay/base/kiln/install.hoon` (both added).

**The trim deleted the two things we now want back.** `gub/nex/shell.hoon`
and `gub/nex/desk.hoon` are in the deleted-by-us list, and they are the
entire mechanism this migration runs on. So the resolution is not
uniform, but it is small — **8 files come back, 36 stay deleted**:

- Restore from `develop`: `gub/nex/shell.hoon` with `shell/app.js`,
  `shell/docs.html`, `shell/docs.js`; `gub/nex/desk.hoon` with
  `desk/ui/{app.js,index.html,style.css}`.
- `git rm` every other deleted-by-us conflict.
- Resolve `root.hoon` by hand: our stripped rows plus rows for shell and
  desk.
- `tools/desk-reach.py` already has the new roots (commit `5d880ed` on
  `dist/develop-merge`); run it, then `tools/trim-lattice-only.sh`.
- Re-vendor the lattice overlay, then build on `~wex` before anything
  else.

**Explorer comes back too — as a default, not an app-tier extra**
(2026-09-10). It is the only way to look at a grubbery ship's namespace
at all, and it is not merely nice to have: `shell.hoon` builds every
storefront app icon as
`/grubbery/ball{...}/desk/code/{icon}?raw=1` (+read-peer-desks, line
~1853), and **`/grubbery/ball` is bound by explorer and nothing else**.
Without it, every icon in "Get apps" is a dead link — on the very
surface step 5 of §9.1 depends on. It takes upstream's `root.hoon` row
unchanged and costs `gub/lib/feather.hoon` plus ~83 KB of its own assets;
the codemirror and `lib/ui` bundles it draws on were already carried.

**Nothing else in the app tier comes back**, on the standing assumption
that every other app is installed by adding a peer. Three that looked
like they might be needed, checked rather than assumed:

- **`tiles.hoon` is not needed.** `+read-all-tiles` welds
  `+read-local-tiles` with `+read-app-tiles`; an absent store peeks to a
  non-`%ball` view and returns `~`, and app tiles come from each app's own
  `tile.json`. The launcher grid works without a tiles store.
- **`notifications.hoon` is not needed.** `+register-notify` is
  `poke-soft` and says so: *"a failed registration is logged, not fatal —
  re-run on every rise."*
- **`peers.hoon` is not needed.** It is the usergroup and ship-management
  *UI*; the peering mechanism itself is the shell's `peers.json` poke and
  its `/peers` mirrors. One consequence lands on us rather than on users:
  publishing means putting a road into `public.grp`'s weir, and without
  that page we do it by poking. Worth asking whether the shell is meant
  to grow a publish surface, since a distributor with no UI for
  publishing is a rough edge for anyone but us.

The shell imports only its own assets and `/lib/feather-icons.hoon` — it
does **not** compile in other app-tier nexuses. It composes the tiles
store and the notifications bell over the namespace at runtime, so an
absent store means an empty grid, not a broken shell.

**And `dist/launcher-restore` should be abandoned, not merged.** It
restores pre-split `tiles.hoon` (upstream `d839ede`) as a self-contained
launcher. Post-split, tiles is a pure data store and the shell is the
view; taking `develop` gives us both, correctly. Merging the old fork
would carry a launcher we would then have to un-carry.


### 9.4 Where the five steps actually stand — 2026-09-10

Everything below was read off a ship or a branch on the date written.
Nothing has touched `~ricsul-bilwyt`.

| # | Step | State |
|---|------|-------|
| 1 | Grubbery catches up to `develop` | **done and rehearsed**, `nisfeb/grubbery` `dist/develop-merge` @ `ec8674a`. Merged, trimmed, deployed to `~wex`, ball rebuilt, 0 bangs. Not on ricsul. |
| 2 | Restructure — `alias.json`, `weir.json`, code namespace | **done**. Both apps declare both files and serve them live on `~wex`. Both `--code-dir` outputs build and resolve every source import (`scripts/codedir-check.py`, 0 unresolved each). |
| 3 | Peer `~ricsul-bilwyt` | **not started** — production, and it wants the upstream default-peer rule first (issue #6). |
| 4 | Lattice migrates in place | **blocked on the open question** (issue #5): a desk nexus cannot adopt an existing instance, so the guest route strands the data. |
| 5 | Auspex discoverable | **waits on 3**. |

Verified on `~wex` the same day: `/apps/auspex/`, `/apps/lattice/app`,
`/grubbery/mcp`, `/grubbery/ball`, `/apps/grubbery` and
`/grubbery/api/tree/apps` all 200; `/apps` holds exactly
`auspex.auspex_app`, `explorer.explorer`, `lattice.lattice_app`,
`mcp.mcp`, `shell.shell`; the launcher grid is Auspex / Explorer /
Lattice / Tools; the MCP registry lists 14 tools and the protocol
advertises 3; `-test /=grubbery=/tests/lib` is `ok=%.y`; 0 bangs.

The launcher logs **one** 404, and it is a decision rather than a fault:
the bell fetches `/apps/notifications.notifications/inbox.inbox`, and
§9.3 keeps `notifications.hoon` out. The bell is empty and nothing else
notices.

**Two gates, not one, now that there is a tool for the second.**
`tools/desk-reach.py` says what nothing reaches; `tools/imports-resolve.py`
says what is reached but missing. The second found 44 unresolved imports
on its first run, none of them explorer's: `desk/lib/mcp/` was the
pre-relocation tool path still importing the `/lib/nex/tools.hoon`
upstream dropped, and `desk/lib/tool-bundle/` was those tools mirrored to
the desk level where no test imports them. Both deleted; lattice's sync no
longer makes the second. Both gates are clean.

**Known leftovers, none blocking.** `gub/nex/` still carries five asset
directories with no compiling parent — `claw/`, `explorer/`, `git/`,
`github/`, `web-test/`, about 80 KB. They are inert (no `.hoon` reaches
them) and deleting them is a branch change nobody needs before a meeting.

## 10. What the rehearsal on `~wex` actually taught — 2026-09-10

The merge, the trim, the cull and the deploy were all run end to end on
`~wex`. It works — grubbery at `origin/develop`, shell and desk nexus
restored, 211 trimmed files gone from clay, sixteen app instances culled,
lattice and auspex serving, three tiles, zero bangs. Almost everything
below is a correction to what §9 said before it was tried.

### 10.1 The trim tool was lying, and the trim broke the shell

`tools/desk-reach.py` appended `.hoon` to **every** import before looking
it up, so `shell/home.html` was sought as `home.html.hoon`, not found,
and called unreachable. The trim then deleted seven files the shell
needs — `home.html`, `marked.min.js`, `hoon-grammar.json`,
`permits.html`, `style.css`, `/lib/feather-icons.hoon` and
`/lib/docs-tools/` — so `shell.hoon` did not compile and its HTTP
binding went with it. `/apps/grubbery` stopped answering and the console
filled with `BANG file /apps/shell.shell/...`.

The walker now tries an import path **as written** before assuming
`.hoon`, and follows directory imports (`/lib/docs-tools/`).

**But the fix is not to trust the fixed tool.** Gate a trim on an
independent check that opens every remaining `.hoon` in `gub/` and
resolves every `/<`, `/&`, `/=`, `/*` import against the tree. The bar is
**0 unreachable AND 0 unresolved imports**, computed two different ways.
A reachability tool that is wrong reports a clean run.

### 10.2 Reachability by import cannot see instances

`gub/nex/tools.hoon` is imported by nothing, and is needed by mcp's
`tools.tools` **child instance**. The trim removed it and the console
said `build-nexus: no built nexus %tools at /nex (from /apps/mcp.mcp/tools.tools)`.

Rule: **a nexus named by any instance — a `root.hoon` row or a child
instance inside another app — is a root**, whatever imports it. The same
was true of `gub/nex/port.hoon` before upstream deleted it.

### 10.3 Deletions from a mount DO reach clay

Earlier notes say they do not. They do — through the live mount sync,
not through `|commit`, and clay prints one `- /~ship/desk/<rev>/<path>`
line each.

This bit hard: `rsync -a --delete <branch>/desk/ <wex mount>/` removed
**auspex** from clay, because auspex is an overlay the lattice branch
knows nothing about. Auspex went dark and it took a while to see why.

- Never `--delete` onto a mount that carries overlays the source tree
  does not contain. Sync each overlay in afterwards, and commit.
- Do not verify a deletion with `.^` under a pinned `=dir` — the case
  resolves to that revision and a deleted file still reads `%.y`. Read
  the `- /` lines the commit prints instead.

### 10.4 Bulk deletion by `%info` works, in this shape

211 files went in **8 lines of 30 entries**, all accepted:

```
|pass [%c %info %grubbery %.y ~[[/gub/lib/btc-rpc/hoon [%del ~]] ...]]
```

Mount path `a/b/c.ext` becomes clay path `/a/b/c/ext`. Build the list as
*(what clay holds) minus (the branch) minus (every overlay)*, then assert
the intersection with the current mount is **empty** before sending
anything. A line is atomic: one bad path fails all thirty.

### 10.5 Culling instances: shape, silence, and children

The working command is:

```
:grubbery &grub-cmd [%clean2 [%cull /apps/'<name>' ~]]
```

Two things that cost time:

- **The wrong shape is accepted.** `[%cull /apps [~ %'weather.weather']]`
  echoes `>=` and does nothing. A no-op is indistinguishable from
  success, so verify against `/grubbery/api/tree/apps` after each.
- **Culling a parent leaves nested children alive, and they regenerate
  the parent.** `forge.git_forge` came back until its
  `repos/contacts.git_repo` child was culled first. **Children first.**

### 10.6 The tiles store is not needed — now tested, not reasoned

With `tiles.tiles` culled, the shell serves a grid of exactly
**Auspex, Lattice, Tools**, each rendered from the app's own `tile.json`
through `+read-app-tiles`. §9's conclusion stands.

The one cost: the tiles store held exactly one local tile —
**Landscape** — so dropping it removes the link back to Urbit's own UI.
That is a product decision for production, not a technical one.

Ghost tiles are real and now visible: before the cull, `~wex` showed
**13** tiles for 4 live apps, including a stale `Mail -> /apps/urmail`
from the auspex rename. Ricsul's ball has the same shape, so the cull is
required there before the shell arrives — and it is a ball write, so it
needs its own go.

### 10.7 Sequence that worked, in order

1. Merge `origin/develop`; restore shell + desk from upstream; resolve
   `root.hoon` and `kiln/install.hoon`.
2. Relocate lattice's MCP tools to `gub/lib/tool-bundle/tools/` and
   repoint their import to `/lib/tools.hoon` (upstream dropped
   `/lib/nex/`). Without this the memory tools do not build.
3. Fix the reachability walker; re-vendor every overlay; trim; **verify
   both ways**.
4. Deploy additively, `|commit`, read the build line.
5. Cull instances — children before parents — verifying the tree each
   time.
6. Delete the trimmed files with `%info` lines, thirty at a time.
7. Re-sync every overlay and commit again, because step 4's `--delete`
   or step 6's list may have taken one out.
8. Bounce, then check endpoints, the grid, and that the console carries
   no `BANG` or `missing import`.

### 10.8 The tool bundle is a hermetic namespace — and the MCP surface is three tools

Two separate reasons the mcp app listed **zero** tools after the trim.

**`gub/lib/tool-bundle/` is never compiled in the desk's namespace.**
`mcp.hoon` takes it as a directory import and seeds it into its
`tools.tools` child as that instance's own `/code/lib`, and
`+find-code-ns` is explicit: *"Governance is hermetic — Lower namespaces
must include marks/libs they need."* So a tool's
`/<  tools  /lib/tools.hoon` means `tool-bundle/tools.hoon`, **not**
`gub/lib/tools.hoon`. Three files were missing from the bundle
(`tools.hoon` plus the two lattice libs its tools import), so all eleven
failed to compile — and `+scan-own` skips a tool that will not compile
without a word. A hermetic sub-namespace needs its **whole** dep closure
copied in beside it; the reachability walker resolved those imports
against `gub/lib`, found the outer copies, and pruned the inner ones.

**`tools/list` does not advertise the registry.** `mcp-rpc`'s
`+handle-request` skims it down to `list_tools`, `call_tool` and `echo`,
and a client reaches everything else through `call_tool`. All three are
upstream tools, so a trim that keeps only our own leaves an MCP client
looking at a server with no tools however full the registry is. Keep
those three.

Verified on `~wex`: registry 14 tools, protocol advertises 3, and
`call_tool → lattice-list` returns the vault. Both surfaces are worth
checking after a trim, because they fail independently:

```
GET  /grubbery/mcp/api/tools           the full registry
POST /grubbery/mcp {"method":"tools/list"}   what a client sees
```

---

## 11. Publishing an app as a stock desk — the sequence that worked

Written 2026-09-11, after auspex went out this way and lattice followed.
Every step below was run against `~wex`. This section exists because the
auspex install lived only in a chat transcript, which is not somewhere a
runbook step should live.

### 11.1 What the shape is

An app is a **code directory** in its own repo — `lib/`, `mar/`, `nex/`
and four manifests, nothing else:

```
code/
  bill.json      {"<name>.<nexus>": "/<dir>/<nexus>"}   instances to create
  version.json   {"version": N}                         the opaque upgrade tag
  tile.json                                             launcher tile
  icon.svg
  lib/ mar/ nex/
```

Grubbery mirrors that directory into
`/apps/shell.shell/desks/<name>.desk/desk/code`, and `bill.json` creates
each instance in the **sibling** `/desk/data`. Everything outside `code/`
in the repo — tests, build sources, CI, the desk-level `mar/` a dojo poke
resolves — stays behind, because a guest install has no desk for it.

### 11.2 The five calls

```sh
#  1. the forge checks out the repo into the namespace
POST /grubbery/forge/api/add
     {"name":"<n>","repo":"nisfeb/<n>","ref":"master"}

#  2. create the desk instance
POST /grubbery/mcp
     {"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"call_tool",
      "arguments":{"tool_name":"create_desk","tool_args":{
        "name":"<n>",
        "source":"/apps/forge.git_forge/repos/<n>.git_repo/data/tree/code"}}}}

#  3. write source.json BY HAND, because create_desk gets it wrong twice
POST /grubbery/api/poke/apps/shell.shell/desks/<n>.desk/source.json?blot=/json
     {"code":"/apps/forge.git_forge/repos/<n>.git_repo/data/tree/code"}

#  4. consent, in the shell UI — /apps/shell

#  5. thereafter, to ship a change: bump code/version.json, push, then
POST /grubbery/forge/api/run   {"repo":"<n>.git_repo","command":"pull"}
```

**Step 3 is not optional.** `create-desk.hoon` pokes `config.json` where
`desk.hoon` declares `source.json`, and writes the key `source` where the
reader wants `code`. Two one-word upstream bugs; fix them there and step 3
disappears.

### 11.3 Replacing an app that used to live at the app tier

Auspex was new, so it just installed. Lattice was already running as
`/apps/lattice.lattice_app` from grubbery's own `gub/nex/lattice/`, and
**both bind `/apps/lattice`** — `code/nex/lattice/app.hoon:275`. Two
instances cannot share an eyre binding, so the old one goes first:

**A migration deletes nothing.** An earlier draft of this section culled
the old instance here, which is wrong: culling is how you free the eyre
binding only if you have forgotten that removing the CODE frees it too. An
instance with no code cannot run, so it cannot bind eyre, and its data sits
where it is - readable as raw nouns (§11.6), which is exactly the source
the copy reads from. Leave it.

1. Remove its `%fall` row from `lib/root.hoon` and `|commit %grubbery`.
   A row does not delete an instance, but leaving it in recreates one.
2. Delete `gub/nex/<n>/` and `gub/lib/<n>-*.hoon`, and commit again.
   Deletions from a mount do reach clay (§10.3). The old instance is now
   **dormant**: no code, no fibers, no eyre binding, data intact.
3. Then the five calls in 11.2. The desk instance takes `/apps/<n>` with
   no contention, because nothing else is holding it.
4. Copy the data (§11.6), and verify it.
5. **Later, once the user is satisfied**, cull the dormant instance to
   reclaim the space. This is a separate, reversible-until-done decision
   and it is not part of getting the data moved.

Order matters in one direction only, and it is the opposite of what it
looks like: the code goes BEFORE the copy, not after. Removing the code is
what makes the old instance safe to read from - dormant, with nothing
writing to it while the copy walks it.

`~wex` was culled during the rehearsal, before this was understood. Its
lattice data was UI-matrix fixtures, so nothing was lost, but the sequence
above is the one to use and the cull is not in it.

### 11.4 The MCP tools know where lattice lives, and it moved

`gub/lib/tool-bundle/lattice-mcp.hoon` has exactly one constant:

```hoon
++  base  `path`/apps/'shell.shell'/desks/'lattice.desk'/desk/data/'lattice.lattice_app'
```

Every memory tool — `lattice-list`, `lattice-read`, `lattice-save` and the
rest — reaches the store through it. A desk install moves the instance, so
this line moves with it, and **on `~ricsul-bilwyt` this line is what
decides whether the memory store still answers**.

No weir grant is needed: mcp's own weir is `/`, because it runs arbitrary
user tools. That is also why an absolute road is right here and nowhere
else in app code — mcp is reaching into somebody else's install rather
than addressing itself.

The tool bundle is hermetic (§10.8), so it carries its own copies of
`lattice-know.hoon` and `lattice-mcp.hoon`. Deleting the outer
`gub/lib/lattice-*.hoon` does not touch the tools. Verified: nothing
outside `gub/nex/lattice/` and the bundle imports them.

### 11.5 The data migration is still open

`apply-bill` creates an instance in `/desk/data` with no adoption path for
data that already exists elsewhere — grubbery issue #5. That is why the
copy in §11.6 exists. It is NOT a reason to delete the source: the old
instance goes dormant and keeps its data, so a migration that copies wrong
can be re-run against an unchanged original.

The table below is what the rehearsal destroyed and what a real ship must
not:

| ship | lattice data | safe to cull |
|---|---|---|
| `~wex` | 16 pages, all `bis-*`/`uimx-*`/`scrolltest` fixtures from the UI matrix scripts | yes |
| `~ricsul-bilwyt` | the real memory store | **no — not until there is an adoption path** |

### 11.6 The automatic migration, and why it needs no granted road

Read on 2026-09-11. The grant-then-revoke plan is not needed: every piece
of this already exists, and the kernel carries a precedent for the exact
shape.

**The precedent.** `app/grubbery.hoon:576`, `+carry-behn-state`, is a
one-time rename of a service grub. Its doc comment is the specification we
want, already satisfied: *"Reads the RAW noun via +sang-noun — no mark, no
validation — so it works from any past version, even though the old mark
file is gone and the old grub's view booms... Union-merges into the new
grub, then culls the old. Idempotent and inert once no pier holds the old
grub; cheap to keep forever."*

**We take everything from that except the cull.** `+carry-behn-state` culls
because a service grub is grubbery's own and it knows the merge was
complete. A user's pages are not ours to delete on their behalf, and the
whole value of leaving them is that a bad copy is re-runnable against an
unchanged original. So: copy, leave the source dormant, and let the user
decide when it goes (§11.3).

**The data survives losing its code.** `app/grubbery.hoon:4422`: a
validation failure never drops the write — `+record` stores the raw noun
and the boom surfaces lazily on read. Confirmed empirically: removing
lattice's `%fall` row and committing left `/apps/lattice.lattice_app`
standing on `~wex`; it took an explicit cull to remove it. So an
installer who upgrades keeps their data, sitting as raw nouns.

**Booms convert cleanly.** `lib/tarball.hoon:567`, `+ball-to-bole`, runs
`+sang-noun` over every entry unconditionally, and `+sang-noun` handles
both branches — `%&` valid and `%|` boom. A boom becomes an ordinary
bask, losing only the error tang. Over-folded or made into a destination
where the marc DOES compile, it re-validates on write and stops being a
boom. This works because **the marcs travel with the code directory**:
the destination can validate what the source no longer can.

**No road is needed.** `sur/grub.hoon` offers `[%peek path name deep=?]`
and `[%make-file path name mark noun force=?]`, and says plainly that
*"content validation is the reader's job (mark labels are advisory
here)"* and *"local privilege is just the absence of a weir on your own
path."* A host-layer arm in the agent runs as the ship, with root. So the
migration is a `+carry-lattice-data` arm beside `+carry-behn-state` — not
a fiber in lattice's code, and not a temporary grant in its `weir.json`.

**What it copies.** Derived from lattice's own on-load block
(`code/nex/lattice/app.hoon:110-215`), which classifies exhaustively:

| | |
|---|---|
| directories | `/legacy` `/know/vault` `/know/trash-vault` `/pub/vault` `/sub/pages` `/page` `/template` `/comments` `/idx/b` |
| single grubs | `/know/trash` `/pub/index` `/pub/meta` `/sub/follows` `/bookmarks` `/history` `/beacon/rev` `/mirror/cursor` `/mirror/config.json` `/shared` |
| **never** | the five `sig` fibers (`main` `ui/main` `shares` `comments` `fs` `mirror/mirror`) — processes, and the new instance has its own running; the `%over` UI assets under `/app`, which the new code lays down and whose old copies are stale; `/ui/requests`, transient; `alias.json` `link.json` `manifest.json` `icon.svg` `prism.js`, all declared by the new code |

Not copying the sig fibers is what makes this safe: nothing live is
overwritten, so there is no respawn question to answer.

That table is an invariant worth checking rather than trusting — any row
in on-load that appears in none of the three lists is a migration bug.

**Two releases, not one.** One would work, since booms are recoverable,
but two means the copy moves validated grubs with marcs live on both
sides, and release N stays a working rollback:

| release | grubbery ships | effect |
|---|---|---|
| N | lattice's code and its `%fall` row, plus a `lattice.desk` row sourced from ricsul, plus `+carry-lattice-data` | desk installs, migration runs, both tiers valid |
| N+1 | lattice out of the ball, row gone; the arm stays (inert, cheap) | old instance culled, one lattice left |

This is cheap because the code is already tier-agnostic: `+nexus-up`
reads `get-here`'s root flag, so one lattice runs at
`/apps/lattice.lattice_app` and at the desk path both. That was built for
this window.

### 11.7 The publish path that wedged — fixed in the fork

Found on `~wex` on 2026-09-11 while verifying the desk install, and it had
nothing to do with the migration: any lattice, any tier, could hit it.

**The symptom.** One `/pub/index` publish answers 500, and then every
publish answers 500 forever. `POST /pub-regrow`, the intended repair, 500s
on the same path. Reproducible in four calls: save a page, publish it, move
it, and the move 500s. Moving an *unpublished* page was fine, which is what
made it look like a data-state problem rather than a kernel one.

**The cause,** `app/grubbery.hoon` `+farm-top`. It resolved a spur's top
case by asking `%gt` whether the spur was listed and then `%gw` for the
case — and its own comment already said that pair cannot be made safe:

> *gall keeps an emptied plot after a full cull, so %gt still lists a spur
> %gw would crash on — callers gate re-culls on their own records.*

A failing `.^` cannot be softened from inside the event (`+mute` hands the
scry back out to the real namespace, so the crash lands outside the
simulation). So one re-cull of an already-culled spur crashed the event,
inside the agent, with a stack trace containing no app code at all.

**The fix** is that "callers gate re-culls on their own records" is the
wrong division of labour. Every `%grow` and `%cull` in the system is emitted
by the two handlers beside `+farm-top`, so grubbery can keep the record
itself: `scry-state` gains `farm=(map path @ud)`, spur to top case, and
`+farm-top` is a lookup. Both `.^` reads are gone.

Lattice was the caller doing what the old comment asked — a `/pub/meta`
counter mirroring the farm — and that is exactly the design that fails:
two records of one truth, no way to compare them, and no recovery when they
diverge. One app-level counter fixed in the fork removes the class for every
app.

`scry-state` gains a `%1`; `+get-scry-state` upgrades `%0` in place, keeping
keens and starting the ledger empty. A spur grown before the ledger exists
reads as unbound, so culling it leaks a plot instead of crashing. Leak over
crash.

**Measured:** lattice's `api-matrix` against the desk install went
**114/126 → 123/126**, and the two remaining failures are a stale assertion
(`+mode-arg` deliberately 400s an unknown `?mode=`; the test still pins the
older fold-to-private-with-200 behaviour).

Fork commit `c6d30b1` on `dist/develop-merge`. Worth upstreaming: nothing in
it is lattice-specific, and the caveat it removes is upstream's own.

**If you meet a pier that is already wedged** (a counter/farm disagreement
from before this fix), reset the counter to **0** — the one value
`+grow-pub-index` guards, so publishing restarts cleanly and climbs again
from 1:

```
:grubbery &grub-cmd
  [%fix [%make-file /apps/…/lattice.lattice_app/pub %meta %ud 0 %.y]]
```

`%make-file` with `force=%.y`, not `%poke`: `/pub/meta` is a plain data grub
with no process, so a poke to it is silently nothing.


---

## 12. The migration, built and measured — 2026-09-11

§11.6 designed a migration and §11.3 said what order to run it in. This is
what happened when it was built and run, and three things the design got
wrong.

### 12.1 It belongs in `desk.hoon`, not in the agent

§11.6 proposed a `+carry-lattice-data` arm in `app/grubbery.hoon`, beside
`+carry-behn-state`. That was the wrong home. The agent's write primitives
are low-level — `+record` will not even create a grub, only revise one —
while `desk.hoon` is a **host-layer nexus**, so it has no weir, it can read
any path, and it already contains `+sync-dir`: peek a subtree, convert with
`+ball-to-bole`, `+over-fold` it into place preserving the destination's
neck. The copy is that, once.

Putting it there also makes it **generic**, which makes it grubbery issue
#5 rather than a lattice patch:

```json
"adopt": {
  "lattice.lattice_app": {
    "from": "/apps/lattice.lattice_app",
    "omit": ["/ui"]
  }
}
```

The desk knows how to copy a subtree; the app's own `bill.json` says what.
Additive — a bill with no `adopt` behaves exactly as before.

### 12.2 Fold only what the destination LACKS

This took two wrong versions.

The instance's `on-load` runs when `apply-bill` makes it, so by the time
`adopt` folds, everything the app declares about itself is already there:
its `.sig` processes, its `%over` assets (`weir.json`, `alias.json`, the UI
bundle, the tile), its declared empty dirs. **Whatever is absent is the old
instance's data, and only that.**

Folding everything and trusting `%over` rows to restore themselves on the
next load leaves the new instance running the **old** app's UI bundle and
the **old** app's `weir.json` until something reloads it — a window in
which the shell reads a road set the code never asked for. Filtering only
`.sig` grubs, as the first version did, is not enough.

The rule also makes the operation idempotent for free: run it twice and the
second run folds nothing.

### 12.3 An undeclared directory cannot be adopted

First run: **50 of 51** grubs. The miss was
`/mirror/tr/reconciler-started`.

`/page` and `/know/vault` are declared `%fall %| … empty-dir:loader`, and
their descendants came across four levels deep. `/mirror/tr` is created at
runtime by `+ensure-dirs` and declared nowhere, so the fold had nothing to
land in. Declaring it fixed the migration — and is more honest about the
layout regardless, since the directory is real and merely relied on being
made lazily.

**Generalise this before migrating any app:** every directory the source
holds must be declared in the destination's `on-load`, or descend from one
that is. A dir that only ever existed because something made it at runtime
will be silently dropped.

### 12.4 What it copies, measured

An old-tier lattice was rebuilt on `~wex` with real data and adopted into a
fresh desk install. **51 of 51 data grubs, identical paths and marks**, and
the destination kept its own `weir.json` (8 pokes, 2 peeks — the new road
set, not the old six-poke one).

| | |
|---|---|
| pages | `code`, `data`, `deps`, `err`, `cmd`, `show`, `wake` per page, nested four deep |
| knowledge | `/know/vault/<key>/entry` and the trash index |
| published | `/pub/vault`, `/pub/index`, and `/pub/meta` |
| the rest | `/comments` `/sub/pages` `/sub/follows` `/template` `/idx/b` `/legacy` `bookmarks` `history` `shared` `/mirror/cursor` `/beacon/rev` |
| never | the six `.sig` fibers; the six `%over` assets; `/ui` |

`/pub/meta` is the publish counter, and the farm spurs it points at
(`/pub/index/<n>`) are **ship-level, not instance-level** — both instances
address the same farm. So copying it is correct, and it is another reason
the old instance must be dormant rather than merely re-routed: two live
instances would fight over one farm.

### 12.5 Consent does not survive the move

`apply-bill` creates a **fresh** instance, and a fresh instance has no
recorded consent. So the migrated app is jailed until the user approves its
roads again, and the approval prompt is part of the upgrade whether we like
it or not.

The data is intact regardless — consent gates an app's outward reaches, not
its own tree — but the release notes have to say that the user will be
asked, or the first thing they will see is an app that serves nothing.


### 12.6 The shell provisions it — §11.2's manual sequence is for one-offs

§11.2 lists five calls, of which step 3 (hand-writing `source.json`) is
marked "not optional" because `create-desk.hoon` pokes `config.json` and
writes the key `source`. **That applies only to a desk installed by hand.**

A desk in the shell's stock list never goes near `create_desk`. Measured on
`~wex` with `lattice.desk` culled entirely — no desk, `/apps/lattice`
unbound, which is the state an upgrading ship is in — one call:

```
POST /apps/grubbery/desks/sync  {"name":"lattice"}
```

and 210 seconds later:

```
source.json  {"code":"/apps/forge.git_forge/repos/lattice.git_repo/data/tree/code"}
version.json {"version": 15}
instance     62 grubs
```

The shell provisioned the git_repo, pointed the desk at the checkout, wrote
`source.json` **itself and correctly**, `apply-bill` created the instance,
and `adopt` folded the old one's data in. **51 of 51 data grubs
byte-identical.** No manual step at any point.

So the release path is the stock entry, and §11.2 is what you use to install
a desk that is not in the list.

### 12.7 Adopted pages spawn their evaluators immediately

Writing a page's `code` grub spawns that page's evaluator fiber. So an
adopt writes N pages and starts N fibers at once — into an instance that
has no consent yet, because `apply-bill` just created it. Every one is
vetoed:

```
here=[…/lattice.lattice_app/page/notes/alpha name=~.code] jump=%poke → vetoed
%lattice /page eval: failed
```

**They park rather than spin.** Veto count held steady across twenty
seconds, which is `+rise-wait` doing what auspex's comment describes: a
restarted process blocks on a poke that never comes instead of reaching
again.

That is the good outcome and it was not a given. On a store with hundreds
of pages the difference between parking and looping is the difference
between a quiet upgrade and a pegged pier during the exact window the user
is being asked to approve roads. Worth re-checking on a large store before
release, since four pages is not a load test.

## 13. The carry, working — and the four bugs between here and there — 2026-09-12

§12 left the carry written but unproven. It took four more fixes, and every
one of them was invisible to all six checkers. What follows is each bug, the
symptom it actually presented, and the rule that makes it a class rather
than an incident.

### 13.1 A road's trailing slash decides which lane it is

`weir.json` declared the carry road as `'/apps/lattice.lattice_app'`. The ask
rendered it, the user granted it, and grubbery applied it — the dump showed it
in the instance's weir:

```
peek={[%.y p=[%.y p=[path=/apps name=~.lattice.lattice_app]]] ...}
```

That is a FILE lane: the grub `lattice.lattice_app` inside the directory
`/apps`. The peek in `+carry-old-data` asks for a DIRECTORY:

```
dest=[%.n p=/apps/lattice.lattice_app]
```

Two different lanes. The grant was real and never matched what was asked, so
the peek was vetoed with the road visibly granted — the worst kind of veto to
read, because the weir dump is right there and looks correct.

The rule: a declared road ending in `/` is a directory lane, and one without
is a grub lane. `/sys/lick/` and `/sys/ames/registry` differ for exactly this
reason, which is the thing to compare against when a granted road is refused.

### 13.2 A refused road must not mark a migration done

The first version treated `peek-soft` returning `~` as "no old instance" and
marked itself carried. `+peek-soft` returns `~` ONLY for `[~ %veto *]`; a peek
that reached the namespace and found nothing comes back `[~ %none]`. So a
refused road wrote the migration off permanently — and combined with §13.1,
which guaranteed the refusal, the carry would have been skipped for every
user while reporting success.

The rule: for anything that runs once and marks itself, a veto and an absence
are different answers. Absence is final; a veto is "not yet". §12's graceful
degradation was right about vetoes being survivable and wrong about them
being conclusive.

### 13.3 A nexus cannot read or write its own root as a directory

This one is structural and worth internalising. `+nearest-governor` in
grubbery:

```hoon
%|
=/  pref=fold:tarball  (prefix:tarball path.here p.u.dest)
?.  =(pref p.u.dest)
  [~ pref]
?~  pref  [~ ~]
[~ (snip `fold:tarball`pref)]
```

A directory's entry is owned by its PARENT, so a directory road at-or-above
`here` is governed by the directory above the destination. For a sandboxed
nexus asking about its own root, that governor is outside the sandbox, and
the weir walk then checks the instance's own weir — which never grants a road
to itself. Vetoed.

So `(rv up /)` is not available to a sandboxed nexus, in either direction:
neither `(peek:io (rv up /) ~)` nor `(over-fold:io (rv up /) bol)`. The carry
was written as one fold at the root, which cannot work. `+over-fold` is hard,
so the writer crash-looped — `%lattice writer failed` on every rise, directly
after `%sand-applied`, which reads as "the grant broke it".

One level down is fine, and that is the whole fix. For a grub at our root the
governor is our root; for a directory below it the governor is our root; and
the walk stops AT the governor without checking its weir. So: the root's
grubs one write each, and one fold per top-level subtree.

A pleasant consequence — the root keeps its own neck for free, which the root
fold had to preserve by hand by peeking the root first. That peek was the
line that crashed.

### 13.4 A fold overwrites a directory, so it deletes what it does not list

With the per-child fold in, the carry ran and landed 61 of 62 grubs. The one
missing was `/mirror/mirror.sig` — the reconciler this install had already
spawned. `%over` on a directory removes every grub the bole does not carry,
and `+carry-bole` strips every `.sig` because processes do not travel. So the
fold killed a running process.

`+carry-merge` lays the carried tree over the tree that is here: per grub the
carried copy wins — §12 established that keeping what the destination has is
what loses data, because a `%fall` row's bunt is indistinguishable from real
content — but a grub only this install has survives. Directory necks stay
ours, since a neck is a mark prefix for the code we are running.

The root-level writes never had this problem, because they are one grub at a
time. It is only directories, and only because a fold is a whole-directory
overwrite.

### 13.5 How to verify a carry, given the source is boomed

The obvious check — byte-compare every grub against the source — cannot work,
and the reason is the same reason the carry is possible at all. The release
removes lattice's code from the ball, so the old instance's marks are gone and
every typed grub there reads `File is boomed`. 44 of 56 "differed" on first
comparison for exactly this reason; the 12 that matched were plain `json`.

What does verify it, and what these numbers were:

- **Path and mark parity against the source.** 62/62 present, marks
  identical. The only extras in the destination were `/carried.json` and
  `/mirror/tr/reconciler-started` — the second being proof `mirror.sig`
  survived §13.4's fix and is running.
- **Zero booms in the destination.** 56/56 typed grubs re-validated against
  the marks in the desk's own `code/`. This is `+ball-to-bole`'s unconditional
  `+sang-noun` doing the work the whole design rests on.
- **Content through the app's own API.** 4 pages with their kinds and share
  modes (`notes/alpha` still `clearweb`), 3 know entries with their original
  timestamps, 1 bookmark. One know body reads "memory entry for
  migration/plan, written to the OLD instance", which is as direct as
  evidence gets.
- **The published page still serves publicly.** `/apps/lattice/c/notes/alpha`
  answers 200 with no cookie from the new install.
- **The source untouched.** Still 62 grubs afterwards. The migration copies.

### 13.6 What no checker caught

All four bugs shipped past six checkers. Two are reachable by tooling and two
are not:

- §13.1 is checkable: `weir-check.py` already resolves io-arm to road, so it
  could compare the declared road's lane shape against the shape the call
  asks for. It currently reports the carry road as "declared, nothing reaches
  it" because it cannot see an inline absolute road, which is the same blind
  spot from the other side.
- §13.3 is checkable as a flat rule: `(rv up /)` and `(rf up / ...)`-adjacent
  root directory roads are never valid in a sandboxed nexus.
- §13.2 and §13.4 are semantic. A checker cannot know that a veto means
  "later" or that a fold must not remove a process.

The pattern from §12 held again in a fifth and sixth form: the failure never
appeared where the mistake was. §13.1 presented as a granted road being
refused, §13.2 as a silent success, §13.3 as the grant breaking the app, and
§13.4 as a one-grub rounding error.

## 14. The end-to-end test — 2026-09-12

§13 proved the carry. This proves the whole release, from the shell's
catalog to verified data, with exactly one human action in the middle.

### 14.1 What was actually run

wex was reset to a real user's starting position: `lattice.desk` culled, the
forge repo culled, and the old instance left dormant at `/apps/lattice.lattice_app`
with its 62 grubs — which is precisely where a ship sits once the release has
removed lattice's code from the ball. The data was snapshotted first, through
the app's own API, and every later check compares against that snapshot.

The release itself is **one line** — the stock catalog entry in shell.hoon's
`default-repos`, which is that list's documented purpose:

```hoon
[%github 'lattice' 'nisfeb/lattice' 'main']
```

Then `|commit %grubbery`, and nothing else was touched until consent.

### 14.2 The chain, unattended

Every step below happened with no intervention. This is the part §12 and §13
never tested — the desk was created by hand on every previous run.

```
default-repos entry
  → lattice.git_repo provisioned in the forge
  → clone
  → lattice.desk created
  → code checked out into /desk/code
  → bill.json processed:  [%desk-bill 1]
  → instance created:     [%desk-bill-entry ~.lattice.lattice_app /lattice app]
  → ask.json raised: 11 roads
        ↓
   ONE HUMAN ACTION: grant
        ↓
  → writer rises
  → [%lattice-carrying-old-data /apps/lattice.lattice_app]
  → carried.json true
```

### 14.3 The bug this found, and it is the seventh of its kind

The first attempt got as far as the code checkout and then stopped dead: no
instance, no ask, `manifest.json` frozen at version 0, and nothing in the log
to say why. It sat there for ten minutes looking like a slow clone.

`bill.json` still carried the `adopt` block from the generic desk.hoon
migration that §12 reverted. And `+apply-bill` reads a bill like this:

```hoon
=/  entries=(list [@t @t])
  (turn ~(tap by p.u.bill) |=([k=@t v=json] [k (so:dejs:format v)]))
```

`so:dejs` demands a string for every value in the object. `adopt` holds an
object, so the gate crashes — and the crash takes the ENTIRE bill with it,
including the one entry that was valid. A crashed fiber rolls its event back,
so there is no error to read.

Seventh sighting of the pattern: a hard call early in a sequence, and
everything after it silently gone. Two things follow from it. The stale block
was ours to delete when the migration moved into app.hoon — a revert leaves
debris on the other side of the boundary. And `+apply-bill` should ignore or
reject a key it does not understand rather than lose the install; an upstream
finding worth carrying into the PR argument, since any desk with a
forward-looking bill key hits it.

### 14.4 The verification

`scratchpad/e2e-verify.sh`, against the snapshot taken before the release was
applied. All 17 checks passed:

- **Namespace parity** — source still 62 grubs; every one of them present at
  the new install. Destination-only: `/carried.json` and
  `/mirror/tr/reconciler-started` (the reconciler running, per §13.4).
- **Zero booms** — every typed grub re-validated against the marks in the
  desk's own `code/`.
- **Through the app** — 4 pages with their kinds AND share modes
  (`notes/alpha` still `clearweb`), 3 know entries, 1 bookmark.
- **Bodies byte-for-byte** — all 3 know bodies and all 4 page bodies
  identical to the snapshot.
- **Serving** — owner reader 200; `/apps/lattice/c/notes/alpha` 200 with no
  cookie.
- **The memory store** — `lattice-list` through `/grubbery/mcp` returns all 3
  entries with their original timestamps, which means `+base` in
  `tool-bundle/lattice-mcp.hoon` resolves correctly after the move. This is
  the line the ricsul rollout depends on.

### 14.5 What this test did NOT establish

Stated plainly, because a passing test that oversells itself is worse than no
test:

- ~~The clone was not slow.~~ **Corrected.** The lane's log settles it: the
  clone was cold and it worked.

  ```
  id=0  pull  ok=True  cloned              ~2026.09.12..15.30.18
  id=1  pull  ok=True  already up to date  ~2026.09.12..15.33.14
  ```

  Culling the repo instance removes every object with it — packs, refs and
  tree all live under `<repo>/data` — so id=0 cloned from nothing. id=1 is
  `+ensure-pairing`'s follow-up pull, which correctly found nothing new, and
  reading THAT as the clone is what produced the wrong claim. The desk was
  created after the clone completed, so the pull-before-desk ordering held
  against a roughly three-minute cold clone. §12's finding stands as a
  latent risk for a slower clone, not as something this run failed to
  exercise.
- **The live→dormant transition was not re-run.** wex had already made it,
  and the data survived; reconstructing the pre-release ball to re-prove it
  would have cost two full rebuilds. The evidence is historical rather than
  fresh.
- **Four pages is not a load test.** §12.7's warning stands.
- **`+base` has a window.** It points at the desk path, so between the
  update landing and consent being granted, the memory tools read an EMPTY
  vault rather than failing — honest, but silent. On ricsul that is the
  memory store answering "nothing remembered" for the length of that window.
  It argues for moving `+base` in the release AFTER the carry, not the one
  that performs it.

## 15. Run #2: the same test from a real pre-migration ship — 2026-09-12

§14's run had a bug fixed in the middle of it, which means it was not a pass.
This is the same test from a genuine State A, cold, start to finish.

### 15.1 What made this one real

- **State A was rebuilt and verified live.** Lattice's 52 sources went back
  into the ball with the `%fall` row, the instance loaded, and `/apps/lattice`
  served 4 pages with their kinds and share modes, 3 know entries, 1 bookmark,
  and a public clearweb read with no cookie. That is a real user's ship, not
  an approximation of one.
- **The snapshot came from that live instance**, so "before" means the user's
  own data as their running app served it. 63 grubs.
- **Cold clone**: desk and forge repo both culled first.
- **No mid-run fixes.** A pre-flight ran all seven checkers, validated
  bill.json, and corrected a stale comment BEFORE the release was committed.

Two mistakes of mine surfaced during setup rather than during the run, which
is the point of having a setup phase:

- The nexus went to `gub/lattice/` when the row's neck `[/lattice %app]`
  resolves under `gub/nex/`. Nothing looked for it there, so the instance had
  no code and could not load — and `+reload-changed-nexuses` never saw it,
  because it scans `/nex` only. Lattice's own repo has the answer in plain
  sight: `code/nex/lattice/app.hoon`.
- A watch that grepped the pane for "build-code done" matched output from the
  PREVIOUS build still in scrollback, and reported a build finished nine
  seconds after it started. Waiting on the dojo being idle cannot false-positive
  that way.

### 15.2 The release, and what ran unattended

The release is still one line — the `default-repos` stock entry — plus the
removal of lattice's code from the ball and its row from root.hoon. That
removal IS the release.

Committed 12:53:48. Everything below happened with no intervention:

```
build → stock entry seen → lattice.git_repo provisioned → COLD CLONE
  → lattice.desk created → code checked out (v24)
  → [%desk-bill 1] → [%desk-bill-entry ~.lattice.lattice_app /lattice app]
  → writer rises jailed: bind-http-self: vetoed — binding deferred
  → ask.json: 11 roads
        ↓
   ONE HUMAN ACTION: grant
        ↓
  → [%lattice-carrying-old-data /apps/lattice.lattice_app]
  → carried.json true, /apps/lattice/app 200
```

### 15.3 Every check passed

`scratchpad/e2e-verify.sh`, against the snapshot from the live State A
instance, now comparing to a recorded baseline rather than a hardcoded count:

- source still 63 grubs, and every one of them present at the new install
- zero booms — every typed grub re-validated against the desk's own `code/`
- pages, kinds and share modes identical; know count identical; bookmarks
  identical
- all 3 know bodies and all 4 page bodies byte-for-byte
- owner reader 200; published page 200 with no cookie
- `lattice-list` through `/grubbery/mcp` returns all 3 entries with their
  original timestamps

Destination-only: `/carried.json` and `/mirror/tr/reconciler-started`.

**Losslessness is proven.** The data survives the move intact, and the only
thing the user does is grant.

### 15.4 The finding that blocks the single release

The uptime probe is the reason this run matters more than §14's.

```
12:53:46  last 200
12:53:48  release committed
12:53:55  first gap — nine seconds later
          ... nothing serves /apps/lattice until consent is granted
```

This is structural, not incidental:

- the release removes lattice's code from the ball, so the OLD instance goes
  dormant and cannot serve
- the NEW instance is created jailed, and `bind-http-self` is vetoed until
  its weir is approved
- therefore nothing answers `/apps/lattice` between the release landing and
  the user granting

Downtime is bounded below by build-plus-provision and **unbounded above by how
long the user takes to notice the prompt**. For a ship whose owner is asleep
that is hours, and the app is simply gone in the meantime.

So the two-release sequence is not an optimisation. Release N adds the stock
entry AND KEEPS lattice's code in the ball: the old instance serves
continuously while the new one waits for consent and then carries the data.
Release N+1 removes the code once `carried.json` reads true. §9's plan was
right for a reason this run now measures.

### 15.5 Measuring downtime this way causes downtime

The probe polled `/apps/lattice/app` every 5s with a 4s timeout. Once nothing
was bound there, each sample became a request that never completed: 225 of
them queued, and the HTTP surface stopped answering anything — including the
shell's own consent UI, which is the one page the user needs in order to end
the outage.

The wedge was mine, not the system's; it drained on its own once the probe
stopped, exactly as §12's spins did. But it means this run's absolute
downtime figure is contaminated and only the STRUCTURE of §15.4 should be
quoted. A probe for the two-release test needs a short timeout and to back
off hard on consecutive failures, so that observing the outage cannot deepen
it.

### 15.6 Still not established

- **Four pages is not a load test.** Unchanged from §12.7 and §14.5.
- **The two-release sequence itself is untested.** §15.4 argues it is
  required; that is a different thing from having run it.
- **`+base` reads an empty vault between the update landing and consent** —
  the same window as §15.4, and on ricsul that is the memory store answering
  "nothing remembered". Moving `+base` in release N+1 rather than N closes it.

## 16. THE RELEASE PROCEDURE — run this on ricsul

Everything above is how we got here. This section is the procedure. It was
rehearsed on two ships end to end, and every step below either passed there or
is a step the rehearsal proved we had forgotten.

### 16.0 What the release is

Three changes to ricsul's `%grubbery` desk, and nothing else:

1. lattice's sources and its `root.hoon` row **leave the ball**. That removal is
   the release.
2. the stock catalog gains two `+published` entries, lattice and auspex.
3. `+base` in `tool-bundle/lattice-mcp.hoon` moves to the desk instance.

Everything a user then experiences follows from those three, unattended, except
one consent prompt per app — two, for lattice and auspex.

### 16.0b Unpublish first, republish after you have verified

The release reaches every subscriber the moment ricsul commits, because kiln
follows the desk. To get ricsul into the new shape and CHECK it before anyone
else sees it, close the desk first.

**Before you begin, on ricsul:**

```
|private %grubbery
```

Confirm it took, rather than assuming:

```
.^([r=dict:clay w=dict:clay] %cp /=grubbery=)
```

Private is an empty WHITELIST — nobody is on the list, so nobody may read:

```
[r=[src=/ rul=[mod=%white who=[p={} q={}]]] w=[...]]
                    ^^^^^^
```

**After you have verified everything, to release:**

```
|public %grubbery
```

which is an empty BLACKLIST — nobody is excluded, so everybody may read:

```
[r=[src=/ rul=[mod=%black who=[p={} q={}]]] w=[...]]
                    ^^^^^^
```

Only the `r` (read) rule matters here; `w` stays `%white` and should not be
touched. Both commands and both outputs above were run and read back on a live
ship, not written from memory.

#### These are NOT the same "publish" as sharing the desks

Two independent mechanisms, and the release needs both. Confusing them will cost
you an afternoon:

| | controls | set by | checked with |
|---|---|---|---|
| **clay desk permission** | whether a subscriber can kiln-sync `%grubbery` **at all** | `\|public` / `\|private` | `.^(... %cp /=grubbery=)` |
| **grubbery usergroup share** | whether a subscriber can read lattice's and auspex's **desk code** out of the namespace | `share.usergroups` ← `/public` (§16.3) | six peek roads in `public.grp/how.weir` |

A ship can be clay-private while still serving grubbery-namespace reads to peers
— that is how the two-ship rehearsal ran, with the publisher's desk private the
whole time. So `|private` does not protect you from forgetting §16.3, and §16.3
does not gate the release. Do both.

#### What a subscriber experiences while you are private

kiln's `%next` treats a refused read as a failed download: it drops the sync and
re-runs `init`, which means subscribers RETRY rather than break permanently, and
they pick the release up when you go public. That is the behaviour you want, but
it also means they are retrying in a loop the whole time — keep the private
window as short as your verification allows, and do the verification with a
plan rather than by exploring.

### 16.1 Preconditions — all must be true before you commit anything

- **PRs merged, or shipped locally.** #60 and #61 are REQUIRED: without #60 a
  user gets a repo and no desk; without #61 two desks cannot hold grants at once,
  so only one app is installable. #62 and #63 are strongly wanted — #63 is what
  lets a subscriber that catches ricsul offline recover without you.
- `dist/single-release` audits clean: `scratchpad/h/audit-release.sh`, 23 checks.
- **lattice's repo is pushed** and `code/version.json` is bumped. Subscribers
  re-sync only on a version change; code alone changes nothing.
- **auspex's repo is pushed.** Its default branch is `master`, not `main`.
- ricsul's own data is backed up. The carry copies rather than moves, so the old
  instance is the backup — but COUNT it before and after rather than assume it:

  ```
  GET /grubbery/api/tree/apps/lattice.lattice_app
  ```

  and total the `files` entries recursively. The number must be identical after
  the carry. On the rehearsal ships it was, both times (63 and 251).

### 16.2 The sequence on ricsul

```
 0. close the desk                    |private %grubbery      (§16.0b, verify it)
 1. record the data you are moving    count grubs at /apps/lattice.lattice_app
 2. commit the desk                   |commit %grubbery
 3. wait for the ball to rebuild      expect several minutes
 4. ricsul provisions its OWN desks   lattice + auspex, from its forge — unattended
 5. grant lattice's roads             11 roads, in the shell
 6. grant auspex's roads              6 roads — a SEPARATE prompt
 7. lattice carries its data          carried.json flips to true — unattended
 8. SHARE BOTH DESKS, count six       §16.3 — do not skip this
 9. verify ricsul                     §16.5b, every line
10. open the desk                     |public %grubbery       (§16.0b, verify it)
```

Steps 4 and 7 need nobody. Everything else is yours, and 8 must come before
10: a subscriber that syncs before the share exists gets a desk that mirrors
nothing, and #63 means it will keep retrying against the missing grant until
you notice.

### 16.3 Share both desks, or every subscriber silently gets nothing

**This is the step most likely to be forgotten, and its failure is silent.**

A desk's share list is per-desk state and it does NOT survive the desk being
recreated. The release creates BRAND NEW desks on ricsul, so their share state
starts empty — whatever ricsul shared before the release is gone.

For each of `lattice` and `auspex`:

```
POST /grubbery/api/poke/apps/shell.shell/desks/<name>.desk/share.usergroups?blot=/json
     {"add":"/public"}
```

`/public` is the group every foreign ship belongs to automatically.

Then CHECK it, because a poke returning 200 is not evidence the grant landed:

```
GET /grubbery/ball/sys/ames/usergroups/public.grp/how.weir?blot=/json
```

You want **six** peek roads — two per desk plus the shell's own two:

```
peek /apps/shell.shell/public.json
peek /apps/shell.shell/share/public/desks.json
peek /apps/shell.shell/desks/lattice.desk/desk/code
peek /apps/shell.shell/desks/lattice.desk/version.json
peek /apps/shell.shell/desks/auspex.desk/desk/code
peek /apps/shell.shell/desks/auspex.desk/version.json
```

Fewer than six means a subscriber will get a desk with the right `source.json`,
an empty `/desk/code`, no instance, and **no error anywhere**. Do not proceed to
16.4 until you see six.

Poke it through `/grubbery/api/poke/...?blot=/json`, NOT with `&grub-cmd` from the
dojo: the handler reads the poke with an unwrapped `!<(json ...)`, so an untyped
noun crashes the fiber and the share silently never applies.

### 16.4 What a subscriber does, and what they see

Nothing, until they are asked. kiln syncs each revision in order (`%sing %w
ud+let`, then `%merg` that exact revision — it does not collapse to head), so the
release arrives on its own.

Then, unattended: the shell provisions a desk per `+published` entry, each desk
mirrors the distributor's `/desk/code` cross-ship, `bill.json` creates the
instance, and a consent prompt appears per app.

The user grants. lattice then carries their old data on the writer's first rise,
and their pages, memories and bookmarks are at the new location.

**Between the release landing and that grant, lattice is DOWN on their ship.** The
old instance is dormant the moment its code leaves the ball, and the new one
cannot bind until its weir is approved. That gap is as long as the user takes to
notice, and it is accepted: downtime pending user action is tolerable, data loss
is not.

During the same window the MCP memory tools report an EMPTY vault rather than an
error, because `+base` points at an instance with no data yet. Also accepted, and
also worth saying out loud to anyone who asks.

### 16.5 Verifying a migration

Grub-level byte comparison against the old instance is IMPOSSIBLE and that is by
design: the release takes lattice's marks out of the ball with its code, so every
typed grub at the old instance reads `File is boomed`. An earlier run reported 44
of 56 grubs "differing" for exactly that reason and the comparison meant nothing.

What actually proves it, and what the rehearsal measured:

| check | wex | feb |
|---|---|---|
| grubs carried | 63/63 | **251/251** |
| booms at the new install | 0 | 0 (245 typed) |
| source untouched afterwards | yes | yes, 251 |
| pages, kinds, share modes, know, bookmarks | identical | — |
| page and know bodies | 7/7 byte-for-byte | — |
| owner reader / published page, no cookie | 200 / 200 | 200 |
| memory store from the new location | answers | — |

`scratchpad/h/p3-verify.sh` runs all of it against a snapshot taken while the
pre-migration ship was still serving — on the rehearsal ships. It is wired to
their cookies and ports and it needs a snapshot from BEFORE the release, so it
is not a tool for ricsul on the day. Use §16.5b.

### 16.5b The ricsul checklist — every line, before `|public`

Read each of these by hand. A poke returning 200 proves nothing; only the read
does.

```
carried.json is true
  GET /grubbery/ball/apps/shell.shell/desks/lattice.desk/desk/data/lattice.lattice_app/carried.json?raw=1

the old instance still has every grub it had at step 1
  GET /grubbery/api/tree/apps/lattice.lattice_app          -> same count as step 1

the new instance has at least that many
  GET /grubbery/api/tree/apps/shell.shell/desks/lattice.desk/desk/data/lattice.lattice_app

nothing boomed: open a few typed grubs at the new instance and see content
  GET /grubbery/ball/.../lattice.lattice_app/know/vault/<key>/entry?raw=1
  (a boom reads "File is boomed" — that means the marks did not travel)

lattice serves, and your pages are there
  GET /apps/lattice/app                                    -> 200
  GET /apps/lattice/page-tree                              -> your pages, kinds, share modes
  GET /apps/lattice/know-list                              -> your memory count

a published page is public, no cookie
  GET /apps/lattice/c/<a page you share>                   -> 200, no cookie

the memory store answers from the new location
  POST /grubbery/mcp  {"jsonrpc":"2.0","id":1,"method":"tools/call",
                       "params":{"name":"lattice-list","arguments":{}}}
                                                           -> your real count, not 0

both desks have code
  GET /grubbery/ball/apps/shell.shell/desks/lattice.desk/desk/code/version.json?raw=1
  GET /grubbery/ball/apps/shell.shell/desks/auspex.desk/desk/code/version.json?raw=1

both desks are shared: SIX peek roads                       §16.3

Landscape shows a Grubbery tile that opens /apps/grubbery
```

Only when every line reads right: `|public %grubbery`, then confirm `%black`.

### 16.6 If something goes wrong

- **desk exists, `/desk/code` empty, no error** — the share. Go to 16.3 and count
  the roads.
- **repo exists, no desk** — #60 is not in the build.
- **only one app installable** — #61 is not in the build.
- **subscriber stuck with an empty desk and never recovers** — #63 is not in the
  build. Poking its `source.json` restarts the subscription by hand.
- **`carried.json` stays `false` after the grant, and the log shows
  `%lattice-carry-road-refused`** — the carry road `/apps/lattice.lattice_app/`
  was not granted. The carry deliberately does NOT mark itself done on a
  refusal (an earlier version did, and would have skipped the migration for
  good), so grant the road and the next writer rise re-runs it. If
  `carried.json` is `true` the carry ran; a missing grub then is a bug, not a
  refusal.
- **nothing installed, `manifest.json` at 0, no error** — a bill entry it could
  not read. #62 makes this report the key instead of losing the install.

### 16.7 The old instance is the rollback

The carry copies. `/apps/lattice.lattice_app` keeps every grub it had, and the
rehearsal confirmed the count unchanged afterwards on both ships. Rolling back is
putting lattice's sources and its `root.hoon` row back in the ball; the data never
moved.

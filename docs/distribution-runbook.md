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

1. Remove its `%fall` row from `lib/root.hoon` and `|commit %grubbery`.
   A row does not delete an instance, but leaving it in recreates one.
2. Cull the instance:
   `:grubbery &grub-cmd [%clean2 [%cull /apps/'<n>.<nexus>' ~]]`
   Children before parents. **This destroys the instance's data** — see
   11.5.
3. Delete `gub/nex/<n>/` and `gub/lib/<n>-*.hoon`, and commit again.
   Deletions from a mount do reach clay (§10.3).
4. Then the five calls in 11.2.

Order matters in one direction only: never delete the code while the
instance is still live, or its next reload bangs on missing source.

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
data that already exists elsewhere — grubbery issue #5. So a cull is a
delete, and step 11.3.2 is only safe where the data is disposable:

| ship | lattice data | safe to cull |
|---|---|---|
| `~wex` | 16 pages, all `bis-*`/`uimx-*`/`scrolltest` fixtures from the UI matrix scripts | yes |
| `~ricsul-bilwyt` | the real memory store | **no — not until there is an adoption path** |

Until #5 has an answer, ricsul's route is: grant the new desk instance a
temporary weir road into the old instance's tree, copy, revoke the road.
That is the "we ship grubbery too, so we can grant and then revoke"
plan — it works precisely because we control both tiers during the
migration and will not afterwards.

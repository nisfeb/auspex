# Distributing Auspex — the structure today, the structure after, and the runbook

Written 2026-09-09. Every fact here was read off a ship, a branch, or a
script on that date; where something is a decision still to be made it says
so. The production ship is `~ricsul-bilwyt`. **Nothing in this document is
executed on it until an explicit go, one step at a time.**

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
the ball, BANGed until code returns). The parked plan for that is code in the
ball's app-local namespace (`[[/project/lattice/code-in-the-ball]]`), waiting
on upstream's `tools-nexus-refactor`. This runbook is the desk route, which is
the route that exists today.

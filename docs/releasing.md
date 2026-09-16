#  Releasing auspex: what makes ricsul update, and what makes its subscribers update

Auspex is a **stock desk app**: the source of truth is this git repo, the
publisher is `~ricsul-bilwyt`, and every other ship gets it from ricsul. Two
separate mechanisms move a change along that path, and they fail in different
ways. This file is the same in nisfeb/lattice and nisfeb/calendar, because the
mechanism is identical for all three and the thing that costs hours is not
knowing which half you are looking at.

For the one-time migration that made auspex a stock desk in the first place —
unpublishing, the carry, the six-road grants, ghost tiles — see
`distribution-runbook.md` §16. This file is only the ongoing release path.

Written 2026-09-15 from the grubbery kernel source (`gub/nex/desk.hoon`) and
from failures measured on `~ricsul-bilwyt`, `~martyr-sanryg` and `~wex` that
day. Line references are to grubbery's `desk/gub/nex/desk.hoon`.

##  The short version

```
you: git push  (ref master  -- NOT main, unlike lattice and calendar)
  |
  |  ricsul's forge polls the remote every 15 min  (config.json "poll": 15)
  v
ricsul's forge repo         /apps/forge.git_forge/repos/auspex.git_repo/data/tree/code
  |
  |  ricsul's auspex.desk watches that tree's code/version.json
  |  and pulls when it DIFFERS from its own root version.json
  v
ricsul's desk               /apps/shell.shell/desks/auspex.desk/desk/code
  |
  |  ricsul REPUBLISHES the version file; subscribers watch that
  v
every subscriber's desk     source.json -> ~ricsul-bilwyt/apps/shell.shell/desks/auspex.desk/desk/code
```

**The single thing that makes anything update is `code/version.json` changing.**
Not a new commit, not changed code — the version number. Everything below is
detail on that one fact.

##  1. What makes ricsul update

Ricsul's forge repo tracks this repo. Its config:

```json
{"token":"","ref":"master","repo":"nisfeb/auspex","poll":15}
```

**Note the ref: `master`.** Lattice and calendar track `main`; auspex tracks
`master`. Pushing a release to the wrong branch is a silent no-op — the forge
never sees it, no desk ever pulls, and everything looks fine.

A `git push` to `master` reaches ricsul **on its own within about 15 minutes**.
There is no staging state for a desk app: pushing is deploying, on a timer.

To make it immediate instead of waiting for the poll:

```sh
POST https://urbit.sneagan.com/grubbery/forge/api/run
     {"repo":"auspex.git_repo","command":"pull"}
```

It answers `ok`, which means the forge accepted the command — **not** that the
desk has rebuilt. The pull checks the repo out into the forge tree; the desk
then has to notice.

Ricsul's auspex desk points at that tree:

```json
{"code":"/apps/forge.git_forge/repos/auspex.git_repo/data/tree/code"}
```

A local path, not a ship — ricsul reads its own forge. (Subscribers point at
ricsul over ames instead; see §2.)

##  2. What makes ricsul's subscribers update

Every subscriber's auspex desk has a `source.json` naming ricsul:

```json
{"code":"~ricsul-bilwyt/apps/shell.shell/desks/auspex.desk/desk/code"}
```

The desk nexus keeps a subscription on the source's `code/version.json`
(desk.hoon:163-186). On a `%news` for that file it runs `do-snapshot` then
`sync-release`. **No user action is required** — nobody has to press Fetch
Latest, and no consent prompt appears unless the release adds a road to
`ask.json`.

The gate is exactly this (`+source-behind`):

```hoon
(pure:m !=(src-ver own))
```

An inequality between the source's `code/version.json` and the desk's own root
`version.json`. Nothing else is compared — not file hashes, not commit ids,
not timestamps.

`sync-release` then mirrors the code tree and **republishes the version file
locally**, with the kernel's own comment explaining why:

> mirror the source's version file locally, under its own name, so
> followers of THIS desk watch our republished version

That is the relay hop. It is why a subscriber can itself be a publisher.

##  3. Therefore: bump `code/version.json` on every release

| what you did | what happens |
|---|---|
| changed code, bumped version | ricsul syncs, subscribers sync. Correct. |
| changed code, **forgot** the bump | **nothing propagates.** Ricsul's forge has your commit; no desk ever pulls it. Everything looks fine and nothing shipped. |
| bumped version, no code change | the version file syncs and nothing else does. `sync-dir` is content-addressed — only real changes write — so no nexus rebuilds. |

The second row is the common mistake and it is silent. The third row matters
when you are trying to force a rebuild: a version-only bump will not do it.

**The v13 release is the worked positive example.** The inbox predicate fix
changed `code/lib/auspex-chain.hoon` and `code/nex/auspex/app.hoon` and bumped
12 -> 13. Ricsul's forge had already checked the commit out on its own poll by
the time the pull was fired; the desk mirrored to 13; subscribers picked it up
with nobody clicking anything, and a wedged auspex instance on
`~martyr-sanryg` recovered in the same pass. That is what a correct release
looks like: a real code change *and* a bump.

##  4. Verifying a release actually landed

Check all four, in this order. Each separates a different failure.

```sh
# 1. did the forge fetch?
GET /grubbery/ball/apps/forge.git_forge/repos/auspex.git_repo/data/tree/code/version.json?raw=1

# 2. did ricsul's desk mirror it?
GET /grubbery/ball/apps/shell.shell/desks/auspex.desk/desk/code/version.json?raw=1
GET /grubbery/ball/apps/shell.shell/desks/auspex.desk/version.json?raw=1

# 3. did the instance rebuild, or is it BANGed?
GET /grubbery/ball/apps/shell.shell/desks/auspex.desk/desk/data/auspex.auspex_app?info=1
#    bang: null  = healthy.  bang: "no built nexus %auspex--app ..." = dead.

# 4. does the route answer?
GET /apps/auspex          # fast 200/403 = alive.  404 or hang = dead instance.
```

A version number is not proof. **The instance's `bang` is the proof**, and the
route is the proof a user cares about.

Note that `code/` is what ships and `tests/` is not: the code-namespace shape
carries `lib mar nex bill.json icon.svg tile.json version.json`, and desk-level
`tests/` never reaches a subscriber. Tests run on a dev ship (§7).

##  5. The failure modes, all measured

###  5a. Version matches, code tree empty: wedged for ever

Measured on `~martyr-sanryg`, 2026-09-15, on its calendar desk — the same trap
applies to auspex. Its root read `{"version": 15}`, ricsul published 15, and
`code/` was **empty**. `source-behind` compared 15 to 15, answered "not behind",
and never synced again. The desk page reported itself up to date and the route
hung for 30 seconds per request.

The version gate is the trap: it suppresses the only thing that would refill
the tree. The escape is the unconditional pull, which has no version gate:

```sh
POST /grubbery/desk/auspex/fetch-latest
```

(`+do-fetch`, desk.hoon: *"pull the source's current code now,
unconditionally (no version gate)"*. The same thing runs from a
`{"action":"fetch"}` poke at the desk's `main.sig`.)

###  5b. A BANGed instance is not healed by a successful sync

After a refill the nexus can compile cleanly and the instance still stay
BANGed: `reload-changed-nexuses` follows recorded refs, and a nexus that never
built has none, so the walk never visits it. Measured at 28ms doing nothing
while the app stayed dead.

It comes back when the instance is reloaded explicitly:

```sh
POST /grubbery/ball/apps/shell.shell/desks/auspex.desk/desk/data/auspex.auspex_app
     action=reload-nexus
```

**Auspex's own "icon 404s when clicked" was this shape.** A user ran Fetch
Latest, the log said it updated, and the app still 404'd — because the tree was
fine and the instance was dead. A permit reapply did not fix it either. So: **a
clean compile does not imply a live app.** Check the bang.

###  5c. A neck-less `/desk/code` never compiles anything

A `/desk/code` created as a plain directory — by an older kernel, or by hand —
has no `[/ %code]` neck, and a dir without that neck is not a code namespace,
so grubbery never runs `build-code` over it. Files land with the right marks
and nothing compiles them. Seen on a real subscriber with auspex and lattice
both wedged that way.

`+ensure-code-nexus` repairs it. It used to run only when the desk nexus rose,
which a subscriber does not do by itself; since 2026-09-15 it also runs from
`sync-release`, so an arriving release repairs it. Check the neck with:

```sh
GET /grubbery/ball/apps/shell.shell/desks/auspex.desk/desk?info=1
#    "code" child should have  neck: "/code"
```

###  5d. Symptom shapes

| symptom | usual cause |
|---|---|
| route **hangs** (no response, times out) | dead instance still holding the eyre binding |
| route **404s** | no instance bound at all — auspex's classic symptom |
| route **403s fast** | healthy; that is just unauthenticated |
| desk says up to date, app dead | 5a (empty tree) or 5c (neck-less dir) |

##  6. Desk apps and the kernel are delivered differently

Do not mix these up. Auspex, lattice and calendar are **desk apps**. Grubbery
itself is the **kernel**.

| | desk app (auspex / lattice / calendar) | kernel (grubbery) |
|---|---|---|
| source of truth | this git repo | nisfeb/grubbery branch |
| how it reaches ricsul | `git push`, then forge poll or forge pull | `scp` to ricsul's mount, then `\|commit %grubbery` in the dojo |
| how it reaches subscribers | version bump, automatically | kiln desk sync, automatically |
| release unit | `code/version.json` | a clay commit |

Two notes on the kernel side, both learned the hard way:

- Touching `lib/*.hoon` or `app/grubbery.hoon` bumps the **gall agent**: the
  ship stops answering HTTP for minutes (~4.5 on `~wex`). Touching
  `gub/nex/*.hoon` only rebuilds a nexus, which is seconds.
- On ricsul, **deletions from the mount never reach clay**; adds and edits do.
- A `\|commit` that prints only `>=` with no rebuild means clay saw no change.
  That usually means it was already committed, not that the commit failed.

##  7. Testing before you ship

`~wex` is the fake test ship. Writing into a desk's code tree compiles
**immediately**, with no commit, which is the fast loop:

```sh
POST /grubbery/ball/apps/shell.shell/desks/auspex.desk/desk/code/nex/auspex/app.hoon
     action=write-text  content=<the file>
```

Then read the instance's `?info=1`: `bang: null` means it compiled, and a
non-null bang **carries the compile error with line and column**. That is about
a minute per iteration. A file that does not exist yet needs
`action=create-file&filename=<name>` first — `write-text` 404s on a missing
file.

Unit tests live at desk level and do **not** ship. Copy the lib to wex's `lib/`
and `gub/lib/`, the test to `tests/lib/`, `|commit %grubbery`, then:

```
-test /=grubbery=/tests/lib/auspex-chain
```

Two practical notes on that loop: the dojo needs `--` before a leading-dash
argument when sent through tmux (`tmux send-keys -t <pane> -- '-test ...'`), and
a suite-level `ok=%.y` with no per-test `OK` lines for your file means it did
**not** run — usually the commit had not landed yet.

Fake ships derive every keypair from the `@p`, so signature paths behave
differently there than on a real ship. Auspex's chain verification was proven
on `~martyr-sanryg`, a real planet, for that reason.

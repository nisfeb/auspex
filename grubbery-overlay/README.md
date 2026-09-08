# grubbery-overlay

Canonical source for urmail's ship side, running as a **grubbery nexus** inside
the `%grubbery` desk rather than as its own gall agent. See the `v3 — urmail as
a grubbery nexus` section of `../docs/superpowers/specs/2026-09-07-urmail-design.md`,
which governs this tree.

Grubbery's `sync-gub` only loads `gub/` from its own desk, so the code has to
physically live in `%grubbery`. We keep the source here, under this repo's
version control and tests, and **copy** it into a grubbery desk tree with
`../scripts/sync-overlay.sh`. Re-run it after every grubbery pull: a grubbery
core update knows nothing about this overlay, and committing the desk without
re-syncing culls urmail out of clay.

## Layout

```
grubbery-overlay/
  lib/urmail-chain.hoon        the pure core: types + signing, verification,
                               the three verdicts, +merge, +prune,
                               +thread-key, +freeze, the input caps.
                               Ported unchanged from the desk's
                               lib/urmail.hoon + sur/urmail.hoon.
  tests/lib/urmail-chain.hoon  31 tests, ported unchanged
```

`nex/urmail/`, `mar/urmail/`, `mar-clay/` and `mar-core/` are not here yet —
the nexus and its marcs are later slices. `sync-overlay.sh` already maps them,
so those slices only have to drop files in.

## Two rules this tree obeys

**Everything is named `urmail-*`.** `gub/lib` is shared with grubbery's own
libraries and with every other overlay's, and the sync never uses `--delete`,
so an unprefixed file silently overwrites grubbery's and no later sync puts it
back. `sync-overlay.sh` refuses to run if an overlay lib lacks the prefix.

**An overlay lib imports nothing.** The same file has to compile in two places:
the desk-level `/lib`, where `-test` builds it with ford runes (`/-`, `/+`),
and `gub/lib`, where grubbery's loader builds it with `/<`. Those syntaxes are
not interchangeable. That is why the desk's `sur/urmail.hoon` types are inlined
into `lib/urmail-chain.hoon` rather than kept in a second file — an overlay has
no `sur/`, and a lib that imported one could only live in one of the two trees.
Every lattice overlay lib is import-free for the same reason.

## Deploy loop

```bash
scripts/sync-overlay.sh /home/sneagan/software/wex/grubbery
```

then, in that ship's dojo, one command at a time (a dojo drops keystrokes typed
while an event runs, so verify each echo before sending the next):

```
|commit %grubbery
|suspend %grubbery
|revive %grubbery
-test /=grubbery=/tests/lib/urmail-chain ~
```

The bounce is not optional once a fiber runs here: pushing source recompiles the
nexus but does not respawn long-lived fibers, which keep running old code
silently. And never hotfix one file through the pier mount — the mount is a
stale snapshot and commits wholesale, reverting every file changed since the
last sync. Deploy the whole overlay or nothing.

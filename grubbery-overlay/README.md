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
                               +thread-key, +freeze, the input caps, and
                               the shapes the tree persists.
  lib/urmail-web.hoon          the JSON request decoders: the one part of
                               the HTTP path no Hoon type has checked
  tests/lib/urmail-chain.hoon  the ported chain suite
  tests/lib/urmail-web.hoon    13 tests on the decoders, most of them on
                               what a malformed body does
  nex/urmail/app.hoon          the nexus: /main.sig, the mail tree, and
                               the web surface under /ui
  nex/urmail/ui-app/           the BUILT client, two committed files.
                               `npm run build` in ../ui writes them; the
                               overlay is the deploy source, so an
                               artifact not in it does not ship
  mar/urmail/{msg,meta,idx,    the PERSISTED marcs -> gub/mar/urmail/
             blob,blobvis}
  mar-gub/urmail-{chain,action} the WIRE marcs -> gub/mar/ (top level)
```

`mar-clay/` and `mar-core/` are still unused; `sync-overlay.sh` maps them for
later slices.

## The two marc rules, which point opposite ways

**Persisted marcs are noun passthroughs.** A marc written `|_ s=stored-msg:uc`
re-validates every stored grub against the live type on every read, so the day
the type gains a field, every message already on disk booms and every reader
falls back to the bunt. For mail that is data loss. The shape check lives in
the nexus instead, as a `;;` ladder under `mule` — newest shape first, a later
version added above the default and upgraded in place.

There is one place that rule cannot save anything, and it is worth naming.
`$stored-msg` went to version 1 when `unsigned` gained `attachments`, and a
version 0 grub is **refused**, not upgraded. `msg-id` and the signature both
cover the shape, so rewriting a %0 message into the %1 shape would leave a
message whose signature no longer matches its own contents — which every peer
would then read as `%forged`. Turning genuine mail into apparent forgeries is
worse than refusing it. A signed message cannot be migrated; the only true
migration is to carry every historical shape and its digest forever, and that
is deferred until the chain format is declared stable.

**Wire marcs are typed**, because they are never read back off disk and a
malformed chain from a hostile ship should fail at the boundary.

**Wire marcs live at the top of `gub/mar`, not under `gub/mar/urmail/`.** Both
surfaces a peer pokes through — `sur/grub`'s `%grub-cmd` and a dojo poke —
flatten a blot to its bare mark name, so a blot with a path prefix is
unaddressable from either. The `urmail-` prefix is what keeps a top-level file
in that shared tree from shadowing grubbery's own; `sync-overlay.sh` refuses to
run without it, exactly as it does for `gub/lib`.

## Installing the nexus: one row this overlay does NOT write

A nexus cannot install itself. The directory that carries one is identified by
its *neck*, a directory-level mark fixed when the directory is made, and
nothing reachable at runtime can set one — grubbery's HTTP `PUT /dir` and
`sur/grub`'s `%make-dir` both lay a neck-less directory. The only mechanism the
distribution provides is a row in **grubbery's own** `lib/root.hoon`, which is
how lattice and mcp are installed:

```hoon
[%fall %| /apps/'urmail.urmail_app' [`[`[/urmail %app] ~ %.n ~] ~]]
```

`sync-overlay.sh` greps for that row and prints it when it is missing, but will
not write the file. An overlay that silently edits its host's sources is
exactly how a 28-line `lib/obelisk-ast.hoon` once clobbered grubbery's real
1208-line one. The consequence is real and is not hidden: **the row is outside
this repo and a grubbery pull reverts it.** Re-add it, then `|commit %grubbery`.

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
(cd ui && npm run build)          # only when ui/src changed
scripts/sync-overlay.sh /home/sneagan/software/wex/grubbery
```

The client build writes into `nex/urmail/ui-app/` and the sync carries it, so
a UI change that skips the build deploys the previous one silently.

then, in that ship's dojo, one command at a time (a dojo drops keystrokes typed
while an event runs, so verify each echo before sending the next):

```
|commit %grubbery
|suspend %grubbery
|revive %grubbery
-test /=grubbery=/tests/lib/urmail-chain ~
-test /=grubbery=/tests/lib/urmail-web ~
```

The bounce is not optional once a fiber runs here: pushing source recompiles the
nexus but does not respawn long-lived fibers, which keep running old code
silently. And never hotfix one file through the pier mount — the mount is a
stale snapshot and commits wholesale, reverting every file changed since the
last sync. Deploy the whole overlay or nothing.

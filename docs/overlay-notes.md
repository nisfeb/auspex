# grubbery-overlay

Canonical source for auspex's ship side, running as a **grubbery nexus** inside
the `%grubbery` desk rather than as its own gall agent. See the `v3 — auspex as
a grubbery nexus` section of `../docs/superpowers/specs/2026-09-07-auspex-design.md`,
which governs this tree.

Grubbery's `sync-gub` only loads `gub/` from its own desk, so the code has to
physically live in `%grubbery`. We keep the source here, under this repo's
version control and tests, and **copy** it into a grubbery desk tree with
`../scripts/sync-overlay.sh`. Re-run it after every grubbery pull: a grubbery
core update knows nothing about this overlay, and committing the desk without
re-syncing culls auspex out of clay.

## Layout

```
grubbery-overlay/
  lib/auspex-chain.hoon        the pure core: types + signing, verification,
                               the three verdicts, +merge, +prune,
                               +thread-key, +freeze, the input caps, and
                               the shapes the tree persists.
  lib/auspex-web.hoon          the JSON request decoders: the one part of
                               the HTTP path no Hoon type has checked
  tests/lib/auspex-chain.hoon  the ported chain suite, 57 tests
  tests/lib/auspex-web.hoon    15 tests on the decoders, most of them on
                               what a malformed body does
  nex/auspex/app.hoon          the nexus: /main.sig, the mail tree, and
                               the web surface under /ui
  nex/auspex/ui-app/           the BUILT client, two committed files.
                               `npm run build` in ../ui writes them; the
                               overlay is the deploy source, so an
                               artifact not in it does not ship
  mar/auspex/{msg,meta,idx,    the PERSISTED marcs -> gub/mar/auspex/
             blob,blobvis}
  mar-gub/auspex-{chain,action} the WIRE marcs -> gub/mar/ (top level)
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

## Upgrading from slice 2 — read this before deploying over live mail

`unsigned` changed twice and is now **frozen**. `$stored-msg` is at version 2;
versions 0 (pre-attachments) and 1 (pre-`body-mime`) are **refused, not
migrated**, for the reason below. Three consequences a ship carrying old mail
will actually hit:

- **Old messages become unreadable, not forged.** A refused grub is dropped in
  `+read-stored` before verification, so it never reaches `+verify-chain`, is
  never labelled, is never counted toward unread, and renders as `"unreadable"`
  through the marc. That is the intended outcome: relabelling genuine mail as
  `%forged` would be strictly worse.
- **Ghost threads.** A thread whose every message is an old-version grub still
  has a directory, still appears in `/mail/idx`, and still counts against
  `max-threads` — because the index is maintained on write and nothing sweeps
  it on read. It shows as an empty thread.
- **Old grubs cannot be culled by the writer.** `+sync-slots` builds its cull
  list from what `+read-stored` returned, and it returned nothing for them, so
  they are invisible to the only thing that deletes messages. `%delete-thread`
  removes the whole thread directory and is the only way to clear them.

The clean upgrade is therefore `%delete-thread` on every affected thread, run
before or after the deploy, and there is no in-place path. If a ship's mail
matters, take a copy of the tree first.

There is one place that rule cannot save anything, and it is worth naming.
`$stored-msg` is **refused** rather than upgraded across versions. `msg-id` and
the signature both cover the shape, so rewriting an old message into the new
shape would leave a message whose signature no longer matches its own contents
— which every peer would then read as `%forged`. Turning genuine mail into
apparent forgeries is worse than refusing it. A signed message cannot be
migrated; the only true migration is to carry every historical shape and its
digest forever, and it is not worth doing now that the format is frozen.

`$meta` and `$stored-blob` sit on the other side of that line and **do** upgrade
in place, because nothing in either is covered by a signature. That contrast is
the whole reason local state is kept out of `unsigned`.

**Wire marcs are typed**, because they are never read back off disk and a
malformed chain from a hostile ship should fail at the boundary.

**Wire marcs live at the top of `gub/mar`, not under `gub/mar/auspex/`.** Both
surfaces a peer pokes through — `sur/grub`'s `%grub-cmd` and a dojo poke —
flatten a blot to its bare mark name, so a blot with a path prefix is
unaddressable from either. The `auspex-` prefix is what keeps a top-level file
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
[%fall %| /apps/'auspex.auspex_app' [`[`[/auspex %app] ~ %.n ~] ~]]
```

`sync-overlay.sh` greps for that row and prints it when it is missing, but will
not write the file. An overlay that silently edits its host's sources is
exactly how a 28-line `lib/obelisk-ast.hoon` once clobbered grubbery's real
1208-line one. The consequence is real and is not hidden: **the row is outside
this repo and a grubbery pull reverts it.** Re-add it, then `|commit %grubbery`.

## Two rules this tree obeys

**Everything is named `auspex-*`.** `gub/lib` is shared with grubbery's own
libraries and with every other overlay's, and the sync never uses `--delete`,
so an unprefixed file silently overwrites grubbery's and no later sync puts it
back. `sync-overlay.sh` refuses to run if an overlay lib lacks the prefix.

**An overlay lib imports nothing.** The same file has to compile in two places:
the desk-level `/lib`, where `-test` builds it with ford runes (`/-`, `/+`),
and `gub/lib`, where grubbery's loader builds it with `/<`. Those syntaxes are
not interchangeable. That is why the desk's `sur/auspex.hoon` types are inlined
into `lib/auspex-chain.hoon` rather than kept in a second file — an overlay has
no `sur/`, and a lib that imported one could only live in one of the two trees.
Every lattice overlay lib is import-free for the same reason.

## Deploy loop

```bash
(cd ui && npm run build)          # only when ui/src changed
scripts/sync-overlay.sh /home/sneagan/software/wex/grubbery
```

The client build writes into `nex/auspex/ui-app/` and the sync carries it, so
a UI change that skips the build deploys the previous one silently.

then, in that ship's dojo, one command at a time (a dojo drops keystrokes typed
while an event runs, so verify each echo before sending the next):

```
|commit %grubbery
|suspend %grubbery
|revive %grubbery
-test /=grubbery=/tests/lib/auspex-chain ~
-test /=grubbery=/tests/lib/auspex-web ~
```

The two counts above go stale the moment someone adds an arm and forgets this
file, which has already happened once. What the suites actually hold is
`grep -c '^++  test-' tests/lib/auspex-*.hoon`; check it against the OK lines
the dojo prints rather than against this paragraph.

The bounce is not optional once a fiber runs here: pushing source recompiles the
nexus but does not respawn long-lived fibers, which keep running old code
silently. And never hotfix one file through the pier mount — the mount is a
stale snapshot and commits wholesale, reverting every file changed since the
last sync. Deploy the whole overlay or nothing.

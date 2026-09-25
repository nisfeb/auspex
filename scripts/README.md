# scripts

`sync-overlay.sh` is gone. Auspex is not an overlay copied into somebody's
grubbery desk any more — `code/` **is** the code directory a grubbery `desk`
nexus mirrors, checked in, in the shape `desk.hoon` expects:

```
code/bill.json      instance name -> nexus code path; the ONE desk-level file
code/version.json   the opaque tag a desk watches to know it should re-sync
code/tile.json      the storefront CARD (title/info/color) - not the app's
code/icon.svg       the storefront icon; any icon.* at this level is found
code/{lib,mar,nex}  the app
```

An installed copy lands at
`/apps/shell.shell/desks/<name>.desk/desk/{code,data}` — `code` mirrored from
the source named in that desk's `source.json`, `data` created from
`bill.json` and holding everything the app writes.

- **`code-closure.py <code-dir>`** — the check that matters. A guest is
  hermetic twice over: source resolves only inside the code dir, and marcs do
  too ("Guests distribute every marc they use" — `desk.hoon`). Run it before
  publishing; the bar is closed. `--fill <grubbery-desk>` vendors what is
  missing and repeats until it closes.

## weir-check.py — does this nexus declare every road it reaches?

```
scripts/weir-check.py code/nex/<app>/app.hoon [--io <path to lib/fiberio.hoon>]
```

A nexus asks for roads in `+weir-json`, and the shell grants exactly those.
At the trusted tier there is no weir, so reaching an undeclared road costs
nothing and is invisible. On a sandboxed install it is a veto — and a veto
is a crashed event, which rolls back whatever the fiber had already written.
So the symptom surfaces somewhere else entirely.

That happened three times before this existed:

| app | undeclared road | how it looked |
|---|---|---|
| auspex | `/sys/ames/registry` | "has not been granted the key road" on a ship where that road *was* granted |
| lattice | `/sys/ames/usergroups/` | writer crash-loop; `page-save` answered `{"ok":true}` and wrote nothing |
| lattice | `/sys/ames/registry`, `/sys/lick/` | found by this tool, not by hand |

**The hard part is that the road is usually not in the app.** It lives
inside the io arm: `(reg-register-at:io writer-rail)` contains no path. So
the tool reads `lib/fiberio.hoon`, maps each io arm to the system roads it
reaches — transitively, since `reg-poke` reaches the registry via the
`reg-road` constant — and then asks which of those arms the app calls.

Two distinctions it has to get right, both learned by getting them wrong:

- **A road is not a wire.** `(send-dart %node wire &+&+[/sys %'bowl.sig'] …)`
  carries a wire named `/sys/now` and a road to `/sys/bowl.sig`. Only the
  second is weir-gated. Matching bare `/sys/…` paths counted the wires and
  made every arm look like it reached `/sys/now`.
- **A road constant is referenced bare, never called.** `reg-poke` says
  `(poke reg-road [reg-blot act])`. Following only `(arm …)` call syntax
  missed `reg-road` — and therefore the registry, the one road this tool
  exists to have caught.

It also reports `declared-but-unreached`, which flags a grant asked of the
user for nothing. Trust that direction less: a road built from an app-local
path constant (`[%& %| public-grp]`) is resolved, but a road assembled some
other way will read as unreached when it is not. Never delete a declared
road on this tool's word alone.

## hoon-test-kit/ — the Hoon suites in seconds, and what they miss

```
scripts/hoon-test-kit/hoon-test.sh <pier> [setup | suite ...]
scripts/hoon-test-kit/hoon-mutate.py <pier> [--ops OP,...] [--only ARM,...] [--list]
```

A vendored copy of [nisfeb/hoon-test-kit](https://github.com/nisfeb/hoon-test-kit)
(the commit is in `.kit-version`), configured by `hoon-test.conf` at the repo
root. `hoon-test.sh` runs `tests/lib/*` on a `%auspex-test` desk over the
pier's `conn.sock`, in about 7 s. `hoon-mutate.py` breaks one thing at a time
in the libs and lists what no test noticed. Usage is in the kit's README;
auspex's own results are in `docs/hoon-testing.md`. Update the kit there,
never here, then re-vendor.

## api-matrix.mjs: the HTTP API, end to end, on a dev ship

```
node scripts/api-matrix.mjs http://localhost:8080 <cookie-file>
```

16 checks over every route the clients use, including the refusals. It
writes mail, drafts, rules and lists on the ship, then deletes all of them.
**Dev ships only.** See `docs/hoon-testing.md`, "Step 2".

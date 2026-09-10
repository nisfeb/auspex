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
- **`codedir-check.py`** — the older, source-only check. Superseded by
  `code-closure.py`, which also resolves marcs.

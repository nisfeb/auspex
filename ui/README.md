# urmail — the web client

React + TypeScript + Vite. It talks to the **urmail grubbery nexus**, not to a
gall agent: there is no scry, no poke and no channel subscription here, only
same-origin `fetch` against the routes the nexus binds under `/apps/urmail`.

## Routes it uses

| | |
|---|---|
| `GET /apps/urmail/api/whoami` | our own `@p`, so a reply can drop us from its recipients |
| `GET /apps/urmail/api/inbox` | the thread listing |
| `GET /apps/urmail/api/thread/<id>` | one thread, every message with its own verdict |
| `POST /apps/urmail/api/send` | compose, reply and forward — all one action |
| `POST /apps/urmail/api/read` | mark one message read |
| `POST /apps/urmail/api/delete-thread` | remove a thread from this ship |
| `GET /grubbery/api/keep/apps/urmail.urmail_app/beacon/rev` | grubbery's keep-SSE stream over the nexus's change beacon |

The last one is the live-update channel. The nexus bumps that grub on every
mutation **except a read-mark**, so the stream means "something a reader can
see has changed". Opening a thread marks several messages read at once; if
those bumped the beacon, the stream would refetch the thread, which would mark
it read again, forever.

## Building

```bash
npm run build
```

The output is **not** `dist/`. It lands in
`../grubbery-overlay/nex/urmail/ui-app/` as exactly two files, `index.html` and
`app.js`, which the nexus lays down as grubs in `+on-load` and serves at
`/apps/urmail` and `/apps/urmail/app.js`. The CSS is inlined into the shell:
every asset request costs about two seconds on a serialized pier and burns its
own request fiber, which is why lattice ships one document plus one script and
why this does too.

Those two files are committed. The overlay is the deploy source, so an
artifact that is not in it does not ship. Rebuild and re-commit them whenever
`src/` changes, then `scripts/sync-overlay.sh`.

## Running against a ship

```bash
npm run dev                                     # ~wex, http://localhost:8081
SHIP_URL=http://localhost:8080 npm run dev      # ~feb
```

The app is served under its real route, so open
**http://localhost:5173/apps/urmail/** rather than the bare root — the client
builds every URL from `/apps/urmail`, and serving it anywhere else would only
work by accident. The dev server proxies `/apps/urmail/api` and `/grubbery` to
that ship. Both need the ship's session cookie, so log into it in the same browser first —
the nexus answers an unauthenticated request with 403, and every route in the
client surfaces that as an error rather than as empty state.

There is no `VITE_SHIP` any more, and nothing to keep in step with `SHIP_URL`.
The client no longer knows a ship name: it is served *by* the ship it talks
to, and asks that ship who it is.

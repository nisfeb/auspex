# urmail — the web client

React + TypeScript + Vite. It talks to the **urmail grubbery nexus**: every call
is a same-origin `fetch` against a route the nexus binds under `/apps/urmail`,
carrying the session cookie Eyre already set. There is no ship name to
configure and no way to aim the client at one ship while authenticating
against another, because it is served *by* the ship it talks to and asks that
ship who it is.

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

Every route is owner-gated and every response is JSON, errors included, so the
client has one shape to parse and one failure to render.

The last row is the live-update channel. The nexus bumps that grub on every
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
`/apps/urmail` and `/apps/urmail/app.js`. The CSS is inlined into the shell and
the build fails rather than emit a third file: every asset request costs about
two seconds on a serialized pier and burns its own request fiber, which is why
lattice ships one document plus one script and why this does too.

Those two files are committed. The overlay is the deploy source, so an artifact
that is not in it does not ship — a UI change that skips the build deploys the
previous one silently.

## Deploying a build to a ship

The client is part of the overlay, so it deploys the same way the nexus does:

```bash
npm run build
../scripts/sync-overlay.sh /home/sneagan/software/wex/grubbery   # or .../feb/grubbery
```

then, in that ship's dojo, one command at a time:

```
|commit %grubbery
|suspend %grubbery
|revive %grubbery
```

The bounce is not optional. A commit recompiles the nexus but does not respawn
its long-lived fibers, which keep running the old code with nothing to say so.
And never copy a single file in through the pier mount: the mount is a stale
snapshot and commits wholesale, reverting everything changed since the last
sync.

## Running against a ship without deploying

`vite dev` works against a live nexus, which is the fast loop — no build, no
commit, no bounce.

```bash
npm run dev                                     # ~wex, http://localhost:8081
SHIP_URL=http://localhost:8080 npm run dev      # ~feb
```

Open **http://localhost:5173/apps/urmail/**, not the bare root: the client
builds every URL from `/apps/urmail`, so serving it anywhere else would only
work by accident. The dev server proxies `/apps/urmail/api` and `/grubbery` to
that ship, so the module graph is local and every request that matters is the
ship's own answer. Both proxied prefixes need the ship's session cookie — log
into it in the same browser first, or the nexus answers 403 and the client
surfaces that as an error rather than as empty state.

What `vite dev` does **not** serve is the shell the nexus lays down; it serves
Vite's own `index.html`. Everything about how the built page is assembled — CSS
inlining, the two-grub shape, the absolute `/apps/urmail/` asset URLs — is only
exercised by `npm run build`. Build once before deploying, not only at the end.

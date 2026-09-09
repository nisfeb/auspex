// auspex's service worker. Hand-written, no workbox, no build plugin:
// the whole of what it has to do is a shell precache and one network-
// first data cache, and a generated worker would have been a dependency
// plus a config file to express thirty lines of policy — plus a
// precache manifest keyed on hashed filenames, which this build does not
// have (it emits four files, by name, forever).
//
// `d846103ab120` is stamped by vite.config.ts at copy time. It is
// the ONLY thing that invalidates the shell: the two grubs are replaced
// wholesale on a redeploy and keep their names, so nothing in a URL ever
// changes and a content-addressed cache key is not available.

const VERSION = 'd846103ab120'
const SHELL = `auspex-shell-${VERSION}`
// NOT versioned, unlike the shell. Mail is not part of the build: a
// deploy that changes one line of CSS has nothing to say about the
// listing, and a version-keyed data cache would throw away every cached
// conversation on every deploy — so the first offline open after an
// update would show an empty mailbox.
const DATA = 'auspex-data'

const BASE = '/apps/auspex'

// The shell, by the URLs the nexus actually serves. `/apps/auspex/` and
// `/apps/auspex` are the same document to the nexus (it strips the
// trailing empty knot), and both are reachable from a bookmark, so the
// fetch handler normalises rather than precaching two copies.
const SHELL_URLS = [`${BASE}/`, `${BASE}/app.js`, `${BASE}/manifest.json`]

// No icon URL in that list, because there is no icon URL: the manifest
// carries its icon as a data: URI. auspex has no unauthenticated route
// and never gains one, so an icon fetched over HTTP would be a fetch
// browsers make without credentials against a route that answers 403 —
// and the only other copy of the same grub is under /grubbery/, which
// this worker is forbidden to intercept (see below).

self.addEventListener('install', (e) => {
  e.waitUntil((async () => {
    const c = await caches.open(SHELL)
    // `reload` so an install never re-precaches whatever the HTTP cache
    // happens to hold. The grubs are served no-cache, but the install
    // is the one moment where being wrong about that is permanent.
    await c.addAll(SHELL_URLS.map((u) => new Request(u, { cache: 'reload' })))
    // Take over immediately. The alternative is a tab left on the old
    // shell with the new app.js grub already deployed, which is the
    // blank-page-with-nothing-in-the-console failure the nexus's
    // no-cache header exists to prevent.
    await self.skipWaiting()
  })())
})

self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    // Shell caches only. `auspex-data` is deliberately outside this
    // sweep: it is not keyed by build and must survive one.
    const stale = (await caches.keys())
      .filter((k) => k.startsWith('auspex-shell-') && k !== SHELL)
    for (const k of stale) await caches.delete(k)
    await self.clients.claim()
    // One line to the page, which turns it into a "reload" prompt. The
    // page decides whether to show it; a worker that reloaded the tab
    // itself would throw away an open composer.
    //
    // Only when there was something to replace. A FIRST install has no
    // stale cache, and telling a user who just opened the app for the
    // first time that it has been updated is a prompt that teaches them
    // to ignore the prompt.
    if (stale.length === 0) return
    for (const c of await self.clients.matchAll({ type: 'window' })) {
      c.postMessage({ auspex: 'updated' })
    }
  })())
})

const isShell = (p) => p === BASE || p === `${BASE}/` || p === `${BASE}/app.js`
  || p === `${BASE}/manifest.json`

// The listing and one thread: the two reads that make an offline app
// show mail rather than an empty frame. Network-first, so a live ship
// always wins and a cached page is never shown in preference to a
// current one.
const isMail = (p) => p === `${BASE}/api/inbox` || p.startsWith(`${BASE}/api/thread/`)

// WHAT THIS WORKER MUST NEVER TOUCH.
//
//   - anything that is not a GET. A cached POST is a send that did not
//     happen reported as one that did, and there is no version of that
//     which is acceptable in a mail client.
//   - /api/whoami. It is the ship's identity, it is used to drop us
//     from a reply's recipient list, and a stale one on a ship that has
//     been reinstalled would put us back in our own audience.
//   - /grubbery/*. That is the change beacon, an SSE stream held open
//     for the life of the tab. A worker in front of it either buffers
//     it forever or breaks it.
//   - /~/login. Eyre's own auth page and cookie exchange.
//   - /api/blob/*. Attachment bytes: up to a quarter-megabyte each and
//     saved to disk the moment they arrive, so caching them would
//     double the storage for no offline gain.
const skip = (p) => p.startsWith('/grubbery/') || p.startsWith('/~/')
  || p === `${BASE}/api/whoami` || p.startsWith(`${BASE}/api/blob/`)

self.addEventListener('fetch', (e) => {
  const req = e.request
  if (req.method !== 'GET') return
  const url = new URL(req.url)
  if (url.origin !== self.location.origin) return
  const p = url.pathname
  if (skip(p)) return

  if (isShell(p)) {
    e.respondWith((async () => {
      // Normalise the bookmark form onto the precached one, or a user
      // arriving at /apps/auspex (no slash) offline gets a miss for a
      // document that is sitting in the cache.
      const key = p === BASE ? `${BASE}/` : p
      const hit = await caches.match(key)
      if (hit) {
        // Cache-first, then refresh in the background: the shell is two
        // grubs replaced wholesale, so serving the cached one costs a
        // reload of staleness and buys an app that opens offline.
        e.waitUntil((async () => {
          try {
            const res = await fetch(req)
            if (res.ok) await (await caches.open(SHELL)).put(key, res.clone())
          } catch { /* offline: the cached shell is the answer */ }
        })())
        return hit
      }
      const res = await fetch(req)
      if (res.ok) (await caches.open(SHELL)).put(key, res.clone())
      return res
    })())
    return
  }

  if (isMail(p)) {
    e.respondWith((async () => {
      try {
        const res = await fetch(req)
        // Only a 200 is mail. A 403 from the owner gate is an answer
        // about the session, not about the mailbox, and caching it
        // would mean an expired login permanently shadowing the last
        // good listing.
        if (res.ok) (await caches.open(DATA)).put(req, res.clone())
        return res
      } catch (err) {
        const hit = await caches.match(req)
        if (!hit) throw err
        // MARKED, so nothing downstream can mistake this for live mail.
        // THE APP READS THIS HEADER: `onCachedMail` in api.ts watches it
        // and drives the "showing cached mail" banner off it. That is a
        // stronger signal than `navigator.onLine`, which is false only
        // when the machine has no network — a laptop on working wifi
        // whose ship is down is online by that flag and stale by this
        // one. So this line is load-bearing, not a debugging aid:
        // dropping it makes a stale mailbox indistinguishable from a
        // live one on the surface, not just in devtools.
        const h = new Headers(hit.headers)
        h.set('x-auspex-cached', '1')
        return new Response(await hit.blob(), {
          status: hit.status, statusText: hit.statusText, headers: h,
        })
      }
    })())
  }
})

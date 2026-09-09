//  THE AUTHENTICATED CLIENT. Every request this extension makes is here.
//
//  THE ONE ORIGIN. Every URL below is built from `this.origin`, which comes
//  from storage and nowhere else — never from a message, a header, a
//  recipient or a link. A mail client is a machine for rendering strings an
//  attacker signed, and the one thing it must never do with them is build a
//  URL. `+path` interpolates ids, and every id is encoded on the way in.
//
//  THE COOKIE. auspex has no unauthenticated surface at all: every route is
//  owner-gated behind Eyre's session cookie, which `POST /~/login` sets for
//  the ship's origin. So every call is `credentials: 'include'` and there is
//  no token, no header and no second scheme. The `+code` is used ONCE, at
//  connect, and is never stored: what persists is Thunderbird's cookie jar,
//  which is the browser's problem and not ours.
//
//  A 403 IS "SIGNED OUT", NOT "FAILED". It is what an expired session looks
//  like and what a ship that was reinstalled looks like, and the only cure
//  is the options page. The caller flips status and stops syncing rather
//  than retrying a request that will never start succeeding.

const BASE = '/apps/auspex'

//  Caps mirrored from ui/src/api.ts, which mirrors the nexus lib. A GUARD
//  RAIL, never the boundary: POST /api/blob answers 413 over max-blob and
//  the send refuses the count again. What these buy is a refusal the user
//  can act on at the moment they attach a file.
const MAX_BLOB = 262144
const MAX_ATTACH = 16

//  The 409 on GET /api/blob. NOT FETCHED IS NOT NOT FOUND: bytes are never
//  pushed, so an attachment on a message we hold and have not pulled is the
//  ordinary state of an inbound file.
const NOT_FETCHED = 409

class ApiError extends Error {
  constructor(status, message) {
    super(message)
    this.status = status
    this.signedOut = status === 403
  }
}

//  fetch rejected: the request never reached the ship. Distinguished from
//  an ApiError because "refused" and "never left" need different words —
//  the same distinction ui/src/api.ts draws for the same reason.
class UnreachableError extends Error {}

//  Trim a stored origin to exactly an origin. A trailing path, a trailing
//  slash and a query are all things a person pastes; none of them is an
//  origin, and keeping one would put user text into every URL below.
function normaliseOrigin(raw) {
  const u = new URL(String(raw).trim())
  if (u.protocol !== 'http:' && u.protocol !== 'https:') {
    throw new Error('the ship URL must be http or https')
  }
  return u.origin
}

//  A MATCH PATTERN HAS NO PORT. Firefox's match patterns are
//  scheme://host/path; a host with a port is not a syntax error, it is a
//  pattern that never matches anything, and `permissions.request` grants it
//  happily. With `http://127.0.0.1:8081/*` granted, every fetch to the ship
//  was CORS-checked as ordinary cross-origin traffic and failed on a
//  response with no access-control-allow-origin — which the ship never
//  sends, and should not. Proven with a bare probe extension in
//  Thunderbird 147: the same fetch succeeds with `http://127.0.0.1/*`. So
//  the pattern is the scheme and the bare host, which in Firefox matches
//  every port on it.
function patternFor(origin) {
  const u = new URL(origin)
  return `${u.protocol}//${u.hostname}/*`
}

class Api {
  constructor(origin) {
    this.origin = normaliseOrigin(origin)
  }

  //  The match pattern this origin needs, for permissions.request. Exactly
  //  one origin — never <all_urls>, and never a wildcard host.
  get pattern() { return patternFor(this.origin) }

  //  EVERY URL IN THIS FILE COMES THROUGH HERE. `path` is written by this
  //  file; anything interpolated into it is encoded by its caller.
  url(path) { return `${this.origin}${BASE}${path}` }

  async raw(path, init = {}) {
    let res
    try {
      //  `credentials` LAST, so no caller can drop it by accident: every
      //  route on this surface is owner-gated behind the session cookie,
      //  and a request without it is a 403 with a confusing story.
      res = await fetch(this.url(path), { ...init, credentials: 'include' })
    } catch (e) {
      throw new UnreachableError(e && e.message ? e.message : 'no answer')
    }
    return res
  }

  //  The nexus answers JSON on every path, errors included, so a failure
  //  carries the ship's own reason rather than a bare status code.
  async json(path, init) {
    const res = await this.raw(path, init)
    if (!res.ok) {
      let why = `HTTP ${res.status}`
      try {
        const j = await res.json()
        if (j && typeof j.error === 'string') why = j.error
      } catch { /* not JSON: keep the status line */ }
      throw new ApiError(res.status, why)
    }
    return res.json()
  }

  post(path, body) {
    return this.json(path, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body),
    })
  }

  //  ── the session ───────────────────────────────────────────────────
  //
  //  THE ONLY REQUEST NOT UNDER /apps/auspex, and the only one that ever
  //  sees the code. Eyre's own login form: the answer sets
  //  `urbauth-~ship` for this origin and Thunderbird's cookie jar keeps
  //  it. The code is a parameter here and a local in the caller; it
  //  reaches no storage, no log and no header.
  async login(code) {
    let res
    try {
      res = await fetch(`${this.origin}/~/login`, {
        method: 'POST',
        credentials: 'include',
        headers: { 'content-type': 'application/x-www-form-urlencoded' },
        body: `password=${encodeURIComponent(code)}`,
      })
    } catch (e) {
      throw new UnreachableError(e && e.message ? e.message : 'no answer')
    }
    if (!res.ok) throw new ApiError(res.status, `login refused (HTTP ${res.status})`)
  }

  //  Proof the session took, and the ship's own name for itself. The
  //  client is not configured with a ship name anywhere else: it asks the
  //  ship it is talking to who it is, so it cannot be aimed at one ship
  //  while authenticated against another.
  async whoami() {
    const { ship } = await this.json('/api/whoami')
    return ship
  }

  //  ── reads ─────────────────────────────────────────────────────────

  inbox(view = 'all', offset = 0, limit = 100) {
    const p = new URLSearchParams({ view, offset: String(offset), limit: String(limit) })
    return this.json(`/api/inbox?${p.toString()}`)
  }

  //  Every page of one view, walked. `total` counts the whole view and the
  //  page carries its own offset, so the loop is over `total` and not over
  //  a hasMore flag the route does not send.
  async allThreads(view = 'all', limit = 100) {
    const out = []
    let offset = 0
    for (;;) {
      const page = await this.inbox(view, offset, limit)
      out.push(...(page.threads || []))
      offset += page.threads ? page.threads.length : 0
      if (!page.threads || !page.threads.length || offset >= page.total) {
        return { threads: out, total: page.total }
      }
    }
  }

  thread(id) { return this.json(`/api/thread/${encodeURIComponent(id)}`) }

  //  One attachment's bytes, or null when the ship holds the message and
  //  not the file. `name` and `mime` ride in the query because a blob grub
  //  is bytes and an arrival time and nothing else; both are hostile and
  //  the nexus sanitises them before either reaches a header.
  async blob(hash, name = '', mime = '') {
    const p = new URLSearchParams({ name, mime })
    const res = await this.raw(`/api/blob/${encodeURIComponent(hash)}?${p.toString()}`,
      { headers: { accept: '*/*' } })
    if (res.status === NOT_FETCHED) return null
    if (!res.ok) throw new ApiError(res.status, `blob ${res.status}`)
    return new Uint8Array(await res.arrayBuffer())
  }

  //  Ask the ship to keen for the bytes. Answers as soon as the writer has
  //  queued the request, never when the bytes land — nothing pushes their
  //  arrival, so the caller retries `blob` instead.
  fetchBlob(hash, from) { return this.post('/api/fetch-blob', { hash, from }) }

  //  ── writes ────────────────────────────────────────────────────────

  //  The upload. The body IS the file, byte for byte — no base64, no
  //  decoder on the request fiber. Refused here before a byte goes out,
  //  with the cap in the message.
  async uploadBlob(bytes) {
    if (bytes.length > MAX_BLOB) {
      throw new Error(`over the ${MAX_BLOB} byte limit for one file`)
    }
    const { hash } = await this.json('/api/blob', {
      method: 'POST',
      headers: { 'content-type': 'application/octet-stream' },
      body: bytes,
    })
    return hash
  }

  //  `attachments` is omitted entirely when there are none, so a send with
  //  nothing attached is byte-for-byte the request the web client makes.
  send(to, subj, body, prev, attachments = []) {
    return this.post('/api/send', {
      to, subj, body, prev,
      ...(attachments.length ? { attachments } : {}),
    })
  }

  //  One request for the whole batch: the nexus writer is the ship's single
  //  serialisation point for mail, and one id per request is one full
  //  mailbox scan per message.
  markRead(ids) {
    return ids.length ? this.post('/api/read', { 'msg-ids': ids }) : Promise.resolve()
  }

  markUnread(ids) {
    return ids.length ? this.post('/api/unread', { 'msg-ids': ids }) : Promise.resolve()
  }

  //  LOCAL STATE, PER THREAD. The same two routes the web client uses
  //  (ui/src/api.ts): neither field is signed, neither travels to another
  //  ship, and neither moves the ship's change beacon — which is why a
  //  star set here does not cost every open tab a full listing.
  //
  //  These are what the star and the flame are made of. The extension has
  //  no label UI of its own and asks for none: it writes exactly the two
  //  labels Thunderbird already has a button for.
  setLabel(threadId, label, add) {
    return this.post('/api/label', { 'thread-id': threadId, label, add })
  }

  setArchived(threadId, archived) {
    return this.post('/api/archive', { 'thread-id': threadId, archived })
  }
}

export {
  Api, ApiError, UnreachableError, normaliseOrigin, patternFor,
  BASE, MAX_BLOB, MAX_ATTACH, NOT_FETCHED,
}

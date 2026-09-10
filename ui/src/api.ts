export type Verdict = 'verified' | 'unverified' | 'forged'

// One attached file, as the message describes it. Metadata only — the
// bytes are content-addressed at `hash` and fetched separately.
//
// Every field here is INSIDE the signature, so an intermediary cannot
// alter one. That is a statement about tampering and not about truth:
// the author chose all four, and only `hash` is checkable, because the
// bytes either hash to it or are discarded. `name` and `mime` are
// claims. `size` is tied to `hash` (the hash is taken over the bytes
// with their length) so it cannot drift from the content alone.
export interface Attachment {
  name: string
  size: number
  // HOSTILE. Reported to the reader, never acted on: it must not pick a
  // renderer, must not become a Content-Type, and must not be trusted to
  // agree with the bytes. See the note on `body-mime` below — same
  // field, same signature, same reasoning.
  mime: string
  hash: string
}

export interface Message {
  id: string
  from: string
  to: string[]
  subject: string
  body: string
  // The author's rendering instruction, signed and so unalterable in
  // transit. Empty means text/plain. It is REPORTED, not obeyed: a
  // signature proves the author chose the value, never that it is safe,
  // and it arrives pre-signed inside a chain any ship may deliver. Every
  // body is rendered as plain text; see ThreadView.
  'body-mime': string
  sent: number
  prev: string | null
  // Files this message carries. Signed alongside the body, so the list
  // is as authentic as the message is — and no more. Older builds of the
  // nexus omitted the field entirely, so treat it as optional and
  // default it: a message from one of those is a message with no
  // attachments we can name, which is exactly what an absent field
  // means here.
  attachments?: Attachment[]
  verdict: Verdict
  read: boolean
}

export interface Thread {
  id: string
  messages: Message[]
  participants: string[]
  last: number
  // Copies stored on the ship that THIS BUILD cannot read: grubs written
  // under a pre-body-mime shape, which the nexus refuses rather than
  // relabelling, because rewriting a message into the current shape
  // breaks the signature that makes it evidence. Reported so a thread
  // that renders short says why instead of just looking empty.
  unreadable: number
  archived: boolean
  labels: string[]
}

export interface InboxEntry {
  id: string
  subject: string
  from: string
  snippet: string
  // The verdict of the message this row's from/subject/snippet came from.
  // Provenance belongs on the surface users scan fastest, not only after
  // the thread is opened.
  verdict: Verdict
  // True when the thread holds at least one %forged copy, whether or not
  // the summary above was drawn from one.
  forged: boolean
  count: number
  last: number
  unread: boolean
  participants: string[]
  // Copies in this thread that the ship cannot read: grubs written under
  // a pre-body-mime shape, refused rather than relabelled. Usually 0. A
  // row whose count is nonzero and whose `count` is 0 is a thread with
  // NO readable message — it still gets a row, because a thread silently
  // vanishing from the listing is the failure this field exists to stop.
  unreadable: number
  // Local state, on the row so the list can show it without a request
  // per thread. Neither field is signed and neither travels.
  archived: boolean
  labels: string[]
}

// Everything below is a same-origin fetch under one prefix.
//
// The nexus binds /apps/auspex and answers a small JSON API beneath it,
// and this app is served from that same route as two grubs — the shell
// and this script. So the browser already holds the session cookie Eyre
// set for the ship that served the page, every call is same-origin, and
// there is no ship name anywhere in this client: it asks the ship it was
// served by who it is (see `whoami`). A client configured with a ship
// name can be aimed at one ship while authenticating against another,
// with nothing obviously wrong until every call fails; this one cannot
// be, because it has nothing to aim.
//
// Every route here is owner-gated and answers JSON on every path,
// errors included, which is why `jsonOf` below can read a reason off a
// failure instead of showing a bare status code.
const BASE = '/apps/auspex'

class ApiError extends Error {
  status: number
  constructor(status: number, message: string) {
    super(message)
    this.status = status
  }
}

// THE SHIP ANSWERED AND THE ANSWER WAS NOT READABLE.
//
// Thrown only by `post` below, and only once `fetch` has resolved —
// response headers arrived, so the request reached the ship and the
// poke reached the writer. What failed after that was reading the body.
// This is NOT a send that never left, and it is not a send that was
// refused either: nobody here knows which it was, and the only honest
// thing a client can say is "go and look at Sent".
class GarbledError extends Error {}

// DID THIS REQUEST REACH THE SHIP AT ALL?
//
// An ApiError is the ship answering: a refusal, a 404, a bad @p. A
// GarbledError is the ship answering unintelligibly. Anything else out
// of these calls is fetch rejecting, which means the request never
// arrived — no poke, no signature, nothing written anywhere. The
// distinction is the whole of "no false sent": a send that was refused
// and a send that never left need different words, and only one of them
// is worth retrying by pressing the same button again.
//
// THE THIRD CASE IS WHY THIS IS NOT A BARE `instanceof ApiError` CHECK.
// `res.json()` throws a plain SyntaxError (or a TypeError, on a body
// that dies mid-stream) — a non-ApiError, and so "unreachable" under
// the old test, which told a user nothing had been signed about a send
// the writer may well have completed. That is a false negative on the
// one guarantee this client makes about sending.
export const unreachable = (e: unknown): boolean =>
  !(e instanceof ApiError) && !(e instanceof GarbledError)

// The middle case: reached the ship, no readable answer. Ask before
// `unreachable`, or don't — they are exclusive by construction.
export const garbled = (e: unknown): boolean => e instanceof GarbledError

async function jsonOf(res: Response): Promise<unknown> {
  if (!res.ok) {
    // The nexus answers every route with JSON, errors included
    // ({"error":"..."}), so surface its reason rather than a bare code.
    // A 403 from the owner gate arrives here too, and it is the one an
    // unauthenticated tab will see.
    let why = `HTTP ${res.status}`
    try {
      const j = await res.json()
      if (j && typeof j.error === 'string') why = j.error
    } catch { /* not JSON: keep the status line */ }
    throw new ApiError(res.status, why)
  }
  return res.json()
}

// WAS THIS MAIL SERVED FROM DISK RATHER THAN BY THE SHIP?
//
// The service worker answers /api/inbox and /api/thread from its cache
// when the network fails, and stamps `x-auspex-cached` on what it hands
// back (see ui/sw.js). Without that, a mailbox served from a cache and
// a mailbox served by the ship are the same pixels — which is a client
// quietly showing yesterday's mail as though it were today's.
//
// `navigator.onLine` is not a substitute. It is false only when the
// machine has no network at all; a laptop on a working wifi whose ship
// is down is online by that flag and stale by this one.
let fromCache = false
const cacheWatchers = new Set<(c: boolean) => void>()

// Subscribe to it. Called immediately with the current value, and hands
// back its own teardown.
export const onCachedMail = (fn: (c: boolean) => void): (() => void) => {
  cacheWatchers.add(fn)
  fn(fromCache)
  return () => { cacheWatchers.delete(fn) }
}

const setFromCache = (c: boolean) => {
  if (c === fromCache) return
  fromCache = c
  for (const fn of cacheWatchers) fn(c)
}

// `mail` marks the two routes the worker caches. Every other route
// (whoami, drafts, rules) is never cached and must not clear the flag:
// a drafts fetch succeeding says nothing about whether the listing on
// screen came from the ship.
const get = async <T>(path: string, mail = false): Promise<T> => {
  const res = await fetch(`${BASE}${path}`, {
    headers: { accept: 'application/json' },
  })
  if (mail) setFromCache(res.headers.get('x-auspex-cached') === '1')
  return await jsonOf(res) as T
}

// A WRITE, AND THE ONLY PLACE THAT KNOWS WHETHER THE REQUEST LANDED.
// `fetch` resolving is the fact worth recording: at that point the ship
// has sent response headers, which it cannot have done without having
// received the poke. Everything that fails after that flag is set —
// a body that is not JSON, a connection dropped mid-body — is the ship
// having answered, and gets said as such rather than as "never sent".
const post = async (path: string, body: unknown): Promise<unknown> => {
  let answered = false
  try {
    const res = await fetch(`${BASE}${path}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body),
    })
    answered = true
    return await jsonOf(res)
  } catch (e) {
    // An ApiError is already the ship's own reason and travels intact.
    if (answered && !(e instanceof ApiError)) {
      throw new GarbledError(e instanceof Error ? e.message : 'unreadable response')
    }
    throw e
  }
}

// Our own @p, with the sig. Needed in the UI so a reply composer can drop
// us from its own default recipient list.
//
// A live binding rather than a constant: the ship is the nexus's to know,
// not the browser's, so it arrives over the wire. `+whoami` is awaited
// before the first render (see main.tsx) so no component ever reads it
// empty — the alternative, threading it through props, would have meant
// editing every component to carry a value that never changes.
export let ourShip = ''

// CAN THIS SHIP MAKE OR CHECK A SIGNATURE?
//
// Auspex reaches jael through one road, /sys/scry, and under grubbery's
// distribution model an installed app is created permitted nothing and
// earns each road from the user's consent. Refused it, the nexus can
// neither sign an outgoing message nor look up a sender's key — so
// sending is off and every message reads as unverified, which is the
// correct verdict rather than a degraded one: a missing key is never a
// forgery.
//
// A live binding beside `ourShip`, and set from the same one request,
// because it is the same kind of fact: something about this ship that
// every surface needs and none can derive. Read at render time, so a
// component reads whatever the last whoami established.
//
// TRUE UNTIL THE SHIP SAYS OTHERWISE. A nexus older than /caps sends no
// `caps` at all, and on that ship signing works — so absence means yes
// and only an explicit `false` turns the warnings on. If whoami itself
// fails the app still mounts (see main.tsx) and this stays true: the
// inbox will report its own error, and claiming the ship cannot sign
// because we could not ask it would be a second, invented failure.
export let canSign = true

export const whoami = async () => {
  const { ship, caps } = await get<{
    ship: string
    caps?: { keys?: boolean }
  }>('/api/whoami')
  ourShip = ship
  canSign = caps?.keys !== false
}

// The one sentence the client says about a ship with no key road, in the
// words the sidebar shows. Kept here so the sidebar, the composer and the
// reply box cannot drift into three different explanations of one fact.
export const NO_KEYS_LINE
  = 'This ship cannot check or make signatures. Mail still arrives; every'
  + ' message shows as unverified and sending is off.'

// The listing is always a PAGE now: a page of rows plus the total of the
// view they came from. See `pageOf` below, which every caller uses.

// A deleted (or never-known) thread is a 404, which is the honest status
// for it, and the view already distinguishes "no longer exists" from a
// failed load. Map only that one code to null; every other failure stays
// an exception so it reads as an error rather than as an empty thread.
export const thread = async (id: string): Promise<Thread | null> => {
  try {
    return await get<Thread>(`/api/thread/${id}`, true)
  } catch (e) {
    if (e instanceof ApiError && e.status === 404) return null
    throw e
  }
}

// The caps, mirrored from grubbery-overlay/lib/auspex-chain.hoon. A
// GUARD RAIL, never the boundary: POST /api/blob refuses a body over
// max-blob with a 413 and the send refuses the count again. What these
// buy is a refusal the user can act on — "this file is too big" at the
// moment they pick it, rather than after a quarter-megabyte upload
// comes back 413.
export const MAX_BLOB = 262144
export const MAX_ATTACH = 16

// One attachment on its way into a send: metadata plus the content
// address the upload route answered. NO BYTES AND NO SIZE.
//
// `size` is deliberately absent. It is read off the stored blob by the
// nexus and signed from there, so a client cannot make a signature
// claim a length the bytes do not have — and the hash is not
// re-derived on send either, because the store only ever accepted a
// blob that hashed to its own address.
export interface AttachRef {
  name: string
  mime: string
  hash: string
}

// THE UPLOAD. The body is the File itself — `fetch` streams a File
// straight off disk, so nothing here ever holds the bytes in memory
// and there is no encoding between the file and the store.
//
// WHY NOT BASE64 IN THE SEND BODY, which is what this replaced: the
// nexus had to decode it, the decoder was an interpreted per-character
// loop on the request fiber holding the connection open, and the
// sixteen-file send the caps allow cost about nineteen seconds with no
// partial progress to show for it. Raw bytes need no decoder, and one
// request per file is what makes "uploading 2 of 5" possible at all.
export const uploadBlob = async (f: File): Promise<AttachRef> => {
  const res = await fetch(`${BASE}/api/blob`, {
    method: 'POST',
    // A File streams as-is. Reading it into a string first would cost
    // the file's length in memory per attachment, per open composer.
    body: f,
    headers: { 'content-type': 'application/octet-stream' },
  })
  const { hash } = await jsonOf(res) as { hash: string; size: number }
  return {
    name: f.name,
    // The BROWSER's guess, and it is a guess: it comes off the file
    // extension, and it is empty for a file the browser cannot place.
    // It is sent, signed and shown as the sender's claim, and the
    // download route never echoes it into a header without checking it
    // against an allow-list first.
    mime: f.type || 'application/octet-stream',
    hash,
  }
}

// Upload every file, IN SEQUENCE, reporting which one is in flight.
//
// Sequence and not Promise.all: sixteen concurrent quarter-megabyte
// POSTs at a serialized pier is sixteen request fibers competing for
// one ship, and "uploading 2 of 5" is a true statement only if there
// is one at a time. The throw NAMES THE FILE — "upload failed" alone
// tells a user nothing about which one to remove or retry.
//
// NOTHING IS SIGNED BY ANY OF THIS. An upload stores bytes under their
// content address and moves no message and no beacon, so a caller that
// throws here has a composer to keep open and nothing to undo.
export const uploadAll = async (
  files: File[],
  onProgress: (done: number, total: number) => void,
): Promise<AttachRef[]> => {
  const refs: AttachRef[] = []
  for (let i = 0; i < files.length; i += 1) {
    onProgress(i + 1, files.length)
    try {
      // eslint-disable-next-line no-await-in-loop
      refs.push(await uploadBlob(files[i]))
    } catch (e) {
      throw new Error(
        `${files[i].name}: ${e instanceof Error ? e.message : 'could not be uploaded'}`,
      )
    }
  }
  return refs
}

// WHO THE SHIP WOULD NOT CARRY IT TO, and why, in that ship's own words.
//
// The nexus screens each recipient against what that peer published
// about itself before the message is signed, and answers 200 with the
// ones it will skip rather than refusing the whole send: one peer
// publishing a zero cap inside a hundred-recipient `to` must not kill
// the other ninety-nine. When EVERY recipient is refused the route
// answers 400 instead, which arrives here as an ApiError and leaves the
// composer open — a composed message must not vanish behind a success.
export type Refusal = { ship: string; why: string }

// A 200 from /api/send. `refused` is always present, empty list
// included, so a caller can read it without asking whether the field
// exists — but it is decoded defensively anyway, because this is the
// one place where trusting a shape would turn a successful send into a
// thrown error.
export type SendResult = { refused: Refusal[] }

const asRefusals = (v: unknown): Refusal[] => {
  if (!v || typeof v !== 'object') return []
  const r = (v as { refused?: unknown }).refused
  if (!Array.isArray(r)) return []
  return r.flatMap((x) => (
    x && typeof x === 'object'
      && typeof (x as Refusal).ship === 'string'
      && typeof (x as Refusal).why === 'string'
      ? [{ ship: (x as Refusal).ship, why: (x as Refusal).why }]
      : []
  ))
}

// `attachments` is omitted entirely when there are none, so a send with
// no attachment is byte-for-byte the request every earlier client made.
export const send = async (
  to: string[],
  subject: string,
  body: string,
  prev: string | null,
  attachments: AttachRef[] = [],
): Promise<SendResult> => {
  const res = await post('/api/send', {
    to, subj: subject, body, prev,
    ...(attachments.length ? { attachments } : {}),
  })
  return { refused: asRefusals(res) }
}

// One line, for where a send is confirmed. Ship first on both halves:
// the recipients that got it, then the ones that did not and the reason
// each of them gave. `null` when nobody was refused, which is the
// ordinary case and wants no line at all.
export const refusalLine = (to: string[], refused: Refusal[]): string | null => {
  if (refused.length === 0) return null
  const bad = new Set(refused.map((r) => r.ship))
  const sent = to.filter((s) => !bad.has(s))
  const missed = refused.map((r) => `${r.ship}: ${r.why}`).join('; ')
  return sent.length > 0
    ? `Sent to ${sent.join(', ')} — not to ${missed}`
    : `Not sent to ${missed}`
}

// ── attachment bytes ─────────────────────────────────────────────────

// The download route. `name` and `mime` ride in the query, out of the
// signed attachment record the client just rendered, because a blob grub
// on the ship is bytes and an arrival time and nothing else. They are
// hostile either way — signed by whoever wrote the message, in a chain
// any ship may deliver — and the nexus sanitises both before either one
// reaches a header.
//
// EVERY interpolated field is encoded, the hash included. It reaches the
// client as a `0v…` cord off a signed record and the route parses it
// with `slaw %uv`, so a hash that is not one is a 400 — but "the value
// is well formed by the time anyone looks" is not a reason to build a
// URL by concatenation, and the two fields beside it were already
// encoded.
const blobUrl = (a: Attachment) =>
  `${BASE}/api/blob/${encodeURIComponent(a.hash)}`
  + `?name=${encodeURIComponent(a.name)}&mime=${encodeURIComponent(a.mime)}`

// NOT FETCHED IS NOT NOT FOUND. Bytes are never pushed, so an
// attachment on a message we hold and have not pulled is the ordinary
// state of an inbound file. The nexus answers 409 for it; the caller
// turns that into a Fetch control, not into "this file is gone".
export const NOT_FETCHED = 409

// Bytes, plus the name the SERVER chose for them.
export interface Download {
  blob: Blob
  name: string
}

// The filename out of Content-Disposition, or null if the header is not
// there or not the shape this nexus sends.
//
// THE SERVER'S NAME, NEVER THE MESSAGE'S. `name` on an attachment is
// signed and hostile — a signature proves the author chose the string,
// not that it is safe — and the nexus's +safe-name is what makes it a
// filename: separators, quotes, backslashes, semicolons, control bytes
// and every byte above ASCII are dropped, it is capped at 128, and a
// name that survives as nothing becomes the hash. Handing the raw name
// to `a.download` instead put that sanitiser on the wrong side of the
// boundary: it went out in the header and the browser saved under the
// unsanitised original, leaving the browser's own rules as the only
// guard on a string an attacker signed.
//
// The quoted form is exact rather than lenient BECAUSE of that
// sanitiser: no name the nexus emits can contain a quote, so there is
// no escaping to interpret and nothing to guess at.
const dispositionName = (h: string | null): string | null => {
  if (h === null) return null
  const m = /;\s*filename="([^"]*)"/.exec(h)
  return m && m[1] ? m[1] : null
}

export const getAttachment = async (a: Attachment): Promise<Download | null> => {
  const res = await fetch(blobUrl(a), { headers: { accept: '*/*' } })
  if (res.status === NOT_FETCHED) return null
  if (!res.ok) {
    let why = `HTTP ${res.status}`
    try {
      const j = await res.json()
      if (j && typeof j.error === 'string') why = j.error
    } catch { /* the error path is JSON; a non-JSON body keeps the code */ }
    throw new ApiError(res.status, why)
  }
  // The hash is the fallback, which is also what +safe-name falls back
  // to: a file that arrives with no usable name downloads as its content
  // address rather than as a string nobody checked.
  const name = dispositionName(res.headers.get('content-disposition'))
  return { blob: await res.blob(), name: name ?? a.hash }
}

// Ask the ship to keen for the bytes. `from` is a HINT about where to
// look and nothing more: any ship holding the bytes may serve them, the
// hash proves them, and naming the wrong ship costs a miss.
//
// This answers as soon as the writer has queued the request, never when
// the bytes land — the keen runs on its own fiber with a deadline per
// case probe. Nothing pushes the arrival either: a blob arriving does
// not move the change beacon, because it is not message content. The
// caller retries getAttachment instead.
export const fetchAttachment = (a: Attachment, from: string) =>
  post('/api/fetch-blob', { hash: a.hash, from })

// Hand a downloaded blob to the browser under the name the SHIP sent
// back in Content-Disposition — see `dispositionName`. This function is
// deliberately given no way to name a file itself: the sanitised name
// travels with the bytes, so there is no second string here to get
// wrong.
export const saveBlob = (d: Download) => {
  const url = URL.createObjectURL(d.blob)
  const a = document.createElement('a')
  a.href = url
  a.download = d.name || 'attachment'
  document.body.appendChild(a)
  a.click()
  a.remove()
  // Revoked on a turn of its own: revoking synchronously races the
  // click in some browsers and the download arrives empty.
  setTimeout(() => URL.revokeObjectURL(url), 30_000)
}

// The escape hatch for a thread frozen at a capacity limit, and the only
// way to remove anything from the tree short of culling it by hand. The
// writer gates this on the poke's source being us, so it is local-only.
export const deleteThread = (id: string) =>
  post('/api/delete-thread', { 'thread-id': id })

// One request for the whole batch. Opening a thread marks every unread
// message in it, and the nexus writer is the ship's single serialisation
// point for mail: one id per request meant one writer event and one full
// mailbox scan per message. An empty list is not sent at all.
export const markRead = (ids: string[]) =>
  ids.length === 0
    ? Promise.resolve()
    : post('/api/read', { 'msg-ids': ids }).then(() => undefined)

// Grubbery's own keep-SSE endpoint for one nexus grub. The nexus bumps
// /beacon/rev on every mutation EXCEPT a read-mark, so this stream is
// "something a reader can see has changed" and nothing else. Opening a
// thread marks several messages read at once; if those bumped the beacon
// this subscription would refetch the thread, which would mark it read
// again, forever.
const BEACON = '/grubbery/api/keep/apps/auspex.auspex_app/beacon/rev'

// Retry policy, and it is not a detail. A FIXED delay is what this had,
// and a fixed delay is the shape that saturated ~ricsul-bilwyt for most of
// a day on 2026-09-09: a pier restart drops every client at the same
// instant, so they all come back on the same tick, for ever, while the
// ship is least able to answer. A ship runs its events one at a time, so a
// handful of clients on a timer can consume the whole thing while every
// metric you would check looks healthy. So: double to a cap, and jitter,
// which is what breaks up a synchronised herd.
//
// The reset rule is the subtle half. Resetting whenever an attempt
// REGISTERED would mean a ship that accepts a connection and drops it at
// once never backs off at all, because registration is the first thing
// that happens. So the reset is on DURATION: a stream that held for
// LIVED_MS was a working one whose keep expired on schedule, and the next
// attempt starts from the floor. Anything shorter is a failure, whatever
// it managed to send first.
const RETRY_MIN_MS = 3_000
const RETRY_MAX_MS = 30_000
const LIVED_MS = 10_000
const jitter = (ms: number) => Math.round(ms * (0.5 + Math.random()))

// Subscribe to that stream. Returns a teardown.
//
// `onResume` is called when the tab comes back from hidden, where the
// stream was deliberately not held: whatever changed in the meantime
// arrived on a connection nobody was reading, so the caller catches up
// once. It is the full refresh; `onEvent` is the cheap one.
//
// EventSource cannot set an Accept header and grubbery keys the SSE
// response off it, so this is a plain fetch whose body is read as a
// stream — the same shape lattice's live-view script uses. The stream
// carries the whole /beacon directory, hence the ' /rev' filter, and the
// first event ('old ...') is the current value rather than a change, so
// acting on it would refetch everything on every mount.
export const subscribeChanges = (onEvent: () => void, onResume?: () => void) => {
  let stopped = false
  let ac: AbortController | null = null
  let wait = RETRY_MIN_MS

  const hidden = () => typeof document !== 'undefined' && document.hidden

  // A HIDDEN TAB HOLDS NOTHING. Vere serves HTTP/1.1 and browsers cap
  // about six connections per origin, so a parked tab's held stream is a
  // connection the tab you are actually looking at cannot have. Lattice
  // drops its stream while hidden for exactly this reason. Coming back
  // costs one request, and the catch-up is `onResume` — which also covers
  // the one failure a stream can never report: a connection that dies
  // silently, with no FIN and no error, leaving the reader blocked for
  // ever. A NAT timeout or a closed laptop lid is the realistic trigger.
  const onVis = () => { if (document.hidden) ac?.abort() }
  if (typeof document !== 'undefined') document.addEventListener('visibilitychange', onVis)

  const untilVisible = () => new Promise<void>((r) => {
    const wake = () => {
      if (document.hidden) return
      document.removeEventListener('visibilitychange', wake)
      r()
    }
    document.addEventListener('visibilitychange', wake)
  })

  const read = async () => {
    while (!stopped) {
      if (hidden()) {
        await untilVisible()
        if (stopped) return
        onResume?.()
        wait = RETRY_MIN_MS
      }
      const began = Date.now()
      ac = new AbortController()
      try {
        const res = await fetch(BEACON, {
          headers: { accept: 'text/event-stream' },
          signal: ac.signal,
        })
        if (!res.ok || !res.body) throw new Error(`beacon ${res.status}`)
        const reader = res.body.getReader()
        const dec = new TextDecoder()
        let buf = ''
        for (;;) {
          const { done, value } = await reader.read()
          if (done) break
          buf += dec.decode(value, { stream: true })
          const frames = buf.split('\n\n')
          // The trailing element is a partial frame, not a whole one.
          buf = frames.pop() ?? ''
          for (const f of frames) {
            const ev = f.split('\n').find((l) => l.startsWith('event: '))?.slice(7)
            // `old …` is the current revision replayed at registration,
            // not a change. Ignoring it is what makes a reconnect cost
            // exactly one request and do no work.
            if (ev && ev.endsWith(' /rev') && !ev.startsWith('old')) onEvent()
          }
        }
      } catch {
        // A dropped stream is normal (a ship bounce, a sleeping laptop, a
        // tab going hidden). Retry rather than going quiet: the
        // alternative is a tab that looks live and is not. There is no
        // staleness watchdog here and there must not be one — a healthy
        // connection to a quiet ship sends nothing for minutes, so a
        // watchdog fires on connections that are perfectly fine, and each
        // firing costs a reconnect the ship pays for.
      }
      if (stopped) return
      const lived = Date.now() - began >= LIVED_MS
      if (lived) wait = RETRY_MIN_MS
      // Hidden: no sleep, because the loop parks on visibility at the top.
      if (!hidden()) await new Promise((r) => setTimeout(r, jitter(wait)))
      if (!lived) wait = Math.min(wait * 2, RETRY_MAX_MS)
    }
  }

  read()
  return () => {
    stopped = true
    ac?.abort()
    if (typeof document !== 'undefined') document.removeEventListener('visibilitychange', onVis)
  }
}

// ── the mail-client layer ───────────────────────────────────────────
//
// Everything below is LOCAL STATE. None of it is signed, none of it
// travels, and two ships holding the same thread may disagree about all
// of it. That is the whole reason `unsigned` could be frozen: every
// feature here is a decision about the right-hand column.

// A view is a predicate over the one listing walk, not a stored set.
// Inbox is "we are a participant OR the chain arrived direct" and not
// archived; Sent is authorship; Archived is the flag; a label is the
// label. Drafts is a different shape entirely and has its own route,
// because a draft has no sender, no verdict and no participants and
// inventing them is exactly the confusion drafts are kept out of the
// thread tree to prevent.
export type View = 'inbox' | 'sent' | 'archived' | 'all' | 'label'

// The listing response. `total` counts the whole view, `threads` is one
// page of it, so the UI can render controls without fetching everything.
export interface Page {
  total: number
  offset: number
  limit: number
  view: string
  threads: InboxEntry[]
}

export interface Draft {
  id: string
  to: string[]
  subj: string
  body: string
  prev: string | null
  at: number
}

export interface Rule {
  id: string
  from: string | null
  subject: string | null
  add: string[]
  archive: boolean
}

// One mailing list: a name and the ships in it.
//
// LOCAL AND UNSIGNED, exactly like a Rule and a Draft. A list name never
// travels — the nexus stores it as the path segment and there is no
// field for it in the grub — so nothing downstream of the composer knows
// lists exist: a send, a draft, the recipient validation and the
// blast-radius line all see ships.
export interface MailList {
  name: string
  members: string[]
}

// A @p, checked in the browser before the poke.
//
// The nexus keeps its own validation - this is a convenience, never the
// boundary - but a typo caught at the keystroke is a typo the user can
// fix, and the same typo surfacing as a refusal from a route that
// already answered ok is not. Deliberately structural rather than a
// dictionary of syllables: the client does not carry the syllable
// tables, and a name that is shaped wrong is the mistake people
// actually make.
const SYL = '(?:[a-z]{6}|[a-z]{3})'
const SHIP_RE = new RegExp(`^~(?:${SYL}(?:-${SYL})*)$`)

// The four ship classes, by how many hyphen-separated groups they
// render as: galaxy and star are one, planet two, moon four, comet
// eight. Nothing else is a ship, and "even" is not the rule — six, ten
// and twelve are even and none of them names anything.
const GROUPS = new Set([1, 2, 4, 8])

export const isShip = (s: string): boolean => {
  if (!SHIP_RE.test(s)) return false
  const parts = s.slice(1).split('-')
  if (!GROUPS.has(parts.length)) return false
  // A three-letter group is a galaxy, and a galaxy is the WHOLE name.
  // Without this ~zod-zod passes: two groups is a valid count, and the
  // pattern allows three letters per group, so the two rules apart admit
  // a name that @p never renders.
  return parts.length === 1 || parts.every((p) => p.length === 6)
}

export const pageOf = (
  view: View,
  opts: { label?: string; q?: string; offset?: number; limit?: number } = {},
) => {
  const p = new URLSearchParams({ view })
  if (opts.label) p.set('label', opts.label)
  if (opts.q) p.set('q', opts.q)
  if (opts.offset) p.set('offset', String(opts.offset))
  if (opts.limit) p.set('limit', String(opts.limit))
  return get<Page>(`/api/inbox?${p.toString()}`, true)
}

// Local state, so none of these move the change beacon: they alter a
// thread in ways no other ship can see, and a bump would cost every open
// tab a full listing plus a thread refetch for a change it cannot
// observe. The caller refreshes what it changed.
export const setLabel = (threadId: string, label: string, add: boolean) =>
  post('/api/label', { 'thread-id': threadId, label, add })

export const setArchived = (threadId: string, archived: boolean) =>
  post('/api/archive', { 'thread-id': threadId, archived })

export const markUnread = (ids: string[]) =>
  ids.length === 0 ? Promise.resolve() : post('/api/unread', { 'msg-ids': ids })

export const drafts = () => get<Draft[]>('/api/drafts')

// The id is minted HERE. A draft id is local, means nothing on any other
// ship and never appears in a signature; the route answers as soon as
// the writer takes the poke, so a server-minted id could never be told
// to the client that needs it to save the same draft again.
export const newId = (): string => {
  const b = new Uint8Array(15)
  crypto.getRandomValues(b)
  // @uv is base-32 over 0-9a-v, rendered in dot-separated groups of five
  // after a leading group. Five random digits per group is plenty for an
  // id that only has to be unique within one ship's drafts.
  const d = '0123456789abcdefghijklmnopqrstuv'
  const g = (n: number) => [...b.slice(n, n + 5)].map((x) => d[x % 32]).join('')
  return `0v${g(0)}.${g(5)}.${g(10)}`
}

export const saveDraft = (d: Omit<Draft, 'at'>) =>
  post('/api/draft', { id: d.id, to: d.to, subj: d.subj, body: d.body, prev: d.prev })

export const deleteDraft = (id: string) => post('/api/draft-delete', { id })

// Signs it at this moment and deletes it. A refused send leaves the
// draft where it was - the nexus gates the delete on the send actually
// having happened, so a message is never destroyed at the moment the
// ship declines to carry it.
export const sendDraft = (id: string) => post('/api/draft-send', { id })

export const rules = () => get<Rule[]>('/api/rules')

export const saveRule = (r: Rule) => post('/api/rule', r)

export const deleteRule = (id: string) => post('/api/rule-delete', { id })

export const lists = () => get<MailList[]>('/api/lists')

// ONE VERB. Create, overwrite, add a member, drop one, rename by saving
// under a new name, and copy the membership off a message are all this
// call, because a list is a name and a set of ships and there is nothing
// else in it to do. No tracking and no merge: the ship stores exactly
// the set sent.
//
// A list write does not move the change beacon — no other reader can
// observe it — so the caller refetches its own listing, as the filter
// panel does.
export const saveList = (l: MailList) =>
  post('/api/list', { name: l.name, members: l.members })

export const deleteList = (name: string) => post('/api/list-delete', { name })

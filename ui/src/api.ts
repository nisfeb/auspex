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
}

// Everything below is a same-origin fetch under one prefix.
//
// The nexus binds /apps/urmail and answers a small JSON API beneath it,
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
const BASE = '/apps/urmail'

class ApiError extends Error {
  status: number
  constructor(status: number, message: string) {
    super(message)
    this.status = status
  }
}

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

const get = async <T>(path: string): Promise<T> =>
  await jsonOf(await fetch(`${BASE}${path}`, {
    headers: { accept: 'application/json' },
  })) as T

const post = async (path: string, body: unknown): Promise<void> => {
  await jsonOf(await fetch(`${BASE}${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  }))
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

export const whoami = async () => {
  const { ship } = await get<{ ship: string }>('/api/whoami')
  ourShip = ship
}

export const inbox = () => get<InboxEntry[]>('/api/inbox')

// A deleted (or never-known) thread is a 404, which is the honest status
// for it, and the view already distinguishes "no longer exists" from a
// failed load. Map only that one code to null; every other failure stays
// an exception so it reads as an error rather than as an empty thread.
export const thread = async (id: string): Promise<Thread | null> => {
  try {
    return await get<Thread>(`/api/thread/${id}`)
  } catch (e) {
    if (e instanceof ApiError && e.status === 404) return null
    throw e
  }
}

export const send = (
  to: string[],
  subject: string,
  body: string,
  prev: string | null,
) => post('/api/send', { to, subj: subject, body, prev })

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
const BEACON = '/grubbery/api/keep/apps/urmail.urmail_app/beacon/rev'

// Subscribe to that stream. Returns a teardown.
//
// EventSource cannot set an Accept header and grubbery keys the SSE
// response off it, so this is a plain fetch whose body is read as a
// stream — the same shape lattice's live-view script uses. The stream
// carries the whole /beacon directory, hence the ' /rev' filter, and the
// first event ('old ...') is the current value rather than a change, so
// acting on it would refetch everything on every mount.
export const subscribeChanges = (onChange: () => void) => {
  let stopped = false
  let ac: AbortController | null = null

  const read = async () => {
    while (!stopped) {
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
            if (ev && ev.endsWith(' /rev') && !ev.startsWith('old')) onChange()
          }
        }
      } catch {
        // A dropped stream is normal (a ship bounce, a sleeping laptop).
        // Retry rather than going quiet: the alternative is a tab that
        // looks live and is not.
      }
      if (stopped) return
      await new Promise((r) => setTimeout(r, 3000))
    }
  }

  read()
  return () => { stopped = true; ac?.abort() }
}

import Urbit from '@urbit/http-api'

export type Verdict = 'verified' | 'unverified' | 'forged'

export interface Message {
  id: string
  from: string
  to: string[]
  subject: string
  body: string
  sent: number
  prev: string | null
  verdict: Verdict
  read: boolean
}

export interface Thread {
  id: string
  messages: Message[]
  participants: string[]
  last: number
}

export interface InboxEntry {
  id: string
  subject: string
  from: string
  snippet: string
  count: number
  last: number
  unread: boolean
  participants: string[]
}

const api = new Urbit('', '', 'urmail')
// window.ship is injected by the ship's own index.html. Under `vite dev`
// we serve our own, so it is undefined and must be set explicitly.
api.ship = import.meta.env.VITE_SHIP ?? 'wex'

// NOTE: the on-peek paths in desk/app/urmail.hoon are `/x/inbox` and
// `/x/thread/<id>` (care %x, matching the brief). But @urbit/http-api's
// scry() builds the HTTP request as `/~/scry/{app}{path}.json`, and Eyre's
// `/~/scry/` endpoint already implies care %x — so a `path` that itself
// starts with `/x` double-prepends it and 404s ("no scry result").
// Verified against ~wex: `/~/scry/urmail/x/inbox.json` -> 404,
// `/~/scry/urmail/inbox.json` -> real inbox JSON. Omit the leading /x here.
export const inbox = () =>
  api.scry<InboxEntry[]>({ app: 'urmail', path: '/inbox' })

export const thread = (id: string) =>
  api.scry<Thread | null>({ app: 'urmail', path: `/thread/${id}` })

export const send = (
  to: string[],
  subject: string,
  body: string,
  prev: string | null,
) =>
  api.poke({
    app: 'urmail',
    mark: 'urmail-action',
    json: { send: { to, subj: subject, body, prev } },
  })

export const markRead = (id: string) =>
  api.poke({
    app: 'urmail',
    mark: 'urmail-action',
    json: { read: { 'msg-id': id } },
  })

export const unsubscribe = (id: number) => api.unsubscribe(id)

export const subscribeUpdates = (onThread: (id: string) => void) =>
  api.subscribe({
    app: 'urmail',
    path: '/updates',
    event: (u: { type: string; id: string }) => {
      if (u.type === 'thread') onThread(u.id)
    },
  })

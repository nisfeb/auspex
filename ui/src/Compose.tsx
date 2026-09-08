import { useState } from 'react'
import { send } from './api'

// What a Forward control hands the composer: the message the new message
// will point `prev` at, the subject to base the forwarded one on, and how
// many messages the chain currently holds.
//
// Deliberately NOT a recipient list. A forward is the one case the spec
// calls out as going to "someone new", so seeding the To field from the
// thread's `participants` would be the Critical finding this project
// already fixed once, in its most dangerous form: shipping an entire
// signed conversation to an audience the user never looked at, at the
// moment they meant to hand it to one new person. The field starts empty
// and stays empty until a human types into it.
export interface ForwardIntent {
  prev: string
  subject: string
  // DISTINCT MESSAGES ON THE PATH from the thread root down to `prev`,
  // which is exactly what the nexus ships. Not the thread's message
  // count, which would include sibling branches that no longer travel,
  // and not the stored-copy count, which counts one message several
  // times when copies differ in signature.
  count: number
}

export default function Compose({
  onClose, onSent, forward,
}: {
  onClose: () => void
  onSent: () => void
  forward?: ForwardIntent | null
}) {
  const [to, setTo] = useState('')
  const [subject, setSubject] = useState(forward ? `fwd: ${forward.subject}` : '')
  const [body, setBody] = useState('')
  const [sending, setSending] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const onSend = async () => {
    setSending(true)
    setError(null)
    try {
      const ships = to.split(',').map((s) => s.trim()).filter(Boolean)
      // `prev` is the only thing that makes this a forward rather than a
      // compose. The nexus resolves it to its containing thread and ships
      // that whole chain; there is no separate forward action.
      await send(ships, subject, body, forward ? forward.prev : null)
      onSent()
    } catch (e) {
      // Leave the panel open with the draft intact — a failed send (an
      // unreachable ship, a malformed @p the route's parser rejects)
      // should not look identical to a successful one.
      console.error(e)
      setError('Could not send. Check the recipient and try again.')
    } finally {
      setSending(false)
    }
  }

  return (
    <div className="fixed bottom-0 right-8 w-[32rem] rounded-t-lg border border-neutral-300 bg-white shadow-2xl">
      <header className="flex items-center justify-between bg-neutral-800 px-4 py-2 text-sm text-white">
        {forward ? 'Forward' : 'New message'}
        <button onClick={onClose} aria-label="Close">×</button>
      </header>
      <div className="p-4">
        {/* Forwarding transfers evidence rather than quoting text: the
            recipient gets every message on the path, each still signed
            by whoever wrote it, and can check those signatures without
            ever having spoken to those ships. That is the feature — and
            it is also part of the conversation leaving the room, so it
            is stated before the To field rather than after the Send
            button.

            What travels is the ROOT-TO-HERE PATH, not the thread. A
            thread branches wherever two people reply to the same
            message, and sibling branches do not travel — so this counts
            the messages on the path and says so, rather than counting
            the thread. `count` is distinct messages, never stored
            copies: several copies of one message differing in signature
            are one message here. */}
        {forward && (
          <p className="mb-3 rounded bg-amber-50 p-3 text-xs text-amber-900 ring-1 ring-amber-200">
            This sends the <strong>signed chain leading to this message</strong> —
            {' '}the {forward.count} {forward.count === 1 ? 'message' : 'messages'} from
            the start of “{forward.subject}” down to it, not just the latest one.
            Other branches of the conversation do not travel. Whoever you name below
            can read every message on that path and can verify for themselves who
            wrote each one. Nobody is on this list yet; add only the people who
            should get that history.
          </p>
        )}
        <input
          value={to} onChange={(e) => setTo(e.target.value)}
          placeholder="~sampel-palnet, ~palnet-sampel"
          aria-label={forward ? 'Forward to' : 'To'}
          className="mb-2 w-full border-b border-neutral-200 py-2 text-sm outline-none"
        />
        <input
          value={subject} onChange={(e) => setSubject(e.target.value)}
          maxLength={1000}
          placeholder="Subject"
          className="mb-2 w-full border-b border-neutral-200 py-2 text-sm outline-none"
        />
        {/* The writer rejects a body over max-body (100,000 bytes) or a
            subject over max-subj (1,000) at compose time, and every send
            ships the whole accumulated chain, so an oversized message
            would otherwise be a send that just fails. These caps count
            UTF-16 units rather than bytes, so they are a guard rail, not
            the authority - the nexus stays the authority. */}
        <textarea
          value={body} onChange={(e) => setBody(e.target.value)}
          maxLength={100000}
          placeholder={forward ? 'Add a note (optional)' : undefined}
          className="h-56 w-full resize-none py-2 text-sm outline-none"
        />
        <div className="flex items-center gap-3">
          <button
            onClick={onSend}
            disabled={!to.trim() || sending}
            className="rounded-full bg-blue-600 px-6 py-2 text-white disabled:opacity-40"
          >
            {sending ? 'Sending…' : forward ? 'Forward' : 'Send'}
          </button>
          {error && <span className="text-sm text-red-600">{error}</span>}
        </div>
      </div>
    </div>
  )
}

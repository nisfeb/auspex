import { useEffect, useRef, useState } from 'react'
import { thread, send, markRead, type Thread } from './api'
import VerdictBadge from './VerdictBadge'

export default function ThreadView({
  id, onSent, updatedAt,
}: {
  id: string
  onSent: () => void
  // Set by App when a /updates push names this thread's id. An opaque,
  // monotonically increasing value (not a timestamp) that only changes
  // for the thread currently open, so it is safe as an effect dependency:
  // it triggers exactly the refetches that matter, not one per push for
  // every thread.
  updatedAt?: number | null
}) {
  const [t, setT] = useState<Thread | null>(null)
  const [notFound, setNotFound] = useState(false)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [reply, setReply] = useState('')
  const [sending, setSending] = useState(false)
  const [sendError, setSendError] = useState<string | null>(null)

  // Tracks the id the effect below most recently committed to, so
  // onReply's post-send refetch (see below) can tell whether the user has
  // since navigated to a different thread. Updated synchronously inside
  // the effect, before any async work, so it's always current by the time
  // any later promise resolves.
  const idRef = useRef(id)

  // The stale-thread race: click thread A, then click B before A's scry
  // resolves. React runs A's effect cleanup and B's effect setup back to
  // back, synchronously, with no microtask in between — so a *hoisted*
  // ref re-armed at the top of every invocation is reset to "not stale"
  // by B's setup before A's in-flight network response ever lands, and
  // does nothing to stop it. The guard has to be a variable owned by the
  // one invocation whose request it guards, which only a fresh `let`
  // inside the effect provides (each call gets its own closure; nothing
  // later can reach in and reset it) - the same reason `App.tsx`'s
  // subscription cleanup uses a per-invocation `cancelled`, not a ref.
  useEffect(() => {
    let cancelled = false
    idRef.current = id
    setT(null)
    setNotFound(false)
    setLoadError(null)
    setSendError(null)
    thread(id).then((th) => {
      if (cancelled) return
      if (th === null) {
        setNotFound(true)
        return
      }
      setT(th)
      th.messages.filter((m) => !m.read).forEach((m) => markRead(m.id).catch(console.error))
    }).catch((e) => {
      if (cancelled) return
      console.error(e)
      setLoadError('Could not load this conversation.')
    })
    return () => { cancelled = true }
  }, [id, updatedAt])

  if (loadError) {
    return <p className="p-8 text-red-600">{loadError}</p>
  }
  if (notFound) {
    return <p className="p-8 text-neutral-400">This conversation no longer exists.</p>
  }
  if (!t) return null
  const last = t.messages[t.messages.length - 1]

  const onReply = async () => {
    const forId = id
    setSending(true)
    setSendError(null)
    // The send poke and the post-send refetch are different failures.
    // Only the poke failing means the reply wasn't sent - draft kept, and
    // safe to retry. If it succeeds but the refetch then fails, the reply
    // already went out; clearing the draft and saying so (not "could not
    // send") avoids the user resending a message that already landed.
    try {
      await send(t.participants, `re: ${last.subject}`, reply, last.id)
    } catch (e) {
      console.error(e)
      setSendError('Could not send that reply. Try again.')
      setSending(false)
      return
    }
    setReply('')
    onSent()
    try {
      const th = await thread(forId)
      if (idRef.current === forId && th !== null) setT(th)
    } catch (e) {
      console.error(e)
      setSendError('Sent, but could not refresh this view. Reload to see it.')
    }
    setSending(false)
  }

  return (
    <div className="p-8">
      <h1 className="mb-6 text-2xl">{t.messages[0].subject}</h1>
      {t.messages.map((m, i) => (
        // Up to 4 copies of a message share the same `id` by design (one
        // genuine, others forged) — index into the fixed, backend-ordered
        // list, not `m.id`, or React's key collision folds distinct
        // verified/forged copies into one node.
        <article key={i} className="mb-6 border-b border-neutral-100 pb-6">
          <header className="mb-2 flex items-center gap-3 text-sm">
            <span className="font-medium">{m.from}</span>
            <VerdictBadge verdict={m.verdict} />
            <span className="ml-auto text-neutral-400">
              {new Date(m.sent).toLocaleString()}
            </span>
          </header>
          <p className="whitespace-pre-wrap">{m.body}</p>
        </article>
      ))}
      <textarea
        value={reply}
        onChange={(e) => setReply(e.target.value)}
        placeholder="Reply"
        className="h-28 w-full rounded border border-neutral-300 p-3"
      />
      <div className="mt-2 flex items-center gap-3">
        <button
          onClick={onReply}
          disabled={!reply.trim() || sending}
          className="rounded-full bg-blue-600 px-6 py-2 text-white disabled:opacity-40"
        >
          {sending ? 'Sending…' : 'Send'}
        </button>
        {sendError && <span className="text-sm text-red-600">{sendError}</span>}
      </div>
    </div>
  )
}

import { useEffect, useState } from 'react'
import { thread, send, markRead, type Thread, type Verdict } from './api'

const badge: Record<Verdict, string> = {
  verified: 'bg-green-100 text-green-800',
  unverified: 'bg-neutral-100 text-neutral-600',
  forged: 'bg-red-100 text-red-800 ring-1 ring-red-600 font-semibold',
}

const label: Record<Verdict, string> = {
  verified: 'verified',
  unverified: 'unverified',
  forged: 'FORGED',
}

export default function ThreadView({ id, onSent }: { id: string; onSent: () => void }) {
  const [t, setT] = useState<Thread | null>(null)
  const [notFound, setNotFound] = useState(false)
  const [reply, setReply] = useState('')

  useEffect(() => {
    setT(null)
    setNotFound(false)
    thread(id).then((th) => {
      if (th === null) {
        setNotFound(true)
        return
      }
      setT(th)
      th.messages.filter((m) => !m.read).forEach((m) => markRead(m.id))
    }).catch(console.error)
  }, [id])

  if (notFound) {
    return <p className="p-8 text-neutral-400">This conversation no longer exists.</p>
  }
  if (!t) return null
  const last = t.messages[t.messages.length - 1]

  const onReply = async () => {
    await send(t.participants, `re: ${last.subject}`, reply, last.id)
    setReply('')
    onSent()
    thread(id).then((th) => { if (th !== null) setT(th) })
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
            <span className={`rounded px-2 py-0.5 text-xs ${badge[m.verdict]}`}>
              {label[m.verdict]}
            </span>
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
      <button
        onClick={onReply}
        disabled={!reply.trim()}
        className="mt-2 rounded-full bg-blue-600 px-6 py-2 text-white disabled:opacity-40"
      >
        Send
      </button>
    </div>
  )
}

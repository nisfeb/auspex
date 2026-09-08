import { useState } from 'react'
import { send } from './api'

export default function Compose({
  onClose, onSent,
}: { onClose: () => void; onSent: () => void }) {
  const [to, setTo] = useState('')
  const [subject, setSubject] = useState('')
  const [body, setBody] = useState('')
  const [sending, setSending] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const onSend = async () => {
    setSending(true)
    setError(null)
    try {
      const ships = to.split(',').map((s) => s.trim()).filter(Boolean)
      await send(ships, subject, body, null)
      onSent()
    } catch (e) {
      // Leave the panel open with the draft intact — a failed poke (an
      // unreachable ship, a malformed @p the mark's parser rejects) should
      // not look identical to a successful send.
      console.error(e)
      setError('Could not send. Check the recipient and try again.')
    } finally {
      setSending(false)
    }
  }

  return (
    <div className="fixed bottom-0 right-8 w-[32rem] rounded-t-lg border border-neutral-300 bg-white shadow-2xl">
      <header className="flex items-center justify-between bg-neutral-800 px-4 py-2 text-sm text-white">
        New message
        <button onClick={onClose} aria-label="Close">×</button>
      </header>
      <div className="p-4">
        <input
          value={to} onChange={(e) => setTo(e.target.value)}
          placeholder="~sampel-palnet, ~palnet-sampel"
          className="mb-2 w-full border-b border-neutral-200 py-2 text-sm outline-none"
        />
        <input
          value={subject} onChange={(e) => setSubject(e.target.value)}
          placeholder="Subject"
          className="mb-2 w-full border-b border-neutral-200 py-2 text-sm outline-none"
        />
        <textarea
          value={body} onChange={(e) => setBody(e.target.value)}
          className="h-56 w-full resize-none py-2 text-sm outline-none"
        />
        <div className="flex items-center gap-3">
          <button
            onClick={onSend}
            disabled={!to.trim() || sending}
            className="rounded-full bg-blue-600 px-6 py-2 text-white disabled:opacity-40"
          >
            {sending ? 'Sending…' : 'Send'}
          </button>
          {error && <span className="text-sm text-red-600">{error}</span>}
        </div>
      </div>
    </div>
  )
}

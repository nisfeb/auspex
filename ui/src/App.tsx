import { useEffect, useState, useCallback } from 'react'
import { inbox, subscribeUpdates, unsubscribe, type InboxEntry } from './api'
import ThreadList from './ThreadList'
import ThreadView from './ThreadView'
import Compose from './Compose'

export default function App() {
  const [entries, setEntries] = useState<InboxEntry[]>([])
  const [selected, setSelected] = useState<string | null>(null)
  const [composing, setComposing] = useState(false)

  const refresh = useCallback(() => {
    inbox().then(setEntries).catch(console.error)
  }, [])

  useEffect(() => {
    refresh()
    let id: number | null = null
    let cancelled = false
    subscribeUpdates(refresh).then((n) => {
      // If we already unmounted (or React StrictMode's dev-only double
      // effect already tore down this instance) before the subscribe
      // resolved, the cleanup below already ran with id still null — tear
      // this one down immediately instead of leaking an open channel.
      if (cancelled) { unsubscribe(n); return }
      id = n
    }).catch(console.error)
    return () => {
      cancelled = true
      if (id !== null) unsubscribe(id)
    }
  }, [refresh])

  return (
    <div className="flex h-screen bg-white text-neutral-900">
      <aside className="w-56 shrink-0 border-r border-neutral-200 p-4">
        <button
          onClick={() => setComposing(true)}
          className="w-full rounded-full bg-blue-600 px-6 py-3 text-white hover:bg-blue-700"
        >
          Compose
        </button>
        <nav className="mt-6 text-sm font-medium text-neutral-700">Inbox</nav>
      </aside>

      <ThreadList entries={entries} selected={selected} onSelect={setSelected} />

      <main className="flex-1 overflow-y-auto">
        {selected
          ? <ThreadView id={selected} onSent={refresh} />
          : <p className="p-8 text-neutral-400">Select a conversation</p>}
      </main>

      {composing && (
        <Compose
          onClose={() => setComposing(false)}
          onSent={() => { setComposing(false); refresh() }}
        />
      )}
    </div>
  )
}

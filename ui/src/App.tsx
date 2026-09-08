import { useEffect, useState, useCallback } from 'react'
import { inbox, subscribeUpdates, unsubscribe, type InboxEntry } from './api'
import ThreadList from './ThreadList'
import ThreadView from './ThreadView'
import Compose from './Compose'

export default function App() {
  const [entries, setEntries] = useState<InboxEntry[]>([])
  const [inboxError, setInboxError] = useState<string | null>(null)
  const [selected, setSelected] = useState<string | null>(null)
  const [composing, setComposing] = useState(false)
  // The most recent /updates push, so the open thread (if any) can react
  // to it. ThreadView compares the id against its own and only refetches
  // when they match, so one push never causes every thread to refetch.
  // `seq` is a monotonic counter, not Date.now(): two pushes for the same
  // thread landing in the same millisecond (plausible with a batched
  // channel poll) would otherwise produce an identical `at`, so the
  // dependency comparison in ThreadView sees no change and silently drops
  // the second refetch. A counter is guaranteed distinct every call.
  const [threadUpdate, setThreadUpdate] = useState<{ id: string; seq: number } | null>(null)

  const refresh = useCallback(() => {
    inbox().then((es) => { setInboxError(null); setEntries(es) })
      .catch((e) => { console.error(e); setInboxError('Could not reach the ship.') })
  }, [])

  const onThreadUpdate = useCallback((threadId: string) => {
    refresh()
    setThreadUpdate((prev) => ({ id: threadId, seq: (prev?.seq ?? 0) + 1 }))
  }, [refresh])

  useEffect(() => {
    refresh()
    let id: number | null = null
    let cancelled = false
    subscribeUpdates(onThreadUpdate).then((n) => {
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
  }, [refresh, onThreadUpdate])

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

      <ThreadList entries={entries} error={inboxError} selected={selected} onSelect={setSelected} />

      <main className="flex-1 overflow-y-auto">
        {selected
          ? (
            <ThreadView
              id={selected}
              onSent={refresh}
              onDeleted={() => { setSelected(null); refresh() }}
              updatedAt={threadUpdate && threadUpdate.id === selected ? threadUpdate.seq : null}
            />
          )
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

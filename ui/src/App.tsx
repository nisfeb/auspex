import { useEffect, useState, useCallback } from 'react'
import { inbox, subscribeChanges, type InboxEntry } from './api'
import ThreadList from './ThreadList'
import ThreadView from './ThreadView'
import Compose, { type ForwardIntent } from './Compose'

export default function App() {
  const [entries, setEntries] = useState<InboxEntry[]>([])
  const [inboxError, setInboxError] = useState<string | null>(null)
  const [selected, setSelected] = useState<string | null>(null)
  const [composing, setComposing] = useState(false)
  // Non-null while the composer is open as a forward. Held here rather
  // than in ThreadView so the forward composer is the same panel as the
  // compose one — one composer, one code path, one place where the
  // recipient list is built (from nothing).
  const [forwarding, setForwarding] = useState<ForwardIntent | null>(null)
  // Bumped once per change beacon event, so the open thread (if any) can
  // react to it. The beacon says THAT the tree changed, not which thread
  // changed — it is one small grub the nexus writes on every mutation —
  // so this refetches the open thread and nothing else. That is still one
  // refetch per change rather than one per thread, which is what the old
  // per-thread /updates push bought; a listing that is already refreshed
  // above does not need to know which row moved.
  //
  // A monotonic counter, not Date.now(): two events landing in the same
  // millisecond would produce an identical value, ThreadView's dependency
  // comparison would see no change, and the second refetch would be
  // silently dropped. A counter is guaranteed distinct every call.
  const [threadUpdate, setThreadUpdate] = useState<number | null>(null)

  const refresh = useCallback(() => {
    inbox().then((es) => { setInboxError(null); setEntries(es) })
      .catch((e) => { console.error(e); setInboxError('Could not reach the ship.') })
  }, [])

  const onChange = useCallback(() => {
    refresh()
    setThreadUpdate((prev) => (prev ?? 0) + 1)
  }, [refresh])

  useEffect(() => {
    refresh()
    // subscribeChanges is synchronous and hands back its own teardown, so
    // there is no window in which an unmount (or StrictMode's dev-only
    // double effect) can race an in-flight subscribe and leak a stream.
    return subscribeChanges(onChange)
  }, [refresh, onChange])

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
              onForward={(f) => { setComposing(false); setForwarding(f) }}
              updatedAt={threadUpdate}
            />
          )
          : <p className="p-8 text-neutral-400">Select a conversation</p>}
      </main>

      {(composing || forwarding) && (
        // Keyed so that hitting Forward while a blank compose is open
        // remounts the panel instead of retrofitting a `prev` onto a
        // draft whose subject and recipients were typed for something
        // else. The initial state of a forward composer is only correct
        // on mount.
        <Compose
          key={forwarding ? `forward:${forwarding.prev}` : 'compose'}
          forward={forwarding}
          onClose={() => { setComposing(false); setForwarding(null) }}
          onSent={() => { setComposing(false); setForwarding(null); refresh() }}
        />
      )}
    </div>
  )
}

import type { InboxEntry } from './api'
import VerdictBadge from './VerdictBadge'

// The rows only. The search box and the pager live in App, which owns
// the page this list is one screenful of — so the list never has to know
// what view produced it.
export default function ThreadList({
  entries, error, selected, onSelect,
}: {
  entries: InboxEntry[]
  // Distinct from an empty view: a failed fetch (unreachable ship) reads
  // differently than "nothing here", so the user can tell the two apart.
  error: string | null
  selected: string | null
  onSelect: (id: string) => void
}) {
  if (error) {
    return <div className="flex-1 p-4 text-sm text-red-600">{error}</div>
  }
  if (entries.length === 0) {
    return <div className="flex-1 p-4 text-sm text-neutral-400">Nothing here.</div>
  }
  return (
    <ul className="flex-1 overflow-y-auto">
      {entries.map((e) => (
        <li key={e.id}>
          <button
            onClick={() => onSelect(e.id)}
            className={`w-full border-b border-neutral-100 px-4 py-3 text-left hover:bg-neutral-50
              ${selected === e.id ? 'bg-blue-50' : ''}
              ${e.unread ? 'font-semibold' : ''}`}
          >
            <div className="flex items-center gap-2 text-sm">
              <span className="truncate">{e.from}</span>
              <VerdictBadge verdict={e.verdict} className="shrink-0" />
              {e.forged && e.verdict !== 'forged' && (
                <span
                  className="shrink-0 rounded px-2 py-0.5 text-xs text-red-700 ring-1 ring-red-300"
                  title="This conversation also holds at least one message whose signature failed. Open it to see which."
                >
                  + forged
                </span>
              )}
              {e.count > 1 && (
                <span
                  className="ml-auto shrink-0 text-neutral-400"
                  title={`${e.count} stored copies of this thread's messages, including any unverified or forged duplicates`}
                >
                  {e.count} copies
                </span>
              )}
            </div>
            {e.count === 0 && e.unreadable > 0 ? (
              /* A thread this ship cannot read a single message of. There
                 is no sender or subject to show without reading one, so
                 the row says what it actually knows. Dropping the row
                 instead would make the thread disappear from the listing
                 while its read state and its index entry survived. */
              <div className="truncate text-sm text-neutral-500 italic">
                {e.unreadable} unreadable {e.unreadable === 1 ? 'message' : 'messages'} —
                {' '}stored in an older format this ship cannot read
              </div>
            ) : (
              <>
                <div className="truncate text-sm">{e.subject}</div>
                <div className="truncate text-xs text-neutral-500">{e.snippet}</div>
              </>
            )}
            {/* Local state, shown on the row so a thread's filing is
                visible without opening it. Neither is signed and neither
                travels: another ship holding this conversation sees none
                of it. */}
            {(e.labels.length > 0 || e.archived) && (
              <div className="mt-1 flex flex-wrap items-center gap-1">
                {e.archived && (
                  <span className="rounded bg-neutral-100 px-2 py-0.5 text-xs text-neutral-500">
                    archived
                  </span>
                )}
                {e.labels.map((l) => (
                  <span
                    key={l}
                    className="rounded bg-blue-50 px-2 py-0.5 text-xs text-blue-800"
                  >
                    {l}
                  </span>
                ))}
              </div>
            )}
          </button>
        </li>
      ))}
    </ul>
  )
}

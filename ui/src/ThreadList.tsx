import type { InboxEntry } from './api'
import VerdictBadge from './VerdictBadge'

export default function ThreadList({
  entries, error, selected, onSelect,
}: {
  entries: InboxEntry[]
  // Distinct from an empty inbox: a failed fetch (unreachable ship) reads
  // differently than "no mail yet", so the user can tell the two apart.
  error: string | null
  selected: string | null
  onSelect: (id: string) => void
}) {
  if (error) {
    return (
      <div className="w-96 shrink-0 border-r border-neutral-200 p-4 text-sm text-red-600">
        {error}
      </div>
    )
  }
  if (entries.length === 0) {
    return (
      <div className="w-96 shrink-0 border-r border-neutral-200 p-4 text-sm text-neutral-400">
        No mail yet.
      </div>
    )
  }
  return (
    <ul className="w-96 shrink-0 overflow-y-auto border-r border-neutral-200">
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
            <div className="truncate text-sm">{e.subject}</div>
            <div className="truncate text-xs text-neutral-500">{e.snippet}</div>
          </button>
        </li>
      ))}
    </ul>
  )
}

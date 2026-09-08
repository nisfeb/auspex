import type { InboxEntry } from './api'

export default function ThreadList({
  entries, selected, onSelect,
}: {
  entries: InboxEntry[]
  selected: string | null
  onSelect: (id: string) => void
}) {
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
            <div className="flex justify-between text-sm">
              <span className="truncate">{e.from}</span>
              {e.count > 1 && (
                <span
                  className="text-neutral-400"
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

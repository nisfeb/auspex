import type { Draft } from './api'

// A DRAFT IS NOT A MESSAGE, and this list says so rather than assuming
// the reader knows. There is no sender line and no verdict badge here,
// because a draft has neither: nothing has been signed yet, and the
// moment of signing is the moment of sending.
export default function Drafts({
  drafts, onOpen, onDelete,
}: {
  drafts: Draft[]
  onOpen: (d: Draft) => void
  onDelete: (id: string) => void
}) {
  if (drafts.length === 0) {
    return (
      <div className="w-96 shrink-0 border-r border-neutral-200 p-4 text-sm text-neutral-400">
        No drafts.
      </div>
    )
  }
  return (
    <ul className="w-96 shrink-0 overflow-y-auto border-r border-neutral-200">
      {drafts.map((d) => (
        <li key={d.id} className="flex items-start gap-1 border-b border-neutral-100">
          <button
            type="button"
            onClick={() => onOpen(d)}
            className="flex-1 px-4 py-3 text-left hover:bg-neutral-50"
          >
            <div className="truncate text-sm">
              {d.subj || <span className="text-neutral-400">(no subject)</span>}
            </div>
            <div className="truncate text-xs text-neutral-500">
              {d.to.length ? `to ${d.to.join(', ')}` : 'no recipients yet'}
            </div>
            <div className="truncate text-xs text-neutral-400">{d.body}</div>
          </button>
          <button
            type="button"
            onClick={() => onDelete(d.id)}
            aria-label={`Delete draft ${d.subj || '(no subject)'}`}
            title="Delete this draft. Nothing was ever signed, so nothing is lost but the text."
            className="px-3 py-3 text-neutral-400 hover:text-red-600"
          >
            ×
          </button>
        </li>
      ))}
    </ul>
  )
}

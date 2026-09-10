import type { Draft } from './api'
import Loading from './Loading'

// A DRAFT IS NOT A MESSAGE, and this list says so rather than assuming
// the reader knows. There is no sender line and no verdict badge here,
// because a draft has neither: nothing has been signed yet, and the
// moment of signing is the moment of sending.
//
// The frame — the column width, the border, the scroll — belongs to the
// pane in App, which is the one that also holds the thread list. Two
// components each declaring the same width is two places to change it
// and one place to forget.
export default function Drafts({
  drafts, loading, onOpen, onDelete,
}: {
  drafts: Draft[]
  // Drafts are fetched with the sidebar, once, so this pane opened on
  // "No drafts." for as long as that took — a lie about the one folder
  // whose whole point is that it holds work in progress.
  loading: boolean
  onOpen: (d: Draft) => void
  onDelete: (id: string) => void
}) {
  if (drafts.length === 0) {
    if (loading) return <Loading />
    return <div className="flex-1 p-3 text-ink-faint">No drafts.</div>
  }
  return (
    <ul className="min-h-0 flex-1 overflow-y-auto">
      {drafts.map((d) => (
        <li key={d.id} className="flex items-center border-b border-line">
          <button
            type="button"
            onClick={() => onOpen(d)}
            className="touch flex min-w-0 flex-1 items-center gap-2 px-2 py-1 text-left hover:bg-sunken"
          >
            <span className="w-24 shrink-0 truncate text-ink-faint md:w-32">
              {d.to.length ? d.to.join(', ') : 'no recipients yet'}
            </span>
            <span className="flex min-w-0 flex-1 items-center gap-1.5">
              <span className="truncate text-ink">
                {d.subj || <span className="text-ink-faint">(no subject)</span>}
              </span>
              <span className="truncate text-ink-faint">{d.body}</span>
            </span>
          </button>
          <button
            type="button"
            onClick={() => onDelete(d.id)}
            aria-label={`Delete draft ${d.subj || '(no subject)'}`}
            title="Delete this draft. Nothing was ever signed, so nothing is lost but the text."
            className="btn btn-danger shrink-0"
          >
            ×
          </button>
        </li>
      ))}
    </ul>
  )
}

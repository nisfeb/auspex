import type { View } from './api'

// The views, and the one rule that shapes this whole panel: a FOLDER IS
// A LABEL. Inbox, Sent, Archived and Drafts are the four views that are
// not labels, and every other folder in this list is one. There is no
// second taxonomy anywhere in the product, because two would eventually
// disagree about where a thread is and the disagreement would be
// invisible.
const FIXED: { view: View; name: string; hint: string }[] = [
  {
    view: 'inbox',
    name: 'Inbox',
    hint: 'Threads you are part of, or that were delivered here — a blind copy is'
      + ' in neither the sender nor the recipient list, so it is the delivery that'
      + ' puts it in your inbox. Archived threads are not shown.',
  },
  {
    view: 'sent',
    name: 'Sent',
    hint: 'Threads holding a message you signed.',
  },
  {
    view: 'archived',
    name: 'Archived',
    hint: 'Out of the inbox and nowhere else: still stored, still searchable,'
      + ' and a new message arriving in one brings it back.',
  },
  { view: 'all', name: 'All mail', hint: 'Everything stored on this ship.' },
]

export default function Sidebar({
  view, label, labels, drafts, rules, counts, onView, onCompose, onFilters,
}: {
  view: View | 'drafts' | 'rules'
  label: string
  labels: string[]
  drafts: number
  rules: number
  counts: Record<string, number>
  onView: (v: View | 'drafts' | 'rules', label?: string) => void
  onCompose: () => void
  onFilters: () => void
}) {
  const row = (
    active: boolean, name: string, hint: string, n: number | null, onClick: () => void,
  ) => (
    <button
      key={name}
      type="button"
      onClick={onClick}
      title={hint}
      className={`flex w-full items-center gap-2 rounded-r-full px-4 py-2 text-left text-sm
        ${active ? 'bg-blue-100 font-semibold text-blue-900' : 'hover:bg-neutral-100'}`}
    >
      <span className="truncate">{name}</span>
      {n !== null && n > 0 && (
        <span className="ml-auto shrink-0 text-xs text-neutral-500">{n}</span>
      )}
    </button>
  )

  return (
    <aside className="flex w-56 shrink-0 flex-col border-r border-neutral-200 py-4">
      <div className="px-4">
        <button
          onClick={onCompose}
          className="w-full rounded-full bg-blue-600 px-6 py-3 text-white hover:bg-blue-700"
        >
          Compose
        </button>
      </div>

      <nav className="mt-6 flex-1 overflow-y-auto pr-2">
        {FIXED.map((f) =>
          row(view === f.view, f.name, f.hint, counts[f.view] ?? null,
            () => onView(f.view)))}
        {row(
          view === 'drafts',
          'Drafts',
          'Messages you have written and not sent. A draft is not signed and is not'
          + ' a message; sending one signs it at that moment.',
          drafts,
          () => onView('drafts'),
        )}

        {labels.length > 0 && (
          <p className="mt-4 px-4 text-xs uppercase tracking-wide text-neutral-400">
            Labels
          </p>
        )}
        {labels.map((l) =>
          row(view === 'label' && label === l, l,
            `Threads you have labelled ${l}. A label is local: it never travels and`
            + ' no other ship can see it.',
            null, () => onView('label', l)))}
      </nav>

      <div className="border-t border-neutral-200 px-4 pt-3">
        <button
          type="button"
          onClick={onFilters}
          title="Rules applied to mail as it arrives. A filter may add labels and
            archive; it can never delete a message, mark one read, or hide one whose
            signature failed."
          className="text-sm text-neutral-500 hover:text-blue-700"
        >
          Filters{rules > 0 ? ` (${rules})` : ''}
        </button>
      </div>
    </aside>
  )
}

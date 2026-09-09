import type { View } from './api'

// The views, and the one rule that shapes this whole panel: a FOLDER IS
// A LABEL. Inbox, Sent, Archived and Drafts are the four views that are
// not labels, and every other folder in this list is one. There is no
// second taxonomy anywhere in the product, because two would eventually
// disagree about where a thread is and the disagreement would be
// invisible.
//
// ALL MAIL IS NOT IN THIS LIST, and its absence is deliberate. `all`
// still exists as an API primitive and two things depend on it: a search
// runs against it, so a query escapes whatever pane it was typed in, and
// the label list below is derived from it, so a label exists exactly as
// long as some thread carries it. What it is not is a place to go. A
// folder holding every message that has ever arrived, sorted by a field
// the sender chooses, is not a view of anything — it is the absence of
// one, and its only real use was as a search that had already been run.
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
]

export default function Sidebar({
  view, label, labels, drafts, rules, counts, onView, onCompose, onFilters,
  theme, onTheme, installable, onInstall,
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
  theme: 'light' | 'dark'
  onTheme: () => void
  // Only true once the browser has actually offered the prompt. There is
  // no way to install on demand and no way to ask whether one is
  // installed, so a permanent "Install" entry would be a button that
  // does nothing on every browser that never fires the event.
  installable: boolean
  onInstall: () => void
}) {
  const row = (
    active: boolean, name: string, hint: string, n: number | null, onClick: () => void,
  ) => (
    <button
      key={name}
      type="button"
      onClick={onClick}
      title={hint}
      className={`touch flex w-full items-center gap-2 rounded-sm px-3 py-1 text-left
        ${active
          ? 'bg-accent-soft font-medium text-accent-soft-ink'
          : 'text-ink-dim hover:bg-sunken hover:text-ink'}`}
    >
      <span className="truncate">{name}</span>
      {n !== null && n > 0 && (
        <span className="ml-auto shrink-0 text-[11px] text-ink-faint">{n}</span>
      )}
    </button>
  )

  return (
    <aside className="flex h-full w-full flex-col border-r border-line bg-surface py-2 md:w-52">
      <div className="px-2">
        <button onClick={onCompose} className="btn btn-primary w-full">
          Compose
        </button>
      </div>

      <nav className="mt-2 min-h-0 flex-1 overflow-y-auto px-1">
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
          <p className="mt-3 px-3 pb-1 text-[11px] uppercase tracking-wide text-ink-faint">
            Labels
          </p>
        )}
        {labels.map((l) =>
          row(view === 'label' && label === l, l,
            `Threads you have labelled ${l}. A label is local: it never travels and`
            + ' no other ship can see it.',
            null, () => onView('label', l)))}
      </nav>

      <div className="flex flex-col items-start gap-0.5 border-t border-line px-1 pt-2">
        <button
          type="button"
          onClick={onFilters}
          title="Rules applied to mail as it arrives. A filter may add labels and
            archive; it can never delete a message, mark one read, or hide one whose
            signature failed."
          className="btn touch w-full justify-start"
        >
          Filters{rules > 0 ? ` (${rules})` : ''}
        </button>
        <button
          type="button"
          onClick={onTheme}
          aria-label={theme === 'dark' ? 'Switch to the light theme' : 'Switch to the dark theme'}
          title="Light or dark. Your choice is remembered in this browser; without one,
            urmail follows the theme your system asks for."
          className="btn touch w-full justify-start"
        >
          {theme === 'dark' ? 'Light theme' : 'Dark theme'}
        </button>
        {installable && (
          <button
            type="button"
            onClick={onInstall}
            title="Install urmail as an app on this device. It opens in its own window
              and, thanks to its service worker, starts and shows cached mail even
              when the ship is unreachable."
            className="btn touch w-full justify-start"
          >
            Install
          </button>
        )}
      </div>
    </aside>
  )
}

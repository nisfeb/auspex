import type { InboxEntry } from './api'
import VerdictBadge from './VerdictBadge'

// A date in the width a list row can spare. Today is a time, this year
// is a day and a month, anything older is a year — the same ladder every
// mail client uses, for the same reason: a full timestamp on every row
// is a column of noise, and the exact one is on the message.
const when = (ms: number): string => {
  const d = new Date(ms)
  const now = new Date()
  if (d.toDateString() === now.toDateString()) {
    return d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })
  }
  if (d.getFullYear() === now.getFullYear()) {
    return d.toLocaleDateString([], { month: 'short', day: 'numeric' })
  }
  return String(d.getFullYear())
}

// The rows only. The search box and the pager live in App, which owns
// the page this list is one screenful of — so the list never has to know
// what view produced it.
//
// ONE LINE PER THREAD. Everything on a row is on the same line and every
// variable-length field truncates, so a row's height does not depend on
// its content — which is what makes a list scannable, and also what
// stops a sender-chosen subject or ship name from deciding the layout.
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
    return <div className="flex-1 p-3 text-danger">{error}</div>
  }
  if (entries.length === 0) {
    return <div className="flex-1 p-3 text-ink-faint">Nothing here.</div>
  }
  return (
    <ul className="min-h-0 flex-1 overflow-y-auto">
      {entries.map((e) => (
        <li key={e.id}>
          <button
            onClick={() => onSelect(e.id)}
            className={`touch flex w-full items-center gap-2 border-b border-line px-2 py-1
              text-left hover:bg-sunken
              ${selected === e.id ? 'bg-accent-soft' : ''}
              ${e.unread ? 'font-semibold text-ink' : 'text-ink-dim'}`}
          >
            {/* A STRAIGHT SCAN COLUMN. Two of the verdicts are a glyph
                and the third is a stamped word, so an unpadded slot
                pushed the sender and subject of a forged row sideways
                — nudging the one row a reader must be able to find by
                running an eye down a straight edge. `min-w` on the slot
                and nothing on the mark: the gutter gets wider, `forged`
                is exactly as loud as it was. */}
            <span className="flex min-w-14 shrink-0 items-center">
              <VerdictBadge verdict={e.verdict} from={e.from} />
            </span>
            <span className="w-24 shrink-0 truncate md:w-32">{e.from}</span>
            {e.count === 0 && e.unreadable > 0 ? (
              /* A thread this ship cannot read a single message of. There
                 is no sender or subject to show without reading one, so
                 the row says what it actually knows. Dropping the row
                 instead would make the thread disappear from the listing
                 while its read state and its index entry survived. */
              <span className="min-w-0 flex-1 truncate italic text-ink-faint">
                {e.unreadable} unreadable {e.unreadable === 1 ? 'message' : 'messages'}
                {' '}— stored in an older format this ship cannot read
              </span>
            ) : (
              <span className="flex min-w-0 flex-1 items-center gap-1.5">
                {/* Local state, on the row so a thread's filing is visible
                    without opening it. Neither is signed and neither
                    travels: another ship holding this conversation sees
                    none of it. */}
                {e.archived && (
                  <span className="shrink-0 rounded-sm bg-sunken px-1 text-[11px] text-ink-faint">
                    archived
                  </span>
                )}
                {e.labels.map((l) => (
                  <span
                    key={l}
                    className="max-w-20 shrink-0 truncate rounded-sm bg-accent-soft px-1 text-[11px] text-accent-soft-ink"
                  >
                    {l}
                  </span>
                ))}
                {/* ONE truncate over the pair, not one each. Two
                    truncating siblings split the row between them, so a
                    short snippet stole half the width from a long
                    subject and both ended in an ellipsis. Gmail's rule:
                    the subject gets what it needs and the snippet gets
                    what is left. */}
                <span className="min-w-0 flex-1 truncate">
                  <span className="text-ink">{e.subject}</span>
                  {e.snippet && (
                    <span className="font-normal text-ink-faint"> — {e.snippet}</span>
                  )}
                </span>
              </span>
            )}
            {e.forged && e.verdict !== 'forged' && (
              <span
                className="shrink-0 rounded-sm bg-forged-bg px-1 text-[11px] font-bold uppercase text-forged-ink ring-1 ring-forged-line"
                title="This conversation also holds at least one message whose signature failed. Open it to see which."
              >
                + forged
              </span>
            )}
            {e.count > 1 && (
              <span
                className="shrink-0 text-[11px] font-normal text-ink-faint"
                title={`${e.count} stored copies of this thread's messages, including any unverified or forged duplicates`}
              >
                {e.count} copies
              </span>
            )}
            <span className="w-12 shrink-0 text-right text-[11px] font-normal text-ink-faint">
              {when(e.last)}
            </span>
          </button>
        </li>
      ))}
    </ul>
  )
}

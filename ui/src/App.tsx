import { useCallback, useEffect, useState } from 'react'
import {
  deleteDraft as apiDeleteDraft, deleteRule, drafts as apiDrafts, pageOf,
  rules as apiRules, saveRule, subscribeChanges,
  type Draft, type InboxEntry, type Rule, type View,
} from './api'
import ThreadList from './ThreadList'
import ThreadView from './ThreadView'
import Compose, { type ForwardIntent } from './Compose'
import Sidebar from './Sidebar'
import Drafts from './Drafts'
import Filters from './Filters'

// One page of rows per request. The nexus counts the whole view and
// returns a page of it, so this number is a rendering choice and not a
// bound on anything: `total` is honest about the rest.
const PER_PAGE = 25

type Pane = View | 'drafts' | 'rules'

export default function App() {
  const [pane, setPane] = useState<Pane>('inbox')
  const [label, setLabel] = useState('')
  const [query, setQuery] = useState('')
  // The query actually sent. Typing into a search box must not poke a
  // linear sweep over the mailbox per keystroke, even though the sweep
  // runs on its own request fiber and never touches the writer.
  const [applied, setApplied] = useState('')
  const [offset, setOffset] = useState(0)

  const [entries, setEntries] = useState<InboxEntry[]>([])
  const [total, setTotal] = useState(0)
  const [inboxError, setInboxError] = useState<string | null>(null)
  const [selected, setSelected] = useState<string | null>(null)
  const [composing, setComposing] = useState(false)
  const [resume, setResume] = useState<Draft | null>(null)
  const [drafts, setDrafts] = useState<Draft[]>([])
  const [rules, setRules] = useState<Rule[]>([])
  // Every label any thread carries, which is the label list the sidebar
  // shows. Derived from the ALL view rather than stored: a label exists
  // exactly as long as some thread carries it, so a separate registry
  // could only ever drift from the threads it claims to describe.
  const [labels, setLabels] = useState<string[]>([])

  // Non-null while the composer is open as a forward. Held here rather
  // than in ThreadView so the forward composer is the same panel as the
  // compose one — one composer, one code path, one place where the
  // recipient list is built (from nothing).
  const [forwarding, setForwarding] = useState<ForwardIntent | null>(null)
  // Bumped once per change beacon event, so the open thread (if any) can
  // react to it. The beacon says THAT the tree changed, not which thread
  // changed — it is one small grub the nexus writes on every mutation —
  // so this refetches the open thread and nothing else.
  //
  // A monotonic counter, not Date.now(): two events landing in the same
  // millisecond would produce an identical value, ThreadView's dependency
  // comparison would see no change, and the second refetch would be
  // silently dropped. A counter is guaranteed distinct every call.
  const [threadUpdate, setThreadUpdate] = useState<number | null>(null)

  const isThreadPane = pane !== 'drafts' && pane !== 'rules'
  // A SEARCH LEAVES THE PANE. The nexus ANDs the query with the view
  // predicate, which is right as a primitive and wrong as the only
  // behaviour a user can get: searching from the Inbox would then be
  // searching everything EXCEPT archived mail, and a rule can archive a
  // thread - including one holding a forgery, aimed by a sender who
  // knows your rules. The nexus is honest that archived mail stays
  // searchable and that no rule can hide a failed signature; both were
  // true of the nexus and false of the box the user types into.
  const searching = applied.trim() !== ''

  const refresh = useCallback(() => {
    if (!isThreadPane) return
    pageOf(searching ? 'all' : pane as View, {
      // The label narrows a view, so it goes with the view and not with
      // the search: a query is a question about the whole mailbox.
      label: searching ? undefined : label,
      q: applied,
      offset,
      limit: PER_PAGE,
    })
      .then((p) => {
        setInboxError(null)
        setEntries(p.threads)
        setTotal(p.total)
      })
      .catch((e) => { console.error(e); setInboxError('Could not reach the ship.') })
  }, [pane, label, applied, offset, isThreadPane, searching])

  // The label list and the draft count are sidebar state, not list
  // state: they have to be right whatever pane is open, so they are
  // fetched separately from whichever view is on screen.
  const refreshSidebar = useCallback(() => {
    pageOf('all', { limit: 200 })
      .then((p) => {
        const seen = new Set<string>()
        for (const e of p.threads) for (const l of e.labels) seen.add(l)
        setLabels([...seen].sort())
      })
      .catch((e) => { console.error(e) })
    apiDrafts().then(setDrafts).catch((e) => { console.error(e) })
    apiRules().then(setRules).catch((e) => { console.error(e) })
  }, [])

  const onChange = useCallback(() => {
    refresh()
    refreshSidebar()
    setThreadUpdate((prev) => (prev ?? 0) + 1)
  }, [refresh, refreshSidebar])

  useEffect(() => { refresh() }, [refresh])
  useEffect(() => { refreshSidebar() }, [refreshSidebar])

  useEffect(() => {
    // subscribeChanges is synchronous and hands back its own teardown, so
    // there is no window in which an unmount (or StrictMode's dev-only
    // double effect) can race an in-flight subscribe and leak a stream.
    return subscribeChanges(onChange)
  }, [onChange])

  // Debounce the search box. A search is a read and runs on its own
  // request fiber, so it never queues behind the writer — but it is
  // still a linear sweep over every stored thread, and one per keystroke
  // is a request per keystroke against a serialized pier.
  useEffect(() => {
    const h = setTimeout(() => { setApplied(query); setOffset(0) }, 300)
    return () => { clearTimeout(h) }
  }, [query])

  const goto = (p: Pane, l?: string) => {
    setPane(p)
    setLabel(l ?? '')
    setOffset(0)
    setSelected(null)
  }

  const pages = Math.max(1, Math.ceil(total / PER_PAGE))
  const current = Math.floor(offset / PER_PAGE) + 1

  return (
    <div className="flex h-screen bg-white text-neutral-900">
      <Sidebar
        view={pane}
        label={label}
        labels={labels}
        drafts={drafts.length}
        rules={rules.length}
        counts={{}}
        onView={goto}
        onCompose={() => { setResume(null); setForwarding(null); setComposing(true) }}
        onFilters={() => goto('rules')}
      />

      {pane === 'rules' ? (
        <Filters
          rules={rules}
          onSave={async (r) => { await saveRule(r); refreshSidebar() }}
          onDelete={(id) => { deleteRule(id).then(refreshSidebar).catch(console.error) }}
          onClose={() => goto('inbox')}
        />
      ) : (
        <>
          <div className="flex w-96 shrink-0 flex-col border-r border-neutral-200">
            {isThreadPane && (
              <div className="border-b border-neutral-200 p-3">
                <input
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  placeholder="Search subject, body and sender"
                  aria-label="Search"
                  className="w-full rounded-full bg-neutral-100 px-4 py-2 text-sm outline-none"
                />
                {searching && (
                  // Search covers forged messages deliberately, and a
                  // result row is drawn from the message that matched —
                  // so a hit on a forgery says FORGED rather than
                  // borrowing a verified copy's sender line. It also
                  // covers archived mail, and saying so is the point:
                  // the guarantee is that nothing can hide a message,
                  // and a search silently scoped to one folder would
                  // quietly not be that.
                  <p className="mt-2 text-xs text-neutral-500">
                    {total} {total === 1 ? 'conversation' : 'conversations'} in
                    {' '}<strong>all mail</strong> matching “{applied}” — archived
                    conversations included, and messages whose signature failed are
                    included and shown as forged.
                  </p>
                )}
              </div>
            )}
            {pane === 'drafts' ? (
              <Drafts
                drafts={drafts}
                onOpen={(d) => { setForwarding(null); setComposing(false); setResume(d) }}
                onDelete={(id) => {
                  apiDeleteDraft(id).then(refreshSidebar).catch(console.error)
                }}
              />
            ) : (
              <>
                <ThreadList
                  entries={entries}
                  error={inboxError}
                  selected={selected}
                  onSelect={setSelected}
                />
                {total > PER_PAGE && (
                  <div className="flex items-center gap-3 border-t border-neutral-200 p-3 text-sm">
                    <button
                      type="button"
                      disabled={offset === 0}
                      onClick={() => setOffset(Math.max(0, offset - PER_PAGE))}
                      className="rounded px-3 py-1 ring-1 ring-neutral-300 disabled:opacity-30"
                    >
                      ‹
                    </button>
                    <span className="text-neutral-500">
                      {current} of {pages} · {total} conversations
                    </span>
                    <button
                      type="button"
                      disabled={offset + PER_PAGE >= total}
                      onClick={() => setOffset(offset + PER_PAGE)}
                      className="ml-auto rounded px-3 py-1 ring-1 ring-neutral-300 disabled:opacity-30"
                    >
                      ›
                    </button>
                  </div>
                )}
              </>
            )}
          </div>

          <main className="flex-1 overflow-y-auto">
            {selected
              ? (
                <ThreadView
                  id={selected}
                  onSent={refresh}
                  onDeleted={() => { setSelected(null); refresh() }}
                  onForward={(f) => { setComposing(false); setResume(null); setForwarding(f) }}
                  onFiled={() => { refresh(); refreshSidebar() }}
                  updatedAt={threadUpdate}
                />
              )
              : <p className="p-8 text-neutral-400">Select a conversation</p>}
          </main>
        </>
      )}

      {(composing || forwarding || resume) && (
        // Keyed so that hitting Forward while a blank compose is open
        // remounts the panel instead of retrofitting a `prev` onto a
        // draft whose subject and recipients were typed for something
        // else. The initial state of a forward composer, and of a
        // resumed draft, is only correct on mount.
        <Compose
          key={forwarding ? `forward:${forwarding.prev}` : resume ? `draft:${resume.id}` : 'compose'}
          forward={forwarding}
          resume={resume}
          onDraftsChanged={refreshSidebar}
          onClose={() => { setComposing(false); setForwarding(null); setResume(null) }}
          onSent={() => {
            setComposing(false); setForwarding(null); setResume(null)
            refresh(); refreshSidebar()
          }}
        />
      )}
    </div>
  )
}

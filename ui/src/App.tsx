import { useCallback, useEffect, useRef, useState } from 'react'
import {
  deleteDraft as apiDeleteDraft, deleteList, deleteRule, drafts as apiDrafts,
  lists as apiLists, onCachedMail, pageOf, rules as apiRules, saveList, saveRule,
  subscribeChanges,
  type Draft, type InboxEntry, type MailList, type Rule, type View,
} from './api'
import ThreadList from './ThreadList'
import ThreadView from './ThreadView'
import Compose, { type ForwardIntent } from './Compose'
import Sidebar from './Sidebar'
import Drafts from './Drafts'
import Filters from './Filters'
import Lists from './Lists'

// One page of rows per request. The nexus counts the whole view and
// returns a page of it, so this number is a rendering choice and not a
// bound on anything: `total` is honest about the rest.
const PER_PAGE = 25

type Pane = View | 'drafts' | 'rules' | 'lists'

// The install prompt, which is the one browser API here with no types in
// lib.dom: `beforeinstallprompt` is Chromium-only and unspecified. Only
// the two members this file touches are declared, because inventing the
// rest would be describing an API nobody has agreed on.
interface InstallPrompt extends Event {
  prompt: () => Promise<unknown>
}

const THEME_KEY = 'auspex:theme'

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
  // WHO A SEND WAS NOT CARRIED TO, after the composer has closed.
  //
  // The composer unmounts on a successful send, so a refusal that is
  // not an error has nowhere of its own to be said. It lives up here,
  // beside the offline banner, because it is the same kind of thing:
  // one line about what the ship did with the last thing asked of it,
  // dismissible, and never sticky enough to be mistaken for the state
  // of the mailbox.
  const [notice, setNotice] = useState<string | null>(null)
  const [selected, setSelected] = useState<string | null>(null)
  const [composing, setComposing] = useState(false)
  const [resume, setResume] = useState<Draft | null>(null)
  const [drafts, setDrafts] = useState<Draft[]>([])
  const [rules, setRules] = useState<Rule[]>([])
  // The mailing lists this ship holds. Sidebar state, like the rules and
  // the draft count: the composer offers them whatever pane is open, so
  // they are fetched with the sidebar and not with a view.
  const [lists, setLists] = useState<MailList[]>([])
  // Every label any thread carries, which is the label list the sidebar
  // shows. Derived from the ALL view rather than stored: a label exists
  // exactly as long as some thread carries it, so a separate registry
  // could only ever drift from the threads it claims to describe. This
  // is one of the two remaining users of `all`, which is why the view
  // stayed an API primitive after it left the sidebar.
  const [labels, setLabels] = useState<string[]>([])

  // ── the shell's own state ──────────────────────────────────────────

  // The palette. index.html has already put the class on <html> before
  // the first paint (from localStorage, else prefers-color-scheme), so
  // this reads the decision rather than making it — a second, later
  // decision here would be a flash of the wrong palette on every load.
  // Nothing below writes storage except the toggle: an unstored theme
  // is a theme still following the system, and that is a state the app
  // has to be able to stay in.
  const [theme, setTheme] = useState<'light' | 'dark'>(
    () => (document.documentElement.classList.contains('dark') ? 'dark' : 'light'),
  )
  // Whether the browser has offered to install. There is no way to ask,
  // so the only honest signal is the event itself: no event, no entry.
  const [install, setInstall] = useState<InstallPrompt | null>(null)
  // NOT `!navigator.onLine` as a starting value only. The flag lies in
  // one direction (a captive portal is "online") and is right in the
  // other, which is the direction that matters here: false means no
  // request will succeed, and the app should say so rather than
  // rendering cached mail as though it were current.
  const [online, setOnline] = useState(() => navigator.onLine)
  // The listing on screen was served by the service worker out of its
  // cache, because the ship did not answer. Stronger than `online`: it
  // is true whenever what is displayed is stale, including on a machine
  // whose network is fine and whose ship is not.
  const [stale, setStale] = useState(false)
  // The service worker replaced a shell it had already cached, so the
  // script this tab is running is not the script on the ship any more.
  const [updated, setUpdated] = useState(false)
  // Below md the three panes are one pane, and the sidebar is a drawer.
  const [navOpen, setNavOpen] = useState(false)

  // THE CLASS, AND ONLY THE CLASS. Persisting here would write a
  // preference nobody expressed: this effect also runs on mount, so a
  // first visit stored whatever the system happened to say that day and
  // the app stopped following the system from then on. The one place a
  // real choice is made is the sidebar toggle, and that is the only
  // place that writes storage.
  useEffect(() => {
    document.documentElement.classList.toggle('dark', theme === 'dark')
  }, [theme])

  // FOLLOW THE SYSTEM WHILE NOTHING IS STORED. index.html makes this
  // same decision once, before the first paint; this keeps it true for a
  // tab that is already open when the system flips at sunset. The stored
  // value is read when the event fires and not at mount, so the first
  // toggle silences this listener for good without needing to unbind it.
  useEffect(() => {
    const mq = window.matchMedia('(prefers-color-scheme: dark)')
    const follow = (e: MediaQueryListEvent) => {
      let saved: string | null = null
      try { saved = localStorage.getItem(THEME_KEY) } catch { /* private mode */ }
      if (saved === 'light' || saved === 'dark') return
      setTheme(e.matches ? 'dark' : 'light')
    }
    mq.addEventListener('change', follow)
    return () => { mq.removeEventListener('change', follow) }
  }, [])

  useEffect(() => {
    const offer = (e: Event) => {
      // Chromium shows its own bar unless the event is cancelled, and
      // this app puts the entry in the sidebar footer instead.
      e.preventDefault()
      setInstall(e as InstallPrompt)
    }
    // One prompt, one use: the event cannot be replayed, so drop it the
    // moment the browser says the app is installed.
    const done = () => { setInstall(null) }
    window.addEventListener('beforeinstallprompt', offer)
    window.addEventListener('appinstalled', done)
    return () => {
      window.removeEventListener('beforeinstallprompt', offer)
      window.removeEventListener('appinstalled', done)
    }
  }, [])

  useEffect(() => {
    const up = () => { setOnline(true) }
    const down = () => { setOnline(false) }
    window.addEventListener('online', up)
    window.addEventListener('offline', down)
    return () => {
      window.removeEventListener('online', up)
      window.removeEventListener('offline', down)
    }
  }, [])

  useEffect(() => onCachedMail(setStale), [])

  useEffect(() => {
    if (!('serviceWorker' in navigator)) return
    const heard = (e: MessageEvent) => {
      if ((e.data as { auspex?: string } | null)?.auspex === 'updated') setUpdated(true)
    }
    navigator.serviceWorker.addEventListener('message', heard)
    return () => { navigator.serviceWorker.removeEventListener('message', heard) }
  }, [])

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

  // Non-null while the composer is open as a forward. Held here rather
  // than in ThreadView so the forward composer is the same panel as the
  // compose one — one composer, one code path, one place where the
  // recipient list is built (from nothing).
  const [forwarding, setForwarding] = useState<ForwardIntent | null>(null)

  const isThreadPane = pane !== 'drafts' && pane !== 'rules' && pane !== 'lists'
  // A SEARCH LEAVES THE PANE. The nexus ANDs the query with the view
  // predicate, which is right as a primitive and wrong as the only
  // behaviour a user can get: searching from the Inbox would then be
  // searching everything EXCEPT archived mail, and a rule can archive a
  // thread - including one holding a forgery, aimed by a sender who
  // knows your rules. The nexus is honest that archived mail stays
  // searchable and that no rule can hide a failed signature; both were
  // true of the nexus and false of the box the user types into.
  //
  // This is the other user of `all`, and the reason it is still a view:
  // it is what a search escapes INTO, not a folder anyone visits.
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
    apiLists().then(setLists).catch((e) => { console.error(e) })
  }, [])

  const onChange = useCallback(() => {
    refresh()
    refreshSidebar()
    setThreadUpdate((prev) => (prev ?? 0) + 1)
  }, [refresh, refreshSidebar])

  useEffect(() => { refresh() }, [refresh])
  useEffect(() => { refreshSidebar() }, [refreshSidebar])

  // Coming back from offline is the one moment where everything on
  // screen is known-stale at once: the beacon was dropped while the
  // network was gone, so no push will arrive to say what was missed.
  //
  // On the TRANSITION only. `onChange` is rebuilt whenever the view
  // changes, so refetching whenever this effect re-runs would mean a
  // second full listing fetch on every pane click, for a connection
  // that never went anywhere.
  const wasOnline = useRef(online)
  useEffect(() => {
    if (online && !wasOnline.current) onChange()
    wasOnline.current = online
  }, [online, onChange])

  // A NEWLY INSTALLED WORKER MISSED THIS PAGE'S FIRST FETCHES. It
  // registers after mount and only starts controlling the page once it
  // has installed and claimed, by which time the listing has already
  // been fetched around it and so is not in its cache. One refetch when
  // it takes over is the difference between "opens offline with mail"
  // working from the second visit and working from the first.
  useEffect(() => {
    if (!('serviceWorker' in navigator)) return
    const claimed = () => { onChange() }
    navigator.serviceWorker.addEventListener('controllerchange', claimed)
    return () => { navigator.serviceWorker.removeEventListener('controllerchange', claimed) }
  }, [onChange])

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
    setNavOpen(false)
  }

  const pages = Math.max(1, Math.ceil(total / PER_PAGE))
  const current = Math.floor(offset / PER_PAGE) + 1

  const paneName = pane === 'rules' ? 'Filters'
    : pane === 'lists' ? 'Lists'
      : pane === 'drafts' ? 'Drafts'
        : pane === 'label' ? label
          : pane.charAt(0).toUpperCase() + pane.slice(1)

  return (
    // `overflow-hidden` on the shell and `min-w-0` on every flexible
    // child: NO HORIZONTAL SCROLL, EVER. Nearly every string on this
    // surface — a ship name, a subject, a filename — was chosen by
    // whoever poked the chain, so "the content is reasonable" is not an
    // assumption this layout is allowed to make.
    <div className="flex h-screen w-full flex-col overflow-hidden bg-surface text-ink">
      {notice && (
        // A SEND, NOT A FAILURE. The message was signed and did go out
        // to every recipient the ship would carry it to; these are the
        // ones it would not, in each peer's own published words. When
        // NOBODY could be sent to, the route answers 400 instead and
        // the composer stays open with every word in it - so this line
        // never means "nothing was sent".
        <div
          role="status"
          className="flex shrink-0 items-start gap-2 bg-warn-soft px-3 py-1 text-warn-ink ring-1 ring-warn-line"
        >
          <p className="min-w-0 flex-1 break-words" data-test="send-notice">{notice}</p>
          <button
            type="button"
            onClick={() => setNotice(null)}
            aria-label="Dismiss"
            className="shrink-0 px-1"
          >
            ×
          </button>
        </div>
      )}
      {(!online || stale) && (
        <div className="shrink-0 bg-warn-soft px-3 py-1 text-warn-ink ring-1 ring-warn-line">
          {!online ? (
            <>
              <strong>Offline.</strong> What is shown is mail cached on this
              {' '}device, not what is on the ship now. Nothing can be sent until
              {' '}the connection is back — a message you write is kept here, and
              {' '}nothing is signed until it is actually sent.
            </>
          ) : (
            <>
              <strong>Showing cached mail.</strong> The ship did not answer, so
              {' '}this is the last listing this device stored. A send will fail
              {' '}rather than sit in a queue, and will say so.
            </>
          )}
        </div>
      )}
      {updated && (
        <div className="flex shrink-0 items-center gap-2 bg-accent-soft px-3 py-1 text-accent-soft-ink">
          A newer auspex is installed on this device.
          <button
            type="button"
            onClick={() => { window.location.reload() }}
            className="btn btn-outline"
          >
            Reload
          </button>
        </div>
      )}

      {/* THE PHONE'S ONLY NAVIGATION, and it is the whole of it: a menu
          button that opens the sidebar as a drawer, or a back control
          when a thread is open. Below md exactly one pane is on screen
          at a time, so every transition between them is one of these
          two controls. Above md this bar does not exist and the three
          panes sit side by side as before. */}
      <header className="flex shrink-0 items-center gap-1 border-b border-line px-1 md:hidden">
        {selected ? (
          <button
            type="button"
            onClick={() => { setSelected(null) }}
            className="btn"
          >
            ‹ Back
          </button>
        ) : (
          <button
            type="button"
            onClick={() => { setNavOpen(true) }}
            aria-label="Open the folder list"
            className="btn"
          >
            ☰
          </button>
        )}
        <span className="min-w-0 truncate text-ink-dim">{paneName}</span>
      </header>

      <div className="flex min-h-0 min-w-0 flex-1">
        {/* The drawer's backdrop. Only rendered while it is open, so it
            can never sit invisibly over the desktop layout. */}
        {navOpen && (
          <button
            type="button"
            aria-label="Close the folder list"
            onClick={() => { setNavOpen(false) }}
            className="fixed inset-0 z-20 bg-black/40 md:hidden"
          />
        )}
        <div
          className={`z-30 shrink-0 md:static md:block
            ${navOpen ? 'fixed inset-y-0 left-0 w-56' : 'hidden md:block'}`}
        >
          <Sidebar
            view={pane}
            label={label}
            labels={labels}
            drafts={drafts.length}
            rules={rules.length}
            lists={lists.length}
            counts={{}}
            onView={goto}
            onCompose={() => {
              setResume(null); setForwarding(null); setComposing(true); setNavOpen(false)
            }}
            onFilters={() => goto('rules')}
            onLists={() => goto('lists')}
            theme={theme}
            onTheme={() => {
              // A REAL CHOICE, and the only thing that makes one stick.
              // Until this runs the app is following the system, which
              // is what "follows prefers-color-scheme, with a manual
              // override that persists" means in the two directions.
              const next = theme === 'dark' ? 'light' : 'dark'
              setTheme(next)
              try { localStorage.setItem(THEME_KEY, next) } catch { /* private mode */ }
            }}
            installable={install !== null}
            onInstall={() => {
              // One shot. The event cannot be prompted twice, so it is
              // dropped whether the user accepts or dismisses — a second
              // click on a spent prompt does nothing at all, which is
              // worse than the entry not being there.
              const p = install
              setInstall(null)
              void p?.prompt()
            }}
          />
        </div>

        {pane === 'rules' ? (
          <Filters
            rules={rules}
            onSave={async (r) => { await saveRule(r); refreshSidebar() }}
            onDelete={(id) => { deleteRule(id).then(refreshSidebar).catch(console.error) }}
            onClose={() => goto('inbox')}
          />
        ) : pane === 'lists' ? (
          // A list write does not move the change beacon — no other
          // reader can observe it — so this tab refetches its own
          // sidebar after each one, exactly as the filter panel does.
          <Lists
            lists={lists}
            onSave={async (l) => { await saveList(l); refreshSidebar() }}
            onDelete={(name) => {
              deleteList(name).then(refreshSidebar).catch(console.error)
            }}
            onClose={() => goto('inbox')}
          />
        ) : (
          <>
            <div
              className={`min-w-0 flex-col border-r border-line md:flex md:w-96 md:shrink-0 md:flex-none
                ${selected ? 'hidden md:flex' : 'flex flex-1'}`}
            >
              {isThreadPane && (
                <div className="shrink-0 border-b border-line p-1">
                  <input
                    value={query}
                    onChange={(e) => setQuery(e.target.value)}
                    placeholder="Search subject, body and sender"
                    aria-label="Search"
                    className="field field-box bg-sunken"
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
                    <p className="mt-1 text-[11px] text-ink-dim">
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
                    <div className="flex shrink-0 items-center gap-2 border-t border-line px-1 py-0.5">
                      <button
                        type="button"
                        disabled={offset === 0}
                        onClick={() => setOffset(Math.max(0, offset - PER_PAGE))}
                        aria-label="Previous page"
                        className="btn"
                      >
                        ‹
                      </button>
                      <span className="min-w-0 truncate text-[11px] text-ink-faint">
                        {current} of {pages} · {total} conversations
                      </span>
                      <button
                        type="button"
                        disabled={offset + PER_PAGE >= total}
                        onClick={() => setOffset(offset + PER_PAGE)}
                        aria-label="Next page"
                        className="btn ml-auto"
                      >
                        ›
                      </button>
                    </div>
                  )}
                </>
              )}
            </div>

            <main
              className={`min-w-0 flex-1 overflow-y-auto ${selected ? 'block' : 'hidden md:block'}`}
            >
              {selected
                ? (
                  <ThreadView
                    id={selected}
                    onSent={(n) => { setNotice(n ?? null); refresh() }}
                    onDeleted={() => { setSelected(null); refresh() }}
                    onForward={(f) => { setComposing(false); setResume(null); setForwarding(f) }}
                    onFiled={() => { refresh(); refreshSidebar() }}
                    onRead={(tid) => setEntries((es) => es.map((e) => e.id === tid ? { ...e, unread: false } : e))}
                    updatedAt={threadUpdate}
                    lists={lists}
                    onSaveList={async (l) => { await saveList(l); refreshSidebar() }}
                  />
                )
                : <p className="p-3 text-ink-faint">Select a conversation</p>}
            </main>
          </>
        )}
      </div>

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
          lists={lists}
          onDraftsChanged={refreshSidebar}
          onClose={() => { setComposing(false); setForwarding(null); setResume(null) }}
          onSent={(n) => {
            setComposing(false); setForwarding(null); setResume(null)
            setNotice(n ?? null)
            refresh(); refreshSidebar()
          }}
        />
      )}
    </div>
  )
}

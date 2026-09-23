import { useEffect, useEffectEvent, useId, useRef, useState } from 'react'
import Loading from './Loading'
import {
  canSign, deleteThread, markRead, markUnread, NO_KEYS_LINE,
  ourShip, refusalLine, send, sendFailure, setArchived, setLabel, thread,
  uploadAll,
  type MailList, type Message, type Thread,
} from './api'
import { FilePicker } from './Attachments'
import MessageCard from './MessageCard'
import ShipChips, { commitShip } from './ShipChips'
import ThreadTree, { allForged, copiesOf, speaker } from './ThreadTree'
import { IncludedMessages, type ForwardIntent } from './Compose'
import { when } from './ThreadList'
import { quoteInto } from './quote'

// The default reply audience.
//
// NOT `thread.participants`. That set is the union of `from` and `to`
// across every message the ship holds for this thread, INCLUDING ones
// nobody authenticated. Filing into an existing thread needs only the
// root message's unsigned bytes and no valid signature — a junk-signed
// copy of the root has the same msg-id, so `+thread-key` files it into
// the real thread — which means anyone ever forwarded a chain can poke us
// a message reading `from=~evil to={~evil-two}` and land both ships in
// `participants`. Replying to that set would ship them the entire
// accumulated conversation.
//
// Verdict filtering alone is not the fix either: an attacker who signs
// correctly as their own ship reads `verified`. It only removes the free
// case. The actual fix is that a human sees this list and can edit it
// before the reply goes out, which is what every mail client does and
// what the composer below renders.
function defaultRecipients(th: Thread): string[] {
  const ships = new Set<string>()
  for (const m of th.messages) {
    if (m.verdict === 'forged') continue
    ships.add(m.from)
    for (const r of m.to) ships.add(r)
  }
  ships.delete(ourShip)
  return [...ships].sort()
}

export default function ThreadView({
  id, onSent, onDeleted, onForward, onFiled, onRead, updatedAt, lists, onSaveList, knownLabels,
}: {
  // The labels in use on this ship, offered as a label is typed.
  knownLabels?: string[]
  id: string
  // Called once a read mark this view made has landed on the ship and
  // left nothing in the thread unread, so the listing can un-bold the row
  // without a refetch.
  onRead: (threadId: string) => void
  onSent: (notice?: string | null) => void
  onDeleted: () => void
  // Opens the composer as a forward: `prev` set to this thread's newest
  // message and NO recipients. See ForwardIntent in Compose.tsx for why
  // the audience is not carried across.
  onForward: (f: ForwardIntent) => void
  // Called after a label, an archive or an unread mark: none of those
  // move the change beacon - they alter a thread in ways no other ship
  // can see - so the tab that made the change is the one that has to
  // refresh the listing and the sidebar.
  onFiled: () => void
  // Bumped by App on every change-beacon event. An opaque, monotonically
  // increasing value (not a timestamp), so it is safe as an effect
  // dependency: each event triggers exactly one refetch of the thread on
  // screen. The beacon does not name a thread, so this fires for any
  // mutation — but only the open thread refetches, and read-marks never
  // bump the beacon, so opening a thread cannot start a refetch loop.
  updatedAt?: number | null
  // Passed straight through to each MessageCard, which carries the
  // Save-as-list control: the audience of ONE message is what a list is
  // copied from, so the control belongs on the card and not on the
  // thread.
  lists: MailList[]
  onSaveList: (l: MailList) => Promise<void>
}) {
  const [t, setT] = useState<Thread | null>(null)
  // The messages the effect below last loaded, so a beacon refetch can
  // tell mail that just arrived from mail already on screen.
  const loaded = useRef<Message[]>([])
  const [notFound, setNotFound] = useState(false)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [reply, setReply] = useState('')
  // The reply audience, seeded from the thread and then owned by the user.
  // Every send ships the whole signed chain, so this list is the blast
  // radius of the Send button and has to be visible before it is pressed.
  const [recipients, setRecipients] = useState<string[]>([])
  const [pending, setPending] = useState('')
  const [sending, setSending] = useState(false)
  // Which file is in flight. See Compose.tsx: uploads are one request
  // per file, in sequence, and a reply with files attached is several
  // round trips before the send itself starts.
  const [upload, setUpload] = useState<string | null>(null)
  const [sendError, setSendError] = useState<string | null>(null)
  // Files on the reply. Not seeded from the message being replied to:
  // re-sending someone else's attachment would re-sign its metadata
  // under our name, and the bytes are already fetchable by anyone on
  // the chain from their own content hash.
  const [files, setFiles] = useState<File[]>([])
  // LIST OR TREE. Component state, deliberately not stored: the shape of
  // a conversation is a question a reader asks about one conversation,
  // not a preference, and a persisted toggle would answer it for every
  // thread they open afterwards. List is the default because it is the
  // right shape for reading.
  const [view, setView] = useState<'list' | 'tree'>('list')
  // The reply box, to focus when a message's own Reply is pressed; the
  // messages, so a quote is taken only from text selected in them.
  const replyRef = useRef<HTMLTextAreaElement>(null)
  const messagesRef = useRef<HTMLDivElement>(null)
  // A label being typed, or null while the field is shut, and the DOM id
  // of the suggestions it offers.
  const [labelDraft, setLabelDraft] = useState<string | null>(null)
  const labelsId = useId()
  const [hint, setHint] = useState<string | null>(null)
  // The node the tree has selected, by message id — null until the user
  // picks one, when it stands for "whatever the list would have replied
  // to". Cleared on a thread change and never on a beacon push: a
  // selection is the user's, and an unrelated delivery must not move it.
  const [picked, setPicked] = useState<string | null>(null)

  // Tracks the id the effect below most recently committed to, so
  // `file`'s refetch (see below) can tell whether the user has since
  // navigated to a different thread. Updated synchronously inside
  // the effect, before any async work, so it's always current by the time
  // any later promise resolves.
  const idRef = useRef(id)

  // The thread id the reply audience was last seeded from, and the guard
  // that keeps finding 1's fix from being switched off remotely.
  //
  // The effect below re-runs on `updatedAt`, which App bumps for every
  // change-beacon event — and the writer bumps the beacon on EVERY
  // delivery, including a delivery the attacker sent. The beacon does not
  // name a thread, so ANY inbound mail at all re-runs this effect for
  // whatever thread happens to be open; a re-seed here would throw
  // away the user's removals and restore the attacker-inclusive default,
  // at a moment of the attacker's choosing, including the window between
  // the removal and the click on Send. Worse, the same effect leaves the
  // typed `reply` alone, so the composer would look untouched while its
  // audience had silently widened.
  //
  // The whole Critical fix rests on the edit surviving until Send, so the
  // seed happens once per thread and no remote push ever repeats it. The
  // refetch itself still runs on every push: only the seed is gated.
  const seededFor = useRef<string | null>(null)

  // The stale-thread race: click thread A, then click B before A's
  // request resolves. React runs A's effect cleanup and B's effect setup back to
  // back, synchronously, with no microtask in between — so a *hoisted*
  // ref re-armed at the top of every invocation is reset to "not stale"
  // by B's setup before A's in-flight network response ever lands, and
  // does nothing to stop it. The guard has to be a variable owned by the
  // one invocation whose request it guards, which only a fresh `let`
  // inside the effect provides (each call gets its own closure; nothing
  // later can reach in and reset it) - the same reason `App.tsx`'s
  // subscription cleanup uses a per-invocation `cancelled`, not a ref.
  //
  // `onRead` through an effect event: the mark lands after the listing
  // may have been refreshed, and App decides the unread count off the
  // rows it holds NOW, not the ones it held when this effect started.
  const readEvent = useEffectEvent(onRead)
  useEffect(() => {
    let cancelled = false
    idRef.current = id
    // A different thread than the one the audience was seeded from, so
    // this run may seed. A re-run for the SAME thread - which is what a
    // beacon event produces - may not.
    const fresh = seededFor.current !== id
    setNotFound(false)
    setLoadError(null)
    // A beacon refetch keeps the thread on screen until the new copy lands,
    // and keeps what the reply box last said - an unrelated delivery must
    // not erase why a send failed. Only a different thread starts over.
    if (fresh) {
      setSendError(null)
      setT(null)
      setRecipients([])
      setPending('')
      setPicked(null)
    }
    thread(id).then((th) => {
      if (cancelled) return
      if (th === null) {
        setNotFound(true)
        return
      }
      // WHAT THIS LOAD MARKS READ. Opening a thread marks every unread
      // message in it. A beacon refetch of the thread already open marks
      // only what was not on screen before it — mail that arrived while
      // it was open. The beacon does not name a thread, so ANY delivery
      // re-runs this, and marking the whole thread again would silently
      // undo a Mark unread the user had just set.
      const before = new Set(fresh ? [] : loaded.current.map((m) => m.id))
      loaded.current = th.messages
      const unread = th.messages.filter((m) => !m.read && !before.has(m.id)).map((m) => m.id)
      setT(th)
      if (fresh) {
        setRecipients(defaultRecipients(th))
        setPending('')
        seededFor.current = id
      }
      if (unread.length > 0) {
        // One request for the whole batch, not one per message, naming
        // the thread: the writer serialises every mutation.
        markRead(th.id, unread).then(() => {
          // A read mark does not move the change beacon (deliberately:
          // opening a thread must not refetch the thread), so nothing
          // tells the listing that the row is no longer bold — the tab
          // that made the mark is the one that knows. Told even if this
          // view has moved on, because the mark landed either way; not
          // told while an honest message the user left unread is still
          // unread, because then the row is still bold on the ship.
          const left = th.messages.some((m) =>
            !m.read && m.verdict !== 'forged' && before.has(m.id))
          if (!left) readEvent(th.id)
        }).catch(console.error)
      }
    }).catch((e) => {
      if (cancelled) return
      console.error(e)
      setLoadError('Could not load this conversation.')
    })
    return () => { cancelled = true }
  }, [id, updatedAt])

  if (loadError) {
    return <p className="p-3 text-danger">{loadError}</p>
  }
  if (notFound) {
    return <p className="p-3 text-ink-faint">This conversation no longer exists.</p>
  }
  //  Was `null`: a blank pane, which on a slow read is indistinguishable
  //  from a thread that failed to open. `t` survives a navigation, so
  //  this is the FIRST thread only — every later one keeps the previous
  //  conversation on screen until its own arrives.
  if (!t) return <Loading what="Opening" />

  const onDelete = async () => {
    // Deleting drops evidence: the signed chain is the artifact, and a
    // forged message in it is proof of an attempt. Worth a confirm.
    if (!window.confirm(
      'Delete this conversation and everything stored under it? '
      + 'The signed chain, including any forged messages kept as evidence, '
      + 'is removed from this ship. Other ships keep their own copies.',
    )) return
    try {
      await deleteThread(id)
      onDeleted()
    } catch (e) {
      console.error(e)
      setSendError('Could not delete this conversation.')
    }
  }

  // FILING CONTROLS. Every one of these is local state: a label, an
  // archive flag and a read mark never travel, are never signed, and no
  // other ship holding this same conversation can see any of them. They
  // do not move the change beacon either, which is why each one calls
  // onFiled to refresh what this tab is showing rather than waiting for
  // a push that will never come.
  // `Promise<unknown>` and not `Promise<void>`: the shared POST helper
  // answers the ship's parsed body now, because /api/send has something
  // to say. Nothing here reads it - filing a conversation is local
  // state and the ship has no more to report than ok - so the value is
  // taken and ignored.
  const file = async (go: Promise<unknown>) => {
    try {
      await go
      const th = await thread(id)
      if (idRef.current === id && th !== null) setT(th)
      onFiled()
    } catch (e) {
      console.error(e)
      setSendError(e instanceof Error ? e.message : 'Could not file this conversation.')
    }
  }

  const onArchive = () => file(setArchived(id, !t.archived))

  const onLabel = (l: string, add: boolean) => file(setLabel(id, l, add))

  // A LABEL IS TYPED IN PLACE, and the browser's own suggestion list
  // offers the ones already in use as it is typed: most labels are
  // picked, not spelled. It was a browser prompt that offered nothing.
  const addLabel = (raw: string) => {
    const l = raw.trim()
    if (!l) { setLabelDraft(null); return }
    if (!/^[a-z][a-z0-9-]*$/.test(l)) {
      setSendError('A label is a lowercase term: a-z, 0-9 and hyphens, starting with a letter.')
      return
    }
    setSendError(null)
    setLabelDraft(null)
    void onLabel(l, true)
  }

  // MARK UNREAD, the inverse of the read mark opening the thread laid
  // down. Forged copies are excluded, for the same reason they never
  // count toward unread: a message whose signature failed has no
  // business bolding an inbox row. The thread stays open: a beacon
  // refetch marks only mail that is new since, so nothing here undoes it.
  const onUnread = async () => {
    const ids = t.messages.filter((m) => m.verdict !== 'forged').map((m) => m.id)
    try {
      await markUnread(id, ids)
      onFiled()
    } catch (e) {
      console.error(e)
      setSendError('Could not mark this unread.')
    }
  }

  // A THREAD THIS SHIP CANNOT READ A SINGLE MESSAGE OF.
  //
  // The nexus serves this rather than 404ing, deliberately: the copies
  // are on disk, this build refuses them (see `unreadable`), and a 404
  // would say "no such thread", which is a different and false thing.
  // So `messages` is empty and every field below that reads from it —
  // `messages[0].subject` for the heading, `last` for reply and forward
  // — has nothing to read. Rendering that pane threw, and a throw during
  // render unmounts the WHOLE React tree, so one such thread blanked the
  // entire app rather than degrading one pane. main.tsx now carries a
  // boundary so no render can do that again; this branch is why it does
  // not have to.
  //
  // Reachable on any ship carrying pre-freeze mail, which is not
  // hypothetical: ~wex holds three such threads.
  //
  // What the pane offers is the honest set: the count, why, and Delete —
  // the only action that can act on messages nothing can read. There is
  // no reply target, so there is no composer.
  if (t.messages.length === 0) {
    return (
      <div className="p-3">
        <div className="mb-3 flex items-center gap-2">
          <h1 className="min-w-0 truncate text-base font-medium text-ink-dim">
            Unreadable conversation
          </h1>
          <button
            type="button"
            onClick={onDelete}
            title="Remove this conversation from this ship. Other ships keep their own copies."
            className="btn btn-danger btn-outline ml-auto shrink-0"
          >
            Delete
          </button>
        </div>
        <p className="max-w-prose rounded-sm bg-sunken p-2 text-ink-dim ring-1 ring-line">
          {t.unreadable === 0 && 'This conversation holds no message this ship can show.'}
          {t.unreadable === 1 && (
            <>
              The only stored copy of this conversation is in a message format this
              ship can no longer read. It is still on disk. It is not shown because
              rewriting it into the current format would break the signature that
              makes it evidence, and a message whose signature no longer matches its
              own contents is one every other ship reads as forged.
            </>
          )}
          {t.unreadable > 1 && (
            <>
              All {t.unreadable} stored copies of this conversation are in a message
              format this ship can no longer read. They are still on disk. They are
              not shown because rewriting one into the current format would break the
              signature that makes it evidence, and a message whose signature no
              longer matches its own contents is one every other ship reads as forged.
            </>
          )}
        </p>
        {sendError && <p className="mt-2 text-danger">{sendError}</p>}
      </div>
    )
  }

  // WHICH MESSAGE A REPLY OR FORWARD POINTS AT.
  //
  // Not simply the last one. `messages` is ordered by `sent`, which is a
  // signed field the AUTHOR chooses, so anyone who can poke a chain at
  // this ship controls which message sorts last. The listing already
  // refuses to draw its sender and subject from a forged copy for
  // exactly this reason.
  //
  // It matters more now than it did. `prev` decides which root-to-leaf
  // path the nexus ships, so letting a forged copy be the newest would
  // let one poked chain make every subsequent reply carry the attacker's
  // message as its parent — and amputate the genuine branch from what
  // the recipient receives. Fall back to the raw newest only when every
  // copy is forged, where there is nothing honest to choose.
  const last = speaker(t.messages)

  // How many DISTINCT MESSAGES actually travel when `last` is forwarded:
  // the path from the thread root to it, which is what the nexus ships.
  // Not t.messages.length — that counts stored COPIES, several of which
  // may be one message kept in several signatures, and it counts sibling
  // branches that no longer leave the ship at all.
  // The messages a reply to [from] carries, root first: one per id, the
  // copy that speaks for it, never a forged twin chosen by position.
  const pathTo = (from: Message): Message[] => {
    const byId = new Map(t.messages.map((m) => [m.id, m]))
    const seen: string[] = []
    let cur: Message | undefined = from
    while (cur && !seen.includes(cur.id)) {
      seen.push(cur.id)
      cur = cur.prev ? byId.get(cur.prev) : undefined
    }
    return seen.reverse().map((i) => speaker(copiesOf(t.messages, i)))
  }

  // WHICH VIEW IS ACTUALLY ON SCREEN. The toggle is only offered on a
  // thread with something to branch, so a one-message thread cannot be
  // left in tree mode by a choice made on the thread before it.
  const branching = t.messages.length > 1
  const mode = branching ? view : 'list'

  // THE MESSAGE A REPLY OR FORWARD POINTS AT.
  //
  // In the list view this is `last`, unchanged: there is no way to say
  // "that one" on a flat list, so the rule above picks for the user.
  //
  // In the tree view the user has said it. Clicking a node is a claim
  // about which branch the next message belongs on, and honouring it is
  // the whole point of drawing the tree — `prev` decides which
  // root-to-leaf path the nexus ships, so a reply aimed at a node ships
  // that node's path and no sibling branch.
  //
  // The honest-copy rule survives the move. A node collapses every copy
  // of one id, and picking a node whose copies are ALL forged would aim
  // the new message's entire travelling chain at a message nobody wrote
  // — so such a node is not a reply target, and the controls say so
  // rather than quietly falling back to somewhere the user did not
  // click. Within a node that has an honest copy, that copy speaks.
  const pickedCopies = picked ? copiesOf(t.messages, picked) : []
  // Picked from the tree, or by a message's own Reply in either view.
  const target = pickedCopies.length ? speaker(pickedCopies) : last
  // In EVERY view, and of the DEFAULT target too, not just a clicked one.
  // On a thread where every copy is forged `last` above falls back to a
  // forged message, so the reply box opens aimed at a message nothing
  // may point at, and it has to say so from the first render. The writer
  // refuses such a send anyway — after the route has answered 200, so
  // offering it here would be a "sent" that never left.
  const targetForged = allForged(copiesOf(t.messages, target.id))
  const noTarget = targetForged
    ? 'Every stored copy of this message failed its signature, so nothing can'
      + ' point at it: a reply naming it would carry a chain nobody signed.'
      + ' Select another message.'
    : null

  const path = pathTo(target)
  const travels = path.length
  const replyTo = (mid: string) => {
    setPicked(mid)
    requestAnimationFrame(() => {
      replyRef.current?.focus()
      replyRef.current?.scrollIntoView({ block: 'center', behavior: 'smooth' })
    })
  }
  const forwardFrom = (m: Message) => {
    const p = pathTo(m)
    onForward({ prev: m.id, subject: m.subject, count: p.length, path: p })
  }
  // A QUOTE, FROM WHAT IS SELECTED IN THE MESSAGES ABOVE: the lines go
  // into the reply at the cursor, each set with "> ". Only a selection
  // inside the thread counts, so something highlighted elsewhere on the
  // page is not quoted into a signed message by accident.
  const quoteSelection = () => {
    const sel = window.getSelection()
    const text = sel?.toString() ?? ''
    const inThread = sel !== null && sel.rangeCount > 0
      && (messagesRef.current?.contains(sel.getRangeAt(0).commonAncestorContainer) ?? false)
    if (!text.trim() || !inThread) {
      setHint('Select some lines in a message above, then press Quote selection.')
      return
    }
    setHint(null)
    const ta = replyRef.current
    const q = quoteInto(reply, text, ta ? ta.selectionStart : reply.length)
    setReply(q.body)
    requestAnimationFrame(() => { ta?.focus(); ta?.setSelectionRange(q.cursor, q.cursor) })
  }
  // A message's own Reply and Forward. Not on a copy whose signature
  // failed, which nothing may point at.
  //
  // Up to 4 copies of a message share the same `id` by design (one
  // genuine, others forged): keyed on the position in the fixed,
  // backend-ordered list, not `m.id`, or React's key collision folds
  // distinct verified and forged copies into one node.
  const card = (m: Message, i: number) => (
    <MessageCard
      key={i}
      m={m}
      lists={lists}
      onSaveList={onSaveList}
      onReply={m.verdict === 'forged' ? undefined : () => replyTo(m.id)}
      onForward={m.verdict === 'forged' ? undefined : () => forwardFrom(m)}
      targeted={m.verdict !== 'forged' && m.id === target.id}
    />
  )

  const onReply = async () => {
    // A @p typed but not yet committed to a chip is still a recipient the
    // user meant, and a typo refuses the send rather than dropping out of
    // it - the same fold the composer does.
    const { ships: to, error: chipError } = commitShip(recipients, pending)
    if (chipError) {
      setSendError(chipError)
      return
    }
    setRecipients(to)
    setPending('')
    if (to.length === 0) {
      setSendError('Add at least one recipient.')
      return
    }
    setSending(true)
    setSendError(null)
    // THE BYTES GO UP FIRST. An upload signs nothing and moves no
    // message, so a file that will not upload leaves the reply exactly
    // where it was, with an error naming the file.
    let refs
    try {
      refs = await uploadAll(files, (i, n) => { setUpload(`uploading ${i} of ${n}`) })
    } catch (e) {
      console.error(e)
      setSendError(
        `${e instanceof Error ? e.message : 'An attachment could not be uploaded.'}`
        + ' Nothing has been sent — your reply and its files are still here.',
      )
      setUpload(null)
      setSending(false)
      return
    }
    setUpload(null)
    let notice: string | null = null
    try {
      const res = await send(to, `re: ${target.subject}`, reply, target.id, refs)
      // WHO THE SHIP WOULD NOT CARRY IT TO. The reply went out to
      // everyone else and is gone from this box, so this is a line
      // beside a successful send and not an error - see Compose.tsx.
      // The all-refused case is a 400 and lands in the catch below,
      // where the reply stays in the box.
      notice = refusalLine(to, res.refused)
    } catch (e) {
      // NO FALSE "SENT" WHEN THE SHIP WAS NEVER REACHED. The worker
      // never touches a POST, so a reply whose request did not arrive
      // was not signed and did not leave. See Compose.tsx.
      console.error(e)
      setSendError(sendFailure(e, 'Your reply is still here.'))
      setSending(false)
      return
    }
    setReply('')
    setFiles([])
    // Sent: the next reply answers the conversation as it now stands.
    setPicked(null)
    setSending(false)
    // No refetch of our own. The writer bumps the change beacon before it
    // fans the reply out, and the beacon refetches this thread and the
    // listing both — a second fetch here was the same request twice.
    onSent(notice)
  }

  return (
    <div className="p-3">
      {/* The subject takes a line of its own below md and shares one
          above it, so four controls and an attacker-chosen subject
          cannot between them push this row wider than the pane. */}
      <div className="mb-2 flex flex-wrap items-center gap-1">
        <h1 className="min-w-0 basis-full truncate text-base font-medium md:basis-0 md:flex-1">
          {t.messages[0].subject}
        </h1>
        {/* LIST OR TREE, offered only where there is a shape to see. A
            thread of one message has no branch to draw, and a control
            switching between two identical pictures is furniture. */}
        {/* THE TREE IS SHOWN OR IT IS NOT: one switch. Two buttons, List
            and Tree, read as a pair of views, and pressing Tree again did
            nothing. Offered only where there is a shape to see. */}
        {branching && (
          <button
            type="button"
            onClick={() => setView(mode === 'tree' ? 'list' : 'tree')}
            aria-pressed={mode === 'tree'}
            title="Who replied to what. A reply or forward ships the path from the root down to
              the message it points at; this is that shape, and a node picked here is what
              the next message points at."
            className={`btn shrink-0 border-line-strong ${mode === 'tree' ? 'bg-sunken text-ink' : ''}`}
          >
            Tree
          </button>
        )}
        {/* ARCHIVE IS NOT DELETE, and the two sit side by side, so the
            difference has to be on the buttons rather than only in a
            document. Archiving takes a thread out of the Inbox view and
            nothing else: the chain is untouched, every signature still
            stands, it is still searchable, and a new message arriving in
            it brings it straight back. */}
        <button
          type="button"
          onClick={onArchive}
          title={t.archived
            ? 'Put this back in the inbox.'
            : 'Take this out of the inbox. Nothing is deleted, nothing is unsigned, and'
              + ' a new message in this conversation brings it back on its own.'}
          className="btn shrink-0"
        >
          {t.archived ? 'Unarchive' : 'Archive'}
        </button>
        {/* Always offered: opening a thread marks it read, so there is
            always something to un-read. */}
        <button
          type="button"
          onClick={onUnread}
          title="Mark every message here unread. Messages whose signature failed are left
            alone: a forgery never counts toward unread."
          className="btn shrink-0"
        >
          Mark unread
        </button>
        <button
          type="button"
          onClick={onDelete}
          title="Remove this conversation from this ship. The only way to free a thread pinned at a capacity limit."
          className="btn btn-danger shrink-0"
        >
          Delete
        </button>
      </div>
      {/* Labels, and the button that adds one. A FOLDER IS A LABEL: there
          is no separate place a conversation can be filed, so this row is
          the whole of this thread's filing. None of it travels. */}
      <div className="mb-2 flex flex-wrap items-center gap-1">
        {t.labels.map((l) => (
          <span
            key={l}
            className="flex max-w-full items-center gap-1 rounded-sm bg-accent-soft py-0.5 pl-2 pr-1 text-[11px] text-accent-soft-ink"
          >
            <span className="min-w-0 truncate">{l}</span>
            <button
              type="button"
              onClick={() => { void onLabel(l, false) }}
              aria-label={`Remove the label ${l}`}
              className="touch shrink-0 px-0.5 hover:text-danger"
            >
              ×
            </button>
          </span>
        ))}
        {labelDraft === null ? (
          <button type="button" onClick={() => setLabelDraft('')} className="btn btn-outline">
            + label
          </button>
        ) : (
          // A FORM, so Enter is the form's own submit and not a keydown:
          // a browser that takes Enter to pick from the suggestion list
          // cancels the submit, where a keydown handler could see the
          // Enter first and file the half-typed text.
          <form onSubmit={(e) => { e.preventDefault(); addLabel(labelDraft) }}>
            <input
              autoFocus
              value={labelDraft}
              onChange={(e) => setLabelDraft(e.target.value.toLowerCase())}
              onKeyDown={(e) => { if (e.key === 'Escape') setLabelDraft(null) }}
              onBlur={() => { if (!labelDraft.trim()) setLabelDraft(null) }}
              list={labelsId}
              placeholder="label"
              aria-label="Label this conversation"
              title="Labels are local: they never travel, and no other ship can see them. Lowercase letters, digits and hyphens."
              className="field w-32"
            />
            <datalist id={labelsId}>
              {(knownLabels ?? []).filter((l) => !t.labels.includes(l)).map((l) => (
                <option key={l} value={l} />
              ))}
            </datalist>
          </form>
        )}
      </div>
      {/* Messages stored on this ship that this build cannot read. The
          nexus refuses pre-body-mime grubs rather than relabelling them,
          because rewriting one breaks the signature that makes it
          evidence — so they are absent from the list above. Saying so is
          the difference between "your mail is gone" and a true statement
          the user can act on. */}
      {t.unreadable > 0 && (
        <p className="mb-2 max-w-prose rounded-sm bg-sunken p-2 text-[11px] text-ink-dim ring-1 ring-line">
          {t.unreadable} stored {t.unreadable === 1 ? 'copy' : 'copies'} in this
          conversation {t.unreadable === 1 ? 'is' : 'are'} not shown: they were
          written in an older message format that this ship can no longer read.
          They are still on disk. They are not shown because rewriting one into
          the current format would break the signature that makes it evidence.
        </p>
      )}
      <div ref={messagesRef}>
      {mode === 'tree' ? (
        <>
          <ThreadTree
            messages={t.messages}
            selected={target.id}
            onSelect={setPicked}
          />
          {/* The selected node's copies, in the same card the list view
              uses. Every copy, not one: a node collapses the copies that
              share an id, and a forged twin of the message on screen is
              exactly the thing a reader must be able to see. */}
          {copiesOf(t.messages, target.id).map(card)}
        </>
      ) : t.messages.map(card)}
      </div>
      {/* WHAT THE REPLY ANSWERS, AND WHAT GOES WITH IT. The message it
          answers is marked above; the rest of what travels, every signed
          message from the start of the conversation down to it, is here
          to read before sending, and other branches are not in it. Keyed
          on the target: another message is another path, and it opens
          shut. */}
      <IncludedMessages key={target.id} earlier={path.slice(0, -1)} className="mb-1 mt-3">
        <span className="text-ink-dim">Replying to</span>
        <span className="font-medium">{target.from}</span>
        <span className="text-ink-faint">{when(target.sent)}</span>
        {picked !== null && target.id !== last.id && (
          <button type="button" onClick={() => setPicked(null)} className="btn">
            Reply to the newest instead
          </button>
        )}
      </IncludedMessages>
      <div className="mb-1 rounded-sm border border-line p-2">
        <div className="mb-1">
          <ShipChips
            ships={recipients}
            pending={pending}
            onShips={setRecipients}
            onPending={setPending}
            onError={setSendError}
            lists={lists}
            label="To"
          />
        </div>
        <p className="text-[11px] text-ink-dim">
          Everyone listed receives the {travels} signed{' '}
          {travels === 1 ? 'message' : 'messages'} leading to this one, not just
          your reply — and nothing from other branches of the conversation.
          Anyone who was ever added to this conversation appears here; remove
          anyone who should not get that history.
        </p>
      </div>
      {/* max-body in grubbery-overlay/lib/auspex-chain.hoon. See
          Compose.tsx: a guard rail in UTF-16 units, not the authority. */}
      <div className="mb-1 flex items-center gap-2">
        {/* Kept from stealing the selection: a press on a button can
            clear what was highlighted before the click reads it. */}
        <button
          type="button"
          onMouseDown={(e) => e.preventDefault()}
          onClick={quoteSelection}
          title="Put the lines selected in a message above into your reply, each set with >."
          className="btn"
        >
          Quote selection
        </button>
        {hint && <span className="text-[11px] text-ink-dim">{hint}</span>}
      </div>
      <textarea
        ref={replyRef}
        value={reply}
        onChange={(e) => setReply(e.target.value)}
        maxLength={100000}
        placeholder="Reply"
        className="field field-box h-28 resize-y"
      />
      <FilePicker files={files} onChange={setFiles} disabled={sending} />
      {/* The one filled button in this pane. Forward, Archive, Mark
          unread and Delete are all text-weight: exactly one primary per
          surface, and on a thread the primary action is the reply. */}
      <div className="mt-2 flex items-center gap-2">
        <button
          onClick={onReply}
          disabled={
            (!reply.trim() && files.length === 0)
            || sending
            || targetForged
            || !canSign
            || (recipients.length === 0 && !pending.trim())
          }
          title={noTarget ?? (canSign ? undefined : NO_KEYS_LINE)}
          className="btn btn-primary"
        >
          {upload ?? (sending ? 'Sending…' : 'Send')}
        </button>
      </div>
      {/* Same reason the forged-target line below is repeated here: a
          disabled button's title is not something a reader finds
          without hovering the thing that is refusing them. */}
      {!canSign && (
        <p className="mt-1 text-[11px] text-warn-ink">{NO_KEYS_LINE}</p>
      )}
      {/* A NODE NOTHING CAN POINT AT. Said here as well as on the two
          disabled controls, because a disabled button's title is not
          something a reader finds without hovering the thing that is
          refusing them. */}
      {noTarget && <p className="mt-1 text-[11px] text-ink-dim">{noTarget}</p>}
      {sendError && <p className="mt-1 text-danger">{sendError}</p>}
    </div>
  )
}

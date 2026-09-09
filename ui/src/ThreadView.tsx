import { useEffect, useRef, useState } from 'react'
import {
  deleteThread, garbled, isShip, markRead, markUnread, ourShip, send, setArchived,
  setLabel, thread, unreachable, uploadAll, type Message, type Thread,
} from './api'
import { FilePicker } from './Attachments'
import MessageCard from './MessageCard'
import ThreadTree, { allForged, copiesOf, speaker } from './ThreadTree'
import type { ForwardIntent } from './Compose'

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
  id, onSent, onDeleted, onForward, onFiled, updatedAt,
}: {
  id: string
  onSent: () => void
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
}) {
  const [t, setT] = useState<Thread | null>(null)
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
  // The node the tree has selected, by message id — null until the user
  // picks one, when it stands for "whatever the list would have replied
  // to". Cleared on a thread change and never on a beacon push: a
  // selection is the user's, and an unrelated delivery must not move it.
  const [picked, setPicked] = useState<string | null>(null)

  // Tracks the id the effect below most recently committed to, so
  // onReply's post-send refetch (see below) can tell whether the user has
  // since navigated to a different thread. Updated synchronously inside
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
  useEffect(() => {
    let cancelled = false
    idRef.current = id
    // A different thread than the one the audience was seeded from, so
    // this run may seed. A re-run for the SAME thread - which is what a
    // beacon event produces - may not.
    const fresh = seededFor.current !== id
    setT(null)
    setNotFound(false)
    setLoadError(null)
    setSendError(null)
    if (fresh) {
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
      setT(th)
      if (fresh) {
        setRecipients(defaultRecipients(th))
        setPending('')
        seededFor.current = id
      }
      // One request for the whole batch, not one per message: the
      // writer serialises every mutation and each poke costs it a full
      // mailbox scan.
      markRead(th.messages.filter((m) => !m.read).map((m) => m.id)).catch(console.error)
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
  if (!t) return null

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
  const file = async (go: Promise<void>) => {
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

  const addLabel = () => {
    const l = (window.prompt(
      'Label this conversation. Labels are local: they never travel, and no other'
      + ' ship can see them. Lowercase letters, digits and hyphens.',
    ) ?? '').trim()
    if (!l) return
    if (!/^[a-z][a-z0-9-]*$/.test(l)) {
      setSendError('A label is a lowercase term: a-z, 0-9 and hyphens, starting with a letter.')
      return
    }
    void onLabel(l, true)
  }

  // MARK UNREAD, the exact inverse of the read mark opening the thread
  // laid down. Forged copies are excluded from both directions for the
  // same reason they never count toward unread: a message whose
  // signature failed has no business bolding an inbox row.
  const onUnread = async () => {
    const ids = t.messages.filter((m) => m.verdict !== 'forged').map((m) => m.id)
    try {
      await markUnread(ids)
      onFiled()
      // Leave the thread: staying would re-run the effect that marks it
      // read again, and the user would watch the mark they just set
      // undo itself.
      onDeleted()
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
  const honest = t.messages.filter((m) => m.verdict !== 'forged')
  const last = (honest.length ? honest : t.messages)[
    (honest.length ? honest : t.messages).length - 1
  ]

  // How many DISTINCT MESSAGES actually travel when `last` is forwarded:
  // the path from the thread root to it, which is what the nexus ships.
  // Not t.messages.length — that counts stored COPIES, several of which
  // may be one message kept in several signatures, and it counts sibling
  // branches that no longer leave the ship at all.
  const pathLength = (from: Message): number => {
    const byId = new Map(t.messages.map((m) => [m.id, m]))
    const seen = new Set<string>()
    let cur: Message | undefined = from
    while (cur && !seen.has(cur.id)) {
      seen.add(cur.id)
      cur = cur.prev ? byId.get(cur.prev) : undefined
    }
    return seen.size
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
  const target = mode === 'tree' && pickedCopies.length ? speaker(pickedCopies) : last
  // Only ever true in the tree view: `last` above already falls back to
  // a forged message when the whole thread is forged, and that is the
  // list view's long-standing behaviour, not something to change here.
  const targetForged = mode === 'tree' && pickedCopies.length
    ? allForged(pickedCopies)
    : false
  const noTarget = targetForged
    ? 'Every stored copy of this message failed its signature, so nothing can'
      + ' point at it: a reply naming it would carry a chain nobody signed.'
      + ' Select another message.'
    : null

  const travels = pathLength(target)

  // A @p typed but not yet committed to a chip would otherwise vanish on
  // send. Fold it in rather than silently dropping a recipient the user
  // clearly meant to add.
  const commitPending = (): string[] => {
    const v = pending.trim().replace(/,$/, '')
    if (!v) return recipients
    // RECIPIENT VALIDATION, BEFORE THE POKE. The nexus parses `to` as a
    // set of @p and refuses the whole send on a bad one, so a typo here
    // would surface as a refusal with nothing pointing at the field that
    // caused it. Checked at the keystroke instead, where it is still a
    // typo. The nexus keeps its own check; this is a convenience and
    // never the boundary.
    if (!isShip(v)) {
      setSendError(`${v} is not a ship name.`)
      return recipients
    }
    setSendError(null)
    if (recipients.includes(v)) { setPending(''); return recipients }
    const next = [...recipients, v]
    setRecipients(next)
    setPending('')
    return next
  }

  const onReply = async () => {
    const forId = id
    const to = commitPending()
    if (to.length === 0) {
      setSendError('Add at least one recipient.')
      return
    }
    setSending(true)
    setSendError(null)
    // The send poke and the post-send refetch are different failures.
    // Only the poke failing means the reply wasn't sent - draft kept, and
    // safe to retry. If it succeeds but the refetch then fails, the reply
    // already went out; clearing the draft and saying so (not "could not
    // send") avoids the user resending a message that already landed.
    // THE BYTES GO UP FIRST. An upload signs nothing and moves no
    // message, so a file that will not upload leaves the reply exactly
    // where it was, with an error naming the file.
    let refs
    try {
      refs = await uploadAll(files, (i, n) => { setUpload(`uploading ${i} of ${n}`) })
    } catch (e) {
      console.error(e)
      // punctuated, for the reason Compose.tsx gives.
      const why = e instanceof Error ? e.message : 'An attachment could not be uploaded'
      setSendError(
        `${why.replace(/[.!?]?$/, '.')}`
        + ' Nothing has been sent — your reply and its files are still here.',
      )
      setUpload(null)
      setSending(false)
      return
    }
    setUpload(null)
    try {
      await send(to, `re: ${target.subject}`, reply, target.id, refs)
    } catch (e) {
      // NO FALSE "SENT" WHEN THE SHIP WAS NEVER REACHED. The worker
      // never touches a POST, so a reply whose request did not arrive
      // was not signed and did not leave. See Compose.tsx.
      console.error(e)
      setSendError(garbled(e)
        // Reached the ship, no readable answer: it may have gone out.
        // Sending it again on a "not sent" would be the duplicate.
        ? 'The ship answered but the reply was unreadable — check Sent before'
          + ' resending. Your reply is still here.'
        : unreachable(e)
          ? 'Offline — not sent. The ship did not answer; nothing was signed and your'
            + ' reply is still here.'
          : 'Could not send that reply. Try again.')
      setSending(false)
      return
    }
    setReply('')
    setFiles([])
    onSent()
    try {
      const th = await thread(forId)
      if (idRef.current === forId && th !== null) setT(th)
    } catch (e) {
      console.error(e)
      setSendError('Sent, but could not refresh this view. Reload to see it.')
    }
    setSending(false)
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
        {branching && (
          <span className="flex shrink-0 items-center" role="group" aria-label="Conversation shape">
            <button
              type="button"
              onClick={() => setView('list')}
              aria-pressed={mode === 'list'}
              title="Every stored copy of every message, oldest first."
              className={`btn rounded-r-none border-line-strong ${mode === 'list' ? 'bg-sunken text-ink' : ''}`}
            >
              List
            </button>
            <button
              type="button"
              onClick={() => setView('tree')}
              aria-pressed={mode === 'tree'}
              title="Who replied to what. A reply or forward ships the path from the root down to
                the message it points at — this is that shape, and a node picked here is what
                the next message points at."
              className={`btn -ml-px rounded-l-none border-line-strong ${mode === 'tree' ? 'bg-sunken text-ink' : ''}`}
            >
              Tree
            </button>
          </span>
        )}
        {/* Forward is a reply addressed elsewhere: same poke, `prev`
            pointing into this chain, `to` naming someone new. The chain
            it carries is the payload, and the recipient can verify every
            author in it without ever having met them - which is why the
            composer says so before the To field. */}
        <button
          type="button"
          disabled={targetForged}
          onClick={() => onForward({
            prev: target.id,
            subject: target.subject,
            count: travels,
          })}
          title={noTarget
            ?? `Hand this line of the conversation to someone new. The ${travels} signed ${travels === 1 ? 'message' : 'messages'} leading to this one travel; other branches do not. The recipient can verify each author independently.`}
          className="btn shrink-0"
        >
          Forward
        </button>
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
        <button
          type="button"
          onClick={onUnread}
          title="Mark every message here unread and go back to the list. Messages whose
            signature failed are left alone: a forgery never counts toward unread."
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
        <button type="button" onClick={addLabel} className="btn btn-outline">
          + label
        </button>
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
          {copiesOf(t.messages, target.id).map((m, i) => (
            <MessageCard key={i} m={m} />
          ))}
        </>
      ) : t.messages.map((m, i) => (
        // Up to 4 copies of a message share the same `id` by design (one
        // genuine, others forged) — index into the fixed, backend-ordered
        // list, not `m.id`, or React's key collision folds distinct
        // verified/forged copies into one node.
        <MessageCard key={i} m={m} />
      ))}
      <div className="mb-1 rounded-sm border border-line p-2">
        <div className="mb-1 flex flex-wrap items-center gap-1">
          <span className="text-ink-dim">To</span>
          {recipients.map((r) => (
            <span
              key={r}
              className="flex max-w-full items-center gap-1 rounded-sm bg-sunken py-0.5 pl-2 pr-1"
            >
              <span className="min-w-0 truncate">{r}</span>
              <button
                type="button"
                onClick={() => setRecipients(recipients.filter((x) => x !== r))}
                aria-label={`Remove ${r}`}
                title={`Remove ${r} from this reply`}
                className="touch shrink-0 px-0.5 text-ink-dim hover:text-danger"
              >
                ×
              </button>
            </span>
          ))}
          <input
            value={pending}
            onChange={(e) => setPending(e.target.value)}
            onBlur={commitPending}
            onKeyDown={(e) => {
              if (e.key === 'Enter' || e.key === ',') {
                e.preventDefault()
                commitPending()
              }
            }}
            placeholder="~sampel-palnet"
            aria-label="Add a recipient"
            className="field min-w-32 flex-1 border-b-0"
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
      {/* max-body in grubbery-overlay/lib/urmail-chain.hoon. See
          Compose.tsx: a guard rail in UTF-16 units, not the authority. */}
      <textarea
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
            || (recipients.length === 0 && !pending.trim())
          }
          title={noTarget ?? undefined}
          className="btn btn-primary"
        >
          {upload ?? (sending ? 'Sending…' : 'Send')}
        </button>
      </div>
      {/* A NODE NOTHING CAN POINT AT. Said here as well as on the two
          disabled controls, because a disabled button's title is not
          something a reader finds without hovering the thing that is
          refusing them. */}
      {noTarget && <p className="mt-1 text-[11px] text-ink-dim">{noTarget}</p>}
      {sendError && <p className="mt-1 text-danger">{sendError}</p>}
    </div>
  )
}

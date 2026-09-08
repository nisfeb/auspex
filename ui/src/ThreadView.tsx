import { useEffect, useRef, useState } from 'react'
import { thread, send, markRead, deleteThread, ourShip, type Thread } from './api'
import VerdictBadge from './VerdictBadge'
import type { ForwardIntent } from './Compose'

// The default reply audience.
//
// NOT `thread.participants`. That set is the union of `from` and `to`
// across every message the agent holds for this thread, INCLUDING ones
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
  id, onSent, onDeleted, onForward, updatedAt,
}: {
  id: string
  onSent: () => void
  onDeleted: () => void
  // Opens the composer as a forward: `prev` set to this thread's newest
  // message and NO recipients. See ForwardIntent in Compose.tsx for why
  // the audience is not carried across.
  onForward: (f: ForwardIntent) => void
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
  const [sendError, setSendError] = useState<string | null>(null)

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
  // delivery, including a delivery the attacker sent. Re-seeding there
  // is worse on the nexus than it was on the agent, because the beacon
  // does not name a thread: any inbound mail at all would re-run this
  // effect for whatever thread is open. Re-seeding would throw
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

  // The stale-thread race: click thread A, then click B before A's scry
  // resolves. React runs A's effect cleanup and B's effect setup back to
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
      th.messages.filter((m) => !m.read).forEach((m) => markRead(m.id).catch(console.error))
    }).catch((e) => {
      if (cancelled) return
      console.error(e)
      setLoadError('Could not load this conversation.')
    })
    return () => { cancelled = true }
  }, [id, updatedAt])

  if (loadError) {
    return <p className="p-8 text-red-600">{loadError}</p>
  }
  if (notFound) {
    return <p className="p-8 text-neutral-400">This conversation no longer exists.</p>
  }
  if (!t) return null
  const last = t.messages[t.messages.length - 1]

  // A @p typed but not yet committed to a chip would otherwise vanish on
  // send. Fold it in rather than silently dropping a recipient the user
  // clearly meant to add.
  const commitPending = (): string[] => {
    const v = pending.trim().replace(/,$/, '')
    if (!v) return recipients
    if (recipients.includes(v)) { setPending(''); return recipients }
    const next = [...recipients, v]
    setRecipients(next)
    setPending('')
    return next
  }

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
    try {
      await send(to, `re: ${last.subject}`, reply, last.id)
    } catch (e) {
      console.error(e)
      setSendError('Could not send that reply. Try again.')
      setSending(false)
      return
    }
    setReply('')
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
    <div className="p-8">
      <div className="mb-6 flex items-start gap-4">
        <h1 className="text-2xl">{t.messages[0].subject}</h1>
        {/* Forward is a reply addressed elsewhere: same poke, `prev`
            pointing into this chain, `to` naming someone new. The chain
            it carries is the payload, and the recipient can verify every
            author in it without ever having met them - which is why the
            composer says so before the To field. */}
        <button
          type="button"
          onClick={() => onForward({
            prev: last.id,
            subject: last.subject,
            count: t.messages.length,
          })}
          title={`Hand this whole conversation to someone new. All ${t.messages.length} signed messages travel; the recipient can verify each author independently.`}
          className="ml-auto shrink-0 rounded-full px-4 py-2 text-sm text-neutral-600 ring-1 ring-neutral-300 hover:text-blue-700 hover:ring-blue-400"
        >
          Forward
        </button>
        <button
          type="button"
          onClick={onDelete}
          title="Remove this conversation from this ship. The only way to free a thread pinned at a capacity limit."
          className="shrink-0 rounded-full px-4 py-2 text-sm text-neutral-500 ring-1 ring-neutral-300 hover:text-red-700 hover:ring-red-400"
        >
          Delete
        </button>
      </div>
      {t.messages.map((m, i) => (
        // Up to 4 copies of a message share the same `id` by design (one
        // genuine, others forged) — index into the fixed, backend-ordered
        // list, not `m.id`, or React's key collision folds distinct
        // verified/forged copies into one node.
        <article key={i} className="mb-6 border-b border-neutral-100 pb-6">
          <header className="mb-2 flex items-center gap-3 text-sm">
            <span className="font-medium">{m.from}</span>
            <VerdictBadge verdict={m.verdict} />
            <span className="ml-auto text-neutral-400">
              {new Date(m.sent).toLocaleString()}
            </span>
          </header>
          <p className="whitespace-pre-wrap">{m.body}</p>
        </article>
      ))}
      <div className="mb-2 rounded border border-neutral-300 p-3">
        <div className="mb-2 flex flex-wrap items-center gap-2">
          <span className="text-sm text-neutral-500">To</span>
          {recipients.map((r) => (
            <span
              key={r}
              className="flex items-center gap-1 rounded-full bg-neutral-100 py-1 pl-3 pr-2 text-sm"
            >
              {r}
              <button
                type="button"
                onClick={() => setRecipients(recipients.filter((x) => x !== r))}
                aria-label={`Remove ${r}`}
                title={`Remove ${r} from this reply`}
                className="px-1 text-neutral-500 hover:text-red-600"
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
            className="min-w-40 flex-1 py-1 text-sm outline-none"
          />
        </div>
        <p className="text-xs text-neutral-500">
          Everyone listed receives the entire signed chain, not just this
          reply. Anyone who was ever added to this conversation appears here
          — remove anyone who should not get the history.
        </p>
      </div>
      {/* max-body in grubbery-overlay/lib/urmail-chain.hoon. See
          Compose.tsx: a guard rail in UTF-16 units, not the authority. */}
      <textarea
        value={reply}
        onChange={(e) => setReply(e.target.value)}
        maxLength={100000}
        placeholder="Reply"
        className="h-28 w-full rounded border border-neutral-300 p-3"
      />
      <div className="mt-2 flex items-center gap-3">
        <button
          onClick={onReply}
          disabled={!reply.trim() || sending || (recipients.length === 0 && !pending.trim())}
          className="rounded-full bg-blue-600 px-6 py-2 text-white disabled:opacity-40"
        >
          {sending ? 'Sending…' : 'Send'}
        </button>
        {sendError && <span className="text-sm text-red-600">{sendError}</span>}
      </div>
    </div>
  )
}

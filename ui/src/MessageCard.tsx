import { useId, useMemo, useState, type ReactNode } from 'react'
import { AttachmentRow } from './Attachments'
import VerdictBadge from './VerdictBadge'
import ShipChips, { addMembers, commitShip } from './ShipChips'
import { listNameError, type MailList, type Message } from './api'
import { ownWords, quoteBlocks } from './quote'

// ONE MESSAGE, RENDERED ONCE. The list view stacks these in `sent`
// order and the tree view shows the copies of whichever node is
// selected — the same component in both, because a second renderer is
// a second set of decisions about hostile input, and the two would
// disagree the first time one of them was fixed.
//
// A COPY, NOT A MESSAGE. Up to `max-copies` grubs share one id and
// differ only in signature (one genuine, the rest forged), which is why
// callers key on their position in the backend-ordered list rather than
// on `m.id`.
export default function MessageCard({
  m, lists, onSaveList, onReply, onForward, targeted, folded, onFold,
}: {
  m: Message
  // FOLDED: the header and one line of what it says. The state lives on
  // the ship (see Thread.folded), so the card only asks to change it.
  folded?: boolean
  onFold?: (fold: boolean) => void
  // REPLY AND FORWARD ON THE MESSAGE ITSELF. Answering one used to mean
  // switching to the tree, picking its node, and going back up to the
  // top of the thread; now it is the message you are looking at. Absent
  // for a copy whose signature failed: nothing may point at it.
  onReply?: () => void
  onForward?: () => void
  // This is the message the reply box below answers.
  targeted?: boolean
  // The lists this ship holds, so the Save-as-list form can offer their
  // names and say when a save will OVERWRITE one. Optional, and the
  // control is absent without a handler: a card rendered somewhere with
  // no list surface should not grow a dead button.
  lists?: MailList[]
  onSaveList?: (l: MailList) => Promise<void>
}) {
  const [saving, setSaving] = useState(false)
  const [copied, setCopied] = useState(false)
  // A DOM id that is unique per card. Several cards render at once and a
  // thread can hold several copies of one message, so keying the
  // datalist on the message id would collide — and a duplicated id
  // silently binds every input to the first one.
  const listId = useId()
  // The audience of THIS message, as the list would start out: the
  // author and everyone it names, minus us.
  //
  // THIS IS THE WHOLE "COPY THE GROUNDWIRE LIST OFF THIS MONTH'S
  // MESSAGE" FLOW, and it works because a list name never travels. There
  // is no list in this message to recover — there never was one, the
  // sender expanded theirs before signing — so there is nothing to
  // reconstruct and nothing to get wrong: these are the ships the
  // message actually went to, and saving them under a name is the only
  // honest thing the data supports.
  const seed = () => addMembers([], [m.from, ...m.to])
  const [name, setName] = useState('')
  const [members, setMembers] = useState<string[]>([])
  const [pending, setPending] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [done, setDone] = useState(false)
  // Parsed once per body: the thread re-renders every card on each
  // keystroke in its reply box, and a body can be 100,000 characters.
  const blocks = useMemo(() => quoteBlocks(m.body), [m.body])

  const open = () => {
    setName('')
    setMembers(seed())
    setPending('')
    setError(null)
    setDone(false)
    setSaving(true)
  }

  // A name that already exists is an OVERWRITE, said before the button
  // is pressed and not after. No tracking, no merge, no "sync from this
  // message": the stored membership becomes exactly what is on screen.
  const clash = (lists ?? []).find((l) => l.name === name.trim().toLowerCase())

  const save = async () => {
    const n = name.trim().toLowerCase()
    const bad = listNameError(n)
    if (bad) { setError(bad); return }
    // The half-typed member nobody committed is still a member they meant.
    const { ships: final, error: chipError } = commitShip(members, pending)
    if (chipError) { setError(chipError); return }
    setMembers(final)
    setPending('')
    try {
      await onSaveList!({ name: n, members: final })
      setDone(true)
      setSaving(false)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save that list.')
    }
  }

  const frame = (children: ReactNode) => (
    <article
      className={`mb-3 border-b border-line pb-3
        ${targeted ? 'border-l-2 border-l-accent pl-2' : ''}`}
      aria-current={targeted ? 'true' : undefined}
    >
      {children}
    </article>
  )

  const header = (
    <header className="mb-1 flex min-w-0 flex-wrap items-center gap-x-2">
      <VerdictBadge verdict={m.verdict} from={m.from} />
      <span className="min-w-0 truncate font-medium">{m.from}</span>
      <span className="ml-auto shrink-0 text-[11px] text-ink-faint">
        {new Date(m.sent).toLocaleString()}
      </span>
      {onReply && (
        <button type="button" onClick={onReply} className="btn shrink-0" title="Reply to this message">
          Reply
        </button>
      )}
      {onForward && (
        <button
          type="button"
          onClick={onForward}
          className="btn shrink-0"
          title="Hand this message, and the signed messages leading to it, to someone new"
        >
          Forward
        </button>
      )}
      {onFold && (
        <button
          type="button"
          onClick={() => onFold(!folded)}
          aria-expanded={!folded}
          className="btn shrink-0"
          title={folded ? 'Show this message in full' : 'Collapse this message to one line'}
        >
          {folded ? 'Unfold' : 'Fold'}
        </button>
      )}
    </header>
  )

  // ponytail: one line of the sender's own words; a body that is all
  // quote falls back to the quote.
  if (folded) {
    return frame(<>
      {header}
      <button
        type="button"
        onClick={() => onFold?.(false)}
        className="block w-full truncate text-left text-ink-dim"
      >
        {ownWords(m.body) || m.body}
      </button>
    </>)
  }

  return frame(<>
    {header}
    {/* `break-words`, not just `whitespace-pre-wrap`: a body is
        attacker-chosen text and one unbroken 400-character token
        would otherwise decide how wide this pane is.

        A QUOTE IS SET OFF, a rule beside it and quieter text: lines
        somebody took from an earlier message, inside what this
        sender says. Still plain text, still React-escaped. */}
    {blocks.map((b, i) => b.quoted ? (
      <blockquote
        key={i}
        className="my-1 whitespace-pre-wrap break-words border-l-2 border-line-strong pl-2 text-ink-dim"
      >
        {b.text}
      </blockquote>
    ) : (
      <p key={i} className="whitespace-pre-wrap break-words">{b.text}</p>
    ))}
    {/* body-mime is signed, so an intermediary cannot change which
        message you read — but a signature proves the author CHOSE
        the value, never that it is safe, and the chain carrying it
        may have been delivered by any ship. So the instruction is
        reported and not obeyed: every body renders as plain text,
        and a message that asked for anything else says so rather
        than looking like a rendering bug. */}
    {m['body-mime'] && m['body-mime'] !== 'text/plain' && (
      <p className="mt-1 text-[11px] text-ink-dim">
        Sent as <code>{m['body-mime']}</code>; shown as plain text.
      </p>
    )}
    {/* ATTACHMENTS. Metadata plus the one action the bytes can
        honestly support: download what this ship holds, and fetch
        what it does not. Nothing is pushed, so an attachment we
        have not pulled is the ordinary state of an inbound file
        and says so rather than reading as an error.

        `mime` is rendered as text, on its own line, marked as the
        sender's claim. It never picks an icon, never picks a
        renderer, never reaches a header. It arrives pre-signed
        inside a chain any ship may deliver, so the signature proves
        the author chose it and nothing else — same argument as
        body-mime above, which is why they read the same way.

        The name is the other hostile field and is treated as text
        for the same reason: React escapes it, `break-all` stops a
        long one from pushing the layout around, and nothing here
        ever treats it as a path. */}
    {(m.attachments?.length ?? 0) > 0 && (
      <ul className="mt-2 space-y-1">
        {m.attachments!.map((a, j) => (
          // `from` is a HINT about where to look for the bytes and
          // nothing more: any ship holding them may serve them,
          // the hash proves them, and naming the wrong ship costs
          // a miss and never a bad file. The author is the best
          // guess available from a message alone.
          <AttachmentRow key={j} a={a} from={m.from} />
        ))}
      </ul>
    )}
    {/* SAVE THE AUDIENCE OF THIS MESSAGE AS A LIST. Text-weight, like
        every other per-message control: the primary action on a thread
        is the reply, and exactly one control per surface may look like
        one. */}
    <p className="mt-1 flex flex-wrap gap-1">
      {/* The whole body in one go: selecting it works too, but a long
          message is a long drag. */}
      <button
        type="button"
        onClick={() => {
          void navigator.clipboard?.writeText(m.body).then(() => { setCopied(true) })
        }}
        className="btn"
      >
        {copied ? 'Copied' : 'Copy'}
      </button>
      {onSaveList && !saving && (
        <button type="button" onClick={open} className="btn">
          {done ? 'Saved as a list' : 'Save as list'}
        </button>
      )}
    </p>
    {onSaveList && saving && (
      <div className="mt-2 max-w-prose space-y-1 rounded-sm border border-line p-2">
        <h3 className="font-medium">Save these ships as a list</h3>
        {/* A LIST NAME IS LOCAL AND NEVER TRAVELS. Said here because
            this is the one place a user might think they are naming
            something the recipients will see. */}
        <p className="text-[11px] text-ink-dim">
          The name is yours and stays on this ship — it is never sent and no
          recipient ever sees it. What a list does is put ships in the To
          field.
        </p>
        <input
          value={name}
          onChange={(e) => { setName(e.target.value); setError(null) }}
          list={listId}
          placeholder="groundwire"
          aria-label="List name"
          className="field"
        />
        <datalist id={listId}>
          {(lists ?? []).map((l) => <option key={l.name} value={l.name} />)}
        </datalist>
        {clash && (
          <p className="text-[11px] text-warn-ink">
            A list called “{clash.name}” already exists; saving overwrites its{' '}
            {clash.members.length}{' '}
            {clash.members.length === 1 ? 'member' : 'members'}.
          </p>
        )}
        <ShipChips
          ships={members}
          pending={pending}
          onShips={setMembers}
          onPending={setPending}
          onError={setError}
          label="Members"
        />
        <div className="flex items-center gap-2 pt-1">
          <button type="button" onClick={save} className="btn btn-primary">
            Save list
          </button>
          <button type="button" onClick={() => setSaving(false)} className="btn">
            Cancel
          </button>
        </div>
        {error && <p className="text-danger">{error}</p>}
      </div>
    )}
  </>)
}

import { useId, useState } from 'react'
import { AttachmentRow } from './Attachments'
import VerdictBadge from './VerdictBadge'
import ShipChips, { commitShip } from './ShipChips'
import { ourShip, type MailList, type Message } from './api'

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
  m, lists, onSaveList,
}: {
  m: Message
  // The lists this ship holds, so the Save-as-list form can offer their
  // names and say when a save will OVERWRITE one. Optional, and the
  // control is absent without a handler: a card rendered somewhere with
  // no list surface should not grow a dead button.
  lists?: MailList[]
  onSaveList?: (l: MailList) => Promise<void>
}) {
  const [saving, setSaving] = useState(false)
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
  const seed = () => {
    const all = [m.from, ...m.to]
    const out: string[] = []
    for (const s of all) {
      if (s === ourShip) continue
      if (!out.includes(s)) out.push(s)
    }
    return out
  }
  const [name, setName] = useState('')
  const [members, setMembers] = useState<string[]>([])
  const [pending, setPending] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [done, setDone] = useState(false)

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
    if (!n) { setError('A list needs a name.'); return }
    if (!/^[a-z0-9-]{1,64}$/.test(n)) {
      setError('A list name is 1–64 lowercase letters, digits or hyphens.')
      return
    }
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

  return (
    <article className="mb-3 border-b border-line pb-3">
      <header className="mb-1 flex min-w-0 items-center gap-2">
        <VerdictBadge verdict={m.verdict} from={m.from} />
        <span className="min-w-0 truncate font-medium">{m.from}</span>
        <span className="ml-auto shrink-0 text-[11px] text-ink-faint">
          {new Date(m.sent).toLocaleString()}
        </span>
      </header>
      {/* `break-words`, not just `whitespace-pre-wrap`: a body is
          attacker-chosen text and one unbroken 400-character token
          would otherwise decide how wide this pane is. */}
      <p className="whitespace-pre-wrap break-words">{m.body}</p>
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
      {onSaveList && !saving && (
        <p className="mt-1">
          <button type="button" onClick={open} className="btn">
            {done ? 'Saved as a list' : 'Save as list'}
          </button>
        </p>
      )}
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
    </article>
  )
}

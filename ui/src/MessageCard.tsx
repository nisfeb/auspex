import { AttachmentRow } from './Attachments'
import VerdictBadge from './VerdictBadge'
import type { Message } from './api'

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
export default function MessageCard({ m }: { m: Message }) {
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
    </article>
  )
}

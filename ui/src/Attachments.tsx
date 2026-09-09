import { useEffect, useRef, useState } from 'react'
import {
  fetchAttachment, getAttachment, MAX_ATTACH, MAX_BLOB, saveBlob,
  type Attachment,
} from './api'

// `size` in something a person reads. It is signed and tied to the
// content hash, so unlike the name and the mime type it cannot drift
// from the bytes — which makes it the one attachment field worth
// rendering prominently.
export function fileSize(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes < 0) return 'unknown size'
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

// ── attaching ────────────────────────────────────────────────────────

// The file control, shared by Compose and the reply composer.
//
// REFUSES BEFORE IT SENDS. max-blob is 256K and max-attach is 16, and
// the nexus checks both again on the decoded bytes — but a file refused
// here is refused at the moment the user picked it, while a file refused
// there is refused after a quarter-megabyte round trip. Both checks
// exist; only this one can say which file was the problem while the user
// still has the dialog in mind.
//
// The bytes are NOT read here. A File handle costs nothing; base64 of
// one costs 4/3 of the file in a JS string, and holding that from the
// moment of picking until the moment of sending would mean every open
// composer carrying its attachments in memory. They are read in the
// send handler, once.
export function FilePicker({
  files, onChange, disabled,
}: {
  files: File[]
  onChange: (fs: File[]) => void
  disabled?: boolean
}) {
  const [error, setError] = useState<string | null>(null)

  const add = (picked: FileList | null) => {
    if (!picked || picked.length === 0) return
    const incoming = [...picked]
    // Size first, and named: "one of your files is too big" is not
    // something a user can act on.
    const big = incoming.filter((f) => f.size > MAX_BLOB)
    if (big.length > 0) {
      setError(
        `${big.map((f) => f.name).join(', ')}: over the ${fileSize(MAX_BLOB)} limit`
        + ' for one attachment. Attachments travel over the ship-to-ship'
        + ' namespace, which has no partial-progress story yet.',
      )
      return
    }
    const next = [...files, ...incoming]
    if (next.length > MAX_ATTACH) {
      setError(`A message carries at most ${MAX_ATTACH} attachments.`)
      return
    }
    setError(null)
    onChange(next)
  }

  return (
    <div className="mt-1">
      <label className="btn touch cursor-pointer">
        <input
          type="file"
          multiple
          disabled={disabled}
          className="hidden"
          onChange={(e) => {
            add(e.target.files)
            // Cleared so picking the same file twice in a row still
            // fires a change event.
            e.target.value = ''
          }}
        />
        + attach a file
      </label>
      {files.length > 0 && (
        <ul className="mt-1 space-y-0.5">
          {files.map((f, i) => (
            <li
              key={`${f.name}-${i}`}
              className="flex min-w-0 items-center gap-2 rounded-sm border border-line px-2 py-0.5"
            >
              <span className="min-w-0 break-all">{f.name}</span>
              <span className="shrink-0 text-ink-faint">{fileSize(f.size)}</span>
              <button
                type="button"
                aria-label={`Remove ${f.name}`}
                onClick={() => { onChange(files.filter((_, j) => j !== i)) }}
                className="btn btn-danger ml-auto shrink-0"
              >
                ×
              </button>
            </li>
          ))}
        </ul>
      )}
      {error && <p className="mt-1 text-[11px] text-danger">{error}</p>}
    </div>
  )
}

// ── downloading ──────────────────────────────────────────────────────

// How long to keep asking after a fetch is queued, and how often. The
// keen probes up to three cases with a ten-second deadline each, so a
// miss takes about thirty seconds to be a miss. Nothing pushes the
// arrival — a blob landing does not move the change beacon, because it
// is not message content — so this is the client's own patience.
const POLL_MS = 2000
const POLL_TRIES = 20

type State =
  | { at: 'idle' }
  | { at: 'busy'; why: string }
  | { at: 'absent' }
  | { at: 'error'; why: string }

// One attachment, with whatever action it can honestly offer.
//
// THREE STATES, AND THEY ARE NOT THE SAME. Bytes we hold download.
// Bytes we do not hold are NOT MISSING: they were never pushed, so an
// unfetched attachment is the ordinary state of an inbound file and the
// honest control is "fetch it", not an error. Bytes we asked for and
// did not get are a miss — the file may be on a ship that is offline,
// or nowhere at all, and blobs are a cache, so losing one loses a file
// and never a message or a signature.
export function AttachmentRow({ a, from }: { a: Attachment; from: string }) {
  const [state, setState] = useState<State>({ at: 'idle' })

  // IS THIS ROW STILL ON SCREEN? `pull` below sleeps and asks up to
  // twenty times over forty seconds, and a thread the user navigated
  // away from unmounts every row in it. Without this the poll keeps
  // running against a dead component: twenty more requests to the ship
  // for bytes nobody is waiting on, each one ending in a setState React
  // discards. Checked after every await, because every await is a point
  // where the component can have gone.
  const alive = useRef(true)
  useEffect(() => () => { alive.current = false }, [])

  const download = async () => {
    setState({ at: 'busy', why: 'Opening…' })
    try {
      const b = await getAttachment(a)
      if (!alive.current) return
      if (b === null) { setState({ at: 'absent' }); return }
      saveBlob(b)
      setState({ at: 'idle' })
    } catch (e) {
      console.error(e)
      if (!alive.current) return
      setState({ at: 'error', why: e instanceof Error ? e.message : 'Could not open that file.' })
    }
  }

  // Queue the keen, then keep asking. The route answers as soon as the
  // writer has taken the request, never when the bytes land.
  const pull = async () => {
    setState({ at: 'busy', why: 'Fetching from the network…' })
    try {
      await fetchAttachment(a, from)
    } catch (e) {
      console.error(e)
      if (!alive.current) return
      setState({ at: 'error', why: e instanceof Error ? e.message : 'Could not ask for that file.' })
      return
    }
    if (!alive.current) return
    for (let i = 0; i < POLL_TRIES; i += 1) {
      await new Promise((r) => { setTimeout(r, POLL_MS) })
      if (!alive.current) return
      try {
        const b = await getAttachment(a)
        if (!alive.current) return
        if (b !== null) {
          saveBlob(b)
          setState({ at: 'idle' })
          return
        }
      } catch (e) {
        console.error(e)
        if (!alive.current) return
        setState({ at: 'error', why: e instanceof Error ? e.message : 'Could not open that file.' })
        return
      }
    }
    setState({
      at: 'error',
      why: 'Nobody answered with those bytes. The sender may be offline;'
        + ' the message and its signature are unaffected.',
    })
  }

  return (
    <li className="rounded-sm border border-line px-2 py-1">
      <div className="flex flex-wrap items-center gap-2">
        <span className="min-w-0 break-all">{a.name || '(unnamed file)'}</span>
        <span className="shrink-0 text-ink-faint">{fileSize(a.size)}</span>
        {/* `mime` is rendered as text, marked as the sender's claim. It
            never picks an icon, never picks a renderer, and the byte
            route refuses to echo it into a header unless it is on a
            fixed allow-list. It arrives pre-signed inside a chain any
            ship may deliver, so the signature proves the author chose
            it and nothing else. */}
        {a.mime && (
          <span className="text-[11px] text-ink-faint">
            sender says <code>{a.mime}</code>
          </span>
        )}
        {state.at === 'busy' ? (
          <span className="ml-auto text-[11px] text-ink-dim">{state.why}</span>
        ) : state.at === 'absent' ? (
          <button
            type="button"
            onClick={() => { void pull() }}
            title="This ship does not hold these bytes yet. Attachments are never
              pushed: the message carries the file's content hash and the bytes are
              pulled on request from whoever has them. The hash proves them."
            className="btn btn-outline ml-auto"
          >
            Fetch
          </button>
        ) : (
          <button
            type="button"
            onClick={() => { void download() }}
            className="btn btn-outline ml-auto"
          >
            Download
          </button>
        )}
      </div>
      {state.at === 'absent' && (
        <p className="mt-1 text-[11px] text-ink-dim">
          Not fetched yet — this ship holds the message, not the bytes.
        </p>
      )}
      {state.at === 'error' && <p className="mt-1 text-[11px] text-danger">{state.why}</p>}
    </li>
  )
}

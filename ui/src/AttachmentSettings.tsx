import { useEffect, useState } from 'react'
import {
  attachmentSettings, MAX_BLOB, saveAttachmentSettings, type AttachmentSettings,
} from './api'
import ShipChips, { commitShip } from './ShipChips'

// WHICH ATTACHMENTS DOWNLOAD ON THEIR OWN. Nothing does by default: a
// delivered message carries only an attachment's hash and details, and
// the bytes come when the owner fetches them or under a rule set here.
//
// The allow list is the real protection. A size limit only holds an
// honest sender to their claim — the sending ship decides what it
// serves, and this ship logs the bytes before it can measure them — so
// the panel says so rather than letting a size feel like a guard.

const MiB = 1024 * 1024
const toMiB = (b: number) => String(Math.round((b / MiB) * 10) / 10)

export default function AttachmentSettings({ onClose }: { onClose: () => void }) {
  const [loaded, setLoaded] = useState<AttachmentSettings | null>(null)
  const [auto, setAuto] = useState('0')
  const [budget, setBudget] = useState('64')
  const [allow, setAllow] = useState<string[]>([])
  const [block, setBlock] = useState<string[]>([])
  const [allowPending, setAllowPending] = useState('')
  const [blockPending, setBlockPending] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [saved, setSaved] = useState(false)

  useEffect(() => {
    attachmentSettings().then((s) => {
      setLoaded(s)
      setAuto(toMiB(s['auto-size']))
      setBudget(toMiB(s.budget))
      setAllow(s.allow)
      setBlock(s.block)
    }).catch(() => setError('Could not load the attachment settings.'))
  }, [])

  const save = async () => {
    setError(null)
    setSaved(false)
    const a = commitShip(allow, allowPending)
    if (a.error) { setError(a.error); return }
    const b = commitShip(block, blockPending)
    if (b.error) { setError(b.error); return }
    const both = a.ships.filter((s) => b.ships.includes(s))
    if (both.length) {
      setError(`${both.join(', ')} is on both lists. A ship can be allowed or blocked, not both.`)
      return
    }
    const autoBytes = Math.round(Number(auto) * MiB)
    const budgetBytes = Math.round(Number(budget) * MiB)
    if (!Number.isFinite(autoBytes) || autoBytes < 0 || autoBytes > MAX_BLOB) {
      setError(`The size for other ships must be between 0 and ${toMiB(MAX_BLOB)} MB.`)
      return
    }
    if (!Number.isFinite(budgetBytes) || budgetBytes < MAX_BLOB) {
      setError(`Storage must be at least ${toMiB(MAX_BLOB)} MB, enough for one largest file.`)
      return
    }
    try {
      await saveAttachmentSettings({ 'auto-size': autoBytes, allow: a.ships, block: b.ships, budget: budgetBytes })
      setAllow(a.ships); setBlock(b.ships); setAllowPending(''); setBlockPending('')
      setSaved(true)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save the attachment settings.')
    }
  }

  return (
    <div className="min-w-0 flex-1 overflow-y-auto p-3">
      <div className="mb-3 flex items-center gap-2">
        <h1 className="text-base font-medium">Attachments</h1>
        <button type="button" onClick={onClose} className="btn btn-outline ml-auto">
          Close
        </button>
      </div>

      <p className="mb-3 max-w-prose rounded-sm bg-sunken p-2 text-ink-dim ring-1 ring-line">
        A message arrives with only its attachments’ names and sizes. The files
        themselves come to this ship when you fetch them, or on their own under the
        rules below. Only messages whose signature checked out download on their own.
        A file can be at most {toMiB(MAX_BLOB)} MB.
      </p>

      {!loaded && !error && <p className="text-ink-faint">Loading…</p>}
      {loaded && (
        <div className="max-w-prose space-y-3">
          <section className="space-y-1 rounded-sm border border-line p-2">
            <h2 className="font-medium">Always download from</h2>
            <p className="text-[11px] text-ink-dim">
              Files from these ships download as their messages arrive, up to the
              largest file allowed.
            </p>
            <ShipChips
              ships={allow}
              pending={allowPending}
              onShips={(s) => { setAllow(s); setSaved(false) }}
              onPending={setAllowPending}
              onError={setError}
              label="Allowed ships"
            />
          </section>

          <section className="space-y-1 rounded-sm border border-line p-2">
            <h2 className="font-medium">Never download from</h2>
            <p className="text-[11px] text-ink-dim">
              Files from these ships never download on their own. You can still fetch
              one by hand.
            </p>
            <ShipChips
              ships={block}
              pending={blockPending}
              onShips={(s) => { setBlock(s); setSaved(false) }}
              onPending={setBlockPending}
              onError={setError}
              label="Blocked ships"
            />
          </section>

          <section className="space-y-1 rounded-sm border border-line p-2">
            <h2 className="font-medium">Everyone else</h2>
            <label className="flex items-center gap-2">
              <span>Download files up to</span>
              <input
                type="number"
                min="0"
                max={toMiB(MAX_BLOB)}
                step="0.1"
                value={auto}
                onChange={(e) => { setAuto(e.target.value); setSaved(false) }}
                aria-label="Largest file to download from other ships, in MB"
                className="field w-24"
              />
              <span>MB</span>
            </label>
            <p className="text-[11px] text-ink-dim">
              0 downloads nothing from ships on neither list. The size is what the
              sender says; a hostile ship can send more than it says, so only the
              allow list truly keeps a stranger’s files out.
            </p>
          </section>

          <section className="space-y-1 rounded-sm border border-line p-2">
            <h2 className="font-medium">Storage</h2>
            <label className="flex items-center gap-2">
              <span>Keep up to</span>
              <input
                type="number"
                min={toMiB(MAX_BLOB)}
                step="1"
                value={budget}
                onChange={(e) => { setBudget(e.target.value); setSaved(false) }}
                aria-label="Storage for attachments, in MB"
                className="field w-24"
              />
              <span>MB of attachments</span>
            </label>
            <p className="text-[11px] text-ink-dim">
              Files live in your ship’s memory, so keep this well inside what your
              ship was given. Automatic downloads stop at three quarters of it, leaving
              room for files you fetch yourself. When it is full, files no message
              refers to any more are dropped first.
            </p>
          </section>

          <div className="flex items-center gap-2">
            <button type="button" onClick={save} className="btn btn-primary">
              Save
            </button>
            {saved && <span className="text-ink-dim">Saved.</span>}
          </div>
        </div>
      )}
      {error && <p className="mt-2 text-danger">{error}</p>}
    </div>
  )
}

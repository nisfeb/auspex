import { useState } from 'react'
import { isShip, newId, type Rule } from './api'

// WHAT A FILTER CAN AND CANNOT DO, said on the panel rather than in a
// document nobody opens.
//
// A rule may add labels and it may archive. It cannot delete a message,
// cannot mark one read, and cannot hide one whose signature failed —
// there is no field in the rule for any of it, and rules run after
// verification and after the message is stored. That matters because
// rules are a standing instruction and subject lines are guessable: a
// filter that could quarantine "anything from ~evil" would be a way for
// ~evil to make the evidence of their own forgery land somewhere the
// user never looks.
export default function Filters({
  rules, onSave, onDelete, onClose,
}: {
  rules: Rule[]
  onSave: (r: Rule) => Promise<void>
  onDelete: (id: string) => void
  onClose: () => void
}) {
  const [from, setFrom] = useState('')
  const [subject, setSubject] = useState('')
  const [labels, setLabels] = useState('')
  const [archive, setArchive] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const shipBad = from.trim() !== '' && !isShip(from.trim())

  const add = async () => {
    setError(null)
    const f = from.trim()
    const s = subject.trim()
    if (!f && !s) {
      setError('A rule needs a sender or a subject. One with neither matches every'
        + ' message that arrives.')
      return
    }
    if (f && !isShip(f)) {
      setError(`${f} is not a ship name.`)
      return
    }
    try {
      await onSave({
        id: newId(),
        from: f || null,
        subject: s || null,
        add: labels.split(',').map((x) => x.trim()).filter(Boolean),
        archive,
      })
      setFrom(''); setSubject(''); setLabels(''); setArchive(false)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save that rule.')
    }
  }

  return (
    <div className="min-w-0 flex-1 overflow-y-auto p-3">
      <div className="mb-3 flex items-center gap-2">
        <h1 className="text-base font-medium">Filters</h1>
        <button type="button" onClick={onClose} className="btn btn-outline ml-auto">
          Close
        </button>
      </div>

      <p className="mb-3 max-w-prose rounded-sm bg-sunken p-2 text-ink-dim ring-1 ring-line">
        Rules run on mail as it arrives, <strong>after</strong> its signatures have
        been checked and after it has been stored. A rule can add labels and send a
        thread straight to Archived. It cannot delete anything, cannot mark anything
        read, and cannot hide a message whose signature failed — a forged message is
        evidence, and no rule you write can make it disappear.
      </p>

      <ul className="mb-4 max-w-prose space-y-1">
        {rules.length === 0 && <li className="text-ink-faint">No filters yet.</li>}
        {rules.map((r) => (
          <li
            key={r.id}
            className="flex min-w-0 items-center gap-2 rounded-sm border border-line px-2 py-1"
          >
            <span className="min-w-0 flex-1">
              {r.from && <>from <code>{r.from}</code> </>}
              {r.from && r.subject && 'and '}
              {r.subject && <>subject contains “{r.subject}” </>}
              →{' '}
              {r.add.length > 0 && <>label {r.add.join(', ')}</>}
              {r.add.length > 0 && r.archive && ', '}
              {r.archive && 'skip the inbox'}
              {r.add.length === 0 && !r.archive && <em>do nothing</em>}
            </span>
            <button
              type="button"
              onClick={() => onDelete(r.id)}
              aria-label="Delete this filter"
              className="btn btn-danger shrink-0"
            >
              ×
            </button>
          </li>
        ))}
      </ul>

      <div className="max-w-prose space-y-1 rounded-sm border border-line p-2">
        <h2 className="font-medium">New filter</h2>
        <input
          value={from} onChange={(e) => setFrom(e.target.value)}
          placeholder="From (~sampel-palnet)"
          aria-label="From"
          className={`field ${shipBad ? 'field-bad' : ''}`}
        />
        {shipBad && (
          <p className="text-[11px] text-danger">Not a ship name.</p>
        )}
        <input
          value={subject} onChange={(e) => setSubject(e.target.value)}
          placeholder="Subject contains"
          aria-label="Subject contains"
          className="field"
        />
        <input
          value={labels} onChange={(e) => setLabels(e.target.value)}
          placeholder="Add labels (comma separated, lowercase)"
          aria-label="Labels to add"
          className="field"
        />
        <label className="touch flex items-center gap-2 py-1">
          <input
            type="checkbox"
            checked={archive}
            onChange={(e) => setArchive(e.target.checked)}
          />
          Skip the inbox (archive it)
        </label>
        <button
          type="button"
          onClick={add}
          className="btn btn-primary"
        >
          Add filter
        </button>
        {error && <p className="text-danger">{error}</p>}
      </div>
    </div>
  )
}

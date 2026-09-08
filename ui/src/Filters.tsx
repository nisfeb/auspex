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
    <div className="flex-1 overflow-y-auto p-8">
      <div className="mb-6 flex items-start gap-4">
        <h1 className="text-2xl">Filters</h1>
        <button
          type="button"
          onClick={onClose}
          className="ml-auto rounded-full px-4 py-2 text-sm text-neutral-600 ring-1 ring-neutral-300"
        >
          Close
        </button>
      </div>

      <p className="mb-6 max-w-prose rounded bg-neutral-100 p-3 text-sm text-neutral-700 ring-1 ring-neutral-300">
        Rules run on mail as it arrives, <strong>after</strong> its signatures have
        been checked and after it has been stored. A rule can add labels and send a
        thread straight to Archived. It cannot delete anything, cannot mark anything
        read, and cannot hide a message whose signature failed — a forged message is
        evidence, and no rule you write can make it disappear.
      </p>

      <ul className="mb-8 max-w-prose space-y-2">
        {rules.length === 0 && <li className="text-sm text-neutral-400">No filters yet.</li>}
        {rules.map((r) => (
          <li
            key={r.id}
            className="flex items-center gap-3 rounded border border-neutral-200 px-3 py-2 text-sm"
          >
            <span className="flex-1">
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
              className="text-neutral-400 hover:text-red-600"
            >
              ×
            </button>
          </li>
        ))}
      </ul>

      <div className="max-w-prose space-y-2 rounded border border-neutral-300 p-4">
        <h2 className="text-sm font-medium">New filter</h2>
        <input
          value={from} onChange={(e) => setFrom(e.target.value)}
          placeholder="From (~sampel-palnet)"
          aria-label="From"
          className={`w-full border-b py-2 text-sm outline-none
            ${shipBad ? 'border-red-400' : 'border-neutral-200'}`}
        />
        {shipBad && (
          <p className="text-xs text-red-600">Not a ship name.</p>
        )}
        <input
          value={subject} onChange={(e) => setSubject(e.target.value)}
          placeholder="Subject contains"
          aria-label="Subject contains"
          className="w-full border-b border-neutral-200 py-2 text-sm outline-none"
        />
        <input
          value={labels} onChange={(e) => setLabels(e.target.value)}
          placeholder="Add labels (comma separated, lowercase)"
          aria-label="Labels to add"
          className="w-full border-b border-neutral-200 py-2 text-sm outline-none"
        />
        <label className="flex items-center gap-2 py-2 text-sm">
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
          className="rounded-full bg-blue-600 px-6 py-2 text-sm text-white"
        >
          Add filter
        </button>
        {error && <p className="text-sm text-red-600">{error}</p>}
      </div>
    </div>
  )
}

import { useState } from 'react'
import type { MailList } from './api'
import ShipChips, { commitShip } from './ShipChips'

// WHAT A MAILING LIST IS AND IS NOT, said on the panel rather than in a
// document nobody opens.
//
// A list is a name and a set of ships, stored on this ship only. The
// name never travels: picking a list in the composer puts its members
// into the To field as ordinary ships, and what the recipients receive
// is that — every one of them sees every other, exactly as if the sender
// had typed the names one at a time. There is no hidden audience here,
// because there is nowhere in a signed message for one to hide.

// One row, edited in place. A member is added or dropped with a single
// click and the whole set is re-saved, because %save-list is an
// OVERWRITE and that is the only verb: create, add, remove, rename and
// copy-from-a-message are all "store exactly this set under this name".
function ListRow({
  l, onSave, onDelete,
}: {
  l: MailList
  onSave: (next: MailList) => Promise<void>
  onDelete: () => void
}) {
  const [pending, setPending] = useState('')
  const [error, setError] = useState<string | null>(null)
  // Deleting a list destroys an audience the user assembled by hand and
  // no undo exists, so the control asks once. It is the same two-step
  // the thread delete uses: one click arms it, the next does it.
  const [armed, setArmed] = useState(false)

  const write = async (members: string[]) => {
    try {
      await onSave({ name: l.name, members })
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save that list.')
    }
  }

  return (
    <li className="rounded-sm border border-line p-2">
      <div className="mb-1 flex min-w-0 items-center gap-2">
        <span className="min-w-0 truncate font-medium">{l.name}</span>
        <span className="shrink-0 text-[11px] text-ink-faint">
          {l.members.length} {l.members.length === 1 ? 'member' : 'members'}
        </span>
        {armed ? (
          <>
            <button
              type="button"
              onClick={onDelete}
              className="btn btn-danger ml-auto shrink-0"
            >
              Delete “{l.name}”
            </button>
            <button
              type="button"
              onClick={() => setArmed(false)}
              className="btn shrink-0"
            >
              Keep
            </button>
          </>
        ) : (
          <button
            type="button"
            onClick={() => setArmed(true)}
            title={`Delete the list ${l.name}. The ships in it are not affected —`
              + ' a list is only a name for an audience.'}
            className="btn ml-auto shrink-0"
          >
            Delete
          </button>
        )}
      </div>
      {l.members.length === 0 && (
        <p className="mb-1 text-[11px] text-ink-faint">
          No members yet. A list you are still filling is fine; picking it in the
          composer adds nobody.
        </p>
      )}
      <ShipChips
        ships={l.members}
        pending={pending}
        onShips={(next) => { void write(next) }}
        onPending={setPending}
        onError={setError}
        label="Members"
      />
      {error && <p className="mt-1 text-danger">{error}</p>}
    </li>
  )
}

export default function Lists({
  lists, onSave, onDelete, onClose,
}: {
  lists: MailList[]
  onSave: (l: MailList) => Promise<void>
  onDelete: (name: string) => void
  onClose: () => void
}) {
  const [name, setName] = useState('')
  const [members, setMembers] = useState<string[]>([])
  const [pending, setPending] = useState('')
  const [error, setError] = useState<string | null>(null)

  const add = async () => {
    setError(null)
    const n = name.trim().toLowerCase()
    if (!n) {
      setError('A list needs a name.')
      return
    }
    // The same rule the nexus enforces, checked at the keystroke: the
    // name becomes a path segment on the ship, so it is lowercase
    // letters, digits and hyphens and nothing else. The nexus keeps its
    // own check and stays the boundary.
    if (!/^[a-z0-9-]{1,64}$/.test(n)) {
      setError('A list name is 1–64 lowercase letters, digits or hyphens.')
      return
    }
    if (lists.some((l) => l.name === n)) {
      setError(`A list called “${n}” already exists. Edit it below, or pick`
        + ' another name.')
      return
    }
    const { ships: final, error: chipError } = commitShip(members, pending)
    if (chipError) { setError(chipError); return }
    try {
      await onSave({ name: n, members: final })
      setName(''); setMembers([]); setPending('')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save that list.')
    }
  }

  return (
    <div className="min-w-0 flex-1 overflow-y-auto p-3">
      <div className="mb-3 flex items-center gap-2">
        <h1 className="text-base font-medium">Lists</h1>
        <button type="button" onClick={onClose} className="btn btn-outline ml-auto">
          Close
        </button>
      </div>

      <p className="mb-3 max-w-prose rounded-sm bg-sunken p-2 text-ink-dim ring-1 ring-line">
        A list is a name for a set of ships, kept on this ship and nowhere else.
        <strong> The name never travels.</strong> Picking a list in the composer
        drops its members into the To field as ordinary recipients, so what is on
        screen is exactly what will be sent — and everyone on it sees everyone
        else, the way group mail works here. There are no blind lists: a message
        names its recipients, and nothing in this app can hide one.
      </p>

      <ul className="mb-4 max-w-prose space-y-2">
        {lists.length === 0 && <li className="text-ink-faint">No lists yet.</li>}
        {lists.map((l) => (
          <ListRow
            key={l.name}
            l={l}
            onSave={onSave}
            onDelete={() => onDelete(l.name)}
          />
        ))}
      </ul>

      <div className="max-w-prose space-y-1 rounded-sm border border-line p-2">
        <h2 className="font-medium">New list</h2>
        <input
          value={name}
          onChange={(e) => { setName(e.target.value); setError(null) }}
          placeholder="Name (lowercase letters, digits and hyphens)"
          aria-label="List name"
          className="field"
        />
        <ShipChips
          ships={members}
          pending={pending}
          onShips={setMembers}
          onPending={setPending}
          onError={setError}
          label="Members"
        />
        <button type="button" onClick={add} className="btn btn-primary">
          Add list
        </button>
        {error && <p className="text-danger">{error}</p>}
      </div>
    </div>
  )
}

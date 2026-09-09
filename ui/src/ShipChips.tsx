import { isShip, ourShip, type MailList } from './api'

// THE SHIP-CHIP INPUT, ONCE. The composer's To field, the members field
// on Save-as-list and the add-a-member field in the Lists panel are the
// same control, so they are the same component: a second implementation
// is a second set of decisions about a half-typed name, about the
// owner's own ship, and about what a comma means, and the two would
// disagree the first time one of them was fixed.
//
// A CHIP IS ALWAYS A WELL-FORMED SHIP. Nothing becomes a chip that
// `isShip` refuses, so every surface downstream of this control — a
// send, a saved draft, a list — receives ships and never a typo. That is
// the recipient validation the spec asks for, moved from "check the
// string before the poke" to "the bad string never gets in": the nexus
// keeps its own check and remains the boundary, but a typo is caught at
// the keystroke, where it is still a typo.

// Fold a half-typed name into the chips.
//
// Exported and pure, because the parent needs it too: a name typed and
// not committed would otherwise vanish when Send is pressed, and the
// user meant to add it. Every commit path — Enter, comma, blur, and the
// parent's own flush on send — runs this one function.
export const commitShip = (
  ships: string[],
  pending: string,
): { ships: string[]; error: string | null } => {
  const v = pending.trim().replace(/,$/, '')
  if (!v) return { ships, error: null }
  if (!isShip(v)) return { ships, error: `${v} is not a ship name.` }
  // THE OWNER IS NEVER A MEMBER OR A RECIPIENT OF THEIR OWN SEND. The
  // nexus refuses it on a list save; dropping it here as well means the
  // rule is the same on every surface rather than a refusal the user
  // only meets at the end.
  if (v === ourShip) return { ships, error: `${v} is you.` }
  if (ships.includes(v)) return { ships, error: null }
  return { ships: [...ships, v], error: null }
}

// Merge a list's members in, without duplicating what is already there
// and without ever adding the owner.
//
// The nexus refuses the owner as a member at save time, so a stored list
// cannot hold one — this drops it anyway, because a list written by an
// older build, or by a dojo poke, must not be able to put the user on
// their own send.
export const addMembers = (ships: string[], members: string[]): string[] => {
  const next = [...ships]
  for (const m of members) {
    if (m === ourShip) continue
    if (!next.includes(m)) next.push(m)
  }
  return next
}

export default function ShipChips({
  ships, pending, onShips, onPending, onError, lists, label, placeholder, disabled,
}: {
  ships: string[]
  // The half-typed name, owned by the PARENT rather than by this
  // component. A send has to be able to fold it in (see `commitShip`),
  // and a value this component held privately could not be reached from
  // the button that needs it.
  pending: string
  onShips: (next: string[]) => void
  onPending: (next: string) => void
  // Where a refused name is reported. The parent owns the message
  // because the same line shows send failures, save failures and this,
  // and two error lines in one panel is two places to look.
  onError: (msg: string | null) => void
  // Mailing lists offered beside ships as the user types. Omitted where
  // there are none to offer — the members field on a Save-as-list form
  // is naming ships, not composing lists out of lists.
  //
  // NESTING IS NOT A FEATURE HERE AND WILL NOT BECOME ONE: picking a
  // list inserts its members as chips immediately, so what is on screen
  // is what will be sent, and nothing downstream ever resolves a name.
  lists?: MailList[]
  label: string
  placeholder?: string
  disabled?: boolean
}) {
  const typed = pending.trim().toLowerCase()
  const suggestions = (lists ?? []).filter(
    (l) => typed !== '' && l.name.startsWith(typed),
  )

  // PICKING A LIST INSERTS ITS MEMBERS, NOW. Not a chip standing for the
  // list, not a name resolved at send time: the members become ordinary
  // ship chips and the list is over. Editing the list afterwards does
  // not change this composer, and what is on screen is exactly what will
  // be sent.
  const pick = (l: MailList) => {
    onShips(addMembers(ships, l.members))
    onPending('')
    onError(null)
  }

  const commit = () => {
    // A typed name that IS a list name takes the list. Otherwise the
    // blur that follows clicking a suggestion would report "groundwire
    // is not a ship name" for a name that is not meant to be one.
    const exact = (lists ?? []).find((l) => l.name === typed)
    if (exact) { pick(exact); return }
    const { ships: next, error } = commitShip(ships, pending)
    onError(error)
    if (error) return
    onPending('')
    if (next !== ships) onShips(next)
  }

  return (
    <div>
      <div className="flex flex-wrap items-center gap-1">
        <span className="text-ink-dim">{label}</span>
        {ships.map((s) => (
          <span
            key={s}
            className="flex max-w-full items-center gap-1 rounded-sm bg-sunken py-0.5 pl-2 pr-1"
          >
            <span className="min-w-0 truncate">{s}</span>
            <button
              type="button"
              disabled={disabled}
              onClick={() => onShips(ships.filter((x) => x !== s))}
              aria-label={`Remove ${s}`}
              className="touch shrink-0 px-0.5 text-ink-dim hover:text-danger"
            >
              ×
            </button>
          </span>
        ))}
        <input
          value={pending}
          disabled={disabled}
          onChange={(e) => { onPending(e.target.value); onError(null) }}
          onBlur={commit}
          onKeyDown={(e) => {
            if (e.key === 'Enter' || e.key === ',') {
              e.preventDefault()
              commit()
            }
          }}
          placeholder={placeholder ?? '~sampel-palnet'}
          aria-label={label}
          className="field min-w-32 flex-1 border-b-0"
        />
      </div>
      {/* The list offers. `onMouseDown` is prevented so the click does
          not blur the input first: a blur commits, and a commit on a
          list name that is only a prefix would report it as a bad ship
          before the click ever landed. */}
      {suggestions.length > 0 && (
        <ul className="mt-1 flex flex-wrap gap-1">
          {suggestions.map((l) => (
            <li key={l.name}>
              <button
                type="button"
                onMouseDown={(e) => { e.preventDefault() }}
                onClick={() => pick(l)}
                title={l.members.length > 0
                  ? `Add ${l.members.join(', ')}`
                  : 'This list has no members yet.'}
                className="btn btn-outline"
              >
                {l.name} ({l.members.length})
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

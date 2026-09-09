//  ship ⇄ address, and nothing else.
//
//  Thunderbird's whole world is `user@domain`: an identity, a To field, an
//  address book card and the From on a mirrored message are all that shape.
//  Auspex's world is `~feb`. This file is the one place the two meet, and
//  it is PURE so the mapping can be tested without a mail client.
//
//  `auspex.urbit` is a RESERVED PSEUDO-DOMAIN. `.urbit` is not a TLD, so
//  nothing here can ever resolve, which is the point: an address that
//  escapes into an SMTP identity bounces at the first hop rather than
//  reaching a stranger. The send path refuses any recipient that is not of
//  this shape before a byte leaves the machine.

const DOMAIN = 'auspex.urbit'

//  A @p, checked structurally. Ported from ui/src/api.ts +isShip, with the
//  same reasoning: the client does not carry the syllable tables, and a
//  name that is SHAPED wrong is the mistake people actually make. The nexus
//  keeps its own validation; this is a convenience, never the boundary.
const SYL = '(?:[a-z]{6}|[a-z]{3})'
const SHIP_RE = new RegExp(`^~(?:${SYL}(?:-${SYL})*)$`)

//  The four ship classes, by hyphen-separated groups: galaxy and star one,
//  planet two, moon four, comet eight. "Even" is not the rule — six, ten
//  and twelve are even and name nothing.
const GROUPS = new Set([1, 2, 4, 8])

function isShip(s) {
  if (typeof s !== 'string' || !SHIP_RE.test(s)) return false
  const parts = s.slice(1).split('-')
  if (!GROUPS.has(parts.length)) return false
  //  a three-letter group is a galaxy, and a galaxy is the WHOLE name.
  //  Without this ~zod-zod passes both rules apart.
  return parts.length === 1 || parts.every((p) => p.length === 6)
}

//  `~feb` → `~feb@auspex.urbit`. Throws rather than returning a broken
//  string: every caller is building a header or a recipient, and a header
//  built from a bad ship is a message that goes somewhere.
function shipToAddress(ship) {
  if (!isShip(ship)) throw new Error(`not a ship: ${String(ship)}`)
  return `${ship}@${DOMAIN}`
}

//  Pull the addr-spec out of whatever Thunderbird handed us. Compose fields
//  carry `Name <a@b>` as often as a bare address, and an identity's From is
//  always the display form.
function bareAddress(raw) {
  if (typeof raw !== 'string') return ''
  const s = raw.trim()
  const m = /<([^<>]*)>\s*$/.exec(s)
  return (m ? m[1] : s).trim().replace(/^"|"$/g, '')
}

//  `~feb@auspex.urbit` → `~feb`, and null for anything else — an ordinary
//  internet address, a mailing list, a typo. Null is the REFUSAL: the send
//  path turns it into a compose error naming the address, because a
//  recipient this extension cannot deliver to must never be silently
//  dropped from a message the user believes went out whole.
function addressToShip(raw) {
  const a = bareAddress(raw)
  const at = a.lastIndexOf('@')
  if (at < 0) return null
  if (a.slice(at + 1).toLowerCase() !== DOMAIN) return null
  const ship = a.slice(0, at)
  return isShip(ship) ? ship : null
}

//  Is this address one we can carry at all? The question the compose guard
//  asks per recipient.
const isAuspexAddress = (raw) => addressToShip(raw) !== null

//  A recipient list off ComposeDetails: strings, or {addressBookId}/{id}
//  entries for a contact or list. Only strings can be mapped, so anything
//  else comes back as an unmappable entry and is refused by name.
function describeRecipient(r) {
  if (typeof r === 'string') return r
  if (r && typeof r === 'object' && typeof r.address === 'string') return r.address
  return JSON.stringify(r)
}

export {
  DOMAIN, isShip, shipToAddress, addressToShip, bareAddress,
  isAuspexAddress, describeRecipient,
}

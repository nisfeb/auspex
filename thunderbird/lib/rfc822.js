//  An auspex message, rendered as RFC 5322 — and read back again.
//
//  PURE. No browser, no WebExtension API, no ship: it takes a plain object
//  and returns a string, which is what makes the whole import path testable
//  under `node --test`. Everything hostile about a message is handled here,
//  because this is the file that decides what Thunderbird will be told.
//
//  THE THREE RULES THIS FILE EXISTS TO KEEP:
//
//  1. A body is text/plain, ALWAYS. `body-mime` is signed and therefore
//     unalterable in transit, and that is a statement about tampering and
//     not about truth — the author chose it, in a chain any ship may
//     deliver. It is carried as a header for a human to read and never as
//     a Content-Type. See the design's "body-mime, name and mime are
//     hostile input".
//  2. An attachment's Content-Type is application/octet-stream, whatever
//     the signed `mime` says, and its filename is sanitised. Thunderbird
//     sniffs less at octet-stream, and a hostile HTML or SVG rendered
//     inline is the failure the nexus's own download route refuses too.
//  3. The body is base64, not raw. That is not about size: it makes the
//     signed bytes survive VERBATIM through mbox (where a line beginning
//     "From " would otherwise be escaped), through line-length limits
//     (RFC 5322 caps a line at 998 octets and a signed body has no such
//     cap) and through any transfer that would normalise CRLF.

const DOMAIN = 'auspex.urbit'
const CRLF = '\r\n'

const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

//  base64 over bytes, written out rather than borrowed: `btoa` is a browser
//  global and `Buffer` is a node one, and this file has to run in both.
function base64(bytes) {
  const b = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes)
  let out = ''
  let i = 0
  for (; i + 2 < b.length; i += 3) {
    const n = (b[i] << 16) | (b[i + 1] << 8) | b[i + 2]
    out += B64[(n >> 18) & 63] + B64[(n >> 12) & 63] + B64[(n >> 6) & 63] + B64[n & 63]
  }
  const rem = b.length - i
  if (rem === 1) {
    const n = b[i] << 16
    out += B64[(n >> 18) & 63] + B64[(n >> 12) & 63] + '=='
  } else if (rem === 2) {
    const n = (b[i] << 16) | (b[i + 1] << 8)
    out += B64[(n >> 18) & 63] + B64[(n >> 12) & 63] + B64[(n >> 6) & 63] + '='
  }
  return out
}

const utf8 = (s) => new TextEncoder().encode(s)

//  base64 in 76-character lines, which is what every MIME reader expects
//  and what keeps a 200KB attachment from becoming one 270KB line.
function base64Lines(bytes, width = 76) {
  const s = base64(bytes)
  const out = []
  for (let i = 0; i < s.length; i += width) out.push(s.slice(i, i + width))
  return out.join(CRLF)
}

const isAscii = (s) => !/[^\x20-\x7e]/.test(s)

//  RFC 2047, base64, UTF-8. A word is capped at 75 characters INCLUDING
//  the `=?utf-8?B?` and `?=`, so the payload is 60 base64 characters — 45
//  bytes — and the split is made on code points so a multi-byte character
//  is never cut in half (a half character in one word and its other half
//  in the next decodes to a replacement character in every reader).
function encodeWords(s) {
  const chunks = []
  let cur = []
  let len = 0
  for (const ch of s) {
    const n = utf8(ch).length
    if (len + n > 45) { chunks.push(cur.join('')); cur = []; len = 0 }
    cur.push(ch)
    len += n
  }
  if (cur.length || !chunks.length) chunks.push(cur.join(''))
  return chunks.map((c) => `=?utf-8?B?${base64(utf8(c))}?=`)
}

//  One header line, folded to stay under 78 characters.
//
//  Folding happens at existing whitespace (a fold is a CRLF plus a space,
//  and the space is part of the value on the way back out), so a value
//  with no whitespace in it — a long Message-ID — is emitted long rather
//  than corrupted. A References list folds naturally: it is a sequence of
//  whitespace-separated ids, which is exactly what makes a chain of depth
//  four legible instead of a 300-byte line.
function foldHeader(name, value) {
  const words = String(value).split(/\s+/).filter((w) => w.length)
  const lines = []
  let line = `${name}:`
  for (const w of words) {
    if (line.length + 1 + w.length > 78 && line !== `${name}:`) {
      lines.push(line)
      line = ` ${w}`
    } else {
      line += ` ${w}`
    }
  }
  lines.push(line)
  return lines.join(CRLF)
}

//  An unstructured header (Subject) whose value may be anything at all.
//  Non-ASCII becomes encoded words; a control byte is dropped, because a
//  CR or LF in a signed subject is a header-injection primitive and this
//  is the boundary where it would land.
function headerLine(name, value) {
  const clean = String(value).replace(/[\r\n\t\0]+/g, ' ')
  return foldHeader(name, isAscii(clean) ? clean : encodeWords(clean).join(' '))
}

//  A filename, made safe. Mirrors the nexus's +safe-name deliberately:
//  separators, quotes, backslashes, semicolons, control bytes and every
//  byte above ASCII are dropped, it is capped at 128, and a name that
//  survives as nothing becomes the hash. The signed `name` is a claim by
//  whoever wrote the message and this is the only guard on it.
function safeName(name, fallback) {
  const s = String(name ?? '')
    .replace(/[^\x20-\x7e]/g, '')
    .replace(/[\/\\";:<>|*?]/g, '')
    .trim()
    .slice(0, 128)
  return s.length ? s : String(fallback ?? 'attachment')
}

//  A filename for Content-Disposition. Sanitised first; if the ORIGINAL
//  had non-ASCII worth keeping, an encoded word carries it, because a
//  reader that cannot decode it still sees the sanitised ASCII form.
function dispositionFilename(name, fallback) {
  const safe = safeName(name, fallback)
  const raw = String(name ?? '')
  if (isAscii(raw) || !raw.trim()) return `"${safe}"`
  //  the encoded word is unquoted: a quoted string is not a place an
  //  encoded word is decoded in, per RFC 2047 §5.
  return encodeWords(raw.replace(/[\r\n\0"]/g, '')).join(' ')
}

const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
const p2 = (n) => String(n).padStart(2, '0')

//  RFC 5322 date, in UTC, built by hand. `toUTCString` is close but not
//  the same grammar, and a locale-dependent formatter in a mail header is
//  a bug waiting for a machine with a different LANG.
function rfc5322Date(ms) {
  const d = new Date(ms)
  return `${DAYS[d.getUTCDay()]}, ${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} `
    + `${d.getUTCFullYear()} ${p2(d.getUTCHours())}:${p2(d.getUTCMinutes())}`
    + `:${p2(d.getUTCSeconds())} +0000`
}

//  An auspex message id, as a Message-ID. The id is a `0v…` cord off a
//  signed record and the domain is ours, so this is a total mapping in
//  both directions and the only thing that ties a mirrored message back to
//  the thread it came from.
const messageId = (id) => `<${id}@${DOMAIN}>`

//  …and back. Returns null for anything that is not one of ours, which is
//  what a reply to a non-auspex message looks like on the send path.
function idFromMessageId(header) {
  if (typeof header !== 'string') return null
  const m = /<?([^<>@\s]+)@auspex\.urbit>?/.exec(header.trim())
  return m ? m[1] : null
}

//  Every id in a References (or In-Reply-To) value, in order. The order is
//  the whole point: References is root-to-parent, and that is what makes
//  Thunderbird's threaded view draw the tree rather than a flat list.
function parseReferences(value) {
  if (typeof value !== 'string') return []
  const out = []
  const re = /<([^<>@\s]+)@auspex\.urbit>/g
  let m
  while ((m = re.exec(value)) !== null) out.push(m[1])
  return out
}

//  A multipart boundary. Derived from the message id, not random: an
//  import is idempotent only if the bytes are, and a random boundary would
//  make the same message produce a different file on every sync.
const boundaryFor = (id) => `--=_auspex_${String(id).replace(/[^a-zA-Z0-9]/g, '')}`

//  THE BUILDER.
//
//    msgId       the auspex message id (the `0v…` cord)
//    threadId    the thread it belongs to
//    from        `~ship`
//    to          [`~ship`, …]
//    subject     the signed subject
//    sent        epoch ms
//    body        the signed body, verbatim
//    bodyMime    the signed `body-mime`, REPORTED and never obeyed
//    verdict     'verified' | 'unverified' | 'forged'
//    copies      how many stored copies share this id (omitted when 1)
//    references  ids root→parent, from the thread's own `prev` chain
//    parts       [{name, mime, size, hash, bytes|note}] — `bytes` for a
//                blob we hold, `note` for one we could not fetch
function buildMessage(m) {
  const to = (m.to || []).map((s) => `${s}@${DOMAIN}`)
  const refs = m.references || []
  const forged = m.verdict === 'forged'
  const parts = m.parts || []

  const headers = [
    headerLine('Message-ID', messageId(m.msgId)),
    headerLine('Date', rfc5322Date(m.sent)),
    headerLine('From', `${m.from}@${DOMAIN}`),
    headerLine('To', to.join(', ') || `${m.from}@${DOMAIN}`),
    //  THE LOUDEST VERDICT STAYS LOUD. Thunderbird's list pane has no
    //  badge to hang a verdict on, so a forgery says so in the one field
    //  a list pane always shows. The header below is the machine-readable
    //  form and the message display button reads it; this is the form a
    //  person reads without clicking anything.
    headerLine('Subject', forged ? `[FORGED] ${m.subject}` : m.subject),
  ]
  if (refs.length) {
    headers.push(headerLine('In-Reply-To', messageId(refs[refs.length - 1])))
    headers.push(headerLine('References', refs.map(messageId).join(' ')))
  }
  headers.push(headerLine('X-Auspex-Verdict', m.verdict))
  headers.push(headerLine('X-Auspex-Thread', m.threadId))
  if (m.copies && m.copies > 1) {
    headers.push(headerLine('X-Auspex-Copies', String(m.copies)))
  }
  //  reported, never obeyed — see the note at the top of this file.
  if (m.bodyMime) headers.push(headerLine('X-Auspex-Body-Mime', m.bodyMime))
  headers.push(headerLine('MIME-Version', '1.0'))

  const bodyPart = [
    'Content-Type: text/plain; charset=utf-8',
    'Content-Transfer-Encoding: base64',
    '',
    base64Lines(utf8(m.body ?? '')),
  ].join(CRLF)

  //  no attachments: the body part IS the message body, headers and all.
  if (!parts.length) return `${headers.join(CRLF)}${CRLF}${bodyPart}${CRLF}`

  const b = boundaryFor(m.msgId)
  const chunks = [`--${b}`, bodyPart]
  for (const a of parts) {
    if (a.bytes) {
      chunks.push(`--${b}`)
      chunks.push([
        //  octet-stream, NOT the signed mime. See rule 2 above.
        'Content-Type: application/octet-stream',
        'Content-Transfer-Encoding: base64',
        `Content-Disposition: attachment; filename=${dispositionFilename(a.name, a.hash)}`,
        '',
        base64Lines(a.bytes),
      ].join(CRLF))
    } else {
      //  NOT FETCHED IS NOT NOT FOUND. Bytes are never pushed, so an
      //  attachment on a message we hold and have not pulled is the
      //  ordinary state of an inbound file. A placeholder says which file,
      //  how big, and where to go for it — and it is PERMANENT for this
      //  import, because a message is never imported twice.
      chunks.push(`--${b}`)
      chunks.push([
        'Content-Type: text/plain; charset=utf-8',
        'Content-Transfer-Encoding: base64',
        '',
        base64Lines(utf8(a.note)),
      ].join(CRLF))
    }
  }
  chunks.push(`--${b}--`)
  const ct = foldHeader('Content-Type', `multipart/mixed; boundary="${b}"`)
  return `${headers.join(CRLF)}${CRLF}${ct}${CRLF}${CRLF}${chunks.join(CRLF)}${CRLF}`
}

//  The words a placeholder says. Its own function so the test can assert
//  the sentence rather than a substring of the builder.
const notFetchedNote = (a) =>
  `attachment "${safeName(a.name, a.hash)}" (${a.size} bytes, ${a.hash})`
  + ' not yet fetched — open the thread in the web client'

export {
  DOMAIN, CRLF, base64, base64Lines, utf8, encodeWords, foldHeader,
  headerLine, safeName, dispositionFilename, rfc5322Date, messageId,
  idFromMessageId, parseReferences, buildMessage, notFetchedNote,
}

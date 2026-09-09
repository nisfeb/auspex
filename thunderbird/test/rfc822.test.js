import test from 'node:test'
import assert from 'node:assert/strict'
import {
  base64, encodeWords, foldHeader, headerLine, safeName,
  dispositionFilename, rfc5322Date, messageId, idFromMessageId,
  parseReferences, buildMessage, notFetchedNote,
} from '../lib/rfc822.js'
import { referencesFor } from '../lib/sync.js'

const headersOf = (raw) => {
  const head = raw.split('\r\n\r\n')[0]
  const out = {}
  //  unfold first: a folded header is one logical line.
  for (const line of head.replace(/\r\n[ \t]+/g, ' ').split('\r\n')) {
    const i = line.indexOf(':')
    const k = line.slice(0, i)
    out[k] = out[k] ? `${out[k]}|${line.slice(i + 1).trim()}` : line.slice(i + 1).trim()
  }
  return out
}
const bodyOf = (raw) => Buffer.from(raw.split('\r\n\r\n').slice(1).join('\r\n\r\n')
  .replace(/\r\n/g, ''), 'base64').toString('utf8')

test('base64 matches node, on every remainder', () => {
  for (const s of ['', 'a', 'ab', 'abc', 'abcd', 'hé — ✓', ' ÿ']) {
    const b = new TextEncoder().encode(s)
    assert.equal(base64(b), Buffer.from(b).toString('base64'), JSON.stringify(s))
  }
})

test('a non-ASCII subject becomes encoded words, and decodes back', () => {
  const subject = 'réunion — déjeuner à midi ✓'
  const raw = buildMessage({
    msgId: '0v1.a', threadId: '0v2.b', from: '~wex', to: ['~feb'],
    subject, sent: 0, body: '', verdict: 'verified',
  })
  const h = headersOf(raw).Subject
  assert.match(h, /^=\?utf-8\?B\?/)
  //  no line of the message is over 78 characters
  for (const line of raw.split('\r\n')) assert.ok(line.length <= 78, line)
  const decoded = h.split(/\s+/)
    .map((w) => Buffer.from(/=\?utf-8\?B\?(.*)\?=/.exec(w)[1], 'base64').toString('utf8'))
    .join('')
  assert.equal(decoded, subject)
})

test('an encoded word never splits a multi-byte character', () => {
  //  60 three-byte characters: the 45-byte payload cap falls mid-character
  //  unless the split is made on code points.
  const s = '✓'.repeat(60)
  const words = encodeWords(s)
  assert.ok(words.length > 1)
  for (const w of words) assert.ok(w.length <= 75, `${w.length}`)
  const back = words
    .map((w) => Buffer.from(/=\?utf-8\?B\?(.*)\?=/.exec(w)[1], 'base64').toString('utf8'))
    .join('')
  assert.equal(back, s)
})

test('a 300-byte header value is folded, and unfolds unchanged', () => {
  const value = Array.from({ length: 50 }, (_, i) => `word${i}`).join(' ')
  assert.ok(value.length >= 300, `${value.length}`)
  const folded = foldHeader('X-Long', value)
  assert.ok(folded.includes('\r\n '))
  for (const line of folded.split('\r\n')) assert.ok(line.length <= 78, line)
  assert.equal(folded.replace(/\r\n[ \t]+/g, ' '), `X-Long: ${value}`)
})

test('a 300-byte body line survives verbatim through base64', () => {
  //  RFC 5322 caps a line at 998 octets and mbox escapes a leading
  //  "From ": base64 is what makes a signed body come back byte for byte.
  const body = `${'x'.repeat(300)}\nFrom the top\n>From quoted\n✓ unicode`
  const raw = buildMessage({
    msgId: '0v1.a', threadId: '0v2.b', from: '~wex', to: ['~feb'],
    subject: 's', sent: 0, body, verdict: 'verified',
  })
  for (const line of raw.split('\r\n')) assert.ok(line.length <= 78, `${line.length}`)
  assert.equal(bodyOf(raw), body)
})

test('a forged message is prefixed, and says so in a header', () => {
  const raw = buildMessage({
    msgId: '0v1.a', threadId: '0v2.b', from: '~feb', to: ['~wex'],
    subject: 'signer cap probe', sent: 0, body: 'x', verdict: 'forged',
  })
  const h = headersOf(raw)
  assert.equal(h.Subject, '[FORGED] signer cap probe')
  assert.equal(h['X-Auspex-Verdict'], 'forged')
  //  and the two honest verdicts are not prefixed
  for (const v of ['verified', 'unverified']) {
    const r = buildMessage({
      msgId: '0v1.a', threadId: '0v2.b', from: '~feb', to: ['~wex'],
      subject: 'signer cap probe', sent: 0, body: 'x', verdict: v,
    })
    assert.equal(headersOf(r).Subject, 'signer cap probe')
    assert.equal(headersOf(r)['X-Auspex-Verdict'], v)
  }
})

test('body-mime is reported and never obeyed', () => {
  const raw = buildMessage({
    msgId: '0v1.a', threadId: '0v2.b', from: '~feb', to: ['~wex'],
    subject: 's', sent: 0, body: '<img onerror=alert(1)>', verdict: 'verified',
    bodyMime: 'text/html',
  })
  const h = headersOf(raw)
  assert.equal(h['X-Auspex-Body-Mime'], 'text/html')
  assert.equal(h['Content-Type'], 'text/plain; charset=utf-8')
  assert.ok(!/Content-Type:\s*text\/html/i.test(raw))
})

test('a References chain of depth 4 round-trips to ids', () => {
  const chain = ['0v7.root', '0v3.aaa', '0v2.bbb', '0v5.ccc']
  const raw = buildMessage({
    msgId: '0v6.ddd', threadId: '0vT', from: '~wex', to: ['~feb'],
    subject: 's', sent: 0, body: 'b', verdict: 'verified', references: chain,
  })
  const h = headersOf(raw)
  assert.deepEqual(parseReferences(h.References), chain)
  assert.equal(idFromMessageId(h['In-Reply-To']), '0v5.ccc')
  assert.equal(idFromMessageId(h['Message-ID']), '0v6.ddd')
  //  and the whole loop: sync builds the path, rfc822 writes it, rfc822
  //  reads it back.
  const ms = [
    { id: '0v7.root', prev: null }, { id: '0v3.aaa', prev: '0v7.root' },
    { id: '0v2.bbb', prev: '0v3.aaa' }, { id: '0v5.ccc', prev: '0v2.bbb' },
    { id: '0v6.ddd', prev: '0v5.ccc' },
  ]
  const byId = new Map(ms.map((m) => [m.id, m]))
  assert.deepEqual(referencesFor(byId.get('0v6.ddd'), byId), chain)
})

test('a Message-ID that is not ours reads back as null', () => {
  assert.equal(idFromMessageId('<abc@example.com>'), null)
  assert.equal(idFromMessageId(''), null)
  assert.equal(idFromMessageId(undefined), null)
  assert.deepEqual(parseReferences('<a@example.com> <0v1.x@auspex.urbit>'), ['0v1.x'])
})

test('a hostile subject cannot inject a header', () => {
  const raw = buildMessage({
    msgId: '0v1.a', threadId: '0v2.b', from: '~feb', to: ['~wex'],
    subject: 'ok\r\nX-Evil: yes\r\nBcc: someone@example.com',
    sent: 0, body: 'x', verdict: 'verified',
  })
  const h = headersOf(raw)
  assert.equal(h['X-Evil'], undefined)
  assert.equal(h.Bcc, undefined)
  assert.match(h.Subject, /^ok X-Evil: yes Bcc: someone@example\.com$/)
})

test('an attachment is octet-stream with a sanitised filename', () => {
  const bytes = new Uint8Array([0, 1, 2, 250, 255])
  const raw = buildMessage({
    msgId: '0v1.a', threadId: '0v2.b', from: '~feb', to: ['~wex'],
    subject: 's', sent: 0, body: 'see attached', verdict: 'verified',
    parts: [{
      name: '../../etc/pas"swd.html', size: 5, mime: 'text/html',
      hash: '0vh', bytes,
    }],
  })
  assert.match(raw, /Content-Type: multipart\/mixed; boundary="/)
  assert.match(raw, /Content-Type: application\/octet-stream/)
  assert.ok(!/text\/html/.test(raw), 'the signed mime never becomes a Content-Type')
  assert.match(raw, /filename="\.\.\.\.etcpasswd\.html"/)
  assert.ok(raw.includes(Buffer.from(bytes).toString('base64')))
})

test('safeName falls back to the hash, and caps at 128', () => {
  assert.equal(safeName('', '0vhash'), '0vhash')
  assert.equal(safeName('///', '0vhash'), '0vhash')
  assert.equal(safeName('ééé', '0vhash'), '0vhash') // all non-ASCII dropped
  assert.equal(safeName('a'.repeat(400), '0vh').length, 128)
  assert.equal(dispositionFilename('plain.txt', '0vh'), '"plain.txt"')
  assert.match(dispositionFilename('résumé.pdf', '0vh'), /^=\?utf-8\?B\?/)
})

test('an unfetched attachment becomes a permanent placeholder', () => {
  const a = { name: 'omen.txt', size: 1024, hash: '0vabc' }
  const raw = buildMessage({
    msgId: '0v1.a', threadId: '0v2.b', from: '~feb', to: ['~wex'],
    subject: 's', sent: 0, body: 'b', verdict: 'verified',
    parts: [{ ...a, note: notFetchedNote(a) }],
  })
  const note = notFetchedNote(a)
  //  base64 is emitted in 76-character lines, so compare after unwrapping.
  const flat = raw.replace(/\r\n(?![-.])/g, '')
  assert.ok(flat.includes(Buffer.from(note, 'utf8').toString('base64')), raw)
  assert.equal(note,
    'attachment "omen.txt" (1024 bytes, 0vabc) not yet fetched'
    + ' — open the thread in the web client')
  //  no Content-Disposition: there is no file here to offer.
  assert.ok(!/Content-Disposition: attachment/.test(raw))
})

test('the date is UTC and locale-free', () => {
  assert.equal(rfc5322Date(0), 'Thu, 1 Jan 1970 00:00:00 +0000')
  assert.equal(rfc5322Date(1788957311103), 'Wed, 9 Sep 2026 12:35:11 +0000')
  assert.equal(messageId('0v1.x'), '<0v1.x@auspex.urbit>')
  assert.equal(headerLine('To', 'x'), 'To: x')
})

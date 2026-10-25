// QUOTING, both ways. A quote is lines of an earlier message set with
// "> " in the reply's own body. It is plain text inside a signed body,
// so it proves nothing about who said it: the message it came from
// travels with the reply, signed, and a reader checks the quote against
// that, not against the quote.

/** A body as runs of its own words and of quoted lines, the "> " taken off. */
export function quoteBlocks(body: string): { quoted: boolean, text: string }[] {
  const out: { quoted: boolean, lines: string[] }[] = []
  for (const line of body.trimEnd().split('\n')) {
    const t = line.trimStart()
    const quoted = t.startsWith('>')
    const text = quoted ? t.slice(1).replace(/^ /, '') : line
    const last = out[out.length - 1]
    if (last && last.quoted === quoted) last.lines.push(text)
    else out.push({ quoted, lines: [text] })
  }
  return out
    .map((b) => ({ quoted: b.quoted, text: trimBlank(b.lines).join('\n') }))
    .filter((b) => b.text.trim() !== '')
}

// The blank lines at either end of a block, dropped as lines. It was a
// `/^\n+|\n+$/` over the joined text, which backtracks through every
// interior run of newlines. Any ship can send a body of 99,998 of them,
// and that froze the app for seven seconds per copy. A lookbehind would
// be linear, and it is a SyntaxError that stops app.js loading on
// Safari 16.0 to 16.3.
const trimBlank = (lines: string[]): string[] => {
  let i = 0
  let j = lines.length
  while (i < j && lines[i] === '') i += 1
  while (j > i && lines[j - 1] === '') j -= 1
  return lines.slice(i, j)
}

/** [text] as a quote: each line set with "> ", a blank one with ">". */
export function asQuote(text: string): string {
  return text.trimEnd().split('\n').map((l) => (l.trim() ? `> ${l}` : '>')).join('\n')
}

/**
 * [quote] put into [body] at [at], on lines of its own with a blank line
 * either side, and where the cursor should go after it.
 */
export function quoteInto(body: string, quote: string, at: number): { body: string, cursor: number } {
  const before = body.slice(0, at).trimEnd()
  const after = body.slice(at).trimStart()
  const head = (before ? `${before}\n\n` : '') + asQuote(quote) + '\n\n'
  return { body: head + after, cursor: head.length }
}

/** A message's own words, without its quotes or blank lines. */
export function ownWords(body: string): string {
  return quoteBlocks(body).filter((b) => !b.quoted).map((b) => b.text).join(' ').replace(/\s+/g, ' ').trim()
}

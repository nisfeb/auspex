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
    .map((b) => ({ quoted: b.quoted, text: b.lines.join('\n').replace(/^\n+|\n+$/g, '') }))
    .filter((b) => b.text.trim() !== '')
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

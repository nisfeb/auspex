import test from 'node:test'
import assert from 'node:assert/strict'
import { ownWords, quoteBlocks, quoteInto } from '../src/quote.ts'

test('a quote put into a reply reads back as that quote, and the cursor lands after it', () => {
  const { body, cursor } = quoteInto('Thanks.  Later', 'first line\n\nsecond line', 7)
  assert.equal(body, 'Thanks.\n\n> first line\n>\n> second line\n\nLater')
  assert.equal(body.slice(cursor), 'Later')
  assert.deepEqual(quoteBlocks(body), [
    { quoted: false, text: 'Thanks.' },
    { quoted: true, text: 'first line\n\nsecond line' },
    { quoted: false, text: 'Later' },
  ])
})

test("a message's own words never include what it quotes", () => {
  //  the tree and the listing label a message by these words; quoted text
  //  there is someone else's sentence under this author's name
  assert.equal(ownWords('> you said this\n>\n  > and this\n\nI say   this\nand that'), 'I say this and that')
  assert.equal(ownWords('> only a quote'), '')
})

test('any body up to the cap is split in linear time', () => {
  //  the trim was a regex that backtracked through every run of newlines:
  //  about 7 s for the first of these and 2 s for the last, before the fix
  const bodies = [
    'a' + '\n'.repeat(99_998) + 'b',
    '> a' + '\n>'.repeat(49_998),
    '> a' + '\n>'.repeat(49_998) + '\n> b',
  ]
  for (const body of bodies) {
    const t0 = performance.now()
    quoteBlocks(body)
    ownWords(body)
    assert.ok(performance.now() - t0 < 500, `${body.length} bytes took too long`)
  }
})

test('blank lines at the ends of a block go, and the ones inside it stay', () => {
  //  pinned to what the regex trim answered
  assert.deepEqual(quoteBlocks('\n\nhello\n\nthere\n\n> \n> x\n>\n>\n\n'), [
    { quoted: false, text: 'hello\n\nthere' },
    { quoted: true, text: 'x' },
  ])
  assert.deepEqual(quoteBlocks('hi\n\n> a\n>\n>\n> b\n\nbye  \n'), [
    { quoted: false, text: 'hi' },
    { quoted: true, text: 'a\n\n\nb' },
    { quoted: false, text: 'bye' },
  ])
  assert.deepEqual(quoteBlocks('>\n>\n\n  \nok'), [{ quoted: false, text: '  \nok' }])
  assert.deepEqual(quoteBlocks('a\n\n\n\n\nb'), [{ quoted: false, text: 'a\n\n\n\n\nb' }])
  assert.deepEqual(quoteBlocks('\n\n\n'), [])
})

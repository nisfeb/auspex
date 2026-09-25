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

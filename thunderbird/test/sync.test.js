import test from 'node:test'
import assert from 'node:assert/strict'
import {
  dedupeCopies, referencesFor, folderFor, threadsToFetch, snapshotOf,
  readStateOps, planThread,
} from '../lib/sync.js'

const msg = (id, prev, over = {}) => ({
  id, prev, from: '~feb', to: ['~wex'], subject: 's', body: 'b',
  'body-mime': '', sent: 1000, attachments: [], verdict: 'verified',
  read: false, ...over,
})

test('the honest copy wins, and the others are counted', () => {
  const copies = dedupeCopies([
    msg('a', null, { verdict: 'forged', body: 'forged one' }),
    msg('a', null, { verdict: 'verified', body: 'the real one' }),
    msg('a', null, { verdict: 'unverified' }),
    msg('b', 'a'),
  ])
  assert.equal(copies.length, 2)
  const a = copies.find((c) => c.msg.id === 'a')
  assert.equal(a.copies, 3)
  assert.equal(a.msg.verdict, 'verified')
  assert.equal(a.msg.body, 'the real one')
})

test('a lone forged copy is still imported, as forged', () => {
  const copies = dedupeCopies([msg('f', null, { verdict: 'forged' })])
  assert.equal(copies.length, 1)
  assert.equal(copies[0].copies, 1)
  assert.equal(copies[0].msg.verdict, 'forged')
})

test('References is the root-to-parent path', () => {
  //  root → a → b → c → d, a chain of depth 4 above the root.
  const ms = [msg('root', null), msg('a', 'root'), msg('b', 'a'),
    msg('c', 'b'), msg('d', 'c')]
  const byId = new Map(ms.map((m) => [m.id, m]))
  assert.deepEqual(referencesFor(byId.get('d'), byId), ['root', 'a', 'b', 'c'])
  assert.deepEqual(referencesFor(byId.get('root'), byId), [])
})

test('a branch: two children of one parent each name only their own path', () => {
  const ms = [msg('root', null), msg('x', 'root'), msg('y', 'root'),
    msg('x2', 'x')]
  const byId = new Map(ms.map((m) => [m.id, m]))
  assert.deepEqual(referencesFor(byId.get('x'), byId), ['root'])
  assert.deepEqual(referencesFor(byId.get('y'), byId), ['root'])
  assert.deepEqual(referencesFor(byId.get('x2'), byId), ['root', 'x'])
})

test('a cycle stops rather than hanging', () => {
  const ms = [msg('p', 'q'), msg('q', 'p')]
  const byId = new Map(ms.map((m) => [m.id, m]))
  assert.deepEqual(referencesFor(byId.get('p'), byId), ['q'])
})

test('the folder choice', () => {
  const ours = '~wex'
  assert.equal(folderFor(msg('a', null, { from: '~feb' }), { archived: false }, ours), 'Inbox')
  assert.equal(folderFor(msg('a', null, { from: '~wex' }), { archived: false }, ours), 'Sent')
  //  archived beats authorship, both ways
  assert.equal(folderFor(msg('a', null, { from: '~feb' }), { archived: true }, ours), 'Archived')
  assert.equal(folderFor(msg('a', null, { from: '~wex' }), { archived: true }, ours), 'Archived')
})

test('only changed threads are fetched', () => {
  const entries = [
    { id: 't1', last: 5, count: 2, archived: false },
    { id: 't2', last: 9, count: 1, archived: false },
    { id: 't3', last: 1, count: 1, archived: true },
    { id: 't4', last: 4, count: 1, archived: false },
  ]
  const snap = {
    t1: { last: 5, count: 2, archived: false },   // unchanged
    t2: { last: 8, count: 1, archived: false },   // last moved
    t3: { last: 1, count: 1, archived: false },   // archived flipped
    // t4 unknown → new
  }
  assert.deepEqual(threadsToFetch(entries, snap), ['t2', 't3', 't4'])
  assert.deepEqual(threadsToFetch(entries, snapshotOf(entries)), [])
})

test('read state does not loop', () => {
  const remote = [
    msg('a', null, { read: true }),
    msg('b', null, { read: false }),
    msg('c', null, { read: true }),
    msg('d', null, { read: true }),   // not mirrored locally
  ]
  //  a already read locally, b already unread locally: neither differs,
  //  so neither produces a local update, so nothing is echoed back.
  const ops = readStateOps(remote, { a: true, b: false, c: false })
  assert.deepEqual(ops, { read: ['c'], unread: [] })
  //  and the other direction: the ship says unread about one we read.
  assert.deepEqual(
    readStateOps([msg('a', null, { read: false })], { a: true }),
    { read: [], unread: ['a'] },
  )
})

test('planThread: nothing imported twice, oldest first, folders assigned', () => {
  const thread = {
    id: 'T',
    messages: [
      msg('root', null, { from: '~wex', sent: 10 }),
      msg('kid', 'root', { from: '~feb', sent: 20 }),
      msg('kid', 'root', { from: '~feb', sent: 20, verdict: 'forged' }),
      msg('old', null, { from: '~feb', sent: 5 }),
    ],
  }
  const plan = planThread(thread, { archived: false }, '~wex', new Set(['root']))
  assert.deepEqual(plan.map((p) => p.msg.id), ['old', 'kid'])
  assert.deepEqual(plan.map((p) => p.folder), ['Inbox', 'Inbox'])
  assert.equal(plan.find((p) => p.msg.id === 'kid').copies, 2)
  assert.deepEqual(plan.find((p) => p.msg.id === 'kid').references, ['root'])
  //  a second run with everything imported plans nothing.
  assert.deepEqual(planThread(thread, {}, '~wex', new Set(['root', 'kid', 'old'])), [])
})

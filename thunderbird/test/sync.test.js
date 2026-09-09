import test from 'node:test'
import assert from 'node:assert/strict'
import {
  dedupeCopies, referencesFor, folderFor, threadsToFetch, snapshotOf,
  readStateOps, planThread, flagsFor, flagUpdate, flagOps,
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
    { id: 't1', last: 5, count: 2, archived: false, labels: [] },
    { id: 't2', last: 9, count: 1, archived: false, labels: [] },
    { id: 't3', last: 1, count: 1, archived: true, labels: [] },
    { id: 't4', last: 4, count: 1, archived: false, labels: [] },
  ]
  const snap = snapshotOf([
    { id: 't1', last: 5, count: 2, archived: false, labels: [] },   // unchanged
    { id: 't2', last: 8, count: 1, archived: false, labels: [] },   // last moved
    { id: 't3', last: 1, count: 1, archived: false, labels: [] },   // archived flipped
    // t4 unknown → new
  ])
  assert.deepEqual(threadsToFetch(entries, snap), ['t2', 't3', 't4'])
  assert.deepEqual(threadsToFetch(entries, snapshotOf(entries)), [])
})

test('a thread that only changed its labels is a change', () => {
  const before = [{ id: 't', last: 5, count: 1, archived: false, labels: ['work'] }]
  //  the star arrives on the ship and nothing else about the thread moves:
  //  no new message, no new timestamp, no archive flip.
  const after = [{ id: 't', last: 5, count: 1, archived: false, labels: ['work', 'flagged'] }]
  assert.deepEqual(threadsToFetch(after, snapshotOf(before)), ['t'])
  //  the same labels in another order are not a change: the ship makes no
  //  promise about the order within the set.
  const reordered = [{ id: 't', last: 5, count: 1, archived: false, labels: ['flagged', 'work'] }]
  assert.deepEqual(threadsToFetch(reordered, snapshotOf(after)), [])
  //  and a snapshot written before labels existed re-reads once.
  assert.deepEqual(threadsToFetch(after, { t: { last: 5, count: 1, archived: false } }), ['t'])
})

test('the star and the flame come off the thread labels', () => {
  assert.deepEqual(flagsFor({ labels: ['flagged'] }), { flagged: true, junk: false })
  assert.deepEqual(flagsFor({ labels: ['junk'] }), { flagged: false, junk: true })
  assert.deepEqual(flagsFor({ labels: ['junk', 'work', 'flagged'] }),
    { flagged: true, junk: true })
  //  any other label is not a flag, and a thread with no labels at all —
  //  or no entry at all — carries neither.
  assert.deepEqual(flagsFor({ labels: ['flag', 'Flagged', 'junky'] }),
    { flagged: false, junk: false })
  assert.deepEqual(flagsFor({ labels: [] }), { flagged: false, junk: false })
  assert.deepEqual(flagsFor(undefined), { flagged: false, junk: false })
})

test('flags that already match produce no write', () => {
  //  THE RULE THAT STOPS THE CHURN. An update fires onUpdated whether or
  //  not it changed anything, and onUpdated is the relay to the ship.
  assert.equal(flagUpdate({ flagged: true, junk: false }, { flagged: true, junk: false }), null)
  assert.equal(flagUpdate({ flagged: false, junk: false }, { flagged: false, junk: false }), null)
  //  only the half that differs is written.
  assert.deepEqual(
    flagUpdate({ flagged: false, junk: false }, { flagged: true, junk: false }),
    { flagged: true },
  )
  assert.deepEqual(
    flagUpdate({ flagged: true, junk: true }, { flagged: true, junk: false }),
    { junk: false },
  )
  assert.deepEqual(
    flagUpdate({ flagged: true, junk: false }, { flagged: false, junk: true }),
    { flagged: false, junk: true },
  )
  //  a header that names neither flag reads as neither set.
  assert.equal(flagUpdate({}, { flagged: false, junk: false }), null)
  assert.deepEqual(flagUpdate({}, { flagged: true, junk: false }), { flagged: true })
})

test('the flame is two calls, the label before the archive', () => {
  assert.deepEqual(flagOps('T', 'flagged', true),
    [{ call: 'label', threadId: 'T', label: 'flagged', add: true }])
  assert.deepEqual(flagOps('T', 'flagged', false),
    [{ call: 'label', threadId: 'T', label: 'flagged', add: false }])
  //  ORDER: the label first, so a thread that lands in the archived view
  //  is already labelled when it gets there.
  assert.deepEqual(flagOps('T', 'junk', true), [
    { call: 'label', threadId: 'T', label: 'junk', add: true },
    { call: 'archive', threadId: 'T', archived: true },
  ])
  assert.deepEqual(flagOps('T', 'junk', false), [
    { call: 'label', threadId: 'T', label: 'junk', add: false },
    { call: 'archive', threadId: 'T', archived: false },
  ])
  //  nothing else is relayed as a label.
  assert.deepEqual(flagOps('T', 'read', true), [])
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

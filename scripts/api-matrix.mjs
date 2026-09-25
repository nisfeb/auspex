#!/usr/bin/env node
// The HTTP API, end to end, on a live ship: every route the clients use,
// driven the way the web client drives it, and every refusal it promises.
//
//   node scripts/api-matrix.mjs <base-url> <cookie-file>
//
// <cookie-file> is a curl cookie jar (or a bare `urbauth-~ship=...` line)
// for the ship's owner. The ship must be a DEV ship: this sends mail to
// itself, and labels, archives, folds and deletes it. Everything it makes
// carries a per-run tag and is deleted at the end, pass or fail, and the
// attachment settings are put back as they were.
//
// Unit tests (tests/lib) prove the libs; this proves the nexus wires them
// to the right routes, with the right marks and grants, and that a write
// posted here is what the next read returns. Exit 0 when every check
// passes.

import { readFileSync } from 'node:fs'

const [base, jar] = process.argv.slice(2)
if (!base || !jar) {
  console.error('usage: api-matrix.mjs <base-url> <cookie-file>')
  process.exit(2)
}
const cookie = (() => {
  const text = readFileSync(jar, 'utf8')
  const tab = text.split('\n').map((l) => l.split('\t')).find((f) => f[5]?.startsWith('urbauth-'))
  if (tab) return `${tab[5]}=${tab[6].trim()}`
  const bare = text.match(/urbauth-~[a-z-]+=[^\s;]+/)
  if (bare) return bare[0]
  throw new Error(`no urbauth cookie in ${jar}`)
})()
const API = `${base.replace(/\/+$/, '')}/apps/auspex/api`
const tag = `api-matrix-${Date.now().toString(36)}`

// ── transport ────────────────────────────────────────────────────────

const call = async (method, path, body, headers = {}) => {
  const raw = body instanceof Uint8Array
  const res = await fetch(`${API}${path}`, {
    method,
    headers: {
      cookie,
      accept: 'application/json',
      ...(body === undefined ? {} : { 'content-type': raw ? 'application/octet-stream' : 'application/json' }),
      ...headers,
    },
    body: body === undefined ? undefined : raw ? body : typeof body === 'string' ? body : JSON.stringify(body),
  })
  const bytes = new Uint8Array(await res.arrayBuffer())
  let json = null
  try { json = JSON.parse(new TextDecoder().decode(bytes)) } catch { /* not json */ }
  return { status: res.status, json, bytes, headers: res.headers }
}
const get = (path) => call('GET', path)
const post = (path, body) => call('POST', path, body)

// Writes go through the nexus's writer after the route answers, so a
// read straight after a write can precede it. Poll until it lands.
const until = async (what, probe, ms = 20000) => {
  const end = Date.now() + ms
  for (;;) {
    const v = await probe()
    if (v) return v
    if (Date.now() > end) throw new Error(`timed out waiting for ${what}`)
    await new Promise((r) => setTimeout(r, 250))
  }
}

const newId = () => {
  const d = '0123456789abcdefghijklmnopqrstuv'
  const g = () => Array.from({ length: 5 }, () => d[Math.floor(Math.random() * 32)]).join('')
  return `0v${g()}.${g()}.${g()}`
}

// ── checks ───────────────────────────────────────────────────────────

let failed = 0
const check = async (name, fn) => {
  try {
    await fn()
    console.log(`ok      ${name}`)
  } catch (e) {
    failed++
    console.log(`FAILED  ${name}\n        ${e.message}`)
  }
}
const eq = (got, want, what) => {
  const g = JSON.stringify(got), w = JSON.stringify(want)
  if (g !== w) throw new Error(`${what}: expected ${w}, got ${g}`)
}
const ok = (cond, what) => { if (!cond) throw new Error(what) }
const refused = async (res, status, what) => {
  const r = await res
  eq(r.status, status, `${what}: status`)
}

const listing = async (params) => {
  const r = await get(`/inbox?${new URLSearchParams({ limit: '200', ...params })}`)
  eq(r.status, 200, `inbox ${JSON.stringify(params)}`)
  return r.json
}
const ours = async (params) => (await listing({ view: 'all', q: tag, ...params })).threads
const inView = async (view, id, extra = {}) =>
  (await listing({ view, ...extra })).threads.some((t) => t.id === id)
const thread = async (id) => {
  const r = await get(`/thread/${id}`)
  eq(r.status, 200, `thread ${id}`)
  return r.json
}

// ── the run ──────────────────────────────────────────────────────────

const made = { threads: new Set(), drafts: new Set(), rules: new Set(), lists: new Set() }
let settings0 = null
let me = null
let tid = null   // the thread this run lives in
let root = null  // its first message
let second = null

try {
  await check('whoami names the ship and says whether it can sign', async () => {
    const r = await get('/whoami')
    eq(r.status, 200, 'status')
    me = r.json.ship
    ok(/^~[a-z-]+$/.test(me), `ship is ${me}`)
    eq(r.json.caps?.keys, true, 'a dev ship holds its keys, so it can sign')
  })
  if (!me) {
    console.log('\nno session: is the cookie current, and is this the right ship?')
    process.exit(1)
  }

  await check('a send to ourselves lands in the Inbox as one verified message', async () => {
    const r = await post('/send', { to: [me], subject: tag, body: `one ${tag}`, prev: null })
    eq(r.status, 200, 'status')
    eq(r.json?.refused ?? [], [], 'refused')
    const [t] = await until('the new thread', async () => (await ours({})).length && ours({}))
    tid = t.id
    made.threads.add(tid)
    eq([t.from, t.subject, t.verdict, t.count, t.forged], [me, tag, 'verified', 1, false], 'row')
    ok(await inView('inbox', tid), 'in the Inbox view')
    const th = await thread(tid)
    root = th.messages[0]
    eq([root.from, root.subject, root.body, root.verdict, root.prev, root.attachments],
      [me, tag, `one ${tag}`, 'verified', null, []], 'message')
  })

  await check('a reply joins the thread it answers', async () => {
    const r = await post('/send', { to: [me], subject: `re: ${tag}`, body: `two ${tag}`, prev: root.id })
    eq(r.status, 200, 'status')
    const th = await until('the reply', async () => {
      const t = await thread(tid)
      return t.messages.length === 2 && t
    })
    second = th.messages[1]
    eq([second.prev, second.body], [root.id, `two ${tag}`], 'reply')
    eq((await ours({})).length, 1, 'still one thread')
  })

  await check('read and unread flip a message, and the listing agrees', async () => {
    eq((await post('/read', { 'thread-id': tid, 'msg-ids': [root.id, second.id] })).status, 200, 'read')
    await until('both read', async () => (await thread(tid)).messages.every((m) => m.read))
    eq((await post('/unread', { 'thread-id': tid, 'msg-ids': [second.id] })).status, 200, 'unread')
    await until('one unread', async () => !(await thread(tid)).messages[1].read)
    ok((await ours({}))[0].unread, 'the row says unread')
  })

  await check('fold and unfold are stored on the thread', async () => {
    eq((await post('/fold', { 'thread-id': tid, 'msg-ids': [root.id] })).status, 200, 'fold')
    await until('folded', async () => (await thread(tid)).folded.includes(root.id))
    eq((await post('/unfold', { 'thread-id': tid, 'msg-ids': [root.id] })).status, 200, 'unfold')
    await until('unfolded', async () => !(await thread(tid)).folded.includes(root.id))
  })

  await check('a label files the thread under that label, and comes off again', async () => {
    eq((await post('/label', { 'thread-id': tid, label: 'api-matrix', add: true })).status, 200, 'add')
    await until('labelled', async () => (await thread(tid)).labels.includes('api-matrix'))
    ok(await inView('label', tid, { label: 'api-matrix' }), 'in the label view')
    ok((await listing({ view: 'all' })).labels.includes('api-matrix'), 'in the label list')
    eq((await post('/label', { 'thread-id': tid, label: 'api-matrix', add: false })).status, 200, 'remove')
    await until('unlabelled', async () => !(await thread(tid)).labels.includes('api-matrix'))
    await refused(post('/label', { 'thread-id': tid, label: 'Not A Term', add: true }), 400, 'a bad label')
  })

  await check('archive moves the thread out of the Inbox and back', async () => {
    eq((await post('/archive', { 'thread-id': tid, archived: true })).status, 200, 'archive')
    await until('archived', async () => (await thread(tid)).archived)
    ok(await inView('archived', tid), 'in Archived')
    ok(!(await inView('inbox', tid)), 'out of the Inbox')
    eq((await post('/archive', { 'thread-id': tid, archived: false })).status, 200, 'unarchive')
    await until('back', async () => inView('inbox', tid))
  })

  await check('search finds the thread by its words and not by others', async () => {
    ok((await listing({ view: 'all', q: `two ${tag}` })).threads.some((t) => t.id === tid), 'found')
    eq((await listing({ view: 'all', q: `${tag}-nowhere` })).threads.length, 0, 'a miss')
  })

  await check('an attachment uploads, rides in a send, and downloads as sent', async () => {
    const bytes = new TextEncoder().encode(`attached ${tag}`)
    const up = await post('/blob', bytes)
    eq(up.status, 200, 'upload')
    eq(up.json.size, bytes.length, 'size')
    const hash = up.json.hash
    const r = await post('/send', {
      to: [me], subject: `re: ${tag}`, body: `three ${tag}`, prev: second.id,
      attachments: [{ name: 'a.txt', mime: 'text/plain', hash }],
    })
    eq(r.status, 200, 'send')
    const th = await until('the attachment message', async () => {
      const t = await thread(tid)
      return t.messages.length === 3 && t
    })
    eq(th.messages[2].attachments.map((a) => [a.name, a.hash, a.size]), [['a.txt', hash, bytes.length]], 'attachment')
    const down = await get(`/blob/${hash}?${new URLSearchParams({ name: 'a.txt', mime: 'text/plain' })}`)
    eq(down.status, 200, 'download')
    eq(new TextDecoder().decode(down.bytes), `attached ${tag}`, 'bytes')
    await refused(post('/send', {
      to: [me], subject: tag, body: 'x', prev: null,
      attachments: [{ name: 'a.txt', mime: 'text/plain', hash: '0v1.2345' }],
    }), 400, 'an attachment we do not hold')
  })

  await check('a draft saves, lists and deletes', async () => {
    const id = newId()
    made.drafts.add(id)
    eq((await post('/draft', { id, to: [me], subject: tag, body: 'draft', prev: null })).status, 200, 'save')
    await until('listed', async () => (await get('/drafts')).json.some((d) => d.id === id))
    eq((await post('/draft-delete', { id })).status, 200, 'delete')
    await until('gone', async () => !(await get('/drafts')).json.some((d) => d.id === id))
    made.drafts.delete(id)
    await refused(post('/draft', { to: [me], subject: tag, body: 'no id', prev: null }), 400, 'a draft without an id')
  })

  await check('a rule saves, lists and deletes, and a rule with no condition is refused', async () => {
    const id = newId()
    made.rules.add(id)
    eq((await post('/rule', { id, from: null, subject: `${tag}-rule`, add: ['api-matrix'], archive: false })).status, 200, 'save')
    await until('listed', async () => (await get('/rules')).json.some((r) => r.id === id))
    eq((await post('/rule-delete', { id })).status, 200, 'delete')
    await until('gone', async () => !(await get('/rules')).json.some((r) => r.id === id))
    made.rules.delete(id)
    await refused(post('/rule', { id: newId(), from: null, subject: '', add: [], archive: true }), 400, 'a rule matching everything')
  })

  await check('a mailing list saves, lists and deletes, and a bad name is refused', async () => {
    const name = `am-${Date.now().toString(36)}`
    made.lists.add(name)
    eq((await post('/list', { name, members: ['~zod'] })).status, 200, 'save')
    await until('listed', async () => (await get('/lists')).json.some((l) => l.name === name))
    eq((await post('/list-delete', { name })).status, 200, 'delete')
    await until('gone', async () => !(await get('/lists')).json.some((l) => l.name === name))
    made.lists.delete(name)
    await refused(post('/list', { name: 'Bad Name', members: ['~zod'] }), 400, 'a capital and a space')
  })

  await check('settings round-trip, and settings out of bounds are refused', async () => {
    const r = await get('/settings')
    eq(r.status, 200, 'get')
    settings0 = r.json
    eq((await post('/settings', settings0)).status, 200, 'save as-is')
    await refused(post('/settings', { ...settings0, budget: 1 }), 400, 'a budget below one file')
    await refused(post('/settings', { ...settings0, allow: ['~zod'], block: ['~zod'] }), 400, 'a ship on both lists')
    eq((await get('/settings')).json, settings0, 'unchanged by the refusals')
  })

  await check('malformed and misrouted requests are refused, not half-applied', async () => {
    await refused(post('/send', 'not json'), 400, 'a body that is not json')
    await refused(post('/send', { to: ['not-a-ship'], subject: 's', body: 'b', prev: null }), 400, 'a bad recipient')
    await refused(post('/send', { to: [me], subject: 's', body: 'b', prev: 'nope' }), 400, 'a bad prev')
    await refused(post('/read', { 'thread-id': tid, 'msg-ids': 'nope' }), 400, 'msg-ids not a list')
    // a read body sent to the delete route must not delete (release 17)
    await refused(post('/delete-thread', { 'thread-id': tid, 'msg-ids': [root.id] }), 400, 'a read body at delete')
    eq((await get(`/thread/${tid}`)).status, 200, 'the thread survived it')
    eq((await get('/thread/0v1.23456')).status, 404, 'an unknown thread')
    eq((await get('/thread/0v1.2345')).status, 400, 'a malformed thread id')
  })

  await check('delete-thread removes the thread from every view', async () => {
    eq((await post('/delete-thread', { 'thread-id': tid })).status, 200, 'delete')
    await until('gone', async () => (await get(`/thread/${tid}`)).status === 404)
    ok(!(await inView('all', tid)), 'out of All')
    made.threads.delete(tid)
  })
} finally {
  // whatever failed, leave the ship as it was found
  for (const id of made.threads) await post('/delete-thread', { 'thread-id': id })
  for (const id of made.drafts) await post('/draft-delete', { id })
  for (const id of made.rules) await post('/rule-delete', { id })
  for (const name of made.lists) await post('/list-delete', { name })
  if (settings0) await post('/settings', settings0)
}

console.log(failed ? `\n${failed} check(s) FAILED` : '\nevery check passed')
process.exit(failed ? 1 : 0)

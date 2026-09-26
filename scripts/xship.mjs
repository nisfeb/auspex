#!/usr/bin/env node
// Mail between two dev ships, exercising what only mail from another ship
// reaches on the ship under test ("us"):
//
//   node scripts/xship.mjs <url> <cookie-jar> <peer-url> <peer-cookie-jar>
//
//   - both ships forget each other, so the exchange has to rediscover
//     each other's protocol (+run-probe, +keen-proto, +publish-proto);
//   - the peer starts two threads; we archive the first and reply to it;
//   - the peer answers in that first thread with a file, while our
//     settings let that peer's files download on their own, and a rule
//     here labels the peer's mail.
//
// Then: every copy verified; the first thread un-archived by the new mail
// (+file-arrival), back at the top of the Inbox and unread (a delivery
// into an existing thread counts as a change); the file fetched by itself
// (+deliver's download rules, the fetch fiber, +take-blob); and each ship
// holding a discovered protocol for the other. Threads are deleted and
// settings restored at the end, pass or fail. Exit 0 when it all holds.

import { readFileSync } from 'node:fs'

const [url, jar, peerUrl, peerJar] = process.argv.slice(2)
if (!peerJar) {
  console.error('usage: xship.mjs <url> <cookie-jar> <peer-url> <peer-cookie-jar>')
  process.exit(2)
}
const cookie = (f) => {
  const t = readFileSync(f, 'utf8')
  const tab = t.split('\n').map((l) => l.split('\t')).find((x) => x[5]?.startsWith('urbauth-'))
  return tab ? `${tab[5]}=${tab[6].trim()}` : t.match(/urbauth-~[a-z-]+=[^\s;]+/)[0]
}
const ships = { us: [url.replace(/\/+$/, ''), cookie(jar)], peer: [peerUrl.replace(/\/+$/, ''), cookie(peerJar)] }
const INSTANCE = '/grubbery/ball/apps/shell.shell/desks/auspex.desk/desk/data/auspex.auspex_app'
const call = async (s, method, path, body, raw = false) => {
  const [base, c] = ships[s]
  const r = await fetch(`${base}${path}`, {
    method,
    headers: { cookie: c, 'content-type': raw ? 'application/octet-stream' : 'application/json' },
    body: body === undefined ? undefined : raw ? body : JSON.stringify(body),
  })
  const text = await r.text()
  let json = null
  try { json = JSON.parse(text) } catch { /* not json */ }
  return { status: r.status, json, text }
}
const api = (s, method, path, body, raw) => call(s, method, `/apps/auspex/api${path}`, body, raw)
const until = async (what, f, ms = 180000) => {
  const end = Date.now() + ms
  for (;;) {
    const v = await f()
    if (v) return v
    if (Date.now() > end) throw new Error(`timed out: ${what}`)
    await new Promise((r) => setTimeout(r, 1000))
  }
}
const need = (cond, what) => { if (!cond) throw new Error(what) }
const tag = `xship-${Date.now().toString(36)}`
const ours = async (view = 'all') => (await api('us', 'GET', `/inbox?view=${view}&q=${tag}&limit=20`)).json.threads
const theirs = async () => (await api('peer', 'GET', `/inbox?view=all&q=${tag}&limit=20`)).json.threads
// a discovery record holds a protocol: [%0 who [~ proto] asked]
const discovered = async (s, who) => {
  const r = await call(s, 'GET', `${INSTANCE}/mail/peer/${who}?info=1`)
  return r.status === 200 && /^\[0 \d+ \[0 /.test(r.json?.text ?? '')
}

const made = { us: new Set(), peer: new Set(), rule: null }
let settings0 = null
let failed = false
try {
  const us = (await api('us', 'GET', '/whoami')).json.ship
  const them = (await api('peer', 'GET', '/whoami')).json.ship
  // forget each other: the exchange must rediscover each other's protocol
  await api('us', 'POST', '/forget-peer', { ship: them })
  await api('peer', 'POST', '/forget-peer', { ship: us })
  // a rule here labels the peer's mail as it arrives (+filing's labels)
  const ruleId = `0v${Date.now().toString(32).slice(-5)}.${'abcde'}.${'fghij'}`
  made.rule = ruleId
  need((await api('us', 'POST', '/rule', { id: ruleId, from: them, subject: null, add: ['xship'], archive: false })).status === 200, 'could not save the rule')
  // the peer's files download here on their own
  settings0 = (await api('us', 'GET', '/settings')).json
  need((await api('us', 'POST', '/settings', { ...settings0, allow: [...new Set([...settings0.allow, them])] })).status === 200, 'could not allow the peer')

  // the peer starts two threads, the second newer
  need((await api('peer', 'POST', '/send', { to: [us], subject: `${tag} one`, body: `first from ${them}`, prev: null })).status === 200, 'the peer could not send')
  const one = await until('the first thread arriving', async () => (await ours()).find((t) => t.subject === `${tag} one`))
  made.us.add(one.id)
  need(one.from === them && one.verdict === 'verified', `received ${one.from} ${one.verdict}`)
  need((await api('peer', 'POST', '/send', { to: [us], subject: `${tag} two`, body: `second from ${them}`, prev: null })).status === 200, 'the peer could not send again')
  const two = await until('the second thread arriving', async () => (await ours()).find((t) => t.subject === `${tag} two`))
  made.us.add(two.id)

  // we archive the first, read everything, and reply to the first
  need((await api('us', 'POST', '/archive', { 'thread-id': one.id, archived: true })).status === 200, 'archive refused')
  for (const t of [one, two]) {
    const th = (await api('us', 'GET', `/thread/${t.id}`)).json
    await api('us', 'POST', '/read', { 'thread-id': t.id, 'msg-ids': th.messages.map((m) => m.id) })
  }
  await until('the first thread archived', async () => (await api('us', 'GET', `/thread/${one.id}`)).json.archived)
  const first = (await api('us', 'GET', `/thread/${one.id}`)).json.messages[0]
  need((await api('us', 'POST', '/send', { to: [them], subject: `re: ${tag} one`, body: `reply from ${us}`, prev: first.id })).status === 200, 'our reply was refused')
  const back = await until('the peer receiving our reply', async () => {
    for (const r of await theirs()) {
      const t = (await api('peer', 'GET', `/thread/${r.id}`)).json
      if (t.messages.some((m) => m.prev === first.id)) return [r, t]
    }
    return null
  })
  for (const r of await theirs()) made.peer.add(r.id)
  need(back[1].messages.every((m) => m.verdict === 'verified'), 'the peer holds an unverified copy')

  // the peer answers in the first thread, with a file
  const bytes = new TextEncoder().encode(`a file from ${them} ${tag}`)
  const up = await api('peer', 'POST', '/blob', bytes, true)
  need(up.status === 200, 'the peer could not upload')
  const ours2 = back[1].messages.find((m) => m.prev === first.id)
  need((await api('peer', 'POST', '/send', {
    to: [us], subject: `re: ${tag} one`, body: `answer from ${them}`, prev: ours2.id,
    attachments: [{ name: 'f.txt', mime: 'text/plain', hash: up.json.hash }],
  })).status === 200, 'the peer could not answer')
  const th = await until('the answer arriving in the first thread', async () => {
    const t = (await api('us', 'GET', `/thread/${one.id}`)).json
    return t.messages.length === 3 && t
  })
  need(th.messages.every((m) => m.verdict === 'verified'), 'a copy is not verified')
  // new mail un-archived the thread, put it back on top, and it is unread
  need(!th.archived, 'new mail did not un-archive the thread')
  need(th.labels.includes('xship'), 'the rule did not label the thread')
  // and a thread whose archive state never changed is labelled too
  need((await api('us', 'GET', `/thread/${two.id}`)).json.labels.includes('xship'), 'the rule did not label an unarchived thread')
  const inbox = await until('the thread back at the top', async () => {
    const ts = await ours('inbox')
    return ts[0]?.id === one.id && ts
  }, 30000)
  need(inbox[0].unread, 'the answered thread is not unread')
  need(inbox.some((t) => t.id === two.id), 'the second thread left the Inbox')
  // and its file came by itself
  const q = new URLSearchParams({ name: 'f.txt', mime: 'text/plain' })
  await until('the file downloading by itself', async () => {
    const r = await api('us', 'GET', `/blob/${up.json.hash}?${q}`)
    return r.status === 200 && r.text === `a file from ${them} ${tag}`
  })
  // each ship rediscovered the other's protocol
  need(await until('our discovery record for the peer', () => discovered('us', them), 60000), 'no protocol discovered for the peer')
  need(await until('the peer\'s discovery record for us', () => discovered('peer', us), 60000), 'the peer discovered no protocol for us')
  console.log('mail, filing, a file and discovery all held, both ways')
} catch (e) {
  failed = true
  console.log(`FAILED  ${e.message}`)
} finally {
  for (const id of made.us) await api('us', 'POST', '/delete-thread', { 'thread-id': id })
  for (const r of await theirs().catch(() => [])) made.peer.add(r.id)
  for (const id of made.peer) await api('peer', 'POST', '/delete-thread', { 'thread-id': id })
  if (settings0) await api('us', 'POST', '/settings', settings0)
  if (made.rule) await api('us', 'POST', '/rule-delete', { id: made.rule })
}
process.exit(failed ? 1 : 0)

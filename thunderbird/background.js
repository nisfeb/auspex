//  The extension's one long-lived script: the mirror, the send interception
//  and the read-state relay.
//
//  Nothing here is clever. Every rule that could be a pure function IS one,
//  in lib/sync.js and lib/rfc822.js, where it has a test; what is left is
//  the part that must touch Thunderbird and the ship, and it is written to
//  be read rather than to be short.

import { Api, ApiError, UnreachableError, MAX_BLOB, MAX_ATTACH } from './lib/api.js'
import {
  addressToShip, shipToAddress, describeRecipient, DOMAIN,
} from './lib/address.js'
import { buildMessage, idFromMessageId, notFetchedNote } from './lib/rfc822.js'
import {
  threadsToFetch, snapshotOf, planThread, readStateOps,
} from './lib/sync.js'

const PARENT = 'Auspex'
const SUBFOLDERS = ['Inbox', 'Sent', 'Archived']
const SYNC_MINUTES = 1

//  ── state ───────────────────────────────────────────────────────────
//
//  All of it in storage.local, all of it derived: delete the lot and the
//  next sync rebuilds it from the ship, except `imported`, which is what
//  stops a message being imported twice. THE CODE IS NOT HERE. It is used
//  once, at connect, and what persists is Thunderbird's cookie jar.

const DEFAULTS = {
  origin: '',
  ship: '',
  status: 'unconfigured',   // unconfigured | connected | signed-out | unreachable
  lastError: '',
  lastSync: 0,
  folders: {},              // name → MailFolderId
  snapshot: {},             // threadId → {last, count, archived}
  imported: {},             // auspex msg id → {tbId, folder, read}
  counts: { messages: 0, threads: 0 },
}

const getState = async () => ({ ...DEFAULTS, ...(await browser.storage.local.get()) })
const setState = (patch) => browser.storage.local.set(patch)

//  ONE NOTIFICATION PER TRANSITION, not per failed request. A sync every
//  sixty seconds against a ship that is down would otherwise be a
//  notification every sixty seconds.
let lastNotifiedStatus = null

async function setStatus(status, lastError = '') {
  const prev = (await getState()).status
  await setState({ status, lastError })
  if (status === prev || status === lastNotifiedStatus) return
  lastNotifiedStatus = status
  if (status === 'signed-out') {
    notify('Auspex: signed out',
      'The ship refused the session. Open the extension options and connect again.')
  }
}

function notify(title, message) {
  try {
    browser.notifications.create({
      type: 'basic', iconUrl: browser.runtime.getURL('icons/auspex-64.png'),
      title, message,
    })
  } catch { /* notifications are a courtesy, never a dependency */ }
}

const apiFor = async () => {
  const { origin } = await getState()
  if (!origin) throw new Error('no ship configured')
  return new Api(origin)
}

//  Every failure that reaches a sync or a send lands here, so "signed out"
//  is decided in one place. A 403 is the session, not the request.
async function classify(e) {
  if (e instanceof ApiError && e.signedOut) { await setStatus('signed-out', e.message); return }
  if (e instanceof UnreachableError) { await setStatus('unreachable', e.message); return }
  await setState({ lastError: e && e.message ? e.message : String(e) })
}

//  ── the local account, its folders and its identity ──────────────────

//  Local Folders is the account whose type is 'none'. messages.import
//  requires a local folder, which is the whole reason the mirror lives
//  there rather than under an invented IMAP account.
async function localAccount() {
  const accounts = await browser.accounts.list(false)
  const local = accounts.find((a) => a.type === 'none')
  if (!local) throw new Error('no Local Folders account in this profile')
  return local
}

async function ensureFolders() {
  const state = await getState()
  const folders = { ...state.folders }
  const account = await localAccount()

  //  the account's own children, by name. folders.create throws on a name
  //  that exists, so an existing tree is adopted rather than fought.
  const kidsOf = async (id) => {
    try { return await browser.folders.getSubFolders(id, false) } catch { return [] }
  }
  const rootId = account.rootFolder ? account.rootFolder.id : account.id
  let parent = (await kidsOf(rootId)).find((f) => f.name === PARENT)
  if (!parent) parent = await browser.folders.create(rootId, PARENT)

  const kids = await kidsOf(parent.id)
  for (const name of SUBFOLDERS) {
    const found = kids.find((f) => f.name === name)
    folders[name] = found ? found.id : (await browser.folders.create(parent.id, name)).id
  }
  await setState({ folders })
  return folders
}

//  THE OWNER'S IDENTITY, so a compose window can be opened at all and a
//  reply has a From. Thunderbird will not open a composer without one, and
//  the address is the same pseudo-domain form every mirrored message uses.
async function ensureIdentity(ship) {
  const account = await localAccount()
  const email = shipToAddress(ship)
  const existing = await browser.identities.list(account.id)
  const found = existing.find((i) => (i.email || '').toLowerCase() === email.toLowerCase())
  if (found) return found.id
  const made = await browser.identities.create(account.id, { email, name: ship })
  return made.id
}

//  ── the mirror ──────────────────────────────────────────────────────

//  An attachment's bytes, or null. On a 409 the ship is asked to keen for
//  them and the route is polled — ten times, three seconds apart, which is
//  a shape a per-case-probe deadline can actually finish inside. If they
//  are still absent the caller writes a placeholder, and the placeholder is
//  PERMANENT for that import: a message is imported once.
async function attachmentBytes(api, att, from) {
  let bytes = await api.blob(att.hash, att.name, att.mime)
  if (bytes) return bytes
  try { await api.fetchBlob(att.hash, from) } catch { /* a miss costs a placeholder */ }
  for (let i = 0; i < 10; i += 1) {
    await new Promise((r) => setTimeout(r, 3000))
    bytes = await api.blob(att.hash, att.name, att.mime)
    if (bytes) return bytes
  }
  return null
}

async function importOne(api, item, folders, imported) {
  const { msg } = item
  const parts = []
  for (const a of (msg.attachments || [])) {
    const bytes = await attachmentBytes(api, a, msg.from)
    parts.push(bytes ? { ...a, bytes } : { ...a, note: notFetchedNote(a) })
  }
  const raw = buildMessage({
    msgId: msg.id,
    threadId: item.threadId,
    from: msg.from,
    to: msg.to,
    subject: msg.subject,
    sent: msg.sent,
    body: msg.body,
    bodyMime: msg['body-mime'],
    verdict: msg.verdict,
    copies: item.copies,
    references: item.references,
    parts,
  })
  const file = new File([raw], `${msg.id}.eml`, { type: 'message/rfc822' })
  const header = await browser.messages.import(file, folders[item.folder], {
    read: !!msg.read, new: false,
  })
  imported[msg.id] = { tbId: header.id, folder: item.folder, read: !!msg.read }
}

let syncing = false

async function syncNow() {
  if (syncing) return { skipped: true }
  syncing = true
  try {
    const state = await getState()
    if (!state.origin) return { skipped: true, why: 'unconfigured' }
    const api = new Api(state.origin)
    const ship = await api.whoami()
    await setStatus('connected')
    if (ship !== state.ship) await setState({ ship })
    const folders = await ensureFolders()
    await ensureIdentity(ship)

    const { threads: entries } = await api.allThreads('all', 100)
    const wanted = threadsToFetch(entries, state.snapshot)
    const byThread = new Map(entries.map((e) => [e.id, e]))
    const imported = { ...state.imported }
    const importedIds = new Set(Object.keys(imported))
    let added = 0

    //  ship → local read state, gathered as the threads are walked and
    //  applied at the end. Only where the two sides DIFFER: a ship that
    //  agrees with us produces no local update, so nothing is echoed back.
    const remote = []

    for (const id of wanted) {
      let thread
      try {
        thread = await api.thread(id)
      } catch (e) {
        //  a thread deleted between the listing and the fetch is a 404 and
        //  is not an error worth stopping the sync for.
        if (e instanceof ApiError && e.status === 404) continue
        throw e
      }
      remote.push(...(thread.messages || []))
      const plan = planThread(thread, byThread.get(id), ship, importedIds)
      for (const item of plan) {
        try {
          await importOne(api, item, folders, imported)
          importedIds.add(item.msg.id)
          added += 1
        } catch (e) {
          //  Thunderbird throws on a duplicate Message-ID in a folder,
          //  which is a mirror that lost its bookkeeping and not a
          //  failure: record it as imported so the next sync moves on.
          if (/Message-ID/i.test(String(e && e.message))) {
            imported[item.msg.id] = { tbId: null, folder: item.folder, read: !!item.msg.read }
            importedIds.add(item.msg.id)
          } else throw e
        }
      }
    }

    const flags = {}
    for (const [id, rec] of Object.entries(imported)) flags[id] = rec.read
    const ops = readStateOps(remote, flags)
    for (const [ids, read] of [[ops.read, true], [ops.unread, false]]) {
      for (const id of ids) {
        const rec = imported[id]
        if (!rec || rec.tbId === null) continue
        //  the record moves FIRST, so the onUpdated this provokes sees a
        //  flag that already matches and posts nothing back.
        rec.read = read
        try { await browser.messages.update(rec.tbId, { read }) } catch { /* gone */ }
      }
    }

    await setState({
      imported,
      snapshot: snapshotOf(entries),
      lastSync: Date.now(),
      counts: { messages: Object.keys(imported).length, threads: entries.length },
      lastError: '',
    })
    if (added) notify('Auspex', `${added} new message${added === 1 ? '' : 's'} mirrored.`)
    return { added, threads: entries.length }
  } catch (e) {
    await classify(e)
    return { error: e && e.message ? e.message : String(e) }
  } finally {
    syncing = false
  }
}

//  ── read state, local → ship ────────────────────────────────────────
//
//  Debounced, and one request for the batch: the nexus writer is the ship's
//  single serialisation point for mail, and a request per message is a full
//  mailbox scan per message.
const pendingRead = new Set()
const pendingUnread = new Set()
let readTimer = null

function queueReadState(id, read) {
  ;(read ? pendingRead : pendingUnread).add(id)
  ;(read ? pendingUnread : pendingRead).delete(id)
  if (readTimer) clearTimeout(readTimer)
  readTimer = setTimeout(flushReadState, 2000)
}

async function flushReadState() {
  readTimer = null
  const read = [...pendingRead]
  const unread = [...pendingUnread]
  pendingRead.clear()
  pendingUnread.clear()
  if (!read.length && !unread.length) return
  try {
    const api = await apiFor()
    await api.markRead(read)
    await api.markUnread(unread)
  } catch (e) { await classify(e) }
}

browser.messages.onUpdated.addListener(async (message, changed) => {
  if (!('read' in changed)) return
  const id = idFromMessageId(message.headerMessageId)
  if (!id) return
  const state = await getState()
  const rec = state.imported[id]
  //  NOT OURS, or ALREADY WHAT WE RECORDED. The second is the echo of an
  //  update this extension just made, and skipping it is what keeps the
  //  relay from looping.
  if (!rec || rec.read === message.read) return
  rec.read = message.read
  await setState({ imported: state.imported })
  queueReadState(id, message.read)
})

//  ── send ────────────────────────────────────────────────────────────

const refuse = (why) => {
  notify('Auspex: message not sent', why)
  return { cancel: true }
}

//  `prev` for a reply or a forward: the auspex id of the message the
//  composer was opened from. A fresh compose has none, and `prev: null` is
//  what starts a thread.
async function prevFor(details) {
  if (details.relatedMessageId === undefined || details.relatedMessageId === null) return null
  try {
    const full = await browser.messages.getFull(details.relatedMessageId)
    const h = (full.headers && full.headers['message-id']) || []
    return h.length ? idFromMessageId(h[0]) : null
  } catch { return null }
}

//  HTML → text, and the ceiling is right here. Thunderbird's own composer
//  can be an HTML one; auspex carries a signed plain-text body and nothing
//  else. A tag strip and an entity decode is what this does, and it is not
//  a renderer: a table comes out as its cells run together, and a message
//  whose meaning is in its formatting loses that meaning. Compose in plain
//  text (the identity this extension creates does) and none of this runs.
function htmlToText(html) {
  const withBreaks = String(html)
    .replace(/<\s*(br|\/p|\/div|\/tr|\/li|\/h[1-6])\s*\/?\s*>/gi, '\n')
    .replace(/<\s*(script|style)[\s\S]*?<\s*\/\s*\1\s*>/gi, '')
  const stripped = withBreaks.replace(/<[^>]*>/g, '')
  const entities = {
    amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', mdash: '—', ndash: '–',
  }
  return stripped
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
    .replace(/&([a-z]+);/gi, (m, name) => (name.toLowerCase() in entities
      ? entities[name.toLowerCase()] : m))
    .replace(/\n{3,}/g, '\n\n')
    .trim()
}

async function handleSend(tab, details) {
  const state = await getState()
  if (!state.origin) return refuse('No ship is configured. Open the Auspex options.')
  if (state.status === 'signed-out') {
    return refuse('Signed out of the ship. Reconnect in the Auspex options; '
      + 'your message is still in the compose window.')
  }

  //  RECIPIENTS. Every one must be a ship, and a recipient this extension
  //  cannot carry is a refusal naming it — never a silent drop from a
  //  message the user believes went out whole.
  const to = []
  for (const r of (details.to || [])) {
    const ship = addressToShip(describeRecipient(r))
    if (!ship) {
      return refuse(`${describeRecipient(r)} is not an auspex address. `
        + `Auspex carries mail only to ~ship@${DOMAIN}.`)
    }
    to.push(ship)
  }
  if (!to.length) return refuse('No recipient.')

  //  NO CC AND NO BCC. A chain proves authorship, not delivery, and the
  //  wire has no field for either — a Cc would silently become a second To
  //  and a Bcc would silently become a visible one.
  if ((details.cc || []).length || (details.bcc || []).length) {
    return refuse('Auspex has no Cc or Bcc on the wire: every recipient of a '
      + 'message is named inside the signature. Put them all in To, or send twice.')
  }

  const body = details.isPlainText
    ? (details.plainTextBody || '')
    : htmlToText(details.body || '')

  let api
  try { api = new Api(state.origin) } catch (e) { return refuse(e.message) }

  //  ATTACHMENTS, uploaded before the send so the send names files the
  //  ship already holds. Refused by NAME and before a byte is uploaded:
  //  "too big" without a filename tells a person nothing about what to
  //  remove.
  let refs = []
  try {
    const list = await browser.compose.listAttachments(tab.id)
    if (list.length > MAX_ATTACH) {
      return refuse(`${list.length} attachments; auspex carries at most ${MAX_ATTACH}.`)
    }
    for (const a of list) {
      const file = await browser.compose.getAttachmentFile(a.id)
      const bytes = new Uint8Array(await file.arrayBuffer())
      if (bytes.length > MAX_BLOB) {
        return refuse(`${a.name} is ${bytes.length} bytes; the limit for one `
          + `file is ${MAX_BLOB}.`)
      }
      const hash = await api.uploadBlob(bytes, file.type)
      refs.push({ name: a.name, mime: file.type || 'application/octet-stream', hash })
    }
  } catch (e) {
    await classify(e)
    return refuse(`Attachment upload failed: ${e && e.message ? e.message : e}`)
  }

  const prev = await prevFor(details)

  try {
    await api.send(to, details.subject || '', body, prev, refs)
  } catch (e) {
    await classify(e)
    return refuse(`The ship refused the send: ${e && e.message ? e.message : e}. `
      + 'Nothing was sent; your message is still here.')
  }

  //  SENT. Thunderbird must not also try to deliver it by SMTP — there is
  //  no SMTP here and the identity's address does not resolve — so the
  //  send is cancelled and the window closed by us.
  try { await browser.tabs.remove(tab.id) } catch { /* already gone */ }
  syncNow()
  return { cancel: true }
}

browser.compose.onBeforeSend.addListener((tab, details) => handleSend(tab, details))

//  ── the verdict, on the open message ────────────────────────────────

const VERDICT_UI = {
  verified: { label: '✓', title: 'Auspex: verified — the signature is this ship\'s' },
  unverified: { label: '○', title: 'Auspex: unverified — no key to check it against' },
  forged: { label: 'FORGED', title: 'Auspex: FORGED — the signature does not match' },
}

browser.messageDisplay.onMessageDisplayed.addListener(async (tab, message) => {
  let verdict = null
  try {
    const full = await browser.messages.getFull(message.id)
    const h = (full.headers && full.headers['x-auspex-verdict']) || []
    verdict = h.length ? String(h[0]).trim() : null
  } catch { /* not one of ours */ }
  const ui = VERDICT_UI[verdict]
  const set = browser.messageDisplayAction
  if (!ui) {
    await set.setLabel({ tabId: tab.id, label: '' })
    await set.setTitle({ tabId: tab.id, title: 'Auspex: not a mirrored message' })
    await set.disable(tab.id)
    return
  }
  await set.enable(tab.id)
  await set.setLabel({ tabId: tab.id, label: ui.label })
  await set.setTitle({ tabId: tab.id, title: ui.title })
})

browser.messageDisplayAction.onClicked.addListener(async (tab) => {
  const title = await browser.messageDisplayAction.getTitle({ tabId: tab.id })
  notify('Auspex', title)
})

//  ── the popup's and the options page's one door ─────────────────────

browser.runtime.onMessage.addListener(async (msg) => {
  if (msg.kind === 'state') return getState()
  if (msg.kind === 'sync') return syncNow()
  if (msg.kind === 'connect') return connect(msg.origin, msg.code)
  if (msg.kind === 'disconnect') {
    await setState({ ...DEFAULTS })
    return { ok: true }
  }
  return undefined
})

//  CONNECT. The code arrives here, is used once, and is never written
//  anywhere: what persists is the cookie Eyre set on the answer.
async function connect(rawOrigin, code) {
  let api
  try { api = new Api(rawOrigin) } catch (e) { return { ok: false, error: e.message } }
  try {
    await api.login(code)
    const ship = await api.whoami()
    await setState({ origin: api.origin, ship, status: 'connected', lastError: '' })
    lastNotifiedStatus = 'connected'
    await ensureFolders()
    await ensureIdentity(ship)
    syncNow()
    return { ok: true, ship, origin: api.origin }
  } catch (e) {
    await classify(e)
    return { ok: false, error: e && e.message ? e.message : String(e) }
  }
}

//  ── the clock ───────────────────────────────────────────────────────

browser.alarms.create('auspex-sync', { periodInMinutes: SYNC_MINUTES })
browser.alarms.onAlarm.addListener((a) => { if (a.name === 'auspex-sync') syncNow() })

//  On startup, and only if there is something to sync: an unconfigured
//  install makes no request at all.
;(async () => {
  //  THE SELFTEST HOOK. Present only in a build made with
  //  `npm run build -- --selftest`; the shipped zip has no such file, the
  //  fetch 404s, and nothing below runs. It exists because every other way
  //  to drive this extension without a human is a way of seeding
  //  storage.local from outside, and there is not one.
  try {
    const res = await fetch(browser.runtime.getURL('selftest.json'))
    if (res.ok) {
      const cfg = await res.json()
      const { runSelftest } = await import('./selftest.js')
      runSelftest(cfg, { connect, syncNow, getState, setState, apiFor })
      return
    }
  } catch { /* no selftest in this build */ }
  const { origin } = await getState()
  if (origin) syncNow()
})()

export { syncNow, connect, htmlToText }

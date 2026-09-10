//  The extension's one long-lived script: the mirror, the send interception
//  and the read-state relay.
//
//  Nothing here is clever. Every rule that could be a pure function IS one,
//  in lib/sync.js and lib/rfc822.js, where it has a test; what is left is
//  the part that must touch Thunderbird and the ship, and it is written to
//  be read rather than to be short.

import { Api, ApiError, UnreachableError, MAX_BLOB, MAX_ATTACH } from './lib/api.js'
import { isChange, framesIn, nextDelay, nextAttempt } from './lib/beacon.js'
import {
  addressToShip, shipToAddress, describeRecipient, DOMAIN,
} from './lib/address.js'
import { buildMessage, idFromMessageId, notFetchedNote } from './lib/rfc822.js'
import {
  threadsToFetch, snapshotOf, planThread, readStateOps,
  flagsFor, flagUpdate, flagOps,
} from './lib/sync.js'

const PARENT = 'Auspex'
const SUBFOLDERS = ['Inbox', 'Sent', 'Archived']

//  THE FALLBACK, and it is a fallback: the beacon is what syncs this
//  extension. Fifteen minutes rather than one, and it exists for exactly
//  one case the briefing names — a connection that dies SILENTLY, with no
//  FIN and no error, so the reader blocks for ever and the stream neither
//  delivers nor fails. A NAT timeout and a laptop sleep both do it.
//
//  It is an alarm rather than a setInterval so it survives a background
//  page the browser decided to suspend, and it SYNCS rather than
//  reconnecting: silence is not death, and tearing down a quiet stream is
//  the bug this whole change is here to avoid.
const FALLBACK_MINUTES = 15

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
  snapshot: {},             // threadId → {last, count, archived, labels}
  imported: {},             // auspex msg id → {tbId, folder, read, flagged, junk}
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
  //  SIGNED OUT IS NOT A RETRY LOOP. A 403 is the session, and no amount
  //  of reconnecting fixes it — so the stream stops here, with everything
  //  else that stops, and only a successful connect from the options page
  //  starts it again.
  if (status === 'signed-out') stopBeacon()
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

//  `flags` is the thread's star and flame AT IMPORT TIME, so a message
//  arriving into a thread the owner already starred is starred the moment
//  it appears rather than one sync later.
async function importOne(api, item, folders, imported, flags) {
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
    read: !!msg.read, new: false, flagged: flags.flagged, junk: flags.junk,
  })
  imported[msg.id] = {
    tbId: header.id,
    folder: item.folder,
    read: !!msg.read,
    flagged: flags.flagged,
    junk: flags.junk,
  }
}

//  A STORED THUNDERBIRD ID IS A HINT, NEVER AN ADDRESS.
//
//    `MessageHeader.id` is minted by Thunderbird's message tracker as
//    messages are encountered, and it is NOT stable across restarts.
//    Proven in a scratch profile: a record whose `tbId` was 16 came back
//    holding a different message's Message-ID entirely, several restarts
//    after the import that wrote it.
//
//    A flag written through a stale id marks THE WRONG MAIL, silently,
//    which is worse than not writing it at all — and read state has been
//    going through the same door since the mirror was written.
//
//    So the id is checked against the Message-ID it is supposed to name,
//    and re-found by that name when it is wrong or gone. The record is
//    repaired in place, so the cost is one lookup per moved message per
//    restart and nothing at all afterwards. A message the mirror recorded
//    with no id at all — the duplicate-Message-ID case below — is found
//    the same way.
async function headerFor(auspexId, rec) {
  if (rec.tbId !== null && rec.tbId !== undefined) {
    try {
      const h = await browser.messages.get(rec.tbId)
      if (h && idFromMessageId(h.headerMessageId) === auspexId) return h
    } catch { /* gone from under that id: look it up by name */ }
  }
  try {
    const found = await browser.messages.query({ headerMessageId: `${auspexId}@${DOMAIN}` })
    const h = (found.messages || [])[0]
    if (!h) return null
    rec.tbId = h.id
    return h
  } catch { return null }
}

let syncing = false

//  A change that arrives WHILE a sync is running is not lost.
//
//  The listing walk takes seconds against a large mailbox, and mail
//  landing inside that window would otherwise wait for the fifteen-minute
//  fallback. Set here, read in the `finally` below: one more sync, once,
//  however many changes arrived — the sync reads the whole listing, so
//  coalescing them is not an approximation, it is the same answer.
let pendingChange = false

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

    //  The star and the flame live on the THREAD and Thunderbird's flags
    //  live on the MESSAGE, so applying them needs the membership: the
    //  flags of each thread looked at this sync, and the ids in it.
    const want = new Map()   // threadId → {flagged, junk, ids}

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
      const entry = byThread.get(id) || thread
      const flags = flagsFor(entry)
      want.set(id, { ...flags, ids: (thread.messages || []).map((m) => m.id) })
      const plan = planThread(thread, byThread.get(id), ship, importedIds)
      for (const item of plan) {
        try {
          await importOne(api, item, folders, imported, flags)
          importedIds.add(item.msg.id)
          added += 1
        } catch (e) {
          //  Thunderbird refuses a duplicate Message-ID in a folder,
          //  which is a mirror that lost its bookkeeping and not a
          //  failure. Both wordings, because Thunderbird 147 says
          //  "Destination folder already contains a message with id"
          //  and does not use the word Message-ID at all — a sync that
          //  did not know that aborted on the first duplicate and left
          //  the flags of every later thread unapplied.
          const why = String(e && e.message)
          if (/Message-ID|already contains a message/i.test(why)) {
            //  the message IS in the folder — that is what the refusal
            //  says — so find it by name rather than recording a hole.
            const rec = {
              tbId: null, folder: item.folder,
              read: !!item.msg.read, flagged: flags.flagged, junk: flags.junk,
            }
            await headerFor(item.msg.id, rec)
            imported[item.msg.id] = rec
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
        if (!rec) continue
        const header = await headerFor(id, rec)
        if (!header) continue
        //  the record moves FIRST, so the onUpdated this provokes sees a
        //  flag that already matches and posts nothing back.
        rec.read = read
        try { await browser.messages.update(rec.tbId, { read }) } catch { /* gone */ }
      }
    }

    //  ship → local star and flame, for every thread looked at this sync.
    //  READ FIRST, WRITTEN ONLY WHERE THEY DIFFER, for exactly the reason
    //  the read pass above is written that way: an update fires
    //  onUpdated whether or not it changed anything, and onUpdated is the
    //  relay back to the ship.
    for (const wantFlags of want.values()) {
      for (const msgId of wantFlags.ids) {
        const rec = imported[msgId]
        if (!rec) continue
        const current = await headerFor(msgId, rec)
        if (!current) continue
        const patch = flagUpdate(current, wantFlags)
        //  the record moves FIRST, so the onUpdated this provokes sees
        //  flags that already match and posts nothing back.
        rec.flagged = wantFlags.flagged
        rec.junk = wantFlags.junk
        if (!patch) continue
        try { await browser.messages.update(rec.tbId, patch) } catch { /* gone */ }
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
    if (pendingChange) { pendingChange = false; syncNow() }
  }
}

//  ── the change beacon ───────────────────────────────────────────────
//
//  WHAT THIS REPLACED, and why. Until now the mirror ran on a
//  sixty-second alarm: a whoami plus a paged inbox walk plus a fetch per
//  changed thread, 1,440 times a day, whatever the user was doing and
//  whether or not anything had moved. Measured against ~wex with 42
//  threads that is about 1.2 seconds of ship time per idle sync, and the
//  nexus's listing is O(total stored messages), so it gets worse with
//  every message the mailbox holds. A ship runs its events ONE AT A TIME.
//
//  So: subscribe, don't poll. One connection, held open, and a sync only
//  when the ship says something a reader can see has changed. The rules
//  it obeys are in lib/beacon.js next to the functions that enforce them;
//  what is left here is the loop, which is the part a test cannot reach.

//  ONE STREAM, EVER. Two readers would be two held connections and two
//  syncs per change — and Vere serves HTTP/1.1, where a wasted connection
//  is one the rest of the client does not get.
let streaming = false
let stopStream = false
let streamAbort = null

//  Diagnostics, bounded. The last few attempts, so the popup and a
//  selftest can say what the stream has actually been doing rather than
//  only whether it is up.
const beaconLog = []
const logAttempt = (entry) => {
  beaconLog.push({ at: Date.now(), ...entry })
  if (beaconLog.length > 20) beaconLog.shift()
}

//  Read frames until the stream ends. Returns when it does; throws only
//  if the read itself does.
async function readStream(res, onFrame) {
  const reader = res.body.getReader()
  const dec = new TextDecoder()
  let buf = ''
  for (;;) {
    const { done, value } = await reader.read()
    if (done) return
    buf += dec.decode(value, { stream: true })
    const { frames, rest } = framesIn(buf)
    buf = rest
    for (const f of frames) onFrame(f)
  }
}

//  THE LOOP. Open the beacon, read until it drops, wait, open it again.
//
//  Three things it deliberately does NOT do:
//
//    - it does not sync on connect. Registration replays the current
//      revision as an `old /rev` frame, which lib/beacon.js does not call
//      a change, so a reconnect costs exactly ONE request and mirrors
//      nothing. That is the briefing's third rule and it is the whole
//      reason a reconnect is allowed to be ordinary.
//    - it does not watch for staleness. A healthy connection to a quiet
//      ship sends nothing for minutes; the only thing that acts on
//      silence is the fifteen-minute fallback alarm, and it syncs rather
//      than reconnecting.
//    - it does not retry a 403. That is the session, not the request.
async function runBeacon() {
  let attempt = 0
  while (!stopStream) {
    const { origin, status } = await getState()
    if (!origin || status === 'signed-out') return
    const startedAt = Date.now()
    let why = 'ended'
    try {
      const api = new Api(origin)
      streamAbort = new AbortController()
      const res = await api.beacon(streamAbort.signal)
      await readStream(res, (frame) => {
        if (!isChange(frame)) return
        logAttempt({ change: true })
        //  THE ONE ACTION. Nothing else in this file syncs except the
        //  fallback alarm and a user pressing Sync.
        if (syncing) pendingChange = true
        else syncNow()
      })
    } catch (e) {
      why = e && e.message ? e.message : String(e)
      if (e instanceof ApiError && e.signedOut) {
        logAttempt({ lived: Date.now() - startedAt, why })
        await setStatus('signed-out', e.message)
        return
      }
    } finally {
      streamAbort = null
    }
    const lived = Date.now() - startedAt
    if (stopStream) return
    //  RESET ON A STREAM THAT LIVED, not on one that registered: see
    //  nextAttempt in lib/beacon.js for the trap that hides there.
    const delay = nextDelay(attempt)
    attempt = nextAttempt(attempt, lived)
    logAttempt({ lived, why, delay, attempt })
    await new Promise((r) => setTimeout(r, delay))
  }
}

//  Start it, once. Called at startup with a configured origin, and again
//  after a successful connect — which for a fresh install is the first
//  moment there is anything to watch.
function startBeacon() {
  if (streaming) return false
  streaming = true
  stopStream = false
  runBeacon().finally(() => { streaming = false })
  return true
}

//  Stop it: a disconnect, or a 403. `abort` is what unblocks a reader
//  sitting on a stream that will never send anything again.
function stopBeacon() {
  stopStream = true
  try { if (streamAbort) streamAbort.abort() } catch { /* already gone */ }
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

//  ── the star and the flame, local → ship ────────────────────────────
//
//  Per THREAD, because a label is a thread's, and debounced like the read
//  relay for the same reason. Keyed by thread and flag, so a star clicked
//  twice inside the debounce is one request and the LAST state wins.
const pendingFlags = new Map()   // `${threadId}\0${flag}` → boolean
let flagTimer = null

function queueFlag(threadId, flag, on) {
  pendingFlags.set(`${threadId}\u0000${flag}`, on)
  if (flagTimer) clearTimeout(flagTimer)
  flagTimer = setTimeout(flushFlags, 2000)
}

async function flushFlags() {
  flagTimer = null
  const batch = [...pendingFlags.entries()]
  pendingFlags.clear()
  if (!batch.length) return
  try {
    const api = await apiFor()
    for (const [key, on] of batch) {
      const [threadId, flag] = key.split('\u0000')
      //  IN ORDER, and awaited one at a time: the flame is a label and an
      //  archive, and the ship's writer is one serialisation point.
      for (const op of flagOps(threadId, flag, on)) {
        if (op.call === 'label') await api.setLabel(op.threadId, op.label, op.add)
        else await api.setArchived(op.threadId, op.archived)
      }
    }
  } catch (e) { await classify(e) }
}

//  WHICH THREAD a mirrored message belongs to, read off the message
//  itself rather than out of storage. `X-Auspex-Thread` is written at
//  import by lib/rfc822.js and every mirrored message has one, including
//  the ones imported by a version that had never heard of labels — which
//  is the whole reason the thread is not a field on the record.
async function threadOf(tbId) {
  try {
    const full = await browser.messages.getFull(tbId)
    const h = (full.headers && full.headers['x-auspex-thread']) || []
    return h.length ? String(h[0]).trim() : null
  } catch { return null }
}

//  THE ONE RELAY, for all three flags.
//
//  `changed` names the properties that moved; the values are read off the
//  header. The no-loop rule is the same for each: a flag that already
//  matches what we recorded is the echo of an update this extension just
//  made during a sync, and relaying it is how a mirror starts talking to
//  itself. Recorded state is compared loosely because a record written by
//  an older version has no `flagged` or `junk` field at all, and absent
//  must read as "not set" rather than as "differs from false".
const RELAYED = ['read', 'flagged', 'junk']

browser.messages.onUpdated.addListener(async (message, changed) => {
  const touched = RELAYED.filter((k) => k in changed)
  if (!touched.length) return
  const id = idFromMessageId(message.headerMessageId)
  if (!id) return
  const state = await getState()
  const rec = state.imported[id]
  if (!rec) return                                    // not ours
  let moved = false
  let threadId
  for (const key of touched) {
    if (!!rec[key] === !!message[key]) continue       // already what we recorded
    rec[key] = !!message[key]
    moved = true
    if (key === 'read') { queueReadState(id, !!message.read); continue }
    if (threadId === undefined) threadId = await threadOf(message.id)
    if (threadId) queueFlag(threadId, key, !!message[key])
  }
  if (moved) await setState({ imported: state.imported })
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
      const hash = await api.uploadBlob(bytes)
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
    stopBeacon()
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
    //  THE SEED, and the only sync this extension asks for by itself. Not
    //  the same thing as a stream reconnect, which mirrors nothing: this
    //  is a person pressing Connect on a mailbox nothing has mirrored
    //  yet, and it happens once.
    syncNow()
    startBeacon()
    return { ok: true, ship, origin: api.origin }
  } catch (e) {
    await classify(e)
    return { ok: false, error: e && e.message ? e.message : String(e) }
  }
}

//  One line on the terminal that started Thunderbird, when dump is enabled
//  there: the cheapest possible proof that this script ran at all.
try { dump('AUSPEX background: start\n') } catch { /* no dump outside the shell */ }

//  ── the clock ───────────────────────────────────────────────────────

//  THE FALLBACK, not the clock. The beacon is what syncs this extension;
//  this fires only for the case the beacon cannot see — a stream that
//  died silently, so the reader blocks for ever and nothing errors.
//
//  It skips when the stream is running AND has proved itself since the
//  last time this fired, because a stream that delivered a change is a
//  stream that is demonstrably alive and syncing it again would be the
//  sixty-second poll back in slower clothes.
browser.alarms.create('auspex-sync', { periodInMinutes: FALLBACK_MINUTES })
browser.alarms.onAlarm.addListener(async (a) => {
  if (a.name !== 'auspex-sync') return
  const { origin, status } = await getState()
  if (!origin || status === 'signed-out') return
  //  A loop that has genuinely EXITED is restarted — that is not a
  //  staleness watchdog, it is noticing there is no reader at all.
  if (!streaming) startBeacon()
  const since = Date.now() - FALLBACK_MINUTES * 60000
  const proved = beaconLog.some((e) => e.change && e.at >= since)
  if (streaming && proved) return
  syncNow()
})

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
      runSelftest(cfg, {
        connect, syncNow, getState, setState, apiFor,
        beacon: {
          log: beaconLog, start: startBeacon, stop: stopBeacon,
          running: () => streaming,
          abort: () => { try { if (streamAbort) streamAbort.abort() } catch { /* */ } },
        },
      })
      return
    }
  } catch { /* no selftest in this build */ }
  const { origin } = await getState()
  //  ONE sync at startup — the mailbox may have moved while Thunderbird
  //  was closed, and the beacon says nothing about what it missed — and
  //  then the stream, which is what carries everything after it.
  if (origin) { syncNow(); startBeacon() }
})()

export { syncNow, connect, htmlToText }

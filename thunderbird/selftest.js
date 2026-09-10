//  THE SELFTEST PATH — present only in a build made with
//  `npm run build -- --selftest`, never in the shipped zip.
//
//  WHY IT EXISTS AT ALL. Driving this extension end to end without a human
//  means seeding the connect form, and there is no way in: an extension's
//  storage.local lives in a per-extension IndexedDB inside the profile,
//  under a moz-extension origin whose UUID is minted at install, and
//  nothing in a profile's prefs reaches it. What an extension CAN read
//  without a click is its own packaged files. So the selftest build carries
//  one — `selftest.json` — and the background fetches it at startup. In an
//  ordinary build that fetch 404s and none of this file is even imported.
//
//  It reports by POSTing to a sink named in the config, because an
//  extension's console.log does not reach the terminal that started
//  Thunderbird. The sink is a plain node http server on localhost; the
//  selftest manifest grants that origin and the ship's, and nothing else.

import { patternFor, setTap } from './lib/api.js'
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

export async function runSelftest(cfg, api) {
  const log = async (step, ok, detail) => {
    const line = JSON.stringify({ step, ok, detail, at: Date.now() })
    //  TWO CHANNELS, because either one can be the one that survives. `dump`
    //  reaches the terminal that started Thunderbird (with
    //  browser.dom.window.dump.enabled set); the sink reaches a file. The
    //  body is text/plain deliberately: a JSON content-type makes this a
    //  preflighted CORS request, and a preflight is one more thing that can
    //  fail between the evidence and the person meant to read it.
    try { dump(`AUSPEX-SELFTEST ${line}\n`) } catch { /* no dump here */ }
    try {
      await fetch(cfg.sink, {
        method: 'POST', headers: { 'content-type': 'text/plain' }, body: line,
      })
    } catch (e) {
      try { dump(`AUSPEX-SELFTEST sink-failed ${e && e.message}\n`) } catch { /* */ }
    }
  }

  const step = async (name, fn) => {
    try {
      const detail = await fn()
      await log(name, true, detail === undefined ? 'ok' : detail)
      return detail
    } catch (e) {
      await log(name, false, `${e && e.message ? e.message : e}`)
      return null
    }
  }

  //  THE BEACON RUN, a different question entirely and so a different
  //  script. The run above asks whether the mirror is correct; this one
  //  asks what it COSTS — how many requests an idle extension makes, that
  //  a change still arrives, that a reconnect mirrors nothing, and that a
  //  dead ship is backed off rather than drummed on.
  if (cfg.mode === 'beacon') return runBeaconTest(cfg, api, log, step)

  //  A FETCH PROBE, first, because "NetworkError" from an extension is one
  //  word for a dozen causes and the only way to tell them apart is to vary
  //  one thing at a time.
  await step('probe', async () => {
    const out = {}
    const tries = [
      ['sink-cors', `${new URL(cfg.sink).origin}/report`, {}],
      ['sink-nocors', `${new URL(cfg.sink).origin}/nocors`, {}],
      ['get-plain', `${cfg.origin}/~/login`, {}],
      ['get-creds', `${cfg.origin}/~/login`, { credentials: 'include' }],
      ['get-api', `${cfg.origin}/apps/auspex/api/whoami`, { credentials: 'include' }],
      ['post-plain', `${cfg.origin}/~/login`, {
        method: 'POST',
        headers: { 'content-type': 'application/x-www-form-urlencoded' },
        body: `password=${encodeURIComponent(cfg.code)}`,
      }],
      ['post-creds', `${cfg.origin}/~/login`, {
        method: 'POST',
        credentials: 'include',
        headers: { 'content-type': 'application/x-www-form-urlencoded' },
        body: `password=${encodeURIComponent(cfg.code)}`,
      }],
    ]
    try {
      out.hasShipOrigin = await browser.permissions.contains({ origins: [patternFor(cfg.origin)] })
      out.hasSinkOrigin = await browser.permissions.contains({ origins: [patternFor(cfg.sink)] })
      out.all = JSON.stringify(await browser.permissions.getAll())
    } catch (e) { out.perms = `THREW ${e && e.message}` }
    for (const [name, url, init] of tries) {
      try {
        const r = await fetch(url, init)
        out[name] = `${r.status} ${r.type}`
      } catch (e) { out[name] = `THREW ${e && e.message}` }
    }
    //  Is the origin merely RECORDED as granted, or actually registered
    //  with the extension policy the network layer consults? Re-requesting
    //  an already-granted permission resolves without a prompt, and if the
    //  fetch works afterwards the two were out of step.
    try {
      out.reRequest = await browser.permissions.request({ origins: [patternFor(cfg.origin)] })
      const r = await fetch(`${cfg.origin}/apps/auspex/api/whoami`, { credentials: 'include' })
      out.afterRequest = `${r.status} ${r.type}`
    } catch (e) { out.afterRequest = `THREW ${e && e.message}` }
    return JSON.stringify(out)
  })

  //  ── connect and mirror ────────────────────────────────────────────

  //  A CLEAN MIRROR, when the config asks for one. Only the derived
  //  state — everything below is rebuilt from the ship on the next sync —
  //  and it is here because a run that starts from mail an earlier run
  //  left behind cannot tell a flag it just set from one that was already
  //  there. The mail itself is deleted from the profile by the harness.
  if (cfg.reset) {
    await step('reset', async () => {
      await api.setState({
        imported: {}, snapshot: {}, folders: {}, counts: { messages: 0, threads: 0 },
      })
      return 'imported, snapshot, folders cleared'
    })
  }

  await step('connect', async () => {
    const res = await api.connect(cfg.origin, cfg.code)
    if (!res.ok) throw new Error(res.error)
    return res.ship
  })

  //  A SYNC THAT ACTUALLY RAN. `connect` starts one in the background, so
  //  the first explicit `syncNow` answers `{skipped: true}` and everything
  //  below it would be reading the state from BEFORE the mirror was
  //  brought up to date. A skipped sync proves nothing: ask again.
  const syncForReal = async () => {
    let r = await api.syncNow()
    for (let i = 0; i < 25 && r && r.skipped && !r.why; i += 1) {
      await sleep(2000)
      r = await api.syncNow()
    }
    return r
  }

  await step('sync', async () => {
    const r = await syncForReal()
    const s = await api.getState()
    return JSON.stringify({ r, counts: s.counts, folders: s.folders, status: s.status })
  })

  const folderIds = (await api.getState()).folders

  const listFolder = async (name) => {
    const page = await browser.messages.list(folderIds[name])
    let msgs = page.messages.slice()
    let id = page.id
    while (id) {
      const next = await browser.messages.continueList(id)
      msgs = msgs.concat(next.messages)
      id = next.id
    }
    return msgs
  }

  await step('folders', async () => {
    const out = {}
    for (const n of ['Inbox', 'Sent', 'Archived']) out[n] = (await listFolder(n)).length
    return JSON.stringify(out)
  })

  //  ── the star and the flame, both directions ───────────────────────
  //
  //  Two per-message buttons in Thunderbird, two labels on the ship. What
  //  is worth proving here is not that a click reaches the ship — that is
  //  one POST — but the two rules around it: that the flame writes BOTH
  //  the label and the archive flag, and that a label arriving from
  //  outside reaches EVERY mirrored message of its thread and no message
  //  of any other.

  const shipThread = async (id) => (await api.apiFor()).thread(id)

  //  Every mirrored message of one thread: the ship's own membership,
  //  each looked up in Thunderbird BY MESSAGE-ID.
  //
  //    Neither half of this comes from the extension's bookkeeping, and
  //    that is the point. The ship says which messages are in the thread;
  //    Thunderbird says which local message carries each id. A test that
  //    read `imported[id].tbId` would be asking the thing under test
  //    where to look, and would pass just as happily against a record
  //    pointing at the wrong mail.
  const mirrored = async (threadId) => {
    const t = await shipThread(threadId)
    const out = []
    for (const m of (t.messages || [])) {
      try {
        const found = await browser.messages.query({ headerMessageId: `${m.id}@auspex.urbit` })
        const h = (found.messages || [])[0]
        if (h) out.push({ id: m.id, tbId: h.id })
      } catch { /* not mirrored */ }
    }
    return out
  }

  const flagsOf = async (ms) => {
    const out = []
    for (const m of ms) {
      try { out.push(!!(await browser.messages.get(m.tbId)).flagged) } catch { out.push(null) }
    }
    return out
  }

  //  What a flag step reports, pass or fail. A bare "labels []" says the
  //  ship has no label and nothing about WHY — whether the local flag
  //  even moved, whether the message under that id is the one meant, and
  //  what the mirror had recorded about it.
  const seenOf = async (target, before, after, t) => JSON.stringify({
    want: target.id,
    header: after.headerMessageId,
    wasFlagged: before.flagged, nowFlagged: after.flagged,
    wasJunk: before.junk, nowJunk: after.junk,
    record: (await api.getState()).imported[target.id],
    labels: (t && t.labels) || null,
    archived: t ? t.archived : null,
  })

  //  Set one flag on one mirrored message and read the ship back. The
  //  relay is debounced by two seconds; the local read at 1.5s is before
  //  that, so it says whether Thunderbird took the write at all
  //  independently of whether the ship heard about it.
  const localFlag = async (threadId, patch) => {
    const ms = await mirrored(threadId)
    if (!ms.length) throw new Error(`nothing mirrored for ${threadId}`)
    const target = ms[0]
    //  A FLAG ALREADY WHERE THIS STEP MEANS TO PUT IT PROVES NOTHING:
    //  `messages.update` fires no onUpdated for a value that did not
    //  move, so the relay never runs and the step would be measuring
    //  whatever an earlier run left on the ship. Put it back first, and
    //  give that relay its own two seconds to land.
    const [key] = Object.keys(patch)
    const initial = await browser.messages.get(target.tbId)
    if (!!initial[key] === !!patch[key]) {
      await browser.messages.update(target.tbId, { [key]: !patch[key] })
      await sleep(4000)
    }
    const before = await browser.messages.get(target.tbId)
    await browser.messages.update(target.tbId, patch)
    await sleep(1500)
    const after = await browser.messages.get(target.tbId)
    await sleep(4000)
    const t = await shipThread(threadId)
    return { target, before, after, t, seen: await seenOf(target, before, after, t) }
  }

  await step('flag-star', async () => {
    const r = await localFlag(cfg.starThread, { flagged: true })
    if (!(r.t.labels || []).includes('flagged')) throw new Error(r.seen)
    return r.seen
  })

  await step('flag-junk', async () => {
    const r = await localFlag(cfg.junkThread, { junk: true })
    //  BOTH, and this is the whole point of the flame being two calls.
    if (!(r.t.labels || []).includes('junk')) throw new Error(r.seen)
    if (r.t.archived !== true) throw new Error(r.seen)
    return r.seen
  })

  await step('flag-unjunk', async () => {
    const r = await localFlag(cfg.junkThread, { junk: false })
    //  the flag has to have BEEN set, or this proves nothing at all.
    if (!r.before.junk) throw new Error(`was not junk to begin with: ${r.seen}`)
    if ((r.t.labels || []).includes('junk')) throw new Error(r.seen)
    if (r.t.archived !== false) throw new Error(r.seen)
    return r.seen
  })

  //  SHIP → THUNDERBIRD. The label is put on by the harness outside, with
  //  curl, while this waits: polled rather than slept on, because what is
  //  waited for belongs to another process.
  await step('flag-inbound', async () => {
    let t = null
    for (let i = 0; i < 45; i += 1) {
      t = await shipThread(cfg.inboundThread)
      if ((t.labels || []).includes('flagged')) break
      await sleep(2000)
    }
    if (!((t && t.labels) || []).includes('flagged')) {
      throw new Error(`${cfg.inboundThread} never gained the label from outside`)
    }
    const r = await syncForReal()
    const ours = await mirrored(cfg.inboundThread)
    const others = await mirrored(cfg.untouchedThread)
    const flags = await flagsOf(ours)
    const otherFlags = await flagsOf(others)
    const missed = ours.filter((m, i) => !flags[i]).map((m) => m.id)
    const stray = others.filter((m, i) => otherFlags[i]).map((m) => m.id)
    const seen = JSON.stringify({
      sync: r,
      thread: cfg.inboundThread,
      labels: t.labels,
      mirrored: ours.length,
      flagged: flags.filter(Boolean).length,
      missed,
      untouched: cfg.untouchedThread,
      untouchedCount: others.length,
      stray,
    })
    if (!ours.length) throw new Error(`nothing mirrored for the inbound thread: ${seen}`)
    if (!others.length) throw new Error(`nothing mirrored for the untouched thread: ${seen}`)
    if (missed.length) throw new Error(`not every message flagged: ${seen}`)
    if (stray.length) throw new Error(`an untouched thread is flagged: ${seen}`)
    return seen
  })

  //  ── a fresh send ──────────────────────────────────────────────────

  //  compose.sendMessage rejects when onBeforeSend cancels, and this
  //  extension ALWAYS cancels: a successful auspex send is one this
  //  extension made itself over HTTP, and letting Thunderbird also try to
  //  deliver it by SMTP is the failure the cancel exists to stop. So the
  //  rejection is expected and what proves the send is the ship's copy.
  //  sendMessage's promise settles when Thunderbird's own send finishes —
  //  and when onBeforeSend cancels it (which is the whole point here) it
  //  never settles at all. Proven live: the first end-to-end run delivered
  //  the message to the other ship and then sat on this await forever. So
  //  the await is raced against a clock, and "still pending" is the
  //  expected answer for a send the extension took over.
  const sendVia = async (tab) => {
    const timeout = new Promise((r) => setTimeout(() => r('sendMessage still pending after 15s (expected: the extension cancelled the SMTP send)'), 15000))
    try {
      return await Promise.race([
        browser.compose.sendMessage(tab.id).then(() => 'sendMessage resolved'),
        timeout,
      ])
    } catch (e) { return String(e && e.message) }
  }

  await step('send-new', async () => {
    const tab = await browser.compose.beginNew(undefined, {
      to: cfg.to, subject: cfg.subject, plainTextBody: cfg.body, isPlainText: true,
    })
    const r = await sendVia(tab)
    await sleep(2000)
    const open = (await browser.tabs.query({})).some((t) => t.id === tab.id)
    return JSON.stringify({ r, composeStillOpen: open })
  })

  //  ── a reply to a mirrored message ─────────────────────────────────

  await step('send-reply', async () => {
    const inbox = await listFolder('Inbox')
    const target = inbox.find((m) => (m.subject || '').includes(cfg.replyToSubject))
    if (!target) throw new Error(`no mirrored message matching ${cfg.replyToSubject}`)
    const full = await browser.messages.getFull(target.id)
    const parent = (full.headers['message-id'] || [])[0]
    const tab = await browser.compose.beginReply(target.id, 'replyToSender', {
      to: cfg.to, plainTextBody: cfg.replyBody, isPlainText: true,
    })
    const r = await sendVia(tab)
    await sleep(2000)
    return JSON.stringify({ r, repliedTo: parent, subject: target.subject })
  })

  //  ── an attachment ─────────────────────────────────────────────────

  await step('send-attachment', async () => {
    //  1KB of deterministic bytes, so the sha256 on the other ship is a
    //  number this test can be checked against from outside.
    const bytes = new Uint8Array(1024)
    for (let i = 0; i < bytes.length; i += 1) bytes[i] = (i * 7 + 11) & 0xff
    const file = new File([bytes], cfg.attachName, { type: 'application/octet-stream' })
    const tab = await browser.compose.beginNew(undefined, {
      to: cfg.to, subject: cfg.attachSubject, plainTextBody: 'one file attached',
      isPlainText: true, attachments: [{ file, name: cfg.attachName }],
    })
    const r = await sendVia(tab)
    await sleep(3000)
    return JSON.stringify({ r, bytes: bytes.length })
  })

  //  ── the failure case ──────────────────────────────────────────────
  //
  //  Signed out: the session cookie is removed under the ship's origin,
  //  which is exactly what an expired session looks like. The send must be
  //  cancelled, nothing must reach the ship, and the compose window must
  //  still be there with its content.
  await step('signed-out-send', async () => {
    const removed = []
    for (const c of await browser.cookies.getAll({ url: cfg.origin })) {
      await browser.cookies.remove({ url: cfg.origin, name: c.name })
      removed.push(c.name)
    }
    const tab = await browser.compose.beginNew(undefined, {
      to: cfg.to, subject: cfg.failSubject, plainTextBody: 'this must not arrive',
      isPlainText: true,
    })
    const r = await sendVia(tab)
    await sleep(1500)
    const open = (await browser.tabs.query({})).some((t) => t.id === tab.id)
    const s = await api.getState()
    return JSON.stringify({ removed, r, composeStillOpen: open, status: s.status })
  })

  await step('done', async () => JSON.stringify((await api.getState()).counts))
}

//  ── the beacon run ──────────────────────────────────────────────────
//
//  The claim under test is a COST, so everything here is a count. The
//  request tap in lib/api.js is the instrument: it is the only way to
//  count from inside an extension what that extension asked the ship for,
//  because an add-on cannot see its own network log and a count taken
//  from outside cannot tell this extension's traffic from the browser's.
//
//  The one step that needs a hand from outside is the change: something
//  has to send mail. This logs a marker and then waits, so the harness can
//  watch for the marker, send from the other ship, and watch for what
//  follows.
async function runBeaconTest(cfg, api, log, step) {
  //  every request, from the moment the tap is set
  const requests = []
  setTap((path) => requests.push({ at: Date.now(), path }))
  const since = (t) => requests.filter((r) => r.at >= t)

  const listFolder = async (name) => {
    const folders = (await api.getState()).folders
    const page = await browser.messages.list(folders[name])
    let msgs = page.messages.slice()
    let id = page.id
    while (id) {
      const next = await browser.messages.continueList(id)
      msgs = msgs.concat(next.messages)
      id = next.id
    }
    return msgs
  }

  //  A sync that actually ran. `connect` starts one in the background, so
  //  the first explicit syncNow answers `{skipped: true}` and anything
  //  measured after it would be measuring the seed.
  const settled = async () => {
    let r = await api.syncNow()
    for (let i = 0; i < 30 && r && r.skipped && !r.why; i += 1) {
      await sleep(2000)
      r = await api.syncNow()
    }
    return r
  }

  await step('connect', async () => {
    const res = await api.connect(cfg.origin, cfg.code)
    if (!res.ok) throw new Error(res.error)
    await settled()
    return JSON.stringify({ ship: res.ship, counts: (await api.getState()).counts })
  })

  //  ── 1. what an idle extension costs ───────────────────────────────
  //
  //  The whole reason for the change. The old build synced every sixty
  //  seconds: three syncs in this window, each a whoami plus at least one
  //  inbox page plus a thread fetch per changed thread. The new one
  //  should make NOTHING — one connection, already open, held.
  await step('idle', async () => {
    //  let the seed's own traffic finish before the window opens
    await sleep(5000)
    const from = Date.now()
    const streamAt = requests.length
    for (let i = 0; i < 18; i += 1) await sleep(10000)   // 180s, in slices
    const made = since(from)
    return JSON.stringify({
      windowSeconds: Math.round((Date.now() - from) / 1000),
      requests: made.length,
      paths: made.map((r) => r.path),
      streamOpens: requests.slice(streamAt).filter((r) => r.path.includes('/beacon/')).length,
      streaming: api.beacon.running(),
      log: api.beacon.log.slice(-5),
    })
  })

  //  ── 2. a change still arrives ─────────────────────────────────────
  //
  //  The marker is the handshake: the harness sends from the other ship
  //  when it sees this line, and what follows is the beacon's own doing.
  await step('await-send', async () => 'SEND NOW')

  await step('change', async () => {
    const from = Date.now()
    const before = api.beacon.log.filter((e) => e.change).length
    let seen = null
    for (let i = 0; i < 60; i += 1) {
      const changes = api.beacon.log.filter((e) => e.change)
      if (changes.length > before) { seen = changes[changes.length - 1]; break }
      await sleep(1000)
    }
    if (!seen) throw new Error(`no beacon change in 60s; requests: ${since(from).length}`)
    //  the sync the change fired has to finish before the folder is read
    await sleep(1000)
    await settled()
    const inbox = await listFolder('Inbox')
    const hit = inbox.filter((m) => (m.subject || '').includes(cfg.expectSubject))
    return JSON.stringify({
      secondsToChange: (seen.at - from) / 1000,
      requestsAfterChange: since(seen.at).map((r) => r.path),
      inbox: inbox.length,
      matched: hit.length,
      subject: hit.length ? hit[0].subject : null,
    })
  })

  //  ── 3. a reconnect mirrors nothing ────────────────────────────────
  //
  //  Abort the stream under the reader. It reconnects, registration
  //  replays the current revision as `old /rev`, and that must cost
  //  exactly one request and produce no sync at all.
  await step('reconnect', async () => {
    const from = Date.now()
    api.beacon.abort()
    for (let i = 0; i < 20; i += 1) {
      await sleep(1000)
      if (since(from).some((r) => r.path.includes('/beacon/'))) break
    }
    await sleep(15000)
    const made = since(from)
    const beacons = made.filter((r) => r.path.includes('/beacon/'))
    return JSON.stringify({
      total: made.length,
      beaconOpens: beacons.length,
      apiRequests: made.filter((r) => !r.path.includes('/beacon/')).map((r) => r.path),
      streaming: api.beacon.running(),
    })
  })

  //  ── 4. a dead ship is backed off, not drummed on ──────────────────
  //
  //  Pointed at a port nothing listens on, so every attempt fails at once
  //  — which is the shape that makes a bare retry loop a hot loop. The
  //  gaps are what is under test: 3, 6, 12, 24, 30, 30, each spread over
  //  0.5–1.5×, and not six evenly spaced threes.
  //
  //  LAST, because it leaves the extension pointed at nothing.
  await step('backoff', async () => {
    api.beacon.stop()
    await sleep(2000)
    await api.setState({ origin: cfg.deadOrigin })
    api.beacon.log.length = 0
    const from = Date.now()
    api.beacon.start()
    for (let i = 0; i < 13; i += 1) await sleep(10000)   // 130s
    const attempts = api.beacon.log.filter((e) => e.delay !== undefined)
    const gaps = attempts.map((e, i) => (i ? (e.at - attempts[i - 1].at) / 1000 : (e.at - from) / 1000))
    return JSON.stringify({
      windowSeconds: Math.round((Date.now() - from) / 1000),
      attempts: attempts.length,
      gapsSeconds: gaps,
      plannedDelays: attempts.map((e) => e.delay / 1000),
      counts: attempts.map((e) => e.attempt),
    })
  })

  await step('done', async () => JSON.stringify({ requests: requests.length }))
}

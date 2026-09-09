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

import { patternFor } from './lib/api.js'
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

  //  Every mirrored message of one thread. `threadId` is on the imported
  //  record precisely so the relay can find it; reading it back here is
  //  also the proof that it was recorded.
  const mirrored = async (threadId) => {
    const imported = (await api.getState()).imported
    return Object.entries(imported)
      .filter(([, r]) => r.threadId === threadId && r.tbId !== null)
      .map(([id, r]) => ({ id, tbId: r.tbId }))
  }

  const shipThread = async (id) => (await api.apiFor()).thread(id)

  const flagsOf = async (ms) => {
    const out = []
    for (const m of ms) {
      try { out.push(!!(await browser.messages.get(m.tbId)).flagged) } catch { out.push(null) }
    }
    return out
  }

  await step('flag-star', async () => {
    const ms = await mirrored(cfg.starThread)
    if (!ms.length) throw new Error(`nothing mirrored for ${cfg.starThread}`)
    await browser.messages.update(ms[0].tbId, { flagged: true })
    //  the relay is debounced by two seconds; five is that plus the round
    //  trip, and a bare sleep is honest here because the thing waited on
    //  is a timer this process owns.
    await sleep(5000)
    const t = await shipThread(cfg.starThread)
    const labels = t.labels || []
    if (!labels.includes('flagged')) throw new Error(`labels ${JSON.stringify(labels)}`)
    return JSON.stringify({ starred: ms[0].id, labels, archived: t.archived })
  })

  await step('flag-junk', async () => {
    const ms = await mirrored(cfg.junkThread)
    if (!ms.length) throw new Error(`nothing mirrored for ${cfg.junkThread}`)
    await browser.messages.update(ms[0].tbId, { junk: true })
    await sleep(5000)
    const t = await shipThread(cfg.junkThread)
    const labels = t.labels || []
    //  BOTH, and this is the whole point of the flame being two calls.
    if (!labels.includes('junk')) throw new Error(`labels ${JSON.stringify(labels)}`)
    if (t.archived !== true) throw new Error(`archived ${t.archived}`)
    return JSON.stringify({ junked: ms[0].id, labels, archived: t.archived })
  })

  await step('flag-unjunk', async () => {
    const ms = await mirrored(cfg.junkThread)
    await browser.messages.update(ms[0].tbId, { junk: false })
    await sleep(5000)
    const t = await shipThread(cfg.junkThread)
    const labels = t.labels || []
    if (labels.includes('junk')) throw new Error(`labels ${JSON.stringify(labels)}`)
    if (t.archived !== false) throw new Error(`archived ${t.archived}`)
    return JSON.stringify({ unjunked: ms[0].id, labels, archived: t.archived })
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
    if (!ours.length) throw new Error('nothing mirrored for the inbound thread')
    if (!others.length) throw new Error('nothing mirrored for the untouched thread')
    if (flags.some((f) => !f)) throw new Error(`not every message flagged: ${JSON.stringify(flags)}`)
    if (otherFlags.some((f) => f)) {
      throw new Error(`an untouched thread is flagged: ${JSON.stringify(otherFlags)}`)
    }
    return JSON.stringify({
      sync: r,
      thread: cfg.inboundThread,
      labels: t.labels,
      flagged: flags,
      untouched: cfg.untouchedThread,
      untouchedFlags: otherFlags,
    })
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

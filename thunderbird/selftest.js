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
      out.hasShipOrigin = await browser.permissions.contains({ origins: [`${cfg.origin}/*`] })
      out.hasSinkOrigin = await browser.permissions.contains({ origins: [`${new URL(cfg.sink).origin}/*`] })
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
      out.reRequest = await browser.permissions.request({ origins: [`${cfg.origin}/*`] })
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

  await step('sync', async () => {
    const r = await api.syncNow()
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

  //  ── a fresh send ──────────────────────────────────────────────────

  //  compose.sendMessage rejects when onBeforeSend cancels, and this
  //  extension ALWAYS cancels: a successful auspex send is one this
  //  extension made itself over HTTP, and letting Thunderbird also try to
  //  deliver it by SMTP is the failure the cancel exists to stop. So the
  //  rejection is expected and what proves the send is the ship's copy.
  const sendVia = async (tab) => {
    try { await browser.compose.sendMessage(tab.id) } catch (e) { return String(e && e.message) }
    return 'sendMessage resolved'
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

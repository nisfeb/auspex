//  The options page. Two fields, one button, and the only place the access
//  code is ever typed.
//
//  THE HOST PERMISSION IS REQUESTED HERE, for exactly the origin the user
//  just typed, from inside the click handler — `permissions.request` needs
//  a user gesture and will not be given one anywhere else. The manifest
//  asks for `http://*/*` and `https://*/*` as OPTIONAL, which is a promise
//  that nothing is granted until this moment; it never asks for
//  <all_urls> outright.

import { patternFor } from './lib/api.js'
const $ = (id) => document.getElementById(id)
const say = (text, bad = false) => {
  $('status').textContent = text
  $('status').classList.toggle('bad', bad)
}

const describe = (s) => {
  if (s.status === 'connected') {
    return `Connected as ${s.ship} at ${s.origin}.`
      + (s.lastSync ? ` Last sync ${new Date(s.lastSync).toLocaleString()}.` : '')
  }
  if (s.status === 'signed-out') return `Signed out of ${s.origin}. Connect again.`
  if (s.status === 'unreachable') return `${s.origin} did not answer: ${s.lastError}`
  return 'No ship configured yet.'
}

async function refresh() {
  const s = await browser.runtime.sendMessage({ kind: 'state' })
  if (s.origin) $('origin').value = s.origin
  say(describe(s), s.status === 'signed-out' || s.status === 'unreachable')
}

$('connect').addEventListener('click', async () => {
  const raw = $('origin').value.trim()
  const code = $('code').value.trim()
  if (!raw || !code) { say('A ship URL and an access code, please.', true); return }
  let origin
  try { origin = new URL(raw).origin } catch { say('That is not a URL.', true); return }

  say('Asking Thunderbird for permission to talk to that origin…')
  let granted = false
  try {
    granted = await browser.permissions.request({ origins: [patternFor(origin)] })
  } catch (e) { say(`Permission request failed: ${e.message}`, true); return }
  if (!granted) { say('Without permission for that origin nothing can be fetched.', true); return }

  say('Logging in…')
  const res = await browser.runtime.sendMessage({ kind: 'connect', origin, code })
  //  THE CODE LEAVES THE PAGE THE MOMENT IT IS USED. It was never stored
  //  and it is not left sitting in a form field either.
  $('code').value = ''
  if (!res.ok) { say(`Could not connect: ${res.error}`, true); return }
  say(`Connected as ${res.ship}. Mirroring into Local Folders → Auspex.`)
})

$('disconnect').addEventListener('click', async () => {
  await browser.runtime.sendMessage({ kind: 'disconnect' })
  say('Forgotten. The mirrored folders are still in Local Folders; delete them '
    + 'yourself if you want them gone.')
})

refresh()

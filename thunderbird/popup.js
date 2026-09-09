//  Status, and the three things a person actually wants from a toolbar
//  button: sync it now, open the client that owns the features this mirror
//  does not, and get to the options.

const $ = (id) => document.getElementById(id)

async function render() {
  const s = await browser.runtime.sendMessage({ kind: 'state' })
  const dot = $('dot')
  dot.className = 'dot'
  if (s.status === 'connected') { dot.classList.add('ok'); $('who').textContent = `Connected as ${s.ship}` }
  else if (s.status === 'signed-out') { dot.classList.add('bad'); $('who').textContent = 'Signed out' }
  else if (s.status === 'unreachable') { dot.classList.add('warn'); $('who').textContent = 'Ship unreachable' }
  else { $('who').textContent = 'No ship configured' }
  $('last').textContent = s.lastSync ? new Date(s.lastSync).toLocaleTimeString() : 'never'
  $('threads').textContent = s.counts ? s.counts.threads : 0
  $('messages').textContent = s.counts ? s.counts.messages : 0
  $('err').textContent = s.lastError || ''
  $('web').disabled = !s.origin
  return s
}

$('sync').addEventListener('click', async () => {
  $('sync').disabled = true
  $('sync').textContent = 'Syncing…'
  await browser.runtime.sendMessage({ kind: 'sync' })
  $('sync').textContent = 'Sync now'
  $('sync').disabled = false
  render()
})

//  The web client owns lists, filters, labels, drafts, the tree view and
//  the attachment fetch control. This button is the honest answer to every
//  one of them.
$('web').addEventListener('click', async () => {
  const s = await browser.runtime.sendMessage({ kind: 'state' })
  if (s.origin) browser.windows.openDefaultBrowser(`${s.origin}/apps/auspex/`)
})

$('opts').addEventListener('click', () => browser.runtime.openOptionsPage())

render()

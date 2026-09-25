import test from 'node:test'
import assert from 'node:assert/strict'
import { Api, normaliseOrigin, patternFor } from '../lib/api.js'

test('a permission pattern names the host and never the port', () => {
  //  a pattern with a port matches nothing, is granted anyway, and every
  //  fetch to the ship then fails CORS (92fd21f)
  assert.equal(patternFor('http://127.0.0.1:8081'), 'http://127.0.0.1/*')
  assert.equal(patternFor('https://ship.example.com'), 'https://ship.example.com/*')
})

test('a stored origin is exactly an origin, and only http or https', () => {
  assert.equal(normaliseOrigin('  http://localhost:8081/apps/auspex/?x=1 '), 'http://localhost:8081')
  assert.equal(new Api('https://ship.example.com/').origin, 'https://ship.example.com')
  for (const bad of ['javascript:alert(1)', 'file:///etc/passwd', 'not a url']) {
    assert.throws(() => normaliseOrigin(bad), bad)
  }
})

test('an id from a message never steers a request off its route', async (t) => {
  //  ids arrive in mail an attacker signed; each must stay one path segment
  const seen = []
  t.mock.method(globalThis, 'fetch', async (url, init) => {
    seen.push([url, init.credentials])
    return new Response('{}', { status: 200, headers: { 'content-type': 'application/json' } })
  })
  const api = new Api('http://localhost:8081')
  await api.thread('../../../~/login?x=1#y')
  await api.blob('../session', 'a.txt&mime=text/html', 'text/plain')
  const [thread, blob] = seen.map(([u]) => new URL(u))
  assert.equal(thread.origin, 'http://localhost:8081')
  assert.equal(thread.pathname, '/apps/auspex/api/thread/..%2F..%2F..%2F~%2Flogin%3Fx%3D1%23y')
  assert.equal(thread.search, '')
  assert.equal(blob.pathname, '/apps/auspex/api/blob/..%2Fsession')
  assert.equal(blob.searchParams.get('name'), 'a.txt&mime=text/html')
  assert.deepEqual(blob.searchParams.getAll('mime'), ['text/plain'])
  assert.deepEqual(seen.map(([, c]) => c), ['include', 'include'])
})

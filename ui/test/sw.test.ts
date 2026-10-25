import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import vm from 'node:vm'

//  ui/sw.js run in a vm, with Cache Storage and fetch mocked. Cache
//  Storage is the origin's, so the mock's caches.match searches every
//  cache, as a browser's does.
const ORIGIN = 'https://ship.example'
const abs = (u: string) => new URL(u, ORIGIN).href
class Req extends Request { constructor(u: string, o?: RequestInit) { super(abs(u), o) } }
const keyOf = (k: string | Request) => typeof k === 'string' ? abs(k) : k.url

function worker() {
  const handlers: Record<string, (e: any) => void> = {}
  const stores = new Map<string, Map<string, Response>>()
  const caches = {
    async open(n: string) {
      if (!stores.has(n)) stores.set(n, new Map())
      const m = stores.get(n)!
      return {
        async put(k: string | Request, r: Response) { m.set(keyOf(k), r) },
        async addAll(rs: Request[]) { for (const r of rs) m.set(r.url, new Response('<shell>')) },
        async match(k: string | Request) { return m.get(keyOf(k))?.clone() },
        async delete(k: string | Request) { return m.delete(keyOf(k)) },
      }
    },
    async match(k: string | Request) {
      for (const m of stores.values()) if (m.has(keyOf(k))) return m.get(keyOf(k))!.clone()
      return undefined
    },
    async keys() { return [...stores.keys()] },
    async delete(n: string) { return stores.delete(n) },
  }
  let mode: 'owner' | 'ended' | 'offline' = 'owner'
  const gone = new Set<string>()
  let fetches = 0
  const fetch = async (req: Request) => {
    fetches += 1
    const p = new URL(req.url).pathname
    if (mode === 'offline') throw new TypeError('Failed to fetch')
    if (mode === 'ended') return new Response('{"error":"forbidden"}', { status: 403 })
    if (gone.has(p)) return new Response('{"error":"not found"}', { status: 404 })
    return new Response(`net ${p}`)
  }
  const self = {
    location: { origin: ORIGIN },
    addEventListener: (t: string, f: (e: any) => void) => { handlers[t] = f },
    skipWaiting: async () => {},
    clients: { claim: async () => {}, matchAll: async () => [] },
  }
  const src = readFileSync(resolve(import.meta.dirname, '../sw.js'), 'utf8')
  vm.runInNewContext(src, { self, caches, fetch, URL, Headers, Response, Request: Req })
  const lifecycle = async (t: 'install' | 'activate') => {
    let p: Promise<unknown> | undefined
    handlers[t]({ waitUntil: (x: Promise<unknown>) => { p = x } })
    await p
  }
  // what the page would get: a status and body, or the rejection
  const get = async (path: string) => {
    let p: Promise<Response> | null = null
    handlers.fetch({ request: new Req(path), respondWith: (x: Promise<Response>) => { p = x } })
    if (!p) return 'not intercepted'
    try {
      const r: Response = await p
      return `${r.status}${r.headers.get('x-auspex-cached') ? ' cached' : ''} ${await r.text()}`
    } catch { return 'rejected' }
  }
  return {
    caches, get, lifecycle, gone,
    set: (m: typeof mode) => { mode = m },
    fetches: () => fetches,
  }
}

const INBOX = '/apps/auspex/api/inbox'
const THREAD = '/apps/auspex/api/thread/0v1.dummy'
const OTHER = '/apps/auspex/api/thread/0v2.dummy'

test('mail read while signed in is served offline, marked as cached', async () => {
  const w = worker()
  assert.equal(await w.get(INBOX), `200 net ${INBOX}`)
  w.set('offline')
  assert.equal(await w.get(INBOX), `200 cached net ${INBOX}`)
})

test('after a 403 no cached mail is served offline', async () => {
  const w = worker()
  await w.get(INBOX)
  await w.get(THREAD)
  w.set('ended')
  assert.equal(await w.get(INBOX), '403 {"error":"forbidden"}')
  w.set('offline')
  assert.equal(await w.get(INBOX), 'rejected')
  assert.equal(await w.get(THREAD), 'rejected')
})

test('after a 404 for a thread that thread is not served offline, and others are', async () => {
  const w = worker()
  await w.get(THREAD)
  await w.get(OTHER)
  w.gone.add(THREAD)
  assert.equal(await w.get(THREAD), '404 {"error":"not found"}')
  w.set('offline')
  assert.equal(await w.get(THREAD), 'rejected')
  assert.equal(await w.get(OTHER), `200 cached net ${OTHER}`)
})

test('the shell comes only from our own cache, never from another on the origin', async () => {
  const w = worker()
  await (await w.caches.open('evil')).put('/apps/auspex/app.js', new Response('evil'))
  // not installed yet, so the network answers
  assert.equal(await w.get('/apps/auspex/app.js'), '200 net /apps/auspex/app.js')
  assert.equal(w.fetches(), 1)
  // installed after the plant, so the browser's match would find it first
  await w.lifecycle('install')
  await w.lifecycle('activate')
  assert.equal(await w.get('/apps/auspex/app.js'), '200 <shell>')
  assert.equal(await w.get('/apps/auspex'), '200 <shell>')
  assert.equal(w.fetches(), 1)
  // and another app's cache is left alone
  assert.ok((await w.caches.keys()).includes('evil'))
})

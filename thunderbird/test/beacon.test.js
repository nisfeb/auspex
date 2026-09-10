import test from 'node:test'
import assert from 'node:assert/strict'
import {
  isChange, revIn, framesIn, backoffFor, jittered, nextDelay, nextAttempt,
  BACKOFF_MIN, BACKOFF_MAX, LIVED_MS, MAX_ATTEMPT, BEACON_PATH,
} from '../lib/beacon.js'

//  ── the frame classifier ────────────────────────────────────────────

test('a reconnect that missed nothing is worth no sync', () => {
  //  The revision rides on every frame, including registration's replay.
  //  Same revision on reconnect = nothing moved while we were away, which
  //  is what makes a reconnect one request instead of a listing.
  const old1 = 'id: 43\nevent: old /rev\ndata: 170141184508152841273086689431159830477'
  const old2 = 'id: 44\nevent: old /rev\ndata: 170141184508152841273086689431159830477'
  const moved = 'id: 45\nevent: old /rev\ndata: 170141184508152841273086689431159830999'
  assert.equal(revIn(old1), '170141184508152841273086689431159830477')
  assert.equal(revIn(old1), revIn(old2), 'an unchanged ship replays the same revision')
  assert.notEqual(revIn(old1), revIn(moved), 'a ship that moved replays a new one')
  assert.equal(isChange(old1), false, 'an old frame is still not a change')
})

test('a frame for another leaf carries no revision', () => {
  //  The stream is the whole /beacon directory, so frames for its other
  //  leaves arrive here and are not the mail revision.
  assert.equal(revIn('id: 1\nevent: new /other\ndata: 12'), null)
  assert.equal(revIn('id: 1\nevent: old /rev'), null, 'a /rev frame with no data line')
})

test('the frame replayed at registration is not a change', () => {
  //  THE WHOLE POINT OF A CHEAP RECONNECT. Registration replays the
  //  current revision as an `old /rev` frame. Treating it as a change
  //  means every reconnect runs a full sync — a whoami plus a paged inbox
  //  walk plus a fetch per thread — and a reconnect is ORDINARY: a ship
  //  bounce, a laptop waking, a network that came back.
  assert.equal(isChange('id: 43\nevent: old /rev\ndata: 17014118450815284\n'), false)
  //  and it is still not a change with no id line, or with \r\n
  assert.equal(isChange('event: old /rev\r\ndata: 1\r\n'), false)
})

test('a /rev frame is a change and nothing else is', () => {
  //  what the ship sends when mail lands
  assert.equal(isChange('id: 44\nevent: new /rev\ndata: 17014118450815999\n'), true)
  assert.equal(isChange('event: over /rev\ndata: 1\n'), true)
  //  the stream carries the whole /beacon directory: its other leaves are
  //  not changes to the mail
  assert.equal(isChange('id: 45\nevent: new /other\ndata: 9\n'), false)
  assert.equal(isChange('id: 45\nevent: new /revision\ndata: 9\n'), false)
  //  /rev must be a whole segment, not the tail of a longer name
  assert.equal(isChange('event: new /notrev\ndata: 9\n'), false)
  //  the PATH is in the event line. `data:` carries the revision number,
  //  so a classifier that read `data` would match nothing and the
  //  extension would never sync again.
  assert.equal(isChange('id: 46\ndata: new /rev\n'), false)
  //  comments, keepalives and nothing at all
  assert.equal(isChange(': keepalive\n'), false)
  assert.equal(isChange(''), false)
})

test('the classifier answers for any bytes at all', () => {
  //  It runs on the stream reader, and a throw there is an extension that
  //  silently stops mirroring mail and never says why.
  for (const s of [undefined, null, 0, {}, [], 'event:', 'event:\n\n', '\r\r\r']) {
    assert.doesNotThrow(() => isChange(s), `threw on ${JSON.stringify(s)}`)
  }
})

test('this is the same stream the other two clients read', () => {
  //  ui/src/api.ts and desktop/src/notify.rs hold the same URL. Three
  //  clients that disagreed about what a change is would be three clients
  //  with different ideas of when mail arrived.
  assert.equal(BEACON_PATH, '/grubbery/api/keep/apps/auspex.auspex_app/beacon/rev')
})

//  ── the reader's buffer ─────────────────────────────────────────────

test('a partial frame stays in the buffer until it is whole', () => {
  //  A read lands wherever the network cut it. Losing the tail here would
  //  drop changes exactly when the ship is busy enough to split a frame.
  const a = framesIn('event: new /rev\ndata: 1\n\nevent: new /rev\ndata: 2\n\nevent: ne')
  assert.deepEqual(a.frames, ['event: new /rev\ndata: 1', 'event: new /rev\ndata: 2'])
  assert.equal(a.rest, 'event: ne')
  //  the rest, once the next read completes it, is one whole frame
  const b = framesIn(`${a.rest}w /rev\ndata: 3\n\n`)
  assert.deepEqual(b.frames, ['event: new /rev\ndata: 3'])
  assert.equal(b.rest, '')
  //  nothing whole yet is no frames and everything kept
  const c = framesIn('id: 1\nevent: new')
  assert.deepEqual(c.frames, [])
  assert.equal(c.rest, 'id: 1\nevent: new')
  //  \r\n\r\n separates too
  assert.deepEqual(framesIn('event: new /rev\r\ndata: 1\r\n\r\n').frames,
    ['event: new /rev\r\ndata: 1'])
})

//  ── the backoff ─────────────────────────────────────────────────────

test('the wait doubles from three seconds to a thirty-second cap', () => {
  //  A fixed retry delay turns one outage into a steady drum against a
  //  ship that is least able to answer.
  assert.deepEqual([0, 1, 2, 3, 4, 5, 6].map(backoffFor), [3000, 6000, 12000, 24000, 30000, 30000, 30000])
  assert.equal(backoffFor(0), BACKOFF_MIN)
  assert.equal(backoffFor(MAX_ATTEMPT), BACKOFF_MAX)
  //  a nonsense count is the minimum, not NaN: this feeds a setTimeout
  assert.equal(backoffFor(-3), BACKOFF_MIN)
})

test('every wait is spread over half to one and a half times itself', () => {
  //  A pier restart drops every client at the same instant. Without the
  //  jitter a well-shaped backoff still brings them all back on the same
  //  tick, and keeps doing it.
  assert.equal(jittered(3000, 0), 1500)
  assert.equal(jittered(3000, 0.5), 3000)
  assert.equal(jittered(3000, 0.999), 4497)
  for (let i = 0; i < 500; i += 1) {
    const d = nextDelay(2)
    assert.ok(d >= 12000 * 0.5 && d <= 12000 * 1.5, `${d} outside 0.5–1.5× of 12s`)
  }
  //  and the cap is a cap on the BASE, so a jittered one may exceed it —
  //  which is the point: 45s is a spread, 30s exactly would be a drum.
  const top = nextDelay(9, 0.999)
  assert.ok(top > BACKOFF_MAX && top <= BACKOFF_MAX * 1.5, `${top}`)
})

test('the count resets on a stream that lived, not on one that registered', () => {
  //  THE TRAP. A ship that accepts the connection and immediately drops
  //  it registers every time, so resetting on registration means it never
  //  backs off at all — which is the loop the whole change exists to
  //  avoid, wearing a backoff as a disguise.
  assert.equal(nextAttempt(0, 40), 1, 'accept-and-drop is a failure')
  assert.equal(nextAttempt(3, 0), 4)
  assert.equal(nextAttempt(3, LIVED_MS - 1), 4)
  //  an attempt that genuinely worked, however it ended
  assert.equal(nextAttempt(4, LIVED_MS), 0)
  assert.equal(nextAttempt(4, 60 * 60 * 1000), 0)
  //  and the count does not climb for ever
  assert.equal(nextAttempt(MAX_ATTEMPT, 0), MAX_ATTEMPT)
})

test('a run of failures is the sequence the briefing asks for', () => {
  //  3, 6, 12, 24, 30, 30 — each jittered — and not six evenly spaced
  //  threes. Read with a fixed `rand` so the shape is visible.
  let attempt = 0
  const gaps = []
  for (let i = 0; i < 6; i += 1) {
    gaps.push(nextDelay(attempt, 0.5))
    attempt = nextAttempt(attempt, 20)    // every attempt failed at once
  }
  assert.deepEqual(gaps, [3000, 6000, 12000, 24000, 30000, 30000])
  //  and one good stream in the middle puts it back to the start
  assert.equal(nextDelay(nextAttempt(5, LIVED_MS + 1), 0.5), 3000)
})

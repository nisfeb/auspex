//  THE CHANGE BEACON, reduced to the parts that decide something.
//
//  The extension used to sync on a sixty-second alarm. It does not any
//  more: it holds the ship's change beacon open and syncs when the ship
//  says something moved. Everything in this file is a pure function,
//  because everything in this file is a rule that a loop gets subtly
//  wrong — which frame is a change, and how long to wait after a failure.
//  The loop that uses them is in background.js, where a test cannot reach.
//
//  WHY, in one paragraph. A briefing written after ~ricsul-bilwyt spent
//  most of 2026-09-09 saturated: a ship runs its events ONE AT A TIME, so
//  a handful of clients on a timer can consume the whole thing while
//  loom, mass and host load all look fine. A sixty-second sync is
//  `GET /api/whoami` plus a paged inbox walk — about 1.2 seconds of ship
//  time, 1,440 times a day, and the inbox listing is O(total stored
//  messages), so it gets worse with every message the mailbox holds. The
//  rule the briefing gives is "judge cost, not rate": this file is what
//  replaces that cost with one held connection.

//  The stream. NOT under /apps/auspex and NOT an eyre channel: it is
//  grubbery's keep-SSE endpoint, so there are no acks to send and no clog
//  threshold to fall foul of. The same URL the web client reads
//  (`ui/src/api.ts`) and the desktop notifier reads
//  (`desktop/src/notify.rs`); all three must agree, because a filter that
//  drifted would leave one of them syncing on things the others do not
//  call changes.
const BEACON_PATH = '/grubbery/api/keep/apps/auspex.auspex_app/beacon/rev'

//  Backoff: 3 seconds doubling to 30, jittered 0.5–1.5×.
//
//  The doubling is for a ship that is up and REFUSING — a stale session
//  fails instantly, and a bare retry there is a hot loop against the pier.
//  The jitter is for the other shape: a pier restart drops every client it
//  has at the same instant, so an undithered delay however well shaped
//  brings them all back on the same tick, for ever, while the ship is
//  least able to answer.
const BACKOFF_MIN = 3000
const BACKOFF_MAX = 30000

//  How long an attempt must last before it counts as having WORKED.
//
//  Not "did it register". The trap is a ship that accepts the connection
//  and immediately drops it: reset the count on registration and that
//  never backs off at all, which is precisely the loop the briefing was
//  written about. Ten seconds is far longer than an accept-and-drop and
//  far shorter than the keep's own expiry, so an ordinary stream ending on
//  schedule still resets.
const LIVED_MS = 10000

//  The exponent is capped, not because 2**n overflows anything a person
//  will reach, but because `attempt` is a number that only ever goes up on
//  an outage and there is no reason to carry a big one.
const MAX_ATTEMPT = 10

//  Does this SSE frame mean "something a reader can see changed"?
//
//  The path is in the `event:` line; `data:` carries the revision number.
//  A real frame off ~wex:
//
//      id: 43
//      event: old /rev
//      data: 170141184508152841273086689431159830477
//
//  Two filters, both load-bearing:
//
//    - ` /rev` — the stream carries the whole `/beacon` DIRECTORY, so
//      frames for its other leaves arrive here too and are not changes to
//      the mail.
//    - not `old` — the first frame after registration is the CURRENT
//      value replayed, not a change. Acting on it would run a full sync on
//      every reconnect, and a reconnect is ORDINARY: a ship bounce, a
//      laptop waking. That is how a cheap reconnect becomes an expensive
//      one, which is the third rule in the briefing.
//
//  This is `is_change` in desktop/src/notify.rs, in JS.
function isChange(frame) {
  const line = String(frame).split(/\r?\n/).find((l) => l.startsWith('event:'))
  if (line === undefined) return false
  const ev = line.slice('event:'.length).trim()
  return ev.endsWith(' /rev') && !ev.startsWith('old')
}

//  Split a read buffer into whole frames and whatever is left over.
//
//  A blank line ends an SSE frame, and a `reader.read()` lands wherever
//  the network cut it — mid-frame, mid-line, mid-UTF-8. The LAST element
//  of the split is a partial frame, never a whole one, so it goes back in
//  the buffer. Getting this wrong drops changes at exactly the moment the
//  ship is busy enough to split a frame across two packets.
function framesIn(buf) {
  const parts = String(buf).split(/\r?\n\r?\n/)
  return { frames: parts.slice(0, -1), rest: parts[parts.length - 1] }
}

//  The undithered delay for the nth consecutive failure: 3, 6, 12, 24,
//  30, 30 … seconds.
function backoffFor(attempt) {
  return Math.min(BACKOFF_MAX, BACKOFF_MIN * 2 ** Math.max(0, attempt))
}

//  0.5–1.5× it. `rand` is a parameter so the jitter can be tested rather
//  than believed.
function jittered(ms, rand) {
  return Math.round(ms * (0.5 + rand))
}

function nextDelay(attempt, rand = Math.random()) {
  return jittered(backoffFor(attempt), rand)
}

//  What the count becomes after an attempt that lasted `livedMs`. An
//  attempt that genuinely worked resets it; anything shorter is a failure
//  and the wait doubles. See LIVED_MS.
function nextAttempt(attempt, livedMs) {
  return livedMs >= LIVED_MS ? 0 : Math.min(attempt + 1, MAX_ATTEMPT)
}

export {
  BEACON_PATH, BACKOFF_MIN, BACKOFF_MAX, LIVED_MS, MAX_ATTEMPT,
  isChange, framesIn, backoffFor, jittered, nextDelay, nextAttempt,
}

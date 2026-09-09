//  THE DIFF. What to fetch, what to import, where it goes, and what to say
//  about read state.
//
//  PURE, and that is deliberate: every rule here is one a sync loop gets
//  subtly wrong at three in the morning — the loop that marks a message
//  read on the ship because the ship said it was read locally, the import
//  that runs twice, the forged copy that shadows the real one. Each is a
//  function of data here, and each has a test.

//  verified > unverified > forged. Higher wins.
const VERDICT_RANK = { verified: 2, unverified: 1, forged: 0 }
const rank = (v) => (VERDICT_RANK[v] ?? 0)

//  ONE MESSAGE PER ID, and the honest copy wins.
//
//    Up to `max-copies` copies of one id that differ in SIGNATURE are kept
//    on the ship deliberately — one genuine, the rest forged — so a forged
//    copy cannot shadow a real one. A mail client has one message per
//    Message-ID and no way to show two, so the choice is made here: the
//    highest-ranked verdict is imported and the count of the others rides
//    in X-Auspex-Copies, so a thread that looks short says why.
//
//    Ties keep the FIRST, which is the ship's own canonical chain order.
function dedupeCopies(messages) {
  const byId = new Map()
  for (const m of messages) {
    const cur = byId.get(m.id)
    if (!cur) { byId.set(m.id, { msg: m, copies: 1 }); continue }
    cur.copies += 1
    if (rank(m.verdict) > rank(cur.msg.verdict)) cur.msg = m
  }
  return [...byId.values()]
}

//  The root-to-parent path of ids for one message, walked over the
//  thread's own `prev` links.
//
//    This is what makes Thunderbird draw the TREE. A thread here is not a
//    list: a message names its parent and nothing else, and two messages
//    naming the same parent are a branch. References is the only field a
//    mail client threads on, and it wants exactly this — every ancestor,
//    oldest first.
//
//    A cycle would be a malformed thread rather than an impossible one
//    (ids come off signed records, and a chain any ship may deliver can
//    contain anything), so the walk carries a seen-set and stops. A
//    missing parent stops it too: the path we can prove is shorter than
//    the path claimed, and a shorter References is a flatter tree, never
//    a wrong one.
function referencesFor(msg, byId) {
  const out = []
  const seen = new Set([msg.id])
  let cur = msg.prev
  while (cur && !seen.has(cur)) {
    seen.add(cur)
    out.push(cur)
    const parent = byId.get(cur)
    cur = parent ? parent.prev : null
  }
  return out.reverse()
}

//  WHICH FOLDER, decided once, at import.
//
//    A message lives in exactly one folder and never moves. The
//    alternative — a message in Inbox that becomes a message in Archived
//    when the thread is archived in the web client — means either moving
//    mail behind the user's back or holding two copies, and this mirror
//    is not the owner of that state: the web client is.
//
//    Archived beats authorship: a thread the owner archived is archived
//    whoever wrote it, which is the same order the nexus's own views use.
const folderFor = (msg, entry, ourShip) => {
  if (entry && entry.archived) return 'Archived'
  return msg.from === ourShip ? 'Sent' : 'Inbox'
}

//  THE STAR AND THE FLAME, which are two of the ship's labels.
//
//    Thunderbird has a per-message `flagged` (the star) and a per-message
//    `junk` (the flame). Auspex has per-THREAD labels. So the mapping is
//    two named labels and nothing else — no new state anywhere, and the
//    web client shows the same two as ordinary labels, which is what
//    makes them honest: the mirror invents nothing.
//
//    The flame carries the archive flag with it. Junk mail is not mail
//    you want left in the inbox, and the web client's own answer to junk
//    is to archive it; a flame that labelled and left the thread in the
//    listing would be a star with a worse icon.
const FLAGGED = 'flagged'
const JUNK = 'junk'

const flagsFor = (entry) => {
  const labels = (entry && entry.labels) || []
  return { flagged: labels.includes(FLAGGED), junk: labels.includes(JUNK) }
}

//  The labels of a thread as ONE comparable string. Sorted, because the
//  ship's order within the set is not a promise and a reordering is not a
//  change; joined with a byte no label can contain, so `['a','b']` and
//  `['a,b']` are not the same key.
const labelKey = (entry) => [...((entry && entry.labels) || [])].sort().join('\u0000')

//  Which threads changed since the last sync.
//
//    `last` and `count` together: `last` misses a copy arriving with an
//    older timestamp (a forgery is signed by whoever forged it and can
//    claim any time it likes), `count` misses nothing that is stored but
//    would not notice a thread going from archived to not. The meta
//    fields ride along for the same reason — the folder choice reads
//    `archived` and the message flags read `labels`, so a thread that
//    only changed one of those still has to be looked at once.
//
//    A thread with no snapshot is new and is always fetched — which is
//    also what makes a snapshot written by an older version safe: it has
//    no `labels` key, every thread mismatches once, and the next sync
//    re-reads the lot.
function threadsToFetch(entries, snapshot) {
  const out = []
  for (const e of entries) {
    const s = snapshot[e.id]
    if (!s || s.last !== e.last || s.count !== e.count
      || s.archived !== e.archived || s.labels !== labelKey(e)) out.push(e.id)
  }
  return out
}

const snapshotOf = (entries) => {
  const out = {}
  for (const e of entries) {
    out[e.id] = {
      last: e.last, count: e.count, archived: e.archived, labels: labelKey(e),
    }
  }
  return out
}

//  NEVER A BLIND WRITE.
//
//    `messages.update` fires `messages.onUpdated` whether or not it
//    changed anything, and onUpdated is the relay back to the ship. So a
//    sync that wrote the flags every message already carries would push
//    the whole mirror through the relay every sixty seconds, forever.
//    The patch is what DIFFERS, or nothing at all.
function flagUpdate(current, wanted) {
  const patch = {}
  if (!!(current && current.flagged) !== wanted.flagged) patch.flagged = wanted.flagged
  if (!!(current && current.junk) !== wanted.junk) patch.junk = wanted.junk
  return Object.keys(patch).length ? patch : null
}

//  WHAT TO SEND when a flag is changed in Thunderbird, in order.
//
//    The star is one call. The flame is two — the label and the archive
//    flag are two routes — and the label goes FIRST, so a thread that
//    reaches the archived view is already labelled when it gets there and
//    never appears there unexplained.
function flagOps(threadId, flag, on) {
  if (flag === 'flagged') return [{ call: 'label', threadId, label: FLAGGED, add: on }]
  if (flag === 'junk') {
    return [
      { call: 'label', threadId, label: JUNK, add: on },
      { call: 'archive', threadId, archived: on },
    ]
  }
  return []
}

//  READ STATE, IN THE DIRECTION THAT DOES NOT LOOP.
//
//    Two sides hold a read flag and either can change it, so the rule is
//    "apply only a difference, and never echo one back":
//
//      ship → local   only for a message whose LOCAL flag differs. A ship
//                     that says read about a message already read locally
//                     produces no update, so no messages.onUpdated fires,
//                     so nothing is posted back.
//      local → ship   only from a real onUpdated, debounced.
//
//    A read-mark does not move the change beacon on the ship (see
//    ui/src/api.ts on BEACON), so a ship-side mark never provokes a sync
//    of its own either. The loop this prevents is the one where opening a
//    thread marks it read, the mark bumps a sync, the sync applies the
//    flag, the flag fires onUpdated and the mark is posted again, forever.
function readStateOps(remote, localFlags) {
  const toRead = []
  const toUnread = []
  for (const m of remote) {
    if (!(m.id in localFlags)) continue
    if (localFlags[m.id] === m.read) continue
    ;(m.read ? toRead : toUnread).push(m.id)
  }
  return { read: toRead, unread: toUnread }
}

//  The whole import plan for one thread: the messages not yet imported,
//  each with its folder, its References path and its copy count.
//
//    `imported` is the set of auspex ids already in the mirror. A message
//    is imported ONCE — Thunderbird itself throws on a duplicate
//    Message-ID in a folder, and a placeholder for an attachment we could
//    not fetch is therefore permanent for that import.
function planThread(thread, entry, ourShip, imported) {
  const copies = dedupeCopies(thread.messages || [])
  const byId = new Map(copies.map((c) => [c.msg.id, c.msg]))
  const plan = []
  for (const { msg, copies: n } of copies) {
    if (imported.has(msg.id)) continue
    plan.push({
      msg,
      copies: n,
      folder: folderFor(msg, entry, ourShip),
      references: referencesFor(msg, byId),
      threadId: thread.id,
    })
  }
  //  oldest first, so a parent is in the folder before its child and
  //  Thunderbird never has to re-thread a message that arrived orphaned.
  plan.sort((a, b) => a.msg.sent - b.msg.sent)
  return plan
}

export {
  VERDICT_RANK, rank, dedupeCopies, referencesFor, folderFor,
  threadsToFetch, snapshotOf, readStateOps, planThread,
  FLAGGED, JUNK, flagsFor, labelKey, flagUpdate, flagOps,
}

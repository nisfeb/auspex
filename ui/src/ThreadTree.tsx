import { useEffect, useRef, useState } from 'react'
import type { Message, Verdict } from './api'
import VerdictBadge from './VerdictBadge'
import { when } from './ThreadList'

// THE SHAPE OF A CONVERSATION, DRAWN.
//
// A thread is not a list. `prev` names a parent, two replies to one
// message are siblings, and a reply or forward ships exactly the
// root-to-leaf path to the message it points at — so the branch a user
// is about to hand to a stranger is a fact about this picture, and a
// flat list cannot show it. The list view stays the default because it
// is the right shape for reading; this is the right shape for deciding
// what travels.
//
// Plain SVG, hand-rolled layout, no dependency. `foreignObject` carries
// each node's contents so `VerdictBadge` is the same component here as
// on a list row and on a message card: the mark for a failed signature
// is the one thing on this surface that must not have two definitions
// that can drift apart.

// One drawn node: every stored copy that shares an id, collapsed.
//
// COPIES ARE NOT MESSAGES. Up to `max-copies` grubs share one id and
// differ only in signature — one genuine, the rest forged — and drawing
// each as its own node would show a two-message conversation as five,
// with the forgeries indistinguishable from real replies. One node per
// id; the copies are what the panel below shows.
interface Node {
  id: string
  from: string
  sent: number
  // The verdict of the WHOLE node, which is the loudest of its copies:
  // one forged copy makes the node forged. The listing's rule for a row
  // that holds a forgery is the same — a reader must not have to open a
  // node to find out a signature failed under it.
  verdict: Verdict
  parent: string | null
  // `prev` names an id this ship does not hold. The message is real and
  // its parent is not here — usually a chain that arrived without its
  // head. Drawn as its own root with a dashed stub, never silently
  // reparented to the real root and never dropped: a branch that quietly
  // moves is worse than one that is visibly missing an ancestor.
  orphan: boolean
  depth: number
  row: number
}

const NODE_W = 178
const NODE_H = 40 // ≥40px on a finger, and the same on a mouse.
const COL = NODE_W + 46
const ROW = 52
const PAD = 12
const STUB = 22 // the dashed edge an orphan hangs from.

// Every copy of one id, in the order the nexus returned them (by `sent`).
export const copiesOf = (ms: Message[], id: string): Message[] =>
  ms.filter((m) => m.id === id)

// WHICH COPY SPEAKS FOR A NODE. The newest that is not forged, falling
// back to the newest of all only when there is nothing honest to choose
// — the same rule the listing uses for a row's sender and subject, and
// for the same reason: `sent` is a signed field the AUTHOR picks, so
// letting a forged copy speak lets whoever poked the chain choose what
// a node says it is.
export const speaker = (copies: Message[]): Message => {
  const honest = copies.filter((m) => m.verdict !== 'forged')
  const from = honest.length ? honest : copies
  return from[from.length - 1]
}

// True when every stored copy of this id failed its signature. Such a
// node is not a reply target: `prev` would point the new message's whole
// travelling path at a message nobody wrote.
export const allForged = (copies: Message[]): boolean =>
  copies.length > 0 && copies.every((m) => m.verdict === 'forged')

// THE LAYOUT, in five lines: collapse copies to one node per id; give
// each node the parent its `prev` names, or none when this ship does not
// hold that id (an orphan) or when following `prev` would close a loop;
// sort each node's children by `sent`; walk the forest post-order giving
// each leaf the next free row and centring each parent on the span of
// its children; x is generation, y is row.
export function layout(messages: Message[]): { nodes: Node[]; rows: number; cols: number } {
  const nodes: Node[] = []
  const byId = new Map<string, Node>()
  for (const m of messages) {
    if (byId.has(m.id)) continue
    const copies = copiesOf(messages, m.id)
    const s = speaker(copies)
    const n: Node = {
      id: m.id,
      from: s.from,
      sent: s.sent,
      verdict: copies.some((c) => c.verdict === 'forged') ? 'forged' : s.verdict,
      // The speaker's `prev`, not the first copy's: a forged copy can
      // name a different parent, and letting it would let a forgery
      // re-hang a genuine branch somewhere else in the picture.
      parent: s.prev,
      orphan: false,
      depth: 0,
      row: 0,
    }
    nodes.push(n)
    byId.set(m.id, n)
  }

  // A `prev` naming nothing we hold is an orphan root; a `prev` that
  // walks back into the node itself is a cycle. Neither can be trusted
  // to terminate a walk, and both arrive over the wire, so the parent
  // link is cut here rather than guarded at every later use. Cutting as
  // we go means the walk below can never revisit: each cycle loses
  // exactly one link, at the first node whose walk closes it.
  for (const n of nodes) {
    if (n.parent !== null && !byId.has(n.parent)) {
      n.orphan = true
      n.parent = null
      continue
    }
    const seen = new Set<string>([n.id])
    let p = n.parent
    while (p !== null) {
      if (seen.has(p)) { n.parent = null; break }
      seen.add(p)
      p = byId.get(p)?.parent ?? null
    }
  }

  const kids = new Map<string, Node[]>()
  const roots: Node[] = []
  for (const n of nodes) {
    if (n.parent === null) { roots.push(n); continue }
    const k = kids.get(n.parent)
    if (k) k.push(n)
    else kids.set(n.parent, [n])
  }
  // Children in `sent` order, ties broken by id so the picture does not
  // reshuffle between renders when two replies share a millisecond.
  for (const k of kids.values()) {
    k.sort((a, b) => (a.sent - b.sent) || (a.id < b.id ? -1 : 1))
  }
  roots.sort((a, b) => (a.sent - b.sent) || (a.id < b.id ? -1 : 1))

  // Post-order, iteratively: a leaf takes the next free row, a parent
  // sits at the midpoint of its first and last child. Recursion would
  // be shorter and would blow the stack at `max-chain` (1.000) on a
  // linear thread, which is a shape an attacker can send.
  let row = 0
  let cols = 1
  const stack: { n: Node; entered: boolean }[] = []
  for (let i = roots.length - 1; i >= 0; i--) stack.push({ n: roots[i], entered: false })
  while (stack.length) {
    const f = stack.pop()!
    const k = kids.get(f.n.id)
    if (!f.entered && k && k.length) {
      stack.push({ n: f.n, entered: true })
      for (let i = k.length - 1; i >= 0; i--) {
        k[i].depth = f.n.depth + 1
        stack.push({ n: k[i], entered: false })
      }
      continue
    }
    if (k && k.length) {
      f.n.row = (k[0].row + k[k.length - 1].row) / 2
    } else {
      f.n.row = row++
    }
    if (f.n.depth + 1 > cols) cols = f.n.depth + 1
  }

  return { nodes, rows: row, cols }
}

const x = (n: Node) => PAD + STUB + n.depth * COL
const y = (n: Node) => PAD + n.row * ROW

export default function ThreadTree({
  messages, selected, onSelect,
}: {
  messages: Message[]
  // The node whose path is lit and whose copies the panel below shows.
  selected: string
  onSelect: (id: string) => void
}) {
  const { nodes, rows, cols } = layout(messages)
  const byId = new Map(nodes.map((n) => [n.id, n]))

  // THE PATH THAT WOULD TRAVEL. Root to selected, which is exactly what
  // `+path-chain` ships when this node is replied to or forwarded — so
  // the lit edges and the "N signed messages travel" line below the tree
  // are two renderings of one fact, and cannot disagree.
  const lit = new Set<string>()
  {
    let cur = byId.get(selected)
    while (cur && !lit.has(cur.id)) {
      lit.add(cur.id)
      cur = cur.parent ? byId.get(cur.parent) : undefined
    }
  }

  const w = PAD * 2 + STUB + Math.max(1, cols) * COL - (COL - NODE_W)
  const h = PAD * 2 + Math.max(1, rows) * ROW - (ROW - NODE_H)

  // ZOOM. The layout is computed once in its own units; zooming is the
  // SVG's rendered size against a fixed viewBox, so the nodes, the text
  // inside the foreignObjects and the edges all scale together and the
  // hit targets stay where the picture says they are. Half to double:
  // below half a node's label is unreadable, above double a phone shows
  // one node. Ctrl+wheel (pinch, on a trackpad) over the box, or the
  // buttons; the listener is attached by hand because React registers
  // wheel as passive and a passive listener cannot stop the page zoom.
  const [zoom, setZoom] = useState(1)
  const box = useRef<HTMLDivElement>(null)
  const clamp = (z: number) => Math.min(2, Math.max(0.5, Math.round(z * 20) / 20))
  useEffect(() => {
    const el = box.current
    if (!el) return
    const onWheel = (e: WheelEvent) => {
      if (!e.ctrlKey && !e.metaKey) return
      e.preventDefault()
      setZoom((z) => clamp(z * (e.deltaY < 0 ? 1.1 : 1 / 1.1)))
    }
    el.addEventListener('wheel', onWheel, { passive: false })
    return () => el.removeEventListener('wheel', onWheel)
  }, [])

  return (
    // The box scrolls; the page does not. A thread eight generations
    // deep is wider than a phone and there is no honest way around that
    // — but a pane that scrolls sideways is a pane the user chose to
    // scroll, and a PAGE that does is a layout bug.
    <div
      ref={box}
      className="relative mb-3 max-w-full overflow-auto rounded-sm border border-line bg-sunken"
      role="group"
      aria-label="Conversation tree"
    >
      <div className="sticky top-1 left-1 z-10 inline-flex items-center gap-1 rounded-sm border border-line bg-surface px-1 text-xs text-ink-faint">
        <button type="button" className="btn px-1" aria-label="Zoom out" onClick={() => setZoom((z) => clamp(z / 1.25))}>−</button>
        <button type="button" className="px-1 tabular-nums" title="Reset zoom" onClick={() => setZoom(1)}>{Math.round(zoom * 100)}%</button>
        <button type="button" className="btn px-1" aria-label="Zoom in" onClick={() => setZoom((z) => clamp(z * 1.25))}>+</button>
      </div>
      <svg width={w * zoom} height={h * zoom} viewBox={`0 0 ${w} ${h}`} className="block">
        {nodes.map((n) => {
          const p = n.parent ? byId.get(n.parent) : undefined
          if (!p) {
            if (!n.orphan) return null
            // THE STUB. A dashed edge to nowhere, because "this message
            // names a parent we do not hold" and "this message is a
            // thread root" are different facts and the picture has to
            // keep them apart.
            return (
              <line
                key={`e-${n.id}`}
                x1={x(n) - STUB}
                y1={y(n) + NODE_H / 2}
                x2={x(n)}
                y2={y(n) + NODE_H / 2}
                strokeDasharray="3 3"
                className="stroke-line-strong"
                strokeWidth={1.5}
              >
                <title>parent not held by this ship</title>
              </line>
            )
          }
          // An elbow, not a curve: two straight runs and a corner read
          // as "descends from" at any zoom, and cost nothing to follow
          // when eight siblings share one parent.
          const on = lit.has(n.id) && lit.has(p.id)
          const mx = x(p) + NODE_W + (COL - NODE_W) / 2
          return (
            <path
              key={`e-${n.id}`}
              d={`M ${x(p) + NODE_W} ${y(p) + NODE_H / 2}
                  H ${mx} V ${y(n) + NODE_H / 2} H ${x(n)}`}
              fill="none"
              className={on ? 'stroke-accent' : 'stroke-line-strong'}
              strokeWidth={on ? 2 : 1}
            />
          )
        })}
        {nodes.map((n) => {
          const on = lit.has(n.id)
          const here = n.id === selected
          return (
            <foreignObject key={n.id} x={x(n)} y={y(n)} width={NODE_W} height={NODE_H}>
              <button
                type="button"
                onClick={() => onSelect(n.id)}
                aria-pressed={here}
                title={n.orphan
                  ? `${n.from} — the message this one replies to is not held by this ship.`
                  : `${n.from} — ${new Date(n.sent).toLocaleString()}`}
                className={`flex h-10 w-full items-center gap-1.5 rounded-sm border px-1.5 text-left
                  ${here
                    ? 'border-accent bg-accent-soft text-accent-soft-ink ring-1 ring-accent'
                    : on
                      ? 'border-accent bg-raised text-ink'
                      : 'border-line bg-raised text-ink-dim hover:bg-sunken'}`}
              >
                <VerdictBadge verdict={n.verdict} from={n.from} />
                <span className="min-w-0 flex-1 truncate text-[12px]">{n.from}</span>
                <span className="shrink-0 text-[11px] text-ink-faint">{when(n.sent)}</span>
              </button>
            </foreignObject>
          )
        })}
      </svg>
    </div>
  )
}

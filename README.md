# auspex

Mail on Urbit, without IMAP or SMTP. Every message is signed by the ship that
wrote it, and when you reply or forward, the whole line of the conversation
travels with your message — so a third party who never spoke to the original
author can still verify every word of it against that author's key. Named for
the one who reads messages from birds; Talon's sibling.

- `grubbery-overlay/` — the ship side, a **grubbery nexus** (not a gall agent).
  Its README covers the layout, the two marc rules and the deploy loop.
- `ui/` — the web client (React, served by the ship at `/apps/auspex`, PWA).
- `desktop/` — the Tauri app: the same client in a window, plus native
  notifications for new mail. See `docs/desktop-plan.md`.
- `docs/superpowers/specs/2026-09-07-auspex-design.md` — the design, which
  governs everything above.

## Threads branch

A message names its parent (`prev`), and nothing else about the ordering is
stored. A thread is therefore a **tree**, and the tree view (`List | Tree` in
the thread header, on any thread with more than one message) draws it as one.
A branch appears whenever two messages name the **same parent**. That happens
when:

1. **Two people reply to the same message.** The commonest case: you send to
   three ships and two of them answer. Each answer is a child of your message,
   side by side.
2. **One person replies twice to the same message** — two separate points in
   two separate replies, rather than one reply with both.
3. **Someone replies to an older message, not the newest.** In list view,
   Reply always answers the newest honest message in the thread. In tree view,
   Reply and Forward answer the **selected node** — so selecting anything but
   the tip and replying starts a branch on purpose. This is how you take one
   sub-topic aside without dragging the rest of the conversation along.
4. **A forward.** A forward is a reply addressed to someone new. The forwarded
   message is its parent, so when the new recipient answers, their answer sits
   beside the original conversation's continuation, on a branch of its own.
5. **A race.** Two ships reply to the tip before either has seen the other's
   reply. Neither did anything wrong; the tree simply records that both
   happened.

What does **not** make a branch: several stored copies of one message (the
same signed content arriving by different routes, or one genuine copy and one
forged one) collapse onto a single node. A node with any forged copy is marked
`FORGED`, loudly, and cannot be replied to.

Why the shape matters: **a reply or forward ships only the path from the root
to the message it answers** — never sibling branches. Select a node in the
tree and its path lights up; that lit path is exactly what a reply from there
would carry, and the line under the tree ("N signed messages travel") counts
it. Two people having a side exchange on one branch are not forwarded to
whoever receives a forward from another branch. That is the leak the tree
exists to prevent, and the reason the picture and the count can never
disagree: they are two renderings of one fact.

## Development

Two fake ships run the nexus for development; production is never touched
until the release plan (`docs/release-plan.md`) says so. Deploy an overlay
change with `scripts/sync-overlay.sh <grubbery-desk-root>`, then `|commit
%grubbery` and a suspend/revive in that ship's dojo. Tests run on the ship:
`-test /~<ship>/grubbery/<rev>/tests/lib/auspex-chain ~` and `…/auspex-web ~`,
with the revision pinned.

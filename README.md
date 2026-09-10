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

## Where a thread lives, and what the ids are

The tree in the UI is not a rendering of a flat list — it is the shape the
messages are stored in. A thread on the ship is:

```
/apps/auspex.auspex_app/mail/thread/<tid>/meta
/apps/auspex.auspex_app/mail/thread/<tid>/msg/<id>/<id>/.../<slot>
```

A message id is a **directory**; its replies are subdirectories keyed by their
own ids. So a message's path *is* its ancestry, two branches are two sibling
directories, and reading the chain a reply must carry is walking one path
rather than sorting a set and chasing pointers through it. `meta` holds the
local state — read marks, archive, labels — which is never signed and never
travels.

All three names are hashes. `sham` is Urbit's 128-bit noun hash, printed
`@uv`.

**`<id>`, a message id — `(sham unsigned)`.** It hashes the whole `$unsigned`
noun and nothing else: `from`, `life`, `to`, `subj`, `body`, `body-mime`,
`sent`, `prev`, `attachments`. That is the same preimage the signature covers,
which is the point — an id cannot name content the signature did not
authorise. `prev` is inside it, so a message's id depends on its parent's id:
the ancestry is hashed in, and nothing can be reparented without becoming a
different message.

**`<tid>`, a thread id — the root message's id.** Not a separate hash and not
assigned by anyone. Two ships hold the same conversation under the same path
without coordinating, because the root message is byte-identical for both and
so is its hash.

**`<slot>`, one signed copy — `(sham [id sig])`.** The id paired with the
signature bytes, not a positional index. This is what stops shadowing: two
copies of one message differing only in signature hash to two different slots,
so they sit as two grubs with two verdicts at the same node and neither can
overwrite the other. A forgery lands *beside* the real message; it cannot
displace it. Files and subdirectories are separate maps in a grubbery ball, so
a node carries both its copies and its replies with no collision possible.

Two hashes nearby that are **not** ids:

- **The signature preimage** is `digest`, `(shaf %auspex (sham unsigned))` —
  the message id with an `%auspex` salt on top. The salt is load-bearing: the
  same key signs ames packets and attestations, and salting keeps those
  preimage spaces disjoint so an auspex signature can never be replayed as one
  of them.
- **An attachment hash** is `(sham octs)` over the content bytes. Content
  addressing means the hash is the authority and the courier is irrelevant, so
  a blob may be fetched from any ship that has it.

### `subj` or `subject`

Both appear, and the split is a rule rather than an accident: **`subj` is the
frozen wire name, `subject` is everything else.**

`subj` is the field in `$unsigned` and nothing else. It cannot be renamed —
the face is part of the noun a signature covers, so changing it changes every
message id and makes every message in existence read as forged. `docs/protocol.md`
fixes it at field 4, and the names derived from it (`max-subj`,
`+fits-subjects`) belong to that spec too.

`subject` is the name everywhere a person or a client sees it: the local HTTP
API in **both** directions, every marc's JSON, the filter type (`$rule` is
user-authored, never signed, never on the wire) and drafts. The API is strict
about it — a request carrying `subj` is a 400, not an alias.

The wire-level definitions live in `docs/protocol.md`, with conformance
vectors under `protocol/vectors/`; `grubbery-overlay/lib/auspex-chain.hoon` is
the implementation.

## Development

Two fake ships run the nexus for development; production is never touched
until the release plan (`docs/release-plan.md`) says so. Deploy an overlay
change with `scripts/sync-overlay.sh <grubbery-desk-root>`, then `|commit
%grubbery` and a suspend/revive in that ship's dojo. Tests run on the ship:
`-test /~<ship>/grubbery/<rev>/tests/lib/auspex-chain ~` and `…/auspex-web ~`,
with the revision pinned.

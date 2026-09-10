# Auspex for Thunderbird

Thunderbird as a second client for [auspex](../README.md) mail — read *and*
send — over the ship's own authenticated HTTP API.

There is no IMAP here and no SMTP. Auspex mail is signed by the ship that
wrote it and travels as a chain; nothing about that fits an SMTP envelope.
So this extension is an **adapter**: it mirrors the ship's mail into local
folders as RFC 5322 messages, and it intercepts Send and does the sending
itself over `POST /apps/auspex/api/send`. Thunderbird never puts a byte on
the wire on auspex's behalf.

## Install

```
npm test          # the four pure libs
npm run build     # → dist/auspex-thunderbird-0.1.0.zip
```

Then in Thunderbird: **Add-ons and Themes → the gear → Install Add-on From
File…** and pick the zip. Thunderbird does not require add-on signing, so
there is nothing else to do.

## First run

1. The extension's **Options** page (Add-ons → Auspex → Options) asks for two
   things: your ship's URL and its `+code`.
2. Clicking **Connect** asks Thunderbird for permission to talk to *that one
   origin* — the manifest asks for no host permission at install, only the
   ability to request one later.
3. It then `POST`s the code to `/~/login`, which is Eyre's own login form.
   The answer sets the session cookie for that origin and Thunderbird's
   cookie jar keeps it. **The code is used once and is never stored** — not
   in `storage.local`, not in a log, not in the form field it was typed
   into.
4. `GET /api/whoami` proves the session and records the ship's name. An
   identity `<ship>@auspex.urbit` is created on Local Folders so a compose
   window can be opened at all, and three folders appear under **Local
   Folders → Auspex**: `Inbox`, `Sent`, `Archived`.
5. Mail is mirrored immediately, and after that whenever the ship says
   something changed — see **The beacon** below.

A `403` anywhere flips the status to **signed out**, raises one notification,
and stops syncing until you connect again. That is what an expired session
looks like, and no amount of retrying fixes it.

### If Connect says `NetworkError` and the name ends in `.ts.net`

**Thunderbird's DNS-over-HTTPS cannot resolve a tailnet (MagicDNS) name.**
DoH sends the lookup to a public resolver, and a public resolver has never
heard of your tailnet: the name is real, it resolves fine in a terminal on
the same machine, and Thunderbird still cannot reach it. What you see is a
bare `NetworkError` on Connect, which is the same word Thunderbird uses for
a dozen unrelated causes — this is the first one to rule out.

Either fix works:

- put the ship's **IP address** in the options page instead of its name
  (`http://100.x.y.z:8080`), or
- turn DoH off: **Settings → Privacy & Security → DNS over HTTPS → Off**,
  so lookups go through the system resolver that knows about the tailnet.

## Addresses

A ship is `~feb`; Thunderbird's whole world is `user@domain`. The mapping is
`~feb ⇄ ~feb@auspex.urbit`, both ways, everywhere.

`auspex.urbit` is a **reserved pseudo-domain**: `.urbit` is not a TLD, so an
address of this shape cannot resolve, which is the point — one that escaped
into an ordinary identity would bounce at the first hop rather than reach a
stranger. A send to anything that is *not* of this shape is refused in the
compose window, by name.

Thunderbird's own address book works normally: save `~feb@auspex.urbit` as a
card, put cards in a Thunderbird mailing list, and the composer expands it.

## The beacon

**This extension does not poll.** It holds one connection open —
`GET /grubbery/api/keep/apps/auspex.auspex_app/beacon/rev` with
`Accept: text/event-stream`, the ship's change beacon — and syncs when the
ship says something a reader can see has moved. That is the same stream
the web client reads (`ui/src/api.ts`) and the desktop app reads
(`desktop/src/notify.rs`), and all three agree about what a change is:
the stream carries the whole `/beacon` directory, so a frame counts only
if its `event:` line ends in ` /rev`, and a frame whose event starts with
`old` is the **current value replayed at registration** and not news.

**Why, since a 60-second alarm is simpler.** A ship runs its events *one
at a time*. An idle sync is `GET /api/whoami` plus a paged
`GET /api/inbox` walk — measured against `~wex`: 0.52 s and 0.72 s, so
about **1.2 seconds of ship time**, and the nexus's listing is O(total
stored messages), so it gets worse with every message the mailbox holds.
At one minute that was 1,440 idle syncs a day for ever, whatever you were
doing. A briefing written after `~ricsul-bilwyt` spent most of a day
saturated by exactly this shape of client puts it as: *judge cost, not
rate.* Measured with the beacon, in a three-minute idle window with the
extension connected: **zero requests, one held connection.**

**A reconnect is cheap, so a reconnect is allowed to be ordinary.** A ship
bounce, a laptop waking, a network coming back — the stream re-registers,
sees `old … /rev`, and mirrors **nothing**. One request, no sync. Measured:
one request, zero API calls.

**A dead ship is backed off, not drummed on.** 3 seconds doubling to 30,
every wait spread over 0.5–1.5× itself — because a pier restart drops every
client at the same instant, and an undithered delay however well shaped
brings them all back on the same tick. The count resets on a stream that
*lived*, not on one that merely registered: a ship that accepts the
connection and immediately drops it would otherwise never back off at all.
Measured against a dead port: seven attempts in 130 seconds, gaps of 4.5,
9.0, 8.1, 25.4, 42.9, 23.5 s. A fixed 3-second retry would have been
forty-three.

**There is no staleness watchdog, deliberately.** A healthy connection to a
quiet ship sends nothing for minutes; treating that as death is precisely
the bug that saturated `~ricsul-bilwyt`, and a client that tears down
healthy streams re-runs its bootstrap on every one. Nothing here reconnects
because the stream has been quiet.

**A 15-minute alarm is the one thing that acts on silence**, and it *syncs*
rather than reconnecting. It exists for the case the stream cannot see: a
connection that dies **silently**, with no FIN and no error, so the reader
blocks for ever and nothing ever throws. A NAT timeout or a laptop sleep
does it. It is an `alarms` entry so it survives a suspended background page,
and it skips when the stream is running and has delivered a change since it
last fired.

A `403` stops the stream along with everything else — that is the session,
not the request, and only connecting again on the options page starts it.

## What is mirrored, and what is not

**Mirrored.** Every thread the ship lists under `view=all`, as one RFC 5322
message per auspex message:

| | |
|---|---|
| `Message-ID` | `<msgid@auspex.urbit>` — the auspex id, both ways |
| `In-Reply-To` / `References` | the root-to-parent path, walked over `prev` |
| `Subject` | the signed subject, prefixed `[FORGED] ` when the verdict is forged |
| `X-Auspex-Verdict` | `verified` \| `unverified` \| `forged`, **per message** |
| `X-Auspex-Thread` | the thread id |
| `X-Auspex-Copies` | when several stored copies share one id |
| `X-Auspex-Body-Mime` | the signed `body-mime`, reported and never obeyed |
| body | `text/plain; charset=utf-8`, base64, the signed bytes verbatim |
| attachments | `application/octet-stream`, sanitised filename, base64 |

Threads branch — a message names its parent and two messages naming the same
parent are a branch — and `References` is exactly what makes Thunderbird's
threaded view draw that tree rather than a flat list. Switch the message list
to **View → Sort by → Threaded** to see it.

**The star and the flame.** Thunderbird's two per-message buttons are two of
the ship's labels, and nothing else:

| Thunderbird | auspex |
|---|---|
| ★ starred | the `flagged` label on the thread |
| 🔥 junk | the `junk` label on the thread, **and** archived |

Both ways. Star a mirrored message and the thread gains `flagged` on the
ship; add `flagged` in the web client and every mirrored message of that
thread is starred at the next sync. Junk does the same with two calls — the
label, then `POST /api/archive` — because junk mail is not mail you want
left in the listing, and a flame that only labelled would be a star with a
worse icon. Un-junking clears both.

A label is a **thread's** and a Thunderbird flag is a **message's**, so the
two directions are not symmetrical, deliberately: ship → Thunderbird applies
the thread's flags to every message in it, and Thunderbird → ship lets any
one message's click speak for its thread. Star one message of a thread and
the next sync stars its siblings — that is the ship's answer coming back,
not a bug.

Which thread a starred message belongs to is read from its own
`X-Auspex-Thread` header, not from anything the mirror wrote down, so a
message mirrored by a version that had never heard of labels can be starred
the moment you upgrade.

**Thunderbird's junk filter training is not used.** The flame writes a label
to the ship and nothing else; it does not train the local Bayesian filter,
and no message is ever moved to a Junk folder. The mirror's folders are
chosen once at import (below) and the flame does not change that — a junked
thread's *future* messages import to `Auspex/Archived`, the ones already
mirrored stay where they are.

**Not mirrored.** Lists, filters, labels other than those two, drafts, the
tree view's select-a-node-and-reply, the attachment fetch control,
delete-thread, search. The web client owns all of them and the popup's
**Open web client** button is the honest answer to each. This is a ceiling,
not a bug: a mirror that invented local state for a label the ship has never
heard of would be a second source of truth for something that is already
stored in exactly one place. `flagged` and `junk` escape that rule precisely
because they are *not* invented here — they are ordinary labels the web
client shows and edits like any other.

**Folders.** A message goes to exactly one folder, chosen once at import and
never moved: archived thread → `Archived`, otherwise written by you → `Sent`,
otherwise → `Inbox`. Archiving a thread in the web client later does *not*
move the messages already mirrored — the alternative is either moving mail
behind your back or holding two copies of it.

**Read state, the star and the flame** all go both ways, and all three by the
same rule: **only where the two sides differ.** Marking a message read in
Thunderbird posts `/api/read` (debounced, one request for the batch) and
starring one posts `/api/label` (debounced, per thread); in the other
direction a flag is written locally *only* when it actually differs from
what is there. That is what stops the two sides echoing a mark back and
forth forever — `messages.update` fires `messages.onUpdated` whether or not
it changed anything, so a blind write would put the whole mirror through the
relay on every change the ship reports.

## Sending

Send is intercepted (`compose.onBeforeSend`) and always cancelled, because a
successful auspex send is one this extension already made over HTTP and
Thunderbird must not also try to deliver it. On success the compose window
closes and a sync runs so the message appears in `Auspex/Sent`. **On failure
the window stays open with everything in it** — nothing is lost and nothing
is claimed sent.

Refused, with the reason in a notification:

- any recipient that is not `~ship@auspex.urbit`;
- **anything in Cc or Bcc.** A chain proves authorship, not delivery, and
  the wire has no field for either: a Cc would silently become a second To
  and a Bcc would silently become a visible one. Put everyone in To, or send
  twice;
- more than 16 attachments, or one over 262144 bytes (the file is named);
- being signed out.

`prev` — which message this one answers, and so where it hangs in the tree —
is taken from the message the composer was opened from (reply or forward). A
fresh compose has `prev: null` and starts a thread.

**The HTML ceiling.** Auspex carries a signed plain-text body. If you compose
in HTML, the body is reduced to text by a tag strip and an entity decode
before it is signed. That is not a renderer: a table comes out as its cells
run together. The identity this extension creates composes in plain text, and
that is the shape auspex actually has.

## Verdicts

The verdict is **per message**, never per thread: a thread holding one
unverified message is not an unverified thread. It reaches you three ways —
the `[FORGED] ` subject prefix (which is what the list pane shows, where
there is no room for a badge), the `X-Auspex-Verdict` header, and a toolbar
button on the open message reading `✓`, `○` or `FORGED`.

## Ceilings, in one list

- Read state, the star and the flame are the only things that flow
  Thunderbird → ship besides a send.
- A message is imported once. If an attachment's bytes had not been fetched
  by the ship at that moment, its place holds a note saying so, and that note
  is permanent for that import — open the thread in the web client to pull
  the file.
- Copies of one id (one genuine, the rest forged) collapse to the
  highest-ranked verdict, with the count in `X-Auspex-Copies`. Mail clients
  have one message per `Message-ID` and no way to show two.
- Live updates arrive on the ship's change beacon and nothing else. A sync
  runs when the ship says something moved; a 15-minute alarm is the only
  fallback, and it is there for a stream that died silently rather than for
  the ordinary quiet one.
- Manifest **v2**, deliberately: `optional_host_permissions`,
  `host_permissions` and `action` are v3-only keys, MV2 host patterns in
  `optional_permissions` do the same job, and a persistent background page is
  a better fit for a held stream plus a debounced relay than an event
  page that may be unloaded between them. Everything used here is supported
  on Thunderbird 128 through 147.

## Testing

`npm test` covers the four pure libs (`lib/address.js`, `lib/beacon.js`,
`lib/rfc822.js`, `lib/sync.js`) — every rule that a sync loop gets subtly
wrong is a function in one of them, the beacon's frame classifier and its
backoff included.

For an end-to-end run against a live ship there is a selftest build:

```
npm run build -- --selftest /path/to/config.json
```

whose config names the ship origin, its `+code`, a sink URL to POST results
to, the messages to send, and the four thread ids the star/flame steps act
on (`starThread`, `junkThread`, `inboundThread`, `untouchedThread` — the
third has its label added from outside with `curl` while the test polls for
it). A config with `"mode": "beacon"` runs a different script entirely: it
counts what the extension *costs* — requests made over a three-minute idle
window, seconds from a beacon change to mail in the folder, requests a
reconnect makes, and the gaps between attempts against a `deadOrigin` that
nothing listens on. It packages one extra file, `selftest.json`,
which the background fetches at startup; an ordinary build has no such file
and none of that code is even imported. **Never install a selftest build you
did not build yourself: it carries an access code.**

### A caveat about sideloaded builds

A selftest build is installed by dropping the zip at
`<profile>/extensions/auspex@nisfeb.org.xpi`, which grants its host
permissions at install rather than through `permissions.request`. **On
Thunderbird 147 that grant is recorded but not effective for `fetch`.**
`browser.permissions.getAll()` lists the origin, and a fetch to it still
comes back with `response.type === "cors"` and throws on any response
without an `access-control-allow-origin` header — the ship sends none,
because it is answering a same-origin client. A control endpoint on the
*same permitted origin* that does send the header succeeds, which is what
isolates the cause to CORS rather than to the network or to the ship.

So a sideloaded selftest build reaches the ship (the login answers 200 and
sets `urbauth-~ship`) and `fetch` rejects anyway. The ordinary install path
does not go through that door: **Install Add-on From File** plus the
options page's `permissions.request({origins})` under a real click is a
different grant, and is the path to use. If you see "unreachable" against a
ship you can `curl`, this is the first thing to check.

## Manual test, if you would rather click

1. Connect on the options page; **Local Folders → Auspex → Inbox** fills.
2. Sort threaded: a branching thread draws as a tree.
3. Open a message: the toolbar button shows its verdict.
4. Reply, send: the compose window closes, and the message appears in
   `Auspex/Sent` within a few seconds — the send bumps the beacon, and the
   beacon is what mirrors it — and in the web client's thread, in the right
   place.
5. Put an ordinary address in To and send: refused, with the address named,
   and the window still open.

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
npm test          # the three pure libs
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
5. Mail is mirrored immediately, and every 60 seconds after that.

A `403` anywhere flips the status to **signed out**, raises one notification,
and stops syncing until you connect again. That is what an expired session
looks like, and no amount of retrying fixes it.

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

**Not mirrored.** Lists, filters, labels, drafts, the tree view's
select-a-node-and-reply, the attachment fetch control, delete-thread, search.
The web client owns all of them and the popup's **Open web client** button is
the honest answer to each. This is a ceiling, not a bug: a mirror that
invented local state for a label the ship has never heard of would be a
second source of truth for something that is already stored in exactly one
place.

**Folders.** A message goes to exactly one folder, chosen once at import and
never moved: archived thread → `Archived`, otherwise written by you → `Sent`,
otherwise → `Inbox`. Archiving a thread in the web client later does *not*
move the messages already mirrored — the alternative is either moving mail
behind your back or holding two copies of it.

**Read state** goes both ways, and only where the two sides differ. Marking
a message read in Thunderbird posts `/api/read` (debounced, one request for
the batch); a message the ship says is read gets its local flag set, but only
if the flag actually differs — which is what stops the two sides echoing a
mark back and forth forever.

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

- Read state is the only thing that flows Thunderbird → ship besides a send.
- A message is imported once. If an attachment's bytes had not been fetched
  by the ship at that moment, its place holds a note saying so, and that note
  is permanent for that import — open the thread in the web client to pull
  the file.
- Copies of one id (one genuine, the rest forged) collapse to the
  highest-ranked verdict, with the count in `X-Auspex-Copies`. Mail clients
  have one message per `Message-ID` and no way to show two.
- No live updates. The ship's change beacon is an SSE stream the web client
  holds open; this syncs on a 60-second alarm instead.
- Manifest **v2**, deliberately: `optional_host_permissions`,
  `host_permissions` and `action` are v3-only keys, MV2 host patterns in
  `optional_permissions` do the same job, and a persistent background page is
  a better fit for a 60-second alarm plus a debounced relay than an event
  page that may be unloaded between them. Everything used here is supported
  on Thunderbird 128 through 147.

## Testing

`npm test` covers the three pure libs (`lib/address.js`, `lib/rfc822.js`,
`lib/sync.js`) — every rule that a sync loop gets subtly wrong is a function
in one of them.

For an end-to-end run against a live ship there is a selftest build:

```
npm run build -- --selftest /path/to/config.json
```

whose config names the ship origin, its `+code`, a sink URL to POST results
to, and the messages to send. It packages one extra file, `selftest.json`,
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
   `Auspex/Sent` within a minute — and in the web client's thread, in the
   right place.
5. Put an ordinary address in To and send: refused, with the address named,
   and the window still open.

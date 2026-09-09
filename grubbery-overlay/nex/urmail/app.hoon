::  nex/urmail/app: the grubbery-native %urmail nexus.
::
::  urmail is a nexus, not a gall agent. The tree it owns:
::    /main.sig                    the WRITER. Takes %urmail-action (local
::                                 only) and %urmail-chain (any ship) pokes
::                                 and serialises every mutation. Nothing
::                                 else in this nexus writes.
::    /mail/thread/<tid>/msg/<id>/<id>/.../<slot>
::                                 THE THREAD, AS THE TREE IT ALWAYS WAS.
::                                 `prev` makes a thread BRANCH - two
::                                 replies to one message are siblings,
::                                 and mail threads branch constantly -
::                                 so each message id is a DIRECTORY and
::                                 its replies are subdirectories keyed
::                                 by their own ids. A message's path is
::                                 its ancestry, two branches are two
::                                 sibling directories, and reading a
::                                 chain is walking one path instead of
::                                 sorting a set and chasing pointers
::                                 through it.
::                                 <slot> is one SIGNED COPY, verdict and
::                                 all, filed as a FILE inside its own
::                                 message's directory. It is still
::                                 (sham [id sig]), so the [id sig]
::                                 anti-shadowing key IS the storage key:
::                                 two copies of one message differing in
::                                 signature are two grubs with two
::                                 verdicts at ONE node, and neither can
::                                 overwrite the other. Files and
::                                 subdirectories are separate maps in a
::                                 ball, so a node carries both its
::                                 copies and its replies with no
::                                 collision possible - lattice's
::                                 fixed-leaf trick, with a leaf per copy
::                                 rather than one.
::    /mail/thread/<tid>/meta      local state: read marks, archive, labels.
::                                 Never signed, never travels.
::    /mail/blob/<hash>            ATTACHMENT BYTES, content-addressed.
::                                 The message carries name/size/mime/hash
::                                 inside `unsigned`; the bytes live here
::                                 and are published into gall's remote-scry
::                                 farm at /urmail/blob/<hash>, where any
::                                 ship holding the hash may %keen them.
::                                 The hash is the authority and the
::                                 courier is irrelevant, so a blob whose
::                                 bytes do not hash to the name they came
::                                 under is discarded without comment.
::    /mail/blobvis                per-blob permission: %public (the
::                                 default, in the farm) or %restricted
::                                 (withdrawn from it, weir-gated).
::    /fetch/<id>                  ONE EPHEMERAL FIBER PER BLOB FETCH.
::                                 A keen is a network round trip and
::                                 the writer serialises MUTATIONS; a
::                                 fetch that ran on the writer queued
::                                 every send, every inbound chain and
::                                 every read-mark behind it for as long
::                                 as the probe took. The fiber keens
::                                 and pokes the answer back; only the
::                                 writer touches the tree.
::    /mail/idx                    the derived inbox order, newest first.
::    /app/index.html              the web client, laid down as four
::    /app/app.js                  grubs: a shell with its css inlined,
::    /app/manifest.json           one script, a web manifest and a
::    /app/sw.js                   service worker. Assets in cords wedge
::                                 every request fiber, so the client is
::                                 one document and one script, the shape
::                                 lattice ships for the same reason. The
::                                 other two are fetched by the BROWSER
::                                 rather than by the app - once each -
::                                 and are what make it installable and
::                                 openable offline.
::    /ui/main.sig                 binds /apps/urmail and dispatches each
::                                 request into its own fiber.
::    /ui/requests/<id>            ONE EPHEMERAL FIBER PER HTTP REQUEST.
::                                 Reads peek the tree here; writes poke
::                                 the writer and answer ok. The writer
::                                 serialises mutations and a send fans
::                                 out to every recipient with a deadline
::                                 each, so a render or a round trip on it
::                                 would queue every other mutation behind
::                                 it.
::    /beacon/rev                  the change beacon. Open readers keep-SSE
::                                 this one small grub and refetch when it
::                                 moves. Bumped on every mutation EXCEPT a
::                                 read-mark, on a refused poke and on a
::                                 redelivery that wrote nothing; and
::                                 bumped from inside +do-send rather
::                                 than after it, so a local reader
::                                 never waits on a remote ship. +apply
::                                 answers which is which.
::    /tr/last                     the last writer outcome, as json. Fiber
::                                 prints go to the raw console and are
::                                 invisible to every tool that can reach
::                                 this ship; a grub is not. This is the
::                                 only way to see WHY a poke was refused.
::
::  Every guarantee the gall agent established holds here unchanged:
::  verification happens before anything is stored, the three verdicts, a
::  missing key is %unverified and never %forged, %forged messages are
::  stored as evidence, +prune sheds and never sheds a %verified copy,
::  thread identity comes from content, and the write path accepts a chain
::  from ANY ship because the signatures are the authority and the courier
::  is irrelevant.
::
::  THE WRITER MUST NOT CRASH. +rise-wait restarts a failed process by
::  CONSUMING the next poke without processing it, so a crash on a bad
::  input eats the next legitimate message. Every rejection below is
::  therefore a branch that returns cleanly, never a ?> or a !!. The one
::  arm that can crash on hostile input, +thread-key, is called under mule.
::
/<  uc  /lib/urmail-chain.hoon
/<  uw  /lib/urmail-web.hoon
::  the built client. Imports resolve relative to THIS file's directory
::  (/nex/urmail), not /nex. Rebuilt by `npm run build` in ui/, which
::  writes exactly these two files and fails if it would emit a third.
/<  uih  ui-app/index.html
/<  uij  ui-app/app.js
::  the PWA's other two files, built by the same `npm run build` and
::  laid down as grubs exactly like the two above. Same %mime marc, so
::  no new marc.
::
::  `manifest.json` and not the conventional `manifest.webmanifest`:
::  grubbery turns every non-hoon file in a gub tree into a %mime grub
::  through the clay tube for that file's EXTENSION, and this desk has
::  no `webmanifest` mark, so the .webmanifest name would be a sync-gub
::  that crashes rather than a route that 404s. The extension picks the
::  mark; the route below sets application/manifest+json, which is the
::  part a browser reads.
/<  uim  ui-app/manifest.json
/<  uisw  ui-app/sw.js
::  the launcher tile's icon, served at /apps/urmail/icon.svg and
::  pulled by the tiles nexus through /grubbery/tiles/icon/urmail.
/<  uicon  icon.svg
=<  ^-  nexus:nexus
    |%
    ++  on-load
      |=  =ball:tarball
      ^-  bole:tarball
      ::  Every persistent path needs a covering row: spin rebuilds the
      ::  bole from scratch and DROPS anything uncovered, and an uncovered
      ::  path here is lost mail.
      %+  spin:loader  ball
      :~  (manifest:loader 0)
          ::  tile.json: THE LAUNCHER LISTS ONLY APPS THAT CARRY ONE.
          ::  Without it urmail is installed, running and serving, and
          ::  invisible from the grubbery home screen - which reads as
          ::  "not installed" to everyone but the person who typed the
          ::  route by hand. %over, not %fall, so a redeploy replaces
          ::  the tile rather than leaving every ship on whatever it
          ::  first loaded, exactly as /app does below.
          ::
          ::  `image` names the app SLUG - the name before the first dot
          ::  in /apps/urmail.urmail_app - not the folder, and the tiles
          ::  nexus resolves it against the icon.svg grub laid beside
          ::  this row.
          :^  %over  %&  [/ %'tile.json']
          :-  [/ %json]
          %-  pairs:enjs:format
          :~  title+s+'Mail'
              info+s+'Signed mail, verified end to end'
              color+s+'#2563eb'
              image+s+'/grubbery/tiles/icon/urmail'
              href+s+'/apps/urmail'
          ==
          [%over %& [/ %'icon.svg'] [[/ %mime] uicon]]
          ::  the writer. %fall, so an existing live process is kept.
          [%fall %& [/ %'main.sig'] [[/ %sig] ~]]
          ::  /mail: %fall %| copies the WHOLE existing subtree, which is
          ::  what makes every dynamically created thread, message and meta
          ::  grub survive a reload. Without this row a nexus reload
          ::  deletes the mailbox.
          [%fall %| /mail empty-dir:loader]
          ::  /mail/thread: the same guarantee stated at the level the
          ::  writer actually makes directories under, and the row that
          ::  creates it on a first load. +ensure-thread only makes the
          ::  per-thread dirs; the parent has to already be there.
          [%fall %| /mail/thread empty-dir:loader]
          ::  /mail/idx: a FILE row, not a directory one, so the inbox
          ::  order survives a reload and gets a real default (an empty
          ::  list, versioned) on a first load. A grub laid under a mark
          ::  with no source file gets a BOOM sang, so this names
          ::  [/urmail %idx], which mar/urmail/idx.hoon is.
          [%fall %& [/mail %idx] [[/urmail %idx] *mail-idx:uc]]
          ::  /mail/blob: the blob store. Covered for the same reason
          ::  /mail/thread is - the %fall %| on /mail already copies the
          ::  subtree, and this row is what CREATES the directory on a
          ::  first load, since +store-blob only writes leaves into it.
          [%fall %| /mail/blob empty-dir:loader]
          ::  /mail/blobvis: one small grub for every blob's visibility,
          ::  deliberately not a field beside the bytes: changing who may
          ::  read a quarter-megabyte file must not rewrite the file.
          [%fall %& [/mail %blobvis] [[/urmail %blobvis] *blob-index:uc]]
          ::  /mail/draft and /mail/rule: NEW PERSISTENT PATHS, and an
          ::  uncovered persistent path is lost data - spin rebuilds the
          ::  bole from scratch and drops whatever no row names. The
          ::  %fall %| on /mail above already copies the subtree; these
          ::  two rows are what CREATE the directories on a first load,
          ::  since the writer only ever writes leaves into them.
          ::
          ::  A lost draft is a message the user wrote and never sent,
          ::  and a lost rule is a filter that silently stops filtering.
          [%fall %| /mail/draft empty-dir:loader]
          [%fall %| /mail/rule empty-dir:loader]
          ::  /mail/list: the mailing lists, one grub per list, KEYED BY
          ::  NAME - the name is the path segment and is not a field of
          ::  the grub, so nothing that reads a list can carry its name
          ::  into a message. Covered for exactly the reason the two
          ::  above are: an uncovered persistent path is dropped by
          ::  spin, and a lost list is an audience the user assembled by
          ::  hand and would have to assemble again.
          [%fall %| /mail/list empty-dir:loader]
          ::  /fetch: one grub per in-flight blob fetch, each grub the
          ::  state of its own fiber. Covered like every other
          ::  persistent path - spin drops what it does not cover - and
          ::  %fall so a request that outlives a reload respawns and
          ::  retries rather than vanishing half-done.
          [%fall %| /fetch empty-dir:loader]
          ::  /tr: the writer's trace. Covered so the last outcome survives
          ::  a reload, which is the case where you most want to read it.
          [%fall %| /tr empty-dir:loader]
          [%fall %& [/tr %last] [[/ %json] ~]]
          ::  /app: the client, %over so a redeploy actually replaces it.
          ::  A %fall would leave every ship running the build it first
          ::  loaded, with no error and no way to tell from outside.
          [%over %& [/app %'index.html'] [[/ %mime] uih]]
          [%over %& [/app %'app.js'] [[/ %mime] uij]]
          ::  the manifest and the service worker, %over for the same
          ::  reason: a stale service worker is worse than a stale
          ::  script, because it is the thing that decides which script
          ::  the browser gets.
          [%over %& [/app %'manifest.json'] [[/ %mime] uim]]
          [%over %& [/app %'sw.js'] [[/ %mime] uisw]]
          ::  /ui: the HTTP front end. main.sig binds /apps/urmail and
          ::  spawns one fiber per request under /ui/requests.
          [%fall %& [/ui %'main.sig'] [[/ %sig] ~]]
          [%fall %| /ui/requests empty-dir:loader]
          ::  /beacon/rev: the change beacon. NESTED, not at the nexus
          ::  root - grubbery's keep-SSE does not stream a root grub, and
          ::  a beacon that never streams is a UI that looks live and is
          ::  not. %fall so the counter survives a reload.
          [%fall %& [/beacon %rev] [[/ %json] (numb:enjs:format 0)]]
      ==
    ::
    ++  on-file
      |=  [=rail:tarball =blot:tarball]
      ^-  spool:fiber:nexus
      |=  =prod:fiber:nexus
      =/  m  (fiber:fiber:nexus ,~)
      ^-  process:fiber:nexus
      ?+    rail  stay:m
          ::  /main.sig: the single writer. rise, grant, then loop on
          ::  take-poke forever. Every road it builds below is ABSOLUTE,
          ::  derived from +get-here-abs at start: a depth-relative road
          ::  called from the wrong depth climbs past the nexus root and
          ::  crashes the fiber, and a crashed sig fiber respawns, so one
          ::  bad road is an infinite crash loop at 100% CPU.
          [~ %'main.sig']
        ;<  ~  bind:m  (rise-wait:io prod "%urmail writer failed")
        ;<  here=rail:tarball  bind:m  get-here-abs:io
        =/  root=path  path.here
        ;<  ~  bind:m  (grant-public root)
        ;<  ~  bind:m  (republish-all root)
        ;<  ~  bind:m  (migrate-flat root)
        |-
        ;<  [=from:fiber:nexus =sage:tarball]  bind:m  take-poke-from:io
        ::  +apply answers whether the tree actually changed, and that
        ::  answer - not the shape of the poke - is what moves the
        ::  beacon. Anyone may poke this writer, so a bump on a refusal
        ::  or on a redelivery that wrote nothing would be free remote
        ::  amplification: one bump costs every open client a full
        ::  inbox listing plus a thread refetch. See +apply.
        ;<  changed=?  bind:m  (apply root from sage)
        ;<  ~  bind:m
          ?.  changed  (pure:m ~)
          (bump-beacon root)
        $
      ::  /fetch/*: one EPHEMERAL fiber per blob fetch. It keens, pokes
      ::  the answer at the writer, and ends; the writer culls the
      ::  request grub on receipt, whether the fetch hit or missed.
      ::
      ::  Ephemeral is not an incidental choice. A timed-out keen leaves
      ::  a late %keen-response poke behind and a stray %veto arrives
      ::  too, and a LONG-LIVED fiber that %skips those piles them in
      ::  its skip queue to be re-offered on every later take. Running
      ::  the probe here means that debris lands on a process that is
      ::  about to be culled, instead of on the ship's single
      ::  serialisation point for mail.
          [[%fetch ~] @]
        ;<  ~  bind:m  (rise-wait:io prod "%urmail fetch: failed")
        (run-fetch name.rail)
      ::  /ui/main.sig: bind the HTTP endpoint and dispatch each request
      ::  into its own fiber under /ui/requests. This fiber never touches
      ::  the mail tree; it only routes.
          [[%ui ~] %'main.sig']
        ;<  ~  bind:m  (rise-wait:io prod "%urmail /ui/main: failed")
        ;<  ~  bind:m  (bind-http:io [~ /apps/urmail])
        (http-dispatch:io %urmail)
      ::  /ui/requests/*: one ephemeral fiber per in-flight HTTP request.
          [[%ui %requests ~] @]
        ;<  ~  bind:m  (rise-wait:io prod "%urmail /ui/requests: failed")
        (handle-request name.rail)
      ==
    --
|%
::  ── paths ───────────────────────────────────────────────────────────
::
++  mail-dir    |=(root=path ^-(path (weld root /mail)))
++  thread-dir  |=(root=path ^-(path (weld root /mail/thread)))
++  tdir        |=([root=path t=thread-id:uc] ^-(path (weld (thread-dir root) /[(scot %uv t)])))
++  mdir        |=([root=path t=thread-id:uc] ^-(path (weld (tdir root t) /msg)))
++  blob-dir    |=(root=path ^-(path (weld root /mail/blob)))
++  blob-rail   |=([root=path h=@uv] ^-(road:tarball [%& %& (blob-dir root) (scot %uv h)]))
++  vis-rail    |=(root=path ^-(road:tarball [%& %& (mail-dir root) %blobvis]))
++  draft-dir   |=(root=path ^-(path (weld root /mail/draft)))
++  rule-dir    |=(root=path ^-(path (weld root /mail/rule)))
++  list-dir    |=(root=path ^-(path (weld root /mail/list)))
++  draft-rail  |=([root=path i=@uv] ^-(road:tarball [%& %& (draft-dir root) (scot %uv i)]))
++  rule-rail   |=([root=path i=@uv] ^-(road:tarball [%& %& (rule-dir root) (scot %uv i)]))
::  +list-rail: the grub for one list. The NAME IS THE SEGMENT, cast
::  straight to a knot rather than scotted: +list-name-ok:uw has already
::  refused everything a knot cannot hold - anything but a-z, 0-9 and
::  '-', an empty name, and anything over 64 bytes - and it is checked
::  at the route AND again at the writer, so this cast never sees a
::  name that was not admitted by both.
++  list-rail   |=([root=path n=@t] ^-(road:tarball [%& %& (list-dir root) `@ta`n]))
++  meta-rail   |=([root=path t=thread-id:uc] ^-(road:tarball [%& %& (tdir root t) %meta]))
::  +slot: the grub name of one SIGNED COPY.
::
::    (sham [id sig]), not a positional index. The spec writes this leaf as
::    <n> without saying what n is; a position would have to be renumbered
::    on every insert (a chain is ordered by `sent`, and mail arrives out of
::    order), which is a thousand rewrites per delivery and, worse, makes
::    the storage key something other than [id sig]. Deriving the name from
::    [id sig] makes the anti-shadowing key and the storage key the same
::    thing by construction: two copies of one message differing in
::    signature cannot collide, a redelivery of the same chain is a no-op,
::    and +prune sheds a copy by culling exactly one grub.
::
++  slot  |=([i=msg-id:uc s=@ux] ^-(@ta (scot %uv (sham [i s]))))
::
::  +node-dir: the directory one message's copies live in, relative to
::  the thread's msg/ directory. Its segments ARE the message's ancestry,
::  root first, so the path a copy is stored at is the whole answer to
::  "what conversation led to this".
::
++  node-dir  |=(place=(list msg-id:uc) ^-(path (id-path:uc place)))
::
::  +sorted-dirs: directories shallowest first, which is the only order
::  in which they can be made - a directory needs its parent.
::
++  sorted-dirs
  |=  ds=(set path)
  ^-  (list path)
  (sort ~(tap in ds) |=([a=path b=path] (lth (lent a) (lent b))))
::
::  ── writes ──────────────────────────────────────────────────────────
::
::  +put-file: create-or-overwrite one grub. %over's forced make creates
::  when the rail is missing and overwrites when it exists, so no
::  peek-exists round trip.
::
++  put-file
  |=  [road=road:tarball =blot:tarball noun=*]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  (over:io road [blot noun])
::
++  ensure-dir
  |=  pax=path
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  road=road:tarball  [%& %| pax]
  ;<  ex=?  bind:m  (peek-exists:io road)
  ?:  ex  (pure:m ~)
  (make:io road &+empty-dir:loader)
::
::  +ensure-nodes: make each of these node directories, in order.
::
::    Recursion by ARM NAME, not by $: a $ with arguments inside a ;<
::    continuation cannot find the trap.
::
++  ensure-nodes
  |=  [dir=path ps=(list path)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  ps  (pure:m ~)
  ;<  ~  bind:m  (ensure-dir (weld dir i.ps))
  (ensure-nodes dir t.ps)
::
++  ensure-thread
  |=  [root=path t=thread-id:uc]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  ~  bind:m  (ensure-dir (thread-dir root))
  ;<  ~  bind:m  (ensure-dir (tdir root t))
  ;<  ~  bind:m  (ensure-dir (mdir root t))
  ::  lay a default meta so EVERY thread has the leaf the tree says it
  ::  has. A delivered thread is never marked read, so nothing else would
  ::  ever create one, and a reader would find the leaf missing rather
  ::  than empty. Guarded, so it never clobbers real read marks.
  ;<  ex=?  bind:m  (peek-exists:io [%& %& (tdir root t) %meta])
  ?:  ex  (pure:m ~)
  (put-file [%& %& (tdir root t) %meta] [/urmail %meta] *meta:uc)
::
::  ── reads ───────────────────────────────────────────────────────────
::
::  +read-stored / +read-meta / +read-idx: the `;;` ladders.
::
::    Each persisted marc is a noun passthrough, so what comes back is a
::    raw noun and the SHAPE CHECK LIVES HERE. Newest shape first; a later
::    version adds a branch above the default and upgrades in place. Doing
::    it in the marc instead would re-validate every stored grub against
::    the live type on read, booming every message the day the type moves.
::
::  +read-stored: %2 grubs only. %0 and %1 are REFUSED, not upgraded.
::
::    $stored-msg went to 1 when `unsigned` gained attachments and to 2
::    when it gained body-mime and was frozen. An old grub is
::    recognisable - its head is its version - but it cannot be
::    migrated: msg-id and the signature both cover the shape, so
::    rewriting an old message into the new shape leaves a message whose
::    signature no longer matches its own contents, which every peer
::    would then read as %forged. Turning genuine mail into apparent
::    forgeries is worse than refusing it.
::
::    So an old grub is DROPPED HERE, before verification: it never
::    reaches +verify-chain, is never labelled, is never counted, and
::    renders as "unreadable" through the marc. The version was bumped
::    rather than reused so a %1 grub is refused as cleanly as a %0 one
::    instead of clamming into the new shape by accident.
::
::    $unsigned is now frozen, so this is the last such break. Nothing
::    may be added to it again.
::
++  read-stored
  |=  n=*
  ^-  (unit stored-msg:uc)
  =/  res  (mule |.(;;(stored-msg:uc n)))
  ?:(?=(%& -.res) `p.res ~)
::
::  +read-meta: the local-state ladder, which DOES upgrade in place.
::
::    Nothing in meta is covered by a signature, so a %0 meta becomes a
::    %1 with direct=%.n and no bcc record and misrepresents nothing.
::    That is the contrast with +read-stored above, and it is the whole
::    reason local state is kept out of `unsigned`.
::
++  read-meta
  |=  [root=path t=thread-id:uc]
  =/  m  (fiber:fiber:nexus ,meta:uc)
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io [%& %& (tdir root t) %meta] ~)
  ?.  ?=([%file *] vw)  (pure:m *meta:uc)
  ?:  (is-boom:tarball sang.vw)  (pure:m *meta:uc)
  =/  n  (sang-noun:tarball sang.vw)
  =/  r1  (mule |.(;;(meta:uc n)))
  ?:  ?=(%& -.r1)  (pure:m p.r1)
  =/  r0  (mule |.(;;(meta-0:uc n)))
  ?:  ?=(%| -.r0)  (pure:m *meta:uc)
  (pure:m [%1 read.p.r0 archived.p.r0 labels.p.r0 | ~])
::
::  +read-drafts / +read-rules: the two new persisted subtrees.
::
::    One deep peek each, and the shape ladder is here rather than in the
::    marc for the reason every other ladder here is: a typed marc
::    re-validates every stored grub against the live type on read, so
::    moving the type booms what is on disk. A grub that does not clam is
::    DROPPED from the list, never crashed on - these run on the writer
::    and on request fibers, and neither may fail on one bad grub.
::
++  read-drafts
  |=  root=path
  =/  m  (fiber:fiber:nexus ,(list draft:uc))
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io [%& %| (draft-dir root)] ~)
  ?.  ?=([%ball *] vw)  (pure:m ~)
  (pure:m (collect-drafts ball.vw))
::
++  collect-drafts
  |=  b=ball:tarball
  ^-  (list draft:uc)
  ?~  fil.b  ~
  %+  murn  ~(val by contents.u.fil.b)
  |=  c=[=sang:tarball gain=? bang=(unit tang)]
  ^-  (unit draft:uc)
  ?:  (is-boom:tarball sang.c)  ~
  =/  res  (mule |.(;;(draft:uc (sang-noun:tarball sang.c))))
  ?:(?=(%| -.res) ~ `p.res)
::
++  read-draft
  |=  [root=path i=@uv]
  =/  m  (fiber:fiber:nexus ,(unit draft:uc))
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io (draft-rail root i) ~)
  ?.  ?=([%file *] vw)  (pure:m ~)
  ?:  (is-boom:tarball sang.vw)  (pure:m ~)
  =/  res  (mule |.(;;(draft:uc (sang-noun:tarball sang.vw))))
  (pure:m ?:(?=(%| -.res) ~ `p.res))
::
++  read-rules
  |=  root=path
  =/  m  (fiber:fiber:nexus ,(list rule:uc))
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io [%& %| (rule-dir root)] ~)
  ?.  ?=([%ball *] vw)  (pure:m ~)
  (pure:m (collect-rules ball.vw))
::
++  collect-rules
  |=  b=ball:tarball
  ^-  (list rule:uc)
  ?~  fil.b  ~
  %+  murn  ~(val by contents.u.fil.b)
  |=  c=[=sang:tarball gain=? bang=(unit tang)]
  ^-  (unit rule:uc)
  ?:  (is-boom:tarball sang.c)  ~
  =/  res  (mule |.(;;(rule:uc (sang-noun:tarball sang.c))))
  ?:(?=(%| -.res) ~ `p.res)
::
::  +read-lists: every mailing list, as [name members] pairs.
::
::    The ONE reader here that has to keep the map's KEY, because a
::    list's name is its path segment and is deliberately not a field of
::    the grub. So this taps the contents map rather than walking its
::    values the way +collect-drafts and +collect-rules do.
::
::    Same ladder discipline as those two: a grub that does not clam is
::    DROPPED rather than crashed on. This runs on the writer and on
::    request fibers, and neither may fail on one bad grub.
::
++  read-lists
  |=  root=path
  =/  m  (fiber:fiber:nexus ,(list [name=@t members=(set @p)]))
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io [%& %| (list-dir root)] ~)
  ?.  ?=([%ball *] vw)  (pure:m ~)
  (pure:m (collect-lists ball.vw))
::
++  collect-lists
  |=  b=ball:tarball
  ^-  (list [name=@t members=(set @p)])
  ?~  fil.b  ~
  %+  murn  ~(tap by contents.u.fil.b)
  |=  [nom=@ta =sang:tarball gain=? bang=(unit tang)]
  ^-  (unit [@t (set @p)])
  ?:  (is-boom:tarball sang)  ~
  =/  res  (mule |.(;;(mail-list:uc (sang-noun:tarball sang))))
  ?:(?=(%| -.res) ~ `[`@t`nom members.p.res])
::
++  read-idx
  |=  root=path
  =/  m  (fiber:fiber:nexus ,mail-idx:uc)
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io [%& %& (mail-dir root) %idx] ~)
  ?.  ?=([%file *] vw)  (pure:m *mail-idx:uc)
  ?:  (is-boom:tarball sang.vw)  (pure:m *mail-idx:uc)
  =/  res  (mule |.(;;(mail-idx:uc (sang-noun:tarball sang.vw))))
  (pure:m ?:(?=(%& -.res) p.res *mail-idx:uc))
::
::  +read-stored-blob-noun: the blob shape ladder.
::
::    Newest first, and unlike +read-stored this one really does upgrade
::    in place: a %0 blob (bytes, no arrival time) becomes a %1 with
::    at=0, which sorts it oldest and evicts it first. That is safe here
::    for the reason it is not safe for a message - a blob's shape is
::    covered by no signature, so supplying a default misrepresents
::    nothing.
::
++  read-stored-blob-noun
  |=  n=*
  ^-  (unit stored-blob:uc)
  =/  r1  (mule |.(;;(stored-blob:uc n)))
  ?:  ?=(%& -.r1)  `p.r1
  =/  r0  (mule |.(;;(stored-blob-0:uc n)))
  ?:(?=(%| -.r0) ~ `[%1 octs.p.r0 *@da])
::
::  +read-blob: one attachment's bytes, ~ when we do not hold them.
::
++  read-blob
  |=  [root=path h=@uv]
  =/  m  (fiber:fiber:nexus ,(unit octs))
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io (blob-rail root h) ~)
  ?.  ?=([%file *] vw)  (pure:m ~)
  ?:  (is-boom:tarball sang.vw)  (pure:m ~)
  =/  st  (read-stored-blob-noun (sang-noun:tarball sang.vw))
  ?~(st (pure:m ~) (pure:m `octs.u.st))
::
::  +blob-size: the DECLARED LENGTH of a blob we hold, ~ when we do not.
::
::    The size that ends up inside a signature, and the only thing the
::    send path wants off a stored blob. It reads the grub the same way
::    +read-blob does and answers p.octs alone, so the bytes never leave
::    this arm - a send naming sixteen attachments would otherwise carry
::    four megabytes of octs through the rest of the send for four
::    numbers.
::
++  blob-size
  |=  [root=path h=@uv]
  =/  m  (fiber:fiber:nexus ,(unit @ud))
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io (blob-rail root h) ~)
  ?.  ?=([%file *] vw)  (pure:m ~)
  ?:  (is-boom:tarball sang.vw)  (pure:m ~)
  =/  st  (read-stored-blob-noun (sang-noun:tarball sang.vw))
  ?~(st (pure:m ~) (pure:m `p.octs.u.st))
::
++  read-blobvis
  |=  root=path
  =/  m  (fiber:fiber:nexus ,blob-index:uc)
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io (vis-rail root) ~)
  ?.  ?=([%file *] vw)  (pure:m *blob-index:uc)
  ?:  (is-boom:tarball sang.vw)  (pure:m *blob-index:uc)
  =/  res  (mule |.(;;(blob-index:uc (sang-noun:tarball sang.vw))))
  (pure:m ?:(?=(%& -.res) p.res *blob-index:uc))
::
::  +list-blobs: every blob this ship holds, with its age and weight.
::
::    The store's whole bookkeeping. Both bounds - max-blobs by count and
::    max-blob-bytes by weight - are computed off this, and so is the
::    eviction order.
::
::    Neither bound can be weaponised: bytes only ever enter through a
::    LOCAL action (%send's files, or %fetch-blob), never through a
::    delivered chain, which carries metadata and no bytes at all.
::
++  list-blobs
  |=  root=path
  =/  m  (fiber:fiber:nexus ,(list blob-row:uc))
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io [%& %| (blob-dir root)] ~)
  ?.  ?=([%ball *] vw)  (pure:m ~)
  ?~  fil.ball.vw  (pure:m ~)
  %-  pure:m
  %+  murn  ~(tap by contents.u.fil.ball.vw)
  |=  [nm=@ta c=[=sang:tarball gain=? bang=(unit tang)]]
  ^-  (unit blob-row:uc)
  ?:  (is-boom:tarball sang.c)  ~
  =/  hh=(unit @uv)  (slaw %uv nm)
  ?~  hh  ~
  =/  st  (read-stored-blob-noun (sang-noun:tarball sang.c))
  ?~  st  ~
  `[u.hh at.u.st p.octs.u.st]
::
::  +all-referenced: every content address any stored message mentions.
::
::    The other half of the eviction predicate. A blob named by any
::    message is never shed; an unreferenced blob is a file whose every
::    message has been deleted, and %delete-thread culls messages
::    without culling their blobs, so these genuinely accumulate.
::
++  all-referenced
  |=  root=path
  =/  m  (fiber:fiber:nexus ,(set @uv))
  ^-  form:m
  ;<  loaded=(map thread-id:uc (map path stored-msg:uc))  bind:m  (read-threads root)
  (pure:m (chain-hashes:uc (zing (turn ~(val by loaded) chain-of))))
::
::  +make-room: shed unreferenced blobs until one more of `bytes` fits.
::
::    Refuses rather than half-evicting: +shed-for returns an empty drop
::    list when the store cannot be made to fit, so a caller never culls
::    files and then rejects the write anyway.
::
::    THE CULL IS OF THE TREE GRUB ONLY, NEVER THE FARM BINDING, and
::    that is not a shortcut. Culling the binding would park a
::    high-water mark that nothing re-binds under, burning case 1 for
::    that hash permanently and making the blob unfetchable at every
::    peer's first probe. The cost of the rule is stated plainly: an
::    evicted blob's bytes are still bound in gall's farm, so these
::    bounds govern the TREE store, not everything the ship holds.
::
++  make-room
  |=  [root=path bytes=@ud]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  held=(list blob-row:uc)  bind:m  (list-blobs root)
  ;<  refs=(set @uv)  bind:m  (all-referenced root)
  =/  plan  (shed-for:uc held refs 1 bytes)
  ?.  ok.plan  (pure:m |)
  ;<  ~  bind:m  (evict root drop.plan)
  (pure:m &)
::
++  evict
  |=  [root=path hs=(list @uv)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  hs  (pure:m ~)
  ;<  ~  bind:m  (cull-if-there (blob-rail root i.hs))
  (evict root t.hs)
::
::  +read-threads: every stored thread, as copy maps keyed by TREE PATH.
::
::    One deep peek of /mail/thread rather than a walk per thread. This is
::    the O(total stored messages) read the spec already records against
::    +thread-key, now paid on the tree instead of on agent state; the
::    upgrade path is the same, a [msg-id sig] -> thread-id index grub.
::
++  read-threads
  |=  root=path
  =/  m  (fiber:fiber:nexus ,(map thread-id:uc (map path stored-msg:uc)))
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io [%& %| (thread-dir root)] ~)
  ?.  ?=([%ball *] vw)  (pure:m ~)
  (pure:m (collect-threads ball.vw))
::
++  collect-threads
  |=  b=ball:tarball
  ^-  (map thread-id:uc (map path stored-msg:uc))
  %-  ~(gas by *(map thread-id:uc (map path stored-msg:uc)))
  %+  murn  ~(tap by dir.b)
  |=  [seg=@ta kid=ball:tarball]
  ^-  (unit [thread-id:uc (map path stored-msg:uc)])
  =/  t=(unit @uv)  (slaw %uv seg)
  ?~  t  ~
  `[u.t (collect-slots kid)]
::
::  +collect-slots: one thread's copies, each under its own tree path.
::
::    The key is the path RELATIVE TO msg/ - the message's ancestry as
::    directories, then the copy's slot - so the map that comes back
::    carries the branching, not just the messages.
::
::    A copy sitting directly under msg/ has a path of length one and is
::    a PRE-TREE grub, from before this layout. It reads back perfectly
::    (nothing downstream of here cares where a copy was stored), which
::    is what lets the migration be a background tidy rather than a gate
::    on reading the mailbox. See +migrate-flat.
::
++  collect-slots
  |=  kid=ball:tarball
  ^-  (map path stored-msg:uc)
  =/  sub=(unit ball:tarball)  (~(get by dir.kid) %msg)
  ?~  sub  ~
  (collect-node ~ u.sub)
::
::  +collect-node: one node of the message tree and everything under it.
::
::    Files are this message's signed copies; subdirectories are its
::    replies. A ball keeps those in two separate maps, so the two can
::    never collide however the names are chosen - which is the whole
::    reason a node can be both a message and a parent.
::
++  collect-node
  |=  [base=path b=ball:tarball]
  ^-  (map path stored-msg:uc)
  =/  here=(map path stored-msg:uc)
    ?~  fil.b  ~
    %-  ~(gas by *(map path stored-msg:uc))
    %+  murn  ~(tap by contents.u.fil.b)
    |=  [nm=@ta c=[=sang:tarball gain=? bang=(unit tang)]]
    ^-  (unit [path stored-msg:uc])
    ?:  (is-boom:tarball sang.c)  ~
    =/  s=(unit stored-msg:uc)  (read-stored (sang-noun:tarball sang.c))
    ?~(s ~ `[(snoc base nm) u.s])
  =/  kids=(list [seg=@ta kid=ball:tarball])  ~(tap by dir.b)
  |-  ^-  (map path stored-msg:uc)
  ?~  kids  here
  =.  here  (~(uni by here) (collect-node (snoc base seg.i.kids) kid.i.kids))
  $(kids t.kids)
::
::  +unreadable-in: copies under this node that no reader can produce.
::
::    +read-stored refuses %0 and %1 grubs rather than upgrading them,
::    and that decision is right and stays: msg-id and the signature
::    both cover the shape, so rewriting an old message into the new
::    one leaves a message whose signature no longer matches its own
::    contents, which every peer then reads as %forged. Turning genuine
::    mail into apparent forgeries is worse than refusing it.
::
::    But refusing SILENTLY is a different thing. +collect-node murns
::    them away, so every message stored before the body-mime break
::    simply vanishes from the API while its thread's meta and its
::    /mail/idx entry survive - a thread that renders short, or empty,
::    with nothing anywhere saying why. Counting them is what turns
::    "your mail is gone" into "this ship cannot read N messages here",
::    which is a true statement a user can act on.
::
::    A separate walk rather than a second return value from
::    +collect-node, deliberately: the collector is on the writer's
::    hot path and is called for every send, read-mark and delivery,
::    while this is wanted only by the two read routes and once at
::    rise.
::
::    TAKES THE THREAD'S BALL AND DIVES INTO msg/, exactly as
::    +collect-slots does, and for the same reason: msg/ is where the
::    copies are, and the sibling `meta` leaf is a $meta and not a
::    $stored-msg. Counting from the thread ball counted meta too - it
::    fails +read-stored the way a pre-freeze grub does, because that
::    ladder answers one question and meta is not an answer to it - so
::    every ordinary thread on the ship would have reported one
::    unreadable copy it does not have. The two walks have to agree on
::    what they are walking or the count is not of the same thing the
::    listing shows.
::
++  unreadable-in
  |=  kid=ball:tarball
  ^-  @ud
  =/  sub=(unit ball:tarball)  (~(get by dir.kid) %msg)
  ?~  sub  0
  (unreadable-under u.sub)
::
::  +unreadable-under: the recursive half, over one node of the message
::  tree and everything below it.
::
::    `here` and `below` are added. They were not: the recursion was one
::    +roll whose accumulator starts at the BUNT of its own sample, so
::    every level computed its own count and then threw it away by
::    starting the children's fold at 0. The arm therefore answered 0
::    for every thread on every ship, which made the whole
::    unreadable-copy report dead: +serve-thread's `lost` was always 0,
::    so a thread whose every copy is unreadable took the 404 branch
::    that is meant for a thread that is not there, +inbox-json's
::    placeholder row was unreachable, and the banner never rendered.
::    A count that is structurally always zero is worse than no count,
::    because the surfaces above it read it as good news.
::
++  unreadable-under
  |=  b=ball:tarball
  ^-  @ud
  =/  here=@ud
    ?~  fil.b  0
    %+  roll  ~(val by contents.u.fil.b)
    |=  [c=[=sang:tarball gain=? bang=(unit tang)] acc=@ud]
    ?:  (is-boom:tarball sang.c)  +(acc)
    ?~((read-stored (sang-noun:tarball sang.c)) +(acc) acc)
  =/  below=@ud
    %+  roll  ~(val by dir.b)
    |=([kid=ball:tarball acc=@ud] (add acc (unreadable-under kid)))
  (add here below)
::
::  +chain-of: a thread's copies as one chain, WHOLE TREE INCLUDED.
::
::    This is the local view: opening a thread shows every branch of it,
::    which is what a mail client does. Only a SEND narrows to a
::    root-to-leaf path - see +do-send and +path-chain:uc.
::
::    +merge with an empty `old` is what re-imposes the canonical display
::    order across branches. Sibling order matters for display and never
::    for identity, so it is imposed here rather than stored.
::
++  chain-of
  |=  ss=(map path stored-msg:uc)
  ^-  chain:uc
  (merge:uc ~ (turn ~(val by ss) |=(s=stored-msg:uc msg.s)))
::
++  verdicts-of
  |=  ss=(map path stored-msg:uc)
  ^-  (map [msg-id:uc @ux] verdict:uc)
  %-  ~(gas by *(map [msg-id:uc @ux] verdict:uc))
  %+  turn  ~(val by ss)
  |=(s=stored-msg:uc [[(id:uc unsigned.msg.s) sig.msg.s] verdict.s])
::
++  threads-of
  |=  loaded=(map thread-id:uc (map path stored-msg:uc))
  ^-  (map thread-id:uc thread:uc)
  %-  ~(run by loaded)
  |=  ss=(map path stored-msg:uc)
  ^-  thread:uc
  =/  c=chain:uc  (chain-of ss)
  [c (participants:uc c) (last-sent:uc c)]
::
::  ── the trace grub ──────────────────────────────────────────────────
::
++  note
  |=  [root=path stage=@t ok=? why=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  now=@da  bind:m  bowl-now
  %^  put-file  [%& %& (weld root /tr) %last]  [/ %json]
  %-  pairs:enjs:format
  :~  ['stage' [%s stage]]
      ['ok' [%b ok]]
      ['why' [%s why]]
      ['at' (time:enjs:format now)]
  ==
::
::  +reject: refuse a poke without crashing the writer. See the header.
::
::    Returns %.n, because every arm under +apply answers the writer's
::    one question - DID ANYTHING CHANGE - and a refusal never did.
::
++  reject
  |=  [root=path why=@t]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  ~  bind:m  (trace:io ~[leaf+"urmail: rejected: {(trip why)}"])
  ;<  ~  bind:m  (note root 'reject' | why)
  (pure:m |)
::
::  ── permissions ─────────────────────────────────────────────────────
::
::  +grant-public: whitelist a POKE road to /main.sig in the `public`
::  usergroup, so any ship may hand us a chain.
::
::    The sanctioned path: a grant lands through the registry's %how
::    action, which validates the roads against the sender's registered
::    prefix and merges them server-side, so lattice's grants in the same
::    group survive untouched. A direct write to how.weir does none of that.
::
::    The grant is a ROAD, not a mark: a peer that can reach /main.sig can
::    address any marc at it, %urmail-action included. +apply's source
::    check is what makes that harmless, and it is the same check the
::    agent's `?>  =(our.bowl src.bowl)` was.
::
++  grant-public
  |=  root=path
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  gdir=road:tarball  [%& %| /sys/ames/usergroups/'public.grp']
  ;<  ok=?  bind:m  (peek-exists:io gdir)
  ?.  ok
    (trace:io ~[leaf+"urmail: no public usergroup, delivery is local only"])
  ;<  ~  bind:m  (reg-register-at:io [root %'main.sig'])
  %+  reg-how:io  /public
  [make=~ poke=(sy ~[`road:tarball`[%& %& root %'main.sig']]) peek=~]
::
::  ── the writer ──────────────────────────────────────────────────────
::
::  +apply: one poke. ANSWERS WHETHER THE TREE ACTUALLY CHANGED.
::
::    That answer is the beacon's gate, and it has to come from here
::    rather than from re-reading the poke, because only the arms below
::    know. Delivery is granted to the `public` usergroup, so ANY ship
::    may poke this writer; if a bump followed every poke, a chain
::    refused in microseconds - or a redelivery of a chain we already
::    hold - would move /beacon/rev, and each move costs every open
::    client a full inbox listing, which is O(total stored messages),
::    plus a refetch of whatever thread it is showing. That is remote
::    amplification bought for nothing.
::
::    %send answers %.n despite changing everything: it has already
::    bumped from inside +do-send, before its fan-out, so that a local
::    reader never waits on a remote ship. %read answers %.n because a
::    read-mark is not content and a bump would make an open reader
::    refetch, which marks it read again - a loop, not a burst.
::
::    EVERY PAYLOAD IS CLAMMED HERE, UNDER MULE, AND NOWHERE ELSE.
::
::    The wire marcs are noun passthroughs precisely so that they
::    cannot refuse anything, and this is where the refusing happens.
::    They used to be typed, which looked stricter and was catastrophic:
::    grubbery validates a poke in +hydrate, before any nexus code runs,
::    and a validation failure there fails the writer PROCESS - after
::    which +rise-wait restarts it by CONSUMING the next poke without
::    processing it. A typed wire marc therefore never rejected a bad
::    chain; it destroyed the NEXT GOOD ONE, silently. /main.sig is
::    granted to the `public` usergroup, so any ship on the network
::    could do that for the price of one malformed noun, repeatedly, to
::    a mail application.
::
::    Validation you cannot catch is not validation, it is a fuse. A
::    malformed payload is now refused the way every other cap is
::    refused: a branch that returns cleanly, labelled, with the writer
::    still standing and the next poke still its own.
::
++  apply
  |=  [root=path =from:fiber:nexus =sage:tarball]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ::  a chain from ANYONE. src is deliberately not checked against the
  ::  participants: the signatures are the authority, not the courier.
  ?:  =([/ %urmail-chain] p.sage)
    =/  res  (mule |.(~|(%urmail-bad-chain ;;(chain:uc q.q.sage))))
    ?:  ?=(%| -.res)  (reject root 'malformed chain')
    (deliver root p.res)
  ?.  ?|(=([/ %urmail-action] p.sage) =([/urmail %blob-in] p.sage))
    ::  an unknown blot. Ignore it rather than crash - see the header.
    (pure:m |)
  ;<  our=@p  bind:m  bowl-our
  ::  +get-poke-src reads the SHIP off the transport, never the payload.
  ::  ~ is a fiber inside this nexus; our own ship arrives named, because
  ::  the agent-facing surface makes every caller a /sys/ames/ships/<who>.
  =/  src=(unit @p)  (get-poke-src:io from)
  ?.  ?|(?=(~ src) =(our u.src))
    (reject root 'foreign action refused')
  ::  a fetch fiber's answer. Local-only for the same reason an action
  ::  is: the blot has a path prefix, which the agent-facing surface and
  ::  a dojo poke cannot name, but a peer poking over ames can - so the
  ::  source check is what makes that harmless. The hash is re-checked
  ::  in +take-blob regardless.
  ?:  =([/urmail %blob-in] p.sage)
    =/  res  (mule |.(~|(%urmail-bad-blob-in ;;(blob-in:uc q.q.sage))))
    ?:  ?=(%| -.res)  (reject root 'malformed blob-in')
    (take-blob root p.res)
  =/  res  (mule |.(~|(%urmail-bad-action ;;(action:uc q.q.sage))))
  ?:  ?=(%| -.res)  (reject root 'malformed action')
  (act root p.res)
::
++  act
  |=  [root=path a=action:uc]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ?-  -.a
    ::  +do-send answers WHETHER IT SENT, not whether to bump: it bumps
    ::  the beacon itself, from before its fan-out, so a local reader
    ::  never waits on a remote ship. The answer is discarded here and
    ::  used by %send-draft, which must not delete a draft whose send
    ::  the writer refused.
      %send
    ;<  *  bind:m
      (do-send root to.a subj.a body.a body-mime.a prev.a files.a bcc.a)
    (pure:m |)
  ::  the same send, naming blobs the store already holds instead of
  ::  carrying bytes. The web surface's only send path.
  ::
      %send-ref
    ;<  *  bind:m
      (do-send-refs root to.a subj.a body.a body-mime.a prev.a refs.a bcc.a)
    (pure:m |)
  ::
    %read           (do-read root ids.a)
    %delete-thread  (do-delete root thread-id.a)
    %fetch-blob     (do-fetch-blob root hash.a from.a)
    %restrict-blob  (do-restrict root hash.a ships.a)
    %publish-blob   (do-publish root hash.a)
  ::  the mail-client layer. EVERY ONE OF THESE ANSWERS %.n, and that is
  ::  not an oversight. The beacon tells OTHER open readers that content
  ::  moved; a label, an archive, an unread mark, a draft and a rule are
  ::  local state on a thread nobody else can see. Bumping for them would
  ::  cost every open tab a full inbox listing plus a thread refetch for
  ::  a change it cannot observe - the read-mark storm again, and the tab
  ::  that made the change refetches on its own anyway.
    %label          (do-label root thread-id.a label.a add.a)
    %archive        (do-archive root thread-id.a archived.a)
    %unread         (do-unread root ids.a)
    %save-draft     (do-save-draft root draft.a)
    %delete-draft   (do-delete-draft root id.a)
    %send-draft     (do-send-draft root id.a)
    %save-rule      (do-save-rule root rule.a)
    %delete-rule    (do-delete-rule root id.a)
  ::  mailing lists, local state like the rest of this block and %.n for
  ::  the same reason: a list is an address book entry on this ship, no
  ::  peer can observe it, and the tab that saved it refetches its own
  ::  listing. Bumping here would cost every open tab a full inbox
  ::  listing plus a thread refetch for a change nobody else can see.
    %save-list      (do-save-list root name.a members.a)
    %delete-list    (do-delete-list root name.a)
  ==
::
::  +do-send: compose, reply and forward are all this.
::
::    A reply points `prev` at a message in a chain we hold. A forward is
::    the same action addressed elsewhere. The chain that travels is the
::    payload, and that is the whole design.
::
::    WHAT TRAVELS IS A ROOT-TO-LEAF PATH, not the thread. Shipping the
::    whole thread was a leak: two participants have a side exchange on
::    one branch, one of them forwards a message on another branch
::    onward, and the third party receives the side exchange - signed,
::    permanent, attributable, and nobody asked for it. The path from the
::    thread root to `prev` is what a recipient needs to verify this
::    message and is all it needs; see +path-chain:uc.
::
::    The bounds +deliver enforces are enforced here too. Every send ships
::    the path it is replying into, so one oversized compose would poison
::    a thread permanently: every later message on that path rejected by
::    every recipient, silently, forever. Failing at compose time is the
::    only point where a human can still do something about it.
::::    ANSWERS WHETHER IT SENT. Not whether to bump: this arm bumps the
::    beacon itself, from inside, before the fan-out. See the end.
::
++  do-send
  |=  $:  root=path
          to=(set ship)
          subj=@t
          body=@t
          body-mime=@t
          prev=(unit msg-id:uc)
          files=(list file:uc)
          bcc=(set ship)
      ==
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ?.  (files-ok:uc files)
    (reject root 'bad attachment')
  ::  the store bound counts only the files we would actually ADD.
  ::  +store-blob skips a file we already hold, so counting every
  ::  attachment against the cap refuses a send that stores nothing -
  ::  and the commonest attachment in a thread is one already in it.
  ;<  fresh=(list file:uc)  bind:m  (unheld-files root files)
  ::  the metadata is derived FROM THE BYTES IN HAND, which is what
  ::  makes `size` and `hash` agree with what a fetcher re-measures.
  (do-send-core root to subj body body-mime prev (turn files describe:uc) fresh bcc)
::
::  +do-send-refs: the same send, naming blobs the store already holds.
::
::    THE WEB SURFACE'S SEND. The browser uploaded each file to
::    POST /api/blob first, which hashed and stored it and answered the
::    address; this names those addresses and carries no bytes.
::
::    THE SIZE THAT GETS SIGNED IS READ OFF THE STORED BLOB, never off
::    the request, and the hash is NOT re-derived. The store only ever
::    accepted a blob that hashed to its own address - +do-web-blob and
::    +take-blob are the only two writers and both check - so re-hashing
::    here would pay a quarter-megabyte of +sham for a fact the store
::    already guarantees, while trusting a client's `size` would let one
::    sign a length the bytes do not have.
::
::    A ref naming no stored blob refuses the WHOLE send: nothing is
::    signed, nothing is stored, and the route ahead of this one has
::    already answered 400 with the hash, which is the message a person
::    can act on. This is the point-of-use half of that pair, and it is
::    not redundant: this route is not the only caller, and a blob can
::    be evicted between the route's check and the writer's.
::
++  do-send-refs
  |=  $:  root=path
          to=(set ship)
          subj=@t
          body=@t
          body-mime=@t
          prev=(unit msg-id:uc)
          refs=(list attach-ref:uc)
          bcc=(set ship)
      ==
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  as=(unit (list attachment:uc))  bind:m  (resolve-refs root refs)
  ?~  as  (reject root 'unknown attachment')
  ::  nothing to store: the bytes are already in the tree and already
  ::  published, which is what the upload route did.
  (do-send-core root to subj body body-mime prev u.as ~ bcc)
::
::  +resolve-refs: each named blob's SIGNED metadata, or ~ if any is
::  missing.
::
::    Recursion by ARM NAME, not $: a $ with arguments inside a ;<
::    continuation cannot find the trap.
::
::    +blob-size and not +read-blob: the size is the only thing wanted
::    here and the octs must not travel any further than the arm that
::    measures it.
::
++  resolve-refs
  |=  [root=path rs=(list attach-ref:uc)]
  =/  m  (fiber:fiber:nexus ,(unit (list attachment:uc)))
  ^-  form:m
  ?~  rs  (pure:m `~)
  ;<  sz=(unit @ud)  bind:m  (blob-size root hash.i.rs)
  ?~  sz  (pure:m ~)
  ;<  rest=(unit (list attachment:uc))  bind:m  (resolve-refs root t.rs)
  ?~  rest  (pure:m ~)
  (pure:m `[[name.i.rs u.sz mime.i.rs hash.i.rs] u.rest])
::
::  +do-send-core: everything both send paths do once the signed
::  attachment list exists.
::
::    `as` is the metadata that goes inside `unsigned`; `store` is the
::    bytes still to be written, which is every file on the dojo path
::    and nothing at all on the web path. Splitting there is what keeps
::    ONE signing path: the two entry points differ in where
::    [name size mime hash] came from and in nothing else.
::
++  do-send-core
  |=  $:  root=path
          to=(set ship)
          subj=@t
          body=@t
          body-mime=@t
          prev=(unit msg-id:uc)
          as=(list attachment:uc)
          store=(list file:uc)
          bcc=(set ship)
      ==
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ?.  (lte (met 3 body) max-body:uc)
    (reject root 'body too long')
  ?.  (lte (met 3 subj) max-subj:uc)
    (reject root 'subject too long')
  ?.  (lte (add ~(wyt in to) ~(wyt in bcc)) max-to:uc)
    (reject root 'too many recipients')
  ?.  (text-ok:uc body-mime max-mime:uc)
    (reject root 'bad body mime')
  ?.  (attaches-ok:uc as)
    (reject root 'bad attachment')
  ;<  room=?  bind:m  (room-for root store)
  ?.  room
    (reject root 'blob store full')
  ;<  loaded=(map thread-id:uc (map path stored-msg:uc))  bind:m  (read-threads root)
  ::  resolve prev to its containing thread. A msg-id is a hash over the
  ::  message's full contents, so it names exactly one message and
  ::  therefore exactly one chain.
  =/  tid=(unit thread-id:uc)
    ?~  prev  ~
    =/  hits
      %+  skim  ~(tap by loaded)
      |=  [t=thread-id:uc ss=(map path stored-msg:uc)]
      %+  lien  ~(val by ss)
      |=(s=stored-msg:uc =((id:uc unsigned.msg.s) u.prev))
    ?~(hits ~ `p.i.hits)
  ?:  &(?=(^ prev) ?=(~ tid))
    (reject root 'unknown prev')
  ;<  our=@p    bind:m  bowl-our
  ;<  now=@da   bind:m  bowl-now
  ;<  lyf=@ud   bind:m  (our-life our)
  ;<  rng=ring  bind:m  (our-ring lyf)
  ::  `as` goes INSIDE `unsigned`, so it is covered by the signature and
  ::  by msg-id: swapping a file breaks the signature. Every field in it
  ::  was derived from bytes THIS SHIP HOLDS - measured off the store on
  ::  the ref path, off the octs in hand on the dojo one - which is what
  ::  makes `size` and `hash` agree with what a fetcher will re-measure.
  ::  the chain names `to` and NOTHING ELSE. bcc affects delivery only:
  ::  the blind-copied ships get the same canonical bytes, the same
  ::  msg-id and the same thread, and see the visible recipients, which
  ::  is what BCC means. Nothing about them is signed, and no hashed
  ::  commitment to them is signed either - that would leak that a BCC
  ::  exists while staying testable against any guessed ship.
  =/  u=unsigned:uc  [our lyf to subj body body-mime now prev as]
  =/  mg=msg:uc     [u (sign-with:uc rng (digest:uc u))]
  ::  `full` is the whole stored thread, every branch of it; `old` is the
  ::  ONE PATH this message answers, root to `prev`. The difference
  ::  between them is exactly what no longer travels.
  =/  full=chain:uc  ?~(tid ~ (chain-of (~(gut by loaded) u.tid ~)))
  =/  old=chain:uc
    ?~  prev  ~
    (with-root:uc full (path-chain:uc full u.prev))
  =/  new=chain:uc  (merge:uc old ~[mg])
  ::  the outgoing chain must clear the same length bound the recipient
  ::  will apply on arrival, or the send is a silent no-op at the far end
  ::  while looking successful here.
  ?.  (fits-length:uc new max-chain:uc)
    (reject root 'chain too long')
  ::  and the same for depth, for the same reason: a reply past the cap
  ::  would be stored here and refused by every recipient, silently.
  ?.  (fits-depth:uc new max-depth:uc)
    (reject root 'chain too deep')
  ::  and the same for signers. A thread can only exceed the cap through
  ::  our own sends, since delivery refuses such a chain on arrival, so
  ::  this is unreachable in practice - which is the point: it fails
  ::  LOUDLY here, at the one moment a human is looking, instead of
  ::  succeeding locally and being discarded by every recipient.
  ?.  (fits-signers:uc new max-signers:uc)
    (reject root 'too many signers')
  ::  the thread is already resolved: `tid` came from `prev`, which names
  ::  exactly one message, and a compose is by definition a new root.
  ::  Re-deriving it with +thread-key here would be slower AND wrong -
  ::  it returns the first map-traversal match, so a coincidental [id sig]
  ::  overlap with another thread would file this send into that thread.
  ::  Nothing here is attacker-supplied, so no identity fixing is needed.
  =/  rid=thread-id:uc  ?^(tid u.tid (id:uc u))
  ::  store and publish the bytes BEFORE the message goes out. A
  ::  recipient that fetches the instant the chain lands must find the
  ::  blob bound, and a keen at an unbound spur PARKS rather than
  ::  failing, so the ordering is the difference between a fast fetch
  ::  and a fetch that waits out our deadline.
  ;<  ~  bind:m  (store-files root store)
  ;<  ~  bind:m  (ensure-thread root rid)
  ::  where this message sits in the tree: its own ancestry, root first.
  ::  Derived from `prev` against the WHOLE thread, not against the path
  ::  that travels - the two agree, and the whole thread is what is
  ::  actually on disk.
  =/  place=(list msg-id:uc)  (place-of:uc (merge:uc full ~[mg]) (id:uc u))
  ;<  ~  bind:m  (write-msg root rid place mg %verified)
  ;<  ~  bind:m  (mark-read root rid (sy ~[(id:uc u)]) &)
  ::  record who we blind-copied, LOCALLY, so our own Sent view is
  ::  accurate. This never travels and is not part of any signature.
  ;<  ~  bind:m  (record-bcc root rid (id:uc u) bcc)
  ;<  ~  bind:m  (touch-idx root rid)
  ;<  ~  bind:m  (note root 'send' & (scot %uv rid))
  ::  BUMP BEFORE THE FAN-OUT. Everything local has landed by here, and
  ::  the fan-out carries a send-timeout deadline PER RECIPIENT: bumping
  ::  after it made one unreachable ship delay every open tab on this
  ::  ship by up to twenty seconds each, for a change already committed.
  ::  A local reader must never wait on a remote ship. This arm answers
  ::  %.n below so the writer's loop does not bump a second time, which
  ::  is what keeps a send to exactly one bump.
  ;<  ~  bind:m  (bump-beacon root)
  ::  ship the PATH to every recipient, visible and blind alike. A ship
  ::  added at message forty receives the forty on this path, each
  ::  independently verifiable, and nothing off it.
  ;<  ~  bind:m  (fan-out root new ~(tap in (~(del in (~(uni in to) bcc)) our)))
  ::  %.y MEANS "IT SENT", NOT "BUMP THE BEACON". The beacon is already
  ::  moved, above, and +act discards this answer precisely so the
  ::  writer's loop does not move it a second time.
  ::
  ::  The answer exists for %send-draft, which must not delete a draft
  ::  whose send this arm refused. Every +reject above returns %.n, so a
  ::  refused send is distinguishable from a completed one by the one
  ::  caller that has to be able to tell - and a composed message
  ::  survives its own rejection instead of being deleted at the moment
  ::  the ship declines to carry it.
  (pure:m &)
::
::  +do-read: mark a SET of messages read, in one pass.
::
::    Opening a thread marks every unread message in it, so this used to
::    be one poke, one writer event and one FULL MAILBOX SCAN per
::    message - forty messages, forty serialised scans on the ship's
::    single serialisation point for mail, to record something no peer
::    will ever see. One scan now covers the whole set: the mailbox is
::    read once, every id is placed against the thread that holds it,
::    and each affected thread's meta is rewritten once however many of
::    its messages were named.
::
::    Ids naming nothing are skipped rather than refused. A set is not a
::    single request that can be wrong; it is a client reporting what it
::    just rendered, and a thread deleted in another tab between render
::    and poke would otherwise make the whole batch fail.
::
++  do-read
  |=  [root=path ids=(set msg-id:uc)]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ?:  =(~ ids)  (pure:m |)
  ;<  loaded=(map thread-id:uc (map path stored-msg:uc))  bind:m  (read-threads root)
  =/  hits  (group-ids loaded ids)
  ?~  hits  (reject root 'unknown message')
  ;<  ~  bind:m  (mark-read-loop root hits &)
  ::  %.n ALWAYS. Read state is not content: lattice learned this with
  ::  page history, where every visit bumped and every open reader
  ::  reloaded. It is worse here, because a reader answers a bump by
  ::  refetching the thread it is showing and that refetch marks it read
  ::  again - a loop, not a burst.
  (pure:m |)
::
::  +group-ids: which thread holds each of these message ids.
::
::    ONE PASS over the mailbox, shared by %read and %unread so the two
::    cannot disagree about what a set of ids names. Flat on purpose: a
::    roll nested inside a roll cannot thread the outer accumulator
::    through, because the inner one starts from the BUNT of its own
::    sample rather than from the value in hand - it silently drops what
::    the outer had accumulated, and the `_acc` needed to spell it BANGS
::    this file at spawn, which takes the writer with it.
::
::    Ids naming nothing are skipped rather than refused. A set is not a
::    single request that can be wrong; it is a client reporting what it
::    just rendered, and a thread deleted in another tab between render
::    and poke would otherwise make the whole batch fail.
::
++  group-ids
  |=  [loaded=(map thread-id:uc (map path stored-msg:uc)) ids=(set msg-id:uc)]
  ^-  (list [t=thread-id:uc is=(set msg-id:uc)])
  %+  murn  ~(tap by loaded)
  |=  [t=thread-id:uc ss=(map path stored-msg:uc)]
  ^-  (unit [thread-id:uc (set msg-id:uc)])
  =/  mine=(set msg-id:uc)
    %-  ~(gas in *(set msg-id:uc))
    %+  murn  ~(val by ss)
    |=  st=stored-msg:uc
    ^-  (unit msg-id:uc)
    =/  i=msg-id:uc  (id:uc unsigned.msg.st)
    ?:((~(has in ids) i) `i ~)
  ?:(=(~ mine) ~ `[t mine])
::
::  +do-unread: the exact inverse of %read, over the same pass.
::
::    Marking a %forged message unread is a no-op on every surface a
::    user sees, and no branch here says so: the unread count in
::    +entry-json already skips forged copies, because "%forged messages
::    are never counted as unread" is a property of how unread is
::    COMPUTED and not of what is stored. Special-casing it here would
::    be a second place for that rule to live and a second place for it
::    to drift.
::
::    %.n, always, exactly as %read is: read state is not content, and a
::    reader that answered a bump by refetching the thread it is showing
::    would mark it read again - a loop, not a burst.
::
++  do-unread
  |=  [root=path ids=(set msg-id:uc)]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ?:  =(~ ids)  (pure:m |)
  ;<  loaded=(map thread-id:uc (map path stored-msg:uc))  bind:m  (read-threads root)
  =/  hits  (group-ids loaded ids)
  ?~  hits  (reject root 'unknown message')
  ;<  ~  bind:m  (mark-read-loop root hits |)
  ;<  ~  bind:m  (note root 'unread' & 'ok')
  (pure:m |)
::
::  ── labels, folders and archive ─────────────────────────────────────
::
::  +do-label: add or remove ONE label on one thread.
::
::    One label and a direction rather than a whole set, so two tabs
::    adding two different labels do not clobber each other. A
::    set-valued action is last-write-wins over everything the other tab
::    did, which for local state that nothing else can reconcile is a
::    silent loss.
::
::    A FOLDER IS A LABEL. There is no second taxonomy anywhere in this
::    nexus - Inbox, Sent, Archived and Drafts are views, every other
::    folder is a label, and a message is in as many as its thread
::    carries. Two taxonomies would eventually disagree about where a
::    thread is, and the disagreement would be invisible.
::
++  do-label
  |=  [root=path t=thread-id:uc l=@tas add=?]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ::  the label is user input arriving as a JSON string. Nothing
  ::  downstream re-checks it - a cord sits in a (set @tas) perfectly
  ::  happily and then crashes `scot %tas` on a request fiber, which is
  ::  an HTTP connection that never answers.
  ?.  (label-ok:uc l)  (reject root 'bad label')
  ;<  ex=?  bind:m  (peek-exists:io [%& %| (tdir root t)])
  ?.  ex  (reject root 'unknown thread')
  ;<  mt=meta:uc  bind:m  (read-meta root t)
  =/  now=(set @tas)  ?:(add (~(put in labels.mt) l) (~(del in labels.mt) l))
  ::  a no-op writes nothing. Removing a label a thread does not carry
  ::  is a request a client makes freely.
  ?:  =(now labels.mt)  (pure:m |)
  ?.  (lte ~(wyt in now) max-labels:uc)  (reject root 'too many labels')
  ;<  ~  bind:m  (put-file (meta-rail root t) [/urmail %meta] mt(labels now))
  ;<  ~  bind:m  (note root 'label' & l)
  (pure:m |)
::
::  +do-archive: set or clear a thread's archive flag.
::
::    ARCHIVING IS NOT DELETION. It removes a thread from the Inbox view
::    and from nowhere else: the chain is untouched, every signature
::    still stands, the thread is still searchable and still counted,
::    and new mail arriving in it UN-ARCHIVES it. See +file-arrival -
::    without that, archiving would be a way for mail to disappear
::    silently, which is the one thing a mail client must never do.
::
++  do-archive
  |=  [root=path t=thread-id:uc arch=?]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  ex=?  bind:m  (peek-exists:io [%& %| (tdir root t)])
  ?.  ex  (reject root 'unknown thread')
  ;<  mt=meta:uc  bind:m  (read-meta root t)
  ?:  =(arch archived.mt)  (pure:m |)
  ;<  ~  bind:m  (put-file (meta-rail root t) [/urmail %meta] mt(archived arch))
  ;<  ~  bind:m  (note root 'archive' & (scot %uv t))
  (pure:m |)
::
::  ── drafts ──────────────────────────────────────────────────────────
::
::  +do-save-draft: create or overwrite one unsigned draft.
::
::    NOTHING IS SIGNED HERE. A draft has no author, no life, no send
::    time and no signature, and it is stored outside /mail/thread so no
::    walk that produces messages can reach it. Signing happens once, at
::    %send-draft, over the fields as they stand at that moment.
::
::    The id comes from the client and is overwritten in place, so a
::    debounced save costs one grub however many keystrokes it covers.
::
++  do-save-draft
  |=  [root=path d=draft:uc]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ::  the send caps, checked at SAVE time. A draft that cannot be sent
  ::  is a message the user loses at the last moment, and the whole
  ::  point of a draft is that nothing is lost.
  ?.  (draft-ok:uc d)  (reject root 'bad draft')
  ;<  ~  bind:m  (ensure-dir (draft-dir root))
  ;<  ds=(list draft:uc)  bind:m  (read-drafts root)
  ::  the store bound counts only a draft we do not already hold, so
  ::  re-saving an existing draft is never refused for capacity.
  ?.  ?|  (lien ds |=(o=draft:uc =(id.o id.d)))
          (lth (lent ds) max-drafts:uc)
      ==
    (reject root 'too many drafts')
  ;<  ~  bind:m  (put-file (draft-rail root id.d) [/urmail %draft] d)
  ;<  ~  bind:m  (note root 'save-draft' & (scot %uv id.d))
  (pure:m |)
::
++  do-delete-draft
  |=  [root=path i=@uv]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  ~  bind:m  (cull-if-there (draft-rail root i))
  ;<  ~  bind:m  (note root 'delete-draft' & (scot %uv i))
  (pure:m |)
::
::  +do-send-draft: SIGN IT NOW, THEN DELETE IT.
::
::    The draft becomes a message at this instant and not before: the
::    signature is made over the fields as they stand, by +do-send,
::    exactly as a compose is. There is no path by which a draft is
::    signed at save time and no path by which a stored draft carries a
::    signature.
::
::    DELETION IS GATED ON THE SEND ACTUALLY HAVING HAPPENED. +do-send
::    answers whether it sent; a refused send - a body over the cap, an
::    unknown prev, a full blob store - leaves the draft exactly where
::    it was. Deleting unconditionally would destroy the composed
::    message at the one moment the ship is telling the user it will not
::    carry it, which is the failure the web route's cap checks were
::    added to prevent, arriving through a different door.
::
++  do-send-draft
  |=  [root=path i=@uv]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  d=(unit draft:uc)  bind:m  (read-draft root i)
  ?~  d  (reject root 'unknown draft')
  ;<  sent=?  bind:m  (do-send root to.u.d subj.u.d body.u.d '' prev.u.d ~ ~)
  ?.  sent
    ::  +do-send has already written its own reason to /tr/last. The
    ::  draft survives.
    (pure:m |)
  ;<  ~  bind:m  (cull-if-there (draft-rail root i))
  ;<  ~  bind:m  (note root 'send-draft' & (scot %uv i))
  ::  %.n: +do-send bumped the beacon itself, before its fan-out.
  (pure:m |)
::
::  ── filters ─────────────────────────────────────────────────────────
::
++  do-save-rule
  |=  [root=path r=rule:uc]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ::  a rule with no condition matches every delivered chain, and with
  ::  `archive` set would empty the inbox permanently and silently.
  ?.  (rule-ok:uc r)  (reject root 'bad rule')
  ;<  ~  bind:m  (ensure-dir (rule-dir root))
  ;<  rs=(list rule:uc)  bind:m  (read-rules root)
  ::  every rule is evaluated against every delivered chain, ON THE
  ::  WRITER, which is the ship's single serialisation point for mail.
  ?.  ?|  (lien rs |=(o=rule:uc =(id.o id.r)))
          (lth (lent rs) max-rules:uc)
      ==
    (reject root 'too many rules')
  ;<  ~  bind:m  (put-file (rule-rail root id.r) [/urmail %rule] r)
  ;<  ~  bind:m  (note root 'save-rule' & (scot %uv id.r))
  (pure:m |)
::
++  do-delete-rule
  |=  [root=path i=@uv]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  ~  bind:m  (cull-if-there (rule-rail root i))
  ;<  ~  bind:m  (note root 'delete-rule' & (scot %uv i))
  (pure:m |)
::
::  ── mailing lists ───────────────────────────────────────────────────
::
::  +do-save-list: create or OVERWRITE one list. That is the whole verb.
::
::    Create, add a member, drop one, rename by re-saving under a new
::    name and copy the membership off a message are all this, because a
::    list is a name and a set of ships and there is nothing else in it.
::    No tracking, no merge, no "sync from" - the client sends the set it
::    wants and this stores exactly that.
::
::    THE NAME IS RE-CHECKED HERE, not only at the route. It becomes a
::    path segment, this arm is reachable from a dojo poke as well as
::    from the HTTP surface, and a name that is not a knot would be a
::    write to a road nobody meant. Belt to the route's braces.
::
::    OUR OWN SHIP IS REFUSED AS A MEMBER, again at both ends. A list
::    naming you sends you your own mail on every send that expands it,
::    and refusing the shape once is one rule instead of one rule at
::    every place that expands a list.
::
++  do-save-list
  |=  [root=path name=@t members=(set @p)]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ?.  (list-name-ok:uw name)  (reject root 'bad list name')
  ;<  our=@p  bind:m  bowl-our
  ?:  (~(has in members) our)  (reject root 'a list may not hold your own ship')
  ::  a list larger than a send may carry is a list that cannot be used.
  ?.  (lte ~(wyt in members) max-to:uc)  (reject root 'too many members')
  ;<  ~  bind:m  (ensure-dir (list-dir root))
  ;<  ls=(list [name=@t members=(set @p)])  bind:m  (read-lists root)
  ::  the store bound counts only a list we do not already hold, so
  ::  overwriting an existing list is never refused for capacity - which
  ::  is the whole copy-from-a-message flow at the cap.
  ?.  ?|  (lien ls |=(o=[name=@t members=(set @p)] =(name.o name)))
          (lth (lent ls) max-lists:uc)
      ==
    (reject root 'too many lists')
  ;<  ~  bind:m
    (put-file (list-rail root name) [/urmail %list] `mail-list:uc`[%0 members])
  ;<  ~  bind:m  (note root 'save-list' & name)
  (pure:m |)
::
++  do-delete-list
  |=  [root=path name=@t]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ?.  (list-name-ok:uw name)  (reject root 'bad list name')
  ;<  ~  bind:m  (cull-if-there (list-rail root name))
  ;<  ~  bind:m  (note root 'delete-list' & name)
  (pure:m |)
::
::  +file-arrival: what happens to a thread's LOCAL state when mail
::  lands in it. Un-archive, then the filters, in ONE rewrite of meta.
::
::    ORDER IS THE WHOLE ARGUMENT, and it runs AFTER verification and
::    after the chain is stored - never before. A filter that ran first
::    could decide what gets stored, and an attacker who learns your
::    rules could then aim a forgery at one and have the evidence of it
::    quietly put somewhere you do not look. Here the chain is already
::    on disk with every verdict already set, and all a rule can reach
::    is a label and a flag.
::
::    UN-ARCHIVE ON NEW MAIL. Without it, archiving a thread would make
::    every later message in it vanish silently, which is mail loss
::    wearing the costume of a feature. Only actual new content
::    un-archives: `wrote` is +sync-slots' answer, so a redelivery of a
::    chain we already hold - which any ship may poke at us, since
::    delivery is public - changes nothing.
::
::    A MATCHING RULE'S ARCHIVE STILL WINS for the mail that just
::    arrived, because "skip the inbox" is a standing instruction about
::    exactly this delivery. So the un-archive is the DEFAULT that
::    rules are then applied over, not something applied after them.
::
++  file-arrival
  |=  [root=path t=thread-id:uc c=chain:uc wrote=?]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  rs=(list rule:uc)  bind:m  (read-rules root)
  =/  got  (apply-rules:uc rs c)
  ;<  mt=meta:uc  bind:m  (read-meta root t)
  =/  arch=?  ?:(wrote archive.got |(archived.mt archive.got))
  =/  want=(set @tas)  (~(uni in labels.mt) add.got)
  ::  the label bound refuses the ADDITION, never the delivery: a rule
  ::  that would push a thread past the cap simply does not add. Nacking
  ::  the chain instead would turn a rule the user wrote into a way for
  ::  a sender to get their own mail rejected.
  =/  ls=(set @tas)  ?:((lte ~(wyt in want) max-labels:uc) want labels.mt)
  ?:  &(=(arch archived.mt) =(ls labels.mt))  (pure:m ~)
  ;<  ~  bind:m
    (put-file (meta-rail root t) [/urmail %meta] mt(archived arch, labels ls))
  (note root 'file-arrival' & (scot %uv t))
::
::  +do-delete: the escape hatch. Every capacity limit here is otherwise
::  permanent: a thread pinned at the distinct-id cap has no other remedy.
::  Culling the thread dir takes its messages, its verdicts and its read
::  marks with it, so deleting actually reclaims capacity.
::
++  do-delete
  |=  [root=path t=thread-id:uc]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  road=road:tarball  [%& %| (tdir root t)]
  ;<  ~  bind:m  (cull-if-there road)
  ;<  ix=mail-idx:uc  bind:m  (read-idx root)
  ;<  ~  bind:m
    %^  put-file  [%& %& (mail-dir root) %idx]  [/urmail %idx]
    ix(inbox (skip inbox.ix |=(o=thread-id:uc =(o t))))
  ;<  ~  bind:m  (note root 'delete-thread' & (scot %uv t))
  (pure:m &)
::
::  +cull-if-there: cull a road that may not exist, soft. Its own arm rather
::  than a ?: at the call site, because the two branches would be fibers of
::  different result types and cannot be unified.
::
++  cull-if-there
  |=  road=road:tarball
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  ex=?  bind:m  (peek-exists:io road)
  ?.  ex  (pure:m ~)
  ;<  *  bind:m  (cull-soft:io road)
  (pure:m ~)
::
::  +deliver: accept a chain from any ship.
::
::    The courier is deliberately not checked against the participants.
::    Anyone may hand us a chain; the signatures are the authority. That is
::    what makes chains portable and what separates this from a chat app.
::
::    Order is load-bearing: cap, then VERIFY, then resolve identity, then
::    merge, then store. Nothing is written before every signature in the
::    incoming chain has a verdict.
::
++  deliver
  |=  [root=path c=chain:uc]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ?:  =(~ c)  (pure:m |)
  ::  reject rather than truncate. A chain that violates a limit is not
  ::  partially trustworthy. This governs the INCOMING poke only; once
  ::  merged, excess capacity is a different question with a different
  ::  answer, and +prune sheds there rather than rejecting.
  ?.  (fits-length:uc c max-chain:uc)      (reject root 'chain too long')
  ?.  (fits-bodies:uc c max-body:uc)       (reject root 'body too long')
  ?.  (fits-subjects:uc c max-subj:uc)     (reject root 'subject too long')
  ?.  (fits-recipients:uc c max-to:uc)     (reject root 'too many recipients')
  ::  a delivered chain carries attachment METADATA and never bytes, so
  ::  this bounds what a hostile peer can make us store per message and
  ::  what it can later make us try to fetch. Rejected, not truncated:
  ::  the metadata is inside the signature, so trimming it would forge.
  ?.  (fits-attachments:uc c max-attach:uc)  (reject root 'too many attachments')
  ::  body-mime is a signed field a recipient cannot repair, so it is
  ::  bounded here where the chain is still refusable whole.
  ?.  (fits-body-mimes:uc c max-mime:uc)   (reject root 'bad body mime')
  ::  DEPTH, refused before verification because it is the cheapest
  ::  refusal and the walk is bounded. A message is stored under its
  ::  ancestry and every peek of the mail tree rebuilds those keys, so
  ::  depth is quadratic and is NOT off the read path - see +max-depth.
  ::  This one bounds a single poke; the merged check below is what
  ::  actually bounds what ends up on disk.
  ?.  (fits-depth:uc c max-depth:uc)       (reject root 'chain too deep')
  ::  DISTINCT SIGNERS, and this one is refused HERE - above the two
  ::  binds below - because those two binds are the cost it bounds.
  ::  +key-map does one scry to /sys/scry per distinct [ship life], so
  ::  an unbounded signer set turned one remote poke into up to
  ::  max-chain internal round trips on the writer, which is the ship's
  ::  single serialisation point for mail; +verify-chain then pays an
  ::  ed25519 verify per message on top, and a forged signature costs
  ::  exactly what a real one does. Every cap above is cheaper than the
  ::  work it protects, and this is the only one that protects work
  ::  measured in round trips rather than in bytes. See +max-signers for
  ::  why the number is 128 and for the per-source rate budget this
  ::  deliberately does not attempt.
  ?.  (fits-signers:uc c max-signers:uc)   (reject root 'too many signers')
  ;<  fake=?  bind:m  fake-ship
  ;<  keys=(map [ship @ud] (unit pass))  bind:m
    (key-map fake ~(tap in (signers:uc c)) ~)
  =/  vs=(list [[msg-id:uc @ux] verdict:uc])  (verify-chain:uc keys c)
  ;<  loaded=(map thread-id:uc (map path stored-msg:uc))  bind:m  (read-threads root)
  ::  thread identity is never (root:uc c). `c` is attacker-controlled and
  ::  unsorted, so the head-as-supplied is not a stable identity.
  ::  +thread-key crashes on a first-contact chain with no unique prev=~
  ::  root, which is hostile input reaching the writer, so: mule.
  =/  rk  (mule |.((thread-key:uc (threads-of loaded) c)))
  ?:  ?=(%| -.rk)  (reject root 'no unique root')
  =/  rid=thread-id:uc  p.rk
  =/  ss=(map path stored-msg:uc)  (~(gut by loaded) rid ~)
  =/  new=chain:uc  (merge:uc (chain-of ss) c)
  ::  a genuine state-capacity limit, and it stays a reject: shedding a
  ::  distinct non-root id would orphan the prev pointers of later
  ::  messages. The cost is recorded in the spec and not hidden.
  ?.  (lte (distinct-ids:uc new) max-chain:uc)
    (reject root 'too many messages')
  ::  and the merged depth, since two chains each inside the cap can
  ::  compose past it. Same reasoning as the distinct-id cap directly
  ::  above, including the cost: a thread genuinely deeper than
  ::  max-depth accepts nothing further.
  ?.  (fits-depth:uc new max-depth:uc)
    (reject root 'chain too deep')
  ::  an EXISTING thread always accepts - a reply must never be refused
  ::  because some unrelated thread filled the cap. Only a brand-new
  ::  thread id is capped.
  ?.  ?|((~(has by loaded) rid) (lth ~(wyt by loaded) max-threads:uc))
    (reject root 'too many threads')
  ::  fold this poke's verdicts into the stored ones BEFORE pruning:
  ::  +prune needs a verdict for every message in `new`, including ones
  ::  stored by an earlier poke that this one did not carry.
  =/  vs2  (freeze:uc (verdicts-of ss) vs)
  =/  pruned=chain:uc  (prune:uc new vs2 max-copies:uc)
  ;<  ~  bind:m  (ensure-thread root rid)
  ;<  wrote=?  bind:m  (sync-slots root rid ss (want-slots pruned vs2))
  ;<  fresh=?  bind:m  (mark-direct root rid)
  ::  A REDELIVERY THAT WROTE NOTHING CHANGES NOTHING, and must not
  ::  look like it did. Delivery is granted to the `public` usergroup,
  ::  so any ship may re-poke a chain we already hold; without this it
  ::  would reorder the inbox and move the beacon every time, for free.
  =/  changed=?  ?|(wrote fresh)
  ?.  changed
    ;<  ~  bind:m  (note root 'deliver' & 'no change')
    (pure:m |)
  ;<  ~  bind:m  (touch-idx root rid)
  ::  LOCAL FILING, AFTER STORAGE AND AFTER EVERY VERDICT IS SET. New
  ::  mail un-archives the thread; then the user's filters may add
  ::  labels and archive it again. Nothing here can suppress a message,
  ::  because by this point the chain is already on disk with its
  ::  verdicts and a $rule has no field that reaches it. See
  ::  +file-arrival.
  ;<  ~  bind:m  (file-arrival root rid c wrote)
  ;<  ~  bind:m  (note root 'deliver' & (scot %uv rid))
  (pure:m &)
::
::  ── blobs ───────────────────────────────────────────────────────────
::
::  +store-files: put each attached file in the store and publish it.
::
++  store-files
  |=  [root=path fs=(list file:uc)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  fs  (pure:m ~)
  ;<  ~  bind:m  (store-blob root octs.i.fs)
  ::  recursion by ARM NAME. A $ with arguments inside a ;< continuation
  ::  cannot find the trap.
  (store-files root t.fs)
::
::  +store-blob: write one blob's bytes and bind them in the farm.
::
::    GATED ON NOT ALREADY HOLDING IT, and that gate is what keeps the
::    fetch path simple. gall assigns a spur's case itself
::    (+grow:of-farm in sys/lull): an unbound, never-culled spur takes
::    case 1, and every later %grow at the same spur takes the next key
::    up. A remote fetcher cannot discover a case - gall's %w care, the
::    only read that answers one, is gated on `=(our ship)` - so it has
::    to construct the path from the hash alone and therefore has to be
::    able to assume case 1. Growing only when the grub is absent means
::    a re-send of a file we still hold, or a re-fetch of one, does not
::    bump the case. See +keen-blob for the one thing that does.
::
++  store-blob
  |=  [root=path =octs]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  h=@uv  (blob-hash:uc octs)
  ;<  ex=?  bind:m  (peek-exists:io (blob-rail root h))
  ?:  ex  (pure:m ~)
  ;<  now=@da  bind:m  bowl-now
  ;<  ~  bind:m  (put-file (blob-rail root h) [/urmail %blob] [%1 octs now])
  (publish-blob h octs |)
::
::  +unheld-files: the files in a send we do not already hold.
::
++  unheld-files
  |=  [root=path fs=(list file:uc)]
  =/  m  (fiber:fiber:nexus ,(list file:uc))
  ^-  form:m
  ?~  fs  (pure:m ~)
  ;<  ex=?  bind:m  (peek-exists:io (blob-rail root (blob-hash:uc octs.i.fs)))
  ;<  rest=(list file:uc)  bind:m  (unheld-files root t.fs)
  (pure:m ?:(ex rest [i.fs rest]))
::
::  +room-for: can the store take all of these? Sheds if it has to.
::
++  room-for
  |=  [root=path fs=(list file:uc)]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ?~  fs  (pure:m &)
  ;<  ok=?  bind:m  (make-room root p.octs.i.fs)
  ?.  ok  (pure:m |)
  (room-for root t.fs)
::
::  +publish-blob: bind the bytes in gall's remote-scry farm.
::
::    This is the whole permission story for a public blob. A %keen is
::    the kernel scry farm and the only permissionless channel on this
::    platform: peeks and keeps are weir-gated, and a cross-ship peek
::    between un-granted peers HANGS rather than failing, while a keen at
::    a bound spur is answered by the publisher's kernel without waking
::    %grubbery at all. So "the hash is the authority, the courier is
::    irrelevant" is not a policy urmail enforces - it is what the
::    transport already is.
::
::    gall's farm is a FLAT namespace shared by every nexus in this yoke
::    (lattice grows at /pub/page/...), hence the /urmail prefix.
::
++  publish-blob
  |=  [h=@uv =octs force=?]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ::  NOTHING MAY GROW A SPUR IT HAS NOT ESTABLISHED IS UNBOUND. gall
  ::  assigns las+1 on a non-empty fan, so a second %grow at a bound
  ::  spur raises the case a peer has to probe for, and cases only ever
  ::  go up. This check is the structural guard; +do-publish's own
  ::  visibility gate is belt to these braces.
  ::
  ::  `force` exists for exactly one caller. A restrict CULLED the spur,
  ::  and gall keeps the emptied plot, so %gt still lists a spur that no
  ::  longer answers - the one case where "listed" and "bound" disagree.
  ::  +do-publish has already established the blob is %restricted, which
  ::  is the record that says the cull happened, and so may grow anyway.
  ?:  force  (grow:io (blob-spur:uc h) [blob-page-mark:uc octs])
  ;<  bound=?  bind:m  (farm-has (blob-spur:uc h))
  ?:  bound  (pure:m ~)
  (grow:io (blob-spur:uc h) [blob-page-mark:uc octs])
::
::  +farm-has: is this spur listed in our own remote-scry farm?
::
::    %gt is the TOTAL read - it lists every bound spur strictly below
::    the path it is given and never blocks for a live agent - which is
::    why it is asked rather than %gw, whose partial read crashes on a
::    spur it does not hold and cannot be softened from inside the
::    event. The scry runs through /sys/scry with the agent's live bowl,
::    which is what supplies the `now` case gall demands for %t.
::
++  farm-has
  |=  spur=path
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  n=noun  bind:m
    (typed-scry:io noun %noun ~[%gt mesa-agent %$ %'1' %urmail %blob])
  =/  res  (mule |.(;;((list path) n)))
  ::  a read we could not understand must not be taken as "absent",
  ::  because "absent" is the branch that grows and raises a case.
  ?:  ?=(%| -.res)  (pure:m &)
  (pure:m (lien p.res |=(x=path =(x spur))))
::
::  +republish-all: re-bind every public blob the farm has lost.
::
::    The farm lives OUTSIDE the nexus tree and outside on-load, so no
::    %fall row protects it. If a binding is ever lost - a nuked agent,
::    a rebuilt yoke - the bytes sit intact in the tree while every peer
::    silently reports a miss. This runs at writer rise and re-binds
::    exactly what is missing.
::
::    Gated on the farm listing, so it is a no-op in the ordinary case
::    and can never raise a case by running again. A %restricted blob is
::    skipped: it is withdrawn on purpose.
::
++  republish-all
  |=  root=path
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ::  no ?~ early-return on `held`: it would narrow the face to a lest,
  ::  and the ;< continuations below are gates whose bodies mull against
  ::  BOTH branches of that narrowing, so the null case then fails to
  ::  nest. The empty case costs one scry and is not worth the shape.
  ;<  held=(list blob-row:uc)  bind:m  (list-blobs root)
  ;<  ix=blob-index:uc  bind:m  (read-blobvis root)
  ;<  n=noun  bind:m
    (typed-scry:io noun %noun ~[%gt mesa-agent %$ %'1' %urmail %blob])
  =/  res  (mule |.(;;((list path) n)))
  ?:  ?=(%| -.res)  (pure:m ~)
  =/  bound=(set path)  (~(gas in *(set path)) p.res)
  %+  republish-loop  root
  %+  skip  held
  |=  r=blob-row:uc
  ^-  ?
  ?:  (~(has in bound) (blob-spur:uc h.r))  &
  =/  v=blob-vis:uc  (~(gut by vis.ix) h.r [%public ~])
  ?=(%restricted -.v)
::
++  republish-loop
  |=  [root=path rs=(list blob-row:uc)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  rs  (pure:m ~)
  ;<  o=(unit octs)  bind:m  (read-blob root h.i.rs)
  ;<  ~  bind:m
    ?~  o  (pure:m ~)
    ;<  ~  bind:m  (grow:io (blob-spur:uc h.i.rs) [blob-page-mark:uc u.o])
    (trace:io ~[leaf+"urmail: republished blob {<h.i.rs>}"])
  (republish-loop root t.rs)
::
::  ── the blob fetch ──────────────────────────────────────────────────
::
::  +mesa-agent: the gall agent whose scry farm holds the bindings.
::  urmail is a NEXUS inside %grubbery, so the spurs live under
::  %grubbery's yoke, not under an agent named %urmail. A fiber cannot
::  read its own `dap`, so this is a constant and it must track the
::  desk's agent name.
::
++  mesa-agent  ^-(@ta %grubbery)
::
::  +blob-timeout: how long ONE keen waits. keen:io carries no deadline
::  of its own - ames holds an unanswerable request forever - so this is
::  the only bound. A namespace read is answered from a cache or from the
::  publisher's kernel with no agent in the loop, so a keen that is slow
::  is a keen that is not coming.
::
++  blob-timeout  ^-(@dr ~s10)
::
::  +max-case-probe: how far up the case ladder to look.
::
::    Case 1 is the answer for a blob the publisher grew once and never
::    culled, which is every ordinary blob (+store-blob only grows when
::    the grub is absent). The ladder exists for the one operation that
::    burns a case: %restrict-blob culls the spur, and gall's +ap-cull
::    parks the culled case as a high-water mark so nothing ever re-binds
::    at or below it. A blob restricted and later re-published therefore
::    answers at case 2, not 1, permanently. Probing a few cases up is
::    the fetcher's whole defence against that, and it costs one timeout
::    per miss, paid only by a blob that has actually been restricted.
::
++  max-case-probe  ^-(@ud 3)
::
::  +keen-blob: a peer's blob bytes, ~ on any failure.
::
++  keen-blob
  |=  [who=ship h=@uv case=@ud]
  =/  m  (fiber:fiber:nexus ,(unit octs))
  ^-  form:m
  ?:  (gth case max-case-probe)  (pure:m ~)
  ;<  got=(unit octs)  bind:m  (keen-blob-at who h case)
  ?^  got  (pure:m got)
  (keen-blob who h +(case))
::
::  +keen-blob-at: one %keen, at one case.
::
::    ~ on every failure: our own deadline, an unbound spur, a mark we do
::    not understand, a noun that is not octs. On our deadline firing,
::    %yawn the request - ames otherwise holds an unanswerable keen
::    forever, one parked request per miss.
::
++  keen-blob-at
  |=  [who=ship h=@uv case=@ud]
  =/  m  (fiber:fiber:nexus ,(unit octs))
  ^-  form:m
  =/  pax=path  (blob-keen-path:uc mesa-agent h case)
  ;<  res=(unit (unit page))  bind:m
    ((deadline ,(unit page)) blob-timeout (keen:io who pax))
  ?~  res
    ;<  ~  bind:m  (yawn:io who pax)
    (pure:m ~)
  ?~  u.res  (pure:m ~)
  =/  pag=page  u.u.res
  ?.  =(blob-page-mark:uc p.pag)  (pure:m ~)
  =/  got  (mule |.(;;(octs q.pag)))
  ?:(?=(%| -.got) (pure:m ~) (pure:m `p.got))
::
::  +do-fetch-blob: fetch one attachment's bytes on demand.
::
::    Receiving a chain stores it immediately; bytes are never pushed.
::    This is the pull, and it is deliberately an explicit action rather
::    than something delivery triggers: a chain from a stranger naming a
::    hundred attachments must not make this ship go fetch them.
::
::    THE ACCEPTANCE RULE, and the only thing that matters here: a blob
::    whose contents do not hash to the address it was fetched under is
::    DISCARDED. Not stored, not shown, not held against the sender.
::    `who` is a hint about where to look and nothing more - any ship
::    holding the bytes may serve them, and the hash proves them.
::
++  do-fetch-blob
  |=  [root=path h=@uv who=ship]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  have=(unit octs)  bind:m  (read-blob root h)
  ?^  have
    ;<  ~  bind:m  (note root 'fetch-blob' & 'already held')
    (pure:m |)
  ;<  ~  bind:m  (ensure-dir (weld root /fetch))
  ::  the id is derived from [hash ship], so asking twice for the same
  ::  blob from the same peer overwrites one request rather than
  ::  spawning a second fiber to race the first.
  =/  id=@ta  (scot %uv (sham [h who]))
  ;<  ~  bind:m
    (put-file [%& %& (weld root /fetch) id] [/urmail %fetchreq] [%0 h who])
  ::  %.n, AND +take-blob ANSWERS %.n TOO: neither queueing the fetch
  ::  nor the bytes arriving moves /beacon/rev, so nothing on this path
  ::  ever bumps it. A queued request is not something any reader
  ::  renders, and an arrival is not message content either - no
  ::  message appeared, none changed, no listing row reads differently.
  ::  The reason it must stay that way is that the ANSWER COMES FROM A
  ::  PEER: a bump here would let whoever serves the bytes decide when
  ::  this ship refetches its whole mailbox, at O(total stored
  ::  messages) per open tab. The waiting tab polls GET /api/blob
  ::  instead, which is a route it was going to call anyway. See
  ::  +take-blob for the same argument at the other end.
  ;<  ~  bind:m  (note root 'fetch-blob' & 'queued')
  (pure:m |)
::
::  +run-fetch: the ephemeral fetch fiber. Runs OFF the writer.
::
::    Its state is its own grub, so it needs nothing passed in. It keens
::    (probing cases, each bounded and yawned), hands the outcome to the
::    writer and ends. It writes nothing: the writer is still the only
::    thing that mutates the tree, including culling this request.
::
::    Its road to the writer is ABSOLUTE, derived from +get-here-abs.
::    This fiber lives at a fixed depth today, but a depth-relative road
::    called from the wrong depth climbs past the nexus root and crashes
::    the fiber, and there is no reason to leave that hostage to a later
::    move of the path.
::
++  run-fetch
  |=  id=@ta
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  here=rail:tarball  bind:m  get-here-abs:io
  =/  root=path  (snip path.here)
  ;<  rq=fetch-req:uc  bind:m  (get-state-as:io ,fetch-req:uc)
  ;<  got=(unit octs)  bind:m  (keen-blob from.rq hash.rq 1)
  %+  poke:io  [%& %& root %'main.sig']
  [[/urmail %blob-in] [%0 id hash.rq got]]
::
::  +take-blob: the writer's half of a fetch. Local only.
::
::    THE ACCEPTANCE RULE, and the only thing that matters here: a blob
::    whose contents do not hash to the address it was fetched under is
::    DISCARDED. Not stored, not shown, not held against the sender.
::    The peer named in the request is a hint about where to look and
::    nothing more - any ship holding the bytes may serve them, and the
::    hash proves them.
::
::    The request grub is culled FIRST and unconditionally, so a miss
::    leaves nothing behind to respawn on the next reload.
::
++  take-blob
  |=  [root=path b=blob-in:uc]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  ~  bind:m  (cull-if-there [%& %& (weld root /fetch) id.b])
  ?~  res.b  (reject root 'blob fetch missed')
  ::  bound what a hostile publisher can hand back before we measure it
  ?.  (lte p.u.res.b max-blob:uc)
    (reject root 'blob too large')
  ?.  (gte p.u.res.b (met 3 q.u.res.b))
    (reject root 'blob malformed')
  ?.  (blob-ok:uc u.res.b hash.b)
    (reject root 'blob hash mismatch')
  ;<  room=?  bind:m  (make-room root p.u.res.b)
  ?.  room
    (reject root 'blob store full')
  ;<  now=@da  bind:m  bowl-now
  ;<  ~  bind:m
    (put-file (blob-rail root hash.b) [/urmail %blob] [%1 u.res.b now])
  ::  we hold the bytes now, so we can serve them: a blob request is
  ::  answerable by ANYONE holding the bytes, not only the author,
  ::  exactly as a chain is forwardable by anyone. That is also why
  ::  restriction is unpublishing and not revocation - see $blob-vis.
  ;<  ~  bind:m  (publish-blob hash.b u.res.b |)
  ;<  ~  bind:m  (note root 'fetch-blob' & (scot %uv hash.b))
  ::  %.n, AND THE BEACON IS THE REASON. +apply's answer is what moves
  ::  /beacon/rev, and a blob arrival is not message content: no
  ::  message appeared, none changed, and no listing row reads any
  ::  differently for it. Bumping would cost every open tab a full
  ::  inbox listing - which is O(total stored messages) - plus a thread
  ::  refetch, for bytes only the tab that asked for them is waiting
  ::  on, and that tab is already retrying GET /api/blob. It is the
  ::  same argument that keeps a read-mark off the beacon, and the same
  ::  amplification: %fetch-blob is a local action, but the ANSWER
  ::  arrives from a peer, so a bump here would let whoever serves the
  ::  bytes decide when this ship refetches its whole mailbox.
  ::
  ::  The store did change, and nothing is lost by saying so quietly:
  ::  /tr/last records the arrival above, and the blob is served the
  ::  moment the next request asks for it.
  (pure:m |)
::
::  ── per-attachment permission ───────────────────────────────────────
::
::  +do-restrict: withdraw a blob from the permissionless namespace.
::
::    A restricted blob is culled out of the scry farm, which is the only
::    thing that actually stops an un-granted ship reading it: the farm
::    has no weir on it at all. What remains is the grubbery peek road,
::    which is deny-by-default for foreign ships and opens only through a
::    usergroup, so the named ships are granted by adding this blob's own
::    road to a group at /urmail/<hash>.
::
::    THE GROUP IS NOT CREATED HERE, and that is a platform limit rather
::    than a choice. $registry-action carries no group-lifecycle op, so a
::    nexus can only grant into a group that already exists; laying the
::    group's own grubs by hand would mean a +make under
::    /sys/ames/usergroups, and a veto there arrives as a %fail that
::    crashes this writer - the one thing it must never do, because
::    +rise-wait would then eat the next legitimate poke. So the grant is
::    attempted and skipped quietly when the group is absent.
::
++  do-restrict
  |=  [root=path h=@uv ships=(set ship)]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  have=(unit octs)  bind:m  (read-blob root h)
  ?~  have  (reject root 'no such blob')
  ;<  ix=blob-index:uc  bind:m  (read-blobvis root)
  =/  cur=blob-vis:uc  (~(gut by vis.ix) h [%public ~])
  ::  cull ONLY from public. cull-farm is not idempotent: +farm-top's %gw
  ::  lookup crashes on the emptied plot a previous cull left.
  ;<  ~  bind:m  (unpublish-if-public cur h)
  ;<  ~  bind:m
    %^  put-file  (vis-rail root)  [/urmail %blobvis]
    ix(vis (~(put by vis.ix) h [%restricted ships]))
  ;<  ~  bind:m  (grant-blob root h)
  ;<  ~  bind:m  (note root 'restrict-blob' & (scot %uv h))
  (pure:m &)
::
++  unpublish-if-public
  |=  [cur=blob-vis:uc h=@uv]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?.  ?=(%public -.cur)  (pure:m ~)
  (cull-farm:io (blob-spur:uc h))
::
::  +do-publish: put a restricted blob back in the permissionless
::  namespace. It re-binds at a HIGHER case than 1, because the cull
::  parked a high-water mark; +max-case-probe is what covers that.
::
++  do-publish
  |=  [root=path h=@uv]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  have=(unit octs)  bind:m  (read-blob root h)
  ?~  have  (reject root 'no such blob')
  ;<  ix=blob-index:uc  bind:m  (read-blobvis root)
  ::  GATED, and this gate is load-bearing rather than tidy. Publishing
  ::  an already-public blob would %grow an already-bound spur, and
  ::  +grow:of-farm assigns las+1 on a non-empty fan, so an
  ::  idempotent-LOOKING "make public" pushes the binding one case
  ::  higher every time it is pressed. Three presses put it past
  ::  +max-case-probe and the attachment is unfetchable by every peer,
  ::  forever, with no error - the fetcher just reports a miss. Cases
  ::  only ever go up, so there is no recovery. Nothing may %grow a spur
  ::  it has not first established is unbound.
  =/  cur=blob-vis:uc  (~(gut by vis.ix) h [%public ~])
  ?.  ?=(%restricted -.cur)
    ;<  ~  bind:m  (note root 'publish-blob' & 'already public')
    (pure:m |)
  ;<  ~  bind:m
    %^  put-file  (vis-rail root)  [/urmail %blobvis]
    ix(vis (~(del by vis.ix) h))
  ;<  ~  bind:m  (publish-blob h u.have &)
  ;<  ~  bind:m  (note root 'publish-blob' & (scot %uv h))
  (pure:m &)
::
::  +grant-blob: give the named ships a peek road on one blob.
::
::    Per-attachment permission, expressed as one usergroup per content
::    address. %how replaces this prefix's roads in THAT group wholesale,
::    so a group per blob is also what keeps two restricted attachments
::    from overwriting each other's grant.
::
++  grant-blob
  |=  [root=path h=@uv]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  grp=path  /urmail/[(scot %uv h)]
  =/  gdir=path  (weld /sys/ames/usergroups/urmail /[(cat 3 (scot %uv h) '.grp')])
  ;<  ok=?  bind:m  (peek-exists:io [%& %& gdir %'who.ships'])
  ?.  ok
    %-  trace:io
    :_  ~
    :-  %leaf
    "urmail: no usergroup at {<grp>}, blob {<h>} is withdrawn but ungranted"
  ;<  ~  bind:m  (reg-register-at:io [root %'main.sig'])
  %+  reg-how:io  grp
  [make=~ poke=~ peek=(sy ~[(blob-rail root h)])]
::
::  ── slot writing ────────────────────────────────────────────────────
::
::  +write-msg: one copy, at its own node in the tree.
::
::    `place` is the message's ancestry, root first, and it becomes the
::    directories the copy is filed under. The node directories are made
::    shallowest-first because a directory needs its parent; a reply's
::    ancestors are already there, and only the message's own node is
::    actually new.
::
++  write-msg
  |=  [root=path t=thread-id:uc place=(list msg-id:uc) mg=msg:uc v=verdict:uc]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  dir=path  (mdir root t)
  =/  pax=path  (node-dir place)
  ;<  ~  bind:m  (ensure-nodes dir (prefixes:uc pax))
  %^  put-file  [%& %& (weld dir pax) (slot (id:uc unsigned.mg) sig.mg)]
    [/urmail %msg]
  [%2 mg v]
::
::  +want-slots: where every copy of a chain BELONGS in the tree.
::
::    One ancestor-map over the whole chain rather than a walk per
::    message, then each copy's key is its message's ancestry as
::    directories plus its own slot. Two copies of one id land at one
::    node with two leaves; two replies to one message land as two
::    sibling directories.
::
++  want-slots
  |=  [c=chain:uc vs=(map [msg-id:uc @ux] verdict:uc)]
  ^-  (map path stored-msg:uc)
  =/  am=(map msg-id:uc (list msg-id:uc))  (ancestor-map:uc c)
  %-  ~(gas by *(map path stored-msg:uc))
  %+  turn  c
  |=  mg=msg:uc
  ^-  [path stored-msg:uc]
  =/  i=msg-id:uc  (id:uc unsigned.mg)
  :-  (snoc (node-dir (~(gut by am) i ~[i])) (slot i sig.mg))
  [%2 mg (~(gut by vs) [i sig.mg] %unverified)]
::
::  +sync-slots: make the thread's grubs equal `want`.
::
::    Cull what +prune shed, write what is new or whose verdict moved,
::    leave the rest alone. Redelivering a chain we already hold writes
::    nothing at all, and nothing here is a peek.
::
::    Two kinds of cull, because the layout has two kinds of thing. A
::    NODE DIRECTORY the tree no longer wants goes whole - that is the
::    case where a message's ancestry changed, which happens when an
::    orphan is finally joined to its parent, and it takes the orphan's
::    own descendants with it. Then any remaining copy FILE that is not
::    wanted goes on its own, which is what +prune's shedding looks like
::    and what the pre-tree migration looks like.
::
::    Only the MINIMAL stale directories are culled, and a copy already
::    inside one of them is not culled again: a cull of a road that a
::    parent cull already removed is at best waste.
::
::    WRITE FIRST, CULL SECOND, AND THAT ORDER IS THE WHOLE SAFETY
::    ARGUMENT. Every step here is its own event, so any prefix of them
::    is a state the ship can be interrupted in - by a crash, or by the
::    |suspend that every deploy performs. Culling first meant a
::    re-placement spent one event per copy with NO copy of the message
::    on disk anywhere, and a migration re-places every message in the
::    thread at once: the whole thread, signatures included, existed
::    nowhere for that window. Writing first makes the transient state a
::    DUPLICATE instead of a HOLE, and a duplicate is invisible - the
::    old and new paths hold the same grub, and +chain-of dedupes on
::    [id sig] before anything reads it.
::
::    Culling after writing cannot remove what was just written, and
::    that follows from an arm above rather than from care here. `wn` is
::    +node-dirs over `want`, and +prefixes yields EVERY non-empty
::    prefix, so `wn` is prefix-closed. A written path is in `want`, so
::    each of its directories is in `wn`; a created directory is in `wn`
::    by construction. `stale` is node-dirs(have) MINUS `wn`, so nothing
::    in it is a prefix of either, and +cull-slots only ever names paths
::    that are in `have` and not in `want`. The two sets provably do not
::    overlap.
::
++  sync-slots
  |=  $:  root=path
          t=thread-id:uc
          have=(map path stored-msg:uc)
          want=(map path stored-msg:uc)
      ==
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  dir=path  (mdir root t)
  =/  wn=(set path)  (node-dirs:uc ~(tap in ~(key by want)))
  =/  stale=(set path)
    %-  ~(gas in *(set path))
    %+  skip  ~(tap in (node-dirs:uc ~(tap in ~(key by have))))
    |=(pk=path (~(has in wn) pk))
  =/  puts=(list [pk=path st=stored-msg:uc])
    %+  skip  ~(tap by want)
    |=([pk=path st=stored-msg:uc] =(`st (~(get by have) pk)))
  =/  gone=(list path)
    %+  skip  ~(tap in ~(key by have))
    |=(pk=path ?|((~(has by want) pk) (under-any:uc pk stale)))
  =/  dead=(list path)  (minimal-dirs:uc stale)
  ;<  ~  bind:m  (ensure-nodes dir (sorted-dirs (node-dirs:uc (turn puts |=([pk=path *] pk)))))
  ;<  ~  bind:m  (put-slots dir puts)
  ;<  ~  bind:m  (cull-dirs dir dead)
  ;<  ~  bind:m  (cull-slots dir gone)
  ::  the answer +deliver needs: did this emit a single dart? A
  ::  redelivery of a chain we already hold emits none, and must not be
  ::  allowed to look like new mail.
  (pure:m ?|(?=(^ puts) ?=(^ dead) ?=(^ gone)))
::
::  recursion by ARM NAME, not by $. A $ with arguments inside a ;<
::  continuation cannot find the trap (-find.$.+2).
::
++  cull-dirs
  |=  [dir=path ps=(list path)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  ps  (pure:m ~)
  ;<  ~  bind:m  (cull-if-there [%& %| (weld dir i.ps)])
  (cull-dirs dir t.ps)
::
++  cull-slots
  |=  [dir=path ps=(list path)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  ps  (pure:m ~)
  ;<  *  bind:m  (cull-soft:io [%& %& (weld dir (snip i.ps)) (rear i.ps)])
  (cull-slots dir t.ps)
::
++  put-slots
  |=  [dir=path xs=(list [pk=path st=stored-msg:uc])]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  xs  (pure:m ~)
  ;<  ~  bind:m
    %^  put-file  [%& %& (weld dir (snip pk.i.xs)) (rear pk.i.xs)]
      [/urmail %msg]
    st.i.xs
  (put-slots dir t.xs)
::
::  ── the pre-tree migration ──────────────────────────────────────────
::
::  +migrate-flat: move a mailbox stored flat into the tree.
::
::    Before this layout every copy sat directly under msg/<slot>. Those
::    grubs READ back perfectly - nothing outside the storage layer cares
::    where a copy was filed, and +collect-slots keys them by a
::    one-segment path - so this is a tidy, not a gate: a ship that
::    somehow never ran it still shows all its mail.
::
::    IT IS A LAYOUT MIGRATION AND NOTHING ELSE, which is why it may
::    happen in place at all. The two format breaks recorded in
::    +read-stored could not, because a signature covers a shape and
::    rewriting the shape turns genuine mail into apparent forgeries.
::    Here every byte a signature covers is untouched: the same grub is
::    written at a different path.
::
::    Runs once at writer rise, gated on a thread actually holding a flat
::    copy, so a migrated ship pays one peek of /mail/thread per reload
::    and writes nothing. +sync-slots does the work, so the migration and
::    the delivery path cannot disagree about where a message goes.
::
::  REPORTING DOES NOT HAPPEN ON THE WRITER'S RISE.
::
::    An earlier draft counted the unreadable grubs from inside the rise
::    sequence and noted the total. It is off that path now as policy,
::    not because it was seen to misbehave: the writer rises ONCE and
::    only then enters its take-poke loop, so anything added there that
::    fails to return would leave every poke queued forever, with no
::    crash, no restart and no print, since +rise-wait fires on failure
::    and not on a hang. The rise does the minimum needed to serve, and
::    a count that exists to inform a human is served from a REQUEST
::    FIBER, where the worst case costs one HTTP connection instead of
::    the ship's entire mail path. +unreadable-in is therefore called
::    only from +serve-thread.
::
++  migrate-flat
  |=  root=path
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  loaded=(map thread-id:uc (map path stored-msg:uc))  bind:m  (read-threads root)
  (migrate-loop root ~(tap by loaded))
::
++  migrate-loop
  |=  [root=path ts=(list [t=thread-id:uc ss=(map path stored-msg:uc)])]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  ts  (pure:m ~)
  ;<  ~  bind:m  (migrate-one root t.i.ts ss.i.ts)
  (migrate-loop root t.ts)
::
++  migrate-one
  |=  [root=path t=thread-id:uc ss=(map path stored-msg:uc)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ::  a one-segment path is a copy directly under msg/, which is what a
  ::  pre-tree grub is and what a tree grub can never be.
  ?.  (lien ~(tap in ~(key by ss)) |=(pk=path =(1 (lent pk))))
    (pure:m ~)
  ;<  *  bind:m
    (sync-slots root t ss (want-slots (chain-of ss) (verdicts-of ss)))
  (note root 'migrate' & (scot %uv t))
::
::  +record-bcc: the sender's own note of who it blind-copied.
::
::    Keyed by the message, kept in the thread's local meta, and never
::    shipped. An empty set writes nothing, so an ordinary send does not
::    grow the grub.
::
++  record-bcc
  |=  [root=path t=thread-id:uc i=msg-id:uc bcc=(set ship)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?:  =(~ bcc)  (pure:m ~)
  ;<  mt=meta:uc  bind:m  (read-meta root t)
  %^  put-file  [%& %& (tdir root t) %meta]  [/urmail %meta]
  mt(bcc (~(put by bcc.mt) i bcc))
::
::  +mark-direct: this thread reached us through a DELIVERY POKE.
::
::    The Inbox view is threads we participate in, and a BCC'd recipient
::    is in neither `from` nor `to` - without this their mail would be
::    invisible. Inbox is participant OR direct. Set on delivery only,
::    never on our own sends, and idempotent so a redelivery does not
::    rewrite meta.
::
++  mark-direct
  |=  [root=path t=thread-id:uc]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  mt=meta:uc  bind:m  (read-meta root t)
  ?:  direct.mt  (pure:m |)
  ;<  ~  bind:m
    %^  put-file  [%& %& (tdir root t) %meta]  [/urmail %meta]
    mt(direct &)
  (pure:m &)
::
::  recursion by ARM NAME: a $ with arguments inside a ;< continuation
::  cannot find the trap.
::
++  mark-read-loop
  |=  [root=path xs=(list [t=thread-id:uc is=(set msg-id:uc)]) rd=?]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  xs  (pure:m ~)
  ;<  ~  bind:m  (mark-read root t.i.xs is.i.xs rd)
  (mark-read-loop root t.xs rd)
::
::  +mark-read: fold a set of ids into one thread's read marks, in ONE
::  rewrite of its meta grub however many ids are named.
::
::    `rd` is the direction: & unions the ids in, | takes them out.
::    %read and %unread are the same walk and the same write, which is
::    what keeps them from disagreeing about what a set of ids names.
::
++  mark-read
  |=  [root=path t=thread-id:uc is=(set msg-id:uc) rd=?]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  mt=meta:uc  bind:m  (read-meta root t)
  %^  put-file  (meta-rail root t)  [/urmail %meta]
  mt(read ?:(rd (~(uni in read.mt) is) (~(dif in read.mt) is)))
::
++  touch-idx
  |=  [root=path t=thread-id:uc]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  ix=mail-idx:uc  bind:m  (read-idx root)
  %^  put-file  [%& %& (mail-dir root) %idx]  [/urmail %idx]
  ix(inbox [t (skip inbox.ix |=(o=thread-id:uc =(o t)))])
::
::  ── delivery out ────────────────────────────────────────────────────
::
++  fan-out
  |=  [root=path c=chain:uc ws=(list ship)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  ws  (pure:m ~)
  ;<  ~  bind:m  (send-one root c i.ws)
  (fan-out root c t.ws)
::
::  +send-one: poke one recipient's writer with the whole chain.
::
::    Bounded by a deadline, and soft. This runs INSIDE the writer, which
::    is the ship's single serialisation point for mail; an unreachable
::    recipient must not wedge it forever, and a nack from a peer running
::    a different urmail must not crash it.
::
++  send-one
  |=  [root=path c=chain:uc who=ship]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  rd=road:tarball  (remote-road [%& %& root %'main.sig'] who)
  ;<  res=(unit (unit tang))  bind:m
    ((deadline ,(unit tang)) send-timeout (poke-soft:io rd [[/ %urmail-chain] c]))
  ?~  res
    (trace:io ~[leaf+"urmail: send to {<who>} timed out"])
  ?~  u.res  (pure:m ~)
  (trace:io ~[leaf+"urmail: send to {<who>} nacked"])
::
++  send-timeout  ^-(@dr ~s20)
::
::  +remote-road: rewrite an absolute road into its /sys/ames mirror on
::  `shp`, so a dart routes to that ship. The peer's urmail sits at the
::  same absolute path its own root nexus gave it.
::
++  remote-road
  |=  [=road:tarball shp=@p]
  ^-  road:tarball
  ?-  -.road
    %|  road
    %&
      =/  prefix=path  /sys/ames/ships/[(scot %p shp)]/root
      ?-  -.p.road
        %&  [%& %& (weld prefix path.p.p.road) name.p.p.road]
        %|  [%& %| (weld prefix p.p.road)]
      ==
  ==
::
::  ── jael, through the scry service ──────────────────────────────────
::
::  A nexus cannot .^ directly; /sys/scry does it with the agent's live
::  bowl, which is exactly what jael needs - it answers scries only at
::  exactly `now`, so nothing may scry it with a stored date. The mark is
::  %noun and the shape check is a `;;` here, because !< against a
::  noun-marc vase would nest-fail on any narrower mold.
::
++  our-life
  |=  our=@p
  =/  m  (fiber:fiber:nexus ,@ud)
  ^-  form:m
  ;<  n=noun  bind:m  (typed-scry:io noun %noun ~[%j %life (scot %p our)])
  (pure:m ;;(@ud n))
::
++  our-ring
  |=  lyf=@ud
  =/  m  (fiber:fiber:nexus ,ring)
  ^-  form:m
  ;<  n=noun  bind:m  (typed-scry:io noun %noun ~[%j %vein (scot %ud lyf)])
  (pure:m ;;(ring n))
::
++  fake-ship
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  n=noun  bind:m  (typed-scry:io noun %noun ~[%j %fake])
  (pure:m ;;(? n))
::
::  +peer-pass: a ship's public key at a given life, or ~ when none.
::
::    %puby is the UNITIZED public-key scry: ~ for a ship absent from the
::    local azimuth snapshot, rather than blocking. A blocking scry stalls
::    the agent that runs it, so %deed is not an option.
::
::    %puby has no fake-ship branch the way %deed does, so on a fake ship
::    it returns ~ for nearly every ship and nothing would ever verify in
::    development. Mirror what %deed does for fake ships instead.
::
++  peer-pass
  |=  [fake=? who=ship lyf=@ud]
  =/  m  (fiber:fiber:nexus ,(unit pass))
  ^-  form:m
  ?:  fake  (pure:m `(fake-pass:uc who))
  ;<  n=noun  bind:m
    (typed-scry:io noun %noun ~[%j %puby (scot %p who) (scot %ud lyf)])
  =/  res  (mule |.(;;((unit [crypto-suite=@ud =pass]) n)))
  ?:  ?=(%| -.res)  (pure:m ~)
  ?~  p.res  (pure:m ~)
  (pure:m `pass.u.p.res)
::
::  +key-map: one scry per distinct [ship life], not one per message.
::  Recursion by arm name, for the ;< reason stated above.
::
++  key-map
  |=  $:  fake=?
          sg=(list [who=ship lyf=@ud])
          acc=(map [ship @ud] (unit pass))
      ==
  =/  m  (fiber:fiber:nexus ,(map [ship @ud] (unit pass)))
  ^-  form:m
  ?~  sg  (pure:m acc)
  ;<  p=(unit pass)  bind:m  (peer-pass fake who.i.sg lyf.i.sg)
  (key-map fake t.sg (~(put by acc) [who.i.sg lyf.i.sg] p))
::
::  ── bowl reads ──────────────────────────────────────────────────────
::
::  +bowl-our / +bowl-now: our/now, with the reply MARK-FILTERED. The
::  writer is a busy fiber: a %urmail-chain poke queued while it was
::  mid-work must be skipped back to the loop, not stolen by a bowl read.
::
++  bowl-our
  =/  m  (fiber:fiber:nexus ,ship)
  ^-  form:m
  ;<  ~  bind:m  (poke:io &+&+[/sys %'bowl.sig'] [[/ %bowl-req] %our])
  |=  input:fiber:nexus
  :+  ~  q.state
  ?+  in  [%skip ~]
      ~  [%wait ~]
      [~ %poke * *]
    ?.  =([/ %ship] p.sage.u.in)  [%skip ~]
    [%done !<(ship q.sage.u.in)]
  ==
::
++  bowl-now
  =/  m  (fiber:fiber:nexus ,@da)
  ^-  form:m
  ;<  ~  bind:m  (poke:io &+&+[/sys %'bowl.sig'] [[/ %bowl-req] %now])
  |=  input:fiber:nexus
  :+  ~  q.state
  ?+  in  [%skip ~]
      ~  [%wait ~]
      [~ %poke * *]
    ?.  =([/ %time] p.sage.u.in)  [%skip ~]
    [%done !<(@da q.sage.u.in)]
  ==
::
::  +deadline: with-timeout, rebuilt from primitives every grubbery in the
::  fleet shares. +with-timeout:io's BODY is identical across the versions
::  our ships run but its SIGNATURE is not, so calling it directly makes
::  this file buildable on exactly one grubbery generation. Taken from
::  lattice, which learned this the expensive way.
::
++  deadline
  |*  result=mold
  =/  m   (fiber:fiber:nexus ,(unit result))
  =/  mr  (fiber:fiber:nexus ,result)
  |=  [time=@dr computation=form:mr]
  ^-  form:m
  ;<  =wire    bind:m  (nonce:io /urmail-to)
  ;<  now=@da  bind:m  get-time:io
  ;<  ~        bind:m  (set-timer:io wire (add now time))
  |=  input:fiber:nexus
  ^-  output:m
  ?:  ?&  ?=([~ %poke * *] in)
          =([/ %timer-wake] p.sage.u.in)
          =(wire !<(^wire q.sage.u.in))
      ==
    [~ q.state %done ~]
  =/  c-res=output:mr  (computation +<)
  ?:  ?=(%cont -.next.c-res)
    [darts.c-res state.c-res %cont ..$(computation self.next.c-res)]
  ?:  ?=(%done -.next.c-res)
    =/  fin=form:m
      ;<  ~  bind:m  (cancel-timer:io wire)
      (pure:m `value.next.c-res)
    [darts.c-res state.c-res %cont fin]
  ?:  ?=(%fail -.next.c-res)
    =/  err=tang  err.next.c-res
    =/  fin=form:m
      ;<  ~  bind:m  (cancel-timer:io wire)
      |=  input:fiber:nexus
      [~ q.state %fail err]
    [darts.c-res state.c-res %cont fin]
  :+  darts.c-res  state.c-res
  ?-  -.next.c-res
    %wait  [%wait ~]
    %skip  [%skip ~]
  ==
::
::  ── the web surface ─────────────────────────────────────────────────
::
::  Two kinds of route and one rule between them: a READ peeks the tree
::  from the request fiber and answers; a WRITE pokes the writer and
::  answers ok. Nothing here writes to the tree. That is the whole reason
::  per-request fibers exist - the writer is this ship's single
::  serialisation point for mail, and a send fans out to every recipient
::  with a deadline each, so a render or a network round trip placed on it
::  would queue every other mutation in the ship behind it.
::
::  The JSON is byte-for-byte what the gall agent produced, because the
::  client that consumes it is the reviewed one and a port that quietly
::  changed the contract would be a rewrite wearing a port's name.
::
::  +srv: the HTTP response door. Every response travels up to
::  /ui/main.sig through it, so the dispatcher can cull the fiber of a
::  connection the browser already dropped.
::
++  srv  ~(. http-res:io [%| 1 %& ~ %'main.sig'])
::
::  +bump-beacon: move the beacon so open readers refetch.
::
::    The value is `now`, not a counter: a counter would have to be read
::    before it is written, which is a peek on the write path, and the
::    reader only ever compares it against the last one it saw.
::
++  bump-beacon
  |=  root=path
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  now=@da  bind:m  bowl-now
  (put-file [%& %& (weld root /beacon) %rev] [/ %json] (numb:enjs:format `@ud`now))
::
::  +nexus-root: this nexus's absolute tree path, from a REQUEST fiber.
::
::    Derived, not a constant. A request fiber sits at
::    <root>/ui/requests/<id>, so its own directory is two below the
::    root. Lattice hardcodes its equivalent; here the install name is a
::    documented failure mode - a nexus made under the wrong name seeds a
::    tree that nothing looks at, with no error anywhere - and a constant
::    that disagreed with the real install would peek an empty tree and
::    serve an empty inbox rather than fail.
::
++  nexus-root
  =/  m  (fiber:fiber:nexus ,path)
  ^-  form:m
  ;<  here=rail:tarball  bind:m  get-here-abs:io
  =/  p=path  path.here
  =/  n=@ud  (lent p)
  (pure:m ?:((lth n 2) p (scag (sub n 2) p)))
::
::  +is-owner: is this request really from the ship that owns us?
::
::    `authenticated.req` is eyre's own answer and should already imply
::    this - it means the request carried a valid session for our
::    owner's web login. This compares the `src` the request fiber was
::    handed anyway, so the surface does not rest on one flag from one
::    vane. Lattice rests on that flag alone; matching a reference
::    implementation is not a reason to stop at it on a write surface.
::
::    ON EVERY ROUTE THAT TOUCHES MAIL, and on no other. `src` is in
::    hand but `our` is not: getting it is a poke to /sys/bowl.sig and
::    a reply, the round trip whose ~0.2s per request is recorded on
::    the owner gate below. That is worth paying wherever the answer
::    could be someone else's mail, and not worth paying anywhere else.
::
::    So: the three writes, and the two DATA READS - /api/inbox and
::    /api/thread/<id> - which return the owner's mailbox. If
::    `authenticated` could ever be true for a visiting ship those two
::    would hand over the mail, and the cost of being wrong about that
::    is not comparable to the cost of a bowl read.
::
::    NOT the shell or app.js. They are a static document and a static
::    script, identical for every viewer, and 0.2s on each asset load
::    buys nothing. /api/whoami is likewise only the answer `our`,
::    which is what the check would fetch anyway.
::
++  is-owner
  |=  src=@p
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  our=@p  bind:m  bowl-our
  (pure:m =(our src))
::
::  +handle-request: one HTTP request, on its own ephemeral fiber.
::
++  handle-request
  |=  eyre-id=@ta
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  [src=@p req=inbound-request:eyre]  bind:m
    (get-state-as:io ,[src=@p inbound-request:eyre])
  =/  parsed  (parse-url:http-utils url.request.req)
  ::  drop the /apps/urmail prefix; the remainder is the route.
  =/  suffix=path  (slag 2 site.parsed)
  ::  a trailing '/' parses as a trailing empty knot, so without this
  ::  /apps/urmail/ would miss the shell route and fall to the 404 - and
  ::  a trailing slash is exactly what a browser adds when the app is
  ::  opened from a bookmark.
  =/  suffix=path
    ?:  &(?=(^ suffix) =('' (rear `path`suffix)))
      (snip `path`suffix)
    suffix
  =/  meth=@tas  method.request.req
  ::  THE OWNER GATE. urmail has no unauthenticated surface at all: no
  ::  clearweb view, no public form, no unauthenticated asset. Eyre
  ::  stamps a request authenticated to our own web login, so this flag
  ::  IS the src==our check and it is already in hand - reading `our`
  ::  over /sys/bowl just to compare cost lattice ~0.2s on every request.
  ?.  authenticated.req
    (send-err eyre-id 403 'forbidden')
  ::  the shell and its one script, laid down as grubs in +on-load.
  ?:  &(?=(~ suffix) =(%'GET' meth))
    (serve-ui eyre-id %'index.html')
  ?:  &(=(`path`[%'app.js' ~] suffix) =(%'GET' meth))
    (serve-ui eyre-id %'app.js')
  ::  the PWA's two files, served out of the same /app directory and
  ::  through the same arm. BEHIND THE OWNER GATE like everything else:
  ::  urmail has no unauthenticated surface, and these two are not an
  ::  exception carved for convenience. A manifest is fetched
  ::  anonymously by default, so the shell asks for it with
  ::  crossorigin="use-credentials"; a browser that ignores that gets a
  ::  403 and no install, which is the honest trade for a nexus that
  ::  never serves a byte to a stranger.
  ?:  &(=(`path`[%'manifest.json' ~] suffix) =(%'GET' meth))
    (serve-ui eyre-id %'manifest.json')
  ?:  &(=(`path`[%'sw.js' ~] suffix) =(%'GET' meth))
    (serve-ui eyre-id %'sw.js')
  ::  the launcher tile's icon, and the manifest's. It is a NEXUS-ROOT
  ::  grub rather than one of the four under /app - the tiles nexus
  ::  pulls it from there through /grubbery/tiles/icon/urmail - so it
  ::  needs a route of its own even though +serve-ui serves it. Without
  ::  this arm the path +on-load's comment names 404s, which is what
  ::  drove the manifest to carry the icon as a data: URI instead.
  ?:  &(=(`path`[%'icon.svg' ~] suffix) =(%'GET' meth))
    (serve-ui eyre-id %'icon.svg')
  ::  GET /api/thread/<id>: the id is the last segment, so this cannot
  ::  sit in the table below, which keys on the whole suffix. The ?= comes
  ::  FIRST in the &, so the branch can reach into the path it matched.
  ?:  &(?=([%api %thread @ ~] suffix) =(%'GET' meth))
    (serve-thread src eyre-id i.t.t.suffix)
  ::  GET /api/blob/<hash>: THE ONLY ROUTE THAT ANSWERS ANYTHING BUT
  ::  JSON, and the only one whose response body is not something this
  ::  nexus wrote. Same shape as /api/thread/<id> and here for the same
  ::  reason: the hash is the last segment, so it cannot sit in the
  ::  table below, which keys on the whole suffix.
  ?:  &(?=([%api %blob @ ~] suffix) =(%'GET' meth))
    (serve-blob src eyre-id i.t.t.suffix args.parsed)
  ::  the rest of the surface, keyed on the WHOLE suffix rather than on
  ::  its last segment: /read and /api/read are different requests and
  ::  only one of them is a route.
  ?+    [meth suffix]
    (send-err eyre-id 404 'not found')
      [%'GET' [%api %whoami ~]]         (serve-whoami eyre-id)
    ::  THE LISTING, AND EVERY VIEW IS THIS ONE ROUTE. Inbox, Sent,
    ::  Archived, a label and a search are the same walk over the same
    ::  tree with a different predicate, so they are the same route with
    ::  a different `view` - see +serve-inbox. Query args, not path
    ::  segments, because a view plus a label plus a query plus an
    ::  offset plus a limit in the path would be five positional
    ::  segments a client has to get in the right order.
      [%'GET' [%api %inbox ~]]          (serve-inbox src eyre-id args.parsed)
      [%'GET' [%api %drafts ~]]         (serve-drafts src eyre-id)
      [%'GET' [%api %rules ~]]          (serve-rules src eyre-id)
      [%'GET' [%api %lists ~]]          (serve-lists src eyre-id)
      [%'POST' [%api %send ~]]          (do-web-send src eyre-id (req-body req))
    ::  POST /api/blob: THE UPLOAD, and the only route whose REQUEST
    ::  body is not JSON. The body is the file, byte for byte, and it
    ::  is handed on as the $octs eyre already built - no decode, no
    ::  copy, no encoding to undo. It is the pair to the GET above,
    ::  which is the only route whose RESPONSE body is not JSON.
      [%'POST' [%api %blob ~]]
    (do-web-blob src eyre-id body.request.req)
      [%'POST' [%api %read ~]]          (do-web-read src eyre-id (req-body req))
      [%'POST' [%api %'fetch-blob' ~]]  (do-web-fetch src eyre-id (req-body req))
      [%'POST' [%api %unread ~]]        (do-web-unread src eyre-id (req-body req))
      [%'POST' [%api %label ~]]         (do-web-label src eyre-id (req-body req))
      [%'POST' [%api %archive ~]]       (do-web-archive src eyre-id (req-body req))
      [%'POST' [%api %draft ~]]         (do-web-draft src eyre-id (req-body req))
      [%'POST' [%api %'draft-delete' ~]]
    (do-web-id src eyre-id (req-body req) %delete-draft)
      [%'POST' [%api %'draft-send' ~]]
    (do-web-draft-send src eyre-id (req-body req))
      [%'POST' [%api %rule ~]]          (do-web-rule src eyre-id (req-body req))
      [%'POST' [%api %'rule-delete' ~]]
    (do-web-id src eyre-id (req-body req) %delete-rule)
    ::  ONE VERB FOR A LIST. Create, overwrite, add a member, drop one,
    ::  rename by re-saving and copy the membership off a message are
    ::  all this POST, because a list is a name and a set of ships.
      [%'POST' [%api %list ~]]          (do-web-list src eyre-id (req-body req))
      [%'POST' [%api %'list-delete' ~]]
    (do-web-list-delete src eyre-id (req-body req))
      [%'POST' [%api %'delete-thread' ~]]
    (do-web-delete src eyre-id (req-body req))
  ==
::
::  ── the client, as grubs ────────────────────────────────────────────
::
::  +serve-ui: the shell or its script, out of /app.
::
++  serve-ui
  |=  [eyre-id=@ta nam=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  ct=@t
    ?+  nam  'text/html'
      %'app.js'         'text/javascript'
      %'sw.js'          'text/javascript'
      %'manifest.json'  'application/manifest+json'
      %'icon.svg'       'image/svg+xml'
    ==
  ;<  root=path  bind:m  nexus-root
  ::  the client's four files are grubs under /app; the icon is a grub
  ::  at the nexus ROOT, because that is where the tiles nexus reads it
  ::  from. One arm, two directories, rather than a second copy of the
  ::  peek-and-unwrap for one file.
  =/  dir=path  ?:(=(%'icon.svg' nam) root (weld root /app))
  ;<  pv=view:nexus  bind:m  (peek:io [%& %& dir nam] ~)
  ?.  ?=([%file *] pv)  (send-err eyre-id 404 'not found')
  =/  res=(each mime tang)  (mule |.(!<(mime (need-vase:tarball sang.pv))))
  ?:  ?=(%| -.res)  (send-err eyre-id 500 'bad asset')
  ::  no-cache, not a max-age. The asset grubs (shell, script, manifest,
  ::  service worker, icon) are replaced wholesale by a reload, and a
  ::  cached shell pointing at a script that no longer matches it is a
  ::  blank page with nothing in the console.
  %+  send-simple:srv  eyre-id
  :-  [200 ~[['content-type' ct] ['cache-control' 'no-cache']]]
  `q.p.res
::
::  ── reads ───────────────────────────────────────────────────────────
::
::  +serve-whoami: our own @p, so the reply composer can drop us from its
::  own default recipient list. One /sys/bowl round trip, and the client
::  makes it once at startup rather than per request.
::
++  serve-whoami
  |=  eyre-id=@ta
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  our=@p  bind:m  bowl-our
  (send-json eyre-id (pairs:enjs:format ~[['ship' [%s (scot %p our)]]]))
::
::  +serve-inbox: the thread listing - EVERY VIEW, PAGED, SEARCHABLE.
::
::    ONE deep peek of /mail/thread, walked three times - once for the
::    message grubs, once for the meta leaves and once for the copies
::    this build cannot read. The alternative, a peek per thread, is a
::    dart per row on the surface a user hits first. This is the same
::    O(total stored messages) read the writer already pays and that the
::    spec already records against +thread-key; the upgrade path is the
::    same summary grub.
::
::    A VIEW IS A PREDICATE OVER THAT ONE WALK, NOT A STORED SET. Inbox,
::    Sent, Archived and each label are the same listing filtered
::    differently, which is why they cannot disagree about where a
::    thread is - there is only one place a thread is, and the views are
::    questions asked of it. See +in-view.
::
::    SEARCH IS THE SAME WALK with `q` non-empty, and it runs HERE, on a
::    request fiber, never on the writer: a search is a read, the writer
::    serialises mutations, and a linear sweep placed on it would queue
::    every send and every delivery behind whatever someone typed into a
::    search box.
::
::    PAGINATION counts the whole view and renders only the page, so
::    `total` is honest about a view the client has not fetched. It is
::    applied AFTER the predicate: a page of the inbox is a page of the
::    inbox, not the inbox-shaped subset of the first fifty threads.
::
++  serve-inbox
  |=  [src=@p eyre-id=@ta args=quay:eyre]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ::  `our` in hand, not just the owner answer: Inbox and Sent are both
  ::  questions about us, so the bowl read the owner gate pays for is
  ::  the same one those two views need.
  ;<  our=@p  bind:m  bowl-our
  ?.  =(our src)  (send-err eyre-id 403 'forbidden')
  =/  view=@t   (fall (arg args 'view') 'inbox')
  =/  q=@t      (fall (arg args 'q') '')
  =/  lab=@t    (fall (arg args 'label') '')
  =/  off=@ud   (fall (arg-ud args 'offset') 0)
  ::  an ABSENT limit defaults; a limit of 0 is an empty page, literally.
  =/  lim=@ud   (min max-page:uc (fall (arg-ud args 'limit') 50))
  ;<  root=path  bind:m  nexus-root
  ;<  ix=mail-idx:uc  bind:m  (read-idx root)
  ;<  vw=view:nexus  bind:m  (peek:io [%& %| (thread-dir root)] ~)
  =/  b=ball:tarball  ?:(?=([%ball *] vw) ball.vw *ball:tarball)
  =/  loaded  (collect-threads b)
  =/  metas   (collect-metas b)
  =/  lost    (collect-unreadable b)
  =/  keep=(list thread-id:uc)
    %+  skim  inbox.ix
    |=(t=thread-id:uc (in-view our view lab q t loaded metas lost))
  =/  jon=json
    %-  pairs:enjs:format
    :~  ['total' (numb:enjs:format (lent keep))]
        ['offset' (numb:enjs:format off)]
        ['limit' (numb:enjs:format lim)]
        ['view' [%s view]]
        :-  'threads'
        (inbox-json (page:uc keep off lim) loaded metas lost q)
    ==
  (send-json eyre-id jon)
::
::  +arg / +arg-ud: one query argument, decoded.
::
::    A quay is a (list [@t @t]) and a repeated key is legal in a URL, so
::    the FIRST occurrence wins rather than the last - a client that
::    sends ?view=inbox&view=archived gets the one it asked for first
::    instead of whatever ended up at the end of the list.
::
++  arg
  |=  [args=quay:eyre k=@t]
  ^-  (unit @t)
  ?~  args  ~
  ?:(=(k p.i.args) `q.i.args $(args t.args))
::
++  arg-ud
  |=  [args=quay:eyre k=@t]
  ^-  (unit @ud)
  =/  v=(unit @t)  (arg args k)
  ?~  v  ~
  ::  dim, not dem. +dem:ag is the DOT-GROUPED decimal parser - it reads
  ::  9.999 and refuses 9999, so an offset past the first thousand
  ::  threads would silently fall back to 0 and hand the client page one
  ::  while it believed it was on page five hundred.
  (rush u.v dim:ag)
::
::  +in-view: is this thread in the named view, under this query?
::
::    Pure, and every clause is a lib predicate rather than a rule
::    written twice - +in-inbox and +in-sent are import-free and tested.
::
::    A THREAD WITH NO READABLE COPY IS NOT DROPPED. Its chain is empty,
::    so it is a participant in nothing and would fail every view test;
::    dropping it would make it vanish from the listing while its meta
::    and its /mail/idx entry survived, which is exactly the silent
::    disappearance the unreadable count exists to stop. It answers the
::    only questions that can honestly be asked of it - archived or not
::    - and it never answers a SEARCH, because we cannot search what we
::    cannot read and saying we did would be a lie.
::
++  in-view
  |=  $:  our=@p
          view=@t
          lab=@t
          q=@t
          t=thread-id:uc
          loaded=(map thread-id:uc (map path stored-msg:uc))
          metas=(map thread-id:uc meta:uc)
          lost=(map thread-id:uc @ud)
      ==
  ^-  ?
  =/  ss=(map path stored-msg:uc)  (~(gut by loaded) t ~)
  =/  n=@ud  (~(gut by lost) t 0)
  ::  the index names a thread with nothing at all under it: a stale
  ::  entry, which +inbox-json also drops.
  ?:  &(=(~ ss) =(0 n))  |
  =/  mt=meta:uc  (~(gut by metas) t *meta:uc)
  ?:  =(~ ss)
    ::  unreadable-only. No chain, so no participants, no authorship and
    ::  no searchable text.
    ?&  =('' q)
        ?+  view  |
          %inbox     !archived.mt
          %all       &
          %archived  archived.mt
          %label     (~(has in labels.mt) `@tas`lab)
        ==
    ==
  =/  c=chain:uc  (chain-of ss)
  ?&  ?+  view  |
        %inbox     (in-inbox:uc our (participants:uc c) archived.mt direct.mt)
        %sent      (in-sent:uc our c)
        %archived  archived.mt
        %all       &
        %label     ?&((label-ok:uc `@tas`lab) (~(has in labels.mt) `@tas`lab))
      ==
      (chain-matches:uc q c)
  ==
::
::  +serve-drafts: the Drafts view.
::
::    A SEPARATE ROUTE, not a `view` on the listing, because a draft is
::    not a thread and has no sender, no verdict, no participants and no
::    unread state. Squeezing it into a thread row would mean inventing
::    every one of those, and inventing a sender for an unsigned message
::    is the exact confusion drafts are kept out of /mail/thread to
::    prevent.
::
++  serve-drafts
  |=  [src=@p eyre-id=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  mine=?  bind:m  (is-owner src)
  ?.  mine  (send-err eyre-id 403 'forbidden')
  ;<  root=path  bind:m  nexus-root
  ;<  ds=(list draft:uc)  bind:m  (read-drafts root)
  ::  newest first, matching the listing's order.
  =/  sorted=(list draft:uc)
    (sort ds |=([a=draft:uc b=draft:uc] (gth at.a at.b)))
  %+  send-json  eyre-id
  :-  %a
  %+  turn  sorted
  |=  d=draft:uc
  ^-  json
  %-  pairs:enjs:format
  :~  ['id' [%s (scot %uv id.d)]]
      ['to' [%a (turn ~(tap in to.d) |=(w=@p `json`[%s (scot %p w)]))]]
      ['subj' [%s subj.d]]
      ['body' [%s body.d]]
      ['prev' ?~(prev.d ~ [%s (scot %uv u.prev.d)])]
      ['at' (time:enjs:format at.d)]
  ==
::
++  serve-rules
  |=  [src=@p eyre-id=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  mine=?  bind:m  (is-owner src)
  ?.  mine  (send-err eyre-id 403 'forbidden')
  ;<  root=path  bind:m  nexus-root
  ;<  rs=(list rule:uc)  bind:m  (read-rules root)
  %+  send-json  eyre-id
  :-  %a
  %+  turn  rs
  |=  r=rule:uc
  ^-  json
  %-  pairs:enjs:format
  :~  ['id' [%s (scot %uv id.r)]]
      ['from' ?~(from.r ~ [%s (scot %p u.from.r)])]
      ['subject' ?~(subject.r ~ [%s u.subject.r])]
      ['add' [%a (turn ~(tap in add.r) |=(l=@tas `json`[%s l]))]]
      ['archive' [%b archive.r]]
  ==
::
::  +serve-lists: every mailing list, SORTED BY NAME.
::
::    Sorted here rather than in the client because the order is a
::    property of the answer, not of one renderer: the compose
::    autocomplete and the manage panel both read this route and neither
::    should have to agree separately about what order lists come in.
::
::    `members` is ships, rendered. A list name is a key on this ship and
::    goes no further - see mar/urmail/list.
::
++  serve-lists
  |=  [src=@p eyre-id=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  mine=?  bind:m  (is-owner src)
  ?.  mine  (send-err eyre-id 403 'forbidden')
  ;<  root=path  bind:m  nexus-root
  ;<  ls=(list [name=@t members=(set @p)])  bind:m  (read-lists root)
  =/  sorted=(list [name=@t members=(set @p)])
    %+  sort  ls
    |=  [a=[name=@t members=(set @p)] b=[name=@t members=(set @p)]]
    (aor name.a name.b)
  %+  send-json  eyre-id
  :-  %a
  %+  turn  sorted
  |=  l=[name=@t members=(set @p)]
  ^-  json
  %-  pairs:enjs:format
  :~  ['name' [%s name.l]]
      ['members' [%a (turn ~(tap in members.l) |=(w=@p `json`[%s (scot %p w)]))]]
  ==
::
::  +serve-thread: one thread, every stored copy with its own verdict.
::
++  serve-thread
  |=  [src=@p eyre-id=@ta seg=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  mine=?  bind:m  (is-owner src)
  ?.  mine  (send-err eyre-id 403 'forbidden')
  =/  t=(unit @uv)  (slaw %uv seg)
  ?~  t  (send-err eyre-id 400 'bad thread id')
  ;<  root=path  bind:m  nexus-root
  ::  one peek, walked twice: once for the copies a reader can produce
  ::  and once for the ones it cannot. The second number is what stops
  ::  a thread holding only pre-break grubs from rendering as an empty
  ::  thread with no explanation - see +unreadable-in.
  ;<  vw=view:nexus  bind:m  (peek:io [%& %| (tdir root u.t)] ~)
  =/  b=ball:tarball  ?:(?=([%ball *] vw) ball.vw *ball:tarball)
  =/  ss=(map path stored-msg:uc)  (collect-slots b)
  =/  lost=@ud  (unreadable-in b)
  ::  an empty thread dir and an absent one are the same thing to a
  ::  reader. The client turns this 404 into "no longer exists", which is
  ::  what a thread deleted in another tab actually is. A thread whose
  ::  every copy is UNREADABLE is neither, so it is served rather than
  ::  404'd: the messages are on disk, this build cannot read them, and
  ::  saying so is the whole point of counting.
  ?:  &(=(~ ss) =(0 lost))  (send-err eyre-id 404 'no such thread')
  ;<  mt=meta:uc  bind:m  (read-meta root u.t)
  (send-json eyre-id (thread-json u.t ss mt lost))
::
::  +serve-blob: one attachment's bytes, to the owner's browser.
::
::    THE DOWNLOAD, and the one route on this surface whose body is not
::    JSON this nexus wrote. Everything below is about that difference.
::
::    NOT FETCHED IS NOT NOT FOUND. A blob this ship does not hold is a
::    409 saying `not fetched`, never a 404: bytes are never pushed, so
::    a message we hold and an attachment we have not pulled is the
::    ORDINARY state of an inbound attachment, and 404 would tell the
::    client the file does not exist when what it means is "ask for it".
::    The client turns the 409 into the Fetch control that pokes
::    %fetch-blob and then retries this route.
::
::    ONLY BYTES THAT HASH TO THE REQUESTED PATH. +read-blob reads the
::    grub filed under the hash, and this re-derives the hash from the
::    bytes before answering. The store is written only by +take-blob
::    and +store-blob, both of which check, so this is belt to those
::    braces - but the whole design says the hash is the authority, and
::    a serving path that trusted a filename would be the one place it
::    was not.
::
::    `name` and `mime` ride in the QUERY, from the signed $attachment
::    the client just rendered, because a blob grub is bytes and an
::    arrival time and nothing else - the metadata lives in the message,
::    and finding it here would mean walking every thread on the ship
::    per download. That makes them client-supplied, which changes
::    nothing: they were HOSTILE ALREADY. Every one arrived signed by
::    whoever wrote the message, in a chain any ship may deliver, and
::    +safe-mime and +safe-name refuse them the same way whether they
::    came off the wire or out of the tree.
::
::    Content-Disposition: attachment, ALWAYS, on every response. A
::    hostile HTML or SVG rendered inline is XSS in the owner's session
::    with their cookie attached, and the allow-list above already
::    refuses to name either type - two independent reasons, which is
::    the right number. `nosniff` is the third, against a browser that
::    would guess a type we deliberately did not give it.
::
++  serve-blob
  |=  [src=@p eyre-id=@ta seg=@ta args=quay:eyre]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  mine=?  bind:m  (is-owner src)
  ?.  mine  (send-err eyre-id 403 'forbidden')
  =/  h=(unit @uv)  (slaw %uv seg)
  ?~  h  (send-err eyre-id 400 'bad hash')
  ;<  root=path  bind:m  nexus-root
  ;<  got=(unit octs)  bind:m  (read-blob root u.h)
  ?~  got  (send-err eyre-id 409 'not fetched')
  ?.  (blob-ok:uc u.got u.h)
    (send-err eyre-id 500 'stored blob does not match its address')
  =/  nm=@t  (safe-name:uw (fall (arg args 'name') '') (scot %uv u.h))
  =/  mt=@t  (safe-mime:uw (fall (arg args 'mime') ''))
  %+  send-simple:srv  eyre-id
  :-  :-  200
      :~  ['content-type' mt]
          ['content-disposition' (rap 3 ~['attachment; filename="' nm '"'])]
          ['x-content-type-options' 'nosniff']
          ['cache-control' 'no-store']
      ==
  `u.got
::
::  +collect-unreadable: per thread, how many copies this build cannot
::  read - out of the same deep peek +collect-threads already walks.
::
::    Only threads with a nonzero count appear, so an ordinary mailbox
::    produces an empty map and the listing pays nothing for it.
::
++  collect-unreadable
  |=  b=ball:tarball
  ^-  (map thread-id:uc @ud)
  %-  ~(gas by *(map thread-id:uc @ud))
  %+  murn  ~(tap by dir.b)
  |=  [seg=@ta kid=ball:tarball]
  ^-  (unit [thread-id:uc @ud])
  =/  t=(unit @uv)  (slaw %uv seg)
  ?~  t  ~
  =/  n=@ud  (unreadable-in kid)
  ?:(=(0 n) ~ `[u.t n])
::
::  +collect-metas: every thread's meta leaf, out of the same deep peek
::  +collect-threads walks for message grubs.
::
++  collect-metas
  |=  b=ball:tarball
  ^-  (map thread-id:uc meta:uc)
  %-  ~(gas by *(map thread-id:uc meta:uc))
  %+  murn  ~(tap by dir.b)
  |=  [seg=@ta kid=ball:tarball]
  ^-  (unit [thread-id:uc meta:uc])
  =/  t=(unit @uv)  (slaw %uv seg)
  ?~  t  ~
  ?~  fil.kid  ~
  =/  c=(unit [=sang:tarball gain=? bang=(unit tang)])
    (~(get by contents.u.fil.kid) %meta)
  ?~  c  ~
  ?:  (is-boom:tarball sang.u.c)  ~
  =/  res  (mule |.(;;(meta:uc (sang-noun:tarball sang.u.c))))
  ?:(?=(%| -.res) ~ `[u.t p.res])
::
::  ── json ────────────────────────────────────────────────────────────
::
::  Ported from the gall agent's renderers, contract unchanged.
::
::  A NOTE ON `enjs:format`, carried over from the agent: every arm below
::  qualifies `pairs` / `time` / `numb` fully instead of `=,`-ing the core
::  in. Face-injecting it made `(scot %p ...)` inside a nested |= nest-fail
::  on this ship's hoon (reproduced live on ~wex and ~feb). Every ship
::  rendered here sits inside a `turn` lambda, so the workaround is load
::  bearing, not stylistic.
::
++  msg-json
  |=  [vs=(map [msg-id:uc @ux] verdict:uc) rd=(set msg-id:uc) m=msg:uc]
  ^-  json
  =/  i=msg-id:uc  (id:uc unsigned.m)
  %-  pairs:enjs:format
  :~  ['id' [%s (scot %uv i)]]
      ['from' [%s (scot %p from.unsigned.m)]]
      ['to' [%a (turn ~(tap in to.unsigned.m) |=(s=ship [%s (scot %p s)]))]]
      ['subject' [%s subj.unsigned.m]]
      ['body' [%s body.unsigned.m]]
    ::  the author's rendering instruction, signed and therefore
    ::  unalterable in transit - and hostile input at the render
    ::  boundary for exactly that reason: a signature proves the author
    ::  CHOSE the value, never that it is safe. It is reported, not
    ::  obeyed. The client renders every body as plain text and says so
    ::  when the message asked for something else.
      ['body-mime' [%s body-mime.unsigned.m]]
      ['sent' (time:enjs:format sent.unsigned.m)]
      ['prev' ?~(prev.unsigned.m ~ [%s (scot %uv u.prev.unsigned.m)])]
    ::  ATTACHMENTS. They live INSIDE `unsigned`, so what is rendered
    ::  here is covered by the same signature the verdict below was
    ::  computed over: a reader comparing the two is comparing the same
    ::  bytes, and swapping a file breaks the signature.
    ::
    ::  Emitted because the alternative was not "unrendered" but
    ::  UNREPRESENTABLE: with no field here, a message carrying a file
    ::  was indistinguishable through this API from one carrying none,
    ::  and no client could have shown it however it was written. The
    ::  storage marc has rendered them all along (see mar/urmail/msg),
    ::  which is what made the gap easy to miss - the data was one
    ::  route away the whole time.
    ::
    ::  `mime` is the author's claim about the file and NOTHING MORE,
    ::  exactly as body-mime above is. It is signed, so an intermediary
    ::  cannot change it; a signature proves the author chose it, never
    ::  that it is true or safe, and the chain carrying it may have been
    ::  delivered by any ship. It is reported for a human to read. It
    ::  must never pick a renderer and must never reach a
    ::  Content-Type header.
    ::
    ::  `hash` is the content address and the only field here that
    ::  proves anything: the bytes live at /mail/blob/<hash>, any ship
    ::  holding them can serve them, and bytes that do not hash to it
    ::  are discarded. `size` is tied to it - the hash is over octs, so
    ::  a lie about the size is a lie about the address.
      :-  'attachments'
      :-  %a
      %+  turn  attachments.unsigned.m
      |=  a=attachment:uc
      ^-  json
      %-  pairs:enjs:format
      :~  ['name' [%s name.a]]
          ['size' (numb:enjs:format size.a)]
          ['mime' [%s mime.a]]
          ['hash' [%s (scot %uv hash.a)]]
      ==
    ::  THE VERDICT IS PER MESSAGE, never per thread. A thread holding one
    ::  unverified message is not an unverified thread, and this field is
    ::  the whole product claim reaching the screen.
      ['verdict' [%s (~(gut by vs) [i sig.m] %unverified)]]
      ['read' [%b (~(has in rd) i)]]
  ==
::
++  thread-json
  |=  [t=thread-id:uc ss=(map path stored-msg:uc) mt=meta:uc lost=@ud]
  ^-  json
  ::  +chain-of re-imposes the canonical order, which the tree does not
  ::  store: slots are named by (sham [id sig]) and a map has no order.
  =/  c=chain:uc  (chain-of ss)
  =/  vs=(map [msg-id:uc @ux] verdict:uc)  (verdicts-of ss)
  %-  pairs:enjs:format
  :~  ['id' [%s (scot %uv t)]]
      ['messages' [%a (turn c |=(m=msg:uc (msg-json vs read.mt m)))]]
      ['participants' [%a (turn ~(tap in (participants:uc c)) |=(s=ship [%s (scot %p s)]))]]
      ['last' (time:enjs:format (last-sent:uc c))]
    ::  copies stored here that THIS BUILD cannot read - grubs written
    ::  under a pre-body-mime shape, refused rather than relabelled by
    ::  +read-stored. Reported so a thread that renders short says why.
      ['unreadable' (numb:enjs:format lost)]
    ::  LOCAL STATE, rendered beside the signed content and never mixed
    ::  into it. Nothing here travels and nothing here is covered by a
    ::  signature; two ships holding this thread may disagree about
    ::  every field below and still agree, byte for byte, about who
    ::  signed what.
      ['archived' [%b archived.mt]]
      ['labels' [%a (turn ~(tap in labels.mt) |=(l=@tas `json`[%s l]))]]
  ==
::
::  +inbox-json: the listing. Deliberately not the full chains - the list
::  view needs a subject and a sender, not a hundred message bodies.
::
::    +murn, not +turn: the index is a derived grub naming thread ids, and
::    a thread whose grubs are gone should drop out of the listing rather
::    than crash the route the way the agent's +got did.
::
++  inbox-json
  |=  $:  order=(list thread-id:uc)
          loaded=(map thread-id:uc (map path stored-msg:uc))
          metas=(map thread-id:uc meta:uc)
          lost=(map thread-id:uc @ud)
        ::  the search term, '' for an ordinary listing. It reaches
        ::  +entry-json because a search row must be drawn from the
        ::  message that MATCHED, not from the newest honest copy - see
        ::  there.
          q=@t
      ==
  ^-  json
  :-  %a
  %+  murn  order
  |=  t=thread-id:uc
  ^-  (unit json)
  =/  ss=(map path stored-msg:uc)  (~(gut by loaded) t ~)
  =/  n=@ud  (~(gut by lost) t 0)
  ::  A THREAD WITH NO READABLE COPY STILL GETS A ROW, as long as
  ::  something is actually stored under it. After the %1 refusal that
  ::  is reachable on any ship carrying pre-freeze mail: every copy is
  ::  refused, +entry-json has no message to draw a sender and subject
  ::  from, and dropping the row made the thread disappear from the
  ::  listing while its meta and its /mail/idx entry survived. That is
  ::  the silent disappearance this build exists to stop saying
  ::  nothing about, so the row says it instead.
  ?:  =(~ ss)
    ?:(=(0 n) ~ `(unreadable-entry-json t n (~(gut by metas) t *meta:uc)))
  `(entry-json t ss (~(gut by metas) t *meta:uc) n q)
::
::  +unreadable-entry-json: the row for a thread this build cannot read
::  a single message of.
::
::    Every field is a placeholder and none of them pretends otherwise:
::    there is no sender to name, because naming one would mean reading
::    a message we just said we cannot read. The count is the honest
::    content of the row.
::
++  unreadable-entry-json
  |=  [t=thread-id:uc n=@ud mt=meta:uc]
  ^-  json
  %-  pairs:enjs:format
  :~  ['id' [%s (scot %uv t)]]
      ['subject' [%s '']]
      ['from' [%s '']]
      ['snippet' [%s '']]
      ['verdict' [%s %unverified]]
      ['forged' [%b |]]
      ['count' (numb:enjs:format 0)]
      ['last' (time:enjs:format *@da)]
      ['unread' [%b |]]
      ['participants' [%a ~]]
      ['unreadable' (numb:enjs:format n)]
    ::  the row shape is uniform across both branches, so a client never
    ::  has to ask which kind of row it is holding before reading a field.
      ['archived' [%b archived.mt]]
      ['labels' [%a (turn ~(tap in labels.mt) |=(l=@tas `json`[%s l]))]]
  ==
::
++  entry-json
  |=  [t=thread-id:uc ss=(map path stored-msg:uc) mt=meta:uc lost=@ud q=@t]
  ^-  json
  =/  c=chain:uc  (chain-of ss)
  =/  vs=(map [msg-id:uc @ux] verdict:uc)  (verdicts-of ss)
  ::  the list view is the surface a user scans fastest, and every field
  ::  on it is attacker-chosen: anyone may poke a one-message chain
  ::  claiming from=~zod, subj='Password reset' with a `sent` far in the
  ::  future, and `sent` is what orders the chain. Two things follow.
  ::
  ::  One: the summary is drawn from the newest NON-%forged copy, not from
  ::  (rear c). A message whose signature we checked and rejected has no
  ::  business supplying the sender line of an inbox row.
  ::
  ::  Two: the row carries the verdict of whatever message it did draw
  ::  from, so provenance is visible before the thread is opened rather
  ::  than only after. If every copy is %forged there is nothing honest to
  ::  fall back to - show the newest anyway, labeled %forged, since hiding
  ::  the row would delete evidence.
  =/  honest=chain:uc
    %+  skip  c
    |=(m=msg:uc =(%forged (~(gut by vs) [(id:uc unsigned.m) sig.m] %unverified)))
  ::  ON A SEARCH, THE ROW IS DRAWN FROM THE MESSAGE THAT MATCHED.
  ::
  ::  The two rules above are right for a listing and wrong for a
  ::  search. A search for a forgery answered with a row drawn from the
  ::  newest honest copy would name a ship that did not write the thing
  ::  the user searched for and label it `verified` - the safety
  ::  mechanism telling a lie about the result it was asked to find.
  ::  Search covers %forged messages deliberately; the row says which
  ::  one it found and carries that copy's verdict, so a forged hit
  ::  reads FORGED.
  =/  picked=(unit msg:uc)  (newest-match:uc q c)
  =/  newest=msg:uc  ?^(picked u.picked ?~(honest (rear c) (rear honest)))
  ::  the spec is explicit that %forged messages "are never counted as
  ::  unread and never sort into the normal inbox flow", so an unread
  ::  count that included them would let one poke bold every row.
  =/  unread=?
    %+  lien  c
    |=  m=msg:uc
    ?&  !=(%forged (~(gut by vs) [(id:uc unsigned.m) sig.m] %unverified))
        !(~(has in read.mt) (id:uc unsigned.m))
    ==
  %-  pairs:enjs:format
  :~  ['id' [%s (scot %uv t)]]
      ['subject' [%s subj.unsigned.newest]]
      ['from' [%s (scot %p from.unsigned.newest)]]
      ['snippet' [%s (crip (scag 140 (trip body.unsigned.newest)))]]
      ['verdict' [%s (~(gut by vs) [(id:uc unsigned.newest) sig.newest] %unverified)]]
      ['forged' [%b (lth (lent honest) (lent c))]]
    ::  `count` is STORED COPIES, not distinct messages, and the client
    ::  labels it as such. Up to max-copies copies of one message that
    ::  differ in signature are kept on purpose - one genuine, the rest
    ::  forged - so a forged copy cannot shadow a real one. A thread
    ::  showing four may be one message and three forgeries, and calling
    ::  that a message count would be a lie told by the safety mechanism.
      ['count' (numb:enjs:format (lent c))]
      ['last' (time:enjs:format (last-sent:uc c))]
      ['unread' [%b unread]]
      ['participants' [%a (turn ~(tap in (participants:uc c)) |=(s=ship [%s (scot %p s)]))]]
    ::  copies stored here that this build cannot read. Usually 0; a row
    ::  can be partly readable, which is why the count rides on the
    ::  ordinary row too and not only on the placeholder one.
      ['unreadable' (numb:enjs:format lost)]
    ::  local state, so the sidebar can show which view a row is in
    ::  without a second request per row.
      ['archived' [%b archived.mt]]
      ['labels' [%a (turn ~(tap in labels.mt) |=(l=@tas `json`[%s l]))]]
  ==
::
::  ── writes ──────────────────────────────────────────────────────────
::
::  +poke-writer: hand one action to the serialised writer.
::
::    The route answers ok once the writer has taken the poke, not once it
::    has applied it. The beacon is what closes that gap: the writer bumps
::    it after the action lands and the open client refetches then. A
::    request fiber that waited for the apply would hold the connection
::    across a fan-out - a send to an unreachable ship carries a
::    twenty-second deadline per recipient.
::
++  poke-writer
  |=  a=action:uc
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  (poke:io [%| 2 %& ~ %'main.sig'] [[/ %urmail-action] a])
::
::  +do-web-send: compose, reply and forward. `prev` is the only thing
::  that tells them apart, here as everywhere else.
::
++  do-web-send
  |=  [src=@p eyre-id=@ta raw=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  mine=?  bind:m  (is-owner src)
  ?.  mine  (send-err eyre-id 403 'forbidden')
  =/  jon=(unit json)  (de:json:html raw)
  ?~  jon  (send-err eyre-id 400 'not json')
  =/  req=(unit send-req:uw)  (de-send:uw u.jon)
  ?~  req  (send-err eyre-id 400 'bad send')
  ::  THE CAPS, CHECKED HERE, WHERE THE ANSWER CAN STILL BE NO.
  ::
  ::    This route pokes the writer and answers as soon as the writer
  ::    takes the poke, because waiting for the apply would hold the
  ::    connection across a fan-out that carries a twenty-second
  ::    deadline per recipient. The cost of that split was a lie: a
  ::    send +do-send refuses wrote its reason to /tr/last and returned,
  ::    while the route had already answered 200 {"ok":true}. A body one
  ::    byte over max-body was a composed message silently destroyed,
  ::    with no draft to recover it - and the composer's own maxLength
  ::    cannot catch it, because that counts UTF-16 units and the cap
  ::    counts BYTES.
  ::
  ::    "No delivery receipts" is a deliberate limit about REMOTE
  ::    delivery. This was the ship refusing its owner's own message and
  ::    saying yes, which is a different thing entirely.
  ::
  ::    Every cap that depends only on the request is checked here, from
  ::    the same lib arms +do-send uses, so the two cannot drift. The
  ::    writer still checks them all: this route is not the only caller,
  ::    and a check on the boundary is not a substitute for a check at
  ::    the point of use.
  ::    `from`, `life`, `sent` and the signature are bunted: not one of
  ::    the three predicates below reads them, and inventing values the
  ::    writer will overwrite would be the drift this shares arms to
  ::    avoid.
  =/  one=chain:uc
    ~[[[*@p 0 to.u.req subj.u.req body.u.req '' *@da prev.u.req ~] 0x0]]
  ?.  (fits-bodies:uc one max-body:uc)
    (send-err eyre-id 400 'body too long')
  ?.  (fits-subjects:uc one max-subj:uc)
    (send-err eyre-id 400 'subject too long')
  ?.  (fits-recipients:uc one max-to:uc)
    (send-err eyre-id 400 'too many recipients')
  ::  ATTACHMENTS, AND NOT ONE BYTE OF THEM. Each entry names a blob
  ::  this ship already holds, because the browser uploaded it to
  ::  POST /api/blob first. Decoded off the SAME json object rather than
  ::  out of $send-req, so a client that sends no `attachments` key -
  ::  which is this one on a send with nothing attached - decodes
  ::  exactly as it always did. A key that is present and wrong is a
  ::  400: that is a client that meant to attach something and did not,
  ::  and answering ok would be the same lie the cap checks above exist
  ::  to stop.
  =/  rs=(unit (list up-ref:uw))  (de-refs:uw u.jon max-attach:uc)
  ?~  rs  (send-err eyre-id 400 'bad attachment')
  =/  refs=(list attach-ref:uc)  u.rs
  ::  the count and the two hostile strings, from the same lib arm the
  ::  writer's +attaches-ok shares. `size` is NOT checked here: a ref
  ::  does not carry one, reading it off the store costs a peek of the
  ::  bytes per file, and the upload route already refused anything
  ::  over max-blob with a 413 before it stored a thing.
  ?.  (refs-ok:uc refs)  (send-err eyre-id 400 'bad attachment')
  ::  EVERY REF NAMES A BLOB WE HOLD, CHECKED HERE SO THE ANSWER CAN
  ::  STILL BE NO. This route pokes the writer and answers as soon as
  ::  the poke is taken, so a ref the writer cannot resolve would be a
  ::  composed message destroyed silently behind a 200 - the exact
  ::  failure the cap checks above were added to stop, arriving through
  ::  a different door. Naming the hash is the point: "unknown
  ::  attachment" alone tells a person nothing about which file went
  ::  missing. +peek-exists and not +blob-size, because existence is
  ::  all this needs and the writer has to read the blob anyway.
  ;<  root=path  bind:m  nexus-root
  ;<  missing=(unit @uv)  bind:m  (first-unheld root refs)
  ?^  missing
    %^  send-err  eyre-id  400
    (rap 3 ~['unknown attachment ' (scot %uv u.missing)])
  ::  body-mime='' is 'text/plain', which is what this composer produces
  ::  and the only thing the client renders. bcc=~: no BCC field exists
  ::  in the web client yet, and it is absent from $send-req rather than
  ::  defaulted there, so a client cannot set it by accident through a
  ::  route that has no UI behind it.
  ;<  ~  bind:m
    (poke-writer [%send-ref to.u.req subj.u.req body.u.req '' prev.u.req refs ~])
  (send-ok eyre-id)
::
::  +first-unheld: the first named blob this ship does not hold, ~ when
::  it holds them all.
::
::    ONE +peek-exists PER REF AND NOT ONE BYTE READ. The route needs
::    two things from the store - that every ref resolves, and which one
::    does not when the answer is no - and neither of them is the size.
::    Reading the size here would peek sixteen quarter-megabyte grubs on
::    a request fiber for a send that has not been signed yet, and the
::    writer, which does have to read them to sign them, would read them
::    all again a moment later.
::
++  first-unheld
  |=  [root=path rs=(list attach-ref:uc)]
  =/  m  (fiber:fiber:nexus ,(unit @uv))
  ^-  form:m
  ?~  rs  (pure:m ~)
  ;<  ex=?  bind:m  (peek-exists:io (blob-rail root hash.i.rs))
  ?.  ex  (pure:m `hash.i.rs)
  (first-unheld root t.rs)
::
::  +do-web-blob: THE UPLOAD. Raw bytes in, a content address out.
::
::    The body IS the file. eyre hands a request fiber an $octs with a
::    declared length, which is exactly the shape +blob-hash and the
::    store want, so this route has no decoder and cannot have a
::    decoding bug: there is no encoding between the bytes on the wire
::    and the bytes in the tree. That is the whole reason it exists -
::    the base64-in-JSON transport it replaced spent about a second of
::    an interpreted character loop per quarter-megabyte file, on this
::    same fiber, holding the connection open.
::
::    ON THE REQUEST FIBER, NOT THE WRITER. A blob write is
::    content-addressed and therefore idempotent: two uploads of the
::    same bytes compute the same address and write the same grub, so
::    there is nothing for a serialisation point to protect. +take-blob
::    is the precedent for a blob written from outside the writer's
::    poke, and the alternative - poking a quarter-megabyte payload at
::    the ship's single serialisation point for mail - is exactly the
::    thing the caps exist to keep off it.
::
::    OWNER-GATED LIKE +serve-blob, flag and src both. This is a write
::    surface; resting it on one flag from one vane is thinner than it
::    needs to be.
::
::    IT DOES NOT EVICT, and that is a stated gap rather than an
::    oversight. +make-room reads every blob in the store and every
::    message on the ship to decide what is unreferenced - the exact
::    O(mailbox) work this slice exists to keep off a request fiber -
::    and a cull racing the writer's own is not idempotent the way the
::    put is. So max-blobs and max-blob-bytes bound the tree store at
::    the two places that still evict, %send's dojo path and a blob
::    fetch, and an upload can carry the store past them. The fix is
::    the same sweep of unreferenced blobs that collects abandoned
::    uploads, on the writer, and it is not in this slice.
::
::    IT DOES NOT BUMP THE BEACON. No message appeared, none changed,
::    and no listing row reads differently for a blob arriving - the
::    same argument that keeps a fetched blob and a read-mark off it.
::    The only tab that cares is the one holding the composer, and it
::    is reading this response.
::
++  do-web-blob
  |=  [src=@p eyre-id=@ta bod=(unit octs)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  mine=?  bind:m  (is-owner src)
  ?.  mine  (send-err eyre-id 403 'forbidden')
  ::  NO BODY AND A ZERO-BYTE BODY ARE THE SAME REFUSAL. An empty file
  ::  has a content address like any other and the store would hold it
  ::  quite happily, but there is nothing a user gains by attaching one
  ::  and the request is indistinguishable from a client that meant to
  ::  send bytes and sent none. Refused, loudly, at the boundary.
  ?~  bod  (send-err eyre-id 400 'empty body')
  =/  bts=octs  u.bod
  ?:  =(0 p.bts)  (send-err eyre-id 400 'empty body')
  ::  THE CAP, WITH ITS NUMBER IN THE MESSAGE. A client that guessed
  ::  wrong should not have to read the source to find out by how much.
  ?.  (lte p.bts max-blob:uc)
    %^  send-err  eyre-id  413
    %+  rap  3
    :~  'attachment over the '
        (crip (scow %ud max-blob:uc))
        ' byte limit for one file'
    ==
  ::  a declared length below the measured one is a malformed octs and
  ::  would make +blob-hash disagree with anything the bytes are later
  ::  re-measured against. eyre builds this pair itself, so this is belt
  ::  to its braces and costs one +met.
  ?.  (gte p.bts (met 3 q.bts))  (send-err eyre-id 400 'malformed body')
  =/  h=@uv  (blob-hash:uc bts)
  ;<  root=path  bind:m  nexus-root
  ::  IDEMPOTENT, AND THAT IS THE ADDRESSING WORKING. The same bytes
  ::  are the same blob; re-uploading them rewrites nothing, bumps no
  ::  case in the scry farm (see +store-blob on why that matters) and
  ::  answers exactly what the first upload answered.
  ;<  ex=?  bind:m  (peek-exists:io (blob-rail root h))
  ?:  ex  (blob-uploaded eyre-id h p.bts)
  ;<  now=@da  bind:m  bowl-now
  ;<  ~  bind:m  (put-file (blob-rail root h) [/urmail %blob] [%1 bts now])
  ::  PUBLISHED, exactly as an outbound attachment is: an uploaded blob
  ::  is OUR file and a recipient must be able to keen it the instant
  ::  the chain lands. Visibility is %public by absence from
  ::  /mail/blobvis, which is what +store-files leaves behind too.
  ;<  ~  bind:m  (publish-blob h bts |)
  (blob-uploaded eyre-id h p.bts)
::
::  +blob-uploaded: the upload's one answer shape, on both paths through
::  it - the bytes were already here, or they are now.
::
++  blob-uploaded
  |=  [eyre-id=@ta h=@uv size=@ud]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  %+  send-json  eyre-id
  %-  pairs:enjs:format
  :~  ['hash' [%s (scot %uv h)]]
      ['size' (numb:enjs:format size)]
  ==
::
++  do-web-read
  |=  [src=@p eyre-id=@ta raw=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  mine=?  bind:m  (is-owner src)
  ?.  mine  (send-err eyre-id 403 'forbidden')
  =/  jon=(unit json)  (de:json:html raw)
  ?~  jon  (send-err eyre-id 400 'not json')
  =/  i=(unit (set @uv))  (de-read:uw u.jon)
  ?~  i  (send-err eyre-id 400 'bad msg-ids')
  ;<  ~  bind:m  (poke-writer [%read u.i])
  (send-ok eyre-id)
::
::  +do-web-fetch: pull an attachment's bytes from a peer.
::
::    A POKE AND NOTHING ELSE. The keen runs on its own ephemeral fiber
::    under /fetch/<id> (see +do-fetch-blob and +run-fetch), so this
::    route answers as soon as the writer has queued the request, not
::    when the bytes land - a network round trip with a ten-second
::    deadline per case probe has no business holding an HTTP
::    connection, and it has less business on the writer.
::
::    Nothing tells the client when the bytes arrive: a blob arrival
::    does NOT move the change beacon (see +take-blob), because it is
::    not message content and one bump costs every open tab a full inbox
::    listing plus a thread refetch. The client retries GET /api/blob
::    instead, which is one peek per retry against a route it was going
::    to call anyway.
::
++  do-web-fetch
  |=  [src=@p eyre-id=@ta raw=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  mine=?  bind:m  (is-owner src)
  ?.  mine  (send-err eyre-id 403 'forbidden')
  =/  jon=(unit json)  (de:json:html raw)
  ?~  jon  (send-err eyre-id 400 'not json')
  =/  r=(unit [hash=@uv from=@p])  (de-fetch:uw u.jon)
  ?~  r  (send-err eyre-id 400 'bad fetch request')
  ;<  ~  bind:m  (poke-writer [%fetch-blob hash.u.r from.u.r])
  (send-ok eyre-id)
::
::  ── the mail-client writes ──────────────────────────────────────────
::
::  Each one is the same three steps: owner gate, decode, poke. The
::  decoders live in the import-free web lib so a test can reach them;
::  the semantic checks (is this a @tas? does this rule have a
::  condition?) live at the writer, because this route is not the only
::  caller and a check at the boundary is not a substitute for a check
::  at the point of use.
::
++  do-web-unread
  |=  [src=@p eyre-id=@ta raw=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  mine=?  bind:m  (is-owner src)
  ?.  mine  (send-err eyre-id 403 'forbidden')
  =/  jon=(unit json)  (de:json:html raw)
  ?~  jon  (send-err eyre-id 400 'not json')
  =/  i=(unit (set @uv))  (de-read:uw u.jon)
  ?~  i  (send-err eyre-id 400 'bad msg-ids')
  ;<  ~  bind:m  (poke-writer [%unread u.i])
  (send-ok eyre-id)
::
++  do-web-label
  |=  [src=@p eyre-id=@ta raw=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  mine=?  bind:m  (is-owner src)
  ?.  mine  (send-err eyre-id 403 'forbidden')
  =/  jon=(unit json)  (de:json:html raw)
  ?~  jon  (send-err eyre-id 400 'not json')
  =/  r=(unit label-req:uw)  (de-label:uw u.jon)
  ?~  r  (send-err eyre-id 400 'bad label request')
  ::  ANSWERED HERE, WHERE THE ANSWER CAN STILL BE NO. The route pokes
  ::  and returns as soon as the writer takes the poke, so a label the
  ::  writer refuses would otherwise be a 200 and a sidebar entry that
  ::  never appears, with the reason only in /tr/last.
  ?.  (label-ok:uc `@tas`label.u.r)
    (send-err eyre-id 400 'a label is a lowercase term: a-z, 0-9 and -')
  ;<  ~  bind:m
    (poke-writer [%label thread-id.u.r `@tas`label.u.r add.u.r])
  (send-ok eyre-id)
::
++  do-web-archive
  |=  [src=@p eyre-id=@ta raw=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  mine=?  bind:m  (is-owner src)
  ?.  mine  (send-err eyre-id 403 'forbidden')
  =/  jon=(unit json)  (de:json:html raw)
  ?~  jon  (send-err eyre-id 400 'not json')
  =/  r=(unit [t=@uv a=?])  (de-archive:uw u.jon)
  ?~  r  (send-err eyre-id 400 'bad archive request')
  ;<  ~  bind:m  (poke-writer [%archive t.u.r a.u.r])
  (send-ok eyre-id)
::
::  +do-web-draft: save one draft. NOTHING IS SIGNED ON THIS PATH.
::
::    The caps are checked here for the same reason /api/send checks
::    them: this route answers before the writer applies, and a draft
::    silently refused is the composed message the drafts feature exists
::    to protect, lost at save time instead of at send time.
::
++  do-web-draft
  |=  [src=@p eyre-id=@ta raw=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  mine=?  bind:m  (is-owner src)
  ?.  mine  (send-err eyre-id 403 'forbidden')
  =/  jon=(unit json)  (de:json:html raw)
  ?~  jon  (send-err eyre-id 400 'not json')
  =/  r=(unit draft-req:uw)  (de-draft:uw u.jon)
  ?~  r  (send-err eyre-id 400 'bad draft')
  ;<  now=@da  bind:m  bowl-now
  =/  d=draft:uc
    [%0 id.u.r to.u.r subj.u.r body.u.r prev.u.r now]
  ?.  (draft-ok:uc d)
    (send-err eyre-id 400 'draft too long')
  ;<  ~  bind:m  (poke-writer [%save-draft d])
  (send-ok eyre-id)
::
++  do-web-rule
  |=  [src=@p eyre-id=@ta raw=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  mine=?  bind:m  (is-owner src)
  ?.  mine  (send-err eyre-id 403 'forbidden')
  =/  jon=(unit json)  (de:json:html raw)
  ?~  jon  (send-err eyre-id 400 'not json')
  =/  r=(unit rule-req:uw)  (de-rule:uw u.jon)
  ?~  r  (send-err eyre-id 400 'bad rule')
  ::  labels arrive as strings and are refused here if they are not
  ::  terms, so the 400 names the field the user got wrong.
  ?.  (levy add.u.r |=(l=@t (label-ok:uc `@tas`l)))
    (send-err eyre-id 400 'a label is a lowercase term: a-z, 0-9 and -')
  =/  rl=rule:uc
    :*  %0
        id.u.r
        from.u.r
        subject.u.r
        (~(gas in *(set @tas)) (turn add.u.r |=(l=@t `@tas`l)))
        archive.u.r
    ==
  ::  a rule with neither a sender nor a subject matches every delivered
  ::  chain, and with `archive` set would empty the inbox silently.
  ?.  (rule-ok:uc rl)
    (send-err eyre-id 400 'a rule needs a sender or a subject to match')
  ;<  ~  bind:m  (poke-writer [%save-rule rl])
  (send-ok eyre-id)
::
::  +do-web-list: create or overwrite one mailing list.
::
::    THE MALFORMED BODY IS REFUSED HERE, WITH A 400, and never reaches
::    the writer. `name` becomes a path segment, so a name that is not a
::    knot is a write to a road nobody meant; `our` is refused as a
::    member so a list cannot send you your own mail. Both are checked
::    again at the writer, which is reachable from a dojo poke that never
::    passes through this arm - a boundary check is not a substitute for
::    one at the point of use, and this route is not the only door.
::
::    The reason a bad name is a 400 rather than a silent normalisation:
::    a user typed the name, and a list that quietly became something
::    else is a list they will look for under the name they chose.
::
++  do-web-list
  |=  [src=@p eyre-id=@ta raw=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  mine=?  bind:m  (is-owner src)
  ?.  mine  (send-err eyre-id 403 'forbidden')
  =/  jon=(unit json)  (de:json:html raw)
  ?~  jon  (send-err eyre-id 400 'not json')
  ;<  our=@p  bind:m  bowl-our
  =/  r=(unit list-req:uw)  (de-list:uw u.jon our)
  ::  ONE REFUSAL, THREE CAUSES, and the message names all three rather
  ::  than making the user guess which one they hit: the decoder is a
  ::  unit and cannot say why, and splitting it into three decoders to
  ::  get three messages would be three places for the name rule to
  ::  live.
  ?~  r
    %^  send-err  eyre-id  400
    %^  cat  3  'a list needs a name of 1-64 lowercase letters, digits or - '
    'and members that are ships other than your own'
  ?.  (lte ~(wyt in members.u.r) max-to:uc)
    (send-err eyre-id 400 'a list may not hold more members than a message may name')
  ;<  ~  bind:m  (poke-writer [%save-list name.u.r members.u.r])
  (send-ok eyre-id)
::
++  do-web-list-delete
  |=  [src=@p eyre-id=@ta raw=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  mine=?  bind:m  (is-owner src)
  ?.  mine  (send-err eyre-id 403 'forbidden')
  =/  jon=(unit json)  (de:json:html raw)
  ?~  jon  (send-err eyre-id 400 'not json')
  =/  n=(unit @t)  (de-list-name:uw u.jon)
  ?~  n  (send-err eyre-id 400 'bad list name')
  ;<  ~  bind:m  (poke-writer [%delete-list u.n])
  (send-ok eyre-id)
::
::  +do-web-id: the two routes that carry only an id and nothing to check.
::
::    delete-draft and delete-rule differ in nothing but the action tag,
::    so they share one arm rather than two copies of the same owner
::    gate and the same decoder. draft-send used to be here and is not
::    any more: it has caps to check, and answering ok to a send the
::    writer will refuse is what its own arm exists to stop.
::
::  +do-web-draft-send: sign a draft and send it.
::
::    THE CAPS ARE CHECKED HERE, WHERE THE ANSWER CAN STILL BE NO, for
::    the same reason /api/send checks them: this route answers as soon
::    as the writer takes the poke, so a draft the writer then refuses
::    was answered `ok` and the composer closed on it. The draft
::    survives on disk - +do-send-draft deletes only on a send that
::    happened - so nothing is lost, but the user was told a message
::    went out that did not, which is the one thing "no delivery
::    receipts" was never meant to cover.
::
::    The same three predicates +do-web-send uses, from the same lib
::    arms, so the two boundaries cannot drift. What stays writer-side
::    is what only the writer can answer: an unknown `prev` and a blob
::    store with no room. Those still refuse cleanly and still leave the
::    draft where it was; the trace says which.
::
++  do-web-draft-send
  |=  [src=@p eyre-id=@ta raw=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  mine=?  bind:m  (is-owner src)
  ?.  mine  (send-err eyre-id 403 'forbidden')
  =/  jon=(unit json)  (de:json:html raw)
  ?~  jon  (send-err eyre-id 400 'not json')
  =/  i=(unit @uv)  (de-id:uw u.jon)
  ?~  i  (send-err eyre-id 400 'bad id')
  ;<  root=path  bind:m  nexus-root
  ;<  d=(unit draft:uc)  bind:m  (read-draft root u.i)
  ::  a draft that is not there is a 404 and not an ok. The composer
  ::  turns it into "this draft no longer exists", which is what a draft
  ::  deleted in another tab actually is.
  ?~  d  (send-err eyre-id 404 'no such draft')
  ::  `from`, `life`, `sent` and the signature are bunted: not one of
  ::  the three predicates below reads them, and inventing values the
  ::  writer will overwrite would be the drift this shares arms to
  ::  avoid.
  =/  one=chain:uc
    ~[[[*@p 0 to.u.d subj.u.d body.u.d '' *@da prev.u.d ~] 0x0]]
  ?.  (fits-bodies:uc one max-body:uc)
    (send-err eyre-id 400 'body too long')
  ?.  (fits-subjects:uc one max-subj:uc)
    (send-err eyre-id 400 'subject too long')
  ?.  (fits-recipients:uc one max-to:uc)
    (send-err eyre-id 400 'too many recipients')
  ;<  ~  bind:m  (poke-writer [%send-draft u.i])
  (send-ok eyre-id)
::
++  do-web-id
  |=  [src=@p eyre-id=@ta raw=@t tag=?(%delete-draft %delete-rule)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  mine=?  bind:m  (is-owner src)
  ?.  mine  (send-err eyre-id 403 'forbidden')
  =/  jon=(unit json)  (de:json:html raw)
  ?~  jon  (send-err eyre-id 400 'not json')
  =/  i=(unit @uv)  (de-id:uw u.jon)
  ?~  i  (send-err eyre-id 400 'bad id')
  ;<  ~  bind:m
    %-  poke-writer
    ?-  tag
      %delete-draft  [%delete-draft u.i]
      %delete-rule   [%delete-rule u.i]
    ==
  (send-ok eyre-id)
::
++  do-web-delete
  |=  [src=@p eyre-id=@ta raw=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  mine=?  bind:m  (is-owner src)
  ?.  mine  (send-err eyre-id 403 'forbidden')
  =/  jon=(unit json)  (de:json:html raw)
  ?~  jon  (send-err eyre-id 400 'not json')
  =/  i=(unit @uv)  (de-delete:uw u.jon)
  ?~  i  (send-err eyre-id 400 'bad thread-id')
  ;<  ~  bind:m  (poke-writer [%delete-thread u.i])
  (send-ok eyre-id)
::
::  ── responses ───────────────────────────────────────────────────────
::
++  req-body
  |=  req=inbound-request:eyre
  ^-  @t
  ?~  body.request.req  ''
  q.u.body.request.req
::
++  send-ok
  |=  eyre-id=@ta
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  (send-json eyre-id (pairs:enjs:format ~[['ok' [%b &]]]))
::
++  send-json
  |=  [eyre-id=@ta jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  %+  send-simple:srv  eyre-id
  :-  [200 ['content-type' 'application/json']~]
  `(as-octs:mimes:html (en:json:html jon))
::
::  +send-err: errors are JSON too, so the client has one shape to parse
::  and can show the nexus's own reason instead of a bare status code.
::
++  send-err
  |=  [eyre-id=@ta code=@ud msg=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  %+  send-simple:srv  eyre-id
  :-  [code ['content-type' 'application/json']~]
  `(as-octs:mimes:html (en:json:html (pairs:enjs:format ~[['error' [%s msg]]])))
--
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
::    /app/index.html              the web client, laid down as two grubs:
::    /app/app.js                  a shell with its css inlined and one
::                                 script. Assets in cords wedge every
::                                 request fiber, so the shell is one
::                                 document and one script, the shape
::                                 lattice ships for the same reason.
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
++  apply
  |=  [root=path =from:fiber:nexus =sage:tarball]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ::  a chain from ANYONE. src is deliberately not checked against the
  ::  participants: the signatures are the authority, not the courier.
  ?:  =([/ %urmail-chain] p.sage)
    (deliver root !<(chain:uc q.sage))
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
    (take-blob root !<(blob-in:uc q.sage))
  (act root !<(action:uc q.sage))
::
++  act
  |=  [root=path a=action:uc]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ?-  -.a
    %send           (do-send root to.a subj.a body.a body-mime.a prev.a files.a bcc.a)
    %read           (do-read root msg-id.a)
    %delete-thread  (do-delete root thread-id.a)
    %fetch-blob     (do-fetch-blob root hash.a from.a)
    %restrict-blob  (do-restrict root hash.a ships.a)
    %publish-blob   (do-publish root hash.a)
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
  ?.  (lte (met 3 body) max-body:uc)
    (reject root 'body too long')
  ?.  (lte (met 3 subj) max-subj:uc)
    (reject root 'subject too long')
  ?.  (lte (add ~(wyt in to) ~(wyt in bcc)) max-to:uc)
    (reject root 'too many recipients')
  ?.  (text-ok:uc body-mime max-mime:uc)
    (reject root 'bad body mime')
  ?.  (files-ok:uc files)
    (reject root 'bad attachment')
  ::  the store bound counts only the files we would actually ADD.
  ::  +store-blob skips a file we already hold, so counting every
  ::  attachment against the cap refuses a send that stores nothing -
  ::  and the commonest attachment in a thread is one already in it.
  ;<  fresh=(list file:uc)  bind:m  (unheld-files root files)
  ;<  room=?  bind:m  (room-for root fresh)
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
  ::  the metadata goes INSIDE `unsigned`, so it is covered by the
  ::  signature and by msg-id. Swapping a file breaks the signature.
  ::  Building it here, from the bytes actually stored, is what makes
  ::  `size` and `hash` agree with what a fetcher will re-measure.
  =/  as=(list attachment:uc)  (turn files describe:uc)
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
  ;<  ~  bind:m  (store-files root fresh)
  ;<  ~  bind:m  (ensure-thread root rid)
  ::  where this message sits in the tree: its own ancestry, root first.
  ::  Derived from `prev` against the WHOLE thread, not against the path
  ::  that travels - the two agree, and the whole thread is what is
  ::  actually on disk.
  =/  place=(list msg-id:uc)  (place-of:uc (merge:uc full ~[mg]) (id:uc u))
  ;<  ~  bind:m  (write-msg root rid place mg %verified)
  ;<  ~  bind:m  (mark-read root rid (id:uc u))
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
  ::  %.n: the beacon is already moved, above. The writer's loop must
  ::  not move it a second time, which would cost every open reader a
  ::  pointless refetch of a thread it already has.
  (pure:m |)
::
++  do-read
  |=  [root=path mid=msg-id:uc]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  loaded=(map thread-id:uc (map path stored-msg:uc))  bind:m  (read-threads root)
  =/  hits
    %+  skim  ~(tap by loaded)
    |=  [t=thread-id:uc ss=(map path stored-msg:uc)]
    (lien ~(val by ss) |=(s=stored-msg:uc =((id:uc unsigned.msg.s) mid)))
  ?~  hits  (reject root 'unknown message')
  ;<  ~  bind:m  (mark-read root p.i.hits mid)
  ::  %.n ALWAYS. Read state is not content: lattice learned this with
  ::  page history, where every visit bumped and every open reader
  ::  reloaded. It is worse here, because a reader answers a bump by
  ::  refetching the thread it is showing and that refetch marks it read
  ::  again - a loop, not a burst.
  (pure:m |)
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
  ::  %.n: a queued request is not something any reader renders. The
  ::  bump that matters is +take-blob's, when the bytes actually land
  ::  and the attachment becomes readable.
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
  (pure:m &)
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
++  mark-read
  |=  [root=path t=thread-id:uc i=msg-id:uc]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  mt=meta:uc  bind:m  (read-meta root t)
  %^  put-file  [%& %& (tdir root t) %meta]  [/urmail %meta]
  mt(read (~(put in read.mt) i))
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
  ::  GET /api/thread/<id>: the id is the last segment, so this cannot
  ::  sit in the table below, which keys on the whole suffix. The ?= comes
  ::  FIRST in the &, so the branch can reach into the path it matched.
  ?:  &(?=([%api %thread @ ~] suffix) =(%'GET' meth))
    (serve-thread eyre-id i.t.t.suffix)
  ::  the rest of the surface, keyed on the WHOLE suffix rather than on
  ::  its last segment: /read and /api/read are different requests and
  ::  only one of them is a route.
  ?+    [meth suffix]
    (send-err eyre-id 404 'not found')
      [%'GET' [%api %whoami ~]]         (serve-whoami eyre-id)
      [%'GET' [%api %inbox ~]]          (serve-inbox eyre-id)
      [%'POST' [%api %send ~]]          (do-web-send eyre-id (req-body req))
      [%'POST' [%api %read ~]]          (do-web-read eyre-id (req-body req))
      [%'POST' [%api %'delete-thread' ~]]
    (do-web-delete eyre-id (req-body req))
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
  =/  ct=@t  ?:(=(%'app.js' nam) 'text/javascript' 'text/html')
  ;<  root=path  bind:m  nexus-root
  ;<  pv=view:nexus  bind:m  (peek:io [%& %& (weld root /app) nam] ~)
  ?.  ?=([%file *] pv)  (send-err eyre-id 404 'not found')
  =/  res=(each mime tang)  (mule |.(!<(mime (need-vase:tarball sang.pv))))
  ?:  ?=(%| -.res)  (send-err eyre-id 500 'bad asset')
  ::  no-cache, not a max-age. The two grubs are replaced wholesale by a
  ::  reload, and a cached shell pointing at a script that no longer
  ::  matches it is a blank page with nothing in the console.
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
::  +serve-inbox: the thread listing, in the index's order.
::
::    ONE deep peek of /mail/thread, walked twice - once for the message
::    grubs and once for the meta leaves. The alternative, a peek per
::    thread, is a dart per row on the surface a user hits first. This is
::    the same O(total stored messages) read the writer already pays and
::    that the spec already records against +thread-key; the upgrade path
::    is the same summary grub.
::
++  serve-inbox
  |=  eyre-id=@ta
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  root=path  bind:m  nexus-root
  ;<  ix=mail-idx:uc  bind:m  (read-idx root)
  ;<  vw=view:nexus  bind:m  (peek:io [%& %| (thread-dir root)] ~)
  =/  b=ball:tarball  ?:(?=([%ball *] vw) ball.vw *ball:tarball)
  (send-json eyre-id (inbox-json inbox.ix (collect-threads b) (collect-metas b)))
::
::  +serve-thread: one thread, every stored copy with its own verdict.
::
++  serve-thread
  |=  [eyre-id=@ta seg=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  t=(unit @uv)  (slaw %uv seg)
  ?~  t  (send-err eyre-id 400 'bad thread id')
  ;<  root=path  bind:m  nexus-root
  ;<  ss=(map path stored-msg:uc)  bind:m  (read-thread-slots root u.t)
  ::  an empty thread dir and an absent one are the same thing to a
  ::  reader. The client turns this 404 into "no longer exists", which is
  ::  what a thread deleted in another tab actually is.
  ?:  =(~ ss)  (send-err eyre-id 404 'no such thread')
  ;<  mt=meta:uc  bind:m  (read-meta root u.t)
  (send-json eyre-id (thread-json u.t ss mt))
::
::  +read-thread-slots: one thread's message grubs.
::
++  read-thread-slots
  |=  [root=path t=thread-id:uc]
  =/  m  (fiber:fiber:nexus ,(map path stored-msg:uc))
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io [%& %| (tdir root t)] ~)
  ?.  ?=([%ball *] vw)  (pure:m ~)
  (pure:m (collect-slots ball.vw))
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
    ::  THE VERDICT IS PER MESSAGE, never per thread. A thread holding one
    ::  unverified message is not an unverified thread, and this field is
    ::  the whole product claim reaching the screen.
      ['verdict' [%s (~(gut by vs) [i sig.m] %unverified)]]
      ['read' [%b (~(has in rd) i)]]
  ==
::
++  thread-json
  |=  [t=thread-id:uc ss=(map path stored-msg:uc) mt=meta:uc]
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
      ==
  ^-  json
  :-  %a
  %+  murn  order
  |=  t=thread-id:uc
  ^-  (unit json)
  =/  ss=(map path stored-msg:uc)  (~(gut by loaded) t ~)
  ?:  =(~ ss)  ~
  `(entry-json t ss (~(gut by metas) t *meta:uc))
::
++  entry-json
  |=  [t=thread-id:uc ss=(map path stored-msg:uc) mt=meta:uc]
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
  =/  newest=msg:uc  ?~(honest (rear c) (rear honest))
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
  |=  [eyre-id=@ta raw=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
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
  ::  body-mime='' is 'text/plain', which is what this composer produces
  ::  and the only thing the client renders. files=~ and bcc=~: bytes
  ::  enter the blob store through their own action, and neither an
  ::  attachment control nor a BCC field exists in the web client yet.
  ::  All three are absent from $send-req rather than defaulted there, so
  ::  a client cannot set them by accident through a route that has no UI
  ::  behind it.
  ;<  ~  bind:m
    (poke-writer [%send to.u.req subj.u.req body.u.req '' prev.u.req ~ ~])
  (send-ok eyre-id)
::
++  do-web-read
  |=  [eyre-id=@ta raw=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  jon=(unit json)  (de:json:html raw)
  ?~  jon  (send-err eyre-id 400 'not json')
  =/  i=(unit @uv)  (de-read:uw u.jon)
  ?~  i  (send-err eyre-id 400 'bad msg-id')
  ;<  ~  bind:m  (poke-writer [%read u.i])
  (send-ok eyre-id)
::
++  do-web-delete
  |=  [eyre-id=@ta raw=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
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

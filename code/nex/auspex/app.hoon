::  nex/auspex/app: the grubbery-native %auspex nexus.
::
::  auspex is a nexus, not a gall agent. The tree it owns:
::    /main.sig                    the WRITER. Takes %auspex-action (local
::                                 only) and %auspex-chain (any ship) pokes
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
::                                 farm at /auspex/blob/<hash>, where any
::                                 ship holding the hash may %keen them.
::                                 The hash is the authority and the
::                                 courier is irrelevant, so a blob whose
::                                 bytes do not hash to the name they came
::                                 under is discarded without comment.
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
::    /ui/main.sig                 binds /apps/auspex and dispatches each
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
/<  uc  /lib/auspex-chain.hoon
/<  uw  /lib/auspex-web.hoon
::  the built client. Imports resolve relative to THIS file's directory
::  (/nex/auspex), not /nex. Rebuilt by `npm run build` in ui/, which
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
::  the launcher tile's icon, served at /apps/auspex/icon.svg and
::  pulled by the tiles nexus through /grubbery/tiles/icon/auspex.
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
          ::  Without it auspex is installed, running and serving, and
          ::  invisible from the grubbery home screen - which reads as
          ::  "not installed" to everyone but the person who typed the
          ::  route by hand. %over, not %fall, so a redeploy replaces
          ::  the tile rather than leaving every ship on whatever it
          ::  first loaded, exactly as /app does below.
          ::
          ::  `image` names the app SLUG - the name before the first dot
          ::  in /apps/auspex.auspex_app - not the folder, and the tiles
          ::  nexus resolves it against the icon.svg grub laid beside
          ::  this row.
          :^  %over  %&  [/ %'tile.json']
          :-  [/ %json]
          %-  pairs:enjs:format
          :~  title+s+'Auspex'
              info+s+'Signed mail, verified end to end'
              color+s+'#1E1B4B'
              image+s+'/grubbery/tiles/icon/auspex'
              href+s+'/apps/auspex'
          ==
          ::  link.json: WHO THIS NEXUS CLAIMS TO BE, in the form the
          ::  shell SCANS. +read-app-aliases walks /apps and each desk's data
          ::  children reading link.json, not alias.json, and folds what it
          ::  finds into the /sys/link registry as @name -> {path,
          ::  description, source}. Without this grub auspex claims @auspex
          ::  nowhere, and nothing can resolve it by name.
          ::
          ::  This is what makes a peer's auspex FINDABLE once desks are
          ::  named at install time and no two ships need agree on a path.
          ::  See +remote-install for the constant it is meant to retire.
          :^  %over  %&  [/ %'link.json']
          :-  [/ %json]
          %-  pairs:enjs:format
          :~  name+s+'auspex'
              description+s+'Signed mail, verified end to end'
          ==
          ::  weir.json: WHAT THIS NEXUS REACHES OUTSIDE ITS OWN TREE, and
          ::  why, in words meant for the person being asked. A desk-
          ::  installed instance is created with an empty weir - permit
          ::  nothing - and earns each road through this file and the
          ::  shell's consent. Auspex's own subtree (/mail, /proto, /probe,
          ::  /beacon, /fetch, /ui, /requests, /tr) never crosses its own
          ::  boundary and is not declared here.
          [%over %& [/ %'weir.json'] [[/ %json] weir-json]]
          [%over %& [/ %'icon.svg'] [[/ %mime] uicon]]
          ::  /proto: WHAT THIS NEXUS SPEAKS. %over, not %fall, for the
          ::  same reason /app is: a redeploy that left every ship
          ::  publishing whatever it first loaded would make discovery
          ::  answer with yesterday's caps, which is worse than not
          ::  answering - it makes a sender confident about a send this
          ::  ship would drop.
          ::
          ::  The grub is the tree's copy. The copy a PEER reads is the
          ::  binding in gall's remote-scry farm, grown by
          ::  +publish-proto at writer rise; see that arm for why it
          ::  grows only when the spur is unbound.
          [%over %& [/ %proto] [[/auspex %proto] our-proto:uc]]
          ::  /proto-pub: WHAT WE LAST GREW INTO THE FARM, which is not
          ::  the same question as what we now publish. The farm binding
          ::  cannot be read back from inside this ship - a keen
          ::  addressed to ourselves does not answer - and growing on a
          ::  read that failed burns a case for no information, so the
          ::  record is kept here instead. %fall with the BUNT, so the
          ::  first boot after this row existed republishes once and
          ::  every boot after that is free.
          [%fall %& [/ %'proto-pub'] [[/auspex %proto] *proto:uc]]
          ::  the writer. %fall, so an existing live process is kept.
          [%fall %& [/ %'main.sig'] [[/ %sig] ~]]
          ::  /caps: WHAT THIS INSTANCE MAY REACH, and the one thing
          ::  every jael reach below is gated on. %over and DENIED, on
          ::  every load, because a veto cannot be caught: the road is
          ::  granted by the shell at install time and nothing in this
          ::  nexus can ask whether it was. So we assume not, and the
          ::  key probe below raises the flag by proving the reach
          ::  works. A load that came up granted spends one scry to
          ::  say so again; a load that came up refused spends nothing
          ::  and keeps its writer.
          ::
          ::  DENIED IS WRITTEN OUT, never bunted: $caps's `keys` is a
          ::  `?`, and `?` bunts to %.y. See +caps-denied:uc.
          [%over %& [/ %caps] [[/auspex %caps] caps-denied:uc]]
          ::  /keys/probe: THE PROBE, and writing this grub IS the
          ::  spawn - grubbery calls +on-file for every file in the
          ::  bole on every load. One cheap jael scry, a poke at the
          ::  writer if it answers, and nothing at all if it is
          ::  vetoed. See +run-key-probe.
          ::
          ::  %over rather than %fall so the question is asked again
          ::  after every deploy, which is when the answer can have
          ::  changed. Its own directory, so the grub can never
          ::  collide with a mail path.
          [%fall %| /keys empty-dir:loader]
          [%over %& [/keys %probe] [[/ %json] ~]]
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
          ::  [/auspex %idx], which mar/auspex/idx.hoon is.
          [%fall %& [/mail %idx] [[/auspex %idx] *mail-idx:uc]]
          ::  /mail/blob: the blob store. Covered for the same reason
          ::  /mail/thread is - the %fall %| on /mail already copies the
          ::  subtree, and this row is what CREATES the directory on a
          ::  first load, since +store-blob only writes leaves into it.
          [%fall %| /mail/blob empty-dir:loader]
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
          ::  /mail/peer: the discovery cache, one grub per ship we have
          ::  asked. Covered like every other persistent path - spin
          ::  drops what it does not cover - and %fall so the answers
          ::  survive a reload. Losing one is not lost mail: it costs
          ::  one probe and one version-1 attempt, which is exactly what
          ::  a ship with no record does anyway.
          [%fall %| /mail/peer empty-dir:loader]
          ::  /probe: one EPHEMERAL fiber per discovery keen, exactly as
          ::  /fetch is one per blob fetch and for the same reason - a
          ::  keen is a network round trip and the writer serialises
          ::  MUTATIONS, so a probe that ran on the writer would queue
          ::  every send and every inbound chain behind it. %fall so a
          ::  probe that outlives a reload respawns rather than leaving
          ::  a grub nothing will ever answer.
          [%fall %| /probe empty-dir:loader]
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
          ::  /tr/discovery: what discovery last learned, kept OFF
          ::  /tr/last. A probe answers on its own schedule - it is a
          ::  network round trip on a fiber nobody is watching - so
          ::  writing it to /tr/last would overwrite the outcome of the
          ::  send a person is actually looking at, seconds after they
          ::  looked. Two traces, two grubs.
          [%fall %& [/tr %discovery] [[/ %json] ~]]
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
          ::  /ui: the HTTP front end. main.sig binds /apps/auspex and
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
        ;<  ~  bind:m  (rise-later prod "%auspex writer failed")
        =/  root=@ud  (lent path.rail)
        ;<  ~  bind:m  (grant-public root)
        ::  BOTH OF THESE REACH /sys/scry, and +on-load has just laid
        ::  /caps denied, so on this line the answer is always "not
        ::  yet". They are no-ops here and run from +do-set-caps the
        ::  moment the key probe raises the flag - which is a poke this
        ::  writer takes a few events from now. On a ship that was
        ::  refused the road they never run, which is the point: a
        ::  vetoed grow here would fail the writer, and a failed writer
        ::  is restarted, and the restart would reach again.
        ;<  ~  bind:m  (republish-all root)
        ;<  ~  bind:m  (publish-proto root)
        ::  the blob-restriction record, from before restriction was
        ::  removed. The %fall row on /mail copies it forward as a grub
        ::  whose marc is gone. ponytail: one peek per rise; delete this
        ::  line once every released ship has risen past it.
        ;<  ~  bind:m  (cull-if-there (rf root mail-dir %blobvis))
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
        ;<  ~  bind:m  (rise-wait:io prod "%auspex fetch: failed")
        (run-fetch (lent path.rail) name.rail)
      ::  /probe/*: one EPHEMERAL fiber per discovery keen. It reads its
      ::  own grub - a $peer-rec with proto=~, the question rather than
      ::  the answer - keens the peer's /proto, pokes the completed
      ::  record at the writer and ends. It writes nothing: the writer
      ::  is still the only thing that mutates the tree, including
      ::  culling this request.
          [[%probe ~] @]
        ;<  ~  bind:m  (rise-wait:io prod "%auspex probe: failed")
        (run-probe (lent path.rail) name.rail)
      ::  /keys/probe: THE ONE FIBER THAT IS ALLOWED TO DIE.
      ::
      ::  Its whole job is to find out whether this instance was
      ::  granted /sys/scry, and the only way to find that out is to
      ::  reach for it: no arm asks the shell what our weir holds, and
      ::  a veto is not catchable - lib/fiberio.hoon answers [~ %veto *]
      ::  with [%fail (veto-error ...)] in +typed-scry, in +keen and in
      ::  the +take-pack every poke ends on, the -soft arms included.
      ::  So the probe is the reach, and the answer arrives either as a
      ::  poke at the writer or as an absence.
      ::
      ::  EPHEMERAL, AND NOT ON THE WRITER. A failed process is
      ::  RESTARTED by grubbery - immediately, with `prod` set - so a
      ::  vetoed scry on a long-lived sig fiber is an infinite
      ::  full-speed crash loop: 100% CPU and no HTTP. +rise-wait is
      ::  what makes the restart harmless: on a restart it BLOCKS on a
      ::  poke that will never come, so the restarted process parks
      ::  instead of reaching again. That is the /fetch and /probe
      ::  discipline exactly, and it is why this is a grub of its own
      ::  rather than three lines at the top of the writer.
          [[%keys ~] %probe]
        ;<  ~  bind:m  (rise-wait:io prod "%auspex key probe: no key road")
        (run-key-probe (lent path.rail))
      ::  /ui/main.sig: bind the HTTP endpoint and dispatch each request
      ::  into its own fiber under /ui/requests. This fiber never touches
      ::  the mail tree; it only routes.
          [[%ui ~] %'main.sig']
        ;<  ~  bind:m  (rise-later prod "%auspex /ui/main: failed")
        ::  bind-http-self, not bind-http: the latter calls +get-here-abs
        ::  to learn where it is, which a sandboxed app may not do. Its
        ::  own docs name this case - 'so a nexus serving its own UI needs
        ::  no walk to root' - and it is veto-tolerant besides, so a jailed
        ::  install logs the refusal and lands in its request loop instead
        ::  of parking the fiber. The approval reload re-runs the bind with
        ::  grants in hand, which is why consent alone brings the UI up.
        ;<  ~  bind:m  (bind-http-self:io [~ /apps/auspex])
        (http-dispatch:io %auspex)
      ::  /ui/requests/*: one ephemeral fiber per in-flight HTTP request.
          [[%ui %requests ~] @]
        ;<  ~  bind:m  (rise-wait:io prod "%auspex /ui/requests: failed")
        (handle-request name.rail)
      ==
    --
|%
::  ── the console ─────────────────────────────────────────────────────
::
::  A ship that is working prints nothing. A line means something left
::  its normal range and a person can act on it; everything else is in
::  the tree (/caps, /tr/last, /tr/discovery) or behind +dbg.
::
::  +dbg: the routine traces print only when this is yes.
::
++  dbg  ^-(? |)
::  +say: a routine trace. Silent unless +dbg, and never with a marker.
::
++  say
  |=  msg=tape
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?.  dbg  (pure:m ~)
  (trace:io ~[leaf+msg])
::  +warn: one line at >>, for a degradation a person can act on.
::
++  warn
  |=  msg=tape
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ~>  %slog.[2 leaf+msg]
  (pure:m ~)
::  ── paths ───────────────────────────────────────────────────────────
::
::  ROADS HERE ARE NEXUS-RELATIVE, and `root` is not a path any more: it
::  is the number of steps from the calling fiber UP to the nexus root.
::
::    A sandboxed install cannot learn its own absolute path, and that is
::    the sandbox working rather than a gap. +walk-here reveals only the
::    ancestors a grub may peek and then stops, +coerce-here asserts
::    `?> root.here` on what it got, and a desk-installed app fails that
::    assertion - so every fiber that opened with +get-here-abs crashed on
::    its first line, respawned, and crashed again.
::
::    So: no absolute roads. [%| steps lane] climbs `steps` to the nexus
::    root and descends into `lane`, which is what +nex-road:io does and
::    what every nexus upstream ships uses - wallet, mcp and the shell
::    build roads this way and call +get-here-abs zero, zero and twice.
::
::    The step count is (lent path.rail) at the fiber's own dispatch arm,
::    which is exact: a request fiber at <root>/ui/requests/<id> reads 2.
::    The old +nexus-root computed the same number and then threw it away
::    in favour of a path it had to ask permission to learn.
::
::  +rf, +rv: a file road and a directory road, `up` steps from here.
::
++  rf  |=([up=@ud p=path n=@ta] ^-(road:tarball [%| up [%& p n]]))
++  rv  |=([up=@ud p=path] ^-(road:tarball [%| up [%| p]]))
::  The directories are CONSTANTS: nexus-relative paths that need no
::  depth. Only a road needs `up`, so only the rails take it.
::
++  mail-dir    ^-(path /mail)
++  thread-dir  ^-(path /mail/thread)
++  tdir        |=(t=thread-id:uc ^-(path (weld thread-dir /[(scot %uv t)])))
++  mdir        |=(t=thread-id:uc ^-(path (weld (tdir t) /msg)))
++  blob-dir    ^-(path /mail/blob)
++  blob-rail   |=([root=@ud h=@uv] ^-(road:tarball (rf root blob-dir (scot %uv h))))
++  draft-dir   ^-(path /mail/draft)
++  rule-dir    ^-(path /mail/rule)
++  list-dir    ^-(path /mail/list)
++  draft-rail  |=([root=@ud i=@uv] ^-(road:tarball (rf root draft-dir (scot %uv i))))
++  rule-rail   |=([root=@ud i=@uv] ^-(road:tarball (rf root rule-dir (scot %uv i))))
::  +list-rail: the grub for one list. The NAME IS THE SEGMENT, cast
::  straight to a knot rather than scotted: +list-name-ok:uw has already
::  refused everything a knot cannot hold - anything but a-z, 0-9 and
::  '-', an empty name, and anything over 64 bytes - and it is checked
::  at the route AND again at the writer, so this cast never sees a
::  name that was not admitted by both.
++  list-rail   |=([root=@ud n=@t] ^-(road:tarball (rf root list-dir `@ta`n)))
++  meta-rail   |=([root=@ud t=thread-id:uc] ^-(road:tarball (rf root (tdir t) %meta)))
++  settings-rail  |=(root=@ud ^-(road:tarball (rf root mail-dir %settings)))
::  +caps-rail: the one grub every jael reach is gated on, at the nexus
::  root. See the /caps row in +on-load and $caps:uc.
++  caps-rail   |=(root=@ud ^-(road:tarball (rf root / %caps)))
::  the discovery cache and the ephemeral probe that fills it. Two roads,
::  one $peer-rec shape - see mar/auspex/peer.hoon for why.
++  peer-dir    ^-(path /mail/peer)
++  peer-rail   |=([root=@ud who=ship] ^-(road:tarball (rf root peer-dir (scot %p who))))
++  probe-dir   ^-(path /probe)
++  probe-rail  |=([root=@ud who=ship] ^-(road:tarball (rf root probe-dir (scot %p who))))
++  slot  slot:uc
++  node-dir  node-dir:uc
++  sorted-dirs  sorted-dirs:uc
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
  |=  [up=@ud pax=path]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  road=road:tarball  (rv up pax)
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
  |=  [up=@ud dir=path ps=(list path)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  ps  (pure:m ~)
  ;<  ~  bind:m  (ensure-dir up (weld dir i.ps))
  (ensure-nodes up dir t.ps)
::
++  ensure-thread
  |=  [root=@ud t=thread-id:uc]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  ~  bind:m  (ensure-dir root thread-dir)
  ;<  ~  bind:m  (ensure-dir root (tdir t))
  ;<  ~  bind:m  (ensure-dir root (mdir t))
  ::  lay a default meta so EVERY thread has the leaf the tree says it
  ::  has. A delivered thread is never marked read, so nothing else would
  ::  ever create one, and a reader would find the leaf missing rather
  ::  than empty. Guarded, so it never clobbers real read marks.
  ;<  ex=?  bind:m  (peek-exists:io (meta-rail root t))
  ?:  ex  (pure:m ~)
  (put-file (meta-rail root t) [/auspex %meta] *meta:uc)
::
::  ── reads ───────────────────────────────────────────────────────────
::
::  THE `;;` LADDERS. Each persisted marc is a noun passthrough, so what
::  comes back is a raw noun and the SHAPE CHECK LIVES HERE, newest shape
::  first; a later version adds a branch and upgrades in place. Doing it
::  in the marc instead would re-validate every stored grub against the
::  live type on read, booming every message the day the type moves.
::
::  +peek-noun: one grub's noun, ~ when it is absent, not a file, or a
::  boom. Every single-grub reader below is this and then its ladder.
::
++  peek-noun
  |=  =road:tarball
  =/  m  (fiber:fiber:nexus ,(unit *))
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io road ~)
  ?.  ?=([%file *] vw)  (pure:m ~)
  ?:  (is-boom:tarball sang.vw)  (pure:m ~)
  (pure:m `(sang-noun:tarball sang.vw))
::
::  +read-leaves: the nouns of every readable file directly in one
::  directory, in one peek. A grub that does not clam is DROPPED by the
::  caller's ladder, never crashed on: these run on the writer and on
::  request fibers, and neither may fail on one bad grub.
::
++  read-leaves
  |=  [root=@ud dir=path]
  =/  m  (fiber:fiber:nexus ,(list *))
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io (rv root dir) ~)
  ?.  ?=([%ball *] vw)  (pure:m ~)
  ?~  fil.ball.vw  (pure:m ~)
  %-  pure:m
  %+  murn  ~(val by contents.u.fil.ball.vw)
  |=  c=[=sang:tarball gain=? bang=(unit tang)]
  ?:((is-boom:tarball sang.c) ~ `(sang-noun:tarball sang.c))
++  read-stored  read-stored:uc
::
::  +read-meta: the local-state ladder, which DOES upgrade in place - see
::  +meta-from-noun:uc, which the marc reads through too.
::
++  read-meta
  |=  [root=@ud t=thread-id:uc]
  =/  m  (fiber:fiber:nexus ,meta:uc)
  ^-  form:m
  ;<  n=(unit *)  bind:m  (peek-noun (meta-rail root t))
  (pure:m (fall (biff n meta-from-noun:uc) *meta:uc))
::
::  +read-settings: the owner's attachment settings, or the defaults -
::  which download nothing on their own - when none were ever saved.
::
++  read-settings
  |=  root=@ud
  =/  m  (fiber:fiber:nexus ,settings:uc)
  ^-  form:m
  ;<  n=(unit *)  bind:m  (peek-noun (settings-rail root))
  (pure:m (fall (biff n |=(x=* (mole |.(;;(settings:uc x))))) *settings:uc))
::
++  read-drafts
  |=  root=@ud
  =/  m  (fiber:fiber:nexus ,(list draft:uc))
  ^-  form:m
  ;<  ns=(list *)  bind:m  (read-leaves root draft-dir)
  (pure:m (murn ns |=(n=* (mole |.(;;(draft:uc n))))))
::
++  read-draft
  |=  [root=@ud i=@uv]
  =/  m  (fiber:fiber:nexus ,(unit draft:uc))
  ^-  form:m
  ;<  n=(unit *)  bind:m  (peek-noun (draft-rail root i))
  (pure:m (biff n |=(x=* (mole |.(;;(draft:uc x))))))
::
++  read-rules
  |=  root=@ud
  =/  m  (fiber:fiber:nexus ,(list rule:uc))
  ^-  form:m
  ;<  ns=(list *)  bind:m  (read-leaves root rule-dir)
  (pure:m (murn ns |=(n=* (mole |.(;;(rule:uc n))))))
::
::  +read-lists: every mailing list, as [name members] pairs.
::
::    The ONE reader here that has to keep the map's KEY, because a
::    list's name is its path segment and is deliberately not a field of
::    the grub. So this taps the contents map rather than going through
::    +read-leaves.
::
++  read-lists
  |=  root=@ud
  =/  m  (fiber:fiber:nexus ,(list [name=@t members=(set @p)]))
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io (rv root list-dir) ~)
  ?.  ?=([%ball *] vw)  (pure:m ~)
  ?~  fil.ball.vw  (pure:m ~)
  %-  pure:m
  %+  murn  ~(tap by contents.u.fil.ball.vw)
  |=  [nom=@ta =sang:tarball gain=? bang=(unit tang)]
  ^-  (unit [@t (set @p)])
  ?:  (is-boom:tarball sang)  ~
  %+  bind  (mole |.(;;(mail-list:uc (sang-noun:tarball sang))))
  |=(l=mail-list:uc [`@t`nom members.l])
::
++  read-idx
  |=  root=@ud
  =/  m  (fiber:fiber:nexus ,mail-idx:uc)
  ^-  form:m
  ;<  n=(unit *)  bind:m  (peek-noun (rf root mail-dir %idx))
  (pure:m (fall (biff n |=(x=* (mole |.(;;(mail-idx:uc x))))) *mail-idx:uc))
::
::  +read-blob: one attachment's bytes, ~ when we do not hold them.
::
++  read-blob
  |=  [root=@ud h=@uv]
  =/  m  (fiber:fiber:nexus ,(unit octs))
  ^-  form:m
  ;<  n=(unit *)  bind:m  (peek-noun (blob-rail root h))
  (pure:m (bind (biff n blob-from-noun:uc) |=(b=stored-blob:uc octs.b)))
::
::  +read-peer: what we last learned about one ship, ~ when we have never
::  asked or the grub is unreadable.
::
::    A peek and not a scry: the record is ours, it is in our own tree,
::    and both the writer and a request fiber read it. An unreadable
::    grub answers ~ - which means "ask again", the safe direction -
::    rather than crashing a fiber that must not fail on one bad grub.
::
++  read-peer
  |=  [root=@ud who=ship]
  =/  m  (fiber:fiber:nexus ,(unit peer-rec:uc))
  ^-  form:m
  ;<  n=(unit *)  bind:m  (peek-noun (peer-rail root who))
  (pure:m (biff n |=(x=* (mole |.(;;(peer-rec:uc x))))))
++  known-proto  known-proto:uc
::
::  +read-probe: the discovery in flight for one ship, and the mail
::  queued behind it. ~ when there is none.
::
::    Read defensively for the same reason every other ladder here is:
::    a grub that does not clam answers ~, and ~ here means "start a
::    fresh probe", which loses the queue but never wedges the fiber.
::    +run-probe reads the same grub and recovers the same way.
::
++  read-probe
  |=  [root=@ud who=ship]
  =/  m  (fiber:fiber:nexus ,(unit probe-req:uc))
  ^-  form:m
  ;<  n=(unit *)  bind:m  (peek-noun (probe-rail root who))
  (pure:m (biff n |=(x=* (mole |.(;;(probe-req:uc x))))))
::
::  +list-blobs: every blob this ship holds, with its age and weight.
::
::    The store's whole bookkeeping. Both bounds - max-blobs by count and
::    the $settings budget by weight - are computed off this, and so is
::    the eviction order.
::
::    Neither bound can be weaponised: bytes only ever enter through a
::    LOCAL decision (an upload, a %fetch-blob, or a download rule the
::    owner set), never because a delivered chain named them.
::
++  list-blobs
  |=  root=@ud
  =/  m  (fiber:fiber:nexus ,(list blob-row:uc))
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io (rv root blob-dir) ~)
  ?.  ?=([%ball *] vw)  (pure:m ~)
  ?~  fil.ball.vw  (pure:m ~)
  %-  pure:m
  %+  murn  ~(tap by contents.u.fil.ball.vw)
  |=  [nm=@ta c=[=sang:tarball gain=? bang=(unit tang)]]
  ^-  (unit blob-row:uc)
  ?:  (is-boom:tarball sang.c)  ~
  =/  hh=(unit @uv)  (slaw %uv nm)
  ?~  hh  ~
  =/  st  (blob-from-noun:uc (sang-noun:tarball sang.c))
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
  |=  root=@ud
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
  |=  [root=@ud bytes=@ud]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  held=(list blob-row:uc)  bind:m  (list-blobs root)
  ;<  s=settings:uc  bind:m  (read-settings root)
  ::  THE FAST PATH FIRST. +shed-for answers [& ~] without looking at
  ::  the references whenever the store fits, and the references are a
  ::  walk of every message on the ship - which only a full store needs.
  ?:  =([& ~] (shed-for:uc held ~ 1 bytes budget.s))  (pure:m &)
  ;<  refs=(set @uv)  bind:m  (all-referenced root)
  =/  plan  (shed-for:uc held refs 1 bytes budget.s)
  ?.  ok.plan  (pure:m |)
  ;<  ~  bind:m  (evict root drop.plan)
  (pure:m &)
::
++  evict
  |=  [root=@ud hs=(list @uv)]
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
  |=  root=@ud
  =/  m  (fiber:fiber:nexus ,(map thread-id:uc (map path stored-msg:uc)))
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io (rv root thread-dir) ~)
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
::    a PRE-TREE grub, from before this layout. It reads back perfectly -
::    nothing downstream of here cares where a copy was stored - and the
::    next delivery into its thread re-places it, because +sync-slots
::    culls what +want-slots does not name.
::
++  collect-slots
  |=  kid=ball:tarball
  ^-  (map path stored-msg:uc)
  ss:(slots-of kid)
::
::  +slots-of: one thread's copies AND how many of its copies no reader
::  can produce, out of ONE walk of its msg/ directory.
::
::    +read-stored refuses %0 and %1 grubs rather than upgrading them,
::    and that decision is right and stays. But refusing SILENTLY is a
::    different thing: every message stored before the body-mime break
::    would simply vanish from the API while its thread's meta and its
::    /mail/idx entry survived - a thread that renders short, or empty,
::    with nothing anywhere saying why. The count is what turns "your
::    mail is gone" into "this ship cannot read N messages here".
::
::    It DIVES INTO msg/, where the copies are: the sibling `meta` leaf is
::    a $meta, and counting from the thread ball counted it as one
::    unreadable copy on every ordinary thread on the ship.
::
++  slots-of
  |=  kid=ball:tarball
  ^-  [ss=(map path stored-msg:uc) lost=@ud]
  =/  sub=(unit ball:tarball)  (~(get by dir.kid) %msg)
  ?~  sub  [~ 0]
  (walk-node ~ u.sub)
::
::  +walk-node: one node of the message tree and everything under it.
::
::    Files are this message's signed copies; subdirectories are its
::    replies. A ball keeps those in two separate maps, so the two can
::    never collide however the names are chosen - which is the whole
::    reason a node can be both a message and a parent.
::
::    The file +roll starts from the empty pair, and each child's result
::    is ADDED to this node's rather than folded from a fresh bunt - the
::    shape that once made every count here zero.
::
++  walk-node
  |=  [base=path b=ball:tarball]
  ^-  [ss=(map path stored-msg:uc) lost=@ud]
  =/  here=[ss=(map path stored-msg:uc) lost=@ud]
    ?~  fil.b  [~ 0]
    %+  roll  ~(tap by contents.u.fil.b)
    |=  $:  [nm=@ta c=[=sang:tarball gain=? bang=(unit tang)]]
            acc=[ss=(map path stored-msg:uc) lost=@ud]
        ==
    =/  s=(unit stored-msg:uc)
      ?:  (is-boom:tarball sang.c)  ~
      (read-stored (sang-noun:tarball sang.c))
    ?~  s  acc(lost +(lost.acc))
    acc(ss (~(put by ss.acc) (snoc base nm) u.s))
  =/  kids=(list [seg=@ta kid=ball:tarball])  ~(tap by dir.b)
  |-  ^-  [ss=(map path stored-msg:uc) lost=@ud]
  ?~  kids  here
  =/  k  (walk-node (snoc base seg.i.kids) kid.i.kids)
  $(kids t.kids, here [(~(uni by ss.here) ss.k) (add lost.here lost.k)])
++  chain-of  chain-of:uc
++  verdicts-of  verdicts-of:uc
++  key-threads  key-threads:uc
::
::  ── the trace grub ──────────────────────────────────────────────────
::
++  note
  |=  [root=@ud stage=@t ok=? why=@t]
  (note-at root %last stage ok why)
::
::  +note-at: the same, at a named trace grub. Discovery writes its own
::  rather than sharing /tr/last - see the /tr/discovery row.
::
++  note-at
  |=  [root=@ud name=@ta stage=@t ok=? why=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  now=@da  bind:m  bowl-now
  %^  put-file  (rf root /tr name)  [/ %json]
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
  |=  [root=@ud why=@t]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  ~  bind:m  (say "auspex: rejected: {(trip why)}")
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
::    address any marc at it, %auspex-action included. +apply's source
::    check is what makes that harmless, and it is the same check the
::    agent's `?>  =(our.bowl src.bowl)` was.
::
::  +grant-public: put our writer in the public usergroup so another ship
::  may poke it. desk.hoon reaches for +get-here-abs at this exact spot
::  and may, being a host-layer nexus; we register +writer-rail instead.
::  If the group is absent the arm already says so and delivery stays
::  local, which is the honest degradation rather than a crash.
::  +exists-soft: +peek-exists, but a VETO answers no instead of killing
::  the fiber. +peek-soft handles [~ %veto *] with [%done ~]; the hard
::  peek does not, and the writer is not a fiber that may die - a crashed
::  sig fiber respawns, so one refused road is a crash loop.
::
::  This is what makes the usergroup roads OPTIONAL rather than required.
::  An install that was not granted them delivers locally and says so,
::  which is the degradation the weir.json copy promises.
::
++  exists-soft
  |=  =road:tarball
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  vw=(unit view:nexus)  bind:m  (peek-soft:io road ~)
  ?~  vw  (pure:m %.n)
  (pure:m !?=(?(%none %miss %veto %tomb) -.u.vw))
::
++  grant-public
  |=  root=@ud
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  gdir=road:tarball  [%& %| /sys/ames/usergroups/'public.grp']
  ;<  ok=?  bind:m  (exists-soft gdir)
  ?.  ok
    (warn "auspex: other ships cannot deliver mail here: no public usergroup is reachable; grant /sys/ames/usergroups/ at /apps/grubbery/permits, then reload")
  ::  SOFT, both of them. A veto is a crashed event, so it rolls back
  ::  whatever this fiber already wrote - and that is not hypothetical
  ::  here: /sys/ames/registry was missing from weir.json, the key probe's
  ::  %set-caps landed, +do-set-caps wrote /caps and then ran rise work
  ::  that reached this arm, and the veto took the /caps write with it. The
  ::  app then reported "not granted the key road" on a ship where that
  ::  road WAS granted.
  ::
  ::  The arm already degrades honestly when there is no usergroup; these
  ::  make it degrade the same way when the ROAD is refused, which is what
  ::  the weir.json copy above promises.
  ;<  reg=(unit tang)  bind:m  (reg-register-at-soft:io writer-rail)
  ?^  reg
    (warn "auspex: other ships cannot deliver mail here: the registry road is refused; grant /sys/ames/registry at /apps/grubbery/permits, then reload")
  ;<  how=(unit tang)  bind:m
    %+  reg-how-soft:io  /public
    [make=~ poke=(sy ~[`road:tarball`(rf root / %'main.sig')]) peek=~]
  ?~  how  (pure:m ~)
  (warn "auspex: other ships cannot deliver mail here: the registry refused the public grant")
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
  |=  [root=@ud =from:fiber:nexus =sage:tarball]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ::  a chain from ANYONE. src is deliberately not checked against the
  ::  participants: the signatures are the authority, not the courier.
  =/  kind  (poke-kind:uc p.sage)
  ?:  ?=(%chain kind)
    ::  counted before the clam, because the clam is the walk a shared
    ::  subtree multiplies. Not in the marc, where a refusal fails and
    ::  restarts the writer. See +max-cells.
    ?.  (cells-within:uc q.q.sage max-cells:uc)
      (reject root 'chain too large')
    =/  res  (mule |.(~|(%auspex-bad-chain ;;(chain:uc q.q.sage))))
    ?:  ?=(%| -.res)  (reject root 'malformed chain')
    (deliver root p.res)
  ::  an unknown blot. Ignore it rather than crash - see the header.
  ?:  ?=(%other kind)  (pure:m |)
  ;<  our=@p  bind:m  bowl-our
  ::  +get-poke-src reads the SHIP off the transport, never the payload.
  ::  ~ is a fiber inside this nexus; our own ship arrives named, because
  ::  the agent-facing surface makes every caller a /sys/ames/ships/<who>.
  =/  src=(unit @p)  (get-poke-src:io from)
  ?.  (may-act:uc our src)
    (reject root 'foreign action refused')
  ::  a fetch fiber's answer. Local-only for the same reason an action
  ::  is: the blot has a path prefix, which the agent-facing surface and
  ::  a dojo poke cannot name, but a peer poking over ames can - so the
  ::  source check is what makes that harmless. The hash is re-checked
  ::  in +take-blob regardless.
  ?:  ?=(%blob-in kind)
    =/  res  (mule |.(~|(%auspex-bad-blob-in ;;(blob-in:uc q.q.sage))))
    ?:  ?=(%| -.res)  (reject root 'malformed blob-in')
    (take-blob root p.res)
  ::  a probe fiber's answer. Local-only for the same reason a fetch
  ::  fiber's is, and by the same check: the blot has a path prefix,
  ::  which the agent-facing surface and a dojo poke cannot name, but a
  ::  peer poking over ames can - and a peer that could write our
  ::  discovery cache could tell us it speaks a version it does not, or
  ::  caps larger than it enforces, and either one turns a send into a
  ::  message that vanishes.
  ?:  ?=(%probe kind)
    =/  res  (mule |.(~|(%auspex-bad-probe ;;(probe-req:uc q.q.sage))))
    ?:  ?=(%| -.res)  (reject root 'malformed probe result')
    (take-probe-done root p.res)
  =/  res  (mule |.(~|(%auspex-bad-action ;;(action:uc q.q.sage))))
  ?:  ?=(%| -.res)  (reject root 'malformed action')
  (act root p.res)
::
++  act
  |=  [root=@ud a=action:uc]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ?-  -.a
    ::  +do-send bumps the beacon itself, from before its fan-out, so a
    ::  local reader never waits on a remote ship - and answers %.n so the
    ::  writer's loop does not bump a second time.
    %send           (do-send root to.a subject.a body.a prev.a refs.a)
    %read           (do-mark root ids.a tid.a %read &)
    %delete-thread  (do-delete root thread-id.a)
    %fetch-blob     (do-fetch-blob root hash.a from.a)
  ::  %forget-peer drops one discovery record so the next send re-probes.
  ::  %.n like every other local-state action: no message appeared, none
  ::  changed, and the tab that asked for it is the only one waiting.
    %forget-peer    (do-forget-peer root who.a)
  ::  the mail-client layer. EVERY ONE OF THESE ANSWERS %.n, and that is
  ::  not an oversight. The beacon tells OTHER open readers that content
  ::  moved; a label, an archive, an unread mark, a draft and a rule are
  ::  local state on a thread nobody else can see. Bumping for them would
  ::  cost every open tab a full inbox listing plus a thread refetch for
  ::  a change it cannot observe - the read-mark storm again, and the tab
  ::  that made the change refetches on its own anyway.
    %label          (do-label root thread-id.a label.a add.a)
    %archive        (do-archive root thread-id.a archived.a)
    %unread         (do-mark root ids.a tid.a %read |)
    %fold           (do-mark root ids.a tid.a %folded &)
    %unfold         (do-mark root ids.a tid.a %folded |)
    %save-draft     (do-save-draft root draft.a)
    %delete-draft   (do-delete-leaf root (draft-rail root id.a) 'delete-draft' id.a)
    %save-rule      (do-save-rule root rule.a)
    %delete-rule    (do-delete-leaf root (rule-rail root id.a) 'delete-rule' id.a)
  ::  mailing lists, local state like the rest of this block and %.n for
  ::  the same reason: a list is an address book entry on this ship, no
  ::  peer can observe it, and the tab that saved it refetches its own
  ::  listing. Bumping here would cost every open tab a full inbox
  ::  listing plus a thread refetch for a change nobody else can see.
    %save-list      (do-save-list root name.a members.a)
    %delete-list    (do-delete-list root name.a)
    %save-settings  (do-save-settings root settings.a)
  ::  the key road. Raised by the probe, and forceable from the dojo -
  ::  see +do-set-caps for why that seam is the honest way to reach the
  ::  degraded paths at all. %.n like every other local-state action.
    %set-caps       (do-set-caps root keys.a)
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
::    ATTACHMENTS ARE NAMED, NOT CARRIED. The browser uploaded each file
::    to POST /api/blob first, which hashed and stored it; `refs` names
::    those addresses. THE SIZE THAT GETS SIGNED IS READ OFF THE STORED
::    BLOB, never off the request, and the hash is not re-derived: the
::    store only ever accepted a blob that hashed to its own address, so
::    re-hashing here would pay for a fact the store already guarantees,
::    while trusting a client's `size` would let one sign a length the
::    bytes do not have.
::
::    The bounds +deliver enforces are enforced here too. Every send ships
::    the path it is replying into, so one oversized compose would poison
::    a thread permanently: every later message on that path rejected by
::    every recipient, silently, forever. Failing at compose time is the
::    only point where a human can still do something about it.
::
::    ANSWERS %.n, ALWAYS: this arm bumps the beacon itself, from
::    inside, before the fan-out. See the end.
::
++  do-send
  |=  $:  root=@ud
          to=(set ship)
          subject=@t
          body=@t
          prev=(unit msg-id:uc)
          refs=(list attach-ref:uc)
      ==
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ::  THE KEY ROAD, CHECKED BEFORE ANYTHING IS SIGNED OR STORED.
  ::
  ::    Signing needs jael twice - %j /life for our life and %j /vein
  ::    for the ring - and both go down /sys/scry. Denied, those two
  ::    binds are a VETO, and a veto is not a nack: it fails the fiber,
  ::    and this fiber is /main.sig, the ship's single serialisation
  ::    point for mail. So the send is refused HERE, at the top, where
  ::    nothing has been written: no thread made, no copy filed, no
  ::    beacon moved.
  ::
  ::    +do-web-send refuses the same send at the route with the same
  ::    words, so the composer stays open - but a route check is not a
  ::    substitute for this one: a dojo poke arrives without passing it.
  ;<  may=?  bind:m  (may-scry root)
  ?.  may
    (reject root 'this ship cannot sign mail: Auspex has not been granted the key road')
  =/  bad=(unit @t)  (compose-refusal:uc body subject to)
  ?^  bad  (reject root u.bad)
  ::  A ref naming no stored blob refuses the WHOLE send: nothing is
  ::  signed. The route has already answered 400 with the hash; this is
  ::  the point-of-use half, for the other callers and for a blob evicted
  ::  between the route's check and this one.
  ;<  as=(unit (list attachment:uc))  bind:m  (resolve-refs root refs)
  ?~  as  (reject root 'unknown attachment')
  ?.  (attaches-ok:uc u.as)
    (reject root 'bad attachment')
  ;<  loaded=(map thread-id:uc (map path stored-msg:uc))  bind:m  (read-threads root)
  ::  resolve prev to its containing thread. A msg-id is a hash over the
  ::  message's full contents, so it names exactly one message and
  ::  therefore exactly one chain.
  ::
  ::  ponytail: a walk of every thread per reply, the one writer walk left
  ::  on the send path; a [msg-id -> thread-id] index grub retires it.
  =/  tid=(unit thread-id:uc)  ?~(prev ~ (thread-holding:uc loaded u.prev))
  ?:  &(?=(^ prev) ?=(~ tid))
    (reject root 'unknown prev')
  =/  ss=(map path stored-msg:uc)  ?~(tid ~ (~(gut by loaded) u.tid ~))
  ::  NOTHING ANSWERS A MESSAGE THAT HAS ONLY FORGED COPIES. `prev` picks
  ::  the path that travels, so a reply to a forgery would ship a message
  ::  nobody wrote as the parent of ours - and anyone can poke us a
  ::  forged copy of an id. The clients refuse to offer it; this is where
  ::  it is actually refused.
  ?.  (honest-copy:uc ss prev)
    (reject root 'every copy of the message this answers is forged')
  ;<  our=@p    bind:m  bowl-our
  ;<  now=@da   bind:m  bowl-now
  ;<  lyf=@ud   bind:m  (our-life our)
  ;<  rng=ring  bind:m  (our-ring lyf)
  ::  `as` goes INSIDE `unsigned`, so it is covered by the signature and
  ::  by msg-id: swapping a file breaks the signature. body-mime is '',
  ::  which is text/plain: every body this nexus signs is one.
  =/  u=unsigned:uc  [our lyf to subject body '' now prev u.as]
  =/  mg=msg:uc     [u (sign-with:uc rng (digest:uc u))]
  ::  `full` is the whole stored thread, every branch of it; `old` is the
  ::  ONE PATH this message answers, root to `prev`. The difference
  ::  between them is exactly what no longer travels.
  =/  full=chain:uc  (chain-of ss)
  =/  old=chain:uc
    ?~  prev  ~
    (with-root:uc full (path-chain:uc full u.prev))
  =/  new=chain:uc  (merge:uc old ~[mg])
  ::  the outgoing chain must clear the same length bound the recipient
  ::  will apply on arrival, or the send is a silent no-op at the far end
  ::  while looking successful here.
  ::  and the same for depth, for the same reason: a reply past the cap
  ::  would be stored here and refused by every recipient, silently.
  ::  and the same for signers. A thread can only exceed the cap through
  ::  our own sends, since delivery refuses such a chain on arrival, so
  ::  this is unreachable in practice - which is the point: it fails
  ::  LOUDLY here, at the one moment a human is looking, instead of
  ::  succeeding locally and being discarded by every recipient.
  ::  (all three are +sent-refusal's, in this order)
  =/  big=(unit @t)  (sent-refusal:uc new)
  ?^  big  (reject root u.big)
  ::  the thread is already resolved: `tid` came from `prev`, which names
  ::  exactly one message, and a compose is by definition a new root.
  ::  Re-deriving it with +thread-key here would be slower AND wrong -
  ::  it returns the first map-traversal match, so a coincidental [id sig]
  ::  overlap with another thread would file this send into that thread.
  ::  Nothing here is attacker-supplied, so no identity fixing is needed.
  =/  rid=thread-id:uc  ?^(tid u.tid (id:uc u))
  ;<  ~  bind:m  (ensure-thread root rid)
  ::  where this message sits in the tree: its own ancestry, root first.
  ::  Derived from `prev` against the WHOLE thread, not against the path
  ::  that travels - the two agree, and the whole thread is what is
  ::  actually on disk.
  =/  place=(list msg-id:uc)  (place-of:uc (merge:uc full ~[mg]) (id:uc u))
  ;<  ~  bind:m  (write-msg root rid place mg %verified)
  ;<  ~  bind:m  (mark-read root rid (sy ~[(id:uc u)]) %read &)
  ;<  ~  bind:m  (touch-idx root rid)
  ;<  ~  bind:m  (note root 'send' & (scot %uv rid))
  ::  BUMP BEFORE THE FAN-OUT. Everything local has landed by here. A
  ::  local reader must never wait on a remote ship. This arm answers
  ::  %.n below so the writer's loop does not bump a second time, which
  ::  is what keeps a send to exactly one bump.
  ;<  ~  bind:m  (bump-beacon root)
  ::  ship the PATH to every recipient. A ship added at message forty
  ::  receives the forty on this path, each independently verifiable,
  ::  and nothing off it.
  ;<  ~  bind:m  (fan-out root new now ~(tap in (~(del in to) our)))
  ::  %.n: the beacon already moved, above.
  (pure:m |)
::
::  +resolve-refs: each named blob's SIGNED metadata, or ~ if any is
::  missing. The size is read off the bytes this ship holds.
::
::    Recursion by ARM NAME, not $: a $ with arguments inside a ;<
::    continuation cannot find the trap.
::
++  resolve-refs
  |=  [root=@ud rs=(list attach-ref:uc)]
  =/  m  (fiber:fiber:nexus ,(unit (list attachment:uc)))
  ^-  form:m
  ?~  rs  (pure:m `~)
  ;<  o=(unit octs)  bind:m  (read-blob root hash.i.rs)
  ?~  o  (pure:m ~)
  ;<  rest=(unit (list attachment:uc))  bind:m  (resolve-refs root t.rs)
  ?~  rest  (pure:m ~)
  (pure:m `[[name.i.rs p.u.o mime.i.rs hash.i.rs] u.rest])
::
::  +do-mark: mark a SET of messages read (`rd` &) or unread (|), in one
::  pass, with one rewrite of each affected thread's meta however many of
::  its messages were named. `k` picks the set: %read, or %folded for
::  %fold and %unfold, which are the same walk over a different field.
::
::    ONE THREAD IS READ, NOT THE MAILBOX. Opening a thread marks what it
::    shows and the client knows which thread that is, so finding it again
::    by walking every thread cost the writer a full mailbox scan per open.
::
::    Marking a %forged message unread is a no-op on every surface a user
::    sees, and no branch here says so: +entry-json never counts a forged
::    copy as unread, because that is a property of how unread is
::    COMPUTED and not of what is stored.
::
::    %.n ALWAYS, both ways. Read state is not content: lattice learned
::    this with page history, where every visit bumped and every open
::    reader reloaded. It is worse here, because a reader answers a bump
::    by refetching the thread it is showing and that refetch marks it
::    read again - a loop, not a burst.
::
++  do-mark
  |=  [root=@ud ids=(set msg-id:uc) tid=thread-id:uc k=?(%read %folded) rd=?]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ?:  =(~ ids)  (pure:m |)
  ;<  loaded=(map thread-id:uc (map path stored-msg:uc))  bind:m
    (read-one-thread root tid)
  =/  hits  (group-ids loaded ids)
  ?~  hits  (reject root 'unknown message')
  ;<  ~  bind:m  (mark-read-loop root hits k rd)
  (pure:m |)
::
::  +read-one-thread: one thread's copies, in the shape +read-threads
::  answers, so +group-ids reads either.
::
++  read-one-thread
  |=  [root=@ud t=thread-id:uc]
  =/  m  (fiber:fiber:nexus ,(map thread-id:uc (map path stored-msg:uc)))
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io (rv root (tdir t)) ~)
  ?.  ?=([%ball *] vw)  (pure:m ~)
  (pure:m (my ~[[t (collect-slots ball.vw)]]))
++  group-ids  group-ids:uc
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
  |=  [root=@ud t=thread-id:uc l=@tas add=?]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ::  the label is user input arriving as a JSON string. Nothing
  ::  downstream re-checks it - a cord sits in a (set @tas) perfectly
  ::  happily and then crashes `scot %tas` on a request fiber, which is
  ::  an HTTP connection that never answers.
  ?.  (label-ok:uc l)  (reject root 'bad label')
  ;<  ex=?  bind:m  (peek-exists:io (rv root (tdir t)))
  ?.  ex  (reject root 'unknown thread')
  ;<  mt=meta:uc  bind:m  (read-meta root t)
  ::  a no-op writes nothing. Removing a label a thread does not carry
  ::  is a request a client makes freely. (+relabel)
  =/  change  (relabel:uc labels.mt l add)
  ?~  change  (pure:m |)
  ?:  ?=(%| -.u.change)  (reject root p.u.change)
  ;<  ~  bind:m  (put-file (meta-rail root t) [/auspex %meta] mt(labels p.u.change))
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
  |=  [root=@ud t=thread-id:uc arch=?]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  ex=?  bind:m  (peek-exists:io (rv root (tdir t)))
  ?.  ex  (reject root 'unknown thread')
  ;<  mt=meta:uc  bind:m  (read-meta root t)
  ?:  =(arch archived.mt)  (pure:m |)
  ;<  ~  bind:m  (put-file (meta-rail root t) [/auspex %meta] mt(archived arch))
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
::    the send, over the fields as they stand at that moment.
::
::    The id comes from the client and is overwritten in place, so a
::    debounced save costs one grub however many keystrokes it covers.
::
++  do-save-draft
  |=  [root=@ud d=draft:uc]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ::  the send caps, checked at SAVE time. A draft that cannot be sent
  ::  is a message the user loses at the last moment, and the whole
  ::  point of a draft is that nothing is lost.
  ?.  (draft-ok:uc d)  (reject root 'bad draft')
  ;<  ~  bind:m  (ensure-dir root draft-dir)
  ;<  ds=(list draft:uc)  bind:m  (read-drafts root)
  ::  the store bound counts only a draft we do not already hold, so
  ::  re-saving an existing draft is never refused for capacity.
  ?.  ?|  (lien ds |=(o=draft:uc =(id.o id.d)))
          (lth (lent ds) max-drafts:uc)
      ==
    (reject root 'too many drafts')
  ;<  ~  bind:m  (put-file (draft-rail root id.d) [/auspex %draft] d)
  ;<  ~  bind:m  (note root 'save-draft' & (scot %uv id.d))
  (pure:m |)
::
::  +do-delete-leaf: cull one draft or rule. The two deletes differ in
::  nothing but the road and the trace label.
::
++  do-delete-leaf
  |=  [root=@ud =road:tarball stage=@t i=@uv]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  ~  bind:m  (cull-if-there road)
  ;<  ~  bind:m  (note root stage & (scot %uv i))
  (pure:m |)
::
::  ── filters ─────────────────────────────────────────────────────────
::
++  do-save-rule
  |=  [root=@ud r=rule:uc]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ::  a rule with no condition matches every delivered chain, and with
  ::  `archive` set would empty the inbox permanently and silently.
  ?.  (rule-ok:uc r)  (reject root 'bad rule')
  ;<  ~  bind:m  (ensure-dir root rule-dir)
  ;<  rs=(list rule:uc)  bind:m  (read-rules root)
  ::  every rule is evaluated against every delivered chain, ON THE
  ::  WRITER, which is the ship's single serialisation point for mail.
  ?.  ?|  (lien rs |=(o=rule:uc =(id.o id.r)))
          (lth (lent rs) max-rules:uc)
      ==
    (reject root 'too many rules')
  ;<  ~  bind:m  (put-file (rule-rail root id.r) [/auspex %rule] r)
  ;<  ~  bind:m  (note root 'save-rule' & (scot %uv id.r))
  (pure:m |)
::
++  do-save-settings
  |=  [root=@ud s=settings:uc]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ?.  (settings-ok:uc s)  (reject root 'bad settings')
  ;<  ~  bind:m  (put-file (settings-rail root) [/auspex %settings] s)
  ;<  ~  bind:m  (note root 'save-settings' & '')
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
  |=  [root=@ud name=@t members=(set @p)]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ?.  (list-name-ok:uw name)  (reject root 'bad list name')
  ;<  our=@p  bind:m  bowl-our
  ::  never our own ship, and a list larger than a send may carry is a
  ::  list that cannot be used (+members-refusal)
  =/  bad=(unit @t)  (members-refusal:uc members our)
  ?^  bad  (reject root u.bad)
  ;<  ~  bind:m  (ensure-dir root list-dir)
  ;<  ls=(list [name=@t members=(set @p)])  bind:m  (read-lists root)
  ::  the store bound counts only a list we do not already hold, so
  ::  overwriting an existing list is never refused for capacity - which
  ::  is the whole copy-from-a-message flow at the cap.
  ?:  (lists-full:uc ls name)
    (reject root 'too many lists')
  ;<  ~  bind:m
    (put-file (list-rail root name) [/auspex %list] `mail-list:uc`[%0 members])
  ;<  ~  bind:m  (note root 'save-list' & name)
  (pure:m |)
::
++  do-delete-list
  |=  [root=@ud name=@t]
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
  |=  [root=@ud t=thread-id:uc c=chain:uc wrote=?]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  rs=(list rule:uc)  bind:m  (read-rules root)
  =/  got  (apply-rules:uc rs c)
  ;<  mt=meta:uc  bind:m  (read-meta root t)
  ::  the label bound refuses the ADDITION, never the delivery: a rule
  ::  that would push a thread past the cap simply does not add. Nacking
  ::  the chain instead would turn a rule the user wrote into a way for
  ::  a sender to get their own mail rejected. (+filing)
  =/  [arch=? ls=(set @tas)]  (filing:uc mt got wrote)
  ?:  &(=(arch archived.mt) =(ls labels.mt))  (pure:m ~)
  ;<  ~  bind:m
    (put-file (meta-rail root t) [/auspex %meta] mt(archived arch, labels ls))
  (note root 'file-arrival' & (scot %uv t))
::
::  +do-delete: the escape hatch. Every capacity limit here is otherwise
::  permanent: a thread pinned at the distinct-id cap has no other remedy.
::  Culling the thread dir takes its messages, its verdicts and its read
::  marks with it, so deleting actually reclaims capacity.
::
++  do-delete
  |=  [root=@ud t=thread-id:uc]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  road=road:tarball  (rv root (tdir t))
  ;<  ~  bind:m  (cull-if-there road)
  ;<  ix=mail-idx:uc  bind:m  (read-idx root)
  ;<  ~  bind:m
    %^  put-file  (rf root mail-dir %idx)  [/auspex %idx]
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
::    Order is load-bearing: cap, then resolve identity, then VERIFY, then
::    merge, then store. Nothing is written before every signature in the
::    incoming chain has a verdict. Identity comes first so the verify can
::    skip what is already settled: a copy this thread holds %verified or
::    %forged keeps that verdict whatever a re-check says (+freeze), so
::    only new and %unverified copies are checked (+unsettled).
::
++  deliver
  |=  [root=@ud c=chain:uc]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ?:  =(~ c)  (pure:m |)
  ::  reject rather than truncate. A chain that violates a limit is not
  ::  partially trustworthy. This governs the INCOMING poke only; once
  ::  merged, excess capacity is a different question with a different
  ::  answer, and +prune sheds there rather than rejecting.
  ::  every cap below is +incoming-refusal's, in this order:
  ::  length, bodies, subjects, recipients, then these.
  ::  every signed atom within its type's width, since a mold clams an
  ::  atom of any size and the copy is stored whole. See +fits-fields.
  ::  a delivered chain carries attachment METADATA and never bytes, so
  ::  this bounds what a hostile peer can make us store per message and
  ::  what it can later make us try to fetch. Rejected, not truncated:
  ::  the metadata is inside the signature, so trimming it would forge.
  ::  body-mime is a signed field a recipient cannot repair, so it is
  ::  bounded here where the chain is still refusable whole.
  ::  DEPTH, refused before verification because it is the cheapest
  ::  refusal and the walk is bounded. A message is stored under its
  ::  ancestry and every peek of the mail tree rebuilds those keys, so
  ::  depth is quadratic and is NOT off the read path - see +max-depth.
  ::  This one bounds a single poke; the merged check below is what
  ::  actually bounds what ends up on disk.
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
  =/  bad=(unit @t)  (incoming-refusal:uc c)
  ?^  bad  (reject root u.bad)
  ;<  loaded=(map thread-id:uc (map path stored-msg:uc))  bind:m  (read-threads root)
  ::  thread identity is never (root:uc c). `c` is attacker-controlled and
  ::  unsorted, so the head-as-supplied is not a stable identity.
  ::  +thread-key crashes on a first-contact chain with no unique prev=~
  ::  root, which is hostile input reaching the writer, so: mule.
  =/  rk  (mule |.((thread-key:uc (key-threads loaded) c)))
  ?:  ?=(%| -.rk)  (reject root 'no unique root')
  =/  rid=thread-id:uc  p.rk
  =/  ss=(map path stored-msg:uc)  (~(gut by loaded) rid ~)
  =/  held=(map [msg-id:uc @ux] verdict:uc)  (verdicts-of ss)
  =/  todo=chain:uc  (unsettled:uc held c)
  ;<  keys=(map [ship @ud] (unit pass))  bind:m  (delivery-keys root todo)
  =/  vs=(list [[msg-id:uc @ux] verdict:uc])  (verify-chain:uc keys todo)
  =/  new=chain:uc  (merge:uc (chain-of ss) c)
  ::  a genuine state-capacity limit, and it stays a reject: shedding a
  ::  distinct non-root id would orphan the prev pointers of later
  ::  messages. The cost is recorded in the spec and not hidden.
  ::  and the merged depth, since two chains each inside the cap can
  ::  compose past it. Same reasoning as the distinct-id cap directly
  ::  above, including the cost: a thread genuinely deeper than
  ::  max-depth accepts nothing further.
  ::  an EXISTING thread always accepts - a reply must never be refused
  ::  because some unrelated thread filled the cap. Only a brand-new
  ::  thread id is capped.
  ::  all three are +admit-refusal's, in this order
  =/  over=(unit @t)  (admit-refusal:uc new (~(has by loaded) rid) ~(wyt by loaded))
  ?^  over  (reject root u.over)
  ::  fold this poke's verdicts into the stored ones BEFORE pruning:
  ::  +prune needs a verdict for every message in `new`, including ones
  ::  stored by an earlier poke that this one did not carry.
  =/  vs2  (freeze:uc held vs)
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
  ::  THE OWNER'S DOWNLOAD RULES, over the copies this delivery checked
  ::  (`todo`): a copy settled earlier was offered its downloads when it
  ::  arrived. Queued like a manual fetch, so no peer is waited on here,
  ::  and skipped outright for mail with no attachments - most of it.
  ?:  (levy todo |=(x=msg:uc =(~ attachments.unsigned.x)))  (pure:m &)
  ;<  s=settings:uc  bind:m  (read-settings root)
  ;<  held=(list blob-row:uc)  bind:m  (list-blobs root)
  ;<  ~  bind:m
    (queue-fetches root (auto-picks:uc s todo vs2 (held-bytes:uc held)))
  (pure:m &)
::
::  ── blobs ───────────────────────────────────────────────────────────
::
::  +publish-blob: bind the bytes in gall's remote-scry farm.
::
::    This is the whole permission story for a public blob. A %keen is
::    the kernel scry farm and the only permissionless channel on this
::    platform: peeks and keeps are weir-gated, and a cross-ship peek
::    between un-granted peers HANGS rather than failing, while a keen at
::    a bound spur is answered by the publisher's kernel without waking
::    %grubbery at all. So "the hash is the authority, the courier is
::    irrelevant" is not a policy auspex enforces - it is what the
::    transport already is.
::
::    gall's farm is a FLAT namespace shared by every nexus in this yoke
::    (lattice grows at /pub/page/...), hence the /auspex prefix.
::
::    GROWN ONLY WHEN UNBOUND, and that is what keeps the fetch path
::    simple. gall assigns a spur's case itself (+grow:of-farm in
::    sys/lull): an unbound, never-culled spur takes case 1, and every
::    later %grow at the same spur takes the next key up. A remote
::    fetcher cannot discover a case - gall's %w care, the only read that
::    answers one, is gated on `=(our ship)` - so it builds the path from
::    the hash alone at case 1, and nothing here ever culls a blob spur.
::
++  publish-blob
  |=  [root=@ud h=@uv =octs]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ::  THE FARM IS DOWN /sys/scry, so this whole arm is behind the key
  ::  road. Denied, we keep the bytes and publish nothing: peers cannot
  ::  fetch our attachments, which is honest degradation - a fetcher
  ::  reports a miss and the message is still stored, threaded and
  ::  readable. A grow here would be a veto, and a veto on the writer
  ::  is the application.
  ;<  may=?  bind:m  (may-scry root)
  ?.  may
    (say "auspex: no key road; blob {<h>} stays unpublished")
  ::  NOTHING MAY GROW A SPUR IT HAS NOT ESTABLISHED IS UNBOUND. gall
  ::  assigns las+1 on a non-empty fan, so a second %grow at a bound
  ::  spur would move the blob off the case 1 every fetcher asks for.
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
::    The listing prefix is /auspex and not /auspex/blob: this nexus
::    binds two kinds of thing in the farm now - every blob, and the one
::    /proto - and one %gt under the prefix they share answers for both.
::    %gt lists FULL spurs, so the membership test below is unchanged.
++  farm-has
  |=  spur=path
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  n=noun  bind:m
    (typed-scry:io noun %noun ~[%gt mesa-agent %$ %'1' %auspex])
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
::    and can never raise a case by running again.
::
++  republish-all
  |=  root=@ud
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ::  the farm listing and every regrow are /sys/scry. Denied, there is
  ::  nothing to re-bind and nothing lost by saying so quietly: the
  ::  bytes are in the tree either way. Re-run from +do-set-caps if the
  ::  road is ever granted.
  ;<  may=?  bind:m  (may-scry root)
  ?.  may
    (say "auspex: no key road; not republishing blobs")
  ::  no ?~ early-return on `held`: it would narrow the face to a lest,
  ::  and the ;< continuations below are gates whose bodies mull against
  ::  BOTH branches of that narrowing, so the null case then fails to
  ::  nest. The empty case costs one scry and is not worth the shape.
  ;<  held=(list blob-row:uc)  bind:m  (list-blobs root)
  ;<  n=noun  bind:m
    (typed-scry:io noun %noun ~[%gt mesa-agent %$ %'1' %auspex %blob])
  =/  res  (mule |.(;;((list path) n)))
  ?:  ?=(%| -.res)  (pure:m ~)
  =/  bound=(set path)  (~(gas in *(set path)) p.res)
  %+  republish-loop  root
  (skip held |=(r=blob-row:uc (~(has in bound) (blob-spur:uc h.r))))
::
++  republish-loop
  |=  [root=@ud rs=(list blob-row:uc)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  rs  (pure:m ~)
  ;<  o=(unit octs)  bind:m  (read-blob root h.i.rs)
  ;<  ~  bind:m
    ?~  o  (pure:m ~)
    ;<  ~  bind:m  (grow:io (blob-spur:uc h.i.rs) [blob-page-mark:uc u.o])
    (say "auspex: republished blob {<h.i.rs>}")
  (republish-loop root t.rs)
::
::  +publish-proto: bind what this nexus speaks where any ship can read it.
::
::    The tree's /proto grub is laid by an %over row; this is the copy a
::    PEER reads, and it is a farm binding exactly like a blob's.
::
::    GROWN ONLY WHEN THE SPUR IS UNBOUND, which is +publish-blob's rule
::    and it is here for the same structural reason: gall assigns las+1
::    on a non-empty fan, so a second %grow raises the case a peer has to
::    probe for and cases only ever go up. Three redeploys of an
::    unconditional grow would push /proto past +proto-probe-cases and make
::    it unreadable by every peer, forever, with no error - the fetcher
::    would simply report a miss, which is the answer that means
::    "version 1" and would then be wrong.
::
::    THE COST, SAID PLAINLY: a change to `versions`, `marks` or the caps
::    does NOT reach the farm on a redeploy. The spur has to be culled
::    first, after which it rebinds at case 2 and the probe ladder finds
::    it. That is a deliberate trade of automatic propagation for an
::    address that cannot be bricked, and it is affordable because the
::    thing being published changes on the timescale of a protocol
::    version. A peer holding the old answer is not misled about
::    VERSIONS - version 1 is what silence means anyway - only about
::    caps, and the receiver enforces those regardless.
::
::    ROOT IS PASSED IN, and it has to be. This arm used to derive it
::    with (snip path.here) from +get-here-abs, which is right for the
::    ephemeral fibers under /probe and /fetch and WRONG here: this runs
::    on the writer, whose own rail is [<nexus root> %'main.sig'], so
::    path.here IS the nexus root and snipping it climbed one directory
::    ABOVE the nexus - /apps. Every read and write of /proto-pub below
::    went there, so the "did it change" record was never found and
::    every rise republished. Both callers hold the real root; they pass
::    it.
::
++  publish-proto
  |=  root=@ud
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ::  the farm is /sys/scry, so discovery is behind the key road too.
  ::  Denied, we publish nothing and a peer's probe finds nothing -
  ::  which already means "treated as version 1", the answer every
  ::  Auspex before discovery gave. Honest degradation, and it costs
  ::  the peer one probe.
  ;<  may=?  bind:m  (may-scry root)
  ?.  may
    (say "auspex: no key road; /proto not published")
  ;<  bound=?  bind:m  (farm-has proto-spur:uc)
  ;<  last=proto:uc  bind:m  (read-proto-pub root)
  ?.  (proto-stale:uc bound last)
    (say "auspex: /proto unchanged; not republishing")
  ::  IT CHANGED, or the binding is gone. GROW, NEVER CULL: the grow
  ::  lands one case above every earlier one, and +keen-proto takes the
  ::  HIGHEST case that answers and stops at the first that does not. A
  ::  cull cannot retire an old answer anyway - vere serves a namespace
  ::  read from its own jumbo cache without asking arvo (io/mesa.c) and
  ::  never evicts one entry - and once the cache does drop a culled
  ::  case, that case goes silent, which the walk would read as the top.
  ::
  ::  ONE GROW PER PROTOCOL CHANGE, never per deploy - which is what
  ::  keeps this inside +proto-probe-cases. /proto-pub is the record that
  ::  makes a redeploy of unchanged content free, and it is a LOCAL
  ::  record rather than a read of the farm because the farm cannot be
  ::  read from here: a keen addressed to our own ship does not answer,
  ::  and treating that silence as "unbound" would grow on every bounce
  ::  and reach the ceiling in three.
  ::
  ::  +farm-has is still consulted, so a binding lost to a nuked agent
  ::  or a rebuilt yoke is re-grown even when our record says we already
  ::  published it - the same insurance +republish-all is for blobs.
  ;<  ~  bind:m  (grow:io proto-spur:uc [proto-page-mark:uc our-proto:uc])
  ;<  ~  bind:m
    (put-file (rf root / %'proto-pub') [/auspex %proto] our-proto:uc)
  (say "auspex: /proto {?:(bound "changed" "published")}; grown into the farm")
::
::  +read-proto-pub: what we last grew. The bunt when the grub is absent
::  or unreadable, and the bunt is never a real $proto, so either way the
::  answer is "republish" - the safe direction, since a spurious
::  republish costs one case and a missed one costs every peer a stale
::  answer until the next protocol change.
::
++  read-proto-pub
  |=  root=@ud
  =/  m  (fiber:fiber:nexus ,proto:uc)
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io (rf root / %'proto-pub') ~)
  ?.  ?=([%file *] vw)  (pure:m *proto:uc)
  ?:  (is-boom:tarball sang.vw)  (pure:m *proto:uc)
  =/  res  (mule |.(;;(proto:uc (sang-noun:tarball sang.vw))))
  (pure:m ?:(?=(%| -.res) *proto:uc p.res))
::
::  ── the blob fetch ──────────────────────────────────────────────────
::
::  +mesa-agent: the gall agent whose scry farm holds the bindings.
::  auspex is a NEXUS inside %grubbery, so the spurs live under
::  %grubbery's yoke, not under an agent named %auspex. A fiber cannot
::  read its own `dap`, so this is a constant and it must track the
::  desk's agent name.
::
++  mesa-agent  ^-(@ta %grubbery)
++  blob-timeout  blob-timeout:uc
::
::  +proto-probe-cases / +proto-timeout: /proto's case ladder.
::
::    A blob is content-addressed and immutable and is only ever grown at
::    case 1. /proto is MUTABLE: it moves one case every time a ship
::    changes its version ladder or its caps, which is a normal thing for
::    a deployed protocol to do, and every release that changes a cap
::    spends one. The walk ends at the first case that times out (see
::    +keen-proto) and a culled case answers at once, so a probe costs
::    one RTT per case plus ONE deadline, and those seconds hold QUEUED
::    MAIL on first contact. The ceiling only bounds a peer that answers
::    at every case it is asked. The deadline is 10s, not less, because
::    the walk reads a timeout as the top: an uncached first answer from
::    a busy publisher took more than 4s on ~feb, and stopping there read
::    the case below it.
::
++  proto-probe-cases  proto-probe-cases:uc
++  proto-timeout  proto-timeout:uc
::
::  +keen-page: one %keen. ~ when OUR DEADLINE fired - nothing answered,
::  which for a case ladder means nothing is bound there yet; [~ ~] when
::  the peer answered with nothing we can use - an empty or culled case,
::  or a page under a mark we did not ask for. On the deadline, %yawn
::  the request: ames otherwise holds an unanswerable keen forever, one
::  parked request per miss. The caller clams the noun.
::
++  keen-page
  |=  [who=ship pax=path to=@dr mark=@tas]
  =/  m  (fiber:fiber:nexus ,(unit (unit *)))
  ^-  form:m
  ;<  res=(unit (unit page))  bind:m
    ((deadline ,(unit page)) to (keen:io who pax))
  ?~  res
    ;<  ~  bind:m  (yawn:io who pax)
    (pure:m ~)
  ?~  u.res  (pure:m [~ ~])
  ?.  =(mark p.u.u.res)  (pure:m [~ ~])
  (pure:m ``q.u.u.res)
::
::  +fetch-keen / +probe-keen: the two keens, BEHIND THE KEY ROAD.
::
::    A %keen is a poke at /sys/scry like every other farm operation, so
::    both are vetoed on an instance that was refused it. These two
::    fibers are ephemeral, so a veto would not touch the writer - but
::    it would spend a fiber and a restart to learn what /caps already
::    says, and leave a request grub for the next reload to respawn.
::
::    ~ IS ALREADY BOTH CALLERS' ANSWER for "did not come back": a blob
::    fetch reports a miss and the writer culls the request; a peer that
::    answers no /proto is treated as version 1, which is what every
::    Auspex before discovery speaks. Nothing new has to be handled.
::
++  fetch-keen
  |=  [root=@ud who=ship h=@uv]
  =/  m  (fiber:fiber:nexus ,(unit octs))
  ^-  form:m
  ;<  may=?  bind:m  (may-scry root)
  ?.  may  (pure:m ~)
  ;<  n=(unit (unit *))  bind:m
    (keen-page who (blob-keen-path:uc mesa-agent h 1) blob-timeout blob-page-mark:uc)
  (pure:m (biff (biff n same) |=(x=* (mole |.(;;(octs x))))))
::
++  probe-keen
  |=  [root=@ud who=ship]
  =/  m  (fiber:fiber:nexus ,(unit proto:uc))
  ^-  form:m
  ;<  may=?  bind:m  (may-scry root)
  ?.  may  (pure:m ~)
  (keen-proto who 1 ~)
::
::  +keen-proto: up /proto's ladder, and the HIGHEST case that answers
::  wins. Not the first: a republish culls the old case and grows the
::  new one above it, but vere keeps answering the culled case from its
::  cache (see +publish-proto), so the first hit can be a stale one.
::  The walk ends at our deadline, which is the first case nothing is
::  bound at yet - so every probe pays one +proto-timeout, once a day
::  per peer (+proto-ttl). A noun that is not a $proto, or a $proto
::  saying what one cannot truthfully say - lists that disagree in
::  length, or a ship claiming to speak nothing - is a miss, and a peer
::  with no hit at all is treated as silent: silence means version 1,
::  and version 1 is what we would have poked anyway.
::
++  keen-proto
  |=  [who=ship case=@ud best=(unit proto:uc)]
  =/  m  (fiber:fiber:nexus ,(unit proto:uc))
  ^-  form:m
  ?.  (more-cases:uc case)  (pure:m best)
  ;<  n=(unit (unit *))  bind:m
    (keen-page who (proto-keen-path:uc mesa-agent case) proto-timeout proto-page-mark:uc)
  ?~  n  (pure:m best)
  =/  got=(unit proto:uc)
    (biff u.n |=(x=* (mole |.(;;(proto:uc x)))))
  =.  best  (better-proto:uc best got)
  (keen-proto who +(case) best)
::
::  +enqueue-chain: hand this send to the peer's probe fiber.
::
::    EVERY SEND GOES THIS WAY, known peer or not. The writer used to poke
::    a peer it had a fresh answer for itself, and a poke carries
::    +send-timeout because grubbery never returns a remote ack: each
::    known recipient held the writer twenty seconds, and every
::    read-mark, delivery and autosave queued behind it. The fiber reads
::    the cache first and keens only when nothing fresh is there.
::
::    AND NOTHING GOES OUT AS VERSION 1 ON A GUESS. Poking v1 while a
::    probe was still in flight meant the "no common protocol version"
::    refusal could never fire on FIRST CONTACT - the one send most
::    likely to reach a ship running something else.
::
::    Writing the grub is the whole spawn: grubbery runs +on-file for
::    the rail. An UPDATE does not spawn a second fiber (see
::    +do-fetch-blob on the same property), so appending to a live
::    probe's queue is safe and is what makes two quick sends to one
::    unknown ship both arrive.
::
++  enqueue-chain
  |=  [root=@ud c=chain:uc who=ship now=@da]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  ~  bind:m  (ensure-dir root probe-dir)
  ;<  rq=(unit probe-req:uc)  bind:m  (read-probe root who)
  =/  nex=probe-req:uc
    ?~  rq  [%0 who now ~[c] ~ 0]
    u.rq(pending (queue-chain:uc pending.u.rq c))
  ;<  ~  bind:m  (put-file (probe-rail root who) [/auspex %probereq] nex)
  (say "auspex: handing a send to {<who>} to its fiber")
::
::  +deliver-chain: THE DECISION, made on the probe fiber and nowhere
::  else.
::
::      answer, common version   poke the mark for the HIGHEST common one
::      answer, none in common   REFUSE. Never poke: a mark the peer does
::                               not carry PARKS, and a park is what all
::                               of this exists to stop looking like a
::                               timeout.
::      answer, over their caps  REFUSE, naming THEIR number.
::      no answer at all         one version-1 attempt, because silence
::                               is version 1 - and only the PROBE's own
::                               empty result reaches here, never a cache
::                               that merely had no entry.
::
::    The outcome goes to the console. Only the writer mutates the tree,
::    and it records what discovery learned when the fiber reports back.
::
++  deliver-chain
  |=  [root=@ud c=chain:uc who=ship known=(unit proto:uc)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  mk=(unit @tas)  (peer-mark:uc known)
  ?~  mk
    ::  unreachable with known=~: silence is version 1, so +peer-mark
    ::  answers ~ only for a peer that ANSWERED and shares nothing with
    ::  us. Written rather than needed, because +need here would be a
    ::  crash on whichever fiber got here.
    ?~  known  (pure:m ~)
    (say-send (no-version-error:uc who u.known))
  =/  cerr=(unit @t)  (peer-cap-error:uc who c known)
  ?^  cerr  (say-send u.cerr)
  ::  no answer: the compatibility rule, said out loud before the poke
  ::  rather than after it fails.
  ;<  ~  bind:m
    ?^  known  (pure:m ~)
    (say-send (unanswered-note:uc who))
  =/  rd=road:tarball  (remote-road [%& %& remote-install %'main.sig'] who)
  ;<  res=(unit (unit tang))  bind:m
    ((deadline ,(unit tang)) send-timeout (poke-soft:io rd [[/ u.mk] c]))
  ?~  res
    ::  THE ACK IS NOT OBSERVABLE FROM HERE, so its absence is not
    ::  evidence of anything.
    ::
    ::    Grubbery does not return a poke-ack to a nexus fiber. Every
    ::    cross-ship send this project has made both timed out here and
    ::    arrived, verified and stored, at the far end - measured
    ::    repeatedly between ~feb and ~wex. So this deadline fires on
    ::    every successful send, and treating it as a failure cost two
    ::    things: a line of alarm to the user on every message, and the
    ::    peer record, culled - which meant a fresh probe before every
    ::    single send and a day-long TTL that was never once in force.
    ::
    ::    DISCOVERY IS THE LIVENESS SIGNAL, not the ack. A peer that
    ::    answered /proto answered over a channel that does return
    ::    something, and it answered recently; a peer that did not is
    ::    already told about, before the poke, by +unanswered-note.
    ::    There is nothing this branch can add to either.
    ::
    ::    So: the record STAYS, the user is told nothing, and the fact
    ::    is traced only under +dbg: it fires on every successful send,
    ::    so on the console it would be a line per message that means
    ::    nothing.
    ::
    ::    An explicit NACK is different in kind and is handled below: it
    ::    is the far end SAYING no, which is a fact, and it does drop
    ::    the record.
    (say "auspex: {(trip (late-ack-note:uc who (div send-timeout ~s1)))}; grubbery returns no poke-ack to a nexus fiber, so this is not a failure")
  ?~  u.res  (pure:m ~)
  ;<  ~  bind:m  (cull-if-there (peer-rail root who))
  (say-send (nacked-note:uc who))
::
::  +say-send: one sentence, to the console, at >>: a send the far end
::  refused or that could not be made. The fiber that says it does not
::  write the tree; the writer records what discovery learned.
::
++  say-send
  |=  why=@t
  (warn "auspex: {(trip why)}")
::
::  +run-probe: the ephemeral discovery fiber. Runs OFF the writer, and
::  it is the fiber that SENDS the mail it was holding.
::
::    Order, and every step of it is load-bearing:
::
::      1  `who` off the RAIL NAME, not the grub. A grub that does not
::         clam - an old shape left by a previous build - would
::         otherwise crash this fiber, and a crashed fiber respawns,
::         which is an infinite crash loop at 100% CPU. Reading the name
::         means the recovery poke below can always be sent.
::      2  the cached answer if it is fresh; otherwise keen /proto's
::         ladder, bounded and yawned.
::      3  RE-READ the state. Anything the writer appended while the
::         keen was in flight is picked up here, which is what makes two
::         quick sends to one unknown ship both arrive.
::      4  drain, in order, through the same +deliver-chain the writer
::         uses.
::      5  report [answer drained] to the writer, which stores the
::         record, culls exactly what was sent, and re-sends anything
::         that arrived behind the count.
::
::    Its road to the writer is ABSOLUTE, derived from +get-here-abs,
::    for the reason +run-fetch's is.
::
++  run-probe
  |=  [root=@ud id=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  wu=(unit @p)  (slaw %p id)
  ?~  wu
    (say "auspex: probe at {<id>} is not a ship name")
  =/  who=ship  u.wu
  ;<  now=@da  bind:m  get-time:io
  ::  A FRESH RECORD IS THE ANSWER, and it keeps the time it was asked:
  ::  a peer written to every hour must still expire on +proto-ttl.
  ;<  rec=(unit peer-rec:uc)  bind:m  (read-peer root who)
  =/  n  (fiber:fiber:nexus ,[(unit proto:uc) @da])
  ;<  [got=(unit proto:uc) asked=@da]  bind:m
    =/  hit  (cached-probe:uc rec now)
    ?^  hit  (pure:n [p.u.hit asked.u.hit])
    ;<  p=(unit proto:uc)  bind:n  (probe-keen root who)
    (pure:n [p now])
  ;<  rq=(unit probe-req:uc)  bind:m  (read-probe root who)
  =/  q=(list chain:uc)  ?~(rq ~ pending.u.rq)
  ;<  ~  bind:m  (drain-probe root who got q)
  %+  poke:io  (rf root / %'main.sig')
  [[/auspex %probereq] `probe-req:uc`[%0 who asked ~ got (lent q)]]
::
::  +drain-probe: send the held chains, oldest first.
::
::    Recursion by ARM NAME: a $ with arguments inside a ;< continuation
::    cannot find the trap.
::
++  drain-probe
  |=  [root=@ud who=ship known=(unit proto:uc) q=(list chain:uc)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  q  (pure:m ~)
  ;<  ~  bind:m  (deliver-chain root i.q who known)
  (drain-probe root who known t.q)
::
::  +take-probe-done: the writer's half of a probe. Local only.
::
::    A MISS IS RECORDED, not discarded: `proto=~` in the stored record
::    is a REMEMBERED SILENCE, so a ship running a build without
::    discovery costs one probe rather than one per send.
::
::    Then the hand-off. The fiber says how many of the queue it sent;
::    everything past that count arrived while it was draining and has
::    never been near a wire, so it goes back to A FRESH FIBER - never
::    out from here, because every delivery waits out +send-timeout for
::    an ack grubbery does not return, and the writer is the ship's
::    single serialisation point for mail. The fresh fiber finds the
::    record just written and sends without asking again. Culling the
::    whole queue instead would have destroyed exactly those messages.
::
::    ANSWERS %.n, AND THE BEACON IS THE REASON. A peer record is local
::    state no reader renders, and the ANSWER COMES FROM A PEER - a bump
::    here would let whoever publishes a /proto decide when this ship
::    refetches its whole mailbox. Same argument as +take-blob's.
::
++  take-probe-done
  |=  [root=@ud r=probe-req:uc]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  ~  bind:m  (record-peer root [%0 who.r answer.r asked.r])
  ;<  held=(unit probe-req:uc)  bind:m  (read-probe root who.r)
  =/  rest=(list chain:uc)
    ?~  held  ~
    rest:(drain-queue:uc pending.u.held drained.r)
  ;<  ~  bind:m  (cull-if-there (probe-rail root who.r))
  ;<  ~  bind:m  (requeue root who.r rest)
  (pure:m |)
::
::  +record-peer: store what a probe learned. A CACHED ANSWER COMES
::  BACK UNCHANGED from the fiber that used it, and writes nothing.
::
++  record-peer
  |=  [root=@ud rec=peer-rec:uc]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  was=(unit peer-rec:uc)  bind:m  (read-peer root who.rec)
  ?:  =(`rec was)  (pure:m ~)
  ;<  ~  bind:m  (ensure-dir root peer-dir)
  ;<  ~  bind:m  (put-file (peer-rail root who.rec) [/auspex %peer] rec)
  =/  spoke=@t
    ?~  proto.rec
      (rap 3 ~[(scot %p who.rec) ' published no /proto'])
    (rap 3 ~[(scot %p who.rec) ' speaks ' (num-list:uc versions.u.proto.rec)])
  ;<  ~  bind:m  (say "auspex: discovery: {(trip spoke)}")
  (note-at root %discovery 'discovery' & spoke)
::
::  +requeue: hand held chains to a fresh probe fiber. Writing the grub
::  is the whole spawn.
::
++  requeue
  |=  [root=@ud who=ship q=(list chain:uc)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  q  (pure:m ~)
  ;<  now=@da  bind:m  bowl-now
  %^  put-file  (probe-rail root who)  [/auspex %probereq]
  `probe-req:uc`[%0 who now q ~ 0]
::
::  +do-forget-peer: drop one discovery record.
::
::    THE ESCAPE HATCH FOR A SELF-SEALING REFUSAL. A record that lets
::    mail through is checked by the send itself - a nack or a timeout
::    drops it - but a record that REFUSES is never checked by anything,
::    because the poke is never sent. +proto-refusal-ttl shortens that to
::    an hour for the case derivable from the record alone; a CAP refusal
::    depends on the message and is not derivable, so this is its remedy
::    and the only one.
::
::    THE PROBE GRUB IS NOT CULLED. Mail waits in it. Forgetting what a
::    peer said must not throw away what a person wrote.
::
++  do-forget-peer
  |=  [root=@ud who=ship]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  ~  bind:m  (cull-if-there (peer-rail root who))
  ;<  ~  bind:m  (say "auspex: forgot what {<who>} speaks")
  ;<  ~  bind:m  (note-at root %discovery 'forget-peer' & (scot %p who))
  (pure:m |)
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
  |=  [root=@ud h=@uv who=ship]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  have=(unit octs)  bind:m  (read-blob root h)
  ?^  have
    ;<  ~  bind:m  (note root 'fetch-blob' & 'already held')
    (pure:m |)
  ;<  ~  bind:m  (ensure-dir root /fetch)
  ::  the id is derived from [hash ship], so asking twice for the same
  ::  blob from the same peer overwrites one request rather than
  ::  spawning a second fiber to race the first.
  =/  id=@ta  (scot %uv (sham [h who]))
  ;<  ~  bind:m
    (put-file (rf root /fetch id) [/auspex %fetchreq] [%0 h who])
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
::  recursion by arm name, for the ;< reason stated at +mark-read-loop.
::
++  queue-fetches
  |=  [root=@ud xs=(list [h=@uv who=ship])]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  xs  (pure:m ~)
  ;<  *  bind:m  (do-fetch-blob root h.i.xs who.i.xs)
  (queue-fetches root t.xs)
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
  |=  [root=@ud id=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  rq=fetch-req:uc  bind:m  (get-state-as:io ,fetch-req:uc)
  ;<  got=(unit octs)  bind:m  (fetch-keen root from.rq hash.rq)
  %+  poke:io  (rf root / %'main.sig')
  [[/auspex %blob-in] [%0 id hash.rq got]]
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
  |=  [root=@ud b=blob-in:uc]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  ~  bind:m  (cull-if-there (rf root /fetch id.b))
  =/  bad=(unit @t)  (blob-refusal:uc res.b hash.b)
  ?^  bad  (reject root u.bad)
  ::  (the size bounds what a hostile publisher can hand back before it
  ::  is measured; see +blob-refusal)
  ?>  ?=(^ res.b)
  ;<  room=?  bind:m  (make-room root p.u.res.b)
  ?.  room
    (reject root 'blob store full')
  ;<  now=@da  bind:m  bowl-now
  ;<  ~  bind:m
    (put-file (blob-rail root hash.b) [/auspex %blob] [%1 u.res.b now])
  ::  we hold the bytes now, so we can serve them: a blob request is
  ::  answerable by ANYONE holding the bytes, not only the author,
  ::  exactly as a chain is forwardable by anyone.
  ;<  ~  bind:m  (publish-blob root hash.b u.res.b)
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
  |=  [root=@ud t=thread-id:uc place=(list msg-id:uc) mg=msg:uc v=verdict:uc]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  dir=path  (mdir t)
  =/  pax=path  (node-dir place)
  ;<  ~  bind:m  (ensure-nodes root dir (prefixes:uc pax))
  %^  put-file  (rf root (weld dir pax) (slot (id:uc unsigned.mg) sig.mg))
    [/auspex %msg]
  [%2 mg v]
++  want-slots  want-slots:uc
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
  |=  $:  root=@ud
          t=thread-id:uc
          have=(map path stored-msg:uc)
          want=(map path stored-msg:uc)
      ==
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  dir=path  (mdir t)
  =/  [puts=(list [pk=path st=stored-msg:uc]) dead=(list path) gone=(list path)]
    (slot-plan:uc have want)
  ;<  ~  bind:m  (ensure-nodes root dir (sorted-dirs (node-dirs:uc (turn puts |=([pk=path *] pk)))))
  ;<  ~  bind:m  (put-slots root dir puts)
  ;<  ~  bind:m  (cull-dirs root dir dead)
  ;<  ~  bind:m  (cull-slots root dir gone)
  ::  the answer +deliver needs: did this emit a single dart? A
  ::  redelivery of a chain we already hold emits none, and must not be
  ::  allowed to look like new mail.
  (pure:m (plan-writes:uc puts dead gone))
::
::  recursion by ARM NAME, not by $. A $ with arguments inside a ;<
::  continuation cannot find the trap (-find.$.+2).
::
++  cull-dirs
  |=  [up=@ud dir=path ps=(list path)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  ps  (pure:m ~)
  ;<  ~  bind:m  (cull-if-there (rv up (weld dir i.ps)))
  (cull-dirs up dir t.ps)
::
++  cull-slots
  |=  [up=@ud dir=path ps=(list path)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  ps  (pure:m ~)
  ;<  *  bind:m  (cull-soft:io (rf up (weld dir (snip i.ps)) (rear i.ps)))
  (cull-slots up dir t.ps)
::
++  put-slots
  |=  [up=@ud dir=path xs=(list [pk=path st=stored-msg:uc])]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  xs  (pure:m ~)
  ;<  ~  bind:m
    %^  put-file  (rf up (weld dir (snip pk.i.xs)) (rear pk.i.xs))
      [/auspex %msg]
    st.i.xs
  (put-slots up dir t.xs)
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
  |=  [root=@ud t=thread-id:uc]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  mt=meta:uc  bind:m  (read-meta root t)
  ?:  direct.mt  (pure:m |)
  ;<  ~  bind:m
    %^  put-file  (meta-rail root t)  [/auspex %meta]
    mt(direct &)
  (pure:m &)
::
::  recursion by ARM NAME: a $ with arguments inside a ;< continuation
::  cannot find the trap.
::
++  mark-read-loop
  |=  [root=@ud xs=(list [t=thread-id:uc is=(set msg-id:uc)]) k=?(%read %folded) rd=?]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  xs  (pure:m ~)
  ;<  ~  bind:m  (mark-read root t.i.xs is.i.xs k rd)
  (mark-read-loop root t.xs k rd)
::
::  +mark-read: fold a set of ids into one thread's read marks, in ONE
::  rewrite of its meta grub however many ids are named.
::
::    `rd` is the direction: & unions the ids in, | takes them out.
::    %read and %unread are the same walk and the same write, which is
::    what keeps them from disagreeing about what a set of ids names.
::
++  mark-read
  |=  [root=@ud t=thread-id:uc is=(set msg-id:uc) k=?(%read %folded) rd=?]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  mt=meta:uc  bind:m  (read-meta root t)
  =/  old=(set msg-id:uc)  ?-(k %read read.mt, %folded folded.mt)
  =/  nex=(set msg-id:uc)  (marks:uc old is rd)
  ::  a mark that changes nothing writes nothing: a thread opened twice,
  ::  or a relay echoing a mark back, is not a meta rewrite.
  ?:  =(nex old)  (pure:m ~)
  %^  put-file  (meta-rail root t)  [/auspex %meta]
  ?-(k %read mt(read nex), %folded mt(folded nex))
::
++  touch-idx
  |=  [root=@ud t=thread-id:uc]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  ix=mail-idx:uc  bind:m  (read-idx root)
  %^  put-file  (rf root mail-dir %idx)  [/auspex %idx]
  ix(inbox [t (skip inbox.ix |=(o=thread-id:uc =(o t)))])
::
::  ── delivery out ────────────────────────────────────────────────────
::
++  fan-out
  |=  [root=@ud c=chain:uc now=@da ws=(list ship)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  ws  (pure:m ~)
  ;<  ~  bind:m  (enqueue-chain root c i.ws now)
  (fan-out root c now t.ws)
::
::  +weir-json: every road auspex reaches outside its own tree, with the
::  reason a person would need to judge it.
::
::    The `why` strings are not documentation. They are the text the shell
::    shows when it asks, so each one says what the road buys the user,
::    not what the code does with it.
::
::    /sys/scry is the uncomfortable one and it is written honestly. It is
::    a single road that carries every vane answer: the sender's public
::    key, which every recipient needs merely to VERIFY a message, and
::    this ship's private key, which only sending needs. There is nothing
::    narrower to ask for - the scry service passes the vane path straight
::    through and no per-vane gating exists - so a user who only reads
::    mail must still grant what a sender needs. Saying so is the least we
::    can do about it; see docs/distribution-proposal.md.
::
++  weir-json
  ^-  json
  =/  line
    |=  [r=@t w=@t]
    `json`(pairs:enjs:format ~[['road' s+r] ['why' s+w]])
  %-  pairs:enjs:format
  :~  :-  'poke'
      :-  %a
      :~  %+  line  '/sys/bowl.sig'
          'read the clock and the name of this ship: every message is stamped with when it was sent, and signed as who sent it'
          %+  line  '/sys/behn/'
          'give up on a delivery or an attachment fetch that is not coming, instead of waiting for ever'
          %+  line  '/sys/eyre/'
          'serve the mail client at /apps/auspex'
          %+  line  '/sys/scry/'
          'verify a signature against the public key of the ship that sent it, sign the mail you send, fetch attachments from other ships, and follow the theme you set in talon (with your contacts profile colour). This one road also carries the private key of this ship: signing needs it, and nothing narrower can be asked for today'
        ::  The registry WRITE, and it belongs beside the usergroup read
        ::  below rather than with the four above: same feature, same
        ::  optionality. +grant-public registers this writer with the
        ::  usergroup machinery and then lays its grant through the %how
        ::  action, and both of those are pokes at /sys/ames/registry.
        ::
        ::  It was missing, and a sandboxed install showed exactly why
        ::  that costs more than the feature: the key probe proved the
        ::  scry road, poked %set-caps, and +do-set-caps wrote /caps and
        ::  THEN ran the rise work - which pokes the registry, drew a
        ::  veto, and rolled the whole event back including the /caps
        ::  write. So auspex reported 'has not been granted the key road'
        ::  on a ship where that road was granted, and no veto naming
        ::  auspex was ever logged, because the one that mattered was
        ::  about a road auspex never asked for.
          %+  line  '/sys/ames/registry'
          'publish this ship as somewhere mail can be delivered. Refuse this and you can still read and send; people just cannot reach you first'
        ::  the peer mirror: another ship's auspex is a writer under
        ::  /sys/ames/ships/<ship>/root, and delivering mail is a poke at
        ::  it. Without this road the poke is vetoed at home, before it
        ::  leaves the ship, and every send reports a failed delivery.
          %+  line  '/sys/ames/ships/'
          'deliver the mail you send: a message is a poke at the auspex on the recipient ship. Refuse this and you can still read what arrives; you cannot send'
      ==
    ::  the usergroup roads are READS, and they are OPTIONAL: refuse them
    ::  and auspex still runs, still reads mail, still signs and sends to
    ::  ships that can already reach it - it just cannot publish itself
    ::  for delivery, and says so. +exists-soft is what makes that true
    ::  rather than aspirational.
      :-  'peek'
      :-  %a
      :~  %+  line  '/sys/ames/usergroups/'
          'let other ships deliver mail to you. Without this you can still read and send; people cannot reach you first'
      ==
  ==
++  send-timeout  send-timeout:uc
::
::  +remote-road: rewrite an absolute road into its /sys/ames mirror on
::  `shp`, so a dart routes to that ship. The peer's auspex sits at the
::  same absolute path its own root nexus gave it.
::
::  +remote-install: WHERE AUSPEX LIVES ON SOMEBODY ELSE'S SHIP.
::
::    A stopgap, and the last absolute path in this file. Delivery pokes
::    the recipient's writer, which means naming a path in THEIR tree -
::    and this used to be our own absolute path, on the assumption that
::    two ships install auspex in the same place. The desk model retires
::    that assumption twice: a sandboxed app cannot read its own absolute
::    path, and the desk NAME is chosen by whoever installs it.
::
::    The real answer is the alias book. An app publishes link.json to
::    claim @auspex, the shell folds it into /sys/link, and a sender
::    resolves the recipient's @auspex against THEIR registry - the same
::    move wallet makes for @contacts, which the shell resolves into
::    grant.json's aliases map so that "we never hardcode where contacts
::    lives - it follows renames".
::
::    Until that lands, this constant is the conventional install path
::    and it is WRONG for any ship that named its desk something else or
::    still runs auspex in /apps. Delivery to such a ship fails; nothing
::    is mis-sent, because a bad road is refused rather than rerouted.
::
++  remote-install  ^-(path /apps/'shell.shell'/desks/'auspex.desk'/desk/data/'auspex.auspex_app')
++  remote-road
  |=  [=road:tarball shp=@p]
  ^-  road:tarball
  ?-  -.road
    ::  a RELATIVE road names a place in OUR tree, so mirroring it onto
    ::  another ship would poke ourselves and call it delivery. Refuse.
    %|  ~|(%auspex-remote-road-relative !!)
    %&
      =/  prefix=path  /sys/ames/ships/[(scot %p shp)]/root
      ?-  -.p.road
        %&  [%& %& (weld prefix path.p.p.road) name.p.p.road]
        %|  [%& %| (weld prefix p.p.road)]
      ==
  ==
::
::  ── the key road: what we may reach, and how we found out ───────────
::
::  +read-caps: /caps, or DENIED if it cannot be read.
::
::    Unreadable, absent, a shape this build does not understand: all
::    three answer denied, and that is the only safe direction. A
::    wrongly-denied ship refuses to sign and shows every message
::    unverified until the probe corrects it; a wrongly-granted one
::    reaches into a road it was not given and the reach is a VETO,
::    which kills the fiber that made it. On the writer that is the
::    whole application.
::
++  read-caps
  |=  root=@ud
  =/  m  (fiber:fiber:nexus ,caps:uc)
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io (caps-rail root) ~)
  ?.  ?=([%file *] vw)  (pure:m caps-denied:uc)
  ?:  (is-boom:tarball sang.vw)  (pure:m caps-denied:uc)
  =/  res  (mule |.(;;(caps:uc (sang-noun:tarball sang.vw))))
  (pure:m ?:(?=(%| -.res) caps-denied:uc p.res))
::
::  +may-scry: may this ship reach /sys/scry? One peek of a tiny grub.
::
::    EVERY REACH INTO THAT ROAD IS BEHIND THIS, and it is a read of
::    our own tree rather than a question asked of the shell, because
::    there is nothing to ask: no arm reports our weir, and the only
::    way to learn the answer is to reach and see whether we survive.
::    The probe did that once, off the writer, so nothing else has to.
::
++  may-scry
  |=  root=@ud
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  c=caps:uc  bind:m  (read-caps root)
  (pure:m keys.c)
::
::  +run-key-probe: the ephemeral fiber that asks the only question.
::
::    ONE SCRY, and the cheapest one auspex makes: %j /life/<our>, which
::    +our-life already does on every send. It is harmless - our own
::    life is not a secret and nothing is written from it here - and it
::    goes down the same /sys/scry road every other jael read does, so
::    surviving it is proof for all of them.
::
::    On success: poke the writer to raise /caps. On a veto: this fiber
::    FAILS, grubbery restarts it, +rise-wait parks the restart on a
::    poke that never comes, and /caps stays denied. The signal we
::    wanted arrives as an absence, which is the only shape a veto can
::    take.
::
::    Its road to the writer is ABSOLUTE, from +get-here-abs, for the
::    reason every long-lived road here is: a depth-relative road called
::    from the wrong depth climbs past the nexus root and crashes.
::
++  run-key-probe
  |=  root=@ud
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  our=@p  bind:m  bowl-our
  ::  the reach. If we were not granted the road, execution stops on
  ::  this line and the two below never run.
  ;<  *  bind:m  (our-life our)
  ;<  ~  bind:m  (say "auspex: key road reachable")
  %+  poke:io  (rf root / %'main.sig')
  [[/ %auspex-action] `action:uc`[%set-caps &]]
::
::  +do-set-caps: raise or lower /caps, on the writer.
::
::    Two callers: the key probe, which raises it by proof, and a dojo
::    poke, which is the TEST SEAM - auspex lives in /apps, the trusted
::    tier, which has no weir, so no veto can be made to happen on a
::    development ship and forcing the flag is the only way to walk the
::    degraded paths. See %set-caps in $action:uc.
::
::    A RAISE RUNS THE RISE WORK THE DENIED WRITER SKIPPED. +on-load
::    lays /caps denied on every load, so the writer's own rise finds
::    it denied and skips +republish-all and +publish-proto - and on a
::    granted ship the probe's answer lands a moment later. Without
::    this the two would never run again on any ship: discovery would
::    answer with whatever was published before this existed, and a
::    blob binding lost to a nuked agent would stay lost. Both are
::    gated on the farm listing and are no-ops in the ordinary case.
::
::    %.n: the beacon does not move for this. Nothing a reader renders
::    changed, the flag is fetched once at startup with /api/whoami,
::    and the probe pokes on EVERY load - so a bump here would cost
::    every open tab a full inbox listing on every deploy, for a change
::    it would not observe.
::
++  do-set-caps
  |=  [root=@ud keys=?]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  was=caps:uc  bind:m  (read-caps root)
  ?:  =(keys keys.was)  (pure:m |)
  ;<  ~  bind:m  (put-file (caps-rail root) [/auspex %caps] `caps:uc`[%0 keys])
  ;<  ~  bind:m  (note root 'set-caps' & ?:(keys 'key road granted' 'key road denied'))
  ?.  keys  (pure:m |)
  ;<  ~  bind:m  (republish-all root)
  ;<  ~  bind:m  (publish-proto root)
  (pure:m |)
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
::  +delivery-keys: the keys to verify an inbound chain against, or NONE.
::
::    Denied the key road, this answers the EMPTY MAP and reaches for
::    nothing - not the per-signer %puby scries, and not the %j /fake
::    read that decides how to answer them, which is a jael scry too.
::
::    An empty key map is not a degraded verdict, it is the correct
::    one. +verify-chain answers %unverified for a signer it has no key
::    for and %forged for none, because A MISSING KEY IS NEVER A
::    FORGERY - the same rule that makes every moon and comet message
::    %unverified today. So mail still arrives, is still verified before
::    storage, is still threaded and readable, and every message says
::    plainly that its signature was not checked. Three verdicts, and
::    no fourth for this.
::
++  delivery-keys
  |=  [root=@ud c=chain:uc]
  =/  m  (fiber:fiber:nexus ,(map [ship @ud] (unit pass)))
  ^-  form:m
  ::  a redelivery with nothing left to check asks jael nothing
  ?:  =(~ c)  (pure:m ~)
  ;<  may=?  bind:m  (may-scry root)
  ?.  may  (pure:m ~)
  ;<  fake=?  bind:m  fake-ship
  (key-map fake ~(tap in (signers:uc c)) ~)
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
::  ── coming back from a crash ────────────────────────────────────────
::
::  +rise-later: a long-lived fiber that crashed comes back by itself,
::  after a wait. Taken from calendar (its +rise-later, commit da42ed6)
::  after its versions 18 and 19 locked ships; the rules it keeps are in
::  the hoon-test-kit's PLAYBOOK, "Never ship a crash loop".
::
::    +rise-wait:io was not enough here, twice over. The writer takes
::    peers' deliveries and the routes' actions, and rise-wait takes the
::    first poke after a crash as its restart signal and DROPS it, acked:
::    a delivery or an action lost without a word. And /ui/main, which
::    serves the whole HTTP API, is poked by nobody, so under rise-wait
::    a crash left the API dead until a reload.
::
::    So: a crash waits 1, 2, 4 and up to 60 minutes (the count starts
::    over after two quiet hours), prints its whole trace only the first
::    two times, and then goes on by itself on a timer. A poke that comes
::    while it waits is REFUSED (a nack its sender sees), never held and
::    never swallowed. It never fails itself: grubbery restarts a failed
::    fiber at once, in the same event, so a failure in here would spin.
::    Its clock and timer are soft, on fixed wires (a nonce is itself a
::    bowl.sig poke); with either refused it parks until a poke instead.
::    The count lives in `rise.json` beside the fiber, one per directory:
::    each of the two directories holds one long-lived fiber.
::
++  rise-later
  |=  [=prod:fiber:nexus msg=tape]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ::  TAKE THE START KICK FIRST. After a reload or restart grubbery queues
  ::  the kick BEHIND any input already waiting (a timer wake, news, a
  ::  late answer), and a step that only sends a dart asserts it was
  ::  kicked, so a real input arriving first crashed it: every reload
  ::  counted as a crash. Found in calendar (its 9733316, rule 9 of the
  ::  crash-loop rules); +take-kick holds whatever came ahead of the kick.
  ;<  ~  bind:m  take-kick
  ::  a clean start takes down any wait an earlier run left set: its wake
  ::  would come to a fiber no longer waiting for it
  ?~  prod
    ;<  *  bind:m  (soft-behn /rise/rest [[/ %timer-rest] `wire`/rise])
    (pure:m ~)
  ::  what a refused poke fails with; the restart that follows is not a crash
  =/  note=tang  ~[leaf+"{msg}: waiting after a crash; the poke was refused"]
  ::  A poke whose mark the kernel could not validate is not a crash
  ::  either. Grubbery fails the fiber in +hydrate, before any code here
  ::  runs, and has already nacked and dropped that poke by the time it
  ::  restarts us, so nothing is replayed. /main.sig takes pokes from any
  ::  ship, and counting these would let a stranger hold the writer in
  ::  its 60-minute wait for one malformed noun an hour. Should the
  ::  kernel rename the tank, this falls back to the backoff.
  =/  dropped=?  =(~[leaf+"hydrate failed"] (scag 1 u.prod))
  =/  crash=?  &(!dropped !=(note u.prod))
  %-  ?.(dropped same (slog leaf+"{msg}: a poke failed its mark and was dropped" ~))
  ;<  clock=(unit @da)  bind:m  soft-now
  ?~  clock
    %-  ?.(crash same (slog [leaf+"{msg}: no clock (weir?); waiting for a poke" u.prod]))
    (rise-park note)
  =/  now=@da  u.clock
  ;<  row=[n=@ud last=@da until=@da]  bind:m  read-rise
  =/  n=@ud
    ?.  crash  n.row
    ?:((gth now (add last.row ~h2)) 1 +(n.row))
  =/  until=@da
    ?.  crash  until.row
    (add now (min ~h1 (mul ~m1 (bex (dec (min n 7))))))
  ?.  (gth until now)  (pure:m ~)
  ;<  ~  bind:m
    =/  m  (fiber:fiber:nexus ,~)
    ?.  crash  (pure:m ~)
    %-  %-  slog
        ?:  (lte n 2)  [leaf+msg u.prod]
        ~[leaf+"{msg} again ({(a-co:co n)} times running); next try in {(a-co:co (div (sub until now) ~m1))} min"]
    ;<  *  bind:m
      (over-as-soft:io rise-road [[/ %json] (rise-json n now until)] [/ %json])
    (pure:m ~)
  ;<  set=?  bind:m
    (soft-behn /rise/set [[/ %timer-set] `[wire @da]`[/rise until]])
  %-  ?:(|(set !crash) same (slog leaf+"{msg}: no timer (weir?); waiting for a poke" ~))
  (rise-park note)
::
::  +take-kick: the start's null kick, holding (%skip) any real input
::  that was queued ahead of it, so it reaches the step that wants it
++  take-kick
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  |=  input:fiber:nexus
  :+  ~  q.state
  ?~(in [%done ~] [%skip ~])
::
::  +rise-park: wait for the /rise wake; a poke meanwhile is refused with
::  note (the restart it brings is not a crash, see +rise-later)
++  rise-park
  |=  note=tang
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  |=  input:fiber:nexus
  :+  ~  q.state
  ?+  in  [%wait ~]
      [~ %poke * *]
    ?.  =([/ %timer-wake] p.sage.u.in)  [%fail note]
    ?.  ?=([%rise *] !<(path q.sage.u.in))  [%wait ~]
    [%done ~]
  ==
::
::  +soft-behn: a poke to the timer service, & when it landed. A refusal
::  (a weir without /sys/behn) is | rather than a failure. The wire is
::  fixed: a nonce would ask /sys/bowl.sig for entropy, refusable too.
++  soft-behn
  |=  [=wire =bask:tarball]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  ~  bind:m
    (send-dart:io %node wire &+&+[/sys/behn %'main.behn-state'] %poke bask)
  |=  input:fiber:nexus
  :+  ~  q.state
  ?+  in  [%skip ~]
      ~  [%wait ~]
      [~ %veto *]  [%done |]
      [~ %pack * *]
    ?.  =(wire wire.u.in)  [%skip ~]
    [%done =(~ err.u.in)]
  ==
::
::  +soft-now: the time, or ~ when /sys/bowl.sig refuses (+get-time:io
::  fails instead). The answer and its ack come in either order.
++  soft-now
  =/  m  (fiber:fiber:nexus ,(unit @da))
  ^-  form:m
  ;<  ~  bind:m
    (send-dart:io %node /rise/now &+&+[/sys %'bowl.sig'] %poke [[/ %bowl-req] %now])
  ;<  first=(unit (each @da ~))  bind:m
    =/  mi  (fiber:fiber:nexus ,(unit (each @da ~)))
    ^-  form:mi
    |=  input:fiber:nexus
    :+  ~  q.state
    ?+  in  [%skip ~]
        ~  [%wait ~]
        [~ %veto *]  [%done ~]
        [~ %pack * *]  ?^(err.u.in [%done ~] [%done `[%| ~]])
        [~ %poke * *]
      ?.  =([/ %time] p.sage.u.in)  [%skip ~]
      [%done `[%& !<(@da q.sage.u.in)]]
    ==
  ?~  first  (pure:m ~)
  ?:  ?=(%| -.u.first)
    ::  acked: now the answer
    |=  input:fiber:nexus
    :+  ~  q.state
    ?+  in  [%skip ~]
        ~  [%wait ~]
        [~ %poke * *]
      ?.  =([/ %time] p.sage.u.in)  [%skip ~]
      [%done `!<(@da q.sage.u.in)]
    ==
  ::  the answer first: take its ack
  ;<  ~  bind:m
    =/  md  (fiber:fiber:nexus ,~)
    ^-  form:md
    |=  input:fiber:nexus
    :+  ~  q.state
    ?+  in  [%skip ~]
        ~  [%wait ~]
        [~ %pack *]  [%done ~]
    ==
  (pure:m `p.u.first)
::
::  the crash record beside the fiber: how many crashes running, the last
::  one, and when the wait ends. Anything unreadable is no record.
++  rise-road  (cord-to-road:tarball './rise.json')
++  read-rise
  =/  m  (fiber:fiber:nexus ,[n=@ud last=@da until=@da])
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io rise-road ~)
  =/  none=[n=@ud last=@da until=@da]  [0 *@da *@da]
  ?.  ?=([%file *] vw)  (pure:m none)
  =/  j=(unit json)  (mole |.(!<(json (need-vase:tarball sang.vw))))
  (pure:m ?~(j none (fall (de-rise:uc u.j) none)))
++  rise-json  rise-json:uc
::
::  ── bowl reads ──────────────────────────────────────────────────────
::
::  +bowl-our / +bowl-now: our/now, with the reply MARK-FILTERED. The
::  writer is a busy fiber: an %auspex-chain poke queued while it was
::  mid-work must be skipped back to the loop, not stolen by a bowl read.
::
++  bowl-ask
  |=  [ask=?(%our %now) mark=@tas]
  =/  m  (fiber:fiber:nexus ,vase)
  ^-  form:m
  ;<  ~  bind:m  (poke:io &+&+[/sys %'bowl.sig'] [[/ %bowl-req] ask])
  |=  input:fiber:nexus
  :+  ~  q.state
  ?+  in  [%skip ~]
      ~  [%wait ~]
      [~ %poke * *]
    ?.  =([/ mark] p.sage.u.in)  [%skip ~]
    [%done q.sage.u.in]
  ==
::
++  bowl-our
  =/  m  (fiber:fiber:nexus ,ship)
  ;<  v=vase  bind:m  (bowl-ask %our %ship)
  (pure:m !<(ship v))
::
++  bowl-now
  =/  m  (fiber:fiber:nexus ,@da)
  ;<  v=vase  bind:m  (bowl-ask %now %time)
  (pure:m !<(@da v))
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
  ;<  =wire    bind:m  (nonce:io /auspex-to)
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
  |=  root=@ud
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  now=@da  bind:m  bowl-now
  (put-file (rf root /beacon %rev) [/ %json] (numb:enjs:format `@ud`now))
::
::  +nexus-root: how far a REQUEST FIBER is from the nexus root.
::
::    Every serve-* arm below runs in a fiber at <root>/ui/requests/<id>,
::    laid there by the /ui/requests row in +on-load. So the distance is
::    the length of that path, and it is written as that path rather than
::    as the number 2 - move the requests directory and this follows.
::
::    This is not the thing the sandbox forbids. We are not claiming to
::    know where the nexus SITS, which no installed app can know; we are
::    counting our own layout, which this file declares.
::
++  req-dir   ^-(path /ui/requests)
::  +writer-rail: the writer's own rail, nexus-relative. Declared by the
::  /main.sig row in +on-load, so it is our layout rather than a guess
::  about where we are installed. The usergroup registry wants a rail and
::  a sandboxed app has no absolute one to give it.
++  writer-rail  ^-(rail:tarball [/ %'main.sig'])
++  nexus-root  ^-(@ud (lent req-dir))
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
  ::  drop the /apps/auspex prefix; the remainder is the route.
  =/  suffix=path  (slag 2 site.parsed)
  ::  a trailing '/' parses as a trailing empty knot, so without this
  ::  /apps/auspex/ would miss the shell route and fall to the 404 - and
  ::  a trailing slash is exactly what a browser adds when the app is
  ::  opened from a bookmark.
  =/  suffix=path
    ?:  &(?=(^ suffix) =('' (rear `path`suffix)))
      (snip `path`suffix)
    suffix
  =/  meth=@tas  method.request.req
  ::  THE OWNER GATE. auspex has no unauthenticated surface at all: no
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
  ::  auspex has no unauthenticated surface, and these two are not an
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
  ::  pulls it from there through /grubbery/tiles/icon/auspex - so it
  ::  needs a route of its own even though +serve-ui serves it.
  ?:  &(=(`path`[%'icon.svg' ~] suffix) =(%'GET' meth))
    (serve-ui eyre-id %'icon.svg')
  ::  the manifest's raster icons, for installers that want a PNG, and
  ::  the maskable one Android crops to its own shape. Behind the gate
  ::  with the rest, because Chromium sends the session cookie when it
  ::  fetches manifest icons.
  ?:  &(=(`path`[%'icon-192.png' ~] suffix) =(%'GET' meth))
    (send-png eyre-id icon-192)
  ?:  &(=(`path`[%'icon-512.png' ~] suffix) =(%'GET' meth))
    (send-png eyre-id icon-512)
  ?:  &(=(`path`[%'icon-maskable.png' ~] suffix) =(%'GET' meth))
    (send-png eyre-id icon-maskable)
  ::  our own @p, which is what the mail gate below would fetch anyway.
  ?:  &(=(`path`/api/whoami suffix) =(%'GET' meth))
    (serve-whoami eyre-id)
  ::  THE MAIL GATE, ONCE, FOR EVERY ROUTE BELOW. `authenticated` is
  ::  eyre's answer and should already imply this; comparing the `src`
  ::  the fiber was handed means the mailbox does not rest on one flag
  ::  from one vane. It costs a /sys/bowl round trip, which is worth
  ::  paying wherever the answer could be someone else's mail - and
  ::  written here once, a route added later cannot ship without it.
  ;<  our=@p  bind:m  bowl-our
  ?.  =(our src)  (send-err eyre-id 403 'forbidden')
  ?:  =(%'GET' meth)
    ::  keyed on the WHOLE suffix: /read and /api/read are different
    ::  requests and only one of them is a route.
    ?+  suffix  (send-err eyre-id 404 'not found')
    ::  THE LISTING, AND EVERY VIEW IS THIS ONE ROUTE. Inbox, Sent,
    ::  Archived, a label and a search are the same walk over the same
    ::  tree with a different predicate - see +serve-inbox. Query args,
    ::  not path segments, because a view plus a label plus a query plus
    ::  an offset plus a limit in the path would be five positional
    ::  segments a client has to get in the right order.
        [%api %inbox ~]     (serve-inbox our eyre-id args.parsed)
        [%api %thread @ ~]  (serve-thread eyre-id i.t.t.suffix)
    ::  THE ONLY ROUTE THAT ANSWERS ANYTHING BUT JSON, and the only one
    ::  whose response body is not something this nexus wrote.
        [%api %blob @ ~]    (serve-blob eyre-id i.t.t.suffix args.parsed)
        [%api %drafts ~]    (serve-drafts eyre-id)
        [%api %rules ~]     (serve-rules eyre-id)
        [%api %settings ~]  (serve-settings eyre-id)
        [%api %lists ~]     (serve-lists eyre-id)
    ::  the theme the owner set in talon, for a client that follows it.
        [%api %'talon-theme' ~]  (serve-talon-theme eyre-id)
    ==
  ?.  =(%'POST' meth)  (send-err eyre-id 404 'not found')
  ::  POST /api/blob: THE UPLOAD, and the only route whose REQUEST body
  ::  is not JSON. The body is the file, byte for byte, handed on as the
  ::  $octs eyre already built - no decode, no copy, no encoding to undo.
  ?:  =(`path`/api/blob suffix)
    (do-web-blob eyre-id body.request.req)
  ::  every other write is a JSON object, parsed once, here.
  =/  jon=(unit json)  (de:json:html (req-body req))
  ?~  jon  (send-err eyre-id 400 'not json')
  ?+  suffix  (send-err eyre-id 404 'not found')
      [%api %send ~]             (do-web-send eyre-id u.jon)
      [%api %read ~]             (do-web-mark eyre-id u.jon %read)
      [%api %unread ~]           (do-web-mark eyre-id u.jon %unread)
      [%api %fold ~]             (do-web-mark eyre-id u.jon %fold)
      [%api %unfold ~]           (do-web-mark eyre-id u.jon %unfold)
      [%api %'fetch-blob' ~]     (do-web-fetch eyre-id u.jon)
    ::  forget one discovery record, so the next send re-probes. The
    ::  user-facing half of +proto-refusal-ttl: a cap refusal is not
    ::  derivable from the record alone, so it keeps the ordinary TTL
    ::  and this is the way out of it.
      [%api %'forget-peer' ~]    (do-web-forget eyre-id u.jon)
      [%api %label ~]            (do-web-label eyre-id u.jon)
      [%api %archive ~]          (do-web-archive eyre-id u.jon)
      [%api %draft ~]            (do-web-draft eyre-id u.jon)
      [%api %'draft-delete' ~]   (do-web-id eyre-id u.jon %delete-draft)
      [%api %rule ~]             (do-web-rule eyre-id u.jon)
      [%api %settings ~]         (do-web-settings eyre-id u.jon)
      [%api %'rule-delete' ~]    (do-web-id eyre-id u.jon %delete-rule)
    ::  ONE VERB FOR A LIST. Create, overwrite, add a member, drop one,
    ::  rename by re-saving and copy the membership off a message are
    ::  all this POST, because a list is a name and a set of ships.
      [%api %list ~]             (do-web-list our eyre-id u.jon)
      [%api %'list-delete' ~]    (do-web-list-delete eyre-id u.jon)
      [%api %'delete-thread' ~]  (do-web-delete eyre-id u.jon)
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
  =/  root=@ud  nexus-root
  ::  the client's four files are grubs under /app; the icon is a grub
  ::  at the nexus ROOT, because that is where the tiles nexus reads it
  ::  from. One arm, two directories, rather than a second copy of the
  ::  peek-and-unwrap for one file.
  =/  dir=path  ?:(=(%'icon.svg' nam) / /app)
  ;<  pv=view:nexus  bind:m  (peek:io (rf root dir nam) ~)
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
::  +send-png: one of the manifest's raster icons, out of its cord below.
::
::    Cords rather than grubs. This desk has no png mark, and a file
::    whose extension has no mark crashes the desk build rather than
::    404ing. Rendered from icon.svg, which stays the one drawing:
::
::      rsvg-convert -w 192 -h 192 icon.svg | base64 -w0     icon-192
::      rsvg-convert -w 512 -h 512 icon.svg | base64 -w0     icon-512
::      sed 's/<rect x="52" y="52" width="920" height="920" rx="200"/<rect
::        width="1024" height="1024"/' icon.svg
::        | rsvg-convert -w 512 -h 512 | base64 -w0          icon-maskable
::
::    The maskable one is the same drawing with the rounded square
::    filled out to the edges, so Android's crop never shows a corner.
::    iOS takes it as the touch icon too. It wants an opaque square and
::    rounds it itself.
::
++  send-png
  |=  [eyre-id=@ta b64=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  %+  send-simple:srv  eyre-id
  :-  [200 ~[['content-type' 'image/png'] ['cache-control' 'no-cache']]]
  (de:base64:mimes:html b64)
::
++  icon-192
  ^-  @t
  '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'
++  icon-512
  ^-  @t
  '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AERERCbEAkBERGRCLABEREQmxAJARERkQiwAREREJsQCQEREZEIsAERERCbEAkBERGRCLABEREQmxAJARERkQiwAREREJsQCQEREZEIsAERERCbEAkBERGRCLABEREQmxAJARERkQiwAREREJsQCQEREZEIsAERERCbEAkBERGRCLABEREQmxAJARERkQiwAREREJsQCQEREZEIsAERERCbEAkBERGRCLABEREQmxAJARERkQiwAREREJsQCQEREZEIsAERERCbEAkBERGRCLABEREQmxAJARERkQiwAREREJsQCQEREZEIsAERERCbEAkBERGRCLABEREQmxAJARERkQiwAREREJsQCQEREZEIsAERERCbEAkBERGRCLABEREQmxAJARERkQiwAREREJsQCQEREZEIsAERERCZkUx2AiLQXbXfBHuwBAHT3WeHsDlKciIi0xgJAFKCsFokRKe2YnNuMU4a2IyexE5kJXYgJcx31n2/tCkJpQxgO1oejqDYSm4pjUVgdCY9XaJyciLTAAkAUQIKsXkzPb8TFBTWYdkoTouxHv9gfTUyYC+MynBiX4fzqP3N2B+GTA3F4d0syPtqbADfLAFHA0OyvOd0xW2o1FpHZJEb14ObpZbhkUjViw/v8MkZzZzAWbU7Bcx9loL4t1C9jEBFQXrVMk2szCwCRgSVF9+D2cw7hu5OrEGzzajJmn9uChZscePL9bBYBIj9gASCiY7JZJa6ZVo6fXlCMiFC3kgxdfVY8uyYT8z/IhsvDB4qIfIUFgIiOKjuxE/+6dgfyHe2qowAA9lZF4icvj0NJfZjqKEQBQasCwNpOZCCXFFTj7Z9+ppuLPwDkO9qx+Oef4IopVaqjENEA8CkAIgMQAvj1hftx04xS1VGOKjTIgz9dsRtZCR3427JhkJzvI9I9zgAQ6ZzVIvGnubt1e/E/0i1nleLvV+2CzcIGQKR3nAEg0jGLkPjHNbswe1yN6ij9dnFBNYKsXvzs5THwSu4bQKRXnAEg0rHfXLzfUBf/L80aV4s/XLZXdQwiOg4WACKduvXsEnz/jDLVMQbt6mkVuNkAty2IzIoFgEiHxmU48fOZRapjnLRfzDqAgqxW1TGI6ChYAIh0Zkh4Hx77/vaAWEhns0o8fO3OYx5ARETqsAAQ6cw9sw9gaHSP6hg+kxzTjbtnH1Adg4i+gQWA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'
++  icon-maskable
  ^-  @t
  'iVBORw0KGgoAAAANSUhEUgAAAgAAAAIACAIAAAB7GkOtAAAABmJLR0QA/wD/AP+gvaeTAAAgAElEQVR4nO3dd3hb5aH4cS1LlmTLS957xIkT23HiJIYwEvZqIVBoKYRNoIxOOu9tud3tvbe9lELDCnuVTUIpBQLZgTixM+3YjvfetizLS+v3R/hRGmg8dI6OpPf7+ZMHn/Pqia2vdM573ledkXqJCgAgHo3SAwAAKIMAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACIoAAICgCAAACEqn9AAQxMwGV3bCWG7CaIZ13BoxmRg1aY2cjI2Y0mu94Xq3TuMN03rGnVq3W+2Y0o5PaXts4X0jhj67vmvIWN9rru8xD9gNSr8IhcVFTuYlOvISHMkx4wmWKWvkZGLUhFHvNundOq3XGOZ2ujUuj3p8Sut0qwdH9f12Q4/N0D9qaOkzNvZFNPaYx6a0Sr8IBCt1RuolSo8BQSNM6ylMH1mSOVyaPVyYNpIcPa5W+3RA23hYTWdkZXP0/uboAy1RQw69RCMNXDHmqZJM25Ks4aVZwwtS7FFGpy9H83pVXcPGI+2Wiqbo/S3RR9osTjdf6zFTBADTy44fW1XQt7qgb1nOkEHnkeksXq+qtjtye411W3V8ZUu0y+1bWwKJTustzRo6s6B/1YK+/KRRH6t5EpMuzb7GmK1H47dWxzf3m+Q6DUIFAcC/lZfkuHRp58WLuzOtY34+9ch42Jbq+E0VybuOxbk9wVoCnda7Mm/g0tKusxb2WXz7pD8HLf2mvx9M2lSZUt9t9vOpESwIAE4Ua55as6zzstLOhal2pceiGrAb3j6Y+MqetJrOSKXHMgsLUuxXlbVfsrgnLnJS6bGoqjsiN1akvLkvZVCAK2yYFQKAf1qUNnL1qW2XLe0y6t1Kj+VER9osz+zMeKsyxRXAXwi0Gu+qgr4bTm89dd6AfNd55mbKpfmgKuGp7ZmVzdFKjwWBggBApVarzl7Ye/vZTUuyhpUeyzR6R8Kf3J754kdpjonAmsBmDndds7LtpjNb4gPgI//J7W+OfvjD7C3VCV6v0kOB0giA0DRq7+qFfXef31CUNqL0WGZhdEL3wkfpj32YPTwWpvRYVOZw17Wntq07uyna5O+r/L6o7Yp4fGvWpsqU4L3FAt8RAHGdtbDvB1+qm5c4qvRA5mh0Qvfoh9lP7cgcV2givFHvvvGMlnVnN0WGuxQZgO/qu83/8/b8LdXxSg8EyiAAIipKG/nRl2vL8gaVHogEemzhD76X+0p5qj8/yWrU3guKe370pdrU2Am/nVQ++5uj//tv8yuauDcgHAIglrjIyR9/ue6ypZ2BdovSRzWdkT9/faF/3sJKs4d/fkX1ghTlp0hJyOtVbaxM+f1b+TybLRQCIAq1WrWmtOMnl9bFmKeUHossPnkL2zR/YFSuyY5RRue3Lqxfe1qbRh2a909HxsP+/G7uc7syuDEgCAIghPnJo7/56pHFGTalByK7QYf+95vy39iXKvmRL1/W8eNL62JDNJ+fdaA16j9fKqzrjlB6IJCdNsqSr/QYICOtxrtudfN9aw+lxoTC1eppGfXu84p6SzJtH9fHOialmSoaGzH1x2sOf+OcpgB8PEIOSVGTXzu1Xav27muK8Xr5KhDKCEAoS48dX3/T/qvKOrSa0Lxk8e9kWseuKuvstRlqunx9fviixd0b1lUWBtU0Wd9p1KqyvKHTF/RXNMWIsEKfsAhAyLqqrOORWyr9v4xPgDCEec4v6k2LndhdFze3BTLNBtdvvlr9vYuOCfLB//OSoiavXNHRN2qo7rAoPRbIggCEILPB9furq+48tyFMK9YH/88rSLVfWNy9tym2f5aTW3ITHU/cVnF6/oBMAwsWYVrvuYt685MdO2utUy4Wmg41BCDUFKTan7p93ykhMcdfEjFm5xXLOwfshqoZf4y9+pT29TcdSIwK9EUd/CYvcfT8op45dBQBjgCElC8t6Xr4pv3xltCfqTIrOq33nEW9mdbx7TVWl+dkH2P1Os+vrqy6+/wGnfBfnk4QY3Z+ZUVH13B4TSeXg0IHAQgRWo33+5cc+49La8N0vHN9sQUp9lPzBrcejR+b+uLZQQmWicfXVZyzqM/PAwsWOo33vKLehKjJHbXxHmYHhQSeAwgFUUbnfdcdOmN+v4JjcLo1zf2mzkFj/2jYwKjBMalzuT55j7CYnBEGV2LUpNUymR0/5uMmiD7qsYXf/VTJgdaoE/57SabtLzceSLAoOVnWNh7W1GfqHzH02AyOKZ3N8clSdzqt1xzuiouYtEY4U2LHs6xjYVq59mWbie211u8+WzwyrvxKfPARAQh6qbHjj99akZvo8PN5PV51dXtkZUv0/uboI21R7UPGGW7iaI2cnJ88ujR7eGnm8NLsIZPf59hMOLX3PF/03uHET//LBcU9f7jmcHiYv0cyNqWtaIrZ3xJd2RRd2xUxwyvsOq03LWa8MN22NGt4adZwQard/08m13ebb9lQ2jlk9PN5IS0CENwK00ceu6XS6sc16MentFuq47dUx++otfq+6IJe51meM3TWwr4LinuSovz36dvjVf924/ynd2SqVKobz2z5yaW1/nwP7Ro2vnsoYevR+L2NMb5PrYmLmDpzQd9ZC/vPWtjnz4b12Q3rNiytaueWQBAjAEFsdUHfn647ZDb4Yy1ir1f1cX3cG/uS3zuSKMdmLBq1d1nO0OWlnRcv6fbbd4Kntmeq1aobzmjxz+nGprRv70/aWJGytzFGjmvo5nDX+YU9VyzvLMsd9M9if45J3befLd52lNWkgxUBCFZrSjt/97Ujfpis4pjQvbEv5dldGY29/thb3GJ0XrG889rTWrNC6BG25n7T87syXitPtftlI7PcRMfala2XL+s0y79Rgcut/slLhW9WpMh9IsiBAASla1e23XvFUbmvWjgmdM8rtPHW8a3KvnleQ2F6cK/BUNcdsWGLMhtvRYS7rvHLVmVer+q3mxY8tT1T1rNADgQg+Nx5XuN3Lzwm6ykck7ontmY+sT1rVNGtd9Vq1XmFPd+/pC47Pvi+DTT1mf749/z3Dicqu/WuOdx186qWW1Y1y32p8L535q3fnCPrKSA5ngMIMj+8pO6u8xrkO77LrX5pT9pdT5VsOZoQCI/+N/RGvLg7Y2DUUJRu8/98obkZHNX/z9/m/+SlwmMBsKKy06Upb4h9tTzVbHAtTLVrZPsecuq8wXC9Z3ddnFwngAwIQDD53sXHbj+nSb7jV7Vb7npqyV8/Tv93j0opwuNVH2qLenlPmlHvLkwbke8tzHfHN6W5/Ykl5Q2xAfWo1NiUbkt1wuaqhIIUe3K0XLOtSrOHI8LdO2utMh0fkiMAQeMHX6r7xtlyvfvbJ3S/3bjgZ68u7LaFy3QKH026tNtr4nfWWoszbNbIQFzroqYz8o4nlz67M2PCqcwm9dPqtxte25vabzcsyxky6GR5lGxJ1rAxzLPrGN8DggMBCA73XHzsdtne/XfVxd38aOlHx+K8qgD60PqFum3hr5anqlWqJVnDGuUvUH3C5VY/9EHuPc8Xdw0HaD4/5VWpD7dFbdqfPD9pND1uXI5TlGYPG8I8u2lAMCAAQeDm1c3fvbBejiOPT2l/82bBrzcW2CeC5rF+j1f9cX3cjhrr8pyhGLOSq0oc19Bjvm1D6abK5IC65nNyoxNhGytTBuyGsrxBOdYMX5Y9PO7UVTZHS35kSIsABLrFGbb7rj0kx6fdYz0RNz66fNvRoLxi2zMS/vre1KToyYIUu4LDeH1v6p1PLukIzhURDrdFbT6SUJY7GBshfUdPyR3cVWsN2CuKOI4ABLo/rT2UJsNX9VfLU+96akmvLYiXd3e6Ne8fSegYMp6WP+D/rW/GprQ/fWXRA+/lzW27sQAx6NC/vi813jK5MFXijmo0qryk0VfL06Q9LKRFAAJacbrtuxdJfPHH6db812sL7383zxXM71yfOtpp2VKdcMaC/iijP5bEOK5r2HjLY6WhsQSCy635oCqhbcC0qqBfJ+ne0cnRE9tr4nv4EhDACEBAu+6M1mXZwxIesN9uWLeh9P0jCRIeU3EDo/pNlcmLUu0y3dU8we66uBsfKW3tN/nhXH5T0xX5cX3cWQv7TQYpH7awjYUxIyiQhcJnwBBWLOlCCFXtljX3nVLRFIK35oYc+ls2lD67M0PuEz2zM+OWDaVDDl+XQQ1Alc3Ra+47pbojUsJjFmfYJDwaJEcAAlqidCsk76qLW/vQ8hD+Pu5yq3/5RsGv31wg02wcr1f1wLu5v3qjYIbbHgSjHlv41x8s21It2aUtZTfYwbQIQEBTq6S5JvvXj9Nu3VCq7MI+/vH0jsxvPbNY8kexJpzau58u+fN7edIeNgCNTWnvfGrJSx9Lc/NWzRtMYOPfJ6D1j0owS+eBd3N/9sqiEP7ceoJ3DyXe9GiphAsv2yd0Nz1a+tkdxEKby63+6SuLHnwv1/dDDdhD8FpZKCEAAe1op08XZL1e1W82LhDhc+sJ9jXGrF2/wvcNy1Qq1eCofu36FfsaY3w/VHC5/928325c4ONSptUd7BcW0AhAQNvsw3Qdt0f9n68UCrtKe3VH5Nf/UtY17NMjWn12w3UPLZf2vmgQeXJ75g9eLPLlu+PmqpCabxZ6CEBA21MfW989l3243B71D14semVPquRDCiJNvaZr1i+f88blnUPGrz5QVhcASzoraGNFyg//WjS33Wwae8176mMlHxIkxHMAAc2rUncOG7+8tGtWP+X2qH/wQtFb+5NlGlUQGRkP21yVcH5hb+QsHxPrGjJe+9Dy9oGgXONBWnVdkS0DpnMLe2e7EPePXyps7BU6n4GPAAS65j5zXMRUccZMHwhwe9Q/fLHwrf3s0fqJ4w24YDYN6BoyXrt+efsg7/6fqOuKbOmfXQOe353+5LYs+YYESRCAILCj1poaOzGTVc+mXJofvljEu/8JRsbD3q9KWLWgbyarhzb3m254eHkb7/7/qq47sqnPdNaivpksF/FmRcq9ry7yBs/yqMIiAEHA61W/fyTBNqZfljOs//f7eNR3m+94cukO9mP6IiPjYRsrUlKiJ+Ynj57kf/vb/uQ7n1zSaw/iNfLkc6w7cmetdWn2cFzEv92QxzGp+5+/5f/h7/lBtDi2yNgUPpjER05ed0brJSVdGZ9Z9MblVh9oiX61PG1jRbJrTjfrhLIka/i601pXFfRbjP/8NmCf0G2tjn9uVwZL2E9Lp/FeWtp55YqOJZnDus8swto2aHx7f/KzO9N7R0L2afPQQwCCUoJlItM6HqbzjIyHNfWZHAI84istndabHjeeFDWuUqm6bca2AaM4D8pJxRzuyo4fsxidTpempd/I+34wIgAAICieAwAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQREAABAUAQAAQemUHgBmRK/zWCMnYyOcFqNTpVKFh7knnFqPRz06qRuwh/XbDU53iLTcoPNYLZMx5n95pW6P2jGp6x/RD4zqA/mVhmk9cRFTVstUhMGl0XiPD97rVdknwoYcYf0jhklX4A5+VsK0HqtlMi7CGRnuVKtVn32lg6Nh/XbDVKi80tBGAAKRUe8uTrcVZ9py4h15SaOZceMx5qmT/8jgqL6pz9TQa67vjjzcbjncGhUU7zUmvbsow7Y43ZaTOJqX6Mi0jkWbnCf/kQG74ZNX2hNxqDXqSLtFqfcavc5TlD5SnG7LS7LnJjiy48diI6b5Zxpy6FsGjPXdEY195oMtUUfaosamtP4ZrS8MOk9Rhq04w5aXMJqb6Mi0jsVN90oHHfrWfuOx7oiG3ojDrVGH2y3jwfBKRaPOSL1E6TFApVKptBpvcYbtrIV9K+cNLEob0Wm8vhxtyqU50m7ZWWfdWhV/pMPi9elgEtNqvEuyhlcX9K3MHyhItuu0Pg1u0qU50mbZUWvdejS+Wv5XqlarFqWNrC7oOz2/vyh9RK/z+HI0l1td3WnZXRe39Wj8gZYot0ct1Th9p1F7C9NGVhf0nTZ/oCh9JEzr2yv1qI+0W3bXxW2pTjjUavF4A+iViowAKEytVpVmD126tPOC4t7Y6T7mz02/3fDOwcRNFSkHWqPkOP4MadTe5TlDl5Z2nlfYN+0XmrnpsYW/czBxY2XKkTaL5AcvTrddWtp10eKeBMuE5AdXqVRDDv17hxM2VaTsbYpRNtglmbbLlnZeuLjHGjkpx/EHRvXvHkrcVJlS2RwdUB9NBEQAFBMR7rr61Pa1K1tSY2V5Q/m8pj7TszszXytP9fNlB4vR+fVT269d2ZYcM+6fMzb0mJ/dmfna3pQJp6+v1Kh3X7G88/rTW3ISHJKMbVqdQ8bnd6W/+FG6fcKvV2hNeveVKzquO6MlyzrmnzO2Dxif3Z3x8sdpo/59pfgUAVBAXOTktae2XX9ma5RxmuvdcrBP6N7Yl/LIB9m9I+Fyn8saOXnNqW03nNlqUeKVDjr0z+9Mf25XxqBDP4cfjzVPXbmi48ZVLfHyfBA+Ocek7rW9KRu2ZnUNGeU+V1zE1LUrW9ee3ibTN7OTc0zoXtuX8tiH2d022X8hcQIC4Fd5SY5bVjVdVtrl4xVV3004ta/vTXliW1ZLv0mO489PHr31rKYvLeny8WaG78amtK+Xpz6+Pat9YKbvpOmx47esbrpieadR75Z1bNNyujV/25+8YUtWXXeEHMfPso7dtKr5Kys6DL7dzPDdlEuzqSJ5w7bshh6zsiMRCgHwk2iT85sX1F+7sk2r9BviZ7nc6lf3pt7393lz+4z8hWLMU3ef37D2tDaNOpBeqUf9wu70P70z7+TXVUx6962rm75xbpPihf4sr1e1sTLl92/lD9gNUh3TYnR++8L6a05t8/EmvLQ8XvWmyuTfbZo/OCrZLyROggDITqP2Xlba+eNL62S6x+u74bGwB9/LfW5Xho+zUHRa77UrW799YX1kuEuqsUlryKH/y/s5z+7M+PwsFLVataa044dfOibTnU/fjU1pH9+S9dAHOT4+CXH8lf74y3XTTlpVysh42J/fzX1+d4bLzWQheREAeZXlDv708poFyXalBzK9qnbLr94sqGiKntuPl+UN3nv50fykUWlHJYfD7ZZfvVGwv/mfr3RR2si9lx9dmjWs4KhmqKnP9Os3C7bXWOf240VpI/deUV2SaZN2VHJo7DX/6s0FO2vn+EoxEwRALhaj87+uqLl0aafSA5kFr1f18p60322a75icxayMaJPzF1+pvrikW76BSc7jVb+wO+2/35qvVqt++KXaa1a2B9QFq2m9fSD5568VDI+FzfxHzAbXf1xWc9WKDnVQfareWJHyi9cL/DwhShwEQBYlGbY/rj2YEeenWY/Sah8wfu+F4s9+QD6JFbmDf7z2cFKUn2aySqt9wOj2qjP9NetRWt228HueLypviJ3J/1yYPvJ/1x7Mjg/KV9o1ZLznhaK9jTFKDyQEaaMs+UqPIaRoNd51q5v/sPZQjFmBiY+SsJhcly/r1Kq9extjvKp/+3FRp/XefV7Db79WZTEG6BX/aVlMrmlXnghYEeGuK5Z1RpudHx2LO8mDtWq16oYzWu6/7tC0izcErEija82yTqPBXV4fyyPE0iIAUkqOGX/45v1XlXVogvy3VKNRleUNLc8Z2n0s7gsvB6XGjj9yc+WaZV3B/kqDmlqtWpxhO2PBwJ76WNsXXQ6Ki5x84PqD153eGlBzz+ZAo1aVZg+fvqB/T32cbXwWF75wcgRAMmct7Hvq9gq/PS/qB2mx45eVdh1pj2of/JcZ9OcV9jx5W0VWcF5PCD2JUZNXLO9s7DU39v7LswKn5A0+d+e+BSlBMAFhhpKiJi9f1lnXFdHcz7MC0iAA0rj6lPb//fphxZ8bkpxJ7750adewQ3+47ZN1hG44o+V3V1cZwgJomjz0Os/FJd1qlWrP/78lcGVZx/3XHzQbQu0X0hDmuaSke8qlqWjmloAECICvtBrvz9bUfOeiek0QrL48FxqNavXCvuPXmu+94ujd5zUG1zQSQajVqrK8oZToiR211rvObfiPy2pD9eqcRq06LX8gIWpyR008twR8xCwgn0SEu+6//uCZ8/uVHog/DNgNcYH6kBQ+Jc4/0/Za67efWcxCcr7gG8DcJUZNPH37vmXZQfD0kCRMIXc9ISSJ88+UaR07e1Hftpp4O7eF5ypEL1vILzt+7LVv7ylIDZ07bEDQyU8affVbe/KSQmfmhZ8RgLnIThh77s69icH59BMQSqyRk899Y29QrEESgLgHMGvzEkefvWOf3y6zHt/csardUt8T0TEU3jMc/unE/AijK9EykRY7kZdoX5Q+UujzRpLKmnRpDrdGVXVYGnoiOobCe22GT1+pxeRMsEymxo7nJowuzrT5vpGk5I5v7ni4zXKsO7JjMLx3JNw+/sngzQZXYvRESvRkbuJoYZrN940klXV8c8eqNkt9T2T7YHjPSPjop6803JUYNZEaM5GbOFqYNuL7RpIzN2A3XPfQsmM9siyaHcIIwOzMTx595ht7/bCM4sCo/p2DiVuqEsobY2a4rZVJ7z513sDZi3ovKO5VZKuZuRmwG945mPhBdfzehtgZbmRvNrhW5g+cXdB3weIeZVceHRkPe/dQwpaj8bvrvviJuc8z6DwrcgfPWdR70eKegF2P8/OGx8LePZT4YXX8x8fiZrijXHiYe0Xu0NnHX6n8S+EOjOpvfHhZTVek3CcKJQRgFgpS7U/dvk/uX+WKpujHt2ZtqU5wzXVxZr3Oc35Rzy2rmgvTR6Qdm7T2NMQ+uS1zW038nFf9Neg8FxR337q62f83Y6o7IjdsyX7vcOIMo/V5Oq13dUHfTauaV+QMSTs2aR1qi3pia+b7RxKn5vxKNd6zF/XesrpZ7vVWhxz6Gx9ZVt1BA2aKAMxUToLjhbvK5VtQxeNVf1gV/9iW7MqZrcI2E6fkDa47q+mM+f0BNXPf41W/fzhhw5ZsCTepPy1/YN1ZTaflD0h1wJPYVRf36Jbs3XVxUh2wJMN261lN5xX1BtSKpF6vaket9dEt2XvqZ7Te3EyUZg/furrp7EV98r3SQYf+mr+sYFuxGSIAMxIe5n7jOx/JN9lgX2PML98sOCrPJ5eSDNvPrjhanB4QS8CXN8T+8o2C2i5ZrtUuzxnasK7CJNvz2GNT2nUbSssbZHkGdX7y6L2XH12ROyjHwWfrUFvUr14vkLDQn1WQar93zdFlsn3vaegxr7nv1BleOBUczwHMyG1nN1+yRJb17vvshl+8XvCbTQV9I5Lt9neCblv4K3vS2gaMS7NsCk4S77GF//KNBb/dtKDfLtduf2fMH7iguEemg6tUqjCt90Bz9JF2ixwHHxjVv743tarDUppli1RugdXhsbA/vJ3/s1cXdQ3LtUV7v93w2t7Uqg7LMnleaWyEc9KlZfnomSAA09PrPH++/qDk6/x4vapndmbe+WTJoTbJrvmcRE2n5eU9qdEmZ2Gav28MeLzqJ7Zl3f10yacLCslBrVbdf/2BKJO8b535SaPP7MyU7/hNfeaXP07T6zwlmTb/X7h76eO02x9fWt4Q65V/iYWmPvPL5akmg7s4XfpXWpBif3pHpo9bnIqAAExvVUHfVWUd0h5zwG745tMlz+7K8HF/11mZdGk/rE6o7Yo8LX8g3F+rufWOhN/5VMlfP0qX+5WWZNjWndUs6ylUKpXF5NpRa+2W7dOxSqVyujU766yVzdGn5Q+aDX76KjA8Fva954o3bM2edPnvyonTpdleE3+wNfr0/EFpv5uGh3mOtEc19nInYBoEYHpXlnWUSrrew/Ya602PldZ0ynIlYVoNvRFvVSYXptlTY2XfsOyDqoRbH1t6rNsfszIuLuk+Y74/bgI39EbMcLs0X7QNmN7cl5KbMJYt/wLj5Q2xNz6yzD/fRD+vpd/0RkVyfvKotFuzdQ+H76pjP+FpEIDpfa2sfZ5Ezxm6Per/fXv+L15fODabTXclNzqp21iRolKplucMyXSdweVW/2ZjwW83LRif2Zxx3126tKs4wx83upv7TYxd3S4AABAJSURBVNuOxvvhRONO7dsHkm1jYaflD8i0tKfXq3rwvdyfvFRon1ByOZ3xKd1blSljU7qV8wal+oXstYe/czBJmmOFLhbSm55UV0sck7p7ni/6oCpBkqP5yO1R3/9uXmOf+XdfO2KQ+sHU0Qndt59ZvL3Wr5+/DGF+ur/tt6tnKpXK61U9vSOzqc98/3UHI6R+5G3SpfnxXwv/tj9Z2sPOjder2rAlq6nX9H9rD0kyjyvcX78PQY21gKYnyRZ0Pbbwa/6yIkDe/T/1VmXy9Q8tHxyVclpO55Dx6gfL/Pzur1KpRvy1JKTfTvSp7TXWqx8s6xwyTv+/ztjgqP66h5YHyLv/pz6oSvj6g2U9NglusXzhHpk4AQGYXl23r5PWa7oir3pgRWA+oFjZHP2VP59S3y3N7bKDrVFfub9Mpmn+J+f7P9NMT6TEYgO1XRGX33fKPommNjb3m772QJkf7mTMQXVH5BV/KjvS5usdslp//T4ENQIwvV2+PfNZ3hhz9QMruiT9+Cat9gHj1Q+WHfZ5evtHx+Kue2h5v12uBxpObnddnB/2h/J41bvrlZlgPujQ3/xY6UfHfH0C+XC75co/ndLcb5JkVHLoHQlf+/ByHyfyS/iodggjANM72hFZNdc3x/KG2HWPlc5wmTAF2cbDbnx4mS9Pfu6std72+BK/3fL9vG5b+E75/+Z318Up2PLxKe1tjy/Z6cPltQOtUTc+vEySq5qyckzobn2stLxhjqtQVPvwNysUZgHNSOew8bLSrtn+1EfH4m57fKmC74mzMunSvnMwaUXuUHL0rPc52F5rveOJJf6cQv6FmnvNV5V1yPf8lMer/v7zxd1SXKGeM5dH84+DSYXpI3OYNLm/OfqWR5cpO+Fn5pxuzTsHk0oybelxs56v/JOXC1v6eQhgegRgRlr6TcnRE4vSZrHk5K66uNufWBJcC5JMuTTvHEpalj2cEjOLBmw9Gn/nk0vmvFSkhHpGwg06j3yLzDy2Nfv1vakyHXzm3B71Pw4lLUy1Z8fPogEVTdE3bygNrh10XW7NOwcTi9NHMmZTu1fLUx/fmi3fqEIJAZip7TXWohl/7NpeY73jiaWKfyKeA6dL849DiUuzbDN8TGzzkYS7ny7x5/PMJ7enPjbTOj4/eUapPtga1T0cnhQ9o7193qpM/uUbBX5YI2Em3B71Pw4l5ic7cmf2mNiehth1G5YG/qXIzzv+jWdhmj1rZrXbUWv9/gvFLAIxQwRgpjxe9d8PJEcaXcUZIye5yODxqp/cnvWTlwsD5z1xtpxuzVuVyVEmZ1H6yV6p26N+bEv2va8ucnkC6JV6VerNRxJUXlVpzvBJHp7yelWvlad+65mS1/emWi2TC1PtJ3mlLrd6/ebcX7+5wA83mWfO41X/41CiVutdmjXNK33xo/Tvv1AcXF9GP8vtUb9zMMkY5j75+kger/rZXRk/erEoeP/0/I/loGetJMN2x7mNqwr6tP+6/6Lbo95SHf/Q5pxDci555k+l2cN3nNN4xoL+E1Zvd7nVH1QlrN+cG5gTW4+bnzx6x7mNFxR3n7BNpter2n0sbv3mnM/eYFyRM3THuY0r8wdOfKUe9XuHEtdvzlVkYusMFaTa7zy38dxFPSdsk+nxqnfWxq3fnFvRFIjTPeegKG3kjnMbz17Ue8Kfnser3nbUun5z7oGWEPnT8xsCMEcx5qnlOUPZ8WMWk9PmCGvqM+1tjB0OxWdP4iKmluUMZcc7Io2u4bGwpl7z3oaYwJ9GclxkuGt57mBOwliMeWp0XNfcbypvjBn4NxNVYyOmynIHs6xjEUbXkEPf1Gsqb4i1B8lFc4vRuSJ3KDvBEW1y2sd1zX2mvY2xA5I+4hcgok3O5TmD2fFjUWbnyNjxP72YIUcIvlI/IAAAICgulgGAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAiKAACAoAgAAAhKp/QAAGVEGZ1GvVulUo1PaW3jYUoPB1AAAUDo02q8C1PsK/IG5yXZcxMcWfFj0SbnCf/P8FhYc5+podd8rDuyvD62ujPS7VErMlrAb9QZqZcoPQZAFmFaz6qC/stKu1bOG7AYT3zHPznbeNjuuriNFcnbjsa7KAFCFAFACEqwTNyyqmXN8s5Y85SPhxp06N/Ym/LEtszekXBJxgYEDgKAkJIYNXHnuY1XrujQ6zwSHnbKpXmlPHX9+zlkAKGEACBE6LTea1e2fufC+ohwl0ynGJvSPr4l66EPcpxups8hFBAAhIKcBMef1h4sSLX74VxHOyK//VxJU6/JD+cCZKWNsuQrPQbAJ2tKOx+6+UBKzIR/ThdvmbqqrGPAbqjqsPjnjIBMCACCmFqt+smXa3/05Tppr/hPS6f1nrOo16R37z5m9ed5AWkRAAQrrcb766uq1p7eptQAlmYPZ8SNf1iV4PEyTxRBiQAgKGnU3v9be3jNsk5lh7EgxZ6T4HjvcKJXRQMQfAgAgtJ/rqm9qqxd6VGoVCrVvKTRuIiprUfjlR4IMGsEAMFn3dlNd53bqPQo/qkofWRsSre/OVrpgQCzw3RmBJmSTNv3Ljqm9ChO9P2L60qzh5UeBTA7BADBJMY89cANB3Qar9IDOZFO671v7aHPrzEHBDICgGDyg0vqkqL8NN9/tpKjx++5pE7pUQCzQAAQNBZn2L6yQuFpPyf31bKOJVlcCELQIAAIDmq16hdfqdaoA+7iz2dp1N6frqlRehTATBEABIdVC/oWpY0oPYrpFafbzlzQr/QogBkhAAgO3zgngOZ9ntw3z69XegjAjBAABIHFGbYgmmRZkmkrTrcpPQpgegQAQeDyZR1KD2F2FF+jApgJ9gOQkUHnOXNB36nzBjOtY77vTSgstVo1P8UegHP/T8LlVtd2RXqDacgBZGQ8zOnWtA4YPzoWu70mftLF51S5EABZ6DTeG1e13Lq6KS6C931g7gZG9U9szXpiW5bLw3J70iMA0kuKmlh/8/6iYJiyAgSFI22WO58q6Ro2Kj2QUMN3K4klRk28eFc57/6AhArTR1765t6UmHGlBxJqCICUdFrvgzccSIvj1xSQWHL0+F8CchmooEYApPT1U9tKMpn/B8iiMH3k2tNalR5FSCEAktFpvXcE0iL1QOj5xjlNOi1fAiRDACRzSt5AfOSk0qMAQpk1cnJl3oDSowgdBEAyy3OGlB4CEPqW5fKHJhkCIJlMK/d+AdllWceUHkLoIACSMRtcSg8BCH38oUmIAEhmZDxM6SEAoc82xh+aZAiAZBp6zEoPAQh99b0RSg8hdBAAyXxcH6v0EIDQV94Qo/QQQgcBkMz+luimXpPSowBCWXO/qaKJAEiGAEjG61U98H6e0qMAQtkD7+ayyLaECICU3qpM3nwkQelRAKHpw6qEt/anKD2KkEIAJPb9F4sOtkYpPQog1Bxut9zzQhEf/6WljbLkKz2GkOJ0ad4+kJRpHZ+XNKr0WIAQ8e6hxDufWuKY0Ck9kFBDAKTndGveOZh0tNOSZR1LiGJ1IGDuqtotP3+t4MH385xsDCkDdgSTV16Soyx3MCdhNMro0us8Sg8nOKlVqxf0GfVupccxC+NO7bbqeC5XzM34lHZ0UtvUZ95zLPZYD7P+ZcRXKnnVd5vru3lAzFffvejYnUG11PaTWzPv+8c8pUcBTINvVQgCb1akBtHdP69X9WZlqtKjAKZHABAEmnpNW6qDZn7tB1UJPBKIoEAAEBzWb85Reggz9VDwDBWCIwAIDgdbo7bXWJUexfS2VMcfauNBEAQHAoCg8cs3CiYDey7glEvzu00LlB4FMFMB/ecEfFZLv+nxLVlKj+JkHvkgu6mPq/8IGgQAwWT95tyjHZFKj+KLVXdEPvIhV/8RTAgAgsmkS/PNZ0pGA29JAMek7jvPlQT4FSrgBPy+Isi09Jv+4+VFHq9a6YH8k8er/vFfFzH1E0GHtYAQfOp7IoYd+tUFfUoP5BO/27Tg1fI0pUcBzBoBQFA61BYVpvMuzxlSeiCqhz/ICaJnFIDPIgAIVh8dixsZDztjfr9aoatBXq/qwfdy/8SaPwhaBABB7GBrdLfNuKqgT+P3Brg86p++Wvjk9ix/nxiQDgFAcKvusGw/Gr9y/kCU0eW3k3YNG2/bsPSDqqBZngj4QgQAQa93xLCxIiU9zk+7sP39QNJtG5Y297PKN4IeAUAomHBq3zmYtLcxtiTTFmN2ynSW1gHj955f/MiHOZMurUynAPyJHcEQUgw6z1dPaV93VnNy9LiEh+0aNj66Jevlj9OmeNQLIYQAIASFaT2XL+u66pS2kgybj4c60Br18sfpb+5Ldrp560eoIQAIZdkJY5ct7Tx9fn9h2ohWM9NNxdwe9eF2y84a66b9KTzfixBGACCEyHDXspyh/KTRrHhHdrzDGjllNrhNBpdKpRqf1I1Oavvt+qY+c3Ofua47Yl9jjD3wlhsCJEcAAEBQXNYEAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEERAAAQFAEAAEH9P1CWyje1Faw6AAAAAElFTkSuQmCC'
::
::  ── reads ───────────────────────────────────────────────────────────
::
::  +serve-whoami: our own @p AND WHAT THIS SHIP MAY DO, so the client
::  can say so before a person composes a message it cannot sign.
::
::    One /sys/bowl round trip and one peek, and the client makes it
::    once at startup rather than per request.
::
::    `caps` rides here rather than on a route of its own because it is
::    the same kind of fact - something about this ship that every
::    surface needs and no surface can derive - and because a second
::    startup request for one boolean would be a second round trip
::    before the first paint.
::
++  serve-whoami
  |=  eyre-id=@ta
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  our=@p  bind:m  bowl-our
  =/  root=@ud  nexus-root
  ;<  c=caps:uc  bind:m  (read-caps root)
  %+  send-json  eyre-id
  %-  pairs:enjs:format
  :~  ['ship' [%s (scot %p our)]]
      ['caps' (pairs:enjs:format ~[['keys' [%b keys.c]]])]
  ==
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
  |=  [our=@p eyre-id=@ta args=quay:eyre]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  view=@t   (fall (arg args 'view') 'inbox')
  =/  q=@t      (fall (arg args 'q') '')
  =/  lab=@t    (fall (arg args 'label') '')
  =/  off=@ud   (fall (arg-ud args 'offset') 0)
  ::  an ABSENT limit defaults; a limit of 0 is an empty page, literally.
  =/  lim=@ud   (min max-page:uc (fall (arg-ud args 'limit') 50))
  =/  root=@ud  nexus-root
  ;<  ix=mail-idx:uc  bind:m  (read-idx root)
  ;<  vw=view:nexus  bind:m  (peek:io (rv root thread-dir) ~)
  =/  b=ball:tarball  ?:(?=([%ball *] vw) ball.vw *ball:tarball)
  =/  rows=(map thread-id:uc row)  (collect-rows b)
  =/  keep=(list thread-id:uc)
    %+  skim  inbox.ix
    |=(t=thread-id:uc (in-view our view lab q (~(get by rows) t)))
  =/  jon=json
    %-  pairs:enjs:format
    :~  ['total' (numb:enjs:format (lent keep))]
        ['offset' (numb:enjs:format off)]
        ['limit' (numb:enjs:format lim)]
        ['view' [%s view]]
      ::  WHAT THE SIDEBAR SHOWS, WHATEVER VIEW IS OPEN: the Inbox's
      ::  unread count and every label in use. Out of the same walk, so
      ::  the client needs no second listing of everything to draw them -
      ::  and neither stops at a page size, which a client's count off the
      ::  rows it holds did.
        ['unread' (numb:enjs:format (inbox-unread our rows))]
        ['labels' (sorted-labels (all-labels rows))]
        ['threads' (inbox-json (page:uc keep off lim) rows q)]
    ==
  (send-json eyre-id jon)
++  arg  arg:uc
++  arg-ud  arg-ud:uc
++  in-view  in-view:uc
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
  |=  [eyre-id=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  root=@ud  nexus-root
  ;<  ds=(list draft:uc)  bind:m  (read-drafts root)
  ::  newest first, matching the listing's order.
  =/  sorted=(list draft:uc)
    (sort ds |=([a=draft:uc b=draft:uc] (gth at.a at.b)))
  (send-json eyre-id [%a (turn sorted draft-json:uc)])
::
++  serve-settings
  |=  eyre-id=@ta
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  s=settings:uc  bind:m  (read-settings nexus-root)
  (send-json eyre-id (settings-json:uc s))
::
::  +serve-talon-theme: the theme the owner set in talon, so an auspex
::  that follows it draws the same colours.
::
::    THREE RAW STRINGS, derived on the client. The nexus hands over
::    talon's `themes` and `accent` entries (the %settings agent, desk
::    talon, bucket ui-prefs) and our own %contacts profile, each as the
::    JSON it was stored as; the client runs talon's colour maths over
::    them. Keeping every colour decision in one place - the client -
::    rather than half here and half there.
::
::    Gated on may-scry, like every other reach into /sys/scry: a ship
::    that never proved that road is handed nulls and the client keeps
::    auspex's own palette, rather than a request that reaches for a road
::    it was refused. A ship WITHOUT talon, or without %contacts, answers
::    null for that field and never crashes - see +talon-themes-raw.
::
++  serve-talon-theme
  |=  eyre-id=@ta
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  nul=json  ~
  =/  str  |=(u=(unit @t) ^-(json ?~(u nul s+u.u)))
  ;<  may=?  bind:m  (may-scry nexus-root)
  ?.  may
    %+  send-json  eyre-id
    (pairs:enjs:format ~[['themes' nul] ['accent' nul] ['profile' nul]])
  ;<  [t=(unit @t) a=(unit @t)]  bind:m  talon-themes-raw
  ;<  p=(unit @t)  bind:m  profile-self-raw
  %+  send-json  eyre-id
  (pairs:enjs:format ~[['themes' (str t)] ['accent' (str a)] ['profile' (str p)]])
::
::  +talon-themes-raw: talon's `themes` and `accent` %settings entries
::  (desk talon, bucket ui-prefs), as the raw JSON cords they were stored
::  as; [~ ~] when %settings does not run here. A missing entry is ~.
::
++  talon-themes-raw
  =/  m  (fiber:fiber:nexus ,[themes=(unit @t) accent=(unit @t)])
  ^-  form:m
  ;<  up=(unit vase)  bind:m  (scry %noun ~[%gu %settings %$])
  ?.  (running up)  (pure:m [~ ~])
  ;<  t=(unit @t)  bind:m  (talon-entry 'themes')
  ;<  a=(unit @t)  bind:m  (talon-entry 'accent')
  (pure:m [t a])
::
::  +talon-entry: one talon ui-prefs entry, as its raw JSON cord; ~ when
::  there is no such entry. Existence is checked first (has-entry): the
::  scry service catches no failure, and a failed scry takes the whole
::  event down, the page request with it.
::
++  talon-entry
  |=  key=@t
  =/  m  (fiber:fiber:nexus ,(unit @t))
  ^-  form:m
  =/  at=path  /talon/'ui-prefs'/[key]/noun
  ;<  has=(unit vase)  bind:m  (scry %noun (weld /gx/settings/'has-entry' at))
  ?.  (running has)  (pure:m ~)
  ;<  e=(unit vase)  bind:m  (scry %noun (weld /gx/settings/entry at))
  ?~  e  (pure:m ~)
  (pure:m (bind (mole |.(;;([%entry %s @t] q.u.e))) |=([* * t=@t] t)))
::
::  +profile-self-raw: our own %contacts profile, as its raw v1 JSON;
::  ~ when %contacts does not run here. Talon's accent, when set to the
::  profile colour, takes it from this.
::
++  profile-self-raw
  =/  m  (fiber:fiber:nexus ,(unit @t))
  ^-  form:m
  ;<  up=(unit vase)  bind:m  (scry %noun ~[%gu %contacts %$])
  ?.  (running up)  (pure:m ~)
  ;<  j=(unit vase)  bind:m  (scry %json /gx/contacts/v1/self/json)
  ?~  j  (pure:m ~)
  (pure:m (bind (mole |.(!<(json u.j))) |=(jo=json (en:json:html jo))))
::
::  +running: did a %gu existence peek come back true? A grubbery scry
::  answers (unit vase); [~ &] is "the agent runs here".
::
++  running  |=(u=(unit vase) =([~ &] (bind u |=(v=vase q.v))))
::
::  +scry: a scry of one of this ship's agents, through /sys/scry, its
::  answer handed back under a mark we keep; ~ when the road is refused.
::  Ask only for what the agent surely answers (hence %gu and has-entry
::  first): the service catches no failure, and a failed scry takes the
::  whole event down, the request with it.
::
++  scry
  |=  [mark=@tas pax=path]
  =/  m  (fiber:fiber:nexus ,(unit vase))
  ^-  form:m
  ;<  err=(unit tang)  bind:m
    (poke-soft:io &+&+[/sys/scry %'main.sig'] [[/ %scry-request] [mark pax]])
  ?^  err  (pure:m ~)
  |=  input:fiber:nexus
  :+  ~  q.state
  ?+  in  [%skip ~]
      ~  [%wait ~]
      [~ %poke * *]
    ?.  =([/ mark] p.sage.u.in)  [%skip ~]
    [%done `q.sage.u.in]
  ==
::
++  serve-rules
  |=  [eyre-id=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  root=@ud  nexus-root
  ;<  rs=(list rule:uc)  bind:m  (read-rules root)
  (send-json eyre-id [%a (turn rs rule-json:uc)])
::
::  +serve-lists: every mailing list, SORTED BY NAME.
::
::    Sorted here rather than in the client because the order is a
::    property of the answer, not of one renderer: the compose
::    autocomplete and the manage panel both read this route and neither
::    should have to agree separately about what order lists come in.
::
::    `members` is ships, rendered. A list name is a key on this ship and
::    goes no further - see mar/auspex/list.
::
++  serve-lists
  |=  [eyre-id=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  root=@ud  nexus-root
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
      ['members' (ships-json:uc members.l)]
  ==
::
::  +serve-thread: one thread, every stored copy with its own verdict.
::
++  serve-thread
  |=  [eyre-id=@ta seg=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  t=(unit @uv)  (slaw %uv seg)
  ?~  t  (send-err eyre-id 400 'bad thread id')
  =/  root=@ud  nexus-root
  ::  one peek, one walk: the copies a reader can produce and the count
  ::  it cannot. The second number is what stops a thread holding only
  ::  pre-break grubs from rendering as an empty thread with no
  ::  explanation - see +slots-of.
  ;<  vw=view:nexus  bind:m  (peek:io (rv root (tdir u.t)) ~)
  =/  b=ball:tarball  ?:(?=([%ball *] vw) ball.vw *ball:tarball)
  =/  w  (slots-of b)
  =/  ss=(map path stored-msg:uc)  ss.w
  =/  lost=@ud  lost.w
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
  |=  [eyre-id=@ta seg=@ta args=quay:eyre]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  h=(unit @uv)  (slaw %uv seg)
  ?~  h  (send-err eyre-id 400 'bad hash')
  =/  root=@ud  nexus-root
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
+$  row  row:uc
::
++  collect-rows
  |=  b=ball:tarball
  ^-  (map thread-id:uc row)
  %-  ~(gas by *(map thread-id:uc row))
  %+  murn  ~(tap by dir.b)
  |=  [seg=@ta kid=ball:tarball]
  ^-  (unit [thread-id:uc row])
  =/  t=(unit @uv)  (slaw %uv seg)
  ?~  t  ~
  =/  w  (slots-of kid)
  `[u.t [ss.w (chain-of ss.w) (verdicts-of ss.w) lost.w (fall (meta-of kid) *meta:uc)]]
::
::  +meta-of: a thread's meta leaf, out of the thread's own ball, through
::  the same ladder +read-meta uses - so the listing and the thread view
::  cannot disagree about an old meta's labels and archive flag.
::
++  meta-of
  |=  kid=ball:tarball
  ^-  (unit meta:uc)
  ?~  fil.kid  ~
  =/  c=(unit [=sang:tarball gain=? bang=(unit tang)])
    (~(get by contents.u.fil.kid) %meta)
  ?~  c  ~
  ?:  (is-boom:tarball sang.u.c)  ~
  (meta-from-noun:uc (sang-noun:tarball sang.u.c))
++  row-unread  row-unread:uc
++  inbox-unread  inbox-unread:uc
++  all-labels  all-labels:uc
++  sorted-labels  sorted-labels:uc
++  msg-json  msg-json:uc
++  thread-json  thread-json:uc
++  inbox-json  inbox-json:uc
++  unreadable-entry-json  unreadable-entry-json:uc
++  entry-json  entry-json:uc
++  best-copy  best-copy:uc
::
::  ── writes ──────────────────────────────────────────────────────────
::
::  +ask-writer: hand one action to the serialised writer.
::
::    The route answers ok once the writer has taken the poke, not once it
::    has applied it. The beacon is what closes that gap: the writer bumps
::    it after the action lands and the open client refetches then. A
::    request fiber that waited for the apply would hold the connection
::    across a fan-out - a send to an unreachable ship carries a
::    twenty-second deadline per recipient.
::
::    A writer that refuses the poke is one that crashed and is waiting
::    (+rise-later refuses pokes rather than hold or drop them). The
::    route then answers 503 at once and ends cleanly: with +poke:io the
::    refusal failed this request fiber, which parked with the browser's
::    request unanswered until it timed out.
::
++  ask-writer
  |=  [eyre-id=@ta a=action:uc]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  err=(unit tang)  bind:m
    (poke-soft:io [%| 2 %& ~ %'main.sig'] [[/ %auspex-action] a])
  ?~  err  (pure:m &)
  ;<  ~  bind:m  (send-err eyre-id 503 'mail is recovering from a crash; try again in a minute')
  (pure:m |)
::
::  +do-web-send: compose, reply and forward. `prev` is the only thing
::  that tells them apart, here as everywhere else.
::
++  do-web-send
  |=  [eyre-id=@ta jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  req=(unit send-req:uw)  (de-send:uw jon)
  ?~  req  (send-err eyre-id 400 'bad send')
  ::  ATTACHMENTS, AND NOT ONE BYTE OF THEM. Each entry names a blob
  ::  this ship already holds, because the browser uploaded it to
  ::  POST /api/blob first. Decoded off the SAME json object rather than
  ::  out of $send-req, so a client that sends no `attachments` key
  ::  decodes exactly as it always did. A key that is present and wrong
  ::  is a 400: that is a client that meant to attach something and did
  ::  not, and answering ok would be a lie.
  =/  rs=(unit (list up-ref:uw))  (de-refs:uw jon max-attach:uc)
  ?~  rs  (send-err eyre-id 400 'bad attachment')
  =/  refs=(list attach-ref:uc)  u.rs
  ::  EVERYTHING THIS ROUTE CAN REFUSE IS REFUSED HERE, BEFORE THE WRITER
  ::  TAKES THE POKE. The route answers as soon as the writer takes it,
  ::  because waiting for the apply would hold the connection across the
  ::  fan-out, and the cost of that split is a lie wherever a check lives
  ::  only on the writer: a send the writer refuses writes its reason to
  ::  /tr/last, while the route has already answered 200 and the
  ::  composer has closed on the message. So every check that depends
  ::  only on the request is made here, from the same lib arms +do-send
  ::  uses. The writer still makes them all - a route check is not a
  ::  substitute for one at the point of use.
  =/  root=@ud  nexus-root
  ;<  may=?  bind:m  (may-scry root)
  ?.  may
    %^  send-err  eyre-id  400
    'this ship cannot sign mail: Auspex has not been granted the key road'
  ::  THE CAPS. The composer's own maxLength cannot catch the body one,
  ::  because that counts UTF-16 units and the cap counts BYTES. `from`,
  ::  `life`, `sent` and the signature are bunted: no predicate here
  ::  reads them. The attachment sizes are 0 for the same reason - a
  ::  ref carries no size, and the upload route already refused anything
  ::  over max-blob with a 413 before it stored a thing.
  =/  one=chain:uc
    :~  :-  :*  *@p  0  to.u.req  subject.u.req  body.u.req  ''  *@da  prev.u.req
                (turn refs |=(r=attach-ref:uc `attachment:uc`[name.r 0 mime.r hash.r]))
            ==
        0x0
    ==
  ?.  (fits-bodies:uc one max-body:uc)    (send-err eyre-id 400 'body too long')
  ?.  (fits-subjects:uc one max-subj:uc)  (send-err eyre-id 400 'subject too long')
  ?.  (fits-recipients:uc one max-to:uc)  (send-err eyre-id 400 'too many recipients')
  ?.  (refs-ok:uc refs)                   (send-err eyre-id 400 'bad attachment')
  ::  EVERY REF NAMES A BLOB WE HOLD, and naming the hash that does not
  ::  is the point: "unknown attachment" alone tells a person nothing
  ::  about which file went missing. +peek-exists, because existence is
  ::  all this needs and the writer has to read the blob anyway.
  ;<  missing=(unit @uv)  bind:m  (first-unheld root refs)
  ?^  missing
    (send-err eyre-id 400 (rap 3 ~['unknown attachment ' (scot %uv u.missing)]))
  ::  DISCOVERY: what the RECIPIENT will carry. A poke of a mark the far
  ::  end does not hold parks, and a send over the far end's caps is
  ::  dropped there, and both look from here exactly like a ship that is
  ::  offline. FROM THE CACHE ONLY: a send may name max-to recipients,
  ::  and a probe per unknown one would put a hundred round trips on the
  ::  connection the composer is waiting on. A recipient we have never
  ::  asked about is silent, silence is version 1, and its probe fiber
  ::  asks. So this refuses what we KNOW will be refused and never
  ::  guesses.
  ;<  now=@da  bind:m  bowl-now
  ;<  bad=(list [who=ship why=@t])  bind:m
    (peer-refusals root now one ~(tap in to.u.req) ~)
  ::  ONE HOSTILE RECIPIENT MUST NOT BLOCK THE OTHER NINETY-NINE. The
  ::  refusals are reported per recipient and the send goes out; each
  ::  recipient's probe fiber refuses its own, which is the real gate.
  ::
  ::  `to` IS NOT TRIMMED. It is a signed field naming the audience the
  ::  author chose; rewriting it would sign a different message than the
  ::  one composed. Delivery skips them; the message does not.
  ::
  ::  Every recipient refused is a 400: a composed message must not
  ::  vanish behind a 200 with nobody to carry it to.
  ?:  =((lent bad) ~(wyt in to.u.req))  (send-err eyre-id 400 (refusal-line bad))
  ;<  ok=?  bind:m  (ask-writer eyre-id [%send to.u.req subject.u.req body.u.req prev.u.req refs])
  ?.  ok  (pure:m ~)
  (send-refused eyre-id bad)
++  refusal-line  refusal-line:uc
::
::  +peer-refusals: EVERY recipient this send cannot reach, and why.
::
::    One peek per recipient and no round trip: the record is in our own
::    tree. A recipient we have never asked about, or whose answer
::    expired, is silent - and silence is version 1, so it is not
::    refused here and the writer will queue it for a probe.
::
::    Answers a LIST and not the first hit, because the caller sends to
::    everyone else. Returning the first refusal was how one peer
::    publishing a zero cap blocked ninety-nine others.
::
::    `size` in the probe chain is 0 and deliberately so. A ref carries
::    no size and reading one off the store costs a peek of the bytes per
::    file, on the fiber holding the connection - the same reasoning that
::    keeps `size` off this route everywhere else. What that leaves
::    unchecked here is the peer's max-blob, which the WRITER checks on
::    the real chain, where it has read the blobs anyway to sign them.
::    The count, the recipients, the subject, the body and the body mime
::    are all checked here, against the peer's numbers.
::
::    Two the route CANNOT check, and they are named rather than hidden:
::    the peer's max-chain and max-depth, because the probe chain is one
::    message and the real chain is the path this reply is joining. The
::    writer checks both on the real chain.
::
++  peer-refusals
  |=  $:  root=@ud
          now=@da
          c=chain:uc
          ws=(list ship)
          acc=(list [ship @t])
      ==
  =/  m  (fiber:fiber:nexus ,(list [ship @t]))
  ^-  form:m
  ?~  ws  (pure:m (flop acc))
  ;<  rec=(unit peer-rec:uc)  bind:m  (read-peer root i.ws)
  =/  known=(unit proto:uc)  (known-proto rec now)
  ?~  known  (peer-refusals root now c t.ws acc)
  =/  why=(unit @t)
    ?~  (peer-mark:uc known)  `(no-version-error:uc i.ws u.known)
    (peer-cap-error:uc i.ws c known)
  ::  recursion by ARM NAME: a $ with arguments inside a ;<
  ::  continuation cannot find the trap.
  ?~  why  (peer-refusals root now c t.ws acc)
  (peer-refusals root now c t.ws [[i.ws u.why] acc])
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
  |=  [root=@ud rs=(list attach-ref:uc)]
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
::    put is. So max-blobs and the budget in $settings bound the store at
::    the one place that still evicts, a blob fetch, and an upload can
::    carry the store past them. The fix is
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
  |=  [eyre-id=@ta bod=(unit octs)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
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
        (crip (a-co:co max-blob:uc))
        ' byte limit for one file'
    ==
  ::  a declared length below the measured one is a malformed octs and
  ::  would make +blob-hash disagree with anything the bytes are later
  ::  re-measured against. eyre builds this pair itself, so this is belt
  ::  to its braces and costs one +met.
  ?.  (gte p.bts (met 3 q.bts))  (send-err eyre-id 400 'malformed body')
  =/  h=@uv  (blob-hash:uc bts)
  =/  root=@ud  nexus-root
  ::  IDEMPOTENT, AND THAT IS THE ADDRESSING WORKING. The same bytes
  ::  are the same blob; re-uploading them rewrites nothing, bumps no
  ::  case in the scry farm (see +store-blob on why that matters) and
  ::  answers exactly what the first upload answered.
  ;<  ex=?  bind:m  (peek-exists:io (blob-rail root h))
  ?:  ex  (blob-uploaded eyre-id h p.bts)
  ;<  now=@da  bind:m  bowl-now
  ;<  ~  bind:m  (put-file (blob-rail root h) [/auspex %blob] [%1 bts now])
  ::  PUBLISHED: an uploaded blob is OUR file, and a recipient must be
  ::  able to keen it the instant the chain lands.
  ;<  ~  bind:m  (publish-blob root h bts)
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
::  +do-web-mark: POST /api/read, /api/unread, /api/fold and /api/unfold:
::  the ids and the thread they are in, so the writer reads one thread
::  and not the mailbox.
::
++  do-web-mark
  |=  [eyre-id=@ta jon=json a=?(%read %unread %fold %unfold)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  i=(unit (set @uv))  (de-read:uw jon)
  ?~  i  (send-err eyre-id 400 'bad msg-ids')
  =/  t=(unit @uv)  (de-uv-field:uw jon %'thread-id')
  ?~  t  (send-err eyre-id 400 'bad thread-id')
  ;<  ok=?  bind:m
    %+  ask-writer  eyre-id
    ?-  a
      %read    [%read u.i u.t]
      %unread  [%unread u.i u.t]
      %fold    [%fold u.i u.t]
      %unfold  [%unfold u.i u.t]
    ==
  ?.  ok  (pure:m ~)
  (send-ok eyre-id)
::
++  do-web-forget
  |=  [eyre-id=@ta jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  w=(unit @p)  (de-forget:uw jon)
  ?~  w  (send-err eyre-id 400 'bad ship')
  ;<  ok=?  bind:m  (ask-writer eyre-id [%forget-peer u.w])
  ?.  ok  (pure:m ~)
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
  |=  [eyre-id=@ta jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  r=(unit [hash=@uv from=@p])  (de-fetch:uw jon)
  ?~  r  (send-err eyre-id 400 'bad fetch request')
  ;<  ok=?  bind:m  (ask-writer eyre-id [%fetch-blob hash.u.r from.u.r])
  ?.  ok  (pure:m ~)
  (send-ok eyre-id)
::
::  ── the mail-client writes ──────────────────────────────────────────
::
::  Each one is the same two steps: decode, poke - the owner gate and the
::  JSON parse happened once, in +handle-request. The decoders live in the import-free web lib so a test can reach them;
::  the semantic checks (is this a @tas? does this rule have a
::  condition?) live at the writer, because this route is not the only
::  caller and a check at the boundary is not a substitute for a check
::  at the point of use.
::
++  do-web-label
  |=  [eyre-id=@ta jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  r=(unit label-req:uw)  (de-label:uw jon)
  ?~  r  (send-err eyre-id 400 'bad label request')
  ::  ANSWERED HERE, WHERE THE ANSWER CAN STILL BE NO. The route pokes
  ::  and returns as soon as the writer takes the poke, so a label the
  ::  writer refuses would otherwise be a 200 and a sidebar entry that
  ::  never appears, with the reason only in /tr/last.
  ?.  (label-ok:uc `@tas`label.u.r)
    (send-err eyre-id 400 'a label is a lowercase term: a-z, 0-9 and -')
  ;<  ok=?  bind:m
    (ask-writer eyre-id [%label thread-id.u.r `@tas`label.u.r add.u.r])
  ?.  ok  (pure:m ~)
  (send-ok eyre-id)
::
++  do-web-archive
  |=  [eyre-id=@ta jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  r=(unit [t=@uv a=?])  (de-archive:uw jon)
  ?~  r  (send-err eyre-id 400 'bad archive request')
  ;<  ok=?  bind:m  (ask-writer eyre-id [%archive t.u.r a.u.r])
  ?.  ok  (pure:m ~)
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
  |=  [eyre-id=@ta jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  r=(unit draft-req:uw)  (de-draft:uw jon)
  ?~  r  (send-err eyre-id 400 'bad draft')
  ;<  now=@da  bind:m  bowl-now
  =/  d=draft:uc
    [%0 id.u.r to.u.r subject.u.r body.u.r prev.u.r now]
  ?.  (draft-ok:uc d)
    (send-err eyre-id 400 'draft too long')
  ;<  ok=?  bind:m  (ask-writer eyre-id [%save-draft d])
  ?.  ok  (pure:m ~)
  (send-ok eyre-id)
::
++  do-web-rule
  |=  [eyre-id=@ta jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  r=(unit rule-req:uw)  (de-rule:uw jon)
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
  ;<  ok=?  bind:m  (ask-writer eyre-id [%save-rule rl])
  ?.  ok  (pure:m ~)
  (send-ok eyre-id)
::
++  do-web-settings
  |=  [eyre-id=@ta jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  r=(unit settings-req:uw)  (de-settings:uw jon)
  ?~  r  (send-err eyre-id 400 'bad settings')
  =/  s=settings:uc  [%0 u.r]
  ?.  (settings-ok:uc s)
    %^  send-err  eyre-id  400
    %+  rap  3
    :~  'the budget must be between one largest file ('
        (crip (a-co:co max-blob:uc))
        ' bytes) and '
        (crip (a-co:co max-budget:uc))
        ' bytes, automatic downloads at most one largest file, and a'
        ' ship may be on one list at most'
    ==
  ;<  ok=?  bind:m  (ask-writer eyre-id [%save-settings s])
  ?.  ok  (pure:m ~)
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
  |=  [our=@p eyre-id=@ta jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  r=(unit list-req:uw)  (de-list:uw jon our)
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
  ;<  ok=?  bind:m  (ask-writer eyre-id [%save-list name.u.r members.u.r])
  ?.  ok  (pure:m ~)
  (send-ok eyre-id)
::
++  do-web-list-delete
  |=  [eyre-id=@ta jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  n=(unit @t)  (de-list-name:uw jon)
  ?~  n  (send-err eyre-id 400 'bad list name')
  ;<  ok=?  bind:m  (ask-writer eyre-id [%delete-list u.n])
  ?.  ok  (pure:m ~)
  (send-ok eyre-id)
::
::  +do-web-id: the two routes that carry only an id and nothing to check.
::  delete-draft and delete-rule differ in nothing but the action tag.
::
++  do-web-id
  |=  [eyre-id=@ta jon=json tag=?(%delete-draft %delete-rule)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  i=(unit @uv)  (de-id:uw jon)
  ?~  i  (send-err eyre-id 400 'bad id')
  ;<  ok=?  bind:m
    %+  ask-writer  eyre-id
    ?-  tag
      %delete-draft  [%delete-draft u.i]
      %delete-rule   [%delete-rule u.i]
    ==
  ?.  ok  (pure:m ~)
  (send-ok eyre-id)
::
++  do-web-delete
  |=  [eyre-id=@ta jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  i=(unit @uv)  (de-delete:uw jon)
  ?~  i  (send-err eyre-id 400 'bad thread-id')
  ;<  ok=?  bind:m  (ask-writer eyre-id [%delete-thread u.i])
  ?.  ok  (pure:m ~)
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
::  +send-refused: ok, and who could not be reached.
::
::    `refused` is always present, empty list included, so a client can
::    read it without asking whether the field exists. The composer shows
::    "sent to N; ~x refused: <why>" off this; a client that ignores it
::    sees exactly what it saw before.
::
++  send-refused
  |=  [eyre-id=@ta bad=(list [who=ship why=@t])]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  %+  send-json  eyre-id
  %-  pairs:enjs:format
  :~  ['ok' [%b &]]
      :-  'refused'
      :-  %a
      %+  turn  bad
      |=  [w=ship y=@t]
      ^-  json
      (pairs:enjs:format ~[['ship' [%s (scot %p w)]] ['why' [%s y]]])
  ==
::
++  send-err
  |=  [eyre-id=@ta code=@ud msg=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  %+  send-simple:srv  eyre-id
  :-  [code ['content-type' 'application/json']~]
  `(as-octs:mimes:html (en:json:html (pairs:enjs:format ~[['error' [%s msg]]])))
--
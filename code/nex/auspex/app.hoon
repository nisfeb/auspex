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
              color+s+'#2563eb'
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
  ;<  ~  bind:m  (trace:io ~[leaf+"auspex: rejected: {(trip why)}"])
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
    (trace:io ~[leaf+"auspex: no public usergroup, delivery is local only"])
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
    %-  (slog leaf+"auspex: no registry road, delivery is local only" u.reg)
    (pure:m ~)
  ;<  how=(unit tang)  bind:m
    %+  reg-how-soft:io  /public
    [make=~ poke=(sy ~[`road:tarball`(rf root / %'main.sig')]) peek=~]
  ?~  how  (pure:m ~)
  %-  (slog leaf+"auspex: registry refused the public grant" u.how)
  (pure:m ~)
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
  ?:  =([/ %auspex-chain] p.sage)
    =/  res  (mule |.(~|(%auspex-bad-chain ;;(chain:uc q.q.sage))))
    ?:  ?=(%| -.res)  (reject root 'malformed chain')
    (deliver root p.res)
  ?.  ?|  =([/ %auspex-action] p.sage)
          =([/auspex %blob-in] p.sage)
          =([/auspex %probereq] p.sage)
      ==
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
  ?:  =([/auspex %blob-in] p.sage)
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
  ?:  =([/auspex %probereq] p.sage)
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
  ?.  (lte (met 3 body) max-body:uc)
    (reject root 'body too long')
  ?.  (lte (met 3 subject) max-subj:uc)
    (reject root 'subject too long')
  ?.  (lte ~(wyt in to) max-to:uc)
    (reject root 'too many recipients')
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
  =/  ss=(map path stored-msg:uc)  ?~(tid ~ (~(gut by loaded) u.tid ~))
  ::  NOTHING ANSWERS A MESSAGE THAT HAS ONLY FORGED COPIES. `prev` picks
  ::  the path that travels, so a reply to a forgery would ship a message
  ::  nobody wrote as the parent of ours - and anyone can poke us a
  ::  forged copy of an id. The clients refuse to offer it; this is where
  ::  it is actually refused.
  =/  honest-prev=?
    ?~  prev  &
    %+  lien  ~(val by ss)
    |=  s=stored-msg:uc
    &(=((id:uc unsigned.msg.s) u.prev) !=(%forged verdict.s))
  ?.  honest-prev
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
  =/  now=(set @tas)  ?:(add (~(put in labels.mt) l) (~(del in labels.mt) l))
  ::  a no-op writes nothing. Removing a label a thread does not carry
  ::  is a request a client makes freely.
  ?:  =(now labels.mt)  (pure:m |)
  ?.  (lte ~(wyt in now) max-labels:uc)  (reject root 'too many labels')
  ;<  ~  bind:m  (put-file (meta-rail root t) [/auspex %meta] mt(labels now))
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
  ?:  (~(has in members) our)  (reject root 'a list may not hold your own ship')
  ::  a list larger than a send may carry is a list that cannot be used.
  ?.  (lte ~(wyt in members) max-to:uc)  (reject root 'too many members')
  ;<  ~  bind:m  (ensure-dir root list-dir)
  ;<  ls=(list [name=@t members=(set @p)])  bind:m  (read-lists root)
  ::  the store bound counts only a list we do not already hold, so
  ::  overwriting an existing list is never refused for capacity - which
  ::  is the whole copy-from-a-message flow at the cap.
  ?.  ?|  (lien ls |=(o=[name=@t members=(set @p)] =(name.o name)))
          (lth (lent ls) max-lists:uc)
      ==
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
  =/  arch=?  ?:(wrote archive.got |(archived.mt archive.got))
  =/  want=(set @tas)  (~(uni in labels.mt) add.got)
  ::  the label bound refuses the ADDITION, never the delivery: a rule
  ::  that would push a thread past the cap simply does not add. Nacking
  ::  the chain instead would turn a rule the user wrote into a way for
  ::  a sender to get their own mail rejected.
  =/  ls=(set @tas)  ?:((lte ~(wyt in want) max-labels:uc) want labels.mt)
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
    (trace:io ~[leaf+"auspex: no key road; blob {<h>} stays unpublished"])
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
    (trace:io ~[leaf+"auspex: no key road; not republishing blobs"])
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
    (trace:io ~[leaf+"auspex: republished blob {<h.i.rs>}"])
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
    (trace:io ~[leaf+"auspex: no key road; /proto not published"])
  ;<  bound=?  bind:m  (farm-has proto-spur:uc)
  ;<  last=proto:uc  bind:m  (read-proto-pub root)
  ?:  &(bound =(last our-proto:uc))
    (trace:io ~[leaf+"auspex: /proto unchanged; not republishing"])
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
  %-  trace:io
  :~  leaf+"auspex: /proto {?:(bound "changed" "published")}; grown into the farm"
  ==
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
++  proto-probe-cases  ^-(@ud 64)
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
  ?:  (gth case proto-probe-cases)  (pure:m best)
  ;<  n=(unit (unit *))  bind:m
    (keen-page who (proto-keen-path:uc mesa-agent case) proto-timeout proto-page-mark:uc)
  ?~  n  (pure:m best)
  =/  got=(unit proto:uc)
    (biff u.n |=(x=* (mole |.(;;(proto:uc x)))))
  =?  best  &(?=(^ got) (proto-ok:uc u.got))  got
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
  (trace:io ~[leaf+"auspex: handing a send to {<who>} to its fiber"])
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
    ::    is written where an operator looks - the console.
    ::
    ::    An explicit NACK is different in kind and is handled below: it
    ::    is the far end SAYING no, which is a fact, and it does drop
    ::    the record.
    %-  trace:io
    :~  leaf+"auspex: {(trip (late-ack-note:uc who (div send-timeout ~s1)))}"
        leaf+"auspex: grubbery returns no poke-ack to a nexus fiber; not a failure"
    ==
  ?~  u.res  (pure:m ~)
  ;<  ~  bind:m  (cull-if-there (peer-rail root who))
  (say-send (nacked-note:uc who))
::
::  +say-send: one sentence, to the console. The fiber that says it does
::  not write the tree; the writer records what discovery learned.
::
++  say-send
  |=  why=@t
  (trace:io ~[leaf+"auspex: {(trip why)}"])
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
    (trace:io ~[leaf+"auspex: probe at {<id>} is not a ship name"])
  =/  who=ship  u.wu
  ;<  now=@da  bind:m  get-time:io
  ::  A FRESH RECORD IS THE ANSWER, and it keeps the time it was asked:
  ::  a peer written to every hour must still expire on +proto-ttl.
  ;<  rec=(unit peer-rec:uc)  bind:m  (read-peer root who)
  =/  n  (fiber:fiber:nexus ,[(unit proto:uc) @da])
  ;<  [got=(unit proto:uc) asked=@da]  bind:m
    ?:  &(?=(^ rec) (peer-fresh:uc u.rec now))
      (pure:n [proto.u.rec asked.u.rec])
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
  ;<  ~  bind:m  (trace:io ~[leaf+"auspex: discovery: {(trip spoke)}"])
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
  ;<  ~  bind:m  (trace:io ~[leaf+"auspex: forgot what {<who>} speaks"])
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
  ;<  ~  bind:m  (ensure-nodes root dir (sorted-dirs (node-dirs:uc (turn puts |=([pk=path *] pk)))))
  ;<  ~  bind:m  (put-slots root dir puts)
  ;<  ~  bind:m  (cull-dirs root dir dead)
  ;<  ~  bind:m  (cull-slots root dir gone)
  ::  the answer +deliver needs: did this emit a single dart? A
  ::  redelivery of a chain we already hold emits none, and must not be
  ::  allowed to look like new mail.
  (pure:m ?|(?=(^ puts) ?=(^ dead) ?=(^ gone)))
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
  =/  nex=(set msg-id:uc)  ?:(rd (~(uni in old) is) (~(dif in old) is))
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
          'verify a signature against the public key of the ship that sent it, sign the mail you send, and fetch attachments from other ships. This one road also carries the private key of this ship: signing needs it, and nothing narrower can be asked for today'
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
  ;<  ~  bind:m  (trace:io ~[leaf+"auspex: key road reachable"])
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
  =/  crash=?  !=(note u.prod)
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
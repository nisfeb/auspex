::  nex/urmail/app: the grubbery-native %urmail nexus.
::
::  urmail is a nexus, not a gall agent. The tree it owns:
::    /main.sig                    the WRITER. Takes %urmail-action (local
::                                 only) and %urmail-chain (any ship) pokes
::                                 and serialises every mutation. Nothing
::                                 else in this nexus writes.
::    /mail/thread/<tid>/msg/<slot>  one SIGNED COPY per grub, verdict and
::                                 all. <slot> is (sham [id sig]), so the
::                                 [id sig] anti-shadowing key IS the
::                                 storage key: two copies of one message
::                                 that differ in signature are two grubs
::                                 with two verdicts, and neither can
::                                 overwrite the other.
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
        |-
        ;<  [=from:fiber:nexus =sage:tarball]  bind:m  take-poke-from:io
        ;<  ~  bind:m  (apply root from sage)
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
::  +read-stored: %1 grubs only, and a %0 grub is REFUSED rather than
::  upgraded.
::
::    $stored-msg went to version 1 when `unsigned` gained attachments.
::    A %0 grub is recognisable - its head is 0 - but it cannot be
::    migrated: msg-id and the signature both cover the shape, so
::    rewriting a %0 message into the %1 shape would leave a message
::    whose signature no longer matches its own contents, which every
::    peer would then read as %forged. Turning genuine mail into apparent
::    forgeries is strictly worse than refusing it, so the ladder has no
::    %0 branch and the format change is recorded as a break. The only
::    real migration is to carry every historical shape and its digest
::    forever, and that is deferred until the format is declared stable.
::
++  read-stored
  |=  n=*
  ^-  (unit stored-msg:uc)
  =/  res  (mule |.(;;(stored-msg:uc n)))
  ?:(?=(%& -.res) `p.res ~)
::
++  read-meta
  |=  [root=path t=thread-id:uc]
  =/  m  (fiber:fiber:nexus ,meta:uc)
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io [%& %& (tdir root t) %meta] ~)
  ?.  ?=([%file *] vw)  (pure:m *meta:uc)
  ?:  (is-boom:tarball sang.vw)  (pure:m *meta:uc)
  =/  res  (mule |.(;;(meta:uc (sang-noun:tarball sang.vw))))
  (pure:m ?:(?=(%& -.res) p.res *meta:uc))
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
  ;<  loaded=(map thread-id:uc (map @ta stored-msg:uc))  bind:m  (read-threads root)
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
::  +read-threads: every stored thread, as slot maps.
::
::    One deep peek of /mail/thread rather than a walk per thread. This is
::    the O(total stored messages) read the spec already records against
::    +thread-key, now paid on the tree instead of on agent state; the
::    upgrade path is the same, a [msg-id sig] -> thread-id index grub.
::
++  read-threads
  |=  root=path
  =/  m  (fiber:fiber:nexus ,(map thread-id:uc (map @ta stored-msg:uc)))
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io [%& %| (thread-dir root)] ~)
  ?.  ?=([%ball *] vw)  (pure:m ~)
  (pure:m (collect-threads ball.vw))
::
++  collect-threads
  |=  b=ball:tarball
  ^-  (map thread-id:uc (map @ta stored-msg:uc))
  %-  ~(gas by *(map thread-id:uc (map @ta stored-msg:uc)))
  %+  murn  ~(tap by dir.b)
  |=  [seg=@ta kid=ball:tarball]
  ^-  (unit [thread-id:uc (map @ta stored-msg:uc)])
  =/  t=(unit @uv)  (slaw %uv seg)
  ?~  t  ~
  `[u.t (collect-slots kid)]
::
++  collect-slots
  |=  kid=ball:tarball
  ^-  (map @ta stored-msg:uc)
  =/  sub=(unit ball:tarball)  (~(get by dir.kid) %msg)
  ?~  sub  ~
  ?~  fil.u.sub  ~
  %-  ~(gas by *(map @ta stored-msg:uc))
  %+  murn  ~(tap by contents.u.fil.u.sub)
  |=  [nm=@ta c=[=sang:tarball gain=? bang=(unit tang)]]
  ^-  (unit [@ta stored-msg:uc])
  ?:  (is-boom:tarball sang.c)  ~
  =/  s=(unit stored-msg:uc)  (read-stored (sang-noun:tarball sang.c))
  ?~(s ~ `[nm u.s])
::
::  +chain-of: a thread's slots as a chain. +merge with an empty `old` is
::  what re-imposes the canonical order, which the tree does not store.
::
++  chain-of
  |=  ss=(map @ta stored-msg:uc)
  ^-  chain:uc
  (merge:uc ~ (turn ~(val by ss) |=(s=stored-msg:uc msg.s)))
::
++  verdicts-of
  |=  ss=(map @ta stored-msg:uc)
  ^-  (map [msg-id:uc @ux] verdict:uc)
  %-  ~(gas by *(map [msg-id:uc @ux] verdict:uc))
  %+  turn  ~(val by ss)
  |=(s=stored-msg:uc [[(id:uc unsigned.msg.s) sig.msg.s] verdict.s])
::
++  threads-of
  |=  loaded=(map thread-id:uc (map @ta stored-msg:uc))
  ^-  (map thread-id:uc thread:uc)
  %-  ~(run by loaded)
  |=  ss=(map @ta stored-msg:uc)
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
++  reject
  |=  [root=path why=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  ~  bind:m  (trace:io ~[leaf+"urmail: rejected: {(trip why)}"])
  (note root 'reject' | why)
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
++  apply
  |=  [root=path =from:fiber:nexus =sage:tarball]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ::  a chain from ANYONE. src is deliberately not checked against the
  ::  participants: the signatures are the authority, not the courier.
  ?:  =([/ %urmail-chain] p.sage)
    (deliver root !<(chain:uc q.sage))
  ?.  ?|(=([/ %urmail-action] p.sage) =([/urmail %blob-in] p.sage))
    ::  an unknown blot. Ignore it rather than crash - see the header.
    (pure:m ~)
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
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?-  -.a
    %send           (do-send root to.a subj.a body.a prev.a files.a)
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
::    The bounds +deliver enforces are enforced here too. Every send ships
::    the whole accumulated chain, so one oversized compose would poison a
::    thread permanently: every later message in it rejected by every
::    recipient, silently, forever. Failing at compose time is the only
::    point where a human can still do something about it.
::
++  do-send
  |=  $:  root=path
          to=(set ship)
          subj=@t
          body=@t
          prev=(unit msg-id:uc)
          files=(list file:uc)
      ==
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?.  (lte (met 3 body) max-body:uc)
    (reject root 'body too long')
  ?.  (lte (met 3 subj) max-subj:uc)
    (reject root 'subject too long')
  ?.  (lte ~(wyt in to) max-to:uc)
    (reject root 'too many recipients')
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
  ;<  loaded=(map thread-id:uc (map @ta stored-msg:uc))  bind:m  (read-threads root)
  ::  resolve prev to its containing thread. A msg-id is a hash over the
  ::  message's full contents, so it names exactly one message and
  ::  therefore exactly one chain.
  =/  tid=(unit thread-id:uc)
    ?~  prev  ~
    =/  hits
      %+  skim  ~(tap by loaded)
      |=  [t=thread-id:uc ss=(map @ta stored-msg:uc)]
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
  =/  u=unsigned:uc  [our lyf to subj body now prev as]
  =/  mg=msg:uc     [u (sign-with:uc rng (digest:uc u))]
  =/  old=chain:uc  ?~(tid ~ (chain-of (~(gut by loaded) u.tid ~)))
  =/  new=chain:uc  (merge:uc old ~[mg])
  ::  the outgoing chain must clear the same length bound the recipient
  ::  will apply on arrival, or the send is a silent no-op at the far end
  ::  while looking successful here.
  ?.  (fits-length:uc new max-chain:uc)
    (reject root 'chain too long')
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
  ;<  ~  bind:m  (write-msg root rid mg %verified)
  ;<  ~  bind:m  (mark-read root rid (id:uc u))
  ;<  ~  bind:m  (touch-idx root rid)
  ;<  ~  bind:m  (note root 'send' & (scot %uv rid))
  ::  ship the WHOLE chain to every recipient. A ship added at message
  ::  forty receives one through forty, each independently verifiable.
  (fan-out root new ~(tap in (~(del in to) our)))
::
++  do-read
  |=  [root=path mid=msg-id:uc]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  loaded=(map thread-id:uc (map @ta stored-msg:uc))  bind:m  (read-threads root)
  =/  hits
    %+  skim  ~(tap by loaded)
    |=  [t=thread-id:uc ss=(map @ta stored-msg:uc)]
    (lien ~(val by ss) |=(s=stored-msg:uc =((id:uc unsigned.msg.s) mid)))
  ?~  hits  (reject root 'unknown message')
  (mark-read root p.i.hits mid)
::
::  +do-delete: the escape hatch. Every capacity limit here is otherwise
::  permanent: a thread pinned at the distinct-id cap has no other remedy.
::  Culling the thread dir takes its messages, its verdicts and its read
::  marks with it, so deleting actually reclaims capacity.
::
++  do-delete
  |=  [root=path t=thread-id:uc]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  road=road:tarball  [%& %| (tdir root t)]
  ;<  ~  bind:m  (cull-if-there road)
  ;<  ix=mail-idx:uc  bind:m  (read-idx root)
  ;<  ~  bind:m
    %^  put-file  [%& %& (mail-dir root) %idx]  [/urmail %idx]
    ix(inbox (skip inbox.ix |=(o=thread-id:uc =(o t))))
  (note root 'delete-thread' & (scot %uv t))
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
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?:  =(~ c)  (pure:m ~)
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
  ;<  fake=?  bind:m  fake-ship
  ;<  keys=(map [ship @ud] (unit pass))  bind:m
    (key-map fake ~(tap in (signers:uc c)) ~)
  =/  vs=(list [[msg-id:uc @ux] verdict:uc])  (verify-chain:uc keys c)
  ;<  loaded=(map thread-id:uc (map @ta stored-msg:uc))  bind:m  (read-threads root)
  ::  thread identity is never (root:uc c). `c` is attacker-controlled and
  ::  unsorted, so the head-as-supplied is not a stable identity.
  ::  +thread-key crashes on a first-contact chain with no unique prev=~
  ::  root, which is hostile input reaching the writer, so: mule.
  =/  rk  (mule |.((thread-key:uc (threads-of loaded) c)))
  ?:  ?=(%| -.rk)  (reject root 'no unique root')
  =/  rid=thread-id:uc  p.rk
  =/  ss=(map @ta stored-msg:uc)  (~(gut by loaded) rid ~)
  =/  new=chain:uc  (merge:uc (chain-of ss) c)
  ::  a genuine state-capacity limit, and it stays a reject: shedding a
  ::  distinct non-root id would orphan the prev pointers of later
  ::  messages. The cost is recorded in the spec and not hidden.
  ?.  (lte (distinct-ids:uc new) max-chain:uc)
    (reject root 'too many messages')
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
  ;<  ~  bind:m  (sync-slots root rid ss (want-slots pruned vs2))
  ;<  ~  bind:m  (touch-idx root rid)
  (note root 'deliver' & (scot %uv rid))
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
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  have=(unit octs)  bind:m  (read-blob root h)
  ?^  have  (note root 'fetch-blob' & 'already held')
  ;<  ~  bind:m  (ensure-dir (weld root /fetch))
  ::  the id is derived from [hash ship], so asking twice for the same
  ::  blob from the same peer overwrites one request rather than
  ::  spawning a second fiber to race the first.
  =/  id=@ta  (scot %uv (sham [h who]))
  ;<  ~  bind:m
    (put-file [%& %& (weld root /fetch) id] [/urmail %fetchreq] [%0 h who])
  (note root 'fetch-blob' & 'queued')
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
  =/  m  (fiber:fiber:nexus ,~)
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
  (note root 'fetch-blob' & (scot %uv hash.b))
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
  =/  m  (fiber:fiber:nexus ,~)
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
  (note root 'restrict-blob' & (scot %uv h))
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
  =/  m  (fiber:fiber:nexus ,~)
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
    (note root 'publish-blob' & 'already public')
  ;<  ~  bind:m
    %^  put-file  (vis-rail root)  [/urmail %blobvis]
    ix(vis (~(del by vis.ix) h))
  ;<  ~  bind:m  (publish-blob h u.have &)
  (note root 'publish-blob' & (scot %uv h))
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
++  write-msg
  |=  [root=path t=thread-id:uc mg=msg:uc v=verdict:uc]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  (put-file [%& %& (mdir root t) (slot (id:uc unsigned.mg) sig.mg)] [/urmail %msg] [%1 mg v])
::
++  want-slots
  |=  [c=chain:uc vs=(map [msg-id:uc @ux] verdict:uc)]
  ^-  (map @ta stored-msg:uc)
  %-  ~(gas by *(map @ta stored-msg:uc))
  %+  turn  c
  |=  mg=msg:uc
  ^-  [@ta stored-msg:uc]
  =/  i=msg-id:uc  (id:uc unsigned.mg)
  [(slot i sig.mg) [%1 mg (~(gut by vs) [i sig.mg] %unverified)]]
::
::  +sync-slots: make the thread's grubs equal `want`.
::
::    Cull what +prune shed, write what is new or whose verdict moved,
::    leave the rest alone. Redelivering a chain we already hold writes
::    nothing at all.
::
++  sync-slots
  |=  $:  root=path
          t=thread-id:uc
          have=(map @ta stored-msg:uc)
          want=(map @ta stored-msg:uc)
      ==
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  ~  bind:m
    %+  cull-slots  (mdir root t)
    (skip ~(tap by have) |=([nm=@ta *] (~(has by want) nm)))
  %+  put-slots  (mdir root t)
  (skip ~(tap by want) |=([nm=@ta s=stored-msg:uc] =(`s (~(get by have) nm))))
::
::  recursion by ARM NAME, not by $. A $ with arguments inside a ;<
::  continuation cannot find the trap (-find.$.+2).
::
++  cull-slots
  |=  [dir=path xs=(list [@ta stored-msg:uc])]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  xs  (pure:m ~)
  ;<  *  bind:m  (cull-soft:io [%& %& dir -.i.xs])
  (cull-slots dir t.xs)
::
++  put-slots
  |=  [dir=path xs=(list [@ta stored-msg:uc])]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  xs  (pure:m ~)
  ;<  ~  bind:m  (put-file [%& %& dir -.i.xs] [/urmail %msg] +.i.xs)
  (put-slots dir t.xs)
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
--

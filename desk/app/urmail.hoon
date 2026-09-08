/-  sur=urmail
/+  default-agent, dbug, urmail
|%
+$  card  card:agent:gall
++  max-chain   1.000        ::  messages per chain
++  max-body    100.000      ::  bytes per body
++  max-subj    1.000        ::  bytes per subject
++  max-to      100          ::  recipients per message
--
%-  agent:dbug
=|  state-0:sur
=*  state  -
^-  agent:gall
::  a gall agent core must carry EXACTLY the ten agent:gall arms, or it will
::  not nest and `|install` fails with a core-nice core-shape diagnostic even
::  though `|commit` builds it fine. Helpers live in a second core below,
::  reached as `:hc`. This is the standard shape - compare app/reins.hoon.
::
=<
|_  =bowl:gall
+*  this  .
    def   ~(. (default-agent this %|) bowl)
    hc    ~(. +> bowl)
::
++  on-init   `this
++  on-save   !>(state)
++  on-load   |=(old=vase `this(state !<(state-0:sur old)))
++  on-arvo   on-arvo:def
++  on-fail   on-fail:def
++  on-leave  |=(path `this)
++  on-agent  |=([wire sign:agent:gall] `this)
++  on-watch  |=(=path (on-watch:def path))
++  on-peek   |=(=path (on-peek:def path))
::
++  on-poke
  |=  [=mark =vase]
  ^-  (quip card _this)
  ?+    mark  (on-poke:def mark vase)
      %urmail-action
    ?>  =(our.bowl src.bowl)
    =/  act  !<(action:sur vase)
    ?-  -.act
        %read
      `this(read (~(put in read) msg-id.act))
    ::
        %send
      =^  cards  state  (send:hc +.act)
      [cards this]
    ==
  ::
      %urmail-chain
    =^  cards  state  (receive:hc !<(chain:sur vase))
    [cards this]
  ==
--
::  helper core: every scry in the desk lives here, plus the send path.
::
|_  =bowl:gall
::  scry wrappers. Jael answers only at exactly now, so these need a live
::  bowl and cannot move into lib/urmail.hoon.
::
++  our-life
  ^-  @ud
  .^(@ud %j /(scot %p our.bowl)/life/(scot %da now.bowl)/(scot %p our.bowl))
::
++  our-ring
  |=  lyf=@ud
  ^-  ring
  .^(ring %j /(scot %p our.bowl)/vein/(scot %da now.bowl)/(scot %ud lyf))
::
++  fake-ship
  ^-  ?
  .^(? %j /(scot %p our.bowl)/fake/(scot %da now.bowl))
::
::  +peer-pass: a ship's public key at a given life, or ~ when none is available.
::
::    %puby is the unitized public-key scry: it returns ~ for a ship absent
::    from the local azimuth snapshot instead of blocking. A blocking scry
::    inside a gall agent stalls the agent, so %deed is not an option here.
::
::    %puby has no fake-ship branch the way %deed does, so on a fake ship it
::    would return ~ for nearly every ship and nothing would ever verify in
::    development. Mirror what %deed does for fake ships instead.
::
++  peer-pass
  |=  [who=ship lyf=@ud]
  ^-  (unit pass)
  ?:  fake-ship
    `(fake-pass:urmail who)
  =/  res
    .^  (unit [crypto-suite=@ud =pass])
        %j
        /(scot %p our.bowl)/puby/(scot %da now.bowl)/(scot %p who)/(scot %ud lyf)
    ==
  ?~  res  ~
  `pass.u.res
::
::  +key-map: one scry per distinct [ship life], not one per message
::
++  key-map
  |=  c=chain:sur
  ^-  (map [ship @ud] (unit pass))
  %-  malt
  %+  turn  ~(tap in (signers:urmail c))
  |=([who=ship lyf=@ud] [[who lyf] (peer-pass who lyf)])
::
::  +send: compose, reply, and forward are all this.
::
::    A reply points `prev` at a message in a chain we hold. A forward is
::    the same poke addressed elsewhere. The chain that travels is the
::    payload, and that is the whole design.
::
++  send
  |=  [to=(set ship) subj=@t body=@t prev=(unit msg-id:sur)]
  ^-  (quip card _state)
  ::  resolve prev to its containing thread. msg-id is a hash over the
  ::  message's full contents, so it names exactly one message and
  ::  therefore exactly one chain.
  =/  tid=(unit thread-id:sur)
    ?~  prev  ~
    =/  hits
      %+  skim  ~(tap by threads)
      |=  [t=thread-id:sur th=thread:sur]
      (lien chain.th |=(m=msg:sur =((id:urmail unsigned.m) u.prev)))
    ?~  hits  ~
    `p.i.hits
  ?:  &(?=(^ prev) ?=(~ tid))
    ~|(%urmail-unknown-prev !!)
  =/  lyf   our-life
  =/  u=unsigned:sur  [our.bowl lyf to subj body now.bowl prev]
  =/  m=msg:sur       [u (sign-with:urmail (our-ring lyf) (digest:urmail u))]
  =/  old=chain:sur
    ?~  tid  ~
    chain:(~(got by threads) u.tid)
  =/  new=chain:sur   (merge:urmail old ~[m])
  =/  rid=thread-id:sur  (root:urmail new)
  =.  threads
    %+  ~(put by threads)  rid
    [new (participants:urmail new) (last-sent:urmail new)]
  =.  inbox      [rid (skip inbox |=(t=thread-id:sur =(t rid)))]
  =.  read       (~(put in read) (id:urmail u))
  =.  verdicts   (~(put by verdicts) [(id:urmail u) sig.m] %verified)
  :_  state
  ::  ship the whole chain to every recipient. A ship added at message
  ::  forty receives messages one through forty, each independently
  ::  verifiable.
  %+  turn  ~(tap in (~(del in to) our.bowl))
  |=  who=ship
  ^-  card
  [%pass /send/(scot %uv rid) %agent [who %urmail] %poke %urmail-chain !>(new)]
::
::  +receive: accept a chain from any ship.
::
::    src.bowl is deliberately not checked against the participants. Anyone
::    may hand us a chain; the signatures are the authority, not the
::    courier. That is what makes chains portable, and it is the property
::    that separates this from a chat app.
::
++  receive
  |=  c=chain:sur
  ^-  (quip card _state)
  ?:  =(~ c)  `state
  ::  reject rather than truncate. A chain that violates a limit is not
  ::  partially trustworthy.
  ?>  (lte (lent c) max-chain)
  ?>  %-  levy  :_  |=(m=msg:sur (lte (met 3 body.unsigned.m) max-body))  c
  ?>  %-  levy  :_  |=(m=msg:sur (lte (met 3 subj.unsigned.m) max-subj))  c
  ?>  %-  levy  :_  |=(m=msg:sur (lte ~(wyt in to.unsigned.m) max-to))    c
  ::  verify before storing anything
  =/  vs  (verify-chain:urmail (key-map c) c)
  =/  rid=thread-id:sur  (root:urmail c)
  =/  old=thread:sur
    (~(gut by threads) rid *thread:sur)
  =/  new=chain:sur  (merge:urmail chain.old c)
  ::  per-poke caps do not bound a thread's growth: +merge keeps copies that
  ::  share an id but differ in signature, so an attacker can re-send one
  ::  message with N junk signatures across N pokes, each individually legal.
  ::  Cap the merged result and reject rather than truncate.
  ?>  (lte (lent new) max-chain)
  =.  threads
    %+  ~(put by threads)  rid
    [new (participants:urmail new) (last-sent:urmail new)]
  ::  a verdict is keyed [id sig], so the two copies of one id that +merge
  ::  deliberately keeps are labeled separately and never collide here. The
  ::  first-write-wins guard is only for the same signed copy arriving twice.
  =.  verdicts
    %+  roll  vs
    |=  [[k=[msg-id:sur @ux] v=verdict:sur] acc=_verdicts]
    ?:  (~(has by acc) k)  acc
    (~(put by acc) k v)
  =.  inbox  [rid (skip inbox |=(t=thread-id:sur =(t rid)))]
  `state
--

/-  sur=urmail
/+  default-agent, dbug, urmail
|%
+$  card  card:agent:gall
++  max-chain    1.000        ::  distinct messages per chain
++  max-body     100.000      ::  bytes per body
++  max-subj     1.000        ::  bytes per subject
++  max-to       100          ::  recipients per message
++  max-copies   4            ::  copies (same id, distinct sig) per message
++  max-threads  10.000       ::  distinct threads this ship will hold
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
::  +thread-key: which thread a chain belongs to.
::
::    Never derived from the incoming list's order or from `sent`: +root
::    returns the head as supplied, and an attacker controls both the order
::    and every `sent` field, so either lets one poke duplicate a conversation
::    or migrate an established thread onto a new id. An established thread's
::    identity is immutable once set; a first-contact chain is anchored on the
::    message with prev=~, which is signed content and cannot be forged.
::
::    The root is deduped by id, not counted by message: a hostile relay can
::    forward the genuine root alongside a copy with a tampered signature (the
::    exact shadowing case +merge exists to preserve, see +merge's own doc),
::    and both copies carry prev=~ since prev is part of the signed payload
::    they share. Counting messages instead of distinct ids would reject that
::    otherwise-legitimate first contact outright, which is a self-inflicted
::    denial of the very chain this arm exists to accept.
::
::    Not fixing, recorded rather than dropped: the `hits` scan below is
::    O(total stored messages) with a `sham` per message, on the only
::    externally reachable poke. Bounded by max-threads/max-chain, but
::    large. Upgrade path: a (map [msg-id @ux] thread-id) index in state.
::    This is a performance concern, not an authenticity one.
::
++  thread-key
  |=  c=chain:sur
  ^-  thread-id:sur
  =/  keys
    (~(gas in *(set [msg-id:sur @ux])) (turn c |=(m=msg:sur [(id:urmail unsigned.m) sig.m])))
  =/  hits
    %+  skim  ~(tap by threads)
    |=  [t=thread-id:sur th=thread:sur]
    %+  lien  chain.th
    |=(o=msg:sur (~(has in keys) [(id:urmail unsigned.o) sig.o]))
  ::  not fixing: a chain touching two existing threads conflates them here,
  ::  and p.i.hits picks whichever comes first in map-traversal order. This
  ::  predates +thread-key (the same pattern already existed in +send's own
  ::  `hits` lookup) and is equally reachable before and after this fix.
  ::  Upgrade path: reject chains whose keys match more than one thread,
  ::  rather than silently picking one. Also availability/correctness of
  ::  filing, not authenticity - a wrongly-filed message is still exactly
  ::  as verified or forged as it was.
  ?^  hits  p.i.hits
  =/  roots  (skim c |=(m=msg:sur ?=(~ prev.unsigned.m)))
  =/  root-ids
    (~(gas in *(set msg-id:sur)) (turn roots |=(m=msg:sur (id:urmail unsigned.m))))
  ?.  =(1 ~(wyt in root-ids))  ~|(%urmail-no-unique-root !!)
  (snag 0 ~(tap in root-ids))
::
::  +prune: enforce the per-id copy bound by SHEDDING, never by rejecting.
::
::    Rejecting the merged result is a censorship primitive: an attacker who
::    lands max-copies forged copies of a chain's genuine root at a ship
::    that has never seen the thread mints that thread under the genuine
::    (content-derived) id, holding it full of junk. When the real chain
::    later arrives from any participant, the count is max-copies+1, a
::    reject would nack it, and because every +send ships the whole chain,
::    every subsequent message in that thread would be rejected forever -
::    for the cost of a few junk-signed messages. It also reinstates, at
::    the state layer, precisely the shadowing +merge exists to prevent:
::    junk arriving first would permanently exclude the genuine copy.
::
::    Shed the excess instead, and never shed a %verified copy: +merge is
::    keyless and must keep everything it's handed, but the agent knows the
::    verdicts by the time it prunes, so it can enforce anti-shadowing with
::    that knowledge instead of by raw arrival order.
::
++  prune
  |=  [c=chain:sur vs=(map [msg-id:sur @ux] verdict:sur)]
  ^-  chain:sur
  =/  groups=(jar msg-id:sur msg:sur)
    %+  roll  c
    |=  [m=msg:sur acc=(jar msg-id:sur msg:sur)]
    (~(add ja acc) (id:urmail unsigned.m) m)
  =/  kept=chain:sur
    %-  zing
    %+  turn  ~(tap by groups)
    |=  [i=msg-id:sur ms=(list msg:sur)]
    ^-  chain:sur
    ?:  (lte (lent ms) max-copies)  ms
    =/  ver  |=(m=msg:sur =(%verified (~(gut by vs) [i sig.m] %unverified)))
    =/  good  (scag max-copies (skim ms ver))
    (weld good (scag (sub max-copies (lent good)) (skip ms ver)))
  ::  re-sort: grouping by id destroyed +merge's ordering
  (merge:urmail ~ kept)
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
  ::  thread identity is never (root:urmail new) - see +thread-key.
  =/  rid=thread-id:sur  (thread-key new)
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
  ::  partially trustworthy. This governs the INCOMING poke only - once a
  ::  chain has been verified and merged, excess state capacity is a
  ::  different question with a different answer; see +prune below.
  ~|  %urmail-chain-too-long
  ?>  (lte (lent c) max-chain)
  ~|  %urmail-body-too-long
  ?>  %-  levy  :_  |=(m=msg:sur (lte (met 3 body.unsigned.m) max-body))  c
  ~|  %urmail-subject-too-long
  ?>  %-  levy  :_  |=(m=msg:sur (lte (met 3 subj.unsigned.m) max-subj))  c
  ~|  %urmail-too-many-recipients
  ?>  %-  levy  :_  |=(m=msg:sur (lte ~(wyt in to.unsigned.m) max-to))    c
  ::  verify before storing anything
  =/  vs  (verify-chain:urmail (key-map c) c)
  ::  thread identity is never (root:urmail c) - see +thread-key. `c` is
  ::  attacker-controlled and unsorted at this point, so the head-as-supplied
  ::  is not a stable identity.
  =/  rid=thread-id:sur  (thread-key c)
  =/  old=thread:sur
    (~(gut by threads) rid *thread:sur)
  =/  new=chain:sur  (merge:urmail chain.old c)
  ::  the distinct-id count is a genuine state-capacity limit and stays a
  ::  reject - bounded state wins over availability here for v1. It is not
  ::  airtight: ids are hashes of attacker-CHOSEN content, so anyone
  ::  holding a single [id sig] already part of a thread (any past
  ::  participant, or anyone the chain was ever forwarded to) can self-sign
  ::  enough distinct junk into that same thread to hit this cap and freeze
  ::  it - unforgeable ids don't stop an authorized signer from minting
  ::  many of them. Real fix is a per-source quota; not attempted here.
  ::  Not fixed this round: availability, not authenticity.
  =/  ids  (~(gas in *(set msg-id:sur)) (turn new |=(m=msg:sur (id:urmail unsigned.m))))
  ~|  %urmail-too-many-messages
  ?>  (lte ~(wyt in ids) max-chain)
  ::  the per-thread caps above bound one thread; nothing else bounds how
  ::  many threads this ship will hold, and %urmail-chain is the only
  ::  externally reachable poke, so a fresh single-message chain per poke
  ::  mints unbounded state with no rate limit. An existing thread always
  ::  accepts - a reply must never be rejected because some unrelated thread
  ::  filled the cap - only a brand-new thread-id is capped. Not fixed this
  ::  round: an attacker can still pre-seed up to max-threads junk, self-
  ::  signed, single-message threads ahead of any genuine ones and
  ::  permanently deny new conversations once full. Availability tradeoff,
  ::  accepted for v1, same rationale as the distinct-id limitation above.
  ~|  %urmail-too-many-threads
  ?>  ?|((~(has by threads) rid) (lth ~(wyt by threads) max-threads))
  ::  a verdict is keyed [id sig], so the two copies of one id that +merge
  ::  deliberately keeps are labeled separately and never collide here.
  ::  %unverified freezes only against another %unverified: it is not a
  ::  finding about the signature, only that the key was absent from our
  ::  snapshot at that instant, and a later poke may arrive after we've
  ::  fetched the key. %verified and %forged are definitive for a fixed
  ::  [id sig] - the digest and the key are both fixed - so they can never
  ::  disagree with each other, and freezing only those two is safe.
  ::
  ::    Folded in before +prune, not after: +prune needs the verdict for
  ::    every message in `new`, including ones already stored from a
  ::    previous poke, not just the ones this poke happened to verify.
  =/  vs2=_verdicts
    %+  roll  vs
    |=  [[k=[msg-id:sur @ux] v=verdict:sur] acc=_verdicts]
    ?:  ?=(?(%verified %forged) (~(gut by acc) k %unverified))  acc
    (~(put by acc) k v)
  =/  pruned=chain:sur  (prune new vs2)
  =.  threads
    %+  ~(put by threads)  rid
    [pruned (participants:urmail pruned) (last-sent:urmail pruned)]
  =.  verdicts  vs2
  =.  inbox  [rid (skip inbox |=(t=thread-id:sur =(t rid)))]
  `state
--

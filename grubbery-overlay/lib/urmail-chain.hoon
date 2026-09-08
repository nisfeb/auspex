::  urmail-chain: the pure crypto and chain algebra, plus the types it is
::  written against.
::
::    Ported verbatim from the %urmail desk's lib/urmail.hoon and
::    sur/urmail.hoon. Every arm keeps its behaviour: signing and
::    verification, the three verdicts, [id sig] anti-shadowing, +merge,
::    +prune, +thread-key, +freeze and the input caps. Only the imports
::    changed.
::
::    The two files are ONE file here for a platform reason, not a taste
::    one. This file has to compile in two places: the desk-level /lib,
::    where -test builds it with ford runes (/- /+), and gub/lib, where
::    grubbery's loader builds it with /<. Those import syntaxes are not
::    interchangeable, so an overlay lib that imports anything can only
::    live in one of the two. Every lattice overlay lib is likewise
::    import-free. Types therefore sit in the same core rather than in a
::    sur/ that an overlay does not have.
::
::    Nothing here scries. Jael only answers at exactly `now`, so a scry
::    needs a live bowl, and a test arm has no bowl. Keys arrive as
::    arguments; the nexus is the only thing that fetches them.
::
|%
::  $msg-id: (sham unsigned). Covers exactly what a signature covers.
::
+$  msg-id     @uv
+$  thread-id  msg-id
::
::  $verdict: verification labels a message, it never rejects one.
::
::    %verified   signature checks against the sender's registered key
::    %unverified no key available for that ship (moons, comets)
::    %forged     a key was available and the signature failed
::
+$  verdict  ?(%verified %unverified %forged)
::
::  $unsigned: everything a signature covers.
::
::    `life` travels with the message because signatures must outlive key
::    rotation: a message signed under life 3 stays verifiable after the
::    sender rotates to life 4.
::
::    `prev` is what makes a flat list a chain. A reply points at the
::    message it answers; a forward points into the chain it carries.
::
+$  unsigned
  $:  from=ship
      life=@ud
      to=(set ship)
      subj=@t
      body=@t
      sent=@da
      prev=(unit msg-id)
  ==
::
+$  msg    [=unsigned sig=@ux]
+$  chain  (list msg)
::
+$  thread
  $:  =chain
      participants=(set ship)
      last=@da
  ==
::
::  $action: the local poke. %delete-thread is the escape hatch.
::
::    Every capacity limit in this agent is otherwise permanent and
::    unrecoverable: a thread pinned at the distinct-id cap, or a state
::    filled to max-threads, has no remedy but |nuke. Deletion makes those
::    limitations recoverable without committing to a quota redesign. It is
::    local-only - on-poke gates every action on our.bowl = src.bowl - so
::    no peer can delete a thread out from under us.
::
+$  action
  $%  [%send to=(set ship) subj=@t body=@t prev=(unit msg-id)]
      [%read =msg-id]
      [%delete-thread =thread-id]
  ==
::
+$  update
  $%  [%thread =thread-id]
  ==
::
+$  state-0
  $:  %0
      threads=(map thread-id thread)
      inbox=(list thread-id)              ::  newest first
      read=(set msg-id)
      verdicts=(map [msg-id @ux] verdict)   ::  keyed [id sig], see +verify-chain
  ==
::
::  +digest: the preimage every urmail signature covers.
::
::    The %urmail salt is load-bearing. The same key signs ames packets
::    and attestations; salting keeps those preimage spaces disjoint so
::    an urmail signature can never be replayed as one of those.
::
++  digest
  |=  u=unsigned
  ^-  @
  (shaf %urmail (sham u))
::
++  sign-with
  |=  [=ring msg=@]
  ^-  @ux
  (sigh:as:(nol:nu:cric:crypto ring) msg)
::
++  verify-with
  |=  [=pass sig=@ux msg=@]
  ^-  ?
  (safe:as:(com:nu:cric:crypto pass) sig msg)
::
::  fake ships: jael derives every keypair from the @p, so on a fake ship
::  any ship's keys are computable. This mirrors the fake branch of the
::  %deed scry in sys/vane/jael.hoon.
::
++  fake-core  |=(who=ship (pit:nu:cric:crypto 512 who %b ~))
++  fake-ring  |=(who=ship `ring`sec:ex:(fake-core who))
++  fake-pass  |=(who=ship `pass`pub:ex:(fake-core who))
::
++  id
  |=  u=unsigned
  ^-  msg-id
  (sham u)
::
::  +root: the thread id. Two ships holding the same conversation agree on
::  this without coordinating, because the root message is byte-identical
::  for both.
::
++  root
  |=  c=chain
  ^-  thread-id
  ?~  c  ~|(%urmail-empty-chain !!)
  (id unsigned.i.c)
::
++  participants
  |=  c=chain
  ^-  (set ship)
  %+  roll  c
  |=  [m=msg acc=(set ship)]
  (~(uni in (~(put in acc) from.unsigned.m)) to.unsigned.m)
::
++  last-sent
  |=  c=chain
  ^-  @da
  %+  roll  c
  |=([m=msg acc=@da] ?:((gth sent.unsigned.m acc) sent.unsigned.m acc))
::
++  signers
  |=  c=chain
  ^-  (set [who=ship life=@ud])
  (~(gas in *(set [ship @ud])) (turn c |=(m=msg [from.unsigned.m life.unsigned.m])))
::
::  +merge: union two chains, deduplicating and ordering by sent.
::
::    A message is a duplicate only when its contents AND its signature
::    match. +id covers `unsigned` alone, so two msgs can share an id and
::    carry different signatures - one genuine, one forged. Deduping on the
::    id alone would let whichever arrived first shadow the other, which on
::    a forwarded chain lets a malicious forwarder frame a third party as a
::    forger. Both copies are kept here; +verify-chain labels them and the
::    agent decides what to show.
::
++  merge
  |=  [old=chain new=chain]
  ^-  chain
  =/  key  |=(m=msg [(id unsigned.m) sig.m])
  =/  seen  (~(gas in *(set [msg-id @ux])) (turn old key))
  ::  fold rather than skim: `new` must be deduped against itself too,
  ::  since a peer-supplied chain may repeat a message and `old` is empty
  ::  on first contact.
  =/  added=chain
    =|  acc=chain
    |-  ^-  chain
    ?~  new  (flop acc)
    ?:  (~(has in seen) (key i.new))
      $(new t.new)
    $(new t.new, seen (~(put in seen) (key i.new)), acc [i.new acc])
  %+  sort  (weld old added)
  |=  [a=msg b=msg]
  ?.  =(sent.unsigned.a sent.unsigned.b)
    (lth sent.unsigned.a sent.unsigned.b)
  ?.  =((id unsigned.a) (id unsigned.b))
    (lth (id unsigned.a) (id unsigned.b))
  (lth sig.a sig.b)
::
::  +verify-chain: a verdict per message.
::
::    Keys arrive as a map keyed on [ship life], not just ship: life travels
::    with the message precisely so a signature stays verifiable after the
::    sender rotates, which means one ship can have multiple live keys. A
::    ship/life pair missing from the map is %unverified, never %forged -
::    that is true whether the key is missing because we never fetched that
::    life, or because a tampered life field pointed at a life we don't hold.
::    Keys arrive as a map, keyed this way, so this stays pure: the agent
::    builds it by scrying jael once per distinct [ship life] before calling
::    in.
::
++  verify-chain
  |=  [keys=(map [ship @ud] (unit pass)) c=chain]
  ^-  (list [[msg-id @ux] verdict])
  %+  turn  c
  |=  m=msg
  ^-  [[msg-id @ux] verdict]
  ::  the verdict is keyed on [id sig], not id alone. +merge deliberately
  ::  keeps two copies of one id that differ in signature; keying a verdict
  ::  on the id would collapse %verified and %forged into whichever was
  ::  written first, reinstating the shadowing attack at the state layer.
  :-  [(id unsigned.m) sig.m]
  =/  k  (~(get by keys) [from.unsigned.m life.unsigned.m])
  ?~  k  %unverified
  ?~  u.k  %unverified
  ?:  (verify-with u.u.k sig.m (digest unsigned.m))
    %verified
  %forged
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
::    Shed the excess instead, in strict verdict order: %verified first,
::    then %unverified, then %forged. +merge is keyless and must keep
::    everything it's handed, but the caller knows the verdicts by the time
::    it prunes, so anti-shadowing is enforced with that knowledge rather
::    than by raw arrival order.
::
::    The %unverified rank is not a nicety. EVERY moon and comet message is
::    %unverified in v1 - an entire class of sender, not an edge case - so
::    an unranked fill lets max-copies junk-signature copies evict the one
::    genuine copy of a moon's message, leaving the user holding only
::    forged copies of a message that was never forged. Because every send
::    re-ships the whole accumulated chain, that corrupted chain is then
::    what gets forwarded onward.
::
::    Pure: `vs` and `max-copies` arrive as arguments so this is testable
::    without an agent.
::
++  prune
  |=  [c=chain vs=(map [msg-id @ux] verdict) max-copies=@ud]
  ^-  chain
  =/  groups=(jar msg-id msg)
    %+  roll  c
    |=  [m=msg acc=(jar msg-id msg)]
    (~(add ja acc) (id unsigned.m) m)
  =/  kept=chain
    %-  zing
    %+  turn  ~(tap by groups)
    |=  [i=msg-id ms=(list msg)]
    ^-  chain
    ?:  (lte (lent ms) max-copies)  ms
    =/  vd    |=(m=msg (~(gut by vs) [i sig.m] %unverified))
    =/  good  (skim ms |=(m=msg =(%verified (vd m))))
    =/  fill
      %+  weld  (skim ms |=(m=msg =(%unverified (vd m))))
                (skim ms |=(m=msg =(%forged (vd m))))
    =/  keep  (scag max-copies good)
    (weld keep (scag (sub max-copies (lent keep)) fill))
  ::  re-sort: grouping by id destroyed +merge's ordering
  (merge ~ kept)
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
::    Pure: `threads` arrives as an argument rather than off the agent's
::    state, so thread identity - the property an attacker most wants to
::    move - is testable without an agent.
::
::    Not fixing, recorded rather than dropped: the `hits` scan below is
::    O(total stored messages) with a `sham` per message, on the only
::    externally reachable poke. Bounded by max-threads/max-chain, but
::    large. Upgrade path: a (map [msg-id @ux] thread-id) index in state.
::    This is a performance concern, not an authenticity one.
::
++  thread-key
  |=  [threads=(map thread-id thread) c=chain]
  ^-  thread-id
  =/  keys
    (~(gas in *(set [msg-id @ux])) (turn c |=(m=msg [(id unsigned.m) sig.m])))
  =/  hits
    %+  skim  ~(tap by threads)
    |=  [t=thread-id th=thread]
    %+  lien  chain.th
    |=(o=msg (~(has in keys) [(id unsigned.o) sig.o]))
  ::  not fixing: a chain touching two existing threads conflates them here,
  ::  and p.i.hits picks whichever comes first in map-traversal order. This
  ::  predates +thread-key (the same pattern already existed in +send's own
  ::  `hits` lookup) and is equally reachable before and after this fix.
  ::  Upgrade path: reject chains whose keys match more than one thread,
  ::  rather than silently picking one. Also availability/correctness of
  ::  filing, not authenticity - a wrongly-filed message is still exactly
  ::  as verified or forged as it was.
  ?^  hits  p.i.hits
  =/  roots  (skim c |=(m=msg ?=(~ prev.unsigned.m)))
  =/  root-ids
    (~(gas in *(set msg-id)) (turn roots |=(m=msg (id unsigned.m))))
  ?.  =(1 ~(wyt in root-ids))  ~|(%urmail-no-unique-root !!)
  (snag 0 ~(tap in root-ids))
::
::  +freeze: fold new verdicts into the stored map, definitively-labeled
::  entries first.
::
::    %unverified freezes only against another %unverified: it is not a
::    finding about the signature, only that the key was absent from our
::    snapshot at that instant, and a later poke may arrive after we have
::    fetched the key. %verified and %forged are definitive for a fixed
::    [id sig] - the digest and the key are both fixed - so they can never
::    disagree with each other, and freezing only those two is safe.
::
::    Keyed [id sig], so the two copies of one id that +merge deliberately
::    keeps are labeled separately and never collide.
::
++  freeze
  |=  $:  old=(map [msg-id @ux] verdict)
          new=(list [[msg-id @ux] verdict])
      ==
  ^-  (map [msg-id @ux] verdict)
  =/  acc  old
  |-  ^-  (map [msg-id @ux] verdict)
  ?~  new  acc
  ?:  ?=(?(%verified %forged) (~(gut by acc) -.i.new %unverified))
    $(new t.new)
  $(new t.new, acc (~(put by acc) -.i.new +.i.new))
::
::  the input caps, as predicates. The agent wraps each in its own tall ~|
::  and ?>, since the label is what tells a nacked poke apart from any
::  other crash; keeping the arithmetic here keeps it testable.
::
++  fits-length
  |=([c=chain m=@ud] (lte (lent c) m))
::
++  fits-bodies
  |=([c=chain m=@ud] (levy c |=(x=msg (lte (met 3 body.unsigned.x) m))))
::
++  fits-subjects
  |=([c=chain m=@ud] (levy c |=(x=msg (lte (met 3 subj.unsigned.x) m))))
::
++  fits-recipients
  |=([c=chain m=@ud] (levy c |=(x=msg (lte ~(wyt in to.unsigned.x) m))))
::
::  distinct message ids, not messages: +merge deliberately keeps several
::  signed copies of one id, and the state-capacity bound counts messages
::  the user could actually read, not copies of them.
::
++  distinct-ids
  |=  c=chain
  ^-  @ud
  ~(wyt in (~(gas in *(set msg-id)) (turn c |=(m=msg (id unsigned.m)))))
--

::  urmail: pure crypto and chain algebra.
::
::    Nothing here scries. Jael only answers at exactly `now`, so a scry
::    needs a live bowl, and a test arm has no bowl. Keys arrive as
::    arguments; app/urmail.hoon is the only file that fetches them.
::
/-  sur=urmail
|%
::  +digest: the preimage every urmail signature covers.
::
::    The %urmail salt is load-bearing. The same key signs ames packets
::    and attestations; salting keeps those preimage spaces disjoint so
::    an urmail signature can never be replayed as one of those.
::
++  digest
  |=  u=unsigned:sur
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
  |=  u=unsigned:sur
  ^-  msg-id:sur
  (sham u)
::
::  +root: the thread id. Two ships holding the same conversation agree on
::  this without coordinating, because the root message is byte-identical
::  for both.
::
++  root
  |=  c=chain:sur
  ^-  thread-id:sur
  ?~  c  ~|(%urmail-empty-chain !!)
  (id unsigned.i.c)
::
++  participants
  |=  c=chain:sur
  ^-  (set ship)
  %+  roll  c
  |=  [m=msg:sur acc=(set ship)]
  (~(uni in (~(put in acc) from.unsigned.m)) to.unsigned.m)
::
++  last-sent
  |=  c=chain:sur
  ^-  @da
  %+  roll  c
  |=([m=msg:sur acc=@da] ?:((gth sent.unsigned.m acc) sent.unsigned.m acc))
::
++  signers
  |=  c=chain:sur
  ^-  (set [who=ship life=@ud])
  (~(gas in *(set [ship @ud])) (turn c |=(m=msg:sur [from.unsigned.m life.unsigned.m])))
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
  |=  [old=chain:sur new=chain:sur]
  ^-  chain:sur
  =/  key  |=(m=msg:sur [(id unsigned.m) sig.m])
  =/  seen  (~(gas in *(set [msg-id:sur @ux])) (turn old key))
  ::  fold rather than skim: `new` must be deduped against itself too,
  ::  since a peer-supplied chain may repeat a message and `old` is empty
  ::  on first contact.
  =/  added=chain:sur
    =|  acc=chain:sur
    |-  ^-  chain:sur
    ?~  new  (flop acc)
    ?:  (~(has in seen) (key i.new))
      $(new t.new)
    $(new t.new, seen (~(put in seen) (key i.new)), acc [i.new acc])
  %+  sort  (weld old added)
  |=  [a=msg:sur b=msg:sur]
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
  |=  [keys=(map [ship @ud] (unit pass)) c=chain:sur]
  ^-  (list [[msg-id:sur @ux] verdict:sur])
  %+  turn  c
  |=  m=msg:sur
  ^-  [[msg-id:sur @ux] verdict:sur]
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
  |=  [c=chain:sur vs=(map [msg-id:sur @ux] verdict:sur) max-copies=@ud]
  ^-  chain:sur
  =/  groups=(jar msg-id:sur msg:sur)
    %+  roll  c
    |=  [m=msg:sur acc=(jar msg-id:sur msg:sur)]
    (~(add ja acc) (id unsigned.m) m)
  =/  kept=chain:sur
    %-  zing
    %+  turn  ~(tap by groups)
    |=  [i=msg-id:sur ms=(list msg:sur)]
    ^-  chain:sur
    ?:  (lte (lent ms) max-copies)  ms
    =/  vd    |=(m=msg:sur (~(gut by vs) [i sig.m] %unverified))
    =/  good  (skim ms |=(m=msg:sur =(%verified (vd m))))
    =/  fill
      %+  weld  (skim ms |=(m=msg:sur =(%unverified (vd m))))
                (skim ms |=(m=msg:sur =(%forged (vd m))))
    =/  keep  (scag max-copies good)
    (weld keep (scag (sub max-copies (lent keep)) fill))
  ::  re-sort: grouping by id destroyed +merge's ordering
  (merge ~ kept)
--

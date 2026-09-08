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
::  +merge: union two chains, deduplicating by msg-id and ordering by sent.
::
::    Identical ids imply identical bytes, so on a collision the message we
::    already hold wins and the incoming copy is dropped. Receiving the same
::    chain twice is a no-op.
::
++  merge
  |=  [old=chain:sur new=chain:sur]
  ^-  chain:sur
  =/  seen  (~(gas in *(set msg-id:sur)) (turn old |=(m=msg:sur (id unsigned.m))))
  =/  added
    %+  skim  new
    |=(m=msg:sur !(~(has in seen) (id unsigned.m)))
  %+  sort  (weld old added)
  |=  [a=msg:sur b=msg:sur]
  ?:  =(sent.unsigned.a sent.unsigned.b)
    (lth (id unsigned.a) (id unsigned.b))
  (lth sent.unsigned.a sent.unsigned.b)
::
::  +verify-chain: a verdict per message.
::
::    Keys arrive as a map so this stays pure. The agent builds the map by
::    scrying jael once per distinct signer before calling in.
::
++  verify-chain
  |=  [keys=(map ship (unit pass)) c=chain:sur]
  ^-  (list [msg-id:sur verdict:sur])
  %+  turn  c
  |=  m=msg:sur
  ^-  [msg-id:sur verdict:sur]
  :-  (id unsigned.m)
  =/  k  (~(get by keys) from.unsigned.m)
  ?~  k  %unverified
  ?~  u.k  %unverified
  ?:  (verify-with u.u.k sig.m (digest unsigned.m))
    %verified
  %forged
--

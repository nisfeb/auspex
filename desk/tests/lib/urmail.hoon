/-  sur=urmail
/+  *test, urmail
|%
::  +forge: build a genuinely signed message as any ship, using the fake-ship
::  key derivation. This is what lets the third-party forward case be tested
::  with no network and no second ship.
++  forge
  |=  [who=ship to=(set ship) subj=@t body=@t sent=@da prev=(unit msg-id:sur)]
  ^-  msg:sur
  =/  u=unsigned:sur  [who 1 to subj body sent prev]
  [u (sign-with:urmail (fake-ring:urmail who) (digest:urmail u))]
::
::  +forge hardcodes life 1, so the map is keyed on [w 1] for every ship
::  passed in.
++  all-keys
  |=  who=(list ship)
  ^-  (map [ship @ud] (unit pass))
  %-  malt
  %+  turn  who
  |=(w=ship [[w 1] `(fake-pass:urmail w)])
::
::  a signature made with a ship's key verifies against that ship's key
++  test-sign-verify-roundtrip
  =/  who   ~sampel-palnet
  =/  msg   (shaf %urmail (sham [%hello 'world']))
  =/  sig   (sign-with:urmail (fake-ring:urmail who) msg)
  (expect !>((verify-with:urmail (fake-pass:urmail who) sig msg)))
::
::  a signature does not verify against a different ship's key
++  test-sign-wrong-key-fails
  =/  msg   (shaf %urmail (sham [%hello 'world']))
  =/  sig   (sign-with:urmail (fake-ring:urmail ~sampel-palnet) msg)
  (expect !>(!(verify-with:urmail (fake-pass:urmail ~palnet-sampel) sig msg)))
::
::  a signature does not verify against a different message
++  test-sign-wrong-message-fails
  =/  who   ~sampel-palnet
  =/  sig   (sign-with:urmail (fake-ring:urmail who) (shaf %urmail (sham 'a')))
  (expect !>(!(verify-with:urmail (fake-pass:urmail who) sig (shaf %urmail (sham 'b')))))
::
::  +digest is what every later task signs and verifies over, so it is
::  tested directly rather than reimplemented by its callers.
++  test-digest-is-salted-sham
  =/  u=unsigned:sur
    [~sampel-palnet 1 (sy ~[~palnet-sampel]) 'subj' 'body' ~2026.1.1 ~]
  %+  expect-eq
    !>  (shaf %urmail (sham u))
    !>  (digest:urmail u)
::
::  domain separation: the salted digest must differ from the unsalted hash
::  and from the same message salted for another protocol. This is the
::  property that stops an urmail signature being replayed as an ames one,
::  and it is mandatory per the spec.
++  test-digest-domain-separated
  =/  u=unsigned:sur
    [~sampel-palnet 1 (sy ~[~palnet-sampel]) 'subj' 'body' ~2026.1.1 ~]
  ;:  weld
    (expect !>(!=((digest:urmail u) (sham u))))
    (expect !>(!=((digest:urmail u) (shaf %ames (sham u)))))
  ==
::
::  a msg-id is a hash over every signed field, so changing any field
::  changes the id. This is what lets two ships agree on a thread id
::  without coordinating.
++  test-msg-id-covers-every-field
  =/  base=unsigned:sur
    [~sampel-palnet 1 (sy ~[~palnet-sampel]) 'subj' 'body' ~2026.1.1 ~]
  =/  d  (digest:urmail base)
  ;:  weld
    (expect !>(!=(d (digest:urmail base(body 'other')))))
    (expect !>(!=(d (digest:urmail base(subj 'other')))))
    (expect !>(!=(d (digest:urmail base(life 2)))))
    (expect !>(!=(d (digest:urmail base(from ~palnet-sampel)))))
    (expect !>(!=(d (digest:urmail base(sent ~2026.1.2)))))
    (expect !>(!=(d (digest:urmail base(to (sy ~[~sampel-palnet]))))))
    (expect !>(!=(d (digest:urmail base(prev `0v1)))))
  ==
::
::  THE MARQUEE TEST. ~sampel writes to ~palnet; ~palnet forwards the chain
::  to ~marbud, who has never spoken to ~sampel. ~marbud verifies ~sampel's
::  signature anyway. This is the one thing a chat app cannot do.
++  test-third-party-verifies-forwarded-chain
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'from sampel' ~2026.1.1 ~)
  =/  b
    %-  forge
    :*  ~palnet-sampel  (sy ~[~marbud-marbud])  'fwd: hi'  'see below'
        ~2026.1.2  `(id:urmail unsigned.a)
    ==
  =/  keys  (all-keys ~[~sampel-palnet ~palnet-sampel])
  %+  expect-eq
    !>  ~[%verified %verified]
    !>  (turn (verify-chain:urmail keys ~[a b]) |=([* v=verdict:sur] v))
::
::  a tampered body flips the verdict to %forged, not %unverified
++  test-tampered-body-is-forged
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'real' ~2026.1.1 ~)
  =/  bad=msg:sur  a(body.unsigned 'tampered')
  =/  keys  (all-keys ~[~sampel-palnet])
  %+  expect-eq
    !>  ~[%forged]
    !>  (turn (verify-chain:urmail keys ~[bad]) |=([* v=verdict:sur] v))
::
::  a tampered life flips the verdict too, since life is inside the digest
++  test-tampered-life-is-forged
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'real' ~2026.1.1 ~)
  =/  bad=msg:sur  a(life.unsigned 7)
  =/  keys  (all-keys ~[~sampel-palnet])
  %+  expect-eq
    !>  ~[%forged]
    !>  (turn (verify-chain:urmail keys ~[bad]) |=([* v=verdict:sur] v))
::
::  no key available means %unverified, never %forged. Moons land here.
++  test-missing-key-is-unverified
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'real' ~2026.1.1 ~)
  %+  expect-eq
    !>  ~[%unverified]
    !>  (turn (verify-chain:urmail (malt ~[[~sampel-palnet ~]]) ~[a]) |=([* v=verdict:sur] v))
::
::  merging the same chain twice is a no-op: double delivery must not
::  duplicate messages
++  test-merge-dedupes
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  b
    %-  forge
    :*  ~palnet-sampel  (sy ~[~sampel-palnet])  're: hi'  'two'
        ~2026.1.2  `(id:urmail unsigned.a)
    ==
  %+  expect-eq
    !>  ~[a b]
    !>  (merge:urmail ~[a b] ~[a b])
::
::  merge keeps messages in sent order regardless of arrival order
++  test-merge-orders-by-sent
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  b
    %-  forge
    :*  ~palnet-sampel  (sy ~[~sampel-palnet])  're: hi'  'two'
        ~2026.1.2  `(id:urmail unsigned.a)
    ==
  %+  expect-eq
    !>  ~[a b]
    !>  (merge:urmail ~[b] ~[a])
::
::  the root of a chain is the id of its first message, and every ship
::  computes the same one because the root message is byte-identical
++  test-root-is-first-message-id
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  b
    %-  forge
    :*  ~palnet-sampel  (sy ~[~sampel-palnet])  're: hi'  'two'
        ~2026.1.2  `(id:urmail unsigned.a)
    ==
  %+  expect-eq
    !>  (id:urmail unsigned.a)
    !>  (root:urmail ~[a b])
::
::  participants is the union of from and to across the whole chain, so a
::  ship added by a forward is a participant
++  test-participants-includes-forward-recipient
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  b
    %-  forge
    :*  ~palnet-sampel  (sy ~[~marbud-marbud])  'fwd'  'two'
        ~2026.1.2  `(id:urmail unsigned.a)
    ==
  %+  expect-eq
    !>  (sy ~[~sampel-palnet ~palnet-sampel ~marbud-marbud])
    !>  (participants:urmail ~[a b])
--

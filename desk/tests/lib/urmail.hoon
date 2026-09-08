/-  sur=urmail
/+  *test, urmail
::  the chain mark is built here as a library so its JSON arms are covered
::  by the same suite as everything else. Same pattern as app/lens.hoon in
::  %base, which builds /mar/lens/command this way to reach its +grab.
::
/=  chain-mark  /mar/urmail/chain
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
::  a tampered life looks up a [ship life] pair we hold no key for. That is
::  indistinguishable, from the verifier's side, from an honest ship whose
::  life-7 key we simply never fetched - so this is %unverified, not
::  %forged. Accusing a ship of forgery on a key we never had would be
::  exactly the false-accusation failure the verdict scheme exists to avoid.
++  test-tampered-life-is-unverified
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'real' ~2026.1.1 ~)
  =/  bad=msg:sur  a(life.unsigned 7)
  =/  keys  (all-keys ~[~sampel-palnet])
  %+  expect-eq
    !>  ~[%unverified]
    !>  (turn (verify-chain:urmail keys ~[bad]) |=([* v=verdict:sur] v))
::
::  no key available means %unverified, never %forged. Moons land here.
++  test-missing-key-is-unverified
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'real' ~2026.1.1 ~)
  %+  expect-eq
    !>  ~[%unverified]
    !>  (turn (verify-chain:urmail (malt ~[[[~sampel-palnet 1] ~]]) ~[a]) |=([* v=verdict:sur] v))
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
::
::  a forged copy must not shadow the genuine message. Same id, different
::  signature: both survive the merge so +verify-chain can label them.
++  test-merge-keeps-both-copies-on-sig-collision
  =/  a    (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  bad  a(sig 0x0)
  %+  expect-eq
    !>  2
    !>  (lent (merge:urmail ~[bad] ~[a]))
::
::  a peer-supplied chain that repeats a message must not produce a chain
::  with duplicates. `old` is empty here: this is the first-contact case.
++  test-merge-dedupes-within-new
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  %+  expect-eq  !>(~[a])  !>((merge:urmail ~ ~[a a]))
::
::  the true third-party case: ~marbud holds the forwarder's key but not the
::  original author's, so one chain yields two different verdicts. Catches a
::  whole-chain single-verdict bug and an off-by-one in the per-message lookup.
++  test-mixed-verdicts-per-message
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'from sampel' ~2026.1.1 ~)
  =/  b
    %-  forge
    :*  ~palnet-sampel  (sy ~[~marbud-marbud])  'fwd: hi'  'see below'
        ~2026.1.2  `(id:urmail unsigned.a)
    ==
  =/  keys  (all-keys ~[~palnet-sampel])
  %+  expect-eq
    !>  ~[%unverified %verified]
    !>  (turn (verify-chain:urmail keys ~[a b]) |=([* v=verdict:sur] v))
::
::  the positive rotation case: a message signed under life 2 verifies when
::  the map carries that ship's key at life 2. Without this, a lookup that
::  hardcoded life 1 would pass every other test in the suite.
++  test-verifies-under-rotated-life
  =/  who  ~sampel-palnet
  =/  u=unsigned:sur
    [who 2 (sy ~[~palnet-sampel]) 'subj' 'body' ~2026.1.1 ~]
  =/  m=msg:sur
    [u (sign-with:urmail (fake-ring:urmail who) (digest:urmail u))]
  =/  keys  (malt ~[[[who 2] `(fake-pass:urmail who)]])
  %+  expect-eq
    !>  ~[%verified]
    !>  (turn (verify-chain:urmail keys ~[m]) |=([* v=verdict:sur] v))
::
::  the verdict's key names one specific signed copy. Two copies sharing an
::  id but differing in signature must get separate, correctly-paired
::  verdicts - if they collapsed, a forged copy could mask a genuine one.
++  test-verdict-keyed-on-id-and-sig
  =/  a    (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  bad  a(sig 0x0)
  =/  keys  (all-keys ~[~sampel-palnet])
  %+  expect-eq
    !>  ~[[[(id:urmail unsigned.a) sig.a] %verified] [[(id:urmail unsigned.a) 0x0] %forged]]
    !>  (verify-chain:urmail keys ~[a bad])
::
::  +prune sheds the excess instead of rejecting. Five copies of one id
::  against max-copies=4 must produce a four-message chain, not a crash and
::  not the whole five - rejecting here is the censorship primitive the
::  design's trust-boundary section forbids.
++  test-prune-sheds-excess-rather-than-rejecting
  =/  a   (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  cs  ~[a(sig 0x1) a(sig 0x2) a(sig 0x3) a(sig 0x4) a]
  =/  vs  (malt (verify-chain:urmail (all-keys ~[~sampel-palnet]) cs))
  %+  expect-eq  !>(4)  !>((lent (prune:urmail cs vs 4)))
::
::  a %verified copy is never shed, however many forged copies crowd it and
::  whatever order they arrive in. Both orders, same reason as above.
++  test-prune-never-sheds-a-verified
  =/  a    (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  cs   ~[a(sig 0x1) a(sig 0x2) a(sig 0x3) a(sig 0x4) a]
  =/  cs2  ~[a a(sig 0x1) a(sig 0x2) a(sig 0x3) a(sig 0x4)]
  =/  vs   (malt (verify-chain:urmail (all-keys ~[~sampel-palnet]) cs))
  ;:  weld
    (expect-eq !>(~[a]) !>((prune:urmail cs vs 1)))
    (expect-eq !>(~[a]) !>((prune:urmail cs2 vs 1)))
  ==
::
::  the fill bucket ranks %unverified above %forged. This is not a nicety:
::  every moon and comet message is %unverified in v1, so an unranked fill
::  lets four junk-signature copies evict the one genuine copy of a moon's
::  message and leave the user holding only forged copies of something that
::  was never forged.
::
::  Asserted in BOTH input orders on purpose. +prune groups copies with
::  +add:ja, which PREPENDS, so a group comes out in the reverse of the
::  chain order it was built from - an unranked fill therefore keeps
::  whichever copy was written last, and a single-order fixture passes the
::  broken code half the time by luck. Verified: reverting the fill to the
::  old (skip ms verified) form fails this test.
++  test-prune-prefers-unverified-over-forged
  =/  a   (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  i   (id:urmail unsigned.a)
  =/  vs=(map [msg-id:sur @ux] verdict:sur)
    %-  malt
    ^-  (list [[msg-id:sur @ux] verdict:sur])
    :~  [[i 0x2] %forged]
        [[i 0x3] %forged]
        [[i 0x4] %forged]
        [[i 0x1] %unverified]
    ==
  ;:  weld
    %+  expect-eq
      !>  ~[a(sig 0x1)]
      !>  (prune:urmail ~[a(sig 0x2) a(sig 0x3) a(sig 0x4) a(sig 0x1)] vs 1)
    %+  expect-eq
      !>  ~[a(sig 0x1)]
      !>  (prune:urmail ~[a(sig 0x1) a(sig 0x2) a(sig 0x3) a(sig 0x4)] vs 1)
  ==
::
::  the whole ranking in one shot: %verified, then %unverified, then
::  %forged. With room for two, the survivors are the verified copy and the
::  unverified one, never a forged one.
++  test-prune-ranks-verified-then-unverified-then-forged
  =/  a   (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  i   (id:urmail unsigned.a)
  =/  vs=(map [msg-id:sur @ux] verdict:sur)
    %-  malt
    ^-  (list [[msg-id:sur @ux] verdict:sur])
    :~  [[i 0x2] %forged]
        [[i 0x3] %forged]
        [[i 0x4] %forged]
        [[i 0x1] %unverified]
        [[i sig.a] %verified]
    ==
  ::  both input orders, for the +add:ja reversal reason given above
  =/  one  (prune:urmail ~[a(sig 0x2) a(sig 0x3) a(sig 0x4) a(sig 0x1) a] vs 2)
  =/  two  (prune:urmail ~[a a(sig 0x1) a(sig 0x2) a(sig 0x3) a(sig 0x4)] vs 2)
  ;:  weld
    (expect-eq !>(2) !>((lent one)))
    (expect !>((lien one |=(m=msg:sur =(sig.m sig.a)))))
    (expect !>((lien one |=(m=msg:sur =(sig.m 0x1)))))
    (expect-eq !>(2) !>((lent two)))
    (expect !>((lien two |=(m=msg:sur =(sig.m sig.a)))))
    (expect !>((lien two |=(m=msg:sur =(sig.m 0x1)))))
  ==
::
::  a thread's identity comes from CONTENT, never from the order of the
::  list a poke happened to arrive in. An attacker controls that order, so
::  reading the head-as-supplied would let one poke mint a duplicate of an
::  existing conversation under a fresh id. The root here is deliberately
::  last in the list.
++  test-thread-key-from-content-not-list-order
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  b
    %-  forge
    :*  ~palnet-sampel  (sy ~[~sampel-palnet])  're: hi'  'two'
        ~2026.1.2  `(id:urmail unsigned.a)
    ==
  %+  expect-eq
    !>  (id:urmail unsigned.a)
    !>  (thread-key:urmail ~ ~[b a])
::
::  nor from `sent`, which is a signed field the sender chooses freely. A
::  reply backdated before the root must still resolve to the root.
++  test-thread-key-ignores-sent
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.9.1 ~)
  =/  b
    %-  forge
    :*  ~palnet-sampel  (sy ~[~sampel-palnet])  're: hi'  'backdated'
        ~2020.1.1  `(id:urmail unsigned.a)
    ==
  %+  expect-eq
    !>  (id:urmail unsigned.a)
    !>  (thread-key:urmail ~ ~[b a])
::
::  once a thread exists, its id is immutable. A poke that carries one
::  message we already hold plus a brand-new prev=~ message - the shape
::  that would otherwise migrate an established conversation onto an
::  attacker-chosen id - files into the thread we already have.
++  test-thread-key-established-thread-is-immutable
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  evil
    (forge ~palnet-sampel (sy ~[~sampel-palnet]) 'hi' 'new root' ~2020.1.1 ~)
  =/  tid  (id:urmail unsigned.a)
  =/  stored=(map thread-id:sur thread:sur)
    (malt ~[[tid `thread:sur`[~[a] (participants:urmail ~[a]) ~2026.1.1]]])
  ;:  weld
    (expect-eq !>(tid) !>((thread-key:urmail stored ~[evil a])))
    (expect-eq !>(tid) !>((thread-key:urmail stored ~[a evil])))
    ::  and the new root does NOT become the id
    (expect !>(!=((id:urmail unsigned.evil) (thread-key:urmail stored ~[evil a]))))
  ==
::
::  a forged copy of the root carries the same prev=~ and the same id as
::  the genuine one, because prev is part of the signed payload they
::  share. First contact with both copies must still resolve, not crash on
::  "no unique root" - rejecting there would deny the very chain the
::  anti-shadowing design exists to accept.
++  test-thread-key-tolerates-a-shadowed-root
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  %+  expect-eq
    !>  (id:urmail unsigned.a)
    !>  (thread-key:urmail ~ ~[a a(sig 0x0)])
::
::  +freeze: a definitive verdict is never overwritten. %verified and
::  %forged are both definitive for a fixed [id sig] - digest and key are
::  both fixed - so a later poke claiming otherwise is either noise or an
::  attack, and either way must not win.
++  test-freeze-keeps-a-definitive-verdict
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  k  [(id:urmail unsigned.a) sig.a]
  =/  old=(map [msg-id:sur @ux] verdict:sur)  (malt ~[[k `verdict:sur`%verified]])
  ;:  weld
    %+  expect-eq  !>(`verdict:sur`%verified)
      !>  (~(got by (freeze:urmail old ~[[k %unverified]])) k)
    %+  expect-eq  !>(`verdict:sur`%verified)
      !>  (~(got by (freeze:urmail old ~[[k %forged]])) k)
  ==
::
::  but %unverified is not a finding about the signature - only that the
::  key was absent from our snapshot at that instant - so a later poke
::  arriving after we have fetched the key must be able to upgrade it.
++  test-freeze-upgrades-an-unverified
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  k  [(id:urmail unsigned.a) sig.a]
  =/  old=(map [msg-id:sur @ux] verdict:sur)  (malt ~[[k `verdict:sur`%unverified]])
  ;:  weld
    %+  expect-eq  !>(`verdict:sur`%verified)
      !>  (~(got by (freeze:urmail old ~[[k %verified]])) k)
    %+  expect-eq  !>(`verdict:sur`%forged)
      !>  (~(got by (freeze:urmail old ~[[k %forged]])) k)
  ==
::
::  the input caps reject rather than truncate: a chain that violates one
::  is not partially trustworthy. Each is a whole-chain predicate, so one
::  bad message condemns the poke.
++  test-input-caps-reject-on-any-message
  =/  ok    (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  big   ok(body.unsigned (crip (reap 200 'x')))
  =/  loud  ok(subj.unsigned (crip (reap 200 'x')))
  =/  many  ok(to.unsigned (sy ~[~sampel-palnet ~palnet-sampel ~marbud-marbud]))
  ;:  weld
    (expect !>((fits-length:urmail ~[ok ok] 2)))
    (expect !>(!(fits-length:urmail ~[ok ok] 1)))
    (expect !>((fits-bodies:urmail ~[ok] 100)))
    (expect !>(!(fits-bodies:urmail ~[ok big] 100)))
    (expect !>((fits-subjects:urmail ~[ok] 100)))
    (expect !>(!(fits-subjects:urmail ~[ok loud] 100)))
    (expect !>((fits-recipients:urmail ~[ok] 2)))
    (expect !>(!(fits-recipients:urmail ~[ok many] 2)))
  ==
::
::  the state-capacity bound counts distinct message ids, not messages:
::  +merge deliberately keeps several signed copies of one id, and a user
::  can only read one of them. Counting copies would let four junk
::  signatures consume four slots of a thread's budget.
++  test-distinct-ids-counts-ids-not-copies
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  b
    %-  forge
    :*  ~palnet-sampel  (sy ~[~sampel-palnet])  're: hi'  'two'
        ~2026.1.2  `(id:urmail unsigned.a)
    ==
  %+  expect-eq
    !>  2
    !>  (distinct-ids:urmail ~[a a(sig 0x1) a(sig 0x2) b])
::
::  ---------------------------------------------------------------------
::  the chain mark's JSON form
::
::  "The JSON forms exist so the web UI can read chains without a second
::  representation" - and that only holds if the JSON form is the SAME
::  representation, losslessly. A chain's entire value is that any holder
::  can re-derive its ids and re-check its signatures, so a JSON encoding
::  that rounds, drops or summarises a signed field is not a rendering of
::  the chain, it is a different and unverifiable object.
::  ---------------------------------------------------------------------
::
::  +grow then +grab returns the identical noun, including `life` and
::  `sig` - the two fields a "readable" encoding is most tempted to drop,
::  and the two without which nothing can be verified.
++  test-mark-json-round-trips-a-chain
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  b
    %-  forge
    :*  ~palnet-sampel  (sy ~[~marbud-marbud])  'fwd: hi'  'see below'
        ~2026.1.2  `(id:urmail unsigned.a)
    ==
  =/  c=chain:sur  ~[a b]
  %+  expect-eq
    !>  c
    !>  (json:grab:chain-mark json:grow:~(. chain-mark c))
::
::  the case the millisecond timestamp encoder used elsewhere in this desk
::  gets wrong. `sent` is one of the seven fields (sham unsigned) covers,
::  and on a real send it is `now.bowl`, which carries sub-millisecond
::  bits. Rounding it changes every id and flips every verdict to %forged
::  - silently, and only for chains that came through JSON. A fixture
::  whose `sent` is not a whole millisecond is the only thing that catches
::  it, so the round trip is asserted here AND re-verified afterwards.
++  test-mark-json-keeps-sub-millisecond-sent
  =/  a
    %-  forge
    :*  ~sampel-palnet  (sy ~[~palnet-sampel])  'hi'  'one'
        ~2026.1.1..00.00.00..0001  ~
    ==
  =/  c=chain:sur  ~[a]
  =/  back=chain:sur  (json:grab:chain-mark json:grow:~(. chain-mark c))
  ;:  weld
    (expect-eq !>(c) !>(back))
    %+  expect-eq
      !>  ~[%verified]
      !>  %+  turn  (verify-chain:urmail (all-keys ~[~sampel-palnet]) back)
          |=([* v=verdict:sur] v)
  ==
::
::  a chain that has been through JSON is still a chain a stranger can
::  verify: round-trip the marquee forward case and re-check every
::  signature on the far side. This is the mark arms and the design's
::  headline claim in one assertion.
++  test-mark-json-preserves-third-party-verifiability
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'from sampel' ~2026.1.1 ~)
  =/  b
    %-  forge
    :*  ~palnet-sampel  (sy ~[~marbud-marbud])  'fwd: hi'  'see below'
        ~2026.1.2  `(id:urmail unsigned.a)
    ==
  =/  back=chain:sur
    (json:grab:chain-mark json:grow:~(. chain-mark `chain:sur`~[a b]))
  =/  keys  (all-keys ~[~sampel-palnet ~palnet-sampel])
  %+  expect-eq
    !>  ~[%verified %verified]
    !>  (turn (verify-chain:urmail keys back) |=([* v=verdict:sur] v))
::
::  ---------------------------------------------------------------------
::  SPEC TEST 6: "a chain arriving from a non-participant ship is accepted
::  and verifies". One of the three claims the design says a chat app
::  cannot make.
::
::  The `verifies` half is the marquee test above. These three cover the
::  `accepted` half as far as pure code can: the chain below names neither
::  the ship holding it (~marbud-marbud) nor the ship that couriered it
::  (~wicdev-wisryt), and every arm +receive puts it through takes it
::  unchanged. Nothing in lib/urmail.hoon has a courier argument to check,
::  which is the point.
::
::  What is NOT covered here, and why: that `on-poke` really does omit the
::  `?>  =(our.bowl src.bowl)` gate on %urmail-chain that it applies to
::  %urmail-action. That is a property of the agent core, needs a bowl,
::  and `lib/test-agent.hoon` does not compile at [%zuse 408] - see
::  docs/verification.md, "The headline gap". It is backed by live dojo
::  evidence only. Do not read the tests below as covering it.
::  ---------------------------------------------------------------------
::
::  every message verifies although the holder is in neither `from` nor
::  `to` of any of them. The signatures are the authority, not the courier.
++  test-non-participant-chain-verifies
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  b
    %-  forge
    :*  ~palnet-sampel  (sy ~[~sampel-palnet])  're: hi'  'two'
        ~2026.1.2  `(id:urmail unsigned.a)
    ==
  =/  c=chain:sur  ~[a b]
  =/  keys  (all-keys ~[~sampel-palnet ~palnet-sampel])
  ;:  weld
    (expect !>(!(~(has in (participants:urmail c)) ~marbud-marbud)))
    (expect !>(!(~(has in (participants:urmail c)) ~wicdev-wisryt)))
    %+  expect-eq
      !>  ~[%verified %verified]
      !>  (turn (verify-chain:urmail keys c) |=([* v=verdict:sur] v))
  ==
::
::  and it files under the id every holder of the conversation computes -
::  the root's content hash - with nothing about the courier in it. First
::  contact anchors on the prev=~ message; a later delivery of the same
::  chain by a different courier resolves to the same id, which is what
::  makes double delivery a no-op instead of a duplicate conversation.
++  test-non-participant-chain-files-under-the-root-id
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  b
    %-  forge
    :*  ~palnet-sampel  (sy ~[~sampel-palnet])  're: hi'  'two'
        ~2026.1.2  `(id:urmail unsigned.a)
    ==
  =/  c=chain:sur  ~[a b]
  =/  tid  (id:urmail unsigned.a)
  =/  stored=(map thread-id:sur thread:sur)
    (malt ~[[tid `thread:sur`[c (participants:urmail c) ~2026.1.2]]])
  ;:  weld
    (expect-eq !>(tid) !>((thread-key:urmail ~ c)))
    (expect-eq !>(tid) !>((thread-key:urmail stored c)))
  ==
::
::  and it survives the rest of +receive's pipeline intact: the input caps
::  accept it, it merges whole into empty state, and +prune sheds nothing.
::  Each of these is a pure function of the chain alone - there is no
::  courier to consult - so a stranger's chain is stored exactly as a
::  participant's would be.
++  test-non-participant-chain-survives-the-receive-pipeline
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  b
    %-  forge
    :*  ~palnet-sampel  (sy ~[~sampel-palnet])  're: hi'  'two'
        ~2026.1.2  `(id:urmail unsigned.a)
    ==
  =/  c=chain:sur  ~[a b]
  =/  merged  (merge:urmail ~ c)
  =/  vs  (malt (verify-chain:urmail (all-keys ~[~sampel-palnet ~palnet-sampel]) merged))
  ;:  weld
    (expect !>((fits-length:urmail c 1.000)))
    (expect !>((fits-bodies:urmail c 100.000)))
    (expect !>((fits-subjects:urmail c 1.000)))
    (expect !>((fits-recipients:urmail c 100)))
    (expect-eq !>(c) !>(merged))
    (expect-eq !>(2) !>((distinct-ids:urmail merged)))
    (expect-eq !>(c) !>((prune:urmail merged vs 4)))
  ==
--

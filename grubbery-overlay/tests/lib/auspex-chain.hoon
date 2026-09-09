::  Unit tests for /lib/auspex-chain. Ported verbatim from the %urmail
::  desk's tests/lib/urmail.hoon - the app was called urmail until
::  2026-09-09 - and only the imports and the face names differ.
::
::    The desk split types (/sur/urmail) from arms (/lib/urmail) and this
::    file named them `sur` and `urmail`; the faces are `sur` and
::    `auspex` here. The overlay has no sur/, so both faces are bound to
::    the one lib. Two faces on one file keeps every assertion below
::    structurally identical to the reviewed original, which is the
::    point of a port.
::
/+  *test, auspex=auspex-chain, sur=auspex-chain
|%
::  +forge: build a genuinely signed message as any ship, using the fake-ship
::  key derivation. This is what lets the third-party forward case be tested
::  with no network and no second ship.
++  forge
  |=  [who=ship to=(set ship) subj=@t body=@t sent=@da prev=(unit msg-id:sur)]
  ^-  msg:sur
  (forge-with who to subj body sent prev ~)
::
::  +forge-with: the same, carrying attachments. Kept separate so every
::  assertion ported from the pre-attachment suite stays byte-identical.
++  forge-with
  |=  $:  who=ship
          to=(set ship)
          subj=@t
          body=@t
          sent=@da
          prev=(unit msg-id:sur)
          as=(list attachment:sur)
      ==
  ^-  msg:sur
  =/  u=unsigned:sur  [who 1 to subj body '' sent prev as]
  [u (sign-with:auspex (fake-ring:auspex who) (digest:auspex u))]
::
::  +fake-from: a message SIGNED BY ONE SHIP AND CLAIMING TO BE ANOTHER.
::
::    A genuine signature over a lying `from` - which is exactly what a
::    forgery is, and what makes it verifiable AS a forgery: the key
::    looked up is the claimed sender's, the signature was made with
::    somebody else's, and the check fails. On a fake ship every ship's
::    keypair derives from its @p, so this needs no network and no
::    second ship.
::
++  fake-from
  |=  [signer=ship claim=ship subj=@t body=@t sent=@da]
  ^-  msg:sur
  =/  u=unsigned:sur  [claim 1 (sy ~[~palnet-sampel]) subj body '' sent ~ ~]
  [u (sign-with:auspex (fake-ring:auspex signer) (digest:auspex u))]
::
::  +forge hardcodes life 1, so the map is keyed on [w 1] for every ship
::  passed in.
++  all-keys
  |=  who=(list ship)
  ^-  (map [ship @ud] (unit pass))
  %-  malt
  %+  turn  who
  |=(w=ship [[w 1] `(fake-pass:auspex w)])
::
::  a signature made with a ship's key verifies against that ship's key
++  test-sign-verify-roundtrip
  =/  who   ~sampel-palnet
  =/  msg   (shaf %auspex (sham [%hello 'world']))
  =/  sig   (sign-with:auspex (fake-ring:auspex who) msg)
  (expect !>((verify-with:auspex (fake-pass:auspex who) sig msg)))
::
::  a signature does not verify against a different ship's key
++  test-sign-wrong-key-fails
  =/  msg   (shaf %auspex (sham [%hello 'world']))
  =/  sig   (sign-with:auspex (fake-ring:auspex ~sampel-palnet) msg)
  (expect !>(!(verify-with:auspex (fake-pass:auspex ~palnet-sampel) sig msg)))
::
::  a signature does not verify against a different message
++  test-sign-wrong-message-fails
  =/  who   ~sampel-palnet
  =/  sig   (sign-with:auspex (fake-ring:auspex who) (shaf %auspex (sham 'a')))
  (expect !>(!(verify-with:auspex (fake-pass:auspex who) sig (shaf %auspex (sham 'b')))))
::
::  +digest is what every later task signs and verifies over, so it is
::  tested directly rather than reimplemented by its callers.
++  test-digest-is-salted-sham
  =/  u=unsigned:sur
    [~sampel-palnet 1 (sy ~[~palnet-sampel]) 'subj' 'body' '' ~2026.1.1 ~ ~]
  %+  expect-eq
    !>  (shaf %auspex (sham u))
    !>  (digest:auspex u)
::
::  domain separation: the salted digest must differ from the unsalted hash
::  and from the same message salted for another protocol. This is the
::  property that stops an auspex signature being replayed as an ames one,
::  and it is mandatory per the spec.
++  test-digest-domain-separated
  =/  u=unsigned:sur
    [~sampel-palnet 1 (sy ~[~palnet-sampel]) 'subj' 'body' '' ~2026.1.1 ~ ~]
  ;:  weld
    (expect !>(!=((digest:auspex u) (sham u))))
    (expect !>(!=((digest:auspex u) (shaf %ames (sham u)))))
  ==
::
::  a msg-id is a hash over every signed field, so changing any field
::  changes the id. This is what lets two ships agree on a thread id
::  without coordinating.
++  test-msg-id-covers-every-field
  =/  base=unsigned:sur
    [~sampel-palnet 1 (sy ~[~palnet-sampel]) 'subj' 'body' '' ~2026.1.1 ~ ~]
  =/  d  (digest:auspex base)
  ;:  weld
    (expect !>(!=(d (digest:auspex base(body 'other')))))
    (expect !>(!=(d (digest:auspex base(subj 'other')))))
    (expect !>(!=(d (digest:auspex base(life 2)))))
    (expect !>(!=(d (digest:auspex base(from ~palnet-sampel)))))
    (expect !>(!=(d (digest:auspex base(sent ~2026.1.2)))))
    (expect !>(!=(d (digest:auspex base(to (sy ~[~sampel-palnet]))))))
    (expect !>(!=(d (digest:auspex base(prev `0v1)))))
    ::  attachments are inside `unsigned`, so the id covers them too and
    ::  swapping a file cannot leave the signature standing.
    (expect !>(!=(d (digest:auspex base(attachments ~[['f' 3 'text/plain' 0v2]])))))
    ::  the rendering instruction is part of the message: "render me as
    ::  HTML" and "render me as plain text" are different messages, and
    ::  an intermediary must not be able to switch which one is read.
    (expect !>(!=(d (digest:auspex base(body-mime 'text/html')))))
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
        ~2026.1.2  `(id:auspex unsigned.a)
    ==
  =/  keys  (all-keys ~[~sampel-palnet ~palnet-sampel])
  %+  expect-eq
    !>  ~[%verified %verified]
    !>  (turn (verify-chain:auspex keys ~[a b]) |=([* v=verdict:sur] v))
::
::  a tampered body flips the verdict to %forged, not %unverified
++  test-tampered-body-is-forged
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'real' ~2026.1.1 ~)
  =/  bad=msg:sur  a(body.unsigned 'tampered')
  =/  keys  (all-keys ~[~sampel-palnet])
  %+  expect-eq
    !>  ~[%forged]
    !>  (turn (verify-chain:auspex keys ~[bad]) |=([* v=verdict:sur] v))
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
    !>  (turn (verify-chain:auspex keys ~[bad]) |=([* v=verdict:sur] v))
::
::  no key available means %unverified, never %forged. Moons land here.
++  test-missing-key-is-unverified
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'real' ~2026.1.1 ~)
  %+  expect-eq
    !>  ~[%unverified]
    !>  (turn (verify-chain:auspex (malt ~[[[~sampel-palnet 1] ~]]) ~[a]) |=([* v=verdict:sur] v))
::
::  merging the same chain twice is a no-op: double delivery must not
::  duplicate messages
++  test-merge-dedupes
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  b
    %-  forge
    :*  ~palnet-sampel  (sy ~[~sampel-palnet])  're: hi'  'two'
        ~2026.1.2  `(id:auspex unsigned.a)
    ==
  %+  expect-eq
    !>  ~[a b]
    !>  (merge:auspex ~[a b] ~[a b])
::
::  merge keeps messages in sent order regardless of arrival order
++  test-merge-orders-by-sent
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  b
    %-  forge
    :*  ~palnet-sampel  (sy ~[~sampel-palnet])  're: hi'  'two'
        ~2026.1.2  `(id:auspex unsigned.a)
    ==
  %+  expect-eq
    !>  ~[a b]
    !>  (merge:auspex ~[b] ~[a])
::
::  the root of a chain is the id of its first message, and every ship
::  computes the same one because the root message is byte-identical
++  test-root-is-first-message-id
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  b
    %-  forge
    :*  ~palnet-sampel  (sy ~[~sampel-palnet])  're: hi'  'two'
        ~2026.1.2  `(id:auspex unsigned.a)
    ==
  %+  expect-eq
    !>  (id:auspex unsigned.a)
    !>  (root:auspex ~[a b])
::
::  participants is the union of from and to across the whole chain, so a
::  ship added by a forward is a participant
++  test-participants-includes-forward-recipient
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  b
    %-  forge
    :*  ~palnet-sampel  (sy ~[~marbud-marbud])  'fwd'  'two'
        ~2026.1.2  `(id:auspex unsigned.a)
    ==
  %+  expect-eq
    !>  (sy ~[~sampel-palnet ~palnet-sampel ~marbud-marbud])
    !>  (participants:auspex ~[a b])
::
::  a forged copy must not shadow the genuine message. Same id, different
::  signature: both survive the merge so +verify-chain can label them.
++  test-merge-keeps-both-copies-on-sig-collision
  =/  a    (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  bad  a(sig 0x0)
  %+  expect-eq
    !>  2
    !>  (lent (merge:auspex ~[bad] ~[a]))
::
::  a peer-supplied chain that repeats a message must not produce a chain
::  with duplicates. `old` is empty here: this is the first-contact case.
++  test-merge-dedupes-within-new
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  %+  expect-eq  !>(~[a])  !>((merge:auspex ~ ~[a a]))
::
::  the true third-party case: ~marbud holds the forwarder's key but not the
::  original author's, so one chain yields two different verdicts. Catches a
::  whole-chain single-verdict bug and an off-by-one in the per-message lookup.
++  test-mixed-verdicts-per-message
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'from sampel' ~2026.1.1 ~)
  =/  b
    %-  forge
    :*  ~palnet-sampel  (sy ~[~marbud-marbud])  'fwd: hi'  'see below'
        ~2026.1.2  `(id:auspex unsigned.a)
    ==
  =/  keys  (all-keys ~[~palnet-sampel])
  %+  expect-eq
    !>  ~[%unverified %verified]
    !>  (turn (verify-chain:auspex keys ~[a b]) |=([* v=verdict:sur] v))
::
::  the positive rotation case: a message signed under life 2 verifies when
::  the map carries that ship's key at life 2. Without this, a lookup that
::  hardcoded life 1 would pass every other test in the suite.
++  test-verifies-under-rotated-life
  =/  who  ~sampel-palnet
  =/  u=unsigned:sur
    [who 2 (sy ~[~palnet-sampel]) 'subj' 'body' '' ~2026.1.1 ~ ~]
  =/  m=msg:sur
    [u (sign-with:auspex (fake-ring:auspex who) (digest:auspex u))]
  =/  keys  (malt ~[[[who 2] `(fake-pass:auspex who)]])
  %+  expect-eq
    !>  ~[%verified]
    !>  (turn (verify-chain:auspex keys ~[m]) |=([* v=verdict:sur] v))
::
::  the verdict's key names one specific signed copy. Two copies sharing an
::  id but differing in signature must get separate, correctly-paired
::  verdicts - if they collapsed, a forged copy could mask a genuine one.
++  test-verdict-keyed-on-id-and-sig
  =/  a    (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  bad  a(sig 0x0)
  =/  keys  (all-keys ~[~sampel-palnet])
  %+  expect-eq
    !>  ~[[[(id:auspex unsigned.a) sig.a] %verified] [[(id:auspex unsigned.a) 0x0] %forged]]
    !>  (verify-chain:auspex keys ~[a bad])
::
::  +prune sheds the excess instead of rejecting. Five copies of one id
::  against max-copies=4 must produce a four-message chain, not a crash and
::  not the whole five - rejecting here is the censorship primitive the
::  design's trust-boundary section forbids.
++  test-prune-sheds-excess-rather-than-rejecting
  =/  a   (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  cs  ~[a(sig 0x1) a(sig 0x2) a(sig 0x3) a(sig 0x4) a]
  =/  vs  (malt (verify-chain:auspex (all-keys ~[~sampel-palnet]) cs))
  %+  expect-eq  !>(4)  !>((lent (prune:auspex cs vs 4)))
::
::  a %verified copy is never shed, however many forged copies crowd it and
::  whatever order they arrive in. Both orders, same reason as above.
++  test-prune-never-sheds-a-verified
  =/  a    (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  cs   ~[a(sig 0x1) a(sig 0x2) a(sig 0x3) a(sig 0x4) a]
  =/  cs2  ~[a a(sig 0x1) a(sig 0x2) a(sig 0x3) a(sig 0x4)]
  =/  vs   (malt (verify-chain:auspex (all-keys ~[~sampel-palnet]) cs))
  ;:  weld
    (expect-eq !>(~[a]) !>((prune:auspex cs vs 1)))
    (expect-eq !>(~[a]) !>((prune:auspex cs2 vs 1)))
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
  =/  i   (id:auspex unsigned.a)
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
      !>  (prune:auspex ~[a(sig 0x2) a(sig 0x3) a(sig 0x4) a(sig 0x1)] vs 1)
    %+  expect-eq
      !>  ~[a(sig 0x1)]
      !>  (prune:auspex ~[a(sig 0x1) a(sig 0x2) a(sig 0x3) a(sig 0x4)] vs 1)
  ==
::
::  the whole ranking in one shot: %verified, then %unverified, then
::  %forged. With room for two, the survivors are the verified copy and the
::  unverified one, never a forged one.
++  test-prune-ranks-verified-then-unverified-then-forged
  =/  a   (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  i   (id:auspex unsigned.a)
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
  =/  one  (prune:auspex ~[a(sig 0x2) a(sig 0x3) a(sig 0x4) a(sig 0x1) a] vs 2)
  =/  two  (prune:auspex ~[a a(sig 0x1) a(sig 0x2) a(sig 0x3) a(sig 0x4)] vs 2)
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
        ~2026.1.2  `(id:auspex unsigned.a)
    ==
  %+  expect-eq
    !>  (id:auspex unsigned.a)
    !>  (thread-key:auspex ~ ~[b a])
::
::  nor from `sent`, which is a signed field the sender chooses freely. A
::  reply backdated before the root must still resolve to the root.
++  test-thread-key-ignores-sent
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.9.1 ~)
  =/  b
    %-  forge
    :*  ~palnet-sampel  (sy ~[~sampel-palnet])  're: hi'  'backdated'
        ~2020.1.1  `(id:auspex unsigned.a)
    ==
  %+  expect-eq
    !>  (id:auspex unsigned.a)
    !>  (thread-key:auspex ~ ~[b a])
::
::  once a thread exists, its id is immutable. A poke that carries one
::  message we already hold plus a brand-new prev=~ message - the shape
::  that would otherwise migrate an established conversation onto an
::  attacker-chosen id - files into the thread we already have.
++  test-thread-key-established-thread-is-immutable
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  evil
    (forge ~palnet-sampel (sy ~[~sampel-palnet]) 'hi' 'new root' ~2020.1.1 ~)
  =/  tid  (id:auspex unsigned.a)
  =/  stored=(map thread-id:sur thread:sur)
    (malt ~[[tid `thread:sur`[~[a] (participants:auspex ~[a]) ~2026.1.1]]])
  ;:  weld
    (expect-eq !>(tid) !>((thread-key:auspex stored ~[evil a])))
    (expect-eq !>(tid) !>((thread-key:auspex stored ~[a evil])))
    ::  and the new root does NOT become the id
    (expect !>(!=((id:auspex unsigned.evil) (thread-key:auspex stored ~[evil a]))))
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
    !>  (id:auspex unsigned.a)
    !>  (thread-key:auspex ~ ~[a a(sig 0x0)])
::
::  +freeze: a definitive verdict is never overwritten. %verified and
::  %forged are both definitive for a fixed [id sig] - digest and key are
::  both fixed - so a later poke claiming otherwise is either noise or an
::  attack, and either way must not win.
++  test-freeze-keeps-a-definitive-verdict
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  k  [(id:auspex unsigned.a) sig.a]
  =/  old=(map [msg-id:sur @ux] verdict:sur)  (malt ~[[k `verdict:sur`%verified]])
  ;:  weld
    %+  expect-eq  !>(`verdict:sur`%verified)
      !>  (~(got by (freeze:auspex old ~[[k %unverified]])) k)
    %+  expect-eq  !>(`verdict:sur`%verified)
      !>  (~(got by (freeze:auspex old ~[[k %forged]])) k)
  ==
::
::  but %unverified is not a finding about the signature - only that the
::  key was absent from our snapshot at that instant - so a later poke
::  arriving after we have fetched the key must be able to upgrade it.
++  test-freeze-upgrades-an-unverified
  =/  a  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  k  [(id:auspex unsigned.a) sig.a]
  =/  old=(map [msg-id:sur @ux] verdict:sur)  (malt ~[[k `verdict:sur`%unverified]])
  ;:  weld
    %+  expect-eq  !>(`verdict:sur`%verified)
      !>  (~(got by (freeze:auspex old ~[[k %verified]])) k)
    %+  expect-eq  !>(`verdict:sur`%forged)
      !>  (~(got by (freeze:auspex old ~[[k %forged]])) k)
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
    (expect !>((fits-length:auspex ~[ok ok] 2)))
    (expect !>(!(fits-length:auspex ~[ok ok] 1)))
    (expect !>((fits-bodies:auspex ~[ok] 100)))
    (expect !>(!(fits-bodies:auspex ~[ok big] 100)))
    (expect !>((fits-subjects:auspex ~[ok] 100)))
    (expect !>(!(fits-subjects:auspex ~[ok loud] 100)))
    (expect !>((fits-recipients:auspex ~[ok] 2)))
    (expect !>(!(fits-recipients:auspex ~[ok many] 2)))
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
        ~2026.1.2  `(id:auspex unsigned.a)
    ==
  %+  expect-eq
    !>  2
    !>  (distinct-ids:auspex ~[a a(sig 0x1) a(sig 0x2) b])

::  ── attachments ──────────────────────────────────────────────────────
::
::  the content address covers the LENGTH as well as the atom. Hashing the
::  bare atom would give two files that differ only in leading zero bytes
::  one address, and would let a lie about `size` pass unnoticed.
++  test-blob-hash-covers-length
  =/  a=octs  [3 'abc']
  =/  b=octs  [4 'abc']
  ;:  weld
    (expect !>(=((blob-hash:auspex a) (blob-hash:auspex [3 'abc']))))
    (expect !>(!=((blob-hash:auspex a) (blob-hash:auspex b))))
    (expect !>(!=((blob-hash:auspex a) (sham q.a))))
  ==
::
::  THE ACCEPTANCE RULE. A blob is accepted only if its bytes hash to the
::  address it was fetched under. Everything else about the courier is
::  irrelevant, and a mismatch is discarded rather than stored.
++  test-blob-ok-rejects-wrong-bytes
  =/  good=octs  [11 'hello world']
  =/  h  (blob-hash:auspex good)
  ;:  weld
    (expect !>((blob-ok:auspex good h)))
    (expect !>(!(blob-ok:auspex [11 'hello xorld'] h)))
    ::  right bytes, wrong declared length: still a different address
    (expect !>(!(blob-ok:auspex [12 'hello world'] h)))
    (expect !>(!(blob-ok:auspex good 0v0)))
  ==
::
::  +describe is what puts a file's identity inside the signature. Its
::  size and hash must agree with the bytes it was built from.
++  test-describe-matches-its-bytes
  =/  f=file:sur  ['note.txt' 'text/plain' [11 'hello world']]
  =/  a  (describe:auspex f)
  ;:  weld
    (expect-eq !>('note.txt') !>(name.a))
    (expect-eq !>(11) !>(size.a))
    (expect-eq !>('text/plain') !>(mime.a))
    (expect !>((blob-ok:auspex octs.f hash.a)))
  ==
::
::  a file whose declared length is BELOW its measured bytes is malformed:
::  the atom carries more than the octs claims, so the address computed at
::  send time would not be the address the bytes are re-measured against.
++  test-file-ok-rejects-malformed-octs
  ;:  weld
    (expect !>((file-ok:auspex ['a' 'text/plain' [11 'hello world']])))
    (expect !>((file-ok:auspex ['a' 'text/plain' [40 'hello world']])))
    (expect !>(!(file-ok:auspex ['a' 'text/plain' [3 'hello world']])))
    (expect !>(!(file-ok:auspex ['a' 'text/plain' [1.000.000 'x']])))
    (expect !>(!(file-ok:auspex [(crip (reap 300 'n')) 'text/plain' [1 'x']])))
    (expect !>(!(file-ok:auspex ['a' (crip (reap 200 'm')) [1 'x']])))
  ==
::
::  +attach-ok is +file-ok WITHOUT THE BYTES, and the send path that
::  names an already-stored blob is checked by it alone. Everything
::  +file-ok enforces except the octs measurement is enforced here, so
::  the two ways into a send cannot drift on the caps.
++  test-attach-ok-enforces-the-same-caps
  ;:  weld
    (expect !>((attach-ok:auspex ['a' 11 'text/plain' 0v1])))
    ::  size against max-blob, exactly as +file-ok checks p.octs
    (expect !>((attach-ok:auspex ['a' 262.144 'text/plain' 0v1])))
    (expect !>(!(attach-ok:auspex ['a' 262.145 'text/plain' 0v1])))
    ::  name and mime through +text-ok, same caps
    (expect !>(!(attach-ok:auspex [(crip (reap 300 'n')) 1 'text/plain' 0v1])))
    (expect !>(!(attach-ok:auspex ['a' 1 (crip (reap 200 'm')) 0v1])))
  ==
::
::  the count cap, and it is max-attach and not a number of its own.
++  test-attaches-ok-caps-the-count
  =/  one=attachment:sur  ['a' 1 'text/plain' 0v1]
  ;:  weld
    (expect !>((attaches-ok:auspex (reap 16 one))))
    (expect !>(!(attaches-ok:auspex (reap 17 one))))
    ::  and one bad member fails the list, however short it is
    (expect !>(!(attaches-ok:auspex ~[one ['a' 262.145 'text/plain' 0v1]])))
  ==
::
::  name and mime are attacker-supplied and arrive PRE-SIGNED, so a
::  recipient cannot repair one without destroying the signature. mime is
::  headed for a Content-Type header, where CR or LF is a header-injection
::  primitive; name is headed for a filename. Refused at the boundary,
::  because the boundary is the only place left.
++  test-text-ok-refuses-control-bytes
  ::  built with +cat at the byte level rather than as a tape: a literal
  ::  13 infers as @ud, and @ud does not nest into the @tD a tape wants.
  =/  cr   `@`13
  =/  lf   `@`10
  =/  del  `@`127
  =/  crlf  (cat 3 'text/plain' (cat 3 (cat 3 cr lf) 'X-Evil: yes'))
  ::  the same value arriving DELIVERED, where it is already signed and
  ::  a recipient cannot repair it without destroying the signature.
  =/  bad=msg:sur
    %-  forge-with
    :*  ~sampel-palnet  (sy ~[~palnet-sampel])  's'  'b'  ~2026.1.1  ~
        ~[['f' 3 crlf 0v1]]
    ==
  ;:  weld
    (expect !>((text-ok:auspex 'text/plain' 128)))
    (expect !>(!(text-ok:auspex crlf 128)))
    (expect !>(!(text-ok:auspex (cat 3 'a' (cat 3 lf 'b')) 128)))
    (expect !>(!(text-ok:auspex (cat 3 'a' (cat 3 cr 'b')) 128)))
    (expect !>(!(text-ok:auspex (cat 3 'a' (cat 3 del 'b')) 128)))
    (expect !>(!(fits-attachments:auspex ~[bad] 16)))
    ::  body-mime is checked exactly the same way, and for the same
    ::  reason: it is signed, so a recipient cannot repair it, and it is
    ::  headed for a render boundary.
    %-  expect  !>
    %-  not-fits-mime
    %-  forge-mime  crlf
  ==
::
::  helpers for the assertion above, kept out of the ;: so the tall
::  forms do not have to fit inside a list element.
++  forge-mime
  |=  bm=@t
  ^-  chain:sur
  :_  ~
  =/  u=unsigned:sur
    [~sampel-palnet 1 (sy ~[~palnet-sampel]) 's' 'b' bm ~2026.1.1 ~ ~]
  [u (sign-with:auspex (fake-ring:auspex ~sampel-palnet) (digest:auspex u))]
::
++  not-fits-mime
  |=  c=chain:sur
  ^-  ?
  !(fits-body-mimes:auspex c max-mime:auspex)
::
::  the eviction order: blobs no stored message mentions, oldest first.
::  A referenced blob is never evictable however old, and %delete-thread
::  culls messages without culling their blobs, so the unreferenced set
::  is not hypothetical.
++  test-unreferenced-is-oldest-first
  =/  held=(list blob-row:sur)
    :~  [0v1 ~2026.1.3 10]
        [0v2 ~2026.1.1 20]
        [0v3 ~2026.1.2 30]
        [0v4 ~2026.1.4 40]
    ==
  =/  hs  |=(l=(list blob-row:sur) (turn l |=(r=blob-row:sur h.r)))
  ;:  weld
    ::  0v2 and 0v4 are referenced, so 0v3 (older) then 0v1
    (expect-eq !>(~[0v3 0v1]) !>((hs (unreferenced:auspex held (sy ~[0v2 0v4])))))
    ::  nothing referenced: strict age order over all four
    (expect-eq !>(~[0v2 0v3 0v1 0v4]) !>((hs (unreferenced:auspex held ~))))
    ::  everything referenced: nothing is evictable, however old
    (expect-eq !>(~) !>((hs (unreferenced:auspex held (sy ~[0v1 0v2 0v3 0v4])))))
    (expect-eq !>(100) !>((held-bytes:auspex held)))
  ==
::
::  +shed-for is what makes max-blobs a store that can be full rather
::  than one that jams. It refuses rather than half-evicting when the
::  store cannot be made to fit: culling blobs and THEN rejecting the
::  write would lose files for nothing.
++  test-shed-for-refuses-rather-than-half-evicting
  =/  held=(list blob-row:sur)
    ~[[0v1 ~2026.1.1 10] [0v2 ~2026.1.2 20]]
  ;:  weld
    ::  fits already: no shedding, and nothing is culled speculatively
    (expect-eq !>([%.y ~]) !>((shed-for:auspex held (sy ~[0v1 0v2]) 0 0)))
    ::  over the COUNT bound and nothing is unreferenced: refuse, and
    ::  refuse with an empty drop list, so a caller that culls first and
    ::  checks second cannot lose files for nothing
    (expect-eq !>([%.n ~]) !>((shed-for:auspex held (sy ~[0v1 0v2]) max-blobs:auspex 0)))
    ::  over the COUNT bound, and shedding the unreferenced one is enough
    (expect-eq !>([%.y ~[0v2]]) !>((shed-for:auspex held (sy ~[0v1]) (dec max-blobs:auspex) 0)))
    ::  the BYTE bound binds independently of the count: one blob, well
    ::  under max-blobs, and still no room
    %+  expect-eq  !>([%.y ~[0v1]])
    !>  %^    shed-for:auspex
            ~[[0v1 ~2026.1.1 max-blob-bytes:auspex]]
          ~
        [1 100]
  ==
::
::  swapping a file breaks the signature. This is the whole reason the
::  metadata sits inside `unsigned` rather than beside it: an attacker who
::  substitutes an attachment cannot leave the message verifying.
++  test-swapped-attachment-is-forged
  =/  f=file:sur  ['note.txt' 'text/plain' [11 'hello world']]
  =/  g=file:sur  ['note.txt' 'text/plain' [11 'hello xorld']]
  =/  a
    %-  forge-with
    :*  ~sampel-palnet  (sy ~[~palnet-sampel])  'hi'  'see attached'
        ~2026.1.1  ~  ~[(describe:auspex f)]
    ==
  =/  swapped=msg:sur  a(attachments.unsigned ~[(describe:auspex g)])
  =/  keys  (all-keys ~[~sampel-palnet])
  ;:  weld
    (expect-eq !>(~[%verified]) !>((turn (verify-chain:auspex keys ~[a]) |=([* v=verdict:sur] v))))
    (expect-eq !>(~[%forged]) !>((turn (verify-chain:auspex keys ~[swapped]) |=([* v=verdict:sur] v))))
  ==
::
::  the incoming bound applies per message, and a chain is rejected whole
::  when any message in it exceeds it. A delivered chain carries metadata
::  only, so this is what bounds what a hostile peer can make us store -
::  and what it can later make us try to fetch.
++  test-incoming-attachment-caps
  =/  small  ['f' 3 'text/plain' 0v1]
  =/  huge   ['f' 999.999.999 'text/plain' 0v2]
  =/  ok
    (forge-with ~sampel-palnet (sy ~[~palnet-sampel]) 's' 'b' ~2026.1.1 ~ ~[small small])
  =/  many
    %-  forge-with
    :*  ~sampel-palnet  (sy ~[~palnet-sampel])  's'  'b'  ~2026.1.2  ~
        ~[small small small]
    ==
  =/  big
    (forge-with ~sampel-palnet (sy ~[~palnet-sampel]) 's' 'b' ~2026.1.3 ~ ~[huge])
  ;:  weld
    (expect !>((fits-attachments:auspex ~[ok] 2)))
    (expect !>(!(fits-attachments:auspex ~[ok many] 2)))
    ::  a size beyond max-blob is refused at the boundary whatever the count
    (expect !>(!(fits-attachments:auspex ~[big] 16)))
  ==
::
::  +chain-hashes is what a reader walks to know which bytes it is missing.
++  test-chain-hashes-collects-every-address
  =/  a
    %-  forge-with
    :*  ~sampel-palnet  (sy ~[~palnet-sampel])  'hi'  'one'  ~2026.1.1  ~
        ~[['f' 3 'text/plain' 0v1] ['g' 3 'text/plain' 0v2]]
    ==
  =/  b
    %-  forge-with
    :*  ~palnet-sampel  (sy ~[~sampel-palnet])  're'  'two'  ~2026.1.2
        `(id:auspex unsigned.a)  ~[['h' 3 'text/plain' 0v2]]
    ==
  %+  expect-eq
    !>  (sy ~[0v1 0v2])
    !>  (chain-hashes:auspex ~[a b])
::
::  THE PATHS. A blob is bound at its hash with NO revision segment: the
::  content is its own address, so there is nothing to discover and the
::  fetcher builds the whole path from the hash alone. The keen path is
::  pinned here because the empty knot in it is exactly the segment a path
::  literal cannot spell and the one nobody notices is missing.
++  test-blob-paths-are-content-addressed
  =/  h  0v1.23456
  ;:  weld
    (expect-eq !>(/auspex/blob/'0v1.23456') !>((blob-spur:auspex h)))
    %+  expect-eq
      !>  `path`[%g %x %'1' %grubbery %$ %'1' %auspex %blob '0v1.23456' ~]
      !>  (blob-keen-path:auspex %grubbery h 1)
    ::  the case is a segment of the path, so a probe at a later case is a
    ::  different read of the SAME immutable binding.
    %+  expect-eq
      !>  `path`[%g %x %'2' %grubbery %$ %'1' %auspex %blob '0v1.23456' ~]
      !>  (blob-keen-path:auspex %grubbery h 2)
  ==
::
::  ── the thread as a tree ────────────────────────────────────────────
::
::  +branch: the canonical branching thread these tests are written
::  against. R is the root; A and B are two replies to R, so they are
::  SIBLINGS; A2 answers A. The two branches are R-A-A2 and R-B, and the
::  point of everything below is that one of them travels without the
::  other.
::
++  branch
  |=  ~
  ^-  [r=msg:sur a=msg:sur a2=msg:sur b=msg:sur]
  =/  r   (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'subj' 'root' ~2026.1.1 ~)
  =/  ri  (id:auspex unsigned.r)
  =/  a   (forge ~palnet-sampel (sy ~[~sampel-palnet]) 'subj' 'side one' ~2026.1.2 `ri)
  =/  ai  (id:auspex unsigned.a)
  =/  a2  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'subj' 'side two' ~2026.1.3 `ai)
  =/  b   (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'subj' 'other branch' ~2026.1.4 `ri)
  [r a a2 b]
::
::  a message's ancestry is the ids from the root down to it, inclusive.
++  test-ancestors-are-root-first
  =/  [r=msg:sur a=msg:sur a2=msg:sur b=msg:sur]  (branch ~)
  =/  ps  (prev-map:auspex ~[r a a2 b])
  ;:  weld
    %+  expect-eq
      !>  ~[(id:auspex unsigned.r)]
      !>  (ancestors:auspex ps (id:auspex unsigned.r))
    %+  expect-eq
      !>  ~[(id:auspex unsigned.r) (id:auspex unsigned.a) (id:auspex unsigned.a2)]
      !>  (ancestors:auspex ps (id:auspex unsigned.a2))
    ::  B is a SIBLING of A, so A is nowhere in its ancestry.
    %+  expect-eq
      !>  ~[(id:auspex unsigned.r) (id:auspex unsigned.b)]
      !>  (ancestors:auspex ps (id:auspex unsigned.b))
  ==
::
::  the copies of one message share a `prev`, so they share a NODE: two
::  copies differing only in signature never split the tree, which is the
::  [id sig] anti-shadowing key surviving the layout change.
++  test-prev-map-is-keyed-by-id-not-signature
  =/  [r=msg:sur a=msg:sur a2=msg:sur b=msg:sur]  (branch ~)
  =/  fake=msg:sur  r(sig 0xdead.beef)
  =/  ps  (prev-map:auspex ~[r fake a])
  ;:  weld
    (expect-eq !>(2) !>(~(wyt by ps)))
    %+  expect-eq
      !>  ~[(id:auspex unsigned.r)]
      !>  (ancestors:auspex ps (id:auspex unsigned.r))
  ==
::
::  THE LEAK, CLOSED. Forwarding B ships the path root-to-B; the sibling
::  branch, and everything under it, does not travel.
++  test-path-chain-omits-the-sibling-branch
  =/  [r=msg:sur a=msg:sur a2=msg:sur b=msg:sur]  (branch ~)
  =/  c=chain:sur  (merge:auspex ~ ~[r a a2 b])
  =/  p=chain:sur  (path-chain:auspex c (id:auspex unsigned.b))
  ;:  weld
    (expect-eq !>(~[r b]) !>(p))
    ::  stated again as the property, because the list above is the thing
    ::  under test: neither message of the side exchange travels.
    (expect !>(!(lien p |=(m=msg:sur =(unsigned.m unsigned.a)))))
    (expect !>(!(lien p |=(m=msg:sur =(unsigned.m unsigned.a2)))))
  ==
::
::  and the deep branch travels whole when IT is what was forwarded.
++  test-path-chain-carries-the-whole-path
  =/  [r=msg:sur a=msg:sur a2=msg:sur b=msg:sur]  (branch ~)
  =/  c=chain:sur  (merge:auspex ~ ~[r a a2 b])
  %+  expect-eq
    !>  ~[r a a2]
    !>  (path-chain:auspex c (id:auspex unsigned.a2))
::
::  a forwarded path is a VALID CHAIN on its own: it holds the unique
::  prev=~ root, every prev in it resolves inside it, and +thread-key
::  files it under the thread the whole thread would have been filed
::  under. Without those three a forward would look sent here and be
::  refused at the far end.
++  test-path-chain-is-a-fileable-chain
  =/  [r=msg:sur a=msg:sur a2=msg:sur b=msg:sur]  (branch ~)
  =/  c=chain:sur  (merge:auspex ~ ~[r a a2 b])
  =/  p=chain:sur  (path-chain:auspex c (id:auspex unsigned.b))
  =/  ids  (~(gas in *(set msg-id:sur)) (turn p |=(m=msg:sur (id:auspex unsigned.m))))
  =/  closed=?
    %+  levy  p
    |=(m=msg:sur ?~(prev.unsigned.m & (~(has in ids) u.prev.unsigned.m)))
  ;:  weld
    (expect-eq !>(1) !>((lent (skim p |=(m=msg:sur ?=(~ prev.unsigned.m))))))
    (expect !>(closed))
    %+  expect-eq
      !>  (thread-key:auspex ~ c)
      !>  (thread-key:auspex ~ p)
  ==
::
::  every copy at a node on the path travels, not one chosen copy.
::  Choosing would be exactly the shadowing +merge exists to prevent,
::  made by the forwarder rather than by an attacker.
++  test-path-chain-keeps-both-copies-of-a-node
  =/  [r=msg:sur a=msg:sur a2=msg:sur b=msg:sur]  (branch ~)
  =/  fake=msg:sur  r(sig 0xdead.beef)
  =/  c=chain:sur   (merge:auspex ~ ~[r fake b])
  =/  p=chain:sur   (path-chain:auspex c (id:auspex unsigned.b))
  ;:  weld
    (expect-eq !>(3) !>((lent p)))
    (expect !>((lien p |=(m=msg:sur =(sig.m sig.r)))))
    (expect !>((lien p |=(m=msg:sur =(sig.m 0xdead.beef)))))
  ==
::
::  an ORPHAN - a message whose prev names nothing in the chain - is
::  PLACED, as a root of its own, rather than dropped. Only hostile input
::  makes one, and refusing to store a message is worse than filing it
::  shallow.
++  test-orphan-is-its-own-root
  =/  [r=msg:sur a=msg:sur a2=msg:sur b=msg:sur]  (branch ~)
  =/  lost
    (forge ~palnet-sampel (sy ~[~sampel-palnet]) 'subj' 'orphan' ~2026.1.9 `0vdead)
  =/  ps  (prev-map:auspex ~[r lost])
  %+  expect-eq
    !>  ~[(id:auspex unsigned.lost)]
    !>  (ancestors:auspex ps (id:auspex unsigned.lost))
::
::  a prev cycle TERMINATES. It needs a hash preimage loop and so cannot
::  really happen, but +ancestors runs on attacker-supplied input inside
::  the writer, which must never hang.
++  test-ancestors-survives-a-cycle
  =/  ps=(map msg-id:sur (unit msg-id:sur))
    (malt ~[[0v1 `0v2] [0v2 `0v3] [0v3 `0v1]])
  (expect !>((lte (lent (ancestors:auspex ps 0v1)) 4)))
::
::  +with-root fires only for an orphan path. A well-formed path already
::  holds the root and comes back untouched; a rootless one gets the
::  thread's root, without which the recipient's +thread-key refuses the
::  whole chain.
++  test-with-root-only-adds-when-the-root-is-missing
  =/  [r=msg:sur a=msg:sur a2=msg:sur b=msg:sur]  (branch ~)
  =/  c=chain:sur  (merge:auspex ~ ~[r a a2 b])
  =/  good  (path-chain:auspex c (id:auspex unsigned.b))
  ;:  weld
    (expect-eq !>(good) !>((with-root:auspex c good)))
    (expect-eq !>(~[r a]) !>((with-root:auspex c ~[a])))
  ==
::
::  ── the forest, as storage paths ────────────────────────────────────
::
::  a message's storage path IS its ancestry, so two branches are two
::  sibling directories under the message they both answer.
++  test-ancestor-map-places-siblings-side-by-side
  =/  [r=msg:sur a=msg:sur a2=msg:sur b=msg:sur]  (branch ~)
  =/  am  (ancestor-map:auspex (merge:auspex ~ ~[r a a2 b]))
  =/  ri  `@ta`(scot %uv (id:auspex unsigned.r))
  =/  ai  `@ta`(scot %uv (id:auspex unsigned.a))
  ;:  weld
    %+  expect-eq
      !>  `path`~[ri ai `@ta`(scot %uv (id:auspex unsigned.a2))]
      !>  (id-path:auspex (~(got by am) (id:auspex unsigned.a2)))
    %+  expect-eq
      !>  `path`~[ri `@ta`(scot %uv (id:auspex unsigned.b))]
      !>  (id-path:auspex (~(got by am) (id:auspex unsigned.b)))
  ==
::
::  directories are made shallowest first: a directory needs its parent.
++  test-prefixes-are-shortest-first
  %+  expect-eq
    !>  ~[/a /a/b /a/b/c]
    !>  (prefixes:auspex /a/b/c)
::
::  a copy path is <ancestry>/<slot>, so its directories are the prefixes
::  of everything but the slot. A ONE-SEGMENT path needs no directory at
::  all: it is a pre-tree grub stored flat under msg/, which is exactly
::  how the migration recognises one.
++  test-node-dirs-drops-the-slot-and-keeps-the-ancestry
  ;:  weld
    (expect-eq !>((sy ~[/a /a/b])) !>((node-dirs:auspex ~[/a/b/slot])))
    (expect-eq !>(*(set path)) !>((node-dirs:auspex ~[/flat-slot])))
    ::  two branches under one node share that node's directory
    %+  expect-eq
      !>  (sy ~[/r /r/a /r/b])
      !>  (node-dirs:auspex ~[/r/a/s1 /r/b/s2])
  ==
::
::  culling a directory takes its subtree, so only the shallowest stale
::  directories are culled and nothing already inside one is culled
::  again.
++  test-minimal-dirs-and-under-any
  =/  ds  (sy ~[/r /r/a /r/a/b])
  ;:  weld
    (expect-eq !>(~[/r]) !>((minimal-dirs:auspex ds)))
    (expect !>((under-any:auspex /r/a/b/slot ds)))
    (expect !>(!(under-any:auspex /other/slot ds)))
  ==
::
::  +max-ancestry is what the depth cap is measured against: the DEEPEST
::  root-to-leaf path, not the message count. The branching thread is
::  four messages and three deep.
++  test-max-ancestry-is-the-deepest-path
  =/  [r=msg:sur a=msg:sur a2=msg:sur b=msg:sur]  (branch ~)
  ;:  weld
    (expect-eq !>(3) !>((max-ancestry:auspex ~[r a a2 b])))
    (expect-eq !>(1) !>((max-ancestry:auspex ~[r])))
    (expect-eq !>(0) !>((max-ancestry:auspex ~)))
    ::  the cap refuses at the boundary the way every other one does
    (expect !>((fits-depth:auspex ~[r a a2 b] 3)))
    (expect !>(!(fits-depth:auspex ~[r a a2 b] 2)))
  ==
::
::  the signer cap counts the DISTINCT KEY SET, not the messages, because
::  what it bounds is one scry per distinct [ship life] on the write path
::  - see +max-signers. So many messages from few senders are cheap and
::  must pass, and few messages from many senders are expensive and must
::  be refusable at exactly the same message count.
++  test-signer-cap-counts-keys-not-messages
  =/  a1  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'one' ~2026.1.1 ~)
  =/  a2  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'two' ~2026.1.2 ~)
  =/  a3  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'hi' 'three' ~2026.1.3 ~)
  =/  b   (forge ~palnet-sampel (sy ~[~sampel-palnet]) 'hi' 'four' ~2026.1.4 ~)
  =/  c   (forge ~marbud-marbud (sy ~[~sampel-palnet]) 'hi' 'five' ~2026.1.5 ~)
  ::  a signer is [ship life], not a ship: the same ship at a second life
  ::  is a second key and a second scry, so it counts twice. A message
  ::  signed under life 3 stays verifiable after the sender rotates,
  ::  which is why `life` travels at all.
  =/  a-later  a1(life.unsigned 2)
  ;:  weld
    ::  three messages, one signer: the cap is not a message count
    (expect !>((fits-signers:auspex ~[a1 a2 a3] 1)))
    ::  three messages, three signers, refused at two
    (expect !>((fits-signers:auspex ~[a1 b c] 3)))
    (expect !>(!(fits-signers:auspex ~[a1 b c] 2)))
    ::  an empty chain names nobody and costs nothing
    (expect !>((fits-signers:auspex ~ 0)))
    ::  the same ship at two lives is two keys and two scries
    (expect !>(!(fits-signers:auspex ~[a1 a-later] 1)))
    (expect !>((fits-signers:auspex ~[a1 a-later] 2)))
  ==
::
::  ── the mail-client layer ───────────────────────────────────────────
::
::  Every one of these is a view or a local-state decision. None of them
::  touches `unsigned`, and the two that matter most are the ones that
::  keep a forged message visible: search finds it, and a filter cannot
::  hide it.
::
::  a label is a @tas the user typed, so it is checked at the boundary.
::  A cord holding a space or a capital sits in a (set @tas) perfectly
::  happily and then crashes `scot %tas` on a request fiber, which is an
::  HTTP connection that never answers.
++  test-label-ok-rejects-a-non-term
  ;:  weld
    (expect !>((label-ok:auspex %work)))
    (expect !>((label-ok:auspex %to-read-2)))
    ::  empty, capitalised, spaced, leading digit: none of them is a @tas
    (expect !>(!(label-ok:auspex %$)))
    (expect !>(!(label-ok:auspex `@tas`'Work')))
    (expect !>(!(label-ok:auspex `@tas`'to read')))
    (expect !>(!(label-ok:auspex `@tas`'2fa')))
    (expect !>(!(label-ok:auspex `@tas`'work!')))
    ::  and the length cap
    (expect !>((label-ok:auspex `@tas`(crip (reap 32 'a')))))
    (expect !>(!(label-ok:auspex `@tas`(crip (reap 33 'a')))))
  ==
::
++  test-labels-ok-bounds-the-set
  ;:  weld
    (expect !>((labels-ok:auspex (sy ~[%a %b %c]))))
    ::  one bad member fails the set
    (expect !>(!(labels-ok:auspex (sy ~[%a `@tas`'B']))))
  ==
::
::  the one string primitive the layer has. Case-insensitive on both
::  sides, and an empty needle matches everything - which is what lets an
::  absent query mean "no filter" with no branch at any call site.
++  test-has-sub-is-case-insensitive
  ;:  weld
    (expect !>((has-sub:auspex 'Quarterly Invoice' 'invoice')))
    (expect !>((has-sub:auspex 'quarterly invoice' 'INVOICE')))
    (expect !>((has-sub:auspex 'abc' 'abc')))
    (expect !>((has-sub:auspex 'abc' 'a')))
    (expect !>((has-sub:auspex 'abc' 'c')))
    (expect !>(!(has-sub:auspex 'abc' 'abcd')))
    (expect !>(!(has-sub:auspex '' 'a')))
    ::  an empty needle is no constraint
    (expect !>((has-sub:auspex 'abc' '')))
    (expect !>((has-sub:auspex '' '')))
  ==
::
::  search reads subject, body and the RENDERED sender, so typing part of
::  a ship name finds it.
++  test-search-covers-subject-body-and-sender
  =/  m  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'Quarterly report' 'the numbers are in' ~2026.1.1 ~)
  ;:  weld
    (expect !>((matches:auspex 'quarterly' unsigned.m)))
    (expect !>((matches:auspex 'numbers' unsigned.m)))
    (expect !>((matches:auspex 'sampel-palnet' unsigned.m)))
    (expect !>(!(matches:auspex 'nothing here' unsigned.m)))
    ::  an empty query matches, so a listing with no search term is the
    ::  same code path as one with one
    (expect !>((matches:auspex '' unsigned.m)))
  ==
::
::  SEARCH FINDS A FORGED MESSAGE, and the row it produces is drawn from
::  that message so it can be labelled forged. Drawing the row from the
::  newest non-forged copy - which is right for an ordinary listing - would
::  answer a search for the forgery with a row naming the ship that did
::  not write it.
++  test-search-finds-and-names-the-forged-message
  =/  real   (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'invoice' 'the real one' ~2026.1.1 ~)
  ::  a message ~marbud signed while claiming to be ~sampel-palnet: a
  ::  genuine signature over a lying `from`, which is what a forgery is.
  =/  liar  (fake-from ~marbud-marbud ~sampel-palnet 'invoice' 'PAY HERE INSTEAD' ~2026.1.2)
  =/  c=chain:sur  (merge:auspex ~ ~[real liar])
  ::  the newest match for a term only the forgery carries IS the forgery
  =/  hit  (newest-match:auspex 'pay here' c)
  ::  and its verdict, computed the ordinary way, is %forged - so the row
  ::  this message produces is labelled forged
  =/  vs  (verify-chain:auspex (all-keys ~[~sampel-palnet ~marbud-marbud]) c)
  ;:  weld
    ::  both copies are in the chain, and the query hits the forged one
    (expect-eq !>(2) !>((lent c)))
    (expect !>((chain-matches:auspex 'pay here' c)))
    (expect !>(?=(^ hit)))
    (expect-eq !>('PAY HERE INSTEAD') !>(?~(hit '' body.unsigned.u.hit)))
    (expect !>((lien vs |=([* v=verdict:sur] =(%forged v)))))
  ==
::
::  an empty query has no newest match, which is what makes the ordinary
::  listing keep its own summary rule.
++  test-newest-match-is-empty-without-a-query
  =/  m  (forge ~sampel-palnet ~ 'a' 'b' ~2026.1.1 ~)
  (expect !>(?=(~ (newest-match:auspex '' ~[m]))))
::
::  INBOX IS PARTICIPANT OR DIRECT. The direct flag is what makes a BCC'd
::  recipient's mail visible at all: they are in neither `from` nor `to`
::  of any message in the chain they were handed.
++  test-inbox-is-participant-or-direct
  =/  us  ~sampel-palnet
  =/  ps  (sy ~[~palnet-sampel ~marbud-marbud])
  ;:  weld
    ::  not a participant, not direct: not our inbox
    (expect !>(!(in-inbox:auspex us ps | |)))
    ::  the BCC case: not a participant, but it arrived here
    (expect !>((in-inbox:auspex us ps | &)))
    ::  an ordinary participant
    (expect !>((in-inbox:auspex us (~(put in ps) us) | |)))
    ::  archived beats both
    (expect !>(!(in-inbox:auspex us (~(put in ps) us) & |)))
    (expect !>(!(in-inbox:auspex us ps & &)))
  ==
::
++  test-sent-is-threads-we-authored
  =/  mine   (forge ~sampel-palnet ~ 'a' 'b' ~2026.1.1 ~)
  =/  yours  (forge ~palnet-sampel ~ 'a' 'b' ~2026.1.1 ~)
  ;:  weld
    (expect !>((in-sent:auspex ~sampel-palnet ~[yours mine])))
    (expect !>(!(in-sent:auspex ~sampel-palnet ~[yours])))
    (expect !>(!(in-sent:auspex ~sampel-palnet ~)))
  ==
::
++  test-page-slices-without-losing-the-total
  =/  l=(list @ud)  ~[0 1 2 3 4 5 6 7 8 9]
  ;:  weld
    (expect-eq !>(`(list @ud)`~[0 1 2]) !>((page:auspex l 0 3)))
    (expect-eq !>(`(list @ud)`~[3 4 5]) !>((page:auspex l 3 3)))
    ::  a page past the end is empty, not a crash
    (expect-eq !>(`(list @ud)`~) !>((page:auspex l 100 3)))
    ::  a partial last page
    (expect-eq !>(`(list @ud)`~[9]) !>((page:auspex l 9 3)))
    ::  limit 0 is an empty page, literally. The route defaults an
    ::  ABSENT limit rather than reading 0 as "everything".
    (expect-eq !>(`(list @ud)`~) !>((page:auspex l 0 0)))
  ==
::
::  A DRAFT IS NOT A MESSAGE, and the shapes are what enforce it: the
::  ladder that reads a stored signed copy refuses a draft noun outright,
::  so nothing that produces messages can ever produce one.
++  test-a-draft-is-not-a-stored-message
  =/  d=draft:sur  [%0 0v1 (sy ~[~palnet-sampel]) 'subject' 'body' ~ ~2026.1.1]
  =/  res  (mule |.(;;(stored-msg:sur d)))
  ::  and the converse: a stored copy is not a draft
  =/  m  (forge ~sampel-palnet ~ 'a' 'b' ~2026.1.1 ~)
  =/  st=stored-msg:sur  [%2 m %verified]
  =/  back  (mule |.(;;(draft:sur st)))
  ;:  weld
    (expect !>(?=(%| -.res)))
    (expect !>(?=(%| -.back)))
  ==
::
++  test-draft-ok-applies-the-send-caps
  =/  ok=draft:sur   [%0 0v1 (sy ~[~palnet-sampel]) 'subject' 'body' ~ ~2026.1.1]
  =/  fat=draft:sur  ok(body (crip (reap 100.001 'a')))
  =/  loud=draft:sur  ok(subj (crip (reap 1.001 'a')))
  ;:  weld
    (expect !>((draft-ok:auspex ok)))
    (expect !>(!(draft-ok:auspex fat)))
    (expect !>(!(draft-ok:auspex loud)))
  ==
::
::  a rule with no condition matches everything, and with `archive` set
::  would empty the inbox silently. Refused.
++  test-rule-needs-a-condition
  =/  none=rule:sur  [%0 0v1 ~ ~ ~ |]
  =/  by-from=rule:sur  [%0 0v1 `~sampel-palnet ~ (sy ~[%work]) |]
  =/  by-subj=rule:sur  [%0 0v1 ~ `'invoice' ~ &]
  =/  bad-label=rule:sur  by-from(add (sy ~[`@tas`'Work']))
  ;:  weld
    (expect !>(!(rule-ok:auspex none)))
    (expect !>((rule-ok:auspex by-from)))
    (expect !>((rule-ok:auspex by-subj)))
    (expect !>(!(rule-ok:auspex bad-label)))
  ==
::
::  AN EMPTY SUBJECT IS NOT A CONDITION. [~ ''] is a cell, so a presence
::  check passes it and the length check passes on zero bytes, and
::  +has-sub answers %.y for an empty needle by design - so a rule
::  carrying it fires on every delivered chain and, with archive set,
::  empties the inbox permanently and silently. The test above stops at
::  both-conditions-null and does not discriminate this at all.
++  test-an-empty-subject-is-not-a-condition
  =/  hollow=rule:sur  [%0 0v1 ~ `'' (sy ~[%everything]) &]
  =/  real=rule:sur    [%0 0v1 ~ `'invoice' (sy ~[%everything]) &]
  =/  m  (forge ~sampel-palnet ~ 'anything at all' 'body' ~2026.1.1 ~)
  ;:  weld
    (expect !>(!(rule-ok:auspex hollow)))
    (expect !>((rule-ok:auspex real)))
    ::  an empty sender-less rule paired with a real sender is fine: the
    ::  refusal is about having NO condition, not about the empty cord
    ::  being poisonous
    (expect !>((rule-ok:auspex hollow(from `~sampel-palnet))))
    ::  and the reason it has to be refused: it matches everything
    (expect !>((rule-matches:auspex hollow unsigned.m)))
    (expect !>(!(rule-matches:auspex real unsigned.m)))
  ==
::
++  test-rule-matches-and-across-its-conditions
  =/  m  (forge ~sampel-palnet ~ 'Quarterly Invoice' 'b' ~2026.1.1 ~)
  =/  both=rule:sur    [%0 0v1 `~sampel-palnet `'invoice' ~ |]
  =/  wrong-who=rule:sur  both(from `~palnet-sampel)
  =/  wrong-what=rule:sur  both(subject `'receipt')
  ;:  weld
    (expect !>((rule-matches:auspex both unsigned.m)))
    (expect !>(!(rule-matches:auspex wrong-who unsigned.m)))
    (expect !>(!(rule-matches:auspex wrong-what unsigned.m)))
    ::  an absent condition is not a condition
    (expect !>((rule-matches:auspex both(subject ~) unsigned.m)))
  ==
::
::  A FILTER MAY ADD LABELS AND ARCHIVE, AND NOTHING ELSE. There is no
::  field for delete and none for mark-read, so this is a property of the
::  type rather than a promise: whatever set of rules fires, the answer
::  is a set of labels and one archive flag.
++  test-apply-rules-composes-additively
  =/  m  (forge ~sampel-palnet ~ 'Quarterly Invoice' 'b' ~2026.1.1 ~)
  =/  c=chain:sur  ~[m]
  =/  r1=rule:sur  [%0 0v1 `~sampel-palnet ~ (sy ~[%work]) |]
  =/  r2=rule:sur  [%0 0v2 ~ `'invoice' (sy ~[%money]) &]
  =/  r3=rule:sur  [%0 0v3 `~palnet-sampel ~ (sy ~[%never]) &]
  =/  got  (apply-rules:auspex ~[r1 r2 r3] c)
  ::  no rule fires: no labels, and NOT archived. A bare ? bunts to %.y,
  ::  so an accumulator-shaped fold here would archive everything the
  ::  moment no rule matched.
  =/  quiet  (apply-rules:auspex ~[r3] c)
  =/  none   (apply-rules:auspex ~ c)
  ;:  weld
    ::  the two matching rules' labels union; the non-matching one adds
    ::  nothing
    (expect-eq !>((sy ~[%work %money])) !>(add.got))
    ::  archive ORs across matching rules
    (expect !>(archive.got))
    (expect !>(!archive.quiet))
    (expect-eq !>(*(set @tas)) !>(add.quiet))
    ::  and with no rules at all
    (expect !>(!archive.none))
  ==
::
::  A FILTER CANNOT SUPPRESS A FORGED MESSAGE. Rules are evaluated over
::  the chain AFTER verification and can only ask for labels and an
::  archive - so the forged copy is still in the chain, still carries its
::  own verdict, and is still what a search finds.
++  test-a-filter-cannot-hide-a-forgery
  =/  real  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'invoice' 'the real one' ~2026.1.1 ~)
  =/  liar  (fake-from ~marbud-marbud ~sampel-palnet 'invoice' 'pay here instead' ~2026.1.2)
  =/  c=chain:sur  (merge:auspex ~ ~[real liar])
  ::  a rule aimed squarely at this thread, archiving it
  =/  r=rule:sur  [%0 0v1 `~sampel-palnet `'invoice' (sy ~[%quarantine]) &]
  =/  got  (apply-rules:auspex ~[r] c)
  ;:  weld
    (expect !>(archive.got))
    (expect-eq !>((sy ~[%quarantine])) !>(add.got))
    ::  and the chain the rule was applied to is UNCHANGED: both copies,
    ::  the forgery included, are still there to be stored and shown
    (expect-eq !>(2) !>((lent c)))
    (expect !>((chain-matches:auspex 'pay here' c)))
  ==

::  ── protocol discovery ──────────────────────────────────────────────
::
::  The chooser and the cap pre-check are PURE and live in the lib
::  precisely so they can be asserted here. The fiber code only peeks,
::  caches and calls them; if a rule about which mark to poke lived in a
::  fiber it would be reachable by nothing but a cross-ship send.
::
::  the highest common version, not the first. A sender that took the
::  first common entry would be pinned to whatever order the PEER
::  published, and the peer chooses that order.
++  test-common-version-picks-the-highest
  ;:  weld
    (expect-eq !>(`(unit @ud)`[~ 3]) !>((common-version:auspex ~[1 2 3] ~[3 1 2])))
    (expect-eq !>(`(unit @ud)`[~ 2]) !>((common-version:auspex ~[1 2 3] ~[2 1])))
    (expect-eq !>(`(unit @ud)`[~ 1]) !>((common-version:auspex ~[1] ~[1 2 3])))
  ==
::
::  nothing in common is ~, and ~ is a REFUSAL rather than a fallback:
::  the poke is never sent, because a mark the peer does not carry parks
::  and a park is indistinguishable from a ship that is merely offline.
++  test-common-version-answers-none
  ;:  weld
    (expect-eq !>(`(unit @ud)`~) !>((common-version:auspex ~[1] ~[2 3])))
    (expect-eq !>(`(unit @ud)`~) !>((common-version:auspex ~[1] ~)))
    (expect-eq !>(`(unit @ud)`~) !>((common-version:auspex ~ ~[1])))
  ==
::
::  THE COMPATIBILITY RULE. Auspex shipped before discovery did, so a
::  peer that publishes no /proto is version 1 - not "unknown", which is
::  the only other thing silence could mean and would refuse every peer
::  running the build before this one.
++  test-a-peer-with-no-proto-is-version-1
  =/  q  (peer-proto:auspex ~)
  ;:  weld
    (expect-eq !>(~[1]) !>(versions.q))
    (expect-eq !>(~[%auspex-chain]) !>(marks.q))
    (expect-eq !>(`(unit @tas)`[~ %auspex-chain]) !>((peer-mark:auspex ~)))
    ::  and its caps are version 1's caps, which are the ones this file
    ::  enforces - so a send to a silent peer is checked, not waved past.
    (expect-eq !>(our-caps:auspex) !>((peer-caps:auspex ~)))
  ==
::
::  `versions` and `marks` are parallel: version N's mark is the entry at
::  N's index. A version with no mark at its index answers ~ rather than
::  guessing, because guessing pokes a mark we invented at a ship that
::  never claimed it.
++  test-mark-for-follows-the-parallel-lists
  =/  p=proto:sur  [%auspex ~[1 2] ~[%auspex-chain %auspex-chain-2] our-caps:auspex]
  ;:  weld
    (expect-eq !>(`(unit @tas)`[~ %auspex-chain]) !>((mark-for:auspex p 1)))
    (expect-eq !>(`(unit @tas)`[~ %auspex-chain-2]) !>((mark-for:auspex p 2)))
    (expect-eq !>(`(unit @tas)`~) !>((mark-for:auspex p 3)))
    ::  a publication whose lists disagree in length is refused whole
    ::  rather than read up to the shorter one.
    (expect !>((proto-ok:auspex p)))
    (expect !>(!(proto-ok:auspex [%auspex ~[1 2] ~[%auspex-chain] our-caps:auspex])))
    (expect !>(!(proto-ok:auspex [%auspex ~ ~ our-caps:auspex])))
  ==
::
::  THE PRE-CHECK READS THE PEER'S CAPS AND NEVER OURS. A three-attachment
::  send is legal on this ship - max-attach is sixteen - and is refused by
::  a peer publishing two, and the refusal has to happen HERE, at compose
::  time, because at the far end it is a message that vanishes.
++  test-peer-cap-check-uses-the-peers-caps-not-ours
  =/  as=(list attachment:sur)
    ~[['a' 1 'text/plain' 0v1] ['b' 1 'text/plain' 0v2] ['c' 1 'text/plain' 0v3]]
  =/  m  (forge-with ~sampel-palnet (sy ~[~palnet-sampel]) 's' 'b' ~2026.1.1 ~ as)
  =/  c=chain:sur  ~[m]
  =/  base   our-caps:auspex
  =/  tight  base(max-attach 2)
  =/  small  base(max-blob 0)
  ;:  weld
    ::  our own cap admits it.
    (expect !>((attaches-ok:auspex as)))
    ::  the peer's does not, and the message names the PEER'S number.
    %+  expect-eq
      !>  `(unit @t)`[~ '~sampel-palnet accepts at most 2 attachments']
      !>  (peer-cap-error:auspex ~sampel-palnet c `[%auspex ~[1] ~[%auspex-chain] tight])
    ::  a peer publishing our own caps accepts it.
    %+  expect-eq
      !>  `(unit @t)`~
      !>  (peer-cap-error:auspex ~sampel-palnet c `our-proto:auspex)
    ::  and so does a silent peer, which is version 1 and therefore us.
    (expect-eq !>(`(unit @t)`~) !>((peer-cap-error:auspex ~sampel-palnet c ~)))
    ::  the SIZE bound is the peer's too, not only the count.
    %+  expect-eq
      !>  `(unit @t)`[~ '~sampel-palnet accepts an attachment of at most 0 bytes']
      !>  (peer-cap-error:auspex ~sampel-palnet c `[%auspex ~[1] ~[%auspex-chain] small])
  ==
::
::  what a nexus PUBLISHES is what it ENFORCES. A published cap that
::  disagreed with the enforced one would be worse than publishing
::  nothing: it would make a sender confident about a send the receiver
::  then drops, which is the exact failure discovery exists to remove.
++  test-published-caps-are-the-enforced-caps
  =/  k  our-caps:auspex
  =/  q  our-proto:auspex
  ;:  weld
    (expect-eq !>(max-blob:auspex) !>(max-blob.k))
    (expect-eq !>(max-attach:auspex) !>(max-attach.k))
    (expect-eq !>(max-chain:auspex) !>(max-chain.k))
    (expect-eq !>(max-body:auspex) !>(max-body.k))
    (expect-eq !>(max-subj:auspex) !>(max-subj.k))
    (expect-eq !>(max-to:auspex) !>(max-to.k))
    (expect-eq !>(max-depth:auspex) !>(max-depth.k))
    (expect-eq !>(max-signers:auspex) !>(max-signers.k))
    (expect-eq !>(max-mime:auspex) !>(max-mime.k))
    (expect-eq !>(max-name:auspex) !>(max-name.k))
    ::  and the published head names us, so a noun keened out of a farm
    ::  shared with every other nexus is identifiable before it is trusted.
    (expect !>(?=(%auspex -.q)))
    (expect-eq !>(~[1]) !>(our-versions:auspex))
    (expect-eq !>(~[%auspex-chain]) !>(our-marks:auspex))
  ==
::
::  a cached answer is believed for a day and then it is not. The TTL
::  caches a peer's DEPLOYED CODE, which moves on the timescale of a
::  release; the short correction path is a nack, which drops the record
::  outright rather than waiting this out.
++  test-a-peer-record-expires
  =/  r=peer-rec:sur  [%0 ~sampel-palnet ~ ~2026.1.1]
  ;:  weld
    (expect !>((peer-fresh:auspex r ~2026.1.1)))
    (expect !>((peer-fresh:auspex r (add ~2026.1.1 ~h23))))
    (expect !>(!(peer-fresh:auspex r (add ~2026.1.1 ~d1))))
    (expect !>(!(peer-fresh:auspex r (add ~2026.1.1 ~d2))))
    ::  a record from the future is not fresh either. `asked` is written
    ::  by this ship, so that is a clock that moved, and believing it
    ::  would pin the record forever.
    (expect !>(!(peer-fresh:auspex r ~2025.1.1)))
  ==
::
::  the two version refusals, as the user reads them. Ship name first,
::  one line each: the composer shows one line and the first thing a
::  person needs is which recipient it is about.
++  test-the-discovery-refusals-name-the-ship-first
  =/  p=proto:sur  [%auspex ~[7 9] ~[%a %b] our-caps:auspex]
  ;:  weld
    %+  expect-eq
      !>  ^-  @t
          'no common protocol version: ~sampel-palnet speaks 7, 9, this ship speaks 1'
      !>  (no-version-error:auspex ~sampel-palnet p)
    %+  expect-eq
      !>  ^-  @t
          '~sampel-palnet did not answer discovery and did not ack the send'
      !>  (no-answer-error:auspex ~sampel-palnet)
    ::  and there is no common version with that peer, which is what
    ::  produces the first message rather than a poke.
    (expect-eq !>(`(unit @tas)`~) !>((peer-mark:auspex `p)))
  ==
::
::  the keen path a sender builds for a peer's /proto mirrors the spur
::  the publisher grows at, and carries the EMPTY SEGMENT that a path
::  literal cannot spell - the same segment +blob-keen-path carries, and
::  the one nobody notices is missing until every read misses forever.
++  test-proto-paths-mirror-each-other
  =/  k=path  (proto-keen-path:auspex %grubbery 1)
  ;:  weld
    (expect-eq !>(`path`/auspex/proto) !>(proto-spur:auspex))
    (expect-eq !>(8) !>((lent k)))
    ::  the empty knot is really there, and it is the one segment a path
    ::  literal cannot spell - which is why this list is written by cons.
    (expect-eq !>(`path`~[%g %x '1' %grubbery '' '1' %auspex %proto]) !>(k))
    (expect-eq !>(`@ta`'') !>((snag 4 k)))
    ::  and the tail of the keen path IS the spur, so a change to one
    ::  that is not made to the other fails here rather than in the field.
    (expect-eq !>(proto-spur:auspex) !>((slag 6 k)))
  ==
--

::  Unit tests for /lib/urmail-chain. Ported verbatim from the %urmail
::  desk's tests/lib/urmail.hoon; only the imports differ.
::
::    The desk split types (/sur/urmail) from arms (/lib/urmail) and this
::    file named them `sur` and `urmail`. The overlay has no sur/, so both
::    faces are bound to the one lib. Two faces on one file keeps every
::    assertion below byte-identical to the reviewed original, which is
::    the point of a port.
::
/+  *test, urmail=urmail-chain, sur=urmail-chain
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
    [~sampel-palnet 1 (sy ~[~palnet-sampel]) 'subj' 'body' '' ~2026.1.1 ~ ~]
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
    [~sampel-palnet 1 (sy ~[~palnet-sampel]) 'subj' 'body' '' ~2026.1.1 ~ ~]
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
    [~sampel-palnet 1 (sy ~[~palnet-sampel]) 'subj' 'body' '' ~2026.1.1 ~ ~]
  =/  d  (digest:urmail base)
  ;:  weld
    (expect !>(!=(d (digest:urmail base(body 'other')))))
    (expect !>(!=(d (digest:urmail base(subj 'other')))))
    (expect !>(!=(d (digest:urmail base(life 2)))))
    (expect !>(!=(d (digest:urmail base(from ~palnet-sampel)))))
    (expect !>(!=(d (digest:urmail base(sent ~2026.1.2)))))
    (expect !>(!=(d (digest:urmail base(to (sy ~[~sampel-palnet]))))))
    (expect !>(!=(d (digest:urmail base(prev `0v1)))))
    ::  attachments are inside `unsigned`, so the id covers them too and
    ::  swapping a file cannot leave the signature standing.
    (expect !>(!=(d (digest:urmail base(attachments ~[['f' 3 'text/plain' 0v2]])))))
    ::  the rendering instruction is part of the message: "render me as
    ::  HTML" and "render me as plain text" are different messages, and
    ::  an intermediary must not be able to switch which one is read.
    (expect !>(!=(d (digest:urmail base(body-mime 'text/html')))))
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
    [who 2 (sy ~[~palnet-sampel]) 'subj' 'body' '' ~2026.1.1 ~ ~]
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

::  ── attachments ──────────────────────────────────────────────────────
::
::  the content address covers the LENGTH as well as the atom. Hashing the
::  bare atom would give two files that differ only in leading zero bytes
::  one address, and would let a lie about `size` pass unnoticed.
++  test-blob-hash-covers-length
  =/  a=octs  [3 'abc']
  =/  b=octs  [4 'abc']
  ;:  weld
    (expect !>(=((blob-hash:urmail a) (blob-hash:urmail [3 'abc']))))
    (expect !>(!=((blob-hash:urmail a) (blob-hash:urmail b))))
    (expect !>(!=((blob-hash:urmail a) (sham q.a))))
  ==
::
::  THE ACCEPTANCE RULE. A blob is accepted only if its bytes hash to the
::  address it was fetched under. Everything else about the courier is
::  irrelevant, and a mismatch is discarded rather than stored.
++  test-blob-ok-rejects-wrong-bytes
  =/  good=octs  [11 'hello world']
  =/  h  (blob-hash:urmail good)
  ;:  weld
    (expect !>((blob-ok:urmail good h)))
    (expect !>(!(blob-ok:urmail [11 'hello xorld'] h)))
    ::  right bytes, wrong declared length: still a different address
    (expect !>(!(blob-ok:urmail [12 'hello world'] h)))
    (expect !>(!(blob-ok:urmail good 0v0)))
  ==
::
::  +describe is what puts a file's identity inside the signature. Its
::  size and hash must agree with the bytes it was built from.
++  test-describe-matches-its-bytes
  =/  f=file:sur  ['note.txt' 'text/plain' [11 'hello world']]
  =/  a  (describe:urmail f)
  ;:  weld
    (expect-eq !>('note.txt') !>(name.a))
    (expect-eq !>(11) !>(size.a))
    (expect-eq !>('text/plain') !>(mime.a))
    (expect !>((blob-ok:urmail octs.f hash.a)))
  ==
::
::  a file whose declared length is BELOW its measured bytes is malformed:
::  the atom carries more than the octs claims, so the address computed at
::  send time would not be the address the bytes are re-measured against.
++  test-file-ok-rejects-malformed-octs
  ;:  weld
    (expect !>((file-ok:urmail ['a' 'text/plain' [11 'hello world']])))
    (expect !>((file-ok:urmail ['a' 'text/plain' [40 'hello world']])))
    (expect !>(!(file-ok:urmail ['a' 'text/plain' [3 'hello world']])))
    (expect !>(!(file-ok:urmail ['a' 'text/plain' [1.000.000 'x']])))
    (expect !>(!(file-ok:urmail [(crip (reap 300 'n')) 'text/plain' [1 'x']])))
    (expect !>(!(file-ok:urmail ['a' (crip (reap 200 'm')) [1 'x']])))
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
    (expect !>((text-ok:urmail 'text/plain' 128)))
    (expect !>(!(text-ok:urmail crlf 128)))
    (expect !>(!(text-ok:urmail (cat 3 'a' (cat 3 lf 'b')) 128)))
    (expect !>(!(text-ok:urmail (cat 3 'a' (cat 3 cr 'b')) 128)))
    (expect !>(!(text-ok:urmail (cat 3 'a' (cat 3 del 'b')) 128)))
    (expect !>(!(fits-attachments:urmail ~[bad] 16)))
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
  [u (sign-with:urmail (fake-ring:urmail ~sampel-palnet) (digest:urmail u))]
::
++  not-fits-mime
  |=  c=chain:sur
  ^-  ?
  !(fits-body-mimes:urmail c max-mime:urmail)
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
    (expect-eq !>(~[0v3 0v1]) !>((hs (unreferenced:urmail held (sy ~[0v2 0v4])))))
    ::  nothing referenced: strict age order over all four
    (expect-eq !>(~[0v2 0v3 0v1 0v4]) !>((hs (unreferenced:urmail held ~))))
    ::  everything referenced: nothing is evictable, however old
    (expect-eq !>(~) !>((hs (unreferenced:urmail held (sy ~[0v1 0v2 0v3 0v4])))))
    (expect-eq !>(100) !>((held-bytes:urmail held)))
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
    (expect-eq !>([%.y ~]) !>((shed-for:urmail held (sy ~[0v1 0v2]) 0 0)))
    ::  over the COUNT bound and nothing is unreferenced: refuse, and
    ::  refuse with an empty drop list, so a caller that culls first and
    ::  checks second cannot lose files for nothing
    (expect-eq !>([%.n ~]) !>((shed-for:urmail held (sy ~[0v1 0v2]) max-blobs:urmail 0)))
    ::  over the COUNT bound, and shedding the unreferenced one is enough
    (expect-eq !>([%.y ~[0v2]]) !>((shed-for:urmail held (sy ~[0v1]) (dec max-blobs:urmail) 0)))
    ::  the BYTE bound binds independently of the count: one blob, well
    ::  under max-blobs, and still no room
    %+  expect-eq  !>([%.y ~[0v1]])
    !>  %^    shed-for:urmail
            ~[[0v1 ~2026.1.1 max-blob-bytes:urmail]]
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
        ~2026.1.1  ~  ~[(describe:urmail f)]
    ==
  =/  swapped=msg:sur  a(attachments.unsigned ~[(describe:urmail g)])
  =/  keys  (all-keys ~[~sampel-palnet])
  ;:  weld
    (expect-eq !>(~[%verified]) !>((turn (verify-chain:urmail keys ~[a]) |=([* v=verdict:sur] v))))
    (expect-eq !>(~[%forged]) !>((turn (verify-chain:urmail keys ~[swapped]) |=([* v=verdict:sur] v))))
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
    (expect !>((fits-attachments:urmail ~[ok] 2)))
    (expect !>(!(fits-attachments:urmail ~[ok many] 2)))
    ::  a size beyond max-blob is refused at the boundary whatever the count
    (expect !>(!(fits-attachments:urmail ~[big] 16)))
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
        `(id:urmail unsigned.a)  ~[['h' 3 'text/plain' 0v2]]
    ==
  %+  expect-eq
    !>  (sy ~[0v1 0v2])
    !>  (chain-hashes:urmail ~[a b])
::
::  THE PATHS. A blob is bound at its hash with NO revision segment: the
::  content is its own address, so there is nothing to discover and the
::  fetcher builds the whole path from the hash alone. The keen path is
::  pinned here because the empty knot in it is exactly the segment a path
::  literal cannot spell and the one nobody notices is missing.
++  test-blob-paths-are-content-addressed
  =/  h  0v1.23456
  ;:  weld
    (expect-eq !>(/urmail/blob/'0v1.23456') !>((blob-spur:urmail h)))
    %+  expect-eq
      !>  `path`[%g %x %'1' %grubbery %$ %'1' %urmail %blob '0v1.23456' ~]
      !>  (blob-keen-path:urmail %grubbery h 1)
    ::  the case is a segment of the path, so a probe at a later case is a
    ::  different read of the SAME immutable binding.
    %+  expect-eq
      !>  `path`[%g %x %'2' %grubbery %$ %'1' %urmail %blob '0v1.23456' ~]
      !>  (blob-keen-path:urmail %grubbery h 2)
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
  =/  ri  (id:urmail unsigned.r)
  =/  a   (forge ~palnet-sampel (sy ~[~sampel-palnet]) 'subj' 'side one' ~2026.1.2 `ri)
  =/  ai  (id:urmail unsigned.a)
  =/  a2  (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'subj' 'side two' ~2026.1.3 `ai)
  =/  b   (forge ~sampel-palnet (sy ~[~palnet-sampel]) 'subj' 'other branch' ~2026.1.4 `ri)
  [r a a2 b]
::
::  a message's ancestry is the ids from the root down to it, inclusive.
++  test-ancestors-are-root-first
  =/  [r=msg:sur a=msg:sur a2=msg:sur b=msg:sur]  (branch ~)
  =/  ps  (prev-map:urmail ~[r a a2 b])
  ;:  weld
    %+  expect-eq
      !>  ~[(id:urmail unsigned.r)]
      !>  (ancestors:urmail ps (id:urmail unsigned.r))
    %+  expect-eq
      !>  ~[(id:urmail unsigned.r) (id:urmail unsigned.a) (id:urmail unsigned.a2)]
      !>  (ancestors:urmail ps (id:urmail unsigned.a2))
    ::  B is a SIBLING of A, so A is nowhere in its ancestry.
    %+  expect-eq
      !>  ~[(id:urmail unsigned.r) (id:urmail unsigned.b)]
      !>  (ancestors:urmail ps (id:urmail unsigned.b))
  ==
::
::  the copies of one message share a `prev`, so they share a NODE: two
::  copies differing only in signature never split the tree, which is the
::  [id sig] anti-shadowing key surviving the layout change.
++  test-prev-map-is-keyed-by-id-not-signature
  =/  [r=msg:sur a=msg:sur a2=msg:sur b=msg:sur]  (branch ~)
  =/  fake=msg:sur  r(sig 0xdead.beef)
  =/  ps  (prev-map:urmail ~[r fake a])
  ;:  weld
    (expect-eq !>(2) !>(~(wyt by ps)))
    %+  expect-eq
      !>  ~[(id:urmail unsigned.r)]
      !>  (ancestors:urmail ps (id:urmail unsigned.r))
  ==
::
::  THE LEAK, CLOSED. Forwarding B ships the path root-to-B; the sibling
::  branch, and everything under it, does not travel.
++  test-path-chain-omits-the-sibling-branch
  =/  [r=msg:sur a=msg:sur a2=msg:sur b=msg:sur]  (branch ~)
  =/  c=chain:sur  (merge:urmail ~ ~[r a a2 b])
  =/  p=chain:sur  (path-chain:urmail c (id:urmail unsigned.b))
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
  =/  c=chain:sur  (merge:urmail ~ ~[r a a2 b])
  %+  expect-eq
    !>  ~[r a a2]
    !>  (path-chain:urmail c (id:urmail unsigned.a2))
::
::  a forwarded path is a VALID CHAIN on its own: it holds the unique
::  prev=~ root, every prev in it resolves inside it, and +thread-key
::  files it under the thread the whole thread would have been filed
::  under. Without those three a forward would look sent here and be
::  refused at the far end.
++  test-path-chain-is-a-fileable-chain
  =/  [r=msg:sur a=msg:sur a2=msg:sur b=msg:sur]  (branch ~)
  =/  c=chain:sur  (merge:urmail ~ ~[r a a2 b])
  =/  p=chain:sur  (path-chain:urmail c (id:urmail unsigned.b))
  =/  ids  (~(gas in *(set msg-id:sur)) (turn p |=(m=msg:sur (id:urmail unsigned.m))))
  =/  closed=?
    %+  levy  p
    |=(m=msg:sur ?~(prev.unsigned.m & (~(has in ids) u.prev.unsigned.m)))
  ;:  weld
    (expect-eq !>(1) !>((lent (skim p |=(m=msg:sur ?=(~ prev.unsigned.m))))))
    (expect !>(closed))
    %+  expect-eq
      !>  (thread-key:urmail ~ c)
      !>  (thread-key:urmail ~ p)
  ==
::
::  every copy at a node on the path travels, not one chosen copy.
::  Choosing would be exactly the shadowing +merge exists to prevent,
::  made by the forwarder rather than by an attacker.
++  test-path-chain-keeps-both-copies-of-a-node
  =/  [r=msg:sur a=msg:sur a2=msg:sur b=msg:sur]  (branch ~)
  =/  fake=msg:sur  r(sig 0xdead.beef)
  =/  c=chain:sur   (merge:urmail ~ ~[r fake b])
  =/  p=chain:sur   (path-chain:urmail c (id:urmail unsigned.b))
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
  =/  ps  (prev-map:urmail ~[r lost])
  %+  expect-eq
    !>  ~[(id:urmail unsigned.lost)]
    !>  (ancestors:urmail ps (id:urmail unsigned.lost))
::
::  a prev cycle TERMINATES. It needs a hash preimage loop and so cannot
::  really happen, but +ancestors runs on attacker-supplied input inside
::  the writer, which must never hang.
++  test-ancestors-survives-a-cycle
  =/  ps=(map msg-id:sur (unit msg-id:sur))
    (malt ~[[0v1 `0v2] [0v2 `0v3] [0v3 `0v1]])
  (expect !>((lte (lent (ancestors:urmail ps 0v1)) 4)))
::
::  +with-root fires only for an orphan path. A well-formed path already
::  holds the root and comes back untouched; a rootless one gets the
::  thread's root, without which the recipient's +thread-key refuses the
::  whole chain.
++  test-with-root-only-adds-when-the-root-is-missing
  =/  [r=msg:sur a=msg:sur a2=msg:sur b=msg:sur]  (branch ~)
  =/  c=chain:sur  (merge:urmail ~ ~[r a a2 b])
  =/  good  (path-chain:urmail c (id:urmail unsigned.b))
  ;:  weld
    (expect-eq !>(good) !>((with-root:urmail c good)))
    (expect-eq !>(~[r a]) !>((with-root:urmail c ~[a])))
  ==
::
::  ── the forest, as storage paths ────────────────────────────────────
::
::  a message's storage path IS its ancestry, so two branches are two
::  sibling directories under the message they both answer.
++  test-ancestor-map-places-siblings-side-by-side
  =/  [r=msg:sur a=msg:sur a2=msg:sur b=msg:sur]  (branch ~)
  =/  am  (ancestor-map:urmail (merge:urmail ~ ~[r a a2 b]))
  =/  ri  `@ta`(scot %uv (id:urmail unsigned.r))
  =/  ai  `@ta`(scot %uv (id:urmail unsigned.a))
  ;:  weld
    %+  expect-eq
      !>  `path`~[ri ai `@ta`(scot %uv (id:urmail unsigned.a2))]
      !>  (id-path:urmail (~(got by am) (id:urmail unsigned.a2)))
    %+  expect-eq
      !>  `path`~[ri `@ta`(scot %uv (id:urmail unsigned.b))]
      !>  (id-path:urmail (~(got by am) (id:urmail unsigned.b)))
  ==
::
::  directories are made shallowest first: a directory needs its parent.
++  test-prefixes-are-shortest-first
  %+  expect-eq
    !>  ~[/a /a/b /a/b/c]
    !>  (prefixes:urmail /a/b/c)
::
::  a copy path is <ancestry>/<slot>, so its directories are the prefixes
::  of everything but the slot. A ONE-SEGMENT path needs no directory at
::  all: it is a pre-tree grub stored flat under msg/, which is exactly
::  how the migration recognises one.
++  test-node-dirs-drops-the-slot-and-keeps-the-ancestry
  ;:  weld
    (expect-eq !>((sy ~[/a /a/b])) !>((node-dirs:urmail ~[/a/b/slot])))
    (expect-eq !>(*(set path)) !>((node-dirs:urmail ~[/flat-slot])))
    ::  two branches under one node share that node's directory
    %+  expect-eq
      !>  (sy ~[/r /r/a /r/b])
      !>  (node-dirs:urmail ~[/r/a/s1 /r/b/s2])
  ==
::
::  culling a directory takes its subtree, so only the shallowest stale
::  directories are culled and nothing already inside one is culled
::  again.
++  test-minimal-dirs-and-under-any
  =/  ds  (sy ~[/r /r/a /r/a/b])
  ;:  weld
    (expect-eq !>(~[/r]) !>((minimal-dirs:urmail ds)))
    (expect !>((under-any:urmail /r/a/b/slot ds)))
    (expect !>(!(under-any:urmail /other/slot ds)))
  ==
--

::  Conformance tests for /lib/auspex-chain against protocol/vectors/v1.json.
::
::    The vectors are the wire protocol's fixtures - see docs/protocol.md #8 -
::    and this file is the assertion that THIS implementation still produces
::    them. tests/lib/auspex-chain.hoon tests the arms against each other and
::    would keep passing if every id in the format shifted at once; this file
::    is the one that would not.
::
::    The fixtures are rebuilt here with the same constructors the generator
::    uses (gen/auspex-vectors.hoon), and every expected atom below is
::    TRANSCRIBED FROM THE GENERATOR'S JSON OUTPUT - mechanically, from
::    protocol/vectors/v1.json, not recomputed here. That is the whole point:
::    an assertion that recomputed its own expectation would pass against any
::    change to the format it is meant to pin.
::
::    Every ship is FAKE, so every keypair derives from its @p and every atom
::    below is reproducible on any ship with no network and no Azimuth
::    snapshot. Keys arrive as an explicit map, exactly as in the main suite,
::    which is also the only way to write a deterministic %unverified case:
::    +fake-pass ignores `life`, so a fake ship's every life is one key, and
::    "no key for [~zod 99]" has to be expressed by the map's CONTENTS.
::
::    `jam` is deliberately NOT asserted here. It is in the JSON for an
::    implementer to byte-compare a noun against; in Hoon it would only
::    restate what the id and digest already cover.
::
/+  *test, auspex=auspex-chain, sur=auspex-chain
|%
::  +mk: one signed message. `signer` is the ring used, `from` is what the
::  message CLAIMS, and they differ in exactly one case below.
::
++  mk
  |=  $:  signer=ship
          from=ship
          lyf=@ud
          to=(set ship)
          subj=@t
          body=@t
          bm=@t
          sent=@da
          prev=(unit msg-id:sur)
          as=(list attachment:sur)
      ==
  ^-  msg:sur
  =/  u=unsigned:sur  [from lyf to subj body bm sent prev as]
  [u (sign-with:auspex (fake-ring:auspex signer) (digest:auspex u))]
::
++  bare
  |=  u=unsigned:sur
  ^-  msg:sur
  [u 0x0]
::
++  keys-of
  |=  known=(list [who=ship lyf=@ud])
  ^-  (map [ship @ud] (unit pass))
  %-  malt
  %+  turn  known
  |=([w=ship l=@ud] [[w l] `(fake-pass:auspex w)])
::
++  verdict-of
  |=  [m=msg:sur known=(list [ship @ud])]
  ^-  verdict:sur
  =/  vs  (verify-chain:auspex (keys-of known) ~[m])
  ?~  vs  %unverified
  +.i.vs
::  the fixtures, byte for byte what gen/auspex-vectors.hoon builds.
::
++  m-root
  (mk ~zod ~zod 1 (sy ~[~nec]) 'root' 'the root message' '' ~2026.1.1 ~ ~)
++  i-root  (id:auspex unsigned:m-root)
++  m-reply
  (mk ~nec ~nec 1 (sy ~[~zod]) 'reply' 'the first branch' '' ~2026.1.2 `i-root ~)
++  m-branch
  (mk ~bud ~bud 1 (sy ~[~zod]) 'reply' 'the second branch' '' ~2026.1.3 `i-root ~)
++  m-forged
  (mk ~nec ~zod 1 (sy ~[~nec]) 'root' 'the root message' '' ~2026.1.1 ~ ~)
++  m-life99
  %-  mk
  :*  ~zod  ~zod  99  (sy ~[~nec])  'rotated'  'signed under a life we lack'
      ''  ~2026.1.4  ~  ~
  ==
++  m-orphan
  (mk ~zod ~zod 1 (sy ~[~nec]) 'orphan' 'my parent is not here' '' ~2026.1.5 `0v1 ~)
++  o-one  `octs`[5 'hello']
++  o-two  `octs`[5 'world']
++  a-one  (describe:auspex ['one.txt' 'text/plain' o-one])
++  a-two  (describe:auspex ['two.txt' 'text/plain' o-two])
++  m-attach
  %-  mk
  :*  ~zod  ~zod  1  (sy ~[~nec])  'attached'
      'two files ride inside the signature'  ''  ~2026.1.6  ~  ~[a-one a-two]
  ==
::  the cap fixtures.
::
++  deep
  |=  n=@ud
  ^-  chain:sur
  =|  acc=chain:sur
  =/  pv=(unit msg-id:sur)  ~
  =/  i=@ud  0
  |-  ^-  chain:sur
  ?:  =(i n)  (flop acc)
  =/  u=unsigned:sur
    :*  ~zod  1  (sy ~[~nec])  'depth'
        (crip (weld "d" (scow %ud i)))  ''
        (add ~2026.1.1 (mul i ~s1))  pv  ~
    ==
  $(i +(i), pv `(id:auspex u), acc [(bare u) acc])
::
++  signers-chain
  |=  n=@ud
  ^-  chain:sur
  %+  turn  (gulf 1 n)
  |=  k=@
  ^-  msg:sur
  (bare [`@p`k 1 (sy ~[~zod]) 'many' 'signers' '' ~2026.1.1 ~ ~])
::
++  ships
  |=  n=@ud
  ^-  (set ship)
  (~(gas in *(set ship)) (turn (gulf 1 n) |=(k=@ `@p`k)))
::
++  fat
  |=  n=@ud
  ^-  (list attachment:sur)
  (turn (gulf 1 n) |=(k=@ `attachment:sur`['f' 1 'text/plain' `@uv`k]))
::
::  ── the message cases ───────────────────────────────────────────────
::
::  vector `root`: the id and the digest are a hash over the nine-field
::  noun, so this arm is what would fail if a field were reordered,
::  retyped or added - which is exactly the breaking change docs/protocol
::  #1.2 says must arrive under a new mark instead.
++  test-vectors-root
  ;:  weld
    %+  expect-eq
      !>  `@ux`0xdda.b17e.5c95.a842.8f1a.2620.3c2b.3f5a
      !>  `@ux`(id:auspex unsigned:m-root)
    %+  expect-eq
      !>  `@ux`0x58d3.9974.c4e1.d511.57bf.1796.d14e.f1fd
      !>  `@ux`(digest:auspex unsigned:m-root)
    %+  expect-eq
      !>  `@ux`0x8e4.c82c.130e.aa4e.7f3e.9b26.794d.2861.d7a1.ef36.b562.1c4e.7236.a214.b6ad.5d4c.53da.f3ab.e152.4a95.e1f3.9ebf.4e93.7aa5.38d8.c963.702f.fe60.a16e.518b.1f5f.3032
      !>  sig:m-root
    %+  expect-eq
      !>  %verified
      !>  (verdict-of m-root ~[[~zod 1]])
  ==
::
::  vector `reply`: prev names the root id, and the id changes because
::  prev is one of the nine signed fields.
++  test-vectors-reply
  ;:  weld
    %+  expect-eq
      !>  `@ux`0x3f22.e3b8.5599.ca5d.47ce.04f9.a181.195c
      !>  `@ux`(id:auspex unsigned:m-reply)
    %+  expect-eq
      !>  `@ux`0xc1a2.b086.0db5.7cc4.6d48.c497.e351.1efb
      !>  `@ux`(digest:auspex unsigned:m-reply)
    %+  expect-eq
      !>  `@ux`0xc3f.b5f4.dbb4.a08b.05f5.2550.20de.f84e.6f76.2776.7417.9b4a.f8df.51e4.e004.0377.c9aa.7159.9e96.506f.59c8.4d41.30d8.e7b5.fab1.24c4.f2ee.3ca4.5060.17a0.cca7.f690
      !>  sig:m-reply
    %+  expect-eq
      !>  %verified
      !>  (verdict-of m-reply ~[[~nec 1]])
  ==
::
::  vector `forged-copy`: the SAME `unsigned` and therefore the same id
::  and the same digest, signed with the wrong ring. A key was available
::  and the signature failed against it, which is the whole definition of
::  %forged - and the reason a missing key must never produce one.
++  test-vectors-forged-copy
  ;:  weld
    %+  expect-eq
      !>  `@ux`0xdda.b17e.5c95.a842.8f1a.2620.3c2b.3f5a
      !>  `@ux`(id:auspex unsigned:m-forged)
    %+  expect-eq
      !>  `@ux`0x58d3.9974.c4e1.d511.57bf.1796.d14e.f1fd
      !>  `@ux`(digest:auspex unsigned:m-forged)
    %+  expect-eq
      !>  `@ux`0xd19.8959.ae9d.6fe6.99d8.dfdf.d073.80ce.7c00.5f1b.ada9.546b.c73c.a3aa.ee0f.a0c8.b4b4.8222.8a86.0593.41fc.a26f.155d.057d.5aeb.1431.3b29.cb6e.c7f5.2b58.0b68.b7f4
      !>  sig:m-forged
    %+  expect-eq
      !>  %forged
      !>  (verdict-of m-forged ~[[~zod 1]])
    ::  one id, two signatures.
    (expect !>(=((id:auspex unsigned:m-root) (id:auspex unsigned:m-forged))))
    (expect !>(!=(sig:m-root sig:m-forged)))
  ==
::
::  vector `unverifiable-life`: a GENUINE ~zod signature whose `life` names
::  99. The verifier holds ~zod at life 1 and nothing at life 99, so the
::  verdict is %unverified. It is not a finding about the signature.
++  test-vectors-unverifiable-life
  ;:  weld
    %+  expect-eq
      !>  `@ux`0x9a59.9850.758e.4b63.fc3b.5dff.ca1b.a0c7
      !>  `@ux`(id:auspex unsigned:m-life99)
    %+  expect-eq
      !>  `@ux`0x1fe5.0102.4703.57c8.ddc7.5920.1b14.31c0
      !>  `@ux`(digest:auspex unsigned:m-life99)
    %+  expect-eq
      !>  `@ux`0x499.c2dd.294d.d949.59ff.5fd8.6faa.390e.30fc.b981.d016.b254.bccc.3718.275e.d675.3c00.4441.9fed.e37b.214a.ad3e.82b0.a2a1.2276.2215.d1b8.fbd3.56f9.03ef.1fd7.3e2c
      !>  sig:m-life99
    %+  expect-eq
      !>  %unverified
      !>  (verdict-of m-life99 ~[[~zod 1]])
    ::  and it is %verified the moment the verifier holds that life.
    %+  expect-eq
      !>  %verified
      !>  (verdict-of m-life99 ~[[~zod 99]])
  ==
::
::  vector `two-attachments`: the metadata is INSIDE the signature, so the
::  hashes are part of the id. The two content addresses are (sham octs)
::  over fixed byte strings and are the vectors' `blobs` entries.
++  test-vectors-two-attachments
  ;:  weld
    %+  expect-eq
      !>  `@uv`0v7.ho47b.m4otv.mkrog.7p0g3.0g307
      !>  (blob-hash:auspex o-one)
    %+  expect-eq
      !>  `@uv`0v7.v89o9.0b03c.f1k9n.hgtch.dfso6
      !>  (blob-hash:auspex o-two)
    %+  expect-eq
      !>  `attachment:sur`['one.txt' 5 'text/plain' 0v7.ho47b.m4otv.mkrog.7p0g3.0g307]
      !>  a-one
    %+  expect-eq
      !>  `attachment:sur`['two.txt' 5 'text/plain' 0v7.v89o9.0b03c.f1k9n.hgtch.dfso6]
      !>  a-two
    %+  expect-eq
      !>  `@ux`0x95ea.ed2d.5582.d91a.f0ca.7cd7.39c9.223c
      !>  `@ux`(id:auspex unsigned:m-attach)
    %+  expect-eq
      !>  `@ux`0xd6db.ad76.d1e5.0ed4.6229.4b25.fd96.149c
      !>  `@ux`(digest:auspex unsigned:m-attach)
    %+  expect-eq
      !>  `@ux`0xe5a.e6ec.b9ab.be21.334c.63c6.7e63.f827.cbc7.6d3e.6d9d.b524.eb90.2293.b9c2.bc2e.6fbb.1017.88e4.67f3.b031.1525.16ea.e8a0.58a5.000f.1f98.a741.1e36.1052.eca8.36b4
      !>  sig:m-attach
    %+  expect-eq
      !>  %verified
      !>  (verdict-of m-attach ~[[~zod 1]])
  ==
::
::  ── the chain cases ─────────────────────────────────────────────────
::
::  vector `two-branch-tree`: two replies to one root are siblings. The
::  thread key is the root's id; the tree is three distinct ids and two
::  deep; and a forward of the first branch ships root+branch and NOT the
::  sibling, which is the leak this format closes.
++  test-vectors-two-branch-tree
  =/  c=chain:sur  ~[m-root m-reply m-branch]
  =/  tk  (thread-key:auspex *(map thread-id:sur thread:sur) c)
  =/  pc  (path-chain:auspex c (id:auspex unsigned:m-reply))
  ;:  weld
    %+  expect-eq
      !>  `@ux`0xe5c1.288e.4bb8.eb72.deb7.c21e.aad8.2858
      !>  `@ux`(id:auspex unsigned:m-branch)
    %+  expect-eq
      !>  `@ux`0x733b.d97d.69a2.b837.71bc.2f8f.e1b3.35e1
      !>  `@ux`(digest:auspex unsigned:m-branch)
    %+  expect-eq
      !>  `@ux`0x408.96fa.27cc.b7ba.c442.a35b.a10d.f8c9.8d5a.3cef.b00f.0fc6.40a5.472b.31ac.c2d3.0c04.a3e9.5814.7166.5237.1cbf.2510.317c.82a3.55d0.6576.4184.e054.fd66.bc8a.b33b
      !>  sig:m-branch
    %+  expect-eq
      !>  `@ux`0xdda.b17e.5c95.a842.8f1a.2620.3c2b.3f5a
      !>  `@ux`tk
    %+  expect-eq  !>(3)  !>((distinct-ids:auspex c))
    %+  expect-eq  !>(2)  !>((max-ancestry:auspex c))
    %+  expect-eq  !>(2)  !>((lent pc))
    ::  the sibling is absent from the forwarded path.
    %+  expect-eq
      !>  ~[i-root (id:auspex unsigned:m-reply)]
      !>  (turn pc |=(m=msg:sur (id:auspex unsigned.m)))
    ::  every message in the tree verifies on its own.
    %+  expect-eq
      !>  ~[%verified %verified %verified]
      !>  (turn c |=(m=msg:sur (verdict-of m ~[[~zod 1] [~nec 1] [~bud 1]])))
  ==
::
::  vector `same-id-pair`: +merge keeps both copies, because deduping on
::  the id alone would let whichever arrived first shadow the other. At a
::  cap of one, +prune keeps the %verified copy - never the forged one,
::  whatever the arrival order.
++  test-vectors-same-id-pair
  =/  c=chain:sur  ~[m-root m-forged]
  =/  merged  (merge:auspex ~ c)
  =/  vs  (malt (verify-chain:auspex (keys-of ~[[~zod 1]]) merged))
  =/  pruned  (prune:auspex merged vs 1)
  =/  flipped  (prune:auspex (merge:auspex ~ (flop c)) vs 1)
  ;:  weld
    %+  expect-eq  !>(2)  !>((lent merged))
    %+  expect-eq  !>(1)  !>((lent pruned))
    %+  expect-eq
      !>  ~[sig:m-root]
      !>  (turn pruned |=(m=msg:sur sig.m))
    ::  and the same answer from the other arrival order.
    %+  expect-eq
      !>  ~[sig:m-root]
      !>  (turn flipped |=(m=msg:sur sig.m))
    %+  expect-eq
      !>  ~[%verified %forged]
      !>  (turn merged |=(m=msg:sur (verdict-of m ~[[~zod 1]])))
  ==
::
::  vector `orphan-chain`: `prev` names an id absent from the chain, so
::  the chain holds no prev=~ message and +thread-key refuses it. The
::  message itself is still PLACED - as a root of its own - because
::  refusing to store a message is worse than filing it shallow.
++  test-vectors-orphan-chain
  =/  c=chain:sur  ~[m-orphan]
  =/  rk  (mule |.((thread-key:auspex *(map thread-id:sur thread:sur) c)))
  ;:  weld
    %+  expect-eq
      !>  `@ux`0x792d.0567.621a.2b61.e5b2.a8d3.3ab3.134f
      !>  `@ux`(id:auspex unsigned:m-orphan)
    %+  expect-eq
      !>  `@ux`0x72f5.0b68.de59.07c9.3247.5dfa.41f3.f9ad
      !>  `@ux`(digest:auspex unsigned:m-orphan)
    %+  expect-eq
      !>  `@ux`0x465.f84e.8869.f609.ac2b.2722.3b26.a787.bbbb.8cbf.f21f.83e3.5ffa.434c.8da6.239c.f1db.641b.ab04.56a3.4e36.7ce6.d0e0.5d68.44f9.5bc5.c2d1.4599.1a6c.db2c.2be2.34a3
      !>  sig:m-orphan
    ::  refused, and refused by +thread-key rather than by anything upstream.
    (expect !>(?=(%| -.rk)))
    %+  expect-eq
      !>  1
      !>  (lent (place-of:auspex c (id:auspex unsigned:m-orphan)))
    ::  the message still verifies. A chain the receiver refuses to FILE
    ::  is not a chain of bad signatures.
    %+  expect-eq  !>(%verified)  !>((verdict-of m-orphan ~[[~zod 1]]))
  ==
::
::  ── the cap cases ───────────────────────────────────────────────────
::
::  every cap in the vectors, over the limit and AT it. The at-limit half
::  is what makes these bounds inclusive rather than approximately right,
::  and a cap that refused its own limit would reject legitimate mail
::  permanently: every send ships the path it replies into.
++  test-vectors-caps
  ;:  weld
    ::  max-chain, +fits-length
    (expect !>(!(fits-length:auspex (reap +(max-chain:auspex) m-root) max-chain:auspex)))
    (expect !>((fits-length:auspex (reap max-chain:auspex m-root) max-chain:auspex)))
    ::  max-body, +fits-bodies
    %+  expect-eq  !>(|)
    !>  %+  fits-bodies:auspex
          ~[(bare [~zod 1 (sy ~[~nec]) 's' (fil 3 +(max-body:auspex) 'a') '' ~2026.1.1 ~ ~])]
        max-body:auspex
    %+  expect-eq  !>(&)
    !>  %+  fits-bodies:auspex
          ~[(bare [~zod 1 (sy ~[~nec]) 's' (fil 3 max-body:auspex 'a') '' ~2026.1.1 ~ ~])]
        max-body:auspex
    ::  max-subj, +fits-subjects
    %+  expect-eq  !>(|)
    !>  %+  fits-subjects:auspex
          ~[(bare [~zod 1 (sy ~[~nec]) (fil 3 +(max-subj:auspex) 'a') 'b' '' ~2026.1.1 ~ ~])]
        max-subj:auspex
    ::  max-to, +fits-recipients
    %+  expect-eq  !>(|)
    !>  %+  fits-recipients:auspex
          ~[(bare [~zod 1 (ships +(max-to:auspex)) 's' 'b' '' ~2026.1.1 ~ ~])]
        max-to:auspex
    %+  expect-eq  !>(&)
    !>  %+  fits-recipients:auspex
          ~[(bare [~zod 1 (ships max-to:auspex) 's' 'b' '' ~2026.1.1 ~ ~])]
        max-to:auspex
    ::  max-mime, +fits-body-mimes: length AND control bytes. A CR in a
    ::  Content-Type is a header-injection primitive and the field is
    ::  signed, so the recipient cannot repair it - only refuse it.
    %+  expect-eq  !>(|)
    !>  %+  fits-body-mimes:auspex
          ~[(bare [~zod 1 (sy ~[~nec]) 's' 'b' (fil 3 +(max-mime:auspex) 'a') ~2026.1.1 ~ ~])]
        max-mime:auspex
    %+  expect-eq  !>(|)
    !>  %+  fits-body-mimes:auspex
          ~[(bare [~zod 1 (sy ~[~nec]) 's' 'b' (cat 3 'text/plain' 0xd) ~2026.1.1 ~ ~])]
        max-mime:auspex
    ::  max-attach, +fits-attachments
    %+  expect-eq  !>(|)
    !>  %+  fits-attachments:auspex
          ~[(bare [~zod 1 (sy ~[~nec]) 's' 'b' '' ~2026.1.1 ~ (fat +(max-attach:auspex))])]
        max-attach:auspex
    %+  expect-eq  !>(&)
    !>  %+  fits-attachments:auspex
          ~[(bare [~zod 1 (sy ~[~nec]) 's' 'b' '' ~2026.1.1 ~ (fat max-attach:auspex)])]
        max-attach:auspex
    ::  max-blob, +attach-ok. A claimed size is refused at the boundary:
    ::  it is not evidence of what the bytes weigh, and discovering the
    ::  lie at fetch time is more expensive than refusing the claim.
    %+  expect-eq  !>(|)
    !>  %+  fits-attachments:auspex
          :~  %-  bare
              :*  ~zod  1  (sy ~[~nec])  's'  'b'  ''  ~2026.1.1  ~
                  ~[['big.bin' +(max-blob:auspex) 'application/octet-stream' 0v2]]
              ==
          ==
        max-attach:auspex
    (expect !>((attach-ok:auspex ['ok.bin' max-blob:auspex 'application/octet-stream' 0v2])))
    ::  max-depth, +fits-depth
    (expect !>(!(fits-depth:auspex (deep +(max-depth:auspex)) max-depth:auspex)))
    (expect !>((fits-depth:auspex (deep max-depth:auspex) max-depth:auspex)))
    ::  max-signers, +fits-signers: distinct [ship life] pairs, which is
    ::  one key lookup each and the only cap here that bounds round trips.
    (expect !>(!(fits-signers:auspex (signers-chain +(max-signers:auspex)) max-signers:auspex)))
    (expect !>((fits-signers:auspex (signers-chain max-signers:auspex) max-signers:auspex)))
  ==
::
::  the caps the vectors publish are the caps the lib holds. A vectors
::  file naming different numbers is a spec that has drifted from its
::  implementation, which is the failure this whole file exists to make
::  loud.
++  test-vectors-cap-values
  ;:  weld
    (expect-eq !>(1.000) !>(max-chain:auspex))
    (expect-eq !>(100.000) !>(max-body:auspex))
    (expect-eq !>(1.000) !>(max-subj:auspex))
    (expect-eq !>(100) !>(max-to:auspex))
    (expect-eq !>(4) !>(max-copies:auspex))
    (expect-eq !>(10.000) !>(max-threads:auspex))
    (expect-eq !>(64) !>(max-depth:auspex))
    (expect-eq !>(128) !>(max-signers:auspex))
    (expect-eq !>(262.144) !>(max-blob:auspex))
    (expect-eq !>(16) !>(max-attach:auspex))
    (expect-eq !>(256) !>(max-name:auspex))
    (expect-eq !>(128) !>(max-mime:auspex))
    (expect-eq !>(1.000) !>(max-blobs:auspex))
    (expect-eq !>(33.554.432) !>(max-blob-bytes:auspex))
  ==
::
::  the digest's domain-separation tag is %auspex and nothing else. A
::  changed tag is a changed protocol under docs/protocol #1.2, and it
::  would silently invalidate every signature in the vectors above.
++  test-vectors-digest-tag
  =/  u  unsigned:m-root
  ;:  weld
    (expect-eq !>((shaf %auspex (sham u))) !>((digest:auspex u)))
    (expect !>(!=((digest:auspex u) (sham u))))
    (expect !>(!=((digest:auspex u) (shaf %ames (sham u)))))
    (expect !>(!=((digest:auspex u) (shaf %urmail (sham u)))))
  ==
--

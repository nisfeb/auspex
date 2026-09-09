::  Conformance tests for /lib/auspex-chain against the PUBLISHED
::  artifact, protocol/vectors/v1.json.
::
::    THE FILE IS THE FIXTURE. This suite does not hold a copy of the
::    expected ids, digests and signatures; it reads the artifact an
::    implementer downloads and asserts the library reproduces what is
::    IN IT. The difference is not stylistic. A test carrying
::    hand-transcribed literals passes whether or not the file in the
::    repo says the same thing - and it did not: the file was a dojo
::    transcript reassembled by hand and had already lost two characters
::    to a terminal that strips trailing whitespace. Nothing reported
::    it, because nothing read it.
::
::    So the artifact is now written by the generator straight into clay,
::    copied out of the mount byte for byte, and synced back into the
::    desk by scripts/sync-overlay.sh - which is what lets this file
::    reach it with a /* import.
::
::    The fixtures are rebuilt here with the same constructors the
::    generator uses (gen/auspex-vectors.hoon). Every ship is FAKE, so
::    every keypair derives from its @p and nothing here needs a network
::    or an Azimuth snapshot; keys arrive as an explicit map, which is
::    also the only way to write a deterministic %unverified case, since
::    +fake-pass ignores `life`.
::
/+  *test, auspex=auspex-chain, sur=auspex-chain
/*  vectors  %json  /protocol/vectors/v1/json
|%
++  doc  ^-(json vectors)
::  ── reading the artifact ────────────────────────────────────────────
::
::  Deliberately ?> and not a soft decode. A malformed artifact is a
::  broken build, not a case to handle: the whole point of reading the
::  file is that a mismatch fails here rather than in the field.
::
++  jget
  |=  [j=json k=@t]
  ^-  json
  ?>  ?=([%o *] j)
  (~(got by p.j) k)
::
++  jarr  |=(j=json ^-((list json) ?>(?=([%a *] j) p.j)))
++  jstr  |=(j=json ^-(@t (so:dejs:format j)))
++  jnum  |=(j=json ^-(@ud (ni:dejs:format j)))
++  jbool  |=(j=json ^-(? (bo:dejs:format j)))
++  jux   |=(j=json ^-(@ux (slav %ux (jstr j))))
++  juv   |=(j=json ^-(@uv (slav %uv (jstr j))))
++  juw   |=(j=json ^-(@uw (slav %uw (jstr j))))
::
++  case-by
  |=  nm=@t
  ^-  json
  =/  hit  (skim (jarr (jget doc 'cases')) |=(j=json =(nm (jstr (jget j 'name')))))
  ?~  hit  ~|([%auspex-no-such-vector nm] !!)
  i.hit
::
::  ── the fixtures, as gen/auspex-vectors.hoon builds them ────────────
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
++  bare  |=(u=unsigned:sur ^-(msg:sur [u 0x0]))
::
++  keys-of
  |=  known=(list [who=ship lyf=@ud])
  ^-  (map [ship @ud] (unit pass))
  (malt (turn known |=([w=ship l=@ud] [[w l] `(fake-pass:auspex w)])))
::
++  verdict-of
  |=  [m=msg:sur known=(list [ship @ud])]
  ^-  verdict:sur
  =/  vs  (verify-chain:auspex (keys-of known) ~[m])
  ?~  vs  %unverified
  +.i.vs
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
++  m-three
  %-  mk
  :*  ~zod  ~zod  1  (sy ~[~zod ~nec ~bud])  'three'
      'a set of three recipients, so the treap shape is pinned'
      ''  ~2026.1.7  ~  ~
  ==
++  o-one  `octs`[5 'hello']
++  o-two  `octs`[5 'world']
++  a-one  (describe:auspex ['one.txt' 'text/plain' o-one])
++  a-two  (describe:auspex ['two.txt' 'text/plain' o-two])
++  m-attach
  %-  mk
  :*  ~zod  ~zod  1  (sy ~[~nec])  'attached'
      'two files ride inside the signature'  ''  ~2026.1.6  ~  ~[a-one a-two]
  ==
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
  |=(k=@ ^-(msg:sur (bare [`@p`k 1 (sy ~[~zod]) 'many' 'signers' '' ~2026.1.1 ~ ~])))
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
::  ── the comparisons ─────────────────────────────────────────────────
::
::  +msg-case: one signed message against its entry in the file. `jam`
::  is compared FIRST in spirit though not in order: it is the whole
::  `unsigned` noun, so a mismatch there localises the failure to field
::  order or field type before any hashing or crypto is involved.
::
++  msg-case
  |=  [nm=@t mg=msg:sur signer=ship known=(list [ship @ud])]
  ^-  tang
  =/  k  (case-by nm)
  =/  m  (jget k 'message')
  =/  u  unsigned:mg
  ;:  weld
    (expect-eq !>(nm) !>((jstr (jget k 'name'))))
    (expect-eq !>('message') !>((jstr (jget k 'kind'))))
    (expect-eq !>(`@uw`(jam u)) !>((juw (jget m 'jam'))))
    (expect-eq !>(`@ux`(id:auspex u)) !>((jux (jget m 'msg_id'))))
    (expect-eq !>((id:auspex u)) !>((juv (jget m 'msg_id_uv'))))
    (expect-eq !>(`@ux`(digest:auspex u)) !>((jux (jget m 'digest'))))
    (expect-eq !>(sig:mg) !>((jux (jget m 'sig'))))
    (expect-eq !>(`@t`(scot %p signer)) !>((jstr (jget m 'signer'))))
    %+  expect-eq
      !>  `@t`(scot %tas (verdict-of mg known))
      !>  (jstr (jget k 'verdict'))
  ==
::
++  msgs-match
  |=  [js=(list json) c=chain:sur]
  ^-  tang
  ?~  js  ?~(c ~ (expect !>(|)))
  ?~  c   (expect !>(|))
  %+  weld
    ;:  weld
      (expect-eq !>(`@uw`(jam unsigned.i.c)) !>((juw (jget i.js 'jam'))))
      (expect-eq !>(`@ux`(id:auspex unsigned.i.c)) !>((jux (jget i.js 'msg_id'))))
      (expect-eq !>(`@ux`(digest:auspex unsigned.i.c)) !>((jux (jget i.js 'digest'))))
      (expect-eq !>(sig.i.c) !>((jux (jget i.js 'sig'))))
    ==
  (msgs-match t.js t.c)
::
++  chain-case
  |=  [nm=@t c=chain:sur known=(list [ship @ud])]
  ^-  tang
  =/  k  (case-by nm)
  ;:  weld
    (expect-eq !>(nm) !>((jstr (jget k 'name'))))
    (expect-eq !>('chain') !>((jstr (jget k 'kind'))))
    (expect-eq !>(`@uw`(jam c)) !>((juw (jget k 'chain_jam'))))
    (msgs-match (jarr (jget k 'messages')) c)
    %+  expect-eq
      !>  (turn c |=(m=msg:sur `@t`(scot %tas (verdict-of m known))))
      !>  (turn (jarr (jget k 'verdicts')) jstr)
  ==
::
++  cap-case
  |=  [nm=@t arm=@t limit=@ud tried=@ud refused=? at-limit=?]
  ^-  tang
  =/  k  (case-by nm)
  ;:  weld
    (expect-eq !>('cap') !>((jstr (jget k 'kind'))))
    (expect-eq !>(arm) !>((jstr (jget k 'arm'))))
    (expect-eq !>(limit) !>((jnum (jget k 'limit'))))
    (expect-eq !>(tried) !>((jnum (jget k 'tried'))))
    (expect-eq !>(refused) !>((jbool (jget k 'refused'))))
    (expect-eq !>(at-limit) !>((jbool (jget k 'at_limit_accepted'))))
  ==
::
::  ── the document's own claims ───────────────────────────────────────
::
::  THE PROSE IS ASSERTED TOO, and these three fields are why. They are
::  the ones a lossy transport corrupted - `(shaf%auspex` for
::  `(shaf %auspex`, `theroot` for `the root` - and nothing noticed,
::  because nothing read them. A character lost anywhere in the file now
::  fails a test on the ship that produced it.
::
++  test-vectors-the-document-says-what-it-is
  ;:  weld
    (expect-eq !>(1) !>((jnum (jget doc 'version'))))
    (expect-eq !>('auspex-chain') !>((jstr (jget doc 'mark'))))
    (expect-eq !>('auspex') !>((jstr (jget doc 'digest_tag'))))
    (expect-eq !>('(sham unsigned)') !>((jstr (jget doc 'msg_id_rule'))))
    %+  expect-eq
      !>  '(shaf %auspex (sham unsigned))'
      !>  (jstr (jget doc 'digest_rule'))
    ::  and the tag it names is the tag the lib salts with.
    %+  expect-eq
      !>  (shaf %auspex (sham unsigned:m-root))
      !>  (digest:auspex unsigned:m-root)
    (expect-eq !>(19) !>((lent (jarr (jget doc 'cases')))))
  ==
::
::  what the file publishes as the caps IS what the lib enforces. A
::  fixture naming different numbers is a spec that has drifted from its
::  implementation, which is the failure this whole file exists to make
::  loud.
++  test-vectors-caps-block
  =/  k  (jget doc 'caps')
  ;:  weld
    (expect-eq !>(max-chain:auspex) !>((jnum (jget k 'max_chain'))))
    (expect-eq !>(max-body:auspex) !>((jnum (jget k 'max_body'))))
    (expect-eq !>(max-subj:auspex) !>((jnum (jget k 'max_subj'))))
    (expect-eq !>(max-to:auspex) !>((jnum (jget k 'max_to'))))
    (expect-eq !>(max-copies:auspex) !>((jnum (jget k 'max_copies'))))
    (expect-eq !>(max-threads:auspex) !>((jnum (jget k 'max_threads'))))
    (expect-eq !>(max-depth:auspex) !>((jnum (jget k 'max_depth'))))
    (expect-eq !>(max-signers:auspex) !>((jnum (jget k 'max_signers'))))
    (expect-eq !>(max-blob:auspex) !>((jnum (jget k 'max_blob'))))
    (expect-eq !>(max-attach:auspex) !>((jnum (jget k 'max_attach'))))
    (expect-eq !>(max-name:auspex) !>((jnum (jget k 'max_name'))))
    (expect-eq !>(max-mime:auspex) !>((jnum (jget k 'max_mime'))))
    (expect-eq !>(max-blobs:auspex) !>((jnum (jget k 'max_blobs'))))
    (expect-eq !>(max-blob-bytes:auspex) !>((jnum (jget k 'max_blob_bytes'))))
  ==
::
::  THE SET NOUN. `to` is a (set ship) and +sham hashes the TREAP, so a
::  multi-recipient msg-id is not reproducible from a list of ships: it
::  depends on a shape nothing in the format describes unless the format
::  describes the treap. The mugs are the priorities the heap is ordered
::  by, and the jam is the noun itself.
++  test-vectors-the-set-noun
  =/  k  (jget doc 'set_noun')
  =/  s3  (sy ~[~zod ~nec ~bud])
  ;:  weld
    (expect-eq !>(`@uw`(jam s3)) !>((juw (jget k 'jam'))))
    (expect-eq !>(`@ux`(jam s3)) !>((jux (jget k 'jam_ux'))))
    (expect-eq !>(`@uw`(jam *(set ship))) !>((juw (jget k 'empty_jam'))))
    ::  the mugs, in the order the file lists the ships.
    %+  expect-eq
      !>  ~[`@ud`(mug ~zod) `@ud`(mug ~nec) `@ud`(mug ~bud)]
      !>  (turn (jarr (jget k 'ships')) |=(j=json (jnum (jget j 'mug'))))
    ::  and it is CANONICAL: the same set whatever order it was built in,
    ::  which is what makes a msg-id agree between two ships that typed
    ::  their recipients in different orders.
    (expect !>(=(s3 (sy ~[~bud ~zod ~nec]))))
    (expect !>(=(s3 (~(put in (~(put in (~(put in *(set ship)) ~bud)) ~zod)) ~nec))))
  ==
::
::  ── the signed cases ────────────────────────────────────────────────
::
++  test-vectors-root
  (msg-case 'root' m-root ~zod ~[[~zod 1]])
::
++  test-vectors-reply
  (msg-case 'reply' m-reply ~nec ~[[~nec 1]])
::
::  the SAME `unsigned` byte for byte, signed with the wrong ring. A key
::  was available and the signature failed against it, which is the whole
::  definition of %forged - and the reason a missing key must never
::  produce one.
++  test-vectors-forged-copy
  %+  weld  (msg-case 'forged-copy' m-forged ~nec ~[[~zod 1]])
  ;:  weld
    (expect !>(=((id:auspex unsigned:m-root) (id:auspex unsigned:m-forged))))
    (expect !>(!=(sig:m-root sig:m-forged)))
  ==
::
::  a GENUINE ~zod signature whose `life` names 99. The verifier holds
::  ~zod at life 1 and nothing at life 99, so the verdict is %unverified.
::  It is not a finding about the signature.
++  test-vectors-unverifiable-life
  %+  weld  (msg-case 'unverifiable-life' m-life99 ~zod ~[[~zod 1]])
  (expect-eq !>(%verified) !>((verdict-of m-life99 ~[[~zod 99]])))
::
::  THE MULTI-RECIPIENT CASE, and it is the only one that pins the treap.
::  Every other signed case here names one recipient, so a `to` built in
::  any shape at all would reproduce their ids.
++  test-vectors-three-recipients
  =/  u=unsigned:sur  unsigned:m-three
  =/  fewer=unsigned:sur  u(to (sy ~[~zod ~nec]))
  %+  weld  (msg-case 'three-recipients' m-three ~zod ~[[~zod 1]])
  ;:  weld
    (expect-eq !>(3) !>(~(wyt in to.u)))
    ::  and the id really does depend on the SET, not on a count of it -
    ::  which is the property no one-recipient case can show.
    (expect !>(!=((id:auspex u) (id:auspex fewer))))
    ::  nor on the order the recipients were typed in.
    (expect !>(=((id:auspex u) (id:auspex u(to (sy ~[~bud ~zod ~nec]))))))
  ==
::
++  test-vectors-two-attachments
  %+  weld  (msg-case 'two-attachments' m-attach ~zod ~[[~zod 1]])
  =/  b  (jarr (jget doc 'blobs'))
  ;:  weld
    (expect-eq !>((blob-hash:auspex o-one)) !>((juv (jget (snag 0 b) 'hash'))))
    (expect-eq !>((blob-hash:auspex o-two)) !>((juv (jget (snag 1 b) 'hash'))))
    (expect-eq !>(p:o-one) !>((jnum (jget (snag 0 b) 'octs_p'))))
    (expect-eq !>(`@ux`q:o-one) !>((jux (jget (snag 0 b) 'octs_q'))))
    (expect-eq !>(a-one) !>(`attachment:sur`['one.txt' 5 'text/plain' (blob-hash:auspex o-one)]))
  ==
::
::  ── the chain cases ─────────────────────────────────────────────────
::
++  test-vectors-two-branch-tree
  =/  c=chain:sur  ~[m-root m-reply m-branch]
  =/  k  (case-by 'two-branch-tree')
  =/  pc  (path-chain:auspex c (id:auspex unsigned:m-reply))
  %+  weld  (chain-case 'two-branch-tree' c ~[[~zod 1] [~nec 1] [~bud 1]])
  ;:  weld
    %+  expect-eq
      !>  `@ux`(thread-key:auspex *(map thread-id:sur thread:sur) c)
      !>  (jux (jget k 'thread_key'))
    (expect-eq !>(`@ux`i-root) !>((jux (jget k 'root_id'))))
    (expect-eq !>((distinct-ids:auspex c)) !>((jnum (jget k 'distinct_ids'))))
    (expect-eq !>((max-ancestry:auspex c)) !>((jnum (jget k 'max_ancestry'))))
    (expect-eq !>((lent pc)) !>((jnum (jget k 'path_chain_to_reply_len'))))
    ::  the sibling is absent from the forwarded path.
    %+  expect-eq
      !>  (turn pc |=(m=msg:sur `@t`(scot %ux (id:auspex unsigned.m))))
      !>  (turn (jarr (jget k 'path_chain_to_reply')) jstr)
  ==
::
++  test-vectors-same-id-pair
  =/  c=chain:sur  ~[m-root m-forged]
  =/  k  (case-by 'same-id-pair')
  =/  merged  (merge:auspex ~ c)
  =/  vs  (malt (verify-chain:auspex (keys-of ~[[~zod 1]]) merged))
  =/  pruned  (prune:auspex merged vs 1)
  =/  flipped  (prune:auspex (merge:auspex ~ (flop c)) vs 1)
  %+  weld  (chain-case 'same-id-pair' c ~[[~zod 1]])
  ;:  weld
    (expect-eq !>((lent merged)) !>((jnum (jget k 'merge_kept'))))
    (expect-eq !>((lent pruned)) !>((jnum (jget k 'prune_kept'))))
    (expect !>((jbool (jget k 'same_msg_id'))))
    %+  expect-eq
      !>  (turn pruned |=(m=msg:sur `@t`(scot %ux sig.m)))
      !>  (turn (jarr (jget k 'prune_kept_sigs')) jstr)
    ::  and the same answer from the other arrival order: whichever
    ::  copy landed first, the verified one survives.
    %+  expect-eq
      !>  (turn flipped |=(m=msg:sur sig.m))
      !>  `(list @ux)`~[sig:m-root]
    %+  expect-eq
      !>  `@t`(scot %ux sig:m-root)
      !>  (jstr (jget (jget k 'prune_kept_is_genuine') 'genuine_sig'))
  ==
::
++  test-vectors-orphan-chain
  =/  c=chain:sur  ~[m-orphan]
  =/  k  (case-by 'orphan-chain')
  =/  rk  (mule |.((thread-key:auspex *(map thread-id:sur thread:sur) c)))
  %+  weld  (chain-case 'orphan-chain' c ~[[~zod 1]])
  ;:  weld
    (expect-eq !>(?=(%| -.rk)) !>((jbool (jget k 'thread_key_refused'))))
    (expect-eq !>('+thread-key') !>((jstr (jget k 'refusing_arm'))))
    (expect-eq !>('%auspex-no-unique-root') !>((jstr (jget k 'thread_key_crash'))))
    %+  expect-eq
      !>  (lent (place-of:auspex c (id:auspex unsigned:m-orphan)))
      !>  (jnum (jget k 'ancestors_place_it_as_its_own_root'))
  ==
::
::  ── the cap cases ───────────────────────────────────────────────────
::
::  every cap in the file, over the limit and AT it, recomputed here and
::  compared to what the file claims. The at-limit half is what makes
::  these bounds inclusive rather than approximately right: a cap that
::  refused its own limit would reject legitimate mail permanently,
::  because every send ships the path it replies into.
::
++  test-vectors-caps-refuse-and-admit
  =/  over-blob=attachment:sur
    ['big.bin' +(max-blob:auspex) 'application/octet-stream' 0v2]
  =/  c-over-blob=chain:sur
    ~[(bare [~zod 1 (sy ~[~nec]) 's' 'b' '' ~2026.1.1 ~ ~[over-blob]])]
  =/  c-over-body=chain:sur
    ~[(bare [~zod 1 (sy ~[~nec]) 's' (fil 3 +(max-body:auspex) 'a') '' ~2026.1.1 ~ ~])]
  =/  c-at-body=chain:sur
    ~[(bare [~zod 1 (sy ~[~nec]) 's' (fil 3 max-body:auspex 'a') '' ~2026.1.1 ~ ~])]
  =/  c-over-subj=chain:sur
    ~[(bare [~zod 1 (sy ~[~nec]) (fil 3 +(max-subj:auspex) 'a') 'b' '' ~2026.1.1 ~ ~])]
  =/  c-over-to=chain:sur
    ~[(bare [~zod 1 (ships +(max-to:auspex)) 's' 'b' '' ~2026.1.1 ~ ~])]
  =/  c-at-to=chain:sur
    ~[(bare [~zod 1 (ships max-to:auspex) 's' 'b' '' ~2026.1.1 ~ ~])]
  =/  c-over-mime=chain:sur
    ~[(bare [~zod 1 (sy ~[~nec]) 's' 'b' (fil 3 +(max-mime:auspex) 'a') ~2026.1.1 ~ ~])]
  =/  c-ctrl-mime=chain:sur
    ~[(bare [~zod 1 (sy ~[~nec]) 's' 'b' (cat 3 'text/plain' 0xd) ~2026.1.1 ~ ~])]
  =/  c-over-attach=chain:sur
    ~[(bare [~zod 1 (sy ~[~nec]) 's' 'b' '' ~2026.1.1 ~ (fat +(max-attach:auspex))])]
  =/  c-at-attach=chain:sur
    ~[(bare [~zod 1 (sy ~[~nec]) 's' 'b' '' ~2026.1.1 ~ (fat max-attach:auspex)])]
  ;:  weld
    %^  cap-case  'cap-max-chain'  '+fits-length'
    :*  max-chain:auspex  +(max-chain:auspex)
        !(fits-length:auspex (reap +(max-chain:auspex) m-root) max-chain:auspex)
        (fits-length:auspex (reap max-chain:auspex m-root) max-chain:auspex)
    ==
    %^  cap-case  'cap-max-body'  '+fits-bodies'
    :*  max-body:auspex  +(max-body:auspex)
        !(fits-bodies:auspex c-over-body max-body:auspex)
        (fits-bodies:auspex c-at-body max-body:auspex)
    ==
    %^  cap-case  'cap-max-subj'  '+fits-subjects'
    :*  max-subj:auspex  +(max-subj:auspex)
        !(fits-subjects:auspex c-over-subj max-subj:auspex)
        %.y
    ==
    %^  cap-case  'cap-max-to'  '+fits-recipients'
    :*  max-to:auspex  +(max-to:auspex)
        !(fits-recipients:auspex c-over-to max-to:auspex)
        (fits-recipients:auspex c-at-to max-to:auspex)
    ==
    %^  cap-case  'cap-max-mime-length'  '+fits-body-mimes'
    :*  max-mime:auspex  +(max-mime:auspex)
        !(fits-body-mimes:auspex c-over-mime max-mime:auspex)
        %.y
    ==
    %^  cap-case  'cap-mime-control-byte'  '+fits-body-mimes'
    :*  max-mime:auspex  11
        !(fits-body-mimes:auspex c-ctrl-mime max-mime:auspex)
        %.y
    ==
    %^  cap-case  'cap-max-attach'  '+fits-attachments'
    :*  max-attach:auspex  +(max-attach:auspex)
        !(fits-attachments:auspex c-over-attach max-attach:auspex)
        (fits-attachments:auspex c-at-attach max-attach:auspex)
    ==
    %^  cap-case  'cap-max-blob'  '+attach-ok'
    :*  max-blob:auspex  +(max-blob:auspex)
        !(fits-attachments:auspex c-over-blob max-attach:auspex)
        (attach-ok:auspex ['ok.bin' max-blob:auspex 'application/octet-stream' 0v2])
    ==
    %^  cap-case  'cap-max-depth'  '+fits-depth'
    :*  max-depth:auspex  +(max-depth:auspex)
        !(fits-depth:auspex (deep +(max-depth:auspex)) max-depth:auspex)
        (fits-depth:auspex (deep max-depth:auspex) max-depth:auspex)
    ==
    %^  cap-case  'cap-max-signers'  '+fits-signers'
    :*  max-signers:auspex  +(max-signers:auspex)
        !(fits-signers:auspex (signers-chain +(max-signers:auspex)) max-signers:auspex)
        (fits-signers:auspex (signers-chain max-signers:auspex) max-signers:auspex)
    ==
  ==
::
::  the structural cap cases carry the JAM of the offending message's
::  `unsigned`, so an implementer can rebuild the input rather than
::  being told a predicate answered %.n. The size cases carry a recipe
::  instead, because a hundred-kilobyte body jams to a hundred and
::  thirty and a fixture nine tenths one case is a file nobody reads.
++  test-vectors-cap-samples-rebuild-the-input
  =/  kd  (case-by 'cap-max-depth')
  =/  ks  (case-by 'cap-max-signers')
  =/  kb  (case-by 'cap-max-body')
  =/  dc  (deep +(max-depth:auspex))
  =/  sc  (signers-chain +(max-signers:auspex))
  ;:  weld
    (expect-eq !>((lent dc)) !>((jnum (jget kd 'sample_len'))))
    (expect-eq !>((lent sc)) !>((jnum (jget ks 'sample_len'))))
    (expect-eq !>(`@uw`(jam unsigned:(snag 0 dc))) !>((juw (jget kd 'sample_jam'))))
    (expect-eq !>(`@uw`(jam unsigned:(snag 0 sc))) !>((juw (jget ks 'sample_jam'))))
    ::  and the oversized-body case names its recipe rather than jamming
    ::  a hundred kilobytes into the fixture.
    (expect !>(?=(~ (jget kb 'sample_jam'))))
    %+  expect-eq
      !>  'the `root` unsigned with body = (fil 3 100.001 \'a\')'
      !>  (jstr (jget kb 'sample_recipe'))
  ==
::
::  ── discovery ───────────────────────────────────────────────────────
::
::  the exact noun a version-1 nexus publishes at /proto, where it is
::  bound, and where a peer reads it. This is the one assertion in the
::  suite that pins a noun BY ITS JAM, because $proto is the only noun
::  in this protocol that crosses the wire un-hashed: a peer clams what
::  it keens, so the bytes are the contract, and a field added to $proto
::  or a cap reordered inside $proto-caps changes them without changing
::  any id or digest anywhere.
++  test-vectors-proto
  =/  k  (jget doc 'proto')
  =/  q  our-proto:auspex
  ;:  weld
    (expect-eq !>(`@uw`(jam q)) !>((juw (jget k 'jam'))))
    (expect-eq !>(`@ux`(jam q)) !>((jux (jget k 'jam_ux'))))
    (expect-eq !>(`@t`(scot %tas proto-page-mark:auspex)) !>((jstr (jget k 'page_mark'))))
    (expect-eq !>(`@t`(spat proto-spur:auspex)) !>((jstr (jget k 'spur'))))
    %+  expect-eq
      !>  `@t`(spat (proto-keen-path:auspex %grubbery 1))
      !>  (jstr (jget k 'keen_path'))
    (expect-eq !>(`@t`(scot %dr proto-ttl:auspex)) !>((jstr (jget k 'ttl'))))
    (expect-eq !>(1) !>((jnum (jget k 'silent_peer_is_version'))))
    %+  expect-eq
      !>  (turn our-versions:auspex |=(v=@ud `@ud`v))
      !>  (turn (jarr (jget k 'versions')) jnum)
    %+  expect-eq
      !>  (turn our-marks:auspex |=(t=@tas `@t`t))
      !>  (turn (jarr (jget k 'marks')) jstr)
    ::  the keen path really does carry the empty knot, which is the one
    ::  segment a path literal cannot spell.
    (expect-eq !>(`@ta`'') !>((snag 4 (proto-keen-path:auspex %grubbery 1))))
    ::  a peer that publishes nothing IS version 1, which is what makes
    ::  discovery additive rather than a flag day.
    (expect-eq !>(`(unit @tas)`[~ %auspex-chain]) !>((peer-mark:auspex ~)))
  ==
--

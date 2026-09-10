::  gen/auspex-vectors: the auspex v1 conformance vectors, as JSON.
::
::    Deterministic fixtures a second implementation must reproduce. Every
::    ship named here is a FAKE ship, whose keypair derives from its @p
::    (+fake-core in the lib, mirroring jael's own %deed branch), so every
::    id, digest and signature below is reproducible on any ship, with no
::    network and no Azimuth snapshot. That is the whole reason the
::    vectors can be a fixture at all.
::
::    A GENERATOR AND NOT A THREAD, and not a dojo binding either. A
::    library bound to a dojo variable with -build-file freezes the dojo
::    against that build; a generator is rebuilt per run and holds
::    nothing.
::
::    Nothing here scries. Verdicts are computed by handing +verify-chain
::    an explicit key map, exactly as tests/lib/auspex-chain.hoon does, so
::    each case states WHICH keys the verifier holds - which is the only
::    way to write a deterministic %unverified case on a fake ship, where
::    +fake-pass ignores `life` and every life of a ship resolves to one
::    key.
::
::    Output is a %json cask, so the dojo's write sink lands the document
::    in CLAY, as a file, and the file that gets committed is the one the
::    ship produced. It used to be a %txt wain of 72-character chunks
::    meant to be read off a terminal and rejoined; that survived one
::    round trip and lost two characters on the next - the indent strip
::    ate a leading space inside a string, and the artifact in the repo
::    disagreed with the ship that made it. A fixture reassembled by hand
::    is not a fixture.
::
::    Run in the dojo, with =dir pinned to the grubbery desk at the
::    revision the |commit printed:
::
::      *%/protocol/vectors/v1/json +auspex-vectors
::
::    then copy <desk>/protocol/vectors/v1.json out of the mount. The
::    same file is synced back into the desk by scripts/sync-overlay.sh,
::    which is what lets tests/lib/auspex-vectors.hoon read the artifact
::    itself rather than a transcription of it.
::
/+  ac=auspex-chain
=>  |%
    ::  the three fake ships every vector uses.
    ::
    ++  zod  ~zod
    ++  nec  ~nec
    ++  bud  ~bud
    ::  +mk: one signed message. `signer` is the ring used; `from` is what
    ::  the message CLAIMS. They differ in exactly one case, and that case
    ::  is the definition of a forgery.
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
              prev=(unit msg-id:ac)
              as=(list attachment:ac)
          ==
      ^-  msg:ac
      =/  u=unsigned:ac  [from lyf to subj body bm sent prev as]
      [u (sign-with:ac (fake-ring:ac signer) (digest:ac u))]
    ::  +unsigned-of: an unsigned with no signature at all, for the cap
    ::  cases. Every +fits-* predicate reads `unsigned` and never `sig`,
    ::  so a cap case costs no crypto.
    ::
    ++  bare
      |=  u=unsigned:ac
      ^-  msg:ac
      [u 0x0]
    ::  +keys-of: the key map a verifier is stated to hold.
    ::
    ++  keys-of
      |=  known=(list [who=ship lyf=@ud])
      ^-  (map [ship @ud] (unit pass))
      %-  malt
      %+  turn  known
      |=([w=ship l=@ud] [[w l] `(fake-pass:ac w)])
    ::  +verdict-of: what +verify-chain answers for one message, given
    ::  that map. Computed, never asserted.
    ::
    ++  verdict-of
      |=  [m=msg:ac known=(list [ship @ud])]
      ^-  @t
      =/  vs  (verify-chain:ac (keys-of known) ~[m])
      ?~  vs  'none'
      (scot %tas +.i.vs)
    ::  ── json ──────────────────────────────────────────────────────
    ::
    ++  caps-json
      |=  k=proto-caps:ac
      ^-  json
      %-  pairs:enjs:format
      :~  'max_blob'^(numb:enjs:format max-blob.k)
          'max_attach'^(numb:enjs:format max-attach.k)
          'max_chain'^(numb:enjs:format max-chain.k)
          'max_body'^(numb:enjs:format max-body.k)
          'max_subj'^(numb:enjs:format max-subj.k)
          'max_to'^(numb:enjs:format max-to.k)
          'max_depth'^(numb:enjs:format max-depth.k)
          'max_signers'^(numb:enjs:format max-signers.k)
          'max_mime'^(numb:enjs:format max-mime.k)
          'max_name'^(numb:enjs:format max-name.k)
      ==
    ::
    ++  attach-json
      |=  a=attachment:ac
      ^-  json
      %-  pairs:enjs:format
      :~  name+s+name.a
          size+(numb:enjs:format size.a)
          mime+s+mime.a
          hash+s+(scot %uv hash.a)
      ==
    ::
    ++  unsigned-json
      |=  u=unsigned:ac
      ^-  json
      =/  pj=json  ?~(prev.u ~ [%s (scot %ux u.prev.u)])
      %-  pairs:enjs:format
      :~  from+s+(scot %p from.u)
          life+(numb:enjs:format life.u)
          to+a+(turn ~(tap in to.u) |=(w=ship `json`[%s (scot %p w)]))
          subj+s+subj.u
          body+s+body.u
          'body_mime'^s+body-mime.u
          sent+s+(scot %da sent.u)
          prev+pj
          attachments+a+(turn attachments.u attach-json)
      ==
    ::
    ++  known-json
      |=  known=(list [who=ship lyf=@ud])
      ^-  json
      :-  %a
      %+  turn  known
      |=  [w=ship l=@ud]
      ^-  json
      (pairs:enjs:format ~[ship+s+(scot %p w) life+(numb:enjs:format l)])
    ::  +msg-json: one signed message as a case. `jam` is the whole
    ::  `unsigned` noun, so an implementer byte-compares that first and
    ::  localises a field-order or field-type bug before any hashing.
    ::
    ++  msg-json
      |=  [signer=ship m=msg:ac]
      ^-  json
      =/  u  unsigned.m
      %-  pairs:enjs:format
      :~  signer+s+(scot %p signer)
          unsigned+(unsigned-json u)
          jam+s+(scot %uw (jam u))
          'msg_id'^s+(scot %ux (id:ac u))
          'msg_id_uv'^s+(scot %uv (id:ac u))
          digest+s+(scot %ux (digest:ac u))
          sig+s+(scot %ux sig.m)
      ==
    ::
    ++  case-msg
      |=  $:  name=@t
              note=@t
              signer=ship
              m=msg:ac
              known=(list [ship @ud])
          ==
      ^-  json
      %-  pairs:enjs:format
      :~  name+s+name
          kind+s+'message'
          note+s+note
          message+(msg-json signer m)
          'known_keys'^(known-json known)
          verdict+s+(verdict-of m known)
      ==
    ::
    ++  case-chain
      |=  $:  name=@t
              note=@t
              ms=(list [signer=ship m=msg:ac])
              known=(list [ship @ud])
              extra=(list [@t json])
          ==
      ^-  json
      =/  c=chain:ac  (turn ms |=([* m=msg:ac] m))
      ::  the head is cast to (list [@t json]) BEFORE the weld. +weld is a
      ::  wet gate: handed a bare :~ literal it takes the element type from
      ::  that literal, which is a tuple of nine SPECIFIC pairs and not
      ::  [@t json], and `extra` then does not nest under it.
      =/  head=(list [@t json])
        :~  name+s+name
            kind+s+'chain'
            note+s+note
            'chain_jam'^s+(scot %uw (jam c))
            messages+a+(turn ms |=([w=ship m=msg:ac] (msg-json w m)))
            'known_keys'^(known-json known)
            verdicts+a+(turn c |=(m=msg:ac `json`[%s (verdict-of m known)]))
        ==
      (pairs:enjs:format (weld head extra))
    ::
    ::  +case-cap: one cap, over the limit and at it.
    ::
    ::    `over` is the offending chain itself, and the case carries the
    ::    JAM of its first message's `unsigned` plus the chain's length.
    ::    Without those an implementer knows a predicate answered %.n and
    ::    has no way to reconstruct the input that made it - which is the
    ::    difference between a vector and an assertion.
    ::
    ++  case-cap
      |=  $:  name=@t
              note=@t
              cap=@t
              limit=@ud
              tried=@ud
              arm=@t
              refused=?
              at-limit=?
              over=chain:ac
              recipe=@t
          ==
      ^-  json
      ::  the jam is omitted when it is bigger than the fixture it sits
      ::  in. A hundred-kilobyte body jams to about a hundred and thirty,
      ::  and a fixture file nine tenths one test case is a file nobody
      ::  reads - while "a body of 100.001 'a' bytes" reconstructs the
      ::  input exactly and fits on a line. Structural cases keep the
      ::  jam; size cases carry the recipe.
      =/  sj=json
        ?~  over  ~
        =/  jm=@  (jam unsigned.i.over)
        ?:  (gth (met 3 jm) 2.048)  ~
        [%s (scot %uw jm)]
      %-  pairs:enjs:format
      :~  name+s+name
          kind+s+'cap'
          note+s+note
          cap+s+cap
          limit+(numb:enjs:format limit)
          tried+(numb:enjs:format tried)
          arm+s+arm
          refused+b+refused
          'at_limit_accepted'^b+at-limit
          'sample_len'^(numb:enjs:format (lent over))
          'sample_jam'^sj
          'sample_recipe'^s+recipe
      ==
    ::  ── builders for the cap cases ────────────────────────────────
    ::
    ::  +deep: a linear chain n messages deep, each pointing at the one
    ::  before. Unsigned: +max-ancestry walks `prev` and never reads a
    ::  signature.
    ::
    ++  deep
      |=  n=@ud
      ^-  chain:ac
      =|  acc=chain:ac
      =/  pv=(unit msg-id:ac)  ~
      =/  i=@ud  0
      |-  ^-  chain:ac
      ?:  =(i n)  (flop acc)
      =/  u=unsigned:ac
        :*  zod  1  (sy ~[nec])  'depth'
            (crip (weld "d" (scow %ud i)))  ''
            (add ~2026.1.1 (mul i ~s1))  pv  ~
        ==
      $(i +(i), pv `(id:ac u), acc [(bare u) acc])
    ::  +signers-chain: n messages from n distinct ships, so n distinct
    ::  [ship life] pairs. What +fits-signers counts.
    ::
    ++  signers-chain
      |=  n=@ud
      ^-  chain:ac
      %+  turn  (gulf 1 n)
      |=  k=@
      ^-  msg:ac
      (bare [`@p`k 1 (sy ~[zod]) 'many' 'signers' '' ~2026.1.1 ~ ~])
    ::  +ships: n distinct ships, as a set.
    ::
    ++  ships
      |=  n=@ud
      ^-  (set ship)
      (~(gas in *(set ship)) (turn (gulf 1 n) |=(k=@ `@p`k)))
    ::  +fat: an attachment list of n entries, each inside every cap.
    ::
    ++  fat
      |=  n=@ud
      ^-  (list attachment:ac)
      (turn (gulf 1 n) |=(k=@ `attachment:ac`['f' 1 'text/plain' `@uv`k]))
    --
:-  %say
|=  *
::  ── the fixtures ────────────────────────────────────────────────────
::
::  A. the root. prev=~, so this is what a thread's identity derives from.
=/  m-root=msg:ac
  (mk zod zod 1 (sy ~[nec]) 'root' 'the root message' '' ~2026.1.1 ~ ~)
=/  i-root=msg-id:ac  (id:ac unsigned.m-root)
::  B. a reply, prev = the root's id.
=/  m-reply=msg:ac
  (mk nec nec 1 (sy ~[zod]) 'reply' 'the first branch' '' ~2026.1.2 `i-root ~)
::  C. a second reply to the SAME root: two branches, siblings.
=/  m-branch=msg:ac
  (mk bud bud 1 (sy ~[zod]) 'reply' 'the second branch' '' ~2026.1.3 `i-root ~)
=/  c-tree=chain:ac  ~[m-root m-reply m-branch]
::  D. a forged copy of the root: the SAME `unsigned` byte for byte,
::  signed with ~nec's ring while `from` still names ~zod. Same msg-id,
::  different signature - which is the entire point.
=/  m-forged=msg:ac
  (mk nec zod 1 (sy ~[nec]) 'root' 'the root message' '' ~2026.1.1 ~ ~)
::  E. the same-id pair.
=/  c-pair=chain:ac  ~[m-root m-forged]
=/  merged=chain:ac  (merge:ac ~ c-pair)
=/  vs-pair=(map [msg-id:ac @ux] verdict:ac)
  (malt (verify-chain:ac (keys-of ~[[zod 1]]) merged))
=/  pruned=chain:ac  (prune:ac merged vs-pair 1)
::  F. a message no key answers for. Signed genuinely by ~zod, and
::  `life` names 99: a verifier holding ~zod's key at life 1 has nothing
::  for [~zod 99], so the verdict is %unverified and NEVER %forged.
=/  m-life99=msg:ac
  (mk zod zod 99 (sy ~[nec]) 'rotated' 'signed under a life we lack' '' ~2026.1.4 ~ ~)
::  G. an orphan: `prev` names an id that is not in the chain, and the
::  chain therefore holds no prev=~ message at all. +thread-key refuses.
=/  m-orphan=msg:ac
  (mk zod zod 1 (sy ~[nec]) 'orphan' 'my parent is not here' '' ~2026.1.5 `0v1 ~)
=/  c-orphan=chain:ac  ~[m-orphan]
=/  tk-orphan  (mule |.((thread-key:ac *(map thread-id:ac thread:ac) c-orphan)))
=/  tk-tree    (mule |.((thread-key:ac *(map thread-id:ac thread:ac) c-tree)))
::  I. THREE RECIPIENTS. `to` is a (set ship) and `sham` hashes the
::  TREAP, so the id of a multi-recipient message depends on a noun no
::  prose describes unless it describes the treap. Every other signed
::  case here names one recipient and therefore pins nothing about it.
=/  m-three=msg:ac
  %-  mk
  :*  zod  zod  1  (sy ~[zod nec bud])  'three'
      'a set of three recipients, so the treap shape is pinned'
      ''  ~2026.1.7  ~  ~
  ==
::  H. two attachments, hashed from two fixed byte strings.
=/  o-one=octs  [5 'hello']
=/  o-two=octs  [5 'world']
=/  a-one=attachment:ac  (describe:ac ['one.txt' 'text/plain' o-one])
=/  a-two=attachment:ac  (describe:ac ['two.txt' 'text/plain' o-two])
=/  m-attach=msg:ac
  %-  mk
  :*  zod  zod  1  (sy ~[nec])  'attached'  'two files ride inside the signature'
      ''  ~2026.1.6  ~  ~[a-one a-two]
  ==
::  the over-cap fixtures.
=/  over-blob=attachment:ac  ['big.bin' +(max-blob:ac) 'application/octet-stream' 0v2]
=/  c-over-blob=chain:ac
  ~[(bare [zod 1 (sy ~[nec]) 's' 'b' '' ~2026.1.1 ~ ~[over-blob]])]
=/  c-over-attach=chain:ac
  ~[(bare [zod 1 (sy ~[nec]) 's' 'b' '' ~2026.1.1 ~ (fat +(max-attach:ac))])]
=/  c-at-attach=chain:ac
  ~[(bare [zod 1 (sy ~[nec]) 's' 'b' '' ~2026.1.1 ~ (fat max-attach:ac)])]
=/  c-over-chain=chain:ac  (reap +(max-chain:ac) m-root)
=/  c-at-chain=chain:ac    (reap max-chain:ac m-root)
=/  c-over-body=chain:ac
  ~[(bare [zod 1 (sy ~[nec]) 's' (fil 3 +(max-body:ac) 'a') '' ~2026.1.1 ~ ~])]
=/  c-at-body=chain:ac
  ~[(bare [zod 1 (sy ~[nec]) 's' (fil 3 max-body:ac 'a') '' ~2026.1.1 ~ ~])]
=/  c-over-subj=chain:ac
  ~[(bare [zod 1 (sy ~[nec]) (fil 3 +(max-subj:ac) 'a') 'b' '' ~2026.1.1 ~ ~])]
=/  c-over-to=chain:ac
  ~[(bare [zod 1 (ships +(max-to:ac)) 's' 'b' '' ~2026.1.1 ~ ~])]
=/  c-at-to=chain:ac
  ~[(bare [zod 1 (ships max-to:ac) 's' 'b' '' ~2026.1.1 ~ ~])]
=/  c-over-mime=chain:ac
  ~[(bare [zod 1 (sy ~[nec]) 's' 'b' (fil 3 +(max-mime:ac) 'a') ~2026.1.1 ~ ~])]
=/  c-ctrl-mime=chain:ac
  ~[(bare [zod 1 (sy ~[nec]) 's' 'b' (cat 3 'text/plain' 0xd) ~2026.1.1 ~ ~])]
=/  c-over-depth=chain:ac  (deep +(max-depth:ac))
=/  c-at-depth=chain:ac    (deep max-depth:ac)
=/  c-over-signers=chain:ac  (signers-chain +(max-signers:ac))
=/  c-at-signers=chain:ac    (signers-chain max-signers:ac)
::  ── the document ────────────────────────────────────────────────────
::
=/  doc=json
  %-  pairs:enjs:format
  :~  version+(numb:enjs:format 1)
      mark+s+'auspex-chain'
      'digest_tag'^s+'auspex'
      'msg_id_rule'^s+'(sham unsigned)'
      'digest_rule'^s+'(shaf %auspex (sham unsigned))'
      'id_note'^s+'msg_id and msg_id_uv are one atom in two bases; prev is @ux'
      'ships_note'^s+'every ship is FAKE: its keypair is (pit:nu:cric:crypto 512 who %b ~)'
    ::
      :-  'caps'
      %-  pairs:enjs:format
      :~  'max_chain'^(numb:enjs:format max-chain:ac)
          'max_body'^(numb:enjs:format max-body:ac)
          'max_subj'^(numb:enjs:format max-subj:ac)
          'max_to'^(numb:enjs:format max-to:ac)
          'max_copies'^(numb:enjs:format max-copies:ac)
          'max_threads'^(numb:enjs:format max-threads:ac)
          'max_depth'^(numb:enjs:format max-depth:ac)
          'max_signers'^(numb:enjs:format max-signers:ac)
          'max_blob'^(numb:enjs:format max-blob:ac)
          'max_attach'^(numb:enjs:format max-attach:ac)
          'max_name'^(numb:enjs:format max-name:ac)
          'max_mime'^(numb:enjs:format max-mime:ac)
          'max_blobs'^(numb:enjs:format max-blobs:ac)
          'max_blob_bytes'^(numb:enjs:format max-blob-bytes:ac)
      ==
    ::
    ::  THE SET NOUN, pinned. `to` is a (set ship) and +sham hashes the
    ::  treap, so a msg-id is not reproducible from a list of ships
    ::  alone. The mugs are the priorities the heap is ordered by, and
    ::  the jam is the noun itself.
      :-  'set_noun'
      %-  pairs:enjs:format
      :~  'note'^s+'(sy ~[~zod ~nec ~bud]) - the noun sham hashes for `to`'
          'mold'^s+'(tree [n=ship l=nlr r=nlr]), ~ for empty'
          :-  'ships'
          :-  %a
          %+  turn  `(list ship)`~[zod nec bud]
          |=  w=ship
          ^-  json
          %-  pairs:enjs:format
          :~  'ship'^s+(scot %p w)
              'mug'^(numb:enjs:format (mug w))
          ==
          'jam'^s+(scot %uw (jam (sy ~[zod nec bud])))
          'jam_ux'^s+(scot %ux (jam (sy ~[zod nec bud])))
          'empty_jam'^s+(scot %uw (jam *(set ship)))
      ==
    ::
    ::  the discovery fixture: what a version-1 nexus publishes at
    ::  /proto, and where a peer reads it. `jam` is the noun itself, so
    ::  a second implementation byte-compares that before it compares
    ::  anything derived from it. `keen_path` carries the EMPTY SEGMENT
    ::  as `//`, which is exactly the segment a path literal cannot
    ::  spell and the one nobody notices is missing.
      :-  'proto'
      %-  pairs:enjs:format
      :~  'note'^s+'the /proto noun a version-1 nexus publishes'
          'spur'^s+(spat proto-spur:ac)
          'page_mark'^s+(scot %tas proto-page-mark:ac)
          'keen_path'^s+(spat (proto-keen-path:ac %grubbery 1))
          'keen_case'^(numb:enjs:format 1)
          'jam'^s+(scot %uw (jam our-proto:ac))
          'jam_ux'^s+(scot %ux (jam our-proto:ac))
          'versions'^a+(turn our-versions:ac |=(v=@ud `json`(numb:enjs:format v)))
          'marks'^a+(turn our-marks:ac |=(t=@tas `json`[%s t]))
          'silent_peer_is_version'^(numb:enjs:format 1)
          'ttl'^s+(scot %dr proto-ttl:ac)
          'caps'^(caps-json our-caps:ac)
      ==
    ::
      :-  'blobs'
      :-  %a
      :~  %-  pairs:enjs:format
          :~  label+s+'one'
              bytes+s+'hello'
              'octs_p'^(numb:enjs:format p.o-one)
              'octs_q'^s+(scot %ux q.o-one)
              hash+s+(scot %uv (blob-hash:ac o-one))
          ==
          %-  pairs:enjs:format
          :~  label+s+'two'
              bytes+s+'world'
              'octs_p'^(numb:enjs:format p.o-two)
              'octs_q'^s+(scot %ux q.o-two)
              hash+s+(scot %uv (blob-hash:ac o-two))
          ==
      ==
    ::
      :-  'cases'
      :-  %a
      :~
        ::  A
          %^    case-msg
              'root'
            'a thread root: prev=~, so thread identity derives from it'
          [zod m-root ~[[zod 1]]]
        ::  B
          %^    case-msg
              'reply'
            'prev names the root id, which is what makes a list a chain'
          [nec m-reply ~[[nec 1]]]
        ::  C
          %^    case-chain
              'two-branch-tree'
            'two replies to one root are SIBLINGS, not a sequence'
          :*  ~[[zod m-root] [nec m-reply] [bud m-branch]]
              ~[[zod 1] [nec 1] [bud 1]]
              :~  'thread_key'^s+(scot %ux ?:(?=(%| -.tk-tree) 0 p.tk-tree))
                  'root_id'^s+(scot %ux i-root)
                  'max_ancestry'^(numb:enjs:format (max-ancestry:ac c-tree))
                  'distinct_ids'^(numb:enjs:format (distinct-ids:ac c-tree))
                ::  a forward of the first branch ships root+branch1 and
                ::  NOT the sibling: that omission is the leak, closed.
                  :-  'path_chain_to_reply'
                  :-  %a
                  %+  turn  (path-chain:ac c-tree (id:ac unsigned.m-reply))
                  |=(m=msg:ac `json`[%s (scot %ux (id:ac unsigned.m))])
                  :-  'path_chain_to_reply_len'
                  %-  numb:enjs:format
                  (lent (path-chain:ac c-tree (id:ac unsigned.m-reply)))
              ==
          ==
        ::  D
          %^    case-msg
              'forged-copy'
            'the root unsigned byte for byte, signed with ~nec ring: %forged'
          [nec m-forged ~[[zod 1]]]
        ::  E
          %^    case-chain
              'same-id-pair'
            'one id, two signatures: +merge keeps both, +prune keeps the verified'
          :*  ~[[zod m-root] [nec m-forged]]
              ~[[zod 1]]
              :~  'same_msg_id'^b+=((id:ac unsigned.m-root) (id:ac unsigned.m-forged))
                  'merge_kept'^(numb:enjs:format (lent merged))
                  'prune_max_copies'^(numb:enjs:format 1)
                  'prune_kept'^(numb:enjs:format (lent pruned))
                  :-  'prune_kept_sigs'
                  :-  %a
                  (turn pruned |=(m=msg:ac `json`[%s (scot %ux sig.m)]))
                  :-  'prune_kept_is_genuine'
                  %-  pairs:enjs:format
                  :~  'genuine_sig'^s+(scot %ux sig.m-root)
                      'forged_sig'^s+(scot %ux sig.m-forged)
                  ==
              ==
          ==
        ::  F
          %^    case-msg
              'unverifiable-life'
            'genuine signature, life=99, verifier holds only life 1: %unverified'
          [zod m-life99 ~[[zod 1]]]
        ::  G
          %^    case-chain
              'orphan-chain'
            'prev names an id absent from the chain, so there is no prev=~ root'
          :*  ~[[zod m-orphan]]
              ~[[zod 1]]
              :~  'thread_key_refused'^b+?=(%| -.tk-orphan)
                  'thread_key_crash'^s+'%auspex-no-unique-root'
                  'refusing_arm'^s+'+thread-key'
                  :-  'ancestors_place_it_as_its_own_root'
                  %-  numb:enjs:format
                  (lent (place-of:ac c-orphan (id:ac unsigned.m-orphan)))
              ==
          ==
        ::  I
          %^    case-msg
              'three-recipients'
            'to is a (set ship): the treap noun is what sham hashes'
          [zod m-three ~[[zod 1]]]
        ::  H
          %^    case-msg
              'two-attachments'
            'metadata inside the signature; hashes are (sham octs) over the bytes'
          [zod m-attach ~[[zod 1]]]
      ::  ── the caps ──────────────────────────────────────────────────
          %^    case-cap
              'cap-max-chain'
            'a chain longer than max-chain is refused whole, never truncated'
          :*  'max-chain'  max-chain:ac  +(max-chain:ac)  '+fits-length'
              !(fits-length:ac c-over-chain max-chain:ac)
              (fits-length:ac c-at-chain max-chain:ac)
              c-over-chain
              'a chain of 1.001 copies of the `root` case above'
          ==
          %^    case-cap
              'cap-max-body'
            'body measured with (met 3 body)'
          :*  'max-body'  max-body:ac  +(max-body:ac)  '+fits-bodies'
              !(fits-bodies:ac c-over-body max-body:ac)
              (fits-bodies:ac c-at-body max-body:ac)
              c-over-body
              'the `root` unsigned with body = (fil 3 100.001 \'a\')'
          ==
          %^    case-cap
              'cap-max-subj'
            'subject measured with (met 3 subj)'
          :*  'max-subj'  max-subj:ac  +(max-subj:ac)  '+fits-subjects'
              !(fits-subjects:ac c-over-subj max-subj:ac)
              %.y
              c-over-subj
              'the `root` unsigned with subj = (fil 3 1.001 \'a\')'
          ==
          %^    case-cap
              'cap-max-to'
            'visible recipients per message'
          :*  'max-to'  max-to:ac  +(max-to:ac)  '+fits-recipients'
              !(fits-recipients:ac c-over-to max-to:ac)
              (fits-recipients:ac c-at-to max-to:ac)
              c-over-to
              'the `root` unsigned with to = (sy (turn (gulf 1 101) |=(k=@ `@p`k)))'
          ==
          %^    case-cap
              'cap-max-mime-length'
            'body-mime is a signed field a recipient cannot repair'
          :*  'max-mime'  max-mime:ac  +(max-mime:ac)  '+fits-body-mimes'
              !(fits-body-mimes:ac c-over-mime max-mime:ac)
              %.y
              c-over-mime
              'the `root` unsigned with body-mime = (fil 3 129 \'a\')'
          ==
          %^    case-cap
              'cap-mime-control-byte'
            'a CR in body-mime is a header-injection primitive: refused'
          :*  'max-mime'  max-mime:ac  11  '+fits-body-mimes'
              !(fits-body-mimes:ac c-ctrl-mime max-mime:ac)
              %.y
              c-ctrl-mime
              'the `root` unsigned with body-mime = (cat 3 \'text/plain\' 0xd)'
          ==
          %^    case-cap
              'cap-max-attach'
            'attachments per message, on a DELIVERED chain'
          :*  'max-attach'  max-attach:ac  +(max-attach:ac)  '+fits-attachments'
              !(fits-attachments:ac c-over-attach max-attach:ac)
              (fits-attachments:ac c-at-attach max-attach:ac)
              c-over-attach
              'the `root` unsigned with 17 attachments, each [\'f\' 1 \'text/plain\' 0v<n>]'
          ==
          %^    case-cap
              'cap-max-blob'
            'a claimed size over max-blob is refused at the boundary'
          :*  'max-blob'  max-blob:ac  +(max-blob:ac)  '+attach-ok'
              !(fits-attachments:ac c-over-blob max-attach:ac)
              (attach-ok:ac ['ok.bin' max-blob:ac 'application/octet-stream' 0v2])
              c-over-blob
              'the `root` unsigned with one attachment of size 262.145'
          ==
          %^    case-cap
              'cap-max-depth'
            'the deepest root-to-leaf path, checked on the poke AND the merge'
          :*  'max-depth'  max-depth:ac  +(max-depth:ac)  '+fits-depth'
              !(fits-depth:ac c-over-depth max-depth:ac)
              (fits-depth:ac c-at-depth max-depth:ac)
              c-over-depth
              'a linear chain 65 deep, each message prev-pointing at the one before'
          ==
          %^    case-cap
              'cap-max-signers'
            'distinct [ship life] pairs: one key lookup each'
          :*  'max-signers'  max-signers:ac  +(max-signers:ac)  '+fits-signers'
              !(fits-signers:ac c-over-signers max-signers:ac)
              (fits-signers:ac c-at-signers max-signers:ac)
              c-over-signers
              '129 messages, each from a distinct ship 1..129 at life 1'
          ==
      ==
  ==
[%json doc]

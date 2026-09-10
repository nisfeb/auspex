::  mar/auspex/proto: WHAT THIS NEXUS SPEAKS, at /proto.
::
::    One grub, laid by an %over row so a redeploy replaces it, and grown
::    into gall's remote-scry farm at /auspex/proto so that ANY ship may
::    keen it - the same permissionless read an attachment's bytes get,
::    for the same reason: the reader is not checked because there is
::    nothing here worth checking a reader for.
::
::    It exists because a poke of a mark the far end does not carry
::    PARKS. A blot with no marc never acks, so a peer running a
::    different Auspex, a peer running none, and a peer that is merely
::    offline are three different facts wearing one symptom. Publishing
::    what we speak turns two of those three into an error a person can
::    act on before the poke is sent.
::
::    Noun passthrough, like every other marc here. A TYPED marc would
::    re-validate this grub against the live type on every read, so
::    adding a version to $proto would boom the grub already on disk -
::    which is the one thing a compatibility mechanism must not do.
::
::    The json grow is for a human reading the tree, and for nothing
::    else: no route consumes it and no peer sees it. A peer reads the
::    NOUN, out of the farm.
::
/<  uc  /lib/auspex-chain.hoon
|_  n=*
++  grad  %noun
++  grow
  |%
  ++  noun  n
  ++  json
    ^-  ^json
    =/  res  (mule |.(;;(proto:uc n)))
    ?:  ?=(%| -.res)  [%s 'unreadable']
    =/  p  p.res
    %-  pairs:enjs:format
    :~  ['who' [%s 'auspex']]
        ['versions' [%a (turn versions.p |=(v=@ud `^json`(numb:enjs:format v)))]]
        ['marks' [%a (turn marks.p |=(t=@tas `^json`[%s t]))]]
        :-  'caps'
        %-  pairs:enjs:format
        :~  ['maxBlob' (numb:enjs:format max-blob.caps.p)]
            ['maxAttach' (numb:enjs:format max-attach.caps.p)]
            ['maxChain' (numb:enjs:format max-chain.caps.p)]
            ['maxBody' (numb:enjs:format max-body.caps.p)]
            ['maxSubj' (numb:enjs:format max-subj.caps.p)]
            ['maxTo' (numb:enjs:format max-to.caps.p)]
            ['maxDepth' (numb:enjs:format max-depth.caps.p)]
            ['maxSigners' (numb:enjs:format max-signers.caps.p)]
            ['maxMime' (numb:enjs:format max-mime.caps.p)]
            ['maxName' (numb:enjs:format max-name.caps.p)]
        ==
    ==
  --
++  grab
  |%
  ++  noun  *
  --
--

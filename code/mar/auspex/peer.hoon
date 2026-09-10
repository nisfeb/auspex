::  mar/auspex/peer: ONE CACHED DISCOVERY ANSWER.
::
::    LOCAL STATE and nothing else. It never travels inside a message, no
::    signature covers it, no verdict depends on it, and two ships may
::    hold different records for the same third ship without either
::    being wrong - a record is a snapshot of what that ship published
::    at `asked`.
::
::    TWO ROADS, ONE SHAPE, and that is deliberate rather than thrifty:
::
::      /mail/peer/<ship>   the cache. What we last learned, believed
::                          for +proto-ttl.
::      /probe/<ship>       one EPHEMERAL fiber's state, holding the
::                          same record with proto=~ - the question
::                          rather than the answer.
::
::    The probe fiber reads its own grub, keens, and pokes the completed
::    record at the writer, which is also THIS shape at blot
::    [/auspex %peer]. One ladder covers the stored grub, the fiber's
::    state and the wire poke, so there is no second shape to keep in
::    step with the first, and `who` rides inside the record rather than
::    being read back off the road it came from.
::
::    The probe is ephemeral for exactly the reason +do-fetch-blob's is:
::    a keen is a network round trip, the writer is this ship's single
::    serialisation point for mail, and a timed-out keen leaves a late
::    response and a stray %veto behind. That debris must land on a
::    process about to be culled.
::
::    Noun passthrough, like every other marc here.
::
/<  uc  /lib/auspex-chain.hoon
|_  n=*
++  grad  %noun
++  grow
  |%
  ++  noun  n
  ++  json
    ^-  ^json
    =/  res  (mule |.(;;(peer-rec:uc n)))
    ?:  ?=(%| -.res)  [%s 'unreadable']
    =/  r  p.res
    %-  pairs:enjs:format
    :~  ['who' [%s (scot %p who.r)]]
        ['asked' [%s (scot %da asked.r)]]
        :-  'versions'
        ?~  proto.r  ~
        [%a (turn versions.u.proto.r |=(v=@ud `^json`(numb:enjs:format v)))]
        ['answered' [%b ?=(^ proto.r)]]
    ==
  --
++  grab
  |%
  ++  noun  *
  --
--

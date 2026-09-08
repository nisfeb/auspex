::  mar/urmail/blob: one attachment's BYTES, at /mail/blob/<hash>.
::
::    The dumbest marc in the overlay, on purpose. A blob is bytes, the
::    grub name is their content address, and there is nothing here worth
::    a type. A marc written `|_ b=stored-blob:uc` would re-validate every
::    stored blob against the live type on every read, so the day the
::    shape moves every attachment on the ship booms and every reader
::    falls back to a bunt - which for a blob store means every file gone.
::    Noun in, noun out; the shape check is a `;;` in the nexus.
::
::    +grow json deliberately does NOT render the bytes as text. A blob is
::    arbitrary content, including content that is not a valid cord, and a
::    reader that renders it inline would be the one place a hostile
::    attachment could reach a UI. It reports the address and the length
::    and hands the bytes over as hex, which is exact and inert.
::
/<  uc  /lib/urmail-chain.hoon
|_  n=*
++  grad  %noun
++  grow
  |%
  ++  noun  n
  ++  json
    ^-  ^json
    =/  res  (mule |.(;;(stored-blob:uc n)))
    ?:  ?=(%| -.res)  [%s 'unreadable']
    =/  o  octs.p.res
    %-  pairs:enjs:format
    :~  ['size' (numb:enjs:format p.o)]
        ['hash' [%s (scot %uv (blob-hash:uc o))]]
        ['hex' [%s (scot %ux q.o)]]
    ==
  --
++  grab
  |%
  ++  noun  *
  --
--

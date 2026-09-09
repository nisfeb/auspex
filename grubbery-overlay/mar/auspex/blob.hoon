::  mar/auspex/blob: one attachment's BYTES, at /mail/blob/<hash>.
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
::    THE HEX IS LOSSY RELATIVE TO SIZE, and a decoder must left-pad it
::    to `size` bytes. It is (scot %ux q.octs) over an atom, and an atom
::    has no leading zero bytes, so a file beginning with a NUL renders
::    shorter than it is. `size` is the authority on length - it is the
::    signed field and it is inside the hash - and hex is the authority
::    on the bytes below it. Read the file as: take `size`, take the hex,
::    left-pad with zeros to `size` bytes, LITTLE-ENDIAN.
::
/<  uc  /lib/auspex-chain.hoon
|_  n=*
++  grad  %noun
++  grow
  |%
  ++  noun  n
  ++  json
    ^-  ^json
    ::  the shape ladder, newest first. A %0 blob (no arrival time) is
    ::  upgraded rather than refused: a blob's shape is covered by no
    ::  signature, so supplying a default misrepresents nothing.
    =/  o=(unit octs)
      =/  r1  (mule |.(;;(stored-blob:uc n)))
      ?:  ?=(%& -.r1)  `octs.p.r1
      =/  r0  (mule |.(;;(stored-blob-0:uc n)))
      ?:(?=(%| -.r0) ~ `octs.p.r0)
    ?~  o  [%s 'unreadable']
    %-  pairs:enjs:format
    :~  ['size' (numb:enjs:format p.u.o)]
        ['hash' [%s (scot %uv (blob-hash:uc u.o))]]
        ['hex' [%s (scot %ux q.u.o)]]
    ==
  --
++  grab
  |%
  ++  noun  *
  --
--

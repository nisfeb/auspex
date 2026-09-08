::  mar/urmail/meta: a thread's LOCAL state, at /mail/thread/<tid>/meta.
::
::    read marks, archive state and labels. None of it is signed and none
::    of it travels: two ships may disagree about every field here and
::    still agree, byte for byte, about who signed what.
::
::    Noun passthrough for the same reason as mar/urmail/msg - see that
::    file's header. Losing a read mark to a bunt fallback is survivable;
::    the rule is uniform so that no persisted path is the exception.
::
/<  uc  /lib/urmail-chain.hoon
|_  n=*
++  grad  %noun
++  grow
  |%
  ++  noun  n
  ++  json
    ^-  ^json
    =/  res  (mule |.(;;(meta:uc n)))
    ?:  ?=(%| -.res)  [%s 'unreadable']
    =/  mt  p.res
    %-  pairs:enjs:format
    :~  ['read' [%a (turn ~(tap in read.mt) |=(i=@uv `^json`[%s (scot %uv i)]))]]
        ['archived' [%b archived.mt]]
        ['labels' [%a (turn ~(tap in labels.mt) |=(t=@tas `^json`[%s t]))]]
    ==
  --
++  grab
  |%
  ++  noun  *
  --
--

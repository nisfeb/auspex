::  mar/urmail/fetchreq: one in-flight blob fetch, at /fetch/<id>.
::
::    The grub IS the fiber's state: /fetch/*'s on-file process reads it
::    with get-state-as and needs nothing passed in. Writing the request
::    is how the writer starts a fetch, and culling it is how the writer
::    ends one.
::
::    Noun passthrough like every other persisted marc here. A request
::    is ephemeral, but it can outlive a reload, and a typed marc would
::    boom a stored one the day the shape moves - which for a fiber's
::    own state means a fiber spawned onto a bunt.
::
/<  uc  /lib/urmail-chain.hoon
|_  n=*
++  grad  %noun
++  grow
  |%
  ++  noun  n
  ++  json
    ^-  ^json
    =/  res  (mule |.(;;(fetch-req:uc n)))
    ?:  ?=(%| -.res)  [%s 'unreadable']
    %-  pairs:enjs:format
    :~  ['hash' [%s (scot %uv hash.p.res)]]
        ['from' [%s (scot %p from.p.res)]]
    ==
  --
++  grab
  |%
  ++  noun  *
  --
--

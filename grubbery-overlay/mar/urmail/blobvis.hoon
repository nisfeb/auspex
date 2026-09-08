::  mar/urmail/blobvis: who may fetch each blob we hold, at /mail/blobvis.
::
::    ONE grub for every blob rather than a field beside the bytes: a blob
::    can be a quarter of a megabyte, and changing who may read a file
::    must not rewrite the file. A hash absent from the map is %public,
::    the default, so this grub stays empty until something is restricted.
::
::    Noun passthrough for the same reason as mar/urmail/blob.
::
/<  uc  /lib/urmail-chain.hoon
|_  n=*
++  grad  %noun
++  grow
  |%
  ++  noun  n
  ++  json
    ^-  ^json
    =/  res  (mule |.(;;(blob-index:uc n)))
    ?:  ?=(%| -.res)  [%s 'unreadable']
    %-  pairs:enjs:format
    %+  turn  ~(tap by vis.p.res)
    |=  [h=@uv v=blob-vis:uc]
    ^-  [@t ^json]
    :-  (scot %uv h)
    ?-  -.v
      %public      [%s 'public']
      %restricted  [%a (turn ~(tap in ships.v) |=(w=@p `^json`[%s (scot %p w)]))]
    ==
  --
++  grab
  |%
  ++  noun  *
  --
--

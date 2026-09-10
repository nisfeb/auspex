::  mar/auspex/rule: one delivery FILTER, at /mail/rule/<id>.
::
::    A rule may add labels and it may archive. There is no field here
::    for deleting, rejecting or marking read, and that absence is the
::    guarantee: a filter cannot suppress a %forged message, because the
::    shape gives it nothing to suppress with. Rules are applied AFTER
::    verification and after the chain is stored - see +file-arrival in
::    the nexus.
::
::    Noun passthrough, like every other persisted marc here.
::
/<  uc  /lib/auspex-chain.hoon
|_  n=*
++  grad  %noun
++  grow
  |%
  ++  noun  n
  ++  json
    ^-  ^json
    =/  res  (mule |.(;;(rule:uc n)))
    ?:  ?=(%| -.res)  [%s 'unreadable']
    =/  r  p.res
    %-  pairs:enjs:format
    :~  ['id' [%s (scot %uv id.r)]]
        ['from' ?~(from.r ~ [%s (scot %p u.from.r)])]
        ['subject' ?~(subject.r ~ [%s u.subject.r])]
        ['add' [%a (turn ~(tap in add.r) |=(t=@tas `^json`[%s t]))]]
        ['archive' [%b archive.r]]
    ==
  --
++  grab
  |%
  ++  noun  *
  --
--

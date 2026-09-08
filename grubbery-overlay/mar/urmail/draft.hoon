::  mar/urmail/draft: one UNSIGNED draft, at /mail/draft/<id>.
::
::    A DRAFT IS NOT A MESSAGE. It carries no author, no life, no send
::    time and no signature, because none of those exist until the
::    moment of send - and this marc is deliberately incapable of
::    producing a $msg, so nothing that renders messages can render one
::    of these by accident.
::
::    Noun passthrough for the same reason as mar/urmail/msg and
::    mar/urmail/meta: a typed marc re-validates every stored grub
::    against the live type on read, so moving the type booms every
::    draft on disk. The shape ladder lives in the nexus, under mule.
::
/<  uc  /lib/urmail-chain.hoon
|_  n=*
++  grad  %noun
++  grow
  |%
  ++  noun  n
  ++  json
    ^-  ^json
    =/  res  (mule |.(;;(draft:uc n)))
    ?:  ?=(%| -.res)  [%s 'unreadable']
    =/  d  p.res
    %-  pairs:enjs:format
    :~  ['id' [%s (scot %uv id.d)]]
        ['to' [%a (turn ~(tap in to.d) |=(s=@p `^json`[%s (scot %p s)]))]]
        ['subj' [%s subj.d]]
        ['body' [%s body.d]]
        ['prev' ?~(prev.d ~ [%s (scot %uv u.prev.d)])]
        ['at' (time:enjs:format at.d)]
    ==
  --
++  grab
  |%
  ++  noun  *
  --
--

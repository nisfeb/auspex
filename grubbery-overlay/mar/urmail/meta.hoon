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
    ::  the ladder, and it UPGRADES rather than refusing: none of this is
    ::  covered by a signature, so a %0 meta becomes a %1 with direct=%.n
    ::  and no bcc record and misrepresents nothing.
    =/  got=(unit meta:uc)
      =/  r1  (mule |.(;;(meta:uc n)))
      ?:  ?=(%& -.r1)  `p.r1
      =/  r0  (mule |.(;;(meta-0:uc n)))
      ?:(?=(%| -.r0) ~ `[%1 read.p.r0 archived.p.r0 labels.p.r0 | ~])
    ?~  got  [%s 'unreadable']
    =/  mt  u.got
    %-  pairs:enjs:format
    :~  ['read' [%a (turn ~(tap in read.mt) |=(i=@uv `^json`[%s (scot %uv i)]))]]
        ['archived' [%b archived.mt]]
        ['labels' [%a (turn ~(tap in labels.mt) |=(t=@tas `^json`[%s t]))]]
        ::  set when the thread arrived through a DELIVERY POKE. Inbox is
        ::  participant OR direct, because a BCC'd recipient is in neither
        ::  `from` nor `to` and their mail would otherwise be invisible.
        ['direct' [%b direct.mt]]
        ::  our own record of who we blind-copied. Local, never shipped,
        ::  never signed.
        :-  'bcc'
        :-  %a
        %+  turn  ~(tap by bcc.mt)
        |=  [i=@uv ws=(set @p)]
        ^-  ^json
        %-  pairs:enjs:format
        :~  ['msg' [%s (scot %uv i)]]
            ['ships' [%a (turn ~(tap in ws) |=(w=@p `^json`[%s (scot %p w)]))]]
        ==
    ==
  --
++  grab
  |%
  ++  noun  *
  --
--

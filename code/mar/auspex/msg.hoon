::  mar/auspex/msg: one stored signed copy, at /mail/thread/<tid>/msg/<slot>.
::
::    A NOUN PASSTHROUGH, deliberately. A marc written `|_ s=stored-msg:uc`
::    re-validates every stored grub against the live type on every read, so
::    the day $stored-msg gains a field every message already on disk booms
::    and every reader silently falls back to the bunt. For mail that is
::    data loss. The grub goes in and comes out as a raw noun; the nexus
::    reads it through a `;;` ladder (see +read-stored) which tries the
::    newest shape first and can upgrade an older one in place.
::
::    +grow json is the read surface for verification and for anything that
::    wants to look at a message without the nexus. It is mule-guarded for
::    the same reason: a shape it does not recognise must not crash the
::    reader, only render as unreadable.
::
/<  uc  /lib/auspex-chain.hoon
|_  n=*
++  grad  %noun
++  grow
  |%
  ++  noun  n
  ++  json
    ^-  ^json
    =/  res  (mule |.(;;(stored-msg:uc n)))
    ?:  ?=(%| -.res)  [%s 'unreadable']
    =/  s  p.res
    =/  u  unsigned.msg.s
    %-  pairs:enjs:format
    :~  ['id' [%s (scot %uv (id:uc u))]]
        ['sig' [%s (scot %ux sig.msg.s)]]
        ['from' [%s (scot %p from.u)]]
        ['life' (numb:enjs:format life.u)]
        ['to' [%a (turn ~(tap in to.u) |=(w=ship `^json`[%s (scot %p w)]))]]
        ['subject' [%s subj.u]]
        ['body' [%s body.u]]
        ::  the SIGNED rendering instruction. A renderer must match it
        ::  against a fixed allow-list and fall back to plain text for
        ::  anything else, and must never pass it into a header: the
        ::  signature proves the author chose it, not that it is safe,
        ::  and it arrives pre-signed inside a chain any ship may
        ::  deliver. Empty means text/plain.
        ['bodyMime' [%s body-mime.u]]
        ['sent' (time:enjs:format sent.u)]
        ['prev' ?~(prev.u ~ [%s (scot %uv u.prev.u)])]
        ::  attachments are INSIDE `unsigned`, so what is rendered here is
        ::  covered by the signature above it. A reader comparing the two
        ::  is checking the same bytes the verdict was computed over.
        :-  'attachments'
        :-  %a
        %+  turn  attachments.u
        |=  a=attachment:uc
        ^-  ^json
        %-  pairs:enjs:format
        :~  ['name' [%s name.a]]
            ['size' (numb:enjs:format size.a)]
            ['mime' [%s mime.a]]
            ['hash' [%s (scot %uv hash.a)]]
        ==
        ['verdict' [%s verdict.s]]
    ==
  --
++  grab
  |%
  ++  noun  *
  --
--

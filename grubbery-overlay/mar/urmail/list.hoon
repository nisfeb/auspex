::  mar/urmail/list: one MAILING LIST's members, at /mail/list/<name>.
::
::    A LIST NAME NEVER TRAVELS, and this marc is where that is easiest
::    to see: there is no `name` field here at all. The name is the path
::    segment the grub is laid under, so nothing that serialises a list
::    can put it into a message even by accident. What a recipient
::    receives is `to`, a set of ships, exactly as if each had been
::    typed by hand - which is what makes "copy the membership off this
::    month's message and overwrite the list for next month" a correct
::    operation rather than a guess: the list was never in the message,
::    so there is nothing to recover, only ships to re-save.
::
::    Local and unsigned, like mar/urmail/rule and mar/urmail/draft.
::    Nothing here is signed, nothing here is sent, and two ships may
::    hold lists of the same name with entirely different members.
::
::    Noun passthrough, like every other persisted marc here: a typed
::    marc re-validates every stored grub against the live type on read,
::    so moving the type booms every list on disk. The shape ladder
::    lives in the nexus, under mule.
::
/<  uc  /lib/urmail-chain.hoon
|_  n=*
++  grad  %noun
++  grow
  |%
  ++  noun  n
  ++  json
    ^-  ^json
    =/  res  (mule |.(;;(mail-list:uc n)))
    ?:  ?=(%| -.res)  [%s 'unreadable']
    =/  l  p.res
    %-  pairs:enjs:format
    :~  ['members' [%a (turn ~(tap in members.l) |=(s=@p `^json`[%s (scot %p s)]))]]
    ==
  --
++  grab
  |%
  ++  noun  *
  --
--

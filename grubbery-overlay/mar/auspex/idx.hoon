::  mar/auspex/idx: the derived inbox order, at /mail/idx. Newest first.
::
::    Derived rather than authoritative - every thread id in it also names
::    a directory under /mail/thread - but maintained on insert rather than
::    sorted at read time, exactly as the agent's `inbox` was.
::
::    Noun passthrough; see mar/auspex/msg for why.
::
/<  uc  /lib/auspex-chain.hoon
|_  n=*
++  grad  %noun
++  grow
  |%
  ++  noun  n
  ++  json
    ^-  ^json
    =/  res  (mule |.(;;(mail-idx:uc n)))
    ?:  ?=(%| -.res)  [%s 'unreadable']
    [%a (turn inbox.p.res |=(t=@uv `^json`[%s (scot %uv t)]))]
  --
++  grab
  |%
  ++  noun  *
  --
--

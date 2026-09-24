::  mar/auspex/settings: the owner's attachment settings, at
::  /mail/settings. Local state; never travels.
::
::    Noun passthrough for the same reason as mar/auspex/msg - see that
::    file's header. The nexus reads it back through a `;;` and falls
::    back to the defaults, which download nothing on their own.
::
/<  uc  /lib/auspex-chain.hoon
|_  n=*
++  grad  %noun
++  grow
  |%
  ++  noun  n
  ++  json
    ^-  ^json
    =/  got=(unit settings:uc)  (mole |.(;;(settings:uc n)))
    ?~  got  [%s 'unreadable']
    (settings-json:uc u.got)
  --
++  grab
  |%
  ++  noun  *
  --
--

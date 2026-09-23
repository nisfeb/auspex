::  mar/auspex/draft: one UNSIGNED draft, at /mail/draft/<id>.
::
::    A DRAFT IS NOT A MESSAGE. It carries no author, no life, no send
::    time and no signature, because none of those exist until the
::    moment of send - and this marc is deliberately incapable of
::    producing a $msg, so nothing that renders messages can render one
::    of these by accident.
::
::    Noun passthrough for the same reason as mar/auspex/msg and
::    mar/auspex/meta: a typed marc re-validates every stored grub
::    against the live type on read, so moving the type booms every
::    draft on disk. The shape ladder lives in the nexus, under mule.
::
/<  uc  /lib/auspex-chain.hoon
|_  n=*
++  grad  %noun
++  grow
  |%
  ++  noun  n
  ++  json
    ^-  ^json
    ::  the same renderer /api/drafts answers with.
    (fall (bind (mole |.(;;(draft:uc n))) draft-json:uc) [%s 'unreadable'])
  --
++  grab
  |%
  ++  noun  *
  --
--

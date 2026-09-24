::  mar/auspex/meta: a thread's LOCAL state, at /mail/thread/<tid>/meta.
::
::    read marks, archive state, labels and folds. None of it is signed and none
::    of it travels: two ships may disagree about every field here and
::    still agree, byte for byte, about who signed what.
::
::    Noun passthrough for the same reason as mar/auspex/msg - see that
::    file's header. Losing a read mark to a bunt fallback is survivable;
::    the rule is uniform so that no persisted path is the exception.
::
/<  uc  /lib/auspex-chain.hoon
|_  n=*
++  grad  %noun
++  grow
  |%
  ++  noun  n
  ++  json
    ^-  ^json
    ::  the nexus's own ladder, which UPGRADES rather than refusing: none
    ::  of this is covered by a signature.
    =/  got=(unit meta:uc)  (meta-from-noun:uc n)
    ?~  got  [%s 'unreadable']
    =/  mt  u.got
    %-  pairs:enjs:format
    :~  ['read' (ids-json:uc read.mt)]
        ['archived' [%b archived.mt]]
        ['labels' (labels-json:uc labels.mt)]
        ::  set when the thread arrived through a DELIVERY POKE. Inbox is
        ::  participant OR direct, because a BCC'd recipient is in neither
        ::  `from` nor `to` and their mail would otherwise be invisible.
        ['direct' [%b direct.mt]]
        ['folded' (ids-json:uc folded.mt)]
    ==
  --
++  grab
  |%
  ++  noun  *
  --
--

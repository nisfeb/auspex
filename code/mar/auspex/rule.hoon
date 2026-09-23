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
    ::  the same renderer /api/rules answers with.
    (fall (bind (mole |.(;;(rule:uc n))) rule-json:uc) [%s 'unreadable'])
  --
++  grab
  |%
  ++  noun  *
  --
--

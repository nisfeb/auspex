::  mar/auspex/probereq: ONE DISCOVERY IN FLIGHT, AND THE MAIL WAITING
::  ON IT, at /probe/<ship>.
::
::    A send to a peer this ship has never asked about does not go out
::    as version 1. It WAITS here until the probe answers, because
::    "we have not asked" is the question the version refusal exists to
::    answer, and answering it by guessing means the refusal can never
::    fire on first contact - which is the send most likely to reach a
::    ship running something else.
::
::    `pending` is a list, and the order is the contract: two sends to
::    one unknown ship can both land before the keen answers, and a
::    queue that drained backwards would deliver a reply before the
::    message it answers. See +queue-chain / +drain-queue, which are in
::    the lib and tested there precisely because the order is invisible
::    from a fiber.
::
::    Persisted with a %fall row so a crash mid-probe loses no mail: the
::    fiber respawns and drains the queue it finds.
::
::    THE SAME SHAPE IS ALSO THE DONE POKE the fiber hands the writer -
::    pending=~, `answer` what the keen found, `drained` how many it
::    actually sent. One marc and one `;;` ladder rather than two that
::    have to be kept in step, which is the reasoning mar/auspex/peer
::    already carries.
::
::    Noun passthrough, like every other marc here.
::
/<  uc  /lib/auspex-chain.hoon
|_  n=*
++  grad  %noun
++  grow
  |%
  ++  noun  n
  ++  json
    ^-  ^json
    =/  res  (mule |.(;;(probe-req:uc n)))
    ?:  ?=(%| -.res)  [%s 'unreadable']
    =/  r  p.res
    %-  pairs:enjs:format
    :~  ['who' [%s (scot %p who.r)]]
        ['asked' [%s (scot %da asked.r)]]
        ['pending' (numb:enjs:format (lent pending.r))]
        ['drained' (numb:enjs:format drained.r)]
        ['answered' [%b ?=(^ answer.r)]]
    ==
  --
++  grab
  |%
  ++  noun  *
  --
--

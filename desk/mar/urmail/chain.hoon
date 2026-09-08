::  urmail-chain: the wire format and the entire portable artifact.
::
::    The noun form is what crosses ames. The JSON form exists so a web
::    client can read a chain without anyone inventing a second
::    representation of it, per the design's Marks section.
::
::    +grab and +grow are exact inverses over `chain`: every field a
::    signature covers travels, plus the signature itself. Nothing is
::    dropped and nothing is summarised, because a chain that lost `life`
::    or `sig` on the way through JSON would no longer be verifiable, and
::    verifiability is the only reason this mark exists.
::
::    That is also why `sent` is a @da string rather than the millisecond
::    number `time:enjs:format` produces everywhere else in this desk.
::    `sent` is one of the seven fields (sham unsigned) covers, so
::    rounding it to milliseconds silently changes every id and every
::    verdict in the chain - and a real `sent` is `now.bowl`, which
::    carries sub-millisecond bits. Elsewhere ms timestamps are fine
::    because they feed a view; here they would corrupt the artifact.
::
/-  sur=urmail
/+  urmail
|_  =chain:sur
++  grab
  |%
  ++  noun  chain:sur
  ::  the `id` field +grow emits is deliberately NOT read back here. It is
  ::  (sham unsigned), derivable from the seven signed fields, and any
  ::  consumer of a chain must derive it rather than believe it - a chain
  ::  arriving as JSON is exactly as untrusted as one arriving over ames,
  ::  and an id read off the wire is an attacker-chosen label on someone
  ::  else's bytes. `ot` ignores keys it was not asked for, so the field
  ::  is simply passed over.
  ::
  ::  the reparsers are bound to DRY gate types (`$-`) before use, and the
  ::  array is walked with +turn rather than `ar`. Both matter: `ar`, `ot`,
  ::  `as` and `mu` are all wet gates, and writing them as one nested
  ::  expression makes the compiler re-infer the inner bodies once per
  ::  enclosing wet layer. The obvious spelling of this arm - `%-  ar` over
  ::  an inline gate holding a nested `ot` - overflows the compiler stack
  ::  on this ship: `|commit` dies with `%error-building-mark
  ::  %urmail-chain` and a `recover: dig: over`, not with a type error.
  ::  Pinning each stage to a concrete type collapses that back to one
  ::  inference per gate.
  ::
  ++  json
    |=  jon=^json
    ^-  chain:sur
    ::  `de`, not `=,  dejs:format`. `=,` puts the dejs core at the head
    ::  of the subject, and dejs's own context carries zuse's `json` MOLD
    ::  - which then sits in front of this core's `++  json` ARM. Every
    ::  `^json` after the `=,` therefore skips the mold and lands on the
    ::  arm, and what you get is a nest-fail against `chain` several lines
    ::  away from the `=,` that caused it. A plain face binding shadows
    ::  nothing. (mar/urmail/action.hoon's `=,` is safe only because its
    ::  one `^json` is written before it.)
    ::
    =/  de  dejs:format
    ::  the reparsers are bound to concrete gate types before use, and the
    ::  array is walked with +turn rather than dejs's `ar`. `ar`, `ot`,
    ::  `as` and `mu` are all wet gates, and written as one nested
    ::  expression the compiler re-infers the inner bodies once per
    ::  enclosing wet layer: the obvious spelling of this arm - `%-  ar`
    ::  over an inline gate wrapping a nested `ot` - overflows the
    ::  compiler stack on this ship, and `|commit` reports it as
    ::  `%error-building-mark %urmail-chain` with a `recover: dig: over`,
    ::  not as anything resembling a type error.
    ::
    =/  de-unsigned=$-(^json unsigned:sur)
      %-  ot:de
      :~  from+(se:de %p)
          life+ni:de
          to+(as:de (se:de %p))
          subj+so:de
          body+so:de
          sent+(se:de %da)
          prev+(mu:de (se:de %uv))
      ==
    ::  a second pass over the same object for the signature. `msg` is
    ::  [unsigned sig], not a flat eight-tuple, so one `ot` cannot make it.
    =/  de-sig=$-(^json @ux)  (ot:de ~[sig+(se:de %ux)])
    ?>  ?=([%a *] jon)
    %+  turn  p.jon
    |=(j=^json ^-(msg:sur [(de-unsigned j) (de-sig j)]))
  --
++  grow
  |%
  ++  noun  chain
  ::  not `=,  enjs:format`: composing it into lexical scope breaks type
  ::  inference for `(scot %p ...)` inside a nested `|=` on this ship's
  ::  hoon, and every ship-rendering call below is inside one. Same
  ::  reason, same workaround as app/urmail.hoon's encoders.
  ::
  ++  json
    ^-  ^json
    :-  %a
    %+  turn  chain
    |=  m=msg:sur
    ^-  ^json
    %-  pairs:enjs:format
    :~  ['id' [%s (scot %uv (id:urmail unsigned.m))]]
        ['from' [%s (scot %p from.unsigned.m)]]
        ['life' (numb:enjs:format life.unsigned.m)]
        ['to' [%a (turn ~(tap in to.unsigned.m) |=(s=ship [%s (scot %p s)]))]]
        ['subj' [%s subj.unsigned.m]]
        ['body' [%s body.unsigned.m]]
        ['sent' [%s (scot %da sent.unsigned.m)]]
        ['prev' ?~(prev.unsigned.m ~ [%s (scot %uv u.prev.unsigned.m)])]
        ['sig' [%s (scot %ux sig.m)]]
    ==
  --
++  grad  %noun
--

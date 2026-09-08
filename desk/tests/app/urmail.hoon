::  the trust boundary: anyone may hand us a chain.
::
::    +receive does not check src.bowl against the chain's participants. The
::    signatures are the authority, not the courier. This is what makes chains
::    portable, so it is tested rather than merely commented.
::
/-  sur=urmail
/+  *test-agent, urmail
/=  urmail-agent  /app/urmail
|%
::  a genuinely signed message from ~sampel-palnet to ~palnet-sampel.
::  Neither is the ship under test, and neither is the poking ship.
++  a-chain
  ^-  chain:sur
  =/  u=unsigned:sur
    [~sampel-palnet 1 (sy ~[~palnet-sampel]) 'subj' 'body' ~2026.1.1 ~]
  ~[[u (sign-with:urmail (fake-ring:urmail ~sampel-palnet) (digest:urmail u))]]
::
::  stub jael: report a fake ship, so +peer-pass takes the derivation branch
::  and never reaches %puby. An agent test has no real jael behind it.
++  fake-jael
  ^-  $-(path (unit vase))
  |=  =path
  ^-  (unit vase)
  ::  match on the %fake segment anywhere rather than on a fixed path
  ::  shape: what test-agent hands its scry gate (vane and care prefixed,
  ::  or not) is not documented, and this works either way.
  ?:  ?=(^ (find ~[%fake] path))  `!>(&)
  ~
::
++  stored
  |=  sav=vase
  ^-  @ud
  =/  st  !<(state-0:sur sav)
  ~(wyt by threads.st)
::
++  verdict-of
  |=  sav=vase
  ^-  (list verdict:sur)
  =/  st  !<(state-0:sur sav)
  ~(val by verdicts.st)
::
::  ~nobody-nobody is in neither `from` nor `to` of any message in the chain.
::  The poke must still be accepted and the signature must still verify.
++  test-accepts-chain-from-non-participant
  %-  eval-mare
  =/  m  (mare ,~)
  ;<  *          bind:m  (do-init %urmail urmail-agent)
  ;<  ~          bind:m  (set-scry-gate fake-jael)
  ;<  ~          bind:m  (set-src ~nobody-nobody)
  ;<  *          bind:m  (do-poke %urmail-chain !>(a-chain))
  ;<  sav=vase   bind:m  get-save
  ;<  ~          bind:m  (ex-equal !>((stored sav)) !>(1))
  (ex-equal !>((verdict-of sav)) !>(~[%verified]))
::
::  a chain longer than max-chain is rejected outright, not truncated
++  test-rejects-oversized-chain
  %-  eval-mare
  =/  m  (mare ,~)
  ;<  *  bind:m  (do-init %urmail urmail-agent)
  ;<  ~  bind:m  (set-scry-gate fake-jael)
  ;<  ~  bind:m  (set-src ~nobody-nobody)
  (ex-fail (do-poke %urmail-chain !>(`chain:sur`(reap 1.001 (snag 0 a-chain)))))
--

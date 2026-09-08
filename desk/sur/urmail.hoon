|%
::  $msg-id: (sham unsigned). Covers exactly what a signature covers.
::
+$  msg-id     @uv
+$  thread-id  msg-id
::
::  $verdict: verification labels a message, it never rejects one.
::
::    %verified   signature checks against the sender's registered key
::    %unverified no key available for that ship (moons, comets)
::    %forged     a key was available and the signature failed
::
+$  verdict  ?(%verified %unverified %forged)
::
::  $unsigned: everything a signature covers.
::
::    `life` travels with the message because signatures must outlive key
::    rotation: a message signed under life 3 stays verifiable after the
::    sender rotates to life 4.
::
::    `prev` is what makes a flat list a chain. A reply points at the
::    message it answers; a forward points into the chain it carries.
::
+$  unsigned
  $:  from=ship
      life=@ud
      to=(set ship)
      subj=@t
      body=@t
      sent=@da
      prev=(unit msg-id)
  ==
::
+$  msg    [=unsigned sig=@ux]
+$  chain  (list msg)
::
+$  thread
  $:  =chain
      participants=(set ship)
      last=@da
  ==
::
+$  action
  $%  [%send to=(set ship) subj=@t body=@t prev=(unit msg-id)]
      [%read =msg-id]
  ==
::
+$  state-0
  $:  %0
      threads=(map thread-id thread)
      inbox=(list thread-id)              ::  newest first
      read=(set msg-id)
      verdicts=(map [msg-id @ux] verdict)   ::  keyed [id sig], see +verify-chain
  ==
--

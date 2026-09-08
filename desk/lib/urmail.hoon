::  urmail: pure crypto and chain algebra.
::
::    Nothing here scries. Jael only answers at exactly `now`, so a scry
::    needs a live bowl, and a test arm has no bowl. Keys arrive as
::    arguments; app/urmail.hoon is the only file that fetches them.
::
/-  sur=urmail
|%
::  +digest: the preimage every urmail signature covers.
::
::    The %urmail salt is load-bearing. The same key signs ames packets
::    and attestations; salting keeps those preimage spaces disjoint so
::    an urmail signature can never be replayed as one of those.
::
++  digest
  |=  u=unsigned:sur
  ^-  @
  (shaf %urmail (sham u))
::
++  sign-with
  |=  [=ring msg=@]
  ^-  @ux
  (sigh:as:(nol:nu:cric:crypto ring) msg)
::
++  verify-with
  |=  [=pass sig=@ux msg=@]
  ^-  ?
  (safe:as:(com:nu:cric:crypto pass) sig msg)
::
::  fake ships: jael derives every keypair from the @p, so on a fake ship
::  any ship's keys are computable. This mirrors the fake branch of the
::  %deed scry in sys/vane/jael.hoon.
::
++  fake-core  |=(who=ship (pit:nu:cric:crypto 512 who %b ~))
++  fake-ring  |=(who=ship `ring`sec:ex:(fake-core who))
++  fake-pass  |=(who=ship `pass`pub:ex:(fake-core who))
--

::  mar/urmail-action: the LOCAL wire marc. Compose, reply and forward (all
::  one %send), plus %read and %delete-thread.
::
::    Reaching the writer with this blot is not itself authority: the writer
::    checks the poke's source and refuses a foreign %urmail-action, exactly
::    as the agent's `?>  =(our.bowl src.bowl)` did. The public weir grant
::    lattice-style grants a POKE ROAD, not a mark, so a peer that can
::    deliver a chain can also address this marc; the source check is what
::    stops it mattering.
::
::    Top level in gub/mar for the same addressing reason as urmail-chain,
::    and typed for the same reason: a wire format, never read back off disk.
::
/<  uc  /lib/urmail-chain.hoon
|_  act=action:uc
++  grad  %noun
++  grow
  |%
  ++  noun  act
  --
++  grab
  |%
  ++  noun  action:uc
  --
--

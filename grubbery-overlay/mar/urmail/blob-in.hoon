::  mar/urmail/blob-in: a fetch fiber's answer, poked at the writer.
::
::    TYPED, unlike the persisted marcs, and for the stated reason: this
::    is a wire format, never read back off disk, so the versioning
::    hazard that forces the others to be noun passthroughs does not
::    apply, and a malformed payload should fail at the boundary.
::
::    The blot carries a path prefix, which the agent-facing %grub-cmd
::    surface and a dojo poke cannot name - but a peer poking over ames
::    can, so the writer still checks the source, and re-checks the hash
::    whatever the source. `res` is a unit so a MISS is reported too:
::    the writer culls the request grub either way, and a failed fetch
::    leaves nothing behind to respawn.
::
/<  uc  /lib/urmail-chain.hoon
|_  b=blob-in:uc
++  grad  %noun
++  grow
  |%
  ++  noun  b
  --
++  grab
  |%
  ++  noun  blob-in:uc
  --
--

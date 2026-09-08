::  mar/urmail-chain: the wire marc. A whole signed chain, as poked at the
::  writer by any ship on the network.
::
::    Top level in gub/mar, not gub/mar/urmail/, because a blot with a path
::    prefix is unreachable from the two surfaces a peer actually uses: the
::    %grub-cmd agent surface flattens a blot to its bare name (`mark=@tas`
::    in sur/grub), and a dojo poke names a bare mark too. The delivery blot
::    has to be [/ %urmail-chain] or a foreign ship cannot address it at
::    all. The urmail- prefix is what keeps a top-level file in a shared
::    tree from shadowing grubbery's own.
::
::    TYPED, unlike the persisted marcs: this is a wire format, not stored
::    state. A malformed chain from a hostile ship should fail validation at
::    the boundary rather than reach the writer as an unchecked noun, and
::    nothing here is ever read back off disk, so the versioning hazard that
::    forces the persisted marcs to be noun passthroughs does not apply.
::
/<  uc  /lib/urmail-chain.hoon
|_  c=chain:uc
++  grad  %noun
++  grow
  |%
  ++  noun  c
  --
++  grab
  |%
  ++  noun  chain:uc
  --
--

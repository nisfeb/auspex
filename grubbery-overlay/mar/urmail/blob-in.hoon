::  mar/urmail/blob-in: a fetch fiber's answer, poked at the writer.
::
::    A NOUN PASSTHROUGH, and the reversal of an earlier decision that
::    is worth stating rather than quietly undoing.
::
::    This marc used to be TYPED, so that a malformed payload failed
::    validation at the boundary instead of reaching the writer as an
::    unchecked noun. That is sound reasoning about the wrong risk.
::    Grubbery validates a poke in +hydrate, BEFORE any nexus code
::    runs; a validation failure there fails the writer PROCESS, and
::    +rise-wait restarts a failed process by CONSUMING the next poke
::    without processing it. So a typed wire marc did not reject a bad
::    chain - it destroyed the NEXT good one, silently, with no crash
::    visible and nothing written anywhere.
::
::    /main.sig is granted to the `public` usergroup by design, so that
::    was reachable by any ship on the network for the price of one
::    malformed noun, and repeating it was a denial of delivery against
::    a mail application. Measured and reproduced; see the branching
::    slice report.
::
::    VALIDATION YOU CANNOT CATCH IS NOT VALIDATION, IT IS A FUSE. The
::    clam now lives in +apply, under mule, where a malformed payload
::    is refused the way every other cap refuses: a branch that returns
::    cleanly, with a ~| label, without failing the writer. This is the
::    same hazard as the typed persisted marcs above it - typed marcs
::    are dangerous in grubbery - arriving at a different boundary for
::    a different reason.
::
::    Do not restore the typed marc for the argument that first
::    justified it. The boundary check is real, and it is not worth
::    what it costs.
::
::    The blot carries a path prefix, which the agent-facing %grub-cmd
::    surface and a dojo poke cannot name - but a peer poking over ames
::    can, so the writer still checks the source, and re-checks the hash
::    whatever the source. `res` is a unit so a MISS is reported too:
::    the writer culls the request grub either way, and a failed fetch
::    leaves nothing behind to respawn.
::
::    No import: with the grab a bare noun, nothing here needs the
::    chain lib, and not depending on it keeps this marc from
::    rebuilding - and every stored grub from revalidating - every
::    time that lib changes.
::
|_  n=*
++  grad  %noun
++  grow
  |%
  ++  noun  n
  --
++  grab
  |%
  ++  noun  *
  --
--

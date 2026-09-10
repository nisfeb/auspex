::  mar/auspex/caps: what this instance may reach, at /caps.
::
::    One flag: `keys`, meaning "this ship may reach /sys/scry". That
::    road carries jael, which is what signing a message and checking a
::    signature both need. Under grubbery's distribution model a desk-
::    installed app is created with an EMPTY WEIR and earns each road
::    from its weir.json and the shell's consent, so this is a road a
::    user may refuse - and a refusal arrives as a VETO, which no arm
::    in lib/fiberio.hoon can catch. See $caps in the lib.
::
::    Default DENIED, and the whole reason this grub exists is that the
::    safe default cannot be the bunt: `?` bunts to %.y. +on-load lays
::    +caps-denied:uc here explicitly, on every load, and the key probe
::    raises it by proof.
::
::    Noun passthrough, like every other persisted marc here. A typed
::    marc on persistent state is a migration bomb: grubbery validates
::    in +hydrate, before any nexus code runs, so a shape change fails
::    the PROCESS rather than the value.
::
/<  uc  /lib/auspex-chain.hoon
|_  n=*
++  grad  %noun
++  grow
  |%
  ++  noun  n
  ++  json
    ^-  ^json
    =/  res  (mule |.(;;(caps:uc n)))
    ?:  ?=(%| -.res)  [%s 'unreadable']
    (pairs:enjs:format ~[['keys' [%b keys.p.res]]])
  --
++  grab
  |%
  ++  noun  *
  --
--

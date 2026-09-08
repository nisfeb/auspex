::  urmail-web: the JSON request decoders for the HTTP surface.
::
::    Everything a browser POSTs at this nexus arrives here first. That is
::    a hostile surface even on a single-user app - the routes sit behind
::    the owner gate, but a request body is still the one thing on the
::    whole HTTP path that no Hoon type has checked - so it gets the same
::    treatment as an inbound chain: parsed at the boundary, refused as a
::    whole when it does not fit, and never allowed to crash the process
::    reading it.
::
::    dejs:format CRASHES on a shape it does not like, and this runs on an
::    ephemeral request fiber. A crash there is not a lost fiber, it is an
::    HTTP connection that never gets a response: the browser hangs until
::    it times out and the user sees a Send button that never comes back.
::    So every arm here is a unit, `mule` is what makes it one, and the
::    caller answers 400.
::
::    IMPORT-FREE, and therefore testable: this is the rule the v3 spec
::    sets out ("anything worth testing goes in an import-free lib, and
::    the nexus glue may import freely"). It is also why the decoded
::    shapes below are stdlib tuples rather than $action:urmail-chain - an
::    overlay lib that imported the chain lib could only be built from the
::    nexus and could never be reached by -test. The nexus assembles the
::    action from these fields, which costs one line per route and keeps
::    the parsing where a test can see it.
::
|%
::  $send-req: the decoded POST /api/send body.
::
::    Compose, reply and forward are all this one request, exactly as they
::    are all one action: `prev` is the only thing that distinguishes them.
::
+$  send-req
  $:  to=(set ship)
      subj=@t
      body=@t
      prev=(unit @uv)
  ==
::
::  +de-send: the send body, or ~ if it is not one.
::
::    Fully qualified rather than `=,  dejs:format`. The desk build hit a
::    real compiler fault from face-injecting `format`'s children into
::    scope around ship rendering (recorded in desk/app/urmail.hoon), and
::    while that was the enjs side, the cost of qualifying is four extra
::    characters and the cost of being wrong is a build that fails on one
::    ship and not another.
::
++  de-send
  |=  jon=json
  ^-  (unit send-req)
  =/  res
    %-  mule
    |.
    ^-  send-req
    %.  jon
    %-  ot:dejs:format
    :~  to+(as:dejs:format (se:dejs:format %p))
        subj+so:dejs:format
        body+so:dejs:format
      ::  the client sends `null` for a compose. `mu` is what makes that
      ::  a missing prev rather than a parse failure.
        prev+(mu:dejs:format (se:dejs:format %uv))
    ==
  ?:(?=(%| -.res) ~ `p.res)
::
::  +de-read: {"msg-id": "0v..."} -> the id.
::
++  de-read
  |=  jon=json
  ^-  (unit @uv)
  (de-uv-field jon %'msg-id')
::
::  +de-delete: {"thread-id": "0v..."} -> the id.
::
++  de-delete
  |=  jon=json
  ^-  (unit @uv)
  (de-uv-field jon %'thread-id')
::
::  +de-uv-field: one named @uv out of an object. The two id routes differ
::  only in the key, so they are one arm and two names rather than two
::  copies of the same ladder.
::
++  de-uv-field
  |=  [jon=json key=@t]
  ^-  (unit @uv)
  =/  res
    %-  mule
    |.
    ^-  @uv
    ((ot:dejs:format ~[[key (se:dejs:format %uv)]]) jon)
  ?:(?=(%| -.res) ~ `p.res)
--

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
::  +de-read: {"msg-ids": ["0v...", ...]} -> the ids.
::
::    A SET, because opening a thread marks every unread message in it
::    at once. One id per request meant one writer poke, one writer
::    event and one full mailbox scan per message, on the ship's single
::    serialisation point for mail, to record something no peer will
::    ever see.
::
::    An empty array decodes fine and is a no-op at the writer, which is
::    what opening an already-read thread should cost.
::
++  de-read
  |=  jon=json
  ^-  (unit (set @uv))
  =/  res
    %-  mule
    |.
    ^-  (set @uv)
    %.  jon
    (ot:dejs:format ~[['msg-ids' (as:dejs:format (se:dejs:format %uv))]])
  ?:(?=(%| -.res) ~ `p.res)
::
::  +de-delete: {"thread-id": "0v..."} -> the id.
::
++  de-delete
  |=  jon=json
  ^-  (unit @uv)
  (de-uv-field jon %'thread-id')
::
::  +de-uv-field: one named @uv out of an object.
::
::
::  ── the mail-client requests ────────────────────────────────────────
::
::  Stdlib tuples, not $action:urmail-chain: this lib is IMPORT-FREE so
::  -test can reach it, and an overlay lib that imported the chain lib
::  could only be built from the nexus. The nexus assembles the action
::  from these fields, which costs one line per route and keeps the
::  parsing where a test can see it.
::
::  Labels arrive as ordinary strings and are NOT decoded as @tas here.
::  dejs has no term decoder that refuses a bad one cleanly, and a cord
::  holding a space or a capital sits in a (set @tas) perfectly happily
::  and then crashes `scot %tas` on a request fiber - an HTTP connection
::  that never answers. The nexus checks +label-ok before it stores.
::
+$  label-req  [thread-id=@uv label=@t add=?]
+$  draft-req  [id=@uv to=(set @p) subj=@t body=@t prev=(unit @uv)]
+$  rule-req   [id=@uv from=(unit @p) subject=(unit @t) add=(list @t) archive=?]
::
++  de-label
  |=  jon=json
  ^-  (unit label-req)
  =/  res
    %-  mule
    |.
    ^-  label-req
    %.  jon
    %-  ot:dejs:format
    :~  ['thread-id' (se:dejs:format %uv)]
        label+so:dejs:format
        add+bo:dejs:format
    ==
  ?:(?=(%| -.res) ~ `p.res)
::
++  de-archive
  |=  jon=json
  ^-  (unit [@uv ?])
  =/  res
    %-  mule
    |.
    ^-  [@uv ?]
    %.  jon
    (ot:dejs:format ~[['thread-id' (se:dejs:format %uv)] archived+bo:dejs:format])
  ?:(?=(%| -.res) ~ `p.res)
::
::  +de-draft: the save-draft body.
::
::    `id` is REQUIRED and comes from the client. A draft id is local,
::    means nothing on any other ship and never appears in a signature,
::    so minting it in the browser is what lets the write path stay a
::    fire-and-forget poke: the route answers when the writer takes the
::    poke, so a server-minted id could never be told to the client that
::    needs it to save the same draft again.
::
++  de-draft
  |=  jon=json
  ^-  (unit draft-req)
  =/  res
    %-  mule
    |.
    ^-  draft-req
    %.  jon
    %-  ot:dejs:format
    :~  id+(se:dejs:format %uv)
        to+(as:dejs:format (se:dejs:format %p))
        subj+so:dejs:format
        body+so:dejs:format
        prev+(mu:dejs:format (se:dejs:format %uv))
    ==
  ?:(?=(%| -.res) ~ `p.res)
::
::  +de-rule: the save-rule body. `from` and `subject` are both optional
::  and the nexus refuses a rule that sets neither - a rule with no
::  condition matches every delivered chain.
::
++  de-rule
  |=  jon=json
  ^-  (unit rule-req)
  =/  res
    %-  mule
    |.
    ^-  rule-req
    %.  jon
    %-  ot:dejs:format
    :~  id+(se:dejs:format %uv)
        from+(mu:dejs:format (se:dejs:format %p))
        subject+(mu:dejs:format so:dejs:format)
        add+(ar:dejs:format so:dejs:format)
        archive+bo:dejs:format
    ==
  ?:  ?=(%| -.res)  ~
  =/  r  p.res
  ::  AN EMPTY SUBJECT IS NOT A CONDITION, so it decodes to ~ rather
  ::  than to [~ '']. Belt to +rule-ok's braces, which refuses the same
  ::  shape at the writer: a rule whose only condition is an empty cord
  ::  fires on every delivered chain, because +has-sub answers %.y for
  ::  an empty needle by design. Normalising here means the shape is
  ::  never spelled rather than spelled and then caught.
  `r(subject ?~(subject.r ~ ?:(=('' u.subject.r) ~ subject.r)))
::
::  +de-id: {"id": "0v..."} -> the id. Shared by delete-draft,
::  send-draft and delete-rule, which differ only in what they act on.
::
++  de-id
  |=  jon=json
  ^-  (unit @uv)
  (de-uv-field jon %id)
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

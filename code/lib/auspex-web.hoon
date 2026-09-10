::  auspex-web: the JSON request decoders for the HTTP surface.
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
::    shapes below are stdlib tuples rather than $action:auspex-chain - an
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
      subject=@t
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
        subject+so:dejs:format
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
::  Stdlib tuples, not $action:auspex-chain: this lib is IMPORT-FREE so
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
+$  draft-req  [id=@uv to=(set @p) subject=@t body=@t prev=(unit @uv)]
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
        subject+so:dejs:format
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
::  ── mailing lists ───────────────────────────────────────────────────
::
::  $list-req: the decoded POST /api/list body. Create, overwrite, add a
::  member, drop one and copy-from-a-message are all this one shape,
::  because a list is a name and a set of ships and there is nothing
::  else in it to do.
::
::  The NAME IS THE KEY and becomes a path segment under /mail/list, so
::  it is checked here rather than trusted: see +list-name-ok.
::
+$  list-req  [name=@t members=(set @p)]
::
::  +list-name-ok: a list name that may be a path segment.
::
::    LOWERCASE LETTERS, DIGITS AND HYPHEN, one to sixty-four bytes.
::    Nothing else, and the reason is that this cord is used as a knot:
::    a name holding a '/' would name a different directory, one holding
::    a '.' or a space would round-trip through +scot and +slaw
::    differently from how it was written, and an empty one would name
::    the parent. The refusal is at the route with a 400, so a name a
::    user typed is refused where they can still see what they typed.
::
::    A CHARACTER ALLOW-LIST, not a blocklist of the dangerous bytes:
::    the set of things a path segment can be made to mean is not one
::    anybody enumerates correctly, and the cost of the strict rule is
::    that a list cannot be called `Groundwire`. That is a cost worth
::    paying for a name the user chooses once.
::
++  list-name-ok
  |=  n=@t
  ^-  ?
  =/  t=tape  (trip n)
  ?&  ?=(^ t)
      (lte (met 3 n) 64)
    ::  `tape`t, WIDENED. ?=(^ t) narrows t to a lest inside the rest of
    ::  this ?&, and +levy is a wet gate that fails to mull against one
    ::  - the same shape recorded against +safe-name above.
      %+  levy  `tape`t
      |=  c=@tD
      ^-  ?
      ?|  &((gte c 'a') (lte c 'z'))
          &((gte c '0') (lte c '9'))
          =(c '-')
      ==
  ==
::
::  +de-list: the save-list body, or ~ if it is not one.
::
::    `our` is passed IN rather than read, the way +de-refs takes its
::    bound: this lib is import-free and has no bowl. It is here so the
::    owner's own ship is refused as a member AT THE BOUNDARY - a list
::    that names you sends you your own mail, and every surface that
::    expands a list would then have to remember to drop you. Refusing
::    the shape once is one rule instead of one rule per call site.
::
::    An EMPTY member set decodes fine: a list you are still filling is
::    a real state.
::
++  de-list
  |=  [jon=json our=@p]
  ^-  (unit list-req)
  =/  res
    %-  mule
    |.
    ^-  list-req
    %.  jon
    %-  ot:dejs:format
    :~  name+so:dejs:format
        members+(as:dejs:format (se:dejs:format %p))
    ==
  ?:  ?=(%| -.res)  ~
  =/  r  p.res
  ?.  (list-name-ok name.r)  ~
  ?:  (~(has in members.r) our)  ~
  `r
::
::  +de-list-name: {"name": "..."} -> the name. The delete body, and the
::  same name rule as a save: a delete naming a path segment we would
::  never have written is a request about nothing.
::
++  de-list-name
  |=  jon=json
  ^-  (unit @t)
  =/  res
    %-  mule
    |.
    ^-  @t
    ((ot:dejs:format ~[[%name so:dejs:format]]) jon)
  ?:  ?=(%| -.res)  ~
  ?.  (list-name-ok p.res)  ~
  `p.res
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
::
::  ── the attachment surface ──────────────────────────────────────────
::
::  Two jobs no other part of this lib has: reading the attachments a
::  send NAMES, and getting a SIGNED, HOSTILE string into an HTTP header
::  without carrying its author's intent with it. Both are pure, so both
::  are tested.
::
::  ── the transport: raw bytes on a route of their own ────────────────
::
::    An attachment does NOT ride in this JSON. The bytes go up on their
::    own request - POST /apps/auspex/api/blob, body = the file, content
::    type application/octet-stream - which stores them and answers
::    their content address; the send that follows names those addresses
::    and carries no bytes at all. So nothing in this lib decodes a file
::    any more: the only file-shaped thing here is $up-ref, three
::    scalars.
::
::    THIS REPLACED BASE64 IN THE JSON BODY, and the reason is measured
::    rather than aesthetic. That transport needed a decoder, the
::    decoder was an interpreted loop over every character of the
::    encoding (~350K of them per max-blob file) on the request fiber
::    holding the connection open, and the sixteen-file send it has to
::    admit cost about nineteen seconds with no partial progress to show
::    for it. Raw bytes need no decoder: eyre hands the fiber an $octs
::    with a declared length, which is exactly the shape the store and
::    the hash want. See the spec under "Bytes across the HTTP surface".
::
::  $up-ref: one attachment named on a send, decoded off the wire.
::
::    NO BYTES AND NO SIZE. The bytes were uploaded already and the size
::    that gets signed is read off the stored blob, so there is nothing
::    here a client could lie about that would survive: a hash naming no
::    stored blob is a 400, and a hash naming one is measured on the
::    ship.
::
::    Structurally $attach-ref:auspex-chain, spelled out here because
::    this lib is IMPORT-FREE and may not reach that one. The nexus
::    nests one into the other; they cannot drift without the build
::    saying so.
::
+$  up-ref  [name=@t mime=@t hash=@uv]
::
::  +de-refs: the `attachments` array of a send body, or ~ if it is not
::  one.
::
::    ABSENT IS NOT MALFORMED. A send with nothing attached sends no
::    `attachments` key at all, and decodes to the empty list. A key that
::    is present and wrong is a 400, because it is a client that meant to
::    attach something and did not - answering ok there would destroy the
::    attachment silently and report success.
::
::    `most` is passed in rather than read from the chain lib's
::    +max-attach, which this lib cannot import. The nexus checks
::    +attaches-ok again on what comes back, because a check at the
::    boundary is not a substitute for one at the point of use.
::
++  de-refs
  |=  [jon=json most=@ud]
  ^-  (unit (list up-ref))
  ?.  ?=([%o *] jon)  ~
  ?~  (~(get by p.jon) 'attachments')  `~
  =/  res
    %-  mule
    |.
    ^-  (list up-ref)
    %.  jon
    %-  ot:dejs:format
    :~  :-  %attachments
        %-  ar:dejs:format
        %-  ot:dejs:format
        :~  name+so:dejs:format
            mime+so:dejs:format
            hash+(se:dejs:format %uv)
        ==
    ==
  ?:  ?=(%| -.res)  ~
  ?:  (gth (lent p.res) most)  ~
  `p.res
::
::  ── hostile signed strings, at the header boundary ──────────────────
::
::  An attachment's `name` and `mime` are SIGNED AND HOSTILE. A
::  signature proves the author chose the value, never that it is safe,
::  and the chain carrying it is delivered by whoever felt like it.
::  +text-ok refuses control bytes on the way IN, but a blob on disk may
::  have been signed and stored by a build that did not, and a recipient
::  cannot repair a signed field without destroying the evidence. So the
::  download header gets its own guard, here, and it does not care where
::  the value came from.
::
::  +ok-mimes: the only Content-Type values this ship will echo.
::
::    An ALLOW-LIST, because the failure it prevents is not a bad type
::    but a CR or an LF in the value, which splits the response and lets
::    a pre-signed string write headers of its own. A blocklist cannot
::    close that; a list of exact cords can, and does it without parsing
::    anything.
::
::    text/html and image/svg+xml are deliberately absent even though
::    every response also carries Content-Disposition: attachment. Two
::    independent reasons not to render a hostile document in the
::    owner's session is the right number.
::
++  ok-mimes
  ^-  (set @t)
  %-  ~(gas in *(set @t))
  :~  'text/plain'
      'text/csv'
      'application/json'
      'application/pdf'
      'application/zip'
      'image/png'
      'image/jpeg'
      'image/gif'
      'image/webp'
      'audio/mpeg'
      'video/mp4'
      'application/octet-stream'
  ==
::
++  safe-mime
  |=  m=@t
  ^-  @t
  ?:((~(has in ok-mimes) m) m 'application/octet-stream')
::
::  +safe-name: a filename fit for a Content-Disposition parameter.
::
::    Everything that could end the quoted string, start a new header or
::    read as a path is DROPPED rather than escaped: a quote, a
::    backslash, a semicolon, a path separator, every control byte (CR
::    and LF among them) and every byte above ASCII. When nothing
::    survives, the hash is the name - a download that saves as its own
::    content address is honest, and one that saves as `..` or as an
::    empty string is not.
::
::    THE COST, STATED: a filename written in a non-Latin script comes
::    out as the hash. RFC 6266's filename*= is the fix and it is not
::    here; dropping the bytes is what keeps this one rule with no
::    encoder to get wrong.
::
++  safe-name
  |=  [n=@t fallback=@t]
  ^-  @t
  =/  keep=tape  (name-bytes (trip n))
  =/  t=tape  (scag 128 keep)
  ?~  t  fallback
  ::  a name of nothing but dots is a path, not a name.
  ::
  ::  `tape`t, WIDENED AT THE CALL SITE. ?~ narrows t to a lest, +levy
  ::  is a wet gate, and mulling it against a lest fails on its own
  ::  internal $(a t.a) - the same shape recorded against +has-sub in
  ::  the chain lib, and it bites every wet list gate called inside a ?~.
  ?:  (levy `tape`t |=(c=@tD =(c '.')))  fallback
  (crip t)
::
++  name-bytes
  |=  a=tape
  ^-  tape
  %+  skim  a
  |=  c=@tD
  ^-  ?
  ?&  (gte c 0x20)
      (lte c 0x7e)
      !=(c '/')
      !=(c 0x5c)
      !=(c '"')
      !=(c 0x27)
      !=(c ';')
  ==
::
::  +de-fetch: {"hash":"0v...","from":"~ship"} -> the fetch request.
::
::    `from` is a HINT about where to look and nothing more. Any ship
::    holding the bytes may serve them and the hash proves them, so
::    naming the wrong ship costs a miss and never a bad blob.
::
++  de-fetch
  |=  jon=json
  ^-  (unit [hash=@uv from=@p])
  =/  res
    %-  mule
    |.
    ^-  [@uv @p]
    %.  jon
    %-  ot:dejs:format
    :~  hash+(se:dejs:format %uv)
        from+(se:dejs:format %p)
    ==
  ?:(?=(%| -.res) ~ `p.res)
--

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
::
::  ── the attachment surface ──────────────────────────────────────────
::
::  Two jobs no other part of this lib has: getting a file's BYTES off a
::  request body without losing any, and getting a SIGNED, HOSTILE
::  string into an HTTP header without carrying its author's intent
::  with it. Both are pure, so both are tested.
::
::  ── the transport, and why it is base64 in the JSON ─────────────────
::
::    /api/send already takes a JSON body, so an attachment rides in it
::    as a base64 string rather than arriving as a multipart part. The
::    alternative was measured and rejected twice over:
::
::    - eyre hands a request fiber the whole body and +de:json:html is
::      jetted, so a 32MB JSON body round-trips in ~1.3s on this ship.
::      The ceiling is nowhere near max-blob (256K, ~350K base64) even
::      with max-attach files in one send.
::    - the desk's /lib/multipart is not in gub/lib, so a nexus cannot
::      import it; and its $part carries `body=@t`, a BARE ATOM with no
::      declared length, which silently drops a file's trailing zero
::      bytes - and the content hash is then taken over the truncated
::      bytes, so the loss is invisible twice.
::
::    One transport, one decoder, no new marc, and the bytes never stop
::    being an $octs with a declared length.
::
::  $up-file: one uploaded file, decoded off the wire.
::
::    Structurally $file:urmail-chain, spelled out here because this lib
::    is IMPORT-FREE and may not reach that one. The nexus nests one
::    into the other; they cannot drift without the build saying so.
::
+$  up-file  [name=@t mime=@t =octs]
::
::  +de-files: the `files` array of a send body, or ~ if it is not one.
::
::    ABSENT IS NOT MALFORMED. Every client before this one sent no
::    `files` key at all, and a send with no attachments still does, so
::    a missing key decodes to the empty list. A key that is present and
::    wrong is a 400, because it is a client that meant to attach
::    something and did not.
::
::    `cap` and `most` are passed in rather than read from the chain
::    lib's +max-blob and +max-attach, which this lib cannot import.
::    Both are refused HERE, before any base64 is decoded, so an
::    oversized upload costs a length comparison rather than a decode -
::    and the nexus checks +files-ok again on what comes back, because a
::    check at the boundary is not a substitute for one at the point of
::    use.
::
++  de-files
  |=  [jon=json cap=@ud most=@ud]
  ^-  (unit (list up-file))
  ?.  ?=([%o *] jon)  ~
  ?~  (~(get by p.jon) 'files')  `~
  =/  res
    %-  mule
    |.
    ^-  (list [name=@t mime=@t data=@t])
    %.  jon
    %-  ot:dejs:format
    :~  :-  %files
        %-  ar:dejs:format
        %-  ot:dejs:format
        :~  name+so:dejs:format
            mime+so:dejs:format
            data+so:dejs:format
        ==
    ==
  ?:  ?=(%| -.res)  ~
  ?:  (gth (lent p.res) most)  ~
  ::  four base64 characters per three bytes, plus padding.
  (de-file-list p.res (add 4 (mul 4 (div (add cap 2) 3))))
::
++  de-file-list
  |=  [ins=(list [name=@t mime=@t data=@t]) lim=@ud]
  ^-  (unit (list up-file))
  ?~  ins  `~
  ::  MEASURED BEFORE DECODED. A body eyre accepted can be far larger
  ::  than any file this ship will store, and refusing it by the length
  ::  of its encoding costs one +met.
  ?:  (gth (met 3 data.i.ins) lim)  ~
  =/  o=(unit octs)  (de-b64 data.i.ins)
  ?~  o  ~
  ::  recursion by ARM NAME, not $. ?~ narrowed `ins` to a lest, and a
  ::  %= against that narrowing is the same widening trap +safe-name
  ::  documents below.
  =/  rest=(unit (list up-file))  (de-file-list t.ins lim)
  ?~  rest  ~
  `[[name.i.ins mime.i.ins u.o] u.rest]
::
::  +de-b64: standard base64 (padded, not url-safe) to $octs.
::
::    NOT +de:base64:mimes:html, which is `(rush a parse)` - a
::    parser-combinator sweep that turns the whole payload into a tape
::    and matches it character by character. That is the same shape the
::    desk's /lib/multipart was rewritten away from after it OOMed on
::    large uploads, and a quarter-megabyte attachment is exactly the
::    size that makes it hurt. This does the same arithmetic over jetted
::    atom ops: one +rip in, one +rep and one +swp out.
::
::    The REDUCTION is zuse's, kept line for line, because it is the
::    part that is easy to get subtly wrong: base64 is big-endian
::    within each 24-bit group and an urbit atom is little-endian, so
::    the digits are flopped before +rep, the padding bits shifted off,
::    the bytes swapped, and the result shifted back up by however many
::    LEADING ZERO BYTES the swap could not carry. `len` is computed
::    from the digit count and never from +met, which is the whole
::    reason a file ending - or beginning - in a zero byte survives.
::
++  de-b64
  |=  a=@t
  ^-  (unit octs)
  =/  cs=(list @)  (rip 3 a)
  =/  n=@ud  (lent cs)
  =/  lap=@ud
    ?:  &((gte n 2) =('=' (snag (sub n 2) cs)) =('=' (snag (dec n) cs)))  2
    ?:  &((gte n 1) =('=' (snag (dec n) cs)))  1
    0
  =/  got=(unit (list @))  (b64-digits (scag (sub n lap) cs))
  ?~  got  ~
  =/  dat=(list @)  u.got
  =/  lat=@ud  (lent dat)
  =/  dif=@ud  (~(dif fo 4) 0 lat)
  ::  padding is REQUIRED and must be exactly the missing digits. A
  ::  digit count of 4n+1 cannot be base64 at all: dif is 3 and no
  ::  amount of padding matches it.
  ?.  =(dif lap)  ~
  =/  len=@ud  (sub (mul 3 (div (add lat dif) 4)) dif)
  =/  res=@  (rsh [1 dif] (rep [0 6] (flop dat)))
  =/  amt=@ud  (met 3 res)
  =/  trl=@ud  ?:((lth len amt) 0 (sub len amt))
  ::  TRIMMED TO `len`, which is the declared length and the authority.
  ::  +file-ok refuses an octs whose atom measures MORE than it declares,
  ::  and +blob-hash hashes the pair, so a stray high byte is a file the
  ::  sender and the receiver hash differently. `len` came from the digit
  ::  count and nothing downstream may widen it.
  `[len (end [3 len] (lsh [3 trl] (swp 3 res)))]
::
++  b64-digits
  |=  cs=(list @)
  ^-  (unit (list @))
  =|  acc=(list @)
  |-  ^-  (unit (list @))
  ?~  cs  `(flop acc)
  =/  v=(unit @)  (b64-digit i.cs)
  ?~  v  ~
  $(cs t.cs, acc [u.v acc])
::
++  b64-digit
  |=  c=@
  ^-  (unit @)
  ?:  &((gte c 'A') (lte c 'Z'))  `(sub c 'A')
  ?:  &((gte c 'a') (lte c 'z'))  `(add 26 (sub c 'a'))
  ?:  &((gte c '0') (lte c '9'))  `(add 52 (sub c '0'))
  ?:  =(c '+')  `62
  ?:  =(c '/')  `63
  ~
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

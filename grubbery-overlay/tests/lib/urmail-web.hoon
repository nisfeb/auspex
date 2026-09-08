::  Unit tests for /lib/urmail-web: the JSON request decoders.
::
::    Every case a browser can produce, plus the cases only a broken or
::    hostile client produces. The point of these is the second group: a
::    dejs ladder crashes on a shape it dislikes, and a crash on a request
::    fiber is a connection that never answers, so "returns ~" is the
::    behaviour under test, not an afterthought.
::
/+  *test, web=urmail-web
|%
::  +jo: parse a JSON literal, so each case below reads as the bytes the
::  browser actually sends rather than as a hand-built $json tree.
++  jo
  |=  t=@t
  ^-  json
  (need (de:json:html t))
::
::  ── send ────────────────────────────────────────────────────────────
::
::  a compose: recipients, a subject, a body, and a null prev.
++  test-de-send-compose
  =/  got  (de-send:web (jo '{"to":["~zod","~nec"],"subj":"hi","body":"there","prev":null}'))
  ;:  weld
    %+  expect-eq
      !>  `(unit (set ship))`[~ (sy ~[~zod ~nec])]
      !>  ?~(got ~ `to.u.got)
    %+  expect-eq  !>(`(unit @t)`[~ 'hi'])  !>(?~(got ~ `subj.u.got))
    %+  expect-eq  !>(`(unit @t)`[~ 'there'])  !>(?~(got ~ `body.u.got))
  ::  a compose has no prev, and that is a successful parse with ~ in it,
  ::  not a failed one.
    %+  expect-eq  !>(`(unit (unit @uv))`[~ ~])  !>(?~(got ~ `prev.u.got))
  ==
::
::  a reply: the same body with a prev naming a message.
++  test-de-send-reply
  =/  jon  (jo '{"to":["~zod"],"subj":"re: hi","body":"yes","prev":"0v3"}')
  %+  expect-eq
    !>  `(unit (unit @uv))`[~ [~ 0v3]]
  =/  got  (de-send:web jon)
  !>  ?~(got ~ `prev.u.got)
::
::  an empty recipient list parses. It is not the decoder's job to refuse
::  it - the writer's caps are the authority on what a send may contain,
::  and a decoder that quietly enforced a second, different rule would be
::  a place for the two to disagree.
++  test-de-send-no-recipients
  %+  expect-eq
    !>  `(unit (set ship))`[~ ~]
  =/  got  (de-send:web (jo '{"to":[],"subj":"s","body":"b","prev":null}'))
  !>  ?~(got ~ `to.u.got)
::
::  ── send, refused ───────────────────────────────────────────────────
::
::  a missing field is ~, not a crash.
++  test-de-send-missing-body
  %+  expect-eq  !>(`(unit send-req:web)`~)
  !>  (de-send:web (jo '{"to":["~zod"],"subj":"s","prev":null}'))
::
::  a recipient that is not a @p is ~. This is the one field a user types
::  by hand, so it is the one that is malformed in ordinary use.
++  test-de-send-bad-recipient
  %+  expect-eq  !>(`(unit send-req:web)`~)
  !>  (de-send:web (jo '{"to":["not a ship"],"subj":"s","body":"b","prev":null}'))
::
::  a prev that is not a @uv is ~, rather than a send that silently
::  becomes a compose and starts a new thread.
++  test-de-send-bad-prev
  %+  expect-eq  !>(`(unit send-req:web)`~)
  !>  (de-send:web (jo '{"to":["~zod"],"subj":"s","body":"b","prev":"nope"}'))
::
::  a body that is a number, not a string.
++  test-de-send-wrong-type
  %+  expect-eq  !>(`(unit send-req:web)`~)
  !>  (de-send:web (jo '{"to":["~zod"],"subj":"s","body":7,"prev":null}'))
::
::  an array where an object belongs - what a client sending the wrong
::  route's payload produces.
++  test-de-send-not-an-object
  %+  expect-eq  !>(`(unit send-req:web)`~)  !>((de-send:web (jo '[1,2]')))
::
::  ── the id routes ───────────────────────────────────────────────────
::
++  test-de-read
  %+  expect-eq  !>(`(unit (set @uv))`[~ (sy ~[0v1a 0v2b])])
  !>  (de-read:web (jo '{"msg-ids":["0v1a","0v2b"]}'))
::
::  opening an already-read thread sends no ids, which decodes and is a
::  no-op at the writer rather than a 400.
++  test-de-read-empty-set
  %+  expect-eq  !>(`(unit (set @uv))`[~ ~])
  !>  (de-read:web (jo '{"msg-ids":[]}'))
::
::  a bare id where an array belongs is refused, not silently wrapped.
++  test-de-read-rejects-a-scalar
  %+  expect-eq  !>(`(unit (set @uv))`~)
  !>  (de-read:web (jo '{"msg-ids":"0v1a"}'))
::
++  test-de-delete
  %+  expect-eq  !>(`(unit @uv)`[~ 0v1a])
  !>  (de-delete:web (jo '{"thread-id":"0v1a"}'))
::
::  the two routes do NOT accept each other's key. They name different
::  things - a message and a thread - and a decoder that took either would
::  let a mis-addressed request mark a thread read or delete a message.
++  test-de-read-rejects-thread-key
  %+  expect-eq  !>(`(unit (set @uv))`~)
  !>  (de-read:web (jo '{"thread-id":"0v1a"}'))
::
++  test-de-delete-rejects-msg-key
  %+  expect-eq  !>(`(unit @uv)`~)  !>((de-delete:web (jo '{"msg-id":"0v1a"}')))
::
++  test-de-read-bad-id
  %+  expect-eq  !>(`(unit (set @uv))`~)
  !>  (de-read:web (jo '{"msg-ids":["~zod"]}'))
--

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
::
::  AN EMPTY SUBJECT DECODES TO ~, NOT TO [~ '']. The cell shape passes
::  every presence check a rule is asked, and +has-sub answers %.y for
::  an empty needle by design, so a rule carrying it fires on every
::  delivered chain. The writer refuses it too; this is what stops the
::  shape from ever being spelled.
++  test-de-rule-empty-subject-is-no-subject
  =/  got  (de-rule:web (jo '{"id":"0v1a","from":null,"subject":"","add":[],"archive":true}'))
  ;:  weld
    (expect !>(?=(^ got)))
    (expect-eq !>(`(unit @t)`~) !>(?~(got ~ subject.u.got)))
  ==
::
++  test-de-rule-keeps-a-real-subject
  =/  got  (de-rule:web (jo '{"id":"0v1a","from":null,"subject":"invoice","add":["work"],"archive":false}'))
  ;:  weld
    (expect-eq !>(`(unit @t)`[~ 'invoice']) !>(?~(got ~ subject.u.got)))
    (expect-eq !>(`(list @t)`~['work']) !>(?~(got ~ add.u.got)))
  ==
::
::  ── base64, and the byte a bare atom loses ──────────────────────────
::
++  test-de-b64-round-trips-text
  %+  expect-eq  !>(`(unit octs)`[~ [5 'hello']])
  !>  (de-b64:web 'aGVsbG8=')
::
::  THE WHOLE REASON THIS DECODER RETURNS OCTS AND NOT AN ATOM. A file
::  whose last byte is 0x00 - every ZIP-family file, whose archive
::  comment length is two zero bytes - measures SHORT as a bare atom,
::  and the truncation is silent twice over because the content hash is
::  then taken over the truncated bytes. `len` comes from the digit
::  count, never from +met, which is what carries it.
++  test-de-b64-keeps-a-trailing-zero-byte
  ::  'A' then one 0x00 byte: two bytes, one of which no atom can hold.
  %+  expect-eq  !>(`(unit octs)`[~ [2 0x41]])
  !>  (de-b64:web 'QQA=')
::
::  and a LEADING zero byte, which the byte swap cannot carry on its own
::  and which the shift back up is there to restore.
++  test-de-b64-keeps-a-leading-zero-byte
  %+  expect-eq  !>(`(unit octs)`[~ [2 0x4100]])
  !>  (de-b64:web 'AEE=')
::
++  test-de-b64-empty-is-an-empty-file
  (expect-eq !>(`(unit octs)`[~ [0 0]]) !>((de-b64:web '')))
::
::  every byte value, so no digit in the table is wrong: 0x00 through
::  0x02 exercises the padding-free case as well.
::  a four-digit group with no padding at all, whose middle byte is the
::  only nonzero one - the case where every step of the reduction has to
::  agree about where a byte went.
++  test-de-b64-decodes-an-unpadded-group
  %+  expect-eq  !>(`(unit octs)`[~ [3 0x1000]])
  !>  (de-b64:web 'ABAA')
::
::  a character outside the alphabet is a refusal, not a silently
::  dropped byte: a dropped byte moves every later byte and the file
::  still hashes to something, just not to the address it claims.
++  test-de-b64-refuses-a-bad-character
  (expect-eq !>(`(unit octs)`~) !>((de-b64:web 'aGV*bG8=')))
::
::  base64url is NOT accepted. It would decode to different bytes for
::  the same string, and nothing this route talks to emits it.
++  test-de-b64-refuses-url-alphabet
  (expect-eq !>(`(unit octs)`~) !>((de-b64:web 'a-_lbG8=')))
::
::  padding is required and must be exactly the missing digits.
++  test-de-b64-refuses-missing-padding
  (expect-eq !>(`(unit octs)`~) !>((de-b64:web 'aGVsbG8')))
::
::  a digit count of 4n+1 cannot be base64 at all: three digits are
::  missing and no amount of padding matches that.
++  test-de-b64-refuses-a-4n-plus-1-digit-count
  (expect-eq !>(`(unit octs)`~) !>((de-b64:web 'aGVsb')))
::
::  ── the files array ─────────────────────────────────────────────────
::
::  ABSENT IS NOT MALFORMED: every client before this one sends no
::  `files` key at all, and so does this one on a send with nothing
::  attached.
++  test-de-files-absent-is-empty
  %+  expect-eq  !>(`(unit (list up-file:web))`[~ ~])
  !>  (de-files:web (jo '{"to":[],"subj":"s","body":"b","prev":null}') 100 4)
::
++  test-de-files-decodes-one-file
  =/  got
    %^  de-files:web
      %-  jo
      '{"files":[{"name":"a.txt","mime":"text/plain","data":"aGk="}]}'
    100
    4
  ;:  weld
    (expect-eq !>(`(unit @ud)`[~ 1]) !>(?~(got ~ `(lent u.got))))
    %+  expect-eq  !>(`(unit up-file:web)`[~ ['a.txt' 'text/plain' 2 'hi']])
    !>  ?~(got ~ `(snag 0 u.got))
  ==
::
::  MEASURED BEFORE DECODED: the cap is applied to the ENCODED length,
::  so an oversized upload costs a +met and not a decode.
++  test-de-files-refuses-a-file-over-the-cap
  %+  expect-eq  !>(`(unit (list up-file:web))`~)
  !>  %^  de-files:web
        %-  jo
        '{"files":[{"name":"a","mime":"text/plain","data":"aGVsbG8="}]}'
      0
      4
::
++  test-de-files-refuses-too-many-files
  %+  expect-eq  !>(`(unit (list up-file:web))`~)
  !>  %^  de-files:web
        %-  jo
        %-  crip
        ;:  weld
          (trip '{"files":[{"name":"a","mime":"t","data":"aGk="},')
          (trip '{"name":"b","mime":"t","data":"aGk="}]}')
        ==
      100
      1
::
::  a `files` key that is present and wrong is a refusal, never an empty
::  list: that is a client that meant to attach something and did not,
::  and answering ok would destroy the attachment silently.
++  test-de-files-refuses-a-malformed-entry
  %+  expect-eq  !>(`(unit (list up-file:web))`~)
  !>  (de-files:web (jo '{"files":[{"name":"a"}]}') 100 4)
::
++  test-de-files-refuses-bad-base64
  %+  expect-eq  !>(`(unit (list up-file:web))`~)
  !>  %^  de-files:web
        %-  jo
        '{"files":[{"name":"a","mime":"text/plain","data":"a*k="}]}'
      100
      4
::
::  ── the header boundary ─────────────────────────────────────────────
::
++  test-safe-name-keeps-an-ordinary-name
  (expect-eq !>('report.pdf') !>((safe-name:web 'report.pdf' '0v1')))
::
::  A CRLF IN A SIGNED FILENAME IS A HEADER-INJECTION PRIMITIVE, and it
::  arrives pre-signed: +text-ok refuses it on the way in, but a blob on
::  disk may have been signed and stored by a build that did not.
++  test-safe-name-strips-a-crlf
  %+  expect-eq  !>('evilSet-Cookie: a=b')
  !>  (safe-name:web 'evil\0d\0aSet-Cookie: a=b' '0v1')
::
::  a quote would close the filename parameter; a semicolon would start
::  a new one; a separator would make it a path.
++  test-safe-name-strips-quotes-and-separators
  (expect-eq !>('abc') !>((safe-name:web '"a;/b\\c\'' '0v1')))
::
::  nothing survivable is the hash, never an empty filename.
++  test-safe-name-falls-back-when-nothing-survives
  (expect-eq !>('0vhash') !>((safe-name:web '"""' '0vhash')))
::
::  and a name of nothing but dots is a path, not a name.
++  test-safe-name-refuses-dots
  (expect-eq !>('0vhash') !>((safe-name:web '..' '0vhash')))
::
::  an allowed type is echoed; everything else is octet-stream. The
::  allow-list is the whole guard - a blocklist cannot close a value
::  carrying its own CRLF.
++  test-safe-mime-allows-a-known-type
  (expect-eq !>('image/png') !>((safe-mime:web 'image/png')))
::
::  text/html would be XSS in the owner's session if a browser ever
::  rendered it inline, which is why it is absent even though every
::  response also carries Content-Disposition: attachment.
++  test-safe-mime-refuses-html
  (expect-eq !>('application/octet-stream') !>((safe-mime:web 'text/html')))
::
++  test-safe-mime-refuses-an-injected-value
  %+  expect-eq  !>('application/octet-stream')
  !>  (safe-mime:web 'text/plain\0d\0aSet-Cookie: a=b')
::
::  even a near miss: a parameter on an allowed type is not on the list,
::  because the list is exact cords and not a parse.
++  test-safe-mime-refuses-a-parameterised-type
  %+  expect-eq  !>('application/octet-stream')
  !>  (safe-mime:web 'text/plain; charset=utf-8')
::
::  ── the fetch request ───────────────────────────────────────────────
::
++  test-de-fetch
  %+  expect-eq  !>(`(unit [@uv @p])`[~ [0v1a ~zod]])
  !>  (de-fetch:web (jo '{"hash":"0v1a","from":"~zod"}'))
::
++  test-de-fetch-needs-a-ship
  %+  expect-eq  !>(`(unit [@uv @p])`~)
  !>  (de-fetch:web (jo '{"hash":"0v1a","from":"nope"}'))
::
++  test-de-fetch-needs-a-hash
  %+  expect-eq  !>(`(unit [@uv @p])`~)
  !>  (de-fetch:web (jo '{"from":"~zod"}'))
--

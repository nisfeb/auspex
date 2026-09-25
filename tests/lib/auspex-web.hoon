::  Unit tests for /lib/auspex-web: the JSON request decoders.
::
::    Every case a browser can produce, plus the cases only a broken or
::    hostile client produces. The point of these is the second group: a
::    dejs ladder crashes on a shape it dislikes, and a crash on a request
::    fiber is a connection that never answers, so "returns ~" is the
::    behaviour under test, not an afterthought.
::
/+  *test, web=auspex-web
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
  =/  got  (de-send:web (jo '{"to":["~zod","~nec"],"subject":"hi","body":"there","prev":null}'))
  ;:  weld
    %+  expect-eq
      !>  `(unit (set ship))`[~ (sy ~[~zod ~nec])]
      !>  ?~(got ~ `to.u.got)
    %+  expect-eq  !>(`(unit @t)`[~ 'hi'])  !>(?~(got ~ `subject.u.got))
    %+  expect-eq  !>(`(unit @t)`[~ 'there'])  !>(?~(got ~ `body.u.got))
  ::  a compose has no prev, and that is a successful parse with ~ in it,
  ::  not a failed one.
    %+  expect-eq  !>(`(unit (unit @uv))`[~ ~])  !>(?~(got ~ `prev.u.got))
  ==
::
::  a reply: the same body with a prev naming a message.
++  test-de-send-reply
  =/  jon  (jo '{"to":["~zod"],"subject":"re: hi","body":"yes","prev":"0v3"}')
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
  =/  got  (de-send:web (jo '{"to":[],"subject":"s","body":"b","prev":null}'))
  !>  ?~(got ~ `to.u.got)
::
::  ── send, refused ───────────────────────────────────────────────────
::
::  a missing field is ~, not a crash.
++  test-de-send-missing-body
  %+  expect-eq  !>(`(unit send-req:web)`~)
  !>  (de-send:web (jo '{"to":["~zod"],"subject":"s","prev":null}'))
::
::  a recipient that is not a @p is ~. This is the one field a user types
::  by hand, so it is the one that is malformed in ordinary use.
++  test-de-send-bad-recipient
  %+  expect-eq  !>(`(unit send-req:web)`~)
  !>  (de-send:web (jo '{"to":["not a ship"],"subject":"s","body":"b","prev":null}'))
::
::  a prev that is not a @uv is ~, rather than a send that silently
::  becomes a compose and starts a new thread.
++  test-de-send-bad-prev
  %+  expect-eq  !>(`(unit send-req:web)`~)
  !>  (de-send:web (jo '{"to":["~zod"],"subject":"s","body":"b","prev":"nope"}'))
::
::  a body that is a number, not a string.
++  test-de-send-wrong-type
  %+  expect-eq  !>(`(unit send-req:web)`~)
  !>  (de-send:web (jo '{"to":["~zod"],"subject":"s","body":7,"prev":null}'))
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
::  A DELETE BODY NAMES THE THREAD AND NOTHING ELSE. A read, unread,
::  fold or unfold body carries the same thread-id, so a decoder that
::  ignored the rest would delete the whole thread when one of those was
::  sent to the wrong route.
++  test-de-delete-refuses-any-other-body
  %+  expect-eq  !>(`(unit @uv)`~)
  !>  (de-delete:web (jo '{"thread-id":"0v1a","msg-ids":["0v1a"]}'))
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
::  label, archive and draft, each as the exact body ui/src/api.ts
::  posts. A renamed key is a route that 400s every click.
++  test-de-label
  %+  expect-eq  !>(`(unit label-req:web)`[~ 0v1a 'work' &])
  !>  (de-label:web (jo '{"thread-id":"0v1a","label":"work","add":true}'))
::
::  `archived`, where a rule's field is `archive`: not a typo to fix.
++  test-de-archive
  %+  expect-eq  !>(`(unit [@uv ?])`[~ 0v1a &])
  !>  (de-archive:web (jo '{"thread-id":"0v1a","archived":true}'))
::
++  test-de-draft
  %+  expect-eq
    !>  `(unit draft-req:web)`[~ 0v1a (sy ~[~zod]) 's' 'b' ~]
  !>  (de-draft:web (jo '{"id":"0v1a","to":["~zod"],"subject":"s","body":"b","prev":null}'))
::
::  the client mints the id; a draft without one could never be saved
::  over again, so it is refused rather than given one here.
++  test-de-draft-needs-an-id
  %+  expect-eq  !>(`(unit draft-req:web)`~)
  !>  (de-draft:web (jo '{"to":["~zod"],"subject":"s","body":"b","prev":null}'))
::
::  ── mailing lists ───────────────────────────────────────────────────
::
::  A list is a NAME and a SET OF SHIPS. The name becomes a path segment
::  under /mail/list, so the decoder is the place the name rule is
::  enforced: everything below is a request a browser or a broken client
::  can actually send.
::
::  the ordinary case: a name and two members.
++  test-de-list-good-name
  =/  got  (de-list:web (jo '{"name":"groundwire","members":["~feb","~nec"]}') ~wex)
  ;:  weld
    (expect-eq !>(`(unit @t)`[~ 'groundwire']) !>(?~(got ~ `name.u.got)))
    %+  expect-eq
      !>  `(unit (set @p))`[~ (sy ~[~feb ~nec])]
      !>  ?~(got ~ `members.u.got)
  ==
::
::  digits and hyphens are in the alphabet, so this is a name.
++  test-de-list-name-with-digits-and-hyphens
  %+  expect-eq  !>(`(unit @t)`[~ 'ops-team-2'])
  =/  got  (de-list:web (jo '{"name":"ops-team-2","members":[]}') ~wex)
  !>  ?~(got ~ `name.u.got)
::
::  AN EMPTY MEMBER SET IS A LIST. One you are still filling is a real
::  state, and refusing it would mean the only way to make a list is to
::  know every member first.
++  test-de-list-empty-members
  =/  got  (de-list:web (jo '{"name":"empty","members":[]}') ~wex)
  ;:  weld
    (expect !>(?=(^ got)))
    (expect-eq !>(`(unit (set @p))`[~ ~]) !>(?~(got ~ `members.u.got)))
  ==
::
::  A CAPITAL IS NOT IN THE ALPHABET. The name is a path segment, and
::  the allow-list is the whole rule: nothing here tries to lowercase it,
::  because a list quietly renamed is a list the user cannot find under
::  the name they typed.
++  test-de-list-rejects-a-capital
  %+  expect-eq  !>(`(unit list-req:web)`~)
  !>  (de-list:web (jo '{"name":"Groundwire","members":["~feb"]}') ~wex)
::
::  a slash would name a different directory.
++  test-de-list-rejects-a-slash
  %+  expect-eq  !>(`(unit list-req:web)`~)
  !>  (de-list:web (jo '{"name":"a/b","members":["~feb"]}') ~wex)
::
::  sixty-four bytes is the cap, so sixty-five is not a name.
++  test-de-list-rejects-a-long-name
  ;:  weld
    (expect !>(?=(^ (de-list:web (jo (cat 3 '{"name":"' (cat 3 (crip (reap 64 'a')) '","members":[]}'))) ~wex))))
    %+  expect-eq  !>(`(unit list-req:web)`~)
    !>  %+  de-list:web
          (jo (cat 3 '{"name":"' (cat 3 (crip (reap 65 'a')) '","members":[]}')))
        ~wex
  ==
::
::  an empty name would name the parent directory.
++  test-de-list-rejects-an-empty-name
  %+  expect-eq  !>(`(unit list-req:web)`~)
  !>  (de-list:web (jo '{"name":"","members":["~feb"]}') ~wex)
::
::  a member that is not a @p. This is the field a user types by hand.
++  test-de-list-rejects-a-bad-ship
  %+  expect-eq  !>(`(unit list-req:web)`~)
  !>  (de-list:web (jo '{"name":"ops","members":["not a ship"]}') ~wex)
::
::  THE OWNER'S OWN SHIP IS NOT A MEMBER. A list holding you sends you
::  your own mail every time it is expanded, and refusing the shape here
::  is one rule instead of one rule at every place that expands a list.
++  test-de-list-rejects-self-as-a-member
  ;:  weld
    %+  expect-eq  !>(`(unit list-req:web)`~)
    !>  (de-list:web (jo '{"name":"ops","members":["~wex","~feb"]}') ~wex)
  ::  and the same body is fine on a ship that is not in it.
    (expect !>(?=(^ (de-list:web (jo '{"name":"ops","members":["~wex","~feb"]}') ~nec))))
  ==
::
::  a missing key is ~, not a crash.
++  test-de-list-missing-members
  %+  expect-eq  !>(`(unit list-req:web)`~)
  !>  (de-list:web (jo '{"name":"ops"}') ~wex)
::
::  the delete body carries a name and nothing else, and the same name
::  rule applies: a delete naming a segment we would never have written
::  is a request about nothing.
++  test-de-list-name-delete
  ;:  weld
    (expect-eq !>(`(unit @t)`[~ 'groundwire']) !>((de-list-name:web (jo '{"name":"groundwire"}'))))
    (expect-eq !>(`(unit @t)`~) !>((de-list-name:web (jo '{"name":"A/b"}'))))
    (expect-eq !>(`(unit @t)`~) !>((de-list-name:web (jo '{"id":"0v1a"}'))))
  ==
::
::  ── the attachments a send names ─────────────────────────────────────
::
::  NO BYTES REACH THIS LIB ANY MORE. The file went up on its own
::  request and was stored under its content address; a send names the
::  address. So every case below is about a three-scalar record, and the
::  base64 decoder these tests used to exercise - and the ~1s per file
::  it cost on a request fiber - is gone with the transport.
::
::  ABSENT IS NOT MALFORMED: a send with nothing attached carries no
::  `attachments` key at all.
++  test-de-refs-absent-is-empty
  %+  expect-eq  !>(`(unit (list up-ref:web))`[~ ~])
  !>  (de-refs:web (jo '{"to":[],"subject":"s","body":"b","prev":null}') 16)
::
++  test-de-refs-decodes-one-ref
  =/  got
    %+  de-refs:web
      (jo '{"attachments":[{"name":"a.txt","mime":"text/plain","hash":"0v3"}]}')
    16
  ;:  weld
    (expect-eq !>(`(unit @ud)`[~ 1]) !>(?~(got ~ `(lent u.got))))
    %+  expect-eq  !>(`(unit up-ref:web)`[~ ['a.txt' 'text/plain' 0v3]])
    !>  ?~(got ~ `(snag 0 u.got))
  ==
::
::  THE COUNT IS REFUSED AT THE BOUNDARY, before the nexus peeks a
::  single blob: `most` refs decode and one more is refused. max-attach
::  is passed in because this lib is import-free and cannot reach the
::  chain lib's caps.
++  test-de-refs-caps-the-count
  =/  two
    %-  jo
    %-  crip
    ;:  weld
      (trip '{"attachments":[{"name":"a","mime":"t","hash":"0v1"},')
      (trip '{"name":"b","mime":"t","hash":"0v2"}]}')
    ==
  =/  at  (de-refs:web two 2)
  ;:  weld
    (expect-eq !>(`(unit @ud)`[~ 2]) !>(?~(at ~ `(lent u.at))))
    (expect-eq !>(`(unit (list up-ref:web))`~) !>((de-refs:web two 1)))
  ==
::
::  A `attachments` key that is present and wrong is a refusal, never an
::  empty list: that is a client that meant to attach something and did
::  not, and answering ok would destroy the attachment silently.
++  test-de-refs-refuses-a-malformed-entry
  %+  expect-eq  !>(`(unit (list up-ref:web))`~)
  !>  (de-refs:web (jo '{"attachments":[{"name":"a","mime":"t"}]}') 16)
::
::  A HASH THAT IS NOT A @uv IS A REFUSAL. It is the one field a client
::  does not type but does echo back, and `slaw %uv` is what makes the
::  echo checkable at the boundary rather than at the store.
++  test-de-refs-refuses-a-bad-hash
  %+  expect-eq  !>(`(unit (list up-ref:web))`~)
  !>  %-  de-refs:web
      :_  16
      (jo '{"attachments":[{"name":"a","mime":"t","hash":"not-a-hash"}]}')
::
::  NO SIZE FIELD, AND AN EXTRA ONE CHANGES NOTHING. `size` is read off
::  the stored blob by the nexus, so a client cannot make the signature
::  claim a length the bytes do not have - and a client that sends one
::  anyway is not refused for it, because the field is simply not part
::  of this shape.
++  test-de-refs-ignores-a-client-supplied-size
  =/  got
    %+  de-refs:web
      %-  jo
      '{"attachments":[{"name":"a","mime":"t","hash":"0v3","size":99}]}'
    16
  %+  expect-eq  !>(`(unit up-ref:web)`[~ ['a' 't' 0v3]])
  !>  ?~(got ~ `(snag 0 u.got))
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
::  printable ASCII is the whole range: `~` (0x7e) is the last byte kept,
::  and DEL and every byte of a UTF-8 character go, so a name written in
::  a non-Latin script comes out as the hash (the stated cost).
++  test-safe-name-keeps-printable-ascii-only
  ;:  weld
    (expect-eq !>('caf~.txt') !>((safe-name:web 'caf\c3\a9\7f~.txt' '0v1')))
    (expect-eq !>('0vhash') !>((safe-name:web '\d0\b4\d0\b0' '0vhash')))
  ==
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
  !>  (de-fetch:web (jo '{"from":"~zod"}'))::
::  ── forgetting a peer ───────────────────────────────────────────────
::
++  test-de-forget
  ;:  weld
    (expect-eq !>(`(unit @p)`[~ ~zod]) !>((de-forget:web (jo '{"ship":"~zod"}'))))
    (expect-eq !>(`(unit @p)`~) !>((de-forget:web (jo '{"ship":"zod"}'))))
    (expect-eq !>(`(unit @p)`~) !>((de-forget:web (jo '{"who":"~zod"}'))))
  ==
::
::  every field is required, because a save is an overwrite
++  test-de-settings
  =/  ok  '{"auto-size":0,"allow":["~zod"],"block":[],"budget":67108864}'
  ;:  weld
    %+  expect-eq
      !>(`(unit settings-req:web)`[~ 0 (sy ~[~zod]) ~ 67.108.864])
    !>((de-settings:web (jo ok)))
    %+  expect-eq  !>(`(unit settings-req:web)`~)
    !>((de-settings:web (jo '{"auto-size":0,"allow":[],"block":[]}')))
    %+  expect-eq  !>(`(unit settings-req:web)`~)
    !>((de-settings:web (jo '{"auto-size":0,"allow":["zod"],"block":[],"budget":1}')))
  ==
--

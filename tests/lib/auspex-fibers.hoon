::  Fiber tests for nex/auspex/app: the nexus driven the way grubbery
::  drives it, through +on-file, with lib/fiber-test answering the darts a
::  ship would. What a route DOES (the pokes it sends the writer, the
::  response it gives) and never how it is written.
::
/+  *test, ft=fiber-test, uc=auspex-chain, tarball
/=  app  /nex/auspex/app
|%
::  a request fiber at /ui/requests/<id>, started as grubbery starts one
++  req-fiber
  ((on-file:app [/ui/requests %r1] *blot:tarball) ~)
::
++  call
  |=  [auth=? meth=@tas url=@t body=@t]
  ^-  trail:ft
  (run:ft a-world:ft req-fiber (request:ft ~zod auth meth url body))
::
::  every writer poke a run sent, as the action it carried
++  writes
  |=  t=trail:ft
  ^-  (list action:uc)
  (turn (pokes:ft t [/ %auspex-action]) |=([* =noun] ;;(action:uc noun)))
::
::  a request without a session cookie is refused before anything else
++  test-an-unauthenticated-request-is-forbidden
  =/  t  (call | %'POST' '/apps/auspex/api/archive' '{"thread-id":"0v1a","archived":true}')
  ;:  weld
    (expect-eq !>(%done) !>(end.t))
    (expect-eq !>(403) !>(code:(status:ft t)))
    (expect-eq !>(`(list action:uc)`~) !>((writes t)))
  ==
::
::  a good archive request reaches the writer as exactly that action, and
::  answers ok once the writer has taken it
++  test-archive-pokes-the-writer-then-answers
  =/  t  (call & %'POST' '/apps/auspex/api/archive' '{"thread-id":"0v1a","archived":true}')
  ;:  weld
    (expect-eq !>(%done) !>(end.t))
    (expect-eq !>(`(list action:uc)`~[[%archive 0v1a &]]) !>((writes t)))
    (expect-eq !>([200 '{"ok":true}']) !>((status:ft t)))
  ==
::
::  a malformed body is refused at the route: nothing reaches the writer
++  test-a-bad-archive-body-never-reaches-the-writer
  =/  t  (call & %'POST' '/apps/auspex/api/archive' '{"thread-id":"nope"}')
  ;:  weld
    (expect-eq !>(400) !>(code:(status:ft t)))
    (expect-eq !>(`(list action:uc)`~) !>((writes t)))
  ==
::
::  a draft is stamped with the ship's own clock, read through bowl.sig
++  test-a-draft-is-stamped-with-the-ships-clock
  =/  t
    %:  call  &  %'POST'  '/apps/auspex/api/draft'
      '{"id":"0v1a","to":["~nec"],"subject":"s","body":"b","prev":null}'
    ==
  ;:  weld
    (expect-eq !>(200) !>(code:(status:ft t)))
    %+  expect-eq
      !>  `(list action:uc)`~[[%save-draft [%0 0v1a (sy ~[~nec]) 's' 'b' ~ now:a-world:ft]]]
    !>  (writes t)
  ==
::
::  the shell's files are served from their grubs, each route reading its
::  own file and no other, and only for a GET
++  test-each-asset-route-reads-its-own-file
  =/  cases=(list [url=@t =road:tarball])
    :~  ['/apps/auspex' [%| 2 %& /app %'index.html']]
        ['/apps/auspex/app.js' [%| 2 %& /app %'app.js']]
        ['/apps/auspex/manifest.json' [%| 2 %& /app %'manifest.json']]
        ['/apps/auspex/sw.js' [%| 2 %& /app %'sw.js']]
        ['/apps/auspex/icon.svg' [%| 2 %& / %'icon.svg']]
    ==
  %+  weld
    ^-  tang
    %-  zing
    %+  turn  cases
    |=  [url=@t =road:tarball]
    =/  t  (call & %'GET' url '')
    (expect-eq !>(`(list road:tarball)`~[road]) !>((peeks:ft t)))
  ::  and a POST to any asset's path is not a request for the asset
  ^-  tang
  %-  zing
  %+  turn  cases
  |=  [url=@t =road:tarball]
  =/  t  (call & %'POST' url '')
  (expect !>(!(lien (peeks:ft t) |=(r=road:tarball =(r road)))))
::
::  whoami asks the ship who it is, then reads what it can sign with
++  test-whoami-reads-our-ship-and-caps
  =/  t  (call & %'GET' '/apps/auspex/api/whoami' '')
  =/  asks  (turn (pokes:ft t [/ %bowl-req]) |=([* =noun] noun))
  ;:  weld
    (expect !>((lien asks |=(a=* =(%our a)))))
    (expect-eq !>(`(list road:tarball)`~[[%| 2 %& / %caps]]) !>((peeks:ft t)))
    ::  and only for a GET. The mail gate below asks for `our` too, but
    ::  only whoami reads the caps.
    =/  p  (call & %'POST' '/apps/auspex/api/whoami' '')
    (expect !>(!(lien (peeks:ft p) |=(r=road:tarball =(r [%| 2 %& / %caps])))))
    ::  and only at its own path: another GET is not a whoami
    =/  d  (call & %'GET' '/apps/auspex/api/drafts' '')
    (expect !>(!(lien (peeks:ft d) |=(r=road:tarball =(r [%| 2 %& / %caps])))))
  ==
--

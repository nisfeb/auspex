::  Fiber tests for nex/auspex/app: the nexus driven the way grubbery
::  drives it, through +on-file, with lib/fiber-test answering the darts a
::  ship would. What a route DOES (the pokes it sends the writer, the
::  response it gives) and never how it is written.
::
/+  *test, ft=fiber-test, uc=auspex-chain, tarball, nexus
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
::  a writer that refuses (crashed, waiting) gets the browser a 503 at
::  once, and the request ends cleanly instead of hanging unanswered
++  test-a-refusing-writer-answers-503
  =/  w=world:ft  a-world:ft
  =.  nack.w  ~[[/ %auspex-action]]
  =/  t
    %^  run:ft  w  req-fiber
    (request:ft ~zod & %'POST' '/apps/auspex/api/archive' '{"thread-id":"0v1a","archived":true}')
  ;:  weld
    (expect-eq !>(%done) !>(end.t))
    (expect-eq !>(503) !>(code:(status:ft t)))
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
::
::  ── coming back from a crash ────────────────────────────────────────
::
::  The rules are the kit's "Never ship a crash loop". A long-lived fiber
::  that crashed must wait without failing, come back by itself, refuse
::  pokes while it waits rather than swallow them, and park rather than
::  spin when the weir refuses its clock or its timer.
::
++  crash  `prod:fiber:nexus``~[leaf+"boom"]
++  writer
  |=  p=prod:fiber:nexus
  ((on-file:app [/ %'main.sig'] *blot:tarball) p)
++  ui-main
  |=  p=prod:fiber:nexus
  ((on-file:app [/ui %'main.sig'] *blot:tarball) p)
::  the timer a run set, as [wire until]
++  timers
  |=  t=trail:ft
  ^-  (list *)
  (turn (pokes:ft t [/ %timer-set]) |=([* =noun] noun))
::
::  a crashed writer reads the clock and its crash record, writes the
::  record, sets a timer for a minute on, and waits
++  test-a-crashed-writer-waits-a-minute
  =/  t0  (run:ft a-world:ft (writer crash) !>(~))
  =/  t1  (answer-peek:ft a-world:ft t0 [%none ~])
  ;:  weld
    (expect-eq !>(%wait) !>(end.t0))
    (expect-eq !>(%wait) !>(end.t1))
    (expect-eq !>(`(list *)`~[[/rise (add now:a-world:ft ~m1)]]) !>((timers t1)))
    ::  and nothing reached the mail while it waits
    (expect-eq !>(~) !>((pokes:ft t1 [/ %auspex-action])))
  ==
::
::  a poke while it waits is refused (its sender sees a nack), never
::  held and never taken as the restart signal and dropped
++  test-a-waiting-writer-refuses-a-poke
  =/  t1  (answer-peek:ft a-world:ft (run:ft a-world:ft (writer crash) !>(~)) [%none ~])
  =/  t2  (feed:ft a-world:ft t1 [%poke *from:fiber:nexus [[/ %auspex-action] !>(~)]])
  ;:  weld
    (expect-eq !>(%fail) !>(end.t2))
    %+  expect-eq
      !>  `tang`~[leaf+"%auspex writer failed: waiting after a crash; the poke was refused"]
    !>  err.t2
  ==
::
::  and the timer's wake brings it back: it goes on to its start-up work
++  test-the-wake-brings-the-writer-back
  =/  t1  (answer-peek:ft a-world:ft (run:ft a-world:ft (writer crash) !>(~)) [%none ~])
  =/  t3  (feed:ft a-world:ft t1 [%poke *from:fiber:nexus [[/ %timer-wake] !>(/rise)]])
  ;:  weld
    (expect !>(!=(%fail end.t3)))
    (expect !>((gth (lent darts.t3) (lent darts.t1))))
  ==
::
::  a weir that refuses the clock: park at once, one dart, no spin
++  test-no-clock-parks-without-spinning
  =/  w=world:ft  a-world:ft
  =.  refuse.w  ~[[%sys %'bowl.sig' ~] /sys/behn]
  =/  t  (run:ft w (writer crash) !>(~))
  ;:  weld
    (expect-eq !>(%wait) !>(end.t))
    (expect-eq !>(1) !>((lent darts.t)))
  ==
::
::  a weir that refuses the timer: park with no timer set, waiting for a
::  poke, and still no spin
++  test-no-timer-parks-without-spinning
  =/  w=world:ft  a-world:ft
  =.  refuse.w  ~[/sys/behn]
  =/  t  (answer-peek:ft w (run:ft w (writer crash) !>(~)) [%none ~])
  (expect-eq !>(%wait) !>(end.t))
::
::  /ui/main serves the whole API and nobody pokes it, so it must come
::  back by itself: it too sets a timer
++  test-ui-main-comes-back-by-itself
  =/  t  (answer-peek:ft a-world:ft (run:ft a-world:ft (ui-main crash) !>(~)) [%none ~])
  ;:  weld
    (expect-eq !>(%wait) !>(end.t))
    (expect-eq !>(`(list *)`~[[/rise (add now:a-world:ft ~m1)]]) !>((timers t)))
  ==
::
::  a clean start clears any wait an earlier run left, then goes on
++  test-a-clean-start-clears-the-old-wait
  =/  t  (run:ft a-world:ft (writer ~) !>(~))
  ;:  weld
    (expect-eq !>(`(list *)`~[/rise]) !>((turn (pokes:ft t [/ %timer-rest]) |=([* =noun] noun))))
    (expect !>(!=(%fail end.t)))
  ==
--

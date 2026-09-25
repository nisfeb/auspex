::  lib/fiber-test: drive a grubbery fiber in a unit test.
::
::    A fiber is $-(input output): one input in, darts and a verb out. This
::    runs one the way grubbery does - %cont steps again at once, %wait and
::    %skip wait for the next input - and answers the darts that have one
::    right answer in a test, so a test sees what the fiber DID (every dart
::    it sent, how it stopped) without a ship:
::
::    - a poke of /sys/bowl.sig (now, our, entropy) is answered from the
::      $world, the way grubbery answers it: a %poke back, and an ack;
::    - every other poke is acked, as if it landed.
::
::    Anything else (a peek, a keen, a timer) is left unanswered, and the
::    run stops %wait with the fiber blocked on it. +feed answers it and
::    carries on. Nothing here knows any app.
::
::    Installed on a test desk by listing it in hoon-test.conf's FILES:
::      scripts/hoon-test-kit/hoon/fiber-test.hoon=lib/fiber-test.hoon
::    with grubbery's nexus and tarball on the desk (SHIP_FILES).
::
/+  nexus, tarball
|%
+$  world  [now=@da eny=@uvJ our=ship]
++  a-world  `world`[~2026.1.1 0v1 ~zod]
::
+$  intake  intake:fiber:nexus
+$  trail
  $:  darts=(list dart:nexus)   ::  every dart sent, oldest first
      end=?(%done %fail %wait)  ::  how the run stopped
      err=tang                  ::  %fail: the fiber's error
      state=vase                ::  the fiber's state when it stopped
      queue=(list intake)       ::  answers not yet taken
  ==
::
::  +run: start a process (a spool given its prod) with this state, and
::  drive it until it finishes or waits on something only a test can answer.
::
++  run
  |=  [w=world p=process:fiber:nexus st=vase]
  ^-  trail
  (drive w p st ~ ~ ~)
::
::  +feed: hand a stopped run the answer it is waiting for, and go on.
::
++  feed
  |=  [w=world p=process:fiber:nexus t=trail in=intake]
  ^-  trail
  (drive w p state.t darts.t [in queue.t] ~)
::
++  drive
  |=  $:  w=world
          p=process:fiber:nexus
          st=vase
          darts=(list dart:nexus)
          queue=(list intake)
          skipped=(list intake)
      ==
  ^-  trail
  =/  in=(unit intake)  ~
  |-
  =/  out  (p [st in])
  =/  n=@ud  (lent darts)
  =.  darts  (weld darts darts.out)
  =.  st  [p.st state.out]
  =.  queue  (weld queue (answers w n darts.out))
  ?-    -.next.out
      %done  [darts %done ~ st (weld skipped queue)]
      %fail  [darts %fail err.next.out st (weld skipped queue)]
      %cont
    $(p self.next.out, in ~, queue (weld skipped queue), skipped ~)
      %wait
    =.  queue  (weld skipped queue)
    ?~  queue  [darts %wait ~ st ~]
    $(in `i.queue, queue t.queue, skipped ~)
      %skip
    =?  skipped  ?=(^ in)  (snoc skipped u.in)
    ?~  queue  [darts %wait ~ st skipped]
    $(in `i.queue, queue t.queue)
  ==
::
::  +answers: what grubbery would send back for these darts. `n` makes each
::  entropy answer different, so every nonce'd wire is distinct.
::
++  answers
  |=  [w=world n=@ud ds=(list dart:nexus)]
  ^-  (list intake)
  ?~  ds  ~
  =/  d=dart:nexus  i.ds
  =/  rest  $(ds t.ds, n +(n))
  ?.  ?=([%node * * %poke *] d)  rest
  =/  b=bask:tarball  bask.load.d
  ?.  =([/ %bowl-req] p.b)
    [[%pack wire.d ~] rest]
  =/  s=sage:tarball
    ?:  =(%now q.b)  [[/ %time] !>(now.w)]
    ?:  =(%our q.b)  [[/ %ship] !>(our.w)]
    [[/ %entropy] !>(`@uvJ`(mix eny.w n))]
  ::  grubbery answers a bowl read AND acks the poke that asked. The
  ::  answer goes first: +take-bowl takes either order (it drains the
  ::  trailing ack), and a +poke waiting on the ack skips the answer,
  ::  which +drive replays to it once the ack has landed.
  [[%poke *from:fiber:nexus s] [%pack wire.d ~] rest]
::
::  ── reading a trail ─────────────────────────────────────────────────
::
::  +pokes: the payloads of every poke with this mark, in order
::
++  pokes
  |=  [t=trail b=blot:tarball]
  ^-  (list [=road:tarball =noun])
  %+  murn  darts.t
  |=  d=dart:nexus
  ?.  ?=([%node * * %poke *] d)  ~
  ?.  =(b p.bask.load.d)  ~
  `[road.d q.bask.load.d]
::
::  +peeks: the road of every grub the fiber asked to read, in order
::
++  peeks
  |=  t=trail
  ^-  (list road:tarball)
  %+  murn  darts.t
  |=  d=dart:nexus
  ?.  ?=([%node * * %peek *] d)  ~
  `road.d
::
::  +responses: every HTTP response the fiber sent, as eyre-id and update
::
++  responses
  |=  t=trail
  ^-  (list [eyre-id=@ta =eyre-update:nexus])
  %+  murn  (pokes t [/ %eyre-action])
  |=  [* =noun]
  =/  a  ;;(eyre-action:nexus noun)
  ?.  ?=(%send -.a)  ~
  `[eyre-id.a eyre-update.a]
::
::  +status: the status code of the one simple response a request sent,
::  and its body as a cord
::
++  status
  |=  t=trail
  ^-  [code=@ud body=@t]
  =/  rs  (responses t)
  ?>  ?=([* ~] rs)
  =/  u=eyre-update:nexus  eyre-update.i.rs
  ?>  ?=(%simple -.u)
  :-  status-code.response-header.simple-payload.u
  ?~(data.simple-payload.u '' q.u.data.simple-payload.u)
::
::  +request: an inbound HTTP request, the state a request fiber starts in
::
++  request
  |=  [src=ship auth=? meth=@tas url=@t body=@t]
  ^-  vase
  !>  :-  src
      ^-  inbound-request:eyre
      :*  auth  |  [%ipv4 .127.0.0.1]
          ;;(method:http meth)  url  ~
          ?:(=('' body) ~ `(as-octs:mimes:html body))
      ==
--

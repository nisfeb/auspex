/-  sur=urmail
|_  =action:sur
++  grab
  |%
  ++  noun  action:sur
  ++  json
    |=  jon=^json
    ^-  action:sur
    =,  dejs:format
    %.  jon
    %-  of
    :~  :-  %send
        %-  ot
        :~  to+(as (se %p))
            subj+so
            body+so
            prev+(mu (se %uv))
        ==
        read+(ot ~[[%msg-id (se %uv)]])
    ==
  --
++  grow
  |%
  ++  noun  action
  --
++  grad  %noun
--

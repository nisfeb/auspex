::  urmail-chain: the pure crypto and chain algebra, plus the types it is
::  written against.
::
::    Ported verbatim from the %urmail desk's lib/urmail.hoon and
::    sur/urmail.hoon. Every arm keeps its behaviour: signing and
::    verification, the three verdicts, [id sig] anti-shadowing, +merge,
::    +prune, +thread-key, +freeze and the input caps. Only the imports
::    changed.
::
::    The two files are ONE file here for a platform reason, not a taste
::    one. This file has to compile in two places: the desk-level /lib,
::    where -test builds it with ford runes (/- /+), and gub/lib, where
::    grubbery's loader builds it with /<. Those import syntaxes are not
::    interchangeable, so an overlay lib that imports anything can only
::    live in one of the two. Every lattice overlay lib is likewise
::    import-free. Types therefore sit in the same core rather than in a
::    sur/ that an overlay does not have.
::
::    Nothing here scries. Jael only answers at exactly `now`, so a scry
::    needs a live bowl, and a test arm has no bowl. Keys arrive as
::    arguments; the nexus is the only thing that fetches them.
::
|%
::  $msg-id: (sham unsigned). Covers exactly what a signature covers.
::
+$  msg-id     @uv
+$  thread-id  msg-id
::
::  $verdict: verification labels a message, it never rejects one.
::
::    %verified   signature checks against the sender's registered key
::    %unverified no key available for that ship (moons, comets)
::    %forged     a key was available and the signature failed
::
+$  verdict  ?(%verified %unverified %forged)
::
::  $attachment: the METADATA of one attached file. Never the bytes.
::
::    The chain travels whole on every send, so bytes must not live in it.
::    An attachment costs the chain ~100 bytes whatever the file weighs.
::
::    `hash` is (sham octs) over the CONTENT, and it is the content's
::    address: the bytes live at /mail/blob/<hash> and are published into
::    the remote-scry farm at that same hash. The hash is the authority
::    and the courier is irrelevant - any ship holding the bytes can serve
::    them, and a blob whose contents do not hash to the name it was
::    fetched under is discarded.
::
::    Hashed as octs, NOT as a bare atom. An atom loses leading zero
::    BYTES, so two different files that differ only in leading zeros
::    would share an address; octs carries the length, so they do not.
::    It also ties `size` to the hash: a lie about the size is a lie
::    about the content address.
::
+$  attachment
  $:  name=@t          ::  original filename
      size=@ud         ::  bytes
      mime=@t          ::  content type
      hash=@uv         ::  (sham octs) over the contents
  ==
::
::  $unsigned: everything a signature covers.
::
::    `life` travels with the message because signatures must outlive key
::    rotation: a message signed under life 3 stays verifiable after the
::    sender rotates to life 4.
::
::    `prev` is what makes a flat list a chain. A reply points at the
::    message it answers; a forward points into the chain it carries.
::
::    `body-mime` says how to read `body`; empty means 'text/plain', so
::    a sender that does not care writes nothing. It is SIGNED because
::    the rendering instruction is part of the message: one that says
::    "render me as HTML" and one that says "render me as plain text"
::    are different messages, and an intermediary must not be able to
::    change which one you read.
::
::    IT IS HOSTILE INPUT AT THE RENDER BOUNDARY. A signature proves the
::    author CHOSE the value, never that it is safe, and it arrives
::    pre-signed inside a chain any ship may deliver. A renderer must
::    match it against a fixed allow-list and fall back to plain text
::    for anything else; it must never pass the value into a header or
::    a Content-Type. Length and control bytes are refused here, at the
::    boundary, because a recipient cannot repair the field without
::    destroying the signature that makes the message evidence - the
::    same reasoning as `mime` on an attachment.
::
::    `attachments` is INSIDE here, so it is covered by the signature and
::    by msg-id. Swapping a file breaks the signature. That placement is
::    also a WIRE BREAK: msg-id is (sham unsigned), so every message
::    signed against the seven-field shape has a different id and a dead
::    signature under the eight-field one. A signed message cannot be
::    migrated - its signature covers a shape that no longer exists - so
::    the only true migration is to carry every historical shape forever,
::    and that is deferred until the format is declared stable. See
::    +read-stored in the nexus for how the old grubs are refused rather
::    than silently relabelled.
::
+$  unsigned
  $:  from=ship
      life=@ud
      to=(set ship)
      subj=@t
      body=@t
      body-mime=@t
      sent=@da
      prev=(unit msg-id)
      attachments=(list attachment)
  ==
::
::  AND THAT IS THE WHOLE OF IT. $unsigned is FROZEN. Nothing may be
::  added without breaking every message in existence, because a
::  signature covers a shape and rewriting the shape produces messages
::  every peer reads as forged. Reply-to, expiry and multi-parent were
::  considered and rejected; BCC is deliberately absent, because the
::  chain proves authorship and not delivery, which is exactly why a
::  forwarded chain works at all. Everything else a mail client needs -
::  labels, folders, archive, read state, drafts, filters, BCC records -
::  is LOCAL, and two ships may disagree about all of it while still
::  agreeing exactly on who signed what.
::
+$  msg    [=unsigned sig=@ux]
+$  chain  (list msg)
::
+$  thread
  $:  =chain
      participants=(set ship)
      last=@da
  ==
::
::  $action: the local poke. %delete-thread is the escape hatch.
::
::    Every capacity limit in this nexus is otherwise permanent and
::    unrecoverable: a thread pinned at the distinct-id cap, or a store
::    filled to max-threads, has no remedy but deleting the tree.
::    Deletion makes those limitations recoverable without committing to
::    a quota redesign. It is local-only - the writer fiber gates every
::    action on the poke's source being us - so no peer can delete a
::    thread out from under us.
::
::    %attach-file carries BYTES, so it is the one action with a size to
::    it. It is local-only like the rest, and it is the only way bytes
::    ever enter this ship's blob store from the user side.
::
::    %send's `bcc` affects DELIVERY ONLY. The chain names `to` and
::    nothing else; the blind-copied ships get the same canonical bytes,
::    the same msg-id and the same thread as everyone else, and see the
::    visible recipients, which is what BCC means. Replying reveals
::    them, because a reply is signed and lists its own `to` - BCC's
::    behaviour everywhere.
::
+$  action
  $%  $:  %send
          to=(set ship)
          subj=@t
          body=@t
          body-mime=@t
          prev=(unit msg-id)
          files=(list file)
          bcc=(set ship)
      ==
    ::  %read takes a SET, because opening a thread marks every unread
    ::  message in it at once. One id per poke meant one writer event
    ::  and one full mailbox scan per message - forty messages, forty
    ::  serialised scans, on the ship's single serialisation point for
    ::  mail, to record something no peer will ever see.
      [%read ids=(set msg-id)]
      [%delete-thread =thread-id]
      [%fetch-blob hash=@uv from=ship]
      [%restrict-blob hash=@uv ships=(set ship)]
      [%publish-blob hash=@uv]
  ==
::
::  $file: one file as handed to %send, before it is hashed and stored.
::
+$  file  [name=@t mime=@t =octs]
::
::  $blob-vis: whether THIS SHIP serves a blob's bytes.
::
::    RESTRICTION IS NOT ACCESS CONTROL, and calling it that would be a
::    lie to the user. It is withdrawal of our own copy, and it is
::    meaningful only before anyone has opened the attachment.
::
::    The reason is structural, not an implementation gap. A blob is
::    content-addressed and answerable by anyone holding the bytes -
::    that property is what makes a forwarded chain's attachments
::    readable at all, and this ship relies on it every time it fetches
::    one. But a ship that fetches a blob stores it and publishes it
::    into ITS OWN permissionless farm, because it is now one of the
::    ships holding the bytes. So the first successful fetch creates a
::    second, independent, un-revocable source. Withdrawing ours after
::    that stops nobody.
::
::    What restriction therefore buys is exactly this: bytes we have not
::    yet served cannot be pulled from us, and a hash is not a
::    capability we hand out by default once we have said no. Treat it
::    as unpublishing, never as revoking.
::
::    %public     grown into the remote-scry farm, so ANY ship holding
::                the hash may keen it. The default: a chain is
::                forwardable to anyone by design, and an attachment
::                nobody but the original recipients could read would
::                make a forward carry an unreadable file.
::    %restricted withdrawn from our farm. The named ships are recorded
::                so a weir grant can serve them a peek instead; see
::                +do-restrict in the nexus for what that costs and what
::                the platform will not yet let a nexus do.
::
+$  blob-vis
  $%  [%public ~]
      [%restricted ships=(set ship)]
  ==
::
::  $stored-blob: one attachment's bytes, at /mail/blob/<hash>.
::
::    Bytes and an arrival time. Visibility lives in a separate small
::    grub so that changing who may read a file does not rewrite the
::    file.
::
::    `at` is what makes "evict the OLDEST unreferenced blob" a thing
::    the store can actually do rather than a phrase in a spec. It is
::    local bookkeeping and is deliberately not part of the address:
::    two ships holding the same file agree on its hash and disagree
::    about when they got it.
::
::    Version 1, and version 0 (no `at`) IS upgraded in place rather
::    than refused. This is the ladder working as intended, and it is
::    worth contrasting with $stored-msg, which cannot do the same: a
::    blob's shape is not covered by any signature, so filling in a
::    default costs nothing and misrepresents nothing.
::
+$  stored-blob  [%1 =octs at=@da]
+$  stored-blob-0  [%0 =octs]
::
::  $blob-row: one held blob, as the store's bookkeeping sees it.
::
+$  blob-row  [h=@uv at=@da size=@ud]
::
::  $fetch-req: one in-flight blob fetch, at /fetch/<id>.
::
::    A request is a GRUB, and the grub is the fiber's state, which is
::    what moves the network round trip off the writer. `from` is a hint
::    about where to look and confers nothing: the hash is what proves
::    the bytes.
::
+$  fetch-req  [%0 hash=@uv from=ship]
::
::  $blob-in: a fetch fiber's answer, poked back at the writer.
::
::    ~ for a miss, so the writer culls the request grub either way and
::    a failed fetch leaves nothing behind. A wire format, never stored.
::
+$  blob-in  [%0 id=@ta hash=@uv res=(unit octs)]
::
::  $blob-index: visibility for every blob we hold, at /mail/blobvis.
::  Absent from the map means %public, the default.
::
+$  blob-index  [%0 vis=(map @uv blob-vis)]
::
::  the tree's persisted shapes. Every one of these is read back through
::  ;; against a NOUN-marc vase, newest shape first, so a later version
::  can be added without booming every grub already on disk. See
::  +read-stored / +read-meta / +read-idx in the nexus.
::
::  $stored-msg: one signed copy, at /mail/thread/<tid>/msg/<slot>.
::
::    The verdict rides WITH the copy rather than in a side map, because
::    a verdict names one signed copy: two messages sharing an id and
::    differing in signature are distinct grubs with distinct verdicts.
::    That is the [id sig] keying, expressed as storage layout.
::
::    Version 2, and versions 0 and 1 are REFUSED rather than upgraded.
::    %0 held the seven-field $unsigned, %1 the eight-field one that
::    added attachments, %2 the nine-field frozen one that adds
::    body-mime. An old grub can be RECOGNISED - its head is its version
::    - but it cannot be migrated: msg-id and the signature both cover
::    the shape, so rewriting an old message into the new shape produces
::    a message whose signature no longer matches its own contents and
::    which every peer would then read as %forged. Turning genuine mail
::    into apparent forgeries is worse than refusing it. So the ladder
::    has no branch for either old version and both breaks are recorded
::    as breaks rather than papered over.
::
::    The version is bumped rather than reused precisely so that a %1
::    grub is refused as cleanly as a %0 one, instead of clamming into
::    the new shape by accident.
::
::    This is the LAST such break. $unsigned is frozen above.
::
+$  stored-msg  [%2 =msg =verdict]
::
::  $meta: local state about a thread, at /mail/thread/<tid>/meta.
::  Never signed, never travels: two ships may disagree about any of it.
::
::  archived defaults to %.n explicitly. A bare ? bunts to %.y, so every
::  thread would be born archived and a v2 inbox view would show nothing.
::  $~ and not $_: $_ produces a mold that IGNORES its input and always
::  returns the default, which would make the read-back flag a constant.
::
::    `direct` is set when a chain arrived through a DELIVERY POKE, and
::    it exists for BCC. The Inbox view is threads we participate in,
::    and a BCC'd recipient is in neither `from` nor `to` - their mail
::    would be invisible. Inbox is therefore participant OR direct.
::
::    `bcc` is the sender's own record of who it blind-copied, keyed by
::    the message it sent, so its Sent view is accurate. IT NEVER
::    TRAVELS and it is not signed. Signing the set would not be BCC,
::    and signing a hashed commitment to it would leak that a BCC
::    exists while remaining testable against any guessed ship - privacy
::    it cannot deliver, which is the same class of overstatement as
::    calling blob restriction access control.
::
::    Version 1, and version 0 IS upgraded in place. None of this is
::    covered by a signature, so supplying defaults misrepresents
::    nothing - the contrast with $stored-msg above is the whole point
::    of keeping local state out of `unsigned`.
::
+$  meta
  $:  %1
      read=(set msg-id)
      archived=$~(%.n ?)
      labels=(set @tas)
      direct=$~(%.n ?)
      bcc=(map msg-id (set ship))
  ==
+$  meta-0  [%0 read=(set msg-id) archived=$~(%.n ?) labels=(set @tas)]
::
::  $mail-idx: the derived inbox order, at /mail/idx. Newest first.
::
+$  mail-idx  [%0 inbox=(list thread-id)]
::
::  the capacity limits. Arms rather than constants in the nexus so the
::  predicates below and their callers cannot drift apart.
::
++  max-chain    1.000        ::  distinct messages per chain
++  max-body     100.000      ::  bytes per body
++  max-subj     1.000        ::  bytes per subject
++  max-to       100          ::  recipients per message
++  max-copies   4            ::  copies (same id, distinct sig) per message
++  max-threads  10.000       ::  distinct threads this ship will hold
::  +max-depth: the deepest ancestry a thread may hold.
::
::    Depth is not free and is NOT off the read path. A message is
::    stored under its ancestry, so its road carries one ~34-byte
::    segment per ancestor, and the nexus rebuilds those keys on every
::    peek of the mail tree - which is every send, every read-mark,
::    every delivery and every inbox listing. Cost is quadratic in
::    depth, and max-chain alone would let ONE hostile linear chain pin
::    a thread at depth 1.000 permanently: measured, 200 messages at
::    depth 200 already cost ~1.8x the same 200 at depth 2, and 1.000
::    extrapolates to minutes of writer time per read, forever, until
::    the thread is deleted.
::
::    64 is deliberately far above any real conversation - sixty-four
::    sequential replies with nobody branching - and far below where
::    the quadratic bites. Like every other cap it REFUSES rather than
::    truncates, because a chain that violates a limit is not partially
::    trustworthy, and it is checked on the MERGED result too, since
::    two chains each inside the cap can compose past it. The cost of
::    that, stated plainly: a thread genuinely deeper than this accepts
::    no further messages, exactly as the max-chain distinct-id cap
::    already behaves, and for the same reason.
::
++  max-depth    64           ::  ancestors from root to leaf
::
::  the attachment limits.
::
::    max-blob is 256K rather than something round and large because a
::    blob is answered over remote scry, which fragments the response
::    into ames packets; a multi-megabyte keen is a lot of packets for a
::    fetch that has no partial-progress story. Raise it when the fetch
::    has one.
::
::    max-blobs bounds this ship's blob store. It cannot be weaponised:
::    bytes only ever enter through a LOCAL action (%send's files or
::    %fetch-blob), never through a delivered chain, which carries
::    metadata alone.
::
++  max-blob     262.144      ::  bytes in one attachment
++  max-attach   16           ::  attachments per message
++  max-name     256          ::  bytes of filename
++  max-mime     128          ::  bytes of content type
++  max-blobs    1.000        ::  blobs this ship will store
::  and the bound the spec actually asked for, which a count is not:
::  1.000 quarter-megabyte blobs is 256MB, and a store bounded only by
::  count is not bounded by storage.
++  max-blob-bytes  33.554.432
::
::  +blob-hash: the content address of a file's bytes.
::
::    Over octs, not over the bare atom: an atom has no leading zero
::    bytes, so hashing q alone gives two distinct files one address.
::
++  blob-hash
  |=  =octs
  ^-  @uv
  (sham octs)
::
::  +blob-ok: do these bytes belong at this address?
::
::    The whole of blob acceptance. A blob whose contents do not hash to
::    the name it was fetched under is discarded without comment: blobs
::    are a cache, so losing one loses a file, never a message and never
::    a signature.
::
++  blob-ok
  |=  [=octs h=@uv]
  ^-  ?
  =(h (blob-hash octs))
::
::  +describe: the signed metadata for one file.
::
++  describe
  |=  f=file
  ^-  attachment
  [name.f p.octs.f mime.f (blob-hash octs.f)]
::
::  +file-ok: is this file storable at all?
::
::    p.octs is the DECLARED length and q is the atom. An atom cannot
::    carry more bytes than it measures, so a declared length below the
::    measured one is a malformed octs and would make +blob-hash disagree
::    with anything the bytes are later re-measured against.
::
++  file-ok
  |=  f=file
  ^-  ?
  ?&  (lte p.octs.f max-blob)
      (gte p.octs.f (met 3 q.octs.f))
      (text-ok name.f max-name)
      (text-ok mime.f max-mime)
  ==
::
::  +text-ok: a signed metadata string that is safe to hand onward.
::
::    Length is not the only thing wrong a `name` or a `mime` can be.
::    Both are ATTACKER-SUPPLIED and both arrive PRE-SIGNED, so a
::    recipient cannot repair one without destroying the signature that
::    makes the message evidence; the only place to refuse it is the
::    boundary. `mime` in particular is headed for a Content-Type
::    header, where a CR or an LF is a header-injection primitive, and
::    `name` is headed for a filename. Control bytes have no legitimate
::    use in either, so both are refused here rather than escaped by
::    whichever consumer remembers to.
::
++  text-ok
  |=  [t=@t m=@ud]
  ^-  ?
  ?&  (lte (met 3 t) m)
      %+  levy  (trip t)
      |=(c=@tD &((gth c 0x1f) !=(c 0x7f)))
  ==
::
++  files-ok
  |=  fs=(list file)
  ^-  ?
  ?&  (lte (lent fs) max-attach)
      (levy fs file-ok)
  ==
::
::  +fits-attachments: the INCOMING bound, applied to a delivered chain.
::
::    A delivered chain carries metadata only, so this bounds what a
::    hostile peer can make us store per message and what it can make us
::    later try to fetch. `size` is checked against max-blob here as
::    well: an attachment claiming a gigabyte is a claim we would never
::    honour, and rejecting it at the boundary is cheaper than
::    discovering it at fetch time.
::
++  fits-attachments
  |=  [c=chain m=@ud]
  ^-  ?
  %+  levy  c
  |=  x=msg
  =/  as  attachments.unsigned.x
  ?&  (lte (lent as) m)
      %+  levy  as
      |=  a=attachment
      ?&  (lte size.a max-blob)
          (text-ok name.a max-name)
          (text-ok mime.a max-mime)
      ==
  ==
::
::  +chain-hashes: every content address a chain refers to.
::
++  chain-hashes
  |=  c=chain
  ^-  (set @uv)
  %-  ~(gas in *(set @uv))
  %-  zing
  (turn c |=(m=msg (turn attachments.unsigned.m |=(a=attachment hash.a))))
::
::  +unreferenced: which held blobs no stored message mentions, oldest
::  first. The eviction order.
::
::    This is the other half of +chain-hashes, and the pair is what makes
::    max-blobs a store that can be full rather than a store that jams.
::    A blob referenced by any stored message is never evicted, however
::    old; an unreferenced one is a file whose every message has been
::    deleted, and %delete-thread culls messages without culling their
::    blobs, so unreferenced blobs genuinely accumulate.
::
::    Ties on `at` fall back to the hash so the order is total and two
::    runs shed the same blob.
::
++  unreferenced
  |=  [held=(list blob-row) refs=(set @uv)]
  ^-  (list blob-row)
  %+  sort  (skip held |=(r=blob-row (~(has in refs) h.r)))
  |=  [a=blob-row b=blob-row]
  ?.  =(at.a at.b)  (lth at.a at.b)
  (lth h.a h.b)
::
::  +held-bytes: what the store currently weighs.
::
++  held-bytes
  |=  held=(list blob-row)
  ^-  @ud
  (roll (turn held |=(r=blob-row size.r)) add)
::
::  +shed-for: which blobs to cull so `need` more, weighing `bytes`,
::  will fit. ~ when no shedding is needed; a list SHORTER than required
::  when the store cannot be made to fit, which the caller must treat as
::  a refusal rather than partially evicting for nothing.
::
::    Takes both bounds at once because they can bind independently: a
::    store can be under the count and over the bytes, or the reverse.
::
++  shed-for
  |=  $:  held=(list blob-row)
          refs=(set @uv)
          need=@ud
          bytes=@ud
      ==
  ^-  [ok=? drop=(list @uv)]
  =/  cnt=@ud    (add (lent held) need)
  =/  weight=@ud  (add (held-bytes held) bytes)
  ?:  &((lte cnt max-blobs) (lte weight max-blob-bytes))
    [& ~]
  =/  dead=(list blob-row)  (unreferenced held refs)
  =|  drop=(list @uv)
  |-  ^-  [ok=? drop=(list @uv)]
  ?:  &((lte cnt max-blobs) (lte weight max-blob-bytes))
    [& (flop drop)]
  ?~  dead  [| ~]
  %=  $
    dead    t.dead
    cnt     (dec cnt)
    weight  (sub weight (min weight size.i.dead))
    drop    [h.i.dead drop]
  ==
::
::  +blob-spur: where a blob is bound in this ship's remote-scry farm.
::
::    gall's farm is a FLAT namespace shared by every nexus in the
::    grubbery yoke (lattice grows at /pub/page/...), so urmail names its
::    own prefix. Content-addressed, and there is NO revision segment:
::    lattice needs one because a page is mutable and the namespace
::    requires an immutable binding per spur, while a blob's bytes are
::    fixed by its name. That is the whole reason this fetch needs no
::    rev-discovery channel, and rev-discovery is the weir-gated part.
::
++  blob-spur
  |=  h=@uv
  ^-  path
  /urmail/blob/[(scot %uv h)]
::
::  +blob-keen-path: the ames spar path of one blob in a PEER's farm.
::
::    MUST mirror +blob-spur or every read misses forever.
::
::      g          gall
::      x          the value care
::      <case>     the gall case. A spur that has never been grown and
::                 never culled binds at case 1 (+grow:of-farm in
::                 sys/lull: an empty fan with no high-water mark takes
::                 key 1), so case 1 is the answer for a
::                 content-addressed blob and a re-grow of the same
::                 bytes leaves it bound and correct.
::      <agent>    the yoke whose farm is read: the gall agent, not the
::                 nexus. urmail lives inside %grubbery.
::      ''         THE EMPTY SEGMENT, load-bearing. The publisher's ames
::                 takes the head of the spur as the beam's desk slot and
::                 the tail as s.bem, and gall's +scry sends anything not
::                 starting with the empty knot to the agent's +on-peek
::                 instead of to the vane's scry farm.
::      1          the namespace version marker gall's +scry requires.
::
::    Built by cons: the empty segment is the one a path literal cannot
::    spell, and the one nobody notices is missing.
::
++  blob-keen-path
  |=  [agent=@ta h=@uv case=@ud]
  ^-  path
  %+  weld  `path`[%g %x (scot %ud case) agent %$ %'1' ~]
  (blob-spur h)
::
::  +blob-page-mark: the page mark a blob is grown under.
::
++  blob-page-mark  ^-(@tas %urmail-blob)
::
::  +digest: the preimage every urmail signature covers.
::
::    The %urmail salt is load-bearing. The same key signs ames packets
::    and attestations; salting keeps those preimage spaces disjoint so
::    an urmail signature can never be replayed as one of those.
::
++  digest
  |=  u=unsigned
  ^-  @
  (shaf %urmail (sham u))
::
++  sign-with
  |=  [=ring msg=@]
  ^-  @ux
  (sigh:as:(nol:nu:cric:crypto ring) msg)
::
++  verify-with
  |=  [=pass sig=@ux msg=@]
  ^-  ?
  (safe:as:(com:nu:cric:crypto pass) sig msg)
::
::  fake ships: jael derives every keypair from the @p, so on a fake ship
::  any ship's keys are computable. This mirrors the fake branch of the
::  %deed scry in sys/vane/jael.hoon.
::
++  fake-core  |=(who=ship (pit:nu:cric:crypto 512 who %b ~))
++  fake-ring  |=(who=ship `ring`sec:ex:(fake-core who))
++  fake-pass  |=(who=ship `pass`pub:ex:(fake-core who))
::
++  id
  |=  u=unsigned
  ^-  msg-id
  (sham u)
::
::  +root: the thread id. Two ships holding the same conversation agree on
::  this without coordinating, because the root message is byte-identical
::  for both.
::
++  root
  |=  c=chain
  ^-  thread-id
  ?~  c  ~|(%urmail-empty-chain !!)
  (id unsigned.i.c)
::
++  participants
  |=  c=chain
  ^-  (set ship)
  %+  roll  c
  |=  [m=msg acc=(set ship)]
  (~(uni in (~(put in acc) from.unsigned.m)) to.unsigned.m)
::
++  last-sent
  |=  c=chain
  ^-  @da
  %+  roll  c
  |=([m=msg acc=@da] ?:((gth sent.unsigned.m acc) sent.unsigned.m acc))
::
++  signers
  |=  c=chain
  ^-  (set [who=ship life=@ud])
  (~(gas in *(set [ship @ud])) (turn c |=(m=msg [from.unsigned.m life.unsigned.m])))
::
::  +merge: union two chains, deduplicating and ordering by sent.
::
::    A message is a duplicate only when its contents AND its signature
::    match. +id covers `unsigned` alone, so two msgs can share an id and
::    carry different signatures - one genuine, one forged. Deduping on the
::    id alone would let whichever arrived first shadow the other, which on
::    a forwarded chain lets a malicious forwarder frame a third party as a
::    forger. Both copies are kept here; +verify-chain labels them and the
::    agent decides what to show.
::
++  merge
  |=  [old=chain new=chain]
  ^-  chain
  =/  key  |=(m=msg [(id unsigned.m) sig.m])
  =/  seen  (~(gas in *(set [msg-id @ux])) (turn old key))
  ::  fold rather than skim: `new` must be deduped against itself too,
  ::  since a peer-supplied chain may repeat a message and `old` is empty
  ::  on first contact.
  =/  added=chain
    =|  acc=chain
    |-  ^-  chain
    ?~  new  (flop acc)
    ?:  (~(has in seen) (key i.new))
      $(new t.new)
    $(new t.new, seen (~(put in seen) (key i.new)), acc [i.new acc])
  %+  sort  (weld old added)
  |=  [a=msg b=msg]
  ?.  =(sent.unsigned.a sent.unsigned.b)
    (lth sent.unsigned.a sent.unsigned.b)
  ?.  =((id unsigned.a) (id unsigned.b))
    (lth (id unsigned.a) (id unsigned.b))
  (lth sig.a sig.b)
::
::  +verify-chain: a verdict per message.
::
::    Keys arrive as a map keyed on [ship life], not just ship: life travels
::    with the message precisely so a signature stays verifiable after the
::    sender rotates, which means one ship can have multiple live keys. A
::    ship/life pair missing from the map is %unverified, never %forged -
::    that is true whether the key is missing because we never fetched that
::    life, or because a tampered life field pointed at a life we don't hold.
::    Keys arrive as a map, keyed this way, so this stays pure: the agent
::    builds it by scrying jael once per distinct [ship life] before calling
::    in.
::
++  verify-chain
  |=  [keys=(map [ship @ud] (unit pass)) c=chain]
  ^-  (list [[msg-id @ux] verdict])
  %+  turn  c
  |=  m=msg
  ^-  [[msg-id @ux] verdict]
  ::  the verdict is keyed on [id sig], not id alone. +merge deliberately
  ::  keeps two copies of one id that differ in signature; keying a verdict
  ::  on the id would collapse %verified and %forged into whichever was
  ::  written first, reinstating the shadowing attack at the state layer.
  :-  [(id unsigned.m) sig.m]
  =/  k  (~(get by keys) [from.unsigned.m life.unsigned.m])
  ?~  k  %unverified
  ?~  u.k  %unverified
  ?:  (verify-with u.u.k sig.m (digest unsigned.m))
    %verified
  %forged
::
::  +prune: enforce the per-id copy bound by SHEDDING, never by rejecting.
::
::    Rejecting the merged result is a censorship primitive: an attacker who
::    lands max-copies forged copies of a chain's genuine root at a ship
::    that has never seen the thread mints that thread under the genuine
::    (content-derived) id, holding it full of junk. When the real chain
::    later arrives from any participant, the count is max-copies+1, a
::    reject would nack it, and because every +send ships the whole chain,
::    every subsequent message in that thread would be rejected forever -
::    for the cost of a few junk-signed messages. It also reinstates, at
::    the state layer, precisely the shadowing +merge exists to prevent:
::    junk arriving first would permanently exclude the genuine copy.
::
::    Shed the excess instead, in strict verdict order: %verified first,
::    then %unverified, then %forged. +merge is keyless and must keep
::    everything it's handed, but the caller knows the verdicts by the time
::    it prunes, so anti-shadowing is enforced with that knowledge rather
::    than by raw arrival order.
::
::    The %unverified rank is not a nicety. EVERY moon and comet message is
::    %unverified in v1 - an entire class of sender, not an edge case - so
::    an unranked fill lets max-copies junk-signature copies evict the one
::    genuine copy of a moon's message, leaving the user holding only
::    forged copies of a message that was never forged. Because every send
::    re-ships the whole accumulated chain, that corrupted chain is then
::    what gets forwarded onward.
::
::    Pure: `vs` and `max-copies` arrive as arguments so this is testable
::    without an agent.
::
++  prune
  |=  [c=chain vs=(map [msg-id @ux] verdict) max-copies=@ud]
  ^-  chain
  =/  groups=(jar msg-id msg)
    %+  roll  c
    |=  [m=msg acc=(jar msg-id msg)]
    (~(add ja acc) (id unsigned.m) m)
  =/  kept=chain
    %-  zing
    %+  turn  ~(tap by groups)
    |=  [i=msg-id ms=(list msg)]
    ^-  chain
    ?:  (lte (lent ms) max-copies)  ms
    =/  vd    |=(m=msg (~(gut by vs) [i sig.m] %unverified))
    =/  good  (skim ms |=(m=msg =(%verified (vd m))))
    =/  fill
      %+  weld  (skim ms |=(m=msg =(%unverified (vd m))))
                (skim ms |=(m=msg =(%forged (vd m))))
    =/  keep  (scag max-copies good)
    (weld keep (scag (sub max-copies (lent keep)) fill))
  ::  re-sort: grouping by id destroyed +merge's ordering
  (merge ~ kept)
::
::  +thread-key: which thread a chain belongs to.
::
::    Never derived from the incoming list's order or from `sent`: +root
::    returns the head as supplied, and an attacker controls both the order
::    and every `sent` field, so either lets one poke duplicate a conversation
::    or migrate an established thread onto a new id. An established thread's
::    identity is immutable once set; a first-contact chain is anchored on the
::    message with prev=~, which is signed content and cannot be forged.
::
::    The root is deduped by id, not counted by message: a hostile relay can
::    forward the genuine root alongside a copy with a tampered signature (the
::    exact shadowing case +merge exists to preserve, see +merge's own doc),
::    and both copies carry prev=~ since prev is part of the signed payload
::    they share. Counting messages instead of distinct ids would reject that
::    otherwise-legitimate first contact outright, which is a self-inflicted
::    denial of the very chain this arm exists to accept.
::
::    Pure: `threads` arrives as an argument rather than off the agent's
::    state, so thread identity - the property an attacker most wants to
::    move - is testable without an agent.
::
::    Not fixing, recorded rather than dropped: the `hits` scan below is
::    O(total stored messages) with a `sham` per message, on the only
::    externally reachable poke. Bounded by max-threads/max-chain, but
::    large. Upgrade path: a (map [msg-id @ux] thread-id) index in state.
::    This is a performance concern, not an authenticity one.
::
++  thread-key
  |=  [threads=(map thread-id thread) c=chain]
  ^-  thread-id
  =/  keys
    (~(gas in *(set [msg-id @ux])) (turn c |=(m=msg [(id unsigned.m) sig.m])))
  =/  hits
    %+  skim  ~(tap by threads)
    |=  [t=thread-id th=thread]
    %+  lien  chain.th
    |=(o=msg (~(has in keys) [(id unsigned.o) sig.o]))
  ::  not fixing: a chain touching two existing threads conflates them here,
  ::  and p.i.hits picks whichever comes first in map-traversal order. This
  ::  predates +thread-key (the same pattern already existed in +send's own
  ::  `hits` lookup) and is equally reachable before and after this fix.
  ::  Upgrade path: reject chains whose keys match more than one thread,
  ::  rather than silently picking one. Also availability/correctness of
  ::  filing, not authenticity - a wrongly-filed message is still exactly
  ::  as verified or forged as it was.
  ?^  hits  p.i.hits
  =/  roots  (skim c |=(m=msg ?=(~ prev.unsigned.m)))
  =/  root-ids
    (~(gas in *(set msg-id)) (turn roots |=(m=msg (id unsigned.m))))
  ?.  =(1 ~(wyt in root-ids))  ~|(%urmail-no-unique-root !!)
  (snag 0 ~(tap in root-ids))
::
::  ── the thread as a tree ────────────────────────────────────────────
::
::  `prev` has always made a thread a TREE. Two people replying to the
::  same message are siblings, and mail threads branch constantly. The
::  arms below read that structure out of the field the format already
::  carries, so NOTHING SIGNED CHANGES: `prev` is the branching, and
::  everything here is a different way of looking at it.
::
::  Two things depend on them. Forwarding ships a ROOT-TO-LEAF PATH
::  rather than a whole thread, which is what stops a forward leaking
::  the sibling branch a third party never asked for; and the nexus
::  stores a message under its ancestry, so a message's path IS its
::  ancestry and two branches are two sibling directories.
::
::  +prev-map: every distinct message id in a chain, to its `prev`.
::
::    Keyed by id and NOT by [id sig], on purpose. `prev` sits inside
::    `unsigned` and msg-id is (sham unsigned), so every copy of one id
::    carries the same `prev` by construction. Two copies differing in
::    signature are ONE NODE of the tree carrying two grubs, which is
::    the [id sig] anti-shadowing key expressed as shape rather than
::    weakened by it.
::
++  prev-map
  |=  c=chain
  ^-  (map msg-id (unit msg-id))
  %-  ~(gas by *(map msg-id (unit msg-id)))
  (turn c |=(m=msg [(id unsigned.m) prev.unsigned.m]))
::
::  +ancestors: the id path from a forest root down to `i`, inclusive.
::
::    Walks `prev` upward and comes back root-first. Three ways to stop,
::    and each one is a root of the forest this chain describes:
::
::      prev=~             the thread root. The ordinary case, and the
::                         only one a well-formed chain reaches.
::      prev unresolvable  an ORPHAN: a message whose parent is not in
::                         this chain. Only hostile input makes one - a
::                         forwarded path is complete by construction,
::                         and +prune never sheds the last copy of an id
::                         - and it is PLACED rather than dropped,
::                         because refusing to store a message is worse
::                         than filing it shallow. An orphan that is
::                         later joined to its parent simply moves.
::      the bound          a cycle. `prev` is a hash of the parent's
::                         contents, so a cycle needs a hash preimage
::                         loop; but this runs on attacker-supplied
::                         input inside the WRITER, which must never
::                         hang, and the guard costs one comparison.
::                         No acyclic path can be longer than the number
::                         of distinct ids.
::
++  ancestors
  |=  [ps=(map msg-id (unit msg-id)) i=msg-id]
  ^-  (list msg-id)
  =|  acc=(list msg-id)
  =/  cur=msg-id  i
  =/  bound=@ud   ~(wyt by ps)
  |-  ^-  (list msg-id)
  ?:  =(0 bound)  [cur acc]
  =/  p=(unit (unit msg-id))  (~(get by ps) cur)
  ?~  p  [cur acc]
  ?~  u.p  [cur acc]
  ?.  (~(has by ps) u.u.p)  [cur acc]
  $(cur u.u.p, acc [cur acc], bound (dec bound))
::
::  +place-of: where one message sits in the forest a chain describes.
::
++  place-of
  |=  [c=chain i=msg-id]
  ^-  (list msg-id)
  (ancestors (prev-map c) i)
::
::  +ancestor-map: +place-of for every id at once, which is what the
::  storage layer needs when it lays a whole merged chain down.
::
++  ancestor-map
  |=  c=chain
  ^-  (map msg-id (list msg-id))
  =/  ps  (prev-map c)
  %-  ~(gas by *(map msg-id (list msg-id)))
  %+  turn  ~(tap by ps)
  |=([i=msg-id *] [i (ancestors ps i)])
::
::  +path-chain: THE CHAIN A FORWARD SHIPS. Root to the named message,
::  and nothing else.
::
::    A chain is a root-to-leaf PATH, not a whole thread. That is what
::    "a portable communication chain" meant all along: the conversation
::    leading to a message, which is exactly what a recipient needs to
::    verify it and exactly what `prev` already describes.
::
::    Shipping the whole thread instead was a LEAK, not an
::    inelegance. Two participants have a side exchange on one branch;
::    one of them forwards a message on a different branch onward; the
::    third party receives the side exchange, signed, permanent and
::    attributable, having asked for none of it.
::
::    The result is a valid chain on its own: every `prev` in it
::    resolves inside it, and it holds the unique prev=~ root, so
::    +thread-key files it under the same thread id and every message
::    still verifies independently.
::
::    EVERY COPY at each node travels, not one per node. Choosing which
::    of two copies of one message to forward would be exactly the
::    shadowing +merge exists to prevent, decided by the forwarder.
::
++  path-chain
  |=  [c=chain i=msg-id]
  ^-  chain
  =/  keep=(set msg-id)  (~(gas in *(set msg-id)) (ancestors (prev-map c) i))
  (merge ~ (skim c |=(m=msg (~(has in keep) (id unsigned.m)))))
::
::  +with-root: a path that never reaches the thread root, plus the root.
::
::    A well-formed path ends at prev=~ and this is a no-op. It fires
::    only for an ORPHAN branch (see +ancestors), where shipping the
::    path alone would hand the recipient a chain with no prev=~ message
::    at all - which +thread-key refuses outright, so the send would
::    look successful here and be dropped at the far end. The root is a
::    message every participant in the thread already holds, and it is
::    what the thread's identity is derived from, so adding it discloses
::    nothing and is what makes the chain filable.
::
++  with-root
  |=  [c=chain p=chain]
  ^-  chain
  ?:  (lien p |=(m=msg ?=(~ prev.unsigned.m)))  p
  (merge p (skim c |=(m=msg ?=(~ prev.unsigned.m))))
::
::  ── the forest, as storage paths ────────────────────────────────────
::
::  Pure path algebra, kept here rather than in the nexus so the layout
::  logic is reachable by -test. The nexus stores a copy at
::  <ancestry as directories>/<slot>, so these arms turn an ancestry
::  into directories and answer the three questions a sync has to ask:
::  which directories a set of copies needs, which of the ones on disk
::  are no longer wanted, and whether a copy is already covered by a
::  directory about to be culled.
::
++  id-path
  |=  is=(list msg-id)
  ^-  path
  (turn is |=(i=msg-id `@ta`(scot %uv i)))
::
::  +prefixes: every non-empty prefix of a path, SHORTEST FIRST.
::
::    The order is load-bearing: a directory cannot be made before its
::    parent exists.
::
++  prefixes
  |=  p=path
  ^-  (list path)
  =|  acc=(list path)
  =/  cur=path  ~
  |-  ^-  (list path)
  ?~  p  (flop acc)
  =.  cur  (snoc cur i.p)
  $(p t.p, acc [cur acc])
::
::  +node-dirs: every directory a set of copy paths needs.
::
::    A copy path is <ancestry>/<slot>, so the directories are the
::    prefixes of everything but its last element. A path of length one
::    is a PRE-TREE grub stored flat under msg/ and needs no directory
::    at all, which is how the migration recognises one.
::
++  node-dirs
  |=  ps=(list path)
  ^-  (set path)
  %-  ~(gas in *(set path))
  (zing (turn ps |=(p=path (prefixes (snip p)))))
::
::  +minimal-dirs: the shallowest directories of a set to cull.
::
::    Culling a directory takes its whole subtree, so culling a child
::    after its parent is at best wasted and at worst a cull of a road
::    that no longer exists.
::
++  minimal-dirs
  |=  ds=(set path)
  ^-  (list path)
  (skim ~(tap in ds) |=(p=path !(~(has in ds) (snip p))))
::
::  +under-any: does this path sit inside one of these directories?
::
++  under-any
  |=  [p=path ds=(set path)]
  ^-  ?
  (lien ~(tap in ds) |=(d=path =(d (scag (lent d) p))))
::
::
::  +freeze: fold new verdicts into the stored map, definitively-labeled
::  entries first.
::
::    %unverified freezes only against another %unverified: it is not a
::    finding about the signature, only that the key was absent from our
::    snapshot at that instant, and a later poke may arrive after we have
::    fetched the key. %verified and %forged are definitive for a fixed
::    [id sig] - the digest and the key are both fixed - so they can never
::    disagree with each other, and freezing only those two is safe.
::
::    Keyed [id sig], so the two copies of one id that +merge deliberately
::    keeps are labeled separately and never collide.
::
++  freeze
  |=  $:  old=(map [msg-id @ux] verdict)
          new=(list [[msg-id @ux] verdict])
      ==
  ^-  (map [msg-id @ux] verdict)
  =/  acc  old
  |-  ^-  (map [msg-id @ux] verdict)
  ?~  new  acc
  ?:  ?=(?(%verified %forged) (~(gut by acc) -.i.new %unverified))
    $(new t.new)
  $(new t.new, acc (~(put by acc) -.i.new +.i.new))
::
::  the input caps, as predicates. The agent wraps each in its own tall ~|
::  and ?>, since the label is what tells a nacked poke apart from any
::  other crash; keeping the arithmetic here keeps it testable.
::
++  fits-length
  |=([c=chain m=@ud] (lte (lent c) m))
::
++  fits-bodies
  |=([c=chain m=@ud] (levy c |=(x=msg (lte (met 3 body.unsigned.x) m))))
::
++  fits-subjects
  |=([c=chain m=@ud] (levy c |=(x=msg (lte (met 3 subj.unsigned.x) m))))
::
++  fits-recipients
  |=([c=chain m=@ud] (levy c |=(x=msg (lte ~(wyt in to.unsigned.x) m))))
::
::  the body's own mime type, checked exactly as an attachment's is:
::  length-capped AND control-free, refused at the boundary because a
::  recipient cannot repair a signed field.
::
++  fits-body-mimes
  |=([c=chain m=@ud] (levy c |=(x=msg (text-ok body-mime.unsigned.x m))))
::
::  distinct message ids, not messages: +merge deliberately keeps several
::  signed copies of one id, and the state-capacity bound counts messages
::  the user could actually read, not copies of them.
::
++  distinct-ids
  |=  c=chain
  ^-  @ud
  ~(wyt in (~(gas in *(set msg-id)) (turn c |=(m=msg (id unsigned.m)))))
::
::  +max-ancestry: the deepest root-to-leaf path a chain describes.
::
::    One +prev-map and one walk per distinct id, which is the work
::    +ancestor-map already does to store the chain - so checking costs
::    no more than accepting, and it is +ancestors that bounds the walk
::    against a cycle.
::
++  max-ancestry
  |=  c=chain
  ^-  @ud
  =/  ps  (prev-map c)
  %+  roll  ~(tap by ps)
  |=  [[i=msg-id *] acc=@ud]
  =/  n  (lent (ancestors ps i))
  ?:((gth n acc) n acc)
::
++  fits-depth
  |=([c=chain m=@ud] (lte (max-ancestry c) m))
--

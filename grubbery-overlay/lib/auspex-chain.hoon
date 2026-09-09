::  auspex-chain: the pure crypto and chain algebra, plus the types it is
::  written against.
::
::    Ported verbatim from the %urmail desk's lib/urmail.hoon and
::    sur/urmail.hoon - the app was called urmail until 2026-09-09, and
::    that desk still carries the old name. Every arm keeps its
::    behaviour: signing and
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
::    %send's `files` carry BYTES, so %send is the one action with a size
::    to it, and it is the only way bytes ever enter this ship's blob
::    store from the user side. There is no separate attach action: the
::    files ride on the send that names them, because the metadata built
::    from those bytes goes inside `unsigned` and is therefore signed -
::    hashing and signing in one step is what makes `size` and `hash`
::    agree with what a fetcher will re-measure. A prior draft of this
::    comment described a %attach-file member; there has never been one.
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
    ::  %send-ref is %send with the bytes ALREADY IN THE STORE. It is
    ::  the web surface's send: the browser uploads each file to
    ::  POST /api/blob first, which stores it and answers its content
    ::  address, and the send then names those addresses. A separate
    ::  member rather than a tenth field on %send, so a programmatic
    ::  poke written against %send keeps working unchanged.
    ::
    ::  Both end in the same signing path; they differ only in where
    ::  the signed [name size mime hash] comes from. Here `size` is
    ::  read off the stored blob and never off the request, so the
    ::  nexus signs what it stores.
      $:  %send-ref
          to=(set ship)
          subj=@t
          body=@t
          body-mime=@t
          prev=(unit msg-id)
          refs=(list attach-ref)
          bcc=(set ship)
      ==
      [%read ids=(set msg-id)]
      [%delete-thread =thread-id]
      [%fetch-blob hash=@uv from=ship]
      [%restrict-blob hash=@uv ships=(set ship)]
      [%publish-blob hash=@uv]
    ::  ── the mail-client actions. Every one is LOCAL STATE ──────────
    ::
    ::  None of these touch `unsigned`, none produce or alter a
    ::  signature, and none of them may move the change beacon: they
    ::  change a thread in ways no other ship can see, and the beacon
    ::  exists to tell OTHER open readers that content moved. Labelling
    ::  a thread and then having every open tab refetch the mailbox is
    ::  the read-mark storm again, wearing a different hat.
    ::
    ::  %label carries one label and a direction rather than a whole
    ::  set, so two tabs adding two different labels do not clobber each
    ::  other: a set-valued action is last-write-wins over everything
    ::  the other tab did.
      [%label =thread-id label=@tas add=?]
      [%archive =thread-id archived=?]
    ::  %unread is the exact inverse of %read, over the same set and
    ::  the same grouping pass. Forged messages never counted toward
    ::  unread in the first place (see +entry-json), so marking one
    ::  unread is a no-op on every surface a user sees - which is the
    ::  correct behaviour and not a special case anywhere.
      [%unread ids=(set msg-id)]
    ::  drafts. %send-draft signs and sends, and deletes the draft ONLY
    ::  if the send succeeded - see +do-send-draft.
      [%save-draft =draft]
      [%delete-draft id=@uv]
      [%send-draft id=@uv]
    ::  filters.
      [%save-rule =rule]
      [%delete-rule id=@uv]
    ::  mailing lists. `name` is the KEY, not a field of the grub: it is
    ::  the path segment under /mail/list, so it is carried on the
    ::  action rather than inside $mail-list. %save-list is a plain
    ::  OVERWRITE and that is the whole verb - create, add a member,
    ::  drop one, rename by re-saving under a new name, and copy the
    ::  membership off a message are all this one action, because a list
    ::  is a set of ships and nothing else.
      [%save-list name=@t members=(set ship)]
      [%delete-list name=@t]
  ==
::
::  $file: one file as handed to %send, before it is hashed and stored.
::
::    The DOJO shape, and only that. Bytes reach the writer this way
::    from a programmatic %send; the web surface uploads them first and
::    names the result, which is $attach-ref below.
::
+$  file  [name=@t mime=@t =octs]
::
::  $attach-ref: a file the ship ALREADY HOLDS, named for a send.
::
::    The upload route stored the bytes and answered their content
::    address; this is the sender naming one. There is no `size` here
::    and there deliberately cannot be: the size that gets SIGNED is
::    read off the stored blob, so a client cannot make the signature
::    say the file is a length it is not. The hash is not re-derived
::    either - the store only holds blobs that hashed correctly at
::    ingest, so re-hashing on send would be paying for a fact the
::    store already guarantees.
::
+$  attach-ref  [name=@t mime=@t hash=@uv]
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
::  ── the mail-client layer: local state, never signed ────────────────
::
::  Everything from here down is the right-hand column of the spec's
::  "Local versus signed" table. None of it touches `unsigned`, none of
::  it travels, and two ships may disagree about all of it.
::
::  $draft: a message that has not been signed, at /mail/draft/<id>.
::
::    A DRAFT IS NOT A MESSAGE AND MUST NEVER BE RENDERABLE AS ONE. It
::    carries no `from`, no `life`, no `sent` and no signature, because
::    there is nothing to sign yet: signing happens at the moment of
::    send, once, over the fields as they stand then. Anything that
::    could show a draft in a thread would be showing an unsigned,
::    unauthenticated message beside signed ones, which is the one
::    confusion this whole product exists to remove.
::
::    Two things enforce that structurally rather than by care. It is
::    stored OUTSIDE /mail/thread, so no tree walk that produces
::    messages can reach it; and its shape shares no prefix with
::    $stored-msg (%0 against %2), so the `;;` ladder that reads a
::    stored copy refuses a draft noun outright. See
::    +test-a-draft-is-not-a-stored-message.
::
::    `id` is minted by the client, not here: a draft id is local,
::    means nothing on any other ship, and never appears in a
::    signature. The client holding it from the first save is what
::    makes a debounced save overwrite one grub instead of laying a new
::    one per keystroke - the write path stays a fire-and-forget poke,
::    exactly like every other action.
::
::    Versioned like every other persisted shape, and version 0 is the
::    first. The spec writes the field list without a version head; the
::    head is added because every persisted grub on this nexus is read
::    back through a `;;` ladder and a shape with no version cannot be
::    laddered later without booming what is already on disk.
::
+$  draft
  $:  %0
      id=@uv
      to=(set ship)
      subj=@t
      body=@t
      prev=(unit msg-id)
      at=@da
  ==
::
::  $rule: one delivery filter, at /mail/rule/<id>.
::
::    APPLIED AFTER VERIFICATION, NEVER BEFORE, and the shape is what
::    enforces it: a rule may add labels and it may archive, and there
::    is no field for deleting, rejecting or marking read. A filter that
::    could suppress a message would let an attacker who learns your
::    rules hide the evidence of their own forgery - subject lines are
::    guessable and a rule is a standing instruction, so "quarantine
::    anything from ~evil" would be exactly the wrong tool.
::
::    Archiving is not suppression: an archived thread is one view away,
::    still counted, still searchable, and new mail in it un-archives it.
::
+$  rule
  $:  %0
      id=@uv
      from=(unit ship)
      subject=(unit @t)
      add=(set @tas)
      archive=?
  ==
::
::  $mail-list: one mailing list's members, at /mail/list/<name>.
::
::    A LIST NAME NEVER TRAVELS. The name is the PATH SEGMENT and is
::    deliberately not a field here: nothing may carry it into a signed
::    message, and a name stored beside the members would be one more
::    place a serialiser could pick it up from. What a recipient sees in
::    `to` is ships, always, exactly as if they had been typed one at a
::    time - which is what makes "copy the list off this month's message
::    and overwrite it for next month" correct rather than a
::    reconstruction: there is nothing to reconstruct, because the list
::    was never part of the message.
::
::    Local and unsigned, like a draft and a rule. Two ships may hold
::    lists of the same name with different members and neither is
::    wrong; no delivery, no verdict and no signature depends on any of
::    it. A list write does not move the change beacon for the same
::    reason a rule write does not: no other reader can observe it.
::
::    Members are ships and never other lists. Nesting would make a send
::    depend on a resolution order the recipient cannot see, and the
::    whole design here is that the audience on screen is the audience
::    that is sent.
::
::    An empty member set is allowed: a list you are still filling is a
::    real state, and refusing it would mean the only way to make one is
::    to know every member first.
::
+$  mail-list
  $:  %0
      members=(set ship)
  ==
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
::  +max-signers: distinct [ship life] pairs one delivered chain may name.
::
::    THIS IS THE ONE CAP THAT BOUNDS WORK OFF THIS SHIP. Every other
::    limit here bounds bytes or nodes; this one bounds ROUND TRIPS. The
::    nexus verifies a chain against real keys, and a key comes from a
::    scry to /sys/scry per distinct [ship life] - see +key-map. Nothing
::    bounded how many of those one poke could ask for, so the ceiling
::    was max-chain: a single junk chain from any ship on the network
::    could name a thousand distinct signers and buy a thousand
::    sequential internal round trips, plus a thousand ed25519 verifies
::    and a deep peek of the whole mail tree, on the ship's SINGLE
::    serialisation point for mail. /main.sig is granted to the `public`
::    usergroup by design - that is what makes delivery from any ship
::    work - so the price of that was one poke, and a forged signature
::    costs exactly what a real one does.
::
::    128, and the number is chosen against max-to rather than against
::    what a conversation looks like. A real thread has a few dozen
::    distinct authors at the outside. But one message may already name
::    max-to (100) recipients, so a thread in which every named
::    recipient replies once is a hundred signers and is legitimate
::    under the caps as they stand; 128 clears that with room for the
::    key rotations that make one ship two entries here, since a signer
::    is [ship life] and not a ship. Refusing at 64 would have refused
::    mail the rest of this file admits, and a refusal is permanent -
::    the chain is rejected whole, every later poke of that thread with
::    it, and the user never gets the mail. The DoS argument does not
::    distinguish 64 from 128; the correctness argument does.
::
::    DEFERRED, AND SAID PLAINLY: this caps one poke, not a sender. A
::    peer willing to send a thousand pokes still buys a thousand times
::    this. The real answer is a per-source rate budget on /main.sig,
::    which is a scheduling problem and not a predicate; this is the
::    cheap 80% and is not a substitute for it.
::
++  max-signers  128          ::  distinct [ship life] pairs per chain
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
::  +attach-ok: is this attachment's METADATA storable at all?
::
::    The whole of +file-ok that does not need the bytes, so the two
::    paths into a send - files with octs, and refs naming blobs the
::    store already holds - are checked by ONE arm and cannot drift.
::    Everything it enforces was enforced before it existed: size
::    against max-blob, name and mime through +text-ok.
::
++  attach-ok
  |=  a=attachment
  ^-  ?
  ?&  (lte size.a max-blob)
      (text-ok name.a max-name)
      (text-ok mime.a max-mime)
  ==
::
++  attaches-ok
  |=  as=(list attachment)
  ^-  ?
  ?&  (lte (lent as) max-attach)
      (levy as attach-ok)
  ==
::
::  +refs-ok: everything about a named attachment that can be checked
::  WITHOUT READING THE BLOB.
::
::    The boundary's half of +attaches-ok. A ref carries no size, and
::    reading one off the store costs a peek of the bytes per file - on
::    the request fiber, sixteen times, for a send that has not been
::    signed yet. So the route checks the count and the two hostile
::    strings here and leaves `size` to the writer, which has to read
::    the blob anyway to sign it. Nothing is skipped: size against
::    max-blob is enforced by the upload route, which refuses an
::    oversized body with a 413 before it stores anything, and again by
::    +attaches-ok at the point of use.
::
++  ref-ok
  |=  r=attach-ref
  ^-  ?
  ?&  (text-ok name.r max-name)
      (text-ok mime.r max-mime)
  ==
::
++  refs-ok
  |=  rs=(list attach-ref)
  ^-  ?
  ?&  (lte (lent rs) max-attach)
      (levy rs ref-ok)
  ==
::
::  +file-ok: is this file storable at all?
::
::    +attach-ok plus the one check only bytes can carry. p.octs is the
::    DECLARED length and q is the atom. An atom cannot carry more bytes
::    than it measures, so a declared length below the measured one is a
::    malformed octs and would make +blob-hash disagree with anything the
::    bytes are later re-measured against.
::
++  file-ok
  |=  f=file
  ^-  ?
  ?&  (gte p.octs.f (met 3 q.octs.f))
      (attach-ok [name.f p.octs.f mime.f *@uv])
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
      (levy as attach-ok)
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
::    grubbery yoke (lattice grows at /pub/page/...), so auspex names its
::    own prefix. Content-addressed, and there is NO revision segment:
::    lattice needs one because a page is mutable and the namespace
::    requires an immutable binding per spur, while a blob's bytes are
::    fixed by its name. That is the whole reason this fetch needs no
::    rev-discovery channel, and rev-discovery is the weir-gated part.
::
++  blob-spur
  |=  h=@uv
  ^-  path
  /auspex/blob/[(scot %uv h)]
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
::                 nexus. auspex lives inside %grubbery.
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
++  blob-page-mark  ^-(@tas %auspex-blob)
::
::  +digest: the preimage every auspex signature covers.
::
::    The %auspex salt is load-bearing. The same key signs ames packets
::    and attestations; salting keeps those preimage spaces disjoint so
::    an auspex signature can never be replayed as one of those.
::
++  digest
  |=  u=unsigned
  ^-  @
  (shaf %auspex (sham u))
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
  ?~  c  ~|(%auspex-empty-chain !!)
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
  ?.  =(1 ~(wyt in root-ids))  ~|(%auspex-no-unique-root !!)
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
::  +fits-signers: how many distinct keys verifying this chain would cost.
::
::    Not a per-message predicate like its neighbours - it counts the
::    SET, because that is what the caller pays for: one scry per
::    distinct [ship life], however many messages share it. A thousand
::    messages from one sender is one key; a thousand messages from a
::    thousand senders is a thousand round trips. See +max-signers.
::
++  fits-signers
  |=([c=chain m=@ud] (lte ~(wyt in (signers c)) m))
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
::
::  ── the mail-client predicates ──────────────────────────────────────
::
::  All pure, all import-free, and therefore all reachable by -test. The
::  nexus arms that use them are fibers and are not; keeping every
::  decision that can be stated as a function on this side is what makes
::  the views testable at all.
::
::  +max-label / +max-labels: a label is a @tas the user typed.
::
::    Capped for the same reason every other user-supplied field is: it
::    is rendered, it is stored per thread, and a label nobody can read
::    off a sidebar is not a label. The count bound is per thread, so no
::    single thread's meta can be grown without limit by a client that
::    keeps adding.
::
++  max-label   32           ::  bytes in one label
++  max-labels  64           ::  labels on one thread
::  +max-rules: filters this ship will hold.
::
::    Every rule is evaluated against every delivered chain, on the
::    writer, which is the ship's single serialisation point for mail.
::    That is a small cost per rule and an unbounded one with no bound.
::
++  max-rules   64
::  +max-lists: mailing lists this ship will hold.
::
::    Bounded like the rules are, and for a weaker reason: a list costs
::    nothing on delivery, but every list is one grub under /mail/list
::    and the whole directory is read on every save and every listing.
::
++  max-lists   64
::  +max-drafts: drafts this ship will hold.
++  max-drafts  1.000
::  +max-page: the largest listing page a request may ask for.
::
::    A page is rendered whole into one JSON response on one request
::    fiber, so the bound is on the response, not on the walk: the walk
::    over every stored thread is paid either way and is what `total`
::    counts.
::
++  max-page    200
::
::  +term-ok: is this atom actually a @tas?
::
::    A label arrives as a JSON string and is stored in a `(set @tas)`,
::    where nothing re-checks it: an atom is an atom, so a cord holding
::    a space or a capital letter would sit in that set and render
::    through `scot %tas` - which crashes. On a request fiber that is an
::    HTTP connection that never answers, so the check happens at the
::    boundary instead, and this is it.
::
++  term-ok
  |=  l=@tas
  ^-  ?
  =/  t=tape  (trip l)
  ?~  t  |
  ?.  &((gte i.t 'a') (lte i.t 'z'))  |
  ::  `tape`t, not t: ?~ has narrowed t to a NON-EMPTY tape and +levy
  ::  recurses on its own sample, so the recursion hands ~ to a gate
  ::  whose sample type no longer admits it. Same shape as the +scag
  ::  call in +has-sub below, and it is the standard cost of calling a
  ::  wet list gate from inside a ?~.
  %+  levy  `tape`t
  |=  c=@tD
  ?|  &((gte c 'a') (lte c 'z'))
      &((gte c '0') (lte c '9'))
      =(c '-')
  ==
::
++  label-ok
  |=(l=@tas &((term-ok l) (lte (met 3 l) max-label)))
::
++  labels-ok
  |=  ls=(set @tas)
  ^-  ?
  &((lte ~(wyt in ls) max-labels) (levy ~(tap in ls) label-ok))
::
::  +has-sub: does `hay` contain `ned`, case-insensitively?
::
::    The one string primitive this layer needs, shared by search and by
::    the filters' subject match so the two cannot disagree about what a
::    substring is. Case-insensitive because a user typing into a search
::    box is not making a statement about capitalisation - and because a
::    filter that missed "Invoice" while matching "invoice" would be a
::    filter that silently does not work.
::
::    An empty needle matches everything, which is what makes an absent
::    query mean "no filter" at every call site without a branch.
::
++  has-sub
  |=  [hay=@t ned=@t]
  ^-  ?
  =/  n=tape  (cass (trip ned))
  ?:  =(~ n)  &
  =/  ln=@ud  (lent n)
  =/  h=tape  (cass (trip hay))
  |-  ^-  ?
  ?~  h  |
  ::  `tape`h, not h: ?~ has narrowed h to a NON-EMPTY tape, +scag is a
  ::  wet gate casting its result to ^+ its sample, and one of its
  ::  branches produces ~ - which does not nest under a non-empty list.
  ::  Widening at the call site is the fix; the same shape bites every
  ::  wet list gate called from inside a ?~.
  ?:  =(n (scag ln `tape`h))  &
  $(h t.h)
::
::  +matches: does one message answer this query?
::
::    Subject, body and sender, which is the set the spec names. The
::    sender is matched on its rendered @p, so typing part of a ship
::    name finds it.
::
::    IT DOES NOT LOOK AT THE VERDICT. Search covers %forged messages
::    exactly as it covers every other, and the result carries the
::    verdict so the reader sees which it found. Hiding a forged message
::    from search would be the same mistake as filtering it out of a
::    thread: the forgery is the thing worth finding.
::
++  matches
  |=  [q=@t u=unsigned]
  ^-  ?
  ?:  =('' q)  &
  ?|  (has-sub subj.u q)
      (has-sub body.u q)
      (has-sub (scot %p from.u) q)
  ==
::
++  chain-matches
  |=  [q=@t c=chain]
  ^-  ?
  ?:  =('' q)  &
  (lien c |=(m=msg (matches q unsigned.m)))
::
::  +newest-match: the newest message in a chain answering the query.
::
::    What a search result row draws its sender, subject and VERDICT
::    from. Drawing them from the newest non-forged copy - which is what
::    an ordinary listing row does, and rightly - would answer a search
::    for a forged message with a row labelled `verified`, naming a
::    ship that did not write the thing that matched. A search says what
::    it found.
::
++  newest-match
  |=  [q=@t c=chain]
  ^-  (unit msg)
  ?:  =('' q)  ~
  =/  hits=chain  (skim c |=(m=msg (matches q unsigned.m)))
  ?~(hits ~ `(rear hits))
::
::  +in-inbox: PARTICIPANT OR DIRECT, and not archived.
::
::    `direct` is set when a chain arrived through a delivery poke, and
::    it is what makes BCC work at all: a blind-copied recipient is in
::    neither `from` nor `to` of any message in the chain, so a
::    participant-only Inbox would hide their mail completely. The flag
::    has existed since the BCC decision and nothing read it until now.
::
++  in-inbox
  |=  [our=ship ps=(set ship) archived=? direct=?]
  ^-  ?
  &(!archived ?|((~(has in ps) our) direct))
::
::  +in-sent: did we write any message in this thread?
::
::    A walk, not a stored set. Authorship is a signed field, so the
::    question is answerable from the chain itself and a second record
::    of it could only ever disagree with the first.
::
++  in-sent
  |=  [our=ship c=chain]
  ^-  ?
  (lien c |=(m=msg =(our from.unsigned.m)))
::
::  +page: one page of a list, and nothing else.
::
::    `total` is the length of the list handed in, computed by the
::    caller before this is called - so the caller reports the size of
::    the view and renders only the page. A limit of 0 is an empty page
::    rather than "everything": the route defaults an absent limit
::    instead, so 0 can stay literal here.
::
++  page
  |*  [l=(list) off=@ud lim=@ud]
  ^+  l
  ?:  =(0 lim)  ~
  (scag lim (slag off l))
::
::  +draft-ok: the request-only caps, on a draft.
::
::    The same three bounds a send is checked against, applied when the
::    draft is SAVED rather than only when it is sent. A draft that
::    cannot be sent is a message the user will lose at the last moment,
::    and the point of drafts is that nothing is lost.
::
++  draft-ok
  |=  d=draft
  ^-  ?
  ?&  (lte (met 3 body.d) max-body)
      (lte (met 3 subj.d) max-subj)
      (lte ~(wyt in to.d) max-to)
  ==
::
::  +rule-ok: a rule that can be stored.
::
::    A rule with neither a sender nor a subject matches EVERY delivered
::    chain. That is refused: with `archive` set it would empty the
::    inbox permanently and silently, and the user who wrote it would
::    see mail stop arriving rather than an error. At least one
::    condition, so a rule is always a statement about some mail rather
::    than about all of it.
::
::    AN EMPTY SUBJECT IS NOT A CONDITION, and the distinction is not
::    pedantry. `[~ '']` is a cell, so a presence check passes it; the
::    length check passes on zero bytes; and +has-sub answers %.y for an
::    empty needle, deliberately, because that is what lets an absent
::    search query mean "no filter" with no branch at any call site.
::    Those three correct decisions compose into a rule that fires on
::    every delivered chain - the exact rule this arm exists to refuse,
::    arriving through the one door the presence check leaves open. A
::    JSON body carrying "subject": "" decodes straight to it.
::
::    So a condition is present AND non-empty, here, once, rather than
::    at each of the places that ask whether a rule has one.
::
++  rule-ok
  |=  r=rule
  ^-  ?
  ?&  ?|(?=(^ from.r) (has-subject r))
      ?~(subject.r & (lte (met 3 u.subject.r) max-subj))
      (labels-ok add.r)
  ==
::
::  +has-subject: does this rule actually constrain the subject?
::
++  has-subject
  |=  r=rule
  ^-  ?
  ?&(?=(^ subject.r) !=('' u.subject.r))
::
::  +rule-matches: one rule against one message. AND across the
::  conditions a rule actually sets; an absent condition is not a
::  condition.
::
++  rule-matches
  |=  [r=rule u=unsigned]
  ^-  ?
  ?&  ?~(from.r & =(u.from.r from.u))
      ?~(subject.r & (has-sub subj.u u.subject.r))
  ==
::
::  +rule-hits: does this rule match ANY message in the delivered chain?
::
::    Any, not the newest: a chain carries the whole path leading to the
::    message that prompted the delivery, and a rule about a sender is a
::    statement about the conversation they are in.
::
++  rule-hits
  |=  [r=rule c=chain]
  ^-  ?
  (lien c |=(m=msg (rule-matches r unsigned.m)))
::
::  +apply-rules: what the matching rules ask for, together.
::
::    Labels union and archive ORs, so rules compose rather than
::    override. There is deliberately no way for one rule to un-archive
::    or to remove a label: a rule is additive, and additive is what
::    makes "a filter cannot suppress a message" a property of the type
::    rather than a promise in a comment.
::
::    Written as two folds over the matching rules rather than one
::    +roll with a tuple accumulator, because that accumulator's bunt
::    would carry `archive=%.y` - a bare ? bunts loud, which is the same
::    trap `archived` in $meta already carries a $~ for.
::
++  apply-rules
  |=  [rs=(list rule) c=chain]
  ^-  [add=(set @tas) archive=?]
  =/  hits=(list rule)  (skim rs |=(r=rule (rule-hits r c)))
  :-  (~(gas in *(set @tas)) (zing (turn hits |=(r=rule ~(tap in add.r)))))
  (lien hits |=(r=rule archive.r))

::  ── protocol discovery ──────────────────────────────────────────────
::
::  A poke of a mark the far end does not carry PARKS. A blot with no
::  marc never acks, so the sender's fiber sits on its deadline and the
::  user is told "timed out" - which is what a ship that is merely
::  offline looks like, and what a ship running a different Auspex looks
::  like, and what a ship running no Auspex at all looks like. Three
::  different facts, one indistinguishable symptom, none of them
::  actionable.
::
::  So a nexus PUBLISHES what it speaks and a sender ASKS before it
::  pokes. The published noun is $proto; it is bound in the permissionless
::  scry farm exactly as an attachment's bytes are, because the same
::  property is wanted: any ship may read it, and nothing about the
::  reader is checked.
::
::  Everything here is PURE and takes the peer's answer as an argument.
::  The keen belongs to a fiber; the choosing does not, and the choosing
::  is the part with rules in it.
::
::  $proto-caps: the receiver's limits, published so a sender can refuse
::  a message the receiver would refuse.
::
::    Every field is one of the cap arms above, NEVER a retyped number.
::    A published cap that disagreed with the enforced one would be worse
::    than publishing nothing: it would make a sender confident about a
::    send the receiver then drops.
::
+$  proto-caps
  $:  max-blob=@ud
      max-attach=@ud
      max-chain=@ud
      max-body=@ud
      max-subj=@ud
      max-to=@ud
      max-depth=@ud
      max-signers=@ud
      max-mime=@ud
      max-name=@ud
  ==
::
::  $proto: what one nexus speaks, as published at /proto.
::
::    `versions` and `marks` are PARALLEL: the mark for version N is the
::    entry at N's index. Two lists rather than a (map @ud @tas) because
::    this noun is jammed into a scry farm and read by an implementation
::    that may not be this one - a list is a shape anything can walk, a
::    treap is a shape you have to know.
::
::    The head is %auspex and not a version number. Versioning lives in
::    `versions`; the head is what tells a reader that the noun it just
::    keened from a shared namespace is ours at all.
::
+$  proto  [%auspex versions=(list @ud) marks=(list @tas) caps=proto-caps]
::
::  $peer-rec: one cached discovery answer, at /mail/peer/<ship>.
::
::    LOCAL STATE. It never travels, no verdict depends on it, and two
::    ships may hold different records for the same third ship without
::    either being wrong - it is a snapshot of what that ship published
::    at `asked`.
::
::    `proto=~` is a REMEMBERED SILENCE and not an absent record: the
::    peer was asked and did not answer, so it is treated as version 1
::    until the record expires. Without that distinction every send to a
::    ship that does not publish /proto would pay a fresh timeout.
::
::    `who` rides INSIDE the record so that the same shape is both the
::    stored grub and the wire poke a request fiber hands the writer.
::    One marc, one ladder, and a record that names its own subject
::    rather than depending on the road it was read from.
::
+$  peer-rec  [%0 who=ship proto=(unit proto) asked=@da]
::
::  $probe-req: one discovery in flight, and THE CHAINS WAITING ON IT.
::
::    A send to a peer we have never asked about cannot go out as
::    version 1 on the strength of not having asked: that is the
::    question the refusal exists to answer, and answering it by
::    guessing means the "no common version" rule can never fire on
::    first contact - which is exactly the send most likely to reach a
::    ship running something else.
::
::    So the chain WAITS, here, and the ephemeral probe fiber sends it
::    once it knows what to send. `pending` is a LIST and not one chain
::    because two sends to the same unknown ship can arrive before the
::    keen answers, and both must be delivered, in the order they were
::    written - a set or an overwrite would silently drop the second
::    message a person composed.
::
::    Persisted, with a %fall row, so a crash mid-probe loses no mail:
::    the fiber respawns and drains the queue it finds.
::
::    ONE SHAPE, THREE JOBS, like $peer-rec above and for the same
::    reason - one `;;` ladder rather than three that must be kept in
::    step:
::
::      the grub at /probe/<ship>   the queue. answer=~, drained=0.
::      the fiber's own state       read back mid-run to pick up
::                                  anything appended during the keen.
::      the done poke               pending=~, `answer` is what the keen
::                                  found and `drained` is how many of
::                                  the queue the fiber actually sent,
::                                  so the writer culls exactly those
::                                  and re-sends anything that arrived
::                                  behind them.
::
+$  probe-req
  $:  %0
      who=ship
      asked=@da
      pending=(list chain)
      answer=(unit proto)
      drained=@ud
  ==
::
::  the published values. Built from the cap arms above, so a change to a
::  limit changes what this ship publishes in the same edit.
::
++  our-versions  ^-((list @ud) ~[1])
++  our-marks     ^-((list @tas) ~[%auspex-chain])
++  our-caps
  ^-  proto-caps
  :*  max-blob  max-attach  max-chain  max-body  max-subj
      max-to  max-depth  max-signers  max-mime  max-name
  ==
++  our-proto  ^-(proto [%auspex our-versions our-marks our-caps])
::
::  +proto-ttl: how long a discovery answer is believed.
::
::    A day. What it caches is a peer's DEPLOYED CODE, which changes on
::    the timescale of a release and not of a conversation, and the cost
::    of being a day stale is one send that fails with a wrong reason
::    rather than a right one. The correction path is shorter than the
::    TTL anyway: a nack or a timeout from a ship invalidates its record
::    immediately, so the only way to hold a stale answer for a day is
::    for the stale answer to keep working.
::
++  proto-ttl  ^-(@dr ~d1)
::
::  +proto-ok: is a keened noun a $proto we can act on?
::
::    Clamming answers "is it this shape", never "does it make sense".
::    The two lists are parallel by contract, so lengths that disagree
::    make +mark-for's index meaningless; an empty `versions` claims a
::    ship that speaks nothing, which is not a statement a running nexus
::    can truthfully make. Both are refused here and the peer is treated
::    as silent - which is the safe direction, since silence means
::    version 1 and version 1 is what every Auspex speaks.
::
++  proto-ok
  |=  p=proto
  ^-  ?
  ?&  ?=(^ versions.p)
      =((lent versions.p) (lent marks.p))
      (lte (lent versions.p) 64)
  ==
::
::  +common-version: the HIGHEST version both ships speak, ~ for none.
::
::    Highest and not first: a sender that picked the first common entry
::    would be pinned to whatever order the peer happened to publish, and
::    the peer chooses that order.
::
++  common-version
  |=  [ours=(list @ud) theirs=(list @ud)]
  ^-  (unit @ud)
  =/  ts  (~(gas in *(set @ud)) theirs)
  =/  hits=(list @ud)  (skim ours |=(v=@ud (~(has in ts) v)))
  ?~  hits  ~
  ::  `(list @ud)`hits, not hits: ?~ has narrowed it to a NON-EMPTY list
  ::  and +roll is a wet gate that recurses on its own sample, so the
  ::  recursion hands ~ to a gate whose sample no longer admits it. The
  ::  same shape +has-sub and +term-ok above already carry a note for.
  `(roll `(list @ud)`hits |=([v=@ud acc=@ud] ?:((gth v acc) v acc)))
::
::  +mark-for: the wire mark a peer named for one version.
::
::    The parallel-list rule, applied. A version present in `versions`
::    with no mark at its index is a malformed publication and answers ~
::    rather than guessing - guessing would poke a mark we invented at a
::    ship that never claimed it.
::
++  mark-for
  |=  [p=proto v=@ud]
  ^-  (unit @tas)
  =/  i  (find ~[v] versions.p)
  ?~  i  ~
  ?:  (gte u.i (lent marks.p))  ~
  `(snag u.i marks.p)
::
::  +peer-proto: what to believe about a peer, given its record.
::
::    THE COMPATIBILITY RULE, in one arm: a peer that publishes no /proto
::    is version 1. Auspex shipped before discovery did, so silence is
::    not "unknown", it is the only thing it can be.
::
++  peer-proto
  |=  p=(unit proto)
  ^-  proto
  ?~(p [%auspex ~[1] ~[%auspex-chain] our-caps] u.p)
::
::  +peer-mark: the mark to poke this peer with, ~ for no common version.
::
++  peer-mark
  |=  p=(unit proto)
  ^-  (unit @tas)
  =/  q  (peer-proto p)
  =/  v  (common-version our-versions versions.q)
  ?~  v  ~
  (mark-for q u.v)
::
::  +peer-caps: the limits to check a send against. A silent peer is
::  version 1, and version 1's limits are the ones this file enforces.
::
++  peer-caps
  |=  p=(unit proto)
  ^-  proto-caps
  caps:(peer-proto p)
::
::  +peer-fresh: is this record still believed?
::
++  peer-fresh
  |=  [r=peer-rec now=@da]
  ^-  ?
  &((gte now asked.r) (lth (sub now asked.r) proto-ttl))
::
::  ── the three refusals, as text ─────────────────────────────────────
::
::  Written here rather than at the two call sites, because a request
::  fiber and the writer both produce them and a message the user reads
::  must not depend on which one got there first. Ship name first: the
::  composer shows one line and the first thing a person needs is which
::  recipient it is about.
::
++  num-list
  |=  l=(list @ud)
  ^-  @t
  ?~  l  'nothing'
  =/  acc=@t  (scot %ud i.l)
  =/  r=(list @ud)  t.l
  |-  ^-  @t
  ?~  r  acc
  $(acc (rap 3 ~[acc ', ' (scot %ud i.r)]), r t.r)
::
::  +no-version-error: the peer answered, and nothing it speaks is
::  anything we speak. This is a REFUSAL and not a failed attempt: the
::  poke is never sent, because a mark the peer does not carry parks.
::
++  no-version-error
  |=  [who=ship p=proto]
  ^-  @t
  %+  rap  3
  :~  'no common protocol version: '  (scot %p who)  ' speaks '
      (num-list versions.p)  ', this ship speaks '  (num-list our-versions)
  ==
::
::  +unanswered-note: the probe ITSELF timed out, so there is nothing to
::  choose from and the compatibility rule decides: silence is version 1.
::
::    Said only when the PROBE's own result is empty, never when a cache
::    entry merely happens to be absent - the writer no longer sends on
::    an absent record at all, it queues, so "has not answered" here is a
::    finding and not an assumption.
::
::    Present perfect, deliberately: the ship has not answered YET. A
::    later send re-asks when the record expires.
::
++  unanswered-note
  |=  who=ship
  ^-  @t
  (rap 3 ~[(scot %p who) ' has not answered discovery; sent as version 1'])
::
::  +late-ack-note: the poke went out and no ack came back inside the
::  deadline.
::
::    NOT "did not ack the send", which asserts a fact this ship cannot
::    know. A poke that is applied late is applied: measured between two
::    live ships, a chain arrived, verified and stored while the sender's
::    own deadline had already fired. The deadline bounds how long we
::    WAIT, and says nothing about what the far end did.
::
::    The number is passed in rather than written here, so the sentence
::    and the deadline it describes cannot drift apart.
::
++  late-ack-note
  |=  [who=ship secs=@ud]
  ^-  @t
  %+  rap  3
  :~  (scot %p who)  ' did not ack within '  (scot %ud secs)
      's; it may still arrive'
  ==
::
++  nacked-note
  |=  who=ship
  ^-  @t
  (rap 3 ~[(scot %p who) ' nacked the send'])
::
::  ── the pending queue ───────────────────────────────────────────────
::
::  Two arms, pure, because the ORDER is the property worth asserting
::  and it is not observable from a fiber: a queue that drained
::  backwards would deliver a reply before the message it answers, and
::  every recipient would file the pair by `prev` anyway - so the bug
::  would show up as nothing at all until someone read a thread.
::
::  +queue-chain: append. Never prepend, never dedupe. Two identical
::  sends are two messages a person wrote twice.
::
++  queue-chain
  |=  [q=(list chain) c=chain]
  ^-  (list chain)
  (snoc q c)
::
::  +drain-queue: the first `n` to send, and what is left behind.
::
::    The remainder matters as much as the head. A chain appended while
::    the fiber was draining is BEHIND the count it reports, so the
::    writer culls exactly what was sent and re-sends the rest - which
::    is what makes the hand-off between the fiber and the writer lose
::    nothing without either of them locking anything.
::
++  drain-queue
  |=  [q=(list chain) n=@ud]
  ^-  [sent=(list chain) rest=(list chain)]
  [(scag n q) (slag n q)]
::
::  +peer-cap-error: does this chain exceed what the PEER published?
::
::    ~ when the send is within the peer's limits. Every bound here is
::    read off the peer's record and never off this ship's arms, which
::    is the whole point: a sixteen-attachment send is legal here and
::    refused by a peer that publishes eight, and finding that out at
::    compose time is the difference between an error a person can act
::    on and a message that vanishes.
::
::    The order is cheapest-first and the FIRST failure is the message.
::    A list of every violated cap would be more complete and less
::    useful: the composer shows one line.
::
++  peer-cap-error
  |=  [who=ship c=chain p=(unit proto)]
  ^-  (unit @t)
  =/  k  (peer-caps p)
  =/  w  `@t`(scot %p who)
  ?.  (levy c |=(x=msg (lte (lent attachments.unsigned.x) max-attach.k)))
    `(rap 3 ~[w ' accepts at most ' (scot %ud max-attach.k) ' attachments'])
  ?.  %+  levy  c
      |=  x=msg
      (levy attachments.unsigned.x |=(a=attachment (lte size.a max-blob.k)))
    `(rap 3 ~[w ' accepts an attachment of at most ' (scot %ud max-blob.k) ' bytes'])
  ?.  (fits-length c max-chain.k)
    `(rap 3 ~[w ' accepts at most ' (scot %ud max-chain.k) ' messages in a chain'])
  ?.  (fits-recipients c max-to.k)
    `(rap 3 ~[w ' accepts at most ' (scot %ud max-to.k) ' recipients'])
  ?.  (fits-subjects c max-subj.k)
    `(rap 3 ~[w ' accepts a subject of at most ' (scot %ud max-subj.k) ' bytes'])
  ?.  (fits-bodies c max-body.k)
    `(rap 3 ~[w ' accepts a body of at most ' (scot %ud max-body.k) ' bytes'])
  ?.  (fits-body-mimes c max-mime.k)
    `(rap 3 ~[w ' accepts a body mime of at most ' (scot %ud max-mime.k) ' bytes'])
  ?.  (fits-depth c max-depth.k)
    `(rap 3 ~[w ' accepts a thread at most ' (scot %ud max-depth.k) ' deep'])
  ?.  (fits-signers c max-signers.k)
    `(rap 3 ~[w ' accepts at most ' (scot %ud max-signers.k) ' distinct signers'])
  ~
::
::  ── where the published noun lives in the farm ──────────────────────
::
::  +proto-spur mirrors +blob-spur: one prefix this nexus owns inside the
::  yoke's FLAT farm namespace. No revision segment and no hash, because
::  there is exactly one /proto per ship and its address must be
::  constructible by a peer that knows nothing but the ship.
::
++  proto-spur  ^-(path /auspex/proto)
::
::  +proto-keen-path: the ames spar path of a PEER's /proto. MUST mirror
::  +proto-spur, and carries the same empty segment +blob-keen-path
::  carries and for the same reason - see that arm.
::
++  proto-keen-path
  |=  [agent=@ta case=@ud]
  ^-  path
  %+  weld  `path`[%g %x (scot %ud case) agent %$ %'1' ~]
  proto-spur
::
++  proto-page-mark  ^-(@tas %auspex-proto)
--

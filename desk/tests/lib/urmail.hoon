/-  sur=urmail
/+  *test, urmail
|%
::  a signature made with a ship's key verifies against that ship's key
++  test-sign-verify-roundtrip
  =/  who   ~sampel-palnet
  =/  msg   (shaf %urmail (sham [%hello 'world']))
  =/  sig   (sign-with:urmail (fake-ring:urmail who) msg)
  (expect !>((verify-with:urmail (fake-pass:urmail who) sig msg)))
::
::  a signature does not verify against a different ship's key
++  test-sign-wrong-key-fails
  =/  msg   (shaf %urmail (sham [%hello 'world']))
  =/  sig   (sign-with:urmail (fake-ring:urmail ~sampel-palnet) msg)
  (expect !>(!(verify-with:urmail (fake-pass:urmail ~palnet-sampel) sig msg)))
::
::  a signature does not verify against a different message
++  test-sign-wrong-message-fails
  =/  who   ~sampel-palnet
  =/  sig   (sign-with:urmail (fake-ring:urmail who) (shaf %urmail (sham 'a')))
  (expect !>(!(verify-with:urmail (fake-pass:urmail who) sig (shaf %urmail (sham 'b')))))
--

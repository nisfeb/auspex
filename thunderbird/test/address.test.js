import test from 'node:test'
import assert from 'node:assert/strict'
import {
  isShip, shipToAddress, addressToShip, bareAddress, isAuspexAddress,
} from '../lib/address.js'

test('a ship maps to an address and back', () => {
  assert.equal(shipToAddress('~feb'), '~feb@auspex.urbit')
  assert.equal(addressToShip('~feb@auspex.urbit'), '~feb')
  assert.equal(shipToAddress('~mister-botter'), '~mister-botter@auspex.urbit')
  assert.equal(addressToShip('~mister-botter@auspex.urbit'), '~mister-botter')
  const moon = '~doztec-migtyd-mister-botter'
  assert.equal(addressToShip(shipToAddress(moon)), moon)
})

test('the display form is unwrapped', () => {
  assert.equal(bareAddress('~feb <~feb@auspex.urbit>'), '~feb@auspex.urbit')
  assert.equal(addressToShip('~feb <~feb@auspex.urbit>'), '~feb')
  assert.equal(addressToShip('  ~feb@AUSPEX.URBIT  '), '~feb')
})

test('the refusals', () => {
  //  an ordinary internet address is not ours, and must never be
  //  silently dropped from a send.
  assert.equal(addressToShip('someone@example.com'), null)
  assert.equal(addressToShip('~feb@example.com'), null)
  assert.equal(addressToShip('feb@auspex.urbit'), null)      // no sig
  assert.equal(addressToShip('~zod-zod@auspex.urbit'), null) // galaxy is whole
  assert.equal(addressToShip('~abc-def-ghi@auspex.urbit'), null) // 3 groups
  assert.equal(addressToShip('not an address'), null)
  assert.equal(addressToShip(''), null)
  assert.equal(addressToShip(undefined), null)
  assert.equal(isAuspexAddress('someone@example.com'), false)
  assert.throws(() => shipToAddress('nope'), /not a ship/)
})

test('ship shapes: galaxy, star, planet, moon, comet', () => {
  assert.ok(isShip('~zod'))                                   // galaxy
  assert.ok(isShip('~marzod'))                                // star
  assert.ok(isShip('~sampel-palnet'))                         // planet
  assert.ok(isShip('~doztec-migtyd-mister-botter'))           // moon
  assert.ok(isShip('~dovmul-mogryt-pinpun-mogbud-pactyv-dishus-borrus-nidnux')) // comet
  assert.ok(!isShip('~sampel-palnet-doznec'))                 // three groups
  assert.ok(!isShip('sampel-palnet'))                         // no sig
})

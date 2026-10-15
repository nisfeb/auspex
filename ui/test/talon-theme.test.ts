import test from 'node:test'
import assert from 'node:assert/strict'
import {
  deriveVars, parseThemes, resolveAccent, parseProfileColor, pickTheme, toHex, mix,
  type Theme5, type TalonResponse,
} from '../src/talon-theme.ts'

const ocean: Theme5 = {
  dark: true, primary: '#38bdf8', secondary: '#a78bfa', tertiary: '#34d399',
  background: '#0b1120', surface: '#111827',
}

test('every auspex token is derived, as a hex, and the picked colours pass through', () => {
  const v = deriveVars(ocean, null)
  const tokens = [
    'surface', 'raised', 'sunken', 'line', 'line-strong', 'ink', 'ink-dim',
    'ink-faint', 'accent', 'accent-hover', 'accent-ink', 'accent-soft',
    'accent-soft-ink', 'ok', 'danger', 'danger-soft', 'warn-soft', 'warn-ink',
    'warn-line', 'forged-bg', 'forged-ink', 'forged-line',
  ]
  for (const t of tokens) assert.match(v[t], /^#[0-9a-f]{6}$/, `${t} is a hex`)
  // the five picked colours land on their tokens untouched
  assert.equal(v.surface, '#0b1120') // background -> page surface
  assert.equal(v.raised, '#111827') // talon surface -> auspex raised
  assert.equal(v.accent, '#38bdf8') // primary
  assert.equal(v.ok, '#34d399') // tertiary
})

test('ink is paper on a dark ground and near-black on a light one', () => {
  const dark = deriveVars(ocean, null)
  assert.equal(dark.ink, '#fafaf9')
  const light = deriveVars({ ...ocean, dark: false, background: '#ffffff', surface: '#ffffff' }, null)
  assert.equal(light.ink, '#1c1917')
})

test('an accent repaints the primary and its ink, but not the soft fill', () => {
  const plain = deriveVars(ocean, null)
  const tinted = deriveVars(ocean, '#ff0000')
  assert.equal(tinted.accent, '#ff0000')
  assert.notEqual(tinted.accent, plain.accent)
  // on red, ink (white) wins; the soft fill still comes off the theme primary
  assert.equal(tinted['accent-ink'], '#ffffff')
  assert.equal(tinted['accent-soft'], plain['accent-soft'])
})

test('an unreadable or empty talon themes entry yields no themes', () => {
  assert.deepEqual(parseThemes('not json').themes, [])
  assert.deepEqual(parseThemes('{}').themes, [])
  assert.deepEqual(parseThemes('{"themes":[{"id":"x"}]}').themes, []) // missing colours
})

test('a well-formed themes entry reads its themes and the active id', () => {
  const txt = JSON.stringify({
    themes: [{
      id: 'a1', name: 'Ocean', dark: true, primary: '#38bdf8', secondary: '#a78bfa',
      tertiary: '#34d399', background: '#0b1120', surface: '#111827',
    }],
    activeId: 'a1',
  })
  const { themes, activeId } = parseThemes(txt)
  assert.equal(themes.length, 1)
  assert.equal(activeId, 'a1')
  assert.equal(themes[0].primary, '#38bdf8')
})

test('pickTheme takes the active custom theme, else the built-in in the user mode', () => {
  const resp: TalonResponse = {
    themes: JSON.stringify({
      themes: [{
        id: 'a1', name: 'Ocean', dark: true, primary: '#38bdf8', secondary: '#a78bfa',
        tertiary: '#34d399', background: '#0b1120', surface: '#111827',
      }],
      activeId: 'a1',
    }),
    accent: null, profile: null,
  }
  assert.equal(pickTheme(resp, false).dark, true) // custom theme forces its own mode
  assert.equal(pickTheme(resp, false).theme.primary, '#38bdf8')
  // no active theme -> talon's built-in, following the user mode
  const builtin = pickTheme({ themes: '{"themes":[]}', accent: null, profile: null }, true)
  assert.equal(builtin.dark, true)
  assert.equal(builtin.theme.primary, '#fbbf24') // talon dark brand amber
})

test('accent resolves by mode, and off when not enabled', () => {
  assert.equal(resolveAccent(null, null), null)
  assert.equal(resolveAccent('{"enabled":false,"mode":"Custom","customHex":"#abc123"}', null), null)
  assert.equal(resolveAccent('{"enabled":true,"mode":"Custom","customHex":"#abc123"}', null), '#abc123')
  assert.equal(resolveAccent('{"enabled":true,"mode":"Brand"}', '#ff5050'), null)
  assert.equal(resolveAccent('{"enabled":true,"mode":"Profile"}', '#ff5050'), '#ff5050')
})

test('a profile colour reads as a bare hex or a typed urbit tint', () => {
  assert.equal(parseProfileColor('{"color":"#ff5050"}'), '#ff5050')
  assert.equal(parseProfileColor('{"color":{"type":"tint","value":"0xff.5050"}}'), '#ff5050')
  assert.equal(parseProfileColor('{}'), null)
  assert.equal(parseProfileColor(null), null)
})

test('mix lands on the endpoints and the midpoint', () => {
  assert.equal(toHex(mix([0, 0, 0], [255, 255, 255], 0)), '#000000')
  assert.equal(toHex(mix([0, 0, 0], [255, 255, 255], 1)), '#ffffff')
  assert.equal(toHex(mix([0, 0, 0], [254, 254, 254], 0.5)), '#7f7f7f')
})

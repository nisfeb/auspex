// FOLLOW TALON'S THEME. The owner picks a look in talon; auspex wears it.
//
// Talon keeps its theme in the ship's %settings (desk talon, bucket
// ui-prefs): a `themes` entry (saved five-colour themes and which is
// active) and an `accent` entry (an optional repaint of the primary).
// The nexus hands those over raw at /api/talon-theme, as the JSON strings
// they were stored as, plus our own %contacts profile (for an accent set
// to the profile colour). ALL the colour maths lives here, on the client,
// rather than half in Hoon: one place decides what every token becomes.
//
// The derivation is talon's own (its ui/theme/CustomTheme.kt), by way of
// furum's lib/furum-theme.hoon, mapped onto auspex's --u-* tokens instead
// of furum's page roles. ponytail: talon blends in Oklab, this in sRGB, so
// a derived shade can land a hair off talon's; the five picked colours,
// and which ink sits on each, match.

export type Rgb = [number, number, number]

// A talon theme: the five colours a person picks, a dark flag, and the
// six it may also set (only `error` is read here; the rest are furum/talon
// page roles auspex has no token for).
export interface Theme5 {
  dark: boolean
  primary: string
  secondary: string
  tertiary: string
  background: string
  surface: string
  error?: string
}

export interface TalonResponse {
  themes: string | null
  accent: string | null
  profile: string | null
}

// ── colour maths ─────────────────────────────────────────────────────

// "#RRGGBB" or "RRGGBB", any case, to channels; null on anything else.
export function parseHex(h: string): Rgb | null {
  const s = h.trim().replace(/^#/, '')
  if (!/^[0-9a-fA-F]{6}$/.test(s)) return null
  return [
    parseInt(s.slice(0, 2), 16),
    parseInt(s.slice(2, 4), 16),
    parseInt(s.slice(4, 6), 16),
  ]
}

const hex2 = (n: number) => Math.max(0, Math.min(255, Math.round(n)))
  .toString(16).padStart(2, '0')
export const toHex = (c: Rgb): string => `#${hex2(c[0])}${hex2(c[1])}${hex2(c[2])}`

// a toward b by fraction f (0..1), per channel.
export function mix(a: Rgb, b: Rgb, f: number): Rgb {
  return [
    a[0] + (b[0] - a[0]) * f,
    a[1] + (b[1] - a[1]) * f,
    a[2] + (b[2] - a[2]) * f,
  ]
}

// Relative luminance, 0..1 (sRGB, as Compose's Color.luminance).
export function lum(c: Rgb): number {
  const lin = (v: number) => {
    const x = v / 255
    return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4)
  }
  return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2])
}

const INK: Rgb = [0x1c, 0x19, 0x17]
const PAPER: Rgb = [0xfa, 0xfa, 0xf9]
const WHITE: Rgb = [0xff, 0xff, 0xff]
const BLACK: Rgb = [0, 0, 0]

// The ink that reads on a colour: dark ink on a light one, paper on a dark.
const on = (c: Rgb): Rgb => (lum(c) > 0.4 ? INK : PAPER)

// Talon's two built-in brand palettes (its Theme.kt), used when talon has
// no active custom theme — i.e. it is on its own default look. Following
// talon then means following its built-in, in whichever mode auspex is in.
const BUILTIN: { light: Theme5; dark: Theme5 } = {
  light: {
    dark: false, primary: '#f59e0b', secondary: '#4338ca', tertiary: '#059669',
    background: '#fafaf9', surface: '#ffffff', error: '#dc2626',
  },
  dark: {
    dark: true, primary: '#fbbf24', secondary: '#a5b4fc', tertiary: '#34d399',
    background: '#0f0d1a', surface: '#1a1625', error: '#f87171',
  },
}

// Warn and forged are semantic and not part of talon's five-colour scheme,
// so they keep auspex's own values in both modes (the originals from
// index.css). Stated here because the derived palette replaces every
// --u-* token at once, so these must be re-supplied, not inherited.
const FIXED = {
  light: {
    'warn-soft': '#fef7e0', 'warn-ink': '#7a5900', 'warn-line': '#fdd663',
    'forged-bg': '#fce8e6', 'forged-ink': '#a50e0e', 'forged-line': '#d93025',
  },
  dark: {
    'warn-soft': '#3a2f0b', 'warn-ink': '#fdd663', 'warn-line': '#7a5900',
    'forged-bg': '#601410', 'forged-ink': '#ffdad6', 'forged-line': '#ff5449',
  },
}

// Every auspex --u-* token from a theme's five colours, by talon's rules:
// the ink on a colour is picked by its luminance; the "soft" fills blend
// toward the background (dark) or white (light); the surface ramp (sunken,
// lines, dim text) blends toward the text. An accent, when given, repaints
// the primary and its ink, leaving the soft fills as talon leaves them.
export function deriveVars(t: Theme5, accent: string | null): Record<string, string> {
  const num = (h: string, fb: Rgb): Rgb => parseHex(h) ?? fb
  const p0 = num(t.primary, [0xf5, 0x9e, 0x0b])
  const b = num(t.background, t.dark ? [0x0f, 0x0d, 0x1a] : PAPER)
  const u = num(t.surface, t.dark ? [0x1a, 0x16, 0x25] : WHITE)
  const e = num(t.tertiary, [0x05, 0x96, 0x69])
  const er = num(t.error ?? '', t.dark ? [0xf8, 0x71, 0x71] : [0xdc, 0x26, 0x26])
  const a = accent ? parseHex(accent) : null
  const p = a ?? p0

  const toward = t.dark ? WHITE : BLACK
  const onS = on(u)
  const box = (c: Rgb): Rgb => (t.dark ? mix(c, b, 0.6) : mix(c, WHITE, 0.8))
  const onBox = (c: Rgb): Rgb => (t.dark ? mix(c, WHITE, 0.75) : mix(c, BLACK, 0.65))

  const out: Record<string, string> = {
    surface: toHex(b),
    raised: toHex(u),
    sunken: toHex(mix(u, toward, 0.06)),
    line: toHex(mix(u, onS, 0.15)),
    'line-strong': toHex(mix(u, onS, 0.4)),
    ink: toHex(on(b)),
    'ink-dim': toHex(mix(onS, u, 0.35)),
    'ink-faint': toHex(mix(onS, u, 0.55)),
    accent: toHex(p),
    'accent-hover': toHex(mix(p, toward, 0.15)),
    'accent-ink': toHex(a ? (lum(a) > 0.5 ? INK : WHITE) : on(p)),
    'accent-soft': toHex(box(p0)),
    'accent-soft-ink': toHex(onBox(p0)),
    ok: toHex(e),
    danger: toHex(er),
    'danger-soft': toHex(box(er)),
    ...(t.dark ? FIXED.dark : FIXED.light),
  }
  return out
}

// ── talon's settings, as %settings holds them (JSON strings) ─────────

interface ThemeEntry extends Theme5 { id: string }

// The `themes` entry: saved themes and the active id. A theme that will
// not read is dropped. Missing colours default (talon's "work it out").
export function parseThemes(txt: string): { themes: ThemeEntry[]; activeId?: string } {
  let o: unknown
  try { o = JSON.parse(txt) } catch { return { themes: [] } }
  if (!o || typeof o !== 'object') return { themes: [] }
  const rec = o as Record<string, unknown>
  const raw = Array.isArray(rec.themes) ? rec.themes : []
  const themes: ThemeEntry[] = []
  for (const j of raw) {
    if (!j || typeof j !== 'object') continue
    const m = j as Record<string, unknown>
    const str = (k: string): string | undefined =>
      (typeof m[k] === 'string' ? (m[k] as string) : undefined)
    const id = str('id'); const primary = str('primary')
    const secondary = str('secondary'); const tertiary = str('tertiary')
    const background = str('background'); const surface = str('surface')
    if (id === undefined || primary === undefined || secondary === undefined
      || tertiary === undefined || background === undefined || surface === undefined
      || typeof m.dark !== 'boolean') continue
    // "" is talon's "derive it", so an empty error is no error here.
    const error = str('error') || undefined
    themes.push({ id, dark: m.dark, primary, secondary, tertiary, background, surface, error })
  }
  const activeId = typeof rec.activeId === 'string' ? rec.activeId : undefined
  return { themes, activeId }
}

// The `accent` entry: on (unset reads as off), where the colour comes
// from, and a custom hex. Resolved against the profile colour.
export function resolveAccent(txt: string | null, profileHex: string | null): string | null {
  if (!txt) return null
  let o: unknown
  try { o = JSON.parse(txt) } catch { return null }
  if (!o || typeof o !== 'object') return null
  const m = o as Record<string, unknown>
  if (m.enabled !== true) return null
  const mode = m.mode
  if (mode === 'Custom') return typeof m.customHex === 'string' ? m.customHex : null
  if (mode === 'Profile') return profileHex
  return null // Brand: no override, the theme's own primary stands
}

// The colour on our %contacts profile (contacts' v1 self JSON): a typed
// field {type, value} as "0xRRGGBB", or a bare "#RRGGBB" string.
export function parseProfileColor(txt: string | null): string | null {
  if (!txt) return null
  let o: unknown
  try { o = JSON.parse(txt) } catch { return null }
  if (!o || typeof o !== 'object') return null
  const c = (o as Record<string, unknown>).color
  let v: string | undefined
  if (typeof c === 'string') v = c
  else if (c && typeof c === 'object' && typeof (c as Record<string, unknown>).value === 'string') {
    v = (c as Record<string, string>).value
  }
  if (!v) return null
  const ux = v.match(/^0x([0-9a-fA-F]{2})\.?([0-9a-fA-F]{4})$/)
  if (ux) return `#${ux[1]}${ux[2]}`
  return parseHex(v) ? (v.startsWith('#') ? v : `#${v.replace(/^#/, '')}`) : null
}

// The theme auspex should wear, and in which mode: the active custom theme
// if one is set (it brings its own dark flag), else talon's built-in in
// the mode auspex is already in.
export function pickTheme(resp: TalonResponse, userDark: boolean): { theme: Theme5; dark: boolean } {
  if (resp.themes) {
    const { themes, activeId } = parseThemes(resp.themes)
    const hit = activeId ? themes.find((t) => t.id === activeId) : undefined
    if (hit) return { theme: hit, dark: hit.dark }
  }
  return { theme: userDark ? BUILTIN.dark : BUILTIN.light, dark: userDark }
}

// ── apply ────────────────────────────────────────────────────────────

const VARS: string[] = [
  'surface', 'raised', 'sunken', 'line', 'line-strong', 'ink', 'ink-dim',
  'ink-faint', 'accent', 'accent-hover', 'accent-ink', 'accent-soft',
  'accent-soft-ink', 'ok', 'danger', 'danger-soft', 'warn-soft', 'warn-ink',
  'warn-line', 'forged-bg', 'forged-ink', 'forged-line',
]

const FOLLOW_KEY = 'auspex:follow-talon'
const CACHE_KEY = 'auspex:talon-cache'

// Unset is on: auspex follows talon by default, and only an explicit 'off'
// turns it back to auspex's own palette.
export const following = (): boolean => {
  try { return localStorage.getItem(FOLLOW_KEY) !== 'off' } catch { return true }
}
export const setFollowing = (on: boolean): void => {
  try { localStorage.setItem(FOLLOW_KEY, on ? 'on' : 'off') } catch { /* private mode */ }
}

// The inline --u-* on <html> that index.html's pre-paint script applies
// from the cache, and that this writes after each fetch. A string of
// "--x:#hex;" so the pre-paint can set it verbatim with no derivation.
const toCss = (vars: Record<string, string>): string =>
  VARS.map((v) => `--u-${v}:${vars[v]};`).join('')

function apply(dark: boolean, css: string): void {
  const el = document.documentElement
  el.classList.toggle('dark', dark)
  for (const v of VARS) {
    const m = new RegExp(`--u-${v}:([^;]+);`).exec(css)
    if (m) el.style.setProperty(`--u-${v}`, m[1])
  }
  try { localStorage.setItem(CACHE_KEY, JSON.stringify({ dark, css })) } catch { /* private mode */ }
}

// Take the inline palette back off, so the stylesheet's own (Gmail) one
// shows again, and forget the cache so the next load does not re-apply it.
export function clearFollow(): void {
  const el = document.documentElement
  for (const v of VARS) el.style.removeProperty(`--u-${v}`)
  try { localStorage.removeItem(CACHE_KEY) } catch { /* private mode */ }
}

let fetched: TalonResponse | null = null

// Fetch talon's settings (once, then reused), derive the palette for the
// given mode, apply it, and cache it. Returns the effective dark flag,
// which a custom theme may differ from `userDark` on. Never throws: a
// ship with no talon, or an unreachable one, just keeps what is on screen.
export async function applyFollow(userDark: boolean): Promise<boolean> {
  try {
    if (!fetched) {
      const res = await fetch('/apps/auspex/api/talon-theme', {
        headers: { accept: 'application/json' },
      })
      fetched = await res.json() as TalonResponse
    }
    const { theme, dark } = pickTheme(fetched, userDark)
    const accent = resolveAccent(fetched.accent, parseProfileColor(fetched.profile))
    apply(dark, toCss(deriveVars(theme, accent)))
    return dark
  } catch {
    return userDark
  }
}

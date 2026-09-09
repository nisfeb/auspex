import type { Verdict } from './api'

// One definition, used by both the thread view and the inbox list. The
// inbox list is the surface a user scans fastest and every field on it is
// chosen by whoever poked the chain, so the two views must not disagree
// about what a verdict looks like.
//
// TWO OF THE THREE SHRANK; THE THIRD DID NOT.
//
// `verified` and `unverified` were pill badges carrying a word each, on
// every message and every row. That is a lot of furniture to say "this
// is normal", and the cost was not only space: three loud badges made
// the one that matters look like a third colour of the same thing.
// `verified` is now a check and `unverified` a hollow ring — small, but
// never absent, because "no mark" and "not checked" have to stay
// different things.
//
// `forged` is EXACTLY as loud as it was, deliberately, and is the one
// mark that still carries its word. It is the only verdict that is an
// accusation, it is the only one a reader must not be able to skim past,
// and a mark that shrinks into ambiguity at the moment it matters is
// worse than no mark at all. Its colours are their own tokens in both
// palettes (see index.css): red on a dark ground is not automatically
// legible, and the dark values were chosen against the dark forged
// background rather than inherited from the light ones.
export default function VerdictBadge({ verdict, from, className = '' }: {
  verdict: Verdict
  // The sender this verdict is about. The tooltip names the ship,
  // because "verified" alone answers a question nobody asked: what a
  // reader wants to know is verified as WHOM.
  from?: string
  className?: string
}) {
  const who = from ?? 'this sender'

  if (verdict === 'forged') {
    return (
      <span
        title={`A key was available for ${who} and the signature failed against it. This message is not from the ship it claims.`}
        aria-label={`Forged: the signature failed against ${who}'s registered key`}
        className={`shrink-0 rounded-sm bg-forged-bg px-1.5 py-0.5 text-[11px] font-bold uppercase tracking-wide text-forged-ink ring-1 ring-forged-line ${className}`}
      >
        forged
      </span>
    )
  }

  if (verdict === 'verified') {
    return (
      <span
        title={`Signed by ${who}, signature verified against their key.`}
        aria-label={`Verified: signed by ${who}, signature verified against their key`}
        className={`shrink-0 text-[13px] leading-none text-ok ${className}`}
      >
        ✓
      </span>
    )
  }

  return (
    <span
      title={`No key available for ${who}, so the signature could not be checked. Moons and comets always land here.`}
      aria-label={`Unverified: no key available for ${who}, so the signature could not be checked`}
      className={`shrink-0 text-[13px] leading-none text-ink-faint ${className}`}
    >
      ○
    </span>
  )
}

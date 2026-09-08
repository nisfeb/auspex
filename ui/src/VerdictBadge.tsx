import type { Verdict } from './api'

// One definition, used by both the thread view and the inbox list. The
// inbox list is the surface a user scans fastest and every field on it is
// chosen by whoever poked the chain, so the two views must not disagree
// about what a verdict looks like.
const style: Record<Verdict, string> = {
  verified: 'bg-green-100 text-green-800',
  unverified: 'bg-neutral-100 text-neutral-600',
  forged: 'bg-red-100 text-red-800 ring-1 ring-red-600 font-semibold',
}

const label: Record<Verdict, string> = {
  verified: 'verified',
  unverified: 'unverified',
  forged: 'FORGED',
}

const title: Record<Verdict, string> = {
  verified: "Signature checks against this sender's registered key.",
  unverified:
    'No key available for this sender, so the signature could not be checked. Moons and comets always land here.',
  forged:
    'A key was available and the signature failed against it. This message is not from the ship it claims.',
}

export default function VerdictBadge({ verdict, className = '' }: {
  verdict: Verdict
  className?: string
}) {
  return (
    <span
      title={title[verdict]}
      className={`rounded px-2 py-0.5 text-xs ${style[verdict]} ${className}`}
    >
      {label[verdict]}
    </span>
  )
}

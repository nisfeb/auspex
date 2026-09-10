// WHAT AN EMPTY PANE MEANS depends on whether the answer has arrived.
// Every list here starts as an empty array, so a pane that says
// "Nothing here." before its first response is not reporting a fact — it
// is reporting the absence of one, and reporting it as if it were
// settled. On a ship that takes a moment, that reads as a broken mailbox.
//
// Shown ONLY while a fetch is in flight AND there is nothing to draw.
// Once rows exist they stay on screen through a refresh: swapping real
// content for a spinner on every change-beacon event would be a flicker,
// and the rows are still true while the next answer is on its way.
//
// `role="status"` so a screen reader announces the wait; aria-hidden on
// the ring because the word beside it already says what it means.
export default function Loading({ what = 'Loading' }: { what?: string }) {
  return (
    // `flex-1` on the OUTER box and the row nested inside it: the box has
    // to claim the pane's height the way the list it stands in for does,
    // but a spinner centred in that height would sit halfway down an empty
    // column and then jump to the top when the rows arrive. The message
    // this replaces starts at the top, so this starts in the same place.
    <div role="status" className="flex-1 p-3 text-ink-faint">
      <span className="flex items-center gap-2">
        <span
          aria-hidden="true"
          className="size-3.5 shrink-0 animate-spin rounded-full border-2
            border-line border-t-ink-faint"
        />
        {what}…
      </span>
    </div>
  )
}

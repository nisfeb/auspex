import { useEffect, useRef, useState } from 'react'
import {
  canSign, deleteDraft, garbled, isShip, newId, NO_KEYS_LINE, refusalLine,
  saveDraft, send, sendDraft, unreachable, uploadAll,
  type Draft, type MailList,
} from './api'
import { FilePicker } from './Attachments'
import ShipChips, { commitShip } from './ShipChips'

// What a Forward control hands the composer: the message the new message
// will point `prev` at, the subject to base the forwarded one on, and how
// many messages the chain currently holds.
//
// Deliberately NOT a recipient list. A forward is the one case the spec
// calls out as going to "someone new", so seeding the To field from the
// thread's `participants` would be the Critical finding this project
// already fixed once, in its most dangerous form: shipping an entire
// signed conversation to an audience the user never looked at, at the
// moment they meant to hand it to one new person. The field starts empty
// and stays empty until a human types into it.
export interface ForwardIntent {
  prev: string
  subject: string
  // DISTINCT MESSAGES ON THE PATH from the thread root down to `prev`,
  // which is exactly what the nexus ships. Not the thread's message
  // count, which would include sibling branches that no longer travel,
  // and not the stored-copy count, which counts one message several
  // times when copies differ in signature.
  count: number
}

// How long the composer sits still before it saves. Long enough that
// typing does not poke the writer per keystroke — the writer is the
// ship's single serialisation point for mail — and short enough that a
// closed tab loses a sentence rather than a message.
const DEBOUNCE = 1500

export default function Compose({
  onClose, onSent, onDraftsChanged, forward, resume, lists,
}: {
  onClose: () => void
  onSent: (notice?: string | null) => void
  // Drafts are their own view, so the panel tells the app when it has
  // written one rather than leaving the sidebar count stale.
  onDraftsChanged: () => void
  forward?: ForwardIntent | null
  // Reopening an existing draft: the panel adopts its id, so saving
  // overwrites that draft rather than laying a second one.
  resume?: Draft | null
  // The mailing lists this ship holds, offered in the To field beside
  // ships. NOTHING BELOW THIS FIELD KNOWS LISTS EXIST: picking one puts
  // its members in as ship chips and the list is over, so the send, the
  // draft that is saved and the recipient check all see ships.
  lists: MailList[]
}) {
  // THE TO FIELD IS CHIPS, and a chip is always a well-formed ship — see
  // ShipChips. `pending` is the half-typed name, held here rather than
  // inside the control so Send can fold it in.
  const [to, setTo] = useState<string[]>(resume ? resume.to : [])
  const [pending, setPending] = useState('')
  const [subject, setSubject] = useState(
    resume ? resume.subj : forward ? `fwd: ${forward.subject}` : '',
  )
  const [body, setBody] = useState(resume ? resume.body : '')
  const [sending, setSending] = useState(false)
  // WHICH FILE IS IN FLIGHT. Uploads are one request per file and run
  // in sequence, so a sixteen-file send is sixteen round trips and the
  // Send button would otherwise say "Sending…" for the whole of it
  // with nothing moving. null once the bytes are up and the send
  // itself is the only thing left.
  const [upload, setUpload] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  // Who the ship would not carry this to, carried out through onSent.
  // A ref and not state: it is written once, on the way out of a
  // component that is about to unmount, and a setState there would be
  // a render nobody sees.
  const refused = useRef<string | null>(null)
  const [saved, setSaved] = useState<string | null>(null)
  // ATTACHMENTS DO NOT SURVIVE A DRAFT. A draft is a local grub with no
  // files field, and the writer's %save-draft carries none — so a
  // composer with a file attached takes the direct /api/send path and
  // never the save-then-send-draft one. Resuming a draft starts with no
  // files for the same reason: there were never any on disk to restore,
  // and pretending otherwise would send a message the user believes
  // carries a file it does not.
  const [files, setFiles] = useState<File[]>([])

  // The draft this panel owns. Minted once, on mount, and never changed:
  // a new id per save would lay one grub per keystroke burst and leave
  // the user a folder full of half-sentences.
  const draftId = useRef(resume ? resume.id : newId())
  // Whether anything has actually been written under that id yet, so
  // closing an untouched composer does not delete a draft that never
  // existed and does not poke the writer for nothing.
  const written = useRef(!!resume)
  // The latest field values, for the save-on-close path: an effect
  // cleanup closes over the values it was created with, and the last
  // keystroke before a close is exactly the one that would be lost.
  const latest = useRef({ to, subject, body })
  latest.current = { to, subject, body }
  // HAS A HUMAN TOUCHED THIS? The save effect runs on mount like every
  // effect, and a Forward composer opens with its subject already
  // filled in, so "is anything in the fields" was true before the user
  // did anything: opening Forward and closing it again left a draft
  // nobody wrote. Autosave is for work that would otherwise be lost,
  // and nothing typed is nothing lost.
  const touched = useRef(false)


  const store = async () => {
    if (!touched.current) return
    const { to: t, subject: s, body: b } = latest.current
    // Only well-formed ships go into a draft: the nexus parses `to` as a
    // set of @p and would refuse the whole save otherwise. Chips are
    // already ships by construction — the half-typed name in `pending`
    // is never one of them, which is exactly why autosave does not stop
    // the moment someone starts typing a name.
    const named = t.filter(isShip)
    // GUARD ON WHAT WILL BE STORED, not on what is on screen. `to`
    // holding nothing but a half-typed name stores as an empty list, so
    // the raw-string test called a blank composer non-empty and
    // autosaved a draft with no recipient, no subject and no body — a
    // draft holding nothing, created by starting to type a name and
    // stopping. Autosave exists to keep work that would otherwise be
    // lost, and there is no work in that.
    if (named.length === 0 && !s.trim() && !b.trim()) return
    try {
      await saveDraft({
        id: draftId.current,
        to: named,
        subj: s,
        body: b,
        prev: forward ? forward.prev : resume ? resume.prev : null,
      })
      written.current = true
      onDraftsChanged()
      setSaved(new Date().toLocaleTimeString())
    } catch (e) {
      console.error(e)
    }
  }

  // Save on a debounce while typing, and once more on close. Both, not
  // either: the debounce covers a browser that goes away, and the close
  // covers the keystrokes inside the last window.
  useEffect(() => {
    const h = setTimeout(() => { void store() }, DEBOUNCE)
    return () => { clearTimeout(h) }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [to, subject, body])

  const closeAndSave = async () => {
    await store()
    onClose()
  }

  const onSend = async () => {
    setError(null)
    // A NAME TYPED AND NOT COMMITTED IS STILL A RECIPIENT THE USER MEANT.
    // Fold it in before anything else, and refuse the send if it is not
    // a ship rather than silently dropping it.
    const { ships: list, error: chipError } = commitShip(to, pending)
    if (chipError) {
      setError(chipError)
      return
    }
    setTo(list)
    setPending('')
    // RECIPIENT VALIDATION, BEFORE THE POKE, KEPT. Every chip came
    // through `commitShip` and so is a ship already — this is the belt to
    // that brace, and the thing that would catch a chip arriving from
    // anywhere else (a resumed draft, a list's members). The nexus keeps
    // its own check and stays the boundary.
    const wrong = list.filter((s) => !isShip(s))
    if (wrong.length > 0) {
      setError(`Not a ship name: ${wrong.join(', ')}`)
      return
    }
    setSending(true)
    try {
      // A FILE ON THE COMPOSER TAKES THE DIRECT PATH. %send-draft signs
      // what is on disk, and what is on disk has no files: routing an
      // attached send through it would drop every attachment silently
      // and report success. The draft, if one was written, is deleted
      // after the send the way discarding one is.
      if (files.length > 0) {
        // THE BYTES GO UP FIRST, AND A FAILURE HERE ABORTS BEFORE THE
        // SEND. An upload stores bytes under their content address and
        // signs nothing, so a file that will not upload is a composer
        // that stays open with its files and an error naming the one
        // that failed — never a half-sent message.
        let refs
        try {
          refs = await uploadAll(files, (i, n) => { setUpload(`uploading ${i} of ${n}`) })
        } catch (e) {
          console.error(e)
          // The ship's own reason, PUNCTUATED. It arrives as a bare
          // clause ("blocked by the test") and runs straight into the
          // sentence after it otherwise.
          const why = e instanceof Error ? e.message : 'An attachment could not be uploaded'
          setError(
            `${why.replace(/[.!?]?$/, '.')}`
            + ' Nothing has been sent — every word and every file is still here.',
          )
          return
        } finally {
          setUpload(null)
        }
        const res = await send(
          list, subject, body, forward ? forward.prev : resume ? resume.prev : null, refs,
        )
        refused.current = refusalLine(list, res.refused)
        if (written.current) {
          try { await deleteDraft(draftId.current) } catch (e) { console.error(e) }
        }
      } else if (written.current) {
        // SIGN THE DRAFT AND DELETE IT, in one action at the writer.
        // Saving first means the message that goes out is exactly the
        // one on disk, and the writer deletes the draft only if the
        // send actually happened — a refused send leaves it intact.
        await saveDraft({
          id: draftId.current,
          to: list,
          subj: subject,
          body,
          prev: forward ? forward.prev : resume ? resume.prev : null,
        })
        await sendDraft(draftId.current)
      } else {
        // `prev` is the only thing that makes this a forward rather than
        // a compose. The nexus resolves it to its containing thread and
        // ships the path leading to it; there is no separate forward
        // action.
        const res = await send(list, subject, body, forward ? forward.prev : null)
        refused.current = refusalLine(list, res.refused)
      }
      onDraftsChanged()
      // A SEND WITH REFUSALS IS A SEND. The panel closes and the draft
      // is gone, because the message was signed and did go out to
      // everyone the ship would carry it to; the line names the ones it
      // would not, in their own words, where the send is confirmed.
      //
      // The all-refused case never reaches here: the route answers 400,
      // which arrives as an ApiError and lands in the catch below with
      // the panel open and every word still in it.
      onSent(refused.current)
    } catch (e) {
      // Leave the panel open with the draft intact — a failed send (an
      // unreachable ship, a malformed @p the route's parser rejects)
      // should not look identical to a successful one.
      //
      // AND NO FALSE "SENT" WHEN THE SHIP WAS NEVER REACHED. A send is a
      // poke to the writer and the service worker never touches a POST,
      // so a request that did not arrive signed nothing and delivered
      // nothing. `unreachable` is the fetch having rejected rather than
      // the ship having refused — a distinction `navigator.onLine`
      // cannot make, since a machine with working wifi and a ship that
      // is down is "online". Saying "check the recipient" there would
      // send the user hunting a typo that is not there.
      //
      // AND THE THIRD CASE, which is neither: `fetch` resolved and the
      // body did not parse. The ship answered, so the poke arrived, so
      // this send may have gone out — see `garbled` in api.ts.
      console.error(e)
      setError(
        garbled(e)
          // THE REQUEST LANDED AND THE ANSWER DID NOT PARSE. The poke
          // reached the writer, so this may well have been sent — and
          // "not sent, try again" here is how a message goes out twice.
          ? 'The ship answered but the reply was unreadable — check Sent before'
            + ' resending. Every word is still in this panel.'
          : unreachable(e)
            ? 'Offline — not sent. The ship did not answer, nothing here has been'
              + ' signed, and every word is still in this panel. Try again when it is back.'
            : e instanceof Error ? e.message : 'Could not send. Check the recipient and try again.',
      )
    } finally {
      setSending(false)
    }
  }

  const discard = async () => {
    if (written.current) {
      try { await deleteDraft(draftId.current) } catch (e) { console.error(e) }
      onDraftsChanged()
    }
    onClose()
  }

  return (
    // Full width on a phone, a panel on a desktop. `inset-x-0` below md
    // rather than a fixed 32rem: a 512px panel on a 360px screen is the
    // whole of "no horizontal scroll ever" undone by one composer.
    <div className="fixed inset-x-0 bottom-0 z-40 border-t border-line bg-raised shadow-2xl
      md:inset-x-auto md:right-4 md:w-[32rem] md:rounded-t md:border">
      <header className="flex items-center justify-between border-b border-line bg-sunken px-2 py-1 font-medium text-ink">
        {forward ? 'Forward' : resume ? 'Draft' : 'New message'}
        <span className="flex items-center gap-2">
          {saved && <span className="text-[11px] font-normal text-ink-faint">saved {saved}</span>}
          <button type="button" onClick={closeAndSave} aria-label="Close" className="btn">×</button>
        </span>
      </header>
      <div className="p-2">
        {/* Forwarding transfers evidence rather than quoting text: the
            recipient gets every message on the path, each still signed
            by whoever wrote it, and can check those signatures without
            ever having spoken to those ships. That is the feature — and
            it is also part of the conversation leaving the room, so it
            is stated before the To field rather than after the Send
            button.

            What travels is the ROOT-TO-HERE PATH, not the thread. A
            thread branches wherever two people reply to the same
            message, and sibling branches do not travel — so this counts
            the messages on the path and says so, rather than counting
            the thread. `count` is distinct messages, never stored
            copies: several copies of one message differing in signature
            are one message here. */}
        {forward && (
          <p className="mb-2 rounded-sm bg-warn-soft p-2 text-[11px] text-warn-ink ring-1 ring-warn-line">
            This sends the <strong>signed chain leading to this message</strong> —
            {' '}the {forward.count} {forward.count === 1 ? 'message' : 'messages'} from
            the start of “{forward.subject}” down to it, not just the latest one.
            Other branches of the conversation do not travel. Whoever you name below
            can read every message on that path and can verify for themselves who
            wrote each one. Nobody is on this list yet; add only the people who
            should get that history.
          </p>
        )}
        {/* THE AUDIENCE, AS CHIPS, AND IT IS EXACTLY WHAT WILL BE SENT.
            Typing the start of a mailing list's name offers it beside
            the ships; picking one drops its members in as ordinary chips
            and the list is over. Nothing below this field — the send,
            the draft that is autosaved, the validation — knows a list
            was involved, and a list edited tomorrow does not change a
            draft written today. */}
        <ShipChips
          ships={to}
          pending={pending}
          onShips={(next) => { touched.current = true; setTo(next) }}
          onPending={(next) => { touched.current = true; setPending(next) }}
          onError={setError}
          lists={lists}
          label={forward ? 'Forward to' : 'To'}
          placeholder="~sampel-palnet or a list name"
          disabled={sending}
        />
        <input
          value={subject} onChange={(e) => { touched.current = true; setSubject(e.target.value) }}
          maxLength={1000}
          placeholder="Subject"
          className="field"
        />
        {/* The writer rejects a body over max-body (100,000 bytes) or a
            subject over max-subj (1,000) at compose time, and every send
            ships the whole accumulated chain, so an oversized message
            would otherwise be a send that just fails. These caps count
            UTF-16 units rather than bytes, so they are a guard rail, not
            the authority - the nexus stays the authority. */}
        <textarea
          value={body} onChange={(e) => { touched.current = true; setBody(e.target.value) }}
          maxLength={100000}
          placeholder={forward ? 'Add a note (optional)' : undefined}
          className="field mt-1 h-40 resize-none border-b-0 md:h-48"
        />
        <FilePicker files={files} onChange={setFiles} disabled={sending} />
        {/* SAID WHILE THE FILES ARE ATTACHED, not on the way out. A
            draft grub has no files field, so the autosave that runs
            every 1.5s and the save on close both write this message
            without its attachments — and a resumed draft comes back
            with none. That is a real limit of the draft store, and the
            one thing that would make it a data-loss bug is the user not
            knowing. It is a line of text and not a confirm dialog: the
            composer is not closing yet, there is nothing to confirm,
            and the fix is for the user to press Send. */}
        {files.length > 0 && (
          <p className="mt-1 text-[11px] text-warn-ink">
            Attachments are not saved with drafts — send this message to keep them.
          </p>
        )}
        {/* ONE FILLED BUTTON ON THIS SURFACE, and it is Send. Discard
            is text-weight: it is the destructive one, and a control that
            competes for the eye with the primary action is a control
            people press by mistake. */}
        <div className="mt-2 flex items-center gap-2">
          {/* DISABLED WITH THE REASON, not refused on submit. The
              nexus refuses this send at the route and again at the
              writer, so pressing it is safe - but a button that looks
              live and then reports that the ship will not sign is a
              message someone composed for nothing. Discard still
              works, and so does Save draft: the text is not lost. */}
          <button
            onClick={onSend}
            disabled={(to.length === 0 && !pending.trim()) || sending || !canSign}
            title={canSign ? undefined : NO_KEYS_LINE}
            className="btn btn-primary"
          >
            {upload ?? (sending ? 'Sending…' : forward ? 'Forward' : 'Send')}
          </button>
          <button
            type="button"
            onClick={discard}
            title="Throw this away. Nothing here has been signed, so nothing but the text is lost."
            className="btn btn-danger"
          >
            Discard
          </button>
        </div>
        {/* Said in the panel as well as on the button: a disabled
            control's title is not something a reader finds without
            hovering the thing that is refusing them. */}
        {!canSign && (
          <p className="mt-1 text-[11px] text-warn-ink">{NO_KEYS_LINE}</p>
        )}
        {error && <p className="mt-1 text-danger">{error}</p>}
      </div>
    </div>
  )
}

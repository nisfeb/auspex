# Admission: which mail auspex stores, screens or refuses

A design proposal, 2026-10-27. Nothing here is built yet. The decisions at the top are the owner's, and implementation waits on them.

## Why now

Two things changed. First, libmesa (github.com/mopfel-winrux/libmesa) lets any program act as an Urbit identity without running Arvo, and it mines comets in seconds. Comets were already free, and now they are free at scale. Second, the owner wants mail from comets refused unless the comet is a verified Groundwire comet.

Auspex has no place to put that rule. What exists today:

| Layer | Where | What it can do |
|---|---|---|
| Caps, field widths, chain size | `+incoming-refusal`, spec §4.6 | refuse a whole chain for its shape |
| Quotas | `+quota-refusal` (release 24) | refuse growth past a payer's share |
| Verdicts | spec §3 | label each copy `%verified`, `%unverified` or `%forged` |
| Rules | `$rule` | label and archive stored mail, and nothing else |
| Allow and block lists | `$settings` | decide which attachments download on their own |

The block list does not block mail. A blocked ship's mail still lands in the Inbox, and only its attachments stop downloading. Rules cannot refuse anything, on purpose: the `$rule` comment explains that a filter able to suppress mail would let an attacker who learns your rules hide the evidence of their own forgery. Nothing decides by who the sender is before mail is stored.

## Decisions for the owner

1. **Comets on a stock kernel.** ricsul runs stock vere 4.6 with no `%gw-btc` desk (checked 2026-10-27). A stock jael never holds a comet's key, so no comet's mail ever verifies there, Groundwire or not. "Only verified Groundwire comets" therefore means no comet mail at all on ricsul, `~larwyx` included. Options:
   - (a) An owner allow list of named comets. They are admitted although unverified. **Default.**
   - (b) Run ricsul on the Groundwire kernel. Then Groundwire comets verify and the rule works as asked, with no list.
   - (c) A verifier ship the owner trusts, such as their own Groundwire comet on asimov, which auspex asks whether a comet is attested. This is new protocol surface and a new trust relationship, and it is medium to large work.
   - (d) Accept no comet mail on stock ships.

   On a Groundwire kernel the same policy admits attested comets with no list, so (a) and (b) combine.
2. **The block list blocks mail.** One list for "this sender is unwelcome" that refuses their mail and stops their attachments, instead of two lists with different meanings. Entries already on the attachment block list would start refusing mail. **Default: yes, one list.**
3. **Strangers.** Mail from a verified planet or star the owner has never corresponded with goes to the Inbox today. Keep that, or send first contact to a Screened view until the owner approves the sender. **Default: Inbox, with "screen first contact" as a setting that is off.**
4. **Unverified mail.** Moons that are not the owner's own, and every sender while the key road is denied, read `%unverified`. Today it all goes to the Inbox. **Default: Screened, unless the sender is on the allow list or the copy joins a thread the owner already has.**
5. **The refusal log.** A bounded record of what was refused, kept so a refused sender can be found. **Default: the last 500 refusals, with the subject cut to 100 bytes.**

## The model

Admission runs once per copy that is new to this ship, after verification and before anything is stored. It is the step that decides whether a copy is kept at all. Rules keep their job: they file mail that admission let in.

### What admission may look at

Only attributes an attacker cannot use to make genuine mail disappear:

- the **signed author** of the copy and its **verdict**;
- the author's **class**: galaxy, star, planet, moon or comet (`clan:title`), and for a comet whether it is **attested** (below);
- the **courier**, the ship ames says delivered the poke, which is authenticated;
- whether the copy joins a **thread this ship already holds** and has admitted;
- the owner's **lists**.

Never the subject, the body or attachment names. Those are the sender's text, and a decision keyed on them is a decision the sender controls.

This keeps the `$rule` principle. To have a genuine copy refused, an attacker would have to change who signed it, which a signature prevents, or edit the owner's lists. A forged copy that claims a blocked or unattested author is refused, and no genuine mail is lost by that.

### Three outcomes

| Outcome | Stored | In the Inbox | Owner sees it |
|---|---|---|---|
| admit | yes | yes | as today |
| screen | yes, verdicts and all | no | in a Screened view, with Approve sender and Block sender |
| refuse | no | no | in the refusal log |

Screening is the default for anything doubtful, because it keeps the evidence. Refusal is only for the block list and the comet rule, where the owner has said in advance that they do not want the mail.

### Attested comets

A comet is attested when this ship's jael holds its point and its pass is suite `%c` with the `%groundwire` domain in its tweak:

- clan `%pawn`;
- the copy verifies `%verified`, which already means jael answered `%puby` for it;
- the pass jael gave is suite `%c` (its first byte is `'c'`, crypto-suite 2), and the domain tag `+rub`-decoded from its tweak data is `%groundwire`.

On a Groundwire kernel this holds exactly for comets the domain's verifier checked on Bitcoin, plus any the operator trusted by hand (`%gw-trusted-peer`). On a stock kernel it never holds. A comet's own pass never counts. Spec §3.5 (PR "the spec states its wire contract and its comet rule") makes that normative. Kelvin 408's `com:nu:cric` already verifies suite `%c` against its tweaked key, so verification needs no new code.

Auspex reads only `%puby`, which every jael has. It must not scry anything Groundwire-only. A stock jael blocks on an unknown scry and `mole` does not catch it, a trap trunk already hit with `%dome`.

### The default policy

Evaluated per copy, first match wins:

| # | When | Outcome |
|---|---|---|
| 1 | author or courier is on the block list | refuse ("blocked") |
| 2 | the owner signed it, `%verified` | admit |
| 3 | author is a comet, not attested, not on the allow list | refuse ("unattested comet") |
| 4 | author is on the allow list | admit |
| 5 | it joins a thread this ship holds and admitted | admit |
| 6 | `%verified`, and "screen first contact" is off | admit |
| 7 | anything else, `%forged` included | screen |

Row 5 keeps a conversation whole. A reply from a moon in a thread the owner started lands in the Inbox. Row 7 keeps forged first contacts as evidence without letting them into the Inbox. A forged copy inside an admitted thread meets row 5 and is kept, marked, as today.

### Per message, not per chain

A chain is the path from the root to the newest message, so a verified planet's reply can carry an unattested comet's message in its history. Refusing the whole chain would drop the planet's mail. Each copy new to this ship is judged by its own author. Refused copies are dropped before the merge, and what is left is placed as today, an orphan where its parent was refused (spec §4.7). The thread keeps its id, since the id is the root's hash and needs no stored root. The client says how many earlier messages were not stored and why.

This changes the spec's §4.8 order of operations: admission becomes a step after verification and before the merge. It is receiver-local and changes nothing on the wire.

### Quotas

The quota buckets from release 24 stay, and refusal now comes before them. With unattested comets refused, the shared pool holds moons, allow-listed comets and mail no key could be found for, so a comet swarm no longer drains it. The separate comet sub-pool proposed on 2026-10-27 is not needed.

### The refusal log

One grub, `/mail/refused`, a ring of the last 500 entries: when, courier, author, class, reason, thread id and the subject cut to 100 bytes. Senders still get no receipt (spec §6.4), but the owner can answer "where did ~x's mail go". The log is local state and never travels.

## Where it lives

- `lib/auspex-chain`: a pure `+admit` arm, from copy, verdict, class, attestation, courier, thread context and lists to an outcome and a reason. It is pure so tests cover the whole table.
- `+deliver` in the nexus: one call per new copy, after `+verify-chain`. For a comet author it reads the suite and domain from the pass `+delivery-keys` already fetched, so no new lookup is needed.
- `$settings` becomes `%1`, with a `%0` ladder: `screen-strangers=?`, and the allow and block lists gain their mail meaning (decision 2).
- Thread meta gains `screened=?`. Orrery reads meta as `[ver read archived rest]`, so a version bump does not break it.
- A `screened` view beside `inbox`, `archived` and the rest. Approve adds the sender to the allow list and clears `screened` on their threads. Block adds them to the block list and archives their threads.
- The web client gets a Screened item in the sidebar with a count, the two buttons, and a Senders page holding the allow list, the block list and the refusal log.

## Effect on other clients

- **Talon** asks for the inbox view, so screened mail simply does not appear there. Talon's session should be told about the new view.
- **Thunderbird** mirrors the `all` view, so screened threads would reach it and land in its Inbox. The add-on needs a small change with phase 2: file a screened thread into a Screened folder, or skip it until approved.
- **Desktop** notifies only for admitted Inbox mail.
- **Orrery** sends `%send`, which is outgoing and untouched.

## Phases

1. **Admission core**: `+admit`, the call in `+deliver`, the comet rule, the allow list for comets, the block list refusing mail, and the refusal log. Medium size. Crash-loop rules 7 to 9 apply, since settings and meta change shape.
2. **Screening**: the `screened` flag and view, Approve and Block, and the client's Screened and Senders pages. Medium size.
3. **Option (c), the verifier ship**, only if decision 1 picks it.

## Not in scope

- Content filtering by subject or body. That stays out of admission for the reason above.
- Rate limits per courier. The quotas bound storage, and CPU per poke is a separate problem.
- Senders outside Urbit's PKI. A gateway signs as itself (spec §6.2).

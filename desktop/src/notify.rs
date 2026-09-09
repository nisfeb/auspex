//! The notifier: the one thing this app does that a browser tab does not.
//!
//! One thread. It holds the ship's change beacon open, and on every change
//! re-reads the inbox and raises an OS notification for each thread that has
//! newly become unread. Nothing else — no tray, no background mode, no
//! polling. The app notifies while it is open, like every desktop mail client
//! that is not also a daemon.
//!
//! Why a Rust thread rather than the page's own `subscribeChanges`: the
//! webview is the ship-served client, and the client is not granted any
//! command that could raise a notification (see
//! capabilities/workspace-remote.json). Keeping the beacon read here means the
//! ship-served page has no say at all in what this machine pops up.
//!
//! Everything that decides ANYTHING is a pure function below `run`:
//! `is_change` reads a frame, `diff` reads a listing. The thread is the
//! plumbing around them, and the plumbing is what a test cannot reach.

use std::collections::HashSet;
use std::io::{BufRead, BufReader};
use std::sync::atomic::{AtomicBool, Ordering};

use serde::Deserialize;
use tauri::AppHandle;
use tauri_plugin_notification::NotificationExt;

use crate::commands::dlog;
use crate::config;
use crate::proxy;

/// The beacon: the same stream the web client reads (`ui/src/api.ts`). It
/// carries the whole `/beacon` directory, hence the ` /rev` filter below.
const BEACON: &str = "/grubbery/api/keep/apps/auspex.auspex_app/beacon/rev";

/// The listing, exactly as the client's inbox view asks for it. `limit=20`
/// because this is a notification source, not a mail reader: a change that
/// brought in more new threads than that is capped at three notifications
/// anyway, and the twenty-first row cannot alter the "…and N more" count in
/// any way a person would notice.
const INBOX: &str = "/apps/auspex/api/inbox?view=inbox&limit=20";

/// Notifications per change, before they collapse into one line.
///
/// Three, because a delivery that lands a dozen threads at once (a ship
/// coming back after a week offline) must not put a dozen popups on someone's
/// screen. The alternative — one summary always — loses the sender and
/// subject in the common case, which is the entire content of a mail
/// notification.
pub const CAP: usize = 3;

const BACKOFF_MIN: std::time::Duration = std::time::Duration::from_secs(1);
const BACKOFF_MAX: std::time::Duration = std::time::Duration::from_secs(30);

/// One row of the listing, cut down to what a notification needs.
///
/// Deliberately NOT the client's whole `InboxEntry`. Every field here is one
/// this file reads; adding the rest would make a listing shape change break
/// notifications for no reason. `serde(default)` throughout for the same
/// reason: a row missing a field it never had is not a reason to go silent.
#[derive(Deserialize, Clone, Debug, Default)]
pub struct Row {
    pub id: String,
    #[serde(default)]
    pub subject: String,
    #[serde(default)]
    pub from: String,
    #[serde(default)]
    pub snippet: String,
    /// True when the thread holds at least one %forged copy. The product's
    /// loudest verdict has to stay loud here above all: a notification is
    /// read where the app's own badge is not being looked at.
    #[serde(default)]
    pub forged: bool,
    #[serde(default)]
    pub unread: bool,
}

#[derive(Deserialize)]
struct Listing {
    #[serde(default)]
    threads: Vec<Row>,
}

/// One notification, decided but not yet raised.
#[derive(Debug, PartialEq, Clone)]
pub struct Note {
    pub title: String,
    /// May be empty (the "…and N more new" line has nothing to add), in which
    /// case no body is set on the platform notification at all.
    pub body: String,
}

/// Does this SSE frame mean "something a reader can see changed"?
///
/// The path is in the `event:` line, not the `data:` line — `data:` carries
/// the revision number. A real frame off ~wex:
///
/// ```text
/// id: 2
/// event: old /rev
/// data: 170141184508152222032218166984159176687
/// ```
///
/// Two filters, both load-bearing:
///
///   - ` /rev` — the stream is the whole `/beacon` DIRECTORY, so frames for
///     its other leaves arrive here too and are not changes to the mail.
///   - not `old` — the first frame is the CURRENT value, not a change.
///     Acting on it would re-read the inbox on every reconnect, and since a
///     reconnect is normal (a ship bounce, a sleeping laptop) that is a
///     notification storm waiting for a bad network.
///
/// This mirrors `subscribeChanges` in `ui/src/api.ts`. The two must agree:
/// they read the same stream, and a filter that drifted would leave the app
/// notifying about things the page does not consider changes.
pub fn is_change(frame: &str) -> bool {
    frame
        .lines()
        .find_map(|l| l.strip_prefix("event:"))
        .map(str::trim)
        .is_some_and(|ev| ev.ends_with(" /rev") && !ev.starts_with("old"))
}

/// Take the current unread set without notifying about any of it.
///
/// The launch snapshot. An inbox with forty unread threads in it at startup
/// is a backlog, not news, and forty popups on launch is the surest way to
/// have someone turn notifications off.
pub fn snapshot(seen: &mut HashSet<String>, rows: &[Row]) {
    *seen = rows.iter().filter(|r| r.unread).map(|r| r.id.clone()).collect();
}

/// What to say about this listing, given what was unread at the last look.
///
/// `seen` is the set of thread ids that were unread last time, and it is
/// REPLACED with the current one. That single choice is the whole read/unread
/// behaviour:
///
///   - a thread already unread last time is not new, so an unrelated change
///     does not re-notify about the whole inbox;
///   - a thread the user reads drops out of the set, so if it later goes
///     unread again (a reply arrives, or they mark it unread) it is new
///     again, which is correct — it is news a second time;
///   - a thread that is merely read never produces anything, and read-marks
///     do not bump the beacon anyway (deliberate on the nexus), so reading
///     mail in the app cannot produce a notification at all.
pub fn diff(seen: &mut HashSet<String>, rows: &[Row]) -> Vec<Note> {
    let fresh: Vec<&Row> =
        rows.iter().filter(|r| r.unread && !seen.contains(&r.id)).collect();
    snapshot(seen, rows);
    let extra = fresh.len().saturating_sub(CAP);
    let mut out: Vec<Note> = fresh.into_iter().take(CAP).map(note_for).collect();
    if extra > 0 {
        // no body: the title is the whole message, and a platform that shows
        // an empty body draws a blank line for nothing
        out.push(Note { title: format!("…and {extra} more new"), body: String::new() });
    }
    out
}

/// Sender, subject, snippet — and the verdict when it is the bad one.
///
/// `FORGED` goes FIRST, before the sender it contradicts. A notification is
/// read left to right in half a second and often not read to the end, so a
/// warning after the name it warns about is a warning that arrives too late.
fn note_for(r: &Row) -> Note {
    let subject = if r.subject.is_empty() { "(no subject)" } else { &r.subject };
    let title = if r.forged {
        format!("FORGED · {} · {}", r.from, subject)
    } else {
        format!("{} · {}", r.from, subject)
    };
    Note { title, body: r.snippet.clone() }
}

/// Up once the notifier thread exists, so the two places that start it —
/// launch, and a successful connect — cannot between them start two. Two
/// threads would hold two beacon streams and raise every notification twice.
static RUNNING: AtomicBool = AtomicBool::new(false);

/// Start the notifier, once. Called at launch (a config with a session is
/// already connected as far as the ship is concerned) and again after a
/// connect (which is the first time a fresh install has anything to watch).
pub fn spawn(app: AppHandle) {
    if RUNNING.swap(true, Ordering::SeqCst) {
        return;
    }
    std::thread::spawn(move || run(app));
}

/// GET the inbox listing through the shared agent, with the session attached.
fn fetch_inbox(base: &str) -> Result<Vec<Row>, String> {
    let url = format!("{}{INBOX}", base.trim_end_matches('/'));
    let body = proxy::with_cookie(proxy::agent().get(&url))
        .call()
        .map_err(|e| e.to_string())?
        .into_string()
        .map_err(|e| e.to_string())?;
    Ok(serde_json::from_str::<Listing>(&body)
        .map_err(|e| format!("inbox: {e}"))?
        .threads)
}

fn raise(app: &AppHandle, n: &Note) {
    let mut b = app.notification().builder().title(&n.title);
    if !n.body.is_empty() {
        b = b.body(&n.body);
    }
    match b.show() {
        Ok(()) => dlog(&format!("notify: raised {:?}", n.title)),
        Err(e) => dlog(&format!("notify: could not raise {:?}: {e}", n.title)),
    }
}

/// Re-read the inbox and notify about whatever is newly unread.
fn on_change(app: &AppHandle, base: &str, seen: &mut HashSet<String>) {
    match fetch_inbox(base) {
        Ok(rows) => {
            let notes = diff(seen, &rows);
            dlog(&format!("notify: change — {} row(s), {} new", rows.len(), notes.len()));
            for n in &notes {
                raise(app, n);
            }
        }
        // A failed read is NOT a reason to reset the snapshot: doing that
        // would make the next successful read treat the whole inbox as new.
        Err(e) => dlog(&format!("notify: inbox read failed: {e}")),
    }
}

/// The thread. Open the beacon, read frames until it drops, reconnect.
///
/// The backoff exists because the failure mode it guards against is a ship
/// that is up and refusing (a stale session), which fails INSTANTLY: a bare
/// retry loop there is a hot loop hammering the pier. It doubles to thirty
/// seconds and resets on a whole frame, so an ordinary drop reconnects in a
/// second and a persistent refusal costs two requests a minute.
fn run(app: AppHandle) {
    let mut seen: HashSet<String> = HashSet::new();
    let mut seeded = false;
    let mut backoff = BACKOFF_MIN;
    loop {
        let base = config::load(&app).url;
        // Defensive only. This thread is started from exactly two places and
        // both have a session in hand — launch with a stored config, and a
        // successful connect — so an empty config here means one was removed
        // underneath a running app. Waiting is the right answer and the long
        // wait is deliberate: nothing is going to fix itself sooner, and a
        // tight loop re-reading a file that is not there is worse than a
        // notifier that is half a minute late to a config nobody restored.
        if base.is_empty() || proxy::session_cookie(&config::cookie_file()).is_none() {
            std::thread::sleep(BACKOFF_MAX);
            continue;
        }
        if !seeded {
            match fetch_inbox(&base) {
                Ok(rows) => {
                    snapshot(&mut seen, &rows);
                    seeded = true;
                    dlog(&format!("notify: snapshot — {} unread at start", seen.len()));
                }
                // Seed failed, so the inbox is unknown. Do NOT open the
                // stream: the first change would then read every unread
                // thread as new and replay the whole backlog.
                Err(e) => {
                    dlog(&format!("notify: snapshot failed: {e}"));
                    std::thread::sleep(backoff);
                    backoff = (backoff * 2).min(BACKOFF_MAX);
                    continue;
                }
            }
        }
        let url = format!("{}{BEACON}", base.trim_end_matches('/'));
        // the shared agent has a CONNECT timeout and no read timeout, which is
        // exactly what a stream held open for hours needs
        match proxy::with_cookie(proxy::agent().get(&url).set("accept", "text/event-stream")).call()
        {
            Ok(resp) => {
                dlog(&format!("notify: beacon stream open at {url}"));
                let mut reader = BufReader::new(resp.into_reader());
                let mut frame = String::new();
                let mut line = String::new();
                loop {
                    line.clear();
                    match reader.read_line(&mut line) {
                        Ok(0) | Err(_) => break, // the stream ended or broke
                        Ok(_) => {}
                    }
                    if line.trim().is_empty() {
                        // a blank line ends a frame. Reaching one means the
                        // stream is genuinely working, so the backoff resets
                        // here rather than on connect: a ship that accepts the
                        // connection and immediately drops it would otherwise
                        // never back off at all.
                        backoff = BACKOFF_MIN;
                        if is_change(&frame) {
                            on_change(&app, &base, &mut seen);
                        }
                        frame.clear();
                    } else {
                        frame.push_str(&line);
                    }
                }
                dlog("notify: beacon stream ended");
            }
            Err(e) => dlog(&format!("notify: beacon failed: {e}")),
        }
        std::thread::sleep(backoff);
        backoff = (backoff * 2).min(BACKOFF_MAX);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(id: &str, unread: bool) -> Row {
        Row {
            id: id.to_string(),
            subject: format!("subject {id}"),
            from: "~feb".to_string(),
            snippet: "a snippet".to_string(),
            forged: false,
            unread,
        }
    }

    #[test]
    fn the_first_frame_is_not_a_change() {
        // A reconnect is NORMAL — a ship bounce, a laptop waking — and the
        // stream's first frame is always the current value. Treating it as a
        // change means every reconnect re-reads the inbox, which on a bad
        // network is a notification storm.
        assert!(!is_change("id: 2\nevent: old /rev\ndata: 17014118450815222\n"));
    }

    #[test]
    fn a_rev_frame_is_a_change_and_nothing_else_is() {
        // the shape the ship actually sends when mail lands
        assert!(is_change("id: 3\nevent: new /rev\ndata: 17014118450815999\n"));
        assert!(is_change("event: over /rev\ndata: 1\n"));
        // the stream carries the whole /beacon directory: other leaves are
        // not changes to what a reader can see
        assert!(!is_change("id: 4\nevent: new /other\ndata: 9\n"));
        assert!(!is_change("id: 4\nevent: new /revision\ndata: 9\n"));
        // /rev must be a whole segment, not a suffix of a longer name
        assert!(!is_change("event: new /notrev\ndata: 9\n"));
        // the PATH is in the event line; data carries the revision number, so
        // reading data would match nothing and the notifier would go silent
        assert!(!is_change("id: 5\ndata: new /rev\n"));
        // frames with no event line at all (comments, keepalives) are not
        assert!(!is_change(": keepalive\n"));
        assert!(!is_change(""));
    }

    #[test]
    fn the_launch_snapshot_suppresses_the_backlog() {
        // Forty unread threads at startup is a backlog, not news. This is the
        // difference between an app someone keeps open and one whose
        // notifications they turn off on the first day.
        let rows = vec![row("a", true), row("b", true), row("c", false)];
        let mut seen = HashSet::new();
        snapshot(&mut seen, &rows);
        assert_eq!(seen.len(), 2, "both unread threads are known, neither is news");
        assert!(diff(&mut seen, &rows).is_empty(), "the backlog must never notify");
    }

    #[test]
    fn a_newly_unread_thread_notifies_exactly_once() {
        let mut seen = HashSet::new();
        snapshot(&mut seen, &[row("a", true)]);

        // mail lands
        let rows = vec![row("a", true), row("b", true)];
        let notes = diff(&mut seen, &rows);
        assert_eq!(notes.len(), 1, "only the new thread");
        assert_eq!(notes[0].title, "~feb · subject b");
        assert_eq!(notes[0].body, "a snippet");

        // an unrelated change comes through with the same listing: the beacon
        // fires for anything a reader can see, so this is the common case and
        // re-notifying here would make the app unusable
        assert!(diff(&mut seen, &rows).is_empty(), "the same unread thread is not new twice");
    }

    #[test]
    fn read_then_unread_again_is_news_again() {
        let mut seen = HashSet::new();
        snapshot(&mut seen, &[]);
        assert_eq!(diff(&mut seen, &[row("a", true)]).len(), 1);
        // the user reads it. Read-marks do not bump the beacon, but a later
        // change re-reads the listing and must see it leave the unread set.
        assert!(diff(&mut seen, &[row("a", false)]).is_empty());
        // ...and a reply arrives on that same thread, or they mark it unread
        assert_eq!(
            diff(&mut seen, &[row("a", true)]).len(),
            1,
            "a thread that becomes unread again is news again"
        );
    }

    #[test]
    fn a_flood_is_capped_and_counted() {
        // A ship back after a week delivers everything at once. Twelve popups
        // is not a notification, it is a denial of service on a screen.
        let mut seen = HashSet::new();
        snapshot(&mut seen, &[]);
        let rows: Vec<Row> = (0..12).map(|i| row(&format!("t{i}"), true)).collect();
        let notes = diff(&mut seen, &rows);
        assert_eq!(notes.len(), CAP + 1, "three, then one line for the rest");
        assert_eq!(notes[CAP].title, "…and 9 more new");
        assert!(notes[CAP].body.is_empty(), "the summary has nothing to add");
        // exactly CAP is CAP notes and no summary: "…and 0 more new" would be
        // a whole extra popup saying nothing
        let mut seen = HashSet::new();
        snapshot(&mut seen, &[]);
        let notes = diff(&mut seen, &rows[..CAP]);
        assert_eq!(notes.len(), CAP);
        assert!(notes.iter().all(|n| !n.title.starts_with('…')));
    }

    #[test]
    fn a_forged_copy_says_so_before_it_says_who() {
        // The product's loudest verdict has to stay loud exactly where the
        // app's own badge is not being looked at. FORGED goes first: a
        // notification is read left to right and often not to the end, so a
        // warning after the name it contradicts arrives too late.
        let mut r = row("a", true);
        r.forged = true;
        let n = note_for(&r);
        assert!(n.title.starts_with("FORGED · ~feb · "), "{}", n.title);
        // and a subject-less thread is still identifiable rather than ending
        // in a dangling separator
        let mut r = row("b", true);
        r.subject = String::new();
        assert_eq!(note_for(&r).title, "~feb · (no subject)");
    }

    #[test]
    fn a_read_only_change_notifies_nothing() {
        // read-marks do not bump the beacon (deliberate on the nexus), but if
        // something else does while a thread was just read, the listing has
        // one fewer unread row and that is not an event
        let mut seen = HashSet::new();
        snapshot(&mut seen, &[row("a", true), row("b", true)]);
        assert!(diff(&mut seen, &[row("a", false), row("b", true)]).is_empty());
        assert_eq!(seen.len(), 1, "the read thread left the unread set");
    }

    #[test]
    fn a_listing_is_read_by_the_fields_that_matter_and_no_others() {
        // the real response off ~wex, trimmed. If the client grows a field
        // this must keep parsing; if it loses one this file does not read,
        // likewise.
        let body = r#"{"total":1,"offset":0,"limit":20,"view":"inbox","threads":[
          {"unread":true,"from":"~feb","count":2,"subject":"Re: auspex rename",
           "unreadable":0,"id":"0v3.chp70","verdict":"verified","forged":false,
           "last":1788936514454,"snippet":"reply on the %auspex mark",
           "labels":[],"archived":false,"participants":["~wex","~feb"]}]}"#;
        let l: Listing = serde_json::from_str(body).unwrap();
        assert_eq!(l.threads.len(), 1);
        assert_eq!(l.threads[0].id, "0v3.chp70");
        assert!(l.threads[0].unread);
        assert_eq!(l.threads[0].from, "~feb");
        // an empty inbox is an empty list, not a parse failure
        let l: Listing = serde_json::from_str(r#"{"total":0,"threads":[]}"#).unwrap();
        assert!(l.threads.is_empty());
    }

    use proptest::prelude::*;

    proptest! {
        // a frame classifier fed arbitrary bytes must answer, never panic:
        // it runs on the notifier thread, and a panic there is an app that
        // stops notifying and never says why
        #[test]
        fn is_change_is_total(s in ".{0,120}") {
            let _ = is_change(&s);
        }

        // Whatever the listing says, diff never announces more than CAP + 1
        // things and never announces a thread that was already unread.
        #[test]
        fn diff_never_exceeds_the_cap(
            flags in proptest::collection::vec(any::<bool>(), 0..40),
        ) {
            let rows: Vec<Row> = flags
                .iter()
                .enumerate()
                .map(|(i, u)| row(&format!("t{i}"), *u))
                .collect();
            let mut seen = HashSet::new();
            let notes = diff(&mut seen, &rows);
            prop_assert!(notes.len() <= CAP + 1);
            // and a second identical listing is never news
            prop_assert!(diff(&mut seen, &rows).is_empty());
        }
    }
}

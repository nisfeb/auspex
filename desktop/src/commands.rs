//! The connect flow and the handful of things the webview may ask of the
//! shell. One +code entry, posted to the ship's own `/~/login`; the session it
//! returns is stored under the app config dir and the bridge attaches it to
//! everything from then on, so the webview itself never holds a cookie.

use std::sync::atomic::{AtomicBool, Ordering};

use tauri::{AppHandle, Manager, WebviewUrl, WebviewWindowBuilder};

use crate::config;

/// stderr diagnostics, on when AUSPEX_LOG is set. Costs nothing otherwise and
/// makes "it 403s on my machine" debuggable from a pasted terminal log. The
/// headless harness reads these too — they are the only output an app with no
/// display produces.
pub fn dlog(msg: &str) {
    if std::env::var_os("AUSPEX_LOG").is_some() {
        eprintln!("auspex: {msg}");
    }
}

/// Log in, remember the ship, open the workspace, get the manager out of the
/// way. Async: the blocking login must run off the main thread.
#[tauri::command]
pub async fn connect(app: AppHandle, url: String, code: String) -> Result<String, String> {
    let url = config::normalise_url(&url);
    if url.is_empty() {
        return Err("enter your ship's URL".into());
    }
    dlog(&format!("connect: logging in at {url}"));
    let (cookie, ship) = crate::proxy::login(&url, code.trim())?;
    // The cookie path is published at setup, but connect can be driven by the
    // headless harness before anything has read it back, and a session stored
    // where nothing looks for it is a login that appears to work and then
    // 403s on every request. Resolve it here from the app that certainly has
    // one, and publish it again — idempotent, and it cannot be skipped.
    let ck = config::cookie_path(&app)?;
    crate::proxy::store_cookie(&ck, &cookie)?;
    config::publish_cookie_path(&ck);
    dlog(&format!("connect: ship {ship}, cookie stored at {}", ck.display()));
    let (u, s) = (url.clone(), ship.clone());
    config::update(&app, move |cfg| {
        cfg.url = u;
        cfg.ship = s;
    })?;
    open_workspace(&app, true)?;
    // First connect on a fresh install: there was nothing to watch at launch,
    // so this is where the notifier starts. Idempotent — a reconnect to
    // another ship does not start a second one; the running thread re-reads
    // the config every time it opens the stream.
    crate::notify::spawn(app.clone());
    Ok(ship)
}

/// manager page's "close" button (and Escape), back to the ship UI.
#[tauri::command]
pub fn go_home(app: AppHandle) -> Result<(), String> {
    open_workspace(&app, false)
}

/// Show the connection page IN the workspace window (single-window app: the
/// manager is a page, not a second window). Local shell pages live at
/// tauri://localhost on macOS but http://tauri.localhost on Linux.
pub fn show_manager(app: &AppHandle) -> Result<(), String> {
    let (w, created) = ensure_workspace(app)?;
    // A window sitting on the ship page is REBUILT, not navigated back.
    //
    // Tauri judges every invoke local or remote from the origin the webview
    // reports. On macOS, after navigating from the ship page to
    // tauri://localhost, that origin can still be the ship page's, so the
    // manager falls under the ship page's capability — which here grants only
    // open_external_url and set_theme, so connect, get_config and
    // connection_status would all be refused with "not allowed by acl" and
    // the connect page would be a dead form. A window BORN on manager.html is
    // the one state that provably works on every platform, and the window is
    // born there anyway, so: destroy it, wait for the label to free (destroy
    // is asynchronous), and make a fresh one. The user is leaving the ship
    // page either way.
    if !created && !on_shell_page(&w) {
        // destroying the ONLY window asks the app to exit; main.rs vetoes
        // that while this flag is up
        dlog("manager: the window is on the ship page, rebuilding it");
        REBUILDING.store(true, Ordering::SeqCst);
        if let Err(e) = w.destroy() {
            REBUILDING.store(false, Ordering::SeqCst);
            return Err(e.to_string());
        }
        let h = app.clone();
        std::thread::spawn(move || {
            for _ in 0..100 {
                if h.get_webview_window("workspace").is_none() {
                    break;
                }
                std::thread::sleep(std::time::Duration::from_millis(20));
            }
            let h2 = h.clone();
            h.run_on_main_thread(move || {
                let made = new_workspace(&h2);
                REBUILDING.store(false, Ordering::SeqCst);
                dlog(&format!("manager: rebuilt the window: {}", made.is_ok()));
                match made {
                    Ok(w) => {
                        w.set_focus().ok();
                    }
                    Err(e) => dlog(&format!("manager: rebuilding the window failed: {e}")),
                }
            })
            .ok();
        });
        return Ok(());
    }
    if !created {
        let url: tauri::Url = "tauri://localhost/manager.html"
            .parse()
            .map_err(|e| format!("{e}"))?;
        w.navigate(url).map_err(|e| e.to_string())?;
    }
    w.set_focus().ok();
    Ok(())
}

/// The page mirrors its colour scheme into the window. The native surfaces
/// (the GTK menubar, and WebKitGTK's own scrollbars in any frame that does
/// not style them) follow the WINDOW theme, not the page, and on Linux the
/// window theme is GTK's light default whatever the desktop portal says. The
/// page does know prefers-color-scheme, so it tells us, on load and whenever
/// it changes. macOS honours the same call.
#[tauri::command]
pub fn set_theme(app: AppHandle, dark: bool) -> Result<(), String> {
    let Some(w) = app.get_webview_window("workspace") else { return Ok(()) };
    w.set_theme(Some(if dark { tauri::Theme::Dark } else { tauri::Theme::Light }))
        .map_err(|e| e.to_string())
}

/// Up while show_manager is between destroying the workspace window and making
/// its replacement. The window is the app's only one, so its destruction reads
/// as "last window closed, exit"; main.rs checks this and vetoes that exit.
pub static REBUILDING: AtomicBool = AtomicBool::new(false);

/// Is the window showing one of the shell's own pages (the manager) rather
/// than the ship-served app?
pub fn on_shell_page(w: &tauri::WebviewWindow) -> bool {
    w.url()
        .map(|u| u.scheme() == "tauri" || u.host_str() == Some("tauri.localhost"))
        .unwrap_or(false)
}

/// The single window is always BORN on manager.html. The app-page protocol
/// handler only attaches to webviews created on an app URL, and a window born
/// on the bridge origin cannot navigate back to the shell's pages ("Could not
/// connect to tauri.localhost").
fn ensure_workspace(app: &AppHandle) -> Result<(tauri::WebviewWindow, bool), String> {
    match app.get_webview_window("workspace") {
        Some(w) => Ok((w, false)),
        None => Ok((new_workspace(app)?, true)),
    }
}

#[tauri::command]
pub fn get_config(app: AppHandle) -> config::Config {
    config::load(&app)
}

#[derive(serde::Serialize)]
pub struct ConnStatus {
    pub url: String,
    /// the ship we are logged in to, when the session actually works
    pub ship: Option<String>,
    pub connected: bool,
    /// set when we could not reach the ship at all (as opposed to being
    /// reachable but unauthenticated). The two need different advice
    pub error: Option<String>,
}

/// What the connection page shows. A configured URL is NOT the same as being
/// logged in, and a page that renders the login form whenever it has nothing
/// better to say makes an already-connected ship look signed out. Async: this
/// makes a real authenticated request.
#[tauri::command]
pub async fn connection_status(app: AppHandle) -> ConnStatus {
    let cfg = config::load(&app);
    if cfg.url.is_empty() {
        return ConnStatus { url: String::new(), ship: None, connected: false, error: None };
    }
    match crate::proxy::probe(&cfg.url) {
        Ok(Some(ship)) => {
            // whoami named the ship; fall back to the stored @p only if the
            // body was unreadable, and never claim one we cannot reach
            let ship = if ship.is_empty() { cfg.ship.clone() } else { ship };
            dlog(&format!("status: connected to {ship}"));
            let ship = (!ship.is_empty()).then_some(ship);
            ConnStatus { url: cfg.url, ship, connected: true, error: None }
        }
        Ok(None) => {
            dlog("status: reachable but not authenticated");
            ConnStatus { url: cfg.url, ship: None, connected: false, error: None }
        }
        Err(e) => {
            dlog(&format!("status: unreachable: {e}"));
            ConnStatus { url: cfg.url, ship: None, connected: false, error: Some(e) }
        }
    }
}

/// Schemes a system handler can sensibly open, and the ONLY ones that leave
/// the app. This is a trust boundary, not a convenience check: the workspace
/// webview renders ship-served content — and in a mail client that content
/// includes links written by whoever sent you a message — so a page could ask
/// us to hand any string to the desktop's URL dispatcher. Refusing here rather
/// than in the page's javascript is the difference between a policy and a
/// suggestion.
///
/// `mailto` is in the list and `tel` is not: this is a mail client, and the
/// one scheme its content plausibly carries is the one that opens a composer.
///
/// Control characters are refused too. The URL is passed as one argv element
/// so no shell parses it, but a handler further down the chain might, and a
/// newline is how a single argument becomes two.
pub fn openable(url: &str) -> bool {
    let Some((scheme, rest)) = url.split_once(':') else { return false };
    if rest.is_empty() {
        return false;
    }
    if !matches!(scheme.to_ascii_lowercase().as_str(), "http" | "https" | "mailto") {
        return false;
    }
    !url.contains(|c: char| c.is_control())
}

/// Hand a vetted URL to the desktop's own dispatcher.
///
/// This is instead of tauri-plugin-opener, which costs ~35 crates (an entire
/// async executor: async-io, polling, blocking, rustix) to run what is one
/// process spawn. No shell is involved: Command passes argv directly.
pub fn open_external(url: &str) -> Result<(), String> {
    if !openable(url) {
        return Err(format!("refused to open {url:?}"));
    }
    // Windows: NOT `cmd /C start` — `&`, `|`, `^` and `%` are legal in a URL
    // query string and are cmd metacharacters, so a crafted link would run
    // a command. rundll32's FileProtocolHandler takes the URL as a plain
    // argv entry and hands it to the default handler with no shell in the
    // path, which is the same property `open` and `xdg-open` have.
    let (bin, pre): (&str, &[&str]) = if cfg!(target_os = "macos") {
        ("open", &[])
    } else if cfg!(target_os = "windows") {
        ("rundll32", &["url.dll,FileProtocolHandler"])
    } else {
        ("xdg-open", &[])
    };
    let child = std::process::Command::new(bin)
        .args(pre)
        .arg(url)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .map_err(|e| format!("{bin}: {e}"))?;
    // reap it. The handler exits immediately after handing off to the
    // browser, and an unwaited child stays a zombie for the life of the app.
    std::thread::spawn(move || {
        let mut child = child;
        let _ = child.wait();
    });
    Ok(())
}

/// The webview's route to the same policy.
#[tauri::command]
pub fn open_external_url(url: String) -> Result<(), String> {
    open_external(&url)
}

/// Open (or reuse) the workspace on the localhost bridge. The webview only
/// ever talks to 127.0.0.1. The bridge relays to the ship with the session
/// attached Rust-side, so no webkit cookie behaviour (site pinning,
/// third-party policy, SW-mediated fetch) can unauthenticate a view — which
/// matters more here than in lattice, because the auspex client is a PWA and
/// its service worker mediates every fetch it makes.
///
/// `fresh` (a new connect) also clears browsing data so a stale service worker
/// and cache from an earlier session — or another ship — cannot linger.
pub fn open_workspace(app: &AppHandle, fresh: bool) -> Result<(), String> {
    let cfg = config::load(app);
    if cfg.url.is_empty() {
        return Err("connect to a ship first".into());
    }
    let local = crate::proxy::ensure(app.state::<crate::proxy::Bridge>().inner(), &cfg.url)?;
    let home: tauri::Url = format!("{local}/apps/auspex/")
        .parse()
        .map_err(|e| format!("{e}"))?;
    // the bridge means the webview needs no cookies, so the window may be
    // born on the local manager page and freely navigate to the ship
    let (w, _) = ensure_workspace(app)?;
    if fresh {
        dlog(&format!("clear browsing data: {:?}", w.clear_all_browsing_data()));
    }
    dlog(&format!("navigate: {home}"));
    w.navigate(home).map_err(|e| e.to_string())?;
    w.set_focus().ok();
    Ok(())
}

/// What to do with a top-level navigation the workspace attempted.
#[derive(Debug, PartialEq)]
enum Nav {
    /// stay in the webview as-is
    Allow,
    /// renavigate the workspace to this url instead
    Rewrite(tauri::Url),
    /// hand to the system opener, which applies openable()
    External,
    /// nothing to open and nothing to rewrite, so the navigation just stops
    Block,
}

/// The whole navigation policy, with no AppHandle and no window in it, so the
/// branches read as one table instead of as plumbing.
///
/// `bridge` yields the live bridge port and `ship_url` the configured ship
/// base, both looked up only if the decision gets far enough to need them.
/// Laziness is the point: some webkits run every frame through this hook, so
/// neither a mutex nor a config read belongs on the path that answers those.
fn nav_decision(
    u: &tauri::Url,
    bridge: impl FnOnce() -> Option<u16>,
    ship_url: impl FnOnce() -> String,
) -> Nav {
    // local shell pages: tauri:// (macOS) or http://tauri.localhost (Linux)
    if u.scheme() == "tauri" || u.host_str() == Some("tauri.localhost") {
        return Nav::Allow;
    }
    // in-page pseudo-navigations. Never route these to the system opener:
    // that pops up "Could not read file about:src:doc."
    if matches!(u.scheme(), "about" | "blob" | "data") {
        return Nav::Allow;
    }
    let bridge = bridge();
    if u.host_str() == Some("127.0.0.1") && u.port() == bridge {
        return Nav::Allow;
    }
    let local = bridge.map(|p| format!("http://127.0.0.1:{p}"));
    // absolute links to the ship's real origin re-route through the bridge.
    // Hitting the ship directly would arrive cookieless — and auspex has no
    // unauthenticated surface at all, so that is a 403, not a login page.
    if tauri::Url::parse(&ship_url()).is_ok_and(|ship| ship.origin() == u.origin()) {
        let Some(local) = &local else { return Nav::Block };
        let pq = &u.as_str()[u.origin().ascii_serialization().len()..];
        return match format!("{local}{pq}").parse::<tauri::Url>() {
            Ok(t) => Nav::Rewrite(t),
            Err(_) => Nav::Block,
        };
    }
    // only things a system handler can sensibly open leave the app. Anything
    // else is silently blocked (an opener error is a popup)
    Nav::External
}

fn new_workspace(app: &AppHandle) -> Result<tauri::WebviewWindow, String> {
    let handle = app.clone();
    let w = WebviewWindowBuilder::new(app, "workspace", WebviewUrl::App("manager.html".into()))
        .title("auspex")
        .inner_size(1200.0, 800.0)
        // tauri's own drag-drop interception would swallow the HTML5 drop
        // events the client's attachment drop zone listens for
        .disable_drag_drop_handler()
        // a webview without browser chrome has no other way to zoom
        .zoom_hotkeys_enabled(true)
        // keep the workspace on the bridge (or the shell's own pages). Any
        // other top-level navigation opens in the system browser. The webview
        // has no back button or url bar to escape from
        .on_navigation(move |u| {
            // renavigate the workspace ourselves, off-thread so the queued
            // navigate never re-enters the policy callback we are inside
            let renav = |t: tauri::Url| {
                let h = handle.clone();
                std::thread::spawn(move || {
                    let h2 = h.clone();
                    h.run_on_main_thread(move || {
                        if let Some(w) = h2.get_webview_window("workspace") {
                            w.navigate(t).ok();
                        }
                    })
                    .ok();
                });
            };
            let bridge = || {
                handle
                    .state::<crate::proxy::Bridge>()
                    .inner()
                    .0
                    .lock()
                    .unwrap()
                    .as_ref()
                    .map(|(_, p)| *p)
            };
            match nav_decision(u, bridge, || config::load(&handle).url) {
                Nav::Allow => true,
                Nav::Rewrite(t) => {
                    renav(t);
                    false
                }
                Nav::External => {
                    open_external(u.as_str()).ok();
                    false
                }
                Nav::Block => false,
            }
        })
        .build()
        .map_err(|e| e.to_string())?;
    Ok(w)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_a_handler_scheme_ever_leaves_the_app() {
        // This is a trust boundary. The workspace renders ship-served mail,
        // and the links in mail are written by whoever sent it.
        assert!(openable("https://example.com"));
        assert!(openable("http://example.com/a?b=c#d"));
        assert!(openable("mailto:someone@example.com"));
        assert!(openable("MAILTO:someone@example.com"), "the scheme is case-insensitive");
        // a mail client's own scheme is not a browser scheme
        assert!(!openable("file:///etc/passwd"));
        assert!(!openable("javascript:alert(1)"));
        assert!(!openable("smb://host/share"));
        assert!(!openable("urb://ship/thing"));
        // a scheme with nothing after it is nothing to open
        assert!(!openable("https:"));
        assert!(!openable("example.com"), "a bare host names no handler");
        assert!(!openable(""));
        // one argv element, but a handler down the chain might parse it, and
        // a newline is how one argument becomes two
        assert!(!openable("https://example.com\nrm -rf /"));
        assert!(!openable("https://example.com\r\nx"));
        assert!(!openable("mailto:a@b\u{0}c"));
    }

    fn url(s: &str) -> tauri::Url {
        s.parse().unwrap()
    }

    #[test]
    fn the_workspace_stays_on_the_bridge() {
        let ship = || "http://ship.example.com".to_string();
        let port = || Some(26600u16);

        // the shell's own pages, both platforms' spellings
        assert_eq!(nav_decision(&url("tauri://localhost/manager.html"), port, ship), Nav::Allow);
        assert_eq!(
            nav_decision(&url("http://tauri.localhost/manager.html"), port, ship),
            Nav::Allow
        );
        // the bridge itself, which is where the client lives
        assert_eq!(
            nav_decision(&url("http://127.0.0.1:26600/apps/auspex/"), port, ship),
            Nav::Allow
        );
        // in-page pseudo-navigations must never reach the system opener
        assert_eq!(nav_decision(&url("about:srcdoc"), port, ship), Nav::Allow);
        assert_eq!(nav_decision(&url("blob:http://127.0.0.1:26600/x"), port, ship), Nav::Allow);

        // A link to the ship's REAL origin goes back through the bridge.
        // Following it directly would arrive cookieless, and auspex has no
        // unauthenticated surface at all — so that is a 403, not a login.
        assert_eq!(
            nav_decision(&url("http://ship.example.com/apps/auspex/?x=1"), port, ship),
            Nav::Rewrite(url("http://127.0.0.1:26600/apps/auspex/?x=1"))
        );
        // ...and with no bridge up there is nowhere to send it
        assert_eq!(
            nav_decision(&url("http://ship.example.com/apps/auspex/"), || None, ship),
            Nav::Block
        );
        // a port that is not OUR port is not the bridge
        assert_eq!(
            nav_decision(&url("http://127.0.0.1:9999/x"), port, ship),
            Nav::External
        );
        // anything genuinely elsewhere leaves, subject to openable()
        assert_eq!(nav_decision(&url("https://example.com/"), port, ship), Nav::External);
    }
}

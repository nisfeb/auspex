//! Persisted app config — the ship URL and the @p we logged in as — plus the
//! one place the session cookie's location is decided.
//!
//! Both live under `<app_config_dir>`: `config.json` and `cookie`. Lattice
//! keeps its cookie in `~/.config/lattice-fs/cookie` because the `lattice-fs`
//! CLI shares it. Nothing shares this one, so it belongs beside the config it
//! is meaningless without.

use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};

use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Clone, Default)]
pub struct Config {
    pub url: String,
    /// The ship's @p, learned at connect from the cookie's own name. Display
    /// only — nothing keys off it.
    #[serde(default)]
    pub ship: String,
}

/// What the connect box's text means as a ship base.
///
/// Trailing slashes go because every route is appended to this, and
/// `http://ship//apps/auspex` is not the same URL. A missing scheme is
/// ADDED rather than refused: the placeholder shows one, but `localhost:8081`
/// is what people actually type, and without a scheme `Url::parse` fails and
/// the whole flow reports "cannot reach this ship" about a ship that is fine.
pub fn normalise_url(raw: &str) -> String {
    let t = raw.trim().trim_end_matches('/').trim();
    if t.is_empty() {
        return String::new();
    }
    if t.starts_with("http://") || t.starts_with("https://") {
        t.to_string()
    } else {
        format!("http://{t}")
    }
}

pub fn load_at(p: &Path) -> Config {
    std::fs::read_to_string(p)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

pub fn save_at(p: &Path, c: &Config) -> Result<(), String> {
    if let Some(dir) = p.parent() {
        std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    let s = serde_json::to_string_pretty(c).map_err(|e| e.to_string())?;
    std::fs::write(p, s).map_err(|e| e.to_string())
}

fn dir(app: &tauri::AppHandle) -> Option<PathBuf> {
    use tauri::Manager;
    app.path().app_config_dir().ok()
}

fn path(app: &tauri::AppHandle) -> Option<PathBuf> {
    dir(app).map(|d| d.join("config.json"))
}

fn require_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    path(app).ok_or_else(|| "no app config dir to save into".to_string())
}

/// `<app_config_dir>/cookie`. The session goes here at connect and every
/// outbound request reads it back from here.
pub fn cookie_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    dir(app)
        .map(|d| d.join("cookie"))
        .ok_or_else(|| "no app config dir for the session cookie".to_string())
}

/// The cookie path, published once so the code that has no AppHandle can
/// still attach the session: the bridge answers each webview connection on
/// its own thread, and the notifier runs on another, and neither is handed an
/// app. Resolving the config dir is the AppHandle's only contribution, so it
/// is done once at setup and the answer left here.
fn cookie_slot() -> &'static Mutex<String> {
    static SLOT: OnceLock<Mutex<String>> = OnceLock::new();
    SLOT.get_or_init(Default::default)
}

pub fn publish_cookie_path(p: &Path) {
    *cookie_slot().lock().unwrap() = p.to_string_lossy().into_owned();
}

/// Where the session cookie is, as the bridge and the notifier see it. Empty
/// before setup has run, which `session_cookie` reads as "no session" — the
/// same answer a missing file gives, and the right one either way.
pub fn cookie_file() -> String {
    cookie_slot().lock().unwrap().clone()
}

/// A config we cannot locate reads as the default, exactly as an unreadable
/// or corrupt one does (see `load_at`). `load` runs on the notifier thread
/// and inside the webview's navigation callback, so losing the config dir
/// must not take either of them down with it.
pub fn load(app: &tauri::AppHandle) -> Config {
    match path(app) {
        Some(p) => load_at(&p),
        None => {
            crate::commands::dlog("config: no app config dir; using defaults");
            Config::default()
        }
    }
}

/// The one lock guarding every load-modify-save span through config.json. It
/// lives here, with the load and the save it sits between, rather than with
/// any caller: a lock a caller can reach around is no lock at all.
fn lock() -> &'static Mutex<()> {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(Default::default)
}

/// Load config.json at `p`, let `f` mutate it in place, save it back, all
/// under the one lock.
pub fn update_at(p: &Path, f: impl FnOnce(&mut Config)) -> Result<Config, String> {
    let _guard = lock().lock().unwrap();
    let mut cfg = load_at(p);
    f(&mut cfg);
    save_at(p, &cfg)?;
    Ok(cfg)
}

/// `update_at` against the app's own config.json. The helper every writer
/// should reach for.
pub fn update(app: &tauri::AppHandle, f: impl FnOnce(&mut Config)) -> Result<Config, String> {
    update_at(&require_path(app)?, f)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp(tag: &str) -> PathBuf {
        use std::sync::atomic::{AtomicUsize, Ordering};
        static N: AtomicUsize = AtomicUsize::new(0);
        std::env::temp_dir().join(format!(
            "auspex-cfg-{}-{tag}-{}.json",
            std::process::id(),
            N.fetch_add(1, Ordering::Relaxed)
        ))
    }

    #[test]
    fn roundtrip() {
        // The config is two fields, and losing either one is a relaunch that
        // lands on the connect page with a live session sitting right there.
        let p = tmp("roundtrip");
        let c = Config { url: "http://localhost:8081".into(), ship: "~wex".into() };
        save_at(&p, &c).unwrap();
        let back = load_at(&p);
        assert_eq!(back.url, c.url);
        assert_eq!(back.ship, c.ship);
        std::fs::remove_file(&p).ok();

        // update_at is load-modify-save: what it writes must be what comes
        // back, and it must create the file (and its directory) from nothing
        let p2 = tmp("update");
        update_at(&p2, |c| c.url = "http://localhost:8080".into()).unwrap();
        update_at(&p2, |c| c.ship = "~feb".into()).unwrap();
        let back = load_at(&p2);
        assert_eq!(back.url, "http://localhost:8080", "the first write survived the second");
        assert_eq!(back.ship, "~feb");
        std::fs::remove_file(&p2).ok();
    }

    #[test]
    fn a_missing_or_corrupt_config_is_the_default_and_never_a_panic() {
        // load runs on the notifier thread and in the navigation callback
        assert!(load_at(Path::new("/nonexistent/auspex/config.json")).url.is_empty());
        let p = tmp("junk");
        std::fs::write(&p, b"{not json at all").unwrap();
        assert!(load_at(&p).url.is_empty());
        std::fs::remove_file(&p).ok();
    }

    #[test]
    fn the_url_normaliser_makes_a_base_out_of_what_people_type() {
        // a trailing slash would make every route //apps/auspex/...
        assert_eq!(normalise_url("http://localhost:8081/"), "http://localhost:8081");
        assert_eq!(normalise_url("  http://localhost:8081  "), "http://localhost:8081");
        assert_eq!(normalise_url("https://ship.example.com///"), "https://ship.example.com");
        // a bare host is the common paste, and refusing it reports a healthy
        // ship as unreachable
        assert_eq!(normalise_url("localhost:8081"), "http://localhost:8081");
        assert_eq!(normalise_url("ship.example.com"), "http://ship.example.com");
        // https is never downgraded
        assert_eq!(normalise_url("https://ship.example.com"), "https://ship.example.com");
        // nothing typed is nothing configured, not "http://"
        assert_eq!(normalise_url("   "), "");
        assert_eq!(normalise_url("/"), "");
    }

    use proptest::prelude::*;

    proptest! {
        // few cases: each one touches the filesystem
        #![proptest_config(ProptestConfig { cases: 48, ..ProptestConfig::default() })]

        // a hand-edited config file must load as the default, never panic
        // the app at startup
        #[test]
        fn load_is_total_on_arbitrary_bytes(bytes in proptest::collection::vec(any::<u8>(), 0..256)) {
            let p = tmp("prop-junk");
            std::fs::write(&p, &bytes).unwrap();
            let _ = load_at(&p);
            std::fs::remove_file(&p).ok();
        }

        // save -> load is the identity for any field content (quotes,
        // backslashes, unicode — everything JSON escaping must survive)
        #[test]
        fn config_roundtrips(url in ".{0,32}", ship in ".{0,32}") {
            let c = Config { url: url.clone(), ship: ship.clone() };
            let p = tmp("prop-rt");
            save_at(&p, &c).unwrap();
            let back = load_at(&p);
            std::fs::remove_file(&p).ok();
            prop_assert_eq!(back.url, url);
            prop_assert_eq!(back.ship, ship);
        }

        // whatever is typed, the result is empty or a parseable base with no
        // trailing slash: everything downstream appends a path to it
        #[test]
        fn normalise_always_yields_a_usable_base(raw in ".{0,40}") {
            let n = normalise_url(&raw);
            prop_assert!(n.is_empty() || !n.ends_with('/'));
        }
    }
}

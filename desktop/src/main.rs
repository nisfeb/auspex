#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;
mod config;
mod notify;
mod proxy;
#[cfg(test)]
mod testutil;

use std::sync::Mutex;

use tauri::Manager;

/// The menubar: Edit, then Preferences.
///
/// Edit is not decoration. On macOS a webview only receives Cmd-C/V/X/A
/// through the standard Edit items; Tauri installs them in its default menu,
/// and setting our own menu throws that away — which is why nobody could
/// paste a +code on a Mac. The items are predefined: the OS routes them to the
/// focused responder, so they need no handler here. It matters twice over in a
/// mail client, where the window is mostly a text field.
///
/// Preferences is one item, because there is one setting. It exists at all
/// because the manager auto-hides after connect, and a connection page with no
/// way back to it is a page you reach by deleting config.json.
fn build_menu(app: &tauri::App) -> tauri::Result<()> {
    let edit = tauri::menu::SubmenuBuilder::new(app, "Edit")
        .undo()
        .redo()
        .separator()
        .cut()
        .copy()
        .paste()
        .select_all()
        .build()?;
    let prefs = tauri::menu::SubmenuBuilder::new(app, "Preferences")
        .text("manager", "connection…")
        .build()?;
    // Worth knowing on macOS: the leading submenu becomes the application
    // menu, so Edit takes that slot there. Cosmetic, on a platform this has
    // not been run on; revisit when there is a mac to look at.
    app.set_menu(tauri::menu::MenuBuilder::new(app).items(&[&edit, &prefs]).build()?)?;
    Ok(())
}

/// The headless test harness, inert unless AUSPEX_AUTOCONNECT is set.
///
/// `AUSPEX_AUTOCONNECT="url,+code"` drives the REAL connect flow with no
/// display, which is the only way to check the login, the bridge and the
/// notifier against a live ship from a shell. Setting it requires already
/// controlling this process's environment, the same bar as handing it a
/// +code on the command line.
fn spawn_test_harness(handle: &tauri::AppHandle) {
    if let Ok(spec) = std::env::var("AUSPEX_AUTOCONNECT") {
        if let Some((u, c)) = spec.split_once(',') {
            let h = handle.clone();
            let (u, c) = (u.to_string(), c.to_string());
            std::thread::spawn(move || {
                std::thread::sleep(std::time::Duration::from_secs(3));
                let r = tauri::async_runtime::block_on(commands::connect(h.clone(), u, c));
                commands::dlog(&format!("autoconnect: {r:?}"));
            });
        }
    }
}

fn main() {
    // webkit2gtk's dmabuf renderer crashes some Wayland stacks outright
    // ("Error 71 (Protocol error) dispatching to Wayland display"). Opt out
    // there, but ONLY there. The fallback is software rendering, and paying it
    // on X11/XWayland sessions makes the whole UI feel sluggish for nothing.
    #[cfg(target_os = "linux")]
    if std::env::var_os("WEBKIT_DISABLE_DMABUF_RENDERER").is_none()
        && std::env::var_os("WAYLAND_DISPLAY").is_some()
        && std::env::var_os("GDK_BACKEND").is_none_or(|b| b != "x11")
    {
        std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
    }
    tauri::Builder::default()
        .plugin(tauri_plugin_notification::init())
        .manage(proxy::Bridge(Mutex::new(None)))
        .on_menu_event(|app, ev| {
            // single-window app: the manager is a page in the workspace
            if ev.id().as_ref() == "manager" {
                commands::show_manager(app).ok();
            }
        })
        .setup(|app| {
            build_menu(app)?;
            let handle = app.handle().clone();
            // Before ANYTHING can make a request: the bridge's connection
            // threads and the notifier read the session through
            // config::cookie_file(), and an empty one reads as "no session",
            // which would 403 a perfectly good login.
            match config::cookie_path(&handle) {
                Ok(p) => {
                    config::publish_cookie_path(&p);
                    commands::dlog(&format!("session cookie: {}", p.display()));
                }
                Err(e) => commands::dlog(&format!("no cookie path: {e}")),
            }
            spawn_test_harness(&handle);
            let cfg = config::load(&handle);
            if cfg.url.is_empty() {
                // first run: the single window opens on the connect page
                commands::show_manager(&handle)?;
            } else {
                // off-thread: bridge setup does network work that must not
                // block the main loop
                let h = handle.clone();
                std::thread::spawn(move || {
                    commands::open_workspace(&h, false).ok();
                });
            }
            // The whole point of the app. Started here so a launch with a
            // stored session notifies without anyone touching the connect
            // page; connect() starts it too, for the first run, and the two
            // calls between them can only ever start one thread.
            notify::spawn(handle.clone());
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::connect,
            commands::connection_status,
            commands::get_config,
            commands::go_home,
            commands::open_external_url,
            commands::set_theme,
        ])
        .build(tauri::generate_context!())
        .expect("error building auspex desktop")
        .run(|_app, event| {
            // the manager rebuild destroys the only window and makes a new
            // one; the gap must not read as "last window closed"
            if let tauri::RunEvent::ExitRequested { code: None, api, .. } = &event {
                if commands::REBUILDING.load(std::sync::atomic::Ordering::SeqCst) {
                    api.prevent_exit();
                }
            }
        });
}

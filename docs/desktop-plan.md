# auspex desktop — plan

**Purpose:** native notifications for new mail. Nothing else. The desktop app
is the web client in a window, plus one Rust thread that watches the ship's
change beacon and raises an OS notification when an unread thread appears.

**Shape:** lattice's desktop app with the FUSE half removed. The parts worth
keeping are exactly the parts that took lattice several releases to get right,
and none of them are about mounts:

- **The localhost bridge.** The webview talks only to `127.0.0.1:<port>`; the
  app relays every request to the ship with the session cookie attached
  Rust-side. Webkit cookie policy (which varies by build and silently drops
  cookies on cross-site flows and service-worker fetches) can therefore never
  unauthenticate a view. Copied from `lattice/desktop/src/proxy.rs` with the
  cookie path changed; the port base is **26600** (lattice holds 26500) so the
  two apps run side by side, and it is fixed for the same reason lattice's is:
  the port is the webview's origin, and the service-worker cache, localStorage
  (theme) and everything else is keyed by origin.
- **The connect page.** Ship URL + `+code` once; Rust posts `/~/login`, stores
  the cookie under the app config dir, remembers the URL. `connection_status`
  makes a real authenticated request rather than checking that a URL exists.
  Copied from `manager.html` with the mounts, backups and local-ships sections
  deleted.
- **Menus.** Edit (undo/redo/cut/copy/paste/select-all — without it a Mac
  webview cannot paste a `+code`), and Preferences → connection.
- **External links** open in the system browser; the ship stays in the app.

## The notifier

One thread, started after connect, reconnecting with backoff when the stream
drops:

1. `GET /grubbery/api/keep/apps/auspex.auspex_app/beacon/rev` with
   `Accept: text/event-stream` and the cookie — the same stream the web client
   reads. The first event (`old …`) is the current value, not a change, and is
   ignored; each later ` /rev` event is "something a reader can see changed".
2. On each change: `GET /apps/auspex/api/inbox?view=inbox&limit=20`. Rows with
   `unread: true` whose thread id was not in the last snapshot are **new**.
   The snapshot is taken at connect, so launching never replays the backlog.
3. One notification per new thread — title `~from · subject`, body the
   snippet — capped at 3 per change, then one "…and N more". A row with
   `forged: true` is titled `FORGED · ~from · subject`: the product's loudest
   verdict stays loud where the user is not looking at the app.
4. Read-marks do not bump the beacon (deliberate on the nexus), so reading mail
   in the app never produces a notification storm, and a thread the user has
   already opened never notifies twice.

`tauri-plugin-notification` raises them. It is the platform's notification
system and nothing more: no click-to-focus on Linux (the plugin does not
support actions there), which is a stated ceiling, not a bug.

## What is deliberately not built

- **No tray, no background mode.** The app notifies while it is open, like
  every desktop mail client that is not also a daemon. Minimise-to-tray is the
  upgrade path if it ever matters.
- **No code signing.** Unsigned bundles, right-click → Open on macOS. Adding
  the `APPLE_*` secrets to `release.yml` is the whole change, and lattice's
  workflow comments say exactly why they are absent by default.
- **No offline queue, no backups, no lick.** They are lattice features and mail
  does not want them: the web client already has its own offline shell and
  honest "not sent".

## Layout

    desktop/
      Cargo.toml  tauri.conf.json  build.rs  icon-src.svg  icons/  capabilities/
      src/main.rs        window, menu, harness env, notifier spawn
      src/config.rs      url, ship, cookie path — <app_config_dir>/config.json
      src/proxy.rs       the bridge (lattice's, cookie path changed)
      src/commands.rs    connect, connection_status, get_config, go_home,
                         open_external_url, set_theme
      src/notify.rs      beacon stream, inbox diff, notification — the only
                         new code, and the only code with real tests
      ui/manager.html    the connect page
    scripts/desktop-commands.mjs   build.rs ↔ invoke_handler ↔ capabilities
                                   parity (lattice's, verbatim — every
                                   omission it catches shipped three times there)
    .github/workflows/ci.yml       cargo test + clippy for desktop; the served
                                   ui-app is current (build, git diff --exit-code)
    .github/workflows/release.yml  tag v* → verify tag == tauri.conf.json
                                   version → one draft release → matrix:
                                   ubuntu-22.04 (deb, appimage), macos-14
                                   (aarch64 dmg; x86_64 dmg cross-compiled on
                                   the same runner), windows-latest (msi, nsis)

Windows is IN the matrix. Lattice excludes it because `fuser` is unix-only;
nothing here is.

## Tests

`cargo test` in `desktop/`: SSE frame parsing (an `old` frame is not a change;
a ` /rev` frame is; a frame for another path is not); the inbox diff (a thread
already in the snapshot does not notify; unread → read → unread again does;
the cap and the "+N more"); config round-trip; the ship-URL normaliser. The
bridge keeps lattice's tests.

Headless harness: `AUSPEX_AUTOCONNECT=url,code` drives the real connect flow
without a display, so the app can be checked against `~wex` from a shell.

## Icons

`desktop/icon-src.svg` is the single source — the auspex birds in the shared
palette (amber `#f9a804` on navy `#101541`→`#080b25`, lattice's stroke weight).
`cargo tauri icon desktop/icon-src.svg` generates `desktop/icons/`, which is
committed. The in-app tile icon (`grubbery-overlay/nex/auspex/icon.svg`) is the
same drawing.

## Version

`desktop/tauri.conf.json` and `desktop/Cargo.toml` carry the version; a tag
`vX.Y.Z` that disagrees fails `release.yml` before any build starts.

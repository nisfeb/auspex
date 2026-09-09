# auspex desktop

The auspex mail client (served live from your ship, never bundled here) in a
window, plus one thing a browser tab cannot do: **native OS notifications for
new mail**. That is the whole reason this exists.

## Build

Prereqs: Rust, `cargo install tauri-cli --locked`, and Tauri v2's platform deps
(<https://v2.tauri.app/start/prerequisites/>). On Linux that is the
webkit2gtk-4.1 development package — `libwebkit2gtk-4.1-dev` on Debian/Ubuntu,
`lib64webkit4.1-devel` on OpenMandriva — plus gtk3, librsvg2, libsoup3 and
libayatana-appindicator3. Nothing needs fuse: this app mounts nothing.

    cd desktop
    cargo tauri build        # bundles in target/release/bundle/
    cargo tauri dev          # run from source
    cargo test               # the frame classifier, the diff, the bridge
    cargo clippy --all-targets -- -D warnings

`cargo tauri icon icon-src.svg -o icons` regenerates `icons/` from the one
source drawing. The output is committed; the same drawing is the in-app tile
icon at `grubbery-overlay/nex/auspex/icon.svg`.

## Use

Enter your ship's URL and `+code` once. The app posts them to the ship's own
`/~/login` and keeps the session it gets back under the app config dir
(`~/.config/org.nisfeb.auspex/cookie` on Linux); the `+code` itself is never
stored. The ship's `@p` comes out of the session cookie's own name, so no
extra request is made to learn it.

The connection page reports the live state — connected (and to which ship),
signed out, or unreachable — from a real authenticated request to
`/apps/auspex/api/whoami`, not from whether a URL is configured. It offers the
login form only when logging in is actually what you need. `reconnect` and
`change ship` are there when you want it anyway. `Preferences → connection…`
returns to it from the client; `close` or Escape goes back.

The workspace webview talks to the ship through a **localhost bridge**. Every
request is relayed by the app with the session attached Rust-side, so the
webview itself holds no cookies and webkit cookie policies (which vary by build
and silently drop cookies on cross-site flows and service-worker fetches) can
never unauthenticate a view. That matters more here than it does in lattice:
the auspex client is a PWA and its service worker mediates every fetch.

The bridge listens on a fixed port — **26600**, or the next free one in a
16-wide range. Deliberate and load-bearing, not cosmetic: the port is part of
the webview's origin, and all web storage (the service-worker cache included)
is keyed by origin, so an ephemeral port would give every launch an empty cache
and a cold start. 26600 rather than lattice's 26500 so both apps can run side
by side.

Links to the ship's own origin are re-routed through the bridge (following one
directly would arrive cookieless, and auspex has no unauthenticated surface at
all, so that is a 403 rather than a login page). Only `http`, `https` and
`mailto` links leave for the system browser, and that allowlist is enforced in
Rust rather than in the page — the workspace renders mail, and the links in
mail are written by whoever sent it. Ctrl/Cmd +/- zooms.

## The notifier

One thread, started at launch when a session already exists and after a
successful connect otherwise.

1. It holds open the ship's change beacon —
   `/grubbery/api/keep/apps/auspex.auspex_app/beacon/rev`, the same stream the
   web client reads. The first event is the current value rather than a change
   and is ignored; the stream carries the whole `/beacon` directory, so only
   ` /rev` events count.
2. On each change it re-reads `/apps/auspex/api/inbox?view=inbox&limit=20`.
   Rows that are `unread` and were **not** unread at the last look are new.
3. One notification per new thread: title `~from · subject`, body the snippet.
   A thread holding a forged copy is titled `FORGED · ~from · subject` —
   first, before the sender it contradicts, because a notification is read
   left to right and often not to the end.
4. A snapshot is taken before the stream opens, so launching never replays the
   backlog. Read-marks do not bump the beacon (deliberate on the nexus), so
   reading mail in the app cannot produce a notification, and a thread that
   goes unread again later is news again — which it is.

A dropped stream reconnects with backoff, 1s doubling to 30s, reset on a whole
frame received. The frame classifier and the diff are pure functions with unit
tests; the thread around them is plumbing.

### Ceilings, stated rather than discovered

- **It notifies while the app is open, and not otherwise.** No tray, no
  background mode, no daemon. Minimise-to-tray is the upgrade path if it ever
  matters. Nothing arrives while the app is closed.
- **No click-to-focus on Linux.** `tauri-plugin-notification` does not support
  notification actions there. The notification tells you; opening the app is
  yours to do.
- **Three per change, then "…and N more new".** A ship back after a week
  delivers everything at once, and twelve popups is not a notification.
- **No offline queue, no backups.** Those are lattice features. The web client
  already has its own offline shell and its own honest "not sent".
- **Unsigned bundles.** On macOS, right-click → Open the first time.

## Releases

Push a version tag and CI builds every supported platform:

    # bump "version" in tauri.conf.json AND Cargo.toml first. CI refuses a tag
    # that disagrees with the config, so the bundles can never be stamped with
    # the wrong version
    git tag v0.2.0 && git push origin v0.2.0

`.github/workflows/release.yml` runs the tests, then builds on ubuntu-22.04
(`.deb` + `.AppImage`), macos-14 (`.dmg`, Apple Silicon, and `.dmg` x86_64
cross-compiled on the same runner) and windows-latest (`.msi` + NSIS `.exe`),
and attaches the bundles to a **draft** release for a human to publish.
`workflow_dispatch` builds the same set without a tag.

Ubuntu 22.04 rather than the newest runner, on purpose: a bundle's glibc floor
is whatever it was built against, so building on the newest image silently
drops every older distro.

macOS bundles are unsigned unless the `APPLE_*` signing secrets are set — see
the comment in `release.yml` for why passing them half-set is worse than not
passing them at all.

## Headless

`AUSPEX_AUTOCONNECT=<url>,<+code>` drives the real connect flow with no
display, and `AUSPEX_LOG=1` puts the shell's diagnostics on stderr — the
bridge's port, each relayed request, the beacon opening, every notification
raised. Together they are how this app is checked against a live ship from a
shell:

    AUSPEX_LOG=1 WEBKIT_DISABLE_DMABUF_RENDERER=1 \
      AUSPEX_AUTOCONNECT=http://localhost:8081,my-code-here \
      xvfb-run -a ./target/release/auspex-desktop

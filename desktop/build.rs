fn main() {
    // Opting ANY command into the app manifest gates them ALL. An unlisted
    // command is denied everywhere ("connect not allowed"), which reads at
    // runtime like anything except what it is. So every command is listed
    // here, local windows get all of them via capabilities/local.json, and
    // the ship-served page gets only the two it can justify
    // (capabilities/workspace-remote.json).
    //
    // scripts/desktop-commands.mjs cross-checks this list against the invoke
    // handler and the capabilities. It comes from lattice, where the same
    // omission shipped three separate times.
    tauri_build::try_build(tauri_build::Attributes::new().app_manifest(
        tauri_build::AppManifest::new().commands(&[
            "connect",
            "connection_status",
            "get_config",
            "go_home",
            "open_external_url",
            // the page reports its colour scheme so the GTK menubar and
            // native scrollbars follow it (both pages: manager + ship UI)
            "set_theme",
        ]),
    ))
    .expect("tauri-build failed")
}

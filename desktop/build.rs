fn main() {
    // Opting ANY command into the app manifest gates them ALL. An unlisted
    // command is denied everywhere ("connect not allowed"), which reads at
    // runtime like anything except what it is. So every command is listed
    // here and local windows get all of them via capabilities/local.json.
    // The ship-served page gets none: it never invokes a command, and a
    // grant to it is a grant to whatever the configured ship serves.
    //
    // scripts/desktop-commands.mjs cross-checks this list against the invoke
    // handler and the capabilities. It comes from lattice, where the same
    // omission shipped three separate times.
    tauri_build::try_build(tauri_build::Attributes::new().app_manifest(
        tauri_build::AppManifest::new().commands(&[
            "connect",
            "connection_status",
            "go_home",
            // the manager reports its colour scheme so the GTK menubar and
            // native scrollbars follow it
            "set_theme",
        ]),
    ))
    .expect("tauri-build failed")
}

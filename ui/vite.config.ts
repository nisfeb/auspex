import { createHash } from 'node:crypto'
import { readFileSync, readdirSync, writeFileSync, rmSync } from 'node:fs'
import { resolve } from 'node:path'
import { defineConfig, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

const SHIP = process.env.SHIP_URL || 'http://localhost:8081'  // ~wex

// Where the build lands: straight into the grubbery overlay, as the four
// files the nexus lays down as grubs in +on-load. They are committed
// build output, the same way lattice commits its own ui-app/ — the
// overlay IS the deploy source, so an artifact that is not in it does not
// ship.
const OUT = resolve(import.meta.dirname, '../grubbery-overlay/nex/urmail/ui-app')

// The four files +on-load lays down as grubs, and nothing else. The
// shell and the script have always been two; the manifest and the
// service worker are two more, and each one is a row in +on-load and a
// route arm in +handle-request. A fifth file in this directory is a grub
// the nexus will not serve.
// `.json` and not `.webmanifest`, which is what a web manifest is usually
// called: grubbery turns every non-hoon file in a gub tree into a %mime grub
// through the clay tube for its EXTENSION, and there is no `webmanifest`
// mark on the desk, so a file by that name is a build that crashes rather
// than one that 404s. The extension names the mark; `application/manifest+json`
// is set by the route that serves it, which is the part browsers read.
const SERVED = ['index.html', 'app.js', 'manifest.json', 'sw.js']

// One document plus one script, and no third request.
//
// Every asset fetch costs about two seconds on a serialized pier, and
// each one is a separate request fiber. Lattice ships its shell this way
// for exactly that reason. Vite emits the stylesheet as its own file, so
// fold it into the shell and drop it.
//
// This plugin also copies the service worker across. `ui/sw.js` is plain
// JS and deliberately not bundled: it is not a module of the app, it has
// its own global scope, and running it through Rollup would emit a
// second entry chunk. Copying it is the whole build step — except for
// the version stamp, which is the only thing that can invalidate a shell
// cache whose filenames never change.
const inlineCss = (): Plugin => ({
  name: 'urmail-inline-css',
  apply: 'build',
  closeBundle() {
    const html = resolve(OUT, 'index.html')
    const css = resolve(OUT, 'app.css')
    const doc = readFileSync(html, 'utf8')
    const style = readFileSync(css, 'utf8')

    // The cache key. Taken over EVERY file the worker precaches — the
    // shell, its inlined CSS, the script and the manifest — so it
    // changes exactly when one of them does and not once per build of
    // identical output: a version bumped by the clock would evict every
    // installed client's cache on every deploy, including the deploys
    // that changed nothing.
    //
    // The manifest is in the chain because it is in SHELL_URLS. Left
    // out, an edit to the app's name, colours or icon hashed to the
    // same version, the worker kept serving the precached copy, and the
    // change reached only browsers that had never installed it.
    const build = createHash('sha256')
      .update(doc).update(style)
      .update(readFileSync(resolve(OUT, 'app.js')))
      .update(readFileSync(resolve(OUT, 'manifest.json')))
      .digest('hex').slice(0, 12)
    const sw = readFileSync(resolve(import.meta.dirname, 'sw.js'), 'utf8')
    if (!sw.includes('__URMAIL_BUILD__')) {
      throw new Error('sw.js lost its __URMAIL_BUILD__ stamp: its cache could never be invalidated')
    }
    writeFileSync(resolve(OUT, 'sw.js'), sw.replaceAll('__URMAIL_BUILD__', build))

    // +on-load lays down exactly these four files. Anything else in the
    // output directory is a grub the nexus will not serve, and the app
    // would 404 on it at runtime with nothing but a missing module in
    // the console — so fail the build instead.
    const stray = readdirSync(OUT)
      .filter((f) => ![...SERVED, 'app.css'].includes(f))
    if (stray.length) {
      throw new Error(`build emitted files the nexus does not serve: ${stray.join(', ')}`)
    }
    // And the other direction: a file the nexus routes and the build
    // stopped emitting is a 404 on a route that answers 200 today.
    const missing = SERVED.filter((f) => !readdirSync(OUT).includes(f))
    if (missing.length) {
      throw new Error(`build did not emit files the nexus serves: ${missing.join(', ')}`)
    }
    writeFileSync(
      html,
      doc.replace(
        /<link rel="stylesheet"[^>]*href="[^"]*app\.css"[^>]*>/,
        `<style>${style}</style>`,
      ),
    )
    rmSync(css)
  },
})

export default defineConfig({
  // The app is served from the nexus's own route, so every emitted URL
  // has to be absolute under it.
  base: '/apps/urmail/',
  plugins: [react(), tailwindcss(), inlineCss()],
  build: {
    outDir: OUT,
    emptyOutDir: true,
    // One chunk, checked below. A dynamic import would otherwise emit a
    // second script grub that +on-load knows nothing about, and a 404 for
    // it would be the app failing to start with nothing in the console
    // but a missing module.
    cssCodeSplit: false,
    rollupOptions: {
      output: {
        entryFileNames: 'app.js',
        assetFileNames: 'app[extname]',
      },
    },
  },
  server: {
    // `npm run dev` talks to a real ship: the nexus's own route for the
    // API and grubbery's keep endpoint for the change beacon. Both need
    // the session cookie, so log into the ship in the same browser first.
    proxy: {
      '/apps/urmail/api': { target: SHIP, changeOrigin: true },
      '/grubbery': { target: SHIP, changeOrigin: true },
    },
  },
})

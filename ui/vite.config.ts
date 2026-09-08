import { readFileSync, readdirSync, writeFileSync, rmSync } from 'node:fs'
import { resolve } from 'node:path'
import { defineConfig, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

const SHIP = process.env.SHIP_URL || 'http://localhost:8081'  // ~wex

// Where the build lands: straight into the grubbery overlay, as the two
// files the nexus lays down as grubs in +on-load. They are committed
// build output, the same way lattice commits its own ui-app/ — the
// overlay IS the deploy source, so an artifact that is not in it does not
// ship.
const OUT = resolve(import.meta.dirname, '../grubbery-overlay/nex/urmail/ui-app')

// One document plus one script, and no third request.
//
// Every asset fetch costs about two seconds on a serialized pier, and
// each one is a separate request fiber. Lattice ships its shell this way
// for exactly that reason. Vite emits the stylesheet as its own file, so
// fold it into the shell and drop it.
const inlineCss = (): Plugin => ({
  name: 'urmail-inline-css',
  apply: 'build',
  closeBundle() {
    const html = resolve(OUT, 'index.html')
    const css = resolve(OUT, 'app.css')
    const doc = readFileSync(html, 'utf8')
    const style = readFileSync(css, 'utf8')
    // +on-load lays down exactly index.html and app.js. Anything else in
    // the output directory is a grub the nexus will not serve, and the
    // app would 404 on it at runtime with nothing but a missing module
    // in the console — so fail the build instead.
    const stray = readdirSync(OUT)
      .filter((f) => !['index.html', 'app.js', 'app.css'].includes(f))
    if (stray.length) {
      throw new Error(`build emitted files the nexus does not serve: ${stray.join(', ')}`)
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

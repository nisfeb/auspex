//  The build. It is a zip, and there is nothing else in it.
//
//  No bundler, no transpiler, no dependencies: the extension is ES modules
//  loaded directly by Thunderbird, and the pure libs are the same files
//  `node --test` runs. A build step that rewrote them would put a
//  translation between what is tested and what ships.
//
//    npm run build              → dist/auspex-thunderbird-<version>.zip
//    npm run build -- --selftest → the same, plus selftest.json and the two
//                                  extra permissions it needs. NEVER ship
//                                  this one: it carries an access code.

import { patternFor } from './lib/api.js'
import { mkdirSync, rmSync, cpSync, writeFileSync, readFileSync, existsSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = dirname(fileURLToPath(import.meta.url))
const pkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'))
const args = process.argv.slice(2)
const selftest = args.includes('--selftest')

//  Everything the extension is. Listed rather than globbed, so a stray file
//  in the working tree cannot end up inside a zip someone installs.
const FILES = [
  'manifest.json',
  'background.js',
  'options.html', 'options.js',
  'popup.html', 'popup.js',
  'lib/api.js', 'lib/address.js', 'lib/rfc822.js', 'lib/sync.js',
  'icons/auspex-16.png', 'icons/auspex-32.png', 'icons/auspex-48.png',
  'icons/auspex-64.png', 'icons/auspex-128.png',
]

const stage = join(root, 'dist', selftest ? 'stage-selftest' : 'stage')
const out = join(root, 'dist',
  `auspex-thunderbird-${pkg.version}${selftest ? '-selftest' : ''}.zip`)

rmSync(stage, { recursive: true, force: true })
mkdirSync(join(stage, 'lib'), { recursive: true })
mkdirSync(join(stage, 'icons'), { recursive: true })
for (const f of FILES) cpSync(join(root, f), join(stage, f))

if (selftest) {
  const cfgPath = args[args.indexOf('--selftest') + 1]
  if (!cfgPath || !existsSync(cfgPath)) {
    throw new Error('--selftest needs the path to a selftest config JSON')
  }
  const cfg = JSON.parse(readFileSync(cfgPath, 'utf8'))
  cpSync(join(root, 'selftest.js'), join(stage, 'selftest.js'))
  writeFileSync(join(stage, 'selftest.json'), JSON.stringify(cfg, null, 2))
  const m = JSON.parse(readFileSync(join(stage, 'manifest.json'), 'utf8'))
  //  granted outright rather than requested: permissions.request needs a
  //  user gesture, and the whole point of this build is that there is no
  //  user. `cookies` is for the signed-out case, which has to be able to
  //  take the session away.
  m.permissions.push('cookies', ...new Set([patternFor(cfg.origin), patternFor(cfg.sink)]))
  //  A distinct version per selftest build. Thunderbird treats an xpi with
  //  the id and version it already knows as the same add-on, keeps the
  //  permissions it recorded for it, and never re-reads the manifest — so a
  //  rebuilt selftest with a changed origin silently ran on the old grant.
  m.version = `${m.version}.${Math.floor(Date.now() / 60000) % 1000000}`
  writeFileSync(join(stage, 'manifest.json'), JSON.stringify(m, null, 2))
}

rmSync(out, { force: true })
//  -X: no extra attributes, so the same tree builds the same zip.
execFileSync('zip', ['-qrX', out, '.'], { cwd: stage })
console.log(out)

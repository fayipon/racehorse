import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { gunzipSync, gzipSync } from 'node:zlib'

const required = ['index.html', 'index.js', 'index.wasm', 'index.pck']
const missing = required.filter(file => !existsSync(fileURLToPath(new URL(`../public/game/${file}`, import.meta.url))))
if (missing.length) {
  console.error(`Godot Web export is missing: ${missing.join(', ')}. Install matching Godot export templates, then run npm run godot:export.`)
  process.exit(1)
}

// Deploys fetch the engine from jsDelivr as a gzip copy (see scripts/mirror.ts),
// so the committed copy must match the export.
const wasm = readFileSync(new URL('../public/game/index.wasm', import.meta.url))
const copy = new URL('../mirror/index.wasm.gz', import.meta.url)
if (!existsSync(copy) || !gunzipSync(readFileSync(copy)).equals(wasm)) {
  if (process.env.CI) {
    console.error('mirror/index.wasm.gz does not match public/game/index.wasm. Run npm run build locally and commit the refreshed copy.')
    process.exit(1)
  }
  mkdirSync(new URL('../mirror/', import.meta.url), { recursive: true })
  writeFileSync(copy, gzipSync(wasm, { level: 9 }))
  console.log('Refreshed mirror/index.wasm.gz from the Godot export. Commit it with the export.')
}

import { existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const required = ['index.html', 'index.js', 'index.wasm', 'index.pck']
const missing = required.filter(file => !existsSync(fileURLToPath(new URL(`../public/game/${file}`, import.meta.url))))
if (missing.length) {
  console.error(`Godot Web export is missing: ${missing.join(', ')}. Install matching Godot export templates, then run npm run godot:export.`)
  process.exit(1)
}

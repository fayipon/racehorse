import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import react from '@vitejs/plugin-react'
import { defineConfig, type Plugin } from 'vite'
import { mirrorCommits } from './scripts/mirror.ts'
import { HTML_LANG, LOCALES } from './src/locale.ts'

// Deploy builds set ASSET_MIRROR to the GitHub repo so heavy files come from jsDelivr.
const repo = process.env.ASSET_MIRROR ?? ''
// The lobby and one page per cup, so each cup page loads only its own race.
const PAGES = ['index.html', 'sunny/index.html', 'thunder/index.html', 'royal/index.html']
const CUP_IDS = PAGES.map(page => page.split('/')[0]).filter(part => part !== 'index.html')

// Every page is also served under each language, as /en/ and /en/sunny/, so an
// address names its language. A static host needs a file for each: the build
// writes each page again in every language's folder, and a 404 page sends a
// mistyped address, such as /EN/sunny, to the page it meant.
function localizedPages(): Plugin {
  let base = '/'
  const prefix = () => new RegExp(`^${base}(${LOCALES.join('|')})(?=[/?#]|$)(.*)$`, 'i')
  return {
    name: 'localized-pages',
    configResolved(config) { base = config.base },
    configureServer(server) {
      server.middlewares.use((req, _res, next) => {
        const match = req.url ? prefix().exec(req.url) : null
        if (match) req.url = base + match[2].replace(/^\//, '')
        next()
      })
    },
    writeBundle({ dir = 'dist' }) {
      for (const page of PAGES) {
        const html = readFileSync(join(dir, page), 'utf8')
        for (const locale of LOCALES) {
          const target = join(dir, locale, page)
          mkdirSync(dirname(target), { recursive: true })
          writeFileSync(target, html.replace(/<html lang="[^"]*"/, `<html lang="${HTML_LANG[locale]}"`))
        }
      }
      writeFileSync(join(dir, '404.html'), `<!doctype html>
<html><head><meta charset="UTF-8" /><title>Pony Racing Club</title><script>
const base = ${JSON.stringify(base)}, locales = ${JSON.stringify(LOCALES)}, cups = ${JSON.stringify(CUP_IDS)}
const parts = location.pathname.slice(base.length).split('/').filter(Boolean).map(part => part.toLowerCase())
const locale = locales.find(code => code.toLowerCase() === parts[0])
const cup = cups.find(id => id === parts[locale ? 1 : 0])
location.replace(base + (locale ? locale + '/' : '') + (cup ? cup + '/' : '') + location.search + location.hash)
</script></head><body></body></html>
`)
    },
  }
}

export default defineConfig({
  plugins: [react(), localizedPages()],
  build: { rollupOptions: { input: PAGES } },
  define: { __MIRROR__: JSON.stringify({ repo, commits: repo ? mirrorCommits() : {} }) },
  server: { host: 'localhost', port: 5175, strictPort: true },
  preview: { host: 'localhost', port: 5175, strictPort: true },
})

import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'
import { mirrorCommits } from './scripts/mirror.ts'

// Deploy builds set ASSET_MIRROR to the GitHub repo so heavy files come from jsDelivr.
const repo = process.env.ASSET_MIRROR ?? ''
export default defineConfig({
  plugins: [react()],
  // The lobby and one page per cup, so each cup page loads only its own race.
  build: { rollupOptions: { input: ['index.html', 'sunny/index.html', 'thunder/index.html', 'royal/index.html'] } },
  define: { __MIRROR__: JSON.stringify({ repo, commits: repo ? mirrorCommits() : {} }) },
  server: { host: 'localhost', port: 5175, strictPort: true },
  preview: { host: 'localhost', port: 5175, strictPort: true },
})

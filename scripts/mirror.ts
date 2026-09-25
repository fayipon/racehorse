import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

// GitHub Pages crawls on some networks (about 50 KB/s from Taiwan, against 10 MB/s
// from jsDelivr), so deploy builds fetch the heavy files from jsDelivr's copy of the
// repo. Each file is pinned to the commit that last changed it: its URL only moves
// when the file does, and jsDelivr lets browsers keep commit-pinned files for a year.
// jsDelivr refuses files over 20 MB, so the engine goes as a gzip copy.
export const MIRRORED = [
  'mirror/index.wasm.gz',
  'public/game/index.pck',
  'public/audio/commentary/voice.mp3',
  'public/audio/commentary/voice-extra.mp3',
  'public/audio/crowd/ambient.ogg',
  'public/audio/crowd/cheer.ogg',
  'public/audio/crowd/roar.ogg',
]

// Needs the full history; a shallow clone pins everything to the latest commit.
export function mirrorCommits() {
  const commits: Record<string, string> = {}
  for (const file of MIRRORED) {
    const commit = execFileSync('git', ['log', '-1', '--format=%H', '--', file], { encoding: 'utf8' }).trim()
    if (commit) commits[file] = commit
  }
  return commits
}

export const mirrorUrl = (repo: string, commit: string, file: string) => `https://cdn.jsdelivr.net/gh/${repo}@${commit}/${file}`

// `node scripts/mirror.ts owner/repo` fetches each file once before a deploy goes
// live, so no visitor waits while jsDelivr pulls it from GitHub.
async function warm(repo: string) {
  for (const [file, commit] of Object.entries(mirrorCommits())) {
    const response = await fetch(mirrorUrl(repo, commit, file))
    const bytes = (await response.arrayBuffer()).byteLength
    console.log(`${response.status} ${bytes} B ${file}@${commit.slice(0, 7)}`)
    if (!response.ok) process.exitCode = 1
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) void warm(process.argv[2])

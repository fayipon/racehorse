// Deploy builds record which commit last changed each heavy file, so it can come
// from jsDelivr's copy of the repo instead of GitHub Pages (see scripts/mirror.ts).
declare const __MIRROR__: { repo: string; commits: Record<string, string> }

const { repo, commits } = __MIRROR__
// A mirror that has not answered by then is treated as unreachable.
const ANSWER_MS = 10_000

// Fetches a file under public/, from the mirror when it has one. Mirror URLs are
// pinned to a commit, so they drop the cache-busting query the site's copy needs.
export async function fetchAsset(path: string) {
  const file = `public/${path.split('?')[0]}`
  if (repo && commits[file]) {
    const abort = new AbortController()
    const timer = setTimeout(() => abort.abort(), ANSWER_MS)
    try {
      const response = await fetch(`https://cdn.jsdelivr.net/gh/${repo}@${commits[file]}/${file}`, { signal: abort.signal })
      if (response.ok) return response
    } catch {
      // The site's own copy below.
    } finally {
      clearTimeout(timer)
    }
  }
  return fetch(`${import.meta.env.BASE_URL}${path}`)
}

// The game page loads the engine and game pack itself, so it gets their commits
// and builds the mirror URLs from its own site's repo.
const engine = commits['mirror/index.wasm.gz'], pack = commits['public/game/index.pck']
export const gameSource = `${import.meta.env.BASE_URL}game/index.html${repo && engine && pack ? `?${new URLSearchParams({ wasm: engine, pck: pack })}` : ''}`

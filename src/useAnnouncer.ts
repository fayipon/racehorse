import { useEffect, useRef } from 'react'
import { BET_MS, HORSES, phaseAt, raceOrder, racePositions, type Game } from './game'
import { racePresentationTime } from './presentation'
import clips from './announcer-clips.json'

type Cue = 'start' | 'pack' | 'overtake' | 'sprint' | 'finish'
// Complete sentences are pre-generated; no browser speech synthesis at runtime.
let context: AudioContext | null = null
let source: AudioBufferSourceNode | null = null
let active = false
let generation = 0
const cache = new Map<string, Promise<AudioBuffer>>()
const lastChoice = new Map<Cue | 'intro', number>()
let endedAt = 0

function buffer(file: string) {
  let promise = cache.get(file)
  if (!promise) {
    const audio = context!
    promise = fetch(`${import.meta.env.BASE_URL}audio/announcer/${file}`)
      .then(response => { if (!response.ok) throw new Error('Voice clip unavailable'); return response.arrayBuffer() })
      .then(bytes => audio.decodeAudioData(bytes))
    cache.set(file, promise)
    void promise.catch(() => cache.delete(file))
  }
  return promise
}
export function stopAnnouncer() {
  generation++
  if (source) { source.onended = null; source.stop(); source.disconnect(); source = null }
  active = false
}
function speak(cue: Cue | 'intro', horse = 0) {
  if (!context || context.state !== 'running') return
  const matching = clips.filter(clip => clip.cue === cue && (clip.horse === 0 || clip.horse === horse))
  const fresh = matching.filter(clip => clip.variant !== lastChoice.get(cue))
  const choices = fresh.length ? fresh : matching
  const clip = choices[Math.floor(Math.random() * choices.length)]
  if (!clip) return
  lastChoice.set(cue, clip.variant)
  stopAnnouncer()
  active = true
  const token = generation
  const deadline = window.setTimeout(() => { if (token === generation) stopAnnouncer() }, 6000)
  void buffer(clip.file).then(decoded => {
    window.clearTimeout(deadline)
    if (token !== generation || !context || document.hidden) return
    const node = context.createBufferSource()
    node.buffer = decoded
    node.connect(context.destination)
    source = node
    node.onended = () => {
      if (token !== generation) return
      node.disconnect(); source = null; active = false; endedAt = performance.now()
    }
    node.start()
  }).catch(() => { window.clearTimeout(deadline); if (token === generation) { active = false; endedAt = performance.now() + 1000 } })
}

// The existing sound button unlocks one AudioContext for effects and the host.
export function enableAnnouncer(audio: AudioContext) {
  context = audio
  void audio.resume().then(() => speak('intro'))
  // Warm the short clips in bounded batches to avoid pauses between sentences.
  let next = 0
  const warm = async () => {
    while (next < clips.length) {
      const clip = clips[next++]
      try { await buffer(clip.file) } catch { /* Playback retries an unavailable clip. */ }
    }
  }
  for (let i = 0; i < 3; i++) void warm()
}

export function useAnnouncer(game: Game, now: number, enabled: boolean) {
  const state = useRef({ round: 0, lastAt: -100, leader: 0, pendingLeader: 0, started: false, sprint: false, finished: false })
  useEffect(() => {
    const stop = () => { if (document.hidden) stopAnnouncer() }
    document.addEventListener('visibilitychange', stop)
    return () => { document.removeEventListener('visibilitychange', stop); stopAnnouncer() }
  }, [])
  useEffect(() => {
    const seconds = (now - game.startedAt - BET_MS) / 1000
    if (state.current.round !== game.round) {
      stopAnnouncer()
      state.current = { round: game.round, lastAt: -100, leader: 0, pendingLeader: 0, started: false, sprint: false, finished: false }
    }
    const current = state.current
    const phase = phaseAt(game, now)
    if (!enabled || document.hidden) { stopAnnouncer(); return }
    if (phase !== 'racing') {
      // Let the finish call complete into settlement, then stop naturally.
      return
    }
    const visual = racePresentationTime(seconds)
    const order = raceOrder(game.seed, game.round)
    const positions = racePositions(game.seed, game.round, visual)
    const ranking = [...HORSES].sort((a, b) => positions[b.id - 1] - positions[a.id - 1] || order.indexOf(a.id) - order.indexOf(b.id))
    const leader = ranking[0].id
    if (current.leader && current.leader !== leader) current.pendingLeader = leader
    current.leader = leader
    let cue: Cue | undefined
    if (visual >= 44.5) {
      if (!current.finished && visual < 47) cue = 'finish'
      current.finished = true
    } else if (seconds < 3 && !current.started) {
      cue = 'start'
    } else if (seconds >= 38 && !current.sprint) {
      cue = 'sprint'
      current.sprint = true
    } else if (seconds >= 2 && !current.finished && !active && performance.now() - endedAt >= 120) {
      cue = seconds >= 38 ? 'sprint' : current.pendingLeader === leader ? 'overtake' : 'pack'
    }
    current.started = true
    if (!cue) return
    current.pendingLeader = 0
    current.lastAt = seconds
    speak(cue, cue === 'finish' ? order[0] : leader)
  }, [game, now, enabled])
}

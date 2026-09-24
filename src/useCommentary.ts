import { useEffect, useRef } from 'react'
import { commentaryCues, commentaryFile, planCommentary, type Cue } from './commentary'
import { BET_MS, type Game, type Result } from './game'
import { fetchAsset } from './mirror'

const LOOKAHEAD = 1.2
// The call runs from the paddock chat a minute before the gates to a few
// seconds into the results.
const CALL_FROM = -60
const CALL_UNTIL = 56

// Plays the planned race call against the race clock. Phrases are scheduled
// ahead on the audio clock, so they land exactly on the moments they describe.
export class CommentaryPlayer {
  private audio: AudioContext
  private output: GainNode
  private sprite: AudioBuffer | null = null
  private loading: Promise<void> | null = null
  private key = ''
  private cues: (Cue & { opens: boolean })[] = []
  private next = 0
  private playing = new Set<AudioBufferSourceNode>()
  onSpeak: (start: number, end: number) => void = () => {}

  constructor(audio: AudioContext) {
    this.audio = audio
    const limiter = audio.createDynamicsCompressor()
    limiter.threshold.value = -4
    limiter.ratio.value = 12
    limiter.attack.value = .003
    limiter.release.value = .12
    limiter.connect(audio.destination)
    this.output = audio.createGain()
    this.output.gain.value = .9
    this.output.connect(limiter)
  }

  load() {
    this.loading ??= fetchAsset(commentaryFile)
      .then(response => { if (!response.ok) throw new Error(`Commentary unavailable: ${response.status}`); return response.arrayBuffer() })
      .then(bytes => this.audio.decodeAudioData(bytes))
      .then(buffer => { this.sprite = buffer })
      .catch(() => { this.loading = null })
  }

  // `seconds` is real time since the gates opened.
  update(seed: number, round: number, history: Result[], seconds: number) {
    const key = `${seed}:${round}`
    if (key !== this.key) {
      this.stop()
      this.key = key
      this.cues = planCommentary(seed, round, history).flatMap(u => commentaryCues([u]).map((cue, i) => ({ ...cue, opens: i === 0 })))
    }
    if (!this.sprite || this.audio.state !== 'running') return
    // Joining late starts at the next full sentence, never mid-phrase.
    while (this.next < this.cues.length && (this.cues[this.next].at < seconds - .05 || (!this.cues[this.next].opens && !this.playing.size))) this.next++
    while (this.next < this.cues.length && this.cues[this.next].at < seconds + LOOKAHEAD) {
      const cue = this.cues[this.next++]
      const source = this.audio.createBufferSource()
      source.buffer = this.sprite
      source.connect(this.output)
      const start = this.audio.currentTime + Math.max(0, cue.at - seconds)
      source.start(start, cue.offset, cue.duration)
      this.onSpeak(start, start + cue.duration)
      source.onended = () => { this.playing.delete(source); source.disconnect() }
      this.playing.add(source)
    }
  }

  stop() {
    for (const source of this.playing) { source.onended = null; try { source.stop() } catch { /* Already ended. */ } source.disconnect() }
    this.playing.clear()
    this.next = 0
  }
}

export function useCommentary(game: Game, enabled: boolean, duck: (start: number, end: number) => void) {
  const player = useRef<CommentaryPlayer | null>(null)
  const latest = useRef({ game, duck })
  useEffect(() => { latest.current = { game, duck } })
  useEffect(() => {
    if (!enabled) { player.current?.stop(); return }
    const timer = window.setInterval(() => {
      const current = player.current
      if (!current) return
      const { game: g, duck: dip } = latest.current
      current.onSpeak = dip
      const seconds = (Date.now() - g.startedAt - BET_MS) / 1000
      if (document.hidden || seconds < CALL_FROM || seconds > CALL_UNTIL) { current.stop(); return }
      current.update(g.seed, g.round, g.history, seconds)
    }, 150)
    return () => { window.clearInterval(timer); player.current?.stop() }
  }, [enabled])
  return {
    enable: (audio: AudioContext) => {
      player.current ??= new CommentaryPlayer(audio)
      player.current.load()
    },
  }
}

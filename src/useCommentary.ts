import { useEffect, useRef } from 'react'
import { commentaryCues, loadVoice, planCommentary, type Cue, type Voice } from './commentary'
import { BET_MS, fieldOf, recentResults, type Game, type Result } from './game'
import { fetchAsset } from './mirror'
import type { Locale } from './i18n'
import { scriptOf } from './raceScript'
import { serverNow } from './schedule'

const LOOKAHEAD = 1.2
// The call runs from the paddock chat a minute before the gates to a few
// seconds into the results (English, the slowest voice, finishes by about 56.5 s).
const CALL_FROM = -60
const CALL_UNTIL = 58

// Plays the planned race call against the race clock. Phrases are scheduled
// ahead on the audio clock, so they land exactly on the moments they describe.
export class CommentaryPlayer {
  private audio: AudioContext
  private output: GainNode
  private voice: Voice | null = null
  private sprites: (AudioBuffer | null)[] = [null, null]
  private loading: (Promise<void> | null)[] = [null, null]
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

  // The main file holds Sunny Cup's eight runners; bigger fields also load the lines naming 9–12.
  load(voice: Voice, field: number) {
    if (voice !== this.voice) {
      this.stop()
      this.voice = voice
      this.sprites = [null, null]
      this.loading = [null, null]
      this.key = ''
    }
    for (const index of field > 8 ? [0, 1] : [0]) {
      this.loading[index] ??= fetchAsset(voice.files[index])
        .then(response => { if (!response.ok) throw new Error(`Commentary unavailable: ${response.status}`); return response.arrayBuffer() })
        .then(bytes => this.audio.decodeAudioData(bytes))
        .then(buffer => { if (this.voice === voice) this.sprites[index] = buffer })
        .catch(() => { if (this.voice === voice) this.loading[index] = null })
    }
  }

  // `seconds` is real time since the gates opened.
  update(seed: number, round: number, field: number, history: Result[], seconds: number) {
    const voice = this.voice
    if (!voice) return
    const key = `${seed}:${round}:${field}:${scriptOf(seed, round, field)?.rev ?? ''}`
    if (key !== this.key) {
      this.stop()
      this.key = key
      this.cues = planCommentary(voice, seed, round, field, history).flatMap(u => commentaryCues([u], voice).map((cue, i) => ({ ...cue, opens: i === 0 })))
    }
    if (!this.sprites[0] || this.audio.state !== 'running') return
    // Joining late starts at the next full sentence, never mid-phrase.
    while (this.next < this.cues.length && (this.cues[this.next].at < seconds - .05 || (!this.cues[this.next].opens && !this.playing.size))) this.next++
    while (this.next < this.cues.length && this.cues[this.next].at < seconds + LOOKAHEAD) {
      const cue = this.cues[this.next++]
      const buffer = this.sprites[cue.sprite]
      if (!buffer) continue
      const source = this.audio.createBufferSource()
      source.buffer = buffer
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

// The race caller speaks the page's language; its recording loads with the first unmute.
export function useCommentary(game: Game, enabled: boolean, duck: (start: number, end: number) => void, locale: Locale) {
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
      const seconds = (serverNow() - g.startedAt - BET_MS) / 1000
      if (document.hidden || seconds < CALL_FROM || seconds > CALL_UNTIL) { current.stop(); return }
      // The form everyone hears comes from the shared results, not this player's.
      current.update(g.seed, g.round, fieldOf(g), recentResults(g.seed, g.round, fieldOf(g), 6), seconds)
    }, 150)
    return () => { window.clearInterval(timer); player.current?.stop() }
  }, [enabled])
  return {
    enable: (audio: AudioContext) => {
      const current = player.current ??= new CommentaryPlayer(audio)
      void loadVoice(locale).then(voice => current.load(voice, fieldOf(latest.current.game)))
    },
  }
}

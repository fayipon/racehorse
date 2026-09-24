import { BET_MS, phaseAt, racePositions, type Game } from './game'
import { COURSE } from './course'
import { racePresentationTime } from './presentation'

export type CrowdMix = readonly [number, number, number]
export const SILENT_CROWD: CrowdMix = [0, 0, 0]
export const CROWD_FILES = ['ambient.ogg', 'cheer.ogg', 'roar.ogg'] as const
const ROUND_END_FADE_SECONDS = 5
const finalBendProgress = Array.from({ length: COURSE.laneCount }, (_, lane) => {
  const radius = COURSE.laneStart + lane * COURSE.laneSpacing
  return (3 * COURSE.halfStraight + Math.PI * radius) / (4 * COURSE.halfStraight + 2 * Math.PI * radius)
})

export function crowdMixAt(game: Game, now: number): CrowdMix {
  const phase = phaseAt(game, now)
  if (phase === 'betting') return SILENT_CROWD
  const visualSeconds = racePresentationTime((now - game.startedAt - BET_MS) / 1000)
  // One continuous swell starts before the final bend and crests midway
  // through it. There is no separate gain switch on entry or at the finish.
  const positions = racePositions(game.seed, game.round, visualSeconds)
  const approach = Math.min(1, Math.max(0, ...positions.map((progress, lane) =>
    (progress - finalBendProgress[lane] + 0.12) / 0.26)))
  // Smootherstep keeps both the gain and its slope continuous at each end.
  const swell = approach ** 3 * (approach * (approach * 6 - 15) + 10)
  return [0.24 - swell * 0.06, 0.2 + swell * 0.5, swell * 0.95]
}

type Layer = { source: AudioBufferSourceNode; gain: GainNode }

export class CrowdAudioPlayer {
  private audio: AudioContext
  private limiter: DynamicsCompressorNode
  private buffers: AudioBuffer[] = []
  private layers: Layer[] = []
  private fading = new Set<Layer>()
  private loading: Promise<void> | null = null
  private wanted: CrowdMix = SILENT_CROWD
  private disposed = false
  private retryAt = 0

  constructor(audio: AudioContext) {
    this.audio = audio
    this.limiter = audio.createDynamicsCompressor()
    this.limiter.threshold.value = -3
    this.limiter.knee.value = 0
    this.limiter.ratio.value = 20
    this.limiter.attack.value = 0.003
    this.limiter.release.value = 0.15
    this.limiter.connect(audio.destination)
  }

  unlock() {
    void this.audio.resume().then(() => this.apply()).catch(() => {})
    this.prepare()
  }

  setMix(mix: CrowdMix) {
    if (this.disposed) return
    this.wanted = mix
    if (!mix.some(value => value > 0)) {
      // Let the celebration trail into the next round instead of cutting it off.
      // Repeated silent updates leave this fade running to its original end.
      if (this.layers.length) this.stop(ROUND_END_FADE_SECONDS)
      return
    }
    this.prepare()
    this.apply()
  }

  private prepare() {
    if (this.disposed || this.buffers.length || this.loading || Date.now() < this.retryAt) return
    this.loading = Promise.all(CROWD_FILES.map(async file => {
      const response = await fetch(`${import.meta.env.BASE_URL}audio/crowd/${file}?v=2`)
      if (!response.ok) throw new Error(`Crowd audio unavailable: ${response.status}`)
      return this.audio.decodeAudioData(await response.arrayBuffer())
    })).then(buffers => {
      if (this.disposed) return
      this.buffers = buffers
      this.apply()
    }).catch(() => { this.retryAt = Date.now() + 10_000 })
      .finally(() => { this.loading = null })
  }

  private apply() {
    if (this.disposed || this.audio.state !== 'running' || !this.buffers.length || !this.wanted.some(value => value > 0)) return
    if (!this.layers.length) {
      const start = this.audio.currentTime
      this.layers = this.buffers.map(buffer => {
        const source = this.audio.createBufferSource(), gain = this.audio.createGain()
        source.buffer = buffer
        source.loop = true
        gain.gain.value = 0
        source.connect(gain)
        gain.connect(this.limiter)
        const layer = { source, gain }
        source.onended = () => { source.disconnect(); gain.disconnect(); this.fading.delete(layer) }
        source.start(start)
        return layer
      })
    }
    this.layers.forEach(({ gain }, index) => {
      // Retarget smoothly even when unmuting or returning late in the race.
      gain.gain.cancelAndHoldAtTime(this.audio.currentTime)
      gain.gain.setTargetAtTime(this.wanted[index], this.audio.currentTime, 0.65)
    })
  }

  stop(fade = 0) {
    this.wanted = SILENT_CROWD
    const stopping = fade ? this.layers : [...this.layers, ...this.fading]
    for (const layer of stopping) {
      const { source, gain } = layer
      const now = this.audio.currentTime
      gain.gain.cancelAndHoldAtTime(now)
      gain.gain.linearRampToValueAtTime(0, now + fade)
      source.stop(now + fade)
      this.fading.add(layer)
    }
    this.layers = []
  }

  dispose() {
    this.disposed = true
    this.stop()
    this.limiter.disconnect()
    if (this.audio.state !== 'closed') void this.audio.close().catch(() => {})
  }
}

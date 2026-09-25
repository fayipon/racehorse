import { afterEach, describe, expect, it, vi } from 'vitest'
import { advance, BET_MS, createGame, racePositions, RACE_MS, ROUND_MS } from './game'
import { CrowdAudioPlayer, crowdMixAt } from './crowdAudio'
import { racePresentationTime } from './presentation'
import { COURSE, coursePoint } from './course'

afterEach(() => { vi.unstubAllGlobals() })

describe('crowd follows the visible race', () => {
  const game = createGame(1000, 'sunny', 123)
  const at = (seconds: number) => game.startedAt + BET_MS + seconds * 1000

  it('swells into the final bend and reaches the sustained climax while turning', () => {
    const early = crowdMixAt(game, at(15))
    const sprint = crowdMixAt(game, at(40))
    expect(sprint[1]).toBeGreaterThan(early[1])
    let bendEntry: number | undefined
    for (let seconds = 0; seconds < 50; seconds += 0.025) {
      const positions = racePositions(game.seed, game.round, racePresentationTime(seconds), 8)
      if (positions.some((progress, lane) => coursePoint(progress,lane,8).x < -COURSE.halfStraight)) {
        bendEntry = seconds
        break
      }
    }
    expect(bendEntry).toBeDefined()
    const before = crowdMixAt(game, at(bendEntry! - 3))[2]
    const entering = crowdMixAt(game, at(bendEntry!))[2]
    const turning = crowdMixAt(game, at(bendEntry! + 3))[2]
    expect(before).toBeGreaterThan(0)
    expect(entering).toBeGreaterThan(before)
    expect(entering).toBeLessThan(turning)
    expect(turning).toBeGreaterThan(0.7)
    expect(crowdMixAt(game, at(35))).toEqual(crowdMixAt(game, at(47)))
  })

  it('has no sudden gain step at bend entry, the finishing straight, or settlement', () => {
    for (const seed of [1, 123, 9999]) {
      const race = { ...game, seed }
      let previous = crowdMixAt(race, at(0))
      // Match the real 250ms render updates across the complete racing/result interval.
      for (let seconds = 0.25; seconds < 60; seconds += 0.25) {
        const current = crowdMixAt(race, at(seconds))
        current.forEach((level, layer) => {
          expect(Math.abs(level - previous[layer])).toBeLessThan(0.05)
          if (layer > 0) expect(level).toBeGreaterThanOrEqual(previous[layer])
        })
        previous = current
      }
    }
  })

  it('sustains the finish climax throughout settlement, then goes quiet next round', () => {
    const finish = crowdMixAt(game, at(47))
    for (const offset of [0, 4000, 9999]) {
      const now = game.startedAt + BET_MS + RACE_MS + offset
      expect(crowdMixAt(advance(game, now), now)).toEqual(finish)
    }
    const next = game.startedAt + ROUND_MS
    expect(crowdMixAt(advance(game, next), next)).toEqual([0, 0, 0])
    expect(crowdMixAt(game, game.startedAt + 50000)).toEqual([0, 0, 0])
  })
})

function fakeAudio() {
  const sources: { start: ReturnType<typeof vi.fn>; stop: ReturnType<typeof vi.fn> }[] = []
  const audio = {
    state: 'running', currentTime: 10, destination: {},
    resume: vi.fn(async () => {}), close: vi.fn(async () => {}),
    createDynamicsCompressor: vi.fn(() => ({
      threshold: { value: 0 }, knee: { value: 0 }, ratio: { value: 0 },
      attack: { value: 0 }, release: { value: 0 }, connect: vi.fn(), disconnect: vi.fn(),
    })),
    decodeAudioData: vi.fn(async () => ({})),
    createGain: vi.fn(() => ({
      connect: vi.fn(), disconnect: vi.fn(),
      gain: { value: 0, setTargetAtTime: vi.fn(), cancelAndHoldAtTime: vi.fn(), linearRampToValueAtTime: vi.fn() },
    })),
    createBufferSource: vi.fn(() => {
      const source = { start: vi.fn(), stop: vi.fn(), connect: vi.fn(), disconnect: vi.fn() }
      sources.push(source)
      return source
    }),
  }
  return { audio: audio as unknown as AudioContext, sources }
}

describe('crowd playback lifecycle', () => {
  it('does not start late audio after muting during a download', async () => {
    let finish!: (value: unknown) => void
    const response = new Promise(resolve => { finish = resolve })
    vi.stubGlobal('fetch', vi.fn(() => response))
    const { audio, sources } = fakeAudio()
    const player = new CrowdAudioPlayer(audio)
    player.setMix([0.1, 0.3, 0.95])
    player.stop()
    finish({ ok: true, arrayBuffer: async () => new ArrayBuffer(4) })
    await vi.waitFor(() => expect(audio.decodeAudioData).toHaveBeenCalledTimes(3))
    expect(sources).toHaveLength(0)
    player.setMix([0.1, 0.3, 0.95])
    expect(sources).toHaveLength(3)
    player.dispose()
  })

  it('keeps the settlement loops for a five-second fade, which manual mute can interrupt', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => ({ ok: true, arrayBuffer: async () => new ArrayBuffer(4) })))
    const { audio, sources } = fakeAudio()
    const player = new CrowdAudioPlayer(audio)
    player.setMix([0.24, 0.12, 0])
    await vi.waitFor(() => expect(sources).toHaveLength(3))
    player.setMix([0.1, 0.3, 0.95])
    player.setMix([0.1, 0.3, 0.95])
    expect(sources).toHaveLength(3)
    player.setMix([0, 0, 0])
    player.setMix([0, 0, 0])
    player.setMix([0, 0, 0])
    sources.forEach(source => {
      expect(source.stop).toHaveBeenCalledOnce()
      expect(source.stop).toHaveBeenLastCalledWith(15)
    })
    // The first gain is the under-commentary duck, which never fades out.
    vi.mocked(audio.createGain).mock.results.slice(1).forEach(({ value: gain }) => {
      expect(gain.gain.linearRampToValueAtTime).toHaveBeenLastCalledWith(0, 15)
    })
    player.stop()
    expect(sources[0].stop).toHaveBeenLastCalledWith(10)
    player.dispose()
    player.setMix([0.1, 0.3, 0.95])
    expect(sources).toHaveLength(3)
    expect(audio.close).toHaveBeenCalledOnce()
  })
})

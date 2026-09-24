/// <reference types="node" />
import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import clips from './announcer-clips.json'

describe('static announcer library', () => {
  it('ships every referenced MP3 without unresolved placeholders', () => {
    expect(new Set(clips.map(clip => clip.file)).size).toBe(clips.length)
    for (const clip of clips) {
      expect(clip.text).not.toMatch(/[{}]/)
      const bytes = readFileSync(new URL(`../public/audio/announcer/${clip.file}`, import.meta.url))
      expect(bytes.length).toBeGreaterThan(1000)
      const hasId3 = bytes.subarray(0, 3).toString() === 'ID3'
      const hasFrameSync = bytes[0] === 0xff && (bytes[1] & 0xe0) === 0xe0
      expect(hasId3 || hasFrameSync).toBe(true)
    }
  })
  it('has varied matching commentary for all eight possible leaders and winners', () => {
    for (let horse = 1; horse <= 8; horse++) {
      for (const cue of ['start', 'pack', 'overtake', 'sprint', 'finish']) {
        const available = clips.filter(clip => clip.cue === cue && (clip.horse === 0 || clip.horse === horse))
        expect(new Set(available.map(clip => clip.variant)).size).toBeGreaterThanOrEqual(4)
      }
    }
  })
})

import { describe, expect, it } from 'vitest'
import { raceOrder, racePlan, racePositions } from './game'
import { HORSE_LENGTH, REFERENCE_LAP } from './raceModel'
import preview from '../godot/assets/race_preview.json'

const lengths = (progress: number) => progress * REFERENCE_LAP / HORSE_LENGTH
describe('race model', () => {
  it('ships the native preview race Godot runs without React', () => {
    expect(preview).toEqual(JSON.parse(JSON.stringify(racePlan(61293, 1))))
  })
  it('keeps the field together and settles positions gradually', () => {
    for (let round = 1; round <= 60; round++) {
      let previousGap = 0
      for (let t = 1; t <= 44.5; t += .1) {
        const p = racePositions(31337, round, t)
        const sorted = [...p].sort((a, b) => b - a)
        expect(lengths(sorted[0] - sorted[7])).toBeLessThan(9)
        const gap = lengths(sorted[0] - sorted[1])
        // The lead changes hands by strides, never by leaps.
        if (t > 1.05) expect(Math.abs(gap - previousGap)).toBeLessThan(.12)
        previousGap = gap
      }
    }
  })
  it('often ends in a fight, sometimes a clear win', () => {
    const margins = Array.from({ length: 200 }, (_, i) => {
      const order = raceOrder(777, i + 1)
      return lengths(1 - racePositions(777, i + 1, 44.5)[order[1] - 1])
    })
    expect(margins.filter(m => m < .6).length).toBeGreaterThan(40)
    expect(margins.filter(m => m > 1.2).length).toBeGreaterThan(30)
    expect(Math.max(...margins)).toBeLessThan(3.5)
  })
})

import { describe, expect, it } from 'vitest'
import manifest from './commentary-clips.json'
import { clipLength, commentaryCues, planCommentary, realFromVisual } from './commentary'
import { raceOrder, racePlan } from './game'
import { racePresentationTime } from './presentation'
import { HORSE_LENGTH, planProgress, REFERENCE_LAP } from './raceModel'

const clips = manifest.clips as Record<string, number[]>
const rounds = Array.from({ length: 80 }, (_, i) => i + 1)
function standing(seed: number, round: number, real: number) {
  const plan = racePlan(seed, round, 8)
  const p = Array.from({ length: 8 }, (_, i) => planProgress(plan, i, racePresentationTime(real)))
  const rank = p.map((_, i) => i).sort((a, b) => p[b] - p[a])
  return { p, rank, behind: (i: number) => (p[rank[0]] - p[i]) * REFERENCE_LAP / HORSE_LENGTH }
}
const named = (clip: string) => Number(clip.split('.')[1]) - 1

describe('race commentary', () => {
  it('only uses recorded phrases, never talks over itself and stays in the race window', () => {
    for (const round of rounds) {
      const call = planCommentary(2468, round, 8)
      call.flat().forEach(u => u.clips.forEach(id => expect(clips[id], id).toBeDefined()))
      call.slice(1).forEach((u, i) => expect(u.at).toBeGreaterThanOrEqual(call[i].at + clipLength(call[i].clips)))
      expect(call.find(u => u.at >= 0)!.clips[0]).toBe('gate')
      expect(call[0].at).toBeGreaterThanOrEqual(-60)
      expect(call.at(-1)!.at + clipLength(call.at(-1)!.clips)).toBeLessThan(55)
      const speaking = call.reduce((sum, u) => sum + clipLength(u.clips), 0)
      expect(speaking).toBeGreaterThan(25)
    }
  })
  it('calls the bigger fields with recorded phrases only', () => {
    for (const field of [10, 12]) for (const round of rounds.slice(0, 30)) {
      const call = planCommentary(2468, round, field)
      call.forEach(u => u.clips.forEach(id => expect(clips[id], `${field} ${id}`).toBeDefined()))
      expect(call.find(u => u.at >= 0)!.clips[0]).toBe('gate')
    }
  })
  it('crosses the line mid-phrase and names the right winner and places', () => {
    const crossing = realFromVisual(44.5)
    for (const round of rounds) {
      const order = raceOrder(2468, round, 8)
      const call = planCommentary(2468, round, 8)
      const over = call.find(u => u.clips[0].startsWith('over.'))!
      expect(named(over.clips[0])).toBe(order[0] - 1)
      expect(over.at).toBeLessThan(crossing)
      expect(over.at + clipLength(over.clips)).toBeGreaterThan(crossing)
      expect(call.some(u => u.clips.includes(`wins.${order[0]}`))).toBe(true)
      expect(call.some(u => u.clips.includes(`secondPlace.${order[1]}`) && u.clips.includes(`thirdPlace.${order[2]}`))).toBe(true)
    }
  })
  it('says what is on screen as it is said', () => {
    for (const round of rounds) {
      for (const cue of commentaryCues(planCommentary(2468, round, 8))) {
        const now = standing(2468, round, cue.at)
        const id = cue.clip.split('.')[0]
        if (['lead', 'leads', 'holds', 'takesLead'].includes(id)) expect(now.behind(named(cue.clip)), `${round} ${cue.clip} @${cue.at}`).toBeLessThan(.35)
        if (id === 'second') expect(now.rank.indexOf(named(cue.clip)), `${round} ${cue.clip}`).toBeLessThanOrEqual(2)
        if (id === 'last') expect(now.rank.indexOf(named(cue.clip))).toBeGreaterThanOrEqual(6)
      }
      // Gap calls match the gap between the two horses being called.
      const call = planCommentary(2468, round, 8)
      for (const u of call) {
        const now = standing(2468, round, u.at)
        const gap = (now.p[now.rank[0]] - now.p[now.rank[1]]) * REFERENCE_LAP / HORSE_LENGTH
        if (u.clips[0] === 'level') expect(gap, `${round} level`).toBeLessThan(.4)
        if (u.clips[0] === 'halfLength') expect(gap, `${round} half`).toBeLessThan(.8)
        if (u.clips[0] === 'oneLength') expect(gap, `${round} one`).toBeLessThan(1.4)
      }
    }
  })
})

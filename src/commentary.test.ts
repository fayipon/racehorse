import { describe, expect, it } from 'vitest'
import manifest from './commentary/zh-TW.json'
import { commentaryCues, planCommentary, realFromVisual, Voice, voiceLanguage, type VoiceManifest } from './commentary'
import { raceOrder, racePlan } from './game'
import { racePresentationTime } from './presentation'
import { HORSE_LENGTH, planProgress, REFERENCE_LAP } from './raceModel'

const voice = new Voice(manifest)
const clips = voice.clips
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
      const call = planCommentary(voice, 2468, round, 8)
      call.flat().forEach(u => u.clips.forEach(id => expect(clips[id], id).toBeDefined()))
      call.slice(1).forEach((u, i) => expect(u.at).toBeGreaterThanOrEqual(call[i].at + voice.length(call[i].clips)))
      expect(call.find(u => u.at >= 0)!.clips[0]).toBe('gate')
      expect(call[0].at).toBeGreaterThanOrEqual(-60)
      expect(call.at(-1)!.at + voice.length(call.at(-1)!.clips)).toBeLessThan(55)
      const speaking = call.reduce((sum, u) => sum + voice.length(u.clips), 0)
      expect(speaking).toBeGreaterThan(25)
    }
  })
  it('calls the bigger fields by name, from the extra voice file only for runners 9–12', () => {
    expect(rounds.flatMap(round => commentaryCues(planCommentary(voice, 2468, round, 8), voice)).every(cue => cue.sprite === 0)).toBe(true)
    for (const field of [10, 12]) for (const round of rounds.slice(0, 30)) {
      const call = planCommentary(voice, 2468, round, field)
      call.forEach(u => u.clips.forEach(id => expect(clips[id], `${field} ${id}`).toBeDefined()))
      expect(call.find(u => u.at >= 0)!.clips[0]).toBe('gate')
      const winner = raceOrder(2468, round, field)[0]
      expect(call.some(u => u.clips.includes(`wins.${winner}`)), `${field} ${round} wins.${winner}`).toBe(true)
      commentaryCues(call, voice).forEach(cue => expect(cue.sprite).toBe(Number(cue.clip.split('.')[1]) > 8 ? 1 : 0))
    }
  })
  it('crosses the line mid-phrase and names the right winner and places', () => {
    const crossing = realFromVisual(44.5)
    for (const round of rounds) {
      const order = raceOrder(2468, round, 8)
      const call = planCommentary(voice, 2468, round, 8)
      const over = call.find(u => u.clips[0].startsWith('over.'))!
      expect(named(over.clips[0])).toBe(order[0] - 1)
      expect(over.at).toBeLessThan(crossing)
      expect(over.at + voice.length(over.clips)).toBeGreaterThan(crossing)
      expect(call.some(u => u.clips.includes(`wins.${order[0]}`))).toBe(true)
      expect(call.some(u => u.clips.includes(`secondPlace.${order[1]}`) && u.clips.includes(`thirdPlace.${order[2]}`))).toBe(true)
    }
  })
  it('says what is on screen as it is said', () => {
    for (const round of rounds) {
      for (const cue of commentaryCues(planCommentary(voice, 2468, round, 8), voice)) {
        const now = standing(2468, round, cue.at)
        const id = cue.clip.split('.')[0]
        if (['lead', 'leads', 'holds', 'takesLead'].includes(id)) expect(now.behind(named(cue.clip)), `${round} ${cue.clip} @${cue.at}`).toBeLessThan(.35)
        if (id === 'second') expect(now.rank.indexOf(named(cue.clip)), `${round} ${cue.clip}`).toBeLessThanOrEqual(2)
        if (id === 'last') expect(now.rank.indexOf(named(cue.clip))).toBeGreaterThanOrEqual(6)
      }
      // Gap calls match the gap between the two horses being called.
      const call = planCommentary(voice, 2468, round, 8)
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

// Every language records the same phrase ids, so the one planner fits each voice's own timing.
const voices = Object.entries(import.meta.glob<VoiceManifest>('./commentary/*.json', { eager: true, import: 'default' }))
  .map(([path, data]) => [path.match(/([\w-]+)\.json$/)![1], new Voice(data)] as const)
describe('race commentary in every language', () => {
  it('records the Mandarin phrase set in each language', () => {
    expect(voices.map(([language]) => language).sort()).toEqual(['en', 'ja', 'pt-BR', 'zh-TW'])
    // Simplified Chinese pages hear the Mandarin recording.
    expect(voiceLanguage('zh-CN')).toBe('zh-TW')
    for (const [language, other] of voices) {
      expect(Object.keys(other.clips).sort(), language).toEqual(Object.keys(voice.clips).sort())
      expect(Object.keys(other.extra).sort(), language).toEqual(Object.keys(voice.extra).sort())
    }
  })
  it('welcomes each cup by name, counts its field at the break and fits every call before the caller stops at 58 s', () => {
    for (const [language, other] of voices) for (const [cup, field] of [['sunny', 8], ['thunder', 10], ['royal', 12]] as const) {
      for (const round of rounds.slice(0, 24)) {
        const call = planCommentary(other, 2468, round, field)
        call.forEach(u => u.clips.forEach(id => expect(other.clips[id], `${language} ${id}`).toBeDefined()))
        call.slice(1).forEach((u, i) => expect(u.at, `${language} ${field} ${round}`).toBeGreaterThanOrEqual(call[i].at + other.length(call[i].clips)))
        expect(call.find(u => u.at >= 0)!.clips, `${language} ${field} ${round}`).toEqual(['gate', `breakAway.${field}`])
        expect(call.at(-1)!.at + other.length(call.at(-1)!.clips), `${language} ${field} ${round}`).toBeLessThan(58)
        if (round === 1) expect(call[0].clips, language).toEqual([`welcome1.${cup}`])
      }
    }
  })
})

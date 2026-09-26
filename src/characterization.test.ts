import { describe, expect, it } from 'vitest'
import en from './commentary/en.json'
import ja from './commentary/ja.json'
import pt from './commentary/pt-BR.json'
import zh from './commentary/zh-TW.json'
import { planCommentary, Voice } from './commentary'
import { raceOrder, racePlan } from './game'

// Races and calls without a script must stay exactly as they were before scripts existed.
const fnv = (text: string) => { let h = 0x811c9dc5; for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 16777619) >>> 0; return h.toString(16) }
const fields = [8, 10, 12]
describe('unscripted races', () => {
  it('generates the same orders and plans', () => {
    const plans = [31337, 987654].flatMap(seed => fields.flatMap(field => Array.from({ length: 100 }, (_, i) => JSON.stringify([raceOrder(seed, i + 1, field), racePlan(seed, i + 1, field)]))))
    expect(fnv(plans.join('\n'))).toBe(PLANS)
  })
  it('calls them the same way in every language', () => {
    const calls = [en, ja, pt, zh].map(manifest => new Voice(manifest)).flatMap(voice => fields.flatMap(field => Array.from({ length: 24 }, (_, i) => JSON.stringify(planCommentary(voice, 2468, i + 1, field)))))
    expect(fnv(calls.join('\n'))).toBe(CALLS)
  })
})
const PLANS = '9dcefad3'
const CALLS = '460cdc68'

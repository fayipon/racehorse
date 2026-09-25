import { describe, expect, it } from 'vitest'
import en from './commentary/en.json'
import ja from './commentary/ja.json'
import pt from './commentary/pt-BR.json'
import zh from './commentary/zh-TW.json'
import shipped from '../public/races.json'
import { planCommentary, realFromVisual, Voice } from './commentary'
import { advance, alignStore, createGame, createStore, CUPS, gameOf, placeBet, planRound, raceNumber, raceOrder, racePlan, recentResults, roundAt, ROUND_MS, startOf, withGame, type CupId, type Store } from './game'
import { buildRacePlan, HORSE_LENGTH, planHealth, planProgress, referenceLap, WINNER_FINISH, type Checkpoint } from './raceModel'
import { installScripts, lockRound, normalizeRace, scriptOf, type RaceScript } from './raceScript'
import { BASELINE, parseSchedule } from './schedule'

const START = 1_800_000_000_000
const voices = [en, ja, pt, zh].map(manifest => new Voice(manifest))
const lengths = (progress: number, field: number) => progress * referenceLap(field) / HORSE_LENGTH
const progressAt = (plan: ReturnType<typeof racePlan>, t: number) => plan.knots.map((_, i) => planProgress(plan, i, t))
function rng(seed: number) { return () => { seed |= 0; seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ seed >>> 15, 1 | seed); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296 } }
// The standings when the leader shows `metres` on the nominal 1200 m, as the progress bar does.
function standingsAt(plan: ReturnType<typeof racePlan>, metres: number) {
  let t = 0
  while (t < WINNER_FINISH && Math.max(...progressAt(plan, t)) * 1200 < metres) t += .01
  const p = progressAt(plan, t)
  return p.map((_, i) => i).sort((a, b) => p[b] - p[a]).map(i => ({ horse: i, p: p[i] }))
}
const script = (raw: object, field = 8, cup = 'sunny') => normalizeRace(raw, field, cup)

describe('race scripts', () => {
  it('reads a full race and numbers horses from zero inside the model', () => {
    const { script: s, warnings } = script({ order: [5, 3], styles: { 5: 'close' }, finish: 'photo', margins: [.2, 1.5], checkpoints: [{ at: 800, order: [7, 3] }, { at: 400, leader: 3, by: 1 }], commentary: { lines: [{ at: -20, clips: ['styleClose.5'] }] } })
    expect(warnings).toEqual([])
    expect(s).toMatchObject({ order: [5, 3], finish: 'photo', margins: [.2, 1.5], checkpoints: [{ at: 400, order: [2], by: 1 }, { at: 800, order: [6, 2] }], commentary: { mode: 'add', lines: [{ at: -20, clips: ['styleClose.5'] }] } })
    expect(s!.styles![4]).toBe('close')
  })
  it('drops a race with a bad order and only the bad parts of any other', () => {
    for (const order of [[1, 1], [9], [], 'five']) expect(script({ order }).script).toBeUndefined()
    const { script: s, warnings } = script({ styles: { 5: 'fast', 12: 'front' }, finish: 'huge', margins: [7], checkpoints: [{ at: 100, leader: 1 }, { at: 500, leader: 2, order: [3] }, { at: 600, leader: 1, by: 5 }, { at: 700, leader: 1 }, { at: 760, leader: 2 }], commentary: { lines: [{ at: -10, clips: ['gate'] }, { at: 5, clips: ['takesLead.9'] }, { at: 6, clips: ['welcome1.royal'] }, { at: 7, clips: ['breakAway.10'] }, { at: 8, clips: ['m600'] }] } })
    expect(warnings).toHaveLength(12)
    expect(s).toEqual({ checkpoints: [{ at: 700, order: [0] }], commentary: { mode: 'add', lines: [{ at: 8, clips: ['m600'] }] } })
    expect(script({ commentary: { mode: 'replace', lines: [{ at: -10, clips: ['gate'] }] } }).script!.commentary!.lines).toHaveLength(1)
  })
  it('parses the shipped file without a single warning', () => {
    const schedule = parseSchedule(shipped)
    expect(schedule.warnings).toEqual([])
    expect(schedule.clocks).toEqual(BASELINE)
  })
  it('places a race by round or by its start time, with a time zone', () => {
    const file = (races: object[]) => parseSchedule({ version: 1, cups: { sunny: { epoch: '2026-09-01T00:00:00+08:00', seed: 1, races } } })
    const round = (Date.parse('2026-09-26T20:00:00+08:00') - Date.parse('2026-09-01T00:00:00+08:00')) / ROUND_MS + 1
    expect([...file([{ at: '2026-09-26T20:00:00+08:00' }]).scripts.sunny.keys()]).toEqual([round])
    expect([...file([{ round: 7 }]).scripts.sunny.keys()]).toEqual([7])
    for (const races of [[{ at: '2026-09-26T20:00:00' }], [{ at: '2026-09-26T20:01:00+08:00' }], [{ at: '2026-09-26T20:00:00+08:00', round: 3 }], [{ round: 0 }], [{ round: 4 }, { round: 4, order: [1] }]]) {
      expect(file(races).warnings, JSON.stringify(races)).toHaveLength(1)
    }
    expect(parseSchedule({ version: 2 }).clocks).toEqual(BASELINE)
  })
  it('keeps a race locked once betting has closed, and lets later rounds follow the file', () => {
    installScripts(11, 8, new Map([[3, { order: [2] }], [4, { order: [6] }]]))
    lockRound(11, 8, 3)
    installScripts(11, 8, new Map([[3, { order: [7] }], [4, { order: [8] }]]))
    expect(raceOrder(11, 3, 8)[0]).toBe(2)
    expect(raceOrder(11, 4, 8)[0]).toBe(8)
    lockRound(11, 8, 5)
    installScripts(11, 8, new Map([[5, { order: [1] }]]))
    expect(scriptOf(11, 5, 8)).toBeUndefined()
  })
})

describe('scripted races', () => {
  it('finish in the scripted order and pay the scripted winner', () => {
    installScripts(21, 8, new Map([[1, { order: [4, 7] }]]))
    const drawn = raceOrder(22, 1, 8)
    const order = raceOrder(21, 1, 8)
    expect(order.slice(0, 2)).toEqual([4, 7])
    expect(new Set(order).size).toBe(8)
    const plan = racePlan(21, 1, 8)
    expect(order.map(id => plan.finishTimes[id - 1])).toEqual([...plan.finishTimes].sort((a, b) => a - b))
    expect(plan.finishTimes[3]).toBeCloseTo(WINNER_FINISH, 2)
    const game = placeBet(createGame(START, 'sunny', 21), 'horse:4', 100, START).game
    expect(advance(game, START + 110_000).history[0]).toMatchObject({ winner: 4, payout: 760 })
    expect(drawn).toHaveLength(8)
  })
  it('honours styles, finishes and exact margins', () => {
    for (const field of [8, 10, 12]) for (let n = 0; n < 12; n++) {
      const order = raceOrder(31, n + 1, field)
      const second = [.1, .5, 1.2, 3][n % 4]
      const { plan, dropped } = buildRacePlan(order, () => rng(n), { styles: ['close', 'front'], margins: [second, 1] })
      const p = progressAt(plan, WINNER_FINISH)
      expect(dropped).toEqual([])
      expect(plan.styles.slice(0, 2)).toEqual(['close', 'front'])
      expect(lengths(p[order[0] - 1] - p[order[1] - 1], field)).toBeCloseTo(second, 2)
      expect(lengths(p[order[1] - 1] - p[order[2] - 1], field)).toBeCloseTo(1, 2)
    }
    const bands = { photo: [0, .25], close: [.25, .6], clear: [.6, 1.46], easy: [1.46, 3] } as const
    for (const [finish, [low, high]] of Object.entries(bands)) for (let n = 0; n < 20; n++) {
      const order = raceOrder(32, n + 1, 8)
      const p = progressAt(buildRacePlan(order, () => rng(n), { finish: finish as keyof typeof bands }).plan, WINNER_FINISH)
      const margin = lengths(p[order[0] - 1] - p[order[1] - 1], 8)
      expect(margin, `${finish} ${n}`).toBeGreaterThanOrEqual(low)
      expect(margin, `${finish} ${n}`).toBeLessThanOrEqual(high)
    }
  })
  it('puts the scripted horses in front at every checkpoint and still runs like a race', () => {
    const pick = rng(99)
    let checked = 0
    for (const field of [8, 10, 12]) for (let n = 0; n < 50; n++) {
      const order = raceOrder(41, n + 1, field)
      const checkpoints: Checkpoint[] = []
      for (let at = 200 + Math.floor(pick() * 300); at <= 1100 && checkpoints.length < 3; at += 150 + Math.floor(pick() * 300)) {
        const horses = Array.from({ length: field }, (_, i) => i).sort(() => pick() - .5).slice(0, 1 + Math.floor(pick() * 3))
        checkpoints.push({ at, order: horses, ...(pick() < .3 ? { by: 1 + Math.floor(pick() * 2) } : {}) })
      }
      const { plan, dropped } = buildRacePlan(order, () => rng(n * 7 + field), { checkpoints })
      const health = planHealth(plan)
      expect(health.backwards).toBe(false)
      expect(health.leadStep).toBeLessThanOrEqual(.13)
      expect(health.rate).toBeLessThanOrEqual(.27)
      expect(plan.knots.every(k => k.at(-1) === 0)).toBe(true)
      expect(order.map(id => plan.finishTimes[id - 1])).toEqual([...plan.finishTimes].sort((a, b) => a - b))
      for (const checkpoint of checkpoints.filter(c => !dropped.includes(`checkpoint ${c.at}m`))) {
        const standings = standingsAt(plan, checkpoint.at)
        expect(standings.slice(0, checkpoint.order.length).map(s => s.horse), `${field}/${n} ${checkpoint.at}m`).toEqual(checkpoint.order)
        if (checkpoint.by) expect(lengths(standings[0].p - standings[1].p, field)).toBeGreaterThan(checkpoint.by - .05)
        checked++
      }
    }
    expect(checked).toBeGreaterThan(250)
  })
  it('drops what it cannot run, the hardest checkpoint first', () => {
    const order = raceOrder(51, 1, 8)
    const leader = order[7] - 1
    const { plan, dropped } = buildRacePlan(order, () => rng(1), { margins: [3], checkpoints: [{ at: 1120, order: [leader], by: 4 }, { at: 300, order: [order[0] - 1] }] })
    expect(dropped).toEqual(['checkpoint 1120m'])
    expect(standingsAt(plan, 300)[0].horse).toBe(order[0] - 1)
    expect(planHealth(plan).backwards).toBe(false)
  })
})

describe('shared schedule', () => {
  const clocks: Record<CupId, { epoch: number; seed: number }> = { sunny: { epoch: START, seed: 5 }, thunder: { epoch: START + 40_000, seed: 6 }, royal: { epoch: START + 80_000, seed: 7 } }
  it('numbers rounds from the epoch and shows the day\'s race number', () => {
    expect([1, 720, 721, 1441].map(raceNumber)).toEqual([1, 720, 1, 1])
    expect(roundAt(clocks.sunny, START + 5 * ROUND_MS + 1)).toBe(6)
    expect(startOf(clocks.sunny, 6)).toBe(START + 5 * ROUND_MS)
    expect(roundAt(clocks.sunny, START - 1)).toBe(1)
  })
  it('opens every cup on the current round for a first visit', () => {
    const now = START + 10 * ROUND_MS + 5_000
    const store = alignStore(createStore(), now, clocks)
    for (const cup of Object.keys(CUPS) as CupId[]) expect(store.cups[cup]).toMatchObject({ seed: clocks[cup].seed, round: roundAt(clocks[cup], now), startedAt: startOf(clocks[cup], roundAt(clocks[cup], now)), bets: [], history: [] })
    expect(alignStore(store, now, clocks)).toBe(store)
    expect(alignStore(store, now - 3 * ROUND_MS, clocks)).toBe(store)
  })
  it('refunds a race an old save will never see and settles one it already ran', () => {
    const now = START + 10 * ROUND_MS + 5_000
    const running = placeBet(createGame(now - 30_000, 'sunny', 999), 'horse:1', 300, now - 30_000).game
    let store: Store = withGame(createStore(), running)
    store = alignStore(store, now, clocks)
    expect(store.balance).toBe(10_000)
    expect(store.cups.sunny).toMatchObject({ seed: 5, round: 11, bets: [], history: [] })
    const finished = placeBet(createGame(now - 115_000, 'thunder', 998), 'horse:1', 300, now - 115_000).game
    const won = advance(finished, now).balance
    expect(alignStore(withGame(createStore(), finished), now, clocks).balance).toBe(won)
  })
  it('gives everyone the same recent winners', () => {
    const results = recentResults(5, 10, 8, 8)
    expect(results.map(r => r.round)).toEqual([9, 8, 7, 6, 5, 4, 3, 2])
    expect(results.map(r => r.winner)).toEqual(results.map(r => raceOrder(5, r.round, 8)[0]))
    expect(recentResults(5, 3, 8, 8)).toHaveLength(2)
    expect(gameOf(alignStore(createStore(), START, clocks), 'royal', START).round).toBe(1)
  })
})

describe('scripted commentary', () => {
  const lines = [{ at: -45, clips: ['styleFront.3'] }, { at: -32, clips: ['styleClose.5'] }, { at: 6, clips: ['evenBreak'] }]
  it('fits scripted lines around the fixed calls in every language', () => {
    for (const voice of voices) {
      const call = planCommentary(voice, 61, 5, 8, [], { mode: 'add', lines })
      for (const line of lines) expect(call.some(u => u.clips.join() === line.clips.join() && u.at >= line.at && u.at <= line.at + 1.5), line.clips[0]).toBe(true)
      for (const line of lines) expect(call.filter(u => u.clips.some(clip => line.clips.includes(clip))), line.clips[0]).toHaveLength(1)
      call.slice(1).forEach((u, i) => expect(u.at).toBeGreaterThanOrEqual(call[i].at + voice.length(call[i].clips)))
      expect(call.find(u => u.at >= 0)!.clips[0]).toBe('gate')
      const winner = raceOrder(61, 5, 8)[0]
      expect(call.some(u => u.clips.includes(`over.${winner}`) && u.at < realFromVisual(WINNER_FINISH))).toBe(true)
      expect(call.some(u => u.clips.includes(`wins.${winner}`))).toBe(true)
      for (const id of ['welcome2.sunny', 'betReminder', 'lastCall', 'closed']) expect(call.some(u => u.clips.includes(id)), id).toBe(true)
    }
  })
  it('leaves the run to the line to the caller and speaks only the script in replace mode', () => {
    const late = planCommentary(voices[3], 61, 5, 8, [], { mode: 'add', lines: [{ at: 40, clips: ['comeback'] }] })
    expect(late.filter(u => u.clips.includes('comeback') && u.at < 41)).toEqual([])
    const only = planCommentary(voices[3], 61, 5, 8, [], { mode: 'replace', lines })
    expect(only.map(u => u.clips)).toEqual(lines.map(l => l.clips))
  })
  it('runs every shipped script as written, in every language', () => {
    const schedule = parseSchedule(shipped)
    for (const cup of Object.keys(CUPS) as CupId[]) {
      const { seed } = schedule.clocks[cup], field = CUPS[cup].field
      installScripts(seed, field, schedule.scripts[cup])
      for (const [round, raceScript] of schedule.scripts[cup] as Map<number, RaceScript>) {
        expect(planRound(seed, round, field).dropped, `${cup} ${round}`).toEqual([])
        for (const line of raceScript.commentary?.lines ?? []) for (const voice of voices) {
          expect(planCommentary(voice, seed, round, field).some(u => u.clips.join() === line.clips.join() && u.at >= line.at && u.at <= line.at + 1.5), `${cup} ${round} ${line.clips}`).toBe(true)
        }
      }
    }
  })
})

import { describe, expect, it } from 'vitest'
import { advance, cancelBet, createGame, isGame, payoutFor, phaseAt, placeBet, raceOrder, racePositions, ROUND_MS, wins, type Pick } from './game'
const START = 1_800_000_000_000
describe('two-minute race lifecycle', () => {
  it('starts racing at precisely 60s, settles at 110s and starts again at 120s', () => {
    const g = createGame(START, 123)
    expect(phaseAt(g, START + 59999)).toBe('betting')
    expect(phaseAt(g, START + 60000)).toBe('racing')
    expect(phaseAt(g, START + 109999)).toBe('racing')
    expect(phaseAt(g, START + 110000)).toBe('result')
    expect(advance(g, START + 120000)).toMatchObject({ round: 2, startedAt: START + 120000, settled: false, bets: [] })
  })
  it('rejects late bets and cancellations even with a stale UI', () => {
    const g = placeBet(createGame(START, 42), 'horse:1', 100, START).game
    expect(placeBet(g, 'odd', 100, START + 47999).error).toBeUndefined()
    for (const time of [48000, 53000, 59999, 60000]) {
      expect(placeBet(g, 'odd', 100, START + time).error).toBeTruthy()
      expect(cancelBet(g, g.bets[0].id, START + time)).toEqual(g)
    }
    expect(cancelBet(g, g.bets[0].id, START + 60000).balance).toBe(9900)
    expect(cancelBet(g, g.bets[0].id, START + 47999).balance).toBe(10000)
  })
  it('pays all winning markets once, including principal', () => {
    let g = createGame(START, 56)
    const winner = raceOrder(g.seed, g.round)[0]
    const picks: Pick[] = [`horse:${winner}`, winner % 2 ? 'odd' : 'even', winner <= 4 ? 'small' : 'big']
    for (const pick of picks) g = placeBet(g, pick, 100, START).game
    expect(g.balance).toBe(9700)
    g = advance(g, START + 110000)
    expect(g.balance).toBe(10840)
    expect(g.history[0]).toMatchObject({ stake: 300, payout: 1140, winner })
    expect(advance(g, START + 115000).balance).toBe(10840)
    expect(advance(JSON.parse(JSON.stringify(g)), START + 119999).balance).toBe(10840)
  })
  it('restores sleep and skipped rounds without losing or duplicating settlements', () => {
    let g = createGame(START, 88)
    const winner = raceOrder(g.seed, 1)[0]
    g = placeBet(g, `horse:${winner}`, 100, START).game
    const after = advance(g, START + ROUND_MS * 1000 + 62000)
    expect(after.round).toBe(1001)
    expect(after.balance).toBe(10660)
    expect(after.history.length).toBeLessThanOrEqual(12)
    expect(after.bets).toEqual([])
    expect(phaseAt(after, START + ROUND_MS * 1000 + 62000)).toBe('racing')
  })
  it('validates amounts and balance', () => {
    const g = createGame(START, 12)
    for (const amount of [0, -10, 5, 15, 10001, 20000, NaN, Infinity]) expect(placeBet(g, 'odd', amount, START).error).toBeTruthy()
    const empty = placeBet(g, 'big', 10000, START).game
    expect(placeBet(empty, 'odd', 10, START).error).toBeTruthy()
    expect(placeBet(g, 'horse:9' as Pick, 100, START).error).toBeTruthy()
  })
})
describe('race integrity', () => {
  it('keeps every horse moving forward and matches animation finish order to payout', () => {
    for (let round = 1; round <= 50; round++) {
      const order = raceOrder(987654, round)
      expect(new Set(order).size).toBe(8)
      let previous = racePositions(987654, round, 0)
      const crossed: number[] = []
      for (let t = .1; t <= 50.1; t += .1) {
        const positions = racePositions(987654, round, t)
        positions.forEach((p, i) => { expect(p).toBeGreaterThanOrEqual(previous[i] - 1e-9); if (p >= 1 && !crossed.includes(i + 1)) crossed.push(i + 1) })
        previous = positions
      }
      expect(crossed).toEqual(order)
    }
  })
  it('uses the specified parity and size boundaries for all eight winners', () => {
    for (let winner = 1; winner <= 8; winner++) {
      expect(wins('odd', winner)).toBe(winner % 2 === 1)
      expect(wins('even', winner)).toBe(winner % 2 === 0)
      expect(wins('small', winner)).toBe(winner <= 4)
      expect(wins('big', winner)).toBe(winner >= 5)
      expect(payoutFor([{id:'x',pick:`horse:${winner}`,amount:10}],winner)).toBe(76)
    }
  })
  it('rejects incompatible or malformed saves', () => {
    expect(isGame(createGame(START, 1))).toBe(true)
    for (const bad of [null, {}, { ...createGame(START, 1), balance: -1 }, { ...createGame(START, 1), history: [{}] }]) expect(isGame(bad)).toBe(false)
  })
})

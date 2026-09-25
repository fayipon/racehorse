import { makeRacePlan, planProgress, type RacePlan } from './raceModel'

export const BET_CLOSE_MS = 48_000
export const BET_MS = 60_000
export const RACE_MS = 50_000
export const RESULT_MS = 10_000
export const ROUND_MS = BET_MS + RACE_MS + RESULT_MS
// The whole stable; a cup runs the first `field` of them.
export const HORSES = [
  { id: 1, name: '赤焰疾風', en: 'RUBY DASH', color: '#e55a53' },
  { id: 2, name: '綠野旋律', en: 'GREEN MELODY', color: '#7da567' },
  { id: 3, name: '日光漫步', en: 'SUNNY STEPS', color: '#e6b73e' },
  { id: 4, name: '紫羅蘭夢', en: 'VIOLET DREAM', color: '#aa8ac7' },
  { id: 5, name: '橘子汽水', en: 'ORANGE POP', color: '#e89950' },
  { id: 6, name: '莓果甜心', en: 'BERRY HEART', color: '#d77bac' },
  { id: 7, name: '晴空之翼', en: 'BLUE BLAZE', color: '#6dbbcc' },
  { id: 8, name: '午夜星辰', en: 'MIDNIGHT STAR', color: '#6686d0' },
  { id: 9, name: '薄荷微風', en: 'MINT BREEZE', color: '#2f9a88' },
  { id: 10, name: '可可雷霆', en: 'COCOA THUNDER', color: '#9b6b4b' },
  { id: 11, name: '銀月流光', en: 'SILVER MOON', color: '#8f9aa6' },
  { id: 12, name: '玫瑰王冠', en: 'ROSE CROWN', color: '#b8475e' },
] as const
export const CUPS = {
  sunny: { id: 'sunny', name: '陽光盃', en: 'SUNNY CUP', field: 8, venue: '陽光賽場', motto: '讓每一場比賽，都多一點陽光。' },
  thunder: { id: 'thunder', name: '雷霆盃', en: 'THUNDER CUP', field: 10, venue: '雷霆賽場', motto: '讓每一次衝線，都像一聲響雷。' },
  royal: { id: 'royal', name: '皇家盃', en: 'ROYAL CUP', field: 12, venue: '皇家賽場', motto: '讓每一匹小馬，都有機會戴上王冠。' },
} as const
export type CupId = keyof typeof CUPS
export const isCup = (value: unknown): value is CupId => typeof value === 'string' && Object.hasOwn(CUPS, value)
export type Phase = 'betting' | 'racing' | 'result'
export type Pick = `horse:${number}` | 'odd' | 'even' | 'small' | 'big'
export interface Bet { id: string; pick: Pick; amount: number }
export interface Result { round: number; winner: number; order: number[]; stake: number; payout: number }
// One cup's rounds, seen with the shared wallet.
export interface Game { version: 3; cup: CupId; seed: number; round: number; startedAt: number; balance: number; bets: Bet[]; settled: boolean; history: Result[] }
export const fieldOf = (game: { cup: CupId }) => CUPS[game.cup].field
export function randomSeed() { return crypto.getRandomValues(new Uint32Array(1))[0] }
export function createGame(now: number, cup: CupId, seed = randomSeed()): Game {
  return { version: 3, cup, seed, round: 1, startedAt: now, balance: 10_000, bets: [], settled: false, history: [] }
}
export function phaseAt(game: Game, now: number): Phase {
  const elapsed = Math.max(0, now - game.startedAt)
  return elapsed < BET_MS ? 'betting' : elapsed < BET_MS + RACE_MS ? 'racing' : 'result'
}
export function countdown(game: Game, now: number) {
  const phase = phaseAt(game, now)
  const end = phase === 'betting' ? BET_MS : phase === 'racing' ? BET_MS + RACE_MS : ROUND_MS
  return Math.max(0, Math.ceil((game.startedAt + end - now) / 1000))
}
function rng(seed: number) {
  return () => {
    seed |= 0; seed = (seed + 0x6D2B79F5) | 0
    let t = Math.imul(seed ^ seed >>> 15, 1 | seed)
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t
    return ((t ^ t >>> 14) >>> 0) / 4294967296
  }
}
export function raceOrder(seed: number, round: number, field: number): number[] {
  const random = rng((seed ^ Math.imul(round, 2654435761)) >>> 0)
  const order = Array.from({ length: field }, (_, i) => i + 1)
  for (let i = order.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1)); [order[i], order[j]] = [order[j], order[i]]
  }
  return order
}
// Every market returns 95%: a winner pays the field size, a half of the field pays 2.
export function odds(pick: Pick, field: number) { return pick.startsWith('horse:') ? Math.round(field * 95) / 100 : 1.9 }
export function validPick(value: unknown, field: number): value is Pick {
  if (typeof value !== 'string') return false
  const horse = /^horse:(\d+)$/.exec(value)
  return horse ? Number(horse[1]) >= 1 && Number(horse[1]) <= field : ['odd', 'even', 'small', 'big'].includes(value)
}
export function pickLabel(pick: Pick) {
  if (pick.startsWith('horse:')) { const id = Number(pick.split(':')[1]); return `${id} 號・${HORSES[id - 1].name}` }
  return { odd: '冠軍馬號・單', even: '冠軍馬號・雙', small: '冠軍馬號・小', big: '冠軍馬號・大' }[pick as 'odd' | 'even' | 'small' | 'big']
}
// Small is the lower half of the numbers, big the upper half.
export function wins(pick: Pick, winner: number, field: number) {
  if (pick.startsWith('horse:')) return Number(pick.split(':')[1]) === winner
  return pick === 'odd' ? winner % 2 === 1 : pick === 'even' ? winner % 2 === 0 : pick === 'small' ? winner <= field / 2 : winner > field / 2
}
export function payoutFor(bets: Bet[], winner: number, field: number) {
  return bets.reduce((sum, bet) => sum + (wins(bet.pick, winner, field) ? Math.round(bet.amount * odds(bet.pick, field)) : 0), 0)
}
function settle(game: Game): Game {
  if (game.settled) return game
  const field = fieldOf(game)
  const order = raceOrder(game.seed, game.round, field)
  const payout = payoutFor(game.bets, order[0], field)
  const result = { round: game.round, winner: order[0], order, stake: game.bets.reduce((s, b) => s + b.amount, 0), payout }
  return { ...game, balance: game.balance + payout, settled: true, history: [result, ...game.history].slice(0, 12) }
}
// Settle once, then advance by wall-clock time, including sleep / background tabs.
export function advance(game: Game, now: number): Game {
  if (now < game.startedAt + BET_MS + RACE_MS) return game
  let next = settle(game)
  const skipped = Math.floor((now - game.startedAt) / ROUND_MS)
  if (!skipped) return next
  // Bound work even if a saved game is reopened years later.
  for (let offset = Math.max(1, skipped - 11); offset < skipped; offset++) {
    next = settle({ ...next, round: game.round + offset, bets: [], settled: false })
  }
  next = { ...next, round: game.round + skipped, startedAt: game.startedAt + skipped * ROUND_MS, bets: [], settled: false }
  return now >= next.startedAt + BET_MS + RACE_MS ? settle(next) : next
}
export function placeBet(game: Game, pick: Pick, amount: number, now: number): { game: Game; error?: string } {
  const current = advance(game, now)
  if (!bettingOpen(current, now)) return { game: current, error: '本場已封盤，下一場再試試手氣。' }
  if (!validPick(pick, fieldOf(current)) || !Number.isSafeInteger(amount) || amount < 10 || amount > 10_000 || amount % 10 !== 0) return { game: current, error: '投注金額須為 10–10,000，且為 10 的倍數。' }
  if (amount > current.balance) return { game: current, error: '可用籌碼不足，請調整投注金額。' }
  if (current.bets.length >= 100) return { game: current, error: '本輪最多 100 筆注單。' }
  return { game: { ...current, balance: current.balance - amount, bets: [...current.bets, { id: crypto.randomUUID(), pick, amount }] } }
}
export function cancelBet(game: Game, id: string, now: number): Game {
  const current = advance(game, now)
  if (!bettingOpen(current, now)) return current
  const bet = current.bets.find(b => b.id === id)
  return bet ? { ...current, balance: current.balance + bet.amount, bets: current.bets.filter(b => b.id !== id) } : current
}
// Smooth, monotonic distances. The finish order is exactly the settlement order.
// One plan per round, shared with Godot; see raceModel.ts.
let cachedPlan: { key: string; plan: RacePlan } | null = null
export function racePlan(seed: number, round: number, field: number): RacePlan {
  const key = `${seed}:${round}:${field}`
  if (cachedPlan?.key !== key) cachedPlan = { key, plan: makeRacePlan(raceOrder(seed, round, field), rng((seed ^ Math.imul(round, 2654435761) ^ 0x5bd1e995) >>> 0)) }
  return cachedPlan.plan
}
export function racePositions(seed: number, round: number, seconds: number, field: number) {
  const plan = racePlan(seed, round, field)
  return Array.from({ length: field }, (_, index) => Math.max(0, Math.min(1, planProgress(plan, index, seconds))))
}
export function cameraShot(phase: Phase, seconds: number) {
  if (phase === 'betting') return { id: 0, label: '賽前巡禮' }
  if (phase === 'result') return { id: 4, label: '前三名頒獎' }
  if (seconds < 7) return { id: 1, label: '起跑鏡頭' }
  if (seconds < 24) return { id: 2, label: '側面追拍' }
  if (seconds < 37) return { id: 3, label: '彎道追逐' }
  return { id: 5, label: seconds < 39.5 ? '終點衝刺' : seconds < 42.3 ? '衝刺特寫' : seconds < 45.8 ? '衝線時刻' : '終點定鏡' }
}
export function isGame(value: unknown): value is Game {
  if (!value || typeof value !== 'object') return false
  const g = value as Game
  if (g.version !== 3 || !isCup(g.cup)) return false
  const field = fieldOf(g)
  return Number.isSafeInteger(g.seed) && Number.isSafeInteger(g.round) && g.round > 0 && Number.isFinite(g.startedAt) && g.startedAt > 0 && Number.isSafeInteger(g.balance) && g.balance >= 0 && typeof g.settled === 'boolean' && Array.isArray(g.bets) && g.bets.every(b => typeof b.id === 'string' && validPick(b.pick, field) && Number.isSafeInteger(b.amount) && b.amount >= 10) && Array.isArray(g.history) && g.history.every(r => Number.isSafeInteger(r.round) && Number.isSafeInteger(r.winner) && r.winner >= 1 && r.winner <= field && Array.isArray(r.order) && r.order.length === field && new Set(r.order).size === field && r.order.every(n => Number.isSafeInteger(n) && n >= 1 && n <= field) && Number.isSafeInteger(r.stake) && r.stake >= 0 && Number.isSafeInteger(r.payout) && r.payout >= 0)
}

// A settled round stays closed even if the device clock moves backwards.
export function bettingOpen(game: Game, now: number) {
  return !game.settled && phaseAt(game, now) === 'betting' && now < game.startedAt + BET_CLOSE_MS
}

// Saved play: one wallet shared by every cup, and each cup's own rounds.
type Rounds = Omit<Game, 'version' | 'cup' | 'balance'>
export interface Store { version: 3; balance: number; cups: Partial<Record<CupId, Rounds>> }
export function createStore(): Store { return { version: 3, balance: 10_000, cups: {} } }
// A cup starts its first round the first time it is opened.
export function gameOf(store: Store, cup: CupId, now: number): Game {
  const rounds = store.cups[cup]
  return rounds ? { version: 3, cup, balance: store.balance, ...rounds } : { ...createGame(now, cup), balance: store.balance }
}
export function withGame(store: Store, game: Game): Store {
  const { version: _version, cup, balance, ...rounds } = game
  return { ...store, balance, cups: { ...store.cups, [cup]: rounds } }
}
// Every cup settles into the one wallet, including cups left open elsewhere.
export function advanceStore(store: Store, now: number): Store {
  return (Object.keys(store.cups) as CupId[]).reduce((next, cup) => withGame(next, advance(gameOf(next, cup, now), now)), store)
}
export function isStore(value: unknown): value is Store {
  if (!value || typeof value !== 'object') return false
  const s = value as Store
  return s.version === 3 && Number.isSafeInteger(s.balance) && s.balance >= 0 && !!s.cups && typeof s.cups === 'object'
    && Object.entries(s.cups).every(([cup, rounds]) => isCup(cup) && isGame({ ...rounds, version: 3, cup, balance: s.balance }))
}
// Saves from before the cups were split: one Sunny game holding the wallet.
export function storeFromSunnySave(value: unknown): Store | undefined {
  if (!value || typeof value !== 'object' || (value as { version?: unknown }).version !== 2) return undefined
  const game = { ...(value as object), version: 3, cup: 'sunny' }
  return isGame(game) ? withGame(createStore(), game) : undefined
}

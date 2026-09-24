export const BET_CLOSE_MS = 48_000
export const BET_MS = 60_000
export const RACE_MS = 50_000
export const RESULT_MS = 10_000
export const ROUND_MS = BET_MS + RACE_MS + RESULT_MS
export const HORSES = [
  { id: 1, name: '赤焰疾風', en: 'RUBY DASH', color: '#e55a53' },
  { id: 2, name: '綠野旋律', en: 'GREEN MELODY', color: '#7da567' },
  { id: 3, name: '日光漫步', en: 'SUNNY STEPS', color: '#e6b73e' },
  { id: 4, name: '紫羅蘭夢', en: 'VIOLET DREAM', color: '#aa8ac7' },
  { id: 5, name: '橘子汽水', en: 'ORANGE POP', color: '#e89950' },
  { id: 6, name: '莓果甜心', en: 'BERRY HEART', color: '#d77bac' },
  { id: 7, name: '晴空之翼', en: 'BLUE BLAZE', color: '#6dbbcc' },
  { id: 8, name: '午夜星辰', en: 'MIDNIGHT STAR', color: '#6686d0' },
] as const
export type Phase = 'betting' | 'racing' | 'result'
export type Pick = `horse:${number}` | 'odd' | 'even' | 'small' | 'big'
export interface Bet { id: string; pick: Pick; amount: number }
export interface Result { round: number; winner: number; order: number[]; stake: number; payout: number }
export interface Game { version: 2; seed: number; round: number; startedAt: number; balance: number; bets: Bet[]; settled: boolean; history: Result[] }
export function randomSeed() { return crypto.getRandomValues(new Uint32Array(1))[0] }
export function createGame(now: number, seed = randomSeed()): Game {
  return { version: 2, seed, round: 1, startedAt: now, balance: 10_000, bets: [], settled: false, history: [] }
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
export function raceOrder(seed: number, round: number): number[] {
  const random = rng((seed ^ Math.imul(round, 2654435761)) >>> 0)
  const order = HORSES.map(h => Number(h.id))
  for (let i = order.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1)); [order[i], order[j]] = [order[j], order[i]]
  }
  return order
}
export function odds(pick: Pick) { return pick.startsWith('horse:') ? 7.6 : 1.9 }
export function validPick(value: unknown): value is Pick {
  return typeof value === 'string' && (/^horse:[1-8]$/.test(value) || ['odd', 'even', 'small', 'big'].includes(value))
}
export function pickLabel(pick: Pick) {
  if (pick.startsWith('horse:')) { const id = Number(pick.split(':')[1]); return `${id} 號・${HORSES[id - 1].name}` }
  return { odd: '冠軍馬號・單', even: '冠軍馬號・雙', small: '冠軍馬號・小', big: '冠軍馬號・大' }[pick as 'odd' | 'even' | 'small' | 'big']
}
export function wins(pick: Pick, winner: number) {
  if (pick.startsWith('horse:')) return Number(pick.split(':')[1]) === winner
  return pick === 'odd' ? winner % 2 === 1 : pick === 'even' ? winner % 2 === 0 : pick === 'small' ? winner <= 4 : winner >= 5
}
export function payoutFor(bets: Bet[], winner: number) {
  return bets.reduce((sum, bet) => sum + (wins(bet.pick, winner) ? Math.round(bet.amount * odds(bet.pick)) : 0), 0)
}
function settle(game: Game): Game {
  if (game.settled) return game
  const order = raceOrder(game.seed, game.round)
  const payout = payoutFor(game.bets, order[0])
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
  if (!validPick(pick) || !Number.isSafeInteger(amount) || amount < 10 || amount > 10_000 || amount % 10 !== 0) return { game: current, error: '投注金額須為 10–10,000，且為 10 的倍數。' }
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
export function racePositions(seed: number, round: number, seconds: number) {
  const order = raceOrder(seed, round)
  return HORSES.map(h => {
    const rank = order.indexOf(h.id)
    const finish = 44.5 + rank * 0.65
    const t = Math.max(0, Math.min(1, seconds / finish))
    const wave = Math.sin(t * Math.PI * 4 + h.id * 1.7) * 0.025 * Math.sin(t * Math.PI)
    return Math.max(0, Math.min(1, t + wave))
  })
}
export function cameraShot(phase: Phase, seconds: number) {
  if (phase === 'betting') return { id: 0, label: '賽前巡禮' }
  if (phase === 'result') return { id: 4, label: '前三名頒獎' }
  if (seconds < 7) return { id: 1, label: '起跑鏡頭' }
  if (seconds < 24) return { id: 2, label: '側面追拍' }
  if (seconds < 37) return { id: 3, label: '彎道追逐' }
  return { id: 5, label: seconds < 39.5 ? '終點衝刺' : seconds < 42.8 ? '衝刺特寫' : seconds < 45.8 ? '衝線時刻' : seconds < 48.75 ? '衝刺加速' : '勝出特寫' }
}
export function isGame(value: unknown): value is Game {
  if (!value || typeof value !== 'object') return false
  const g = value as Game
  return g.version === 2 && Number.isSafeInteger(g.seed) && Number.isSafeInteger(g.round) && g.round > 0 && Number.isFinite(g.startedAt) && g.startedAt > 0 && Number.isSafeInteger(g.balance) && g.balance >= 0 && typeof g.settled === 'boolean' && Array.isArray(g.bets) && g.bets.every(b => typeof b.id === 'string' && validPick(b.pick) && Number.isSafeInteger(b.amount) && b.amount >= 10) && Array.isArray(g.history) && g.history.every(r => Number.isSafeInteger(r.round) && Number.isSafeInteger(r.winner) && r.winner >= 1 && r.winner <= 8 && Array.isArray(r.order) && r.order.length === 8 && new Set(r.order).size === 8 && r.order.every(n => Number.isSafeInteger(n) && n >= 1 && n <= 8) && Number.isSafeInteger(r.stake) && r.stake >= 0 && Number.isSafeInteger(r.payout) && r.payout >= 0)
}

export function bettingOpen(game: Game, now: number) {
  return phaseAt(game, now) === 'betting' && now < game.startedAt + BET_CLOSE_MS
}

import { buildRacePlan, makeRacePlan, planProgress, type RacePlan } from './raceModel'
import { scriptOf } from './raceScript'
import { HOME_TURN } from './presentation'

export const BET_CLOSE_MS = 48_000
export const BET_MS = 60_000
export const RACE_MS = 50_000
export const RESULT_MS = 10_000
export const ROUND_MS = BET_MS + RACE_MS + RESULT_MS
// The whole stable; a cup runs the first `field` of them. Local names are in src/locales.
export const HORSES = [
  { id: 1, en: 'RUBY DASH', color: '#e55a53' },
  { id: 2, en: 'GREEN MELODY', color: '#7da567' },
  { id: 3, en: 'SUNNY STEPS', color: '#e6b73e' },
  { id: 4, en: 'VIOLET DREAM', color: '#aa8ac7' },
  { id: 5, en: 'ORANGE POP', color: '#e89950' },
  { id: 6, en: 'BERRY HEART', color: '#d77bac' },
  { id: 7, en: 'BLUE BLAZE', color: '#6dbbcc' },
  { id: 8, en: 'MIDNIGHT STAR', color: '#6686d0' },
  { id: 9, en: 'MINT BREEZE', color: '#2f9a88' },
  { id: 10, en: 'COCOA THUNDER', color: '#9b6b4b' },
  { id: 11, en: 'SILVER MOON', color: '#8f9aa6' },
  { id: 12, en: 'ROSE CROWN', color: '#b8475e' },
] as const
export const CUPS = {
  sunny: { id: 'sunny', en: 'SUNNY CUP', field: 8 },
  thunder: { id: 'thunder', en: 'THUNDER CUP', field: 10 },
  royal: { id: 'royal', en: 'ROYAL CUP', field: 12 },
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
  // A script names the first finishers; the rest keep the drawn order.
  const scripted = scriptOf(seed, round, field)?.script.order
  return scripted ? [...scripted, ...order.filter(id => !scripted.includes(id))] : order
}
// Every market returns 95%: a winner pays the field size, a half of the field pays 2.
export function odds(pick: Pick, field: number) { return pick.startsWith('horse:') ? Math.round(field * 95) / 100 : 1.9 }
export function validPick(value: unknown, field: number): value is Pick {
  if (typeof value !== 'string') return false
  const horse = /^horse:(\d+)$/.exec(value)
  return horse ? Number(horse[1]) >= 1 && Number(horse[1]) <= field : ['odd', 'even', 'small', 'big'].includes(value)
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
export type BetError = 'closed' | 'amount' | 'balance' | 'limit'
export function placeBet(game: Game, pick: Pick, amount: number, now: number): { game: Game; error?: BetError } {
  const current = advance(game, now)
  if (!bettingOpen(current, now)) return { game: current, error: 'closed' }
  if (!validPick(pick, fieldOf(current)) || !Number.isSafeInteger(amount) || amount < 10 || amount > 10_000 || amount % 10 !== 0) return { game: current, error: 'amount' }
  if (amount > current.balance) return { game: current, error: 'balance' }
  if (current.bets.length >= 100) return { game: current, error: 'limit' }
  return { game: { ...current, balance: current.balance - amount, bets: [...current.bets, { id: crypto.randomUUID(), pick, amount }] } }
}
export function cancelBet(game: Game, id: string, now: number): Game {
  const current = advance(game, now)
  if (!bettingOpen(current, now)) return current
  const bet = current.bets.find(b => b.id === id)
  return bet ? { ...current, balance: current.balance + bet.amount, bets: current.bets.filter(b => b.id !== id) } : current
}
// Smooth, monotonic distances. The finish order is exactly the settlement order.
// One plan per round, shared with Godot; see raceModel.ts. A scripted round is
// keyed by its script too, and what it could not honour is reported once.
const plans = new Map<string, RacePlan>()
export function racePlan(seed: number, round: number, field: number): RacePlan {
  const key = `${seed}:${round}:${field}:${scriptOf(seed, round, field)?.rev ?? ''}`
  let plan = plans.get(key)
  if (!plan) {
    const built = planRound(seed, round, field)
    if (built.dropped.length) console.warn(`Race ${round}: the script could not keep ${built.dropped.join(', ')}`)
    plan = built.plan
    plans.set(key, plan)
    if (plans.size > 4) plans.delete(plans.keys().next().value!)
  }
  return plan
}
export function planRound(seed: number, round: number, field: number) {
  const random = () => rng((seed ^ Math.imul(round, 2654435761) ^ 0x5bd1e995) >>> 0)
  const entry = scriptOf(seed, round, field)
  return entry ? buildRacePlan(raceOrder(seed, round, field), random, entry.script) : { plan: makeRacePlan(raceOrder(seed, round, field), random()), dropped: [] }
}
export function racePositions(seed: number, round: number, seconds: number, field: number) {
  const plan = racePlan(seed, round, field)
  return Array.from({ length: field }, (_, index) => Math.max(0, Math.min(1, planProgress(plan, index, seconds))))
}
// The Godot camera cut for this moment.
export function cameraShot(phase: Phase, seconds: number) {
  if (phase === 'betting') return 0
  if (phase === 'result') return 4
  return seconds < 7 ? 1 : seconds < 24 ? 2 : seconds < HOME_TURN ? 3 : 5
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
// The shared schedule: a cup's round N opens for betting at epoch + (N − 1) rounds,
// and every player runs the cup's one seed, so all see the same race at once.
// Rounds count up from the epoch; the page shows the day's race number instead.
export type CupClock = { epoch: number; seed: number }
export const RACES_PER_DAY = 86_400_000 / ROUND_MS
export const raceNumber = (round: number) => (round - 1) % RACES_PER_DAY + 1
export const roundAt = (clock: CupClock, now: number) => Math.max(1, Math.floor((now - clock.epoch) / ROUND_MS) + 1)
export const startOf = (clock: CupClock, round: number) => clock.epoch + (round - 1) * ROUND_MS
// Brings every cup onto its schedule. A cup off schedule (an older save, or a
// schedule that moved) settles what it can by its old clock, refunds a race that
// will now never be shown, and starts afresh on the current round.
export function alignStore(store: Store, now: number, clocks: Record<CupId, CupClock>): Store {
  return (Object.keys(CUPS) as CupId[]).reduce((next, cup) => {
    const clock = clocks[cup], rounds = next.cups[cup]
    if (rounds && rounds.seed === clock.seed && rounds.startedAt === startOf(clock, rounds.round)) return next
    let balance = next.balance
    if (rounds) {
      const old = advance(gameOf(next, cup, now), now)
      balance = old.balance + (old.settled ? 0 : old.bets.reduce((sum, bet) => sum + bet.amount, 0))
    }
    const round = roundAt(clock, now)
    return { ...next, balance, cups: { ...next.cups, [cup]: { seed: clock.seed, round, startedAt: startOf(clock, round), bets: [], settled: false, history: [] } } }
  }, store)
}
// The latest finished rounds before `round`, the same for everyone, newest first.
export function recentResults(seed: number, round: number, field: number, count: number): Result[] {
  return Array.from({ length: Math.min(count, round - 1) }, (_, i) => {
    const order = raceOrder(seed, round - 1 - i, field)
    return { round: round - 1 - i, winner: order[0], order, stake: 0, payout: 0 }
  })
}

// Saves from before the cups were split: one Sunny game holding the wallet.
export function storeFromSunnySave(value: unknown): Store | undefined {
  if (!value || typeof value !== 'object' || (value as { version?: unknown }).version !== 2) return undefined
  const game = { ...(value as object), version: 3, cup: 'sunny' }
  return isGame(game) ? withGame(createStore(), game) : undefined
}

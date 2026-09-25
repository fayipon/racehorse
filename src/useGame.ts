import { useCallback, useEffect, useState } from 'react'
import { advance, advanceStore, alignStore, BET_CLOSE_MS, cancelBet, createStore, fieldOf, gameOf, isStore, placeBet, storeFromSunnySave, withGame, type BetError, type CupId, type Game, type Pick, type Store } from './game'
import { lockRound } from './raceScript'
import { currentClocks, refreshSchedule, serverNow } from './schedule'
const KEY = 'racehorse-v3'
const SUNNY_SAVE = 'sunny-cup-v2'
let memory: Store | undefined
export function read(): Store {
  try {
    const data: unknown = JSON.parse(localStorage.getItem(KEY) || 'null')
    if (isStore(data)) return data
    const older = storeFromSunnySave(JSON.parse(localStorage.getItem(SUNNY_SAVE) || 'null'))
    if (older) return older
  } catch { /* Private browsing can disable storage. */ }
  return memory ??= createStore()
}
// Every cup on the shared schedule, settled up to `now`.
const current = (now: number) => advanceStore(alignStore(read(), now, currentClocks()), now)
function save(store: Store) { memory = store; try { localStorage.setItem(KEY, JSON.stringify(store)) } catch { /* In-memory play still works. */ } }
export function useGame(cup: CupId) {
  const [game, setGame] = useState(() => { const now = serverNow(); return advance(gameOf(current(now), cup, now), now) })
  const [now, setNow] = useState(serverNow)
  // Each change settles every cup into the shared wallet, then applies to this cup.
  const transact = useCallback(async (fn: (g: Game) => Game, whole: (s: Store) => Store = s => s) => {
    const run = () => {
      const time = serverNow()
      const store = whole(current(time))
      const next = fn(advance(gameOf(store, cup, time), time))
      // Once betting closes here, a newer races.json no longer changes this race.
      if (time >= next.startedAt + BET_CLOSE_MS) lockRound(next.seed, fieldOf(next), next.round)
      save(withGame(store, next)); setGame(next); setNow(time)
    }
    if (navigator.locks) await navigator.locks.request(KEY, run)
    else run()
  }, [cup])
  useEffect(() => {
    const tick = () => { void transact(g => g) }
    // Background tabs are throttled: on return, catch up with the file first.
    const resume = () => { if (!document.hidden) void refreshSchedule().then(tick) }
    tick()
    const timer = window.setInterval(tick, 250)
    window.addEventListener('storage', tick)
    document.addEventListener('visibilitychange', resume)
    return () => { clearInterval(timer); window.removeEventListener('storage', tick); document.removeEventListener('visibilitychange', resume) }
  }, [transact])
  const bet = async (pick: Pick, amount: number) => {
    let error: BetError | undefined
    await transact(g => { const result = placeBet(g, pick, amount, serverNow()); error = result.error; return result.game })
    return error
  }
  const cancel = (id: string) => transact(g => cancelBet(g, id, serverNow()))
  // Free chips only once nothing is riding on any cup.
  const refill = () => transact(g => g, s => s.balance < 10 && Object.values(s.cups).every(r => r.settled || r.bets.length === 0) ? { ...s, balance: 10_000 } : s)
  return { game, now, bet, cancel, refill }
}

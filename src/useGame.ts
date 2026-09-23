import { useCallback, useEffect, useState } from 'react'
import { advance, cancelBet, createGame, isGame, placeBet, type Game, type Pick } from './game'
const KEY = 'sunny-cup-v2'
let memory: Game | undefined
function read() {
  try { const data: unknown = JSON.parse(localStorage.getItem(KEY) || 'null'); if (isGame(data)) return data } catch { /* Private browsing can disable storage. */ }
  return memory ??= createGame(Date.now())
}
function save(game: Game) { memory = game; try { localStorage.setItem(KEY, JSON.stringify(game)) } catch { /* In-memory play still works. */ } }
export function useGame() {
  const [game, setGame] = useState(() => advance(read(), Date.now()))
  const [now, setNow] = useState(Date.now)
  const transact = useCallback(async (fn: (g: Game) => Game) => {
    const run = () => { const current = read(); const next = fn(current); save(next); setGame(next); setNow(Date.now()) }
    if (navigator.locks) await navigator.locks.request(KEY, run)
    else run()
  }, [])
  useEffect(() => {
    const tick = () => { void transact(g => advance(g, Date.now())) }
    tick()
    const timer = window.setInterval(tick, 250)
    window.addEventListener('storage', tick)
    document.addEventListener('visibilitychange', tick)
    return () => { clearInterval(timer); window.removeEventListener('storage', tick); document.removeEventListener('visibilitychange', tick) }
  }, [transact])
  const bet = async (pick: Pick, amount: number) => {
    let error: string | undefined
    await transact(g => { const result = placeBet(g, pick, amount, Date.now()); error = result.error; return result.game })
    return error
  }
  const cancel = (id: string) => transact(g => cancelBet(g, id, Date.now()))
  const refill = () => transact(g => g.balance < 10 && g.bets.length === 0 ? { ...g, balance: 10_000 } : g)
  return { game, now, bet, cancel, refill }
}

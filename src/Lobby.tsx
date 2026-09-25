import { useEffect, useState, type CSSProperties } from 'react'
import { ArrowUpRight, Coins } from 'lucide-react'
import { advanceStore, BET_CLOSE_MS, bettingOpen, CUPS, gameOf, HORSES, odds, phaseAt, type CupId } from './game'
import { read } from './useGame'

const fmt = (n: number) => n.toLocaleString('en-US')
const clock = (s: number) => `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`
// A few runners from each field for the card art.
const FACES: Record<CupId, number[]> = { sunny: [3, 1, 7], thunder: [10, 8, 4], royal: [12, 11, 9] }

// The lobby only reads the saved wallet and schedules; no race loads until a cup is opened.
export default function Lobby() {
  const [now, setNow] = useState(Date.now)
  useEffect(() => { const timer = setInterval(() => setNow(Date.now()), 1000); return () => clearInterval(timer) }, [])
  useEffect(() => { document.title = '賽事大廳・小馬競速俱樂部' }, [])
  const store = advanceStore(read(), now)
  const status = (id: CupId) => {
    if (!store.cups[id]) return '進場即開賽'
    const game = gameOf(store, id, now)
    const phase = phaseAt(game, now)
    if (phase === 'racing') return '比賽進行中'
    if (phase === 'result') return '賽果結算中'
    return bettingOpen(game, now) ? `開放投注・${clock(Math.max(0, Math.ceil((game.startedAt + BET_CLOSE_MS - now) / 1000)))}` : '集合中・即將開跑'
  }
  return <>
    <header className="app-header"><a className="brand" href={import.meta.env.BASE_URL} aria-label="小馬競速俱樂部 大廳"><span className="brand-icon">♞</span><span>小馬競速<span className="brand-light">俱樂部</span><small>賽事大廳</small></span></a><div className="header-wallet"><span className="coin-icon"><Coins size={17} /></span><div><small>我的籌碼</small><strong>{fmt(store.balance)}</strong></div><span className="practice-label">練習模式</span></div></header>
    <main className="app-main lobby">
      <div className="page-heading"><div><span className="overline">CHOOSE YOUR RACE</span><h1>今天想看哪一場<span>？</span></h1></div><p><span className="online-dot" />三種賽事同時開放 <span className="divider">/</span> 籌碼共用</p></div>
      <ul className="cup-list">{(Object.keys(CUPS) as CupId[]).map(id => {
        const cup = CUPS[id]
        return <li key={id}><a className={`cup-card cup-${id}`} href={`${import.meta.env.BASE_URL}${id}/`}>
          <div className="cup-faces" aria-hidden="true">{FACES[id].map(face => <img key={face} src={`${import.meta.env.BASE_URL}assets/horse-head-${face}.webp`} alt="" style={{ '--horse': HORSES[face - 1].color } as CSSProperties} />)}</div>
          <div className="cup-info"><span className="cup-en">{cup.en}</span><h2>{cup.name}</h2><p>{cup.field} 匹小馬 · 冠軍賠率 × {odds('horse:1', cup.field).toFixed(2)} · 每 2 分鐘一場</p><span className="cup-status"><i />{status(id)}</span></div>
          <span className="cup-enter">進入賽場<ArrowUpRight size={16} /></span>
        </a></li>
      })}</ul>
    </main>
  </>
}

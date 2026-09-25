import { useEffect, useState, type CSSProperties } from 'react'
import { ArrowUpRight, ChevronDown, Coins, Languages } from 'lucide-react'
import { advanceStore, alignStore, BET_CLOSE_MS, bettingOpen, CUPS, gameOf, HORSES, odds, phaseAt, type CupId } from './game'
import { read } from './useGame'
import { currentClocks, serverNow } from './schedule'
import { isLocale, LOCALE_NAMES, LOCALE_SHORT, LOCALES, useI18n } from './i18n'

const clock = (s: number) => `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`
// A few runners from each field for the card art.
const FACES: Record<CupId, number[]> = { sunny: [3, 1, 7], thunder: [10, 8, 4], royal: [12, 11, 9] }

// The lobby only reads the saved wallet and the shared schedule; no race loads until a cup is opened.
export default function Lobby() {
  const { m, n, price, locale, setLocale } = useI18n()
  const [now, setNow] = useState(serverNow)
  useEffect(() => { const timer = setInterval(() => setNow(serverNow()), 1000); return () => clearInterval(timer) }, [])
  useEffect(() => { document.title = m.lobby.title }, [m])
  const store = advanceStore(alignStore(read(), now, currentClocks()), now)
  const status = (id: CupId) => {
    const game = gameOf(store, id, now)
    const phase = phaseAt(game, now)
    if (phase === 'racing') return m.lobby.racing
    if (phase === 'result') return m.lobby.result
    return bettingOpen(game, now) ? m.lobby.open(clock(Math.max(0, Math.ceil((game.startedAt + BET_CLOSE_MS - now) / 1000)))) : m.lobby.closing
  }
  return <>
    <header className="app-header lobby-header"><a className="brand" href={import.meta.env.BASE_URL} aria-label={m.lobby.brandLabel}><span className="brand-icon">♞</span><span>{m.lobby.brand[0]}<span className="brand-light">{m.lobby.brand[1]}</span><small>{m.lobby.brandNote}</small></span></a>
      {/* The select sits invisibly over its label, so phones can show a short name while the list shows full ones. */}
      <label className="locale-picker"><Languages size={16} aria-hidden="true" /><span className="locale-name" aria-hidden="true">{LOCALE_NAMES[locale]}</span><span className="locale-short" aria-hidden="true">{LOCALE_SHORT[locale]}</span><ChevronDown size={14} aria-hidden="true" /><select aria-label={m.lobby.language} value={locale} onChange={event => { if (isLocale(event.target.value)) void setLocale(event.target.value) }}>{LOCALES.map(code => <option key={code} value={code} lang={code}>{LOCALE_NAMES[code]}</option>)}</select></label>
      <div className="header-wallet"><span className="coin-icon"><Coins size={17} /></span><div><small>{m.header.wallet}</small><strong>{n(store.balance)}</strong></div><span className="practice-label">{m.header.practice}</span></div></header>
    <main className="app-main lobby">
      <div className="page-heading"><div><span className="overline">CHOOSE YOUR RACE</span><h1>{m.lobby.heading[0]}<span>{m.lobby.heading[1]}</span></h1></div><p><span className="online-dot" />{m.lobby.status} <span className="divider">/</span> {m.lobby.shared}</p></div>
      <ul className="cup-list">{(Object.keys(CUPS) as CupId[]).map(id => {
        const cup = CUPS[id]
        return <li key={id}><a className={`cup-card cup-${id}`} href={`${import.meta.env.BASE_URL}${id}/`}>
          <div className="cup-faces" aria-hidden="true">{FACES[id].map(face => <img key={face} src={`${import.meta.env.BASE_URL}assets/horse-head-${face}.webp`} alt="" style={{ '--horse': HORSES[face - 1].color } as CSSProperties} />)}</div>
          <div className="cup-info"><span className="cup-en">{cup.en}</span><h2>{m.cups[id].name}</h2><p>{m.lobby.cupInfo(cup.field, price(odds('horse:1', cup.field)))}</p><span className="cup-status"><i />{status(id)}</span></div>
          <span className="cup-enter">{m.lobby.enter}<ArrowUpRight size={16} /></span>
        </a></li>
      })}</ul>
    </main>
  </>
}

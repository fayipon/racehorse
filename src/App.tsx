import { useEffect, useMemo, useRef, useState, useSyncExternalStore, type CSSProperties } from 'react'
import { ArrowDownLeft, ArrowUpRight, Check, ChevronDown, ChevronRight, ChevronUp, CircleHelp, Clock3, Coins, Flag, History, LockKeyhole, Maximize2, Minimize2, Radio, Trophy, Volume2, VolumeX, X } from 'lucide-react'
import { BET_CLOSE_MS, bettingOpen, BET_MS, CUPS, HORSES, cameraShot, countdown, fieldOf, odds, phaseAt, raceNumber, raceOrder, racePlan, racePositions, recentResults, wins, type CupId, type Game, type Pick } from './game'
import { useGame } from './useGame'
import { useCrowd } from './useCrowd'
import { useCommentary } from './useCommentary'
import { RaceChat, StageChatCompose, StageChatFeed } from './RaceChat'
import { useRaceChat } from './useRaceChat'
import { PodiumResults } from './PodiumResults'
import { COURSE, coursePoint, makeParadePlan, paradePositions } from './course'
import { racePresentationTime } from './presentation'
import { gameSource } from './mirror'
import { useI18n } from './i18n'

const clock = (s: number) => `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`
// Matches the stylesheet's phone breakpoint, where the chat moves onto the stage.
const phoneQuery = '(max-width: 580px)'
const onPhoneChange = (update: () => void) => { const query = matchMedia(phoneQuery); query.addEventListener('change', update); return () => query.removeEventListener('change', update) }
const usePhone = () => useSyncExternalStore(onPhoneChange, () => matchMedia(phoneQuery).matches)
function HorsePortrait({ id, className = '' }: { id: number; className?: string }) {
  return <span aria-hidden="true" className={`horse-portrait ${className}`} style={{ backgroundImage: `url('${import.meta.env.BASE_URL}assets/horse-${id}.png')` }} />
}
function HorseNumber({ id, small = false }: { id: number; small?: boolean }) {
  return <span className={`horse-number ${small ? 'small' : ''}`} style={{ '--horse': HORSES[id - 1].color } as CSSProperties}>{id}</span>
}
function MiniTrack({ positions }: { positions: number[] }) {
  const { m } = useI18n()
  const radius = COURSE.innerRadius + COURSE.trackWidth / 2
  const half = COURSE.halfStraight
  return <svg className="minitrack" viewBox="-67 -41 134 82" aria-label={m.stage.minimap(positions.length)}>
    <rect x={-half-radius} y={-radius} width={2*(half+radius)} height={2*radius} rx={radius} fill="none" stroke="#ffffff30" strokeWidth={COURSE.trackWidth} />
    <rect x={-half-radius} y={-radius} width={2*(half+radius)} height={2*radius} rx={radius} fill="none" stroke="#ffffff80" strokeWidth=".7" />
    {positions.map((p,i) => { const point = coursePoint(p,i,positions.length); return <circle key={i} cx={point.x} cy={point.z} r="2.7" fill={HORSES[i].color} stroke="white" strokeWidth=".65" /> })}
    <path d={`M-1.5 ${COURSE.innerRadius-1}v${COURSE.trackWidth+2}m3 0v-${COURSE.trackWidth+2}`} stroke="white" strokeWidth="1" />
  </svg>
}
export function RaceStage({ game, now, muted, paused = false, children, notification, betsPanel, celebration, chatFeed, expanded = false, onCollapse, onReady }: { game: Game; now: number; muted: boolean; paused?: boolean; children?: React.ReactNode; notification?: React.ReactNode; betsPanel?: React.ReactNode; celebration?: React.ReactNode; chatFeed?: React.ReactNode; expanded?: boolean; onCollapse?: () => void; onReady: (ready: boolean) => void }) {
  const { m, n, horse, horseAlias } = useI18n()
  const frame = useRef<HTMLIFrameElement>(null)
  const shell = useRef<HTMLDivElement>(null)
  const [ready, setReady] = useState(false)
  const [failed, setFailed] = useState(false)
  const [progress, setProgress] = useState(0)
  // Download, scene construction, then the first rendered frames.
  const [building, setBuilding] = useState(0)
  const [warmup, setWarmup] = useState(0)
  const loaded = Math.min(100, progress * .7 + building * 20 + warmup * 10)
  const [loadAttempt, setLoadAttempt] = useState(0)
  const [finishRound, setFinishRound] = useState(0)
  // Off screen, Godot idles at a few frames a second to spare the battery.
  const [onScreen, setOnScreen] = useState(true)
  useEffect(() => {
    const element = shell.current
    if (!element || !('IntersectionObserver' in window)) return
    const observer = new IntersectionObserver(([entry]) => setOnScreen(entry.isIntersecting), { threshold: 0.05 })
    observer.observe(element)
    return () => observer.disconnect()
  }, [])
  // Wide screens lay the HUD out at 1000px and zoom it to the stage; see --ui-scale in index.css.
  useEffect(() => {
    const element = shell.current
    if (!element) return
    const observer = new ResizeObserver(([entry]) => element.style.setProperty('--ui-scale', String(Math.min(1.6, Math.max(.72, entry.contentRect.width / 1000)))))
    observer.observe(element)
    return () => observer.disconnect()
  }, [])
  const field = fieldOf(game)
  const cupName = m.cups[game.cup].name
  const cupAlias = cupName.toUpperCase() === CUPS[game.cup].en ? '' : `${cupName} · `
  const phase = phaseAt(game, now)
  const seconds = Math.max(0, (now - game.startedAt - BET_MS) / 1000)
  const visualSeconds = racePresentationTime(seconds)
  const shot = cameraShot(phase, seconds)
  const positions = racePositions(game.seed, game.round, visualSeconds, field)
  const order = raceOrder(game.seed, game.round, field)
  const plan = racePlan(game.seed, game.round, field)
  const paradePlan = useMemo(()=>makeParadePlan(game.seed,game.round,CUPS[game.cup].field),[game.seed,game.round,game.cup])
  const ranking = HORSES.slice(0, field).sort((a, b) => positions[b.id - 1] - positions[a.id - 1] || order.indexOf(a.id) - order.indexOf(b.id))
  const remaining = countdown(game, now)
  const assembling = phase === 'betting' && !bettingOpen(game, now)
  const startCue = phase === 'betting' && remaining <= 7 ? (remaining > 5 ? 'READY' : String(remaining)) : phase === 'racing' && seconds < 1.8 ? 'GO!' : null
  const finishing = phase === 'racing' && (finishRound === raceNumber(game.round) || visualSeconds >= 44.6)
  const cinematic = phase === 'racing' && seconds >= 39.5
  // The special-move banner lands with the crossing freeze, then yields to the announcement.
  const winnerCutIn = phase === 'racing' && (finishing || seconds >= 44.6) && seconds < 46.4
  useEffect(() => {
    const listener = (event: MessageEvent) => {
      if (event.origin !== location.origin || event.source !== frame.current?.contentWindow) return
      if (event.data?.type === 'game-visible') { setReady(true); setFailed(false); onReady(true) }
      if (event.data?.type === 'godot-progress' && Number.isFinite(event.data.progress)) { setProgress(Math.max(0, Math.min(100, event.data.progress))); setFailed(false) }
      if (event.data?.type === 'godot-build' && Number.isFinite(event.data.step) && Number.isFinite(event.data.total) && event.data.total > 0) { setProgress(100); setBuilding(Math.max(0, Math.min(1, event.data.step / event.data.total))); setFailed(false) }
      if (event.data?.type === 'godot-warmup' && Number.isFinite(event.data.step) && event.data.total > 0) { setProgress(100); setBuilding(1); setWarmup(Math.max(0, Math.min(1, event.data.step / event.data.total))); setFailed(false) }
      if (event.data?.type === 'godot-error') { setFailed(true); setReady(false); onReady(false) }
      if (event.data?.type === 'race-finish' && Number.isSafeInteger(event.data.round)) setFinishRound(event.data.round)
    }
    window.addEventListener('message', listener)
    return () => window.removeEventListener('message', listener)
  }, [onReady])
  // Slow links can take minutes, so only a load that stops moving counts as failed.
  useEffect(() => {
    if (ready || failed) return
    const timeout = setTimeout(() => setFailed(true), 60000)
    return () => clearTimeout(timeout)
  }, [ready, failed, loadAttempt, progress, building, warmup])
  useEffect(() => {
    frame.current?.contentWindow?.postMessage({ type: 'race-state', phase, seconds, bettingElapsed: Math.max(0, (now-game.startedAt)/1000), positions, paradePlan, finishTimes: plan.finishTimes, racePlan: { winner: plan.winner, ease: plan.ease, cruise: plan.cruise, knots: plan.knots }, winner: order[0], camera: shot, round: raceNumber(game.round), muted, paused, visible: onScreen }, location.origin)
  }, [game.round, game.startedAt, muted, now, order, phase, positions, seconds, shot, ready, paradePlan, plan, paused, onScreen])
  const winnerAlias = horseAlias(order[0])
  return <div ref={shell} className={`race-stage phase-${phase} ${!ready ? 'is-loading' : ''} ${assembling ? 'is-assembling' : ''} ${finishing ? 'has-finished' : ''} ${cinematic ? 'is-cinematic' : ''} ${winnerCutIn ? 'is-cut-in' : ''} ${expanded ? 'is-expanded' : ''}`} style={{ '--runners': field, '--half': field / 2 } as CSSProperties}>
    {!ready && <div className="engine-loading" role="status" aria-live="polite"><div className="loading-emblem" aria-hidden="true">♞</div><span className="loading-brand">{CUPS[game.cup].en}</span><h2>{failed ? m.loading.failed : m.loading.preparing(cupName)}</h2><p>{failed ? m.loading.failedHint : building >= 1 ? m.loading.warmup : progress >= 100 ? m.loading.build : m.loading.download}</p><div className="loading-progress" role="progressbar" aria-label={m.loading.progress} aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.floor(loaded)}><i style={{ width: `${loaded}%` }} /></div><strong>{Math.floor(loaded)}<small>%</small></strong><small>{m.loading.size}</small>{failed && <button onClick={() => { setFailed(false); setProgress(0); setBuilding(0); setWarmup(0); setReady(false); onReady(false); setLoadAttempt(value => value + 1); if (frame.current) frame.current.src = gameSource(game.cup, field) }}>{m.loading.retry}</button>}</div>}

    <iframe tabIndex={ready ? 0 : -1} ref={frame} title={m.loading.frame} src={gameSource(game.cup, field)} allow="autoplay; fullscreen" className={ready ? 'ready' : ''} />
    <div className="stage-vignette" />
    {chatFeed}
    <div className="race-title"><div>RACE <em>{String(raceNumber(game.round)).padStart(2, '0')}</em></div><span /><p>{CUPS[game.cup].en}<small>{cupAlias}{m.stage.distance}</small></p></div>
    {phase === 'betting' && !assembling && <div className="betting-hero"><span className="hero-kicker">A LITTLE LUCK. A LOT OF HEART.</span><h2>{m.stage.heroTitle}</h2><p>{m.stage.heroText}</p><div className="countdown-pill"><Clock3 size={16} />{m.stage.countdown} <strong>{clock(Math.max(0, Math.ceil((game.startedAt + BET_CLOSE_MS - now) / 1000)))}</strong></div></div>}
    {assembling && !startCue && <div className="assembly-caption"><span>TO THE STARTING LINE</span><strong>{m.stage.assembling}</strong><small>{m.stage.assemblingNote}</small></div>}
    {startCue && <div className={`start-sequence ${startCue === 'GO!' ? 'is-go' : ''}`}>
      <div key={`${game.round}-${startCue}`} className="start-cue" role="status" aria-live="polite" aria-atomic="true">
        {startCue === 'GO!' && <span className="start-kicker">THE RACE IS ON</span>}
        <div className="start-number"><i aria-hidden="true" /><strong>{startCue}</strong></div>
        <b className="start-subtitle">{startCue === 'READY' ? m.stage.ready : startCue === 'GO!' ? m.stage.go : m.stage.counting}</b>
        <div className="start-lights" aria-hidden="true">{[5,4,3,2,1].map(n => <i key={n} className={startCue === 'GO!' || Number(startCue) <= n ? 'lit' : ''} />)}</div>      </div>
    </div>}
    {cinematic && <div className="finish-shot-bars" />}
    {winnerCutIn && <div key={`cut-in-${game.round}`} className="sprint-cut-in" aria-hidden="true" style={{ '--horse': HORSES[order[0] - 1].color } as CSSProperties}><div className="cut-in-band"><span className="cut-in-kicker">FIRST ACROSS THE LINE{m.stage.firstAcross && <b>{m.stage.firstAcross}</b>}</span><div className="cut-in-name"><HorseNumber id={order[0]} /><strong>{horse(order[0])}</strong>{winnerAlias && <em>{winnerAlias}</em>}<Trophy size={26} /></div></div></div>}
    {finishing && !winnerCutIn && <div key={`finish-${game.round}`} className="finish-sequence" aria-live="polite"><div className="finish-announcement"><span className="finish-kicker">FIRST ACROSS THE LINE{m.stage.firstAcross && ` · ${m.stage.firstAcross}`}</span><strong>{horse(order[0])}</strong><div><HorseNumber id={order[0]} /><span>{m.stage.champion}{winnerAlias && <small>{winnerAlias}</small>}</span><Trophy size={22} /></div></div></div>}
    {phase === 'result' && <PodiumResults key={`podium-${game.round}`} order={order} round={raceNumber(game.round)} />}
    <div className="stage-bottom">
      <div className="live-ranking"><small>{m.stage.ranking}</small><div className="ranking-list" key={game.round} role="list" aria-label={m.stage.ranking}>{ranking.map((h, i) => <div key={h.id} className={`ranking-row ${i < 3 ? 'is-podium' : ''}`} role="listitem" style={{ '--rank': i, '--rank-color': h.color, zIndex: field - i } as CSSProperties}><span className="ranking-place">{i + 1}</span><HorseNumber id={h.id} small /><b>{h.en}</b></div>)}</div></div>
      <div className="race-progress"><div><span>{phase === 'betting' ? m.stage.waiting : 'RACE PROGRESS'}</span><b>{phase === 'betting' ? '1200 M' : `${n(Math.round(Math.max(...positions) * 1200))} / 1200 M`}</b></div><div className="progress-rail"><span style={{ width: `${phase === 'betting' ? 0 : Math.max(...positions) * 100}%` }} /></div></div>
      <MiniTrack positions={phase === 'betting' ? paradePositions((now-game.startedAt)/1000,paradePlan) : positions} />
    </div>
    {ready && phase === 'betting' && !assembling && children}
    {celebration}
    {ready && phase === 'result' && betsPanel}
    {notification}
    <button className="fullscreen" aria-label={m.toolbar.exitFullscreen} onClick={() => { if (document.fullscreenElement) void document.exitFullscreen().catch(() => {}); else onCollapse?.() }}><Minimize2 size={16} /></button>
  </div>
}
function Dialog({ title, children, onClose }: { title: string; children: React.ReactNode; onClose: () => void }) {
  const { m } = useI18n()
  const ref = useRef<HTMLDialogElement>(null)
  useEffect(() => { ref.current?.showModal() }, [])
  return <dialog ref={ref} onCancel={onClose} onClick={e => { if (e.target === ref.current) onClose() }}><div className="dialog-head"><h2>{title}</h2><button className="icon-button" aria-label={m.dialog.close} onClick={onClose}><X size={20} /></button></div>{children}</dialog>
}
export default function App({ cup: cupId }: { cup: CupId }) {
  const { m, n, price, horse, locale } = useI18n()
  const cup = CUPS[cupId]
  const local = m.cups[cupId]
  const field = cup.field
  const [gameReady, setGameReady] = useState(false)
  const { game, now, bet, cancel, refill } = useGame(cupId)
  const chat = useRaceChat(game, now, m.chat)
  const phone = usePhone()
  const needsRefill = game.balance < 10 && game.bets.length === 0
  const [selected, setSelected] = useState<Pick | null>(null)
  const [amount, setAmount] = useState(100)
  const [message, setMessage] = useState('')
  const [pending, setPending] = useState(false)
  const [dockOpen, setDockOpen] = useState(true)
  // iPhone Safari only fullscreens video, so there the stage fills the viewport itself.
  const [expanded, setExpanded] = useState(false)
  const enterFullscreen = (stage: Element | null | undefined) => {
    if (stage?.requestFullscreen && document.fullscreenEnabled) void stage.requestFullscreen().catch(() => setExpanded(true))
    else setExpanded(true)
  }
  const [modal, setModal] = useState<'rules' | 'history' | null>(null)
  const [muted, setMuted] = useState(true)
  const crowd = useCrowd(game, now, gameReady && !muted)
  // One audio context, unlocked by the sound button, carries the crowd and the race caller.
  const audio = useRef<AudioContext | null>(null)
  const commentary = useCommentary(game, gameReady && !muted, crowd.duck, locale)
  const phase = phaseAt(game, now)
  const locked = !gameReady || !bettingOpen(game, now)
  const totalStake = game.bets.reduce((sum, b) => sum + b.amount, 0)
  const result = game.history.find(r => r.round === game.round)
  // Everyone's latest winners, whether or not this player saw them run.
  const recent = recentResults(game.seed, phase === 'result' ? game.round + 1 : game.round, field, 8)
  const half = field / 2
  const numbers = (from: number) => Array.from({ length: half }, (_, i) => from + i * 2)
  const listed = (list: number[]) => list.length > 4 ? `${list.slice(0, 3).join('·')}…${list.at(-1)}` : list.join('·')
  const winnerOdds = price(odds('horse:1', field))
  const pickLabel = (value: Pick) => {
    if (!value.startsWith('horse:')) return m.picks[value as 'odd' | 'even' | 'small' | 'big']
    const id = Number(value.split(':')[1])
    return m.picks.horse(id, horse(id))
  }
  useEffect(() => { document.title = m.page.title(cup.en, local.name) }, [m, cup, local])
  useEffect(() => { if (!message) return; const timer = setTimeout(() => setMessage(''), 4500); return () => clearTimeout(timer) }, [message])
  async function submit() {
    if (!gameReady || !selected || pending) return
    setPending(true)
    try { const error = await bet(selected, amount); setMessage(error ? m.errors[error] : m.tickets.placed(pickLabel(selected), n(amount))) }
    finally { setPending(false) }
  }
  // While betting, the ticket strip rides on the dock beside its collapse toggle; the results stage shows it alone.
  const ticketStrip = <section aria-label={m.tickets.label} className={`stage-bets placed-bets ${phase === 'result' && result && result.payout > 0 ? 'has-payout' : ''}`}><div className="ticket-strip-heading"><h3>{m.tickets.label} <span>{game.bets.length}</span></h3><b>{n(totalStake)}<Coins size={12} /></b></div>{game.bets.length === 0 ? <p className="empty-bets">{m.tickets.empty}</p> : <ul>{game.bets.map(b => <li key={`${b.id}-${phase}`} className={phase === 'result' && result && wins(b.pick, result.winner, field) ? 'winning-bet' : ''}><span>{pickLabel(b.pick)}<small>{n(b.amount)} × {price(odds(b.pick, field))}</small></span>{phase === 'result' && result ? <b className={wins(b.pick, result.winner, field) ? 'ticket-payout' : 'muted'}>{wins(b.pick, result.winner, field) ? <><span><Check size={10} />{m.tickets.won}</span><strong>+{n(Math.round(b.amount * odds(b.pick, field)))}</strong><small>{m.tickets.includesStake}</small></> : m.tickets.lost}</b> : <button disabled={locked} onClick={() => void cancel(b.id)} aria-label={m.tickets.cancel(pickLabel(b.pick))}><X size={14} /></button>}</li>)}</ul>}</section>
  const pick = (value: Pick) => { if (!locked) { setSelected(value); setMessage('') } }
  const toggleSound = () => {
    if (muted) { audio.current ??= new AudioContext(); crowd.enable(audio.current); commentary.enable(audio.current) } else crowd.stop()
    setMuted(!muted)
  }
  return <>
    <header className="app-header"><a className="brand" href={import.meta.env.BASE_URL} aria-label={m.header.home}><span className="brand-icon">♞</span><span>{cup.en.replace(/ CUP$/, '')}<span className="brand-light">CUP</span><small>{m.site}</small></span></a><nav><a className="nav-active" href={import.meta.env.BASE_URL}><Flag size={16} />{m.header.lobby}</a><button onClick={() => setModal('history')}><History size={16} />{m.header.history}</button><button onClick={() => setModal('rules')}><CircleHelp size={16} />{m.header.rules}</button></nav><div className="header-wallet"><span className="coin-icon"><Coins size={17} /></span><div><small>{m.header.wallet}</small><strong>{n(game.balance)}</strong></div><span className="practice-label">{m.header.practice}</span></div></header>
    <main className="app-main"><div className="page-heading"><div><span className="overline">THE {cup.en} EXPERIENCE</span><h1>{m.page.heading[0]}<span>{m.page.heading[1]}</span></h1></div><p><span className="online-dot" />{m.page.open(local.venue)} <span className="divider">/</span> {m.page.cadence}</p></div>
      <div className="game-layout"><section className="main-column">
        <div className="race-card"><div className="race-toolbar"><div><span className="live-tag"><Radio size={12} />LIVE</span><b>{local.name}</b><span className="toolbar-detail">{local.name.toUpperCase() === cup.en ? '' : `${cup.en} · `}{m.toolbar.detail(field)}</span></div><div className="toolbar-actions"><button className="icon-button" onClick={event => enterFullscreen(event.currentTarget.closest('.race-card')?.querySelector('.race-stage'))} aria-label={m.toolbar.fullscreen}><Maximize2 size={16} /></button><button className="icon-button" onClick={toggleSound} aria-label={muted ? m.toolbar.soundOn : m.toolbar.soundOff}>{muted ? <VolumeX size={17} /> : <Volume2 size={17} />}</button></div></div>
        <RaceStage onReady={setGameReady} game={game} now={now} muted={muted} expanded={expanded} onCollapse={() => setExpanded(false)} chatFeed={phone && <StageChatFeed messages={chat.messages} now={now} />} celebration={phase === 'result' && result && result.payout > 0 ? <div className="payout-celebration" key={`payout-${game.round}`} role="status"><div className="payout-sparks" aria-hidden="true">{Array.from({ length: 12 }, (_, i) => <i key={i} style={{ '--spark': i } as CSSProperties} />)}</div><span className="payout-kicker">WIN!{m.payout.kicker && ` · ${m.payout.kicker}`}</span><strong><Coins size={24} />+{n(result.payout)}</strong><span>{m.payout.note}</span><small>{m.payout.net} {result.payout - result.stake >= 0 ? '+' : ''}{n(result.payout - result.stake)}</small></div> : null} betsPanel={ticketStrip} notification={message && <div key={message} className="toast" role="status" aria-live="polite"><span>{message}</span><button aria-label={m.tickets.closeToast} onClick={() => setMessage('')}><X size={15} /></button></div>}>{dockOpen ? <div className="stage-betting"><div className="dock-bar">{ticketStrip}<button className="dock-toggle" onClick={() => setDockOpen(false)} aria-expanded="true">{m.dock.collapse}<ChevronDown size={14} /></button></div><section className="markets"><div className="section-heading"><h2><span className="section-number">01</span>{m.dock.heading}</h2><span>{locked ? <><LockKeyhole size={13} />{m.dock.closed}</> : m.dock.fair}</span></div>
          <div className="horse-grid">{HORSES.slice(0, field).map(h => <button key={h.id} className={`horse-card ${selected === `horse:${h.id}` ? 'selected' : ''}`} style={{ '--horse': h.color } as CSSProperties} disabled={locked} onClick={() => pick(`horse:${h.id}`)} aria-pressed={selected === `horse:${h.id}`}><HorseNumber id={h.id} small /><HorsePortrait id={h.id} /><span className="horse-card-name">{horse(h.id)}</span><span className="horse-odds">× {winnerOdds}</span>{selected === `horse:${h.id}` && <span className="selection-check"><Check size={10} /></span>}</button>)}</div><div className="stage-side-picks" role="group" aria-label={m.dock.sides}>{(['big', 'small', 'odd', 'even'] as const).map(v => <button key={v} className={selected === v ? 'selected' : ''} disabled={locked} onClick={() => pick(v)} aria-pressed={selected === v}><b>{m.picks.short[v]}</b><span>{{ big: `${half + 1}–${field}`, small: `1–${half}`, odd: listed(numbers(1)), even: listed(numbers(2)) }[v]}</span><em>× {price(1.9)}</em></button>)}</div>
          <p className="market-hint"><CircleHelp size={12} />{m.dock.hint}</p></section><div className="stage-wager"><span>{selected ? pickLabel(selected) : m.dock.choose}<small>{m.dock.balance(n(game.balance), n(totalStake))}</small></span><div className="stage-chips" role="group" aria-label={m.dock.chips}>{[100, 500, 1000].map(value => <button key={value} type="button" disabled={locked || pending} aria-pressed={amount === value} className={amount === value ? 'active' : ''} onClick={() => setAmount(value)}>{n(value)}</button>)}</div><label htmlFor="stage-amount">{m.dock.amount}<input id="stage-amount" type="number" min="10" max="10000" step="10" value={Number.isNaN(amount) ? '' : amount} onChange={e => setAmount(e.currentTarget.valueAsNumber)} /></label><button className="place-bet" disabled={locked || !selected || pending || !Number.isSafeInteger(amount) || amount < 10 || amount > 10000 || amount % 10 !== 0 || amount > game.balance} onClick={() => void submit()}>{pending ? m.dock.pending : m.dock.confirm}<ArrowUpRight size={16} /></button></div></div> : <button className="dock-open" onClick={() => setDockOpen(true)} aria-expanded="false">{m.dock.open}<ChevronUp size={16} /></button>}</RaceStage>
        {phone && <StageChatCompose chat={chat} />}
        <div className="timeline"><div className={phase === 'betting' ? 'current' : 'done'}><span>{phase !== 'betting' ? <Check size={12} /> : '1'}</span>{m.timeline.bet} <small>48s + 12s</small></div><i /><div className={phase === 'racing' ? 'current' : phase === 'result' ? 'done' : ''}><span>{phase === 'result' ? <Check size={12} /> : '2'}</span>{m.timeline.race} <small>50s</small></div><i /><div className={phase === 'result' ? 'current' : ''}><span>3</span>{m.timeline.settle} <small>10s</small></div><div className="next-round"><Clock3 size={13} />{m.timeline.loop}</div></div></div>

        <div className="recent-results"><span><History size={14} />{m.recent.heading}</span>{recent.length ? recent.map(r => <div key={r.round} title={m.recent.round(raceNumber(r.round))}><HorseNumber id={r.winner} small /><small>#{String(raceNumber(r.round)).padStart(2, '0')}</small></div>) : <p>{m.recent.empty}</p>}<button onClick={() => setModal('history')} aria-label={m.recent.all}><ChevronRight size={17} /></button></div>
      </section>
      {(!phone || needsRefill) && <aside className="chat-sidebar">{!phone && <RaceChat chat={chat} round={raceNumber(game.round)} />}{needsRefill && <button className="chat-refill" onClick={() => void refill()}>{m.recent.refill} <ArrowDownLeft size={13} /></button>}</aside>}</div>
      <footer><span>♞ {cup.en} <span>{local.motto}</span></span><span>{m.footer.fun} <span className="footer-dot">•</span> {m.footer.saved} <span className="footer-dot">•</span> <a href={`${import.meta.env.BASE_URL}audio/crowd/LICENSE.txt`} target="_blank" rel="noreferrer">{m.footer.crowd}</a></span></footer>
    </main>

    {modal === 'rules' && <Dialog title={m.rules.title(local.name)} onClose={() => setModal(null)}><div className="rules-content"><p>{m.rules.intro(field)}</p><ol>{m.rules.steps.map(step => <li key={step.head}><b>{step.head}</b>{step.text}</li>)}</ol><table><thead><tr>{m.rules.columns.map(column => <th key={column}>{column}</th>)}</tr></thead><tbody><tr><td>{m.rules.winner.name}</td><td>{m.rules.winner.rule}</td><td>{winnerOdds}</td></tr><tr><td>{m.rules.oddEven.name}</td><td>{m.rules.oddEven.rule(numbers(1).join('/'), numbers(2).join('/'))}</td><td>{price(1.9)}</td></tr><tr><td>{m.rules.bigSmall.name}</td><td>{m.rules.bigSmall.rule(half, field)}</td><td>{price(1.9)}</td></tr></tbody></table><p>{m.rules.example(winnerOdds, n(Math.round(100 * odds('horse:1', field))), n(Math.round(100 * odds('horse:1', field)) - 100))}</p><p className="muted">{m.rules.fine}</p></div></Dialog>}
    {modal === 'history' && <Dialog title={m.history.title} onClose={() => setModal(null)}><div className="history-list">{game.history.length === 0 ? <div className="history-empty"><History size={36} /><h3>{m.history.emptyTitle}</h3><p>{m.history.emptyText}</p></div> : game.history.map(r => <div className="history-row" key={r.round}><span>#{String(raceNumber(r.round)).padStart(2, '0')}</span><HorseNumber id={r.winner} /><div><b>{horse(r.winner)}</b><small>{m.history.detail(m.picks.short[r.winner % 2 ? 'odd' : 'even'], m.picks.short[r.winner <= half ? 'small' : 'big'], n(r.stake))}</small></div><strong className={r.payout >= r.stake ? 'positive' : 'negative'}>{r.payout >= r.stake ? '+' : ''}{n(r.payout - r.stake)}<small>{m.history.net}</small></strong></div>)}<p className="muted">{m.history.kept}</p></div></Dialog>}
  </>
}

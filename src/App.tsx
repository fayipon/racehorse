import { useEffect, useMemo, useRef, useState, type CSSProperties } from 'react'
import { ArrowDownLeft, ArrowUpRight, Check, ChevronRight, CircleHelp, Clock3, Coins, Flag, History, LockKeyhole, Maximize2, Radio, Trophy, Volume2, VolumeX, X } from 'lucide-react'
import { BET_CLOSE_MS, bettingOpen, BET_MS, HORSES, cameraShot, countdown, odds, phaseAt, pickLabel, raceOrder, racePositions, wins, type Game, type Phase, type Pick } from './game'
import { useGame } from './useGame'
import { enableAnnouncer, useAnnouncer } from './useAnnouncer'
import { RaceChat } from './RaceChat'
import { COURSE, coursePoint, makeParadePlan, paradePositions } from './course'
import { racePresentationTime } from './presentation'

const fmt = (n: number) => n.toLocaleString('en-US')
const clock = (s: number) => `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`
function HorsePortrait({ id, className = '' }: { id: number; className?: string }) {
  return <span aria-hidden="true" className={`horse-portrait ${className}`} style={{ backgroundImage: `url('${import.meta.env.BASE_URL}assets/horse-${id}.png')` }} />
}
function HorseNumber({ id, small = false }: { id: number; small?: boolean }) {
  return <span className={`horse-number ${small ? 'small' : ''}`} style={{ '--horse': HORSES[id - 1].color } as CSSProperties}>{id}</span>
}
function MiniTrack({ positions }: { positions: number[] }) {
  const radius = COURSE.innerRadius + COURSE.trackWidth / 2
  const half = COURSE.halfStraight
  return <svg className="minitrack" viewBox="-67 -41 134 82" aria-label="八匹馬的賽道位置：兩段直線與兩端半圓，底部中央為終點">
    <rect x={-half-radius} y={-radius} width={2*(half+radius)} height={2*radius} rx={radius} fill="none" stroke="#ffffff30" strokeWidth={COURSE.trackWidth} />
    <rect x={-half-radius} y={-radius} width={2*(half+radius)} height={2*radius} rx={radius} fill="none" stroke="#ffffff80" strokeWidth=".7" />
    {positions.map((p,i) => { const point = coursePoint(p,i); return <circle key={i} cx={point.x} cy={point.z} r="2.7" fill={HORSES[i].color} stroke="white" strokeWidth=".65" /> })}
    <path d={`M-1.5 ${COURSE.innerRadius-1}v${COURSE.trackWidth+2}m3 0v-${COURSE.trackWidth+2}`} stroke="white" strokeWidth="1" />
  </svg>
}
function RaceStage({ game, now, muted, children, notification, betsPanel, celebration, onReady }: { game: Game; now: number; muted: boolean; children?: React.ReactNode; notification?: React.ReactNode; betsPanel?: React.ReactNode; celebration?: React.ReactNode; onReady: (ready: boolean) => void }) {
  const frame = useRef<HTMLIFrameElement>(null)
  const shell = useRef<HTMLDivElement>(null)
  const [ready, setReady] = useState(false)
  const [failed, setFailed] = useState(false)
  const [progress, setProgress] = useState(0)
  const [loadAttempt, setLoadAttempt] = useState(0)
  const [finishRound, setFinishRound] = useState(0)
  const phase = phaseAt(game, now)
  const seconds = Math.max(0, (now - game.startedAt - BET_MS) / 1000)
  const visualSeconds = racePresentationTime(seconds)
  const shot = cameraShot(phase, seconds)
  const positions = racePositions(game.seed, game.round, visualSeconds)
  const order = raceOrder(game.seed, game.round)
  const paradePlan = useMemo(()=>makeParadePlan(game.seed,game.round),[game.seed,game.round])
  const ranking = [...HORSES].sort((a, b) => positions[b.id - 1] - positions[a.id - 1] || order.indexOf(a.id) - order.indexOf(b.id))
  const remaining = countdown(game, now)
  const assembling = phase === 'betting' && !bettingOpen(game, now)
  const startCue = phase === 'betting' && remaining <= 7 ? (remaining > 5 ? 'READY' : String(remaining)) : phase === 'racing' && seconds < 1.8 ? 'GO!' : null
  const finishing = phase === 'racing' && (finishRound === game.round || visualSeconds >= 44.6)
  useEffect(() => {
    const listener = (event: MessageEvent) => {
      if (event.origin !== location.origin || event.source !== frame.current?.contentWindow) return
      if (event.data?.type === 'game-visible') { setReady(true); setFailed(false); onReady(true) }
      if (event.data?.type === 'godot-progress' && Number.isFinite(event.data.progress)) setProgress(Math.max(0, Math.min(100, event.data.progress)))
      if (event.data?.type === 'godot-error') { setFailed(true); setReady(false); onReady(false) }
      if (event.data?.type === 'race-finish' && Number.isSafeInteger(event.data.round)) setFinishRound(event.data.round)
    }
    window.addEventListener('message', listener)
    return () => window.removeEventListener('message', listener)
  }, [onReady])
  useEffect(() => {
    if (ready || failed) return
    const timeout = setTimeout(() => setFailed(true), 90000)
    return () => clearTimeout(timeout)
  }, [ready, failed, loadAttempt])
  useEffect(() => {
    frame.current?.contentWindow?.postMessage({ type: 'race-state', phase, seconds, bettingElapsed: Math.max(0, (now-game.startedAt)/1000), positions, paradePlan, finishTimes: HORSES.map(h => 44.5 + order.indexOf(h.id) * .65), winner: order[0], camera: shot.id, round: game.round, muted }, location.origin)
  }, [game.round, game.startedAt, muted, now, order, phase, positions, seconds, shot.id, ready, paradePlan])
  return <div ref={shell} className={`race-stage phase-${phase} ${!ready ? 'is-loading' : ''} ${assembling ? 'is-assembling' : ''} ${finishing ? 'has-finished' : ''}`}>
    {!ready && <div className="engine-loading" role="status" aria-live="polite"><div className="loading-emblem" aria-hidden="true">♞</div><span className="loading-brand">SUNNY CUP</span><h2>{failed ? '賽場暫時無法載入' : '正在準備你的陽光賽場'}</h2><p>{failed ? '連線可能中斷或載入逾時，請重試。' : progress >= 100 ? '資源下載完成，正在啟動 3D 賽場…' : '正在下載小馬與賽場資源…'}</p><div className="loading-progress" role="progressbar" aria-label="賽場下載進度" aria-valuemin={0} aria-valuemax={100} aria-valuenow={progress}><i style={{ width: `${progress}%` }} /></div><strong>{Math.floor(progress)}<small>%</small></strong><small>首次載入約 49 MB · 準備完成後開放操作</small>{failed && <button onClick={() => { setFailed(false); setProgress(0); setReady(false); onReady(false); setLoadAttempt(value => value + 1); if (frame.current) frame.current.src = `${import.meta.env.BASE_URL}game/index.html` }}>重新載入賽場</button>}</div>}

    <iframe tabIndex={ready ? 0 : -1} ref={frame} title="Godot 3D 即時賽馬" src={`${import.meta.env.BASE_URL}game/index.html`} allow="autoplay; fullscreen" className={ready ? 'ready' : ''} />
    <div className="stage-vignette" />
    <div className="race-title"><div>RACE <em>{String(game.round).padStart(2, '0')}</em></div><span /><p>SUNNY CUP<small>陽光盃 · 1200 M</small></p></div>
    <div className="stage-status"><span className={`status-dot ${phase}`} />{phase === 'betting' ? (assembling ? '集合中 · 已封盤' : '開放投注') : phase === 'racing' ? 'LIVE 賽事進行中' : '賽事結束'}</div>
    {phase === 'betting' && !assembling && <div className="betting-hero"><span className="hero-kicker">A LITTLE LUCK. A LOT OF HEART.</span><h2>好運，即將起跑。</h2><p>選擇你的小馬，讓心跳跟著賽道加速。</p><div className="countdown-pill"><Clock3 size={16} />投注倒數 <strong>{clock(Math.max(0, Math.ceil((game.startedAt + BET_CLOSE_MS - now) / 1000)))}</strong></div></div>}
    {assembling && !startCue && <div className="assembly-caption"><span>TO THE STARTING LINE</span><strong>小馬集合中</strong><small>本場已封盤，準備迎接起跑！</small></div>}
    {startCue && <div className={`start-sequence ${startCue === 'GO!' ? 'is-go' : ''}`}>
      <div key={`${game.round}-${startCue}`} className="start-cue" role="status" aria-live="polite" aria-atomic="true">
        <span className="start-kicker">{startCue === 'GO!' ? 'THE RACE IS ON' : 'SUNNY CUP · GET READY'}</span>
        <div className="start-number"><i aria-hidden="true" /><strong>{startCue}</strong></div>
        <b className="start-subtitle">{startCue === 'READY' ? '各就各位' : startCue === 'GO!' ? '開跑！全速前進' : '起跑倒數'}</b>
        <div className="start-lights" aria-hidden="true">{[5,4,3,2,1].map(n => <i key={n} className={startCue === 'GO!' || Number(startCue) <= n ? 'lit' : ''} />)}</div>
        {phase === 'betting' && <small className="start-bet-note">本場已封盤 · 等待開跑</small>}
      </div>
    </div>}
    {phase === 'racing' && seconds >= 42.8 && <div className="finish-shot-bars" />}
    {finishing && <div key={game.round} className="finish-sequence" aria-live="polite"><div className="finish-impact" /><div className="finish-announcement"><span className="finish-kicker">PHOTO FINISH · 衝線時刻</span><strong>FINISH!</strong><div><HorseNumber id={order[0]} /><span>{HORSES[order[0]-1].name}<small>率先衝過終點</small></span><Trophy size={25} /></div></div><div className="finish-streaks" /></div>}
    {phase === 'result' && <div className="winner-hero"><span>WINNER</span><h2><HorseNumber id={order[0]} />{HORSES[order[0] - 1].name}</h2><p>{order[0] % 2 ? '單' : '雙'} · {order[0] <= 4 ? '小' : '大'}<span>恭喜本場冠軍！</span></p></div>}
    <div className="stage-bottom">
      <div className="live-ranking"><small>即時排名</small><div className="ranking-list" key={game.round} role="list" aria-label="即時前三名">{ranking.map((h, i) => <div key={h.id} className="ranking-row" role="listitem" aria-hidden={i >= 3} style={{ '--rank': Math.min(i, 3), '--rank-color': h.color, opacity: i < 3 ? 1 : 0, zIndex: 8 - i } as CSSProperties}><span className="ranking-place">{i + 1}</span><HorseNumber id={h.id} small /><b>{h.en}</b></div>)}</div></div>
      <div className="race-progress"><div><span>{phase === 'betting' ? '準備就緒 · 等待開跑' : 'RACE PROGRESS'}</span><b>{phase === 'betting' ? '1200 M' : `${Math.round(Math.max(...positions) * 1200)} / 1200 M`}</b></div><div className="progress-rail"><span style={{ width: `${phase === 'betting' ? 0 : Math.max(...positions) * 100}%` }} /></div><small><i />{shot.label} <span>自動分鏡</span></small></div>
      <MiniTrack positions={phase === 'betting' ? paradePositions((now-game.startedAt)/1000,paradePlan) : positions} />
    </div>
    {ready && phase === 'betting' && !assembling && children}
    {celebration}
    {ready && (phase === 'result' || bettingOpen(game, now)) && betsPanel}
    {notification}
    <button className="fullscreen" aria-label="賽場全螢幕" onClick={() => { if (document.fullscreenElement) void document.exitFullscreen(); else void shell.current?.requestFullscreen().catch(() => {}) }}><Maximize2 size={16} /></button>
  </div>
}
function Dialog({ title, children, onClose }: { title: string; children: React.ReactNode; onClose: () => void }) {
  const ref = useRef<HTMLDialogElement>(null)
  useEffect(() => { ref.current?.showModal() }, [])
  return <dialog ref={ref} onCancel={onClose} onClick={e => { if (e.target === ref.current) onClose() }}><div className="dialog-head"><h2>{title}</h2><button className="icon-button" aria-label="關閉" onClick={onClose}><X size={20} /></button></div>{children}</dialog>
}
export default function App() {
  const [gameReady, setGameReady] = useState(false)
  const { game, now, bet, cancel, refill } = useGame()
  const [selected, setSelected] = useState<Pick | null>(null)
  const [amount, setAmount] = useState(100)
  const [message, setMessage] = useState('')
  const [pending, setPending] = useState(false)
  const [modal, setModal] = useState<'rules' | 'history' | null>(null)
  const [muted, setMuted] = useState(true)
  useAnnouncer(game, now, gameReady && !muted)
  const sound = useRef<AudioContext | null>(null)
  const previous = useRef<Phase>('betting')
  const finishSoundRound = useRef(0)
  const phase = phaseAt(game, now)
  const locked = !gameReady || !bettingOpen(game, now)
  const totalStake = game.bets.reduce((sum, b) => sum + b.amount, 0)
  const result = game.history.find(r => r.round === game.round)
  useEffect(() => {
    if (phase !== 'racing' || racePresentationTime((now-game.startedAt-BET_MS)/1000) < 44.5 || finishSoundRound.current === game.round) return
    finishSoundRound.current = game.round
    if (muted || !sound.current) return
    const audio=sound.current
    ;[523,659,784,1047].forEach((frequency,i) => {
      const tone=audio.createOscillator(), volume=audio.createGain()
      tone.type='triangle'; tone.frequency.value=frequency
      const start=audio.currentTime+i*.11
      volume.gain.setValueAtTime(.001,start)
      volume.gain.exponentialRampToValueAtTime(.06,start+.025)
      volume.gain.exponentialRampToValueAtTime(.001,start+.65)
      tone.connect(volume); volume.connect(audio.destination)
      tone.start(start); tone.stop(start+.7)
    })
  }, [phase, now, game.startedAt, game.round, muted])
  useEffect(() => {
    if (!muted && previous.current !== phase && sound.current) {
      const audio = sound.current
      const notes = phase === 'racing' ? [523, 659, 784] : phase === 'result' ? [784, 988, 1046] : [523]
      notes.forEach((frequency, i) => { const osc = audio.createOscillator(); const gain = audio.createGain(); osc.type = 'sine'; osc.frequency.value = frequency; gain.gain.setValueAtTime(0.06, audio.currentTime + i * .16); gain.gain.exponentialRampToValueAtTime(.001, audio.currentTime + i * .16 + .35); osc.connect(gain); gain.connect(audio.destination); osc.start(audio.currentTime + i * .16); osc.stop(audio.currentTime + i * .16 + .4) })
    }
    previous.current = phase
  }, [phase, muted])
  useEffect(() => { if (!message) return; const timer = setTimeout(() => setMessage(''), 4500); return () => clearTimeout(timer) }, [message])
  async function submit() {
    if (!gameReady || !selected || pending) return
    setPending(true)
    try { const error = await bet(selected, amount); setMessage(error || `投注成功！${pickLabel(selected)} · ${fmt(amount)} 籌碼`) }
    finally { setPending(false) }
  }
  const pick = (value: Pick) => { if (!locked) { setSelected(value); setMessage('') } }
  const toggleSound = () => { if (muted) { sound.current ??= new AudioContext(); void sound.current.resume(); enableAnnouncer() } else if ('speechSynthesis' in window) { window.speechSynthesis.cancel() }; setMuted(!muted) }
  return <>
    <header className="app-header"><a className="brand" href={import.meta.env.BASE_URL} aria-label="Sunny Cup 首頁"><span className="brand-icon">♞</span><span>SUNNY<span className="brand-light">CUP</span><small>小馬競速俱樂部</small></span></a><nav><span className="nav-active"><Flag size={16} />賽事大廳</span><button onClick={() => setModal('history')}><History size={16} />投注紀錄</button><button onClick={() => setModal('rules')}><CircleHelp size={16} />玩法說明</button></nav><div className="header-wallet"><span className="coin-icon"><Coins size={17} /></span><div><small>我的籌碼</small><strong>{fmt(game.balance)}</strong></div><span className="practice-label">練習模式</span></div></header>
    <main className="app-main"><div className="page-heading"><div><span className="overline">THE SUNNY CUP EXPERIENCE</span><h1>每一場，都有新的可能<span>。</span></h1></div><p><span className="online-dot" />陽光賽場開放中 <span className="divider">/</span> 每 2 分鐘一場</p></div>
      <div className="game-layout"><section className="main-column">
        <div className="race-card"><div className="race-toolbar"><div><span className="live-tag"><Radio size={12} />LIVE</span><b>陽光盃</b><span className="toolbar-detail">SUNNY CUP · 草地晴朗 · 1200 公尺</span></div><button className="icon-button" onClick={toggleSound} aria-label={muted ? '開啟主播語音與賽事音效' : '關閉主播語音與賽事音效'}>{muted ? <VolumeX size={17} /> : <Volume2 size={17} />}</button></div>
        <RaceStage onReady={setGameReady} game={game} now={now} muted={muted} celebration={phase === 'result' && result && result.payout > 0 ? <div className="payout-celebration" key={game.round} role="status"><div className="payout-sparks" aria-hidden="true">{Array.from({ length: 12 }, (_, i) => <i key={i} style={{ '--spark': i } as CSSProperties} />)}</div><span className="payout-kicker">WIN! · 中獎啦</span><strong><Coins size={24} />+{fmt(result.payout)}</strong><span>派彩含本金 · 已加入籌碼</span><small>本局淨盈虧 {result.payout - result.stake >= 0 ? '+' : ''}{fmt(result.payout - result.stake)}</small></div> : null} betsPanel={<section aria-label="本局投注" className={`stage-bets placed-bets ${phase === 'result' && result && result.payout > 0 ? 'has-payout' : ''}`}><div className="ticket-strip-heading"><h3>本局投注 <span>{game.bets.length}</span></h3><b>{fmt(totalStake)}<Coins size={12} /></b></div>{game.bets.length === 0 ? <p className="empty-bets">尚無注單，選匹小馬一起加油吧。</p> : <ul>{game.bets.map(b => <li key={`${b.id}-${phase}`} className={phase === 'result' && result && wins(b.pick, result.winner) ? 'winning-bet' : ''}><span>{pickLabel(b.pick)}<small>{fmt(b.amount)} × {odds(b.pick).toFixed(2)}</small></span>{phase === 'result' && result ? <b className={wins(b.pick, result.winner) ? 'ticket-payout' : 'muted'}>{wins(b.pick, result.winner) ? <><span><Check size={10} />中獎</span><strong>+{fmt(Math.round(b.amount * odds(b.pick)))}</strong><small>派彩含本金</small></> : '未中獎'}</b> : <button disabled={locked} onClick={() => void cancel(b.id)} aria-label={`撤回 ${pickLabel(b.pick)} 投注`}><X size={14} /></button>}</li>)}</ul>}</section>} notification={message && <div key={message} className="toast" role="status" aria-live="polite"><span>{message}</span><button aria-label="關閉提示" onClick={() => setMessage('')}><X size={15} /></button></div>}><div className="stage-betting"><section className="markets"><div className="section-heading"><h2><span className="section-number">01</span>選擇你的好運</h2><span>{locked ? <><LockKeyhole size={13} />本場已封盤</> : '所有馬匹機率相同'}</span></div>
          <div className="horse-grid">{HORSES.map(h => <button key={h.id} className={`horse-card ${selected === `horse:${h.id}` ? 'selected' : ''}`} style={{ '--horse': h.color } as CSSProperties} disabled={locked} onClick={() => pick(`horse:${h.id}`)} aria-pressed={selected === `horse:${h.id}`}><HorseNumber id={h.id} small /><HorsePortrait id={h.id} /><span className="horse-card-name">{h.name}</span><span className="horse-odds">× 7.60</span>{selected === `horse:${h.id}` && <span className="selection-check"><Check size={10} /></span>}</button>)}</div><div className="stage-side-picks" role="group" aria-label="大小單雙投注">{(['big', 'small', 'odd', 'even'] as const).map(v => <button key={v} className={selected === v ? 'selected' : ''} disabled={locked} onClick={() => pick(v)} aria-pressed={selected === v}><b>{{ big: '大', small: '小', odd: '單', even: '雙' }[v]}</b><span>{{ big: '5–8', small: '1–4', odd: '1·3·5·7', even: '2·4·6·8' }[v]}</span><em>× 1.90</em></button>)}</div>
          <p className="market-hint"><CircleHelp size={12} />選擇項目與籌碼，確認後完成投注。賠率含本金。</p></section><div className="stage-wager"><span>{selected ? pickLabel(selected) : '選擇你的投注項目'}<small>餘額 {fmt(game.balance)} · 已投注 {fmt(totalStake)}</small></span><div className="stage-chips" role="group" aria-label="快速選擇投注籌碼">{[100, 500, 1000].map(n => <button key={n} type="button" disabled={locked || pending} aria-pressed={amount === n} className={amount === n ? 'active' : ''} onClick={() => setAmount(n)}>{fmt(n)}</button>)}</div><label htmlFor="stage-amount">籌碼<input id="stage-amount" type="number" min="10" max="10000" step="10" value={Number.isNaN(amount) ? '' : amount} onChange={e => setAmount(e.currentTarget.valueAsNumber)} /></label><button className="place-bet" disabled={locked || !selected || pending || !Number.isSafeInteger(amount) || amount < 10 || amount > 10000 || amount % 10 !== 0 || amount > game.balance} onClick={() => void submit()}>{pending ? '處理中…' : '確認投注'}<ArrowUpRight size={16} /></button></div></div></RaceStage>
        <div className="timeline"><div className={phase === 'betting' ? 'current' : 'done'}><span>{phase !== 'betting' ? <Check size={12} /> : '1'}</span>投注／集合 <small>48s + 12s</small></div><i /><div className={phase === 'racing' ? 'current' : phase === 'result' ? 'done' : ''}><span>{phase === 'result' ? <Check size={12} /> : '2'}</span>賽事進行 <small>50s</small></div><i /><div className={phase === 'result' ? 'current' : ''}><span>3</span>賽果結算 <small>10s</small></div><div className="next-round"><Clock3 size={13} />自動循環開賽</div></div></div>

        <div className="recent-results"><span><History size={14} />近期冠軍</span>{game.history.length ? game.history.slice(0, 8).map(r => <div key={r.round} title={`第 ${r.round} 場`}><HorseNumber id={r.winner} small /><small>#{String(r.round).padStart(2, '0')}</small></div>) : <p>第一場賽事即將展開，冠軍會是誰？</p>}<button onClick={() => setModal('history')} aria-label="查看所有賽果"><ChevronRight size={17} /></button></div>
      </section>
      <aside className="chat-sidebar"><RaceChat game={game} now={now} />{game.balance < 10 && game.bets.length === 0 && <button className="chat-refill" onClick={() => void refill()}>領取 10,000 練習籌碼 <ArrowDownLeft size={13} /></button>}</aside></div>
      <footer><span>♞ SUNNY CUP <span>讓每一場比賽，都多一點陽光。</span></span><span>虛擬籌碼 · 純粹好玩 <span className="footer-dot">•</span> 本機自動儲存</span></footer>
    </main>

    {modal === 'rules' && <Dialog title="陽光盃・玩法說明" onClose={() => setModal(null)}><div className="rules-content"><p>每場共 8 匹小馬，每 120 秒自動開始新的一輪。</p><ol><li><b>投注 48 秒</b>：選擇項目與籌碼，確認後扣款，封盤前可撤回。接著集合與倒數 12 秒，期間禁止下注與撤單。</li><li><b>比賽 50 秒</b>：停止投注與撤單，觀看小馬競速。</li><li><b>結算 10 秒</b>：自動派彩，再次開放下一輪投注。</li></ol><table><thead><tr><th>玩法</th><th>中獎條件</th><th>賠率</th></tr></thead><tbody><tr><td>猜冠軍</td><td>選中第 1 名馬號</td><td>7.60</td></tr><tr><td>猜單雙</td><td>單 1/3/5/7；雙 2/4/6/8</td><td>1.90</td></tr><tr><td>猜大小</td><td>小 1–4；大 5–8</td><td>1.90</td></tr></tbody></table><p>賠率含本金。例如投注 100 籌碼、賠率 7.60，中獎派彩 760，淨獲利 660。每匹馬的冠軍機率相同，賽果不受投注影響。</p><p className="muted">初始 10,000 虛擬籌碼；最低投注 10，最高 10,000，每筆須為 10 的倍數，每輪最多 100 筆。餘額少於 10 且無當輪注單時可免費補充。資料儲存於此瀏覽器；無儲值、提領或真實金錢交易。</p></div></Dialog>}
    {modal === 'history' && <Dialog title="賽果與投注紀錄" onClose={() => setModal(null)}><div className="history-list">{game.history.length === 0 ? <div className="history-empty"><History size={36} /><h3>第一場故事，還在路上。</h3><p>比賽結束後，這裡會顯示賽果與你的派彩。</p></div> : game.history.map(r => <div className="history-row" key={r.round}><span>#{String(r.round).padStart(2, '0')}</span><HorseNumber id={r.winner} /><div><b>{HORSES[r.winner - 1].name}</b><small>{r.winner % 2 ? '單' : '雙'} · {r.winner <= 4 ? '小' : '大'}　投注 {fmt(r.stake)}</small></div><strong className={r.payout >= r.stake ? 'positive' : 'negative'}>{r.payout >= r.stake ? '+' : ''}{fmt(r.payout - r.stake)}<small>淨盈虧</small></strong></div>)}<p className="muted">保留最近 12 場賽事紀錄</p></div></Dialog>}
  </>
}

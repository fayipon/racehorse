import { useEffect, useRef } from 'react'
import { BET_MS, HORSES, phaseAt, raceOrder, racePositions, type Game } from './game'
import { racePresentationTime } from './presentation'

type Cue = 'start' | 'pack' | 'overtake' | 'sprint' | 'finish'
const scripts: Record<Cue, string[]> = {
  start: [
    '開跑了！八匹小馬同時出發！這場精彩了！',
    '來了來了！比賽正式開始！各位，眼睛別眨！',
    '出發！全場衝出去啦！陽光盃，現在開始！',
    '起跑！小馬們全速前進！一起盯緊這場比賽！',
    '開閘！衝啊！八匹小馬，誰能搶下冠軍！',
    '比賽開始！速度拉起來了！精彩對決，馬上登場！',
    '跑起來了！全場都在加速！這場可不能錯過！',
    '就是現在！正式起跑！注意看，前方馬群的變化！',
  ],
  pack: [
    '{leader}暫時領先！{second}緊追在後！',
    '看前面！{leader}跑在第一！後方還在追！',
    '目前帶頭的是{leader}！比賽還沒結束！',
    '{second}正在追趕{leader}！繼續盯住！',
    '前方順序！{leader}，接著是{second}！',
    '節奏越來越快！{leader}守住前方！',
    '{leader}在最前面！其他小馬還有機會！',
    '跟上！跟上！{second}還在追！',
  ],
  overtake: [
    '超過去了！{leader}搶到第一！',
    '換人領先！{leader}衝上來了！漂亮！',
    '注意！{leader}超到前面！局勢變了！',
    '哇！{leader}完成超越！現在領先！',
    '衝上去了！{leader}！暫居第一！',
    '領先易主！{leader}搶先！還在拚！',
  ],
  sprint: [
    '最後衝刺！{leader}在前！冠軍還沒確定！',
    '快到終點了！{leader}領先！撐住啊！',
    '衝啊！最後這一段！{second}還在追！',
    '終點就在前面！全力加速！別停下來！',
    '最後關頭！盯住{leader}！要衝線了！',
    '來了！最刺激的衝刺！誰能笑到最後！',
  ],
  finish: [
    '衝線！{winner}！第一個通過終點！',
    '冠軍出爐！{winner}！漂亮的一場！',
    '到了！到了！{winner}率先抵達！恭喜！',
    '贏了！{winner}拿下這一場！太精彩啦！',
    '終點確認！{winner}第一！掌聲送給牠！',
    '漂亮！{winner}衝線奪冠！精彩比賽！',
  ],
}
const lastChoice = new Map<Cue, string>()
function pickLine(cue: Cue) {
  const choices = scripts[cue].filter(line => line !== lastChoice.get(cue))
  const line = choices[Math.floor(Math.random() * choices.length)]
  lastChoice.set(cue, line)
  return line
}
function chineseVoice() {
  const voices = window.speechSynthesis.getVoices()
  return voices.find(voice => /^zh[-_]TW$/i.test(voice.lang))
    ?? voices.find(voice => /^zh[-_](CN|HK)/i.test(voice.lang))
    ?? voices.find(voice => /^zh/i.test(voice.lang))
}
function speak(text: string, intensity = 1) {
  if (!('speechSynthesis' in window)) return
  const engine = window.speechSynthesis
  engine.cancel()
  const speech = new SpeechSynthesisUtterance(text)
  const voice = chineseVoice()
  if (voice) speech.voice = voice
  speech.lang = voice?.lang ?? 'zh-TW'
  speech.rate = 1.24 + intensity * .1
  speech.pitch = 1.08 + intensity * .07
  speech.volume = .95
  engine.speak(speech)
}

// Called inside the sound button's user gesture, also unlocking speech on mobile.
export function enableAnnouncer() {
  speak('主播就位！精彩賽事，馬上為你播報！')
}

export function useAnnouncer(game: Game, now: number, enabled: boolean) {
  const state = useRef({ round: 0, lastAt: -100, leader: 0, started: false, sprint: false, finished: false })
  useEffect(() => {
    if (!('speechSynthesis' in window)) return
    const stop = () => { if (document.hidden) window.speechSynthesis.cancel() }
    // Some browsers populate voices asynchronously; query once to initialize them.
    window.speechSynthesis.getVoices()
    document.addEventListener('visibilitychange', stop)
    return () => { document.removeEventListener('visibilitychange', stop); window.speechSynthesis.cancel() }
  }, [])
  useEffect(() => {
    if (!('speechSynthesis' in window)) return
    const engine = window.speechSynthesis
    const seconds = (now - game.startedAt - BET_MS) / 1000
    if (state.current.round !== game.round) {
      engine.cancel()
      state.current = { round: game.round, lastAt: -100, leader: 0, started: false, sprint: false, finished: false }
    }
    const current = state.current
    const phase = phaseAt(game, now)
    if (!enabled || document.hidden) { engine.cancel(); return }
    if (phase !== 'racing') {
      // Let the finish call complete into settlement, then stop naturally.
      return
    }
    const visual = racePresentationTime(seconds)
    const order = raceOrder(game.seed, game.round)
    const positions = racePositions(game.seed, game.round, visual)
    const ranking = [...HORSES].sort((a, b) => positions[b.id - 1] - positions[a.id - 1] || order.indexOf(a.id) - order.indexOf(b.id))
    const leader = ranking[0].id
    let cue: Cue | undefined
    if (visual >= 44.5) {
      if (!current.finished && visual < 47) cue = 'finish'
      current.finished = true
    } else if (seconds < 3 && !current.started) {
      cue = 'start'
    } else if (seconds >= 38 && !current.sprint) {
      cue = 'sprint'
      current.sprint = true
    } else if (seconds >= 5 && seconds < 38 && seconds - current.lastAt >= 6 && !engine.speaking) {
      cue = current.leader !== 0 && current.leader !== leader ? 'overtake' : 'pack'
    }
    current.started = true
    // Track each actual lead change, including those we skip while speaking.
    const previousLeader = current.leader
    current.leader = leader
    if (cue === 'overtake' && previousLeader === leader) cue = 'pack'
    if (!cue) return
    const label = (id: number) => `${['一','二','三','四','五','六','七','八'][id - 1]}號`
    const text = pickLine(cue).replaceAll('{leader}', label(leader)).replaceAll('{second}', label(ranking[1].id)).replaceAll('{winner}', `${label(order[0])}，${HORSES[order[0] - 1].name}`)
    current.lastAt = seconds
    speak(text, cue === 'finish' || cue === 'sprint' ? 2 : 1)
  }, [game, now, enabled])
}

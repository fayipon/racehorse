import { useEffect, useRef, useState } from 'react'
import { MessageCircle, Send } from 'lucide-react'
import { ROUND_MS, BET_MS, bettingOpen, phaseAt, raceOrder, racePositions, type Game } from './game'
import { racePresentationTime } from './presentation'

const people = [
  { name: '小晴', color: '#cb9874', avatar: '晴' },
  { name: '阿牧', color: '#739982', avatar: '牧' },
  { name: '週末看馬', color: '#8e93be', avatar: '馬' },
  { name: '橘子汽水', color: '#cfac63', avatar: '橘' },
  { name: '慢慢來', color: '#b383a4', avatar: '慢' },
]
type Message = { id: number; person: number; text: string; time: number }
type Moment = 'betting' | 'assembly' | 'racing' | 'finish' | 'result'
const lines: Record<Moment, string[]> = {
  betting: ['來了來了，這場一起看 🐎', '今天賽場的陽光好舒服', '那匹白色的好好看', '我先看一下牠們散步哈哈', '每匹都有自己的步調欸', '有人也喜歡看集合嗎', '我在～剛倒完咖啡 ☕', '小馬走來走去好療癒', '這場幫 {horse} 號加油！'],
  assembly: ['集合了，先看比賽！', '排好隊了，好期待', '倒數的時候突然安靜 😂', '都就位了嗎 🐎', '來了，準備開跑！'],
  racing: ['{leader} 號跑到前面了！', '後面追得好近', '這個彎道看得好緊張', '加油加油 🐎', '鏡頭跟著跑很有臨場感', '我都忘記喝咖啡了哈哈', '還沒到終點，繼續看', '{leader} 號的步伐好快'],
  finish: ['衝線了！{winner} 號第一 👏', '最後這一段好精彩', '剛剛差距好小！', '跑完了，讓小馬休息一下'],
  result: ['恭喜 {winner} 號～', '這場看得很開心', '下一場我也在', '剛剛的衝線想再看一次 👀'],
}

export function RaceChat({ game, now }: { game: Game; now: number }) {
  const [messages, setMessages] = useState<Message[]>(() => [
    { id: 1, person: 0, text: '來了～一起看小馬比賽 🐎', time: Date.now() - 18000 },
    { id: 2, person: 1, text: '我也在，今天的賽場好漂亮', time: Date.now() - 11000 },
    { id: 3, person: 3, text: '咖啡準備好了 ☕', time: Date.now() - 4000 },
  ])
  const [draft, setDraft] = useState('')
  const canChat = game.bets.length > 0
  const list = useRef<HTMLDivElement>(null)
  const follow = useRef(true)
  const nextId = useRef(4)
  const context = useRef({ game, now })
  const lastLine = useRef('')
  const lastPerson = useRef(-1)
  useEffect(() => { context.current = { game, now } }, [game, now])
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout>
    const tick = () => {
      const { game: current, now: time } = context.current
      const phase = phaseAt(current, time)
      const seconds = racePresentationTime(Math.max(0, (time - current.startedAt - BET_MS) / 1000))
      const moment: Moment = phase === 'result' ? 'result' : phase === 'racing' ? (seconds >= 44.5 ? 'finish' : 'racing') : bettingOpen(current, time) ? 'betting' : 'assembly'
      const choices = lines[moment].filter(line => line !== lastLine.current)
      const template = choices[Math.floor(Math.random() * choices.length)]
      lastLine.current = template
      const person = (lastPerson.current + 1 + Math.floor(Math.random() * (people.length - 1))) % people.length
      lastPerson.current = person
      const positions = racePositions(current.seed, current.round, seconds)
      const leader = positions.indexOf(Math.max(...positions)) + 1
      const text = template.replace('{leader}', String(leader)).replace('{winner}', String(raceOrder(current.seed, current.round)[0])).replace('{horse}', String(1 + Math.floor(Math.random() * 8)))
      const message = { id: nextId.current++, person, text, time: Date.now() }
      setMessages(previous => [...previous, message].slice(-60))
      timer = setTimeout(tick, 4500 + Math.random() * 6500)
    }
    timer = setTimeout(tick, 4500)
    return () => clearTimeout(timer)
  }, [])
  useEffect(() => {
    if (follow.current && list.current) list.current.scrollTop = list.current.scrollHeight
  }, [messages])
  return <section className="race-chat">
    <header><MessageCircle size={18} /><h2>賽場聊天室</h2><span>模擬聊天</span></header>
    <div className="chat-topic"><i />一起看比賽，聊聊你的小馬<span>RACE {game.round}</span></div>
    <div className="chat-messages" ref={list} role="log" aria-label="賽事聊天訊息" aria-live="polite" onScroll={() => { const el = list.current; if (el) follow.current = el.scrollHeight - el.scrollTop - el.clientHeight < 45 }}>
      <p className="chat-notice">這裡的觀眾與對話為模擬內容。你的訊息只顯示於此頁。</p>
      {messages.map(message => {
        const person = message.person < 0 ? { name: '你', avatar: '我', color: '#41694f' } : people[message.person]
        return <div className={`chat-message ${message.person < 0 ? 'is-self' : ''}`} key={message.id}><span className="chat-avatar" style={{ background: person.color }}>{person.avatar}</span><div><div className="chat-meta"><b>{person.name}</b><time>{new Date(message.time).toLocaleTimeString('zh-TW', { hour12: false, hour: '2-digit', minute: '2-digit' })}</time></div><p>{message.text}</p></div></div>
      })}
    </div>
    <form className="chat-compose" onSubmit={event => { event.preventDefault(); const current = context.current.game; if (current.bets.length === 0 || Date.now() >= current.startedAt + ROUND_MS) return; const text = draft.trim(); if (!text) return; follow.current = true; const message = { id: nextId.current++, person: -1, text, time: Date.now() }; setMessages(previous => [...previous, message].slice(-60)); setDraft('') }}>
      <label className="chat-input-label" htmlFor="chat-draft">一起聊聊賽事</label><div><input id="chat-draft" disabled={!canChat} aria-describedby="chat-permission" value={draft} maxLength={160} placeholder={canChat ? '說點什麼，為小馬加油…' : '本局投注後即可發言'} autoComplete="off" onChange={event => setDraft(event.target.value)} /><button type="submit" disabled={!canChat || !draft.trim()} aria-label="傳送聊天訊息"><Send size={16} /></button></div><small id="chat-permission">{canChat ? `友善聊天 · ${draft.length}/160` : '本局尚未投注，可觀看聊天；投注後開放發言'}</small>
    </form>
  </section>
}

import { useEffect, useRef } from 'react'
import { MessageCircle, Send } from 'lucide-react'
import { speaker, type Chat, type Message } from './useRaceChat'

export function RaceChat({ chat, round }: { chat: Chat; round: number }) {
  const { messages, draft, setDraft, canChat } = chat
  const list = useRef<HTMLDivElement>(null)
  const follow = useRef(true)
  // Newest lines sit on top; keep them in view unless the reader has scrolled down into older ones.
  useEffect(() => {
    if (follow.current && list.current) list.current.scrollTop = 0
  }, [messages])
  return <section className="race-chat">
    <header><MessageCircle size={18} /><h2>賽場聊天室</h2><span>模擬聊天</span></header>
    <div className="chat-topic"><i />一起看比賽，聊聊你的小馬<span>RACE {round}</span></div>
    <div className="chat-messages" ref={list} role="log" aria-label="賽事聊天訊息" aria-live="polite" onScroll={() => { const el = list.current; if (el) follow.current = el.scrollTop < 45 }}>
      {[...messages].reverse().map(message => {
        const person = speaker(message)
        return <div className={`chat-message ${message.person < 0 ? 'is-self' : ''}`} key={message.id}><span className="chat-avatar" style={{ background: person.color }}>{person.avatar}</span><div><div className="chat-meta"><b>{person.name}</b><time>{new Date(message.time).toLocaleTimeString('zh-TW', { hour12: false, hour: '2-digit', minute: '2-digit' })}</time></div><p>{message.text}</p></div></div>
      })}
      <p className="chat-notice">這裡的觀眾與對話為模擬內容。你的訊息只顯示於此頁。</p>
    </div>
    <form className="chat-compose" onSubmit={event => { event.preventDefault(); follow.current = true; chat.send() }}>
      <label className="chat-input-label" htmlFor="chat-draft">一起聊聊賽事</label><div><input id="chat-draft" disabled={!canChat} aria-describedby="chat-permission" value={draft} maxLength={160} placeholder={canChat ? '說點什麼，為小馬加油…' : '本局投注後即可發言'} autoComplete="off" onChange={event => setDraft(event.target.value)} /><button type="submit" disabled={!canChat || !draft.trim()} aria-label="傳送聊天訊息"><Send size={16} /></button></div><small id="chat-permission">{canChat ? `友善聊天 · ${draft.length}/160` : '本局尚未投注，可觀看聊天；投注後開放發言'}</small>
    </form>
  </section>
}

const lineLife = 10_000
// Phones float recent lines over the stage, newest on top; each fades out after ten seconds instead of scrolling away.
export function StageChatFeed({ messages, now }: { messages: Message[]; now: number }) {
  return <div className="stage-chat" role="log" aria-label="賽事聊天訊息" aria-live="polite">
    {messages.filter(message => now - message.time < lineLife).slice(-6).reverse().map(message => {
      const person = speaker(message)
      return <p key={message.id} className={`${message.person < 0 ? 'is-self' : ''} ${now - message.time > lineLife - 800 ? 'is-leaving' : ''}`}><b style={message.person < 0 ? undefined : { color: person.color }}>{person.name}</b>{message.text}</p>
    })}
  </div>
}

export function StageChatCompose({ chat }: { chat: Chat }) {
  const { draft, setDraft, canChat } = chat
  return <form className="stage-chat-compose" onSubmit={event => { event.preventDefault(); chat.send() }}>
    <span>模擬聊天</span>
    <input aria-label="一起聊聊賽事" disabled={!canChat} value={draft} maxLength={160} placeholder={canChat ? '說點什麼，為小馬加油…' : '本局投注後即可發言'} autoComplete="off" onChange={event => setDraft(event.target.value)} />
    <button type="submit" disabled={!canChat || !draft.trim()} aria-label="傳送聊天訊息"><Send size={16} /></button>
  </form>
}

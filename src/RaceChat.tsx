import { useEffect, useRef } from 'react'
import { MessageCircle, Send } from 'lucide-react'
import { speaker, type Chat, type Message } from './useRaceChat'
import { useI18n } from './i18n'

export function RaceChat({ chat, round }: { chat: Chat; round: number }) {
  const { m, time } = useI18n()
  const { messages, draft, setDraft, canChat } = chat
  const list = useRef<HTMLDivElement>(null)
  const follow = useRef(true)
  // Newest lines sit on top; keep them in view unless the reader has scrolled down into older ones.
  useEffect(() => {
    if (follow.current && list.current) list.current.scrollTop = 0
  }, [messages])
  return <section className="race-chat">
    <header><MessageCircle size={18} /><h2>{m.chat.title}</h2><span>{m.chat.simulated}</span></header>
    <div className="chat-topic"><i />{m.chat.topic}<span>RACE {round}</span></div>
    <div className="chat-messages" ref={list} role="log" aria-label={m.chat.log} aria-live="polite" onScroll={() => { const el = list.current; if (el) follow.current = el.scrollTop < 45 }}>
      {[...messages].reverse().map(message => {
        const person = speaker(message, m.chat)
        return <div className={`chat-message ${message.person < 0 ? 'is-self' : ''}`} key={message.id}><span className="chat-avatar" style={{ background: person.color }}>{person.avatar}</span><div><div className="chat-meta"><b>{person.name}</b><time>{time(message.time)}</time></div><p>{message.text}</p></div></div>
      })}
      <p className="chat-notice">{m.chat.notice}</p>
    </div>
    <form className="chat-compose" onSubmit={event => { event.preventDefault(); follow.current = true; chat.send() }}>
      <label className="chat-input-label" htmlFor="chat-draft">{m.chat.compose}</label><div><input id="chat-draft" disabled={!canChat} aria-describedby="chat-permission" value={draft} maxLength={160} placeholder={canChat ? m.chat.placeholder : m.chat.locked} autoComplete="off" onChange={event => setDraft(event.target.value)} /><button type="submit" disabled={!canChat || !draft.trim()} aria-label={m.chat.send}><Send size={16} /></button></div><small id="chat-permission">{canChat ? m.chat.count(draft.length) : m.chat.permission}</small>
    </form>
  </section>
}

const lineLife = 10_000
// Phones float recent lines over the stage, newest on top; each fades out after ten seconds instead of scrolling away.
export function StageChatFeed({ messages, now }: { messages: Message[]; now: number }) {
  const { m } = useI18n()
  return <div className="stage-chat" role="log" aria-label={m.chat.log} aria-live="polite">
    {messages.filter(message => now - message.time < lineLife).slice(-6).reverse().map(message => {
      const person = speaker(message, m.chat)
      return <p key={message.id} className={`${message.person < 0 ? 'is-self' : ''} ${now - message.time > lineLife - 800 ? 'is-leaving' : ''}`}><b style={message.person < 0 ? undefined : { color: person.color }}>{person.name}</b>{message.text}</p>
    })}
  </div>
}

export function StageChatCompose({ chat }: { chat: Chat }) {
  const { m } = useI18n()
  const { draft, setDraft, canChat } = chat
  return <form className="stage-chat-compose" onSubmit={event => { event.preventDefault(); chat.send() }}>
    <span>{m.chat.simulated}</span>
    <input aria-label={m.chat.compose} disabled={!canChat} value={draft} maxLength={160} placeholder={canChat ? m.chat.placeholder : m.chat.locked} autoComplete="off" onChange={event => setDraft(event.target.value)} />
    <button type="submit" disabled={!canChat || !draft.trim()} aria-label={m.chat.send}><Send size={16} /></button>
  </form>
}

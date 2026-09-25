import { useEffect, useRef, useState } from 'react'
import { ROUND_MS, BET_MS, bettingOpen, fieldOf, phaseAt, raceOrder, racePositions, type Game } from './game'
import { racePresentationTime } from './presentation'
import type { Messages } from './i18n'

// Avatar colours by seat; names and lines come from the page's language.
const colors = ['#cb9874', '#739982', '#8e93be', '#cfac63', '#b383a4']
export type Message = { id: number; person: number; text: string; time: number }
type Moment = keyof Messages['chat']['lines']

export const speaker = (message: Message, chat: Messages['chat']) => message.person < 0
  ? { ...chat.self, color: '#41694f' }
  : { ...chat.people[message.person], color: colors[message.person] }

// One chat per page: phones show it over the stage, wider screens in the sidebar.
export function useRaceChat(game: Game, now: number, words: Messages['chat']) {
  const [messages, setMessages] = useState<Message[]>(() => words.opening.map((text, index) => (
    { id: index + 1, person: [0, 1, 3][index], text, time: Date.now() - [18000, 11000, 4000][index] }
  )))
  const [draft, setDraft] = useState('')
  const nextId = useRef(4)
  const context = useRef({ game, now, words })
  const lastLine = useRef('')
  const lastPerson = useRef(-1)
  useEffect(() => { context.current = { game, now, words } }, [game, now, words])
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout>
    const tick = () => {
      const { game: current, now: time, words: said } = context.current
      const phase = phaseAt(current, time)
      const seconds = racePresentationTime(Math.max(0, (time - current.startedAt - BET_MS) / 1000))
      const moment: Moment = phase === 'result' ? 'result' : phase === 'racing' ? (seconds >= 44.5 ? 'finish' : 'racing') : bettingOpen(current, time) ? 'betting' : 'assembly'
      const choices = said.lines[moment].filter(line => line !== lastLine.current)
      const template = choices[Math.floor(Math.random() * choices.length)]
      lastLine.current = template
      const person = (lastPerson.current + 1 + Math.floor(Math.random() * (said.people.length - 1))) % said.people.length
      lastPerson.current = person
      const field = fieldOf(current)
      const positions = racePositions(current.seed, current.round, seconds, field)
      const leader = positions.indexOf(Math.max(...positions)) + 1
      const text = template.replace('{leader}', String(leader)).replace('{winner}', String(raceOrder(current.seed, current.round, field)[0])).replace('{horse}', String(1 + Math.floor(Math.random() * field)))
      const message = { id: nextId.current++, person, text, time: Date.now() }
      setMessages(previous => [...previous, message].slice(-60))
      timer = setTimeout(tick, 4500 + Math.random() * 6500)
    }
    timer = setTimeout(tick, 4500)
    return () => clearTimeout(timer)
  }, [])
  const send = () => {
    const current = context.current.game
    if (current.bets.length === 0 || Date.now() >= current.startedAt + ROUND_MS) return
    const text = draft.trim()
    if (!text) return
    const message = { id: nextId.current++, person: -1, text, time: Date.now() }
    setMessages(previous => [...previous, message].slice(-60))
    setDraft('')
  }
  return { messages, draft, setDraft, send, canChat: game.bets.length > 0 }
}
export type Chat = ReturnType<typeof useRaceChat>

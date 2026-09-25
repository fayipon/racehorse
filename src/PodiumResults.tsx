import type { CSSProperties } from 'react'
import { HORSES } from './game'
import { useI18n } from './i18n'
import './podium.css'

export function PodiumResults({ order, round }: { order: number[]; round: number }) {
  const { m, horse, horseAlias } = useI18n()
  return <section className="podium-results" aria-label={m.podium.label(round)}>
    <ol className="podium-cutins" aria-label={m.podium.top}>
      {order.slice(0, 3).map((id, rank) => {
        return <li key={id} className={`podium-cutin place-${rank + 1}`} style={{ '--horse': HORSES[id - 1].color } as CSSProperties}>
          <div><span className="cutin-rank">{['1ST', '2ND', '3RD'][rank]}<b>{m.podium.places[rank]}</b></span><strong><b className="podium-number">{id}</b>{horse(id)}</strong><small>{horseAlias(id)}</small></div>
          <img src={`${import.meta.env.BASE_URL}assets/horse-head-${id}.webp`} alt="" />
        </li>
      })}
    </ol>
    <ol className="podium-rest" start={4} aria-label={m.podium.rest(order.length)} style={{ '--rest-rows': Math.min(5, order.length - 3) } as CSSProperties}>
      {order.slice(3).map((id, index) => {
        return <li key={id} value={index + 4} style={{ '--horse': HORSES[id - 1].color } as CSSProperties}>
          <span className="result-rank">{m.podium.place(index + 4)}</span>
          <b className="result-number" aria-label={m.podium.number(id)}>{id}</b>
          <strong>{horse(id)}</strong><small>{horseAlias(id)}</small>
        </li>
      })}
    </ol>
  </section>
}

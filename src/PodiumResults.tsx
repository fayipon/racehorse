import type { CSSProperties } from 'react'
import { Trophy } from 'lucide-react'
import { HORSES } from './game'
import './podium.css'

export function PodiumResults({ order, round }: { order: number[]; round: number }) {
  return <section className="podium-results" aria-label={`第 ${round} 場完整賽果`}>
    <div className="podium-featured">
      <header className="podium-heading"><span>SUNNY CUP · WINNERS' CIRCLE</span><h2>榮耀前三名</h2><i /></header>
      <ol className="podium-places">
        {order.slice(0, 3).map((id, rank) => {
          const horse = HORSES[id - 1]
          return <li key={id} className={`podium-place place-${rank + 1}`} style={{ '--horse': horse.color } as CSSProperties}>
            <span className="podium-medal">{rank === 0 && <Trophy size={15} />}{['冠軍', '亞軍', '季軍'][rank]}<small>{['1ST', '2ND', '3RD'][rank]}</small></span>
            <div><b className="podium-number">{id}</b><h3>{horse.name}<small>{horse.en}</small></h3></div>
          </li>
        })}
      </ol>
    </div>
    <ol className="podium-cutins" aria-label="前三名">
      {order.slice(0, 3).map((id, rank) => {
        const horse = HORSES[id - 1]
        return <li key={id} className={`podium-cutin place-${rank + 1}`} style={{ '--horse': horse.color } as CSSProperties}>
          <div><span className="cutin-rank">{['1ST', '2ND', '3RD'][rank]}<b>{['冠軍', '亞軍', '季軍'][rank]}</b></span><strong><b className="podium-number">{id}</b>{horse.name}</strong><small>{horse.en}</small></div>
          <img src={`${import.meta.env.BASE_URL}assets/horse-head-${id}.webp`} alt="" />
        </li>
      })}
    </ol>
    <ol className="podium-rest" start={4} aria-label="第四至第八名">
      {order.slice(3, 8).map((id, index) => {
        const horse = HORSES[id - 1]
        return <li key={id} value={index + 4} style={{ '--horse': horse.color } as CSSProperties}>
          <span className="result-rank">第 {index + 4} 名</span>
          <b className="result-number" aria-label={`${id} 號馬`}>{id}</b>
          <strong>{horse.name}</strong><small>{horse.en}</small>
        </li>
      })}
    </ol>
  </section>
}

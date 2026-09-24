import type { CSSProperties } from 'react'
import { Trophy } from 'lucide-react'
import { HORSES } from './game'
import './podium.css'

export function PodiumResults({ order, round }: { order: number[]; round: number }) {
  return <section className="podium-results" aria-label={`第 ${round} 場前三名`}>
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
  </section>
}

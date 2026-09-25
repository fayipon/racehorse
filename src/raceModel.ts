import course from '../godot/assets/course.json'
import { laneRadius } from './course'

// A race run to form. Each horse has a running style, and its distance behind a
// virtual pace-setter is a smooth curve over the race, pinned at the line to
// the official finishing margins. The result never changes, but the field stays
// together, positions shift gradually and the finish is usually a fight.
// Godot receives the same plan and evaluates it identically.
export type Style = 'front' | 'stalk' | 'mid' | 'close'
export type RacePlan = {
  winner: number
  ease: number
  cruise: number
  styles: Style[]
  // Per horse, flattened [stage, deficit, slope] knots. The stage is the
  // winner's progress; the deficit is behind the pace-setter, in laps.
  knots: number[][]
  finishTimes: number[]
}

export const WINNER_FINISH = 44.5
// On-screen metres: the minimap's nominal 1200 m is one lap of the oval.
export const HORSE_LENGTH = 2.4
export const lapLength = (lane: number, field: number) => 4 * course.halfStraight + 2 * Math.PI * laneRadius(lane, field)
// Margins are measured on the middle lane of the field.
export const referenceLap = (field: number) => lapLength((field - 1) / 2, field)
export const REFERENCE_LAP = referenceLap(course.laneCount)
const EASE = 1.1
const CRUISE = 1 / (WINNER_FINISH - EASE * (1 - Math.exp(-WINNER_FINISH / EASE)))
const STAGES = [0, .06, .2, .45, .65, .8, .92, 1]
// Metres behind the pace at the early stages, by style: [low, high].
const FORM: Record<Style, number[][]> = {
  front: [[0, .6], [0, 1.2], [0, 1.6], [0, 1.6]],
  stalk: [[.5, 1.8], [2, 4.5], [2.5, 5.5], [2, 5]],
  mid: [[1.2, 3], [5, 8.5], [7, 11], [6, 9.5]],
  close: [[2.2, 4], [8.5, 12.5], [11, 16], [10, 14]],
}
// How far each style has closed from its turn position to its final margin at
// 240 m and 100 m out: front-runners hold on, closers come late and fast.
const KICK: Record<Style, number[]> = { front: [.15, .55], stalk: [.3, .7], mid: [.35, .78], close: [.4, .86] }

// The winner's progress: an eased break into a steady gallop, 1 at the line.
export function leadProgress(time: number) {
  const t = Math.max(0, time)
  return CRUISE * (t - EASE * (1 - Math.exp(-t / EASE)))
}

function hermite(knots: number[], stage: number) {
  const last = knots.length - 3
  if (stage <= knots[0]) return knots[1]
  if (stage >= knots[last]) return knots[last + 1]
  let k = 3
  while (knots[k] < stage) k += 3
  const x0 = knots[k - 3], y0 = knots[k - 2], m0 = knots[k - 1], x1 = knots[k], y1 = knots[k + 1], m1 = knots[k + 2]
  const h = x1 - x0, t = (stage - x0) / h
  return (2 * t ** 3 - 3 * t ** 2 + 1) * y0 + (t ** 3 - 2 * t ** 2 + t) * h * m0 + (-2 * t ** 3 + 3 * t ** 2) * y1 + (t ** 3 - t ** 2) * h * m1
}

// Fritsch–Carlson slopes keep the curve free of overshoot; it settles flat at
// the line so no horse changes place in the last stride after the result.
function monotoneKnots(xs: number[], ys: number[]) {
  const n = xs.length
  const secants = xs.slice(1).map((x, i) => (ys[i + 1] - ys[i]) / (x - xs[i]))
  const slopes = xs.map((_, i) => i === 0 ? secants[0] : i === n - 1 ? 0 : secants[i - 1] * secants[i] <= 0 ? 0 : (secants[i - 1] + secants[i]) / 2)
  for (let i = 0; i < n - 1; i++) {
    if (secants[i] === 0) { slopes[i] = 0; slopes[i + 1] = 0; continue }
    const a = slopes[i] / secants[i], b = slopes[i + 1] / secants[i], r = a * a + b * b
    if (r > 9) { const s = 3 / Math.sqrt(r); slopes[i] = s * a * secants[i]; slopes[i + 1] = s * b * secants[i] }
  }
  const round = (v: number) => Math.round(v * 1e6) / 1e6
  return xs.flatMap((x, i) => [x, round(ys[i]), round(slopes[i])])
}

export function planProgress(plan: RacePlan, index: number, time: number) {
  const stage = plan.cruise * (Math.max(0, time) - plan.ease * (1 - Math.exp(-Math.max(0, time) / plan.ease)))
  return stage - (hermite(plan.knots[index], stage) - hermite(plan.knots[plan.winner], stage))
}

// `order` is the official result, one entry per runner; `random` is seeded per round.
export function makeRacePlan(order: number[], random: () => number): RacePlan {
  const field = order.length
  const between = ([low, high]: number[]) => low + random() * (high - low)
  // Seven set styles, then one near the pace and, in bigger fields, any style.
  const extra = Array.from({ length: field - 7 }, (_, i): Style => i === 0 ? (['front', 'stalk', 'mid'] as Style[])[Math.floor(random() * 3)] : (['front', 'stalk', 'mid', 'close'] as Style[])[Math.floor(random() * 4)])
  const pool: Style[] = ['front', 'stalk', 'stalk', 'mid', 'mid', 'close', 'close', ...extra]
  for (let i = pool.length - 1; i > 0; i--) { const j = Math.floor(random() * (i + 1)); [pool[i], pool[j]] = [pool[j], pool[i]] }
  // Winners come from anywhere, but most often from just off the pace.
  const roll = random()
  const wanted: Style = roll < .25 ? 'front' : roll < .6 ? 'stalk' : roll < .85 ? 'mid' : 'close'
  pool.splice(pool.indexOf(wanted), 1)
  const styles: Style[] = new Array(field)
  styles[order[0] - 1] = wanted
  order.slice(1).forEach((id, i) => { styles[id - 1] = pool[i] })
  // Finishing margins, in reference-lap metres, when the winner hits the line.
  // They are kept in progress terms so horses cross in the official order
  // whatever their lane.
  const margins = [0]
  const photo = random()
  margins.push(photo < .2 ? between([.1, .6]) : photo < .45 ? between([.6, 1.4]) : photo < .75 ? between([1.4, 3.5]) : between([3.5, 7]))
  for (let rank = 2; rank < field; rank++) margins.push(margins[rank - 1] + between(rank <= 3 ? [.3, 2.6] : [.4, 3.2]))
  // Half the races have a mid-race move: a stalker or closer from off the pace
  // runs up to dispute the lead down the back straight, then drops back in.
  const mover = random() < .5 ? Math.floor(random() * field) : -1
  const knots = styles.map((style, index) => {
    const rank = order.indexOf(index + 1)
    const early = FORM[style].map(between)
    if (index === mover && style !== 'front') early[2] = between([0, 1.6])
    const final = margins[rank]
    const turn = early[3]
    const kick = KICK[style].map(share => turn + (final - turn) * share + between([-.3, .3]))
    const metres = [0, ...early, ...kick, final]
    return monotoneKnots(STAGES, metres.map(m => Math.max(0, m) / referenceLap(field)))
  })
  const plan: RacePlan = { winner: order[0] - 1, ease: EASE, cruise: CRUISE, styles, knots, finishTimes: [] }
  // Each horse finishes when its own curve reaches the line.
  plan.finishTimes = styles.map((_, index) => {
    const target = 1 + hermite(knots[index], 1) - hermite(knots[plan.winner], 1)
    let t = WINNER_FINISH
    for (let i = 0; i < 8; i++) t = target / CRUISE + EASE * (1 - Math.exp(-t / EASE))
    return Math.round(t * 1000) / 1000
  })
  return plan
}

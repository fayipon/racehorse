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

// A script's say over one race. Horses are 0-based; margins are lengths behind
// the horse ahead, from second place on; a checkpoint puts `order` in front, in
// that order, when the leader reaches `at` of the nominal 1200 m.
export type Finish = 'photo' | 'close' | 'clear' | 'easy'
export type Checkpoint = { at: number; order: number[]; by?: number }
export type PlanScript = { styles?: (Style | undefined)[]; finish?: Finish; margins?: (number | undefined)[]; checkpoints?: Checkpoint[] }
// The photo roll each finish stands in for, picking its band for second place.
const FINISH: Record<Finish, number> = { photo: 0, close: .3, clear: .6, easy: .9 }

// `order` is the official result, one entry per runner; `random` is seeded per round.
export function makeRacePlan(order: number[], random: () => number): RacePlan {
  const base = generateBase(order, random, {})
  return planFrom(order, base.styles, STAGES, base.metres)
}

// Metres behind the pace at each of STAGES, per horse. A script overrides
// values only after they are drawn, so every race draws the same numbers.
function generateBase(order: number[], random: () => number, script: PlanScript) {
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
  script.styles?.forEach((style, index) => { if (style) styles[index] = style })
  // Finishing margins, in reference-lap metres, when the winner hits the line.
  // They are kept in progress terms so horses cross in the official order
  // whatever their lane.
  const margins = [0]
  const rolled = random()
  const photo = script.finish ? FINISH[script.finish] : rolled
  margins.push(photo < .2 ? between([.1, .6]) : photo < .45 ? between([.6, 1.4]) : photo < .75 ? between([1.4, 3.5]) : between([3.5, 7]))
  for (let rank = 2; rank < field; rank++) margins.push(margins[rank - 1] + between(rank <= 3 ? [.3, 2.6] : [.4, 3.2]))
  if (script.margins) {
    const drawn = margins.slice(1).map((margin, i) => margin - margins[i])
    drawn.forEach((gap, i) => { margins[i + 1] = margins[i] + (script.margins?.[i] === undefined ? gap : script.margins[i]! * HORSE_LENGTH) })
  }
  // Half the races have a mid-race move: a stalker or closer from off the pace
  // runs up to dispute the lead down the back straight, then drops back in.
  const mover = random() < .5 ? Math.floor(random() * field) : -1
  const metres = styles.map((style, index) => {
    const rank = order.indexOf(index + 1)
    const early = FORM[style].map(between)
    if (index === mover && style !== 'front') early[2] = between([0, 1.6])
    const final = margins[rank]
    const turn = early[3]
    const kick = KICK[style].map(share => turn + (final - turn) * share + between([-.3, .3]))
    return [0, ...early, ...kick, final]
  })
  return { styles, metres }
}

// A scripted race: the generated race with the script's overrides, bent through
// its checkpoints. `makeRandom` restarts the round's generator, so each attempt
// draws the same numbers. What the plan cannot honour and still run like a race
// is dropped, the hardest checkpoint first, then the margins, then the styles.
export function buildRacePlan(order: number[], makeRandom: () => () => number, script: PlanScript): { plan: RacePlan; dropped: string[] } {
  const active: PlanScript = { ...script, checkpoints: [...script.checkpoints ?? []].sort((a, b) => a.at - b.at) }
  const dropped: string[] = []
  for (;;) {
    const base = generateBase(order, makeRandom(), active)
    const bent = active.checkpoints!.length ? bend(order, base.metres, active.checkpoints!) : { stages: STAGES, metres: base.metres, demand: [] }
    const plan = planFrom(order, base.styles, bent.stages, bent.metres)
    if (healthy(plan)) return { plan, dropped }
    if (bent.demand.length) {
      const hardest = bent.demand.reduce((worst, demand, i) => demand >= bent.demand[worst] ? i : worst, 0)
      dropped.push(`checkpoint ${active.checkpoints![hardest].at}m`)
      active.checkpoints = active.checkpoints!.filter((_, i) => i !== hardest)
    } else if (active.margins || active.finish) {
      dropped.push('margins'); active.margins = undefined; active.finish = undefined
    } else if (active.styles) {
      dropped.push('styles'); active.styles = undefined
    } else return { plan, dropped }
  }
}

// How a plan runs, sampled as the race is shown: the largest change in the
// leader's gap per 0.1 s, the fastest any horse gains or loses on the winner
// (lengths per 0.1 s), the widest the field spreads, and whether anyone goes backwards.
export function planHealth(plan: RacePlan) {
  const field = plan.knots.length
  const lengths = (progress: number) => progress * referenceLap(field) / HORSE_LENGTH
  let leadStep = 0, rate = 0, spread = 0, backwards = false
  let previous: number[] = [], previousGap = 0
  for (let step = 10; step <= WINNER_FINISH * 10; step++) {
    const p = Array.from({ length: field }, (_, i) => planProgress(plan, i, step / 10))
    const sorted = [...p].sort((a, b) => b - a)
    const gap = lengths(sorted[0] - sorted[1])
    spread = Math.max(spread, lengths(sorted[0] - sorted[field - 1]))
    if (previous.length) {
      if (step > 11) leadStep = Math.max(leadStep, Math.abs(gap - previousGap))
      p.forEach((value, i) => {
        if (value < previous[i] - 1e-9) backwards = true
        rate = Math.max(rate, Math.abs(lengths(value - p[plan.winner] - previous[i] + previous[plan.winner])))
      })
    }
    previous = p; previousGap = gap
  }
  const finish = Array.from({ length: field }, (_, i) => planProgress(plan, i, WINNER_FINISH))
  return { leadStep, rate, spread, finishSpread: lengths(Math.max(...finish) - Math.min(...finish)), backwards }
}
// Limits a scripted race keeps, set just past the worst the generator runs over
// thousands of rounds (0.124, 0.246 and field − 0.3 lengths).
const LEAD_STEP = .13
const RATE = .27
function healthy(plan: RacePlan) {
  const health = planHealth(plan)
  return !health.backwards && health.leadStep <= LEAD_STEP && health.rate <= RATE && health.spread <= Math.max(plan.knots.length + 1, health.finishSpread + 2)
}

// Checkpoint bending, in metres behind the pace. Each checkpoint holds its
// order through a short stretch either side, so it is on screen for about a
// second; the shift fades in before it, between checkpoints and out before the
// line at no more than a mid-race move's pace (the late kick reaches 220 m per stage).
const SEPARATION = .25 * HORSE_LENGTH
const HOLD = .015
const CLEAR = .04
const MIN_SPAN = .2
const RATE_M = 60
const smooth = (x: number) => { const u = Math.min(1, Math.max(0, x)); return u * u * (3 - 2 * u) }
function bend(order: number[], metres: number[][], checkpoints: Checkpoint[]) {
  const field = order.length, winner = order[0] - 1, lap = referenceLap(field)
  const base = metres.map(m => monotoneKnots(STAGES, m))
  const at = (curves: number[][], s: number) => curves.map(k => hermite(k, s))
  // The stage at which the leader shows `metres` on the nominal 1200 m.
  const stageOf = (curves: number[][], metres: number) => {
    let s = metres / 1200
    for (let i = 0; i < 4; i++) { const d = at(curves, s); s = metres / 1200 - (d[winner] - Math.min(...d)) / lap }
    return Math.min(.95, Math.max(.04, s))
  }
  const cascade = (rank: number[], values: number[], gaps: number[]) => {
    const y = [...values]
    for (let r = 1; r < rank.length; r++) {
      const need = y[rank[r - 1]] + gaps[r] - y[rank[r]]
      if (need > 0) for (let q = r; q < rank.length; q++) y[rank[q]] += need
    }
    return y
  }
  let curves = base
  let result = { stages: STAGES, metres, demand: [] as number[] }
  for (let pass = 0; pass < 2; pass++) {
    // Checkpoints 100 m apart can land closer in stages when the leader is far
    // ahead of the winner; their holds must not overlap.
    const stages: number[] = []
    for (const checkpoint of checkpoints) {
      const s = stageOf(curves, checkpoint.at)
      stages.push(stages.length ? Math.max(s, stages.at(-1)! + 2 * HOLD + .02) : s)
    }
    const holds = checkpoints.map((checkpoint, j) => {
      const s = stages[j]
      const d = at(base, s)
      const rest = d.map((_, i) => i).filter(i => !checkpoint.order.includes(i)).sort((a, b) => d[a] - d[b])
      const rank = [...checkpoint.order, ...rest]
      const sorted = [...d].sort((a, b) => a - b)
      const permuted: number[] = []
      rank.forEach((horse, r) => { permuted[horse] = sorted[r] })
      const gaps = rank.map((_, r) => r === 0 ? 0 : r === 1 && checkpoint.by ? Math.max(SEPARATION, checkpoint.by * HORSE_LENGTH) : r <= checkpoint.order.length ? SEPARATION : 0)
      const target = cascade(rank, permuted, gaps)
      const shift = target.map((y, i) => y - d[i])
      const hold = (u: number) => cascade(rank, at(base, u).map((y, i) => y + shift[i]), gaps)
      return { s, points: [s - HOLD, s, s + HOLD].map(u => ({ u, y: u === s ? target : hold(u) })), demand: Math.max(...shift.map(Math.abs)) }
    })
    const spanOf = (d: number) => Math.max(MIN_SPAN, 1.5 * Math.abs(d) / RATE_M)
    const before = holds.map(h => h.points[0].y.map((y, i) => y - hermite(base[i], h.points[0].u)))
    const after = holds.map(h => h.points[2].y.map((y, i) => y - hermite(base[i], h.points[2].u)))
    const shiftAt = (g: number, i: number) => {
      const first = holds[0].points[0].u, last = holds.at(-1)!.points[2].u
      if (g <= first) return before[0][i] * smooth(1 - (first - g) / Math.min(spanOf(before[0][i]), first))
      if (g >= last) return after.at(-1)![i] * (1 - smooth((g - last) / Math.min(spanOf(after.at(-1)![i]), 1 - last)))
      const j = holds.findIndex((h, k) => k < holds.length - 1 && g >= h.points[2].u && g <= holds[k + 1].points[0].u)
      const from = holds[j].points[2].u, to = holds[j + 1].points[0].u
      return after[j][i] + (before[j + 1][i] - after[j][i]) * smooth((g - from) / (to - from))
    }
    const kept = STAGES.filter(x => x === 0 || x === 1 || holds.every(h => Math.abs(x - h.s) > CLEAR + HOLD))
    const grid = [...kept.map(u => ({ u, hold: -1 })), ...holds.flatMap((h, j) => h.points.map(p => ({ u: p.u, hold: j })))].sort((a, b) => a.u - b.u)
    const bent = metres.map((_, i) => grid.map(({ u, hold }) => Math.max(0, hold >= 0 ? holds[hold].points.find(p => p.u === u)!.y[i] : hermite(base[i], u) + shiftAt(u, i))))
    result = { stages: grid.map(p => p.u), metres: bent, demand: holds.map(h => h.demand) }
    curves = bent.map(m => monotoneKnots(result.stages, m))
  }
  return result
}

function planFrom(order: number[], styles: Style[], stages: number[], metres: number[][]): RacePlan {
  const field = order.length
  const knots = metres.map(m => monotoneKnots(stages, m.map(v => Math.max(0, v) / referenceLap(field))))
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

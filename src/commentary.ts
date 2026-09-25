import course from '../godot/assets/course.json'
import manifest from './commentary-clips.json'
import { laneRadius, makeParadePlan } from './course'
import { raceOrder, racePlan, type Result } from './game'
import { racePresentationTime } from './presentation'
import { HORSE_LENGTH, planProgress, referenceLap, WINNER_FINISH, type RacePlan } from './raceModel'

// A race call built like a real broadcast. The whole race is known when the
// gates open, so the call is planned in advance: each line is spoken when what
// it describes is on screen, key calls first, and position reports fill the
// gaps. Lines are short pre-recorded phrases (scripts/commentary-lines.json).
export type Utterance = { at: number; clips: string[]; priority: number }
// `sprite` is 0 for the main voice file, 1 for the lines naming runners 9–12.
export type Cue = { at: number; clip: string; offset: number; duration: number; sprite: 0 | 1 }

// Lines naming runners 9–12 are in a second file that only the bigger cups load.
const EXTRA = manifest.extra.clips as Record<string, number[]>
const CLIPS: Record<string, number[]> = { ...manifest.clips, ...EXTRA }
const METRES = 1200
const STEP = .05
const WITHIN = .06
// Where the pace reaches each part of the oval, on the middle lane of the field.
function landmarks(field: number) {
  const lap = referenceLap(field)
  const bend = Math.PI * laneRadius((field - 1) / 2, field)
  return { turnOne: course.halfStraight / lap, backStraight: (course.halfStraight + bend) / lap, finalBend: (3 * course.halfStraight + bend) / lap, homeStraight: (3 * course.halfStraight + 2 * bend) / lap }
}

type Frame = { v: number; p: number[]; rank: number[] }
const horse = (id: string, index: number) => `${id}.${index + 1}`
// Horses without recorded lines are never named: a line naming one is dropped.
const recorded = (clips: string[]) => clips.every(id => Object.hasOwn(CLIPS, id))
export const clipLength = (clips: string[]) => clips.reduce((sum, id) => sum + (CLIPS[id]?.[1] ?? 0), 0) + WITHIN * (clips.length - 1)

// The presentation clock only slows or holds, never reverses.
export function realFromVisual(visual: number) {
  let low = 0, high = 60
  for (let i = 0; i < 40; i++) { const mid = (low + high) / 2; if (racePresentationTime(mid) < visual - 1e-6) low = mid; else high = mid }
  return high
}

function sample(plan: RacePlan, v: number): Frame {
  const p = plan.knots.map((_, i) => planProgress(plan, i, v))
  return { v, p, rank: p.map((_, i) => i).sort((a, b) => p[b] - p[a]) }
}

class Timeline {
  items: Utterance[] = []
  // A beat between sentences: unhurried before the gates, shorter once the
  // race is flying.
  pause(at: number) { return at < 0 ? 1.2 : at > 36 ? .1 : .2 }
  // The earliest start at or after `desired` where `length` seconds fit.
  slot(desired: number, length: number) {
    let start = desired
    for (let guard = 0; guard < 40; guard++) {
      const blocker = this.items.find(u => start < u.at + clipLength(u.clips) + this.pause(u.at) && start + length + this.pause(start) > u.at)
      if (!blocker) break
      start = blocker.at + clipLength(blocker.clips) + this.pause(blocker.at)
    }
    return start
  }
  commit(at: number, clips: string[], priority: number) {
    if (!recorded(clips)) return false
    this.items.push({ at, clips, priority })
    this.items.sort((a, b) => a.at - b.at)
    return true
  }
  place(desired: number, clips: string[], priority: number, maxDelay: number) {
    const start = this.slot(desired, clipLength(clips))
    if (start - desired > maxDelay) return false
    return this.commit(start, clips, priority)
  }
}

// Before the gates: an unhurried chat over the paddock, in betting time
// (60 s before the gates open is 0). Form lines come from the real results,
// running styles from this race's plan and paddock asides from what the horses
// are doing on screen; the back stories are made up and fixed per horse.
function planPreRace(timeline: Timeline, seed: number, round: number, field: number, history: Result[]) {
  let state = (seed ^ Math.imul(round, 374761393) ^ 0x9e3779b9) >>> 0
  const random = () => { state = (Math.imul(state, 1664525) + 1013904223) >>> 0; return state / 4294967296 }
  const shuffle = <T,>(items: T[]) => { for (let i = items.length - 1; i > 0; i--) { const j = Math.floor(random() * (i + 1)); [items[i], items[j]] = [items[j], items[i]] } return items }
  const race = (betting: number) => betting - 60
  timeline.place(race(1.5), [round === 1 ? 'welcome1' : round % 2 ? 'welcome2' : 'welcome3'], 8, 0)
  timeline.place(race(36), ['betReminder'], 8, 2)
  timeline.place(race(44.6), ['lastCall'], 9, .8)
  timeline.place(race(48.4), ['closed'], 9, .6)
  timeline.place(race(53), ['gateQuiet'], 9, .8)

  // A horse grazing, looking about or resting its head is pointed out while it
  // is still doing it.
  const parade = makeParadePlan(seed, round, field)
  const moods = ['', 'looking', 'resting', 'grazing']
  const asides = shuffle(parade.flatMap((segments, index) => segments
    .filter(s => s.mood > 0 && s.from === s.to && s.start > 6 && s.end < 45)
    .map(s => ({ index, start: s.start, end: s.end, clip: horse(moods[s.mood], index) }))))
  let pointed = 0
  for (const aside of asides) {
    const length = clipLength([aside.clip])
    if (pointed >= 1 || aside.end - aside.start < length + .8) continue
    if (timeline.place(race(aside.start + .4), [aside.clip], 6, aside.end - aside.start - length - .5)) pointed++
  }

  // Form lines, from the real results; at most three, each about a different horse.
  const stories: string[][] = []
  const mentioned = new Set<number>()
  const recent = history.slice(0, 6)
  if (!recent.length) stories.push(['firstRace'])
  else {
    const place = (r: Result, index: number) => r.order.indexOf(index + 1)
    const all = shuffle(Array.from({ length: field }, (_, i) => i))
    const facts: [string, number | undefined][] = [
      ['lastWinner', recent[0].order[0] - 1],
      ['formTop3', recent.length >= 3 ? all.find(i => recent.slice(0, 3).every(r => place(r, i) < 3)) : undefined],
      ['twoWins', all.find(i => recent.filter(r => place(r, i) === 0).length >= 2)],
      ['runnerUp', recent[0].order[1] - 1],
      ['slump', recent.length >= 2 ? all.find(i => recent.slice(0, 2).every(r => place(r, i) >= field - 2)) : undefined],
    ]
    for (const [id, index] of facts) {
      if (index === undefined || mentioned.has(index) || mentioned.size >= 3) continue
      mentioned.add(index)
      stories.push([horse(id, index)])
    }
  }
  // Interleaved with the form: made-up back stories and a word on how a horse
  // likes to run, which this race's plan then bears out.
  const plan = racePlan(seed, round, field)
  const styleLine = { front: 'styleFront', stalk: 'styleStalk', mid: 'styleMid', close: 'styleClose' } as const
  const others = shuffle(Array.from({ length: field }, (_, i) => i).filter(i => !mentioned.has(i)))
  const telling = [...others].sort((a, b) => Number(['close', 'front'].includes(plan.styles[b])) - Number(['close', 'front'].includes(plan.styles[a]))).slice(0, 2)
  const bios = others.filter(i => !telling.includes(i))
  const bio = (index: number) => [horse(random() < .5 ? 'bio1' : 'bio2', index)]
  const style = (index: number) => [horse(styleLine[plan.styles[index]], index)]
  const form = stories.splice(0)
  stories.push(form[0], bio(bios[0]), style(telling[0]))
  if (form[1]) stories.push(form[1])
  stories.push(bio(bios[1]), style(telling[1]))
  if (form[2]) stories.push(form[2])
  stories.push(bio(bios[2]), [shuffle(['equalOdds', 'breeze', 'fullStand', 'warmup'])[0]])
  // Stories fill the free stretches in turn and stop before betting closes.
  let time = race(5.5)
  for (const story of stories) {
    const start = timeline.slot(time, clipLength(story))
    if (start + clipLength(story) > race(44.3)) continue
    timeline.commit(start, story, 4)
    time = start + clipLength(story)
  }
}

export function planCommentary(seed: number, round: number, field: number, history: Result[] = []): Utterance[] {
  const plan = racePlan(seed, round, field)
  const order = raceOrder(seed, round, field)
  const lengths = (progress: number) => progress * referenceLap(field) / HORSE_LENGTH
  const { turnOne, backStraight, finalBend, homeStraight } = landmarks(field)
  const winner = order[0] - 1
  const frames: Frame[] = []
  for (let v = 0; v <= WINNER_FINISH + .001; v += STEP) frames.push(sample(plan, Math.min(v, WINNER_FINISH)))
  const at = (v: number) => sample(plan, v)
  const leaderAt = (v: number) => at(v).rank[0]
  const gap = (f: Frame, a: number, b: number) => lengths(f.p[a] - f.p[b])
  // The moment the pace reaches a progress mark.
  const reach = (progress: number) => frames.find(f => f.p[f.rank[0]] >= progress)?.v ?? WINNER_FINISH
  const toGo = (metres: number) => reach(1 - metres / METRES)
  const timeline = new Timeline()
  planPreRace(timeline, seed, round, field, history)
  const real = realFromVisual

  // The gates and the finish are fixed points the rest of the call fits around:
  // the winner's name twice, the crossing mid-phrase, then the verdict.
  timeline.place(.08, ['gate', 'breakAway'], 10, 0)
  const crossing = real(WINNER_FINISH)
  const decider = frames.findLast(f => f.rank[0] !== winner)
  const lastLeadChange = decider ? decider.v : 0
  const margin = lengths(1 - planProgress(plan, order[1] - 1, WINNER_FINISH))
  const over = [horse('over', winner)]
  const overAt = crossing - clipLength(over) * .55
  const chant = [horse('call', winner), horse('call', winner)]
  const chantAt = overAt - clipLength(chant) - .1
  timeline.place(chantAt, chant, 10, 0)
  timeline.place(overAt, over, 10, 0)
  const call = [margin < .25 ? 'photo' : 'line']
  const callAt = overAt + clipLength(over) + .1
  timeline.place(callAt, call, 10, 0)
  const verdict = lastLeadChange > toGo(60) ? 'lastStride' : lastLeadChange > toGo(400) ? 'comeback' : lastLeadChange < toGo(800) ? 'wire' : margin > 1.8 ? 'clear' : ''
  const result = [...(verdict ? [verdict] : []), horse('wins', winner)]
  const resultAt = callAt + clipLength(call) + .15
  timeline.place(resultAt, result, 10, 0)
  timeline.place(Math.max(crossing + 4.4, resultAt + clipLength(result) + .3), [horse('secondPlace', order[1] - 1), horse('thirdPlace', order[2] - 1)], 5, 2)

  // The run to the line follows the reference call: the leader holding on, the
  // challenger named, then the gap called length by length as it closes. Each
  // line says what is on screen when the voice gets to it.
  const leader200 = leaderAt(toGo(200))
  const challenger = leader200 !== winner ? winner : order[1] - 1
  const chased = challenger === winner ? leader200 : winner
  let cursor = real(toGo(200))
  const say = (clips: string[]) => {
    if (cursor + clipLength(clips) > chantAt - .1) return false
    timeline.place(cursor, clips, 9, 0)
    cursor += clipLength(clips) + .1
    return true
  }
  say(['m200'])
  const at200 = at(racePresentationTime(cursor)).rank[0]
  say([at200 === leader200 ? horse('holds', leader200) : horse('takesLead', at200)])
  const moving = at(racePresentationTime(cursor))
  say([horse(challenger > moving.rank[0] ? 'outside' : 'inside', challenger)])
  let closest = 9
  let passCalled = false
  let hundred = false
  while (cursor < chantAt - .5) {
    const f = at(racePresentationTime(cursor))
    const behind = gap(f, chased, challenger)
    const step = behind <= .12 ? 2 : behind <= .5 ? 1 : behind <= 1.05 ? 0 : behind <= 1.8 ? -1 : 9
    // The surge is called as it happens, or just before when time is short.
    const surging = gap(at(racePresentationTime(cursor + .8)), chased, challenger) < 0
    if (challenger === winner && (behind < 0 || surging) && !passCalled) {
      passCalled = true
      if (say([horse('breaksOut', winner), horse('fights', chased)]) || say([horse('breaksOut', winner)])) continue
    } else if (behind >= 0 && step !== 9 && (closest === 9 || step > closest)) {
      closest = step
      if (say(step === 2 ? ['level'] : step === 1 ? ['halfLength'] : step === 0 ? ['oneLength'] : [horse('nearer', challenger)])) continue
    } else if (!hundred && f.p[f.rank[0]] >= 1 - 100 / METRES) {
      hundred = true
      // A distance call must not talk over the pass or the gap closing.
      const later = at(racePresentationTime(cursor + clipLength(['m100']) + .2))
      const behindLater = gap(later, chased, challenger)
      const stepLater = behindLater <= .12 ? 2 : behindLater <= .5 ? 1 : behindLater <= 1.05 ? 0 : behindLater <= 1.8 ? -1 : 9
      const quiet = !(challenger === winner && behindLater < 0) && !(behindLater >= 0 && stepLater !== 9 && stepLater > closest)
      if (quiet && say(['m100'])) continue
    } else if (closest >= 1 && !passCalled && f.p[f.rank[0]] >= 1 - 70 / METRES) {
      passCalled = true
      if (say([horse('drives', challenger), horse('fights', chased)])) continue
    }
    cursor += .1
  }

  // Lines that name horses by place are composed clip by clip, so each name is
  // the horse in that place at the moment it is spoken.
  type Picker = (f: Frame, named: Set<number>) => string | null
  type Part = string | Picker
  const compose = (start: number, parts: Part[]) => {
    let t = start
    const named = new Set<number>()
    const clips: string[] = []
    for (const part of parts) {
      const id = typeof part === 'string' ? part : part(at(racePresentationTime(t)), named)
      if (!id) continue
      // A report naming a horse without recorded lines is not made at all.
      if (!recorded([id])) return []
      clips.push(id)
      t += CLIPS[id][1] + WITHIN
    }
    return clips
  }
  const placeLive = (desired: number, parts: Part[], priority: number, maxDelay: number) => {
    const start = timeline.slot(desired, clipLength(compose(desired, parts)))
    if (start - desired > maxDelay) return null
    const clips = compose(start, parts)
    if (!clips.length || timeline.slot(start, clipLength(clips)) !== start) return null
    timeline.commit(start, clips, priority)
    return clips
  }
  const inPlace = (id: string, place: number): Picker => (f, named) => {
    const i = f.rank[place]
    if (named.has(i)) return null
    named.add(i)
    return horse(id, i)
  }
  const margin1 = (f: Frame) => gap(f, f.rank[0], f.rank[1])
  const pace: Part[] = [inPlace('leads', 0), f => margin1(f) >= 1.8 ? 'byTwo' : margin1(f) >= .9 ? 'byOne' : null, (f, named) => margin1(f) < .9 ? inPlace('second', 1)(f, named) : null]

  // Lead changes before the sprint are called as they happen.
  let current = leaderAt(3)
  let since = 3
  for (const f of frames) {
    if (f.v < 3 || f.v > toGo(210)) continue
    if (f.rank[0] === current) { since = f.v; continue }
    if (f.v - since < .6) continue
    current = f.rank[0]
    since = f.v
    timeline.place(real(f.v - .6), f.v > 30 ? [horse('passes', current), horse('takesLead', current)] : [horse('takesLead', current)], 6, 1)
  }

  // Landmarks of the first three quarters, each with a word on the order.
  placeLive(real(2.2), [inPlace('quick', 0)], 7, 1)
  placeLive(real(reach(turnOne)), ['firstBend', inPlace('lead', 0), inPlace('second', 1), inPlace('tracks', 2)], 7, 1.5)
  placeLive(real(toGo(1000)), ['m1000', ...pace], 6, 1.5)
  timeline.place(real(reach(backStraight)), ['backStraight'], 5, 1.5)
  placeLive(real(toGo(600)), ['m600', ...pace], 6, 1.5)
  placeLive(real(reach(finalBend)), ['finalBend', inPlace('leads', 0)], 7, 1.2)
  // The horse moving best into the straight gets the call at 400 m.
  const at400 = at(toGo(400)), before400 = at(toGo(400) - 2)
  const mover = at400.rank.slice(1, 6).sort((a, b) => (at400.p[b] - before400.p[b]) - (at400.p[a] - before400.p[a]))[0]
  timeline.place(real(toGo(400)), ['m400', horse('quickens', mover)], 7, 1)
  const home = reach(homeStraight)
  if (home > toGo(200) + 1.5) timeline.place(real(home), ['homeStraight'], 6, .6)

  // Position reports fill the quiet stretches.
  const said = new Map<string, number>()
  const recent = (key: string, time: number, within: number) => (said.get(key) ?? -99) > time - within
  const pick = (id: string, choose: (f: Frame, time: number) => number | undefined): ((time: number) => Picker) => time => (f, named) => {
    const i = choose(f, time)
    if (i === undefined || named.has(i)) return null
    named.add(i)
    return horse(id, i)
  }
  const reports: ((time: number) => Part[])[] = [
    () => [inPlace('lead', 0), inPlace('second', 1)],
    () => [inPlace('third', 2)],
    time => [pick('rail', f => f.rank.slice(0, 4).find(i => i <= 2))(time)],
    time => [pick('wide', f => f.rank.slice(1, 5).find(i => i >= field - 3))(time)],
    () => [inPlace('midfield', Math.floor(field / 2))],
    time => [pick('waiting', f => f.rank.slice(5).find(i => plan.styles[i] === 'close'))(time), (f, named) => named.size ? null : inPlace('last', field - 1)(f, named)],
    time => [pick('improving', (f, t) => {
      const earlier = at(racePresentationTime(Math.max(0, t - 5)))
      return f.rank.find(i => earlier.rank.indexOf(i) - f.rank.indexOf(i) >= 2 && f.rank.indexOf(i) > 0)
    })(time)],
    () => [f => lengths(f.p[f.rank[0]] - f.p[f.rank[field - 1]]) < 5 ? 'tight' : null],
    () => [f => margin1(f) < .4 ? 'closeBehind' : null],
  ]
  let turnIndex = 0
  const end = real(toGo(230))
  for (let time = 5; time < end; ) {
    const start = timeline.slot(time, .9)
    if (start + .9 > end) break
    let placed: string[] | null = null
    for (let tries = 0; tries < reports.length && !placed; tries++) {
      const parts = reports[turnIndex++ % reports.length](start)
      const clips = compose(start, parts)
      if (!clips.length || clips.some(id => recent(id, start, 12)) || start + clipLength(clips) > end) continue
      placed = placeLive(start, parts, 3, 0)
    }
    if (placed) {
      placed.forEach(id => said.set(id, start))
      time = start + clipLength(placed)
    } else time = start + .5
  }
  return timeline.items
}

export function commentaryCues(utterances: Utterance[]): Cue[] {
  return utterances.flatMap(u => {
    let t = u.at
    return u.clips.map(clip => {
      const [offset, duration] = CLIPS[clip]
      const cue: Cue = { at: t, clip, offset, duration, sprite: Object.hasOwn(EXTRA, clip) ? 1 : 0 }
      t += duration + WITHIN
      return cue
    })
  })
}

export const commentaryFiles = [`${manifest.file}?v=${manifest.version}`, `${manifest.extra.file}?v=${manifest.extra.version}`] as const

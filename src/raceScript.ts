import type { Finish, PlanScript, Style } from './raceModel'

// One round's script, read from races.json. `order` is a prefix of the result by
// horse number; the plan fields use 0-based horses, as raceModel does.
export type ScriptLine = { at: number; clips: string[] }
export type RaceScript = PlanScript & { order?: number[]; commentary?: { mode: 'add' | 'replace'; lines: ScriptLine[] } }

const STYLES: Style[] = ['front', 'stalk', 'mid', 'close']
const FINISHES: Finish[] = ['photo', 'close', 'clear', 'easy']
const isInt = (value: unknown): value is number => Number.isSafeInteger(value)
const isHorse = (value: unknown, field: number): value is number => isInt(value) && value >= 1 && value <= field
const distinct = (values: number[]) => new Set(values).size === values.length
// Scripted lines in add mode keep clear of the welcome and the closing calls
// before the gates; the run to the line is checked against the plan when placed.
export const PRE_RACE_LINES = [-55, -17]
export const RACE_LINES_FROM = 2
export const LINES_UNTIL = 57

// Checks one race entry. What is malformed is left out with a warning; a bad
// finishing order drops the whole race, since everything else hangs off it.
export function normalizeRace(raw: unknown, field: number, cup: string): { script?: RaceScript; warnings: string[] } {
  const warnings: string[] = []
  if (!raw || typeof raw !== 'object') return { warnings: ['race is not an object'] }
  const race = raw as Record<string, unknown>
  const script: RaceScript = {}
  if (race.order !== undefined) {
    if (!Array.isArray(race.order) || !race.order.length || !race.order.every(h => isHorse(h, field)) || !distinct(race.order)) return { warnings: [`order must list distinct horses 1–${field}`] }
    script.order = race.order
  }
  if (race.styles !== undefined) {
    const styles: (Style | undefined)[] = new Array(field).fill(undefined)
    if (race.styles && typeof race.styles === 'object') for (const [horse, style] of Object.entries(race.styles)) {
      if (isHorse(Number(horse), field) && STYLES.includes(style as Style)) styles[Number(horse) - 1] = style as Style
      else warnings.push(`styles.${horse}: must be a horse 1–${field} and one of ${STYLES.join('/')}`)
    } else warnings.push('styles must be an object')
    if (styles.some(Boolean)) script.styles = styles
  }
  if (race.finish !== undefined) {
    if (FINISHES.includes(race.finish as Finish)) script.finish = race.finish as Finish
    else warnings.push(`finish must be one of ${FINISHES.join('/')}`)
  }
  if (race.margins !== undefined) {
    const margins = race.margins
    if (Array.isArray(margins) && margins.length && margins.length < field && margins.every(m => typeof m === 'number' && m >= .05 && m <= 6) && margins.reduce((sum, m) => sum + m, 0) <= 15) script.margins = margins
    else warnings.push(`margins must be 1–${field - 1} lengths of 0.05–6 each, 15 in all`)
  }
  if (race.checkpoints !== undefined) {
    const checkpoints = Array.isArray(race.checkpoints) ? race.checkpoints : []
    if (!Array.isArray(race.checkpoints)) warnings.push('checkpoints must be a list')
    const kept: NonNullable<PlanScript['checkpoints']> = []
    for (const raw of checkpoints) {
      const point = (raw ?? {}) as Record<string, unknown>
      const order = point.order === undefined ? (point.leader === undefined ? [] : [point.leader]) : point.order
      const by = point.by
      if (typeof point.at !== 'number' || point.at < 150 || point.at > 1150) { warnings.push('checkpoint at must be 150–1150 m'); continue }
      if (!Array.isArray(order) || !order.length || !order.every(h => isHorse(h, field)) || !distinct(order)) { warnings.push(`checkpoint ${point.at}m needs a leader or an order of distinct horses 1–${field}`); continue }
      if (point.leader !== undefined && point.order !== undefined && order[0] !== point.leader) { warnings.push(`checkpoint ${point.at}m: leader and order disagree`); continue }
      if (by !== undefined && (typeof by !== 'number' || by < 0 || by > 4)) { warnings.push(`checkpoint ${point.at}m: by must be 0–4 lengths`); continue }
      if (kept.some(k => Math.abs(k.at - (point.at as number)) < 100)) { warnings.push(`checkpoint ${point.at}m is within 100 m of another`); continue }
      kept.push({ at: point.at, order: order.map(h => h - 1), ...(typeof by === 'number' && by > 0 ? { by } : {}) })
    }
    if (kept.length) script.checkpoints = kept.sort((a, b) => a.at - b.at)
  }
  if (race.commentary !== undefined) {
    const commentary = (race.commentary ?? {}) as Record<string, unknown>
    const mode = commentary.mode === undefined ? 'add' : commentary.mode
    if (mode !== 'add' && mode !== 'replace') warnings.push('commentary mode must be add or replace')
    else {
      const lines: ScriptLine[] = []
      for (const raw of Array.isArray(commentary.lines) ? commentary.lines : []) {
        const line = (raw ?? {}) as Record<string, unknown>
        const at = line.at, clips = line.clips
        if (typeof at !== 'number' || !Array.isArray(clips) || !clips.length || !clips.every(c => typeof c === 'string')) { warnings.push('commentary line needs at (seconds) and clips (ids)'); continue }
        const bad = clips.find(clip => !clipFits(clip, field, cup))
        if (bad) { warnings.push(`commentary ${at}s: ${bad} does not fit this cup`); continue }
        const window = mode === 'replace' ? at >= -60 && at <= LINES_UNTIL : (at >= PRE_RACE_LINES[0] && at <= PRE_RACE_LINES[1]) || (at >= RACE_LINES_FROM && at <= LINES_UNTIL)
        if (!window) { warnings.push(`commentary ${at}s is outside the ${mode} windows`); continue }
        lines.push({ at, clips })
      }
      if (lines.length || mode === 'replace') script.commentary = { mode, lines: lines.sort((a, b) => a.at - b.at) }
    }
  }
  return { script, warnings }
}
// Runner lines must name a runner in this field, cup lines this cup.
function clipFits(clip: string, field: number, cup: string) {
  const [family, suffix, extra] = clip.split('.')
  if (!family || extra !== undefined) return false
  if (suffix === undefined) return true
  if (family === 'welcome1' || family === 'welcome2') return suffix === cup
  if (family === 'breakAway') return suffix === String(field)
  return isHorse(Number(suffix), field)
}

// Scripts in force, per schedule (seed and field) and round. A round is locked
// the first time its betting has closed here, so a newer file never changes a
// race someone is watching; rounds not yet locked follow the latest file.
type Entry = { script: RaceScript; rev: string }
const installed = new Map<string, Map<number, Entry>>()
const locked = new Map<string, Entry | null>()
const fnv = (text: string) => { let h = 0x811c9dc5; for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 16777619) >>> 0; return h.toString(36) }
export function installScripts(seed: number, field: number, scripts: Map<number, RaceScript>) {
  installed.set(`${seed}:${field}`, new Map([...scripts].map(([round, script]) => [round, { script, rev: fnv(JSON.stringify(script)) }])))
}
export function scriptOf(seed: number, round: number, field: number): Entry | undefined {
  const key = `${seed}:${round}:${field}`
  return locked.has(key) ? locked.get(key) ?? undefined : installed.get(`${seed}:${field}`)?.get(round)
}
export function lockRound(seed: number, field: number, round: number) {
  const key = `${seed}:${round}:${field}`
  if (locked.has(key)) return
  locked.set(key, installed.get(`${seed}:${field}`)?.get(round) ?? null)
  if (locked.size > 64) locked.delete(locked.keys().next().value!)
}

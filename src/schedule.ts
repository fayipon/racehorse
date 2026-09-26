import { CUPS, ROUND_MS, type CupClock, type CupId } from './game'
import { installScripts, normalizeRace, type RaceScript } from './raceScript'

// races.json drives every cup: its schedule and the scripts of chosen rounds.
// The page is a player: it fetches the file at start and again every minute,
// and a service can later serve the same shape (see docs/race-json.md).
export const BASELINE: Record<CupId, CupClock> = {
  sunny: { epoch: Date.parse('2026-09-01T00:00:00+08:00'), seed: 2718281828 },
  thunder: { epoch: Date.parse('2026-09-01T00:00:40+08:00'), seed: 1618033988 },
  royal: { epoch: Date.parse('2026-09-01T00:01:20+08:00'), seed: 1414213562 },
}
export type Schedule = { clocks: Record<CupId, CupClock>; scripts: Record<CupId, Map<number, RaceScript>>; serverTime?: number; warnings: string[] }

// Times must carry their zone, or each player would read them in their own.
const instant = (value: unknown) => typeof value === 'string' && /(Z|[+-]\d\d:\d\d)$/.test(value) ? Date.parse(value) : NaN
export function parseSchedule(json: unknown): Schedule {
  const warnings: string[] = []
  const file = (json ?? {}) as Record<string, unknown>
  const schedule: Schedule = { clocks: { ...BASELINE }, scripts: { sunny: new Map(), thunder: new Map(), royal: new Map() }, warnings }
  if (file.version !== 1) { warnings.push('unknown version; using the built-in schedule'); return schedule }
  if (Number.isFinite(file.serverTime)) schedule.serverTime = file.serverTime as number
  const cups = (file.cups ?? {}) as Record<string, unknown>
  for (const cup of Object.keys(CUPS) as CupId[]) {
    const entry = cups[cup] as Record<string, unknown> | undefined
    if (!entry) continue
    const epoch = instant(entry.epoch)
    const seed = entry.seed
    if (Number.isFinite(epoch) && Number.isSafeInteger(seed) && (seed as number) >= 0) schedule.clocks[cup] = { epoch, seed: seed as number }
    else warnings.push(`${cup}: epoch (with a time zone) and seed (a whole number) are required; using the built-in schedule`)
    const clock = schedule.clocks[cup], field = CUPS[cup].field
    for (const raw of Array.isArray(entry.races) ? entry.races : []) {
      const race = (raw ?? {}) as Record<string, unknown>
      const at = instant(race.at)
      const round = race.round !== undefined ? race.round : Number.isFinite(at) && (at - clock.epoch) % ROUND_MS === 0 ? (at - clock.epoch) / ROUND_MS + 1 : NaN
      const label = `${cup} ${race.at ?? `round ${race.round}`}`
      if ((race.round === undefined) === (race.at === undefined) || !Number.isSafeInteger(round) || (round as number) < 1) { warnings.push(`${label}: give either round (1 or more) or at (a round's start, with a time zone)`); continue }
      if (schedule.scripts[cup].has(round as number)) { warnings.push(`${label}: round ${round} is scripted twice`); continue }
      const { script, warnings: problems } = normalizeRace(race, field, cup)
      warnings.push(...problems.map(problem => `${label}: ${problem}`))
      if (script) schedule.scripts[cup].set(round as number, script)
    }
  }
  return schedule
}

let clocks = BASELINE
// Everyone's clock: the device's, unless a service states its time or the
// device is minutes out. The correction is kept across visits, so a page
// never opens on the device's own clock after playing on a corrected one:
// the saved rounds would then lie minutes ahead of it.
const OFFSET_KEY = 'racehorse-clock-offset'
let offset = (() => {
  try {
    const saved = Number(localStorage.getItem(OFFSET_KEY))
    return Number.isFinite(saved) && Math.abs(saved) < 7 * 86_400_000 ? saved : 0
  } catch { return 0 }
})()
function adopt(next: number) {
  if (next === offset) return
  offset = next
  try { localStorage.setItem(OFFSET_KEY, String(next)) } catch { /* This visit only. */ }
}
export const serverNow = () => Date.now() + offset
// A static host's Date header is good to a second or two, and devices keep
// better time than that, so only a clock minutes out is corrected. Once
// corrected it is followed until it comes within half a minute; wobble of a
// few seconds between readings is left alone.
export function correctedOffset(current: number, skew: number) {
  if (Math.abs(skew) <= (current ? 30_000 : 120_000)) return 0
  return Math.abs(skew - current) > 5_000 ? skew : current
}
export const currentClocks = () => clocks
function install(schedule: Schedule) {
  clocks = schedule.clocks
  for (const cup of Object.keys(CUPS) as CupId[]) installScripts(clocks[cup].seed, CUPS[cup].field, schedule.scripts[cup])
  for (const warning of schedule.warnings) console.warn(`races.json: ${warning}`)
}
const source = () => import.meta.env.VITE_RACES_URL || `${import.meta.env.BASE_URL}races.json`
async function load(timeout: number) {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), timeout)
  try {
    const sent = Date.now()
    // A new URL each minute gets past the host's cache without refetching every tick.
    const response = await fetch(`${source()}?t=${Math.floor(serverNow() / 60_000)}`, { cache: 'no-cache', signal: controller.signal })
    if (!response.ok) return
    const schedule = parseSchedule(await response.json())
    const received = Date.now()
    if (schedule.serverTime !== undefined) adopt(schedule.serverTime + (received - sent) / 2 - received)
    // A slow answer, as when a phone froze the page mid-request, dates nothing.
    else if (received - sent < 3000) {
      const stated = Date.parse(response.headers.get('date') ?? '') + 1000 * Number(response.headers.get('age') ?? 0)
      if (Number.isFinite(stated)) adopt(correctedOffset(offset, stated - (sent + received) / 2))
    }
    install(schedule)
  } catch { /* Keep the last good schedule. */ } finally { clearTimeout(timer) }
}
// Before the first render, so the first settlement already knows the scripts.
export const bootSchedule = () => load(2500)
export const refreshSchedule = () => load(5000)
let refreshing = false
export function startScheduleRefresh() {
  if (refreshing) return
  refreshing = true
  setInterval(() => { void refreshSchedule() }, 60_000)
}

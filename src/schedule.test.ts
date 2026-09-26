import { afterEach, describe, expect, it, vi } from 'vitest'
import { bootSchedule, clockOffset, refreshSchedule, serverNow } from './schedule'

// races.json answered by a host whose Date header reads `date`.
const host = (date: number) => vi.fn(async () => new Response(JSON.stringify({ version: 1, cups: {} }), { headers: { date: new Date(date).toUTCString() } }))

describe('race clock', () => {
  afterEach(() => { vi.unstubAllGlobals() })

  it('corrects only a device clock more than 3 s out', () => {
    expect(clockOffset(1_800)).toBe(0)
    expect(clockOffset(-2_900)).toBe(0)
    expect(clockOffset(3_600)).toBe(3_600)
    expect(clockOffset(-200_000)).toBe(-200_000)
  })

  it('sets the clock from the host before the page starts, then holds it all visit', async () => {
    // A phone three minutes slow opens the page.
    vi.stubGlobal('fetch', host(Date.now() + 180_000))
    await bootSchedule()
    expect(Math.abs(serverNow() - Date.now() - 180_000)).toBeLessThan(1_500)
    // A later reading, even a very different one, never moves the clock mid-race.
    vi.stubGlobal('fetch', host(Date.now()))
    await refreshSchedule()
    expect(Math.abs(serverNow() - Date.now() - 180_000)).toBeLessThan(1_500)
  })
})

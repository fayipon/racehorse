import { describe, expect, it } from 'vitest'
import { COURSE, coursePoint, laneRadius, laneSpacing, makeParadePlan, paradePositions, paradeState } from './course'

describe('shared stadium course geometry', () => {
  it('gives each horse an independent repeatable itinerary that varies between rounds', () => {
    const plan=makeParadePlan(42,7,8)
    expect(plan).toEqual(makeParadePlan(42,7,8))
    expect(plan).not.toEqual(makeParadePlan(42,8,8))
    expect(new Set(plan.map(p=>JSON.stringify(p))).size).toBe(8)
    for(const lane of plan) {
      expect(lane.some(s=>s.from===s.to)).toBe(true)
      expect(lane.some(s=>s.from!==s.to)).toBe(true)
      for(let t=0;t<=47;t+=.07) {
        const state=paradeState(t,lane)
        expect(state.x).toBeGreaterThanOrEqual(-11)
        expect(state.x).toBeLessThanOrEqual(0)
      }
      expect(paradeState(47,lane).speed).toBeCloseTo(0,9)
    }
    for (let time=53;time<=60;time+=.1) {
      expect(paradePositions(time,plan).every(p=>p===0)).toBe(true)
    }
  })
  it('returns to the start without reversing, snapping or drifting after line-up', () => {
    for (let lane=0;lane<8;lane++) {
      let previous=paradePositions(48)[lane]
      for (let step=1;step<=500;step++) {
        const current=paradePositions(48+step*.01)[lane]
        expect(current).toBeGreaterThanOrEqual(previous-1e-12)
        expect(current).toBeLessThanOrEqual(0)
        previous=current
      }
      for (const boundary of [47,48,53]) {
        const h=1e-4
        const before=paradePositions(boundary-h)[lane]
        const at=paradePositions(boundary)[lane]
        const after=paradePositions(boundary+h)[lane]
        expect(Math.abs(after-before)).toBeLessThan(1e-5)
        expect(Math.abs((after-at)/h-(at-before)/h)).toBeLessThan(1e-5)
      }
    }
  })
  it('maps the strolling horses to the near straight and lines them up before racing', () => {
    for (const time of [0,5,20,35,48,58,53]) {
      paradePositions(time).forEach((progress,lane) => {
        const point=coursePoint(progress,lane,8)
        expect(point.x).toBeGreaterThanOrEqual(-11.001)
        expect(point.x).toBeLessThanOrEqual(.001)
        expect(point.z).toBeCloseTo(COURSE.laneStart+lane*COURSE.laneSpacing,7)
      })
    }
    expect(paradePositions(53).every(p=>p===0)).toBe(true)
    expect(paradePositions(60).every(p=>p===0)).toBe(true)
  })
  it('starts and finishes on the middle of the near straight for every lane', () => {
    for (let lane=0; lane<8; lane++) {
      const radius=COURSE.laneStart+lane*COURSE.laneSpacing
      expect(coursePoint(0,lane,8)).toEqual({x:0,z:radius})
      expect(coursePoint(1,lane,8)).toEqual({x:0,z:radius})
      expect(coursePoint(.5,lane,8).x).toBeCloseTo(0,8)
      expect(coursePoint(.5,lane,8).z).toBeCloseTo(-radius,8)
    }
  })
  it('contains genuine straight sections, not an ellipse', () => {
    for (let lane=0;lane<8;lane++) {
      const start=coursePoint(.01,lane,8), next=coursePoint(.04,lane,8)
      expect(start.z).toBeCloseTo(next.z,10)
      expect(next.x).toBeGreaterThan(start.x)
      const farStart=coursePoint(.49,lane,8), farNext=coursePoint(.51,lane,8)
      expect(farStart.z).toBeCloseTo(farNext.z,10)
      expect(farNext.x).toBeLessThan(farStart.x)
    }
  })
  it('joins both semicircles continuously and stays inside the real track', () => {
    for (let lane=0;lane<8;lane++) {
      const radius=COURSE.laneStart+lane*COURSE.laneSpacing
      const lap=4*COURSE.halfStraight+2*Math.PI*radius
      for (const distance of [COURSE.halfStraight,COURSE.halfStraight+Math.PI*radius,3*COURSE.halfStraight+Math.PI*radius,3*COURSE.halfStraight+2*Math.PI*radius]) {
        const a=coursePoint(distance/lap-1e-6,lane,8), b=coursePoint(distance/lap+1e-6,lane,8)
        expect(Math.hypot(a.x-b.x,a.z-b.z)).toBeLessThan(.001)
      }
      for (let i=0;i<200;i++) {
        const p=coursePoint(i/200,lane,8)
        const radial=Math.hypot(Math.max(0,Math.abs(p.x)-COURSE.halfStraight),p.z)
        expect(radial).toBeCloseTo(radius,8)
        expect(radial).toBeGreaterThan(COURSE.innerRadius)
        expect(radial).toBeLessThan(COURSE.innerRadius+COURSE.trackWidth)
      }
    }
  })
})
describe('bigger fields', () => {
  it('closes the lanes up so every runner stays inside the rail', () => {
    expect(laneSpacing(8)).toBe(COURSE.laneSpacing)
    for (const field of [10, 12]) {
      expect(laneSpacing(field)).toBeLessThan(COURSE.laneSpacing)
      expect(laneRadius(field - 1, field)).toBeCloseTo(COURSE.maxLaneRadius, 9)
      expect(COURSE.maxLaneRadius).toBeLessThan(COURSE.innerRadius + COURSE.trackWidth)
      expect(makeParadePlan(42, 7, field)).toHaveLength(field)
    }
  })
})

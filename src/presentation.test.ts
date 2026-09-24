import { expect, it } from 'vitest'
import { racePresentationTime } from './presentation'

it('holds the first crossing for 1.2 seconds, then keeps accelerating through settlement', () => {
  let previous=0
  for(let i=1;i<=5000;i++) {
    const time=i/100, current=racePresentationTime(time)
    expect(current).toBeGreaterThanOrEqual(previous-1e-10)
    expect((current-previous)/.01).toBeGreaterThan(-1e-8)
    expect((current-previous)/.01).toBeLessThan(1.901)
    previous=current
  }
  for(let step=0;step<=120;step++) expect(racePresentationTime(44.6+step/100)).toBeCloseTo(44.5,8)
  let previousSpeed=0
  for(let time=45.8;time<=50;time+=.01) {
    const speed=(racePresentationTime(time+.001)-racePresentationTime(time))/.001
    expect(speed).toBeGreaterThanOrEqual(previousSpeed-1e-7)
    if(time>=46.05) expect(speed).toBeGreaterThanOrEqual(1.35)
    previousSpeed=speed
  }
  expect((racePresentationTime(50.01)-racePresentationTime(50))/.01).toBeCloseTo(1.9,7)
  // Even eighth place (49.05 visual seconds) crosses before the 50s settlement.
  expect(racePresentationTime(50)).toBeGreaterThan(49.05)
  for(const boundary of [44.4,44.6,45.8,46.05,50]) {
    const h=.0001, at=racePresentationTime(boundary)
    expect(Math.abs((at-racePresentationTime(boundary-h))/h-(racePresentationTime(boundary+h)-at)/h)).toBeLessThan(.002)
  }
})

import { expect, it } from 'vitest'
import { CUT_IN, racePresentationTime } from './presentation'

it('banks time through the far side, then slows the sprint cut-in and makes the time back before the post', () => {
  const speed = (time: number) => (racePresentationTime(time+.001)-racePresentationTime(time))/.001
  expect(racePresentationTime(28)).toBe(28)
  // Running a touch ahead beforehand pays for the long slow motion.
  for(let time=28;time<=CUT_IN;time+=.05) expect(speed(time)).toBeLessThan(1.14)
  expect(racePresentationTime(CUT_IN)).toBeGreaterThan(CUT_IN+.8)
  // The slow motion holds at 0.35x for over two and a half seconds of the cut-in.
  for(let time=38.6;time<=41.15;time+=.05) expect(speed(time)).toBeCloseTo(.35,2)
  // The rush back to the post stays near the old 1.45x.
  let rush=0
  for(let time=41.8;time<=44.4;time+=.01) rush=Math.max(rush,speed(time))
  expect(rush).toBeGreaterThan(1.2)
  expect(rush).toBeLessThan(1.55)
  // The first horse still reaches the post exactly when the crossing hold begins.
  expect(racePresentationTime(44.6)).toBeCloseTo(44.5,8)
})

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
  for(const boundary of [28,38.3,38.55,41.2,41.8,44.4,44.6,45.8,46.05,50]) {
    const h=.0001, at=racePresentationTime(boundary)
    expect(Math.abs((at-racePresentationTime(boundary-h))/h-(racePresentationTime(boundary+h)-at)/h)).toBeLessThan(.002)
  }
})

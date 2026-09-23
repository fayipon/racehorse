import { expect, it } from 'vitest'
import { racePresentationTime } from './presentation'

it('slows the finish smoothly without reversing or changing the 50s race boundary', () => {
  let previous=0
  for(let i=1;i<=5000;i++) {
    const time=i/100, current=racePresentationTime(time)
    expect(current).toBeGreaterThan(previous)
    expect((current-previous)/.01).toBeGreaterThan(.4)
    expect((current-previous)/.01).toBeLessThan(1.8)
    previous=current
  }
  expect(racePresentationTime(44.7)-racePresentationTime(43.7)).toBeCloseTo(.45)
  expect(racePresentationTime(50)).toBe(50)
  expect(racePresentationTime(51)).toBe(51)
  for(const boundary of [42.8,43.7,45.8,50]) {
    const h=.0001, at=racePresentationTime(boundary)
    expect(Math.abs((at-racePresentationTime(boundary-h))/h-(racePresentationTime(boundary+h)-at)/h)).toBeLessThan(.002)
  }
})

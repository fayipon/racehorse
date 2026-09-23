import course from '../godot/assets/course.json'

export const COURSE = course
export type ParadeSegment = { start: number; end: number; from: number; to: number }
export function makeParadePlan(seed: number, round: number): ParadeSegment[][] {
  return Array.from({length:course.laneCount},(_,lane) => {
    let state=(seed ^ Math.imul(round,2654435761) ^ Math.imul(lane+1,1597334677))>>>0
    const random=()=>{ state=(Math.imul(state,1664525)+1013904223)>>>0; return state/4294967296 }
    const segments: ParadeSegment[]=[]
    let time=0, x=-2-random()*7
    while(time<47) {
      const pauseEnd=Math.min(47,time+.7+random()*3.1)
      segments.push({start:time,end:pauseEnd,from:x,to:x}); time=pauseEnd
      if(time>=47) break
      const end=Math.min(47,time+4.8+random()*3.5)
      const to=47-time<1.5 ? x : x<-5.5 ? -1-random()*3 : -7-random()*3.5
      segments.push({start:time,end,from:x,to}); x=to; time=end
    }
    return segments
  })
}
const DEFAULT_PARADE=makeParadePlan(123,1)
export function paradeState(seconds: number, segments: ParadeSegment[]) {
  const segment=segments.find(s=>seconds<=s.end)??segments[segments.length-1]
  const t=Math.max(0,Math.min(1,(seconds-segment.start)/(segment.end-segment.start)))
  const ease=t*t*t*(10+t*(-15+6*t))
  return { x:segment.from+(segment.to-segment.from)*ease, speed:(segment.to-segment.from)*30*t*t*(1-t)*(1-t)/(segment.end-segment.start) }
}
export function paradePositions(seconds: number, plan=DEFAULT_PARADE) {
  return Array.from({length:course.laneCount},(_,lane) => {
    let x=paradeState(Math.min(seconds,47),plan[lane]).x
    if (seconds>=48) {
      const t=Math.max(0,Math.min(1,(seconds-48)/5))
      x*=1-t*t*(3-2*t)
    }
    const radius=course.laneStart+lane*course.laneSpacing
    return x/(4*course.halfStraight+2*Math.PI*radius)
  })
}
export function coursePoint(progress: number, lane: number) {
  const half = course.halfStraight
  const radius = course.laneStart + lane * course.laneSpacing
  const lap = 4 * half + 2 * Math.PI * radius
  let distance = ((progress % 1 + 1) % 1) * lap
  if (distance <= half) return { x: distance, z: radius }
  distance -= half
  if (distance <= Math.PI * radius) {
    const angle = Math.PI / 2 - distance / radius
    return { x: half + Math.cos(angle) * radius, z: Math.sin(angle) * radius }
  }
  distance -= Math.PI * radius
  if (distance <= 2 * half) return { x: half - distance, z: -radius }
  distance -= 2 * half
  if (distance <= Math.PI * radius) {
    const angle = -Math.PI / 2 - distance / radius
    return { x: -half + Math.cos(angle) * radius, z: Math.sin(angle) * radius }
  }
  return { x: -half + distance - Math.PI * radius, z: radius }
}

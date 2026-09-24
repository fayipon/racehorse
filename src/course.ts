import course from '../godot/assets/course.json'

export const COURSE = course
// A stroll segment eases x (shared with the minimap) and a lateral offset `lat`
// within the lane (Godot only). While standing, `mood` picks what the horse
// does: 0 stands, 1 looks around, 2 rests its head low, 3 grazes.
export type ParadeSegment = { start: number; end: number; from: number; to: number; lat: number; mood: number }
export function makeParadePlan(seed: number, round: number): ParadeSegment[][] {
  return Array.from({length:course.laneCount},(_,lane) => {
    let state=(seed ^ Math.imul(round,2654435761) ^ Math.imul(lane+1,1597334677))>>>0
    const random=()=>{ state=(Math.imul(state,1664525)+1013904223)>>>0; return state/4294967296 }
    const segments: ParadeSegment[]=[]
    let time=0, x=-2-random()*8, lat=0, heading=random()<.5 ? 1 : -1
    while(time<47) {
      const mood=Math.floor(random()*4)
      const pauseEnd=Math.min(47,time+(mood===3 ? 3.5+random()*2.5 : 1+random()*3))
      segments.push({start:time,end:pauseEnd,from:x,to:x,lat,mood}); time=pauseEnd
      if(time>=47) break
      // Usually carry on the same way; turn back at will or at the paddock ends.
      if(random()<.35) heading=-heading
      const distance=1.6+random()*4.6
      let to=Math.min(-1,Math.max(-10.5,x+heading*distance))
      if(Math.abs(to-x)<1.2) { heading=-heading; to=Math.min(-1,Math.max(-10.5,x+heading*distance)) }
      const nextLat=(random()*2-1)*.45
      const end=Math.min(47,time+Math.abs(to-x)/(.6+random()*.25))
      const hold=47-time<1.5
      segments.push({start:time,end,from:x,to:hold ? x : to,lat:hold ? lat : nextLat,mood:0})
      if(!hold) { x=to; lat=nextLat }
      time=end
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

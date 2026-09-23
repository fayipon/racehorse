import knots from '../godot/assets/cinematic.json'

// Smooth playback timing only. Betting, settlement and the 120s round keep
// their wall-clock schedule; the visual clock catches up continuously by 50s.
export function racePresentationTime(seconds: number) {
  if(seconds<=knots[0][0] || seconds>=knots[knots.length-1][0]) return seconds
  const next=knots.findIndex(k=>k[0]>=seconds)
  const [x0,y0,m0]=knots[next-1], [x1,y1,m1]=knots[next]
  const span=x1-x0, t=(seconds-x0)/span
  return (2*t*t*t-3*t*t+1)*y0+(t*t*t-2*t*t+t)*span*m0+(-2*t*t*t+3*t*t)*y1+(t*t*t-t*t)*span*m1
}

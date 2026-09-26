import knots from '../godot/assets/cinematic.json'

// Race seconds of the sprint's camera beats, as in race.gd: the head-on lens
// out of the final bend, then the special-move cut-in on the leader.
export const HOME_TURN = 34.3
export const CUT_IN = 38.3

// Smooth playback timing only. Betting, settlement and the 120s round keep
// their wall-clock schedule. The field runs a touch ahead through the far side
// (at most 1.13x), banking the time the cut-in's 2.65 s slow motion spends, so
// the rush back to the post stays near 1.5x. The 1.2s crossing hold releases
// into acceleration that keeps building through the end of the race, without
// dropping back to 1x.
export function racePresentationTime(seconds: number) {
  if(seconds<=knots[0][0]) return seconds
  const last=knots[knots.length-1]
  if(seconds>=last[0]) return last[1]+(seconds-last[0])*last[2]
  const next=knots.findIndex(k=>k[0]>=seconds)
  const [x0,y0,m0]=knots[next-1], [x1,y1,m1]=knots[next]
  const span=x1-x0, t=(seconds-x0)/span
  return (2*t*t*t-3*t*t+1)*y0+(t*t*t-2*t*t+t)*span*m0+(-2*t*t*t+3*t*t)*y1+(t*t*t-t*t)*span*m1
}

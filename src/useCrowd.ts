import { useEffect, useRef } from 'react'
import type { Game } from './game'
import { CrowdAudioPlayer, crowdMixAt } from './crowdAudio'

export function useCrowd(game: Game, now: number, enabled: boolean) {
  const player = useRef<CrowdAudioPlayer | null>(null)
  useEffect(() => {
    const hide = () => { if (document.hidden) player.current?.stop() }
    document.addEventListener('visibilitychange', hide)
    return () => {
      document.removeEventListener('visibilitychange', hide)
      player.current?.dispose()
      player.current = null
    }
  }, [])
  useEffect(() => {
    if (!enabled || document.hidden) { player.current?.stop(); return }
    player.current?.setMix(crowdMixAt(game, now))
  }, [game, now, enabled])
  return {
    enable: (audio: AudioContext) => {
      player.current ??= new CrowdAudioPlayer(audio)
      player.current.unlock()
    },
    stop: () => player.current?.stop(),
    duck: (start: number, end: number) => player.current?.duckDuring(start, end),
  }
}

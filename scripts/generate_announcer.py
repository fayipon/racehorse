"""Generate static Microsoft Edge TTS clips: pip install edge-tts==7.2.8."""
import asyncio
import hashlib
import json
from pathlib import Path
import edge_tts

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / 'public' / 'audio' / 'announcer'
VOICE = 'zh-TW-YunJheNeural'

async def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    scripts = json.loads((ROOT / 'scripts/announcer-lines.json').read_text(encoding='utf-8'))
    clips = []
    for cue, lines in scripts.items():
        for variant, template in enumerate(lines):
            numbered = '{leader}' in template or '{winner}' in template
            for horse in (range(1, 9) if numbered else [0]):
                label = '一二三四五六七八'[horse - 1] + '號' if horse else ''
                text = template.replace('{leader}', label).replace('{winner}', label)
                rate = '+65%' if cue in ('sprint', 'finish') else '+48%'
                signature = hashlib.sha256(f'{VOICE}|{rate}|+6Hz|{text}'.encode()).hexdigest()[:12]
                clips.append(dict(cue=cue, variant=variant, horse=horse, text=text, rate=rate, file=f'{cue}-{signature}.mp3'))
    semaphore = asyncio.Semaphore(3)
    done = 0
    async def generate(clip):
        nonlocal done
        target = OUTPUT / clip['file']
        async with semaphore:
            if not target.exists() or target.stat().st_size < 1000:
                for attempt in range(3):
                    try:
                        temporary = target.with_suffix('.part')
                        await edge_tts.Communicate(clip['text'], VOICE, rate=clip['rate'], pitch='+6Hz').save(str(temporary))
                        if temporary.stat().st_size < 1000:
                            raise RuntimeError('Empty audio output')
                        temporary.replace(target)
                        break
                    except Exception:
                        if attempt == 2:
                            raise
                        await asyncio.sleep(2 + attempt * 3)
            done += 1
            if done % 20 == 0:
                print(f'Generated {done}/{len(clips)}', flush=True)
    await asyncio.gather(*(generate(clip) for clip in clips))
    (ROOT / 'src/announcer-clips.json').write_text(json.dumps(clips, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Complete: {len(clips)} clips, {sum((OUTPUT / c["file"]).stat().st_size for c in clips) / 1e6:.2f} MB', flush=True)

if __name__ == '__main__':
    asyncio.run(main())

"""Build the race commentary voice sprite from scripts/commentary-lines.json.

Every line is spoken once per horse where it names one, trimmed, levelled by
intensity and packed into one MP3 (public/audio/commentary/voice.mp3). The clip
offsets go to src/commentary-clips.json, which the planner reads for timing.

Engines (the catalog's voice.engine is the default):
  edge            Microsoft Edge neural voices via edge-tts==7.2.8. Free.
  fish            Fish Audio (api.fish.audio). Set FISH_API_KEY in the
                  environment or in .env.local (git-ignored). With FISH_VOICE_ID
                  (or the catalog's voice.fish) it uses that voice model;
                  otherwise it clones the reference clip in design/
                  (FISH_REFERENCE to override). FISH_MODEL picks the
                  model (default s2.1-pro-free: the same S2.1 Pro model, free
                  through 2026-11-30; set FISH_MODEL=s2.1-pro to bill API credit).

Requires imageio-ffmpeg (tmp/python-tools). Generated parts are cached in
dev/commentary-parts, so only changed lines are requested again.
Run: python scripts/generate_commentary.py [--engine edge|fish] [--preview]
--preview renders only a short reel (dev/commentary-preview.mp3) to judge a
voice before generating every line; its clips are cached for the full run.
"""

import argparse
import array
import asyncio
import hashlib
import json
import math
import os
from pathlib import Path
import struct
import subprocess
import sys
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tmp" / "python-tools"))
import imageio_ffmpeg  # noqa: E402

CATALOG = ROOT / "scripts" / "commentary-lines.json"
PARTS = ROOT / "dev" / "commentary-parts"
SPRITE = ROOT / "public" / "audio" / "commentary" / "voice.mp3"
MANIFEST = ROOT / "src" / "commentary-clips.json"
RATE = 24000
LEAD_IN = 0.3
SPACING = 0.2
# Louder and brighter as the race builds; RMS targets in dBFS by intensity.
LEVEL_RMS = {0: -21.5, 1: -21.0, 2: -19.5, 3: -18.0}
PREVIEW = ROOT / "dev" / "commentary-preview.mp3"
# A paddock aside, then a whole run-in in the reference call's order.
PREVIEW_LINES = ["welcome1", "bio1.1", "lastWinner.3", "styleClose.7", "m200", "holds.6", "outside.7", "nearer.7",
                 "oneLength", "halfLength", "level", "breaksOut.7", "fights.6", "call.7", "call.7", "over.7", "line",
                 "lastStride", "wins.7"]
SHORT_PREVIEW = ["bio1.1", "m200", "holds.6", "outside.7", "halfLength", "level", "call.7", "call.7", "over.7",
                 "lastStride", "wins.7"]
FISH_REFERENCE = ROOT / "design" / "Fish_07_中文_影片衝線語氣試驗.mp3"
# The catalog's chosen Fish voice model; FISH_VOICE_ID overrides it.
FISH_VOICE = None
FISH_REFERENCE_TEXT = ("最後200米，烈焰還在領跑，外面的雷霆衝上來了，雷霆越追越近，只差一個馬身，半個馬身，"
                       "並排了，並排了，兩匹馬並排了，最後50米，雷霆往前衝，烈焰還在頂，雷霆，雷霆，雷霆衝過去了，"
                       "過終點，最後一步逆轉，7號雷霆拿下冠軍。")


def ffmpeg(arguments, payload=None):
    return subprocess.run(
        [imageio_ffmpeg.get_ffmpeg_exe(), "-hide_banner", "-loglevel", "error", *arguments],
        input=payload, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True,
    ).stdout


def decode(path):
    return array.array("h", ffmpeg(["-i", str(path), "-f", "s16le", "-ac", "1", "-ar", str(RATE), "pipe:1"]))


def expand(catalog):
    lines = []
    for line in catalog["lines"]:
        if line.get("texts"):
            # A fixed line per horse, such as its made-up back story.
            for index, text in enumerate(line["texts"]):
                lines.append({"id": f"{line['id']}.{index + 1}", "text": text, "level": line["level"]})
        elif line.get("horse"):
            for index, name in enumerate(catalog["names"]):
                text = line["text"].replace("{name}", name).replace("{number}", catalog["numbers"][index])
                lines.append({"id": f"{line['id']}.{index + 1}", "text": text, "level": line["level"]})
        else:
            lines.append({"id": line["id"], "text": line["text"], "level": line["level"]})
    return lines


def trim(samples):
    """Keep a short margin so consonants are not clipped."""
    voiced = [i for i, s in enumerate(samples) if abs(s) > 180]
    if not voiced:
        raise ValueError("Speech clip contains no audible signal")
    margin = int(RATE * 0.03)
    return samples[max(0, voiced[0] - margin):min(len(samples), voiced[-1] + margin + 1)]


def level(samples, target_db):
    rms = math.sqrt(sum(s * s for s in samples) / len(samples)) / 32768
    gain = 10 ** (target_db / 20) / max(rms, 1e-6)
    peak = max(abs(s) for s in samples) / 32768
    gain = min(gain, 10 ** (-1.0 / 20) / max(peak, 1e-6))
    return array.array("h", (max(-32767, min(32767, int(s * gain))) for s in samples))


# --- engines -----------------------------------------------------------------

async def edge_clip(line, settings, target):
    import edge_tts
    params = settings["levels"][str(line["level"])]
    for attempt in range(3):
        try:
            temporary = target.with_suffix(".part")
            await edge_tts.Communicate(line["text"], settings["edge"], rate=f"{params['rate']:+d}%",
                                       pitch=f"{params['pitch']:+d}Hz").save(str(temporary))
            if temporary.stat().st_size < 800:
                raise ValueError("Speech service returned empty audio")
            temporary.replace(target)
            return
        except Exception:
            if attempt == 2:
                raise
            await asyncio.sleep(1 + attempt)


def msgpack(value):
    """Just enough MessagePack for the Fish Audio request body."""
    if value is None:
        return b"\xc0"
    if value is True or value is False:
        return b"\xc3" if value else b"\xc2"
    if isinstance(value, int):
        return b"\xd3" + struct.pack(">q", value)
    if isinstance(value, float):
        return b"\xcb" + struct.pack(">d", value)
    if isinstance(value, str):
        data = value.encode()
        return b"\xdb" + struct.pack(">I", len(data)) + data
    if isinstance(value, (bytes, bytearray)):
        return b"\xc6" + struct.pack(">I", len(value)) + bytes(value)
    if isinstance(value, list):
        return b"\xdd" + struct.pack(">I", len(value)) + b"".join(msgpack(v) for v in value)
    if isinstance(value, dict):
        return b"\xdf" + struct.pack(">I", len(value)) + b"".join(msgpack(k) + msgpack(v) for k, v in value.items())
    raise TypeError(type(value))


def setting(name, default=None):
    """An environment variable, or a KEY=value line in .env.local."""
    if os.environ.get(name):
        return os.environ[name]
    local = ROOT / ".env.local"
    if local.exists():
        for row in local.read_text(encoding="utf-8").splitlines():
            key, _, value = row.partition("=")
            if key.strip() == name and value.strip():
                return value.strip().strip('"').strip("'")
    return default


# S2 models take free-form bracket cues at the start of a sentence.
FISH_TONE = {
    0: "[relaxed, warm broadcast tone, unhurried] ",
    1: "[lively sports commentary] ",
    2: "[excited horse racing commentator] ",
    3: "[shouting][very excited horse racing commentator, fast] ",
}


def fish_clip(line, target):
    key = setting("FISH_API_KEY")
    if not key:
        raise SystemExit("Set FISH_API_KEY (environment or .env.local) to use the Fish Audio engine.")
    body = {"text": FISH_TONE[line["level"]] + line["text"], "format": "mp3", "mp3_bitrate": 128,
            "normalize": True, "latency": "normal"}
    voice = setting("FISH_VOICE_ID", FISH_VOICE)
    if voice:
        body["reference_id"] = voice
    else:
        reference = Path(setting("FISH_REFERENCE", str(FISH_REFERENCE)))
        body["references"] = [{"audio": reference.read_bytes(), "text": FISH_REFERENCE_TEXT}]
    request = urllib.request.Request("https://api.fish.audio/v1/tts", data=msgpack(body), method="POST", headers={
        "Authorization": f"Bearer {key}", "Content-Type": "application/msgpack", "model": setting("FISH_MODEL", "s2.1-pro-free"),
    })
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            audio = response.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")[:300]
        raise SystemExit(f"Fish Audio refused {line['id']} ({error.code}): {detail}") from None
    if len(audio) < 800:
        raise ValueError(f"Fish Audio returned empty audio for {line['id']}")
    target.write_bytes(audio)


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--engine", choices=["edge", "fish"])
    parser.add_argument("--preview", action="store_true")
    parser.add_argument("--short", action="store_true", help="a shorter preview reel, for comparing voices")
    parser.add_argument("--voice", help="Fish voice model id, overriding FISH_VOICE_ID")
    parser.add_argument("--out", help="where to write the preview reel")
    options = parser.parse_args()
    if options.voice:
        os.environ["FISH_VOICE_ID"] = options.voice
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    settings = catalog["voice"]
    engine = options.engine or settings.get("engine", "edge")
    global FISH_VOICE
    FISH_VOICE = settings.get("fish")
    lines = expand(catalog)
    if options.preview:
        by_id = {line["id"]: line for line in lines}
        lines = [by_id[key] for key in (SHORT_PREVIEW if options.short else PREVIEW_LINES)]
    PARTS.mkdir(parents=True, exist_ok=True)
    semaphore = asyncio.Semaphore(4 if engine == "edge" else 2)

    async def fetch(line):
        voice = settings["edge"] if engine == "edge" else f'{setting("FISH_MODEL", "s2.1-pro-free")}:{setting("FISH_VOICE_ID", FISH_VOICE or "reference")}'
        params = json.dumps(settings["levels"][str(line["level"])], sort_keys=True) if engine == "edge" else FISH_TONE[line["level"]]
        signature = hashlib.sha256(f"{engine}|{voice}|{params}|{line['text']}".encode()).hexdigest()[:16]
        target = PARTS / f"{signature}.mp3"
        if not target.exists():
            async with semaphore:
                if engine == "edge":
                    await edge_clip(line, settings, target)
                else:
                    await asyncio.to_thread(fish_clip, line, target)
        return target

    targets = await asyncio.gather(*[fetch(line) for line in lines])
    if options.preview:
        reel = array.array("h", bytes(int(RATE * .3) * 2))
        for line, target in zip(lines, targets):
            reel.extend(level(trim(decode(target)), LEVEL_RMS[line["level"]]))
            reel.extend(bytes(int(RATE * (1.0 if line["level"] == 0 else .12)) * 2))
        ffmpeg(["-y", "-f", "s16le", "-ac", "1", "-ar", str(RATE), "-i", "pipe:0", "-codec:a", "libmp3lame",
                "-b:a", "96k", str(options.out or PREVIEW)], reel.tobytes())
        print(f"Preview: {options.out or PREVIEW} ({len(reel) / RATE:.1f}s)", flush=True)
        return
    pcm = array.array("h", bytes(int(RATE * LEAD_IN) * 2))
    placed = {}
    for line, target in zip(lines, targets):
        clip = level(trim(decode(target)), LEVEL_RMS[line["level"]] + settings["levels"][str(line["level"])]["gain"])
        placed[line["id"]] = (len(pcm), len(clip), line["level"])
        pcm.extend(clip)
        pcm.extend(bytes(int(RATE * SPACING) * 2))
    SPRITE.parent.mkdir(parents=True, exist_ok=True)
    ffmpeg(["-y", "-f", "s16le", "-ac", "1", "-ar", str(RATE), "-i", "pipe:0", "-codec:a", "libmp3lame",
            "-b:a", "32k", str(SPRITE)], pcm.tobytes())
    # Measure where the first clip actually lands after encoding, so offsets
    # hold however the decoder trims the MP3 start.
    decoded = decode(SPRITE)
    first_start, first_length, _ = placed[lines[0]["id"]]
    window = pcm[first_start:first_start + min(first_length, RATE // 2)]
    best, shift = -1.0, 0
    for candidate in range(-2400, 2401, 4):
        start = first_start + candidate
        if start < 0:
            continue
        score = sum(a * b for a, b in zip(window[::8], decoded[start:start + len(window)][::8]))
        if score > best:
            best, shift = score, candidate
    # Each clip: [start seconds, duration seconds, intensity level].
    clips = {key: [round((start + shift) / RATE, 3), round(length / RATE, 3), intensity]
             for key, (start, length, intensity) in placed.items()}
    digest = hashlib.sha256(SPRITE.read_bytes()).hexdigest()[:10]
    rows = ",\n".join(f'  "{key}": {json.dumps(value)}' for key, value in clips.items())
    MANIFEST.write_text(f'{{\n"file": "audio/commentary/voice.mp3",\n"version": "{digest}",\n"engine": "{engine}",\n'
                        f'"clips": {{\n{rows}\n}}\n}}\n', encoding="utf-8")
    total = len(decoded) / RATE
    print(f"{len(clips)} clips, {total:.1f}s, {SPRITE.stat().st_size // 1024} KB, encoder shift {shift} samples", flush=True)


if __name__ == "__main__":
    asyncio.run(main())

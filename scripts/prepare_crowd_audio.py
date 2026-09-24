"""Build seamless crowd loops from Gregor Quendel's CC-BY 4.0 recordings.

Requires imageio-ffmpeg (may be installed into tmp/python-tools).
The source archive and attribution are documented in public/audio/crowd/LICENSE.txt.
"""
import array
from pathlib import Path
import subprocess
import sys
from urllib.request import urlretrieve
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tmp" / "python-tools"))
import imageio_ffmpeg  # noqa: E402

SOURCE = ROOT / "tmp" / "crowd-source"
OUTPUT = ROOT / "public" / "audio" / "crowd"
URL = "https://opengameart.org/sites/default/files/gregor_quendel_-_free_crowd_cheering_sounds_-_mp3.zip"
RATE = 44100


def decode(source, start, end):
    decoded = subprocess.run([
        imageio_ffmpeg.get_ffmpeg_exe(), "-hide_banner", "-loglevel", "error", "-i", str(source),
        "-af", f"atrim=start={start}:end={end},highpass=f=100,acompressor=threshold=0.09:ratio=4:attack=12:release=220,loudnorm=I=-17:TP=-2:LRA=4",
        "-ar", str(RATE), "-ac", "2", "-f", "f32le", "pipe:1",
    ], check=True, stdout=subprocess.PIPE).stdout
    return array.array("f", decoded)


def loop(samples):
    # Rotate a 750ms end-to-start crossfade to the beginning of the loop.
    # Both the wraparound and the internal transition remain continuous.
    frames = int(RATE * 0.75)
    overlap = frames * 2
    wrap = array.array("f", (
        samples[-overlap + index] * (1 - (index // 2) / (frames - 1))
        + samples[index] * ((index // 2) / (frames - 1))
        for index in range(overlap)
    ))
    return wrap + samples[overlap:-overlap]


def main():
    SOURCE.mkdir(parents=True, exist_ok=True)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    archive = SOURCE / "crowd.zip"
    if not archive.exists():
        urlretrieve(URL, archive)
    with ZipFile(archive) as bundle:
        for name, track in [("ambient", "10"), ("cheer", "05"), ("roar", "03"), ("rhythmic", "01")]:
            source = SOURCE / f"{name}.mp3"
            member = next(path for path in bundle.namelist() if f" - {track} - " in path)
            source.write_bytes(bundle.read(member))
    ambient = loop(decode(SOURCE / "ambient.mp3", 2, 20))
    cheer = loop(decode(SOURCE / "cheer.mp3", 5, 11))
    # Keep the loud middle of each reaction, excluding their quiet lead-in/tail.
    # Overlap two different recordings at different periods, so a whole stand
    # never appears to stop cheering together at a loop boundary.
    strong = loop(decode(SOURCE / "roar.mp3", 5, 11))
    rhythmic = loop(decode(SOURCE / "rhythmic.mp3", 5, 12.5))
    offset = int(RATE * 2.2) * 2
    roar = loop(array.array("f", (
        0.72 * strong[index % len(strong)] + 0.72 * rhythmic[(index + offset) % len(rhythmic)]
        for index in range(RATE * 2 * 18)
    )))
    for name, samples, loudness in [("ambient", ambient, -20), ("cheer", cheer, -17), ("roar", roar, -14)]:
        subprocess.run([
            imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-hide_banner", "-loglevel", "error",
            "-f", "f32le", "-ar", str(RATE), "-ac", "2", "-i", "pipe:0",
            "-af", f"loudnorm=I={loudness}:TP=-2:LRA=4", "-ar", str(RATE),
            "-c:a", "libvorbis", "-q:a", "5", str(OUTPUT / f"{name}.ogg"),
        ], input=samples.tobytes(), check=True)
        print(f"Prepared {name}.ogg ({len(samples) / (RATE * 2):.2f}s)", flush=True)


if __name__ == "__main__":
    main()

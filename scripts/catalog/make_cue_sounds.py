# -*- coding: utf-8 -*-
"""Synthesise the three sounds a timed set needs.

WHY SYNTHESISED

The operator asked for "звуковой сигнал старта... тикание и финальный гонг".
Three short sounds. Every free sound-effect library worth using attaches a
licence with attribution or redistribution terms, and this app already has one
unresolved licensing question hanging over its video library — adding a second
one over four kilobytes of audio would be absurd.

These are generated from arithmetic. Nobody owns a decaying sine.

WHAT THEY ARE

- tick   ~60 ms, a short high click. Plays on each of the last seconds of a
         phase, so it must be brief enough not to overlap the next one and dry
         enough not to become annoying at five in a row.
- start  ~900 ms, a bright two-tone chime, rising. "Go."
- end    ~1400 ms, a lower gong with a long decay. "Stop."

Rising for start and falling for end is the whole design: someone mid-set is
not looking at the phone, and the direction of the interval is recognisable
without counting tones.

Mono, 44.1 kHz, 16-bit PCM WAV. About 250 KB total, which is smaller than
one poster.
"""
from __future__ import annotations

import math
import struct
import wave
from pathlib import Path

OUT = Path(__file__).resolve().parents[2] / 'mobile' / 'assets' / 'sounds'
RATE = 44100


def write(name: str, samples: list[float]) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f'{name}.wav'
    peak = max(1e-9, max(abs(s) for s in samples))
    frames = b''.join(
        struct.pack('<h', int(max(-1.0, min(1.0, s / peak * 0.89)) * 32767))
        for s in samples)
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)
    print(f'{path.name:12} {len(samples) / RATE * 1000:6.0f} ms  '
          f'{path.stat().st_size / 1024:6.1f} KB')


def tone(freq: float, seconds: float, decay: float,
         harmonics: tuple[float, ...] = (1.0,)) -> list[float]:
    """A struck note: partials at multiples of [freq], decaying exponentially.

    The 4 ms fade-in is not cosmetic. A waveform that starts at full amplitude
    begins with a step, and a step is a click — audible on phone speakers as a
    dry snap in front of every sound.
    """
    n = int(RATE * seconds)
    attack = int(RATE * 0.004)
    out = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-decay * t)
        if i < attack:
            env *= i / attack
        s = sum(amp * math.sin(2 * math.pi * freq * mult * t)
                for mult, amp in enumerate(harmonics, start=1))
        out.append(s * env)
    return out


def mix(*layers: list[float]) -> list[float]:
    n = max(len(layer) for layer in layers)
    out = [0.0] * n
    for layer in layers:
        for i, s in enumerate(layer):
            out[i] += s
    return out


def delay(samples: list[float], seconds: float) -> list[float]:
    return [0.0] * int(RATE * seconds) + samples


def main() -> None:
    # A click, not a beep: short, high, and gone before the ear settles.
    write('tick', tone(2100, 0.06, 60.0, (1.0, 0.25)))

    # Rising fifth. Bright, unmistakably "begin".
    write('start_gong', mix(
        tone(660, 0.55, 7.0, (1.0, 0.35, 0.12)),
        delay(tone(990, 0.75, 5.5, (1.0, 0.30, 0.10)), 0.13),
    ))

    # Falling, lower, long tail. The partials are deliberately inharmonic —
    # 2.76 and 5.4 are roughly where a struck metal plate puts them, and a
    # perfect octave stack sounds like an organ rather than a gong.
    write('end_gong', mix(
        tone(300, 1.40, 2.6, (1.0, 0.0, 0.0)),
        tone(300 * 2.76, 1.10, 3.6, (1.0,)),
        tone(300 * 5.40, 0.70, 6.0, (1.0,)),
        delay(tone(200, 1.20, 2.2, (1.0, 0.2)), 0.10),
    ))


if __name__ == '__main__':
    main()

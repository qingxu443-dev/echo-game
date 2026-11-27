"""Regenerate ECHO's original ambient loop and UI/combat cues (stdlib only)."""
from array import array
from math import exp, pi, sin
from pathlib import Path
import random
import wave

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / "assets" / "audio"


def write(name, samples):
    samples = list(samples)
    peak = max(1.0, max(abs(x) for x in samples))
    pcm = array("h", (round(x / peak * 25000) for x in samples))
    with wave.open(str(OUT / f"{name}.wav"), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm.tobytes())


def ambient():
    duration = 32
    # A minor -> F -> C -> G, with quiet overlapping pads and distant bells.
    chords = [(110, 164.81, 220), (87.31, 130.81, 174.61),
              (130.81, 164.81, 196), (98, 146.83, 196)]
    for frame in range(duration * RATE):
        t = frame / RATE
        value = 0.0
        for index, chord in enumerate(chords):
            local = (t - index * 8) % duration
            if local < 12:
                envelope = sin(pi * local / 12) ** 2
                for frequency in chord:
                    frequency = round(frequency * duration) / duration
                    value += 0.10 * envelope * (sin(2*pi*frequency*t) + .12*sin(4*pi*frequency*t))
        for index, frequency in enumerate([440, 523.25, 659.25, 587.33]):
            local = (t - (index * 8 + 2)) % duration
            if local < 5:
                value += .045 * exp(-local * 1.1) * sin(pi * min(local / .03, 1) / 2) * sin(2*pi*frequency*local)
        yield value


def tone(duration, frequencies, decay):
    for frame in range(round(duration * RATE)):
        t = frame / RATE
        attack = min(1.0, t / .008)
        yield .4 * attack * exp(-t * decay) * sum(sin(2*pi*f*t) for f in frequencies) / len(frequencies)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    write("dusk_ambient", ambient())
    write("confirm", tone(.14, [660, 990], 27))
    write("chime", tone(.55, [440, 659.25, 880], 7))
    write("step", tone(.10, [180, 270], 35))
    noise = random.Random(20261127)
    write("impact", (.42 * exp(-i/RATE*26) *
                     (.7*sin(2*pi*95*i/RATE) + .3*noise.uniform(-1, 1))
                     for i in range(round(.18 * RATE))))

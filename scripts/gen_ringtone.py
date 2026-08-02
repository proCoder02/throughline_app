"""One-off generator for the incoming-call notification sound (classic
dual-tone ring cadence: ~1s ring, ~1s silence, repeated), written directly
as an Android raw resource. Not part of the app build -- run manually
whenever the ringtone needs regenerating."""
import math
import struct
import wave

SAMPLE_RATE = 44100
OUT_PATH = "android/app/src/main/res/raw/incoming_call_ringtone.wav"


def tone_samples(freq1, freq2, duration_s, volume=0.35):
    n = int(SAMPLE_RATE * duration_s)
    fade = int(SAMPLE_RATE * 0.02)
    samples = []
    for i in range(n):
        envelope = 1.0
        if i < fade:
            envelope = i / fade
        elif i > n - fade:
            envelope = (n - i) / fade
        val = volume * envelope * (math.sin(2 * math.pi * freq1 * i / SAMPLE_RATE) +
                                    math.sin(2 * math.pi * freq2 * i / SAMPLE_RATE)) / 2
        samples.append(int(val * 32767))
    return samples


def silence_samples(duration_s):
    return [0] * int(SAMPLE_RATE * duration_s)


def main():
    # Classic North American ring cadence: ~440/480Hz dual tone, 1s on, 1s
    # off, three rings -- long enough for a heads-up notification to be
    # clearly audible without dragging on.
    data = []
    for _ in range(3):
        data += tone_samples(440, 480, 1.0)
        data += silence_samples(1.0)

    with wave.open(OUT_PATH, "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SAMPLE_RATE)
        f.writeframes(struct.pack(f"<{len(data)}h", *data))

    print(f"Wrote {OUT_PATH} ({len(data) / SAMPLE_RATE:.1f}s)")


if __name__ == "__main__":
    main()

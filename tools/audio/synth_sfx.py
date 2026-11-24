"""Synthesizes the game's placeholder sound effects (16-bit mono WAV, 22.05 kHz).

Usage: python3 synth_sfx.py <out_dir>
Gunshot = sharp supersonic-style crack + low boom + room tail; mechanical sounds
are short filtered noise bursts with metallic resonances.
"""
import os
import sys
import wave

import numpy as np

SR = 22050
rng = np.random.default_rng(1911)
out = sys.argv[1] if len(sys.argv) > 1 else "."
os.makedirs(out, exist_ok=True)


def t(sec):
    return np.arange(int(SR * sec)) / SR


def env(n, attack, decay):
    x = np.arange(n) / SR
    a = np.clip(x / max(attack, 1e-4), 0, 1)
    return a * np.exp(-x / decay)


def lowpass(x, cutoff):
    # one-pole low-pass, applied twice
    a = np.exp(-2 * np.pi * cutoff / SR)
    for _ in range(2):
        y = np.zeros_like(x)
        acc = 0.0
        for i, v in enumerate(x):
            acc = (1 - a) * v + a * acc
            y[i] = acc
        x = y
    return x


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def ring(freq, sec, decay, amp=1.0):
    tt = t(sec)
    return amp * np.sin(2 * np.pi * freq * tt) * np.exp(-tt / decay)


def pad(x, sec):
    n = int(SR * sec)
    return np.pad(x, (0, max(0, n - len(x))))[:n]


def save(name, x, gain=0.9):
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    data = (x * 32767).astype(np.int16)
    with wave.open(os.path.join(out, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wrote", name)


def mix(*xs):
    """Sum clips of different lengths (zero-padded to the longest)."""
    n = max(len(x) for x in xs)
    return sum(np.pad(x, (0, n - len(x))) for x in xs)


def burst(sec, hp, attack, decay):
    """High-passed noise burst with an envelope."""
    return highpass(noise(sec), hp) * env(int(SR * sec), attack, decay)


def noise(sec):
    return rng.uniform(-1, 1, int(SR * sec))


# --- .45 ACP gunshot: big subsonic boom, less crack than a rifle.
n = noise(0.9)
crack = highpass(n, 2500) * env(len(n), 0.0003, 0.004) * 0.8
boom = lowpass(n, 260) * env(len(n), 0.001, 0.09) * 6.0
body = lowpass(n, 1200) * env(len(n), 0.0005, 0.03) * 1.6
tail = lowpass(noise(0.9), 700) * env(len(n), 0.02, 0.28) * 0.9
thump = ring(70, 0.9, 0.06, 1.2)
save("shot_45.wav", crack + boom + body + tail + thump, 0.95)

# --- Dry fire: hammer falls on an empty chamber.
x = pad(mix(burst(0.03, 1500, 0.0002, 0.004), ring(3100, 0.08, 0.012, 0.5)), 0.12)
save("dry_fire.wav", x, 0.6)

# --- Magazine out / in, slide release.
mo = pad(mix(burst(0.05, 800, 0.0005, 0.01), ring(1800, 0.1, 0.02, 0.4)), 0.2)
save("mag_out.wav", mo, 0.6)
mi1 = mix(burst(0.04, 900, 0.0003, 0.006), ring(2200, 0.04, 0.01, 0.4))
mi = pad(np.concatenate([mi1, np.zeros(int(SR * 0.05)), mix(mi1 * 1.3, ring(1400, 0.04, 0.015, 0.6))]), 0.25)
save("mag_in.wav", mi, 0.7)
sr_ = pad(mix(burst(0.06, 600, 0.0002, 0.012), ring(950, 0.15, 0.03, 0.8), ring(2600, 0.1, 0.015, 0.4)), 0.25)
save("slide_release.wav", sr_, 0.8)

# --- Casing tinkle on the floor.
c = ring(4200, 0.25, 0.05, 0.6) + ring(6100, 0.25, 0.03, 0.4)
c = c + np.concatenate([np.zeros(int(SR * 0.09)), ring(4700, 0.16, 0.03, 0.4)])[:len(c)]
save("casing.wav", pad(c, 0.3), 0.35)

# --- Impacts.
save("impact_hard.wav", pad(lowpass(noise(0.15), 2500) * env(int(SR * 0.15), 0.0003, 0.025), 0.2), 0.6)
save("impact_metal.wav", pad(mix(burst(0.05, 2000, 0.0002, 0.006), ring(2900, 0.4, 0.08, 0.7), ring(4300, 0.3, 0.05, 0.3)), 0.45), 0.7)
save("impact_wood.wav", pad(mix(lowpass(noise(0.12), 1500) * env(int(SR * 0.12), 0.0003, 0.02), ring(420, 0.12, 0.03, 0.5)), 0.15), 0.6)
save("impact_glass.wav", pad(mix(burst(0.5, 3000, 0.0002, 0.12), ring(5200, 0.4, 0.06, 0.3)), 0.55), 0.6)
save("impact_flesh.wav", pad(mix(lowpass(noise(0.12), 600) * env(int(SR * 0.12), 0.001, 0.025), ring(110, 0.12, 0.04, 0.6)), 0.15), 0.6)

# --- Ricochet whine: falling pitch sweep.
tt = t(0.6)
f = 2400 * np.exp(-tt * 2.2) + 600
phase = 2 * np.pi * np.cumsum(f) / SR
rico = np.sin(phase) * np.exp(-tt / 0.22) * 0.6 + highpass(noise(0.6), 3000) * env(len(tt), 0.0002, 0.01)
save("ricochet.wav", rico, 0.55)


# --- Ka-Bar: swish (air past the blade), flesh stab / slash, blade on hard surface, draw from sheath.
def sweep_noise(sec, f0, f1, q=0.25):
    """Noise through a band-pass whose centre slides from f0 to f1 (a blade cutting air)."""
    n = noise(sec)
    out_ = np.zeros_like(n)
    lo, hi = 0.0, 0.0
    for i, v in enumerate(n):
        f = f0 + (f1 - f0) * i / len(n)
        a = np.exp(-2 * np.pi * f / SR)
        b = np.exp(-2 * np.pi * f * (1 + q) / SR)
        lo = (1 - a) * v + a * lo
        hi = (1 - b) * v + b * hi
        out_[i] = hi - lo
    return out_


tt = np.arange(int(SR * 0.28)) / SR
sw = sweep_noise(0.28, 700, 2600) * np.sin(np.pi * np.clip(tt / 0.28, 0, 1)) ** 2
save("knife_swish.wav", pad(sw, 0.3), 0.55)
sw2 = sweep_noise(0.18, 1200, 3200) * np.sin(np.pi * np.clip(np.arange(int(SR * 0.18)) / SR / 0.18, 0, 1)) ** 2
save("knife_thrust.wav", pad(sw2, 0.2), 0.5)

wet = lowpass(noise(0.22), 900) * env(int(SR * 0.22), 0.004, 0.05)
squelch = lowpass(noise(0.22), 2200) * env(int(SR * 0.22), 0.03, 0.04) * 0.5
save("knife_stab_flesh.wav", pad(mix(wet * 1.5, squelch, ring(85, 0.2, 0.05, 0.9)), 0.28), 0.75)

tear = highpass(noise(0.16), 1200) * env(int(SR * 0.16), 0.002, 0.035)
save("knife_slash_flesh.wav", pad(mix(tear, lowpass(noise(0.16), 700) * env(int(SR * 0.16), 0.002, 0.03) * 0.8), 0.2), 0.65)

save("knife_hit_hard.wav", pad(mix(burst(0.04, 2500, 0.0002, 0.005), ring(3600, 0.35, 0.07, 0.6), ring(5100, 0.25, 0.04, 0.35)), 0.4), 0.6)

scrape = sweep_noise(0.35, 2500, 4500, 0.15) * env(int(SR * 0.35), 0.05, 0.25)
save("knife_draw.wav", pad(mix(scrape, ring(4200, 0.3, 0.05, 0.15)), 0.4), 0.45)


# --- Suppressed .45: subsonic, so no crack: a dull "thup", the slide cycling, a little hiss.
n = noise(0.5)
thup = lowpass(n, 380) * env(len(n), 0.001, 0.035) * 3.0
hiss = highpass(noise(0.5), 3000) * env(len(n), 0.002, 0.05) * 0.25
clack = pad(mix(burst(0.03, 1800, 0.0002, 0.006), ring(2600, 0.08, 0.015, 0.4)), 0.5)
clack = np.roll(clack, int(SR * 0.012))
save("shot_45_supp.wav", thup + hiss + clack * 0.9, 0.7)

# --- 5.56 NATO from a 14.5 in carbine: a much sharper, louder supersonic crack and
#     muzzle blast, less low boom than the .45, short and harsh.
n = noise(0.8)
crack = highpass(n, 3200) * env(len(n), 0.0002, 0.006) * 2.2
blast = lowpass(n, 900) * env(len(n), 0.0004, 0.035) * 3.2
boom = lowpass(n, 200) * env(len(n), 0.001, 0.06) * 3.0
tail = lowpass(noise(0.8), 1500) * env(len(n), 0.015, 0.22) * 0.8
save("shot_556.wav", crack + blast + boom + tail + ring(95, 0.8, 0.04, 0.8), 0.95)

# --- AR mechanics: mag out (button click + slide out), mag in (seat + slap),
#     bolt catch release (carrier slams home), charging handle (pull + release),
#     selector (detent click).
mo = pad(mix(burst(0.02, 1500, 0.0002, 0.004), ring(2400, 0.06, 0.01, 0.4),
             np.concatenate([np.zeros(int(SR * 0.05)), lowpass(noise(0.12), 1800) * env(int(SR * 0.12), 0.005, 0.03) * 0.6])), 0.25)
save("mag_out_rifle.wav", mo, 0.6)
seat = mix(burst(0.03, 700, 0.0003, 0.006), ring(1300, 0.06, 0.015, 0.6))
slap = mix(burst(0.04, 500, 0.0002, 0.01) * 1.4, ring(900, 0.08, 0.02, 0.5))
save("mag_in_rifle.wav", pad(np.concatenate([seat, np.zeros(int(SR * 0.06)), slap]), 0.3), 0.75)
br = pad(mix(burst(0.02, 2000, 0.0002, 0.004), np.concatenate([np.zeros(int(SR * 0.03)),
         mix(burst(0.06, 400, 0.0002, 0.015) * 1.5, ring(700, 0.18, 0.04, 0.9), ring(2100, 0.12, 0.02, 0.4))])), 0.3)
save("bolt_release.wav", br, 0.85)
pull = lowpass(noise(0.14), 2500) * env(int(SR * 0.14), 0.01, 0.05) * 0.7
home = mix(burst(0.06, 450, 0.0002, 0.014) * 1.5, ring(720, 0.18, 0.04, 0.9), ring(2000, 0.1, 0.02, 0.4))
save("charge.wav", pad(np.concatenate([pull, np.zeros(int(SR * 0.12)), home]), 0.45), 0.8)
save("selector.wav", pad(mix(burst(0.015, 2500, 0.0001, 0.003), ring(3800, 0.05, 0.008, 0.5)), 0.08), 0.55)

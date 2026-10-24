#!/usr/bin/env python3
"""Offline sound generator for Iron & Angles.

Every sound in the game is synthesized here from noise, oscillators and filters, so the
audio is reproducible and carries no third-party samples. Standard library only (no numpy),
fixed seeds: the same script always writes the same files.

Regenerate (from the project folder):
    python3 audio/tools/generate_sounds.py
then let Godot import them once:
    $GODOT --headless --path . --import

Output: 44.1 kHz, 16-bit mono .wav files in audio/sfx, audio/ui, audio/music, audio/ambience.
Each one-shot is normalized to -1 dBFS; in-game levels live in scripts/fx/sound_bank.gd.
"""

import math
import os
import random
import struct
import sys
import wave
from array import array

SR = 44100
TAU = 2.0 * math.pi
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


# ---------------------------------------------------------------- buffers and helpers

def zeros(seconds):
    return [0.0] * int(seconds * SR)


def n_of(seconds):
    return int(seconds * SR)


def mix(dst, src, at=0.0, gain=1.0):
    """Adds src into dst starting at `at` seconds (dst grows if needed)."""
    start = int(at * SR)
    end = start + len(src)
    if end > len(dst):
        dst.extend([0.0] * (end - len(dst)))
    for i, v in enumerate(src):
        dst[start + i] += v * gain
    return dst


def scale(buf, g):
    return [v * g for v in buf]


def normalize(buf, peak=0.89):
    m = max(1e-9, max(abs(v) for v in buf))
    return [v * peak / m for v in buf]


def soft_clip(buf, drive=1.0):
    t = math.tanh(drive)
    return [math.tanh(v * drive) / t for v in buf]


def fade(buf, fade_in=0.002, fade_out=0.01):
    n = len(buf)
    a = max(1, n_of(fade_in))
    b = max(1, n_of(fade_out))
    for i in range(min(a, n)):
        buf[i] *= i / a
    for i in range(min(b, n)):
        buf[n - 1 - i] *= i / b
    return buf


def trim_tail(buf, threshold_db=-54.0):
    """Cuts the silent end: everything after the last sample above threshold_db re. peak."""
    threshold = max(abs(v) for v in buf) * 10 ** (threshold_db / 20.0)
    i = len(buf) - 1
    while i > 0 and abs(buf[i]) < threshold:
        i -= 1
    return buf[: i + 1 + n_of(0.01)]


# ---------------------------------------------------------------- sources

def noise(rng, seconds):
    return [rng.uniform(-1.0, 1.0) for _ in range(n_of(seconds))]


def sweep(f0, f1, seconds, shape="exp", amp=1.0, wave_fn=math.sin, phase=0.0):
    """Oscillator gliding from f0 to f1 (exponential or linear glide)."""
    n = n_of(seconds)
    out = [0.0] * n
    ph = phase
    for i in range(n):
        t = i / max(1, n - 1)
        f = f0 * (f1 / f0) ** t if shape == "exp" else f0 + (f1 - f0) * t
        ph += TAU * f / SR
        out[i] = amp * wave_fn(ph)
    return out


def tone(freq, seconds, amp=1.0):
    return sweep(freq, freq, seconds, amp=amp)


def partials(freqs_amps_decays, seconds):
    """Inharmonic struck-metal/bell: sum of exponentially decaying sines."""
    n = n_of(seconds)
    out = [0.0] * n
    for f, a, decay in freqs_amps_decays:
        w = TAU * f / SR
        k = math.exp(-1.0 / (decay * SR))
        env = a
        for i in range(n):
            out[i] += env * math.sin(w * i)
            env *= k
    return out


def impulses(rng, seconds, rate, length=0.004, density_env=None):
    """Random clicks (crackle, debris, rain): `rate` clicks per second on average."""
    n = n_of(seconds)
    out = [0.0] * n
    L = max(2, n_of(length))
    i = 0
    while i < n:
        t = i / n
        r = rate * (density_env(t) if density_env else 1.0)
        if r <= 0:
            i += n_of(0.01)
            continue
        i += max(1, int(rng.expovariate(r) * SR))
        if i >= n:
            break
        amp = rng.uniform(0.2, 1.0) * (1 if rng.random() < 0.5 else -1)
        for j in range(min(L, n - i)):
            out[i + j] += amp * (1.0 - j / L) ** 2 * rng.uniform(-1.0, 1.0)
    return out


# ---------------------------------------------------------------- envelopes

def env_exp(buf, decay, attack=0.002):
    a = max(1, n_of(attack))
    k = math.exp(-1.0 / (decay * SR))
    e = 1.0
    for i in range(len(buf)):
        if i < a:
            buf[i] *= i / a
        else:
            buf[i] *= e
            e *= k
    return buf


def env_curve(buf, points):
    """Piecewise-linear envelope from (time_s, gain) points."""
    pts = sorted(points)
    j = 0
    for i in range(len(buf)):
        t = i / SR
        while j < len(pts) - 2 and t > pts[j + 1][0]:
            j += 1
        (t0, g0), (t1, g1) = pts[j], pts[min(j + 1, len(pts) - 1)]
        if t <= t0:
            g = g0
        elif t >= t1:
            g = g1
        else:
            g = g0 + (g1 - g0) * (t - t0) / (t1 - t0)
        buf[i] *= g
    return buf


# ---------------------------------------------------------------- filters

def lowpass1(buf, cutoff):
    a = 1.0 - math.exp(-TAU * cutoff / SR)
    y = 0.0
    out = [0.0] * len(buf)
    for i, x in enumerate(buf):
        y += a * (x - y)
        out[i] = y
    return out


def highpass1(buf, cutoff):
    low = lowpass1(buf, cutoff)
    return [x - l for x, l in zip(buf, low)]


def svf(buf, cutoff, q=0.7, mode="lp"):
    """Zero-delay-feedback state-variable filter (stable at any cutoff and q).
    cutoff may be a number or a function of t in 0..1."""
    k = 1.0 / q
    ic1 = ic2 = 0.0
    out = [0.0] * len(buf)
    n = len(buf)
    fixed = not callable(cutoff)

    def coeffs(fc):
        g = math.tan(math.pi * min(max(fc, 10.0), SR * 0.45) / SR)
        a1 = 1.0 / (1.0 + g * (g + k))
        return a1, g * a1, g * g * a1

    a1, a2, a3 = coeffs(cutoff) if fixed else (0.0, 0.0, 0.0)
    for i, x in enumerate(buf):
        if not fixed and i % 16 == 0:
            a1, a2, a3 = coeffs(cutoff(i / n))
        v3 = x - ic2
        v1 = a1 * ic1 + a2 * v3
        v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        out[i] = v2 if mode == "lp" else v1 if mode == "bp" else x - k * v1 - v2
    return out


def comb_reverb(buf, seconds_tail=1.2, wet=0.25, rng_seed=7):
    """Small Schroeder-style room so stings and chimes don't sound bone dry."""
    delays = [0.0297, 0.0371, 0.0411, 0.0437]
    fb = 0.001 ** (max(delays) / seconds_tail)
    out = buf + [0.0] * n_of(seconds_tail)
    wet_sig = [0.0] * len(out)
    for d in delays:
        D = n_of(d)
        line = [0.0] * D
        idx = 0
        for i in range(len(out)):
            x = out[i] if i < len(buf) else 0.0
            y = line[idx]
            line[idx] = x + y * fb
            idx = (idx + 1) % D
            wet_sig[i] += y / len(delays)
    return [o * (1.0 - wet) + w * wet for o, w in zip(out, wet_sig)]


# ---------------------------------------------------------------- building blocks

def thump(f0, f1, decay, seconds=None):
    s = sweep(f0, f1, seconds or decay * 6)
    return env_exp(s, decay, attack=0.001)


def crack(rng, decay=0.012, hp=1500):
    return env_exp(highpass1(noise(rng, decay * 8), hp), decay, attack=0.0005)


def rumble(rng, seconds, cutoff, decay):
    return env_exp(svf(noise(rng, seconds), cutoff, q=0.6), decay, attack=0.01)


def whoosh(rng, seconds, f_lo, f_hi, q=1.5):
    def center(t):
        return f_lo + (f_hi - f_lo) * math.sin(math.pi * t) ** 2
    s = svf(noise(rng, seconds), center, q=q, mode="bp")
    return env_curve(s, [(0, 0), (seconds * 0.45, 1.0), (seconds, 0)])


def metal_hit(base, decay=0.35, brightness=1.0):
    ratios = [(1.0, 1.0), (2.41, 0.6), (3.87, 0.45 * brightness), (5.43, 0.3 * brightness), (7.1, 0.18 * brightness)]
    return partials([(base * r, a, decay / (1 + 0.4 * k)) for k, (r, a) in enumerate(ratios)], decay * 4)


def bell(freq, decay=0.9, amp=1.0):
    return partials([(freq, amp, decay), (freq * 2.0, amp * 0.35, decay * 0.6),
                     (freq * 2.76, amp * 0.25, decay * 0.4), (freq * 5.4, amp * 0.08, decay * 0.2)], decay * 3.5)


def wood_knock(rng, freq, decay=0.05):
    body = partials([(freq, 1.0, decay), (freq * 1.58, 0.5, decay * 0.7), (freq * 2.37, 0.25, decay * 0.5)], decay * 6)
    click = env_exp(svf(noise(rng, 0.02), freq * 3, q=2, mode="bp"), 0.004)
    return mix(body, click, gain=0.6)


def brass(freq, seconds, amp=1.0, bright=2200.0):
    """Saw-ish brass: harmonic stack through a lowpass that opens on the attack."""
    n = n_of(seconds)
    out = [0.0] * n
    ph = 0.0
    for i in range(n):
        ph += TAU * freq * (1 + 0.003 * math.sin(TAU * 5.2 * i / SR)) / SR
        out[i] = sum(math.sin(ph * h) / h for h in range(1, 9))
    out = svf(out, lambda t: 300 + bright * min(1.0, t * seconds / 0.08), q=0.8)
    return env_curve([v * amp for v in out], [(0, 0), (0.04, 1.0), (seconds * 0.7, 0.75), (seconds, 0)])


# ---------------------------------------------------------------- the sounds

def s_launch_trebuchet(rng):
    out = zeros(1.6)
    # Creak: rope and timber under load, a slow train of resonant friction clicks.
    creak = impulses(rng, 0.42, 55, length=0.006, density_env=lambda t: 0.4 + t)
    creak = svf(creak, 520, q=6, mode="bp")
    creak = env_curve(creak, [(0, 0.2), (0.35, 1.0), (0.42, 0.6)])
    mix(out, creak, 0.0, 0.9)
    # Thunk: the arm hits the crossbar.
    mix(out, thump(95, 48, 0.09), 0.40, 1.0)
    mix(out, wood_knock(rng, 310, 0.06), 0.40, 0.8)
    # Whoosh: the sling and the stone leaving.
    mix(out, whoosh(rng, 0.9, 250, 1400, q=1.2), 0.36, 0.7)
    return fade(out, 0.002, 0.15)


def s_launch_gunpowder(rng):
    out = zeros(2.6)
    mix(out, crack(rng, 0.01, 1200), 0, 0.9)
    mix(out, thump(70, 32, 0.22, 1.4), 0, 1.4)
    mix(out, rumble(rng, 1.6, 420, 0.25), 0, 1.3)
    mix(out, rumble(rng, 2.6, 140, 0.8), 0.02, 1.0)
    return fade(soft_clip(out, 1.8), 0.0005, 0.3)


def s_launch_rocket(rng):
    out = zeros(1.9)
    mix(out, crack(rng, 0.008, 900), 0, 0.5)
    mix(out, thump(110, 60, 0.05), 0, 0.6)
    hiss = svf(noise(rng, 1.9), lambda t: 5200 - 3000 * t, q=0.9, mode="bp")
    hiss = env_curve(hiss, [(0, 0), (0.04, 1.0), (0.6, 0.8), (1.9, 0)])
    mix(out, hiss, 0, 0.9)
    crackle = svf(impulses(rng, 1.4, 160, 0.002), 2500, q=1.5, mode="bp")
    mix(out, env_curve(crackle, [(0, 1), (1.4, 0)]), 0.02, 0.5)
    mix(out, whoosh(rng, 1.3, 180, 700, q=1), 0.05, 0.6)
    return fade(out, 0.001, 0.2)


def s_launch_railgun(rng):
    out = zeros(1.5)
    mix(out, crack(rng, 0.006, 3000), 0, 1.2)
    zap = env_exp(sweep(4200, 180, 0.14, amp=1.0, wave_fn=lambda p: math.copysign(1, math.sin(p)) * 0.6), 0.05)
    mix(out, svf(zap, 6000), 0, 0.6)
    mix(out, metal_hit(1230, 0.45, 1.2), 0, 0.35)
    mix(out, thump(80, 40, 0.12), 0, 0.9)
    mix(out, rumble(rng, 1.2, 300, 0.3), 0.01, 0.4)
    return fade(soft_clip(out, 1.3), 0.0005, 0.2)


def s_railgun_charge(rng):
    """Capacitor whine: the railgun's reload, ending in a 'ready' click."""
    out = zeros(1.15)
    vib = lambda p: math.sin(p) + 0.3 * math.sin(2 * p) + 0.15 * math.sin(3 * p)
    whine = sweep(380, 3900, 1.0, wave_fn=vib, amp=0.6)
    whine = env_curve(whine, [(0, 0), (0.15, 0.5), (0.95, 1.0), (1.0, 0)])
    mix(out, whine, 0, 0.6)
    mix(out, env_curve(svf(noise(rng, 1.0), 6000, q=2, mode="bp"), [(0, 0), (1.0, 0.4)]), 0, 0.2)
    mix(out, metal_hit(2600, 0.04), 1.0, 0.6)
    return fade(out, 0.005, 0.03)


def s_orbital_uplink(rng):
    out = zeros(0.7)
    for k, at in enumerate((0.0, 0.12, 0.24)):
        b = env_curve(tone(1750 + 250 * k, 0.07), [(0, 0), (0.005, 1), (0.06, 1), (0.07, 0)])
        mix(out, b, at, 0.5)
    data = svf(impulses(rng, 0.25, 900, 0.001), 3000, q=1, mode="bp")
    mix(out, data, 0.38, 0.4)
    return fade(out, 0.001, 0.02)


def s_orbital_descent(rng):
    """3 s rising roar: a rod falling from orbit, louder and higher until it lands."""
    out = zeros(3.0)
    shriek = sweep(140, 1600, 3.0, wave_fn=lambda p: math.sin(p) + 0.4 * math.sin(2.01 * p))
    mix(out, env_curve(shriek, [(0, 0), (2.0, 0.35), (2.95, 1.0), (3.0, 0)]), 0, 0.45)
    roar = svf(noise(rng, 3.0), lambda t: 200 + 5000 * t ** 2, q=0.8)
    mix(out, env_curve(roar, [(0, 0), (1.5, 0.25), (2.95, 1.0), (3.0, 0)]), 0, 1.0)
    return out


def s_reload_clank(rng):
    out = zeros(0.9)
    mix(out, metal_hit(440, 0.18), 0.0, 0.7)            # shell slides in
    mix(out, thump(120, 70, 0.04), 0.0, 0.5)
    mix(out, metal_hit(610, 0.28, 1.3), 0.22, 1.0)      # breech slams shut
    mix(out, thump(90, 50, 0.07), 0.22, 0.9)
    mix(out, crack(rng, 0.004, 3000), 0.36, 0.5)        # latch
    return fade(out, 0.001, 0.05)


def s_reload_trebuchet(rng):
    """Winch ratchet winding the arm down, then the rope settles."""
    out = zeros(1.1)
    t = 0.0
    k = 0
    while t < 0.8:
        mix(out, wood_knock(rng, 900 + rng.uniform(-60, 60), 0.012), t, 0.5)
        t += 0.11 - 0.05 * (k / 10.0)
        k += 1
    creak = svf(impulses(rng, 0.5, 70, 0.006), 600, q=8, mode="bp")
    mix(out, env_curve(creak, [(0, 0), (0.25, 1), (0.5, 0)]), 0.3, 0.6)
    mix(out, thump(85, 55, 0.08), 0.85, 0.8)
    return fade(out, 0.001, 0.05)


def s_bounce_thud(rng):
    out = zeros(0.6)
    mix(out, thump(95, 55, 0.07), 0, 1.0)
    mix(out, env_exp(svf(noise(rng, 0.5), 900, q=0.7), 0.08), 0, 0.6)
    mix(out, svf(impulses(rng, 0.4, 60, 0.003, lambda t: 1 - t), 1800, q=1, mode="bp"), 0.03, 0.3)
    return fade(out, 0.0005, 0.05)


def s_impact_explosive(rng):
    out = zeros(3.2)
    mix(out, crack(rng, 0.015, 800), 0, 1.0)
    mix(out, thump(60, 28, 0.3, 1.6), 0, 1.6)
    mix(out, rumble(rng, 2.0, 600, 0.3), 0, 1.4)
    mix(out, rumble(rng, 3.2, 120, 1.0), 0.03, 1.0)
    debris = svf(impulses(rng, 2.2, 45, 0.004, lambda t: (1 - t) ** 2), 1600, q=0.8, mode="bp")
    mix(out, debris, 0.25, 0.5)
    return fade(soft_clip(out, 2.0), 0.0005, 0.4)


def s_impact_kinetic(rng):
    out = zeros(1.6)
    mix(out, thump(75, 40, 0.12), 0, 1.4)
    mix(out, env_exp(svf(noise(rng, 0.6), 1500, q=1.2, mode="bp"), 0.06), 0, 0.9)
    mix(out, rumble(rng, 1.2, 250, 0.3), 0, 0.6)
    debris = svf(impulses(rng, 1.2, 50, 0.004, lambda t: (1 - t) ** 2), 1400, q=0.8, mode="bp")
    mix(out, debris, 0.08, 0.4)
    return fade(soft_clip(out, 1.5), 0.0005, 0.2)


def s_impact_incendiary(rng):
    out = zeros(2.6)
    whoomp = env_curve(svf(noise(rng, 0.9), lambda t: 200 + 900 * t, q=0.7), [(0, 0), (0.06, 1), (0.9, 0)])
    mix(out, whoomp, 0, 1.2)
    mix(out, thump(55, 40, 0.15), 0, 0.6)
    crackle = svf(impulses(rng, 2.4, 90, 0.002, lambda t: 1 - t), 3000, q=1.2, mode="bp")
    mix(out, crackle, 0.1, 0.8)
    mix(out, env_curve(svf(noise(rng, 2.4), 700, q=0.6), [(0, 0.5), (2.4, 0)]), 0.1, 0.4)
    return fade(soft_clip(out, 1.4), 0.002, 0.3)


def s_impact_shrapnel(rng):
    out = zeros(1.6)
    mix(out, crack(rng, 0.01, 1500), 0, 1.1)
    mix(out, thump(85, 45, 0.1), 0, 1.0)
    patter = svf(impulses(rng, 1.0, 160, 0.002, lambda t: (1 - t) ** 1.5), 3200, q=1.5, mode="bp")
    mix(out, patter, 0.05, 0.9)
    mix(out, rumble(rng, 1.2, 400, 0.25), 0, 0.6)
    return fade(soft_clip(out, 1.5), 0.0005, 0.2)


def s_impact_ap(rng):
    out = zeros(1.4)
    mix(out, crack(rng, 0.006, 2500), 0, 1.0)
    mix(out, metal_hit(330, 0.2, 0.8), 0, 0.5)
    mix(out, thump(70, 35, 0.15), 0.01, 1.3)
    mix(out, rumble(rng, 1.2, 300, 0.3), 0.01, 0.6)
    return fade(soft_clip(out, 1.5), 0.0005, 0.2)


def s_impact_massive(rng):
    out = zeros(4.5)
    mix(out, crack(rng, 0.02, 600), 0, 1.0)
    mix(out, thump(48, 22, 0.5, 2.5), 0, 1.8)
    mix(out, rumble(rng, 3.0, 500, 0.5), 0, 1.4)
    mix(out, rumble(rng, 4.5, 90, 1.5), 0.05, 1.2)
    debris = svf(impulses(rng, 3.5, 70, 0.005, lambda t: (1 - t) ** 2), 1200, q=0.8, mode="bp")
    mix(out, debris, 0.4, 0.5)
    return fade(soft_clip(out, 2.4), 0.0005, 0.5)


def s_debris(rng):
    out = zeros(1.3)
    d = svf(impulses(rng, 1.2, 70, 0.005, lambda t: (1 - t) ** 1.5), 1100, q=0.7, mode="bp")
    mix(out, d, 0, 1.0)
    mix(out, env_curve(svf(noise(rng, 1.2), 400), [(0, 0.6), (1.2, 0)]), 0, 0.4)
    return fade(out, 0.005, 0.1)


def s_target_hit(rng):
    out = zeros(0.9)
    for at in (0.0, 0.035, 0.07):
        mix(out, env_exp(svf(noise(rng, 0.2), rng.uniform(900, 1700), q=3, mode="bp"), 0.03), at, 0.8)
    mix(out, wood_knock(rng, 180, 0.08), 0, 0.7)
    creak = svf(impulses(rng, 0.45, 50, 0.006), 380, q=8, mode="bp")
    mix(out, env_curve(creak, [(0, 0), (0.1, 1), (0.45, 0)]), 0.12, 0.5)
    return fade(out, 0.0005, 0.08)


def s_target_collapse(rng):
    out = zeros(3.4)
    creak = svf(impulses(rng, 0.7, 40, 0.008, lambda t: 0.3 + t), 300, q=9, mode="bp")
    mix(out, env_curve(creak, [(0, 0.3), (0.6, 1), (0.7, 0)]), 0, 0.7)
    mix(out, env_exp(highpass1(noise(rng, 0.3), 2000), 0.04), 0.62, 0.6)      # splinter
    mix(out, rumble(rng, 2.6, 260, 0.7), 0.65, 1.4)
    rubble = svf(impulses(rng, 2.4, 55, 0.006, lambda t: math.sin(math.pi * min(1, t * 1.6)) ** 2), 900, q=0.8, mode="bp")
    mix(out, rubble, 0.7, 1.0)
    mix(out, thump(70, 35, 0.2), 0.75, 1.1)
    mix(out, thump(60, 30, 0.25), 1.55, 0.9)
    return fade(soft_clip(out, 1.4), 0.002, 0.4)


def s_battery_hit(rng):
    out = zeros(1.8)
    mix(out, crack(rng, 0.01, 1200), 0, 0.8)
    mix(out, metal_hit(260, 0.6, 1.3), 0, 0.9)
    mix(out, metal_hit(415, 0.4), 0.01, 0.5)
    mix(out, thump(65, 30, 0.2), 0, 1.2)
    mix(out, rumble(rng, 1.4, 500, 0.25), 0, 0.8)
    return fade(soft_clip(out, 1.6), 0.0005, 0.2)


def s_incoming_whistle(rng):
    """Enemy shell: a falling whistle that swells for 2.2 s until it lands."""
    out = zeros(2.2)
    w = sweep(2300, 650, 2.2, wave_fn=lambda p: math.sin(p) + 0.2 * math.sin(2 * p))
    mix(out, env_curve(w, [(0, 0), (1.2, 0.35), (2.15, 1.0), (2.2, 0)]), 0, 0.5)
    air = svf(noise(rng, 2.2), lambda t: 2600 - 1700 * t, q=4, mode="bp")
    mix(out, env_curve(air, [(0, 0), (2.1, 1.0), (2.2, 0)]), 0, 0.5)
    return out


def s_weapon_select(rng):
    out = zeros(0.25)
    mix(out, metal_hit(1500, 0.03), 0, 0.6)
    mix(out, metal_hit(1100, 0.04), 0.06, 0.7)
    mix(out, thump(160, 90, 0.02), 0.06, 0.4)
    return fade(out, 0.0005, 0.02)


def s_ui_click(rng):
    out = zeros(0.08)
    mix(out, env_exp(svf(noise(rng, 0.05), 3200, q=2, mode="bp"), 0.006), 0, 0.8)
    mix(out, env_exp(tone(1250, 0.05), 0.01), 0, 0.5)
    return fade(out, 0.0003, 0.01)


def s_ui_hover(rng):
    out = zeros(0.05)
    mix(out, env_exp(svf(noise(rng, 0.04), 4200, q=3, mode="bp"), 0.004), 0, 0.6)
    mix(out, env_exp(tone(2100, 0.04), 0.006), 0, 0.3)
    return fade(out, 0.0003, 0.01)


def s_ui_purchase(rng):
    out = zeros(1.4)
    mix(out, wood_knock(rng, 600, 0.03), 0, 0.5)                   # drawer
    coins = svf(impulses(rng, 0.3, 60, 0.003), 6000, q=3, mode="bp")
    mix(out, coins, 0.02, 0.5)
    mix(out, bell(1318.5, 0.5), 0.05, 0.6)                          # E6
    mix(out, bell(1760.0, 0.7), 0.15, 0.7)                          # A6
    return fade(comb_reverb(out, 0.6, 0.18), 0.0005, 0.1)


def s_ui_research(rng):
    out = zeros(1.8)
    for k, f in enumerate((523.25, 659.25, 783.99, 1046.5)):        # C5 E5 G5 C6
        mix(out, bell(f, 0.7 + 0.2 * k, 0.8), k * 0.09, 1.0)
    return fade(comb_reverb(out, 1.0, 0.25), 0.0005, 0.2)


def s_ui_era(rng):
    out = zeros(2.6)
    for f in (130.81, 196.0, 261.63, 329.63):                       # C3 G3 C4 E4
        mix(out, brass(f, 0.45, 0.35), 0, 1.0)
    for f in (196.0, 246.94, 293.66, 392.0):                        # G major
        mix(out, brass(f, 0.3, 0.3), 0.5, 1.0)
    for f in (130.81, 261.63, 329.63, 392.0, 523.25):               # C major
        mix(out, brass(f, 1.5, 0.3), 0.85, 1.0)
    mix(out, thump(80, 45, 0.3), 0.85, 0.6)
    return fade(comb_reverb(soft_clip(out, 1.2), 1.2, 0.25), 0.002, 0.3)


def s_auction_gavel(rng):
    out = zeros(0.9)
    mix(out, wood_knock(rng, 520, 0.05), 0, 0.6)
    mix(out, thump(140, 80, 0.04), 0, 0.5)
    mix(out, wood_knock(rng, 470, 0.07), 0.28, 1.0)
    mix(out, thump(120, 70, 0.06), 0.28, 0.8)
    return fade(comb_reverb(out, 0.5, 0.15), 0.0005, 0.08)


def s_ui_stamp(rng):
    out = zeros(0.4)
    mix(out, thump(160, 80, 0.03), 0, 0.9)
    mix(out, env_exp(svf(noise(rng, 0.15), 1800, q=0.8, mode="bp"), 0.02), 0, 0.7)
    return fade(out, 0.0005, 0.04)


def s_ui_payout(rng):
    out = zeros(1.6)
    for k in range(9):
        at = 0.05 * k + rng.uniform(0, 0.02)
        mix(out, bell(rng.uniform(2400, 3600), 0.15, 0.4), at, 1.0)
    mix(out, bell(1567.98, 0.8), 0.45, 0.7)                         # G6
    mix(out, bell(2093.0, 0.9), 0.55, 0.6)                          # C7
    return fade(comb_reverb(out, 0.7, 0.2), 0.0005, 0.15)


def s_ui_alert(rng):
    out = zeros(0.45)
    for at, f in ((0.0, 880.0), (0.16, 660.0)):
        b = env_curve(sweep(f, f, 0.12, wave_fn=lambda p: math.sin(p) + 0.3 * math.sin(3 * p)),
                      [(0, 0), (0.005, 1), (0.11, 1), (0.12, 0)])
        mix(out, b, at, 0.5)
    return fade(out, 0.001, 0.02)


def s_battle_start(rng):
    out = zeros(2.2)
    mix(out, brass(110.0, 1.4, 0.5, 1400), 0, 1.0)
    mix(out, brass(164.81, 1.4, 0.3, 1400), 0.05, 1.0)
    for at in (0.0, 0.5, 0.75):
        mix(out, thump(70, 40, 0.18), at, 0.6)
    return fade(comb_reverb(soft_clip(out, 1.2), 1.0, 0.25), 0.002, 0.3)


def s_sting_victory(rng):
    out = zeros(3.2)
    notes = [(0.0, 261.63, 0.18), (0.18, 329.63, 0.18), (0.36, 392.0, 0.18), (0.54, 523.25, 1.6)]
    for at, f, d in notes:
        mix(out, brass(f, d + 0.05, 0.5), at, 1.0)
        mix(out, brass(f / 2, d + 0.05, 0.25, 1200), at, 1.0)
    for f in (261.63, 329.63, 392.0):
        mix(out, brass(f, 1.6, 0.25, 1600), 0.54, 1.0)
    for at in (0.0, 0.54):
        mix(out, thump(75, 40, 0.3), at, 0.7)
    return fade(comb_reverb(soft_clip(out, 1.1), 1.5, 0.3), 0.002, 0.4)


def s_sting_defeat(rng):
    out = zeros(3.6)
    for at, f, d in ((0.0, 196.0, 0.5), (0.5, 185.0, 0.5), (1.0, 174.61, 0.5), (1.5, 146.83, 1.6)):
        mix(out, brass(f, d, 0.45, 900), at, 1.0)
        mix(out, brass(f / 2, d, 0.3, 600), at, 1.0)
    mix(out, thump(55, 30, 0.6, 2.0), 1.5, 0.8)
    return fade(comb_reverb(soft_clip(out, 1.1), 1.5, 0.3), 0.002, 0.4)


# ---------------------------------------------------------------- loops

def make_table(harmonics):
    size = 2048
    t = [0.0] * size
    for h, a in harmonics:
        for i in range(size):
            t[i] += a * math.sin(TAU * h * i / size)
    m = max(abs(v) for v in t)
    return [v / m for v in t]


def pad_voice(table, freq, seconds, attack, release, detune=1.004):
    n = n_of(seconds)
    out = [0.0] * n
    size = len(table)
    p1 = p2 = 0.0
    d1 = freq * size / SR
    d2 = d1 * detune
    a = max(1, n_of(attack))
    r = max(1, n_of(release))
    for i in range(n):
        p1 = (p1 + d1) % size
        p2 = (p2 + d2) % size
        g = min(1.0, i / a, (n - i) / r)
        out[i] = g * 0.5 * (table[int(p1)] + table[int(p2)])
    return out


def wrap_loop(buf, loop_seconds):
    """Folds everything past the loop end back onto the start, so the loop is seamless."""
    n = n_of(loop_seconds)
    out = buf[:n] + [0.0] * max(0, n - len(buf))
    for i in range(n, len(buf)):
        out[i % n] += buf[i]
    return out


def s_menu_theme(rng):
    """32 s loop: slow drafting-room pads (Dm - Bb - F - C) over a soft timpani pulse."""
    loop = 32.0
    pad_tab = make_table([(1, 1.0), (2, 0.45), (3, 0.3), (4, 0.12), (5, 0.1), (6, 0.05)])
    bass_tab = make_table([(1, 1.0), (2, 0.25), (3, 0.08)])
    chords = [(146.83, 174.61, 220.0, 293.66), (116.54, 146.83, 174.61, 233.08),
              (174.61, 220.0, 261.63, 349.23), (130.81, 164.81, 196.0, 261.63)]
    out = zeros(loop + 4.0)
    for k, chord in enumerate(chords):
        at = k * 8.0
        for f in chord:
            mix(out, pad_voice(pad_tab, f, 9.5, 2.0, 3.0), at, 0.16)
        mix(out, pad_voice(bass_tab, chord[0] / 2, 9.0, 0.6, 2.5, 1.0), at, 0.3)
        # A slow melody note per bar, high and quiet.
        mel = [440.0, 349.23, 523.25, 392.0][k]
        mix(out, pad_voice(pad_tab, mel * 2, 4.0, 0.8, 2.5, 1.002), at + 3.0, 0.06)
    for k in range(16):
        mix(out, env_exp(svf(noise(rng, 1.2), 160, q=0.8), 0.25), k * 2.0, 0.5 if k % 2 == 0 else 0.25)
    out = svf(out, 2400, q=0.6)
    out = wrap_loop(out, loop)
    return normalize(out, 0.6)


def s_amb_wind(rng):
    loop = 12.0
    n = n_of(loop)
    base = noise(rng, loop)

    def cut(t):  # Periodic in the loop, so the seam is clean.
        return 380 + 260 * math.sin(TAU * t) + 160 * math.sin(TAU * 3 * t + 1.3)

    w = svf(base, cut, q=1.4, mode="bp")
    howl = svf(noise(rng, loop), lambda t: 700 + 300 * math.sin(TAU * 2 * t + 0.5), q=10, mode="bp")
    out = [0.0] * n
    for i in range(n):
        t = i / n
        g = 0.6 + 0.3 * math.sin(TAU * t + 0.4) + 0.1 * math.sin(TAU * 4 * t)
        out[i] = g * w[i] + 0.25 * max(0.0, math.sin(TAU * 2 * t)) * howl[i]
    return crossfade_loop(out, 0.5)


def s_amb_rain(rng):
    loop = 8.0
    hiss = svf(noise(rng, loop), 4500, q=0.6)
    hiss = highpass1(hiss, 900)
    drops = svf(impulses(rng, loop, 260, 0.002), 3000, q=1.2, mode="bp")
    patter = svf(impulses(rng, loop, 40, 0.006), 700, q=1.5, mode="bp")
    out = [0.45 * h + 0.5 * d + 0.4 * p for h, d, p in zip(hiss, drops, patter)]
    return crossfade_loop(out, 0.5)


def crossfade_loop(buf, xfade):
    """Blends the last `xfade` seconds into the start and drops them, so the loop is seamless."""
    x = n_of(xfade)
    body = buf[: len(buf) - x]
    tail = buf[len(buf) - x:]
    for i in range(x):
        g = i / x
        body[i] = body[i] * g + tail[i] * (1.0 - g)
    return normalize(body, 0.7)


# ---------------------------------------------------------------- catalogue and output

SOUNDS = {
    "sfx/launch_trebuchet": s_launch_trebuchet,
    "sfx/launch_gunpowder": s_launch_gunpowder,
    "sfx/launch_rocket": s_launch_rocket,
    "sfx/launch_railgun": s_launch_railgun,
    "sfx/railgun_charge": s_railgun_charge,
    "sfx/orbital_uplink": s_orbital_uplink,
    "sfx/orbital_descent": s_orbital_descent,
    "sfx/reload_clank": s_reload_clank,
    "sfx/reload_trebuchet": s_reload_trebuchet,
    "sfx/bounce_thud": s_bounce_thud,
    "sfx/impact_explosive": s_impact_explosive,
    "sfx/impact_kinetic": s_impact_kinetic,
    "sfx/impact_incendiary": s_impact_incendiary,
    "sfx/impact_shrapnel": s_impact_shrapnel,
    "sfx/impact_ap": s_impact_ap,
    "sfx/impact_massive": s_impact_massive,
    "sfx/debris": s_debris,
    "sfx/target_hit": s_target_hit,
    "sfx/target_collapse": s_target_collapse,
    "sfx/battery_hit": s_battery_hit,
    "sfx/incoming_whistle": s_incoming_whistle,
    "sfx/weapon_select": s_weapon_select,
    "ui/click": s_ui_click,
    "ui/hover": s_ui_hover,
    "ui/purchase": s_ui_purchase,
    "ui/research": s_ui_research,
    "ui/era": s_ui_era,
    "ui/gavel": s_auction_gavel,
    "ui/stamp": s_ui_stamp,
    "ui/payout": s_ui_payout,
    "ui/alert": s_ui_alert,
    "music/battle_start": s_battle_start,
    "music/sting_victory": s_sting_victory,
    "music/sting_defeat": s_sting_defeat,
    "music/menu_theme": s_menu_theme,
    "ambience/wind": s_amb_wind,
    "ambience/rain": s_amb_rain,
}

LOOPS = {"music/menu_theme", "ambience/wind", "ambience/rain"}


def write_wav(path, buf):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = array("h", (max(-32767, min(32767, int(round(v * 32767)))) for v in buf))
    if sys.byteorder == "big":
        data.byteswap()
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def main(only=None):
    for k, (name, fn) in enumerate(sorted(SOUNDS.items())):
        if only and not any(o in name for o in only):
            continue
        # A seed per sound (from its name), so editing one sound never changes another.
        seed = sum((i + 1) * ord(c) for i, c in enumerate(name))
        buf = fn(random.Random(seed))
        if name not in LOOPS:
            buf = normalize(trim_tail(buf))
        write_wav(os.path.join(ROOT, name + ".wav"), buf)
        print("%-24s %5.2f s" % (name, len(buf) / SR))


if __name__ == "__main__":
    main(sys.argv[1:])

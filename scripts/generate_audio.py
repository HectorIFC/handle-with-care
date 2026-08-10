#!/usr/bin/env python3
"""Generate PLACEHOLDER 8-bit/chiptune audio for Handle With Care.

These are deterministic, synthesized stand-ins — square waves, noise and
simple arpeggios — for the ~24 sounds PRD section 8 requires. They exist so
the audio wiring (main/audio/audio.script, core/audio_cues.lua) can actually
play something: the volume sliders become testable and the game stops being
silent. A musician replaces these with real chiptune later; the filenames
match core/audio_cues.lua so that swap is drop-in.

Run: python3 scripts/generate_audio.py   (needs ffmpeg for wav->ogg)
"""
import wave, struct, math, os, subprocess, random, tempfile

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "main", "audio")
os.makedirs(OUT, exist_ok=True)

def square(t, freq, duty=0.5):
    return 1.0 if (t * freq) % 1.0 < duty else -1.0

def triangle(t, freq):
    p = (t * freq) % 1.0
    return 4 * abs(p - 0.5) - 1

def noise(rng):
    return rng.uniform(-1, 1)

def env(i, n, attack=0.01, release=0.3):
    # fast attack, exponential-ish decay
    a = int(SR * attack)
    if i < a:
        return i / max(a, 1)
    d = (i - a) / max(n - a, 1)
    return max(0.0, (1 - d)) ** (1 + release * 6)

def render(samples, name, gain=0.5):
    path_wav = os.path.join(tempfile.gettempdir(), name + ".wav")
    path_ogg = os.path.join(OUT, name + ".ogg")
    peak = max(1e-6, max(abs(s) for s in samples))
    with wave.open(path_wav, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(
            struct.pack("<h", int(max(-1, min(1, s / peak * gain)) * 32767))
            for s in samples))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path_wav,
                    "-c:a", "libvorbis", "-q:a", "2", path_ogg], check=True)
    os.remove(path_wav)

def tone(freq, dur, wave_fn=square, duty=0.5, release=0.3, vib=0.0):
    n = int(SR * dur); out = []
    for i in range(n):
        t = i / SR
        f = freq * (1 + vib * math.sin(2 * math.pi * 6 * t))
        s = wave_fn(t, f, duty) if wave_fn is square else wave_fn(t, f)
        out.append(s * env(i, n, release=release))
    return out

def arp(freqs, dur_each, wave_fn=square, release=0.2):
    out = []
    for f in freqs:
        out += tone(f, dur_each, wave_fn, release=release)
    return out

def noise_burst(dur, rng, freq_sweep=None):
    n = int(SR * dur); out = []
    for i in range(n):
        out.append(noise(rng) * env(i, n, release=0.5))
    return out

rng = random.Random(1234)  # deterministic

# --- notes (a small chip scale) ---
def note(semitones):
    return 220.0 * (2 ** (semitones / 12))

CUES = {}  # name -> samples

# Player
CUES["step"]        = tone(note(0), 0.05, duty=0.25, release=0.6)
CUES["jump"]        = arp([note(7), note(12), note(19)], 0.04, release=0.4)
CUES["land"]        = tone(note(-5), 0.10, triangle, release=0.5)
CUES["player_death"] = arp([note(12), note(7), note(3), note(-2), note(-7)], 0.07)
# Package
CUES["package_shake"]   = tone(note(2), 0.08, duty=0.5, release=0.5, vib=0.3)
CUES["package_panic"]   = arp([note(14), note(10), note(15), note(11)], 0.05, release=0.3)
CUES["package_explode"] = noise_burst(0.6, rng)
CUES["package_heavy"]   = tone(note(-9), 0.25, triangle, release=0.2)
CUES["package_light"]   = arp([note(12), note(16), note(19), note(24)], 0.05, release=0.4)
CUES["package_sleep"]   = arp([note(4), note(0), note(-3)], 0.14, triangle, release=0.15)
CUES["package_wake"]    = arp([note(-3), note(4), note(11)], 0.06)
CUES["package_magnet"]  = tone(note(9), 0.30, duty=0.5, release=0.2, vib=0.6)
# Environment
CUES["hazard"]        = tone(note(1), 0.12, duty=0.15, release=0.4)
CUES["platform_fall"] = tone(note(-2), 0.30, triangle, release=0.1, vib=0.2)
CUES["delivery"]      = arp([note(12), note(16), note(19), note(24)], 0.10, release=0.5)
# UI
CUES["ui_move"]    = tone(note(12), 0.04, duty=0.5, release=0.6)
CUES["ui_confirm"] = arp([note(12), note(19)], 0.05, release=0.4)
CUES["ui_back"]    = arp([note(19), note(12)], 0.05, release=0.4)

# Music: short loopable chiptune stubs (a bass + arp pattern)
def music(root_semis, pattern, beat=0.16, bars=4, wave_fn=square):
    out = []
    for _ in range(bars):
        for step in pattern:
            f = note(root_semis + step)
            out += tone(f, beat, wave_fn, duty=0.5, release=0.5)
    return out

CUES["music_menu"]     = music(0,  [0, 4, 7, 4, 5, 7, 4, 0])
CUES["music_gameplay"] = music(2,  [0, 7, 3, 7, 5, 7, 3, 7])
CUES["music_win"]      = arp([note(0), note(4), note(7), note(12), note(16), note(19), note(24)], 0.09, release=0.5)
CUES["music_gameover"] = arp([note(0), note(-2), note(-5), note(-9)], 0.18, triangle, release=0.2)

for name, samples in CUES.items():
    render(samples, name)
    print("  ", name + ".ogg")

print("generated", len(CUES), "placeholder audio files ->", os.path.relpath(OUT))

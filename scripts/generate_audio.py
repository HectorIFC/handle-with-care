#!/usr/bin/env python3
"""Generate the game's chiptune audio for Handle With Care (PRD section 8).

Deterministic: fixed seeds, no wall-clock input, so regenerating produces the
same files and a diff means someone changed the music. Everything here is
synthesized from scratch — there are no sampled assets in this project.

WHAT THIS IS. A small tracker modelled on the NES APU, because that
arrangement is what makes something sound like chiptune rather than like a
beep:

    pulse1    melody      square, variable duty, vibrato
    pulse2    harmony     square, arpeggiated chord tones, slight detune
    triangle  bass        triangle, roots and fifths
    noise     drums       short-decay noise: kick, snare, hat

The previous version of this file was a single square-wave channel playing an
eight-step arpeggio for four bars. It existed to prove the wiring worked. It
was not music.

WHAT CANNOT BE CHECKED HERE. Whether it sounds good. This script asserts what
is checkable — no clipping, loop-point continuity, whole numbers of bars, and
that every cue the game names has a file — and the rest is a listening test
in the playtest checklist. Do not add a comment claiming a track sounds a
particular way; nothing here has ever been heard.

Run: python3 scripts/generate_audio.py   (needs numpy and ffmpeg)
"""
import math
import os
import random
import re
import struct
import subprocess
import tempfile
import wave

try:
    import numpy as np
except ImportError:
    raise SystemExit(
        "generate_audio needs numpy (dev-time only, like Pillow for sprites):\n"
        "  python3 -m pip install numpy")

SR = 44100
HERE = os.path.dirname(__file__)
OUT = os.path.join(HERE, "..", "main", "audio")
CUES_LUA = os.path.join(HERE, "..", "main", "core", "audio_cues.lua")
os.makedirs(OUT, exist_ok=True)


# --- waveforms ---------------------------------------------------------
# Phase is accumulated rather than computed from t * freq, so a note whose
# frequency moves (vibrato, a sweep) stays continuous instead of jumping
# whenever the frequency changes.

def _phase(freq, n):
    return np.cumsum(np.full(n, 2 * math.pi) * freq / SR)


def pulse(freq, n, duty=0.5):
    """DC-free square wave.

    A pulse at duty d has an inherent mean of 2d-1 — at the 12.5%/25% duties
    that give chiptune its nasal lead tone, that is a large constant offset.
    Real hardware has it; on a modern output it is inaudible but eats
    headroom and thumps whenever a note starts or stops. Subtracting the
    mean costs nothing and makes the offset check downstream meaningful.
    """
    ph = (_phase(freq, n) / (2 * math.pi)) % 1.0
    return np.where(ph < duty, 1.0, -1.0) - (2 * duty - 1)


def tri(freq, n):
    ph = (_phase(freq, n) / (2 * math.pi)) % 1.0
    return 4 * np.abs(ph - 0.5) - 1


def noise_arr(n, rng):
    return np.array([rng.uniform(-1, 1) for _ in range(n)])


def adsr(n, attack=0.005, decay=0.05, sustain=0.6, release=0.08):
    """Volume envelope, always reaching zero within its own n samples.

    That last property is not cosmetic: it is what guarantees no note is
    still ringing at the loop point, which is where a looping track shows a
    click. Stages are squeezed proportionally rather than overflowing if a
    note is shorter than attack+decay+release.
    """
    a, d, r = int(SR * attack), int(SR * decay), int(SR * release)
    if a + d + r > n:
        scale = n / max(1, a + d + r)
        a, d, r = int(a * scale), int(d * scale), int(r * scale)
    s = max(0, n - a - d - r)
    return np.concatenate([
        np.linspace(0, 1, a, endpoint=False) if a else np.empty(0),
        np.linspace(1, sustain, d, endpoint=False) if d else np.empty(0),
        np.full(s, sustain),
        np.linspace(sustain, 0, r) if r else np.empty(0),
    ])[:n]


class Instrument:
    def __init__(self, wave="pulse", duty=0.5, gain=0.5, vibrato=0.0,
                 vib_rate=6.0, attack=0.005, decay=0.05, sustain=0.6,
                 release=0.08, detune=0.0):
        self.wave, self.duty, self.gain = wave, duty, gain
        self.vibrato, self.vib_rate = vibrato, vib_rate
        self.attack, self.decay = attack, decay
        self.sustain, self.release = sustain, release
        self.detune = detune

    def render(self, freq, n, rng):
        freq = freq * (1 + self.detune)
        if self.vibrato:
            t = np.arange(n) / SR
            freq = freq * (1 + self.vibrato * np.sin(2 * math.pi * self.vib_rate * t))
        else:
            freq = np.full(n, freq)
        if self.wave == "pulse":
            raw = pulse(freq, n, self.duty)
        elif self.wave == "tri":
            raw = tri(freq, n)
        else:
            raw = noise_arr(n, rng)
        env = adsr(n, self.attack, self.decay, self.sustain, self.release)
        return raw * env * self.gain


def hz(semitone):
    """A2 = 110 Hz as the zero point, equal temperament."""
    return 110.0 * (2 ** (semitone / 12))


# --- music theory ------------------------------------------------------
MAJOR = [0, 2, 4, 5, 7, 9, 11]
MINOR = [0, 2, 3, 5, 7, 8, 10]


def scale_note(mode, degree):
    """Degree may run past the octave; it wraps and transposes."""
    octave, index = divmod(degree, 7)
    return mode[index] + 12 * octave


def triad(mode, degree):
    """The chord built on a scale degree: root, third, fifth."""
    return [scale_note(mode, degree + step) for step in (0, 2, 4)]


# --- tracker -----------------------------------------------------------
class Song:
    def __init__(self, bpm, bars, beats_per_bar=4):
        self.bpm = bpm
        self.bars = bars
        self.beats_per_bar = beats_per_bar
        self.spb = 60.0 / bpm                      # seconds per beat
        self.total = int(round(SR * self.spb * beats_per_bar * bars))
        self.buf = np.zeros(self.total)

    def at(self, beat):
        return int(round(beat * self.spb * SR))

    def play(self, beat, length_beats, semitone, instrument, rng):
        start = self.at(beat)
        n = int(round(length_beats * self.spb * SR))
        # Clamped, never wrapped: a note that would run past the end is cut
        # at the end instead. Wrapping would put sound across the loop
        # point, which is exactly what the loop check later forbids.
        n = min(n, self.total - start)
        if n <= 0:
            return
        self.buf[start:start + n] += instrument.render(hz(semitone), n, rng)


# Drum voices, all from the noise channel plus one pitched thump.
def kick(song, beat, rng):
    start = song.at(beat)
    n = min(int(SR * 0.11), song.total - start)
    if n <= 0:
        return
    sweep = np.linspace(110, 45, n)
    song.buf[start:start + n] += tri(sweep, n) * adsr(n, 0.001, 0.05, 0.2, 0.05) * 0.85


def snare(song, beat, rng):
    start = song.at(beat)
    n = min(int(SR * 0.10), song.total - start)
    if n <= 0:
        return
    song.buf[start:start + n] += noise_arr(n, rng) * adsr(n, 0.001, 0.04, 0.25, 0.05) * 0.5


def hat(song, beat, rng, gain=0.18):
    start = song.at(beat)
    n = min(int(SR * 0.03), song.total - start)
    if n <= 0:
        return
    song.buf[start:start + n] += noise_arr(n, rng) * adsr(n, 0.001, 0.01, 0.1, 0.015) * gain


LEAD = Instrument("pulse", duty=0.25, gain=0.30, vibrato=0.006, attack=0.004,
                  decay=0.06, sustain=0.55, release=0.06)
HARM = Instrument("pulse", duty=0.5, gain=0.16, detune=0.0015, attack=0.002,
                  decay=0.03, sustain=0.45, release=0.05)
BASS = Instrument("tri", gain=0.42, attack=0.002, decay=0.02, sustain=0.9,
                  release=0.04)


def build_track(seed, bpm, root, mode, progression, bars=16, drums="full",
                lead_octave=2, density=0.75, arp_rate=0.5, retrograde_b=False,
                shift_b=0, chord_bars=1):
    """Assemble one looping track.

    `progression` is a list of scale degrees. The bass takes roots, pulse2
    arpeggiates the chord, and the lead picks from chord tones on strong
    beats and neighbouring scale tones elsewhere — that constraint is what
    keeps a generated melody consonant without anyone listening to it.
    """
    rng = random.Random(seed)
    song = Song(bpm, bars)
    beats = song.beats_per_bar

    # The lead line for the first half, so section B can quote it.
    motif = []
    for bar in range(bars):
        chord_index = (bar // chord_bars) % len(progression)
        degree = progression[chord_index]
        chord = triad(mode, degree)
        in_b = bar >= bars // 2
        transpose = shift_b if in_b else 0

        # Bass: root on the downbeat, fifth mid-bar.
        base = root + transpose
        song.play(bar * beats, 1.0, base + chord[0] - 12, BASS, rng)
        song.play(bar * beats + 2, 1.0, base + chord[2] - 12, BASS, rng)

        # Harmony: a steady arpeggio through the chord.
        step = arp_rate
        pos = 0.0
        i = 0
        while pos < beats:
            tone = chord[i % 3] + (12 if (i % 6) >= 3 else 0)
            song.play(bar * beats + pos, step, base + tone, HARM, rng)
            pos += step
            i += 1

        # Lead.
        if in_b and retrograde_b and motif:
            # Section B answers with the A melody backwards (level 9's
            # mirror, and a normal chiptune device besides).
            bar_motif = motif[(bars // 2 - 1) - (bar - bars // 2)]
            for offset, length, tone in bar_motif:
                song.play(bar * beats + offset, length, base + tone + 12 * lead_octave,
                          LEAD, rng)
            continue

        bar_notes = []
        pos = 0.0
        while pos < beats:
            length = rng.choice([0.5, 0.5, 1.0])
            if rng.random() < density:
                strong = abs(pos - round(pos)) < 1e-9 and int(pos) % 2 == 0
                if strong:
                    tone = rng.choice(chord)
                else:
                    tone = scale_note(mode, degree + rng.choice([1, 3, 5, 2, 4]))
                bar_notes.append((pos, length, tone))
                song.play(bar * beats + pos, length,
                          base + tone + 12 * lead_octave, LEAD, rng)
            pos += length
        motif.append(bar_notes)

        # Drums.
        if drums != "none":
            kick(song, bar * beats, rng)
            kick(song, bar * beats + 2.5, rng)
            snare(song, bar * beats + 1, rng)
            snare(song, bar * beats + 3, rng)
            if drums == "full":
                for eighth in range(beats * 2):
                    hat(song, bar * beats + eighth * 0.5, rng)
    return song.buf


# --- output ------------------------------------------------------------
def to_array(samples):
    return samples if isinstance(samples, np.ndarray) else np.array(samples, dtype=float)


RENDERED = {}


def render(samples, name, gain=0.85):
    data = to_array(samples)
    peak = max(1e-6, float(np.max(np.abs(data))))
    data = data / peak * gain
    RENDERED[name] = data

    path_wav = os.path.join(tempfile.gettempdir(), name + ".wav")
    path_ogg = os.path.join(OUT, name + ".ogg")
    with wave.open(path_wav, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(np.clip(data, -1, 1).__mul__(32767).astype("<i2").tobytes())
    # -fflags +bitexact is what makes the output REPRODUCIBLE, and it has to
    # sit AFTER -i so it applies to the OUTPUT muxer — placed on the input
    # side it silently does nothing here. Without it
    # ffmpeg stamps every Ogg stream with a randomly generated serial number
    # (bytes 14-17 of each page header), so regenerating identical audio
    # produced 32 byte-different files and every asset diff was noise.
    # Verified: two encodes of the same input are byte-identical with it and
    # differ without it.
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path_wav,
                    "-c:a", "libvorbis", "-q:a", "1",
                    "-fflags", "+bitexact", path_ogg], check=True)
    os.remove(path_wav)


# --- SFX ---------------------------------------------------------------
# Unchanged in character from the first pass: these are short, they already
# do their job, and rewriting them would risk regressing cues that trigger
# sites already name.
sfx_rng = random.Random(1234)


def env_legacy(i, n, attack=0.01, release=0.3):
    a = int(SR * attack)
    if i < a:
        return i / max(a, 1)
    d = (i - a) / max(n - a, 1)
    return max(0.0, (1 - d)) ** (1 + release * 6)


def tone(freq, dur, wave_fn="pulse", duty=0.5, release=0.3, vib=0.0):
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        f = freq * (1 + vib * math.sin(2 * math.pi * 6 * t))
        if wave_fn == "pulse":
            # Same DC removal as pulse() above, for the same reason.
            s = (1.0 if (t * f) % 1.0 < duty else -1.0) - (2 * duty - 1)
        else:
            p = (t * f) % 1.0
            s = 4 * abs(p - 0.5) - 1
        out.append(s * env_legacy(i, n, release=release))
    return out


def arp(freqs, dur_each, wave_fn="pulse", release=0.2):
    out = []
    for f in freqs:
        out += tone(f, dur_each, wave_fn, release=release)
    return out


def burst(dur):
    n = int(SR * dur)
    return [sfx_rng.uniform(-1, 1) * env_legacy(i, n, release=0.5) for i in range(n)]


CUES = {}
CUES["step"] = tone(hz(0), 0.05, duty=0.25, release=0.6)
CUES["jump"] = arp([hz(7), hz(12), hz(19)], 0.04, release=0.4)
CUES["land"] = tone(hz(-5), 0.10, "tri", release=0.5)
CUES["player_death"] = arp([hz(12), hz(7), hz(3), hz(-2), hz(-7)], 0.07)
CUES["package_shake"] = tone(hz(2), 0.08, duty=0.5, release=0.5, vib=0.3)
CUES["package_panic"] = arp([hz(14), hz(10), hz(15), hz(11)], 0.05, release=0.3)
CUES["package_explode"] = burst(0.6)
CUES["package_heavy"] = tone(hz(-9), 0.25, "tri", release=0.2)
CUES["package_light"] = arp([hz(12), hz(16), hz(19), hz(24)], 0.05, release=0.4)
CUES["package_sleep"] = arp([hz(4), hz(0), hz(-3)], 0.14, "tri", release=0.15)
CUES["package_wake"] = arp([hz(-3), hz(4), hz(11)], 0.06)
CUES["package_magnet"] = tone(hz(9), 0.30, duty=0.5, release=0.2, vib=0.6)
CUES["hazard"] = tone(hz(1), 0.12, duty=0.15, release=0.4)
CUES["platform_fall"] = tone(hz(-2), 0.30, "tri", release=0.1, vib=0.2)
CUES["delivery"] = arp([hz(12), hz(16), hz(19), hz(24)], 0.10, release=0.5)
CUES["ui_move"] = tone(hz(12), 0.04, duty=0.5, release=0.6)
CUES["ui_confirm"] = arp([hz(12), hz(19)], 0.05, release=0.4)
CUES["ui_back"] = arp([hz(19), hz(12)], 0.05, release=0.4)

# --- Music -------------------------------------------------------------
# One theme per level, each derived from that level's mechanic rather than
# being the same track transposed. See the roadmap in CLAUDE.md for what
# each level does.
i_VI_III_VII = [0, 5, 2, 6]
i_iv_v_i = [0, 3, 4, 0]
I_V_vi_IV = [0, 4, 5, 3]

LEVEL_THEMES = {
    1:  dict(bpm=104, root=0,  mode=MAJOR, progression=I_V_vi_IV, drums="light",
             density=0.55, seed=101),                       # tutorial: open, sparse
    2:  dict(bpm=138, root=2,  mode=MINOR, progression=i_VI_III_VII, drums="full",
             density=0.85, arp_rate=0.25, seed=102),        # jump scare: busy
    3:  dict(bpm=88,  root=-5, mode=MINOR, progression=i_iv_v_i, drums="full",
             density=0.6, lead_octave=1, seed=103),         # heavy: low, half-time
    4:  dict(bpm=152, root=4,  mode=MINOR, progression=i_VI_III_VII, drums="full",
             density=0.9, arp_rate=0.25, seed=104),         # hot potato: a running clock
    5:  dict(bpm=126, root=1,  mode=MINOR, progression=[0, 6, 1, 5], drums="full",
             density=0.8, seed=105),                        # magnet: unstable
    6:  dict(bpm=118, root=0,  mode=MINOR, progression=i_VI_III_VII, drums="full",
             density=0.7, shift_b=3, seed=106),             # moods: B shifts key
    7:  dict(bpm=130, root=3,  mode=MINOR, progression=i_iv_v_i, drums="full",
             density=0.8, retrograde_b=True, seed=107),     # control freak: B inverts
    8:  dict(bpm=76,  root=-2, mode=MAJOR, progression=I_V_vi_IV, drums="none",
             density=0.45, arp_rate=1.0, seed=108),         # sleepy: bare
    9:  dict(bpm=122, root=5,  mode=MINOR, progression=i_VI_III_VII, drums="full",
             density=0.75, retrograde_b=True, seed=109),    # mirror: B is A backwards
    10: dict(bpm=144, root=0,  mode=MINOR, progression=[0, 5, 3, 4], drums="full",
             density=0.9, arp_rate=0.25, seed=110),         # final: everything
}

for level, spec in LEVEL_THEMES.items():
    CUES["music_level_%d" % level] = build_track(bars=16, **spec)

CUES["music_menu"] = build_track(seed=1, bpm=96, root=0, mode=MAJOR,
                                 progression=I_V_vi_IV, bars=16, drums="light",
                                 density=0.5, arp_rate=1.0)
# Kept as the fallback any level without its own theme falls back to.
CUES["music_gameplay"] = build_track(seed=2, bpm=124, root=2, mode=MINOR,
                                     progression=i_VI_III_VII, bars=16,
                                     drums="full", density=0.75)
CUES["music_win"] = arp([hz(0), hz(4), hz(7), hz(12), hz(16), hz(19), hz(24)],
                        0.09, release=0.5)
CUES["music_gameover"] = arp([hz(0), hz(-2), hz(-5), hz(-9)], 0.18, "tri",
                             release=0.2)


# --- verification ------------------------------------------------------
def cue_names_from_lua():
    """The cue catalogue is the contract; parse it rather than duplicating
    the list here, so the two cannot drift."""
    text = open(CUES_LUA).read()
    body = text.split("M.CUES = {", 1)[1].split("\n}", 1)[0]
    return set(re.findall(r"^\s*([a-z_0-9]+)\s*=\s*\{", body, re.M))


def verify():
    declared = cue_names_from_lua()
    generated = set(CUES)
    missing = sorted(declared - generated)
    if missing:
        raise SystemExit("audio: cues declared in audio_cues.lua with no file: "
                         + ", ".join(missing))
    extra = sorted(generated - declared)
    if extra:
        raise SystemExit("audio: generated cues absent from audio_cues.lua "
                         "(the game can never play them): " + ", ".join(extra))

    problems = []
    for name, data in RENDERED.items():
        peak = float(np.max(np.abs(data)))
        if peak > 1.0:
            problems.append("%s clips (peak %.3f)" % (name, peak))
        dc = float(np.mean(data))
        if abs(dc) > 0.02:
            problems.append("%s has DC offset %.4f" % (name, dc))
        if name.startswith("music_") and name not in ("music_win", "music_gameover"):
            # Looping tracks only: the seam is where a click would be heard,
            # so the last sample must sit close to the first.
            seam = abs(float(data[-1]) - float(data[0]))
            if seam > 0.05:
                problems.append("%s loop seam jumps %.3f" % (name, seam))
            if float(np.sqrt(np.mean(data ** 2))) < 0.02:
                problems.append("%s is near-silent" % name)
    if problems:
        raise SystemExit("audio verification failed:\n  " + "\n  ".join(problems))
    print("verified: %d cues, no clipping, no DC offset, loop seams clean"
          % len(RENDERED))


for name, samples in CUES.items():
    render(samples, name)
    seconds = len(to_array(samples)) / SR
    print("  %-20s %5.1fs" % (name + ".ogg", seconds))

verify()
print("generated", len(CUES), "audio files ->", os.path.relpath(OUT))

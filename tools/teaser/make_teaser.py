#!/usr/bin/env python3
"""Edits the teaser from the shots filmed by tools/teaser.gd (see tools/teaser/make_teaser.sh).

    python3 tools/teaser/make_teaser.py <shots dir> <out.mp4>

<shots dir> holds one folder of frames per shot (f00000000.png...). The music is synthesised
here (numpy), timed on the cuts; the titles use the game's font (Jersey, assets/fonts, converted
to TTF next to this script's work folder).
"""
import os
import subprocess
import sys
import wave

import numpy as np

FPS = 30
W, H = 1920, 1080
BARS = 118  # letterbox height
SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

# (kind, shot or card, seconds, start frame in the shot, text, transition out)
# Transition out: "black" fades to black, "white" flashes white, "cut".
TIMELINE = [
    ("card", "emblem", 3.0, 0, "", "black"),
    ("shot", "descent", 8.0, 0, "Chaque monde naît d'une graine", "black"),
    ("shot", "village", 4.5, 10, "Des peuples y vivent, bâtissent, inventent", "cut"),
    ("shot", "nightfall", 7.0, 0, "Et quand la nuit tombe...", "cut"),
    ("shot", "shore", 5.0, 20, "", "black"),
    ("card", "god", 3.0, 0, "Et toi ? Tu es leur dieu.", "cut"),
    ("shot", "storm", 6.5, 15, "", "white"),
    ("shot", "meteor", 4.5, 8, "", "white"),
    ("shot", "dragons", 4.0, 0, "", "cut"),
    ("shot", "war", 5.0, 20, "Les royaumes complotent et se font la guerre", "black"),
    ("shot", "dawn", 5.5, 0, "...et l'histoire s'écrit toute seule", "cut"),
    ("shot", "interface", 5.0, 20, "Animundi · en développement", "black"),
    ("card", "end", 6.0, 0, "", "black"),
]


# Colour grading per shot: many burning houses at night blow the picture out to yellow.
GRADE = {
    "dragons": "eq=gamma=0.78:contrast=1.12:saturation=0.9,colorbalance=rh=-0.06:bh=0.05",
    "storm": "eq=gamma=0.9:contrast=1.08",
}


def run(cmd):
    subprocess.run(cmd, check=True)


def esc(text):
    return text.replace("\\", "\\\\").replace("'", "’").replace(":", "\\:").replace("%", "\\%")


def text_filter(text, dur, font, size, y, start=0.4, fade=0.5):
    if not text:
        return []
    end = dur - 0.35
    alpha = f"if(lt(t,{start}),0,if(lt(t,{start + fade}),(t-{start})/{fade},if(lt(t,{end - fade}),1,max(0,({end}-t)/{fade}))))"
    return [f"drawtext=fontfile={font}:text='{esc(text)}':fontsize={size}:fontcolor=0xF2E8D8:"
            f"borderw=5:bordercolor=0x1A0E14:shadowx=0:shadowy=6:shadowcolor=0x000000@0.6:"
            f"x=(w-text_w)/2:y={y}:alpha='{alpha}'"]


def transitions(dur, out, fade_in):
    f = []
    if fade_in:
        f.append("fade=in:st=0:d=0.45")
    if out == "black":
        f.append(f"fade=out:st={dur - 0.5}:d=0.5")
    elif out == "white":
        f.append(f"fade=out:st={dur - 0.18}:d=0.18:color=white")
    return f


def segment(i, item, shots, work, fonts, prev_out):
    kind, name, dur, start, text, out = item
    path = os.path.join(work, f"seg{i:02d}.mp4")
    frames = int(round(dur * FPS))
    fade_in = prev_out in ("black", None)
    title = os.path.join(fonts, "Jersey15-Regular.ttf")
    big = os.path.join(fonts, "Jersey10-Regular.ttf")
    if kind == "shot":
        src = os.path.join(shots, name, "f%08d.png")
        # The first frames of a shot are the game opening, before the scene is set.
        filters = [
            f"scale={W}:{H}:flags=lanczos",
            GRADE.get(name, "eq=contrast=1.06:saturation=1.08"),
            f"drawbox=x=0:y=0:w=iw:h={BARS}:color=black:t=fill",
            f"drawbox=x=0:y=ih-{BARS}:w=iw:h={BARS}:color=black:t=fill",
        ]
        filters += text_filter(text, dur, title, 64, f"h-{BARS}-text_h-40")
        if prev_out == "white":
            filters.append("fade=in:st=0:d=0.25:color=white")
        filters += transitions(dur, out, fade_in)
        run(["ffmpeg", "-loglevel", "error", "-y", "-framerate", str(FPS), "-start_number", str(3 + start),
             "-i", src, "-frames:v", str(frames), "-vf", ",".join(filters),
             "-c:v", "libx264", "-preset", "medium", "-crf", "16", "-pix_fmt", "yuv420p", path])
        return path
    # Cards: the game's emblem in big pixels on the dark wine of the interface.
    emblem = os.path.join(ROOT, "assets", "ui", "emblem.png")
    bg = f"color=c=0x140A10:s={W}x{H}:r={FPS}:d={dur}"
    if name == "emblem":
        fc = (f"[1:v]scale=256:256:flags=neighbor,format=rgba,fade=in:st=0.5:d=1.2:alpha=1[e];"
              f"[0:v][e]overlay=(W-w)/2:(H-h)/2-20,"
              + ",".join(text_filter("anima mundi", dur, title, 54, "h/2+150", start=1.2, fade=0.8)))
    elif name == "end":
        fc = (f"[1:v]scale=224:224:flags=neighbor,format=rgba,fade=in:st=0.1:d=0.4:alpha=1[e];"
              f"[0:v][e]overlay=(W-w)/2:H/2-340,"
              + ",".join(text_filter("ANIMUNDI", dur, big, 230, "h/2-60", start=0.15, fade=0.3)
                         + text_filter("l'âme du monde", dur, title, 58, "h/2+150", start=0.9, fade=0.6)
                         + text_filter("Un god game en pixel art où chaque peuple a sa propre IA", dur, title, 40, "h/2+230", start=1.6, fade=0.6)))
    else:
        fc = "[0:v]" + ",".join(text_filter(text, dur, big, 120, "(h-text_h)/2", start=0.25, fade=0.35))
    fc += "," + ",".join(transitions(dur, out, fade_in) or ["null"]) + "[v]"
    run(["ffmpeg", "-loglevel", "error", "-y", "-f", "lavfi", "-i", bg, "-loop", "1", "-i", emblem,
         "-filter_complex", fc, "-map", "[v]", "-frames:v", str(frames),
         "-c:v", "libx264", "-preset", "medium", "-crf", "16", "-pix_fmt", "yuv420p", path])
    return path


# ---------------------------------------------------------------- music

def env(n, a, r):
    """Attack then exponential release, n samples."""
    t = np.arange(n) / SR
    e = np.minimum(1.0, t / max(a, 1e-4)) * np.exp(-t / max(r, 1e-4))
    return e


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    # One-pole filter, run on blocks with numpy's cumulative trick is unstable; plain loop on a
    # decimated signal is fast enough for pads.
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def saw(f, t):
    return 2.0 * ((f * t) % 1.0) - 1.0


def square(f, t, duty=0.5):
    return np.where((f * t) % 1.0 < duty, 1.0, -1.0)


def note(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def add(buf, at, sig, gain=1.0):
    i = int(at * SR)
    if i >= len(buf):
        return
    j = min(len(buf), i + len(sig))
    buf[i:j] += sig[: j - i] * gain


def pad(chord, dur, gain=0.12, bright=900.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = np.zeros(n)
    for m in chord:
        for det in (-0.12, 0.0, 0.11):
            s += saw(note(m) * 2 ** (det / 12), t + np.random.rand())
    s = lowpass_fast(s, bright)
    fade = np.minimum(1.0, t / 1.2) * np.minimum(1.0, (dur - t) / 1.0)
    return s * fade * gain / len(chord)


def lowpass_fast(x, cutoff):
    # Moving average approximations of a low pass, chained: cheap and smooth enough.
    k = max(1, int(SR / cutoff / 2))
    ker = np.ones(k) / k
    for _ in range(3):
        x = np.convolve(x, ker, mode="same")
    return x


def pluck(m, dur=0.35, gain=0.08, duty=0.25):
    n = int(dur * SR)
    t = np.arange(n) / SR
    return square(note(m), t, duty) * env(n, 0.003, dur / 4) * gain


def kick(gain=0.9):
    n = int(0.6 * SR)
    t = np.arange(n) / SR
    f = 45 + 110 * np.exp(-t * 30)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * env(n, 0.002, 0.22) * gain


def taiko(gain=0.7, pitch=70):
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    f = pitch + 60 * np.exp(-t * 20)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * env(n, 0.002, 0.25)
    skin = lowpass_fast(np.random.randn(n), 1800) * env(n, 0.001, 0.04) * 1.5
    return (body + skin) * gain


def boom(gain=1.0, length=3.5):
    n = int(length * SR)
    t = np.arange(n) / SR
    f = 32 + 70 * np.exp(-t * 6)
    ph = 2 * np.pi * np.cumsum(f) / SR
    sub = np.sin(ph) * env(n, 0.003, length / 3.5)
    noise = lowpass_fast(np.random.randn(n), 600) * env(n, 0.002, 0.5) * 2.5
    return (sub + noise) * gain


def riser(dur, gain=0.35):
    n = int(dur * SR)
    t = np.arange(n) / SR
    noise = np.random.randn(n)
    # Brighter as it rises: mix of a dark and a raw noise.
    dark = lowpass_fast(noise, 400)
    k = (t / dur) ** 2
    s = (dark * (1 - k) + noise * 0.35 * k) * (t / dur) ** 1.6
    tone = np.sin(2 * np.pi * np.cumsum(200 + 900 * (t / dur) ** 2) / SR) * 0.15 * (t / dur) ** 2
    return (s + tone) * gain


def reverb(x, mix=0.3):
    out = x.copy()
    for d, g in ((0.0297, 0.7), (0.0371, 0.68), (0.0411, 0.66), (0.0437, 0.64), (0.113, 0.5), (0.171, 0.4)):
        k = int(d * SR)
        y = np.zeros_like(x)
        y[k:] = x[:-k]
        for _ in range(5):
            y2 = np.zeros_like(y)
            y2[k:] = y[:-k] * g
            y = y + y2
        out += lowpass_fast(y, 3500) * mix / 6
    return out


def music(cuts, total):
    """cuts: start time of each timeline item."""
    np.random.seed(7)
    buf = np.zeros(int((total + 1) * SR))
    t_god = cuts[5]          # "Tu es leur dieu"
    t_action = cuts[6]       # the storm
    t_calm = cuts[10]        # dawn
    t_end = cuts[12]         # end card
    # Am  F  C  G, then Dm F Am E for the action.
    calm = [[57, 60, 64], [53, 57, 60], [48, 55, 60], [55, 59, 62]]
    action = [[50, 53, 57], [53, 57, 60], [57, 60, 64], [52, 56, 59]]
    # Part 1: pads and a pixel arpeggio, slowly building.
    bar = 2.4
    t = 0.0
    k = 0
    while t < t_god - 0.5:
        ch = calm[k % 4]
        add(buf, t, pad([m - 12 for m in ch] + ch, bar + 1.2, gain=0.34, bright=500 + 120 * k))
        add(buf, t, pluck(ch[0] - 24, bar, gain=0.13, duty=0.5))
        if t > cuts[1] + 2.0:
            step = bar / 8
            for s in range(8):
                m = ch[[0, 1, 2, 1, 0, 2, 1, 2][s]] + 12 * (1 + (s // 4 if k % 2 else 0))
                add(buf, t + s * step, pluck(m, 0.3, gain=0.07 + 0.03 * min(k, 6) / 6))
        if t > cuts[3]:
            add(buf, t, kick(0.35))
            add(buf, t + bar / 2, kick(0.25))
        t += bar
        k += 1
    # Rise into the card, silence, then the hit.
    add(buf, t_god - 2.6, riser(2.4, 0.45))
    add(buf, t_god + 0.2, boom(1.1, 3.0))
    add(buf, t_god + 0.2, pad([45, 52, 57, 60, 64], 2.6, gain=0.22, bright=1200))
    # Part 2: drums, bass ostinato, stabs.
    beat = 60 / 104
    t = t_action
    n = 0
    while t < t_calm - 0.3:
        b = n % 16
        ch = action[(n // 8) % 4]
        if b % 4 == 0:
            add(buf, t, kick(0.8))
        if b in (2, 6, 10, 11, 14):
            add(buf, t, taiko(0.45, 90))
        if b in (7, 15):
            add(buf, t, taiko(0.35, 140))
        for half in (0, 0.5):
            add(buf, t + half * beat, pluck(ch[0] - 24 + (12 if half else 0), beat / 2, gain=0.09, duty=0.5))
        add(buf, t + 0.5 * beat, pluck(ch[(n % 3)] + 12, beat / 2, gain=0.035, duty=0.125))
        if b % 8 == 0:
            add(buf, t, pad([m - 12 for m in ch] + ch, beat * 8 + 0.6, gain=0.26, bright=1400))
        t += beat
        n += 1
    # Hits on the impacts of the action shots.
    add(buf, cuts[7] + (42 - 8) / FPS, boom(1.0, 2.5))   # meteor lands (frame 42 of the shot)
    add(buf, cuts[8], boom(0.5, 1.5))
    add(buf, t_calm - 1.6, riser(1.5, 0.3))
    # Part 3: calm again, warm and open.
    t = t_calm
    k = 0
    while t < t_end - 0.2:
        ch = calm[k % 4]
        add(buf, t, pad([m - 12 for m in ch] + ch + [ch[1] + 12], bar + 1.2, gain=0.32, bright=1000))
        for s in range(8):
            add(buf, t + s * bar / 8, pluck(ch[[0, 2, 1, 2, 0, 2, 1, 2][s]] + 24, 0.4, gain=0.065))
        t += bar
        k += 1
    # The end: one big hit, the chord left to ring.
    add(buf, t_end + 0.1, boom(1.2, 4.5))
    add(buf, t_end + 0.1, taiko(0.8, 60))
    add(buf, t_end + 0.1, pad([45, 52, 57, 64, 69], 5.5, gain=0.22, bright=1500))
    add(buf, t_end + 0.1, pluck(81, 1.5, gain=0.05))
    buf = reverb(buf, 0.45)
    buf = buf[: int(total * SR)]
    # Fade out and normalise.
    fade = int(1.5 * SR)
    buf[-fade:] *= np.linspace(1, 0, fade)
    buf = buf / (np.max(np.abs(buf)) + 1e-9)
    buf = np.tanh(buf * 2.2)
    buf /= np.max(np.abs(buf)) + 1e-9
    return (buf * 0.89 * 32767).astype(np.int16)


def write_wav(path, data):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def main():
    shots, out = sys.argv[1], sys.argv[2]
    work = os.path.join(os.path.dirname(os.path.abspath(out)), "teaser_work")
    os.makedirs(work, exist_ok=True)
    fonts = os.environ.get("TEASER_FONTS", os.path.join(work, "fonts"))
    cuts = []
    total = 0.0
    for item in TIMELINE:
        cuts.append(total)
        total += item[2]
    segs = []
    prev = None
    for i, item in enumerate(TIMELINE):
        print("segment", i, item[1], flush=True)
        segs.append(segment(i, item, shots, work, fonts, prev))
        prev = item[5]
    lst = os.path.join(work, "list.txt")
    with open(lst, "w") as f:
        for s in segs:
            f.write(f"file '{s}'\n")
    silent = os.path.join(work, "video.mp4")
    run(["ffmpeg", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst,
         "-vf", "noise=alls=5:allf=t,vignette=PI/6", "-c:v", "libx264", "-preset", "slow", "-crf", "18",
         "-pix_fmt", "yuv420p", silent])
    print("music", flush=True)
    wav = os.path.join(work, "music.wav")
    write_wav(wav, music(cuts, total))
    run(["ffmpeg", "-loglevel", "error", "-y", "-i", silent, "-i", wav, "-c:v", "copy", "-af", "loudnorm=I=-14:TP=-1.5:LRA=11", "-ar", "48000", "-c:a", "aac",
         "-b:a", "192k", "-shortest", "-movflags", "+faststart", out])
    print("teaser:", out, f"{total:.1f} s")


if __name__ == "__main__":
    main()

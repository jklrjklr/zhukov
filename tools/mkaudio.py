#!/usr/bin/env python3
"""Builds every audio/<slot>.ogg: layered ffmpeg synthesis + trimmed Kenney (CC0) samples.

Usage: KEN=/path/to/unzipped/kenney/packs OUT=audio python3 tools/mkaudio.py [name-prefix ...]
KEN holds the folders impact-sounds, sci-fi-sounds, interface-sounds, rpg-audio, digital-audio
(each with an Audio/ folder), as downloaded from kenney.nl. Requires ffmpeg with libvorbis.
Synth layers: (expr, filter, gain[, delay_s]) -> aevalsrc layer -> filter -> gain -> mix -> compress -> peak-normalise.
"""
import os, subprocess, sys, tempfile, math, re, zlib

KEN = os.environ.get("KEN", "/tmp/k")
OUT = os.environ.get("OUT", "audio")
TMP = tempfile.mkdtemp()
ONLY = sys.argv[1:]
SR = 44100
PI = "PI"
N = "(random(1)*2-1)"
N2 = "(random(2)*2-1)"
N3 = "(random(3)*2-1)"


def kp(pack, name):
    return f"{KEN}/{pack}/Audio/{name}.ogg"


def run(args):
    r = subprocess.run(["ffmpeg", "-loglevel", "error", "-y"] + args, capture_output=True, text=True)
    if r.returncode:
        print(r.stderr[:1500])
        raise SystemExit("ffmpeg failed")


def peak_gain(wav, target):
    r = subprocess.run(["ffmpeg", "-hide_banner", "-i", wav, "-af", "volumedetect", "-f", "null", "-"],
                       capture_output=True, text=True)
    m = re.search(r"max_volume: (-?[\d.]+) dB", r.stderr)
    return target - float(m.group(1)) if m else 0.0


def render(name, layers, dur, post="", peak=-3.0, ch=1, q=4, sr=SR, loop=0.0, fade=0.012):
    """layers: list of dict(expr|file, f, g, d(delay s), ch, sr, ss, t)."""
    if ONLY and not any(name.startswith(o) for o in ONLY):
        return
    ins, parts = [], []
    tot = dur + loop
    seed = zlib.crc32(name.encode()) % 997
    for i, L in enumerate(layers):
        if "expr" in L:
            lch = L.get("ch", 1)
            ex = re.sub(r"random\((\d)\)", lambda m: f"mod(abs(sin(floor(t*44100)*12.9898+{int(m.group(1)) * 78.233 + seed * 17.77:.3f})*43758.5453),1)", L["expr"])
            ins += ["-f", "lavfi", "-i", f"aevalsrc='{ex}':s={L.get('sr', SR)}:d={L.get('len', tot)}"]
        else:
            if "ss" in L:
                ins += ["-ss", str(L["ss"])]
            ins += ["-t", str(L.get("t", dur)), "-i", L["file"]]
            lch = 1
        chain = ["aresample=44100"]
        if L.get("f"):
            chain.append(L["f"])
        if "file" in L:
            chain.append("pan=mono|c0=0.5*c0+0.5*c1" if False else "aformat=channel_layouts=mono" if ch == 1 else "aformat=channel_layouts=stereo")
        elif ch == 2 and lch == 1:
            chain.append(L.get("pan", "pan=stereo|c0=c0|c1=c0"))
        chain.append(f"volume={L.get('g', 1.0)}")
        if L.get("d"):
            dd = int(L["d"] * 1000)
            chain.append(f"adelay={dd}|{dd}" if ch == 2 else f"adelay={dd}")
        parts.append(f"[{i}:a]" + ",".join(chain) + f"[l{i}]")
    mix = "".join(f"[l{i}]" for i in range(len(layers)))
    g = ";".join(parts) + f";{mix}amix=inputs={len(layers)}:normalize=0:duration=longest[m]"
    tail = f"[m]atrim=0:{tot},asetpts=PTS-STARTPTS"
    if post:
        tail += "," + post
    tail += ",alimiter=limit=0.97"
    g += ";" + tail + "[o]"
    w1 = f"{TMP}/{name}.wav"
    run(ins + ["-filter_complex", g, "-map", "[o]", "-ar", "44100", "-ac", str(ch), w1])
    gain = peak_gain(w1, peak)
    f = f"volume={gain}dB"
    if loop:
        # seamless loop: source body (loop..tot) with its last `loop` seconds crossfaded into the head (0..loop)
        st = dur - loop
        f += (f",asplit[a][b];[a]atrim={loop}:{tot},asetpts=PTS-STARTPTS,afade=t=out:st={st}:d={loop}:curve=qsin[bd];"
              f"[b]atrim=0:{loop},asetpts=PTS-STARTPTS,afade=t=in:st=0:d={loop}:curve=qsin,adelay={int(st * 1000)}|{int(st * 1000)}[hd];"
              f"[bd][hd]amix=inputs=2:normalize=0:duration=longest")
    else:
        f += f",afade=t=out:st={max(0, dur - fade * 2)}:d={fade * 2}"
    os.makedirs(OUT, exist_ok=True)
    out = f"{OUT}/{name}.ogg"
    if loop:
        run(["-i", w1, "-filter_complex", f.replace(",asplit", ";[0:a]asplit", 1) if False else "[0:a]" + f, "-ac", str(ch), "-ar", "44100", "-c:a", "libvorbis", "-q:a", str(q), out])
    else:
        run(["-i", w1, "-af", f, "-ac", str(ch), "-ar", "44100", "-c:a", "libvorbis", "-q:a", str(q), out])
    print("made", name, os.path.getsize(out))


def kfile(name, pack, src, t=1.5, f="", g=1.0, peak=-3.0, ss=0, post=""):
    render(name, [dict(file=kp(pack, src), f=f, g=g, ss=ss, t=t)], t, post=post, peak=peak)


def sweep(f0, f1, dur, k=0):
    """sin() phase expr for a linear frequency sweep f0->f1 over dur."""
    return f"2*{PI}*({f0}*t+({f1}-{f0})/(2*{dur})*t*t)"


def decay_phase(f_start, f_end, tau):
    """phase of exponentially decaying frequency f_end+(f_start-f_end)*exp(-t/tau)."""
    return f"2*{PI}*({f_end}*t+({f_start}-{f_end})*{tau}*(1-exp(-t/{tau})))"


def saw(freq_expr_phase_base, n=6):
    return "(" + "+".join(f"sin({k}*({freq_expr_phase_base}))/{k}" for k in range(1, n + 1)) + ")*0.6"


COMP = "acompressor=threshold=0.15:ratio=4:attack=2:release=60:makeup=2"

# ---------------------------------------------------------------- firearms
def gun(name, i, base, crack_hz, dur, thud_hz, tail, g_tail=0.35, peak=-1.5, rate=18):
    render(name, [
        dict(expr=f"{N}*exp(-t*{150 + i * 12})", f=f"highpass=f={crack_hz}", g=1.0),
        dict(expr=f"{N2}*exp(-t*{rate + i * 2})", f=f"bandpass=f={1800 + i * 200}:w=2800", g=0.6),
        dict(expr=f"sin({decay_phase(thud_hz * 3.2, thud_hz, 0.025)})*exp(-t*{rate - 4})", g=1.1),
        dict(expr=f"{N3}*exp(-t*{tail})", f="lowpass=f=1400,aecho=0.7:0.5:42|91:0.35|0.2", g=g_tail, d=0.012),
    ], dur, post=COMP + ",highpass=f=45", peak=peak)

for i in range(3):
    sfx = "" if i == 0 else f"_{i}"
    gun("rifle_shot" + sfx, i, 0, 1600 + i * 300, 0.55, 75 + i * 7, 8 + i)
    gun("smg_shot" + sfx, i, 0, 2000 + i * 250, 0.32, 105 + i * 9, 18 + i * 2, g_tail=0.25, peak=-3, rate=30)
for i in range(3):
    gun(f"sentry_shot_{i}" if i else "sentry_shot", i, 0, 2600 + i * 250, 0.3, 130 + i * 10, 22, g_tail=0.2, peak=-4, rate=34)
for i in range(3):
    sfx = "" if i == 0 else f"_{i}"
    gun("shotgun_shot" + sfx, i, 0, 900 + i * 100, 0.75, 60 + i * 5, 6, g_tail=0.6, peak=-1, rate=11)

render("rocket_launch", [
    dict(expr=f"{N}*exp(-t*70)", f="highpass=f=900", g=0.8),
    dict(expr=f"sin({decay_phase(260, 55, 0.12)})*exp(-t*6)", g=1.0),
    dict(expr=f"{N2}*(0.2+0.9*exp(-t*3.2))*min(1,t*40)", f="lowpass=f=2400,highpass=f=120,aecho=0.7:0.6:60|130:0.4|0.25", g=0.9),
], 1.4, post=COMP, peak=-1.5)

# ---------------------------------------------------------------- player
render("throw", [dict(expr=f"{N}*sin({PI}*t/0.32)^2", f="bandpass=f=1100:w=900", g=1.0)], 0.32, peak=-8)
render("dive", [dict(expr=f"{N}*sin({PI}*t/0.42)^1.5", f="lowpass=f=1800,highpass=f=150", g=0.8),
                dict(expr=f"sin({decay_phase(130, 55, 0.05)})*exp(-t*14)", g=0.8, d=0.18)], 0.5, peak=-7)
for i in range(4):
    sfx = "" if i == 0 else f"_{i}"
    kfile("footstep" + sfx, "rpg-audio", f"footstep0{i}", t=0.35, f=f"highpass=f=90,lowpass=f=5000,atempo={0.95 + i * 0.03}", peak=-11)
    kfile("footstep_run" + sfx, "rpg-audio", f"footstep0{i + 4}", t=0.3, f="highpass=f=100,lowpass=f=6000,atempo=1.12", peak=-9)
kfile("stim", "sci-fi-sounds", "forceField_001", t=1.0, peak=-8)
for i in range(3):
    sfx = "" if i == 0 else f"_{i}"
    kfile("player_hit" + sfx, "impact-sounds", f"impactPunch_medium_00{i}", t=0.5, f="lowpass=f=4500", peak=-3)
render("player_death", [
    dict(expr=f"{saw(sweep(260, 70, 1.4))}*exp(-t*1.4)*(1+0.2*sin(2*{PI}*9*t))", f="lowpass=f=1500", g=0.8),
    dict(expr=f"sin({decay_phase(90, 40, 0.1)})*exp(-t*6)", g=1.0, d=0.25),
    dict(expr=f"{N}*exp(-t*20)", f="lowpass=f=900", g=0.7, d=0.25),
], 1.6, post=COMP, peak=-3)
kfile("dry_fire", "interface-sounds", "click_003", t=0.3, f="highpass=f=300", peak=-6)
kfile("mag_out", "impact-sounds", "impactMetal_light_001", t=0.4, peak=-8)
kfile("mag_in", "impact-sounds", "impactPlate_light_002", t=0.4, peak=-8)
kfile("bolt", "impact-sounds", "impactMetal_medium_002", t=0.5, peak=-8)
for i in range(3):
    sfx = "" if i == 0 else f"_{i}"
    kfile("grenade_bounce" + sfx, "impact-sounds", f"impactMetal_light_00{i + 2}", t=0.35, f="lowpass=f=5000,atempo=0.9", peak=-8)
kfile("pickup_ammo", "impact-sounds", "impactMetal_light_000", t=0.4, f="atempo=1.1", peak=-7)
render("pickup_sample", [dict(expr=f"(sin(2*{PI}*1320*t)+0.4*sin(2*{PI}*1980*t))*exp(-t*9)", g=0.7),
                         dict(expr=f"(sin(2*{PI}*1760*t)+0.4*sin(2*{PI}*2640*t))*exp(-t*9)", g=0.7, d=0.09),
                         dict(expr=f"(sin(2*{PI}*2093*t))*exp(-t*7)", g=0.6, d=0.18)], 0.7, peak=-8)

# ---------------------------------------------------------------- bugs
def chitter(name, rate, base, dur, bursts, g=1.0, peak=-9):
    am = f"pow(max(0,sin(2*{PI}*{rate}*t)),2)*max(0,sin(2*{PI}*{bursts}*t+1))"
    render(name, [
        dict(expr=f"{N}*{am}", f=f"bandpass=f={base}:w={base}", g=1.0),
        dict(expr=f"sin(2*{PI}*({base * 0.8}*t+30*sin(2*{PI}*{rate * 0.5}*t)/{rate}))*{am}", g=0.4),
    ], dur, post="tremolo=f=45:d=0.4," + COMP, peak=peak)

for i, (rate, base, bursts) in enumerate([(26, 4200, 3.1), (31, 5000, 4.3), (22, 3600, 2.7), (35, 4600, 3.7)]):
    chitter("bug_chitter" + ("" if i == 0 else f"_{i}"), rate, base, 0.55 + 0.05 * i, bursts)


def screech(name, f0, f1, dur, vib=40, gl=0.4, peak=-2, hz_lp=7000):
    ph = sweep(f0, f1, dur)
    env = f"min(1,t*30)*pow(max(0,1-t/{dur}),0.6)"
    render(name, [
        dict(expr=f"{saw(ph + f'+4*sin(2*{PI}*{vib}*t)', 5)}*{env}", f=f"lowpass=f={hz_lp},highpass=f=500", g=1.0),
        dict(expr=f"{N}*{env}*(1+{gl}*sin(2*{PI}*{vib * 0.5}*t))", f="bandpass=f=3500:w=2500", g=0.35),
    ], dur, post="tremolo=f=28:d=0.35," + COMP + ",aecho=0.6:0.5:35:0.2", peak=peak)

for i, (a, b, d) in enumerate([(1500, 2900, 0.9), (1900, 3300, 0.75), (1300, 2500, 1.0)]):
    screech("bug_alert" + ("" if i == 0 else f"_{i}"), a, b, d, vib=30 + i * 7)
for i, (a, b, d) in enumerate([(2400, 1100, 0.25), (2900, 1500, 0.22), (2100, 900, 0.3)]):
    screech("bug_hurt" + ("" if i == 0 else f"_{i}"), a, b, d, vib=55, peak=-5)
for i, (a, b, d) in enumerate([(2200, 350, 0.9), (1800, 280, 1.0), (2600, 420, 0.8)]):
    ph = sweep(a, b, d)
    env = f"min(1,t*40)*exp(-t*3.2)"
    render("bug_death" + ("" if i == 0 else f"_{i}"), [
        dict(expr=f"{saw(ph + '+3*sin(2*PI*22*t)', 4)}*{env}", f="lowpass=f=5000", g=0.9),
        dict(expr=f"{N}*{env}*(0.6+0.4*sin(2*{PI}*17*t))", f="bandpass=f=2200:w=1800", g=0.4),
        dict(expr=f"{N2}*exp(-t*28)", f="lowpass=f=1200", g=0.9, d=d * 0.55),
        dict(expr=f"sin({decay_phase(120, 50, 0.04)})*exp(-t*20)", g=0.8, d=d * 0.55),
    ], d + 0.4, post="tremolo=f=24:d=0.3," + COMP, peak=-3)
for i, (f, d) in enumerate([(2800, 0.28), (2300, 0.32), (3200, 0.25)]):
    am = f"pow(max(0,sin(2*{PI}*38*t)),2)"
    render("bug_attack" + ("" if i == 0 else f"_{i}"), [
        dict(expr=f"{N}*exp(-t*9)*{am}", f=f"bandpass=f={f}:w=3000", g=1.0),
        dict(expr=f"{N2}*sin({PI}*t/{d})^2", f="bandpass=f=1700:w=1600", g=0.6, d=0.03),
        dict(expr=f"sin({sweep(f * 0.7, f * 0.45, d)})*exp(-t*10)", g=0.4),
    ], d + 0.1, post=COMP, peak=-4)
render("bug_big_step", [
    dict(expr=f"sin({decay_phase(95, 38, 0.06)})*exp(-t*9)", g=1.0),
    dict(expr=f"{N}*exp(-t*28)", f="lowpass=f=700", g=0.8),
    dict(expr=f"{N2}*exp(-t*60)", f="bandpass=f=1800:w=1500", g=0.25),
], 0.5, post=COMP, peak=-5)
render("bug_big_step_1", [
    dict(expr=f"sin({decay_phase(85, 34, 0.07)})*exp(-t*8)", g=1.0),
    dict(expr=f"{N}*exp(-t*24)", f="lowpass=f=600", g=0.9),
], 0.5, post=COMP, peak=-5)
roar_ph = f"2*{PI}*70*t+6*sin(2*{PI}*9*t)"
render("charger_roar", [
    dict(expr=f"{saw(roar_ph + f'+2*PI*40*t', 10)}*min(1,t*8)*max(0,1-pow(t/1.5,3))*(0.7+0.3*sin(2*{PI}*26*t))", f="lowpass=f=1800", g=1.0),
    dict(expr=f"{N}*min(1,t*10)*max(0,1-t/1.5)", f="bandpass=f=900:w=1200", g=0.5),
    dict(expr=f"sin({sweep(90, 180, 1.5)})*min(1,t*6)*max(0,1-t/1.5)", g=0.5),
], 1.6, post=COMP + ",aecho=0.6:0.5:70:0.25", peak=-2)
render("charger_charge", [
    dict(expr=f"sin({decay_phase(90, 40, 0.05)})*exp(-mod(t,0.22)*14)", g=1.0),
    dict(expr=f"{N}*exp(-mod(t,0.22)*20)*min(1,t*3)", f="lowpass=f=900", g=0.6),
    dict(expr=f"{N2}*min(1,t/1.0)", f="lowpass=f=300", g=0.5),
], 1.1, post=COMP, peak=-3)
for i in range(2):
    kfile("bile_spit" + ("" if i == 0 else f"_{i}"), "sci-fi-sounds", f"slime_00{i}", t=0.8, f="atempo=1.15", peak=-5)
render("bile_splash", [
    dict(file=kp("sci-fi-sounds", "slime_001"), f="atempo=0.85", t=1.0),
    dict(expr=f"{N}*exp(-t*14)", f="bandpass=f=1400:w=1800", g=0.7),
    dict(expr=f"sin({decay_phase(180, 70, 0.04)})*exp(-t*12)", g=0.6),
], 0.9, post=COMP, peak=-4)
render("burrow", [
    dict(expr=f"{N}*sin({PI}*t/1.2)^1.5*(0.6+0.4*sin(2*{PI}*13*t))", f="bandpass=f=420:w=500", g=1.0),
    dict(expr=f"gt(random(4),0.992)*{N2}*sin({PI}*t/1.2)", f="lowpass=f=3000", g=1.2),
    dict(expr=f"sin({decay_phase(80, 35, 0.3)})*exp(-t*2.5)", g=0.6, d=0.1),
], 1.3, post=COMP, peak=-4)
render("breach", [
    dict(expr=f"{N}*min(1,t*2.5)*exp(-t*0.9)", f="lowpass=f=260", g=1.4),
    dict(expr=f"sin(2*{PI}*(32+6*sin(2*{PI}*0.7*t))*t)*min(1,t*3)*exp(-t*0.8)", g=1.0),
    dict(expr=f"gt(random(4),0.985)*{N2}*min(1,t*1.5)*exp(-t*0.9)", f="lowpass=f=2500", g=1.0),
    dict(expr=f"{N3}*sin({PI}*t/2.4)^2", f="bandpass=f=700:w=900", g=0.3),
], 2.6, post=COMP, peak=-2)
render("nest_hole_destroyed", [
    dict(expr=f"sin({decay_phase(120, 32, 0.25)})*exp(-t*2.2)", g=1.1),
    dict(expr=f"{N}*exp(-t*3.5)", f="lowpass=f=1800", g=0.9),
    dict(expr=f"gt(random(4),0.99)*{N2}*exp(-t*2.5)", f="lowpass=f=4000", g=1.0),
    dict(expr=f"{saw(sweep(2400, 400, 1.1), 4)}*exp(-t*2.2)", f="lowpass=f=4000", g=0.5, d=0.1),
], 1.9, post=COMP, peak=-1.5)

# ---------------------------------------------------------------- hits
for i in range(3):
    kfile("hit_flesh" + ("" if i == 0 else f"_{i}"), "impact-sounds", f"impactSoft_medium_00{i}", t=0.4, f="lowpass=f=4500", peak=-5)
kfile("hit_armor", "impact-sounds", "impactPlate_heavy_000", t=0.6, peak=-4)
kfile("hit_armor_1", "impact-sounds", "impactPlate_medium_001", t=0.6, f="highpass=f=200,atempo=1.05", peak=-4)
for i in range(3):
    render("hit_ground" + ("" if i == 0 else f"_{i}"), [
        dict(expr=f"{N}*exp(-t*{26 + i * 5})", f="lowpass=f=1100", g=1.0),
        dict(expr=f"sin({decay_phase(130 + i * 12, 60, 0.03)})*exp(-t*16)", g=0.8)], 0.3, post=COMP, peak=-7)
for i in range(3):
    kfile("hit_metal" + ("" if i == 0 else f"_{i}"), "impact-sounds", f"impactMetal_light_00{i}", t=0.5, peak=-5)

# ---------------------------------------------------------------- explosions
def boom(name, dur, f0, tau, rumble_lp, crackle, debris, peak=-1, g_boom=1.2):
    render(name, [
        dict(expr=f"sin({decay_phase(f0, 28, tau)})*exp(-t*{2.2 * 1.0 / dur * 3:.2f})*min(1,t*200)", g=g_boom),
        dict(expr=f"{N}*exp(-t*{4.0 / dur * 2:.2f})*min(1,t*400)", f=f"lowpass=f={rumble_lp}", g=1.2),
        dict(expr=f"{N2}*exp(-t*50)", f="highpass=f=800", g=0.7),
        dict(expr=f"gt(random(4),{1 - crackle})*{N3}*exp(-t*{3.0 / dur * 2:.2f})", f="lowpass=f=6000,highpass=f=300", g=1.4, d=0.03),
        dict(expr=f"gt(random(5),{1 - debris})*{N}*exp(-(t-0.35)*2.2)*gt(t,0.35)*{0.8}", f="bandpass=f=1800:w=2500,aecho=0.5:0.5:90:0.3", g=1.0),
    ], dur, post=COMP + ",acompressor=threshold=0.3:ratio=3,aecho=0.5:0.4:110|220:0.3|0.15", peak=peak)

boom("explosion", 1.7, 120, 0.15, 1400, 0.012, 0.004)
boom("explosion_1", 1.8, 135, 0.14, 1700, 0.016, 0.005)
boom("explosion_2", 1.6, 105, 0.18, 1200, 0.010, 0.004)
boom("explosion_big", 3.4, 90, 0.3, 1000, 0.01, 0.006, g_boom=1.4)
boom("explosion_big_1", 3.2, 80, 0.35, 900, 0.012, 0.007, g_boom=1.4)
for i in range(3):
    render("debris" + ("" if i == 0 else f"_{i}"), [
        dict(expr=f"gt(random(4),{0.992 - i * 0.002})*{N}*exp(-t*3.2)", f="bandpass=f=1900:w=3000", g=1.0),
        dict(expr=f"{N2}*exp(-t*4)", f="lowpass=f=700", g=0.5),
        dict(expr=f"gt(random(5),0.998)*{N3}*exp(-t*2.5)", f="bandpass=f=900:w=300", g=1.4)], 1.0, post=COMP, peak=-6)

# ---------------------------------------------------------------- stratagems
kfile("strat_open", "interface-sounds", "maximize_006", t=0.5, peak=-8)
kfile("strat_input", "interface-sounds", "tick_001", t=0.2, peak=-8)
kfile("strat_error", "interface-sounds", "error_004", t=0.6, peak=-8)
kfile("strat_ready", "interface-sounds", "confirmation_002", t=1.0, peak=-6)
render("beacon", [
    dict(expr=f"(sin(2*{PI}*880*t)+0.5*sin(2*{PI}*1320*t))*exp(-mod(t,0.5)*7)*lt(t,1.5)", g=0.7),
    dict(expr=f"sin({decay_phase(180, 60, 0.04)})*exp(-t*14)", g=0.8),
    dict(expr=f"{N}*exp(-t*30)", f="bandpass=f=2000:w=2000", g=0.4)], 1.6, post=COMP + ",aecho=0.5:0.5:120:0.3", peak=-4)
render("hellpod_streak", [
    dict(expr=f"{N}*min(1,t*3)*(0.5+0.5*t/1.6)", f="bandpass=f=1600:w=2600", g=1.0),
    dict(expr=f"sin({sweep(3000, 700, 1.7)})*min(1,t*4)", g=0.25),
    dict(expr=f"{N2}*min(1,t*2)", f="lowpass=f=500", g=0.9)], 1.7, post=COMP, peak=-3)
render("hellpod_impact", [
    dict(expr=f"sin({decay_phase(110, 30, 0.12)})*exp(-t*3)", g=1.2),
    dict(expr=f"{N}*exp(-t*9)", f="lowpass=f=1800", g=1.0),
    dict(expr=f"{N2}*exp(-t*60)", f="highpass=f=1500", g=0.6),
    dict(expr=f"gt(random(4),0.99)*{N3}*exp(-t*3)", f="bandpass=f=2500:w=3000", g=1.0, d=0.04),
    dict(expr=f"sin(2*{PI}*140*t)*exp(-t*9)*gt(t,0.01)", f="highpass=f=100", g=0.35, d=0.02)], 1.8, post=COMP + ",aecho=0.5:0.4:90:0.3", peak=-1.5)
render("eagle_flyby", [
    dict(expr=f"{N}*sin({PI}*t/2.6)^2.5", f="bandpass=f=900:w=1400", g=0.9),
    dict(expr=f"{saw(sweep(260, 140, 2.6), 6)}*sin({PI}*t/2.6)^2", f="lowpass=f=1200", g=0.7),
    dict(expr=f"{N2}*sin({PI}*t/2.6)^3", f="lowpass=f=300", g=1.0)], 2.7, post=COMP, peak=-3)
render("eagle_bomb", [
    dict(expr=f"sin({sweep(2600, 700, 1.2)})*min(1,t*20)*exp(-t*0.5)", g=0.35, ch=1),
    dict(expr=f"{N}*exp(-t*0.5)*min(1,t*4)", f="highpass=f=1800,lowpass=f=6000", g=0.25)], 1.2, post=COMP, peak=-8)
render("orbital_whistle", [
    dict(expr=f"sin({sweep(3200, 900, 2.0)}+0.4*sin(2*{PI}*7*t))*min(1,t*3)*(0.4+0.6*t/2.0)", g=0.8),
    dict(expr=f"sin({sweep(6400, 1800, 2.0)})*min(1,t*3)*(0.3+0.7*t/2.0)", g=0.15),
    dict(expr=f"{N}*(0.2+0.8*t/2.0)", f="bandpass=f=3000:w=1500", g=0.35)], 2.0, post=COMP, peak=-4)
kfile("orbital_shot", "sci-fi-sounds", "laserLarge_004", t=1.5, peak=-2)
render("sentry_deploy", [
    dict(file=kp("impact-sounds", "impactMetal_heavy_001"), f="atempo=0.9", t=0.6, g=1.0),
    dict(expr=f"sin({sweep(300, 900, 0.6)})*sin({PI}*t/0.6)*(0.7+0.3*sin(2*{PI}*35*t))", f="lowpass=f=2400", g=0.35, d=0.15),
    dict(file=kp("rpg-audio", "metalLatch"), t=0.4, g=0.8, d=0.55)], 1.1, post=COMP, peak=-4)
render("resupply_open", [
    dict(file=kp("sci-fi-sounds", "doorOpen_001"), t=1.0, g=0.9),
    dict(file=kp("impact-sounds", "impactMetal_medium_000"), t=0.5, g=0.7, d=0.05)], 1.0, post=COMP, peak=-6)
kfile("pod_open", "sci-fi-sounds", "doorOpen_001", t=1.2, peak=-6)

# ---------------------------------------------------------------- mission
render("passage_seal", [
    dict(file=kp("impact-sounds", "impactMetal_heavy_003"), t=0.8, f="atempo=0.85", g=1.0, d=1.0),
    dict(expr=f"{N}*sin({PI}*t/1.2)", f="bandpass=f=500:w=600", g=0.6),
    dict(expr=f"sin({decay_phase(70, 30, 0.2)})*exp(-(t-1)*4)*gt(t,1)", g=1.0),
    dict(expr=f"gt(random(4),0.99)*{N2}*exp(-(t-1)*3)*gt(t,1)", f="lowpass=f=3000", g=1.0)], 2.2, post=COMP, peak=-2)
render("objective_progress", [dict(expr=f"(sin(2*{PI}*880*t))*exp(-t*14)", g=0.8),
                              dict(expr=f"(sin(2*{PI}*1175*t))*exp(-t*12)", g=0.8, d=0.07)], 0.35, peak=-9)
render("objective_complete", [
    dict(expr=f"(sin(2*{PI}*{f}*t)+0.3*sin(4*{PI}*{f}*t))*exp(-t*3.5)", g=0.5, d=d)
    for f, d in [(523, 0), (659, 0.1), (784, 0.2), (1047, 0.3)]], 1.4, post="aecho=0.6:0.5:80:0.25," + COMP, peak=-5)
render("objective_failed", [
    dict(expr=f"{saw(sweep(300, 150, 1.0), 6)}*exp(-t*2)", f="lowpass=f=1200", g=1.0),
    dict(expr=f"{saw(sweep(224, 112, 1.0), 6)}*exp(-t*2)", f="lowpass=f=1200", g=0.7)], 1.1, post=COMP, peak=-5)
for i in range(3):
    f = [1500, 1900, 1200][i]
    render("terminal_beep" + ("" if i == 0 else f"_{i}"), [
        dict(expr=f"sin(2*{PI}*{f}*t)*(lt(mod(t,0.14),0.07))*lt(t,0.28)", g=0.8),
        dict(expr=f"sin(2*{PI}*{f * 2}*t)*(lt(mod(t,0.14),0.07))*lt(t,0.28)", g=0.15)], 0.3, post="highpass=f=300", peak=-8)
render("upload_loop", [
    dict(expr=f"sin(2*{PI}*(900+300*floor(mod(t,1.6)/0.1)/16*1)*t)*lt(mod(t,0.1),0.05)*0.7", g=1.0),
    dict(expr=f"{N}*lt(mod(t,0.4),0.01)", f="bandpass=f=4000:w=2000", g=0.3)], 3.2, post="lowpass=f=5000", peak=-12, fade=0.0003)
render("radio_chirp", [
    dict(expr=f"{N}*exp(-t*20)", f="bandpass=f=2200:w=2200", g=0.5),
    dict(expr=f"sin(2*{PI}*1400*t)*lt(t,0.07)*0.6", g=1.0, d=0.02),
    dict(expr=f"sin(2*{PI}*1900*t)*lt(t,0.08)*0.6", g=1.0, d=0.1),
    dict(expr=f"{N2}*lt(t,0.1)", f="bandpass=f=2500:w=1500", g=0.12, d=0.2)], 0.32, post="bandpass=f=1800:w=2600," + COMP, peak=-8)
render("timer_warning", [dict(expr=f"(sin(2*{PI}*1000*t)+0.4*sin(2*{PI}*2000*t))*exp(-mod(t,0.25)*10)*lt(t,0.5)", g=0.8)],
       0.55, peak=-6)
render("departure_alarm", [
    dict(expr=f"{saw('2*PI*(560+280*lt(mod(t,1.0),0.5))*t', 3)}*lt(t,2.0)", f="lowpass=f=3000", g=0.8)], 2.0, post=COMP, peak=-7)
render("pelican_approach", [
    dict(expr=f"{N}*pow(t/4.0,1.5)", f="lowpass=f=1100", g=1.0),
    dict(expr=f"{saw('2*PI*(60+30*t/4.0)*t', 6)}*pow(t/4.0,1.5)*(0.7+0.3*sin(2*PI*22*t))", f="lowpass=f=900", g=0.8)], 4.0, post=COMP, peak=-5)
render("pelican_land", [
    dict(expr=f"{N}*(0.6+0.4*exp(-t*0.8))*max(0,1-t/3.0)", f="lowpass=f=900", g=1.0),
    dict(expr=f"sin({decay_phase(90, 38, 0.1)})*exp(-(t-2.2)*10)*gt(t,2.2)", g=0.9),
    dict(expr=f"{N2}*exp(-(t-2.2)*30)*gt(t,2.2)", f="lowpass=f=1500", g=0.7)], 3.0, post=COMP, peak=-4)
render("pelican_takeoff", [
    dict(expr=f"{N}*min(1,t*1.5)*max(0,1-pow(t/4.0,2))", f="lowpass=f=1300", g=1.0),
    dict(expr=f"{saw('2*PI*(75+40*t/4.0)*t', 6)}*min(1,t*1.5)*max(0,1-pow(t/4.0,2))*(0.7+0.3*sin(2*PI*24*t))", f="lowpass=f=1000", g=0.8)], 4.0, post=COMP, peak=-5)
kfile("pelican", "sci-fi-sounds", "spaceEngineLarge_001", t=6.0, peak=-9) if False else None
kfile("mission_complete_k", "digital-audio", "powerUp8", t=1.5, peak=-30) if False else None
render("mission_complete", [
    dict(expr=f"({saw(f'2*PI*{f}*t', 5)})*min(1,t*30)*exp(-t*0.9)", f="lowpass=f=3500", g=0.35, d=d)
    for f, d in [(262, 0), (330, 0.16), (392, 0.32), (523, 0.48), (659, 0.7), (784, 0.7), (1047, 0.7)]]
    + [dict(expr=f"sin(2*{PI}*131*t)*exp(-t*0.8)", g=0.6), dict(expr=f"{N}*exp(-t*6)", f="highpass=f=5000", g=0.25, d=0.7)],
    3.4, post="aecho=0.6:0.5:90|180:0.3|0.2," + COMP, peak=-3, ch=1)
render("mission_failed", [
    dict(expr=f"({saw(f'2*PI*{f}*t', 5)})*min(1,t*20)*exp(-t*0.7)", f="lowpass=f=1400", g=0.4, d=d)
    for f, d in [(220, 0), (196, 0.5), (175, 1.0), (147, 1.5), (110, 1.5)]]
    + [dict(expr=f"sin({decay_phase(90, 35, 0.3)})*exp(-(t-1.5)*0.8)*gt(t,1.5)", g=1.0)],
    4.0, post="aecho=0.6:0.5:120:0.3," + COMP, peak=-3)
render("reinforce", [
    dict(expr=f"{N}*sin({PI}*t/0.6)^2", f="bandpass=f=1800:w=2800", g=0.5),
    dict(expr=f"sin({sweep(300, 1200, 0.5)})*sin({PI}*t/0.6)", g=0.5),
    dict(expr=f"(sin(2*{PI}*1568*t)+0.4*sin(2*{PI}*2352*t))*exp(-t*8)", g=0.6, d=0.5)], 1.1, post=COMP, peak=-5)

# ---------------------------------------------------------------- ui
kfile("ui_click", "interface-sounds", "select_002", t=0.3, peak=-8)
kfile("ui_back", "interface-sounds", "back_002", t=0.3, peak=-9)
kfile("objective", "interface-sounds", "confirmation_004", t=1.0, peak=-6)

# ---------------------------------------------------------------- legacy / faction slots
for i in range(4):
    kfile("bot_blaster" + ("" if i == 0 else f"_{i}"), "sci-fi-sounds", f"laserSmall_00{i}", t=0.6, peak=-5)
for i in range(3):
    kfile("bot_heavy_blaster" + ("" if i == 0 else f"_{i}"), "sci-fi-sounds", f"laserLarge_00{i}", t=0.9, peak=-4)
kfile("bot_death", "impact-sounds", "impactMetal_heavy_000", t=0.8, peak=-4)
kfile("bot_death_1", "impact-sounds", "impactMetal_heavy_002", t=0.8, peak=-4)
kfile("bot_drop", "sci-fi-sounds", "spaceEngineLow_002", t=3.0, peak=-5)
kfile("chainsaw", "sci-fi-sounds", "engineCircular_002", t=3.0, peak=-8)
kfile("flamer", "sci-fi-sounds", "thrusterFire_001", t=3.0, peak=-8)
kfile("pelican", "sci-fi-sounds", "spaceEngineLarge_001", t=4.0, peak=-9)
kfile("plasma_shot", "sci-fi-sounds", "laserRetro_001", t=0.7, f="atempo=0.9", peak=-5)
kfile("claw", "rpg-audio", "knifeSlice", t=0.4, peak=-7)
render("voteless_death", [dict(expr=f"{saw(sweep(480, 140, 0.8), 4)}*exp(-t*3.5)*(1+0.3*sin(2*PI*14*t))", f="lowpass=f=2500", g=0.9),
                          dict(expr=f"{N}*exp(-t*18)", f="lowpass=f=1500", g=0.6, d=0.5)], 0.9, post=COMP, peak=-4)
kfile("illuminate_death", "digital-audio", "zapThreeToneDown", t=0.9, peak=-4)
kfile("shield_hit", "sci-fi-sounds", "forceField_002", t=0.6, peak=-6)
render("shield_break", [dict(file=kp("sci-fi-sounds", "forceField_004"), t=1.0, g=0.8),
                        dict(file=kp("impact-sounds", "impactGlass_heavy_001"), t=0.8, g=1.0, d=0.1)], 1.0, post=COMP, peak=-3)
kfile("watcher_call", "digital-audio", "zapThreeToneUp", t=1.2, peak=-5)
render("beam_charge", [dict(expr=f"sin({sweep(180, 1800, 1.3)})*(0.2+0.8*t/1.3)", g=0.7),
                       dict(expr=f"{N}*(t/1.3)", f="highpass=f=2500", g=0.3)], 1.4, post=COMP, peak=-6)
render("harvester_beam", [dict(expr=f"{saw('2*PI*(120+8*sin(2*PI*2*t))*t', 8)}*(0.8+0.2*sin(2*PI*8*t))", f="lowpass=f=3000", g=0.8),
                          dict(expr=f"{N}", f="bandpass=f=1800:w=2000", g=0.15)], 2.0, post=COMP, peak=-9, loop=0.25)
kfile("warp_ship", "sci-fi-sounds", "spaceEngineLarge_003", t=3.0, peak=-5)
render("evac_rocket", [
    dict(expr=f"{N}*min(1,t*4)*(0.5+0.5*exp(-t*0.3))", f="lowpass=f=2200,highpass=f=80", g=1.0),
    dict(expr=f"sin({decay_phase(80, 45, 1.0)})*min(1,t*5)", g=0.9),
    dict(expr=f"{N2}*min(1,t*3)", f="lowpass=f=350", g=1.0)], 4.0, post=COMP + ",aecho=0.5:0.5:100:0.3", peak=-3)

# ---------------------------------------------------------------- ambience (stereo, seamless)
render("amb_wind", [
    dict(expr=f"{N}*(0.55+0.45*sin(2*{PI}*0.11*t)*sin(2*{PI}*0.07*t+1))", f="lowpass=f=520,highpass=f=60", g=1.0, ch=1),
    dict(expr=f"{N2}*(0.3+0.7*max(0,sin(2*{PI}*0.05*t+2)))", f="bandpass=f=900:w=700", g=0.5)],
    24.0, post="acompressor=threshold=0.05:ratio=3:makeup=3", ch=2, peak=-6, loop=2.0, q=3,
    sr=44100)
render("amb_insects", [
    dict(expr=f"{N}*pow(max(0,sin(2*{PI}*(33+4*sin(2*{PI}*0.3*t))*t)),2)*(0.4+0.6*max(0,sin(2*{PI}*0.21*t)))", f="bandpass=f=5200:w=1800", g=0.6,
         pan="pan=stereo|c0=0.8*c0|c1=0.35*c0"),
    dict(expr=f"{N2}*pow(max(0,sin(2*{PI}*(27+3*sin(2*{PI}*0.17*t))*t)),2)*(0.4+0.6*max(0,sin(2*{PI}*0.13*t+2)))", f="bandpass=f=4300:w=1500", g=0.6,
         pan="pan=stereo|c0=0.3*c0|c1=0.85*c0"),
    dict(expr=f"sin(2*{PI}*3600*t)*pow(max(0,sin(2*{PI}*11*t)),3)*max(0,sin(2*{PI}*0.09*t+1))", g=0.12,
         pan="pan=stereo|c0=0.6*c0|c1=0.6*c0"),
    dict(expr=f"{N3}*0.5", f="lowpass=f=300", g=0.08)],
    24.0, post="acompressor=threshold=0.05:ratio=3:makeup=3", ch=2, peak=-8, loop=2.0, q=3)

# ---------------------------------------------------------------- music (stereo, 120 bpm, 90 s, seamless)
LOOP = 90.0
def q90(f):
    return round(f * 90) / 90.0

ROOTS = [55.0, 43.65, 65.41, 49.0, 73.42, 41.2]  # A1 F1 C2 G1 D2 E1: 6 x 15 s
def win(i):
    return f"sin({PI}*mod(t-{15 * i}+90,90)/30)^2*lt(mod(t-{15 * i}+90,90),30)"

def pad_expr(side):
    d = 2 / 90.0 * (1 if side else -1)
    terms = []
    for i, r in enumerate(ROOTS):
        parts = []
        for mult, amp in [(1, 0.5), (2, 0.35), (3, 0.22), (4, 0.2), (6, 0.1), (5.0 * 1.2, 0.05)]:
            f = q90(r * mult) + d
            parts.append(f"{amp}*sin(2*{PI}*{f:.6f}*t)")
        # minor 3rd shimmer an octave+ up
        parts.append(f"0.08*sin(2*{PI}*{q90(r * 6.0) + d:.6f}*t+2*sin(2*{PI}*{1 / 15:.6f}*t))")
        terms.append(f"if(lt(mod(t-{15 * i}+90,90),30),{win(i)}*(" + "+".join(parts) + "),0)")
    return "+".join(terms)

def bell_expr(side):
    notes = [(2, 440), (9, 523.25), (14, 659.25), (22, 392), (29, 523.25), (35, 587.33), (43, 440), (50, 659.25),
             (58, 392), (64, 523.25), (73, 587.33), (82, 440)]
    ts = []
    for k, (o, f) in enumerate(notes):
        pan = 0.35 + 0.5 * ((k + side) % 2)
        ts.append(f"if(lt(mod(t-{o}+90,90),7),min(1,mod(t-{o}+90,90)*300)*exp(-mod(t-{o}+90,90)*1.0)*{pan}*"
                  f"(sin(2*{PI}*{q90(f):.5f}*t)+0.3*sin(2*{PI}*{q90(f * 2.76):.5f}*t)),0)")
    return "+".join(ts)

# calm bed: drone + slow pad + heartbeat pulse every bar + sparse bells
render("music_calm", [
    dict(expr=pad_expr(0) + "|" + pad_expr(1), f="lowpass=f=1800", g=0.9, ch=2, sr=22050),
    dict(expr=f"(sin(2*{PI}*{q90(55)}*t)+0.5*sin(2*{PI}*{q90(110)}*t))*(0.7+0.3*sin(2*{PI}*{1 / 18:.6f}*t))|(sin(2*{PI}*{q90(55)}*t)+0.5*sin(2*{PI}*{q90(110)}*t))*(0.7+0.3*sin(2*{PI}*{1 / 18:.6f}*t+1))", g=0.7, ch=2, sr=22050),
    dict(expr=f"sin({decay_phase(95, 48, 0.07)}-0)*exp(-mod(t,2)*5)*(1-0.4*lt(mod(t,4),2))", f="lowpass=f=260", g=0.9, ch=1, sr=22050),
    dict(expr=bell_expr(0) + "|" + bell_expr(1), f="aecho=0.5:0.5:330|520:0.35|0.25", g=0.22, ch=2, sr=22050),
], LOOP, post="", ch=2, peak=-12, q=3)

KICK = f"sin(2*{PI}*(46*mod(t,0.5)+110*0.035*(1-exp(-mod(t,0.5)/0.035))))*exp(-mod(t,0.5)*8)"
SNARE_N = f"{N}*exp(-mod(t-0.5,1)*16)"
SNARE_T = f"sin(2*{PI}*190*t)*exp(-mod(t-0.5,1)*28)"
HAT = f"{N2}*exp(-mod(t,0.25)*55)*(0.5+0.5*lt(mod(t,0.5),0.25))"
def bass_expr():
    terms = []
    for i, r in enumerate(ROOTS):
        f = q90(r * 2)
        terms.append(f"if(lt(mod(t-{15 * i}+90,90),30),{win(i)}*({saw(f'2*PI*{f:.6f}*t', 5)}),0)")
    gate = "gt(mod(floor(mod(t,2)/0.25)>=0 ,2),-1)"
    pat = 0b10110110
    step = "floor(mod(t,2)/0.25)"
    return "(" + "+".join(terms) + f")*exp(-mod(t,0.25)*6)*gt(mod(floor({pat}/pow(2,{step})),2),0.5)"
TOM = (f"sin(2*{PI}*(75+50*floor(mod(t,0.25)*0)+40*(1-exp(-mod(t,0.25)/0.05))*0)*t)")
tomexpr = f"sin(2*{PI}*(160-25*floor(mod(t,2)/0.25))*mod(t,0.25))*exp(-mod(t,0.25)*9)*gt(mod(t,8),7)"
render("music_combat", [
    dict(expr=KICK, g=1.0, f="lowpass=f=400", sr=44100),
    dict(expr=SNARE_N, f="bandpass=f=2800:w=4000", g=0.5, pan="pan=stereo|c0=0.9*c0|c1=0.9*c0"),
    dict(expr=SNARE_T, g=0.5),
    dict(expr=HAT, f="highpass=f=7000", g=0.3, pan="pan=stereo|c0=0.45*c0|c1=0.8*c0"),
    dict(expr=bass_expr(), f="lowpass=f=500", g=0.8),
    dict(expr=tomexpr, f="lowpass=f=700", g=0.8),
    dict(expr=f"{N3}*pow(mod(t,16)/16,3)", f="bandpass=f=3500:w=3000", g=0.25, pan="pan=stereo|c0=0.7*c0|c1=0.7*c0"),
], LOOP, post=COMP, ch=2, peak=-10, q=3)

# extract stinger (~6 s, one-shot)
def chord(freqs, gain, atk, dec, d=0):
    return dict(expr="+".join(f"{saw(f'2*PI*{f}*t', 6)}" for f in freqs) + f"*min(1,t/{atk})*exp(-t*{dec})", f="lowpass=f=3200", g=gain, d=d)
render("music_extract", [
    chord([110, 164.8, 220, 261.6], 0.3, 0.9, 0.55),
    chord([220, 329.6, 440, 523.3, 659.3], 0.22, 1.1, 0.5, d=0.5),
    dict(expr=f"sin({decay_phase(120, 48, 0.08)})*exp(-t*3.5)", g=1.1),
    dict(expr=f"sin({decay_phase(120, 48, 0.08)})*exp(-t*3.5)", g=0.8, d=0.5),
    dict(expr=f"{N}*exp(-t*1.2)*min(1,t*30)", f="highpass=f=4500", g=0.18, d=0.5),
    dict(expr=f"(sin(2*{PI}*1318.5*t)+0.3*sin(2*{PI}*3638*t))*exp(-t*1.1)", f="aecho=0.5:0.5:250:0.4", g=0.2, d=2.0),
    dict(expr=f"(sin(2*{PI}*1760*t)+0.3*sin(2*{PI}*4857*t))*exp(-t*1.1)", f="aecho=0.5:0.5:250:0.4", g=0.18, d=2.6),
], 6.0, post="aecho=0.6:0.5:140|230:0.3|0.2," + COMP + ",afade=t=out:st=4.5:d=1.5", ch=2, peak=-6, q=4)

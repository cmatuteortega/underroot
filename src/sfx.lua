-- Every sound in the game, made at load from nothing: no sample files.
--
-- A sound is a few voices mixed: an oscillator (sine, triangle, square, saw,
-- white noise, or "grit", noise held at a pitch), its pitch swept from one
-- frequency to another, a low or high pass swept the same way, frequency
-- modulation or vibrato, and an envelope that opens over `a` seconds and dies
-- away as a power curve. Each is rendered once into a SoundData and played
-- from a small pool of sources, with a little pitch wobble so a hundred puffs
-- do not sound like one puff a hundred times.
--
-- The game asks for sounds by name (Game:cue in src/game.lua for what happens
-- on the board, src/ui/ for the buttons), with a pan and a volume for where on
-- the screen it happened. Each name has a shortest gap between two plays and a
-- most-at-once, so a spore barrage stays a patter and not a wall.
--
-- Under it all run loops: the network's hum, which swells with the living
-- links and goes quiet when the network does, the soil, and one a weather.

local floor, min, max, abs, sin, exp, sqrt = math.floor, math.min, math.max, math.abs, math.sin, math.exp, math.sqrt
local TAU = 2 * math.pi
local RATE = 22050

local Sfx = { on = false, level = 1, away = false }

-- Notes, by name, for the chimes.
local N = {}
do
    local names = { "C", "Cs", "D", "Ds", "E", "F", "Fs", "G", "Gs", "A", "As", "B" }
    for oct = 1, 7 do
        for k, nm in ipairs(names) do
            N[nm .. oct] = 440 * 2 ^ ((oct - 4) + (k - 10) / 12)
        end
    end
end

--- the synth ---------------------------------------------------------------------------------

-- One voice, added into `out` (a plain table of floats).
local function voice(v, out, rng)
    local start = floor((v.at or 0) * RATE)
    local len = max(1, floor(v.dur * RATE))
    local f0, f1 = v.f0 or 440, v.f1 or v.f0 or 440
    local bend = v.bend or 1
    local wave = v.wave or "sine"
    local duty = v.duty or 0.5
    local a = v.a or 0.004
    local curve = v.curve or 2
    local vol = v.vol or 1
    local lp0, lp1 = v.lp and v.lp[1], v.lp and (v.lp[2] or v.lp[1])
    local hp0, hp1 = v.hp and v.hp[1], v.hp and (v.hp[2] or v.hp[1])
    local vib, fm, trem = v.vib, v.fm, v.trem
    local phase, mphase = v.phase or 0, 0
    local held, last = rng:random() * 2 - 1, 0
    local l1, l2, h1 = 0, 0, 0
    for i = 0, len - 1 do
        local x = i / len
        local t = i / RATE
        local f = f0 * (f1 / f0) ^ (x ^ bend)
        if vib then f = f * (1 + vib[2] * sin(TAU * vib[1] * t)) end
        local pm = 0
        if fm then
            mphase = mphase + f * fm[1] / RATE
            pm = fm[2] * (fm[3] and (1 - x) or 1) * sin(TAU * mphase)
        end
        phase = phase + f / RATE
        local p = (phase + pm / TAU) % 1
        local s
        if wave == "sine" then
            s = sin(TAU * p)
        elseif wave == "tri" then
            s = 1 - 4 * abs(p - 0.5)
        elseif wave == "square" then
            s = (p < duty and 1 - duty or -duty) * 1.4 -- zero on average, whatever the duty
        elseif wave == "saw" then
            s = (2 * p - 1) * 0.8
        elseif wave == "noise" then
            s = rng:random() * 2 - 1
        else -- "grit": noise held for a cycle of f, so it has a pitch
            if floor(phase) ~= last then last, held = floor(phase), rng:random() * 2 - 1 end
            s = held
        end
        if lp0 then
            local c = lp0 * (lp1 / lp0) ^ x
            local k = 1 - exp(-TAU * c / RATE)
            l1 = l1 + k * (s - l1)
            l2 = l2 + k * (l1 - l2)
            s = l2
        end
        if hp0 then
            local c = hp0 * (hp1 / hp0) ^ x
            local k = 1 - exp(-TAU * c / RATE)
            h1 = h1 + k * (s - h1)
            s = s - h1
        end
        local env
        if t < a then env = t / a
        else env = (1 - (t - a) / max(1e-4, v.dur - a)) ^ curve end
        if trem then env = env * (1 - trem[2] * (0.5 + 0.5 * sin(TAU * trem[1] * t))) end
        local o = start + i
        out[o] = (out[o] or 0) + s * env * vol
    end
    return start + len
end

-- A sound: its voices mixed, an echo if it has one, scaled so its loudest
-- moment is `gain`. A loop is crossfaded end into start so it has no seam.
local function render(def)
    local rng = love.math.newRandomGenerator(def.seed or 1)
    local out, n = {}, 0
    for _, v in ipairs(def) do n = max(n, voice(v, out, rng)) end
    if def.gen then
        local len = floor(def.len * RATE)
        for i = 0, len - 1 do out[i] = (out[i] or 0) + def.gen(i / RATE, rng, i) end
        n = max(n, len)
    end
    for i = 0, n - 1 do out[i] = out[i] or 0 end
    if def.echo then
        local d, fb = floor(def.echo[1] * RATE), def.echo[2]
        local tail = n + d * 4
        for i = n, tail - 1 do out[i] = 0 end
        for i = d, tail - 1 do out[i] = out[i] + out[i - d] * fb end
        n = tail
    end
    if def.loop then
        local x = floor(def.loop * RATE)
        n = n - x
        for i = 0, x - 1 do
            local f = i / x
            out[i] = out[i] * f + out[n + i] * (1 - f)
        end
    end
    local peak = 1e-6
    for i = 0, n - 1 do peak = max(peak, abs(out[i])) end
    local g = (def.gain or 0.8) / peak
    local data = love.sound.newSoundData(n, RATE, 16, 1)
    local ok, ptr = pcall(function() return data:getFFIPointer() end)
    if ok and ptr then
        local ffi = require "ffi"
        local p = ffi.cast("int16_t *", ptr)
        for i = 0, n - 1 do p[i] = floor(max(-1, min(1, out[i] * g)) * 32767) end
    else
        for i = 0, n - 1 do data:setSample(i, max(-1, min(1, out[i] * g))) end
    end
    return data
end

--- the sounds -----------------------------------------------------------------------------
--
-- Each: its voices, then how it is played: `vol`, `gap` (shortest time between
-- two), `poly` (most at once), `wob` (how far its pitch wanders, either way).

local function chime(at, f, dur, vol, wave)
    return { at = at, dur = dur or 0.35, wave = wave or "sine", f0 = f, vol = vol or 1, a = 0.003, curve = 3 }
end

local DEFS = {
    --- the buttons
    hover = { vol = 0.12, gap = 0.04, { dur = 0.018, wave = "square", f0 = 2600, f1 = 2400, duty = 0.3, curve = 1 } },
    click = { vol = 0.35, gap = 0.03,
        { dur = 0.04, wave = "tri", f0 = 1100, f1 = 650, curve = 2 },
        { dur = 0.012, wave = "noise", hp = { 3000 }, vol = 0.4 } },
    select = { vol = 0.35, gap = 0.03,
        { dur = 0.05, wave = "tri", f0 = N.E5, curve = 1.5 },
        { at = 0.045, dur = 0.08, wave = "tri", f0 = N.B5, curve = 2 } },
    back = { vol = 0.3, gap = 0.03,
        { dur = 0.05, wave = "tri", f0 = N.B5, curve = 1.5 },
        { at = 0.045, dur = 0.08, wave = "tri", f0 = N.E5, curve = 2 } },
    deny = { vol = 0.35, gap = 0.12,
        { dur = 0.16, wave = "square", f0 = 150, duty = 0.4, lp = { 1400, 600 }, curve = 1 },
        { dur = 0.16, wave = "square", f0 = 159, duty = 0.4, lp = { 1400, 600 }, curve = 1, vol = 0.8 } },
    on = { vol = 0.3, gap = 0.03, { dur = 0.09, wave = "sine", f0 = 520, f1 = 1040, bend = 0.5, curve = 2 },
        { at = 0.05, dur = 0.08, wave = "tri", f0 = 1560, vol = 0.3 } },
    off = { vol = 0.3, gap = 0.03, { dur = 0.1, wave = "sine", f0 = 900, f1 = 420, bend = 0.6, curve = 2 } },
    pause = { vol = 0.35, gap = 0.1, chime(0, N.G4, 0.12, 1, "tri"), chime(0.09, N.C4, 0.2, 1, "tri") },
    unpause = { vol = 0.35, gap = 0.1, chime(0, N.C4, 0.12, 1, "tri"), chime(0.09, N.G4, 0.2, 1, "tri") },
    speed = { vol = 0.3, gap = 0.05, { dur = 0.06, wave = "square", f0 = 700, f1 = 1400, duty = 0.25, lp = { 3000 } } },
    turn = { vol = 0.35, gap = 0.1,
        { dur = 0.32, wave = "noise", a = 0.12, lp = { 400, 2400 }, hp = { 200 }, curve = 1.5 },
        { dur = 0.32, wave = "sine", f0 = 180, f1 = 260, a = 0.1, vol = 0.25 } },
    zoom = { vol = 0.2, gap = 0.04, { dur = 0.05, wave = "sine", f0 = 600, f1 = 900, curve = 2 } },
    panel = { vol = 0.25, gap = 0.05,
        { dur = 0.06, wave = "noise", lp = { 1800, 600 }, vol = 0.5 },
        { dur = 0.07, wave = "tri", f0 = 740, f1 = 990, curve = 2, vol = 0.6 } },
    go = { vol = 0.4, gap = 0.3, echo = { 0.11, 0.3 },
        chime(0, N.C5, 0.2), chime(0.07, N.E5, 0.2), chime(0.14, N.G5, 0.2), chime(0.21, N.C6, 0.45),
        { dur = 0.4, wave = "noise", lp = { 900, 200 }, vol = 0.3, curve = 3 } },

    --- the network
    grow = { vol = 0.4, gap = 0.08, wob = 0.08,
        { dur = 0.26, wave = "sine", f0 = 170, f1 = 430, bend = 0.7, vib = { 22, 0.06 }, curve = 1.5 },
        { dur = 0.22, wave = "noise", lp = { 500, 1600 }, vol = 0.35, a = 0.05, curve = 2 } },
    linked = { vol = 0.3, gap = 0.06, wob = 0.06,
        chime(0, N.A5, 0.28, 1, "tri"), chime(0.005, N.E6, 0.18, 0.4) },
    cut = { vol = 0.5, gap = 0.06, wob = 0.1,
        { dur = 0.05, wave = "noise", hp = { 1800 }, curve = 1.5 },
        { dur = 0.14, wave = "sine", f0 = 320, f1 = 70, bend = 0.4, curve = 2, vol = 0.9 },
        { at = 0.02, dur = 0.1, wave = "grit", f0 = 900, f1 = 300, lp = { 2500 }, vol = 0.4 } },
    prune = { vol = 0.4, gap = 0.06,
        { dur = 0.025, wave = "noise", hp = { 2500 }, curve = 1 },
        { at = 0.06, dur = 0.03, wave = "noise", hp = { 2000 }, curve = 1 },
        { at = 0.06, dur = 0.08, wave = "tri", f0 = 900, f1 = 500, vol = 0.4 } },
    regrow = { vol = 0.3, gap = 0.08, wob = 0.08,
        { dur = 0.22, wave = "sine", f0 = 300, f1 = 640, bend = 0.6, curve = 2 },
        chime(0.12, N.E6, 0.18, 0.35) },
    mend = { vol = 0.3, gap = 0.12,
        chime(0, N.D6, 0.12, 0.6), chime(0.04, N.A6, 0.12, 0.4), chime(0.08, N.D7, 0.2, 0.25) },
    build = { vol = 0.5, gap = 0.08, wob = 0.05,
        { dur = 0.12, wave = "noise", lp = { 700, 150 }, curve = 2 },
        { dur = 0.22, wave = "sine", f0 = 150, f1 = 360, bend = 0.5, curve = 2, vol = 0.9 },
        chime(0.1, N.G5, 0.25, 0.35), chime(0.16, N.D6, 0.3, 0.25) },
    upgrade = { vol = 0.5, gap = 0.1, echo = { 0.09, 0.25 },
        { dur = 0.3, wave = "sine", f0 = 200, f1 = 500, bend = 0.5, curve = 2, vol = 0.6 },
        chime(0.05, N.C5, 0.2, 0.7, "tri"), chime(0.11, N.G5, 0.2, 0.7, "tri"),
        chime(0.17, N.C6, 0.3, 0.7, "tri"), chime(0.23, N.E6, 0.4, 0.5),
        { at = 0.15, dur = 0.3, wave = "noise", hp = { 5000 }, vol = 0.1, curve = 2 } },
    sell = { vol = 0.4, gap = 0.08,
        chime(0, N.E6, 0.12, 0.6, "tri"), chime(0.07, N.B5, 0.18, 0.6, "tri"),
        { dur = 0.15, wave = "noise", lp = { 900, 200 }, vol = 0.3 } },
    lay = { vol = 0.45, gap = 0.08, wob = 0.08,
        { dur = 0.22, wave = "noise", lp = { 300, 1200 }, curve = 1.5, vol = 0.7 },
        { dur = 0.25, wave = "sine", f0 = 110, f1 = 90, vib = { 18, 0.15 }, curve = 1.5 } },
    lift = { vol = 0.4, gap = 0.08,
        { dur = 0.2, wave = "noise", lp = { 1400, 300 }, curve = 1.5, vol = 0.7 },
        { dur = 0.2, wave = "sine", f0 = 90, f1 = 160, curve = 2 } },
    die = { vol = 0.5, gap = 0.1, wob = 0.08, -- a fruiting body lost
        { dur = 0.1, wave = "noise", lp = { 2200, 400 }, curve = 1.2 },
        { dur = 0.4, wave = "sine", f0 = 420, f1 = 90, bend = 0.6, curve = 1.5, vol = 0.8 },
        { at = 0.03, dur = 0.2, wave = "grit", f0 = 300, f1 = 80, lp = { 1200 }, vol = 0.5 } },
    smash = { vol = 0.45, gap = 0.08, wob = 0.1, -- a mat or shelf broken
        { dur = 0.18, wave = "grit", f0 = 600, f1 = 120, lp = { 2000, 300 }, curve = 1.5 },
        { dur = 0.15, wave = "noise", lp = { 1500, 300 }, vol = 0.6 } },
    pulse = { vol = 0.6, gap = 0.3, echo = { 0.12, 0.3 },
        { dur = 0.5, wave = "noise", a = 0.15, lp = { 300, 4000 }, hp = { 150 }, curve = 2, vol = 0.6 },
        { dur = 0.6, wave = "sine", f0 = 220, f1 = 880, bend = 0.4, fm = { 2, 1.5, true }, curve = 1.5 },
        chime(0.3, N.A6, 0.4, 0.35) },
    ring = { vol = 0.5, gap = 0.5, echo = { 0.15, 0.35 },
        chime(0, N.D5, 1, 0.6), chime(0.08, N.Fs5, 1, 0.5), chime(0.16, N.A5, 1, 0.5), chime(0.24, N.D6, 1.1, 0.5),
        { dur = 1, wave = "sine", f0 = N.D4, vib = { 5, 0.006 }, a = 0.2, curve = 1, vol = 0.4 } },
    drink = { vol = 0.25, gap = 0.12, wob = 0.15,
        { dur = 0.22, wave = "sine", f0 = 260, f1 = 620, vib = { 30, 0.1 }, curve = 1.5 },
        { dur = 0.18, wave = "noise", lp = { 600, 1500 }, vol = 0.25 } },
    heart = { vol = 0.6, gap = 0.15,
        { dur = 0.3, wave = "sine", f0 = 110, f1 = 45, curve = 2 },
        { dur = 0.35, wave = "tri", f0 = 330, f1 = 300, vib = { 9, 0.03 }, curve = 1.5, vol = 0.4 },
        { dur = 0.35, wave = "tri", f0 = 349, f1 = 318, curve = 1.5, vol = 0.35 },
        { dur = 0.08, wave = "noise", lp = { 900 }, vol = 0.5 } },
    salt = { vol = 0.5, gap = 0.12, echo = { 0.07, 0.25 },
        { dur = 0.5, wave = "noise", hp = { 3000, 6000 }, curve = 2, vol = 0.45 },
        chime(0, N.Fs6, 0.3, 0.5), chime(0.07, N.C6, 0.3, 0.5), chime(0.14, N.Fs5, 0.4, 0.5) },
    fizzle = { vol = 0.3, gap = 0.1, { dur = 0.35, wave = "noise", hp = { 2500 }, lp = { 7000, 3000 }, curve = 2 } },

    --- the waves
    wave = { vol = 0.6, gap = 0.5,
        { dur = 0.9, wave = "saw", f0 = 98, f1 = 110, lp = { 300, 900 }, a = 0.08, vib = { 5, 0.01 }, curve = 1.2 },
        { dur = 0.9, wave = "saw", f0 = 147, f1 = 165, lp = { 300, 900 }, a = 0.08, curve = 1.2, vol = 0.6 },
        { dur = 0.25, wave = "sine", f0 = 120, f1 = 40, curve = 2 },
        { at = 0.3, dur = 0.25, wave = "sine", f0 = 120, f1 = 40, curve = 2 } },
    clear = { vol = 0.5, gap = 0.5, echo = { 0.12, 0.3 },
        chime(0, N.G5, 0.25), chime(0.08, N.B5, 0.25), chime(0.16, N.D6, 0.25), chime(0.24, N.G6, 0.6),
        chime(0.24, N.G4, 0.6, 0.5, "tri") },
    unlock = { vol = 0.5, gap = 0.5, echo = { 0.1, 0.3 },
        chime(0, N.C6, 0.15, 0.8, "tri"), chime(0.1, N.G6, 0.15, 0.8, "tri"), chime(0.2, N.E6, 0.15, 0.8, "tri"),
        chime(0.3, N.C7, 0.5, 0.6) },
    won = { vol = 0.6, gap = 1, echo = { 0.14, 0.3 },
        chime(0, N.C5, 0.3, 0.8, "tri"), chime(0.15, N.E5, 0.3, 0.8, "tri"), chime(0.3, N.G5, 0.3, 0.8, "tri"),
        chime(0.45, N.C6, 1.1, 0.8, "tri"), chime(0.45, N.E6, 1.1, 0.5), chime(0.45, N.G6, 1.1, 0.4),
        { at = 0.45, dur = 1.1, wave = "sine", f0 = N.C4, a = 0.05, curve = 1.5, vol = 0.6 } },
    lost = { vol = 0.6, gap = 1,
        { dur = 0.5, wave = "tri", f0 = N.E4, f1 = N.Ds4, curve = 1, vol = 0.8 },
        { at = 0.45, dur = 0.5, wave = "tri", f0 = N.Cs4, f1 = N.C4, curve = 1, vol = 0.8 },
        { at = 0.9, dur = 1.2, wave = "tri", f0 = N.A3, f1 = N.Gs3, vib = { 5, 0.01 }, curve = 1.5 },
        { at = 0.9, dur = 1.2, wave = "sine", f0 = N.A2, curve = 1.5, vol = 0.6 } },
    offer = { vol = 0.5, gap = 0.5, echo = { 0.13, 0.4 },
        { dur = 1.2, wave = "sine", f0 = N.E5, vib = { 6, 0.012 }, a = 0.1, curve = 1.2, vol = 0.5 },
        { dur = 1.2, wave = "sine", f0 = N.Gs5, vib = { 6.5, 0.012 }, a = 0.15, curve = 1.2, vol = 0.4 },
        { dur = 1.2, wave = "sine", f0 = N.B5, vib = { 7, 0.012 }, a = 0.2, curve = 1.2, vol = 0.4 },
        { dur = 1.2, wave = "sine", f0 = N.E3, fm = { 1.5, 1.2 }, a = 0.1, curve = 1.2, vol = 0.4 } },
    mutate = { vol = 0.55, gap = 0.5, echo = { 0.1, 0.35 },
        { dur = 0.6, wave = "sine", f0 = 200, f1 = 800, bend = 0.5, fm = { 3, 2, true }, curve = 1.5, vol = 0.5 },
        chime(0.1, N.E5, 0.3, 0.6, "tri"), chime(0.18, N.B5, 0.3, 0.6, "tri"), chime(0.26, N.E6, 0.5, 0.6) },
    boss = { vol = 0.75, gap = 1,
        { dur = 1.4, wave = "saw", f0 = 70, f1 = 52, lp = { 600, 200 }, vib = { 13, 0.08 }, a = 0.1, curve = 1.2 },
        { dur = 1.4, wave = "saw", f0 = 105, f1 = 77, lp = { 800, 250 }, vib = { 11, 0.09 }, a = 0.1, curve = 1.2, vol = 0.6 },
        { dur = 1.3, wave = "noise", lp = { 900, 150 }, a = 0.2, curve = 1, vol = 0.5 },
        { dur = 0.3, wave = "sine", f0 = 80, f1 = 30, vol = 0.8 } },
    stomp = { vol = 0.35, gap = 0.15, wob = 0.1,
        { dur = 0.14, wave = "sine", f0 = 75, f1 = 38, curve = 2 },
        { dur = 0.06, wave = "noise", lp = { 400 }, vol = 0.5 } },

    --- the fruiting bodies
    puff = { vol = 0.3, gap = 0.05, poly = 4, wob = 0.12,
        { dur = 0.13, wave = "noise", a = 0.01, lp = { 1600, 500 }, curve = 2 },
        { dur = 0.08, wave = "sine", f0 = 260, f1 = 160, vol = 0.4 } },
    pop = { vol = 0.2, gap = 0.05, poly = 4, wob = 0.15,
        { dur = 0.07, wave = "noise", lp = { 2500, 700 }, curve = 2 },
        { dur = 0.05, wave = "sine", f0 = 500, f1 = 220, vol = 0.5 } },
    zip = { vol = 0.25, gap = 0.04, poly = 4, wob = 0.08,
        { dur = 0.08, wave = "square", f0 = 2600, f1 = 700, duty = 0.3, lp = { 5000 }, curve = 1.5 },
        { dur = 0.05, wave = "noise", hp = { 4000 }, vol = 0.4 } },
    lance = { vol = 0.35, gap = 0.05, poly = 3, wob = 0.05,
        { dur = 0.14, wave = "saw", f0 = 1800, f1 = 300, lp = { 6000, 1500 }, curve = 1.5 },
        { dur = 0.1, wave = "noise", hp = { 3000 }, vol = 0.5 } },
    thump = { vol = 0.45, gap = 0.08, wob = 0.06,
        { dur = 0.2, wave = "sine", f0 = 140, f1 = 55, curve = 2 },
        { dur = 0.12, wave = "noise", lp = { 900, 200 }, vol = 0.6 } },
    boom = { vol = 0.6, gap = 0.08, poly = 3, wob = 0.1,
        { dur = 0.55, wave = "noise", lp = { 2200, 120 }, curve = 1.8 },
        { dur = 0.4, wave = "sine", f0 = 95, f1 = 35, curve = 1.6 },
        { dur = 0.3, wave = "grit", f0 = 200, f1 = 60, lp = { 900 }, vol = 0.5 } },
    bomblet = { vol = 0.3, gap = 0.05, poly = 4, wob = 0.15,
        { dur = 0.15, wave = "noise", lp = { 1800, 300 }, curve = 2 },
        { dur = 0.1, wave = "sine", f0 = 160, f1 = 60 } },
    spit = { vol = 0.35, gap = 0.08, wob = 0.1,
        { dur = 0.1, wave = "noise", hp = { 800 }, lp = { 4000 }, curve = 1.5 },
        { dur = 0.12, wave = "sine", f0 = 600, f1 = 260, vol = 0.6 } },
    infect = { vol = 0.4, gap = 0.1, wob = 0.08,
        { dur = 0.4, wave = "sine", f0 = 330, f1 = 250, fm = { 1.41, 3 }, vib = { 7, 0.05 }, curve = 1.5 },
        { dur = 0.4, wave = "tri", f0 = 466, f1 = 350, vib = { 6, 0.04 }, curve = 1.5, vol = 0.4 } },
    ink = { vol = 0.35, gap = 0.08, wob = 0.1,
        { dur = 0.12, wave = "sine", f0 = 700, f1 = 180, bend = 0.5, curve = 1.5 },
        { at = 0.08, dur = 0.1, wave = "sine", f0 = 300, f1 = 520, vol = 0.4 } },
    quake = { vol = 0.65, gap = 0.2,
        { dur = 0.8, wave = "noise", lp = { 220, 70 }, a = 0.03, curve = 1.3 },
        { dur = 0.7, wave = "sine", f0 = 52, f1 = 34, vib = { 11, 0.08 }, curve = 1.5 },
        { dur = 0.4, wave = "grit", f0 = 90, f1 = 40, lp = { 400 }, vol = 0.5 } },
    trip = { vol = 0.2, gap = 0.12, wob = 0.15,
        { dur = 0.12, wave = "tri", f0 = 600, f1 = 300, curve = 1.5 },
        { at = 0.06, dur = 0.06, wave = "noise", lp = { 800 }, vol = 0.5 } },
    panic = { vol = 0.4, gap = 0.3,
        { dur = 0.35, wave = "square", f0 = 95, f1 = 75, duty = 0.3, lp = { 700 }, vib = { 24, 0.1 }, curve = 1.2 },
        { dur = 0.3, wave = "noise", lp = { 600 }, vol = 0.4 } },
    flare = { vol = 0.6, gap = 0.2, echo = { 0.08, 0.3 },
        { dur = 0.45, wave = "noise", lp = { 6000, 500 }, curve = 1.5, vol = 0.7 },
        { dur = 0.5, wave = "sine", f0 = 1200, f1 = 300, fm = { 2.5, 2, true }, curve = 1.5 },
        { dur = 0.2, wave = "sine", f0 = 90, f1 = 40, vol = 0.7 } },
    snuff = { vol = 0.35, gap = 0.2, { dur = 0.3, wave = "noise", lp = { 2500, 300 }, curve = 1.5 },
        { dur = 0.3, wave = "sine", f0 = 900, f1 = 250, vol = 0.4 } },
    web = { vol = 0.35, gap = 0.1, wob = 0.1,
        { dur = 0.16, wave = "noise", hp = { 1500, 5000 }, curve = 1.2 },
        { dur = 0.15, wave = "sine", f0 = 1400, f1 = 2200, vol = 0.3 } },
    stun = { vol = 0.3, gap = 0.15, wob = 0.08,
        chime(0, 1650, 0.25, 0.6), chime(0, 2470, 0.2, 0.3) },

    --- the bugs
    hit = { vol = 0.18, gap = 0.04, poly = 3, wob = 0.2,
        { dur = 0.035, wave = "noise", lp = { 2500, 900 }, curve = 1.5 },
        { dur = 0.03, wave = "sine", f0 = 380, f1 = 240, vol = 0.6 } },
    clink = { vol = 0.25, gap = 0.06, poly = 3, wob = 0.1,
        chime(0, 2400, 0.14, 0.7), chime(0, 3550, 0.1, 0.5), { dur = 0.01, wave = "noise", hp = { 5000 }, vol = 0.5 } },
    squish = { vol = 0.35, gap = 0.04, poly = 4, wob = 0.15,
        { dur = 0.14, wave = "noise", lp = { 1800, 250 }, curve = 1.5 },
        { dur = 0.12, wave = "sine", f0 = 330, f1 = 110, bend = 0.6, curve = 1.5, vol = 0.7 } },
    crunch = { vol = 0.5, gap = 0.06, poly = 3, wob = 0.1,
        { dur = 0.25, wave = "grit", f0 = 900, f1 = 200, lp = { 3000, 500 }, curve = 1.4 },
        { dur = 0.2, wave = "sine", f0 = 200, f1 = 60, curve = 2, vol = 0.6 },
        { dur = 0.1, wave = "noise", hp = { 1500 }, vol = 0.4 } },
    fell = { vol = 0.8, gap = 1, echo = { 0.16, 0.35 }, -- a boss falls
        { dur = 1.2, wave = "noise", lp = { 1600, 80 }, curve = 1.4 },
        { dur = 1, wave = "sine", f0 = 80, f1 = 28, curve = 1.3 },
        { dur = 0.5, wave = "grit", f0 = 400, f1 = 70, lp = { 1800 }, vol = 0.6 },
        chime(0.25, N.G4, 0.9, 0.3, "tri"), chime(0.35, N.D5, 0.9, 0.25, "tri") },
    splash = { vol = 0.35, gap = 0.06, poly = 3, wob = 0.12,
        { dur = 0.22, wave = "noise", hp = { 1200 }, lp = { 6000, 2000 }, curve = 1.6 },
        { dur = 0.1, wave = "sine", f0 = 900, f1 = 350, vol = 0.4 } },
    surface = { vol = 0.6, gap = 0.3,
        { dur = 0.6, wave = "noise", hp = { 500 }, lp = { 5000, 900 }, curve = 1.4 },
        { dur = 0.4, wave = "sine", f0 = 180, f1 = 60, curve = 1.5, vol = 0.8 },
        { at = 0.1, dur = 0.3, wave = "sine", f0 = 700, f1 = 300, vol = 0.3 } },
    chew = { vol = 0.12, gap = 0.18, poly = 2, wob = 0.15,
        { dur = 0.02, wave = "noise", lp = { 3000 }, curve = 1 },
        { at = 0.05, dur = 0.02, wave = "noise", lp = { 3000 }, curve = 1 },
        { at = 0.1, dur = 0.02, wave = "noise", lp = { 3000 }, curve = 1 } },
    ball = { vol = 0.7, gap = 0.5,
        { dur = 0.5, wave = "grit", f0 = 700, f1 = 120, lp = { 3000, 300 }, curve = 1.3 },
        { dur = 0.5, wave = "noise", lp = { 1200, 120 }, curve = 1.5 },
        { dur = 0.4, wave = "sine", f0 = 110, f1 = 35, curve = 1.5 } },
    charge = { vol = 0.6, gap = 0.5,
        { dur = 0.6, wave = "saw", f0 = 85, f1 = 140, lp = { 500, 1400 }, vib = { 15, 0.06 }, a = 0.05, curve = 1.2 },
        { dur = 0.6, wave = "noise", lp = { 400 }, vol = 0.6, curve = 1 } },
    -- A springtail off its tail: a tiny twang.
    spring = { vol = 0.2, gap = 0.08, poly = 3, wob = 0.15,
        { dur = 0.07, wave = "tri", f0 = 900, f1 = 2400, bend = 0.4, curve = 2 },
        { dur = 0.03, wave = "noise", hp = { 3000 }, vol = 0.4 } },
    -- The Click Beetle's click: a hard snap, and the thud of it going up.
    clack = { vol = 0.6, gap = 0.3,
        { dur = 0.03, wave = "noise", hp = { 2000 }, lp = { 9000 }, curve = 1 },
        { dur = 0.05, wave = "square", f0 = 1800, f1 = 900, duty = 0.2, curve = 2, vol = 0.7 },
        { at = 0.02, dur = 0.25, wave = "sine", f0 = 160, f1 = 60, curve = 1.8, vol = 0.6 } },
    -- The Mole Cricket's shovels at the soil: a dry scrape, again and again.
    dig = { vol = 0.3, gap = 0.25, poly = 2, wob = 0.12,
        { dur = 0.12, wave = "noise", hp = { 300 }, lp = { 2500, 700 }, curve = 1.5 },
        { at = 0.16, dur = 0.12, wave = "noise", hp = { 300 }, lp = { 2200, 600 }, curve = 1.5 },
        { at = 0.32, dur = 0.14, wave = "noise", hp = { 300 }, lp = { 2000, 500 }, curve = 1.5 } },
    -- Going under: a low rumble of soil falling in behind it.
    burrow = { vol = 0.55, gap = 0.4,
        { dur = 0.7, wave = "grit", f0 = 140, f1 = 50, lp = { 900, 200 }, a = 0.03, curve = 1.3 },
        { dur = 0.6, wave = "noise", lp = { 700, 150 }, curve = 1.4, vol = 0.6 } },
    spray = { vol = 0.5, gap = 0.2,
        { dur = 0.08, wave = "sine", f0 = 200, f1 = 70, curve = 2 },
        { dur = 0.5, wave = "noise", hp = { 1800 }, lp = { 8000, 3000 }, a = 0.02, curve = 1.3, vol = 0.8 } },
    brood = { vol = 0.3, gap = 0.4,
        { dur = 0.06, wave = "tri", f0 = 2200, f1 = 2800 }, { at = 0.08, dur = 0.06, wave = "tri", f0 = 2400, f1 = 3000 },
        { at = 0.16, dur = 0.06, wave = "tri", f0 = 2000, f1 = 2700 },
        { dur = 0.15, wave = "noise", lp = { 600 }, vol = 0.4 } },
}

-- The loops. Each a few seconds, its slow wobbles a whole number of turns
-- over its length so the seam does not show.
local LOOPS = {
    hum = { len = 4.2, loop = 0.2, gain = 0.7,
        gen = function(t)
            local s = sin(TAU * 55 * t) * 0.55 + sin(TAU * 110.24 * t) * 0.3 + sin(TAU * 164.8 * t) * 0.12
            local beat = 0.75 + 0.25 * sin(TAU * t / 4)
            return s * beat + sin(TAU * 220 * t) * 0.05 * (0.5 + 0.5 * sin(TAU * t * 2 / 4))
        end },
    soil = { len = 5.2, loop = 0.4, gain = 0.5, seed = 3,
        { dur = 5.6, wave = "noise", lp = { 160 }, a = 0.01, curve = 0 },
        { dur = 5.6, wave = "noise", lp = { 900 }, hp = { 600 }, a = 0.01, curve = 0, vol = 0.04 } },
    rain = { len = 3.2, loop = 0.3, gain = 0.7, seed = 5,
        { dur = 3.5, wave = "noise", lp = { 3500 }, hp = { 400 }, a = 0.01, curve = 0, vol = 0.5 },
        gen = (function()
            local drops = {}
            return function(t, rng)
                if rng:random() < 0.004 then drops[#drops + 1] = { t = t, f = 1500 + rng:random() * 2500 } end
                local s = 0
                for k = #drops, 1, -1 do
                    local d = drops[k]
                    local u = t - d.t
                    if u > 0.03 then table.remove(drops, k)
                    else s = s + sin(TAU * d.f * u) * (1 - u / 0.03) ^ 2 * 0.5 end
                end
                return s
            end
        end)() },
    wind = { len = 6.4, loop = 0.6, gain = 0.6, seed = 9,
        { dur = 7, wave = "noise", lp = { 500 }, hp = { 120 }, a = 0.01, curve = 0, trem = { 1 / 3.2, 0.6 } },
        { dur = 7, wave = "noise", lp = { 1600 }, hp = { 900 }, a = 0.01, curve = 0, trem = { 1 / 6.4, 0.8 }, vol = 0.25 } },
    night = { len = 4, loop = 0.1, gain = 0.45, seed = 11,
        gen = function(t)
            -- Two crickets, a chirp train each, out of step.
            local function cricket(t0, f, every)
                local u = (t - t0) % every
                if u > 0.32 then return 0 end
                local pulse = (u % 0.04) < 0.022 and 1 or 0
                return sin(TAU * f * t) * pulse * (1 - u / 0.32)
            end
            return cricket(0, 4300, 1) * 0.6 + cricket(0.45, 3900, 1.333333) * 0.4
        end },
    frost = { len = 6, loop = 0.5, gain = 0.5, seed = 13,
        { dur = 6.5, wave = "noise", lp = { 4000 }, hp = { 2500 }, a = 0.01, curve = 0, trem = { 1 / 3, 0.7 }, vol = 0.5 },
        chime(0.6, N.E7, 1.2, 0.2), chime(2.3, N.B6, 1.2, 0.2), chime(3.9, N.Gs6, 1.4, 0.2), chime(4.7, N.E7, 1, 0.15) },
}

--- playing -----------------------------------------------------------------------------------

local pools, last, loops = {}, {}, {}
local clock = 0
local todo = {} -- the sounds not yet rendered, the loops last

-- A sound's pool, rendered now if it was not yet.
local function pool(name)
    local p = pools[name]
    if p and not p.srcs then
        p.srcs, p.next = { love.audio.newSource(render(p.def), "static") }, 1
    end
    return p
end

local function loop(name)
    local l = loops[name]
    if l and not l.src then
        l.src = love.audio.newSource(render(l.def), "static")
        l.src:setLooping(true)
        l.src:setVolume(0)
    end
    return l
end

-- Gets ready to make every sound. Nothing at all if there is no audio device
-- to hear it. They are rendered a few a frame by `warm` (all of them take
-- half a second on a computer, more on a phone), or when first played.
function Sfx.init()
    if not (love.audio and love.sound) then return false end
    local ok, err = pcall(function()
        love.audio.setDistanceModel("none")
        love.sound.newSoundData(1, RATE, 16, 1)
    end)
    if not ok then print("sound off: " .. tostring(err)) return false end
    for name, def in pairs(DEFS) do
        pools[name] = { def = def }
        todo[#todo + 1] = { name = name }
    end
    table.sort(todo, function(a, b) return a.name < b.name end)
    -- The loops the title plays first, so it is not silent while the rest render.
    for name, def in pairs(LOOPS) do
        loops[name] = { def = def, vol = 0 }
        local first = name == "soil" or name == "hum" or name == "night"
        table.insert(todo, first and 1 or #todo + 1, { name = name, loop = true })
    end
    Sfx.on = true
    return true
end

-- Renders what is left to render for up to `budget` seconds.
function Sfx.warm(budget)
    if not Sfx.on or not todo[1] then return end
    local t0 = love.timer.getTime()
    while todo[1] and love.timer.getTime() - t0 < budget do
        local t = table.remove(todo, 1)
        if t.loop then loop(t.name) else pool(t.name) end
    end
end

-- Plays `name`: `pan` from -1 (left) to 1 (right), `vol` 0..1, `pitch` a factor.
function Sfx.play(name, pan, vol, pitch)
    if not Sfx.on or Sfx.away or Sfx.level <= 0 then return end
    if not pools[name] then return end
    local p = pool(name)
    local def = p.def
    if last[name] and clock - last[name] < (def.gap or 0.03) then return end
    last[name] = clock
    -- A free source from the pool, or a new one up to `poly`, or the oldest.
    local src
    for _, s in ipairs(p.srcs) do
        if not s:isPlaying() then src = s break end
    end
    if not src then
        if #p.srcs < (def.poly or 2) then
            src = p.srcs[1]:clone()
            p.srcs[#p.srcs + 1] = src
        else
            src = p.srcs[p.next]
            p.next = p.next % #p.srcs + 1
            src:stop()
        end
    end
    local wob = def.wob or 0.03
    src:setPitch((pitch or 1) * (1 + (love.math.random() * 2 - 1) * wob))
    src:setVolume(max(0, min(1, (def.vol or 0.5) * (vol or 1) * Sfx.level)))
    pan = max(-1, min(1, pan or 0)) * 0.7
    src:setPosition(pan, 0, -sqrt(1 - pan * pan))
    src:play()
end

-- The loops: `want` maps a loop's name to the volume it should be at; the rest
-- fade out. They ease there rather than jump.
function Sfx.update(dt, want, hum)
    clock = clock + dt
    if not Sfx.on or Sfx.away then return end
    for name, l in pairs(loops) do
        local target = (want and want[name] or 0) * Sfx.level
        l.vol = l.vol + (target - l.vol) * min(1, dt * 1.5)
        if l.vol < 0.002 and target == 0 then
            if l.src and l.src:isPlaying() then l.src:stop() end
            l.vol = 0
        elseif l.src then
            if not l.src:isPlaying() then l.src:play() end
            l.src:setVolume(l.vol)
        end
        -- A loop not rendered yet waits for `warm` rather than stall a frame.
    end
    if hum and loops.hum and loops.hum.src then loops.hum.src:setPitch(hum) end
end

-- The game out of sight (the phone locked, the app sent to the background, the
-- window minimised): everything playing stops where it is, and picks up from
-- there when it comes back.
local held
function Sfx.hide(away)
    if not Sfx.on or away == Sfx.away then return end
    Sfx.away = away
    if away then held = love.audio.pause()
    elseif held then love.audio.play(held); held = nil end
end

-- Loud, quiet, off: what the V key goes round.
function Sfx.cycle()
    Sfx.level = Sfx.level >= 1 and 0.5 or (Sfx.level > 0 and 0 or 1)
    return Sfx.level
end

function Sfx.names()
    local list = {}
    for name in pairs(DEFS) do list[#list + 1] = name end
    table.sort(list)
    return list
end

-- Dev: every sound written to a .wav in the save directory, to listen to.
function Sfx.dump()
    local function wav(data)
        local n = data:getSampleCount()
        local parts = {}
        local function u32(v) return string.char(v % 256, floor(v / 256) % 256, floor(v / 65536) % 256, floor(v / 16777216) % 256) end
        local function u16(v) return string.char(v % 256, floor(v / 256) % 256) end
        parts[#parts + 1] = "RIFF" .. u32(36 + n * 2) .. "WAVEfmt " .. u32(16) .. u16(1) .. u16(1) .. u32(RATE) .. u32(RATE * 2) .. u16(2) .. u16(16)
        parts[#parts + 1] = "data" .. u32(n * 2)
        local buf = {}
        for i = 0, n - 1 do
            local v = floor(data:getSample(i) * 32767)
            if v < 0 then v = v + 65536 end
            buf[#buf + 1] = u16(v)
        end
        parts[#parts + 1] = table.concat(buf)
        return table.concat(parts)
    end
    love.filesystem.createDirectory("sounds")
    for name, def in pairs(DEFS) do love.filesystem.write("sounds/" .. name .. ".wav", wav(render(def))) end
    for name, def in pairs(LOOPS) do love.filesystem.write("sounds/loop-" .. name .. ".wav", wav(render(def))) end
end

return Sfx

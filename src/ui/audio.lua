-- The sound's glue to the screen (the sounds themselves are src/sfx.lua):
-- what the game cued, panned to where it happened; the loops under it all; a
-- tick when the pointer comes onto something.

local D = require "src.defs"
local Sfx = require "src.sfx"
local Profile = require "src.profile"
local S = require "src.ui.state"
local flair = require "src.ui.flair"
local Title = require "src.ui.title"
local O = require "src.options"
local Lang = require "src.lang"
local tr, trf = Lang.t, Lang.f

local floor, min = math.floor, math.min
local sound = flair.sound

local audio = {}

-- Whether the game is in front: hidden, every sound pauses where it is.
audio.shown = { focus = true, visible = true }

-- How loud: 1, 0.5 or 0 (the V key goes round them), kept between runs.
function audio.save() Profile.sound = Sfx.level; Profile.save() end

-- A tick when the pointer comes onto something that can be pressed (never
-- for a finger, which has no hover).
function audio.hover()
    local k = S.hover.button or S.hover.wave or S.hover.turn or (S.hover.up and S.hover.up.branch + 100) or S.hover.mutation
        or S.hover.level or S.hover.challenge or S.hover.sound or S.hover.species or S.hover.back or S.hover.go or S.hover.enemy
        or S.hover.bring or S.hover.weather or S.hover.won or (S.hover.buy and "buy") or (S.hover.on and "on") or S.hover.home
        or S.hover.pause or (S.hover.tab and "tab" .. S.hover.tab) or (S.hover.opt and S.hover.opt.key) or S.hover.bind or S.hover.btn
        or S.hover.credits
    if k ~= nil then k = tostring(k) .. (S.hover.up and "u" or S.hover.mutation and "m" or S.hover.level and "l" or S.hover.home and "h" or S.hover.sound and "s" or "") end
    if k and k ~= flair.lastHover and not S.touch then sound("hover") end
    flair.lastHover = k
end

-- A short buzz on a phone for what is felt as well as heard, if the
-- settings leave haptics on: seconds of it, by cue.
local BUZZ = { build = 0.02, cut = 0.04, boss = 0.15, heart = 0.06, lost = 0.25, won = 0.12 }

-- What the game cued this frame, played from where on the screen it happened:
-- panned across, and quieter off the edge.
function audio.hear()
    for _, c in ipairs(S.game.cues) do
        local pan, vol = 0, c.vol or 1
        if c.x then
            local i, j = S.world:toImage(c.x, S.world:groundAt(c.x, c.z), c.z)
            local sx, sy = (i - floor(S.camx)) / S.cw, (j - floor(S.camy)) / S.ch
            pan = sx * 2 - 1
            if sx < -0.05 or sx > 1.05 or sy < -0.05 or sy > 1.05 then vol = vol * 0.35 end
        end
        Sfx.play(c.name, pan, vol)
        if BUZZ[c.name] and O.MOBILE and O.get("haptics") and love.system.vibrate then love.system.vibrate(BUZZ[c.name]) end
        -- Some say so in words too.
        local n = c.name
        if n == "wave" then
            local w = S.game.weather and D.WEATHER[S.game.weather]
            flair.banner = { text = trf("WAVE %s", S.game.wave), sub = w and w.name .. ": " .. w.blurb, k = "r", t = 2.2, max = 2.2 }
        elseif n == "clear" then
            flair.banner = { text = trf("WAVE %s CLEARED", S.game.cleared), k = "g", t = 1.8, max = 1.8 }
        elseif n == "unlock" and S.game.newSpecies then
            flair.banner = { text = trf("NEW SPECIES: %s", D.TOWER[S.game.newSpecies].name), k = "l", t = 2.4, max = 2.4 }
        elseif n == "ring" then
            flair.banner = { text = tr("A FAIRY RING CLOSES"), sub = tr("TOWERS IN IT HIT HARDER. ENEMIES IN IT WADE"), k = "l", t = 2.2, max = 2.2 }
        end
    end
    S.game.cues = {}
end

-- The loops under it all: the soil always, the network's hum as loud as it is
-- alive (and higher the more it carries), the weather's own.
function audio.ambience(dt)
    local want = { soil = 0.35 }
    local pitch
    if S.menu == "title" or S.menu == "home" or S.menu == "settings" or S.menu == "credits" or S.menu == "ending" then
        -- The night over the title, and the network's hum swelling as it grows.
        local age = flair.now() - (Title.t0 or 0)
        want.night, want.hum = 0.3, 0.35 * min(1, age / 4)
        pitch = 0.9 + 0.2 * min(1, age / 6)
    elseif S.game and not S.menu and not S.painter then
        local living, surge = 0, false
        for _, l in ipairs(S.game.links) do
            if l.state == "alive" and l.a.conn then living = living + 1 end
            if l.surge then surge = true end
        end
        want.hum = min(0.5, living * 0.035) * (S.game.phase == "wave" and 1 or 0.6)
        pitch = 0.9 + 0.2 * min(1, living / 24) + (surge and 0.15 or 0)
        local w = S.game.weather
        if w == "rain" then want.rain = 0.5
        elseif w == "drought" then want.wind = 0.5
        elseif w == "night" then want.night = 0.4
        elseif w == "frost" then want.frost = 0.45; want.wind = 0.2 end
        if S.paused then for k, v in pairs(want) do want[k] = v * 0.4 end end
    end
    Sfx.update(dt, want, pitch)
end

return audio

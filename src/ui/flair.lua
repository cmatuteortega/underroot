-- What is laid over whatever screen is up, the HUD's own sounds, and the
-- weather coming and going on the board.

local T = require "src.tracer"
local Font = require "src.font"
local Sfx = require "src.sfx"
local S = require "src.ui.state"
local Draw = require "src.ui.draw"

local floor, max, min = math.floor, math.max, math.min
local IDX = T.IDX
local color, text, centred = Draw.color, Draw.text, Draw.centred
local TOP = S.TOP

-- The HUD's own flourishes: the last thing pressed lighting up, the nutrients
-- going red when they fall short (bright when a lot comes in at once), the
-- edge of the screen going red when the sprout is hit, and a word across the
-- screen when a wave comes or goes.
--   pressed  { t, rect }: the thing just pressed, and how to find its box
--   nut      { t, k }: the nutrients' flash
--   hurt     seconds of red edge left
--   banner   { text, sub, k, t, max }
--   note     seconds left of the word saying how loud the sound is now
--   beat     the sprout's heartbeat, when it is low
local flair = { nut = { t = 0, k = "l" }, hurt = 0, note = 0, lastNut = 0 }
-- The screen's own dice (a shake, a cloud's flicker), apart from the rules'
-- and the sound's, so a scripted run draws the same pictures every time.
flair.dice = love.math.newRandomGenerator(5)
-- The weather coming in or going: the board's picture for the old sky giving
-- way to the new one's a few more pixels a frame, so nothing is ever blended.
-- `from` and `to` are weather kinds or false (clear), `t` the seconds since the
-- change, `time` how long this one takes and `w` the weather whose way of
-- arriving it is (`out`: going, so the same way backwards).
flair.sky = { from = false, to = false, t = 0, time = 1, w = "night", out = false }
-- How each weather settles on the board. Night falls evenly, an ordered dither
-- all over. Rain, frost and drought come in patches: the first wet spots, the
-- first drifts of snow, the first dry earth, then more round them until the
-- ground is covered, and they go the same way backwards, the last spots to
-- come in the first to go. `blob` is a patch's size in board pixels, `rough`
-- how much the patches lead over the plain dither (the dither always
-- breaks up their edges), `lag` how much of the change passes before the
-- ground starts to turn (the rain is falling a moment before anything is wet).
flair.sky.STYLE = {
    night = { time = 2.5, blob = 1, rough = 0, lag = 0, seed = 0 },
    rain = { time = 4.5, blob = 10, rough = 0.75, lag = 0.2, seed = 1 },
    frost = { time = 5.5, blob = 7, rough = 0.7, lag = 0.25, seed = 2 },
    drought = { time = 4.5, blob = 16, rough = 0.7, lag = 0.1, seed = 3 },
}

-- The sky is now `to`: start the change from what mostly shows.
function flair.sky.change(to)
    local from = flair.sky.t >= flair.sky.time / 2 and flair.sky.to or flair.sky.from
    local w = (to and to ~= "night" and to) or (from and from ~= "night" and from) or "night"
    flair.sky.from, flair.sky.to, flair.sky.t = from, to, 0
    flair.sky.w, flair.sky.out, flair.sky.time = w, w ~= to, flair.sky.STYLE[w].time
end

-- A sound of the HUD's: not anywhere on the board, so dead centre.
local function sound(name, pitch) Sfx.play(name, 0, 1, pitch) end

-- Not allowed, or not enough: a buzz, and the nutrients flash red.
local function deny()
    sound("deny")
    flair.nut = { t = 0.4, k = "r" }
end

-- The clock the screen's own animations run on: the script's, when there is one.
function flair.now() return S.script and S.script.now() or love.timer.getTime() end

-- Draws the board's picture `img` over another, a pixel where it has come in
-- and none where it has not: `amount` 0 none of it, 1 all of it. Which pixels
-- come first is the weather's: an 8x8 Bayer dither (64 even steps, for
-- night), or patches of value noise that grow, their edges broken up by the
-- same dither. All of it pinned to the picture's own pixels, so it holds
-- still under a pan or a shake. Every pixel is the one picture's or the
-- other's: chosen, never mixed. False if the shader will not build, and the
-- sky just changes.
function flair.sky.draw(img, x, y, amount)
    if flair.sky.shader == nil then
        local ok, sh = pcall(love.graphics.newShader, [[
            extern vec2 size;
            extern float amount, blob, rough, seed, back;
            float bayer2(vec2 b) { return 2.0 * abs(b.x - b.y) + b.y; }
            float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.0) * 43758.5453); }
            float noise(vec2 p) {
                vec2 i = floor(p), f = fract(p);
                f = f * f * (3.0 - 2.0 * f);
                return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
                           mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
            }
            vec4 effect(vec4 colour, Image tex, vec2 uv, vec2 sc) {
                vec2 p = floor(uv * size);
                float b = (16.0 * bayer2(mod(p, 2.0))
                        + 4.0 * bayer2(mod(floor(p / 2.0), 2.0))
                        + bayer2(mod(floor(p / 4.0), 2.0)) + 0.5) / 64.0;
                float n = 0.65 * noise(p / blob) + 0.35 * noise(p / (blob * 0.4) + 19.0);
                n = clamp((n - 0.2) / 0.6, 0.0, 1.0);
                if (back > 0.5) n = 1.0 - n;
                if (mix(b, n, rough) >= amount) discard;
                return Texel(tex, uv) * colour;
            }
        ]])
        flair.sky.shader = ok and sh or false
    end
    local dither = flair.sky.shader
    if not dither then return false end
    local st = flair.sky.STYLE[flair.sky.w]
    dither:send("size", { img:getDimensions() })
    dither:send("amount", amount)
    dither:send("blob", st.blob)
    dither:send("rough", st.rough)
    dither:send("seed", st.seed)
    -- Going, the same patches backwards: the new picture comes in where the
    -- old weather came in last.
    dither:send("back", flair.sky.out and 1 or 0)
    love.graphics.setShader(dither)
    love.graphics.draw(img, x, y)
    love.graphics.setShader()
    return true
end

function flair.loading()
    love.graphics.clear(unpack(T.RGB[IDX.o]))
    local s = "GROWING " .. S.level.name
    local w = 80
    local x, y = floor((S.vw - w) / 2), floor(S.vh / 2)
    text(s, floor((S.vw - Font.width(s)) / 2), y - 10, "t")
    color("u")
    love.graphics.rectangle("fill", x, y, w, 4)
    color("c")
    love.graphics.rectangle("fill", x, y, floor(w * S.progress), 4)
end

-- Over whatever screen is up: the thing just pressed lit, the screen's edge
-- red when the sprout is hit (and on each heartbeat when it is low), a word
-- when a wave comes or goes, and how loud the sound is when V changes it.
function flair.draw()
    if S.painter then return end
    local function px(x, y, w, h) love.graphics.rectangle("fill", x, y, w or 1, h or 1) end
    if not S.menu and S.game and (flair.hurt > 0 or flair.beat) then
        local deep = flair.hurt > 0.2 and 4 or 2
        color("r")
        for d = 0, deep - 1 do
            local step = d + 1
            for x = (d % step), S.vw - 1, step do px(x, d); px(x, S.vh - 1 - d) end
            for y = (d % step), S.vh - 1, step do px(d, y); px(S.vw - 1 - d, y) end
        end
    end
    if flair.banner and not S.menu then
        local age = flair.banner.max - flair.banner.t
        if flair.banner.t > 0.3 or floor(flair.banner.t * 12) % 2 == 0 then
            local y = floor(S.vh * 0.28) - floor(max(0, 0.15 - age) / 0.15 * 8)
            centred(flair.banner.text, y, flair.banner.k, "o")
            local w = floor(min(1, age / 0.3) * (Font.width(flair.banner.text) + 4))
            color(flair.banner.k)
            px(floor(S.vw / 2 - w / 2), y + 8, w, 1)
            local sub = flair.banner.sub
            if sub and Font.width(sub) > S.vw - S.inset.l - S.inset.r - 12 then sub = sub:match("^[^:]+") end
            if sub then centred(sub, y + 12, "w", "o") end
        end
    end
    if flair.note > 0 then
        local lv = Sfx.level >= 1 and "LOUD" or (Sfx.level > 0 and "QUIET" or "OFF")
        centred("SOUND " .. lv .. "  (V)", S.inset.t + TOP + 46, Sfx.level > 0 and "l" or "k", "o")
    end
    if flair.pressed and flair.pressed.t > 0 then
        local ok, x, y, w, h = pcall(flair.pressed.rect)
        if ok and x then
            local hot = flair.pressed.t > 0.09
            color(hot and "w" or "l")
            px(x - 2, y - 2, w + 4, 1); px(x - 2, y + h + 1, w + 4, 1)
            px(x - 2, y - 2, 1, h + 4); px(x + w + 1, y - 2, 1, h + 4)
            if hot then
                px(x - 1, y - 1, w + 2, 1); px(x - 1, y + h, w + 2, 1)
                px(x - 1, y - 1, 1, h + 2); px(x + w, y - 1, 1, h + 2)
            end
        end
    end
end

flair.sound, flair.deny = sound, deny

return flair

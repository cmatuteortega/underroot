-- The home screen, past the title: the ground and the sprout gone down, and
-- in the sky they left the four ways on -- the levels, the network, the
-- encyclopedia and the settings. The network, the encyclopedia and the
-- settings come back here.

local Font = require "src.font"
local S = require "src.ui.state"
local Draw = require "src.ui.draw"
local flair = require "src.ui.flair"
local Title = require "src.ui.title"
local codex = require "src.ui.codex"
local Network = require "src.ui.network"
local Settings = require "src.ui.settings"

local floor, max = math.floor, math.max
local box, text, centred, inside = Draw.box, Draw.text, Draw.centred, Draw.inside
local sound = flair.sound

local home = {}

-- The choices, top to bottom, each with its key.
home.CHOICES = {
    { id = "levels", name = "LEVELS", key = "l" },
    { id = "network", name = "NETWORK", key = "n" },
    { id = "codex", name = "ENCYCLOPEDIA", key = "e" },
    { id = "settings", name = "SETTINGS", key = "s" },
}
home.STAGGER = 0.08 -- seconds between one choice coming up and the next

-- Seconds since the ground started down; the choices come up once it is
-- there, one after another.
local function age() return flair.now() - (Title.down or -1e9) end
local function shown(k) return Title.f.drop >= 1 and age() >= Title.DROP_TIME + (k - 1) * home.STAGGER end

-- A box a choice, down the middle between the lettering and the sprout; two
-- by two where a column will not fit.
function home.layout()
    local _, _, _, top, bottom = Title.marks()
    local W, H, gap = 96, 16, 4
    local n = #home.CHOICES
    local cols = (bottom - top - 8) >= n * H + (n - 1) * gap and 1 or 2
    local rows = math.ceil(n / cols)
    local y0 = floor(top + max(0, (bottom - top) - (rows * H + (rows - 1) * gap)) / 2)
    local x0 = floor((S.vw - (cols * W + (cols - 1) * gap)) / 2)
    local L = {}
    for k = 1, n do
        local row, col = floor((k - 1) / cols), (k - 1) % cols
        L[k] = { x = x0 + col * (W + gap), y = y0 + row * (H + gap), w = W, h = H, n = k }
    end
    return L
end

function home.choose(k)
    local c = home.CHOICES[k]
    if not c or not shown(#home.CHOICES) then return end
    if c.id == "levels" then sound("select"); S.openMenu()
    elseif c.id == "network" then Network.open()
    elseif c.id == "codex" then codex.open()
    elseif c.id == "settings" then Settings.open() end
end

home.backdrop = Title.backdrop

function home.draw()
    for k, c in ipairs(home.layout()) do
        if shown(k) then
            local ch = home.CHOICES[k]
            local on = S.hover.home == k
            local s, edge, ink = ch.name, on and "t" or "c", "w"
            -- The network's lit while there are spores for something on it.
            if ch.id == "network" then
                local ready = Network.ready()
                if ready > 0 then s, edge, ink = s .. " " .. ready, on and "t" or "g", "g" end
            end
            box(c.x, c.y, c.w, c.h, on and "n" or "u", edge)
            text(s, c.x + floor((c.w - Font.width(s)) / 2), c.y + 6, ink)
        end
    end
    if shown(#home.CHOICES) and not S.touch then
        centred("L N E S OR CLICK ONE", S.vh - S.inset.b - 12, "s", "o")
    end
end

function home.hover(mx, my)
    if not shown(#home.CHOICES) then return end
    for k, c in ipairs(home.layout()) do
        if inside(mx, my, c.x, c.y, c.w, c.h) then S.hover.home = k return end
    end
end

function home.under()
    local k = S.hover.home
    if k then return function() local c = home.layout()[k] return c.x, c.y, c.w, c.h end end
end

function home.click(b)
    if S.hover.home then home.choose(S.hover.home) end
end

function home.key(key)
    for k, c in ipairs(home.CHOICES) do
        if key == c.key or key == tostring(k) then home.choose(k) return end
    end
    if key == "escape" then sound("back"); Title.open() end
end

return home

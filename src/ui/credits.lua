-- The credits: who and what made the game, rolling up over the night from
-- the home screen's corner, and at the end of the ending (src/ui/ending.lua),
-- which rolls the same lines. Once the last level is won, a button here
-- plays the ending again.

local D = require "src.defs"
local Font = require "src.font"
local Profile = require "src.profile"
local V = require "src.version"
local S = require "src.ui.state"
local Draw = require "src.ui.draw"
local flair = require "src.ui.flair"
local Title = require "src.ui.title"
local tr = require("src.lang").t

local floor, max = math.floor, math.max
local box, text, inside = Draw.box, Draw.text, Draw.inside
local sound = flair.sound

local credits = {}

-- Each { head, name, ... }: a head in teal and the names under it, or
-- a line on its own (`big` the game's name, `gap` a space).
credits.LINES = {
    { big = "MYCELIO TD" },
    { line = "A TOWER DEFENSE UNDER A SPROUT" },
    { gap = 20 },
    { "MADE BY", "CMATUTE" },
    { "FROM THE DESIGN DOC OF", "13 OCTOBER 2026" },
    { "THE 3D METHOD", "SURVIVE SCHOOL" },
    { "THE WORLD PAINTER", "THE FROG PROTOTYPE" },
    { "THE LETTERS", "SURVIVE SCHOOL'S 3X5 FACE" },
    { "THE BOARD'S TILES", "A PAINTED ISOMETRIC TILESET" },
    { "EVERY SOUND", "MADE FROM NOTHING AS THE GAME STARTS" },
    { "MADE WITH", "LOVE (LOVE2D.ORG)" },
    { gap = 20 },
    { "THE GARDEN" },
    -- The levels, filled in below.
    { gap = 20 },
    { line = "THANK YOU FOR PLAYING" },
}
for _, l in ipairs(credits.LINES) do
    if l[1] == "THE GARDEN" then for _, level in ipairs(D.LEVELS) do l[#l + 1] = level.name end end
end

local STEP, HEAD, GAP = 8, 9, 10 -- a name's line, a head's, the space after a group

-- The roll's height, from its first line to its last.
function credits.height()
    local h = 0
    for _, l in ipairs(credits.LINES) do
        if l.big then h = h + 18
        elseif l.line then h = h + STEP + 4
        elseif l.gap then h = h + l.gap
        else h = h + HEAD + (#l - 1) * STEP + GAP end
    end
    return h
end

-- The roll drawn with its first line at `y`, centred across the screen;
-- lines off the screen are skipped.
function credits.roll(y)
    local function centre(s, yy, k)
        s = tr(s)
        if yy > -8 and yy < S.vh then text(s, floor((S.vw - Font.width(s)) / 2), yy, k) end
    end
    for _, l in ipairs(credits.LINES) do
        if l.big then
            local s = max(1, math.min(3, floor((S.vw - 16) / Font.width(l.big))))
            if y > -6 * s and y < S.vh then
                love.graphics.push()
                love.graphics.translate(floor((S.vw - Font.width(l.big) * s) / 2), y)
                love.graphics.scale(s, s)
                Draw.color("c")
                Font.print(l.big, 0, 1)
                Draw.color("l")
                Font.print(l.big, 0, 0)
                love.graphics.pop()
            end
            y = y + 18
        elseif l.line then
            centre(l.line, y, "w")
            y = y + STEP + 4
        elseif l.gap then
            y = y + l.gap
        else
            centre(l[1], y, "t")
            y = y + HEAD
            for n = 2, #l do centre(l[n], y, "w"); y = y + STEP end
            y = y + GAP
        end
    end
    return y
end

--- the screen, from the home screen ---------------------------------------------------------

credits.SPEED = 22 -- pixels a second the roll goes up

function credits.open()
    S.menu = "credits"
    credits.t0 = flair.now()
    sound("panel")
end

function credits.close()
    sound("back")
    S.openHome()
end

-- Where the roll is: from just under the bottom of the screen, up until its
-- last line sits in the middle, and held there.
local function rollY()
    local y = S.vh - (flair.now() - (credits.t0 or 0)) * credits.SPEED
    return floor(max(y, floor(S.vh / 2) - credits.height() + 8))
end

-- The last level won: the ending can be seen again.
local function canEnd() return Profile.won[D.LEVELS[#D.LEVELS].id] end

function credits.layout()
    local L = { back = { x = S.inset.l + 4, y = S.inset.t + 4, w = 34, h = 12 } }
    if canEnd() then
        local w = Font.width(tr("THE ENDING")) + 12
        L.ending = { x = S.vw - S.inset.r - 4 - w, y = S.inset.t + 4, w = w, h = 12 }
    end
    return L
end

credits.backdrop = Title.backdrop

function credits.draw()
    credits.roll(rollY())
    local L = credits.layout()
    for _, b in ipairs({ { L.back, "BACK", S.hover.back }, { L.ending, "THE ENDING", S.hover.credits == "ending" } }) do
        local r = b[1]
        if r then
            box(r.x, r.y, r.w, r.h, b[3] and "n" or "u", b[3] and "t" or "k")
            local s = tr(b[2])
            text(s, r.x + floor((r.w - Font.width(s)) / 2), r.y + 4, "w")
        end
    end
    text(V.text, S.vw - S.inset.r - Font.width(V.text) - 3, S.vh - S.inset.b - 8, "k")
end

function credits.hover(mx, my)
    local L = credits.layout()
    if inside(mx, my, L.back.x, L.back.y, L.back.w, L.back.h) then S.hover.back = true return end
    local e = L.ending
    if e and inside(mx, my, e.x, e.y, e.w, e.h) then S.hover.credits = "ending" end
end

function credits.under()
    if S.hover.back then return function() local b = credits.layout().back return b.x, b.y, b.w, b.h end end
    if S.hover.credits then
        return function()
            local e = credits.layout().ending
            if e then return e.x, e.y, e.w, e.h end
            return 0, 0, 0, 0
        end
    end
end

function credits.click(b)
    if b == 2 or S.hover.back then credits.close()
    elseif S.hover.credits == "ending" then require("src.ui.ending").open()
    else
        -- A tap anywhere else sends the roll on ahead.
        credits.t0 = (credits.t0 or flair.now()) - 3
    end
end

function credits.key(key)
    if key == "escape" or key == "backspace" then credits.close()
    elseif key == "space" or key == "down" then credits.t0 = (credits.t0 or flair.now()) - 3
    elseif key == "up" then credits.t0 = (credits.t0 or flair.now()) + 3 end
end

return credits

-- The pause menu, over a run held still: RESUME, RESTART, SETTINGS,
-- ENCYCLOPEDIA, QUIT TO MENU. RESTART asks first, since the run so far is
-- lost; QUIT TO MENU keeps the run for CONTINUE on the home screen, so it
-- does not. Opened by P or back (Esc), the top bar on a phone, and by
-- itself when the game goes to the background (main.lua's love.focus). The
-- settings and the encyclopedia opened from here come back here (S.back).

local T = require "src.tracer"
local Font = require "src.font"
local S = require "src.ui.state"
local Draw = require "src.ui.draw"
local flair = require "src.ui.flair"
local Run = require "src.ui.run"
local codex = require "src.ui.codex"
local Settings = require "src.ui.settings"
local O = require "src.options"
local Lang = require "src.lang"

local floor = math.floor
local box, text, centred, inside = Draw.box, Draw.text, Draw.centred, Draw.inside
local sound = flair.sound
local tr, trf = Lang.t, Lang.f

local pause = {}

pause.ITEMS = {
    { id = "resume", name = "RESUME" },
    { id = "restart", name = "RESTART" },
    { id = "settings", name = "SETTINGS" },
    { id = "codex", name = "ENCYCLOPEDIA" },
    { id = "quit", name = "QUIT TO MENU" },
}
pause.ask = nil -- "restart" while it waits on a yes

-- Is it up: a run paused that is not over.
function pause.shown()
    local g = S.game
    return S.paused and g and not S.menu and not S.script and g.phase ~= "won" and g.phase ~= "lost"
end

function pause.open()
    if S.paused or not S.game then return end
    S.paused, pause.ask = true, nil
    sound("pause")
end

function pause.close()
    S.paused, pause.ask = false, nil
    sound("unpause")
end

-- The box in the middle: its head, then a button a line; or, asking, the
-- question and YES / NO side by side.
local W, BH, GAP = 104, 15, 4
function pause.layout()
    local L = { buttons = {} }
    if pause.ask then
        L.w, L.h = 150, 58
    else
        L.w, L.h = W + 16, 24 + #pause.ITEMS * (BH + GAP) + 4
    end
    L.x, L.y = floor((S.vw - L.w) / 2), floor((S.vh - L.h) / 2)
    if pause.ask then
        local bw = 50
        L.buttons[1] = { id = "yes", name = "YES, RESTART", x = L.x + 8, y = L.y + L.h - BH - 8, w = bw + 16, h = BH }
        L.buttons[2] = { id = "no", name = "NO", x = L.x + L.w - 8 - bw, y = L.y + L.h - BH - 8, w = bw, h = BH }
    else
        for k, it in ipairs(pause.ITEMS) do
            L.buttons[k] = { id = it.id, name = it.name, x = L.x + 8, y = L.y + 22 + (k - 1) * (BH + GAP), w = W, h = BH }
        end
    end
    return L
end

-- Every other pixel of the screen gone to the night's darkest, so the run
-- shows through held still: one picture a screen size, laid over the HUD.
local veil
local function drawVeil()
    if not veil or veil:getWidth() ~= S.vw or veil:getHeight() ~= S.vh then
        local data = love.image.newImageData(S.vw, S.vh)
        local c = T.RGB[T.IDX.o]
        data:mapPixel(function(x, y)
            if (x + y) % 2 == 0 then return c[1], c[2], c[3], 1 end
            return 0, 0, 0, 0
        end)
        veil = love.graphics.newImage(data)
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(veil, 0, 0)
end

function pause.draw()
    drawVeil()
    local L = pause.layout()
    box(L.x, L.y, L.w, L.h, "u", "c")
    if pause.ask then
        text(tr("RESTART THE LEVEL?"), L.x + 8, L.y + 8, "l")
        text(tr("THIS RUN SO FAR IS LOST."), L.x + 8, L.y + 18, "w")
    else
        local head = tr("PAUSED")
        text(head, L.x + floor((L.w - Font.width(head)) / 2), L.y + 6, "l")
        local w = S.game.endless and trf("ENDLESS WAVE %s", S.game.wave) or trf("WAVE %s/%s", S.game.wave, #S.game.waves)
        local s = S.level.name .. "  " .. w
        if Font.width(s) > L.w - 8 then s = w end
        text(s, L.x + floor((L.w - Font.width(s)) / 2), L.y + 13, "s")
    end
    for _, b in ipairs(L.buttons) do
        local on = S.hover.pause == b.id
        local warn = b.id == "yes"
        box(b.x, b.y, b.w, b.h, on and "n" or "u", on and "t" or (warn and "r" or "c"))
        local name = tr(b.name)
        text(name, b.x + floor((b.w - Font.width(name)) / 2), b.y + 5, warn and "r" or "w")
    end
    if not S.touch and not pause.ask then
        centred(trf("ESC OR %s TO RESUME", O.label("p")), L.y + L.h + 6, "s", "o")
    end
end

function pause.hover(mx, my)
    for _, b in ipairs(pause.layout().buttons) do
        if inside(mx, my, b.x, b.y, b.w, b.h) then S.hover.pause = b.id return end
    end
end

function pause.under()
    local id = S.hover.pause
    return function()
        for _, b in ipairs(pause.layout().buttons) do if b.id == id then return b.x, b.y, b.w, b.h end end
        return 0, 0, 0, 0
    end
end

function pause.act(id)
    if id == "resume" then pause.close()
    elseif id == "restart" then pause.ask = "restart"; sound("panel")
    elseif id == "no" then pause.ask = nil; sound("back")
    elseif id == "yes" then
        S.paused, pause.ask = false, nil
        sound("go")
        Run.start()
    elseif id == "settings" then S.fromRun = true; Settings.open()
    elseif id == "codex" then S.fromRun = true; codex.open()
    elseif id == "quit" then
        -- Kept as it stands: CONTINUE picks it up, paused, right here.
        Run.keep()
        sound("back")
        S.openHome()
    end
end

function pause.click(b)
    if b == 2 then
        if pause.ask then pause.act("no") else pause.close() end
        return
    end
    if S.hover.pause then pause.act(S.hover.pause) end
end

-- `key` as pressed, `as` what the moved keys make of it (src/options.lua).
function pause.key(key, as)
    if key == "escape" or key == "backspace" then
        if pause.ask then pause.act("no") else pause.close() end
    elseif as == "p" and not pause.ask then pause.close()
    elseif key == "return" or key == "space" then pause.act(pause.ask and "yes" or "resume")
    elseif pause.ask and (key == "y") then pause.act("yes")
    elseif pause.ask and (key == "n") then pause.act("no")
    end
end

return pause

-- The settings, in sections, over the same night as the home screen: a tab a
-- section across the top (AUDIO, GAMEPLAY, COMFORT, DISPLAY, and on a
-- computer KEYS), and under it a row a setting, its choices to press. What
-- each one is and where it starts is src/options.lua; this screen shows them,
-- keeps them, and puts each to work the moment it changes (settings.apply).
-- Opened from the home screen, back goes there; from a run's pause menu,
-- back to the run (S.back).

local D = require "src.defs"
local Font = require "src.font"
local Sfx = require "src.sfx"
local O = require "src.options"
local S = require "src.ui.state"
local Draw = require "src.ui.draw"
local flair = require "src.ui.flair"
local audio = require "src.ui.audio"
local Title = require "src.ui.title"
local View = require "src.ui.view"
local Profile = require "src.profile"
local Lang = require "src.lang"

local floor, max, min = math.floor, math.max, math.min
local box, text, inside, centred = Draw.box, Draw.text, Draw.inside, Draw.centred
local tr = Lang.t
local sound = flair.sound

local settings = {}

settings.tab = 1 -- the section up, of O.sections()
settings.cursor = nil -- the row the arrow keys are on, of the section's rows
settings.listen = nil -- the key action waiting for its new key

function settings.open()
    S.menu = "settings"
    settings.listen = nil
    sound("panel")
end

function settings.close()
    sound("back")
    settings.listen = nil
    S.back()
end

--- what each setting does --------------------------------------------------------------------

-- The window as the settings have it: fullscreen on the display's own mode,
-- or a window of the size picked (no bigger than the display).
local function window()
    if not love.window or O.MOBILE then return end
    if O.get("window") == "full" then
        if not love.window.getFullscreen() then love.window.setFullscreen(true, "desktop") end
    else
        local w, h = O.get("size"):match("(%d+)x(%d+)")
        w, h = tonumber(w), tonumber(h)
        local dw, dh = love.window.getDesktopDimensions()
        if dw and dw > 0 then w, h = min(w, dw), min(h, dh) end
        love.window.setMode(w, h, { fullscreen = false, resizable = true, highdpi = true, usedpiscale = false,
            vsync = O.get("vsync") and 1 or 0 })
    end
    View.fit()
    if S.world and S.game then View.centre() end
end

-- The setting `id` put to work, as it is now.
function settings.apply(id)
    local v = id ~= "tutorial" and O.ROW[id] and not O.ROW[id].profile and O.get(id)
    if id == "effects" then Sfx.effects = v
    elseif id == "ambience" then Sfx.ambience = v
    elseif id == "text" then
        View.fit()
        if S.world and S.game then View.centre() end
    elseif id == "window" or id == "size" then window()
    elseif id == "vsync" then if love.window and love.window.setVSync then love.window.setVSync(v and 1 or 0) end
    elseif id == "language" then
        Lang.set(v)
        require("src.ui.codex").init()
        if S.game then require("src.ui.toolbar").layTools(S.game) end
    end
end

-- All of them, once, as the game opens. The window only if it is not as
-- conf.lua opened it.
function settings.applyAll()
    for _, id in ipairs({ "effects", "ambience", "text" }) do settings.apply(id) end
    -- (The language is set by main.lua, before anything is drawn.)
    if not O.MOBILE then
        if O.get("window") ~= "full" then window() end
        if not O.get("vsync") then settings.apply("vsync") end
    end
end

-- A row's value now: its own, or the profile's line for the two that have one.
local function current(row)
    if row.id == "sound" then return Sfx.level end
    if row.id == "tips" then return Profile.tips end
    return O.get(row.id)
end

local function choose(row, k)
    local c = row.choices[k]
    if not c then return end
    if row.id == "sound" then
        Sfx.level = c.v
        audio.save()
    elseif row.id == "tips" then
        Profile.tips = c.v
        Profile.save()
    else
        O.set(row.id, c.v)
        Profile.save()
        settings.apply(row.id)
    end
    sound((c.v == false or c.v == 0) and "off" or "on")
end

-- F11 / alt+enter changed it: the setting follows.
function settings.toggleFullscreen()
    local full = not love.window.getFullscreen()
    O.set("window", full and "full" or "window")
    Profile.save()
    if full then love.window.setFullscreen(true, "desktop") else window() end
    View.fit()
end

--- the screen --------------------------------------------------------------------------------

local function section() return O.sections()[settings.tab] or O.sections()[1] end

-- The rows the section up shows: the keys' (one an action, and putting them
-- all back), or its settings, less the tutorial when this is a run's.
local function rows()
    local s = section()
    local list = {}
    if s.keys then
        for _, k in ipairs(O.KEYS) do list[#list + 1] = { id = k.id, name = tr(k.name), bind = true } end
        list[#list + 1] = { id = "unbind", name = tr("PUT EVERY KEY BACK"), button = true }
        return list
    end
    -- Each in the language up: a copy of the row, with its words in it.
    for _, r in ipairs(O.rows(s)) do
        if not (r.id == "tutorial" and S.fromRun) then
            local row = setmetatable({ name = tr(r.name) }, { __index = r })
            if r.choices then
                row.choices = {}
                for k, c in ipairs(r.choices) do row.choices[k] = { v = c.v, name = tr(c.name) } end
            end
            list[#list + 1] = row
        end
    end
    return list
end

local H = 13 -- a choice's height
local SLIDE_W, SLIDE_GAP = 9, 2 -- a slider's bars

-- How wide each choice of a row is.
local function widths(r)
    if r.button then return { Font.width(r.name) + 12 } end
    if r.bind then return { 44 } end
    local out = {}
    if r.slider then
        for k = 1, #r.choices do out[k] = SLIDE_W end
        return out
    end
    for k, c in ipairs(r.choices) do out[k] = max(26, Font.width(c.name) + 8) end
    return out
end
local function span(ws, gap)
    local w = 0
    for k, x in ipairs(ws) do w = w + x + (k > 1 and gap or 0) end
    return w
end

-- Where everything goes: BACK top left, the tabs beside it (or under it, on a
-- narrow screen), then the rows -- the name at the left and the choices
-- beside it where there is room, the name over its choices where there is
-- not, and two columns of them for the keys on a wide screen.
function settings.layout()
    local L = { back = { x = S.inset.l + 4, y = S.inset.t + 4, w = 34, h = 12 }, tabs = {}, rows = {} }
    local secs = O.sections()
    local tws, gap = {}, 3
    for k, s in ipairs(secs) do tws[k] = Font.width(tr(s.name)) + 8 end
    local total = span(tws, gap)
    local x0, ty
    local right = L.back.x + L.back.w + 6
    if right + total <= S.vw - S.inset.r - 4 then
        x0, ty = max(right, floor((S.vw - total) / 2)), L.back.y
    else
        x0, ty = floor((S.vw - total) / 2), L.back.y + L.back.h + 5
    end
    for k, w in ipairs(tws) do
        L.tabs[k] = { x = x0, y = ty, w = w, h = 12 }
        x0 = x0 + w + gap
    end
    local top = ty + 12 + 10
    local _, _, _, _, bottom = Title.marks()
    bottom = max(top + 40, bottom - 2)
    local list = rows()
    local avail = S.vw - S.inset.l - S.inset.r - 16
    -- The names' column, as wide as the widest name.
    local nameW, choiceW = 0, 0
    for _, r in ipairs(list) do
        if not r.button then nameW = max(nameW, Font.width(r.name)) end
        choiceW = max(choiceW, span(widths(r), 3) + (r.slider and 20 or 0))
    end
    local cols = section().keys and avail >= 2 * (nameW + 8 + choiceW) + 16 and 2 or 1
    local beside = avail >= cols * (nameW + 8 + choiceW) + (cols - 1) * 16
    local per = math.ceil(#list / cols)
    local rowH = beside and H + 5 or H + 14
    if per * rowH > bottom - top then rowH = max(beside and H + 2 or H + 10, floor((bottom - top) / per)) end
    local colW = nameW + 8 + choiceW
    local left = floor((S.vw - (cols * colW + (cols - 1) * 16)) / 2)
    local y0 = top + max(0, floor((bottom - top - per * rowH) / 2))
    for n, r in ipairs(list) do
        local col = floor((n - 1) / per)
        local cx = left + col * (colW + 16)
        local y = y0 + ((n - 1) % per) * rowH
        local ws = widths(r)
        local R = { row = r, n = n, choices = {} }
        local cw = span(ws, r.slider and SLIDE_GAP or 3)
        local x
        if r.button then
            x = beside and cx or floor((S.vw - cw) / 2)
            R.name = nil
        elseif beside then
            R.name = { x = cx, y = y + 4 }
            x = cx + nameW + 8
        else
            R.name = { x = floor((S.vw - Font.width(r.name)) / 2), y = y }
            x = floor((S.vw - cw - (r.slider and 20 or 0)) / 2)
            y = y + 8
        end
        for k, w in ipairs(ws) do
            R.choices[k] = { x = x, y = y, w = w, h = H }
            x = x + w + (r.slider and SLIDE_GAP or 3)
        end
        R.after = x + 3
        L.rows[n] = R
    end
    return L
end

settings.backdrop = Title.backdrop

-- A slider: bars that grow left to right, lit up to the level chosen; the
-- first one, nothing, a mark of its own.
local function drawSlider(R, chosen)
    local r = R.row
    for k, c in ipairs(R.choices) do
        local on = S.hover.opt and S.hover.opt.n == R.n and S.hover.opt.k == k
        local lit = chosen and k <= chosen and k > 1
        local h = k == 1 and 3 or 3 + floor((c.h - 3) * (k - 1) / (#r.choices - 1))
        box(c.x, c.y + c.h - h, c.w, h, lit and "l" or (on and "n" or "u"), on and "t" or (lit and "c" or "k"))
    end
    local name = chosen and r.choices[chosen].name or ""
    text(chosen == 1 and tr("OFF") or name .. "%", R.after, R.choices[1].y + 4, chosen == 1 and "k" or "w")
end

function settings.draw()
    local L = settings.layout()
    local b = L.back
    box(b.x, b.y, b.w, b.h, S.hover.back and "n" or "u", S.hover.back and "t" or "k")
    text(tr("BACK"), b.x + floor((b.w - Font.width(tr("BACK"))) / 2), b.y + 4, "w")
    for k, t in ipairs(L.tabs) do
        local up, on = k == settings.tab, S.hover.tab == k
        box(t.x, t.y, t.w, t.h, up and "d" or (on and "n" or "u"), up and "l" or (on and "t" or "k"))
        text(tr(O.sections()[k].name), t.x + 4, t.y + 4, up and "l" or "w")
    end
    for _, R in ipairs(L.rows) do
        local r = R.row
        local focus = settings.cursor == R.n
        if R.name then text(r.name, R.name.x, R.name.y, focus and "l" or "t") end
        if r.bind then
            local c = R.choices[1]
            local listening = settings.listen == r.id
            local on = S.hover.bind == r.id
            box(c.x, c.y, c.w, c.h, listening and "d" or (on and "n" or "u"), listening and "l" or (on and "t" or "c"))
            local s = listening and (floor(flair.now() * 3) % 2 == 0 and tr("PRESS") or "") or O.name(O.key(r.id))
            text(s, c.x + floor((c.w - Font.width(s)) / 2), c.y + 5, O.bound[r.id] and "g" or "w")
        elseif r.button then
            local c = R.choices[1]
            local on = S.hover.btn == r.id
            box(c.x, c.y, c.w, c.h, on and "n" or "u", (on or focus) and "t" or "c")
            text(r.name, c.x + 6, c.y + 5, "w")
        else
            local now = current(r)
            local chosen
            for k, c in ipairs(r.choices) do if c.v == now then chosen = k end end
            if r.slider then drawSlider(R, chosen) else
                for k, c in ipairs(R.choices) do
                    local opt = r.choices[k]
                    local picked, on = chosen == k, S.hover.opt and S.hover.opt.n == R.n and S.hover.opt.k == k
                    box(c.x, c.y, c.w, c.h, on and "n" or (picked and "d" or "u"), picked and "g" or (on and "t" or "c"))
                    text(opt.name, c.x + floor((c.w - Font.width(opt.name)) / 2), c.y + 5, picked and "g" or "w")
                end
            end
        end
    end
    -- What a setting needs said of it.
    local note
    if section().keys then
        note = tr(settings.listen and "PRESS THE NEW KEY, ESC TO LEAVE IT" or "CLICK ONE, THEN PRESS ITS NEW KEY")
    elseif section().id == "comfort" and O.get("text") == "large" and S.textStep == 0 then
        note = tr("THE SCREEN IS TOO SMALL FOR LARGE TEXT")
    elseif section().id == "display" and not O.MOBILE and O.get("window") == "full" then
        note = tr("THE WINDOW SIZE IS FOR WHEN IT IS A WINDOW. F11 SWITCHES")
    end
    if note then centred(note, S.vh - S.inset.b - 12, "s", "o") end
end

function settings.hover(mx, my)
    local L = settings.layout()
    if inside(mx, my, L.back.x, L.back.y, L.back.w, L.back.h) then S.hover.back = true return end
    for k, t in ipairs(L.tabs) do
        if inside(mx, my, t.x, t.y, t.w, t.h) then S.hover.tab = k return end
    end
    for _, R in ipairs(L.rows) do
        for k, c in ipairs(R.choices) do
            -- A slider's bars are hit over their whole height.
            if inside(mx, my, c.x - 1, c.y, c.w + 2, c.h) then
                if R.row.bind then S.hover.bind = R.row.id
                elseif R.row.button then S.hover.btn = R.row.id
                else S.hover.opt = { n = R.n, k = k, key = R.row.id .. k } end
                return
            end
        end
    end
end

function settings.under()
    local function rect(f) return function() local r = f(settings.layout()) if r then return r.x, r.y, r.w, r.h end return 0, 0, 0, 0 end end
    if S.hover.back then return rect(function(L) return L.back end) end
    local k = S.hover.tab
    if k then return rect(function(L) return L.tabs[k] end) end
    local o = S.hover.opt
    if o then return rect(function(L) return L.rows[o.n] and L.rows[o.n].choices[o.k] end) end
    local id = S.hover.bind or S.hover.btn
    if id then
        return rect(function(L)
            for _, R in ipairs(L.rows) do if R.row.id == id then return R.choices[1] end end
        end)
    end
end

local function toTab(k)
    local n = #O.sections()
    k = (k - 1) % n + 1
    if k == settings.tab then return end
    settings.tab, settings.cursor, settings.listen = k, nil, nil
    sound("select")
end

local function press(r)
    if r.id == "tutorial" then sound("go"); S.fromRun = nil; require("src.ui.guide").tutorial()
    elseif r.id == "unbind" then
        O.bound = {}
        Profile.save()
        sound("back")
    elseif r.bind then
        settings.listen = settings.listen ~= r.id and r.id or nil
        sound(settings.listen and "panel" or "back")
    end
end

function settings.click(b)
    if b == 2 then
        if settings.listen then settings.listen = nil; sound("back") else settings.close() end
        return
    end
    if S.hover.back then settings.close()
    elseif S.hover.tab then toTab(S.hover.tab)
    elseif S.hover.opt then
        local R = settings.layout().rows[S.hover.opt.n]
        settings.cursor = nil
        if R then choose(R.row, S.hover.opt.k) end
    elseif S.hover.bind or S.hover.btn then
        for _, r in ipairs(rows()) do if r.id == (S.hover.bind or S.hover.btn) then press(r) end end
    elseif settings.listen then settings.listen = nil; sound("back") end
end

-- The species' own keys: nothing else can go on them.
local function speciesKeys()
    local taken = {}
    for _, t in ipairs(D.TOWERS) do if t.key ~= "1" then taken[t.key:lower()] = true end end
    return taken
end

function settings.key(key)
    if settings.listen then
        if key == "escape" then settings.listen = nil; sound("back") return end
        if O.bind(settings.listen, key, speciesKeys()) then
            settings.listen = nil
            Profile.save()
            sound("on")
        else
            flair.deny()
        end
        return
    end
    if key == "escape" or key == "backspace" then settings.close() return end
    if key == "tab" then toTab(settings.tab + (love.keyboard.isDown("lshift", "rshift") and -1 or 1)) return end
    local n = tonumber(key)
    if n and O.sections()[n] then toTab(n) return end
    -- Up and down go along the rows, left and right along a row's choices.
    local list = rows()
    if key == "up" or key == "down" then
        local c = settings.cursor or (key == "down" and 0 or #list + 1)
        settings.cursor = max(1, min(#list, c + (key == "down" and 1 or -1)))
        sound("hover")
        return
    end
    local r = list[settings.cursor or 1]
    if not r then return end
    if r.button or r.bind then
        if key == "space" or key == "return" then press(r) end
        return
    end
    local now = current(r)
    local at = 1
    for k, c in ipairs(r.choices) do if c.v == now then at = k end end
    if key == "left" and at > 1 then choose(r, at - 1)
    elseif key == "right" and at < #r.choices then choose(r, at + 1) end
end

return settings

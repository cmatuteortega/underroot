-- The settings a player sets once and keeps: what each one is, the choices it
-- has and the one it starts on, in the sections the settings screen shows them
-- in (src/ui/settings.lua, which also puts them to work), and the keys a
-- computer can move off their usual places. Kept in save.txt by the profile
-- (src/profile.lua) as two lines, only what differs from where it starts:
--
--   settings effects=0.5 auto=1 text=large
--   keys start=return pause=k
--
-- How loud the sound is overall (`sound`) and the guide's tips (`tips`) keep
-- the lines they had before there were settings; the screen shows them here.

local Lang = require "src.lang"

local O = {}

local OS = love.system and love.system.getOS() or "Linux"
-- A phone or tablet: its own display settings, and no keys to move.
O.MOBILE = OS == "Android" or OS == "iOS"

local ONOFF = { { v = true, name = "ON" }, { v = false, name = "OFF" } }
local OFFON = { { v = false, name = "OFF" }, { v = true, name = "ON" } }
local LEVEL = {}
for k = 0, 4 do LEVEL[#LEVEL + 1] = { v = k / 4, name = tostring(k * 25) } end

-- Each section's rows: `id`, what it says, its `choices` ({ v, name }, left
-- to right; a `slider` draws them as a bar), the one it starts on, and, for
-- some, only on a computer (`desktop`) or a phone (`mobile`). A row with
-- `profile` keeps its value on the profile's own line of that name. A
-- `button` row is something to press, not a choice.
O.SECTIONS = {
    { id = "audio", name = "AUDIO", rows = {
        { id = "sound", name = "SOUND", profile = true, default = 1,
            choices = { { v = 1, name = "LOUD" }, { v = 0.5, name = "QUIET" }, { v = 0, name = "OFF" } } },
        { id = "effects", name = "EFFECTS", slider = true, choices = LEVEL, default = 1 },
        { id = "ambience", name = "AMBIENCE", slider = true, choices = LEVEL, default = 1 },
        { id = "bgmute", name = "MUTE IN THE BACKGROUND", choices = ONOFF, default = true },
    } },
    { id = "play", name = "GAMEPLAY", rows = {
        -- Starts on the system's language, if the game has it (main.lua).
        { id = "language", name = "LANGUAGE", default = "en", choices = {} },
        { id = "speed", name = "WAVES START AT", default = 1,
            choices = { { v = 1, name = "X1" }, { v = 2, name = "X2" }, { v = 3, name = "X3" } } },
        { id = "auto", name = "NEXT WAVE BY ITSELF", choices = OFFON, default = false },
        { id = "confirm", name = "ASK BEFORE CLEARING", choices = OFFON, default = false },
        { id = "ranges", name = "RANGE CIRCLES", default = "pointed",
            choices = { { v = "pointed", name = "POINTED AT" }, { v = "all", name = "EVERY TOWER" } } },
        { id = "tips", name = "TIPS FOR WHAT IS NEW", profile = true, choices = ONOFF, default = true },
        { id = "tutorial", name = "PLAY THE TUTORIAL", button = true },
    } },
    { id = "comfort", name = "COMFORT", rows = {
        { id = "shake", name = "SCREEN SHAKE", choices = ONOFF, default = true },
        { id = "motion", name = "REDUCE MOTION", choices = OFFON, default = false },
        { id = "colour", name = "COLOUR-BLIND MODE", choices = OFFON, default = false },
        { id = "text", name = "TEXT SIZE", default = "normal",
            choices = { { v = "normal", name = "NORMAL" }, { v = "large", name = "LARGE" } } },
    } },
    { id = "display", name = "DISPLAY", rows = {
        { id = "window", name = "SCREEN", desktop = true, default = "full",
            choices = { { v = "full", name = "FULLSCREEN" }, { v = "window", name = "WINDOW" } } },
        { id = "size", name = "WINDOW SIZE", desktop = true, default = "1280x720",
            choices = { { v = "1280x720", name = "1280X720" }, { v = "1600x900", name = "1600X900" },
                { v = "1920x1080", name = "1920X1080" } } },
        { id = "vsync", name = "VSYNC", desktop = true, choices = ONOFF, default = true },
        { id = "cap", name = "FRAME CAP", desktop = true, default = 0,
            choices = { { v = 0, name = "OFF" }, { v = 30, name = "30" }, { v = 60, name = "60" }, { v = 120, name = "120" } } },
        { id = "haptics", name = "HAPTICS", mobile = true, choices = ONOFF, default = true },
        { id = "battery", name = "BATTERY SAVER", mobile = true, choices = OFFON, default = false },
        { id = "hand", name = "TOOLBAR HAND", mobile = true, default = "right",
            choices = { { v = "right", name = "RIGHT" }, { v = "left", name = "LEFT" } } },
    } },
    { id = "keys", name = "KEYS", desktop = true, keys = true, rows = {} },
}

-- The keys that can be moved, in a run: each with the key it is on until it
-- is moved (the one the screen's code listens for).
O.KEYS = {
    { id = "start", name = "START THE WAVE", key = "space" },
    { id = "speed", name = "GAME SPEED", key = "f" },
    { id = "pause", name = "PAUSE", key = "p" },
    { id = "turn", name = "TURN THE BOARD", key = "e" },
    { id = "prune", name = "PRUNE", key = "x" },
    { id = "regrow", name = "REGROW ALL", key = "1" },
    { id = "pulse", name = "SPORE PULSE", key = "q" },
    { id = "left", name = "UPGRADE LEFT", key = "z" },
    { id = "right", name = "UPGRADE RIGHT", key = "c" },
    { id = "up", name = "PAN UP", key = "w" },
    { id = "down", name = "PAN DOWN", key = "s" },
    { id = "west", name = "PAN LEFT", key = "a" },
    { id = "east", name = "PAN RIGHT", key = "d" },
}
O.KEY = {}
for _, k in ipairs(O.KEYS) do O.KEY[k.id] = k end
-- Keys nothing can be moved onto: the ones every screen has (back, sound,
-- fullscreen, zoom), the won and lost screens' and the species'.
O.FIXED = { escape = true, backspace = true, ["return"] = true, f11 = true, v = true, m = true, n = true, r = true,
    ["="] = true, ["+"] = true, ["-"] = true, kpenter = true, ["kp+"] = true, ["kp-"] = true,
    lshift = true, rshift = true, lalt = true, ralt = true, lctrl = true, rctrl = true }

for _, l in ipairs(Lang.LANGS) do
    local c = O.SECTIONS[2].rows[1].choices
    c[#c + 1] = { v = l.code, name = l.name }
end

O.ROW = {}
for _, s in ipairs(O.SECTIONS) do for _, r in ipairs(s.rows) do O.ROW[r.id] = r end end

-- The rows a section shows on this kind of device, and the sections.
local function here(t) return not (t.desktop and O.MOBILE) and not (t.mobile and not O.MOBILE) end
function O.sections()
    local list = {}
    for _, s in ipairs(O.SECTIONS) do if here(s) then list[#list + 1] = s end end
    return list
end
function O.rows(section)
    local list = {}
    for _, r in ipairs(section.rows) do if here(r) then list[#list + 1] = r end end
    return list
end

--- what is set -------------------------------------------------------------------------------

O.values = {} -- id = value, for what is not where it starts
O.bound = {} -- key action id = the key it is moved to

function O.reset()
    O.values, O.bound = {}, {}
end

function O.get(id)
    local v = O.values[id]
    if v == nil then return O.ROW[id].default end
    return v
end

function O.set(id, v)
    if v == O.ROW[id].default then O.values[id] = nil else O.values[id] = v end
end

-- A value as a word in the file, and back by the row's own choices.
local function word(v)
    if v == true then return "1" elseif v == false then return "0" end
    return tostring(v)
end
local function value(row, w)
    for _, c in ipairs(row.choices or {}) do if word(c.v) == w then return c.v, true end end
    return nil, false
end

-- The `settings` line's words (after the first), and the line to write
-- (nil when everything is where it starts).
function O.read(words)
    for k = 2, #words do
        local id, w = words[k]:match("^(.-)=(.*)$")
        local row = id and O.ROW[id]
        if row and not row.profile and not row.button then
            local v, ok = value(row, w)
            if ok then O.set(id, v) end
        end
    end
end
function O.line()
    local parts = {}
    for _, s in ipairs(O.SECTIONS) do
        for _, r in ipairs(s.rows) do
            if O.values[r.id] ~= nil then parts[#parts + 1] = r.id .. "=" .. word(O.values[r.id]) end
        end
    end
    if #parts == 0 then return nil end
    return "settings " .. table.concat(parts, " ")
end

-- The toolbar and the panel mirrored, for a left hand (a phone's setting).
function O.left() return O.MOBILE and O.get("hand") == "left" end

--- the keys ----------------------------------------------------------------------------------

-- The key an action is on now.
function O.key(id) return O.bound[id] or O.KEY[id].key end

-- An action moved to `key`. A key another action is on swaps with it; one
-- that cannot be moved onto (O.FIXED, or a species' own) is refused.
function O.bind(id, key, taken)
    if O.FIXED[key] or (taken and taken[key]) then return false end
    local was = O.key(id)
    for _, k in ipairs(O.KEYS) do
        if k.id ~= id and O.key(k.id) == key then
            O.bound[k.id] = was ~= k.key and was or nil
        end
    end
    O.bound[id] = key ~= O.KEY[id].key and key or nil
    return true
end

-- What a pressed key means to the run's screen: the usual key of the action
-- it is on now; nothing, if it is an action's usual key and that action has
-- been moved off it; else itself.
function O.translate(key)
    for _, k in ipairs(O.KEYS) do if O.bound[k.id] == key then return k.key end end
    for _, k in ipairs(O.KEYS) do if k.key == key and O.bound[k.id] then return nil end end
    return key
end

-- Is the action's key held (for the pans, which go while it is down)?
function O.down(id)
    return love.keyboard.isDown(O.key(id))
end

-- How a key is written on the screen: "SPACE", "F", "1".
function O.name(key)
    local name = key:gsub("^kp", "PAD "):upper()
    return Lang.t(name)
end
-- The key now doing what `key` (a usual key) does, as it is written.
function O.label(key)
    for _, k in ipairs(O.KEYS) do if k.key == key then return O.name(O.key(k.id)) end end
    return O.name(key)
end

function O.readKeys(words)
    for k = 2, #words do
        local id, key = words[k]:match("^(.-)=(.+)$")
        if id and O.KEY[id] and not O.FIXED[key] then O.bind(id, key) end
    end
end
function O.keysLine()
    local parts = {}
    for _, k in ipairs(O.KEYS) do if O.bound[k.id] then parts[#parts + 1] = k.id .. "=" .. O.bound[k.id] end end
    if #parts == 0 then return nil end
    return "keys " .. table.concat(parts, " ")
end

return O

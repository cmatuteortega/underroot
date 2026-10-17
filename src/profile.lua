-- What the player keeps between runs: the levels won, the endless records,
-- each level's loadout and seed, the Spore Bank, the enemies met and how loud.
--
-- It all lives in one file in the save directory, `save.txt`, a line a thing:
-- a word saying what, then its words.
--
--   version 1
--   won crack pond
--   endless crack 21
--   loadout crack puffer needle mat inky stink relay seed=oak
--   spores 40
--   owned inky stink
--   seeds oak
--   seen ant pillbug
--   sound 0.5
--
-- A save from before that file is the six it replaced (progress.txt,
-- endless.txt, loadout.txt, bank.txt, seen.txt, sound.txt): read once, and
-- written out as save.txt the next time anything is saved. They are left
-- where they are, read no more.

local D = require "src.defs"

local P = {}

local FILE = "save.txt"
local VERSION = 1

-- Everything back to nothing, as on a first run.
local function clear()
    P.won = {} -- { crack = true, ... }
    P.records = {} -- the most waves held in endless: { crack = 21, ... }
    P.loadouts = {} -- the species last brought: { crack = { "puffer", ... } }
    P.sown = {} -- the seed last planted: { crack = "oak" }
    P.spores = 0
    P.owned = {} -- species bought: { inky = true }
    P.seeds = {} -- seeds bought: { oak = true }
    P.seen = {} -- enemies met: { ant = true }
    P.sound = nil -- 1, 0.5 or 0; nil leaves the sound as it starts
end

local function read(name)
    return love.filesystem.getInfo(name) and love.filesystem.read(name)
end

local function words(line)
    local list = {}
    for w in line:gmatch("%S+") do list[#list + 1] = w end
    return list
end

-- A level's loadout: its id, the species it brings and its seed (`seed=oak`).
local function loadout(list)
    local id, species, seed = list[1], {}, nil
    if not (id and D.LEVEL[id]) then return end
    for k = 2, #list do
        local w = list[k]
        if w:match("^seed=") then seed = D.SEED[w:sub(6)] and w:sub(6)
        elseif D.TOWER[w] and #species < D.LOADOUT then species[#species + 1] = w end
    end
    if #species > 0 then P.loadouts[id] = species end
    P.sown[id] = seed
end

-- Each line of save.txt, by its first word.
local LINE = {
    won = function(w) for k = 2, #w do if D.LEVEL[w[k]] then P.won[w[k]] = true end end end,
    endless = function(w) if D.LEVEL[w[2]] and tonumber(w[3]) then P.records[w[2]] = tonumber(w[3]) end end,
    loadout = function(w) table.remove(w, 1); loadout(w) end,
    spores = function(w) P.spores = tonumber(w[2]) or 0 end,
    owned = function(w) for k = 2, #w do if D.TOWER[w[k]] then P.owned[w[k]] = true end end end,
    seeds = function(w) for k = 2, #w do if D.SEED[w[k]] then P.seeds[w[k]] = true end end end,
    seen = function(w) for k = 2, #w do if D.ENEMIES[w[k]] then P.seen[w[k]] = true end end end,
    sound = function(w) P.sound = tonumber(w[2]) end,
}

-- The six files a save from before save.txt kept.
local function readOld()
    local data = read("progress.txt")
    if data then for id in data:gmatch("%S+") do P.won[id] = true end end
    data = read("endless.txt")
    for id, n in (data or ""):gmatch("(%S+)%s+(%d+)") do
        if D.LEVEL[id] then P.records[id] = tonumber(n) end
    end
    for line in (read("loadout.txt") or ""):gmatch("[^\n]+") do loadout(words(line)) end
    data = read("bank.txt")
    if data then
        P.spores = tonumber(data:match("spores%s+(%d+)")) or 0
        for id in (data:match("owned([^\n]*)") or ""):gmatch("%S+") do
            if D.TOWER[id] then P.owned[id] = true end
        end
        for id in (data:match("seeds([^\n]*)") or ""):gmatch("%S+") do
            if D.SEED[id] then P.seeds[id] = true end
        end
    end
    data = read("seen.txt")
    if data then for id in data:gmatch("%S+") do if D.ENEMIES[id] then P.seen[id] = true end end end
    data = read("sound.txt")
    P.sound = data and tonumber(data:match("[%d%.]+"))
end

function P.load()
    clear()
    local data = read(FILE)
    if data then
        for line in data:gmatch("[^\n]+") do
            local w = words(line)
            if LINE[w[1]] then LINE[w[1]](w) end
        end
    else
        readOld()
    end
    -- A save from before the encyclopedia: whatever comes on a level won was met there.
    for _, l in ipairs(D.LEVELS) do
        if P.won[l.id] then for _, w in ipairs(l.waves) do for _, g in ipairs(w) do P.seen[g[1]] = true end end end
    end
end

-- Lists of ids in the order defs gives them, so the file reads the same each time.
local function ids(list, set)
    local out = {}
    for _, x in ipairs(list) do
        local id = type(x) == "table" and x.id or x
        if set[id] then out[#out + 1] = id end
    end
    return table.concat(out, " ")
end

function P.save()
    local lines = { "version " .. VERSION, "won " .. ids(D.LEVELS, P.won) }
    for _, l in ipairs(D.LEVELS) do
        if P.records[l.id] then lines[#lines + 1] = "endless " .. l.id .. " " .. P.records[l.id] end
    end
    for _, l in ipairs(D.LEVELS) do
        local list, seed = P.loadouts[l.id], P.sown[l.id]
        if list or seed then
            lines[#lines + 1] = "loadout " .. l.id .. " " .. table.concat(list or {}, " ") .. (seed and (" seed=" .. seed) or "")
        end
    end
    lines[#lines + 1] = "spores " .. P.spores
    lines[#lines + 1] = "owned " .. ids(D.TOWERS, P.owned)
    lines[#lines + 1] = "seeds " .. ids(D.SEEDS, P.seeds)
    lines[#lines + 1] = "seen " .. ids(D.ENEMY_ORDER, P.seen)
    if P.sound then lines[#lines + 1] = "sound " .. P.sound end
    love.filesystem.write(FILE, table.concat(lines, "\n") .. "\n")
end

clear()

return P

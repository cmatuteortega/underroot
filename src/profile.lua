-- What the player keeps between runs: the levels won, the endless records,
-- each level's loadout and seed, the Spore Bank, the enemies met and how loud;
-- and what that opens: the levels open, and what the bank has and sells.
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

--- the Spore Bank ---------------------------------------------------------------------

-- Can it be brought? The first six always, the rest once bought.
function P.owns(id) return D.TOWER[id].starter or P.owned[id] == true end

-- The level whose first win puts a species up for sale.
function P.prizeOf(id)
    for _, l in ipairs(D.LEVELS) do if l.prize == id then return l end end
end

function P.forSale(id)
    local l = P.prizeOf(id)
    return not P.owns(id) and l ~= nil and P.won[l.id] == true
end

-- Bought for good, if it is for sale and the spores are there.
function P.buy(id)
    local price = D.TOWER[id].price
    if not P.forSale(id) or P.spores < price then return false end
    P.spores = P.spores - price
    P.owned[id] = true
    P.save()
    return true
end

-- Seeds too: the bean from the start, the oak and the tomato for sale from the
-- start, the rest once the level they are `after` is won.
function P.ownsSeed(id) return not D.SEED[id].price or P.seeds[id] == true end

function P.seedForSale(id)
    local sd = D.SEED[id]
    return not P.ownsSeed(id) and (not sd.after or P.won[sd.after] == true)
end

-- Known: had, or up for sale. Anything else is only "???" in the loadout
-- until a win puts it up for sale.
function P.known(id) return P.owns(id) or P.forSale(id) end
function P.seedKnown(id) return P.ownsSeed(id) or P.seedForSale(id) end

function P.buySeed(id)
    local sd = D.SEED[id]
    if not P.seedForSale(id) or P.spores < sd.price then return false end
    P.spores = P.spores - sd.price
    P.seeds[id] = true
    P.save()
    return true
end

-- A level is open once the one before it is won; challenge mode once the last is.
-- One won already, or any after it, keeps it open: a save from before the
-- Flowerpot, the Shed Floor and the Rotting Log came in still has the Pond
-- Edge and the Lawn.
function P.levelOpen(n)
    if n == 1 or P.won[D.LEVELS[n - 1].id] then return true end
    for k = n, #D.LEVELS do if P.won[D.LEVELS[k].id] then return true end end
    return false
end
function P.challengeOpen() return P.won[D.LEVELS[#D.LEVELS].id] end

clear()

return P

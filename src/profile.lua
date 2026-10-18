-- What the player keeps between runs: the levels won, the endless records,
-- each level's loadout and seed, the Spore Bank and the network it has grown,
-- the enemies met and how loud; and what that opens: the levels open, and
-- the species and seeds the network has grown (src/network.lua).
--
-- It all lives in one file in the save directory, `save.txt`, a line a thing:
-- a word saying what, then its words.
--
--   version 2
--   won crack pond
--   endless crack 21
--   loadout crack puffer needle mat seed=oak
--   spores 40
--   net needle=1 puffer.power=2 oak=1
--   all 1
--   seen ant pillbug
--   sound 0.5
--
-- A version 1 save bought species and seeds outright (`owned`, `seeds`):
-- what it spent comes back as spores, at the network's rate, to grow them
-- again. A save from before save.txt is the six files it replaced
-- (progress.txt, endless.txt, loadout.txt, bank.txt, seen.txt, sound.txt):
-- read once, and written out as save.txt the next time anything is saved.
-- They are left where they are, read no more.

local D = require "src.defs"
local N = require "src.network"

local P = {}

local FILE = "save.txt"
local VERSION = 2

-- What a version 1 save paid for what it bought, and how many of today's
-- spores each of its spores is worth: given back to grow the network with.
local OLD_PRICE = { stink = 20, shelf = 25, mortar = 30, lamp = 35, cordyceps = 40, giant = 50,
    oak = 15, tomato = 15, dandelion = 25, sunflower = 35, flytrap = 45 }
local OLD_RATE = 3

-- Everything back to nothing, as on a first run.
local function clear()
    P.won = {} -- { crack = true, ... }
    P.records = {} -- the most waves held in endless: { crack = 21, ... }
    P.loadouts = {} -- the species last brought: { crack = { "puffer", ... } }
    P.sown = {} -- the seed last planted: { crack = "oak" }
    P.spores = 0
    P.net = {} -- the network's ranks: { needle = 1, ["puffer.power"] = 2 }
    P.all = false -- the whole network on, whatever is grown: for trying it all out
    P.version = nil -- the save's, as read: an old one is paid back for what it bought
    P.bought = 0 -- what an old save spent in its Spore Bank
    P.seen = {} -- enemies met: { ant = true }
    P.sound = nil -- 1, 0.5 or 0; nil leaves the sound as it starts
    P.cache = nil
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
    version = function(w) P.version = tonumber(w[2]) end,
    all = function(w) P.all = w[2] == "1" end,
    spores = function(w) P.spores = tonumber(w[2]) or 0 end,
    net = function(w)
        for k = 2, #w do
            local id, n = w[k]:match("^(.-)=(%d+)$")
            if id and D.NET[id] then P.net[id] = math.min(N.ranks(D.NET[id]), tonumber(n)) end
        end
    end,
    -- A version 1 save's: what was bought, to be paid back.
    owned = function(w) for k = 2, #w do P.bought = P.bought + (OLD_PRICE[w[k]] or 0) end end,
    seeds = function(w) for k = 2, #w do P.bought = P.bought + (OLD_PRICE[w[k]] or 0) end end,
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
        for id in (data:match("owned([^\n]*)") or ""):gmatch("%S+") do P.bought = P.bought + (OLD_PRICE[id] or 0) end
        for id in (data:match("seeds([^\n]*)") or ""):gmatch("%S+") do P.bought = P.bought + (OLD_PRICE[id] or 0) end
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
    -- From before the network: the old bank's spores, and what it spent, at
    -- today's rate. Saved at once, so it is paid only the once.
    if (P.version or 1) < VERSION then
        local old = P.spores + P.bought
        P.spores, P.bought = old * OLD_RATE, 0
        if old > 0 then P.save() end
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
    local net = {}
    for _, row in ipairs(D.NETWORK) do
        if (P.net[row.id] or 0) > 0 then net[#net + 1] = row.id .. "=" .. P.net[row.id] end
    end
    lines[#lines + 1] = "net " .. table.concat(net, " ")
    if P.all then lines[#lines + 1] = "all 1" end
    lines[#lines + 1] = "seen " .. ids(D.ENEMY_ORDER, P.seen)
    if P.sound then lines[#lines + 1] = "sound " .. P.sound end
    love.filesystem.write(FILE, table.concat(lines, "\n") .. "\n")
end

--- the Spore Bank's network -----------------------------------------------------------------

-- The ranks the network counts as grown: what was bought, or with the whole
-- network switched on (`all`), every rank of every node. What was bought is
-- kept either way, and is back when it is switched off.
local EVERYTHING
function P.ranks()
    if not P.all then return P.net end
    EVERYTHING = EVERYTHING or N.everything()
    return EVERYTHING
end

-- What the network has grown, for a run (Game.new's `opts.net`). Worked out
-- again only after a rank is bought or the whole of it switched.
function P.grown()
    if not P.cache then P.cache = N.grown(P.ranks()) end
    return P.cache
end

-- The whole network on or off.
function P.setAll(on)
    P.all, P.cache = on and true or false, nil
    P.save()
end

-- Can it be brought, or planted? Once the network has grown it.
function P.owns(id) return P.grown().species[id] == true end
function P.ownsSeed(id) return P.grown().seeds[id] == true end

-- Where a node stands (N.state), and a rank of it bought, saved at once.
-- With the whole network on, every node stands full and nothing is bought.
function P.nodeState(id)
    if P.all then return N.state({ net = P.ranks(), won = P.won, seen = P.seen, spores = P.spores }, id) end
    return N.state(P, id)
end
function P.buy(id)
    if P.all or not N.buy(P, id) then return false end
    P.cache = nil
    P.save()
    return true
end

-- Every rank sold back, for all it cost: the network starts again from the
-- sprout, spores in hand to grow it some other way.
function P.regrow()
    local _, spent = N.total(P.net)
    P.spores = P.spores + spent
    P.net, P.cache = {}, nil
    P.save()
    return spent
end

-- The network's node a species or seed is grown on, for "GROW IT ON THE NETWORK".
function P.nodeOf(id)
    for _, row in ipairs(D.NETWORK) do
        if row.species == id or row.seed == id then return row end
    end
end

-- What a level's first win opens on the network: the rows waiting on it.
function P.opens(level)
    local list = {}
    for _, row in ipairs(D.NETWORK) do if row.won == level then list[#list + 1] = row end end
    return list
end

-- A level is open once the one before it is won; a challenge once its own
-- level is (`id`, or any challenge at all without one).
-- One won already, or any after it, keeps it open: a save from before the
-- Flowerpot, the Shed Floor and the Rotting Log came in still has the Pond
-- Edge and the Lawn.
function P.levelOpen(n)
    if n == 1 or P.won[D.LEVELS[n - 1].id] then return true end
    for k = n, #D.LEVELS do if P.won[D.LEVELS[k].id] then return true end end
    return false
end
function P.challengeOpen(id)
    if id then return P.won[D.CHALLENGE[id].won] or false end
    for _, c in ipairs(D.CHALLENGES) do if P.won[c.won] then return true end end
    return false
end

-- The challenges open, in order.
function P.challenges()
    local list = {}
    for _, c in ipairs(D.CHALLENGES) do if P.won[c.won] then list[#list + 1] = c end end
    return list
end

clear()

return P

-- The run the player is in the middle of, kept in run.txt so that one the
-- OS killed (a call, a message, the phone locked too long), or one quit on a
-- computer, can be picked up again: CONTINUE on the home screen.
--
-- Kept at the start of each build phase, and when the game goes to the
-- background; let go when the run is won or lost, or another is started.
--
-- What is kept is the run itself, the whole of S.game as it stands: every
-- table in it, each once, so what points at what (a link at its two nodes,
-- a tower at its node, an enemy at the link it is biting) points the same
-- way when it is read back. What a run only points at and never changes --
-- the board (src/world.lua) and the numbers (src/defs.lua) -- is not copied:
-- it is kept as the way to it from the top (`W pockets 3`, `D LEVEL crack`)
-- and found again there. The rules' dice are kept as where they had got to,
-- so a run picked up rolls what it would have.
--
-- The file is a line for what the run is (the level, the challenge, the
-- species brought), a line for the ways into the board and the numbers, then a
-- line a table: each a little Lua table of constants, read with nothing in
-- reach (no globals, nothing to call). It ends on `end`, and is written like
-- save.txt, a whole copy there at every moment (Profile.writeWhole).

local D = require "src.defs"
local Game = require "src.game"
local Profile = require "src.profile"

local R = {}

R.FILE = "run.txt"
R.VERSION = 1 -- bumped when a run's tables change shape; a run kept before is let go

local format, floor, huge = string.format, math.floor, math.huge

-- The tables with metatables a run holds, by name.
local META = { Game = Game }
local META_NAME = {}
for name, mt in pairs(META) do META_NAME[mt] = name end

-- The ways into the tables under each root: table to path, the root's name
-- first, then each key on the way. The numbers are walked once; a board once
-- for each board.
local function walk(root, name, into)
    local seen = {}
    local function go(t, path)
        if seen[t] then return end
        seen[t] = true
        if not into[t] then into[t] = path end
        for k, v in pairs(t) do
            local tk = type(k)
            if type(v) == "table" and (tk == "string" or tk == "number" or tk == "boolean") then
                local p = { unpack(path) }
                p[#p + 1] = k
                go(v, p)
            end
        end
    end
    go(root, { name })
    return into
end

local defsPaths
local worldPaths = setmetatable({}, { __mode = "k" })
local function outside(world)
    defsPaths = defsPaths or walk(D, "D", {})
    if not worldPaths[world] then
        local paths = walk(world, "W", {})
        for t, p in pairs(defsPaths) do paths[t] = paths[t] or p end
        worldPaths[world] = paths
    end
    return worldPaths[world]
end

local function isDice(v)
    local ok, yes = pcall(function() return v.typeOf ~= nil and v:typeOf("RandomGenerator") end)
    return ok and yes
end

-- A constant as Lua reads it back, on one line.
local function constant(v)
    local t = type(v)
    if t == "number" then
        if v ~= v then return "0/0" end
        if v == huge then return "1/0" end
        if v == -huge then return "-1/0" end
        if v == floor(v) and v > -2 ^ 53 and v < 2 ^ 53 then return format("%d", v) end
        return format("%.17g", v)
    elseif t == "string" then
        return (format("%q", v):gsub("\\\n", "\\n"):gsub("\r", "\\r"))
    elseif t == "boolean" then
        return tostring(v)
    end
end

-- The run as the file's text, with `head` (plain values only) as its first
-- line. Nil and why, for a run holding something that cannot be kept (a
-- function, a picture): it is kept as it was at the last build phase.
function R.encode(g, head)
    local paths = outside(g.world)
    local ids, list = {}, {}
    local extIds, extList = {}, {}
    local function value(v, where)
        local c = constant(v)
        if c then return c end
        if isDice(v) then return "{dice=" .. constant(v:getState()) .. "}" end
        if type(v) ~= "table" then error(("a %s at %s"):format(type(v), where), 0) end
        local path = paths[v]
        if path then
            if not extIds[v] then
                extList[#extList + 1] = path
                extIds[v] = #extList
            end
            return "{e=" .. extIds[v] .. "}"
        end
        if not ids[v] then
            list[#list + 1] = v
            ids[v] = #list
        end
        return "{" .. ids[v] .. "}"
    end
    local lines = {}
    local ok, err = pcall(function()
        value(g, "the run")
        local n = 1
        while list[n] do
            local t = list[n]
            local mt = getmetatable(t)
            local parts = {}
            if mt then
                if not META_NAME[mt] then error("a table with a metatable at table " .. n, 0) end
                parts[1] = "m=" .. constant(META_NAME[mt])
            end
            for k, v in pairs(t) do
                local where = "table " .. n .. " ." .. tostring(k)
                parts[#parts + 1] = value(k, where)
                parts[#parts + 1] = value(v, where)
            end
            lines[n] = "return {" .. table.concat(parts, ",") .. "}"
            n = n + 1
        end
    end)
    if not ok then return nil, err end
    -- The board's one change a run makes to it: its fords dried by a drought,
    -- until the next wave's weather says otherwise.
    local h = { "dry=" .. tostring(g.world.dry and true or false) }
    for k, v in pairs(head) do h[#h + 1] = k .. "=" .. assert(constant(v), k) end
    local ways = {}
    for k, path in ipairs(extList) do
        local keys = {}
        for j, key in ipairs(path) do keys[j] = constant(key) end
        ways[k] = "{" .. table.concat(keys, ",") .. "}"
    end
    return "return {v=" .. R.VERSION .. "," .. table.concat(h, ",") .. "}\n"
        .. "return {" .. table.concat(ways, ",") .. "}\n"
        .. table.concat(lines, "\n") .. "\nend\n"
end

-- A line of the file read, with nothing in reach.
local function line(s)
    local f = loadstring(s, "=run")
    if not f then return nil end
    setfenv(f, {})
    local ok, t = pcall(f)
    return ok and type(t) == "table" and t or nil
end

-- The head of a run's text: what run it is.
function R.head(text)
    local h = text and line(text:match("^[^\n]*"))
    if h and h.v == R.VERSION then return h end
end

-- The run back from its text, on `world` (the head's level's board, painted
-- or not). Nil when it will not read: from another version of the game, or
-- pointing at something on the board or in the numbers that is no longer there.
function R.decode(text, world)
    local rows = {}
    for s in text:gmatch("[^\n]+") do rows[#rows + 1] = s end
    if rows[#rows] ~= "end" or not R.head(text) then return nil end
    local ways = line(rows[2])
    if not ways then return nil end
    local roots = { D = D, W = world }
    local ext = {}
    for k, path in ipairs(ways) do
        local t = roots[path[1]]
        for j = 2, #path do t = type(t) == "table" and t[path[j]] or nil end
        if type(t) ~= "table" then return nil end
        ext[k] = t
    end
    local recs, tables = {}, {}
    for n = 3, #rows - 1 do
        local rec = line(rows[n])
        if not rec then return nil end
        recs[n - 2], tables[n - 2] = rec, {}
    end
    local function value(v)
        if type(v) ~= "table" then return v end
        if v.e then return ext[v.e] end
        if v.dice then
            local dice = love.math.newRandomGenerator(1)
            dice:setState(v.dice)
            return dice
        end
        return tables[v[1]]
    end
    for n, rec in ipairs(recs) do
        local t = tables[n]
        for k = 1, #rec, 2 do
            local key = value(rec[k])
            if key == nil then return nil end
            t[key] = value(rec[k + 1])
        end
        if rec.m then
            if not META[rec.m] then return nil end
            setmetatable(t, META[rec.m])
        end
    end
    local g = tables[1]
    if not g or getmetatable(g) ~= Game then return nil end
    g.world = world
    world:setDry(R.head(text).dry)
    return g
end

local function whole(data) return data ~= nil and data ~= false and data:match("\nend\n$") ~= nil end

-- Is there a run kept? Known once looked for, then as it is kept and let go.
local kept

-- Keeps the run, with `head` saying what it is. False if it could not be kept.
function R.save(g, head)
    local text = R.encode(g, head)
    if not text then return false end
    Profile.writeWhole(R.FILE, text, whole)
    kept = true
    return true
end

-- The run kept, as text, and its head; nil if there is none (or it will not read).
function R.load()
    local text = Profile.readWhole(R.FILE, whole)
    local h = R.head(text)
    kept = h ~= nil
    if h then return text, h end
end

function R.kept()
    if kept == nil then R.load() end
    return kept
end

function R.clear()
    Profile.removeWhole(R.FILE)
    kept = false
end

return R

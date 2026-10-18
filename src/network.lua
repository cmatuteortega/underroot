-- The network the Spore Bank grows (D.NETWORK), worked out: what can be
-- bought next and for how much, what a profile's ranks come to for a run,
-- and where each node sits on the network's screen. No LÖVE in here: the
-- profile, the rules, the bot and the tests all read it.
--
-- What a run is given is `grown`: { species, seeds, ups, mutations, pulse,
-- tower, world, vs, loot }. Nothing given (nil) is the network fully grown, every
-- number as defs writes it: the bot, the shots and the tests play that.

local D = require "src.defs"

local N = {}

-- How a number answers to `f`, how far the network has grown it (0 to 1):
--   more    v * f       what is better bigger: damage, HP
--
-- Nothing holds back a range or a link's reach: a build is laid out by them,
-- and a tower that cannot reach the trail is not a weaker tower but a wasted one.
--   less    v / f       what is better smaller: seconds between shots, cost
--   bonus   1 + (v-1)f  a multiplier over 1: only the part over 1 grows
--   dampen  1 - (1-v)f  a multiplier under 1 that is stronger the lower: a slow
N.MODE = { every = "less", cost = "less", amp = "bonus", capMul = "bonus", battery = "bonus", feast = "bonus",
    deadEnd = "bonus", slow = "dampen", reek = "dampen", inkSlow = "dampen", shieldMul = "dampen" }

-- The network's own numbers (the rows' `world`), and how each answers.
N.WORLD = { linkHp = "more", linkCap = "more", linkCost = "less", linkGrow = "less",
    ring = "bonus", pulse = "bonus", heart = "more", income = "more", start = "more", bonus = "more" }

function N.scale(mode, v, f)
    if f >= 1 then return v end
    if mode == "less" then return v / f end
    if mode == "bonus" then return 1 + (v - 1) * f end
    if mode == "dampen" then return 1 - (1 - v) * f end
    return v * f
end

--- ranks and prices -------------------------------------------------------------------------

-- How many ranks a node has: a free one has one, had from the start.
function N.ranks(row) return row.free and 1 or #row.price end

-- The rank a profile's `ranks` ({ id = n }) has of a node.
function N.rank(ranks, id)
    local row = D.NET[id]
    if row.free then return 1 end
    return math.min(N.ranks(row), ranks[id] or 0)
end

-- How far a rank brings the node's numbers: `from` at none, all at the last.
function N.factor(row, rank) return row.from + (1 - row.from) * rank / N.ranks(row) end

-- The price of a node's next rank, or nil once it is full.
function N.price(ranks, id)
    local row = D.NET[id]
    if row.free then return end
    return row.price[N.rank(ranks, id) + 1]
end

-- Every spore the whole network costs, and what `ranks` has spent of it.
function N.total(ranks)
    local all, spent = 0, 0
    for _, row in ipairs(D.NETWORK) do
        for k, p in ipairs(row.price or {}) do
            all = all + p
            if ranks and k <= N.rank(ranks, row.id) then spent = spent + p end
        end
    end
    return all, spent
end

-- Where a node stands for a profile `p` ({ net = ranks, won, seen, spores }):
--   full     every rank bought
--   open     its next rank can be bought, and there are the spores for it
--   poor     its next rank can be bought, but not yet afforded
--   locked   it waits on a level won (`won`, the level), whatever else it waits on
--   shut     what it grows from has no rank yet
--   unknown  it waits on an enemy met: shown as nothing at all
function N.state(p, id)
    local row = D.NET[id]
    local r = N.rank(p.net, id)
    if r >= N.ranks(row) then return "full" end
    if row.seen then
        local met = false
        for _, k in ipairs(row.seen) do if p.seen[k] then met = true end end
        if not met then return "unknown" end
    end
    if row.won and not p.won[row.won] then return "locked", D.LEVEL[row.won] end
    if row.at and N.rank(p.net, row.at) == 0 then return "shut" end
    if p.spores < N.price(p.net, id) then return "poor" end
    return "open"
end

-- A rank bought, if it can be: the spores paid, `p.net` raised. True if it was.
function N.buy(p, id)
    if N.state(p, id) ~= "open" then return false end
    p.spores = p.spores - N.price(p.net, id)
    p.net[id] = N.rank(p.net, id) + 1
    return true
end

--- what a run is given -----------------------------------------------------------------------

-- What `ranks` come to, for Game.new's `opts.net`.
function N.grown(ranks)
    local g = { species = {}, seeds = {}, ups = {}, mutations = {}, pulse = false, tower = {}, world = {}, vs = {}, loot = {} }
    for _, row in ipairs(D.NETWORK) do
        local r = N.rank(ranks, row.id)
        if row.species and r > 0 then g.species[row.species] = true end
        if row.seed and r > 0 then g.seeds[row.seed] = true end
        if row.pulse and r > 0 then g.pulse = true end
        if row.up then g.ups[row.up[1] .. ":" .. row.up[2]] = r end
        -- A mutation a rank; a free node brings all it names.
        for k = 1, row.free and #(row.mutations or {}) or r do
            if row.mutations and row.mutations[k] then g.mutations[row.mutations[k]] = true end
        end
        if row.from then
            local f = N.factor(row, r)
            if row.tower then
                local t = g.tower[row.tower] or {}
                for _, k in ipairs(row.stats) do t[k] = f end
                g.tower[row.tower] = t
            end
            if row.world then g.world[row.world] = f end
            for _, k in ipairs(row.vs or {}) do g.vs[k] = (g.vs[k] or 1) * f end
            for _, k in ipairs(row.loot or {}) do g.loot[k] = (g.loot[k] or 1) * f end
        end
    end
    return g
end

-- Every rank of every node: what the full network's `ranks` are.
function N.everything()
    local ranks = {}
    for _, row in ipairs(D.NETWORK) do ranks[row.id] = N.ranks(row) end
    return ranks
end

-- A species' number as `g` grows it (`v`, as defs writes it, at its tier).
function N.value(g, kind, k, v)
    if not g or type(v) ~= "number" then return v end
    local t = g.tower[kind]
    local f = t and t[k]
    if not f then return v end
    return N.scale(N.MODE[k] or "more", v, f)
end

-- One of the network's own numbers (N.WORLD), as `g` grows it.
function N.world(g, key, v)
    local f = g and g.world[key]
    if not f then return v end
    return N.scale(N.WORLD[key], v, f)
end

-- How hard what is grown hits an enemy of this kind: 1 when fully known.
function N.vs(g, kind) return g and g.vs[kind] or 1 end

-- What an enemy of this kind's body is worth drunk, as a part of what defs
-- writes: 1 when fully known.
function N.loot(g, kind) return g and g.loot and g.loot[kind] or 1 end

-- The highest tier of a species' upgrade branch that can be grown.
function N.tier(g, kind, branch)
    if not g then return 2 end
    return g.ups[kind .. ":" .. branch] or 0
end

function N.has(g, what, id)
    if not g then return true end
    if what == "pulse" then return g.pulse end
    return g[what][id] == true
end

--- where the nodes sit ------------------------------------------------------------------------

-- Each node's place on the network's screen, in steps from the sprout:
-- { x, y, depth }. The sprout stands on the ground at the top (y = 0) and
-- what grows from it digs down, a row a step deeper than the one it grows
-- from, the first row further down so the threads have room to fan out
-- under the sprout. Each node sits over the middle of what grows from it,
-- and a branch is packed against the one before as close as their nodes
-- allow, row by row (a tidy tree): a short branch tucks in under a long one's
-- shoulder instead of taking a column of its own all the way down. Each
-- node a little above or below its row (`N.JIG`, by its id), so the rows
-- read as soil dug into, not a grid.
N.GAP, N.FIRST, N.ROW, N.JIG = 1.15, 2.6, 1.6, 0.18 -- steps between neighbours, to the first row, between rows, off it

function N.depthY(depth) return depth == 0 and 0 or N.FIRST + (depth - 1) * N.ROW end

function N.layout()
    if N.places then return N.places end
    local kids = {}
    for _, row in ipairs(D.NETWORK) do
        kids[row.id] = kids[row.id] or {}
        if row.at then
            kids[row.at] = kids[row.at] or {}
            table.insert(kids[row.at], row.id)
        end
    end
    -- A branch laid out about its own node (at 0): where each of its nodes
    -- is across (`x`, relative), and its outline, the leftmost and rightmost
    -- of it a row (`l`, `r`, from its own row down).
    local rel = {}
    local function shape(id)
        local l, r = { 0 }, { 0 }
        local ks = kids[id]
        if #ks == 0 then return l, r end
        local shifts, ol, orr = {}, nil, nil
        for n, k in ipairs(ks) do
            local cl, cr = shape(k)
            local shift = 0
            if ol then
                -- As close to the branches before it as each shared row allows.
                for d = 1, math.min(#orr, #cl) do shift = math.max(shift, orr[d] - cl[d] + N.GAP) end
                for d = 1, #cl do
                    if d > #orr then ol[d], orr[d] = cl[d] + shift, cr[d] + shift
                    else orr[d] = cr[d] + shift end
                end
            else
                ol, orr = {}, {}
                for d = 1, #cl do ol[d], orr[d] = cl[d], cr[d] end
            end
            shifts[n] = shift
        end
        -- Over the middle of the first and last of what grows from it.
        local mid = (shifts[1] + shifts[#ks]) / 2
        for n, k in ipairs(ks) do rel[k] = shifts[n] - mid end
        for d = 1, #ol do l[d + 1], r[d + 1] = ol[d] - mid, orr[d] - mid end
        return l, r
    end
    local root = D.NETWORK[1].id
    shape(root)
    local places = {}
    local function jig(id)
        local h = 0
        for k = 1, #id do h = (h * 31 + id:byte(k)) % 9973 end
        return (h % 101 / 50 - 1) * N.JIG
    end
    local function place(id, depth, x)
        places[id] = { x = x, y = N.depthY(depth) + (depth > 0 and jig(id) or 0), depth = depth }
        for _, k in ipairs(kids[id]) do place(k, depth + 1, x + rel[k]) end
    end
    place(root, 0, 0)
    local b = { l = 0, r = 0, bottom = 0 }
    for _, p in pairs(places) do b.l, b.r, b.bottom = math.min(b.l, p.x), math.max(b.r, p.x), math.max(b.bottom, p.y) end
    N.places, N.kids, N.bounds = places, kids, b
    return places
end

return N

-- The rules: the network, what grows on it, what eats it, and the waves.
--
-- Nothing here draws. It keeps the state the design doc's five parts describe --
-- the Heart, the pockets, the hyphae between them, the nutrients in the bank and
-- the fruiting bodies -- and answers what the player is allowed to do to them.
--
-- The network is a graph small enough to be worked out again from nothing
-- every frame: which nodes the Heart can reach over living links, how many hops
-- away each is (which way is "downstream", for the brine), and the widest path
-- to each (the flow cap a tower is fed at). Recomputing beats keeping it in step
-- with every cut, bite and regrowth, and at a few dozen links it is free.
--
-- Decisions on the design doc's open questions:
--   * Real time, with a build phase between waves. You can rewire during a wave
--     too -- that is the fantasy -- but the pause lowers the barrier.
--   * Severing is kind: a cut tower runs on its reserve, then goes dormant.
--   * Towers need a link only to refill, not to fire. Stricter is one line
--     (`fire` checks `node.conn`) once the kind version is known to be fun.
--   * The next wave is shown in full, gates included: the planning layer is the game.
--
-- The Fairy Ring and the Spore Pulse are worked out here too: rings are the
-- shortest loops through each living link, looked for again only when the set
-- of living links changes; the pulse walks the breadth-first tree back from the
-- node it is sent to.
--
-- Upgrades are two numbers on a tower, its branch and its tier; every stat is
-- read through `stat`, which takes the highest tier's value. Mutations are flags
-- in `mods`, read where the number they change is used. The network the Spore
-- Bank has grown (`net`, src/network.lua) is read the same way: every number it
-- holds back goes through `stat` or one of the few below that a mutation can
-- change too.
--
-- A run is one level: its waves, its starting bank and sprout, which species it
-- opens when. The weather is a name on the wave, and every number it changes
-- is read through `sky` where that number is used, the way a mutation is.

local D = require "src.defs"
local N = require "src.network"
local World = require "src.world"

local sqrt, max, min, abs, floor, huge = math.sqrt, math.max, math.min, math.abs, math.floor, math.huge
local cos, sin, atan2 = math.cos, math.sin, math.atan2
-- Looks only (sparks, dust, motes): their own dice, so what the rules roll
-- (and a bot's run) is the same with or without them.
local looks = love.math.newRandomGenerator(7)
local function fr() return looks:random() end

local Game = {}
Game.__index = Game

local TILE = 16

--- geometry ------------------------------------------------------------------------

-- Distance from (px, pz) to the segment (ax, az)-(bx, bz), and how far along it.
local function segDist(px, pz, ax, az, bx, bz)
    local dx, dz = bx - ax, bz - az
    local l2 = dx * dx + dz * dz
    local t = l2 > 0 and max(0, min(1, ((px - ax) * dx + (pz - az) * dz) / l2)) or 0
    local qx, qz = ax + dx * t, az + dz * t
    return sqrt((px - qx) ^ 2 + (pz - qz) ^ 2), t, qx, qz
end
Game.segDist = segDist

local function dist(a, b) return sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) end

local function unlist(list, item)
    for n = #list, 1, -1 do if list[n] == item then table.remove(list, n) end end
end

--- setting up -------------------------------------------------------------------------

-- A run of one level. `opts.challenge` adds the challenge wave at the end;
-- `opts.best` is the most waves held in endless on this level so far;
-- `opts.loadout`, a list of species ids, is all that can be grown (every
-- species when it is not given: the bot and the shots bring them all);
-- `opts.seed` is the sprout's seed (a D.SEEDS id, the bean if not given);
-- `opts.net`, what the Spore Bank's network has grown (N.grown), holds back
-- what it has not (the whole network when it is not given).
function Game.new(world, level, opts)
    local self = setmetatable({ world = world }, Game)
    level, opts = level or D.LEVELS[1], opts or {}
    -- The rules' own dice: the same `dice` plays the same run, whatever the
    -- screen and the sound roll in between.
    self.dice = love.math.newRandomGenerator(opts.dice or love.math.random(2 ^ 31 - 1))
    self.level = level
    self.waves = {}
    for k, w in ipairs(level.waves) do self.waves[k] = w end
    if opts.challenge then
        self.waves[#self.waves + 1] = D.CHALLENGE
        self.challenge = true
    end
    self.net = opts.net
    self.best = opts.best or 0 -- the endless record, raised as it is beaten
    self.spores = 0 -- earned for the Spore Bank: a few a wave cleared, more for a win
    self.firstWin = opts.firstWin -- the level not won before: its win pays more
    self.uniques = {} -- the one-per-run species already grown
    if opts.loadout then
        self.loadout = {}
        for _, id in ipairs(opts.loadout) do self.loadout[id] = true end
    end
    self.nodes, self.links, self.mats = {}, {}, {}
    self.enemies, self.corpses, self.shots, self.fx, self.texts = {}, {}, {}, {}, {}
    self.clouds, self.inks = {}, {}
    self.tunnels = {} -- a Mole Cricket's: { a = hole, b = hole, owner = it, open }
    self.seed = D.SEED[opts.seed or "bean"] or D.SEEDS[1]
    local seed = self.seed
    self.nutrients = floor(N.world(self.net, "start", level.start) + 0.5) + (seed.start or 0)
    self.heartMax = max(1, floor(N.world(self.net, "heart", level.heart) * (seed.heart or 1) + 0.5))
    self.heartHp = self.heartMax
    self.regrows = seed.regrow or 0 -- a dandelion's lives left
    self.pods = 0 -- free links left from a Bean Pod
    self.trapCd, self.acornCd = 0, 0
    self.wave, self.cleared, self.phase = 0, 0, "build"
    self.clock, self.waveClock = 0, 0
    self.queue = {}
    self.seen = {}
    self.events = {}
    self.cues = {}
    self.stats = { kills = 0, drunk = 0, stolen = 0, cuts = 0, bosses = 0, leaked = {} }
    self.rings, self.ringKey = {}, ""
    self.pulseCd = 0
    self.nextLink = 1
    self.mods = {}
    self.picked = {}

    local h = world.heart
    self.heart = { id = 1, x = h.x, y = h.y + 1, z = h.z, heart = true, quality = "normal", links = {} }
    self.nodes[1] = self.heart
    for n, p in ipairs(world.pockets) do
        self.nodes[n + 1] = { id = n + 1, x = p.x, y = p.y, z = p.z, pocket = p, quality = p.quality, links = {} }
    end
    self:recompute()
    return self
end

function Game:say(text, x, y, z, k)
    self.texts[#self.texts + 1] = { text = text, x = x, y = y, z = z, k = k or "l", life = 1.1 }
end

-- A sound, and where it happened, for src/ui/audio.lua to play (src/sfx.lua). One of
-- a name at a time: a frame of a dozen ants chewing is one chew. A run no one
-- listens to (the bot) stops keeping them once there are a few.
function Game:cue(name, x, z, vol)
    local list = self.cues
    if #list >= 48 then return end
    for _, c in ipairs(list) do if c.name == name then return end end
    list[#list + 1] = { name = name, x = x, z = z, vol = vol }
end

--- numbers a mutation can change --------------------------------------------------------

function Game:linkHp() return N.world(self.net, "linkHp", D.LINK.hp) * (self.mods.thick and 1.5 or 1) end
-- What one link holds when whole: an oak's Bark triples those at the sprout.
function Game:linkFull(l)
    local hp = self:linkHp()
    if self.mods.bark and (l.a.heart or l.b.heart) then hp = hp * 3 end
    return hp
end
function Game:linkReach() return D.LINK.reach * (self.mods.reach and 1.25 or 1) end
function Game:linkCost(len)
    local c = floor(N.world(self.net, "linkCost", D.LINK.cost(len)) + 0.5)
    if self.mods.cheap then c = max(1, floor(c * 0.75 + 0.5)) end
    return c
end
-- The weather this wave, or nothing: every number it changes is read through
-- this, and a missing one means "as usual".
local CLEAR = {}
function Game:sky() return self.weather and D.WEATHER[self.weather] or CLEAR end
function Game:pace() return self:sky().pace or 1 end

function Game:linkCap() return N.world(self.net, "linkCap", D.LINK.cap) end
function Game:linkGrow() return N.world(self.net, "linkGrow", D.LINK.grow) end

-- The pulse: grown on the network, and stronger and quicker back the more it is.
function Game:hasPulse() return N.has(self.net, "pulse") end
function Game:pulseCooldown()
    local f = self.net and self.net.world.pulse or 1
    return N.scale("less", D.PULSE.cooldown, f) * (self.mods.pulse and 0.6 or 1) * (self.mods.chute and 0.7 or 1)
end
function Game:pulseRate() return N.world(self.net, "pulse", D.PULSE.rate) end
function Game:pulseDamage() return N.world(self.net, "pulse", D.PULSE.damage) end
function Game:pulseDuration() return D.PULSE.duration * (self.mods.chute and 1.5 or 1) end
-- A pocket's quality as the towers on it feel it (its power, not its pay): a
-- bean's Nitrogen Fix makes those near the sprout one richer.
local RICHER = { poor = "normal", normal = "rich", rich = "rich" }
function Game:quality(n)
    if self.mods.nitro and not n.heart and n.conn and n.hop <= 2 then return RICHER[n.quality] end
    return n.quality
end
-- In a sunflower's sun: fed, near enough the sprout, and not at night.
function Game:sunlit(n)
    local sun = self.seed.sun
    if not sun or not n.conn or n.heart then return false end
    if self.weather == "night" and not self.mods.helio then return false end
    return n.hop <= (self.mods.helio and 3 or sun.hops)
end
-- The sugar paid when a wave is cleared (and on going endless).
function Game:waveBonus()
    return floor(N.world(self.net, "bonus", D.WAVE_BONUS + 4 * self.wave) * (self.mods.ripen and 1.3 or 1) * (self.mods.overripe and 0.5 or 1))
end
function Game:ringDamage() return N.world(self.net, "ring", self.mods.rings and 1.4 or D.RING.damage) end
function Game:ringSlow()
    return N.scale("dampen", self.mods.rings and 0.55 or D.RING.slow, self.net and self.net.world.ring or 1)
end

--- the network ------------------------------------------------------------------------

function Game:linkBetween(a, b)
    for _, l in ipairs(a.links) do
        if l.a == b or l.b == b then return l end
    end
end

-- Living: carries flow. A growing link does not yet; a cut one never does.
local function alive(l) return l.state == "alive" end
Game.alive = alive

function Game:degree(node)
    local n = 0
    for _, l in ipairs(node.links) do if alive(l) then n = n + 1 end end
    return n
end

function Game:recompute()
    for _, n in ipairs(self.nodes) do
        n.conn, n.hop, n.cap, n.parent, n.via = false, huge, 0, nil, nil
        if n.tower then n.tower.battery, n.tower.amp, n.tower.warded = 1, 1, false end
    end
    for _, l in ipairs(self.links) do l.capMul = 1 end
    local h = self.heart
    h.conn, h.hop, h.cap = true, 0, huge
    -- Hops, breadth first, over living links.
    local queue, head = { h }, 1
    while queue[head] do
        local n = queue[head]
        head = head + 1
        for _, l in ipairs(n.links) do
            if alive(l) then
                local o = l.a == n and l.b or l.a
                if not o.conn then
                    o.conn, o.hop, o.parent, o.via = true, n.hop + 1, n, l
                    queue[#queue + 1] = o
                end
            end
        end
    end
    -- What a fed relay does to the nodes it is linked to, and which branch a
    -- mane tends.
    for _, n in ipairs(self.nodes) do
        local t = n.tower
        if t and n.conn and t.kind == "relay" then
            local m = self:stat(t, "capMul")
            local bat, amp = self:stat(t, "battery") or 1, self:stat(t, "amp") or 1
            for _, l in ipairs(n.links) do
                if alive(l) then
                    l.capMul = max(l.capMul, m)
                    local o = l.a == n and l.b or l.a
                    if o.tower then
                        o.tower.battery = max(o.tower.battery, bat)
                        o.tower.amp = max(o.tower.amp, amp)
                    end
                end
            end
        elseif t and t.kind == "mane" then
            t.care = self:branch(n, self:stat(t, "depth"))
            if n.conn and self:stat(t, "webProof") then
                for o in pairs(t.care) do if o.tower then o.tower.warded = true end end
            end
        end
    end
    local flow = self:sky().flow or 1
    for _, l in ipairs(self.links) do
        l.thick = l.capMul > 1
        l.cap = self:linkCap() * l.capMul * flow
    end
    -- A relay pumps: what it is linked to is fed at its own links' width,
    -- however thin the way to it is.
    for _, n in ipairs(self.nodes) do
        local t = n.tower
        if t and n.conn and t.kind == "relay" then
            n.cap = max(n.cap, self:linkCap() * self:stat(t, "capMul") * flow)
        end
    end
    self.fed = 0
    for _, n in ipairs(self.nodes) do if n.conn and not n.heart then self.fed = self.fed + 1 end end
    self:findRings()
    -- The widest path: the most a node can be fed, limited by the thinnest link
    -- on the best way there. Relaxed until nothing changes; it is a small graph.
    local changed = true
    while changed do
        changed = false
        for _, l in ipairs(self.links) do
            if alive(l) then
                for _, e in ipairs({ { l.a, l.b }, { l.b, l.a } }) do
                    local c = min(e[1].cap, l.cap)
                    if c > e[2].cap then e[2].cap, changed = c, true end
                end
            end
        end
    end
end

-- Whether a link from a to b can be grown, and what it costs, or why not.
function Game:canLink(a, b)
    if not a or not b or a == b then return false, nil, "" end
    local len = dist(a, b)
    local cost = self.pods > 0 and 0 or self:linkCost(len)
    if self:linkBetween(a, b) then return false, cost, "ALREADY LINKED" end
    if len > self:linkReach() then return false, cost, "TOO FAR" end
    if not (a.conn or b.conn) then return false, cost, "NOT CONNECTED TO THE SPROUT" end
    if self.nutrients < cost then return false, cost, "NOT ENOUGH NUTRIENTS" end
    return true, cost
end

function Game:grow(a, b)
    local ok, cost = self:canLink(a, b)
    if not ok then return false end
    -- It grows out from whichever end is already fed.
    if not a.conn then a, b = b, a end
    self.nutrients = self.nutrients - cost
    -- A free one from a Bean Pod is costed as usual, for its repairs, but
    -- pruned it pays nothing back.
    local free = self.pods > 0
    if free then self.pods, cost = self.pods - 1, self:linkCost(dist(a, b)) end
    -- Its cap is set now, not at the next recompute: that waits for it to
    -- arrive, and anything asking about it meanwhile (a hover) needs one.
    local l = { id = self.nextLink, a = a, b = b, len = dist(a, b), cost = cost, state = "grow", grow = 0,
        bitten = {}, cap = self:linkCap(), capMul = 1, free = free }
    l.hp = self:linkFull(l)
    -- Tendrils: out of the sprout it is there at once.
    if self.mods.tendrils and (a.heart or b.heart) then l.grow = 1 end
    self.nextLink = self.nextLink + 1
    self.links[#self.links + 1] = l
    a.links[#a.links + 1] = l
    b.links[#b.links + 1] = l
    self:cue("grow", a.x, a.z)
    return l
end

function Game:removeLink(l)
    unlist(self.links, l)
    unlist(l.a.links, l)
    unlist(l.b.links, l)
    l.state = "gone"
end

-- Your own cut: a partial refund, and whatever was downstream is on its own.
function Game:prune(l)
    local back = l.state == "alive" and D.LINK.prune or D.LINK.prune * 0.5
    local refund = l.free and 0 or floor(l.cost * back)
    self.nutrients = self.nutrients + refund
    local mx, mz = (l.a.x + l.b.x) / 2, (l.a.z + l.b.z) / 2
    self:say("+" .. refund, mx, 4, mz)
    self.fx[#self.fx + 1] = { thread = true, ax = l.a.x, ay = l.a.y, az = l.a.z, bx = l.b.x, by = l.b.y, bz = l.b.z,
        life = 0.5, max = 0.5 }
    self:cue("prune", mx, mz)
    self:removeLink(l)
    self:recompute()
end

function Game:cut(l)
    if l.state ~= "alive" and l.state ~= "grow" then return end
    l.state, l.hp, l.regrow, l.hand = "cut", 0, 0, false
    self.stats.cuts = self.stats.cuts + 1
    self.events.cut = true
    local mx, mz = (l.a.x + l.b.x) / 2, (l.a.z + l.b.z) / 2
    self:burst(mx, 1, mz, 8, { "c", "l", "r" }, 18)
    l.flash = 0.3
    self:shock(mx, mz, 7, 0.25, "r", "w")
    self:cue("cut", mx, mz)
    self:recompute()
end

-- How much of a bite gets through: a shelf fungus nearby takes most of it.
function Game:shield(l)
    local best = 1
    for _, m in ipairs(self.mats) do
        if m.kind == "shelf" then
            local d = D.TOWER.shelf
            if segDist(m.x, m.z, l.a.x, l.a.z, l.b.x, l.b.z) <= d.shield then best = min(best, self:stat(m, "shieldMul")) end
        end
    end
    return best
end

function Game:biteLink(l, amount)
    l.hp = l.hp - amount * self:shield(l)
end

-- Rolled over, sheared, flattened: cut outright, unless a shelf shields it.
function Game:crush(l)
    if self:shield(l) < 1 then
        if not l.crushed or self.clock - l.crushed > 0.5 then
            l.crushed = self.clock
            l.hp = l.hp - 20
        end
        return
    end
    self:cut(l)
end

function Game:repairCost(l) return max(1, floor(l.cost * D.LINK.repair + 0.5)) end

-- The cut links a hand could regrow, nearest the Heart first: by the fewest
-- hops to a fed end, then by how far that end is from the Heart.
function Game:repairable()
    local list, h = {}, self.heart
    for _, l in ipairs(self.links) do
        if l.state == "cut" and not l.hand and not l.salted then
            local hop = min(l.a.conn and l.a.hop or huge, l.b.conn and l.b.hop or huge)
            local d = min(dist(l.a, h), dist(l.b, h))
            list[#list + 1] = { l = l, hop = hop, d = d }
        end
    end
    table.sort(list, function(x, y) if x.hop ~= y.hop then return x.hop < y.hop end return x.d < y.d end)
    for k, e in ipairs(list) do list[k] = e.l end
    return list
end

-- Regrows every cut link it can pay for, nearest the Heart first, stopping at
-- the first it cannot afford. Returns how many.
function Game:repairAll()
    local n = 0
    for _, l in ipairs(self:repairable()) do
        if not self:repair(l) then break end
        n = n + 1
    end
    return n
end

function Game:repair(l)
    if l.state ~= "cut" or l.hand or l.salted then return false end
    local c = self:repairCost(l)
    if self.nutrients < c then return false end
    self.nutrients = self.nutrients - c
    l.hand = true
    local mx, mz = (l.a.x + l.b.x) / 2, (l.a.z + l.b.z) / 2
    self:motes(mx, 1, mz, 5, { "l", "c" }, 4, 10, 0.5)
    self:cue("mend", mx, mz)
    return true
end

--- fairy rings and the pulse ---------------------------------------------------------

local function inPoly(poly, x, z)
    local inside, n = false, #poly
    local j = n
    for i = 1, n do
        local a, b = poly[i], poly[j]
        if (a.z > z) ~= (b.z > z) and x < (b.x - a.x) * (z - a.z) / (b.z - a.z) + a.x then inside = not inside end
        j = i
    end
    return inside
end
Game.inPoly = inPoly

-- Every shortest loop of four or more fed nodes through a living link.
function Game:findRings()
    local live = {}
    for _, l in ipairs(self.links) do
        if alive(l) and l.a.conn and l.b.conn then live[#live + 1] = l.id end
    end
    local key = table.concat(live, ",")
    if key == self.ringKey then return end
    local before = {}
    for _, r in ipairs(self.rings) do before[r.key] = true end
    self.ringKey, self.rings = key, {}
    local seen = {}
    for _, l in ipairs(self.links) do
        if alive(l) and l.a.conn and l.b.conn then
            -- The shortest way round from one end to the other without this link.
            local back, queue, head = { [l.a] = false }, { l.a }, 1
            while queue[head] and back[l.b] == nil do
                local n = queue[head]
                head = head + 1
                for _, o in ipairs(n.links) do
                    if o ~= l and alive(o) then
                        local m = o.a == n and o.b or o.a
                        if back[m] == nil and m.conn then back[m] = n; queue[#queue + 1] = m end
                    end
                end
            end
            if back[l.b] ~= nil then
                local loop, n = {}, l.b
                while n do loop[#loop + 1] = n; n = back[n] end
                if #loop >= (self.level.ringNodes or D.RING.nodes) then
                    local ids = {}
                    for k, m in ipairs(loop) do ids[k] = m.id end
                    table.sort(ids)
                    local k = table.concat(ids, ",")
                    local area = 0
                    for i = 1, #loop do
                        local a, b = loop[i], loop[i % #loop + 1]
                        area = area + a.x * b.z - b.x * a.z
                    end
                    if not seen[k] and abs(area) > 1500 then -- a sliver is not a ring
                        seen[k] = true
                        self.rings[#self.rings + 1] = { nodes = loop, set = {}, key = k }
                        for _, m in ipairs(loop) do self.rings[#self.rings].set[m] = true end
                        self.events.ring = true
                        if not before[k] then
                            -- Closed (or back): caps spring up along it, and the
                            -- first time a ring is made, it chimes.
                            for _, m in ipairs(loop) do self:motes(m.x, 1, m.z, 4, { "w", "l", "g" }, 4, 14, 0.9) end
                            self.ringsMade = self.ringsMade or {}
                            if not self.ringsMade[k] then
                                self.ringsMade[k] = true
                                self:cue("ring", loop[1].x, loop[1].z)
                            end
                        end
                    end
                end
            end
        end
    end
    for _, n in ipairs(self.nodes) do n.ringed = self:ringed(n.x, n.z, n) end
end

-- The branch below a node: itself and every node whose way to the Heart runs
-- through it, up to `depth` hops further out. Cut off, it is the node alone.
function Game:branch(node, depth)
    local set = { [node] = true }
    if not node.conn then return set end
    for _, o in ipairs(self.nodes) do
        local p, k = o, 0
        while p and p ~= node and k < depth do p, k = p.parent, k + 1 end
        if p == node then set[o] = true end
    end
    return set
end

-- What a tower is linked to over living links.
function Game:neighbours(node)
    local out = {}
    for _, l in ipairs(node.links) do
        if alive(l) then out[#out + 1] = l.a == node and l.b or l.a end
    end
    return out
end

-- How many hops out from the Heart a fed node is, for the rules that like
-- the far end of a branch; 1 if it is cut off.
function Game:depth(node)
    return node.conn and node.hop or 1
end

-- Inside a ring (or one of the nodes that make it)?
function Game:ringed(x, z, node)
    for _, r in ipairs(self.rings) do
        if (node and r.set[node]) or inPoly(r.nodes, x, z) then return true end
    end
    return false
end

-- Send a surge from the Heart down to `node`, overcharging every tower on the way.
function Game:canPulse(node)
    return node and node.conn and self.pulseCd <= 0 and self:hasPulse()
end

function Game:pulse(node)
    if not self:canPulse(node) then return false end
    self.pulseCd = self:pulseCooldown()
    local n = node
    while n do
        if n.tower then n.tower.boost = self:pulseDuration() end
        if n.via then n.via.surge = self:pulseDuration() end
        n = n.parent
    end
    self:burst(node.x, node.y + 4, node.z, 12, { "l", "w", "c" }, 26)
    self:shock(node.x, node.z, 30, 0.5, "l", "w")
    self:shock(self.heart.x, self.heart.z, 16, 0.4, "l", "c")
    self:cue("pulse", node.x, node.z)
    return true
end

--- fruiting bodies ----------------------------------------------------------------------

-- A stat of a tower (or a mat or shelf) at its branch and tier, as far as
-- the network has grown it.
function Game:stat(t, k)
    local d = D.TOWER[t.kind]
    if t.branch then
        local b = d.up[t.branch]
        for tier = t.tier, 1, -1 do
            local v = b[tier][k]
            if v ~= nil then return N.value(self.net, t.kind, k, v) end
        end
    end
    return N.value(self.net, t.kind, k, d[k])
end

-- What growing a species costs, and one of its upgrades: dearer while the
-- network has not grown its thrift.
function Game:towerCost(kind) return floor(N.value(self.net, kind, "cost", D.TOWER[kind].cost) + 0.5) end
function Game:upCost(kind, row) return floor(N.value(self.net, kind, "cost", row.cost) + 0.5) end

function Game:reserveMax(t)
    local r = self:stat(t, "reserve") or 0
    return r * (t.battery or 1) * (self.mods.store and 1.5 or 1)
end

function Game:maxHp(t) return self:stat(t, "hp") or 30 end

-- What the network learned of an enemy's kind: how hard it is hit, and
-- what its body is worth drunk.
function Game:vs(kind) return N.vs(self.net, kind) end
function Game:corpseValue(kind) return D.ENEMIES[kind].corpse * N.loot(self.net, kind) end

-- The wave that has to be cleared before a species can be grown, on this level.
function Game:unlockAt(kind) return D.unlockAt(self.level, kind, self.loadout) end

-- Was this species brought on the run?
function Game:brought(kind)
    return (not self.loadout or self.loadout[kind] == true) and N.has(self.net, "species", kind)
end

-- Has the wave that brings this species been cleared?
function Game:unlocked(kind)
    return self:unlockAt(kind) <= self.cleared
end

function Game:canBuild(kind, node)
    local d = D.TOWER[kind]
    if not node or node.heart or node.tower then return false end
    if not self:brought(kind) then return false, "LEFT AT HOME" end
    if not self:unlocked(kind) then return false, "UNLOCKS AFTER WAVE " .. self:unlockAt(kind) end
    if d.unique and self.uniques[kind] then return false, "ONE PER RUN" end
    if (node.salted or 0) > 0 then return false, "SALTED" end
    if self.nutrients < self:towerCost(kind) then return false, "NOT ENOUGH NUTRIENTS" end
    return true
end

local function newTower(kind, cost)
    return { kind = kind, tier = 0, reserve = 0, cool = 0.3, squash = 0, flash = 0, spent = cost,
        grown = 0, battery = 1, amp = 1, ink = 1, webbed = 0, stun = 0, fired = 0 }
end

function Game:build(kind, node)
    if not self:canBuild(kind, node) then return false end
    local cost = self:towerCost(kind)
    self.nutrients = self.nutrients - cost
    return self:plant(kind, node, cost)
end

-- A fruiting body put on a node, paid for (`cost`) or not.
function Game:plant(kind, node, cost)
    local d = D.TOWER[kind]
    local t = newTower(kind, cost)
    t.node, t.hp = node, self:maxHp(t)
    t.reserve = self:stat(t, "reserve") or 0
    node.tower = t
    if d.unique then self.uniques[kind] = true end
    self:burst(node.x, node.y + 2, node.z, 8, { "l", "c", "w" }, 14)
    self:shock(node.x, node.z, 12, 0.35, "l", "c")
    self:motes(node.x, node.y + 2, node.z, 8, { "l", "c" }, 6, 16, 0.7)
    self:cue("build", node.x, node.z)
    self:recompute()
    return t
end

-- The upgrades open to a tower: both branches' first tier, or its branch's
-- next; only what the network has grown of them. `cost` is what it costs here.
function Game:upgrades(t)
    local d = D.TOWER[t.kind]
    if not d.up then return {} end
    local list = {}
    local function offer(branch, tier)
        if tier <= N.tier(self.net, t.kind, branch) then
            local row = d.up[branch][tier]
            list[#list + 1] = { branch = branch, tier = tier, row = row, cost = self:upCost(t.kind, row) }
        end
    end
    if not t.branch then
        offer(1, 1)
        offer(2, 1)
    elseif t.tier < 2 then
        offer(t.branch, t.tier + 1)
    end
    return list
end

function Game:canUpgrade(t, branch)
    for _, u in ipairs(self:upgrades(t)) do
        if u.branch == branch then
            if self.nutrients < u.cost then return false, "NOT ENOUGH NUTRIENTS", u end
            return true, nil, u
        end
    end
    return false
end

function Game:upgrade(t, branch)
    local ok, _, u = self:canUpgrade(t, branch)
    if not ok then return false end
    local before = self:maxHp(t)
    self.nutrients = self.nutrients - u.cost
    t.branch, t.tier, t.spent = u.branch, u.tier, t.spent + u.cost
    t.grown = 0
    t.hp = (t.hp or before) + (self:maxHp(t) - before)
    local x, y, z = t.node and t.node.x or t.x, t.node and t.node.y or 0, t.node and t.node.z or t.z
    self:burst(x, y + 6, z, 16, { "l", "w", "c" }, 22)
    self:shock(x, z, 16, 0.45, "w", "l")
    self:motes(x, y + 2, z, 16, { "l", "w", "w" }, 7, 22, 0.9)
    self:cue("upgrade", x, z)
    self:say(u.row.name, x, y + 18, z, "l")
    self:recompute()
    return true
end

function Game:sell(node)
    local t = node.tower
    if not t then return end
    local back = floor(t.spent * D.SELL)
    self.nutrients = self.nutrients + back
    self:say("+" .. back, node.x, node.y + 10, node.z)
    self:burst(node.x, node.y + 4, node.z, 8, { "t", "n", "w" }, 16)
    self:motes(node.x, node.y + 2, node.z, 6, { "l" }, 5, 18, 0.5)
    self:cue("sell", node.x, node.z)
    node.tower = nil
    self:recompute()
end

function Game:destroyTower(node, why)
    if not node.tower then return end
    self:burst(node.x, node.y + 6, node.z, 14, { "t", "w", "r" }, 24)
    self:shock(node.x, node.z, 12, 0.35, "r", "t")
    self:splat(node.x, node.z, 7, "u", 4)
    self:cue("die", node.x, node.z)
    self:say(why, node.x, node.y + 14, node.z, "r")
    node.tower = nil
    self:recompute()
end

-- Mats and shelves: laid on a trail tile rather than grown on a pocket.
function Game:matAt(c, r)
    for _, m in ipairs(self.mats) do if m.c == c and m.r == r then return m end end
end

function Game:canLay(kind, c, r)
    local d = D.TOWER[kind]
    if not self.world:distAt(c, r) or self.world.cell(c, r) == "H" then return false end
    if not self:brought(kind) then return false, "LEFT AT HOME" end
    if not self:unlocked(kind) then return false, "UNLOCKS AFTER WAVE " .. self:unlockAt(kind) end
    if self:matAt(c, r) then return false, "TILE TAKEN" end
    if d.touch then
        local x, z = c * TILE + TILE / 2, r * TILE + TILE / 2
        local near = false
        for _, l in ipairs(self.links) do
            if alive(l) and l.a.conn and segDist(x, z, l.a.x, l.a.z, l.b.x, l.b.z) <= d.touch then near = true break end
        end
        if not near then return false, "MUST GROW BESIDE A FED LINK" end
    end
    if self.nutrients < self:towerCost(kind) then return false, "NOT ENOUGH NUTRIENTS" end
    return true
end

function Game:lay(kind, c, r)
    if not self:canLay(kind, c, r) then return false end
    local cost = self:towerCost(kind)
    self.nutrients = self.nutrients - cost
    local m = newTower(kind, cost)
    m.c, m.r, m.x, m.z = c, r, c * TILE + TILE / 2, r * TILE + TILE / 2
    m.y = self.world:groundAt(m.x, m.z)
    m.life, m.hp = self:stat(m, "life"), self:stat(m, "hp")
    self.mats[#self.mats + 1] = m
    self:burst(m.x, 2, m.z, 8, { "l", "c", "w" }, 14)
    self:shock(m.x, m.z, 11, 0.3, kind == "shelf" and "t" or "c", "l")
    self:cue("lay", m.x, m.z)
    return m
end

-- What lifting it pays back: less the more it has worn.
function Game:liftValue(m)
    local left = m.kind == "mat" and m.life / self:stat(m, "life") or m.hp / self:maxHp(m)
    return floor(m.spent * D.SELL * max(0, min(1, left)))
end

function Game:liftMat(m)
    local back = self:liftValue(m)
    self.nutrients = self.nutrients + back
    self:say("+" .. back, m.x, 8, m.z)
    self:burst(m.x, 2, m.z, 6, m.kind == "shelf" and { "t", "n" } or { "c", "l" }, 12)
    self:cue("lift", m.x, m.z)
    unlist(self.mats, m)
end

function Game:breakMat(m)
    unlist(self.mats, m)
    self:burst(m.x, 3, m.z, 12, m.kind == "shelf" and { "t", "n", "w" } or { "l", "c" }, 22)
    self:splat(m.x, m.z, 6, m.kind == "shelf" and "n" or "d", 3)
    self:cue("smash", m.x, m.z)
end

--- waves ---------------------------------------------------------------------------------

-- In endless the waves never run out: each one past the last is made when it
-- is first asked for.
function Game:nextWave()
    if self.endless and not self.waves[self.wave + 1] then self.waves[self.wave + 1] = self:endlessWave(self.wave + 1) end
    return self.waves[self.wave + 1]
end

-- Endless: after the level is won the run goes on. Wave n past the last is
-- one of the level's own later waves (one with a boss every fifth, every
-- fourth past 20, every third past 40), more of everything, closer together,
-- and the enemies tougher each wave than the last, bosses too. From 10 a boss
-- wave brings an extra boss from the level's own, and another every 10 more.
function Game:goEndless()
    if self.phase ~= "won" then return end
    self.endless = true
    self.endlessFrom = #self.waves
    self.phase = "build"
    local bonus = self:waveBonus()
    self.nutrients = self.nutrients + bonus
    self:say("ENDLESS +" .. bonus, self.heart.x, 26, self.heart.z, "r")
    self:cue("clear")
end

-- How many waves past the level's last this one is (0 before endless).
function Game:endlessDepth(wave)
    if not self.endless then return 0 end
    return max(0, (wave or self.wave) - self.endlessFrom)
end

function Game:endlessWave(n)
    local k = n - self.endlessFrom
    local plain, bossy = {}, {}
    local waves = self.level.waves
    for i = max(1, floor(#waves / 2)), #waves do
        local boss = false
        for _, g in ipairs(waves[i]) do if D.ENEMIES[g[1]].boss then boss = true end end
        if boss then bossy[#bossy + 1] = waves[i] else plain[#plain + 1] = waves[i] end
    end
    if not bossy[1] then
        for _, w in ipairs(waves) do
            for _, g in ipairs(w) do if D.ENEMIES[g[1]].boss then bossy[#bossy + 1] = w; break end end
        end
    end
    local apart = k > 40 and 3 or (k > 20 and 4 or 5)
    local bossWave = k % apart == 0 and bossy[1]
    local from = bossWave and bossy[self.dice:random(#bossy)] or plain[self.dice:random(#plain)] or waves[#waves]
    local more, closer = 1 + 0.12 * k, 1 / (1 + 0.06 * k)
    local weathers = { false, "rain", "night", "drought", "frost" }
    local w = { weather = from.weather }
    if self.dice:random() < 0.5 then w.weather = weathers[self.dice:random(#weathers)] or nil end
    for _, g in ipairs(from) do
        local boss = D.ENEMIES[g[1]].boss
        local count = boss and g[2] or max(1, floor(g[2] * more + 0.5))
        local every = boss and g[3] or max(0.25, g[3] * closer)
        -- At full strength: a boss met weaker part way through the level is not here.
        w[#w + 1] = { g[1], count, every, g[4], g[5] * closer }
    end
    if bossWave then
        -- The level's bosses, and the gates its waves come in at.
        local bosses, seen, gates = {}, {}, {}
        for _, wv in ipairs(waves) do
            for _, g in ipairs(wv) do
                if D.ENEMIES[g[1]].boss and not seen[g[1]] then seen[g[1]] = true; bosses[#bosses + 1] = g[1] end
                gates[#gates + 1] = g[4]
            end
        end
        for x = 1, floor(k / 10) do
            w[#w + 1] = { bosses[self.dice:random(#bosses)], 1, 1, gates[self.dice:random(#gates)], 4 + 6 * x }
        end
    end
    return w
end

function Game:startWave()
    if self.phase ~= "build" or not self:nextWave() then return end
    self.wave = self.wave + 1
    self.phase = "wave"
    self.waveClock = 0
    self.queue = {}
    self.weather = self.waves[self.wave].weather
    for _, g in ipairs(self.waves[self.wave]) do
        local kind, n, every, gate, at = g[1], g[2], g[3], g[4], g[5]
        for k = 0, n - 1 do
            self.queue[#self.queue + 1] = { kind = kind, gate = gate, t = at + k * every, hp = g[6] }
        end
    end
    table.sort(self.queue, function(a, b) return a.t < b.t end)
    -- Each gate the wave comes in at shakes a little dust loose.
    local gates = {}
    for _, g in ipairs(self.waves[self.wave]) do gates[g[4]] = true end
    for g in pairs(gates) do
        local e = self.world.entrances[g]
        if e then
            self:shock(e.x, e.z, 14, 0.6, "r", "t")
            self:motes(e.x, 1, e.z, 8, { "t", "n" }, 8, 10, 0.8)
        end
    end
    self:cue("wave", self.heart.x, self.heart.z)
end

function Game:spawnAt(kind, x, z, c, r)
    local d = D.ENEMIES[kind]
    local scale = d.boss and 1 or 1 + (self.level.growth or D.HP_GROWTH) * (self.wave - 1)
    -- Endless: everything tougher each wave than the last, bosses too.
    scale = scale * (self.spawnScale or 1) -- a wave's own say: a boss met mid-level comes in weaker
    local deep = self:endlessDepth()
    if deep > 0 then scale = scale * 1.07 ^ deep * (d.boss and 1 + 0.05 * deep or 1) end
    local hp = d.hp * scale
    local en = { kind = kind, x = x, z = z, y = 0, c = c, r = r, tc = c, tr = r,
        hp = hp, maxHp = hp, h = 0, flash = 0, slow = 1, off = (self.dice:random() - 0.5) * 6,
        walked = 0, anim = self.dice:random() * 4, state = "walk", boss = d.boss, stun = 0, mark = 0 }
    if d.boss then en.off = 0 end
    en.y = self.world:groundAt(x, z)
    if d.fly then en.y = 12 end
    if d.ball then en.ballHp = d.ball * (self.spawnScale or 1); en.ballMax = en.ballHp end
    if d.chargeEvery then en.charge = d.chargeEvery * 0.6 end
    if d.broodEvery then en.brood = d.broodEvery * 0.5 end
    if d.webCd then en.webCd = 1 end
    if d.grabEvery then en.grabCd = d.grabEvery * 0.6 end
    if d.sprayEvery then en.spray = d.sprayEvery * 0.5 end
    if d.hopEvery then en.hopCd = d.hopEvery * self.dice:random() end
    if d.clickEvery then en.clickCd = d.clickEvery * 0.6 end
    if d.digEvery then en.digCd, en.digs = d.digEvery * 0.5, 0 end
    if d.sinkEvery then en.sinkCd, en.cut = d.sinkEvery * (0.5 + self.dice:random() * 0.5), 0 end
    if d.moth then en.y = 10 end
    self.enemies[#self.enemies + 1] = en
    return en
end

function Game:spawn(kind, gate)
    local e = self.world.entrances[gate] or self.world.entrances[1]
    local d = D.ENEMIES[kind]
    self.seen[kind] = true
    -- From off the left edge, or up out of a hole in the floor.
    local x, z = e.x - (e.hole and 0 or TILE * 0.6), e.z
    if kind == "mite" then
        for _ = 1, d.swarm do self:spawnAt(kind, x + (self.dice:random() - 0.5) * 10, z + (self.dice:random() - 0.5) * 10, e.c, e.r) end
    else
        local en = self:spawnAt(kind, x, z, e.c, e.r)
        if d.segments then
            -- The train: each segment waits its turn at the gate, then follows
            -- the one ahead of it.
            local train = { n = d.segments + 1, max = en.hp, gap = d.gap }
            en.train = train
            local prev = en
            for k = 1, d.segments do
                local s = self:spawnAt(d.seg, x, z, e.c, e.r)
                s.leader, s.train, s.hidden, s.h = prev, train, k * d.gap / d.speed, 0
                train.max = train.max + s.hp
                prev = s
            end
        end
        if d.boss then
            self.events.boss = kind
            self.bossIntro = { kind = kind, t = 3.5 }
            self:cue("boss", x, z)
            self:shock(x, z, 30, 0.8, "r", "t")
        end
        return en
    end
end

--- harm -------------------------------------------------------------------------------------

function Game:burst(x, y, z, n, keys, speed)
    for _ = 1, n do
        local a, u = self.dice:random() * 2 * math.pi, self.dice:random()
        self.fx[#self.fx + 1] = {
            x = x, y = y, z = z,
            vx = cos(a) * speed * u, vy = speed * (0.4 + self.dice:random()), vz = sin(a) * speed * u,
            life = 0.3 + self.dice:random() * 0.3, k = keys[self.dice:random(#keys)],
        }
    end
end

-- The same, for looks alone: thrown off a hit, not rolled by the rules.
function Game:sparks(x, y, z, n, keys, speed)
    if #self.fx > 500 then return end
    for _ = 1, n do
        local a, u = fr() * 2 * math.pi, fr()
        self.fx[#self.fx + 1] = {
            x = x, y = y, z = z,
            vx = cos(a) * speed * u, vy = speed * (0.3 + fr()), vz = sin(a) * speed * u,
            life = 0.15 + fr() * 0.2, k = keys[floor(fr() * #keys) + 1],
        }
    end
end

-- Specks drifting up and away round (x, y, z): sparkle off a new tower, dust
-- off a footfall, glow off a mended thread.
function Game:motes(x, y, z, n, keys, spread, speed, life)
    if #self.fx > 500 then return end
    for _ = 1, n do
        local a, u = fr() * 2 * math.pi, fr() * spread
        self.fx[#self.fx + 1] = { x = x + cos(a) * u, y = y + fr() * 3, z = z + sin(a) * u, vx = 0, vz = 0,
            vy = speed * (0.5 + fr()), life = life * (0.5 + 0.5 * fr()), k = keys[floor(fr() * #keys) + 1], rise = true }
    end
end

-- A ring running out over the ground from (x, z) to `r`: a landing, a blast,
-- something grown. `k` its leading edge, `k2` behind it.
function Game:shock(x, z, r, life, k, k2)
    self.fx[#self.fx + 1] = { shock = true, x = x, z = z, r = r, life = life, max = life, k = k, k2 = k2 }
end

-- A stain on the ground that wears away: what a kill or a blast leaves.
function Game:splat(x, z, r, k, life)
    life = life or 3
    self.fx[#self.fx + 1] = { splat = true, x = x, z = z, r = r, k = k, life = life, max = life, seed = floor(fr() * 997) }
end

function Game:armor(e)
    local d = D.ENEMIES[e.kind]
    if e.rolling then return d.rolledArmor end
    if e.state == "belly" then return 0 end
    return d.armor
end

-- `quiet` is damage over time: no flash, so a poisoned ant does not strobe.
function Game:hurt(e, amount, pierce, quiet)
    -- Under water, or not yet out of the gate: nothing reaches it.
    if e.dead or e.under or e.hidden then return 0 end
    if e.mark > 0 then amount = amount * (e.markMul or 1) end
    amount = amount * self:vs(e.kind)
    -- On its back, a click beetle is soft.
    if e.state == "belly" then amount = amount * (D.ENEMIES[e.kind].belly or 1) end
    local a = pierce and 0 or self:armor(e)
    local dmg = quiet and amount or max(amount * 0.15, amount - a)
    if not quiet then
        -- Most of it turned by a shell: it rings, and the sparks are grey.
        local glance = a > 0 and dmg < amount * 0.5
        local size = D.ENEMIES[e.kind].size or 1
        self:sparks(e.x, e.y + 3 * size, e.z, glance and 3 or 2, glance and { "s", "w" } or { "w", "t" }, glance and 22 or 14)
        self:cue(glance and "clink" or "hit", e.x, e.z)
    end
    if e.ballHp and e.ballHp > 0 then
        -- The ball takes it. When it breaks, the beetle is in a hurry.
        e.ballHp = e.ballHp - dmg
        e.ballFlash = 0.08
        if e.ballHp <= 0 then self:breakBall(e) end
        return dmg
    end
    e.hp = e.hp - dmg
    if not quiet then e.flash = 0.08 end
    if e.hp <= 0 then self:kill(e) end
    return dmg
end

function Game:ballAt(e)
    local d = D.ENEMIES[e.kind]
    return e.x + cos(e.h) * d.ballAhead, e.z + sin(e.h) * d.ballAhead
end

function Game:breakBall(e)
    local d = D.ENEMIES[e.kind]
    local bx, bz = self:ballAt(e)
    e.ballHp = 0
    self:burst(bx, 8, bz, 30, { "n", "u", "t" }, 34)
    self:say("THE BALL BREAKS", bx, 22, bz, "t")
    self:shock(bx, bz, 26, 0.6, "t", "n")
    self:splat(bx, bz, 12, "n", 6)
    self:cue("ball", bx, bz)
    self.corpses[#self.corpses + 1] = { kind = "ball", x = bx, z = bz, h = e.h, value = d.ballCorpse * N.loot(self.net, e.kind), life = 40 }
    self.events.shake = 0.4
end

function Game:kill(e)
    e.dead = true
    self.stats.kills = self.stats.kills + 1
    local d = D.ENEMIES[e.kind]
    if e.carry then e.carry.carried = nil end
    if e.kind == "brine" then
        -- Salt water: nothing to drink, and a splash.
        self:burst(e.x, e.y + 2, e.z, 10, { "w", "s" }, 22)
        self:splat(e.x, e.z, 5, "s", 2)
        self:cue("splash", e.x, e.z)
        return
    end
    -- A train's boss is down only when its last segment is.
    local boss = d.boss
    if e.train then
        e.train.n = e.train.n - 1
        boss = boss and e.train.n <= 0
    end
    self:burst(e.x, 2 + e.y, e.z, e.kind == "mite" and 2 or (boss and 30 or 6), { "r", "n", "t" }, boss and 30 or 16)
    local size = d.size or 1
    if boss then
        self:cue("fell", e.x, e.z)
        self:shock(e.x, e.z, 40, 0.9, "r", "t")
        self:shock(e.x, e.z, 24, 0.6, "w", "t")
        self:splat(e.x, e.z, 16, "u", 10)
    elseif e.kind == "mite" then
        self:cue("squish", e.x, e.z, 0.5)
        self:splat(e.x, e.z, 2, "r", 1.5)
    else
        self:cue((size > 1.2 or (d.armor or 0) >= 3) and "crunch" or "squish", e.x, e.z)
        self:splat(e.x, e.z, 3 + 2 * size, "r", 2.5)
        self:sparks(e.x, e.y + 3, e.z, 4, { "r", "u" }, 20)
    end
    if boss then
        self.stats.bosses = self.stats.bosses + 1
        self.events.shake = 0.5
        self:say(d.name .. " FALLS", e.x, 30, e.z, "g")
    end
    if e.infected and e.infected > 0 then
        -- Cordyceps: the host fruits where it falls, and the spores look for the next.
        self:burst(e.x, 6, e.z, 10, { "t", "r", "w" }, 18)
        if (e.spread or 0) > 0 then
            local next = self:infectable(e.x, e.z, 34, e.hostMaxHp or 400)
            if next then
                self.shots[#self.shots + 1] = { kind = "cordy", x0 = e.x, y0 = 4, z0 = e.z, target = next,
                    tx = next.x, tz = next.z, t = 0, flight = 0.5,
                    infect = e.infectFor, spread = e.spread - 1, bite = e.hostBite, maxHp = e.hostMaxHp }
            end
        end
    end
    if d.corpse > 0 then
        self.corpses[#self.corpses + 1] = { kind = e.kind, x = e.x, z = e.z, h = e.h, value = self:corpseValue(e.kind), life = 25,
            fruit = e.infected and e.infected > 0 }
    end
end

-- The biggest host in reach a cordyceps can take.
function Game:infectable(x, z, range, maxHp)
    local best
    for _, e in ipairs(self.enemies) do
        local d = D.ENEMIES[e.kind]
        if not e.dead and not d.boss and not d.fly and e.kind ~= "brine" and not (e.infected and e.infected > 0)
            and not e.hidden and not e.under and not e.train and e.hp <= maxHp and (e.x - x) ^ 2 + (e.z - z) ^ 2 <= range * range then
            if not best or e.hp > best.hp then best = e end
        end
    end
    return best
end

function Game:infect(e, s)
    if e.dead then return end
    e.infected, e.infectFor = s.infect, s.infect
    e.spread, e.hostBite, e.hostMaxHp = s.spread or 0, s.bite, s.maxHp
    e.state, e.chewing, e.gnaw = "walk", nil, nil
    e.rolling = false
    if e.carry then e.carry.carried, e.carry = nil, nil end
    -- It turns round on the tile it stands on.
    local c, r = floor(e.x / TILE), floor(e.z / TILE)
    if self.world:distAt(c, r) then e.tc, e.tr = c, r end
    self:burst(e.x, 4, e.z, 8, { "t", "r" }, 14)
    self:shock(e.x, e.z, 8, 0.3, "t", "r")
    self:cue("infect", e.x, e.z)
    self:say("INFECTED", e.x, 12, e.z, "t")
end

--- the frame ---------------------------------------------------------------------------------

function Game:update(dt)
    self.clock = self.clock + dt
    self.events = {}
    if self.bossIntro then
        self.bossIntro.t = self.bossIntro.t - dt
        if self.bossIntro.t <= 0 then self.bossIntro = nil end
    end
    if self.phase == "won" or self.phase == "lost" or self.phase == "mutate" then
        self:updateFx(dt)
        return
    end
    for _, n in ipairs(self.nodes) do
        if n.salted and n.salted > 0 then n.salted = n.salted - dt end
    end
    if self.phase == "wave" then self.pulseCd = max(0, self.pulseCd - dt) end
    for _, l in ipairs(self.links) do
        if l.surge then
            l.surge = l.surge - dt
            if l.surge <= 0 then l.surge = nil end
        end
    end

    if self.phase == "wave" then
        self.waveClock = self.waveClock + dt
        while self.queue[1] and self.queue[1].t <= self.waveClock do
            local q = table.remove(self.queue, 1)
            self.spawnScale = q.hp
            self:spawn(q.kind, q.gate)
            self.spawnScale = nil
        end
        local living = 0
        for _, l in ipairs(self.links) do if alive(l) then living = living + 1 end end
        local income = D.INCOME * (self.seed.income or 1) - living * D.UPKEEP
            + (self.mods.sugar and 0.8 or 0) + (self.mods.overripe and 1 or 0)
        -- A rich pocket that something grows on, fed, pays its own way.
        for _, n in ipairs(self.nodes) do
            if n.conn and n.tower then income = income + World.QUALITY[n.quality].income end
        end
        self.nutrients = max(0, self.nutrients + income * dt)
        self.income = income
    else
        self.income = 0
    end

    self:updateLinks(dt)
    self:updateTowers(dt)
    self:updateMats(dt)
    if self.phase == "wave" then self:updateSeed(dt) end
    for _, e in ipairs(self.enemies) do
        if not e.dead then
            self:move(e, dt)
            -- Whatever walks stands on the ground under it (the trail is sunk a
            -- block, the pond lower still): only fliers and a slider on a
            -- thread keep their own height.
            local d = D.ENEMIES[e.kind]
            -- A hop or a leap lifts it off the ground for a moment.
            if not e.dead and not d.fly and not d.moth and not e.slide then e.y = self.world:groundAt(e.x, e.z) + (e.lift or 0) end
            -- A boss's footfalls kick up the soil; a charge, a cloud of it.
            if d.boss and not e.dead and not d.fly and not e.under and not e.hidden then
                e.stepT = (e.stepT or 0) + dt * (e.charging and 3 or 1)
                if e.stepT >= 0.55 then
                    e.stepT = 0
                    self:motes(e.x, e.y + 1, e.z, e.charging and 6 or 3, { "t", "n" }, 9, 7, 0.6)
                    self:cue("stomp", e.x, e.z)
                end
            end
        end
    end
    for k = #self.tunnels, 1, -1 do
        if self.tunnels[k].owner.dead then self:collapse(self.tunnels[k]) end
    end
    for n = #self.enemies, 1, -1 do if self.enemies[n].dead then table.remove(self.enemies, n) end end
    self:updateShots(dt)
    self:updateClouds(dt)
    self:updateCorpses(dt)
    self:updateFx(dt)
    self:recompute()

    if self.heartHp <= 0 and self.regrows > 0 then
        self:regrow()
    elseif self.heartHp <= 0 then
        self.heartHp = 0
        self.phase = "lost"
        self:cue("lost")
        self:burst(self.heart.x, 8, self.heart.z, 30, { "g", "m", "d" }, 26)
        self:shock(self.heart.x, self.heart.z, 30, 1, "r", "d")
    elseif self.phase == "wave" and not self.queue[1] and not self.enemies[1] then
        self.cleared = self.wave
        self.spores = self.spores + D.SPORES.wave
        self.inks, self.clouds, self.tunnels = {}, {}, {}
        self:seedCleared()
        self.weather = nil
        if self.endless then
            if self.cleared > self.best then self.best, self.record = self.cleared, true end
        end
        if self.wave >= #self.waves and not self.endless then
            self.phase = "won"
            self.spores = self.spores + D.SPORES.win + (self.firstWin and D.SPORES.first or 0)
            self:cue("won")
            self:shock(self.heart.x, self.heart.z, 50, 1.2, "g", "l")
            self:motes(self.heart.x, 4, self.heart.z, 40, { "g", "l", "w" }, 26, 26, 1.6)
        else
            self.phase = "build"
            local bonus = self:waveBonus()
            self.nutrients = self.nutrients + bonus
            self:say("WAVE CLEAR +" .. bonus, self.heart.x, 26, self.heart.z, "g")
            self:cue("clear")
            self:shock(self.heart.x, self.heart.z, 36, 0.8, "g", "l")
            self:motes(self.heart.x, 4, self.heart.z, 18, { "g", "l" }, 12, 22, 1.1)
            for _, t in ipairs(D.TOWERS) do
                if self:brought(t.id) and self:unlockAt(t.id) == self.cleared then
                    self.events.unlock = t.id; self.newSpecies = t.id
                    self:cue("unlock")
                end
            end
            if self.mods.drift then self:drift() end
            if self.level.mutateAfter[self.wave] or (self:endlessDepth() > 0 and self:endlessDepth() % 4 == 0) then
                self:offerMutations()
            end
        end
    end
end

--- mutations --------------------------------------------------------------------------------

-- Three cards: one of the seed's own while it has any left, the rest from
-- the mutations every seed shares (and the seed's, once those run out).
function Game:offerMutations()
    local pool, own = {}, {}
    for _, m in ipairs(D.MUTATIONS) do
        -- Only what the network has grown, and nothing for a pulse it has not.
        if not self.mods[m.id] and N.has(self.net, "mutations", m.id)
            and (self:hasPulse() or (m.id ~= "pulse" and m.id ~= "chute")) then
            if m.seed == self.seed.id then own[#own + 1] = m
            elseif not m.seed then pool[#pool + 1] = m end
        end
    end
    self.choices = {}
    if own[1] then self.choices[1] = table.remove(own, self.dice:random(#own)) end
    for _, m in ipairs(own) do pool[#pool + 1] = m end
    while #self.choices < 3 and pool[1] do
        self.choices[#self.choices + 1] = table.remove(pool, self.dice:random(#pool))
    end
    if self.choices[1] then
        self.phase = "mutate"
        self:cue("offer")
    end
end

function Game:mutate(n)
    local m = self.phase == "mutate" and self.choices[n]
    if not m then return false end
    self.mods[m.id] = true
    self.picked[#self.picked + 1] = m
    if m.id == "thick" then
        for _, l in ipairs(self.links) do l.hp = l.hp * 1.5 end
    elseif m.id == "roots" then
        self.heartMax = self.heartMax + 5
        self.heartHp = self.heartMax
    elseif m.id == "bark" then
        for _, l in ipairs(self.heart.links) do l.hp = l.hp * 3 end
    elseif m.id == "pod" then
        self.pods = self.pods + 3
    elseif m.id == "clock" then
        self.regrows = self.regrows + 1
    end
    self.choices = nil
    self.phase = "build"
    self:say(m.name, self.heart.x, 30, self.heart.z, "l")
    self:burst(self.heart.x, 10, self.heart.z, 20, { "l", "c", "w" }, 26)
    self:shock(self.heart.x, self.heart.z, 40, 0.8, "l", "c")
    self:motes(self.heart.x, 4, self.heart.z, 24, { "l", "c", "w" }, 16, 24, 1.2)
    self:cue("mutate")
    return true
end

--- the seed ------------------------------------------------------------------------------------

-- A dandelion killed comes back at half its HP, and the wave goes on.
function Game:regrow()
    self.regrows = self.regrows - 1
    self.heartHp = max(1, floor(self.heartMax * 0.5 + 0.5))
    local h = self.heart
    if self.mods.taproot then
        for _, l in ipairs(self.links) do
            if l.state == "cut" and not l.salted then l.regrow = 1 end
        end
    end
    self.events.regrow = true
    self:say("THE DANDELION REGROWS", h.x, 30, h.z, "g")
    self:burst(h.x, 12, h.z, 30, { "w", "s", "g" }, 30)
    self:shock(h.x, h.z, 40, 0.9, "w", "g")
    self:motes(h.x, 8, h.z, 30, { "w", "s" }, 30, 20, 2)
    self:cue("clear", h.x, h.z)
end

-- What the seed does each frame of a wave: the flytrap's snap, the oak's
-- acorns, the sunflower's stem, the sundew's glue.
function Game:updateSeed(dt)
    local h = self.heart
    local trap = self.seed.trap
    if trap then
        self.trapCd = self.trapCd - dt
        local range = trap.range * (self.mods.jaws and 1.4 or 1)
        if self.trapCd <= 0 then
            local best, bd = nil, range * range
            for _, e in ipairs(self.enemies) do
                if not e.dead and not e.under and not e.hidden then
                    local d2 = (e.x - h.x) ^ 2 + (e.z - h.z) ^ 2
                    if d2 <= bd then best, bd = e, d2 end
                end
            end
            if best then
                self.trapCd = trap.every * (self.mods.hairs and 0.6 or 1)
                self:snap(best, trap)
            end
        end
    end
    if self.mods.acorn then
        self.acornCd = self.acornCd - dt
        if self.acornCd <= 0 then
            local best, bd = nil, 60 * 60
            for _, e in ipairs(self.enemies) do
                if not e.dead and not e.under and not e.hidden then
                    local d2 = (e.x - h.x) ^ 2 + (e.z - h.z) ^ 2
                    if d2 <= bd then best, bd = e, d2 end
                end
            end
            if best then
                self.acornCd = 6
                self:hurt(best, 30, true)
                if not best.dead and not D.ENEMIES[best.kind].boss then best.stun = max(best.stun, 1) end
                self:burst(best.x, 6, best.z, 8, { "n", "t", "u" }, 18)
                self:shock(best.x, best.z, 10, 0.3, "t", "n")
                self:cue("thump", best.x, best.z)
            end
        end
    end
    if self.mods.stem or self.mods.sundew then
        for _, e in ipairs(self.enemies) do
            if not e.dead and not e.under and not e.hidden then
                local d = D.ENEMIES[e.kind]
                local d2 = (e.x - h.x) ^ 2 + (e.z - h.z) ^ 2
                if self.mods.stem and d.fly and d2 <= 36 * 36 then self:hurt(e, 8 * dt, true, true) end
                if self.mods.sundew and not d.fly and not d.noSlow and d2 <= 40 * 40 then
                    e.stick = min((e.stickT or 0) > 0 and e.stick or 1, 0.5)
                    e.stickT = max(e.stickT or 0, 0.2)
                end
            end
        end
    end
end

-- The flytrap shuts on one: eaten whole if it is small enough, else bitten.
function Game:snap(e, trap)
    local d = D.ENEMIES[e.kind]
    local eat = self.mods.jaws and 80 or trap.eat
    self.snapped = self.clock -- the jaws are drawn shut for a moment
    self:cue("clack", e.x, e.z)
    self:shock(e.x, e.z, 8, 0.25, "g", "m")
    if not d.boss and e.hp <= eat and not (e.ballHp and e.ballHp > 0) then
        self:kill(e)
        self.heartHp = min(self.heartMax, self.heartHp + trap.heal)
        if self.mods.digest and d.corpse > 0 then
            local v = self:corpseValue(e.kind)
            self.nutrients = self.nutrients + v
            self:say("+" .. floor(v + 0.5), e.x, 10, e.z, "g")
        end
        self:burst(e.x, 4, e.z, 6, { "g", "r" }, 16)
    else
        self:hurt(e, trap.bite)
    end
end

-- A tomato's Splat: what reached the sprout bursts a fruit on those near it.
function Game:splatFruit()
    local h = self.heart
    for _, e in ipairs(self.enemies) do
        if not e.dead and not e.under and not e.hidden and (e.x - h.x) ^ 2 + (e.z - h.z) ^ 2 <= 36 * 36 then
            self:hurt(e, 15)
            if not e.dead and not D.ENEMIES[e.kind].noSlow then e.stick, e.stickT = 0.5, 3 end
        end
    end
    self:splat(h.x, h.z, 14, "r", 4)
    self:burst(h.x, 6, h.z, 14, { "r", "w" }, 26)
    self:cue("splash", h.x, h.z)
end

-- What the seed does when a wave is cleared.
function Game:seedCleared()
    local h = self.heart
    if self.mods.growth then
        self.heartMax = self.heartMax + 1
        self.heartHp = self.heartHp + 1
    end
    if self.mods.seedhead then
        local n = 0
        for _, o in ipairs(self.nodes) do if o.tower and self:sunlit(o) then n = n + 1 end end
        if n > 0 then
            self.nutrients = self.nutrients + 4 * n
            self:say("SEED HEAD +" .. 4 * n, h.x, 38, h.z, "t")
        end
    end
    if self.mods.compost then
        local paid = 0
        for k = #self.corpses, 1, -1 do
            local c = self.corpses[k]
            if not c.absorb and not c.carried then
                paid = paid + c.value * 0.5
                table.remove(self.corpses, k)
            end
        end
        paid = floor(paid + 0.5)
        if paid > 0 then
            self.nutrients = self.nutrients + paid
            self:say("COMPOST +" .. paid, h.x, 46, h.z, "l")
        end
    end
end

-- A dandelion's Seed Drift: a puffer on an empty fed pocket, free.
function Game:drift()
    local open = {}
    for _, n in ipairs(self.nodes) do
        if n.conn and not n.heart and not n.tower and (n.salted or 0) <= 0 then open[#open + 1] = n end
    end
    if not open[1] then return end
    local n = open[self.dice:random(#open)]
    self:plant("puffer", n, 0)
    self:say("SEED DRIFT", n.x, n.y + 18, n.z, "w")
end

--- links, towers, mats -----------------------------------------------------------------------

function Game:updateLinks(dt)
    local changed = false
    local quick = (self.mods.quick and 2 or 1) * (self:sky().grow or 1) * (self.seed.grow or 1)
    for _, l in ipairs(self.links) do
        local full = self:linkFull(l)
        if l.flash then
            l.flash = l.flash - dt
            if l.flash <= 0 then l.flash = nil end
        end
        if l.state == "grow" then
            l.grow = l.grow + quick * dt * 16 / (self:linkGrow() * max(16, l.len))
            if l.grow >= 1 then
                l.state, l.grow, changed = "alive", 1, true
                l.flash = 0.35
                self:motes(l.b.x, l.b.y, l.b.z, 5, { "l", "c" }, 3, 12, 0.5)
                self:cue("linked", l.b.x, l.b.z)
            end
        elseif l.state == "alive" then
            if l.hp <= 0 then self:cut(l) end
        elseif l.state == "cut" then
            if l.hand then
                l.regrow = l.regrow + quick * dt / D.LINK.regrow
            end
            if l.regrow >= 1 then
                l.state, l.hp, l.hand, changed = "alive", full * 0.6, false, true
                l.bitten = {}
                l.flash = 0.35
                local mx, mz = (l.a.x + l.b.x) / 2, (l.a.z + l.b.z) / 2
                self:motes(mx, 1, mz, 4, { "l", "c" }, 3, 12, 0.5)
                self:cue("regrow", mx, mz)
            end
        end
    end
    if changed then self:recompute() end
end

-- Feeding and firing.
function Game:updateTowers(dt)
    local Q = World.QUALITY
    local wash = self:sky().wash
    for _, n in ipairs(self.nodes) do
        local t = n.tower
        if t then
            local d = D.TOWER[t.kind]
            t.flash = max(0, t.flash - dt)
            t.squash = max(0, t.squash - dt * 4)
            -- The Humongous Fungus takes its time coming up; an upgrade is quicker.
            t.grown = min(1, t.grown + dt * ((d.growTime and t.tier == 0) and 1 / d.growTime or 1.6))
            t.webbed = max(0, t.webbed - dt)
            t.stun = max(0, t.stun - dt)
            t.fired = t.fired + dt
            -- Rain puddles on a low pocket wash the spores off what grows there.
            if wash and n.pocket and n.pocket.low then t.reserve = max(0, t.reserve - wash * dt) end
            local cap = self:reserveMax(t)
            if cap > 0 and n.conn and self.nutrients > 0 then
                local take = min(cap - t.reserve, n.cap * dt, self.nutrients)
                if take > 0 then
                    t.reserve = t.reserve + take
                    self.nutrients = self.nutrients - take
                end
            end
            t.reach = Q[self:quality(n)].power
            t.power = t.reach * (n.ringed and self:ringDamage() or 1) * (t.amp or 1)
            if self:sunlit(n) then t.power = t.power * self.seed.sun.damage end
            if t.boost then
                t.boost = t.boost - dt
                if t.boost <= 0 then t.boost = nil end
            end
            t.glow = 0 -- a lamp lights itself in `lamp`, if it is fed and free to
            self:fire(n, t, D.TOWER[t.kind], dt)
        end
    end
end

-- What a tower is short of: nil (fine), "starved" (slow) or "dormant" (silent).
function Game:hunger(t)
    local d = D.TOWER[t.kind]
    if not d.reserve then return t.node.conn and nil or "dormant" end
    local need = d.shot or d.drain * 0.5
    if t.reserve < need then return "dormant" end
    if not t.node.conn or t.reserve < self:reserveMax(t) * 0.3 then return "starved" end
end

-- How dangerous a tower looks to a hunting spider.
function Game:threat(t)
    local dmg, every = self:stat(t, "damage"), self:stat(t, "every")
    if dmg and every then return dmg / every * (t.power or 1) end
    return 0.5
end

-- The enemies a tower could shoot, nearest the Heart first.
function Game:targets(n, range, air, minRange)
    local list = {}
    local r2, m2 = range * range, (minRange or 0) ^ 2
    for _, e in ipairs(self.enemies) do
        if not e.dead and not e.under and not e.hidden and not (e.infected and e.infected > 0)
            and (air or not D.ENEMIES[e.kind].fly) then
            local d2 = (e.x - n.x) ^ 2 + (e.z - n.z) ^ 2
            if d2 <= r2 and d2 >= m2 then list[#list + 1] = e end
        end
    end
    table.sort(list, function(a, b) return (a.togo or 0) < (b.togo or 0) end)
    return list
end

-- The towers that work all round them rather than fire: a Game method of
-- the kind's name, taking (n, t, S, power, boost, dt).
local AURAS = { mane = true, inky = true, stink = true, lamp = true }

-- The ones that fire, the Game method that fires each: what it looks and
-- sounds like leaving, and what it sends. Each takes (n, t, d, S, power,
-- range, list), the list its targets, nearest first.
local SHOOTS = { puffer = "puff", needle = "skewer", mortar = "lob", giant = "quake", cordyceps = "spit" }

function Game:fire(n, t, d, dt)
    local hunger = self:hunger(t)
    t.hunger = hunger
    if t.kind == "relay" then return end
    if hunger == "dormant" then return end
    if t.webbed > 0 or t.stun > 0 then return end
    local S = function(k) return self:stat(t, k) end
    local power = t.power or 1
    local boost = t.boost and self:pulseRate() or 1
    if t.boost then power = power * self:pulseDamage() end
    boost = boost * self:pace()
    if AURAS[t.kind] then return self[t.kind](self, n, t, S, power, boost, dt) end
    if t.kind == "giant" and t.grown < 1 then return end

    local rate = (hunger == "starved" and 0.5 or 1) * boost
    -- The mortar drinks three times what anything else does: on a thin link it
    -- cannot be fed fast enough and fires at half pace.
    if d.thirst and n.cap < d.thirst then rate = rate * 0.5; t.thirsty = true else t.thirsty = false end
    t.cool = t.cool - dt * rate
    if t.cool > 0 then return end
    local range = self:towerRange(t)
    local list
    if d.infect then
        -- A host: the biggest it can take, not the nearest.
        local e = self:infectable(n.x, n.z, range, S("maxHp"))
        list = { e }
    else
        list = self:targets(n, range, d.air, not (n.pocket and n.pocket.high) and d.minRange or nil)
    end
    if not list[1] then return end
    t.cool = S("every")
    t.reserve = t.reserve - d.shot
    t.squash = 1
    t.fired = 0
    local e = list[1]
    t.aim = atan2(e.z - n.z, e.x - n.x)
    self[SHOOTS[t.kind]](self, n, t, d, S, power, range, list)
end

-- A puffer: a spore lobbed for every link it has (up to four), splashing.
function Game:puff(n, t, d, S, power, range, list)
    self:motes(n.x, n.y + 8, n.z, 4, { "w", "t" }, 3, 8, 0.4)
    self:cue("puff", n.x, n.z)
    local puffs = max(1, min(4, self:degree(n))) + (S("extraPuff") or 0)
    for k = 1, puffs do
        local o = list[(k - 1) % #list + 1]
        self.shots[#self.shots + 1] = { kind = "spore", x0 = n.x, y0 = n.y + 9, z0 = n.z,
            tx = o.x, tz = o.z, t = 0, flight = 0.45 + 0.05 * k, damage = S("damage") * power, splash = S("splash"),
            linger = S("linger"), toxin = (S("toxin") or 0) * power }
    end
end

-- A needle: a line of light straight through what it aims at, harder from
-- a dead end, and on through more behind it once upgraded.
function Game:skewer(n, t, d, S, power, range, list)
    local e = list[1]
    local big = self:degree(n) == 1 or (self:stat(t, "pierce") or 1) > 1
    self.fx[#self.fx + 1] = { star = true, x = n.x, y = n.y + 12, z = n.z, k = big and "l" or "w", life = 0.08, max = 0.08 }
    self:cue(big and "lance" or "zip", n.x, n.z)
    local deadEnd = self:degree(n) == 1
    local dmg = S("damage") * power * (deadEnd and S("deadEnd") or 1)
    -- Down the line through its target, as far as its reach, for a skewer.
    local hits = { e }
    local pierce = S("pierce") or 1
    if pierce > 1 then
        local dx, dz = e.x - n.x, e.z - n.z
        local l = max(1, sqrt(dx * dx + dz * dz))
        local fx, fz = n.x + dx / l * range, n.z + dz / l * range
        local line = {}
        for _, o in ipairs(list) do
            if o ~= e and segDist(o.x, o.z, n.x, n.z, fx, fz) < 6 then line[#line + 1] = o end
        end
        table.sort(line, function(a, b) return dist(a, n) < dist(b, n) end)
        for k = 1, pierce - 1 do hits[#hits + 1] = line[k] end
    end
    local far = hits[#hits]
    for _, o in ipairs(hits) do
        local mark = S("mark")
        if mark then
            o.mark, o.markMul = S("markFor"), mark
            local ms = S("markSplash")
            if ms then
                for _, p in ipairs(self.enemies) do
                    if not p.dead and dist(p, o) <= ms then p.mark, p.markMul = S("markFor"), mark end
                end
            end
        end
        self:hurt(o, dmg, true)
    end
    self.shots[#self.shots + 1] = { kind = "needle", x0 = n.x, y0 = n.y + 12, z0 = n.z,
        x1 = far.x, y1 = far.y + 3, z1 = far.z, t = 0, flight = 0.12, big = deadEnd, mark = S("mark") }
end

-- A mortar: a shell high over everything, bursting where it lands.
function Game:lob(n, t, d, S, power, range, list)
    local e = list[1]
    self:motes(n.x, n.y + 9, n.z, 7, { "s", "k", "t" }, 4, 12, 0.7)
    self:cue("thump", n.x, n.z)
    self.shots[#self.shots + 1] = { kind = "shell", x0 = n.x, y0 = n.y + 10, z0 = n.z, tx = e.x, tz = e.z,
        t = 0, flight = 1.1, damage = S("damage") * power, splash = S("splash"),
        cluster = S("cluster"), clusterDamage = (S("clusterDamage") or 0) * power, smoke = S("smoke") }
end

-- A cordyceps: a spore spat into a host, which turns on its own.
function Game:spit(n, t, d, S, power, range, list)
    local e = list[1]
    self:motes(n.x, n.y + 9, n.z, 3, { "t", "r" }, 2, 8, 0.4)
    self:cue("spit", n.x, n.z)
    local dur = S("infect") * self:deepHold(t) * (t.boost and 1.5 or 1)
    self.shots[#self.shots + 1] = { kind = "cordy", x0 = n.x, y0 = n.y + 10, z0 = n.z, target = e,
        tx = e.x, tz = e.z, t = 0, flight = 0.6, infect = dur, spread = S("spread") or 0, bite = S("bite") * power,
        maxHp = S("maxHp") }
end

-- A cordyceps holds its host longer the further out along the network it
-- grows: one hop from the Heart is the plain hold.
function Game:deepHold(t)
    local d = D.TOWER.cordyceps
    return 1 + d.perHop * min(d.maxHops, self:depth(t.node) - 1)
end

-- Lion's Mane: heal what is chewed and regrow what is cut on the branch below
-- it (every link with an end in its care, the one that feeds it included); on
-- the purge branch, clear webs and heal the fruiting bodies there too. It only
-- drinks while it has something to do.
function Game:mane(n, t, S, power, boost, dt)
    local busy = false
    local care = t.care or { [n] = true }
    for _, l in ipairs(self.links) do
        local full = self:linkFull(l)
        if care[l.a] or care[l.b] then
            if l.state == "alive" and l.hp < full then
                l.hp = min(full, l.hp + S("heal") * power * boost * dt)
                busy = true
                if fr() < dt * 3 then
                    local f = fr()
                    self:motes(l.a.x + (l.b.x - l.a.x) * f, 1, l.a.z + (l.b.z - l.a.z) * f, 1, { "l", "w" }, 1, 10, 0.5)
                end
            elseif l.state == "cut" and not l.salted then
                l.regrow = l.regrow + S("regrow") * power * boost * dt
                busy = true
            end
        end
    end
    if S("purge") then
        for o in pairs(care) do
            local ot = o.tower
            if ot then
                if ot.webbed > 0 or ot.stun > 0 then ot.webbed, ot.stun, busy = 0, 0, true end
                if ot.hp < self:maxHp(ot) then
                    ot.hp = min(self:maxHp(ot), ot.hp + S("towerHeal") * power * boost * dt)
                    busy = true
                end
            end
        end
    end
    t.busy = busy
    if busy then t.reserve = max(0, t.reserve - D.TOWER.mane.drain * dt) end
end

-- Inky Cap: bodies in its reach are drunk (see updateCorpses); now and then it
-- drips a pool of ink under whatever is walking past.
function Game:inky(n, t, S, power, boost, dt)
    if self.phase ~= "wave" then return end
    t.ink = t.ink - dt * boost
    if t.ink > 0 then return end
    local list = self:targets(n, self:towerRange(t), false)
    local e = list[1]
    if not e then return end
    t.ink = S("inkEvery")
    t.reserve = t.reserve - D.TOWER.inky.shot
    t.squash = 1
    t.fired = 0
    local r = S("inkR") * power
    self.inks[#self.inks + 1] = { x = e.x, z = e.z, r = r, life = S("inkLife"), max = S("inkLife"), slow = S("inkSlow") }
    self.shots[#self.shots + 1] = { kind = "ink", x0 = n.x, y0 = n.y + 12, z0 = n.z, tx = e.x, tz = e.z, t = 0, flight = 0.35 }
    self:cue("ink", n.x, n.z)
end

-- How far a tower reaches: its stat, the pocket's power, the night's glow. The
-- Humongous Fungus spreads with the network; a Ghost Lamp's reach is its pull.
function Game:towerRange(t)
    local r = self:stat(t, "range")
    if not r then return end
    if t.kind == "lamp" then return self:lure(t) end
    if t.kind == "giant" then
        r = min(self:stat(t, "maxRange"), r + self:stat(t, "rangePerNode") * (self:rooted(t)))
    end
    local n = t.node
    if t.kind == "mortar" and n and n.pocket and n.pocket.high then r = r * D.TOWER.mortar.highRange end
    return r * (t.reach or 1) * (self:sky().range or 1)
end

-- A Ghost Lamp's pull: brighter the further out from the Heart it grows,
-- brighter still at night. Out of reserve it is dark.
function Game:lure(t)
    local n = t.node
    if not n or t.hunger == "dormant" then return 0 end
    local d = D.TOWER.lamp
    local out = min(d.maxHops, self:depth(n) - 1)
    return (self:stat(t, "range") + d.perHop * out) * (t.reach or 1) * (self:sky().lamp or 1)
end

-- Can a lamp pull this one off its way? Not a boss, not salt, not a mite
-- set on its thread, not a host, not a centipede's train, and only once.
function Game:lurable(e)
    local d = D.ENEMIES[e.kind]
    return not e.dead and not d.boss and not e.lured and e.kind ~= "brine" and e.kind ~= "mite" and not e.train
        and not (e.infected and e.infected > 0) and not e.rolling and not e.under and not e.hidden
        and (e.state == "walk" or e.state == "chew")
end

-- Stinkhorn: everything in its stench wades through it and now and then
-- trips; on the panic branch they turn and flee. It only drinks while it has
-- someone to stink at. (Flies are drawn to it: see `fly`.)
function Game:stink(n, t, S, power, boost, dt)
    if self.phase ~= "wave" then return end
    local range = self:towerRange(t)
    local r2 = range * range
    t.panicT = (t.panicT or 0) - dt * boost
    local panic = S("panic") and t.panicT <= 0
    local busy, fled = false, false
    -- The stench runs down its own living links: a lane along each.
    local lanes, lane = {}, S("lane")
    for _, l in ipairs(n.links) do if alive(l) then lanes[#lanes + 1] = l end end
    local function reeks(e)
        if (e.x - n.x) ^ 2 + (e.z - n.z) ^ 2 <= r2 then return true end
        for _, l in ipairs(lanes) do
            if segDist(e.x, e.z, l.a.x, l.a.z, l.b.x, l.b.z) <= lane then return true end
        end
    end
    for _, e in ipairs(self.enemies) do
        local d = D.ENEMIES[e.kind]
        if not e.dead and not d.fly and not e.under and not e.hidden and reeks(e) then
            busy = true
            e.reek = (e.reekT or 0) > 0 and min(e.reek, S("reek")) or S("reek")
            e.reekT = 0.25
            if not d.boss and not e.slide and not e.hopT then -- a springtail in the air does not trip
                if self.dice:random() < S("stumble") * boost * dt then
                    e.stun = max(e.stun, S("trip"))
                    self:burst(e.x, 3, e.z, 2, { "m", "d" }, 8)
                    self:cue("trip", e.x, e.z)
                end
                if panic and not e.train then e.panic, fled = S("panic"), true end
            end
            local rot = S("rot")
            if rot then self:hurt(e, rot * power * dt, true, true) end
        end
    end
    if fled then
        t.panicT, t.squash, t.fired = S("panicEvery"), 1, 0
        self:burst(n.x, n.y + 10, n.z, 10, { "m", "d", "r" }, 20)
        self:shock(n.x, n.z, 20, 0.5, "m", "d")
        self:cue("panic", n.x, n.z)
    end
    t.busy = busy
    if busy then
        t.reserve = max(0, t.reserve - D.TOWER.stink.drain * dt)
        if self.dice:random() < dt * (5 + 3 * #lanes) then
            local a, u = self.dice:random() * 2 * math.pi, self.dice:random() * range * 0.8
            local x, z = n.x + cos(a) * u, n.z + sin(a) * u
            if lanes[1] and self.dice:random() < 0.6 then
                local l, f = lanes[self.dice:random(#lanes)], self.dice:random()
                u = self.dice:random() * lane * 0.8
                x, z = l.a.x + (l.b.x - l.a.x) * f + cos(a) * u, l.a.z + (l.b.z - l.a.z) * f + sin(a) * u
            end
            self.fx[#self.fx + 1] = { x = x, y = 2, z = z, vx = 0, vy = 14, vz = 0,
                life = 0.5, k = self.dice:random() < 0.5 and "m" or "d", rise = true }
        end
    end
end

-- Ghost Lamp: whatever walks or flies into its glow comes for it first, and
-- chews at it until it gives up (`hold`) or the lamp goes out.
function Game:lamp(n, t, S, _, _, dt)
    local regen = S("regen")
    if regen then t.hp = min(self:maxHp(t), t.hp + regen * dt) end
    t.glow = self:lure(t)
    if self.phase ~= "wave" or t.glow <= 0 then return end
    local busy = false
    local r2 = t.glow * t.glow
    for _, e in ipairs(self.enemies) do
        if e.lamp == n and e.state == "lured" then
            busy = true
        elseif self:lurable(e) and (e.x - n.x) ^ 2 + (e.z - n.z) ^ 2 <= r2 then
            e.state, e.lamp, e.lureT, e.lured, e.chewing = "lured", n, S("hold"), true, nil
            busy = true
        end
    end
    t.busy = busy
    if busy then t.reserve = max(0, t.reserve - D.TOWER.lamp.drain * dt) end
end

-- A lamp chewed out. On the flare branch it bursts as it goes.
function Game:snuff(n)
    local t = n.tower
    local blast = self:stat(t, "blast")
    if blast then
        local r = self:stat(t, "blastR")
        local stun = self:stat(t, "blastStun")
        for _, e in ipairs(self.enemies) do
            if not e.dead and (e.x - n.x) ^ 2 + (e.z - n.z) ^ 2 <= r * r then
                self:hurt(e, blast * (t.power or 1))
                if stun then e.stun = max(e.stun, stun) end
            end
        end
        self.fx[#self.fx + 1] = { cloud = true, x = n.x, y = self.world:groundAt(n.x, n.z), z = n.z, r = r, life = 0.6, max = 0.6, glowing = true }
        self:burst(n.x, n.y + 6, n.z, 24, { "l", "w", "c" }, 36)
        self:shock(n.x, n.z, r, 0.5, "w", "l")
        self.events.boom = true
        self:cue("flare", n.x, n.z)
    else
        self:motes(n.x, n.y + 6, n.z, 8, { "l", "c" }, 3, 10, 0.8)
        self:cue("snuff", n.x, n.z)
    end
    self:destroyTower(n, blast and "FLARED" or "SNUFFED")
end

-- The Humongous Fungus: the ground round it heaves, everything on it is hit
-- for more the bigger the network is, and on the honey branch it sticks and
-- the links in reach are mended.
-- The Humongous Fungus counts the fed nodes round it: those within `hops`
-- links, and every node of a Fairy Ring it stands in.
function Game:rooted(t)
    local n = t.node
    if not n then return 0, {} end
    local seen, count, set = { [n] = true }, 0, {}
    local frontier = { n }
    for _ = 1, self:stat(t, "hops") do
        local nxt = {}
        for _, f in ipairs(frontier) do
            for _, o in ipairs(self:neighbours(f)) do
                if not seen[o] then
                    seen[o] = true
                    nxt[#nxt + 1] = o
                    if o.conn and not o.heart then count, set[o] = count + 1, true end
                end
            end
        end
        frontier = nxt
    end
    for _, r in ipairs(self.rings) do
        if r.set[n] then
            for m in pairs(r.set) do
                if not seen[m] and m.conn and not m.heart then seen[m], set[m], count = true, true, count + 1 end
            end
        end
    end
    return count, set
end

-- The nodes a tower's network rule works on, for showing them: a mane's
-- branch, what a relay pumps into or an inky feeds, what a giant counts.
function Game:touches(t)
    local n = t.node
    if t.kind == "mane" then return t.care end
    if t.kind == "giant" then return select(2, self:rooted(t)) end
    if t.kind == "relay" or t.kind == "inky" then
        local set = {}
        for _, o in ipairs(self:neighbours(n)) do set[o] = true end
        return set
    end
end

-- The Humongous Fungus: the ground heaves all round it, harder for every
-- fed node rooted near it.
function Game:quake(n, t, d, S, power, range, list)
    self:motes(n.x, n.y + 2, n.z, 10, { "n", "t" }, 14, 10, 0.6)
    self:cue("quake", n.x, n.z)
    local dmg = (S("damage") + S("perNode") * (self:rooted(t))) * power
    local stick, quake = S("stick"), S("quake")
    for _, e in ipairs(list) do
        self:hurt(e, dmg)
        if stick and not D.ENEMIES[e.kind].noSlow then e.stick, e.stickT = stick, S("stickFor") end
        if quake then e.stun = max(e.stun, quake) end
    end
    local mend = S("mend")
    if mend then
        for _, l in ipairs(self:linksNear(n.x, n.z, range)) do l.hp = min(self:linkFull(l), l.hp + mend) end
    end
    self.fx[#self.fx + 1] = { wave = true, x = n.x, z = n.z, r = range, life = 0.7, max = 0.7, honey = stick ~= nil }
    self.events.shake = max(self.events.shake or 0, 0.12)
end

function Game:inkAt(x, z)
    local best
    for _, p in ipairs(self.inks) do
        if (p.x - x) ^ 2 + (p.z - z) ^ 2 <= p.r * p.r and (not best or p.slow < best.slow) then best = p end
    end
    return best
end

function Game:updateMats(dt)
    for k = #self.mats, 1, -1 do
        local m = self.mats[k]
        m.grown = min(1, m.grown + dt * 1.6)
        if m.kind == "mat" then
            -- Every link draped over a mat feeds it: one keeps it from
            -- withering, and each (up to `maxDrape`) makes it stickier.
            m.draped = 0
            for _, l in ipairs(self.links) do
                if alive(l) and segDist(m.x, m.z, l.a.x, l.a.z, l.b.x, l.b.z) <= D.TOWER.mat.feed then m.draped = m.draped + 1 end
            end
            m.draped = min(m.draped, D.TOWER.mat.maxDrape)
            m.fed = m.draped > 0
            if not m.fed then m.life = m.life - dt * (self:sky().wither or 1) end
            if m.life <= 0 then table.remove(self.mats, k) end
        else
            local regen = self:stat(m, "regen")
            if regen and not m.chewed then m.hp = min(self:maxHp(m), m.hp + regen * dt) end
            m.chewed = false
            if m.hp <= 0 then self:breakMat(m) end
        end
    end
end

-- How slow a mat holds what is on it, and how fast it dissolves it: both
-- grow with the links draped over it.
function Game:matSlow(m)
    return self:stat(m, "slow") * D.TOWER.mat.drape ^ (m.draped or 0)
end

function Game:matDigest(m)
    local dg = self:stat(m, "digest")
    return dg and dg * (1 + D.TOWER.mat.drapeDigest * (m.draped or 0))
end

-- The mat under an enemy, if any.
function Game:onMat(e)
    for _, m in ipairs(self.mats) do
        if m.kind == "mat" and abs(e.x - m.x) < 9 and abs(e.z - m.z) < 9 then return m end
    end
end

-- A shelf across the tile an enemy is walking into.
function Game:blocker(e)
    for _, m in ipairs(self.mats) do
        if m.kind == "shelf" and e.tc == m.c and e.tr == m.r and (e.x - m.x) ^ 2 + (e.z - m.z) ^ 2 < 121 then return m end
    end
end

function Game:updateShots(dt)
    for k = #self.shots, 1, -1 do
        local s = self.shots[k]
        s.t = s.t + dt
        if s.target and not s.target.dead then s.tx, s.tz = s.target.x, s.target.z end
        if s.t >= s.flight then
            if s.kind == "spore" then
                for _, e in ipairs(self.enemies) do
                    if not e.dead and (e.x - s.tx) ^ 2 + (e.z - s.tz) ^ 2 <= s.splash ^ 2 then self:hurt(e, s.damage) end
                end
                self.fx[#self.fx + 1] = { cloud = true, x = s.tx, y = self.world:groundAt(s.tx, s.tz), z = s.tz, r = s.splash, life = 0.4, max = 0.4 }
                self:cue("pop", s.tx, s.tz)
                if s.linger then
                    self.clouds[#self.clouds + 1] = { x = s.tx, z = s.tz, r = s.splash, life = s.linger, max = s.linger, dps = s.toxin }
                end
            elseif s.kind == "shell" or s.kind == "bomblet" then
                for _, e in ipairs(self.enemies) do
                    if not e.dead and not D.ENEMIES[e.kind].fly and (e.x - s.tx) ^ 2 + (e.z - s.tz) ^ 2 <= s.splash ^ 2 then
                        self:hurt(e, s.damage)
                        if s.smoke then
                            e.stun = max(e.stun, s.smoke)
                            if e.carry then e.carry.carried, e.carry = nil, nil end
                        end
                    end
                end
                local big = s.kind == "shell"
                self.fx[#self.fx + 1] = { cloud = true, x = s.tx, y = self.world:groundAt(s.tx, s.tz), z = s.tz, r = s.splash, life = big and 0.6 or 0.35,
                    max = big and 0.6 or 0.35, smoke = s.smoke }
                if big then
                    self:burst(s.tx, 3, s.tz, 10, { "t", "n", "w" }, 30)
                    self:shock(s.tx, s.tz, s.splash * 1.2, 0.4, "w", "t")
                    self:splat(s.tx, s.tz, s.splash * 0.6, "u", 3)
                    self.events.boom = true
                    self:cue("boom", s.tx, s.tz)
                else
                    self:shock(s.tx, s.tz, s.splash, 0.25, "t", "n")
                    self:cue("bomblet", s.tx, s.tz)
                end
                if s.cluster then
                    for c = 1, s.cluster do
                        local a, r = c / s.cluster * 2 * math.pi + self.dice:random(), s.splash * (0.8 + self.dice:random() * 0.6)
                        self.shots[#self.shots + 1] = { kind = "bomblet", x0 = s.tx, y0 = 2, z0 = s.tz,
                            tx = s.tx + cos(a) * r, tz = s.tz + sin(a) * r, t = 0, flight = 0.35 + self.dice:random() * 0.15,
                            damage = s.clusterDamage, splash = 9 }
                    end
                end
            elseif s.kind == "ink" then
                self:splat(s.tx, s.tz, 2, "o", 0.6)
            elseif s.kind == "cordy" then
                local e = s.target
                if e and not e.dead and not (e.infected and e.infected > 0) then self:infect(e, s) end
            end
            table.remove(self.shots, k)
        end
    end
end

function Game:updateClouds(dt)
    local wash = self:sky().clouds or 1
    for k = #self.clouds, 1, -1 do
        local c = self.clouds[k]
        c.life = c.life - dt * wash
        for _, e in ipairs(self.enemies) do
            if not e.dead and (e.x - c.x) ^ 2 + (e.z - c.z) ^ 2 <= c.r * c.r then self:hurt(e, c.dps * dt, true, true) end
        end
        if c.life <= 0 then table.remove(self.clouds, k) end
    end
    for k = #self.inks, 1, -1 do
        local p = self.inks[k]
        p.life = p.life - dt * wash
        if p.life <= 0 then table.remove(self.inks, k) end
    end
end

-- The best an Inky Cap does for a body at (x, z): how many times its worth.
function Game:feast(x, z)
    local best
    for _, n in ipairs(self.nodes) do
        local t = n.tower
        if t and t.kind == "inky" and t.hunger ~= "dormant" then
            local r = self:stat(t, "range") * (t.reach or 1)
            if (n.x - x) ^ 2 + (n.z - z) ^ 2 <= r * r then
                local f = self:stat(t, "feast")
                if not best or f > best.f then best = { f = f, n = n } end
            end
        end
    end
    return best
end

-- What an Inky Cap drinks goes first to itself and the fruiting bodies it is
-- linked to, topping up their reserves (cut off or not); the rest to the bank.
function Game:feedFrom(n, amount)
    local list = self:neighbours(n)
    list[#list + 1] = n
    for _, o in ipairs(list) do
        local t = o.tower
        if t and amount > 0 then
            local give = min(amount, self:reserveMax(t) - t.reserve)
            if give > 0 then t.reserve, amount = t.reserve + give, amount - give end
        end
    end
    return amount
end

function Game:updateCorpses(dt)
    for k = #self.corpses, 1, -1 do
        local c = self.corpses[k]
        if c.carried then
            local a = c.carried
            if a.dead then
                c.carried = nil
            else
                c.x, c.z, c.h = a.x - cos(a.h) * 6, a.z - sin(a.h) * 6, a.h
            end
        elseif c.absorb then
            -- Being drunk: the value goes over a second and a half, and you see it go.
            local take = min(c.value, c.full * dt / 1.5)
            c.value = c.value - take
            self.stats.drunk = self.stats.drunk + take
            if c.inky then take = self:feedFrom(c.inky, take) end
            self.nutrients = self.nutrients + take
            if self.dice:random() < dt * 20 then
                self.fx[#self.fx + 1] = { glow = true, x = c.x, y = 2, z = c.z, tx = c.ax, tz = c.az, t = 0, life = 0.5, max = 0.5 }
            end
            if c.value <= 0.01 then table.remove(self.corpses, k) end
        else
            c.life = c.life - dt
            -- Anything within reach of a fed link, or of a fed Inky Cap, is drunk.
            local mult = self.mods.feast and 1.5 or 1
            local inky = self:feast(c.x, c.z)
            if inky then
                c.absorb, c.ax, c.az, c.inky = true, inky.n.x, inky.n.z, inky.n
                mult = mult * inky.f
            else
                for _, l in ipairs(self.links) do
                    if alive(l) and l.a.conn then
                        local dd, _, qx, qz = segDist(c.x, c.z, l.a.x, l.a.z, l.b.x, l.b.z)
                        if dd <= D.LINK.absorb then
                            c.absorb, c.ax, c.az = true, qx, qz
                            break
                        end
                    end
                end
            end
            if c.absorb then
                c.value = c.value * mult
                c.full = c.value
                self:cue("drink", c.x, c.z)
                self:say("+" .. floor(c.value + 0.5), c.x, 8, c.z, inky and "w" or "l")
            elseif c.life <= 0 then
                table.remove(self.corpses, k)
            end
        end
    end
end

function Game:updateFx(dt)
    for k = #self.fx, 1, -1 do
        local p = self.fx[k]
        p.life = p.life - dt
        if p.glow or p.streak then
            p.t = p.t + dt
        elseif p.rise then
            p.y = p.y + p.vy * dt
        elseif p.vx then
            p.vy = p.vy - 200 * dt
            p.x, p.y, p.z = p.x + p.vx * dt, p.y + p.vy * dt, p.z + p.vz * dt
            if p.y < 0 then p.y, p.vy, p.vx, p.vz = 0, 0, p.vx * 0.5, p.vz * 0.5 end
        end
        if p.life <= 0 then table.remove(self.fx, k) end
    end
    for k = #self.texts, 1, -1 do
        local t = self.texts[k]
        t.life = t.life - dt
        t.y = t.y + dt * 10
        if t.life <= 0 then table.remove(self.texts, k) end
    end
end

--- how enemies move ----------------------------------------------------------------------

-- The living link nearest an enemy within `r`.
function Game:linkNear(e, r)
    local best, bd
    for _, l in ipairs(self.links) do
        if alive(l) then
            local d = segDist(e.x, e.z, l.a.x, l.a.z, l.b.x, l.b.z)
            if d <= r and (not bd or d < bd) then best, bd = l, d end
        end
    end
    return best, bd
end

-- Every living link within `r` of (x, z).
function Game:linksNear(x, z, r)
    local out = {}
    for _, l in ipairs(self.links) do
        if alive(l) and segDist(x, z, l.a.x, l.a.z, l.b.x, l.b.z) <= r then out[#out + 1] = l end
    end
    return out
end

local function toward(e, tx, tz, speed, dt)
    local dx, dz = tx - e.x, tz - e.z
    local d = sqrt(dx * dx + dz * dz)
    if d < 0.001 then return true, 0 end
    e.h = atan2(dz, dx)
    local s = min(d, speed * dt)
    e.x, e.z = e.x + dx / d * s, e.z + dz / d * s
    return d <= speed * dt + 0.01, d
end

-- One step along the trail. Answers true when it has reached the Heart.
function Game:walk(e, speed, dt)
    local w = self.world
    local tx, tz = e.tc * TILE + TILE / 2, e.tr * TILE + TILE / 2
    -- Walk a little to one side of the trail's middle, each its own way.
    local nc, nr = w:nextTile(e.tc, e.tr)
    if nc then
        local dx, dz = nc - e.tc, nr - e.tr
        tx, tz = tx - dz * e.off, tz + dx * e.off
    end
    local arrived, d = toward(e, tx, tz, speed, dt)
    local left = w:distAt(e.tc, e.tr) or 0
    e.togo = left * TILE + d
    if arrived then
        if left == 0 then return true end
        if self.tunnels[1] and self:burrow(e) then return end
        if nc then e.tc, e.tr = nc, nr end
    end
end

-- One step back along the trail, away from the Heart: a cordyceps host.
function Game:walkBack(e, speed, dt)
    local w = self.world
    local arrived = toward(e, e.tc * TILE + TILE / 2, e.tr * TILE + TILE / 2, speed, dt)
    if arrived then
        local d = w:distAt(e.tc, e.tr) or 0
        for _, o in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            if w:distAt(e.tc + o[1], e.tr + o[2]) == d + 1 then
                e.tc, e.tr = e.tc + o[1], e.tr + o[2]
                break
            end
        end
    end
    e.togo = 1e6
end

function Game:reachHeart(e)
    local d = D.ENEMIES[e.kind]
    local hit = d.heart
    if e.ballHp and e.ballHp > 0 then hit = hit + d.ballHeart end
    if self.mods.heartwood then hit = hit * 0.7 end
    self.heartHp = self.heartHp - hit
    self.stats.leaked[e.kind] = (self.stats.leaked[e.kind] or 0) + hit
    self.events.heart = true
    e.dead = true
    if e.carry then
        -- Carried off underground: those nutrients are gone.
        unlist(self.corpses, e.carry)
        self.stats.stolen = self.stats.stolen + 1
    end
    if e.train then e.train.n = e.train.n - 1 end
    if d.boss and not d.segment then
        self.events.shake = 0.6
        self.stats.bossLeft = (self.stats.bossLeft or "") .. (" %s %d%%"):format(e.kind, e.hp / e.maxHp * 100)
    end
    self:burst(self.heart.x, 10, self.heart.z, d.boss and 20 or 6, { "g", "m" }, 20)
    self:shock(self.heart.x, self.heart.z, d.boss and 28 or 14, 0.4, "r", "g")
    self:cue("heart", self.heart.x, self.heart.z)
    if self.mods.splat then self:splatFruit() end
end

-- Jaws at a thread: chips of it fly, and it can be heard.
function Game:chewing(e)
    if fr() < 0.06 then
        self:sparks(e.x, e.y + 2, e.z, 1, { "c", "d" }, 10)
        self:cue("chew", e.x, e.z)
    end
end

-- Each kind's own part of its move, by when in the move it comes: a Game
-- method of the kind's name taking (e, d, slow, dt), true when it took the
-- whole frame.
--   burrowed  under the ground, instead of everything else
--   first     before chewing and shelves (it digs, leaps, hops or swims past both)
--   own       after them, before it tramples, bites into a link or walks on
local MOVES = {
    burrowed = { mole = true, cricket = true },
    first = { springtail = true, cricket = true, click = true, waterbug = true, bombardier = true, mole = true },
    own = { mite = true, slug = true, spider = true, queen = true, stag = true, dung = true, pillbug = true, brine = true },
}

function Game:move(e, dt)
    local d = D.ENEMIES[e.kind]
    e.flash = max(0, e.flash - dt)
    e.ballFlash = max(0, (e.ballFlash or 0) - dt)
    e.anim = e.anim + dt
    e.mark = max(0, e.mark - dt)
    -- A centipede segment waiting its turn at the gate, or one down a tunnel.
    if e.hidden then
        e.hidden = e.hidden - dt
        if e.hidden <= 0 then
            e.hidden = nil
            if e.tunnel then self:emerge(e) end
        end
        return
    end
    -- Burrowing: nothing on the surface touches it.
    if e.under and MOVES.burrowed[e.kind] then
        self[e.kind](self, e, d, 1, dt)
        return
    end

    if e.infected and e.infected > 0 then return self:host(e, d, dt) end

    -- Stunned in mortar smoke, or tripped in a stinkhorn's stench.
    if e.stun > 0 then
        e.stun = e.stun - dt
        return
    end

    local pace = self:pace()
    if (e.reekT or 0) > 0 then e.reekT = e.reekT - dt end
    if (e.stickT or 0) > 0 then e.stickT = e.stickT - dt end
    if d.fly then return self:fly(e, d, pace, dt) end

    local mat = self:onMat(e)
    local ink = self:inkAt(e.x, e.z)
    e.blind = ink ~= nil
    local slow = 1
    if not d.noSlow then
        if mat then slow = slow * self:matSlow(mat) end
        if ink then slow = slow * ink.slow end
        if self.rings[1] and self:ringed(e.x, e.z) then slow = slow * self:ringSlow() end
        if (e.reekT or 0) > 0 then slow = slow * e.reek end
        if (e.stickT or 0) > 0 then slow = slow * e.stick end
    end
    -- Frost slows everything, the unslowable included.
    slow = slow * pace
    -- A stomach mat dissolves what stands on it.
    if mat then
        local dg = self:matDigest(mat)
        if dg then self:hurt(e, dg * dt, true, true) end
        if e.dead then return end
    end

    if e.slide then return self:slide(e, d, dt) end

    -- Panicked by a stinkhorn: back the way it came for a moment.
    if (e.panic or 0) > 0 then
        e.panic = e.panic - dt
        e.state, e.chewing, e.gnaw = "walk", nil, nil
        return self:walkBack(e, d.speed * slow, dt)
    end
    -- Pulled off its way by a Ghost Lamp, and back to it after.
    if e.state == "lured" then return self:lured(e, d, slow, dt) end
    if e.state == "back" then
        local arrived = toward(e, e.tc * TILE + TILE / 2, e.tr * TILE + TILE / 2, d.speed * slow, dt)
        e.y = self.world:groundAt(e.x, e.z)
        if arrived then e.state, e.y = "walk", self.world:groundAt(e.x, e.z) end
        return
    end
    if e.leader then return self:follow(e, d, slow, dt) end
    if MOVES.first[e.kind] and self[e.kind](self, e, d, slow, dt) then return end

    -- Stopped to chew a link it walked into.
    if e.state == "chew" then
        local l = e.chewing
        if l.state ~= "alive" or e.blind then
            e.state = "walk"
        else
            self:biteLink(l, d.chew * dt)
            self:chewing(e)
            e.chewT = e.chewT - dt
            if e.chewT <= 0 then e.state = "walk" end
            return
        end
    end

    -- A shelf across the trail: chew through it, and be bitten back.
    local shelf = self:blocker(e)
    if shelf then
        if e.rolling then
            e.rolling, e.walked, e.stuck = false, 0, 0.6
            shelf.hp = shelf.hp - 30
            self:burst(e.x, 3, e.z, 6, { "t", "n" }, 14)
        end
        e.state = "gnawShelf"
        shelf.hp = shelf.hp - (d.bite or 5) * dt
        shelf.chewed = true
        if fr() < 0.05 then
            self:sparks(e.x, e.y + 2, e.z, 1, { "t", "n" }, 10)
            self:cue("chew", e.x, e.z)
        end
        local th = self:stat(shelf, "thorns")
        if th then self:hurt(e, th * dt, true, true) end
        e.anim = e.anim + dt
        return
    elseif e.state == "gnawShelf" then
        e.state = "walk"
    end

    if MOVES.own[e.kind] and self[e.kind](self, e, d, slow, dt) then return end
    self:trample(e, d, dt)

    -- Into a link in its way: it stops to chew it, once a link.
    if d.chew and d.chewFor and not e.blind then
        local l = self:linkNear(e, 3.5)
        if l and not l.bitten[e] then
            l.bitten[e] = true
            e.state, e.chewing, e.chewT = "chew", l, d.chewFor
            return
        end
    end

    -- Ants pick up whatever is lying in their way.
    if d.carries and not e.carry then
        for _, c in ipairs(self.corpses) do
            if not c.carried and not c.absorb and c.kind ~= "ball" and (c.x - e.x) ^ 2 + (c.z - e.z) ^ 2 < 36 then
                c.carried, e.carry = e, c
                break
            end
        end
    end

    local speed = d.speed
    if e.raged then speed = speed * d.rage end
    if self:walk(e, speed * slow, dt) then self:reachHeart(e) end
end

-- A pillbug walks a while, then rolls up: armoured, fast, crushing any link
-- it crosses, until a mat catches it and it uncurls, stuck.
function Game:pillbug(e, d, slow, dt)
    local mat = self:onMat(e)
    if mat and e.rolling then
        -- The mat catches the roll: it uncurls, stuck, and is soft again.
        e.rolling, e.walked, e.stuck = false, 0, 1.0
        self:burst(e.x, 2, e.z, 6, { "l", "c" }, 14)
        self:cue("lay", e.x, e.z, 0.7)
    end
    if e.stuck then
        e.stuck = e.stuck - dt
        if e.stuck <= 0 then e.stuck = nil end
        return true
    end
    e.walked = e.walked + dt
    if e.rolling then
        if e.walked >= d.rollFor then e.rolling, e.walked = false, 0 end
        -- Rolling crushes any link it crosses, outright.
        local l = self:linkNear(e, 4)
        if l then self:crush(l) end
        if self:walk(e, d.rollSpeed * slow, dt) then self:reachHeart(e) end
        return true
    elseif e.walked >= d.walkFor and not mat then
        e.rolling, e.walked = true, 0
    end
end

-- Brine runs down the first link it touches (see Game:slide).
function Game:brine(e)
    local l = self:linkNear(e, 4)
    if l then
        self:attach(e, l)
        return true
    end
end

-- A cordyceps host: back the way it came, biting its own, until it fruits.
function Game:host(e, d, dt)
    e.infected = e.infected - dt
    if e.infected <= 0 then
        e.infected = 0.01 -- still counts as a host for the death it is about to die
        e.hp = 0
        self:kill(e)
        return
    end
    for _, o in ipairs(self.enemies) do
        if o ~= e and not o.dead and not (o.infected and o.infected > 0) and not D.ENEMIES[o.kind].fly
            and (o.x - e.x) ^ 2 + (o.z - e.z) ^ 2 < 64 then
            self:hurt(o, e.hostBite * dt, true, true)
            if self.dice:random() < dt * 6 then self:burst(o.x, 3, o.z, 1, { "r", "t" }, 10) end
        end
    end
    self:walkBack(e, d.speed * 0.8, dt)
end

-- Something chews a fruiting body: a lamp goes out its own way.
function Game:gnawTower(n, amount, why)
    local t = n.tower
    t.hp = t.hp - amount
    t.flash = 0.05
    if t.hp <= 0 then
        if t.kind == "lamp" then self:snuff(n) else self:destroyTower(n, why or "EATEN") end
    end
end

-- The nearest fed stinkhorn whose stench reaches a fly, if any.
function Game:bait(e)
    local best, bd
    for _, n in ipairs(self.nodes) do
        local t = n.tower
        if t and t.kind == "stink" and t.hunger ~= "dormant" then
            local r = self:stat(t, "bait")
            local d2 = (n.x - e.x) ^ 2 + (n.z - e.z) ^ 2
            if d2 <= r * r and (not bd or d2 < bd) then best, bd = n, d2 end
        end
    end
    return best
end

-- The light a moth flies to: a lit Ghost Lamp it can see, or else the
-- nearest glowing fruiting body.
function Game:light(e)
    local lamp, ld, any, ad
    for _, n in ipairs(self.nodes) do
        local t = n.tower
        if t and t.hunger ~= "dormant" then
            local d2 = (n.x - e.x) ^ 2 + (n.z - e.z) ^ 2
            if t.kind == "lamp" and (t.glow or 0) > 0 and d2 <= 140 * 140 and (not ld or d2 < ld) then lamp, ld = n, d2 end
            if n.conn and d2 <= 60 * 60 and (not ad or d2 < ad) then any, ad = n, d2 end
        end
    end
    return lamp or any
end

-- A flier: straight at the sprout over everything, unless a lamp's glow, a
-- stinkhorn's stench or (a moth) any light turns it first.
function Game:fly(e, d, pace, dt)
    local speed = d.speed * pace
    e.y = (d.moth and 10 or 12) + sin(e.anim * (d.moth and 3 or 5)) * 2
    if e.state == "lured" then
        local n = e.lamp
        e.lureT = e.lureT - dt
        if not (n.tower and n.tower.kind == "lamp") or e.lureT <= 0 then
            e.state, e.lamp = "walk", nil
        else
            local a = e.anim * 2 + e.off
            local _, dd = toward(e, n.x + cos(a) * 4, n.z + sin(a) * 4, speed, dt)
            e.togo = 300 + dd
            if dd < 7 then self:gnawTower(n, (d.nibble or d.bite or 3) * dt) end
            return
        end
    end
    if not e.baited and not e.baitDone then
        local n = self:bait(e)
        if n then e.baited, e.baitT = n, self:stat(n.tower, "hold") end
    end
    if e.baited then
        local n = e.baited
        e.baitT = e.baitT - dt
        if not (n.tower and n.tower.kind == "stink") or e.baitT <= 0 then
            e.baited, e.baitDone = nil, true
        else
            local a = e.anim * 2.2 + e.off
            toward(e, n.x + cos(a) * 7, n.z + sin(a) * 7, speed, dt)
            e.togo = 300
            return
        end
    end
    if d.moth then
        local n = self:light(e)
        if n then
            local _, dd = toward(e, n.x, n.z, speed, dt)
            e.togo = 300 + dd
            if dd < 6 then self:gnawTower(n, d.nibble * dt, "EATEN") end
            return
        end
    end
    local h = self.heart
    local arrived, dd = toward(e, h.x, h.z, speed, dt)
    e.togo = dd
    if arrived or dd < 4 then self:reachHeart(e) end
end

-- A walker in a lamp's glow goes to it and chews.
function Game:lured(e, d, slow, dt)
    local n = e.lamp
    e.lureT = e.lureT - dt
    if not (n.tower and n.tower.kind == "lamp") or e.lureT <= 0 then
        e.state, e.lamp = "back", nil
        return
    end
    local dd = sqrt((n.x - e.x) ^ 2 + (n.z - e.z) ^ 2)
    if dd > 5 then
        toward(e, n.x, n.z, d.speed * slow, dt)
    else
        e.h = atan2(n.z - e.z, n.x - e.x)
        e.anim = e.anim + dt
        self:gnawTower(n, (d.bite or 4) * dt, "CHEWED")
    end
    e.y = self.world:groundAt(e.x, e.z)
    e.togo = 200 + dd
end

-- A centipede, every body of it: the Giant crushes every thread it runs
-- over, the small one gnaws them.
function Game:trample(e, d, dt)
    if d.crushR then
        for _, l in ipairs(self:linksNear(e.x, e.z, d.crushR)) do self:crush(l) end
    elseif d.wear then
        for _, l in ipairs(self:linksNear(e.x, e.z, d.wearR)) do
            self:biteLink(l, d.wear * dt)
            if fr() < dt * 3 then self:sparks(e.x, e.y + 1, e.z, 1, { "c", "l" }, 8) end
        end
    end
end

-- A centipede segment keeps its place behind the one ahead, and tramples what
-- it crosses. When the one ahead is gone it leads what is left behind it.
function Game:follow(e, d, slow, dt)
    local L = e.leader
    if L.dead then
        e.leader = nil
        local c, r = floor(e.x / TILE), floor(e.z / TILE)
        if self.world:distAt(c, r) then e.tc, e.tr = c, r end
        return
    end
    if L.hidden then return end
    local dx, dz = L.x - e.x, L.z - e.z
    local dd = sqrt(dx * dx + dz * dz)
    local gap = e.train.gap
    if dd > gap then
        local s = min(dd - gap, d.speed * 1.6 * slow * dt)
        e.x, e.z = e.x + dx / dd * s, e.z + dz / dd * s
    end
    if dd > 0.01 then e.h = atan2(dz, dx) end
    e.togo = (L.togo or 0) + gap
    local c, r = floor(e.x / TILE), floor(e.z / TILE)
    if self.world:distAt(c, r) then e.tc, e.tr = c, r end
    self:trample(e, d, dt)
end

-- Does a fed Lion's Mane tend this node? Its threads hold what the Water Bug
-- grabs.
function Game:maned(node)
    for _, n in ipairs(self.nodes) do
        local t = n.tower
        if t and t.kind == "mane" and n.conn and t.hunger ~= "dormant" and t.care and t.care[node] then return true end
    end
    return false
end

-- The Giant Water Bug: under the flooded lane nothing can touch it. Every few
-- seconds it surfaces, lunges at the nearest fruiting body in reach that is
-- not on high ground, and drags it; it lets go when its hold runs out.
-- Answers true while it is off the trail.
function Game:waterbug(e, d, slow, dt)
    e.grabCd = e.grabCd - dt
    if e.state == "lunge" or e.state == "grab" then
        local n = e.prey
        if not n.tower then e.state, e.prey = "back", nil return true end
        if e.state == "lunge" then
            local _, dd = toward(e, n.x, n.z, d.lunge * slow, dt)
            e.y = self.world:groundAt(e.x, e.z)
            if dd < 8 then e.state, e.holdT = "grab", d.hold end
            return true
        end
        e.h = atan2(n.z - e.z, n.x - e.x)
        e.anim = e.anim + dt * 2
        local grip = self:maned(n) and 0.5 or 1
        self:gnawTower(n, d.drag * grip * dt, "DRAGGED UNDER")
        e.holdT = e.holdT - dt
        if not n.tower then
            self:burst(n.x, 2, n.z, 16, { "s", "w", "d" }, 26)
            self:cue("splash", n.x, n.z)
            e.state, e.prey = "back", nil
        elseif e.holdT <= 0 then
            self:say("IT LETS GO", n.x, n.y + 16, n.z, "l")
            e.state, e.prey = "back", nil
        end
        return true
    end
    e.under = self.world:floodedAt(e.x, e.z) and e.state == "walk"
    if e.under and e.grabCd <= 0 then
        local best, bd
        for _, n in ipairs(self.nodes) do
            if n.tower and not (n.pocket and n.pocket.high) then
                local d2 = (n.x - e.x) ^ 2 + (n.z - e.z) ^ 2
                if d2 <= d.grabR * d.grabR and (not bd or d2 < bd) then best, bd = n, d2 end
            end
        end
        if best then
            e.state, e.prey, e.under, e.grabCd = "lunge", best, false, d.grabEvery
            self:burst(e.x, 2, e.z, 14, { "s", "w", "d" }, 24)
            self:say("IT SURFACES", e.x, 20, e.z, "r")
            self:shock(e.x, e.z, 22, 0.6, "w", "s")
            self:cue("surface", e.x, e.z)
            self.events.shake = 0.25
            return true
        end
    end
    return false
end

-- The Bombardier Beetle: walking, it scalds the nearest tower in reach every
-- few seconds; near the end of the trail it stops, turns its back on the
-- sprout and sprays it until it is killed. Answers true while it holds.
function Game:bombardier(e, d, slow, dt)
    e.spray = e.spray - dt * self:pace()
    local left = self.world:distAt(e.tc, e.tr) or 0
    local h = self.heart
    if e.state == "siege" or left <= d.siege then
        if e.state ~= "siege" then
            e.state = "siege"
            self:say("IT TURNS", e.x, 24, e.z, "r")
            self:shock(e.x, e.z, 20, 0.5, "r", "t")
        end
        e.h = atan2(e.z - h.z, e.x - h.x) -- its back to the sprout: the spray comes out behind
        e.togo = 0
        if e.spray <= 0 then
            e.spray = d.siegeEvery
            self:scald(e, d, h.x, h.z, nil)
        end
        return true
    end
    if e.spray <= 0 then
        local best, bd
        for _, n in ipairs(self.nodes) do
            if n.tower then
                local d2 = (n.x - e.x) ^ 2 + (n.z - e.z) ^ 2
                if d2 <= d.sprayR * d.sprayR and (not bd or d2 < bd) then best, bd = n, d2 end
            end
        end
        if best then
            e.spray = d.sprayEvery
            self:scald(e, d, best.x, best.z, best)
        end
    end
    return false
end

-- A boiling spray from (e) at (tx, tz): the first thing in the way takes it --
-- a shelf, a fruiting body -- or else what it was aimed at. `target` nil is
-- the sprout.
function Game:scald(e, d, tx, tz, target)
    local hit, hd
    local function block(x, z, what)
        local dd, f = segDist(x, z, e.x, e.z, tx, tz)
        if dd <= d.coverR and f > 0.05 and f < 0.98 then
            local k = (x - e.x) ^ 2 + (z - e.z) ^ 2
            if not hd or k < hd then hit, hd = what, k end
        end
    end
    for _, m in ipairs(self.mats) do if m.kind == "shelf" then block(m.x, m.z, m) end end
    for _, n in ipairs(self.nodes) do if n.tower and n ~= target then block(n.x, n.z, n) end end
    local ex, ez = tx, tz
    if hit then
        ex, ez = hit.x, hit.z
        if hit.node == nil and hit.kind == "shelf" then
            hit.hp, hit.chewed = hit.hp - d.scald, true
            self:say("COVER", ex, 14, ez, "l")
        else
            self:gnawTower(hit, d.scald, "SCALDED")
            self:say("COVER", ex, 18, ez, "l")
        end
    elseif target then
        self:gnawTower(target, d.scald, "SCALDED")
    else
        self.heartHp = self.heartHp - d.heartSpray
        self.stats.leaked.bombardier = (self.stats.leaked.bombardier or 0) + d.heartSpray
        self.events.heart = true
    end
    for _, l in ipairs(self:linksNear(ex, ez, 6)) do self:biteLink(l, 20) end
    for k = 1, 14 do
        local f = k / 14
        self.fx[#self.fx + 1] = { streak = true, x = e.x, y = 4, z = e.z, tx = ex + (self.dice:random() - 0.5) * 8 * f,
            tz = ez + (self.dice:random() - 0.5) * 8 * f, t = -f * 0.25, life = 0.55, max = 0.3, k = k % 3 == 0 and "t" or "w" }
    end
    self:burst(ex, 4, ez, 10, { "w", "t", "s" }, 20)
    self:splat(ex, ez, 5, "w", 1.5)
    self:cue("spray", e.x, e.z)
end

-- The Mole Cricket: every so often it stops and digs, then burrows straight
-- across to the trail tile in reach that is the most steps nearer the sprout
-- and comes up there, dazed. The tunnel it leaves stays open (see `burrow`).
-- Answers true while it is not walking.
function Game:mole(e, d, slow, dt)
    if e.state == "dig" then
        local a = e.dug.a
        toward(e, a.x, a.z, d.speed * slow, dt)
        e.h = atan2(e.dug.b.z - e.z, e.dug.b.x - e.x)
        e.anim = e.anim + dt
        e.digT = e.digT - dt * self:pace()
        if fr() < dt * 12 then
            self:motes(e.x + cos(e.h) * 9, e.y, e.z + sin(e.h) * 9, 1, { "t", "n", "u" }, 4, 16, 0.5)
        end
        if e.digT <= 0 then
            e.state, e.under = "burrow", true
            e.x, e.z = a.x, a.z
            self.tunnels[#self.tunnels + 1] = e.dug
            self:burst(a.x, 3, a.z, 18, { "t", "n", "u" }, 24)
            self:splat(a.x, a.z, 8, "u", 4)
            self:say("IT BURROWS", a.x, 24, a.z, "r")
            self:cue("burrow", a.x, a.z)
        end
        return true
    elseif e.state == "burrow" then
        local b = e.dug.b
        e.togo = (self.world:distAt(b.c, b.r) or 0) * TILE
        if fr() < dt * 8 then self:motes(e.x, e.y, e.z, 1, { "t", "n" }, 5, 6, 0.6) end
        if toward(e, b.x, b.z, d.burrow * self:pace(), dt) then
            e.under, e.state, e.surfaceT = false, "surface", d.surfaceFor
            e.tc, e.tr = b.c, b.r
            e.dug.open, e.dug = true, nil
            e.digs, e.digCd = e.digs + 1, d.digEvery
            self:burst(b.x, 3, b.z, 22, { "t", "n", "u" }, 28)
            self:splat(b.x, b.z, 8, "u", 4)
            self:shock(b.x, b.z, 24, 0.6, "t", "n")
            self:say("A TUNNEL OPENS", b.x, 24, b.z, "r")
            self:cue("surface", b.x, b.z)
            self.events.shake = 0.3
        end
        return true
    elseif e.state == "surface" then
        -- Shaking the soil off: still, for a moment.
        e.surfaceT = e.surfaceT - dt
        if e.surfaceT <= 0 then e.state = "walk" end
        return true
    end
    if e.state ~= "walk" or e.digs >= d.digs then return false end
    e.digCd = e.digCd - dt
    if e.digCd > 0 then return false end
    -- The tile it is walking to, and the one in reach most steps on from it.
    local w = self.world
    local from = w:distAt(e.tc, e.tr)
    local ax, az = e.tc * TILE + TILE / 2, e.tr * TILE + TILE / 2
    local best, bd, bs
    local span = math.ceil(d.reach / TILE)
    if not from or w:floodedAt(ax, az) then from, span = 0, -1 end -- no digging in water
    for r = e.tr - span, e.tr + span do
        for c = e.tc - span, e.tc + span do
            local left = w:distAt(c, r)
            local x, z = c * TILE + TILE / 2, r * TILE + TILE / 2
            local d2 = (x - ax) ^ 2 + (z - az) ^ 2
            if left and left >= d.keep and from - left >= d.save and from - left <= d.most and d2 <= d.reach * d.reach
                and not w:floodedAt(x, z)
                and (not best or left < bd or (left == bd and d2 < bs)) then
                best, bd, bs = { c = c, r = r, x = x, z = z }, left, d2
            end
        end
    end
    if not best then
        e.digCd = 1 -- nowhere worth it from here; try again further on
        return false
    end
    e.state, e.digT = "dig", d.digFor
    e.dug = { a = { c = e.tc, r = e.tr, x = ax, z = az }, b = best, owner = e, open = false }
    self:say("IT DIGS", e.x, 24, e.z, "t")
    self:cue("dig", e.x, e.z)
    return true
end

-- Something walking comes to the mouth of an open tunnel: down it goes, and
-- climbs out of the far end a few seconds on. Not a boss, a flier, a drop of
-- brine, a host, or a springtail in the air. Answers true when it went down.
function Game:burrow(e)
    local d = D.ENEMIES[e.kind]
    if d.boss or d.fly or e.slide or e.hopT or (e.infected and e.infected > 0) then return false end
    for _, t in ipairs(self.tunnels) do
        if t.open and e.tc == t.a.c and e.tr == t.a.r then
            e.hidden, e.tunnel = D.ENEMIES[t.owner.kind].tunnelFor, t
            e.state, e.chewing, e.rolling = "walk", nil, false
            self:motes(e.x, e.y, e.z, 2, { "t", "n" }, 3, 8, 0.4)
            self:cue("dig", e.x, e.z, 0.4)
            return true
        end
    end
    return false
end

-- Out of the far end of a tunnel, dazed.
function Game:emerge(e)
    local t = e.tunnel
    e.tunnel = nil
    e.x, e.z = t.b.x + (self.dice:random() - 0.5) * 6, t.b.z + (self.dice:random() - 0.5) * 6
    e.tc, e.tr = t.b.c, t.b.r
    e.y = self.world:groundAt(e.x, e.z)
    e.stun = max(e.stun, D.ENEMIES[t.owner.kind].daze)
    self:motes(e.x, e.y, e.z, 4, { "t", "n" }, 4, 10, 0.5)
end

-- The digger is gone: its tunnel falls in on whatever is down it.
function Game:collapse(t)
    unlist(self.tunnels, t)
    if not t.open then return end
    local buried = 0
    for _, e in ipairs(self.enemies) do
        if e.tunnel == t and not e.dead then
            e.hidden, e.tunnel = nil, nil
            self:kill(e)
            buried = buried + 1
        end
    end
    for _, h in ipairs({ t.a, t.b }) do
        self:burst(h.x, 2, h.z, 12, { "t", "n", "u" }, 18)
        self:shock(h.x, h.z, 14, 0.5, "n", "u")
    end
    self:say(buried > 0 and ("CAVED IN: " .. buried .. " BURIED") or "CAVED IN", t.a.x, 20, t.a.z, "g")
    self:cue("thump", t.a.x, t.a.z)
end

function Game:mite(e, d, slow, dt)
    if e.gnaw and e.gnaw.state ~= "alive" then e.gnaw = nil end
    if not e.gnaw and not e.full and not e.blind then
        local l = self:linkNear(e, d.sniff)
        if l then
            local _, t = segDist(e.x, e.z, l.a.x, l.a.z, l.b.x, l.b.z)
            e.gnaw, e.gt = l, max(0.1, min(0.9, t + (self.dice:random() - 0.5) * 0.3))
        end
    end
    if e.gnaw then
        local l = e.gnaw
        local tx, tz = l.a.x + (l.b.x - l.a.x) * e.gt, l.a.z + (l.b.z - l.a.z) * e.gt
        if toward(e, tx, tz, d.speed * slow, dt) then
            self:biteLink(l, d.chew * dt)
            self:chewing(e)
            e.gnawed = (e.gnawed or 0) + dt
            if e.gnawed > 6 then e.full, e.gnaw = true, nil end -- had enough; back to the march
        end
        return true
    end
    -- Back to the trail tile it left, then on.
    if self:walk(e, d.speed * slow, dt) then self:reachHeart(e) end
    return true
end

-- A slug stops to eat any fruiting body it passes.
function Game:slug(e, d, slow, dt)
    local food
    for _, n in ipairs(self.nodes) do
        if n.tower and (n.x - e.x) ^ 2 + (n.z - e.z) ^ 2 <= d.eatR * d.eatR then food = n break end
    end
    if food then
        e.state = "eat"
        e.h = atan2(food.z - e.z, food.x - e.x)
        food.tower.hp = food.tower.hp - d.eat * dt
        food.tower.flash = 0.05
        if food.tower.hp <= 0 then self:destroyTower(food, "EATEN") end
        return true
    end
    e.state = "walk"
    if self:walk(e, d.speed * slow, dt) then self:reachHeart(e) end
    return true
end

-- A wolf spider leaves the trail for the deadliest tower it can see, webs it
-- shut, and comes back. Answers true while it is off the trail.
function Game:spider(e, d, slow, dt)
    e.webCd = e.webCd - dt
    if e.state == "walk" and e.webCd <= 0 and not e.blind then
        local best, bs
        for _, n in ipairs(self.nodes) do
            local t = n.tower
            if t and t.webbed <= 0 and not t.warded and (n.x - e.x) ^ 2 + (n.z - e.z) ^ 2 <= d.webR * d.webR then
                local s = self:threat(t)
                if not bs or s > bs then best, bs = n, s end
            end
        end
        if best then e.state, e.prey = "hunt", best end
    end
    if e.state == "hunt" then
        local n = e.prey
        if not n.tower then e.state = "back" return true end
        local arrived, dd = toward(e, n.x, n.z, d.speed * slow, dt)
        e.y = self.world:groundAt(e.x, e.z)
        if arrived or dd < 5 then
            if not n.tower.warded then n.tower.webbed = d.web end
            self:burst(n.x, n.y + 8, n.z, 6, { "w", "s" }, 10)
            self:cue("web", n.x, n.z)
            e.webCd, e.state = d.webCd, "back"
        end
        return true
    elseif e.state == "back" then
        local arrived = toward(e, e.tc * TILE + TILE / 2, e.tr * TILE + TILE / 2, d.speed * slow, dt)
        e.y = self.world:groundAt(e.x, e.z)
        if arrived then e.state, e.y = "walk", self.world:groundAt(e.x, e.z) end
        return true
    end
end

-- The Queen lays workers as she goes and gnaws every thread in reach.
function Game:queen(e, d, _, dt)
    e.brood = e.brood - dt
    if e.brood <= 0 then
        e.brood = d.broodEvery
        for k = 1, d.brood do
            local a = k / d.brood * 2 * math.pi
            local o = self:spawnAt("ant", e.x + cos(a) * 6, e.z + sin(a) * 6, e.tc, e.tr)
            o.hp, o.maxHp = D.ENEMIES.ant.hp, D.ENEMIES.ant.hp
        end
        self:burst(e.x, 4, e.z, 8, { "w", "t" }, 12)
        self:cue("brood", e.x, e.z)
    end
    for _, l in ipairs(self:linksNear(e.x, e.z, d.gnawR)) do self:biteLink(l, d.gnaw * dt) end
end

-- The Stag Beetle charges every few seconds: whatever its jaws pass is
-- sheared through, and towers it thunders past are stunned. Answers true
-- while charging (it has moved).
function Game:stag(e, d, slow, dt)
    e.charge = e.charge - dt
    if e.charging then
        e.charging = e.charging - dt
        if e.charging <= 0 then e.charging, e.charge = nil, d.chargeEvery end
        local jx, jz = e.x + cos(e.h) * 10, e.z + sin(e.h) * 10
        for _, l in ipairs(self:linksNear(jx, jz, d.shear)) do self:crush(l) end
        for _, n in ipairs(self.nodes) do
            if n.tower and not n.tower.warded and (n.x - e.x) ^ 2 + (n.z - e.z) ^ 2 <= d.stunR * d.stunR then
                if n.tower.stun <= 0 then
                    self:burst(n.x, n.y + 8, n.z, 4, { "w", "t" }, 10)
                    self:cue("stun", n.x, n.z)
                end
                n.tower.stun = d.stun
            end
        end
        self.events.shake = 0.12
        if self:walk(e, d.chargeSpeed * slow, dt) then self:reachHeart(e) end
        return true
    elseif e.charge <= 0 then
        e.charging = d.chargeFor
        self:say("CHARGE!", e.x, 26, e.z, "r")
        self:burst(e.x, 2, e.z, 10, { "t", "n" }, 20)
        self:shock(e.x, e.z, 18, 0.4, "t", "n")
        self:cue("charge", e.x, e.z)
    end
end

-- The link a cricket nymph would come up beside: the nearest in reach, a fed
-- one before a starved one, and where beside it, out of the water. Answers
-- the link and that spot.
function Game:cricketPrey(e, d)
    local w = self.world
    local best, bx, bz, bd
    for _, l in ipairs(self.links) do
        if alive(l) then
            local dd, _, qx, qz = segDist(e.x, e.z, l.a.x, l.a.z, l.b.x, l.b.z)
            if dd <= d.reach then
                -- A step short of the thread, on its near side.
                local k = dd > 4 and 4 / dd or 0
                local x, z = qx + (e.x - qx) * k, qz + (e.z - qz) * k
                local score = dd + ((l.a.conn or l.b.conn) and 0 or d.reach)
                if not w:floodedAt(x, z) and (not bd or score < bd) then best, bx, bz, bd = l, x, z, score end
            end
        end
    end
    return best, bx, bz
end

-- The trail tile nearest (x, z), for a cricket nymph climbing back to it.
function Game:nearestTrail(x, z, c0, r0)
    local w = self.world
    local bc, br, bd = c0, r0
    local mc, mr = floor(x / TILE), floor(z / TILE)
    for r = mr - 6, mr + 6 do
        for c = mc - 6, mc + 6 do
            if w:distAt(c, r) then
                local d2 = (c * TILE + TILE / 2 - x) ^ 2 + (r * TILE + TILE / 2 - z) ^ 2
                if not bd or d2 < bd then bc, br, bd = c, r, d2 end
            end
        end
    end
    return bc, br
end

-- The cricket nymph: walking, every few seconds it looks for a link in reach
-- off the trail; with one, it digs in (still, for a moment), burrows to it
-- under the board -- a bump in the soil, nothing can touch it -- and comes
-- up beside it and cuts it. Up it is still and soft, then it goes for the
-- next, and after `cuts` of them climbs back to the trail. Answers true
-- while it is off its walk.
function Game:cricket(e, d, slow, dt)
    local pace = self:pace()
    if e.state == "sink" then
        e.sinkT = e.sinkT - dt * pace
        e.anim = e.anim + dt
        if fr() < dt * 10 then self:motes(e.x, e.y, e.z, 1, { "t", "n", "u" }, 3, 10, 0.4) end
        if e.sinkT <= 0 then
            e.state, e.under = "tunnel", true
            self:burst(e.x, 2, e.z, 8, { "t", "n", "u" }, 16)
            self:splat(e.x, e.z, 4, "u", 2)
            self:cue("burrow", e.x, e.z, 0.5)
        end
        return true
    elseif e.state == "tunnel" then
        if not alive(e.prey) then
            -- Its link is gone already: the next, or up where it is.
            e.prey, e.px, e.pz = self:cricketPrey(e, d)
            if not e.prey then e.px, e.pz = e.x, e.z end
        end
        if fr() < dt * 6 then self:motes(e.x, e.y, e.z, 1, { "t", "n" }, 3, 5, 0.5) end
        if toward(e, e.px, e.pz, d.burrow * pace, dt) or self.world:floodedAt(e.x, e.z) and not e.prey then
            e.under, e.state, e.surfaceT = false, "up", d.surfaceFor
            e.y = self.world:groundAt(e.x, e.z)
            self:burst(e.x, 2, e.z, 12, { "t", "n", "u" }, 20)
            self:splat(e.x, e.z, 5, "u", 3)
            self:cue("surface", e.x, e.z, 0.5)
            if e.prey then
                e.h = atan2(e.prey.a.z + e.prey.b.z - 2 * e.z, e.prey.a.x + e.prey.b.x - 2 * e.x)
                self:crush(e.prey)
                e.cut = e.cut + 1
            end
            e.prey = nil
        end
        return true
    elseif e.state == "up" then
        e.surfaceT = e.surfaceT - dt
        if e.surfaceT > 0 then return true end
        if e.cut < d.cuts then
            local l, x, z = self:cricketPrey(e, d)
            if l then
                e.prey, e.px, e.pz, e.state, e.sinkT = l, x, z, "sink", d.sinkFor
                self:cue("dig", e.x, e.z, 0.4)
                return true
            end
        end
        -- Back to the trail, and on along it.
        e.cut = d.cuts
        e.tc, e.tr = self:nearestTrail(e.x, e.z, e.tc, e.tr)
        e.state = "back"
        return true
    end
    if e.state ~= "walk" or e.cut >= d.cuts then return false end
    e.sinkCd = e.sinkCd - dt
    if e.sinkCd > 0 or self.world:floodedAt(e.x, e.z) then return false end
    local l, x, z = self:cricketPrey(e, d)
    if not l then
        e.sinkCd = 1 -- nothing in reach from here; try again further on
        return false
    end
    e.prey, e.px, e.pz, e.state, e.sinkT = l, x, z, "sink", d.sinkFor
    self:cue("dig", e.x, e.z, 0.4)
    return true
end

-- A springtail springs off its tail every few seconds, and at once when a
-- shelf stands in its way or a mat is under it: over, and on down the trail.
-- The first time it comes down by a thread, the thread snaps.
function Game:springtail(e, d, slow, dt)
    if e.hopT then
        e.hopT = e.hopT - dt
        e.lift = sin(min(1, 1 - e.hopT / d.hopFor) * math.pi) * d.hopH
        if self:walk(e, d.hopSpeed * self:pace(), dt) then self:reachHeart(e) return true end
        -- It keeps going until it is past the shelf.
        if e.hopT <= 0 and not self:blocker(e) then
            e.hopT, e.lift, e.hopCd = nil, 0, d.hopEvery * (0.8 + self.dice:random() * 0.4)
            self:motes(e.x, e.y, e.z, 3, { "t", "n" }, 4, 6, 0.4)
            if not e.snapped then
                local l = self:linkNear(e, d.snapR)
                if l then
                    e.snapped = true
                    self:say("SNAP", e.x, e.y + 10, e.z, "r")
                    self:crush(l)
                end
            end
        end
        return true
    end
    e.hopCd = e.hopCd - dt
    if e.hopCd <= 0 or self:blocker(e) or self:onMat(e) then
        e.hopT, e.state, e.chewing = d.hopFor, "walk", nil
        self:cue("spring", e.x, e.z)
        return true
    end
    return false
end

-- The Click Beetle: walks, rolls onto its back and plays dead (soft), then
-- clicks and leaps down the trail. Where it comes down, links are cut and
-- towers stunned.
function Game:click(e, d, _, dt)
    if e.state == "belly" then
        e.bellyT = e.bellyT - dt
        if e.bellyT <= 0 then
            e.state, e.leapT = "leap", d.leapFor
            self:say("CLICK!", e.x, 26, e.z, "r")
            self:burst(e.x, 3, e.z, 10, { "t", "n" }, 22)
            self:cue("clack", e.x, e.z)
            self.events.shake = 0.15
        end
        return true
    elseif e.state == "leap" then
        e.leapT = e.leapT - dt
        local p = min(1, 1 - e.leapT / d.leapFor)
        e.lift, e.spin = sin(p * math.pi) * d.leapH, p
        if self:walk(e, d.leapSpeed * self:pace(), dt) then self:reachHeart(e) return true end
        if e.leapT <= 0 then
            e.state, e.lift, e.spin, e.clickCd = "walk", 0, nil, d.clickEvery
            for _, l in ipairs(self:linksNear(e.x, e.z, d.slamR)) do self:crush(l) end
            for _, n in ipairs(self.nodes) do
                if n.tower and not n.tower.warded and (n.x - e.x) ^ 2 + (n.z - e.z) ^ 2 <= d.stunR * d.stunR then
                    if n.tower.stun <= 0 then
                        self:burst(n.x, n.y + 8, n.z, 4, { "w", "t" }, 10)
                        self:cue("stun", n.x, n.z)
                    end
                    n.tower.stun = d.stun
                end
            end
            self:shock(e.x, e.z, d.slamR + 6, 0.5, "t", "n")
            self:burst(e.x, 2, e.z, 16, { "t", "n", "u" }, 24)
            self:cue("thump", e.x, e.z)
            self.events.shake = 0.5
        end
        return true
    end
    e.clickCd = e.clickCd - dt
    if e.clickCd <= 0 then
        e.state, e.bellyT = "belly", d.bellyFor
        self:say("IT PLAYS DEAD", e.x, 26, e.z, "l")
        self:burst(e.x, 3, e.z, 6, { "t", "n" }, 12)
        self:cue("trip", e.x, e.z)
        return true
    end
    return false
end

-- The Dung Beetle's ball flattens every link and mat it rolls over.
function Game:dung(e, d, _, dt)
    if not e.ballHp or e.ballHp <= 0 then
        e.raged = true
        return
    end
    local bx, bz = self:ballAt(e)
    for _, l in ipairs(self:linksNear(bx, bz, d.ballR)) do self:crush(l) end
    for k = #self.mats, 1, -1 do
        local m = self.mats[k]
        if (m.x - bx) ^ 2 + (m.z - bz) ^ 2 <= (d.ballR + 6) ^ 2 then self:breakMat(m) end
    end
    e.ballRoll = (e.ballRoll or 0) + dt
end

-- Brine touches a link and runs down it, away from the Heart.
function Game:attach(e, l)
    local a, b = l.a, l.b
    local from, to
    if a.hop ~= b.hop then
        if a.hop < b.hop then from, to = a, b else from, to = b, a end
    else
        local da, db = dist(e, a), dist(e, b)
        if da < db then from, to = a, b else from, to = b, a end
    end
    local _, t = segDist(e.x, e.z, from.x, from.z, to.x, to.z)
    e.slide, e.from, e.to, e.st = l, from, to, t
    self.events.brine = true
    self:cue("splash", e.x, e.z, 0.7)
end

function Game:slide(e, d, dt)
    local l = e.slide
    if l.state ~= "alive" then
        -- The thread it ran on is gone: it falls into the soil and is spent.
        e.dead = true
        self:burst(e.x, 2, e.z, 10, { "w", "s" }, 20)
        self:say("FIZZLED", e.x, 8, e.z, "w")
        self:cue("fizzle", e.x, e.z)
        return
    end
    e.st = e.st + d.slide * dt / max(1, l.len)
    local f, t = e.from, e.to
    e.x, e.z = f.x + (t.x - f.x) * e.st, f.z + (t.z - f.z) * e.st
    e.y = (f.y + (t.y - f.y) * e.st) + 1
    e.h = atan2(t.z - f.z, t.x - f.x)
    e.togo = 0
    if e.st >= 1 then
        -- The link it came down is sterile, and so is whatever grew at the end.
        local node = t
        -- Which way is on downstream is decided before the cut, while the
        -- network still says what downstream is.
        local nextLink
        for _, o in ipairs(node.links) do
            local other = o.a == node and o.b or o.a
            if o ~= l and alive(o) and other.hop > node.hop and other.hop < huge then nextLink = o break end
        end
        self:cut(l)
        l.salted = true
        if node.tower then
            self:burst(node.x, node.y + 6, node.z, 14, { "w", "s", "r" }, 26)
            self:say("STERILISED", node.x, node.y + 14, node.z, "r")
            node.tower = nil
        end
        self:shock(node.x, node.z, 10, 0.4, "w", "s")
        self:cue("salt", node.x, node.z)
        node.salted = 12
        if nextLink then
            local other = nextLink.a == node and nextLink.b or nextLink.a
            e.slide, e.from, e.to, e.st = nextLink, node, other, 0
        else
            e.dead = true
            self:burst(node.x, 2, node.z, 8, { "w", "s" }, 18)
        end
        self:recompute()
    end
end

return Game

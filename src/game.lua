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
-- Decisions on the design doc's open questions, for this prototype:
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

local D = require "src.defs"
local World = require "src.world"

local sqrt, max, min, abs, floor, huge = math.sqrt, math.max, math.min, math.abs, math.floor, math.huge
local random = love.math.random

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

--- setting up -------------------------------------------------------------------------

function Game.new(world)
    local self = setmetatable({ world = world }, Game)
    self.nodes, self.links, self.mats = {}, {}, {}
    self.enemies, self.corpses, self.shots, self.fx, self.texts = {}, {}, {}, {}, {}
    self.nutrients = D.START_NUTRIENTS
    self.heartHp = D.HEART_HP
    self.wave, self.phase = 0, "build"
    self.clock, self.waveClock = 0, 0
    self.queue = {}
    self.seen = {}
    self.events = {}
    self.stats = { kills = 0, drunk = 0, stolen = 0, cuts = 0 }
    self.rings, self.ringKey = {}, ""
    self.pulseCd = 0
    self.nextLink = 1

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
    for _, n in ipairs(self.nodes) do n.conn, n.hop, n.cap, n.parent, n.via = false, huge, 0, nil, nil end
    -- Relays first: a link is thick if a fed relay reaches either end of it.
    for _, l in ipairs(self.links) do l.thick = false end
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
    for _, n in ipairs(self.nodes) do
        if n.tower and n.tower.kind == "relay" and n.conn then
            local r = D.TOWER.relay.range
            for _, l in ipairs(self.links) do
                if dist(l.a, n) <= r or dist(l.b, n) <= r then l.thick = true end
            end
        end
    end
    for _, l in ipairs(self.links) do l.cap = D.LINK.cap * (l.thick and 2 or 1) end
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
    local cost = D.LINK.cost(len)
    if self:linkBetween(a, b) then return false, cost, "ALREADY LINKED" end
    if len > D.LINK.reach then return false, cost, "TOO FAR" end
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
    local l = { id = self.nextLink, a = a, b = b, len = dist(a, b), cost = cost, hp = D.LINK.hp, state = "grow", grow = 0, bitten = {} }
    self.nextLink = self.nextLink + 1
    self.links[#self.links + 1] = l
    a.links[#a.links + 1] = l
    b.links[#b.links + 1] = l
    return l
end

local function unlist(list, item)
    for n = #list, 1, -1 do if list[n] == item then table.remove(list, n) end end
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
    local refund = floor(l.cost * back)
    self.nutrients = self.nutrients + refund
    local mx, mz = (l.a.x + l.b.x) / 2, (l.a.z + l.b.z) / 2
    self:say("+" .. refund, mx, 4, mz)
    self:removeLink(l)
    self:recompute()
end

function Game:cut(l, why)
    if l.state ~= "alive" and l.state ~= "grow" then return end
    l.state, l.hp, l.regrow, l.hand = "cut", 0, 0, false
    self.stats.cuts = self.stats.cuts + 1
    self.events.cut = true
    local mx, mz = (l.a.x + l.b.x) / 2, (l.a.z + l.b.z) / 2
    self:burst(mx, 1, mz, 8, { "c", "l", "r" }, 18)
    self:recompute()
end

function Game:repairCost(l) return max(1, floor(l.cost * D.LINK.repair + 0.5)) end

function Game:repair(l)
    if l.state ~= "cut" or l.hand or l.salted then return false end
    local c = self:repairCost(l)
    if self.nutrients < c then return false end
    self.nutrients = self.nutrients - c
    l.hand = true
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
    self.ringKey, self.rings = key, {}
    local seen = {}
    for _, l in ipairs(self.links) do
        if alive(l) and l.a.conn and l.b.conn then
            -- The shortest way round from one end to the other without this link.
            local from, back, queue, head = l.a, { [l.a] = false }, { l.a }, 1
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
                if #loop >= D.RING.nodes then
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
                        self.rings[#self.rings + 1] = { nodes = loop, set = {} }
                        for _, m in ipairs(loop) do self.rings[#self.rings].set[m] = true end
                        self.events.ring = true
                    end
                end
            end
        end
    end
    for _, n in ipairs(self.nodes) do n.ringed = self:ringed(n.x, n.z, n) end
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
    return node and node.conn and self.pulseCd <= 0
end

function Game:pulse(node)
    if not self:canPulse(node) then return false end
    self.pulseCd = D.PULSE.cooldown
    local n = node
    while n do
        if n.tower then n.tower.boost = D.PULSE.duration end
        if n.via then n.via.surge = D.PULSE.duration end
        n = n.parent
    end
    self:burst(node.x, node.y + 4, node.z, 12, { "l", "w", "c" }, 26)
    return true
end

--- fruiting bodies ----------------------------------------------------------------------

function Game:canBuild(kind, node)
    local d = D.TOWER[kind]
    if not node or node.heart or node.tower then return false end
    if (node.salted or 0) > 0 then return false, "SALTED" end
    if self.nutrients < d.cost then return false, "NOT ENOUGH NUTRIENTS" end
    return true
end

function Game:build(kind, node)
    if not self:canBuild(kind, node) then return false end
    local d = D.TOWER[kind]
    self.nutrients = self.nutrients - d.cost
    node.tower = { kind = kind, node = node, reserve = d.reserve or 0, cool = 0.3, squash = 0, flash = 0, spent = d.cost }
    self:recompute()
    return node.tower
end

function Game:sell(node)
    local t = node.tower
    if not t then return end
    local back = floor(t.spent * D.SELL)
    self.nutrients = self.nutrients + back
    self:say("+" .. back, node.x, node.y + 10, node.z)
    node.tower = nil
    self:recompute()
end

function Game:matAt(c, r)
    for _, m in ipairs(self.mats) do if m.c == c and m.r == r then return m end end
end

function Game:canMat(c, r)
    if not self.world:distAt(c, r) or self.world.cell(c, r) == "H" then return false end
    if self:matAt(c, r) then return false, "ALREADY A MAT" end
    if self.nutrients < D.TOWER.mat.cost then return false, "NOT ENOUGH NUTRIENTS" end
    return true
end

function Game:layMat(c, r)
    if not self:canMat(c, r) then return false end
    self.nutrients = self.nutrients - D.TOWER.mat.cost
    local m = { c = c, r = r, x = c * TILE + TILE / 2, z = r * TILE + TILE / 2, life = D.TOWER.mat.life, spent = D.TOWER.mat.cost }
    self.mats[#self.mats + 1] = m
    return m
end

function Game:liftMat(m)
    local back = floor(m.spent * D.SELL * m.life / D.TOWER.mat.life)
    self.nutrients = self.nutrients + back
    unlist(self.mats, m)
end

--- waves ---------------------------------------------------------------------------------

function Game:nextWave() return D.WAVES[self.wave + 1] end

function Game:startWave()
    if self.phase ~= "build" or not self:nextWave() then return end
    self.wave = self.wave + 1
    self.phase = "wave"
    self.waveClock = 0
    self.queue = {}
    for _, g in ipairs(D.WAVES[self.wave]) do
        local kind, n, every, gate, at = g[1], g[2], g[3], g[4], g[5]
        for k = 0, n - 1 do
            self.queue[#self.queue + 1] = { kind = kind, gate = gate, t = at + k * every }
        end
    end
    table.sort(self.queue, function(a, b) return a.t < b.t end)
end

function Game:spawn(kind, gate)
    local e = self.world.entrances[gate] or self.world.entrances[1]
    local d = D.ENEMIES[kind]
    local scale = 1 + D.HP_GROWTH * (self.wave - 1)
    self.seen[kind] = true
    local function one(ox, oz)
        local hp = d.hp * scale
        local en = { kind = kind, x = e.x - TILE * 0.6 + ox, z = e.z + oz, y = 0, c = e.c, r = e.r,
            hp = hp, maxHp = hp, h = 0, flash = 0, slow = 1, off = (random() - 0.5) * 6,
            walked = 0, anim = random() * 4, state = "walk" }
        en.tc, en.tr = e.c, e.r
        self.enemies[#self.enemies + 1] = en
        return en
    end
    if kind == "mite" then
        for _ = 1, d.swarm do one((random() - 0.5) * 10, (random() - 0.5) * 10) end
    else
        one(0, 0)
    end
end

--- harm -------------------------------------------------------------------------------------

function Game:burst(x, y, z, n, keys, speed)
    for _ = 1, n do
        local a, u = random() * 2 * math.pi, random()
        self.fx[#self.fx + 1] = {
            x = x, y = y, z = z,
            vx = math.cos(a) * speed * u, vy = speed * (0.4 + random()), vz = math.sin(a) * speed * u,
            life = 0.3 + random() * 0.3, k = keys[random(#keys)],
        }
    end
end

function Game:armor(e)
    local d = D.ENEMIES[e.kind]
    if e.rolling then return d.rolledArmor end
    return d.armor
end

function Game:hurt(e, amount, pierce)
    if e.dead then return end
    local a = pierce and 0 or self:armor(e)
    local dmg = max(amount * 0.15, amount - a)
    e.hp = e.hp - dmg
    e.flash = 0.08
    if e.hp <= 0 then self:kill(e) end
end

function Game:kill(e)
    e.dead = true
    self.stats.kills = self.stats.kills + 1
    local d = D.ENEMIES[e.kind]
    if e.carry then e.carry.carried = nil end
    if e.kind == "brine" then
        -- Salt water: nothing to drink, and a splash.
        self:burst(e.x, e.y + 2, e.z, 10, { "w", "s" }, 22)
        return
    end
    self:burst(e.x, 2, e.z, e.kind == "mite" and 2 or 6, { "r", "n", "t" }, 16)
    if d.corpse > 0 then
        self.corpses[#self.corpses + 1] = { kind = e.kind, x = e.x, z = e.z, h = e.h, value = d.corpse, life = 25 }
    end
end

--- the frame ---------------------------------------------------------------------------------

function Game:update(dt)
    self.clock = self.clock + dt
    self.events = {}
    if self.phase == "won" or self.phase == "lost" then
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
            self:spawn(q.kind, q.gate)
        end
        local living = 0
        for _, l in ipairs(self.links) do if alive(l) then living = living + 1 end end
        local income = D.INCOME - living * D.UPKEEP
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
    for _, e in ipairs(self.enemies) do if not e.dead then self:move(e, dt) end end
    for n = #self.enemies, 1, -1 do if self.enemies[n].dead then table.remove(self.enemies, n) end end
    self:updateShots(dt)
    self:updateCorpses(dt)
    self:updateFx(dt)
    self:recompute()

    if self.heartHp <= 0 then
        self.heartHp = 0
        self.phase = "lost"
    elseif self.phase == "wave" and not self.queue[1] and not self.enemies[1] then
        if self.wave >= #D.WAVES then
            self.phase = "won"
        else
            self.phase = "build"
            local bonus = D.WAVE_BONUS + 4 * self.wave
            self.nutrients = self.nutrients + bonus
            self:say("WAVE CLEAR +" .. bonus, self.heart.x, 26, self.heart.z, "g")
        end
    end
end

function Game:updateLinks(dt)
    local changed = false
    for _, l in ipairs(self.links) do
        if l.state == "grow" then
            l.grow = l.grow + dt * 16 / (D.LINK.grow * max(16, l.len))
            if l.grow >= 1 then l.state, l.grow, changed = "alive", 1, true end
        elseif l.state == "alive" then
            if l.hp <= 0 then self:cut(l) end
        elseif l.state == "cut" then
            if l.hand then
                l.regrow = l.regrow + dt / D.LINK.regrow
            end
            if l.regrow >= 1 then
                l.state, l.hp, l.hand, changed = "alive", D.LINK.hp * 0.6, false, true
                l.bitten = {}
            end
        end
    end
    if changed then self:recompute() end
end

-- Feeding and firing.
function Game:updateTowers(dt)
    local Q = World.QUALITY
    for _, n in ipairs(self.nodes) do
        local t = n.tower
        if t then
            local d = D.TOWER[t.kind]
            t.flash = max(0, t.flash - dt)
            t.squash = max(0, t.squash - dt * 4)
            if d.reserve and d.reserve > 0 and n.conn and self.nutrients > 0 then
                local want = d.reserve - t.reserve
                local take = min(want, n.cap * dt, self.nutrients)
                if take > 0 then
                    t.reserve = t.reserve + take
                    self.nutrients = self.nutrients - take
                end
            end
            t.reach = Q[n.quality].power
            t.power = t.reach * (n.ringed and D.RING.damage or 1)
            if t.boost then
                t.boost = t.boost - dt
                if t.boost <= 0 then t.boost = nil end
            end
            self:fire(n, t, d, dt)
        end
    end
end

-- What a tower is short of: nil (fine), "starved" (slow) or "dormant" (silent).
function Game:hunger(t)
    local d = D.TOWER[t.kind]
    if t.kind == "relay" then return t.node.conn and nil or "dormant" end
    local need = d.shot or d.drain * 0.5
    if t.reserve < need then return "dormant" end
    if not t.node.conn or t.reserve < d.reserve * 0.3 then return "starved" end
end

-- The enemies a tower could shoot, nearest the Heart first.
function Game:targets(n, range)
    local list = {}
    for _, e in ipairs(self.enemies) do
        if not e.dead and dist(e, n) <= range then list[#list + 1] = e end
    end
    table.sort(list, function(a, b) return (a.togo or 0) < (b.togo or 0) end)
    return list
end

function Game:fire(n, t, d, dt)
    local hunger = self:hunger(t)
    t.hunger = hunger
    if t.kind == "relay" then return end
    if hunger == "dormant" then return end
    local power = t.power or 1
    local boost = t.boost and D.PULSE.rate or 1
    if t.boost then power = power * D.PULSE.damage end
    if t.kind == "mane" then
        -- Heal what is chewed and regrow what is cut, within reach. It only
        -- drinks while it has something to do.
        local busy = false
        local deg = self:degree(n)
        for _, l in ipairs(self.links) do
            local dd = segDist(n.x, n.z, l.a.x, l.a.z, l.b.x, l.b.z)
            if dd <= d.range then
                if l.state == "alive" and l.hp < D.LINK.hp then
                    l.hp = min(D.LINK.hp, l.hp + d.heal * power * boost * dt)
                    busy = true
                elseif l.state == "cut" and not l.salted then
                    l.regrow = l.regrow + d.regrow * (1 + 0.5 * deg) * power * boost * dt
                    busy = true
                end
            end
        end
        if busy then
            t.reserve = max(0, t.reserve - d.drain * dt)
            t.busy = (t.busy or 0) + dt
        end
        return
    end
    t.cool = t.cool - dt * (hunger == "starved" and 0.5 or 1) * boost
    if t.cool > 0 then return end
    local list = self:targets(n, d.range * (t.reach or 1))
    if not list[1] then return end
    t.cool = d.every
    t.reserve = t.reserve - d.shot
    t.squash = 1
    if t.kind == "puffer" then
        local puffs = max(1, min(4, self:degree(n)))
        for k = 1, puffs do
            local e = list[(k - 1) % #list + 1]
            self.shots[#self.shots + 1] = { kind = "spore", x0 = n.x, y0 = n.y + 9, z0 = n.z,
                tx = e.x, tz = e.z, t = 0, flight = 0.45 + 0.05 * k, damage = d.damage * power, splash = d.splash }
        end
    elseif t.kind == "needle" then
        local e = list[1]
        local deadEnd = self:degree(n) == 1
        local dmg = d.damage * power * (deadEnd and d.deadEnd or 1)
        self:hurt(e, dmg, true)
        self.shots[#self.shots + 1] = { kind = "needle", x0 = n.x, y0 = n.y + 12, z0 = n.z,
            x1 = e.x, y1 = e.y + 3, z1 = e.z, t = 0, flight = 0.12, big = deadEnd }
    end
end

function Game:updateMats(dt)
    local d = D.TOWER.mat
    for k = #self.mats, 1, -1 do
        local m = self.mats[k]
        -- A mat touching a link feeds on it and does not wither.
        m.fed = false
        for _, l in ipairs(self.links) do
            if alive(l) and segDist(m.x, m.z, l.a.x, l.a.z, l.b.x, l.b.z) <= d.feed then m.fed = true break end
        end
        if not m.fed then m.life = m.life - dt end
        if m.life <= 0 then table.remove(self.mats, k) end
    end
end

function Game:onMat(e)
    for _, m in ipairs(self.mats) do
        if abs(e.x - m.x) < 9 and abs(e.z - m.z) < 9 then return m end
    end
end

function Game:updateShots(dt)
    for k = #self.shots, 1, -1 do
        local s = self.shots[k]
        s.t = s.t + dt
        if s.t >= s.flight then
            if s.kind == "spore" then
                for _, e in ipairs(self.enemies) do
                    if not e.dead and (e.x - s.tx) ^ 2 + (e.z - s.tz) ^ 2 <= s.splash ^ 2 then self:hurt(e, s.damage) end
                end
                self.fx[#self.fx + 1] = { cloud = true, x = s.tx, y = 0, z = s.tz, r = s.splash, life = 0.4, max = 0.4 }
            end
            table.remove(self.shots, k)
        end
    end
end

function Game:updateCorpses(dt)
    for k = #self.corpses, 1, -1 do
        local c = self.corpses[k]
        if c.carried then
            local a = c.carried
            if a.dead then
                c.carried = nil
            else
                c.x, c.z, c.h = a.x - math.cos(a.h) * 6, a.z - math.sin(a.h) * 6, a.h
            end
        elseif c.absorb then
            -- Being drunk: the value goes over a second and a half, and you see it go.
            local take = min(c.value, c.full * dt / 1.5)
            c.value = c.value - take
            self.nutrients = self.nutrients + take
            self.stats.drunk = self.stats.drunk + take
            if random() < dt * 20 then
                self.fx[#self.fx + 1] = { glow = true, x = c.x, y = 2, z = c.z, tx = c.ax, tz = c.az, t = 0, life = 0.5, max = 0.5 }
            end
            if c.value <= 0.01 then table.remove(self.corpses, k) end
        else
            c.life = c.life - dt
            -- Anything within reach of a fed link is drunk.
            for _, l in ipairs(self.links) do
                if alive(l) and l.a.conn then
                    local dd, _, qx, qz = segDist(c.x, c.z, l.a.x, l.a.z, l.b.x, l.b.z)
                    if dd <= D.LINK.absorb then
                        c.absorb, c.full, c.ax, c.az = true, c.value, qx, qz
                        self:say("+" .. floor(c.value + 0.5), c.x, 8, c.z, "l")
                        break
                    end
                end
            end
            if not c.absorb and c.life <= 0 then table.remove(self.corpses, k) end
        end
    end
end

function Game:updateFx(dt)
    for k = #self.fx, 1, -1 do
        local p = self.fx[k]
        p.life = p.life - dt
        if p.glow then
            p.t = p.t + dt
        elseif not p.cloud then
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

-- Living links within `r` of an enemy, nearest first.
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

local function toward(e, tx, tz, speed, dt)
    local dx, dz = tx - e.x, tz - e.z
    local d = sqrt(dx * dx + dz * dz)
    if d < 0.001 then return true, 0 end
    e.h = math.atan2(dz, dx)
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
        if nc then e.tc, e.tr = nc, nr end
    end
end

function Game:reachHeart(e)
    local d = D.ENEMIES[e.kind]
    self.heartHp = self.heartHp - d.heart
    self.events.heart = true
    e.dead = true
    if e.carry then
        -- Carried off underground: those nutrients are gone.
        unlist(self.corpses, e.carry)
        self.stats.stolen = self.stats.stolen + 1
    end
    self:burst(self.heart.x, 10, self.heart.z, 6, { "g", "m" }, 20)
end

function Game:move(e, dt)
    local d = D.ENEMIES[e.kind]
    e.flash = max(0, e.flash - dt)
    e.anim = e.anim + dt
    local mat = self:onMat(e)
    local slow = mat and D.TOWER.mat.slow or 1
    if self.rings[1] and self:ringed(e.x, e.z) then slow = slow * D.RING.slow end

    if e.kind == "brine" and e.slide then
        return self:slide(e, d, dt)
    end

    -- Stopped to chew a link it walked into.
    if e.state == "chew" then
        local l = e.chewing
        if l.state ~= "alive" then
            e.state = "walk"
        else
            l.hp = l.hp - d.chew * dt
            e.chewT = e.chewT - dt
            if e.chewT <= 0 then e.state = "walk" end
            return
        end
    end

    if e.kind == "mite" then return self:mite(e, d, slow, dt) end

    if e.kind == "pillbug" then
        if mat and e.rolling then
            -- The mat catches the roll: it uncurls, stuck, and is soft again.
            e.rolling, e.walked, e.stuck = false, 0, 1.0
            self:burst(e.x, 2, e.z, 6, { "l", "c" }, 14)
        end
        if e.stuck then
            e.stuck = e.stuck - dt
            if e.stuck <= 0 then e.stuck = nil end
            return
        end
        e.walked = e.walked + dt
        if e.rolling then
            if e.walked >= d.rollFor then e.rolling, e.walked = false, 0 end
            -- Rolling crushes any link it crosses, outright.
            local l = self:linkNear(e, 4)
            if l then self:cut(l) end
            if self:walk(e, d.rollSpeed * slow, dt) then self:reachHeart(e) end
            return
        elseif e.walked >= d.walkFor and not mat then
            e.rolling, e.walked = true, 0
        end
    end

    if e.kind == "brine" then
        local l = self:linkNear(e, 4)
        if l then return self:attach(e, l) end
    elseif d.chew and d.chewFor then
        local l = self:linkNear(e, 3.5)
        if l and not l.bitten[e] then
            l.bitten[e] = true
            e.state, e.chewing, e.chewT = "chew", l, d.chewFor
            return
        end
    end

    -- Ants pick up whatever is lying in their way.
    if e.kind == "ant" and not e.carry then
        for _, c in ipairs(self.corpses) do
            if not c.carried and not c.absorb and (c.x - e.x) ^ 2 + (c.z - e.z) ^ 2 < 36 then
                c.carried, e.carry = e, c
                break
            end
        end
    end

    if self:walk(e, d.speed * slow, dt) then self:reachHeart(e) end
end

-- Mites leave the trail for the nearest link they can smell, gnaw it through,
-- and go back to the trail.
function Game:mite(e, d, slow, dt)
    if e.gnaw and e.gnaw.state ~= "alive" then e.gnaw = nil end
    if not e.gnaw and not e.full then
        local l = self:linkNear(e, d.sniff)
        if l then
            local _, t = segDist(e.x, e.z, l.a.x, l.a.z, l.b.x, l.b.z)
            e.gnaw, e.gt = l, max(0.1, min(0.9, t + (random() - 0.5) * 0.3))
        end
    end
    if e.gnaw then
        local l = e.gnaw
        local tx, tz = l.a.x + (l.b.x - l.a.x) * e.gt, l.a.z + (l.b.z - l.a.z) * e.gt
        if toward(e, tx, tz, d.speed * slow, dt) then
            l.hp = l.hp - d.chew * dt
            e.gnawed = (e.gnawed or 0) + dt
            if e.gnawed > 6 then e.full, e.gnaw = true, nil end -- had enough; back to the march
        end
        return
    end
    -- Back to the trail tile it left, then on.
    if self:walk(e, d.speed * slow, dt) then self:reachHeart(e) end
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
end

function Game:slide(e, d, dt)
    local l = e.slide
    if l.state ~= "alive" then
        -- The thread it ran on is gone: it falls into the soil and is spent.
        e.dead = true
        self:burst(e.x, 2, e.z, 10, { "w", "s" }, 20)
        self:say("FIZZLED", e.x, 8, e.z, "w")
        return
    end
    e.st = e.st + d.slide * dt / max(1, l.len)
    local f, t = e.from, e.to
    e.x, e.z = f.x + (t.x - f.x) * e.st, f.z + (t.z - f.z) * e.st
    e.y = (f.y + (t.y - f.y) * e.st) + 1
    e.h = math.atan2(t.z - f.z, t.x - f.x)
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

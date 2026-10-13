-- Every number the prototype is tuned by, in one place.
--
-- The design doc says it plainly: all numbers are placeholders to tune in
-- playtesting. So they are rows, not code. A new fruiting body is a row in
-- TOWERS and a branch in src/game.lua's `fire`; a new enemy is a row in
-- ENEMIES, a model in src/models.lua and, if it does something to the network
-- nothing else does, a branch in src/game.lua's `move`; a new wave is a row in
-- WAVES.

local D = {}

D.START_NUTRIENTS = 110
D.HEART_HP = 20
D.INCOME = 2.2         -- per second, while a wave is on: the sprout's sugar
D.WAVE_BONUS = 20      -- paid when a wave is cleared, plus 4 a wave
D.UPKEEP = 0.04        -- per living link per second, while a wave is on

-- Hyphae.
D.LINK = {
    reach = 80,        -- the longest link you can grow, in room units (a tile is 16); the
                       -- loneliest pocket, a leaf by the far edge, is 64 from its nearest

    hp = 40,
    cap = 3,           -- nutrients a second a thin link carries
    grow = 1.2,        -- seconds a new link takes to reach the far end
    cost = function(len) return math.floor(6 + len * 0.32 + 0.5) end,
    prune = 0.5,       -- refunded on pruning a living link
    repair = 0.4,      -- of the cost, to regrow a cut one by hand
    regrow = 3,        -- seconds a hand repair takes
    absorb = 14,       -- how near a link a corpse has to lie to be drunk
}

-- A loop of four or more fed nodes closes a Fairy Ring: the ground inside it is
-- the network's. Towers in it hit harder and enemies in it wade.
D.RING = { nodes = 4, damage = 1.25, slow = 0.7 }

-- The Spore Pulse: a surge sent down the path from the Heart to a node,
-- overcharging every tower on the way for a few seconds.
D.PULSE = { cooldown = 45, duration = 6, rate = 2, damage = 1.5 }

-- Fruiting bodies. `reserve` is what a tower holds; a cut runs it on that, a
-- connected one refills it from the bank at up to its path's flow cap.
D.TOWERS = {
    { id = "puffer", name = "SPORE PUFFER", cost = 30, key = "2",
        range = 46, every = 1.3, damage = 6, splash = 12, shot = 0.5, reserve = 8,
        blurb = "LOBS SPORE CLOUDS AT GROUPS. +1 PUFF PER LINK" },
    { id = "needle", name = "ENOKI NEEDLE", cost = 45, key = "3",
        range = 100, every = 1.8, damage = 26, shot = 1.5, reserve = 9, deadEnd = 1.8,
        blurb = "LONG RANGE, PIERCES ARMOR. X1.8 ON A DEAD END" },
    { id = "mat", name = "SLIME MAT", cost = 18, key = "4", onTrail = true,
        slow = 0.45, life = 35, feed = 12,
        blurb = "LAID ON THE TRAIL. SLOWS, STOPS ROLLS. FED BY LINKS" },
    { id = "mane", name = "LION'S MANE", cost = 40, key = "5",
        range = 40, heal = 5, regrow = 0.1, drain = 0.3, reserve = 6,
        blurb = "HEALS LINKS, REGROWS CUT ONES. FASTER PER LINK" },
    { id = "relay", name = "RELAY", cost = 30, key = "6",
        range = 44,
        blurb = "NO ATTACK. DOUBLES FLOW ON LINKS IN REACH" },
}
D.TOWER = {}
for _, t in ipairs(D.TOWERS) do D.TOWER[t.id] = t end
D.SELL = 0.6

-- Enemies. `chew` is damage a second to a link it stops on; `heart` is what it
-- does to the sprout if it gets there; `corpse` is what its body is worth.
D.ENEMIES = {
    ant = { name = "WORKER ANT", hp = 16, speed = 20, armor = 0, chew = 5, chewFor = 1.0,
        heart = 1, corpse = 4, blurb = "CHEWS LINKS ACROSS THE TRAIL. CARRIES OFF CORPSES" },
    pillbug = { name = "PILLBUG", hp = 70, speed = 12, armor = 3, rolledArmor = 10, chew = 4, chewFor = 1.5,
        rollSpeed = 36, walkFor = 3.5, rollFor = 2.6, heart = 3, corpse = 10,
        blurb = "ROLLS AND CRUSHES ANY LINK IT CROSSES. A MAT STOPS IT" },
    mite = { name = "MITE SWARM", hp = 4, speed = 18, armor = 0, chew = 1.6, swarm = 10, sniff = 34,
        heart = 0.34, corpse = 0.6, blurb = "MANY TINY BITES. GNAWS THE NEAREST LINK" },
    brine = { name = "BRINE DROP", hp = 30, speed = 13, armor = 0, slide = 22, heart = 4, corpse = 0,
        blurb = "SLIDES DOWN YOUR HYPHAE, STERILISING. PRUNE AHEAD OF IT" },
}
D.ENEMY_ORDER = { "ant", "pillbug", "mite", "brine" }

-- Waves: { kind, how many, seconds between, gate (1 top, 2 bottom), start }.
-- A mite row counts swarms, not mites.
D.WAVES = {
    { { "ant", 6, 1.6, 1, 0 } },
    { { "ant", 6, 1.4, 1, 0 }, { "ant", 6, 1.4, 2, 4 } },
    { { "ant", 8, 1.2, 2, 0 }, { "pillbug", 1, 1, 1, 6 } },
    { { "mite", 1, 1, 1, 0 }, { "ant", 6, 1.2, 2, 3 }, { "mite", 1, 1, 2, 9 } },
    { { "ant", 10, 1.1, 1, 0 }, { "pillbug", 3, 5, 2, 2 } },
    { { "ant", 8, 1.2, 1, 0 }, { "brine", 1, 1, 2, 6 }, { "ant", 6, 1.2, 2, 10 } },
    { { "mite", 3, 7, 1, 0 }, { "pillbug", 2, 6, 2, 4 }, { "ant", 8, 1, 2, 12 } },
    { { "ant", 12, 1, 2, 0 }, { "brine", 2, 8, 1, 3 }, { "pillbug", 2, 4, 1, 12 } },
    { { "pillbug", 4, 4, 2, 0 }, { "mite", 3, 6, 1, 2 }, { "brine", 2, 8, 2, 10 }, { "ant", 10, 0.9, 1, 14 } },
    { { "ant", 20, 0.8, 1, 0 }, { "pillbug", 4, 4, 2, 2 }, { "mite", 3, 5, 2, 8 }, { "brine", 3, 6, 1, 12 },
        { "ant", 14, 0.8, 2, 18 } },
}
D.HP_GROWTH = 0.1 -- each wave's enemies are this much tougher than the last's

return D

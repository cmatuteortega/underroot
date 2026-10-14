-- Every number the game is tuned by, in one place.
--
-- The design doc says it plainly: all numbers are placeholders to tune in
-- playtesting. So they are rows, not code. A new fruiting body is a row in
-- TOWERS, a model in src/models.lua and a branch in src/game.lua's `fire`; a
-- new enemy is a row in ENEMIES, a model and, if it does something to the
-- network nothing else does, a branch in src/game.lua's `move`; a new wave is
-- a row in a level's waves, and a new level a row in LEVELS with a map in
-- src/world.lua.

local D = {}

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
-- connected one refills it from the bank at up to its path's flow cap. `hp` is
-- what a slug has to eat through. `unlock` is the wave that has to be cleared
-- before the species can be grown.
--
-- Every tower forks twice (the doc's upgrade branches), and each branch has two
-- tiers. A tier row only names what it changes: a stat is read off the highest
-- tier that sets it, then the tower's base row (see Game:stat).
D.TOWERS = {
    { id = "puffer", name = "SPORE PUFFER", cost = 30, key = "2", hp = 30, air = true,
        range = 46, every = 1.3, damage = 6, splash = 12, shot = 0.5, reserve = 8,
        blurb = "LOBS SPORE CLOUDS AT GROUPS. +1 PUFF PER LINK",
        up = {
            { { name = "LINGERING TOXIN", cost = 35, linger = 2, toxin = 4, blurb = "CLOUDS HANG FOR 2S AND POISON" },
              { name = "MIASMA", cost = 65, linger = 3.5, toxin = 8, splash = 16, blurb = "BIGGER, LONGER, NASTIER CLOUDS" } },
            { { name = "RAPID FIRE", cost = 35, every = 0.8, blurb = "PUFFS NEARLY TWICE AS OFTEN" },
              { name = "SPORE GATLING", cost = 65, every = 0.55, extraPuff = 1, blurb = "FASTER STILL, AND ONE MORE PUFF" } },
        } },
    { id = "needle", name = "ENOKI NEEDLE", cost = 45, key = "3", hp = 25, air = true,
        range = 100, every = 1.8, damage = 26, shot = 1.5, reserve = 9, deadEnd = 1.8,
        blurb = "LONG RANGE, PIERCES ARMOR. X1.8 ON A DEAD END",
        up = {
            { { name = "SKEWER", cost = 40, pierce = 2, damage = 32, blurb = "RUNS THROUGH TWO IN A LINE" },
              { name = "LANCE", cost = 75, pierce = 3, damage = 44, range = 118, blurb = "THREE IN A LINE, FURTHER, HARDER" } },
            { { name = "MARK TARGET", cost = 40, mark = 1.25, markFor = 4, blurb = "MARKED PREY TAKES +25% FROM ALL" },
              { name = "HUNTER'S MARK", cost = 75, mark = 1.45, markFor = 5, every = 1.4, markSplash = 16,
                blurb = "+45%, FASTER, MARKS THE PACK AROUND IT" } },
        } },
    { id = "mat", name = "SLIME MAT", cost = 18, key = "4", onTrail = true,
        slow = 0.45, life = 35, feed = 12,
        blurb = "LAID ON THE TRAIL. SLOWS, STOPS ROLLS. FED BY LINKS",
        up = {
            { { name = "GLUE", cost = 20, slow = 0.3, life = 50, blurb = "STICKIER, LASTS LONGER" },
              { name = "AMBER", cost = 40, slow = 0.18, life = 70, blurb = "ALMOST SET SOLID" } },
            { { name = "DIGEST", cost = 25, digest = 5, blurb = "DISSOLVES WHAT STANDS ON IT" },
              { name = "STOMACH", cost = 45, digest = 11, slow = 0.38, blurb = "DISSOLVES FASTER, HOLDS HARDER" } },
        } },
    { id = "mane", name = "LION'S MANE", cost = 40, key = "5", hp = 35,
        range = 40, heal = 5, regrow = 0.1, drain = 0.3, reserve = 6,
        blurb = "HEALS LINKS, REGROWS CUT ONES. FASTER PER LINK",
        up = {
            { { name = "FAST REGROWTH", cost = 35, heal = 8, regrow = 0.17, range = 46, blurb = "HEALS AND REGROWS 70% FASTER" },
              { name = "OLD GROWTH", cost = 60, heal = 13, regrow = 0.27, range = 56, blurb = "FASTER STILL, WIDER" } },
            { { name = "PURGE", cost = 35, purge = true, towerHeal = 4, blurb = "CLEARS WEBS, HEALS FRUITING BODIES" },
              { name = "SANCTUARY", cost = 60, purge = true, towerHeal = 9, webProof = true, range = 50,
                blurb = "TOWERS IN REACH CANNOT BE WEBBED" } },
        } },
    { id = "relay", name = "RELAY", cost = 30, key = "6", hp = 30,
        range = 44, capMul = 2,
        blurb = "NO ATTACK. DOUBLES FLOW ON LINKS IN REACH",
        up = {
            { { name = "BATTERY", cost = 30, battery = 1.7, blurb = "TOWERS IN REACH HOLD 70% MORE RESERVE" },
              { name = "DEEP BATTERY", cost = 55, battery = 2.5, range = 54, blurb = "2.5X RESERVE, WIDER" } },
            { { name = "AMPLIFIER", cost = 40, amp = 1.15, capMul = 2.5, blurb = "TOWERS IN REACH +15% DAMAGE" },
              { name = "RESONATOR", cost = 70, amp = 1.3, capMul = 3, range = 54, blurb = "+30% DAMAGE, TRIPLE FLOW" } },
        } },
    { id = "inky", name = "INKY CAP", cost = 35, key = "7", hp = 30, unlock = 2,
        range = 36, feast = 2, inkEvery = 6, inkLife = 5, inkR = 7, inkSlow = 0.7,
        blurb = "DRINKS BODIES IN REACH FOR X2. INK BLINDS AND SLOWS",
        up = {
            { { name = "WIDE REACH", cost = 30, range = 50, feast = 2.3, blurb = "DRINKS FURTHER OUT, X2.3" },
              { name = "SPORE SHADOW", cost = 55, range = 64, feast = 2.7, blurb = "FURTHER STILL, X2.7" } },
            { { name = "BIG INK", cost = 30, inkEvery = 4, inkR = 10, inkSlow = 0.55, blurb = "BIGGER POOLS, MORE OFTEN" },
              { name = "INK FLOOD", cost = 55, inkEvery = 2.5, inkR = 13, inkSlow = 0.42, inkLife = 7, blurb = "THE TRAIL RUNS BLACK" } },
        } },
    { id = "shelf", name = "SHELF FUNGUS", cost = 35, key = "8", onTrail = true, unlock = 4,
        hp = 140, shield = 30, shieldMul = 0.3, touch = 24,
        blurb = "BLOCKS THE TRAIL: THEY MUST CHEW THROUGH. SHIELDS LINKS",
        up = {
            { { name = "THICK ARMOR", cost = 35, hp = 260, regen = 2, blurb = "TWICE THE WOOD, AND IT HEALS" },
              { name = "IRONWOOD", cost = 60, hp = 430, regen = 4, blurb = "LIKE CHEWING A NAIL" } },
            { { name = "THORNY", cost = 35, thorns = 5, blurb = "BITES BACK AT WHATEVER CHEWS IT" },
              { name = "BRAMBLE", cost = 60, thorns = 12, hp = 200, blurb = "BITES BACK HARD" } },
        } },
    { id = "mortar", name = "PUFFBALL MORTAR", cost = 70, key = "9", hp = 40, unlock = 5,
        range = 92, minRange = 22, every = 3.6, damage = 38, splash = 20, shot = 3, reserve = 10, thirst = 5,
        blurb = "HUGE SLOW BLASTS, MIN RANGE. DRINKS X3: NEEDS A THICK LINK",
        up = {
            { { name = "CLUSTER BLAST", cost = 55, cluster = 3, clusterDamage = 14, blurb = "THREE BOMBLETS SCATTER AFTER" },
              { name = "CARPET", cost = 90, cluster = 5, clusterDamage = 20, damage = 46, blurb = "FIVE BOMBLETS, BIGGER BLAST" } },
            { { name = "SMOKE", cost = 50, smoke = 1.3, blurb = "STUNNED IN THE SMOKE, THEY DROP WHAT THEY CARRY" },
              { name = "BLACKOUT", cost = 85, smoke = 2.3, splash = 27, blurb = "LONGER, WIDER SMOKE" } },
        } },
    { id = "cordyceps", name = "CORDYCEPS BLOOM", cost = 60, key = "0", hp = 30, unlock = 7,
        range = 54, every = 7, shot = 3, reserve = 6, infect = 4, maxHp = 400, bite = 14,
        blurb = "INFECTS ONE: IT TURNS ON ITS OWN, THEN DIES. RICH POCKET +50%",
        up = {
            { { name = "LONGER CONTROL", cost = 45, infect = 6.5, maxHp = 700, blurb = "LONGER HOLD, BIGGER HOSTS" },
              { name = "PUPPETEER", cost = 80, infect = 9, maxHp = 1100, every = 5.5, blurb = "LONGER, BIGGER, MORE OFTEN" } },
            { { name = "SPREADS ON DEATH", cost = 45, spread = 1, blurb = "THE HOST'S SPORES TAKE THE NEXT ONE" },
              { name = "PLAGUE", cost = 80, spread = 2, bite = 24, blurb = "SPREADS TWICE, HOSTS BITE HARDER" } },
        } },
    { id = "stink", name = "STINKHORN", cost = 40, key = "T", hp = 35, unlock = 3,
        range = 28, reek = 0.75, stumble = 0.2, trip = 0.5, bait = 70, hold = 6, drain = 0.35, reserve = 7,
        blurb = "ITS STENCH SLOWS AND TRIPS. FLIES COME TO IT AS BAIT",
        up = {
            { { name = "WIDER STENCH", cost = 35, range = 36, reek = 0.68, bait = 90, blurb = "WIDER, AND THICKER" },
              { name = "CARRION REEK", cost = 60, range = 44, reek = 0.6, rot = 3, hold = 9, blurb = "SO FOUL IT ROTS THEM, AND HOLDS FLIES LONGER" } },
            { { name = "PANIC", cost = 40, panic = 1.2, panicEvery = 8, blurb = "NOW AND THEN THEY TURN AND FLEE" },
              { name = "TERROR", cost = 70, panic = 2, panicEvery = 6, range = 34, blurb = "THEY FLEE LONGER, MORE OFTEN" } },
        } },
    { id = "lamp", name = "GHOST LAMP", cost = 35, key = "G", hp = 80, unlock = 6,
        range = 30, perFlow = 5, hold = 5, drain = 0.25, reserve = 6,
        blurb = "A GLOWING DECOY: THEY GO FOR IT FIRST. BRIGHTER WITH FLOW",
        up = {
            { { name = "LONGER GLOW", cost = 30, hp = 140, hold = 7, range = 36, blurb = "TOUGHER, AND HOLDS THEM LONGER" },
              { name = "WILL-O'-WISP", cost = 55, hp = 220, hold = 9, range = 42, regen = 4, blurb = "TOUGHER STILL, AND HEALS" } },
            { { name = "FLARE", cost = 35, blast = 40, blastR = 22, blurb = "BURSTS WHEN IT IS DESTROYED" },
              { name = "STARBURST", cost = 65, blast = 85, blastR = 30, blastStun = 1.5, blurb = "A BIGGER BURST, AND IT STUNS" } },
        } },
    -- The late unlock. One per run (once grown, never again), slow to grow,
    -- and stronger for every fed node in the network.
    { id = "giant", name = "HUMONGOUS FUNGUS", cost = 150, key = "H", hp = 200, unlock = 9, unique = true,
        range = 40, rangePerNode = 1.5, maxRange = 80, every = 3.2, damage = 8, perNode = 2.5, shot = 3, reserve = 14,
        growTime = 8,
        blurb = "ONE PER RUN, SLOW TO GROW. QUAKES HARDER FOR EVERY FED NODE",
        up = {
            { { name = "SPREADING", cost = 70, perNode = 3.5, rangePerNode = 2, blurb = "MORE PER NODE, REACHES FURTHER" },
              { name = "ARMILLARIA", cost = 110, perNode = 5, rangePerNode = 2.4, every = 2.6, maxRange = 96,
                blurb = "THE BIGGEST LIVING THING THERE IS" } },
            { { name = "HONEY ROOT", cost = 70, stick = 0.5, stickFor = 1.5, mend = 8, blurb = "QUAKES STICK THEM AND MEND LINKS" },
              { name = "ANCIENT", cost = 110, stick = 0.35, stickFor = 2, mend = 16, quake = 0.6,
                blurb = "STICKIER, MENDS MORE, AND STUNS" } },
        } },
}
D.TOWER = {}
for _, t in ipairs(D.TOWERS) do D.TOWER[t.id] = t end
D.SELL = 0.6

-- Enemies. `chew` is damage a second to a link it stops on; `bite` is damage a
-- second to a shelf in its way; `heart` is what it does to the sprout if it gets
-- there; `corpse` is what its body is worth. `size` scales its shadow and where
-- its health bar floats.
D.ENEMIES = {
    ant = { name = "WORKER ANT", hp = 16, speed = 20, armor = 0, chew = 5, chewFor = 1.0, bite = 5,
        heart = 1, corpse = 4, blurb = "CHEWS LINKS ACROSS THE TRAIL. CARRIES OFF CORPSES" },
    pillbug = { name = "PILLBUG", hp = 70, speed = 12, armor = 3, rolledArmor = 10, chew = 4, chewFor = 1.5, bite = 4,
        rollSpeed = 36, walkFor = 3.5, rollFor = 2.6, heart = 3, corpse = 10,
        blurb = "ROLLS AND CRUSHES ANY LINK IT CROSSES. A MAT STOPS IT" },
    mite = { name = "MITE SWARM", hp = 4, speed = 18, armor = 0, chew = 1.6, swarm = 10, sniff = 34, bite = 1.6,
        heart = 0.34, corpse = 0.6, blurb = "MANY TINY BITES. GNAWS THE NEAREST LINK" },
    brine = { name = "BRINE DROP", hp = 30, speed = 13, armor = 0, slide = 22, heart = 4, corpse = 0, bite = 10,
        blurb = "SLIDES DOWN YOUR HYPHAE, STERILISING. PRUNE AHEAD OF IT" },
    gnat = { name = "FUNGUS GNAT", hp = 12, speed = 17, armor = 0, fly = true, heart = 1, corpse = 1,
        blurb = "FLIES STRAIGHT AT THE SPROUT. ONLY PUFFERS AND NEEDLES REACH IT" },
    slug = { name = "SLUG", hp = 240, speed = 6, armor = 0, noSlow = true, eat = 8, eatR = 15, bite = 8,
        heart = 4, corpse = 22, blurb = "SLOW, HUGE, CANNOT BE SLOWED. EATS FRUITING BODIES IT PASSES" },
    spider = { name = "WOLF SPIDER", hp = 55, speed = 30, armor = 1, web = 5, webR = 56, webCd = 9, bite = 6,
        heart = 2, corpse = 8, blurb = "HUNTS YOUR DEADLIEST TOWER AND WEBS IT SHUT" },
    knight = { name = "BEETLE KNIGHT", hp = 150, speed = 9, armor = 9, chew = 6, chewFor = 2, bite = 6,
        heart = 3, corpse = 14, blurb = "HEAVY ARMOR SHRUGS OFF CHEAP HITS. NEEDLES PIERCE IT" },

    moth = { name = "NIGHT MOTH", hp = 22, speed = 15, armor = 0, fly = true, moth = true, nibble = 4, bite = 4,
        heart = 1, corpse = 3, blurb = "COMES OUT AT NIGHT. FLIES TO THE BRIGHTEST LIGHT AND EATS IT" },

    -- Bosses: the big bugs. They do not get tougher wave by wave; they are
    -- tuned for the wave they come on.
    queen = { name = "QUEEN ANT", boss = true, hp = 750, speed = 7, armor = 2, gnaw = 14, gnawR = 8,
        brood = 3, broodEvery = 6, bite = 25, heart = 10, corpse = 40, size = 2.6,
        blurb = "LAYS WORKERS AS SHE WALKS AND GNAWS EVERY THREAD SHE PASSES" },
    stag = { name = "STAG BEETLE", boss = true, hp = 1250, speed = 8, armor = 6, bite = 60,
        chargeEvery = 9, chargeFor = 1.5, chargeSpeed = 26, shear = 11, stun = 3, stunR = 18,
        heart = 12, corpse = 70, size = 3,
        blurb = "CHARGES. ITS JAWS SHEAR LINKS AND STUN THE TOWERS IT PASSES" },
    dung = { name = "DUNG BEETLE", boss = true, hp = 1500, speed = 6.5, armor = 3, bite = 999,
        ball = 900, ballR = 9, ballAhead = 13, ballHeart = 20, ballCorpse = 60, rage = 1.5,
        heart = 12, corpse = 50, size = 3,
        blurb = "ITS BALL SOAKS EVERY HIT AND FLATTENS ALL IT ROLLS OVER. BREAK IT" },
    -- Under water (a flooded trail tile) it cannot be hurt or seen. Every few
    -- seconds it lunges at the nearest fruiting body it can reach that is not
    -- on high ground and drags it under; a fed Lion's Mane in reach halves its grip.
    waterbug = { name = "GIANT WATER BUG", boss = true, hp = 1500, speed = 8, armor = 4, bite = 40,
        grabEvery = 7, grabR = 44, lunge = 34, hold = 2.6, drag = 30, heart = 12, corpse = 60, size = 3,
        blurb = "LURKS UNDER THE FLOODED LANE. SURFACES TO DRAG A TOWER UNDER" },
    -- A head and a train of segments, each its own enemy with its own HP. Each
    -- crushes the links it crosses; break one and the one behind leads.
    centipede = { name = "GIANT CENTIPEDE", boss = true, hp = 260, speed = 11, armor = 5, segments = 11, gap = 8.5,
        bite = 30, crushR = 4.5, heart = 6, corpse = 14, size = 2,
        blurb = "A TRAIN OF ARMORED SEGMENTS. EACH CUTS WHAT IT CROSSES. IT SPLITS WHERE BROKEN" },
    centseg = { name = "GIANT CENTIPEDE", boss = true, segment = true, hp = 220, speed = 11, armor = 5, bite = 20,
        crushR = 4.5, heart = 1.5, corpse = 8, size = 1.6 },
    -- Challenge mode's boss. Walking, it scalds the nearest tower behind it;
    -- `siege` tiles from the sprout it stops and sprays the sprout itself, and
    -- whatever stands in the way (a shelf, a tower) takes the spray instead.
    bombardier = { name = "BOMBARDIER BEETLE", boss = true, hp = 1600, speed = 9, armor = 4, bite = 50,
        sprayEvery = 6, sprayR = 44, scald = 30, siege = 3, siegeEvery = 2.5, heartSpray = 2, coverR = 7,
        heart = 12, corpse = 60, size = 2.6,
        blurb = "AT THE END OF THE TRAIL IT TURNS AND SPRAYS THE SPROUT. COVER IT" },
}
D.ENEMY_ORDER = { "ant", "pillbug", "mite", "gnat", "moth", "brine", "slug", "spider", "knight",
    "queen", "stag", "dung", "waterbug", "centipede", "bombardier" }

-- Weather, per wave: a wave row's `weather` names one of these, and the
-- forecast shows it before the wave starts. `flow` scales every link's flow
-- cap; `wash` is reserve a second rain takes off a tower on a low pocket (a
-- leaf, a lily pad); `clouds` is how much faster lingering clouds and ink wash
-- out; `wither` how much faster an unfed mat dries up; `lamp` and `range`
-- scale a Ghost Lamp's pull and every tower's reach; `pace` scales how fast
-- everything fires and moves, `grow` how fast links grow and regrow.
D.WEATHER = {
    rain = { name = "RAIN", flow = 1.5, wash = 0.3, clouds = 2,
        blurb = "FLOW +50%, BUT PUDDLES WASH LOW POCKETS AND CLOUDS AWAY" },
    drought = { name = "DROUGHT", flow = 0.7, wither = 2,
        blurb = "FLOW -30%: THIN LINKS STARVE FIRST. RELAYS MATTER" },
    night = { name = "NIGHT", lamp = 1.4, range = 1.15,
        blurb = "LAMPS AND THE GLOWING NETWORK REACH FURTHER. MOTHS COME OUT" },
    frost = { name = "FROST", pace = 0.8, grow = 0.6,
        blurb = "EVERYTHING SLOWS: GROWTH, FIRE AND ENEMIES ALIKE" },
}

-- Waves: { kind, how many, seconds between, gate, start }, gates counted down
-- the map's left edge from the top. A mite row counts swarms, not mites.
local CRACK = {
    { { "ant", 6, 1.6, 1, 0 } },
    { { "ant", 6, 1.4, 1, 0 }, { "ant", 6, 1.4, 2, 4 } },
    { { "ant", 8, 1.2, 2, 0 }, { "pillbug", 1, 1, 1, 6 } },
    { weather = "rain", { "gnat", 4, 1.5, 1, 0 }, { "ant", 8, 1.1, 2, 2 }, { "mite", 1, 1, 1, 8 } },
    { { "ant", 8, 1.2, 2, 0 }, { "queen", 1, 1, 1, 4 } },
    { { "ant", 8, 1.2, 1, 0 }, { "pillbug", 2, 5, 2, 2 }, { "brine", 1, 1, 2, 6 }, { "ant", 6, 1.2, 2, 10 } },
    { weather = "night", { "slug", 2, 10, 1, 0 }, { "mite", 2, 7, 2, 3 }, { "moth", 4, 2, 1, 4 }, { "ant", 10, 1, 1, 6 } },
    { { "spider", 3, 5, 2, 0 }, { "ant", 10, 1, 1, 2 }, { "pillbug", 2, 5, 1, 8 }, { "gnat", 5, 1.2, 2, 10 } },
    { weather = "rain", { "knight", 3, 4, 1, 0 }, { "brine", 2, 8, 2, 3 }, { "gnat", 6, 1, 1, 6 }, { "ant", 10, 0.9, 2, 8 } },
    { { "knight", 2, 6, 1, 0 }, { "stag", 1, 1, 2, 3 }, { "ant", 12, 1, 1, 6 } },
    { weather = "drought", { "slug", 3, 7, 2, 0 }, { "spider", 4, 4, 1, 2 }, { "mite", 3, 6, 2, 6 }, { "ant", 12, 0.9, 1, 10 } },
    { weather = "frost", { "knight", 5, 3, 1, 0 }, { "pillbug", 4, 4, 2, 0 }, { "gnat", 8, 0.8, 2, 4 }, { "brine", 2, 9, 1, 6 } },
    { weather = "night", { "spider", 5, 3, 2, 0 }, { "slug", 3, 6, 1, 2 }, { "mite", 4, 5, 1, 6 }, { "brine", 3, 7, 2, 8 },
        { "moth", 6, 1.5, 2, 3 }, { "ant", 16, 0.7, 2, 12 } },
    { { "knight", 6, 2.5, 2, 0 }, { "pillbug", 5, 3, 1, 0 }, { "gnat", 12, 0.6, 2, 4 }, { "spider", 5, 3, 1, 6 },
        { "ant", 20, 0.6, 1, 10 }, { "slug", 2, 8, 2, 12 } },
    { { "ant", 14, 0.8, 2, 0 }, { "dung", 1, 1, 1, 6 }, { "knight", 3, 5, 2, 10 }, { "spider", 3, 6, 1, 16 },
        { "gnat", 8, 1, 2, 20 } },
}

-- The Pond Edge: water and reeds. Both trails wade a flooded lane, where the
-- Giant Water Bug hides; stones are the high ground it cannot reach.
local POND = {
    { { "ant", 8, 1.4, 1, 0 }, { "ant", 6, 1.4, 2, 5 } },
    { weather = "rain", { "ant", 8, 1.2, 2, 0 }, { "pillbug", 2, 5, 1, 4 }, { "gnat", 3, 1.5, 1, 8 } },
    { { "ant", 10, 1.1, 1, 0 }, { "brine", 1, 1, 2, 4 }, { "mite", 1, 1, 2, 8 } },
    { weather = "night", { "moth", 5, 1.6, 1, 0 }, { "ant", 10, 1, 2, 2 }, { "spider", 2, 5, 1, 6 } },
    { weather = "rain", { "slug", 2, 8, 1, 0 }, { "brine", 2, 6, 2, 3 }, { "ant", 12, 0.9, 2, 6 } },
    { weather = "drought", { "knight", 2, 5, 1, 0 }, { "mite", 2, 6, 2, 2 }, { "pillbug", 3, 4, 2, 4 }, { "gnat", 5, 1.2, 1, 8 } },
    { weather = "night", { "moth", 8, 1.2, 2, 0 }, { "spider", 3, 4, 1, 3 }, { "ant", 12, 0.9, 1, 6 } },
    { { "ant", 10, 1, 2, 0 }, { "queen", 1, 1, 1, 3 }, { "gnat", 6, 1, 2, 10 } },
    { weather = "rain", { "brine", 3, 6, 1, 0 }, { "knight", 3, 5, 2, 2 }, { "slug", 2, 8, 1, 6 }, { "gnat", 8, 1, 2, 8 } },
    { weather = "frost", { "pillbug", 5, 3, 1, 0 }, { "knight", 4, 4, 2, 2 }, { "spider", 4, 4, 1, 6 }, { "mite", 3, 5, 2, 8 } },
    { weather = "night", { "moth", 10, 1, 1, 0 }, { "slug", 3, 6, 2, 2 }, { "ant", 20, 0.6, 1, 6 }, { "brine", 2, 8, 2, 8 } },
    { weather = "rain", { "ant", 14, 0.8, 2, 0 }, { "waterbug", 1, 1, 1, 4 }, { "knight", 3, 5, 2, 10 }, { "gnat", 8, 1, 1, 14 } },
}

-- The Lawn: open grass and three gates. Everything at once, then the
-- Giant Centipede.
local LAWN = {
    { { "ant", 6, 1.4, 1, 0 }, { "ant", 6, 1.4, 3, 3 } },
    { { "ant", 8, 1.2, 2, 0 }, { "pillbug", 2, 4, 3, 4 }, { "ant", 6, 1.2, 1, 6 } },
    { weather = "drought", { "mite", 2, 6, 1, 0 }, { "gnat", 4, 1.4, 3, 2 }, { "ant", 10, 1, 2, 4 } },
    { weather = "rain", { "slug", 2, 8, 2, 0 }, { "brine", 2, 6, 1, 2 }, { "ant", 10, 1, 3, 4 } },
    { { "ant", 12, 1, 3, 0 }, { "queen", 1, 1, 2, 4 }, { "spider", 2, 5, 1, 8 } },
    { weather = "frost", { "knight", 3, 4, 1, 0 }, { "pillbug", 3, 4, 3, 2 }, { "mite", 2, 6, 2, 6 }, { "gnat", 6, 1, 2, 8 } },
    { weather = "drought", { "spider", 4, 4, 2, 0 }, { "slug", 2, 8, 3, 2 }, { "ant", 14, 0.8, 1, 4 } },
    { { "knight", 4, 3, 3, 0 }, { "brine", 3, 6, 2, 2 }, { "gnat", 8, 0.9, 1, 4 }, { "ant", 12, 0.8, 2, 8 } },
    { weather = "night", { "moth", 8, 1.2, 1, 0 }, { "spider", 4, 4, 3, 2 }, { "mite", 3, 5, 2, 4 }, { "ant", 12, 0.8, 3, 8 } },
    { { "knight", 3, 5, 1, 0 }, { "stag", 1, 1, 2, 3 }, { "ant", 14, 0.8, 3, 6 } },
    { weather = "rain", { "slug", 3, 6, 1, 0 }, { "brine", 3, 6, 3, 2 }, { "pillbug", 5, 3, 2, 4 }, { "gnat", 10, 0.7, 1, 8 } },
    { weather = "drought", { "knight", 7, 2.5, 2, 0 }, { "spider", 5, 3, 1, 3 }, { "mite", 4, 4, 3, 6 }, { "ant", 18, 0.6, 2, 8 },
        { "pillbug", 3, 4, 3, 10 } },
    { weather = "frost", { "pillbug", 6, 2.5, 1, 0 }, { "slug", 4, 5, 3, 2 }, { "knight", 6, 3, 2, 4 }, { "gnat", 12, 0.6, 3, 6 } },
    { weather = "night", { "moth", 14, 0.7, 2, 0 }, { "spider", 7, 3, 1, 2 }, { "brine", 3, 6, 3, 4 }, { "ant", 24, 0.5, 1, 8 },
        { "knight", 4, 4, 3, 10 } },
    { { "ant", 18, 0.6, 3, 0 }, { "centipede", 1, 1, 2, 4 }, { "knight", 6, 3, 1, 8 }, { "gnat", 12, 0.7, 3, 12 },
        { "slug", 3, 6, 1, 16 } },
}

-- The levels, in the order they open: each is won to open the next. `map`
-- names a map in src/world.lua. `open` grows every species from wave one
-- (the player met them all on the Crack); `unlock` overrides that per
-- species. `growth` is how much tougher each wave's enemies are than the
-- last's, if not HP_GROWTH. The Crack stands in for the design doc's first five levels: it
-- has their three bosses.
D.LEVELS = {
    { id = "crack", name = "THE CRACK", map = "crack", waves = CRACK, start = 110, heart = 20,
        mutateAfter = { [3] = true, [5] = true, [8] = true, [10] = true, [12] = true },
        idea = "A SIDEWALK CRACK. LEARN THE NETWORK", boss = "QUEEN, STAG, DUNG BEETLE" },
    { id = "pond", name = "THE POND EDGE", map = "pond", waves = POND, start = 150, heart = 20, open = true, growth = 0.08,
        unlock = { giant = 4 },
        mutateAfter = { [2] = true, [4] = true, [7] = true, [9] = true },
        idea = "WATER AND REEDS. BUILD ON HIGH GROUND", boss = "GIANT WATER BUG" },
    { id = "lawn", name = "THE LAWN", map = "lawn", waves = LAWN, start = 140, heart = 20, open = true, growth = 0.2,
        unlock = { giant = 5 },
        mutateAfter = { [3] = true, [5] = true, [8] = true, [10] = true, [12] = true },
        idea = "OPEN GRASS, THREE GATES. EVERYTHING AT ONCE", boss = "GIANT CENTIPEDE" },
}
D.LEVEL = {}
for _, l in ipairs(D.LEVELS) do D.LEVEL[l.id] = l end

-- Challenge mode, open once the Lawn is won: any level with this wave added
-- at the end, and the Bombardier Beetle in it.
D.CHALLENGE = { weather = "night", { "bombardier", 1, 1, 1, 0 }, { "knight", 4, 3, 2, 3 }, { "moth", 8, 1, 2, 5 },
    { "spider", 4, 4, 1, 8 }, { "ant", 20, 0.6, 2, 10 } }

D.HP_GROWTH = 0.1 -- each wave's enemies are this much tougher than the last's (bosses aside)

-- Mutations: after the waves a level's `mutateAfter` names, the network picks
-- one of three at random.
D.MUTATIONS = {
    { id = "thick", name = "THICK HYPHAE", blurb = "LINKS HAVE +50% HP" },
    { id = "quick", name = "QUICK GROWTH", blurb = "LINKS GROW AND REGROW TWICE AS FAST" },
    { id = "cheap", name = "THRIFTY THREADS", blurb = "LINKS COST 25% LESS" },
    { id = "feast", name = "HUNGRY SOIL", blurb = "BODIES ARE WORTH 50% MORE" },
    { id = "sugar", name = "SWEET ROOTS", blurb = "+0.8 NUTRIENTS A SECOND IN A WAVE" },
    { id = "pulse", name = "QUICK PULSE", blurb = "SPORE PULSE COMES BACK 40% SOONER" },
    { id = "roots", name = "DEEP ROOTS", blurb = "THE SPROUT GROWS +5 HP AND HEALS" },
    { id = "store", name = "FAT RESERVES", blurb = "FRUITING BODIES HOLD 50% MORE" },
    { id = "rings", name = "OLD RINGS", blurb = "FAIRY RINGS +40% DAMAGE, SLOW HARDER" },
    { id = "reach", name = "LONG REACH", blurb = "LINKS REACH 25% FURTHER" },
}

return D

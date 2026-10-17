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
-- `blurb` is its one line on the toolbar; `role` and `about` are what the
-- info panel says of it, kept short enough to fit there.
--
-- Every tower forks twice (the doc's upgrade branches), and each branch has two
-- tiers. A tier row only names what it changes: a stat is read off the highest
-- tier that sets it, then the tower's base row (see Game:stat).
D.TOWERS = {
    { id = "puffer", name = "SPORE PUFFER", cost = 30, key = "2", hp = 30, air = true,
        range = 46, every = 1.3, damage = 6, splash = 12, shot = 0.5, reserve = 8,
        blurb = "LOBS SPORE CLOUDS AT GROUPS. +1 PUFF PER LINK",
        role = "STARTER DAMAGE",
        about = "CLOUDS HIT ALL INSIDE, FLIERS TOO. +1 PUFF PER LINK IT TOUCHES, UP TO 4.",
        up = {
            { { name = "LINGERING TOXIN", cost = 35, linger = 2, toxin = 4, blurb = "CLOUDS HANG FOR 2S AND POISON" },
              { name = "MIASMA", cost = 65, linger = 3.5, toxin = 8, splash = 16, blurb = "BIGGER, LONGER, NASTIER CLOUDS" } },
            { { name = "RAPID FIRE", cost = 35, every = 0.8, blurb = "PUFFS NEARLY TWICE AS OFTEN" },
              { name = "SPORE GATLING", cost = 65, every = 0.55, extraPuff = 1, blurb = "FASTER STILL, AND ONE MORE PUFF" } },
        } },
    { id = "needle", name = "ENOKI NEEDLE", cost = 45, key = "3", hp = 25, air = true,
        range = 100, every = 1.8, damage = 26, shot = 1.5, reserve = 9, deadEnd = 1.8,
        blurb = "LONG RANGE, PIERCES ARMOR. X1.8 ON A DEAD END",
        role = "SNIPER",
        about = "SHOOTS THE ONE NEAREST THE SPROUT, THROUGH ARMOR, FLIERS TOO. X1.8 ON A DEAD END.",
        up = {
            { { name = "SKEWER", cost = 40, pierce = 2, damage = 32, blurb = "RUNS THROUGH TWO IN A LINE" },
              { name = "LANCE", cost = 75, pierce = 3, damage = 44, range = 118, blurb = "THREE IN A LINE, FURTHER, HARDER" } },
            { { name = "MARK TARGET", cost = 40, mark = 1.25, markFor = 4, blurb = "MARKED PREY TAKES +25%" },
              { name = "HUNTER'S MARK", cost = 75, mark = 1.45, markFor = 5, every = 1.4, markSplash = 16,
                blurb = "+45%, FASTER, MARKS THE PACK" } },
        } },
    { id = "mat", name = "SLIME MAT", cost = 18, key = "4", onTrail = true,
        slow = 0.55, life = 35, feed = 12, drape = 0.82, drapeDigest = 0.5, maxDrape = 3,
        blurb = "LAID ON THE TRAIL. STICKIER FOR EVERY LINK DRAPED OVER IT",
        role = "SLOW",
        about = "ON THE TRAIL: SLOWS WALKERS. NEEDS A LINK OVER IT, AND EACH OF UP TO 3 STICKS MORE.",
        up = {
            { { name = "GLUE", cost = 20, slow = 0.37, life = 50, blurb = "STICKIER, LASTS LONGER" },
              { name = "AMBER", cost = 40, slow = 0.22, life = 70, blurb = "ALMOST SET SOLID" } },
            { { name = "DIGEST", cost = 25, digest = 4, blurb = "DISSOLVES WHAT STANDS ON IT" },
              { name = "STOMACH", cost = 45, digest = 8, slow = 0.46, blurb = "DISSOLVES FASTER, HOLDS HARDER" } },
        } },
    { id = "mane", name = "LION'S MANE", cost = 40, key = "5", hp = 35,
        depth = 3, heal = 5, regrow = 0.18, drain = 0.3, reserve = 6,
        blurb = "TENDS THE BRANCH BELOW IT: 3 HOPS AWAY FROM THE SPROUT",
        role = "HEALER",
        about = "HEALS AND REGROWS LINKS UP TO 3 HOPS PAST IT. DRINKS ONLY WHILE AT WORK.",
        up = {
            { { name = "FAST REGROWTH", cost = 35, heal = 8, regrow = 0.3, depth = 4, blurb = "70% FASTER, REACHES 4 HOPS" },
              { name = "OLD GROWTH", cost = 60, heal = 13, regrow = 0.46, depth = 5, blurb = "FASTER STILL, 5 HOPS DOWN" } },
            { { name = "PURGE", cost = 35, purge = true, towerHeal = 4, blurb = "CLEARS WEBS, HEALS TOWERS" },
              { name = "SANCTUARY", cost = 60, purge = true, towerHeal = 9, webProof = true, depth = 4,
                blurb = "ITS TOWERS CANNOT BE WEBBED" } },
        } },
    { id = "relay", name = "RELAY", cost = 30, key = "6", hp = 30,
        capMul = 2, amp = 1.1,
        blurb = "NO ATTACK. PUMPS X2 FLOW, +10% DAMAGE INTO WHAT IT LINKS TO",
        role = "SUPPORT",
        about = "NO ATTACK. ITS LINKS CARRY X2 FLOW, AND THE TOWERS IT FEEDS HIT +10%.",
        up = {
            { { name = "BATTERY", cost = 30, battery = 1.7, blurb = "LINKED TOWERS +70% RESERVE" },
              { name = "DEEP BATTERY", cost = 55, battery = 2.5, capMul = 2.5, blurb = "2.5X RESERVE, MORE FLOW" } },
            { { name = "AMPLIFIER", cost = 40, amp = 1.2, capMul = 2.5, blurb = "LINKED TOWERS +20% DAMAGE" },
              { name = "RESONATOR", cost = 70, amp = 1.35, capMul = 3, blurb = "+35% DAMAGE, TRIPLE FLOW" } },
        } },
    { id = "inky", name = "INKY CAP", cost = 35, key = "7", hp = 30, unlock = 2,
        range = 36, feast = 2, inkEvery = 6, inkLife = 5, inkR = 7, inkSlow = 0.7, reserve = 6, shot = 0.5,
        blurb = "DRINKS BODIES FOR X2, INTO WHAT IT LINKS TO FIRST. INK SLOWS",
        role = "ECONOMY",
        about = "DRINKS BODIES NEARBY FOR X2 NUTRIENTS. DRIPS INK THAT SLOWS.",
        up = {
            { { name = "WIDE REACH", cost = 30, range = 50, feast = 2.3, blurb = "DRINKS FURTHER OUT, X2.3" },
              { name = "SPORE SHADOW", cost = 55, range = 64, feast = 2.7, blurb = "FURTHER STILL, X2.7" } },
            { { name = "BIG INK", cost = 30, inkEvery = 4, inkR = 10, inkSlow = 0.55, blurb = "BIGGER POOLS, MORE OFTEN" },
              { name = "INK FLOOD", cost = 55, inkEvery = 2.5, inkR = 13, inkSlow = 0.42, inkLife = 7, blurb = "THE TRAIL RUNS BLACK" } },
        } },
    { id = "shelf", name = "SHELF FUNGUS", cost = 35, key = "8", onTrail = true, unlock = 4,
        hp = 140, shield = 30, shieldMul = 0.3, touch = 24,
        blurb = "BLOCKS THE TRAIL: THEY MUST CHEW THROUGH. SHIELDS LINKS",
        role = "BLOCKER",
        about = "BLOCKS A TRAIL TILE BY A FED LINK. LINKS NEAR IT TAKE A THIRD THE CHEWING.",
        up = {
            { { name = "THICK ARMOR", cost = 35, hp = 260, regen = 2, blurb = "TWICE THE WOOD, AND IT HEALS" },
              { name = "IRONWOOD", cost = 60, hp = 430, regen = 4, blurb = "LIKE CHEWING A NAIL" } },
            { { name = "THORNY", cost = 35, thorns = 5, blurb = "BITES WHATEVER CHEWS IT" },
              { name = "BRAMBLE", cost = 60, thorns = 12, hp = 200, blurb = "BITES BACK HARD" } },
        } },
    { id = "mortar", name = "PUFFBALL MORTAR", cost = 70, key = "9", hp = 40, unlock = 5,
        range = 92, minRange = 22, every = 3.6, damage = 38, splash = 20, shot = 3, reserve = 10, thirst = 5, highRange = 1.2,
        blurb = "HUGE SLOW BLASTS, MIN RANGE. NEEDS A RELAY. HIGH GROUND: NO MIN",
        role = "ARTILLERY",
        about = "HUGE SLOW BLASTS, MIN RANGE, NO FLIERS. NEEDS A RELAY. HIGH GROUND: NO MIN.",
        up = {
            { { name = "CLUSTER BLAST", cost = 55, cluster = 3, clusterDamage = 14, blurb = "THREE BOMBLETS SCATTER AFTER" },
              { name = "CARPET", cost = 90, cluster = 5, clusterDamage = 20, damage = 46, blurb = "FIVE BOMBLETS, BIGGER BLAST" } },
            { { name = "SMOKE", cost = 50, smoke = 1.3, blurb = "STUNS, DROPS WHAT THEY CARRY" },
              { name = "BLACKOUT", cost = 85, smoke = 2.3, splash = 27, blurb = "LONGER, WIDER SMOKE" } },
        } },
    { id = "cordyceps", name = "CORDYCEPS BLOOM", cost = 60, key = "0", hp = 30, unlock = 7,
        range = 54, every = 7, shot = 3, reserve = 6, infect = 4, maxHp = 400, bite = 14, perHop = 0.2, maxHops = 6,
        blurb = "INFECTS ONE: IT TURNS ON ITS OWN. HOLDS LONGER THE DEEPER IT GROWS",
        role = "CONTROL",
        about = "TURNS ONE WALKER (UP TO 400 HP) ON ITS OWN. HOLDS +20% PER HOP OUT.",
        up = {
            { { name = "LONGER CONTROL", cost = 45, infect = 6.5, maxHp = 700, blurb = "LONGER HOLD, BIGGER HOSTS" },
              { name = "PUPPETEER", cost = 80, infect = 9, maxHp = 1100, every = 5.5, blurb = "LONGER, BIGGER, MORE OFTEN" } },
            { { name = "SPREADS ON DEATH", cost = 45, spread = 1, blurb = "A DEAD HOST INFECTS THE NEXT" },
              { name = "PLAGUE", cost = 80, spread = 2, bite = 24, blurb = "SPREADS TWICE, HOSTS BITE HARDER" } },
        } },
    { id = "stink", name = "STINKHORN", cost = 40, key = "T", hp = 35, unlock = 3,
        range = 24, lane = 8, reek = 0.75, stumble = 0.2, trip = 0.5, bait = 70, hold = 6, drain = 0.35, reserve = 7,
        blurb = "ITS STENCH SLOWS AND TRIPS, AND RUNS DOWN ITS LINKS. BAITS FLIES",
        role = "DEBUFF AURA",
        about = "STENCH SLOWS AND TRIPS, ROUND IT AND ALONG ITS LINKS. BAITS FLIES.",
        up = {
            { { name = "WIDER STENCH", cost = 35, range = 30, lane = 11, reek = 0.68, bait = 90, blurb = "WIDER, AND THICKER" },
              { name = "CARRION REEK", cost = 60, range = 36, lane = 14, reek = 0.6, rot = 3, hold = 9, blurb = "ROTS THEM, HOLDS FLIES LONGER" } },
            { { name = "PANIC", cost = 40, panic = 1.2, panicEvery = 8, blurb = "NOW AND THEN THEY TURN AND FLEE" },
              { name = "TERROR", cost = 70, panic = 2, panicEvery = 6, range = 30, blurb = "THEY FLEE LONGER, MORE OFTEN" } },
        } },
    { id = "lamp", name = "GHOST LAMP", cost = 35, key = "G", hp = 80, unlock = 6,
        range = 30, perHop = 5, maxHops = 8, hold = 5, drain = 0.25, reserve = 6,
        blurb = "A GLOWING DECOY: THEY GO FOR IT FIRST. BRIGHTER FAR FROM THE SPROUT",
        role = "LURE",
        about = "DECOY: THEY CHEW IT FIRST. BRIGHTER FAR OUT AND AT NIGHT. NOT BOSSES.",
        up = {
            { { name = "LONGER GLOW", cost = 30, hp = 140, hold = 7, range = 36, blurb = "TOUGHER, AND HOLDS THEM LONGER" },
              { name = "WILL-O'-WISP", cost = 55, hp = 220, hold = 9, range = 42, regen = 4, blurb = "TOUGHER STILL, AND HEALS" } },
            { { name = "FLARE", cost = 35, blast = 40, blastR = 22, blurb = "BURSTS WHEN IT IS DESTROYED" },
              { name = "STARBURST", cost = 65, blast = 85, blastR = 30, blastStun = 1.5, blurb = "A BIGGER BURST, AND IT STUNS" } },
        } },
    -- The late unlock. One per run (once grown, never again), slow to grow,
    -- and stronger for every fed node near it: within `hops` links, or in a
    -- Fairy Ring it stands in.
    { id = "giant", name = "HUMONGOUS FUNGUS", cost = 150, key = "H", hp = 200, unlock = 9, unique = true,
        range = 40, rangePerNode = 3, maxRange = 80, every = 3.2, damage = 8, perNode = 5, hops = 2, shot = 3, reserve = 14,
        growTime = 8,
        blurb = "ONE PER RUN, SLOW. HITS HARDER PER FED NODE NEAR IT OR IN ITS RING",
        role = "LATE GAME",
        about = "ONE PER RUN. QUAKES HIT ALL IN REACH, MORE PER FED NODE WITHIN 2 LINKS.",
        up = {
            { { name = "SPREADING", cost = 70, perNode = 6.5, rangePerNode = 3.5, hops = 3, blurb = "MORE PER NODE, 3 LINKS OFF" },
              { name = "ARMILLARIA", cost = 110, perNode = 9, rangePerNode = 4, every = 2.6, maxRange = 96,
                blurb = "MORE PER NODE, FASTER, WIDER" } },
            { { name = "HONEY ROOT", cost = 70, stick = 0.5, stickFor = 1.5, mend = 8, blurb = "QUAKES STICK THEM AND MEND LINKS" },
              { name = "ANCIENT", cost = 110, stick = 0.35, stickFor = 2, mend = 16, quake = 0.6,
                blurb = "STICKIER, MENDS MORE, AND STUNS" } },
        } },
}
D.TOWER = {}
for _, t in ipairs(D.TOWERS) do D.TOWER[t.id] = t end

-- The Spore Bank. The first six species are grown from the start; each of the
-- other six is put up for sale by winning a level (its `prize`, below) and
-- bought for good with spores at its `price`. A run pays a spore for every
-- wave it clears and more for a win.
D.STARTERS = 6
for k, t in ipairs(D.TOWERS) do t.starter = k <= D.STARTERS end
for id, price in pairs({ stink = 20, shelf = 25, mortar = 30, lamp = 35, cordyceps = 40, giant = 50 }) do
    D.TOWER[id].price = price
end
D.SPORES = { wave = 1, win = 10 }

-- Sprout seeds: the plant at the end of the trail, picked with the loadout.
-- Spores buy them too: the bean is there from the start, the oak and the
-- tomato are for sale from the start, the rest once `after` is won. `heart`,
-- `income` and `grow` scale the level's sprout, its sugar and how fast links
-- grow; `start` adds to its nutrients. Each brings mutations of its own (MUTATIONS rows with its
-- `seed`), one of which is on offer every time the network mutates.
D.SEEDS = {
    { id = "bean", name = "BEAN SPROUT", short = "BEAN",
        blurb = "AS IT COMES: NOTHING GAINED, NOTHING GIVEN UP",
        about = "THE SPROUT YOU KNOW. ITS MUTATIONS ARE ABOUT GROWING: QUICK THREADS, RICHER POCKETS, FREE LINKS." },
    { id = "oak", name = "OAK SAPLING", short = "OAK", price = 15, heart = 1.5, grow = 0.75,
        blurb = "SPROUT +50% HP, BUT LINKS GROW 25% SLOWER",
        about = "TOUGH AND SLOW. IT TAKES THE HITS SO THE NETWORK CAN BE THIN. ITS MUTATIONS HARDEN IT AND THE THREADS AT ITS FOOT." },
    { id = "tomato", name = "TOMATO SEEDLING", short = "TOMATO", price = 15, heart = 0.7, income = 1.1, start = 10,
        blurb = "SUGAR +10%, +10 TO START, SPROUT -30% HP",
        about = "RICH BUT SOFT. MORE TO SPEND ON EVERY WAVE, AND LESS ROOM FOR A LEAK. ITS MUTATIONS PAY MORE, OR BURST ON WHAT GETS THROUGH." },
    { id = "dandelion", name = "DANDELION", short = "DANDELION", price = 25, after = "flowerpot", regrow = 1,
        blurb = "KILLED, IT REGROWS ONCE AT HALF HEALTH",
        about = "A WEED: KILL IT AND IT COMES BACK, ONCE, AT HALF ITS HP, AND THE WAVE GOES ON. ITS MUTATIONS SPREAD IT ON THE WIND." },
    { id = "sunflower", name = "SUNFLOWER", short = "SUNFLOWER", price = 35, after = "log", sun = { hops = 2, damage = 1.15 },
        blurb = "TOWERS 2 HOPS FROM IT HIT 15% HARDER, BUT NOT AT NIGHT",
        about = "IT FACES THE SUN, AND WHAT GROWS CLOSE TO IT HITS HARDER BY DAY. AT NIGHT IT HANGS ITS HEAD. ITS MUTATIONS FEED ON THE LIGHT." },
    { id = "flytrap", name = "VENUS FLYTRAP", short = "FLYTRAP", price = 45, after = "lawn", income = 0.9,
        trap = { range = 26, every = 2.5, bite = 20, eat = 40, heal = 0.5 },
        blurb = "SNAPS AT BUGS NEAR IT. EATS SMALL ONES. SUGAR -10%",
        about = "IT BITES WHAT COMES CLOSE: A BUG WITH 40 HP LEFT OR LESS IS EATEN WHOLE, AND HEALS IT A LITTLE. ITS MUTATIONS SHARPEN THE TRAP." },
}
D.SEED = {}
for _, s in ipairs(D.SEEDS) do D.SEED[s.id] = s end
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

    -- Walks the trail and every few seconds springs off its tail: over a
    -- shelf, off a mat, past whatever was slowing it. The first time it comes
    -- down on a thread, the thread snaps.
    springtail = { name = "SPRINGTAIL", hp = 18, speed = 15, armor = 0, bite = 3,
        hopEvery = 2.6, hopFor = 0.55, hopSpeed = 52, hopH = 9, snapR = 5,
        heart = 1, corpse = 2, blurb = "HOPS OVER SHELVES AND MATS. ITS FIRST LANDING SNAPS A LINK" },

    -- Walks the trail until a link is in reach off it, then sinks and burrows
    -- under the board to it (a bump in the soil, nothing can touch it), comes
    -- up beside it and cuts it. Up, it is still and soft for `surfaceFor`;
    -- after `cuts` of them it climbs back to the trail and walks on. No
    -- coming up in water.
    cricket = { name = "CRICKET NYMPH", short = "CRICKET", hp = 45, speed = 12, armor = 1, bite = 5,
        sinkEvery = 3, sinkFor = 0.8, reach = 110, burrow = 24, surfaceFor = 2.2, cuts = 2,
        heart = 2, corpse = 6, blurb = "BURROWS OFF THE TRAIL AND COMES UP BESIDE A LINK TO CUT IT" },
    -- A small centipede: a head and a train of segments, each its own enemy,
    -- like the Giant's. It does not cut what it crosses but wears it, `wear`
    -- a second a body for every link within `wearR`.
    centi = { name = "CENTIPEDE", hp = 34, speed = 14, armor = 1, segments = 4, gap = 5.5, seg = "centiseg",
        bite = 4, wear = 7, wearR = 4, heart = 1, corpse = 4, size = 0.9,
        blurb = "A TRAIN OF SEGMENTS. EVERY ONE GNAWS THE LINKS IT RUNS ALONG" },
    centiseg = { name = "CENTIPEDE", short = "CENTIPEDE", segment = true, hp = 26, speed = 14, armor = 1, bite = 3,
        wear = 7, wearR = 4, heart = 0.5, corpse = 2, size = 0.8 },

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
        seg = "centseg",
        bite = 30, crushR = 4.5, heart = 6, corpse = 14, size = 2,
        blurb = "A TRAIN OF ARMORED SEGMENTS. EACH CUTS WHAT IT CROSSES. IT SPLITS WHERE BROKEN" },
    centseg = { name = "GIANT CENTIPEDE", boss = true, segment = true, hp = 220, speed = 11, armor = 5, bite = 20,
        crushR = 4.5, heart = 1.5, corpse = 8, size = 1.6 },
    -- The Rotting Log's boss. Every few seconds it rolls onto its back and
    -- plays dead (soft: no armor, and it takes `belly` times as much), then
    -- clicks and leaps down the trail; where it lands, links within `slamR`
    -- are cut and towers within `stunR` stunned.
    click = { name = "CLICK BEETLE", boss = true, hp = 2600, speed = 8, armor = 6, bite = 50,
        clickEvery = 7, bellyFor = 2.4, belly = 1.5, leapFor = 0.9, leapSpeed = 60, leapH = 26,
        slamR = 20, stun = 2.5, stunR = 30, heart = 12, corpse = 60, size = 2.6,
        blurb = "PLAYS DEAD ON ITS BACK, SOFT. THEN CLICKS AND LEAPS: ITS LANDING CUTS AND STUNS" },
    -- Challenge mode's boss. Walking, it scalds the nearest tower behind it;
    -- `siege` tiles from the sprout it stops and sprays the sprout itself, and
    -- whatever stands in the way (a shelf, a tower) takes the spray instead.
    bombardier = { name = "BOMBARDIER BEETLE", boss = true, hp = 1600, speed = 9, armor = 4, bite = 50,
        sprayEvery = 6, sprayR = 44, scald = 30, siege = 3, siegeEvery = 2.5, heartSpray = 2, coverR = 7,
        heart = 12, corpse = 60, size = 2.6,
        blurb = "AT THE END OF THE TRAIL IT TURNS AND SPRAYS THE SPROUT. COVER IT" },
    -- Every so often it stops and digs (still, and open to anything), then
    -- burrows straight across to whichever trail tile within `reach` is the
    -- most steps nearer the sprout, up to `most` and at least `save` -- through
    -- the wall to the next turn of a winding trail -- and comes up there, dazed. The tunnel stays open behind
    -- it: anything walking that comes to the first hole goes down and climbs out
    -- of the second `tunnelFor` seconds later, itself dazed for `daze`. Bosses
    -- and fliers do not use it. Killed, it takes its tunnels with it, and what
    -- is down them.
    mole = { name = "MOLE CRICKET", boss = true, hp = 1500, speed = 7, armor = 5, bite = 40,
        digEvery = 10, digFor = 2.5, digs = 2, reach = 96, save = 5, most = 14, keep = 3, burrow = 26, surfaceFor = 1.2,
        tunnelFor = 3, daze = 0.8, heart = 12, corpse = 60, size = 2.6,
        blurb = "DIGS A TUNNEL AHEAD, AND THE REST FOLLOW. KILL IT AND THE TUNNEL CAVES IN" },
}
D.ENEMY_ORDER = { "ant", "pillbug", "mite", "gnat", "moth", "brine", "slug", "spider", "knight", "springtail",
    "cricket", "centi",
    "queen", "stag", "dung", "click", "waterbug", "centipede", "bombardier", "mole" }

-- What answers each enemy: the species the loadout picker lights up when the
-- player points at one coming in the level (the design doc's counterplay).
D.COUNTERS = {
    ant = { "puffer", "mortar", "inky" },
    pillbug = { "mat", "shelf", "needle" },
    mite = { "puffer", "mane", "mortar" },
    gnat = { "stink", "lamp" },
    moth = { "lamp", "stink" },
    brine = { "needle", "puffer" },
    slug = { "cordyceps", "mortar", "needle" },
    spider = { "mane", "shelf" },
    knight = { "needle", "cordyceps" },
    cricket = { "mane", "mortar", "needle" },
    centi = { "puffer", "mortar", "mat" },
    queen = { "puffer", "mortar", "mane" },
    stag = { "mane", "needle", "relay" },
    dung = { "mortar", "needle" },
    waterbug = { "mane", "needle" },
    centipede = { "puffer", "mortar", "mat" },
    bombardier = { "shelf", "lamp" },
    springtail = { "puffer", "stink", "lamp" },
    click = { "needle", "mortar", "mane" },
    mole = { "needle", "mortar", "mat" },
}

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

-- Waves: { kind, how many, seconds between, gate, start[, health] }, health
-- a fraction of the usual (a boss met part way through a level comes weaker), gates counted down
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

local MID = 0.35 -- the health of a boss met part way through a level
-- Every level has three bosses, at about a third, two thirds and the end of
-- it: two met before along the way, its own at the end.

-- The Flowerpot: one long spiral in from the rim, and from wave 3 the
-- drainage hole (gate 2), three tiles from the sprout.
local FLOWERPOT = {
    { { "ant", 8, 1.4, 1, 0 } },
    { { "ant", 8, 1.3, 1, 0 }, { "pillbug", 1, 1, 1, 6 } },
    { weather = "rain", { "ant", 6, 1.4, 1, 0 }, { "ant", 4, 1.6, 2, 6 } },
    { { "pillbug", 2, 5, 1, 0 }, { "ant", 10, 1.1, 1, 2 }, { "dung", 1, 1, 1, 4, MID }, { "mite", 1, 1, 2, 8 } },
    { { "gnat", 4, 1.5, 1, 0 }, { "ant", 8, 1.1, 2, 2 }, { "pillbug", 2, 4, 1, 6 } },
    { weather = "night", { "moth", 4, 2, 1, 0 }, { "ant", 10, 1, 1, 2 }, { "brine", 1, 1, 1, 6 }, { "ant", 4, 1.2, 2, 10 } },
    { { "slug", 1, 1, 1, 0 }, { "pillbug", 3, 4, 1, 2 }, { "mite", 2, 6, 2, 4 }, { "ant", 10, 0.9, 1, 8 } },
    { weather = "drought", { "mole", 1, 1, 1, 0, MID }, { "spider", 2, 5, 1, 2 }, { "gnat", 5, 1.2, 1, 6 }, { "ant", 12, 0.9, 1, 10 },
        { "ant", 6, 1, 2, 10 } },
    { weather = "rain", { "knight", 2, 5, 1, 0 }, { "brine", 2, 7, 1, 3 }, { "pillbug", 3, 4, 2, 4 }, { "ant", 10, 0.9, 1, 8 } },
    { weather = "frost", { "pillbug", 4, 3, 1, 0 }, { "slug", 2, 7, 1, 2 }, { "mite", 3, 5, 2, 4 }, { "gnat", 6, 1, 1, 8 } },
    { weather = "night", { "moth", 6, 1.5, 1, 0 }, { "spider", 3, 4, 1, 2 }, { "knight", 3, 5, 1, 6 }, { "ant", 14, 0.7, 2, 8 } },
    { { "ant", 12, 0.8, 1, 0 }, { "queen", 1, 1, 1, 4 }, { "ant", 8, 1, 2, 10 }, { "pillbug", 3, 4, 1, 12 } },
}

-- The Shed Floor: two ways in that meet at one chokepoint. Springtails hop
-- the shelves that hold it; the Stag Beetle comes last.
local SHED = {
    { { "ant", 8, 1.4, 1, 0 }, { "ant", 6, 1.4, 2, 5 } },
    { { "ant", 8, 1.2, 2, 0 }, { "spider", 1, 1, 1, 4 }, { "ant", 6, 1.3, 1, 6 } },
    { { "pillbug", 2, 5, 1, 0 }, { "ant", 10, 1.1, 2, 2 }, { "gnat", 3, 1.5, 1, 8 } },
    { { "springtail", 6, 1, 1, 0 }, { "ant", 8, 1.1, 2, 3 }, { "springtail", 4, 1, 2, 8 } },
    { weather = "rain", { "spider", 2, 5, 2, 0 }, { "ant", 10, 1, 1, 2 }, { "dung", 1, 1, 1, 4, 0.2 }, { "brine", 1, 1, 1, 6 },
        { "springtail", 6, 0.8, 2, 8 } },
    { { "knight", 1, 1, 1, 0 }, { "mite", 2, 6, 2, 2 }, { "ant", 12, 0.9, 1, 6 } },
    { weather = "night", { "moth", 5, 1.5, 2, 0 }, { "spider", 3, 4, 1, 2 }, { "springtail", 8, 0.7, 2, 4 }, { "ant", 10, 1, 1, 8 } },
    { { "slug", 2, 8, 1, 0 }, { "pillbug", 4, 4, 2, 2 }, { "springtail", 8, 0.6, 1, 6 }, { "gnat", 6, 1, 2, 8 } },
    { weather = "drought", { "knight", 2, 5, 2, 0 }, { "spider", 4, 4, 1, 2 }, { "queen", 1, 1, 1, 4, MID }, { "mite", 3, 5, 2, 6 },
        { "ant", 14, 0.8, 1, 8 } },
    { weather = "frost", { "pillbug", 4, 3, 1, 0 }, { "knight", 2, 5, 2, 2 }, { "springtail", 10, 0.5, 1, 6 }, { "brine", 2, 8, 2, 6 } },
    { weather = "night", { "moth", 8, 1.2, 1, 0 }, { "spider", 5, 3, 2, 2 }, { "slug", 3, 6, 1, 4 }, { "ant", 16, 0.7, 2, 8 } },
    { weather = "rain", { "springtail", 14, 0.4, 2, 0 }, { "knight", 3, 4, 1, 2 }, { "gnat", 10, 0.7, 2, 6 }, { "brine", 3, 6, 1, 8 } },
    { { "ant", 10, 0.9, 1, 0 }, { "stag", 1, 1, 2, 3 }, { "ant", 10, 0.9, 1, 8 }, { "springtail", 8, 0.6, 2, 10 } },
}

-- The Rotting Log: dark nearly every wave. Slugs and mites, the Mole Cricket
-- in the soft wood, and the Click Beetle down the long straights at the end.
local LOG = {
    { weather = "night", { "ant", 8, 1.4, 1, 0 }, { "mite", 1, 1, 2, 4 } },
    { weather = "night", { "ant", 8, 1.2, 2, 0 }, { "slug", 1, 1, 1, 4 }, { "moth", 3, 2, 1, 6 } },
    { weather = "rain", { "mite", 2, 6, 1, 0 }, { "ant", 10, 1.1, 2, 2 }, { "springtail", 4, 1, 1, 6 } },
    { weather = "night", { "slug", 2, 8, 2, 0 }, { "moth", 5, 1.6, 1, 2 }, { "ant", 10, 1, 1, 4 } },
    { weather = "night", { "mite", 3, 5, 1, 0 }, { "pillbug", 3, 4, 2, 2 }, { "queen", 1, 1, 1, 4, MID }, { "gnat", 4, 1.4, 1, 6 },
        { "ant", 8, 1, 2, 8 } },
    { weather = "rain", { "slug", 2, 8, 1, 0 }, { "brine", 2, 6, 2, 2 }, { "springtail", 8, 0.7, 1, 6 }, { "ant", 8, 1, 2, 6 } },
    { weather = "night", { "spider", 3, 4, 2, 0 }, { "moth", 6, 1.4, 1, 2 }, { "mite", 3, 5, 2, 4 }, { "ant", 12, 0.9, 1, 8 } },
    { weather = "night", { "knight", 3, 5, 1, 0 }, { "slug", 3, 6, 2, 2 }, { "springtail", 8, 0.6, 2, 6 }, { "moth", 6, 1.2, 1, 8 } },
    { weather = "frost", { "pillbug", 4, 3, 2, 0 }, { "mite", 2, 4, 1, 2 }, { "mole", 1, 1, 2, 4, MID }, { "knight", 2, 5, 2, 6 },
        { "gnat", 8, 0.9, 1, 8 }, { "mite", 3, 3, 2, 12 } },
    { weather = "night", { "moth", 10, 1, 2, 0 }, { "spider", 4, 4, 1, 2 }, { "slug", 3, 6, 1, 4 }, { "ant", 16, 0.7, 2, 8 } },
    { weather = "rain", { "springtail", 12, 0.5, 1, 0 }, { "knight", 4, 4, 2, 2 }, { "brine", 3, 6, 1, 6 }, { "mite", 4, 4, 2, 8 } },
    { weather = "night", { "slug", 4, 5, 2, 0 }, { "spider", 5, 3, 1, 2 }, { "moth", 12, 0.8, 2, 4 }, { "knight", 4, 4, 1, 8 },
        { "ant", 16, 0.6, 2, 10 } },
    { weather = "night", { "ant", 14, 0.8, 1, 0 }, { "click", 1, 1, 2, 4 }, { "slug", 2, 8, 1, 8 }, { "moth", 8, 1, 2, 10 },
        { "springtail", 8, 0.6, 1, 14 } },
}

-- The Pond Edge: water and reeds. Both trails wade a flooded lane, where the
-- Giant Water Bug hides; stones are the high ground it cannot reach.
local POND = {
    { { "ant", 8, 1.4, 1, 0 }, { "ant", 6, 1.4, 2, 5 } },
    { weather = "rain", { "ant", 8, 1.2, 2, 0 }, { "pillbug", 2, 5, 1, 4 }, { "gnat", 3, 1.5, 1, 8 } },
    { { "ant", 10, 1.1, 1, 0 }, { "brine", 1, 1, 2, 4 }, { "mite", 1, 1, 2, 8 } },
    { weather = "night", { "moth", 5, 1.6, 1, 0 }, { "ant", 10, 1, 2, 2 }, { "queen", 1, 1, 1, 4, MID }, { "spider", 2, 5, 1, 6 } },
    { weather = "rain", { "slug", 2, 8, 1, 0 }, { "brine", 2, 6, 2, 3 }, { "ant", 12, 0.9, 2, 6 }, { "cricket", 2, 5, 1, 8 } },
    { weather = "drought", { "knight", 2, 5, 1, 0 }, { "mite", 2, 6, 2, 2 }, { "pillbug", 3, 4, 2, 4 }, { "gnat", 5, 1.2, 1, 8 } },
    { weather = "night", { "moth", 8, 1.2, 2, 0 }, { "spider", 3, 4, 1, 3 }, { "ant", 12, 0.9, 1, 6 }, { "cricket", 2, 5, 2, 8 } },
    { { "ant", 10, 1, 2, 0 }, { "stag", 1, 1, 1, 3, MID }, { "gnat", 6, 1, 2, 10 } },
    { weather = "rain", { "brine", 3, 6, 1, 0 }, { "knight", 3, 5, 2, 2 }, { "slug", 2, 8, 1, 6 }, { "gnat", 8, 1, 2, 8 },
        { "cricket", 3, 4, 2, 10 } },
    { weather = "frost", { "pillbug", 5, 3, 1, 0 }, { "knight", 4, 4, 2, 2 }, { "spider", 4, 4, 1, 6 }, { "mite", 3, 5, 2, 8 },
        { "cricket", 3, 4, 1, 10 } },
    { weather = "night", { "moth", 10, 1, 1, 0 }, { "slug", 3, 6, 2, 2 }, { "ant", 20, 0.6, 1, 6 }, { "brine", 2, 8, 2, 8 },
        { "cricket", 4, 3, 1, 10 } },
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
    { weather = "frost", { "knight", 3, 4, 1, 0 }, { "pillbug", 3, 4, 3, 2 }, { "mite", 2, 6, 2, 6 }, { "gnat", 6, 1, 2, 8 },
        { "centi", 1, 1, 2, 10 } },
    { weather = "drought", { "spider", 4, 4, 2, 0 }, { "slug", 2, 8, 3, 2 }, { "ant", 14, 0.8, 1, 4 }, { "cricket", 2, 5, 1, 6 } },
    { { "knight", 4, 3, 3, 0 }, { "brine", 3, 6, 2, 2 }, { "gnat", 8, 0.9, 1, 4 }, { "ant", 12, 0.8, 2, 8 },
        { "centi", 2, 6, 3, 10 } },
    { weather = "night", { "moth", 8, 1.2, 1, 0 }, { "spider", 4, 4, 3, 2 }, { "mite", 3, 5, 2, 4 }, { "ant", 12, 0.8, 3, 8 },
        { "cricket", 3, 4, 2, 10 } },
    { { "knight", 3, 5, 1, 0 }, { "stag", 1, 1, 2, 3 }, { "ant", 14, 0.8, 3, 6 } },
    { weather = "rain", { "slug", 3, 6, 1, 0 }, { "brine", 3, 6, 3, 2 }, { "pillbug", 5, 3, 2, 4 }, { "gnat", 10, 0.7, 1, 8 },
        { "centi", 3, 5, 2, 10 } },
    { weather = "drought", { "knight", 7, 2.5, 2, 0 }, { "spider", 5, 3, 1, 3 }, { "mite", 4, 4, 3, 6 }, { "ant", 18, 0.6, 2, 8 },
        { "pillbug", 3, 4, 3, 10 }, { "cricket", 3, 4, 1, 12 } },
    { weather = "frost", { "pillbug", 6, 2.5, 1, 0 }, { "slug", 4, 5, 3, 2 }, { "knight", 6, 3, 2, 4 }, { "gnat", 12, 0.6, 3, 6 },
        { "centi", 3, 4, 1, 8 } },
    { weather = "night", { "moth", 14, 0.7, 2, 0 }, { "spider", 7, 3, 1, 2 }, { "brine", 3, 6, 3, 4 }, { "ant", 24, 0.5, 1, 8 },
        { "knight", 4, 4, 3, 10 }, { "centi", 3, 4, 2, 12 } },
    { { "ant", 18, 0.6, 3, 0 }, { "centipede", 1, 1, 2, 4 }, { "knight", 6, 3, 1, 8 }, { "gnat", 12, 0.7, 3, 12 },
        { "slug", 3, 6, 1, 16 }, { "cricket", 3, 4, 3, 14 } },
}

-- The levels, in the order they open: each is won to open the next. `map`
-- names a map in src/world.lua. Species come as the waves are cleared on
-- every level (see D.unlockAt); `unlock`, if given, overrides a species'
-- wave there. `prize` is the species its first win puts up for sale in the
-- Spore Bank. `loadout` is the species brought the first time it is played,
-- before the player has picked their own. `growth` is how much tougher each wave's enemies are than the
-- last's, if not HP_GROWTH. `ringNodes` is how few fed nodes close a Fairy
-- Ring there, if not RING.nodes. They come in the design doc's order; the
-- Crack is its first level and has the three bosses the later ones each bring.
D.LEVELS = {
    { id = "crack", prize = "stink", name = "THE CRACK", map = "crack", waves = CRACK, start = 110, heart = 20,
        mutateAfter = { [3] = true, [5] = true, [8] = true, [10] = true, [12] = true },
        loadout = { "puffer", "needle", "mat", "mane", "relay", "mortar" },
        idea = "A SIDEWALK CRACK. LEARN THE NETWORK", boss = "QUEEN, STAG, DUNG BEETLE" },
    { id = "flowerpot", prize = "shelf", name = "THE FLOWERPOT", map = "flowerpot", waves = FLOWERPOT, start = 130, heart = 20,
        growth = 0.42,
        mutateAfter = { [2] = true, [4] = true, [7] = true, [9] = true },
        loadout = { "puffer", "needle", "mat", "mane", "relay", "mortar" },
        idea = "A CRACKED POT. CUT AND REGROW, AND WATCH THE HOLE", boss = "DUNG, MOLE, QUEEN ANT" },
    { id = "shed", prize = "mortar", name = "THE SHED FLOOR", map = "shed", waves = SHED, start = 160, heart = 23, growth = 0.08,
        mutateAfter = { [3] = true, [5] = true, [8] = true, [10] = true, [12] = true },
        loadout = { "puffer", "needle", "mat", "mane", "shelf", "stink" },
        idea = "BOARDS AND LEGO. HOLD THE CHOKEPOINT", boss = "DUNG, QUEEN, STAG BEETLE" },
    { id = "log", prize = "lamp", name = "THE ROTTING LOG", map = "log", waves = LOG, start = 130, heart = 20, growth = 0.2,
        ringNodes = 3,
        mutateAfter = { [2] = true, [4] = true, [7] = true, [9] = true, [11] = true },
        loadout = { "puffer", "needle", "mane", "lamp", "inky", "mortar" },
        idea = "DARK AND DAMP. THREE NODES CLOSE A RING", boss = "QUEEN, MOLE, CLICK BEETLE" },
    { id = "pond", prize = "cordyceps", name = "THE POND EDGE", map = "pond", waves = POND, start = 150, heart = 20, growth = 0.08,
        mutateAfter = { [2] = true, [4] = true, [7] = true, [9] = true },
        loadout = { "puffer", "needle", "mat", "mane", "stink", "lamp" },
        idea = "WATER AND REEDS. BUILD ON HIGH GROUND", boss = "QUEEN, STAG, GIANT WATER BUG" },
    { id = "lawn", prize = "giant", name = "THE LAWN", map = "lawn", waves = LAWN, start = 140, heart = 20, growth = 0.2,
        mutateAfter = { [3] = true, [5] = true, [8] = true, [10] = true, [12] = true },
        loadout = { "puffer", "needle", "mat", "mane", "mortar", "stink" },
        idea = "OPEN GRASS, THREE GATES. EVERYTHING AT ONCE", boss = "QUEEN, STAG, GIANT CENTIPEDE" },
}
D.LEVEL = {}
for _, l in ipairs(D.LEVELS) do D.LEVEL[l.id] = l end

-- Challenge mode, open once the Lawn is won: any level with this wave added
-- at the end, and the Bombardier Beetle in it.
D.CHALLENGE = { weather = "night", { "bombardier", 1, 1, 1, 0 }, { "knight", 4, 3, 2, 3 }, { "moth", 8, 1, 2, 5 },
    { "spider", 4, 4, 1, 8 }, { "ant", 20, 0.6, 2, 10 } }

-- The loadout: how many species a run brings, picked before a level from all
-- of them. The rest stay home, off the toolbar. Hyphae, prune and the pulse
-- always come.
D.LOADOUT = 6

-- The wave that has to be cleared on `level` before a species can be grown.
-- `set`, the loadout brought ({ id = true }), makes sure a run starts with
-- something to grow: if nothing in it comes at wave 0, the one of it that
-- comes first (toolbar order breaks a tie) is there from the start.
function D.unlockAt(level, kind, set)
    local function at(id) return level.unlock and level.unlock[id] or D.TOWER[id].unlock or 0 end
    if not (set and set[kind]) then return at(kind) end
    local first
    for _, t in ipairs(D.TOWERS) do
        if set[t.id] and (not first or at(t.id) < at(first)) then first = t.id end
    end
    if at(first) > 0 and kind == first then return 0 end
    return at(kind)
end

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

    -- A seed's own, offered only on a run that brings it.
    { id = "tendrils", seed = "bean", name = "TENDRILS", blurb = "LINKS FROM THE SPROUT GROW AT ONCE" },
    { id = "nitro", seed = "bean", name = "NITROGEN FIX", blurb = "TOWERS 2 HOPS FROM THE SPROUT HIT AS IF ON A POCKET ONE RICHER" },
    { id = "pod", seed = "bean", name = "BEAN POD", blurb = "YOUR NEXT THREE LINKS ARE FREE" },

    { id = "heartwood", seed = "oak", name = "HEARTWOOD", blurb = "THE SPROUT TAKES 30% LESS FROM WHAT GETS THROUGH" },
    { id = "bark", seed = "oak", name = "BARK", blurb = "LINKS TOUCHING THE SPROUT HAVE X3 HP" },
    { id = "acorn", seed = "oak", name = "ACORN DROP", blurb = "EVERY 6S AN ACORN FALLS ON THE BUG NEAREST THE SPROUT: 30, AND IT IS STUNNED" },
    { id = "growth", seed = "oak", name = "RINGS OF GROWTH", blurb = "THE SPROUT GROWS +1 HP EVERY WAVE CLEARED" },

    { id = "ripen", seed = "tomato", name = "RIPENING", blurb = "WAVE CLEAR BONUS +30%" },
    { id = "splat", seed = "tomato", name = "SPLAT", blurb = "WHAT REACHES THE SPROUT BURSTS A FRUIT: 15 TO BUGS NEAR IT, AND THEY STICK" },
    { id = "compost", seed = "tomato", name = "COMPOST", blurb = "BODIES LEFT LYING AT A WAVE'S END PAY HALF" },
    { id = "overripe", seed = "tomato", name = "OVERRIPE", blurb = "+1 SUGAR A SECOND IN A WAVE, BUT HALF THE WAVE CLEAR BONUS" },

    { id = "clock", seed = "dandelion", name = "SEED CLOCK", blurb = "THE SPROUT REGROWS ONE MORE TIME" },
    { id = "taproot", seed = "dandelion", name = "TAPROOT", blurb = "WHEN IT REGROWS, EVERY CUT LINK REGROWS TOO" },
    { id = "drift", seed = "dandelion", name = "SEED DRIFT", blurb = "AFTER EACH WAVE A FREE SPORE PUFFER GROWS ON AN EMPTY FED POCKET" },
    { id = "chute", seed = "dandelion", name = "PARACHUTES", blurb = "THE PULSE COMES BACK 30% SOONER AND LASTS 50% LONGER" },

    { id = "seedhead", seed = "sunflower", name = "SEED HEAD", blurb = "A WAVE CLEARED PAYS +4 FOR EVERY TOWER IN THE SUN" },
    { id = "helio", seed = "sunflower", name = "HELIOTROPE", blurb = "THE SUN REACHES 3 HOPS, AND HOLDS AT NIGHT" },
    { id = "stem", seed = "sunflower", name = "TALL STEM", blurb = "FLIERS NEAR THE SPROUT TAKE 8 A SECOND" },

    { id = "digest", seed = "flytrap", name = "DIGEST", blurb = "WHAT THE TRAP EATS PAYS ITS WORTH AGAIN, AT ONCE" },
    { id = "hairs", seed = "flytrap", name = "TRIGGER HAIRS", blurb = "THE TRAP SNAPS 40% MORE OFTEN" },
    { id = "sundew", seed = "flytrap", name = "SUNDEW", blurb = "BUGS NEAR THE SPROUT WADE AT HALF SPEED" },
    { id = "jaws", seed = "flytrap", name = "WIDE JAWS", blurb = "THE TRAP REACHES 40% FURTHER AND EATS BUGS OF UP TO 80 HP" },
}

return D

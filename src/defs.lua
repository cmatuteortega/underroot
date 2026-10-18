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

    -- The six grown off the others, deep in the network.
    --
    -- Anti-air: light shots at fliers alone, which drift dazed. Strongest on a
    -- bridge (a node with exactly two links), weaker at a dead end or a hub.
    { id = "agaric", name = "FLY AGARIC", cost = 40, key = "A", hp = 25, air = true, airOnly = true,
        range = 70, every = 0.45, damage = 7, shot = 0.25, reserve = 8, daze = 0.5, dazeFor = 1.2,
        bridge = 1.5, edge = 0.75,
        blurb = "FAST SHOTS AT FLIERS ONLY, WHICH DRIFT DAZED. BEST ON A BRIDGE",
        role = "ANTI-AIR",
        about = "SHOOTS FLIERS ONLY, AND SLOWS THEM. X1.5 WITH TWO LINKS, X0.75 WITH ONE OR THREE.",
        up = {
            { { name = "FLY BANE", cost = 35, damage = 11, blurb = "HITS FLIERS HARDER" },
              { name = "MUSCARIA", cost = 65, damage = 14, spread = 14, spreadDamage = 0.5,
                blurb = "THE POISON SPREADS TO FLIERS NEAR" } },
            { { name = "MUSCIMOL", cost = 35, confuse = 1.2, confuseR = 10, blurb = "WALKERS IN ITS CLOUD WANDER BACK" },
              { name = "IBOTENIC", cost = 65, confuse = 2, confuseR = 14, every = 0.38,
                blurb = "LONGER, WIDER, AND FASTER" } },
        } },
    -- Thumps the ground: every walker in reach is hit and staggers, a burrower
    -- or a swimmer twice. Hears further down longer threads.
    { id = "earthstar", name = "EARTHSTAR", cost = 50, key = "S", hp = 40,
        range = 24, perLen = 0.12, maxRange = 52, every = 2.4, damage = 12, deep = 2, stagger = 0.3, shot = 1, reserve = 8,
        blurb = "THUMPS ALL WALKERS IN REACH, DIGGERS X2. HEARS DOWN LONG LINKS",
        role = "GROUND THUMPER",
        about = "HITS EVERY WALKER IN REACH, BURROWED OR UNDER WATER X2. REACH GROWS WITH ITS LINKS' LENGTH.",
        up = {
            { { name = "DEEP LISTENER", cost = 40, range = 28, perLen = 0.16, maxRange = 62, blurb = "HEARS FURTHER" },
              { name = "SEISMIC", cost = 70, perLen = 0.2, maxRange = 72, expose = 3,
                blurb = "FURTHER, AND ALL CAN HIT WHAT IT FINDS" } },
            { { name = "PUFF QUAKE", cost = 40, damage = 20, unearth = 1.5, blurb = "HARDER, AND FORCES DIGGERS UP" },
              { name = "CAVE-IN", cost = 70, damage = 28, unearth = 2, caveIn = true,
                blurb = "CAVES TUNNELS IN ON WHAT IS DOWN THEM" } },
        } },
    -- Armor breaker: each drop strips armor, stacking, and holds its target a
    -- moment. Strongest one hop from the sprout, weaker each hop out.
    { id = "oyster", name = "OYSTER MUSHROOM", cost = 45, key = "O", hp = 30,
        range = 50, every = 1.1, damage = 5, strip = 2, stripMax = 12, regrowArmor = 0.5, hold = 0.35, shot = 0.6, reserve = 8,
        inner = 1.3, perHop = 0.15, outer = 0.55,
        blurb = "STRIPS ARMOR FROM THE TOUGHEST, STACKING. BEST BY THE SPROUT",
        role = "ARMOR BREAKER",
        about = "EACH DROP TAKES 2 ARMOR OFF THE TOUGHEST IN REACH. X1.3 ONE HOP FROM THE SPROUT, LESS EACH HOP OUT.",
        up = {
            { { name = "NEMATODE TRAP", cost = 35, hold = 0.7, blurb = "HOLDS THEM TWICE AS LONG" },
              { name = "LASSO", cost = 60, hold = 1, lift = 1.6, liftHp = 60, blurb = "LIFTS SMALL BUGS OFF THE TRAIL" } },
            { { name = "CORRODE", cost = 35, strip = 3, regrowArmor = 0.2, blurb = "STRIPS MORE, AND IT LASTS" },
              { name = "DISSOLVE", cost = 60, strip = 3, regrowArmor = 0.1, train = true,
                blurb = "SPREADS DOWN A CENTIPEDE'S TRAIN" } },
        } },
    -- Link defence: no attack. What chews, crushes or snaps one of its links is
    -- hurt, slowed and stuck, and a mite dies on it. The sap runs round any
    -- loop it is part of.
    { id = "tooth", name = "BLEEDING TOOTH", cost = 40, key = "B", hp = 35,
        sapHit = 10, bleed = 6, bleedFor = 1, sapSlow = 0.5, sapFor = 1.2, drain = 0.3, reserve = 7,
        blurb = "NO ATTACK. WHAT CUTS ITS LINKS BLEEDS. ROUND A LOOP, ALL OF IT",
        role = "LINK DEFENSE",
        about = "NO ATTACK. WHAT CHEWS OR CRUSHES ITS LINKS IS HURT AND STUCK; MITES DIE. A LOOP IT IS IN IS SAPPED ALL ROUND.",
        up = {
            { { name = "CLOTTING", cost = 35, clot = 0.25, blurb = "ITS CUT LINKS REGROW BY THEMSELVES" },
              { name = "SCAB", cost = 60, clot = 0.5, sapHit = 14, blurb = "REGROW TWICE AS FAST" } },
            { { name = "HEMOTOXIN", cost = 35, sapHit = 18, bleed = 10, blurb = "HURTS MORE" },
              { name = "THORN SAP", cost = 60, sapHit = 26, bleed = 14, bleedFor = 4, blurb = "AND THEY KEEP BLEEDING" } },
        } },
    -- Economy: no attack. Pays interest on the bank at each wave's end, more
    -- every wave its links go uncut. They run underground, where only a
    -- burrower can cut them.
    { id = "truffle", name = "TRUFFLE", cost = 60, key = "U", hp = 30,
        interest = 0.08, cap = 25, perWave = 0.03, maxBonus = 0.15,
        blurb = "NO ATTACK. PAYS INTEREST EACH WAVE. ITS LINKS RUN UNDERGROUND",
        role = "ECONOMY",
        about = "NO ATTACK. 8% OF THE BANK EACH WAVE, UP TO 25; +3% A WAVE UNCUT. ONLY DIGGERS CUT ITS LINKS.",
        up = {
            { { name = "AGED", cost = 40, interest = 0.1, cap = 35, blurb = "MORE INTEREST, HIGHER CAP" },
              { name = "BLACK DIAMOND", cost = 70, interest = 0.12, cap = 50, maxBonus = 0.2, blurb = "MORE STILL" } },
            { { name = "ROOT RUN", cost = 40, rootRun = true, blurb = "THE LINKS OF WHAT IT FEEDS RUN BURIED TOO" },
              { name = "TAPROOT", cost = 70, rootRun = true, tapCap = 1.5, tapStun = 2,
                blurb = "BURIED LINKS X1.5 FLOW. A DIGGER THAT CUTS ONE IS STUNNED" } },
        } },
    -- Support: no attack. What grows within two links of it fires faster and
    -- shakes off stuns and webs, faster still for every species round it.
    { id = "turkey", name = "TURKEY TAIL", cost = 40, key = "Y", hp = 30,
        haste = 1.1, perSpecies = 0.06, maxSpecies = 5, hops = 2, shake = 2,
        blurb = "NO ATTACK. TOWERS 2 LINKS OFF FIRE FASTER, MORE PER SPECIES",
        role = "SUPPORT",
        about = "NO ATTACK. TOWERS WITHIN 2 LINKS FIRE +10%, +6% PER SPECIES THERE (UP TO 5), AND SHAKE OFF STUNS.",
        up = {
            { { name = "MYCELIAL PUMP", cost = 35, capMul = 1.4, blurb = "PUMPS X1.4 FLOW, LIKE A WEAK RELAY" },
              { name = "CAPILLARY", cost = 60, capMul = 1.75, blurb = "X1.75: A MORTAR BESIDE IT FIRES FULL PACE" } },
            { { name = "VERSICOLOR", cost = 35, hops = 3, perSpecies = 0.08, blurb = "3 LINKS OUT, +8% PER SPECIES" },
              { name = "RAINBOW", cost = 60, hops = 3, perSpecies = 0.08, pulseLong = 1.5,
                blurb = "AND THE PULSE LASTS LONGER ON THEM" } },
        } },
}
D.TOWER = {}
for _, t in ipairs(D.TOWERS) do D.TOWER[t.id] = t end

-- Sprout seeds: the plant at the end of the trail, picked with the loadout.
-- The bean is there from the start; the rest grow on the network. `heart`,
-- `income` and `grow` scale the level's sprout, its sugar and how fast links
-- grow; `start` adds to its nutrients. Each brings mutations of its own (MUTATIONS rows with its
-- `seed`), one of which is on offer every time the network mutates.
D.SEEDS = {
    { id = "bean", name = "BEAN SPROUT", short = "BEAN",
        blurb = "AS IT COMES: NOTHING GAINED, NOTHING GIVEN UP",
        about = "THE SPROUT YOU KNOW. ITS MUTATIONS ARE ABOUT GROWING: QUICK THREADS, RICHER POCKETS, FREE LINKS." },
    { id = "oak", name = "OAK SAPLING", short = "OAK", heart = 1.5, grow = 0.75,
        blurb = "SPROUT +50% HP, BUT LINKS GROW 25% SLOWER",
        about = "TOUGH AND SLOW. IT TAKES THE HITS SO THE NETWORK CAN BE THIN. ITS MUTATIONS HARDEN IT AND THE THREADS AT ITS FOOT." },
    { id = "tomato", name = "TOMATO SEEDLING", short = "TOMATO", heart = 0.7, income = 1.1, start = 10,
        blurb = "SUGAR +10%, +10 TO START, SPROUT -30% HP",
        about = "RICH BUT SOFT. MORE TO SPEND ON EVERY WAVE, AND LESS ROOM FOR A LEAK. ITS MUTATIONS PAY MORE, OR BURST ON WHAT GETS THROUGH." },
    { id = "dandelion", name = "DANDELION", short = "DANDELION", regrow = 1,
        blurb = "KILLED, IT REGROWS ONCE AT HALF HEALTH",
        about = "A WEED: KILL IT AND IT COMES BACK, ONCE, AT HALF ITS HP, AND THE WAVE GOES ON. ITS MUTATIONS SPREAD IT ON THE WIND." },
    { id = "sunflower", name = "SUNFLOWER", short = "SUNFLOWER", sun = { hops = 2, damage = 1.15 },
        blurb = "TOWERS 2 HOPS FROM IT HIT 15% HARDER, BUT NOT AT NIGHT",
        about = "IT FACES THE SUN, AND WHAT GROWS CLOSE TO IT HITS HARDER BY DAY. AT NIGHT IT HANGS ITS HEAD. ITS MUTATIONS FEED ON THE LIGHT." },
    { id = "flytrap", name = "VENUS FLYTRAP", short = "FLYTRAP", income = 0.9,
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
    ant = { name = "WORKER ANT", hp = 16, speed = 20, armor = 0, chew = 5, chewFor = 1.0, bite = 5, carries = true,
        heart = 1, corpse = 4, blurb = "CHEWS LINKS ACROSS THE TRAIL. CARRIES OFF CORPSES", "tooth" },
    pillbug = { name = "PILLBUG", hp = 70, speed = 12, armor = 3, rolledArmor = 10, chew = 4, chewFor = 1.5, bite = 4,
        rollSpeed = 36, walkFor = 3.5, rollFor = 2.6, heart = 3, corpse = 10,
        blurb = "ROLLS AND CRUSHES ANY LINK IT CROSSES. A MAT STOPS IT", "oyster" },
    mite = { name = "MITE SWARM", hp = 4, speed = 18, armor = 0, chew = 1.6, swarm = 10, sniff = 34, bite = 1.6,
        heart = 0.34, corpse = 0.6, blurb = "MANY TINY BITES. GNAWS THE NEAREST LINK", "tooth" },
    brine = { name = "BRINE DROP", hp = 30, speed = 13, armor = 0, slide = 22, heart = 4, corpse = 0, bite = 10,
        blurb = "SLIDES DOWN YOUR HYPHAE, STERILISING. PRUNE AHEAD OF IT" },
    gnat = { name = "FUNGUS GNAT", hp = 12, speed = 17, armor = 0, fly = true, heart = 1, corpse = 1,
        blurb = "FLIES STRAIGHT AT THE SPROUT. ONLY PUFFERS AND NEEDLES REACH IT", "agaric" },
    slug = { name = "SLUG", hp = 240, speed = 6, armor = 0, noSlow = true, eat = 8, eatR = 15, bite = 8,
        heart = 4, corpse = 22, blurb = "SLOW, HUGE, CANNOT BE SLOWED. EATS FRUITING BODIES IT PASSES" },
    spider = { name = "WOLF SPIDER", hp = 55, speed = 30, armor = 1, web = 5, webR = 56, webCd = 9, bite = 6,
        heart = 2, corpse = 8, blurb = "HUNTS YOUR DEADLIEST TOWER AND WEBS IT SHUT", "turkey" },
    knight = { name = "BEETLE KNIGHT", hp = 150, speed = 9, armor = 9, chew = 6, chewFor = 2, bite = 6,
        heart = 3, corpse = 14, blurb = "HEAVY ARMOR SHRUGS OFF CHEAP HITS. NEEDLES PIERCE IT", "oyster" },

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
        heart = 2, corpse = 6, blurb = "BURROWS OFF THE TRAIL AND COMES UP BESIDE A LINK TO CUT IT", "earthstar" },
    -- A small centipede: a head and a train of segments, each its own enemy,
    -- like the Giant's. It does not cut what it crosses but wears it, `wear`
    -- a second a body for every link within `wearR`.
    centi = { name = "CENTIPEDE", hp = 34, speed = 14, armor = 1, segments = 4, gap = 5.5, seg = "centiseg",
        bite = 4, wear = 7, wearR = 4, heart = 1, corpse = 4, size = 0.9,
        blurb = "A TRAIN OF SEGMENTS. EVERY ONE GNAWS THE LINKS IT RUNS ALONG", "tooth" },
    centiseg = { name = "CENTIPEDE", short = "CENTIPEDE", segment = true, hp = 26, speed = 14, armor = 1, bite = 3,
        wear = 7, wearR = 4, heart = 0.5, corpse = 2, size = 0.8 },

    moth = { name = "NIGHT MOTH", hp = 22, speed = 15, armor = 0, fly = true, moth = true, nibble = 4, bite = 4,
        heart = 1, corpse = 3, blurb = "COMES OUT AT NIGHT. FLIES TO THE BRIGHTEST LIGHT AND EATS IT", "agaric" },

    -- Swims under a flooded trail tile, out of reach of all but an Earthstar,
    -- `swim` times as fast; on dry ground it walks and chews like an ant.
    diver = { name = "DIVING BEETLE", short = "DIVER", hp = 40, speed = 12, armor = 2, chew = 5, chewFor = 1.2, bite = 5,
        swim = 1.6, heart = 2, corpse = 8,
        blurb = "SWIMS UNDER THE FLOODED TRAIL, WHERE ONLY AN EARTHSTAR HEARS IT" },
    -- A cricket nymph's small cousin, and hungrier for what is buried: it
    -- burrows to the nearest link in reach, a Truffle's buried ones first.
    wireworm = { name = "WIREWORM", hp = 22, speed = 10, armor = 1, bite = 3,
        sinkEvery = 2, sinkFor = 0.5, reach = 90, burrow = 22, surfaceFor = 1.6, cuts = 1, buried = true,
        heart = 1, corpse = 3, size = 0.8,
        blurb = "BURROWS TO A LINK AND CUTS IT, A TRUFFLE'S BURIED ONES FIRST" },
    -- Leaves the trail for the nearest link it can smell, chews it through,
    -- and carries the piece home, slower.
    leafcutter = { name = "LEAFCUTTER ANT", short = "LEAFCUTTER", hp = 28, speed = 18, armor = 0, chew = 12, bite = 5,
        sniff = 44, gnawFor = 5, laden = 0.7, heart = 1, corpse = 4,
        blurb = "LEAVES THE TRAIL TO CUT A LINK, AND CARRIES THE PIECE OFF" },
    -- A rival fungus: it walks until it touches a link, then creeps up it
    -- towards the sprout. A tower it reaches is overgrown, its pocket moldy
    -- for `moldFor` seconds, and the link behind it is cut. Prune ahead of it.
    mold = { name = "GREEN MOLD", short = "MOLD", hp = 45, speed = 9, armor = 0, creep = 7, moldFor = 12, bite = 4,
        heart = 3, corpse = 0,
        blurb = "CREEPS UP YOUR LINKS TO THE SPROUT, OVERGROWING TOWERS. PRUNE AHEAD OF IT" },

    -- Bosses: the big bugs. They do not get tougher wave by wave; they are
    -- tuned for the wave they come on.
    queen = { name = "QUEEN ANT", boss = true, hp = 750, speed = 7, armor = 2, gnaw = 14, gnawR = 8,
        brood = 3, broodEvery = 6, bite = 25, heart = 10, corpse = 40, size = 2.6,
        blurb = "LAYS WORKERS AS SHE WALKS AND GNAWS EVERY THREAD SHE PASSES" },
    stag = { name = "STAG BEETLE", boss = true, hp = 1250, speed = 8, armor = 6, bite = 60,
        chargeEvery = 9, chargeFor = 1.5, chargeSpeed = 26, shear = 11, stun = 3, stunR = 18,
        heart = 12, corpse = 70, size = 3,
        blurb = "CHARGES. ITS JAWS SHEAR LINKS AND STUN THE TOWERS IT PASSES", "turkey" },
    dung = { name = "DUNG BEETLE", boss = true, hp = 1500, speed = 6.5, armor = 3, bite = 999,
        ball = 900, ballR = 9, ballAhead = 13, ballHeart = 20, ballCorpse = 60, rage = 1.5,
        heart = 12, corpse = 50, size = 3,
        blurb = "ITS BALL SOAKS EVERY HIT AND FLATTENS ALL IT ROLLS OVER. BREAK IT" },
    -- Under water (a flooded trail tile) it cannot be hurt or seen. Every few
    -- seconds it lunges at the nearest fruiting body it can reach that is not
    -- on high ground and drags it under; a fed Lion's Mane in reach halves its grip.
    waterbug = { name = "GIANT WATER BUG", boss = true, hp = 1500, speed = 8, armor = 4, bite = 40,
        grabEvery = 7, grabR = 44, lunge = 34, hold = 2.6, drag = 30, heart = 12, corpse = 60, size = 3,
        blurb = "LURKS UNDER THE FLOODED LANE. SURFACES TO DRAG A TOWER UNDER", "earthstar" },
    -- A head and a train of segments, each its own enemy with its own HP. Each
    -- crushes the links it crosses; break one and the one behind leads.
    centipede = { name = "GIANT CENTIPEDE", boss = true, hp = 260, speed = 11, armor = 5, segments = 11, gap = 8.5,
        seg = "centseg",
        bite = 30, crushR = 4.5, heart = 6, corpse = 14, size = 2,
        blurb = "A TRAIN OF ARMORED SEGMENTS. EACH CUTS WHAT IT CROSSES. IT SPLITS WHERE BROKEN", "truffle" },
    centseg = { name = "GIANT CENTIPEDE", boss = true, segment = true, hp = 220, speed = 11, armor = 5, bite = 20,
        crushR = 4.5, heart = 1.5, corpse = 8, size = 1.6 },
    -- The Rotting Log's boss. Every few seconds it rolls onto its back and
    -- plays dead (soft: no armor, and it takes `belly` times as much), then
    -- clicks and leaps down the trail; where it lands, links within `slamR`
    -- are cut and towers within `stunR` stunned.
    click = { name = "CLICK BEETLE", boss = true, hp = 2600, speed = 8, armor = 6, bite = 50,
        clickEvery = 7, bellyFor = 2.4, belly = 1.5, leapFor = 0.9, leapSpeed = 60, leapH = 26,
        slamR = 20, stun = 2.5, stunR = 30, heart = 12, corpse = 60, size = 2.6,
        blurb = "PLAYS DEAD ON ITS BACK, SOFT. THEN CLICKS AND LEAPS: ITS LANDING CUTS AND STUNS", "turkey" },
    -- Challenge mode's boss. Walking, it scalds the nearest tower behind it;
    -- `siege` tiles from the sprout it stops and sprays the sprout itself, and
    -- whatever stands in the way (a shelf, a tower) takes the spray instead.
    bombardier = { name = "BOMBARDIER BEETLE", boss = true, hp = 1600, speed = 9, armor = 4, bite = 50,
        sprayEvery = 6, sprayR = 44, scald = 30, siege = 3, siegeEvery = 2.5, heartSpray = 2, coverR = 7,
        heart = 12, corpse = 60, size = 2.6,
        blurb = "AT THE END OF THE TRAIL IT TURNS AND SPRAYS THE SPROUT. COVER IT", "oyster" },
    -- Every so often it stops and digs (still, and open to anything), then
    -- burrows straight across to whichever trail tile within `reach` is the
    -- most steps nearer the sprout, up to `most` and at least `save` -- through
    -- the wall to the next turn of a winding trail -- and comes up there, dazed. The tunnel stays open behind
    -- it: anything walking that comes to the first hole goes down and climbs out
    -- of the second `tunnelFor` seconds later, itself dazed for `daze`. Bosses
    -- and fliers do not use it. Killed, it takes its tunnels with it, and what
    -- is down them.
    -- The Puddle's boss. A nymph first: under a flooded tile it cannot be
    -- touched but by an Earthstar, and every few seconds it shoots out its
    -- mask of a jaw at the nearest tower. Down to `molt` of its health it
    -- climbs out, splits its skin and flies as a Dragonfly.
    naiad = { name = "DRAGONFLY NYMPH", short = "NYMPH", boss = true, hp = 1700, speed = 7.5, armor = 6, bite = 40,
        swim = 1.3, strikeEvery = 6, strikeR = 34, strike = 30, molt = 0.5, moltFor = 2.5,
        heart = 12, corpse = 30, size = 2.6,
        blurb = "UNDER WATER ONLY AN EARTHSTAR HEARS IT. AT HALF HEALTH IT HATCHES AND FLIES" },
    -- What hatches: a flier, fast, that hawks the towers it passes.
    dragonfly = { name = "DRAGONFLY", boss = true, fly = true, hp = 850, speed = 15, armor = 2, bite = 30,
        diveEvery = 4, diveR = 54, dive = 28, diveStun = 1.5, heart = 12, corpse = 40, size = 2.6,
        from = "naiad", blurb = "A BOSS ON THE WING. IT SNATCHES AT THE TOWERS IT PASSES. A FLY AGARIC DAZES IT" },
    -- The Old Stump's boss. Its plates (armor 12) grow back fast, and a
    -- needle only half pierces them; every few seconds its horn tosses the
    -- nearest tower, hurting and stunning it.
    rhino = { name = "RHINOCEROS BEETLE", short = "RHINO", boss = true, hp = 2300, speed = 6.5, armor = 12, bite = 60,
        plates = 1.5, hardPlates = 0.5, tossEvery = 7, tossR = 30, toss = 45, tossStun = 3,
        heart = 14, corpse = 70, size = 3,
        blurb = "ARMOR 12 THAT GROWS BACK. ONLY AN OYSTER STRIPS IT. ITS HORN TOSSES TOWERS" },
    -- The second challenge boss. A flier that every few seconds dives at the
    -- deadliest tower in reach and stings it still.
    hornet = { name = "HORNET", boss = true, fly = true, hp = 1700, speed = 12, armor = 3, bite = 40,
        diveEvery = 6, diveR = 90, dive = 45, diveStun = 4, deadliest = true,
        heart = 14, corpse = 50, size = 2.4,
        blurb = "CHALLENGE MODE'S FLIER. DIVES AT YOUR DEADLIEST TOWER AND STINGS IT STILL" },
    mole = { name = "MOLE CRICKET", boss = true, hp = 1500, speed = 7, armor = 5, bite = 40,
        digEvery = 10, digFor = 2.5, digs = 2, reach = 96, save = 5, most = 14, keep = 3, burrow = 26, surfaceFor = 1.2,
        tunnelFor = 3, daze = 0.8, heart = 12, corpse = 60, size = 2.6,
        blurb = "DIGS A TUNNEL AHEAD, AND THE REST FOLLOW. KILL IT AND THE TUNNEL CAVES IN", "earthstar" },
}
D.ENEMY_ORDER = { "ant", "pillbug", "mite", "gnat", "moth", "brine", "slug", "spider", "knight", "springtail",
    "cricket", "centi", "diver", "wireworm", "leafcutter", "mold",
    "queen", "stag", "dung", "click", "waterbug", "centipede", "bombardier", "mole", "naiad", "dragonfly", "rhino",
    "hornet" }

-- What the encyclopedia says of each enemy: the whole of what it does, where
-- the loadout's chip has room for one line (`blurb`).
for kind, about in pairs({
    ant = "THE COMMON WORKER. IT STOPS ON A LINK IT WALKS INTO AND CHEWS IT FOR A SECOND, ONCE PER LINK. "
        .. "IT PICKS UP A CORPSE LYING IN ITS WAY: IF IT REACHES THE SPROUT WITH IT, THE BODY IS GONE. "
        .. "KILLED, OR HIT BY SMOKE, IT DROPS IT.",
    pillbug = "PLATED AND PLODDING. AFTER 3.5S OF WALKING IT ROLLS UP FOR 2.6S: ARMOR 10, THREE TIMES AS FAST, "
        .. "AND ANY LINK IT CROSSES IS CUT OUTRIGHT. A SLIME MAT UNCURLS IT AND HOLDS IT FOR A SECOND, "
        .. "AND A SHIELDED LINK TAKES 20 DAMAGE INSTEAD OF BREAKING.",
    mite = "TEN TO A SWARM, EACH A SPECK WITH 4 HP. EACH PICKS THE NEAREST LINK IT CAN SNIFF OUT AND GNAWS IT FOR 6S, "
        .. "THEN GOES BACK TO THE MARCH. ONE SPLASH CLEARS A CLUMP. INK BLINDS THEM: THEY CANNOT PICK A THREAD.",
    gnat = "A FLIER. IT IGNORES THE TRAIL AND MAKES STRAIGHT FOR THE SPROUT, OVER MATS AND SHELVES. ONLY SPORE PUFFERS "
        .. "AND ENOKI NEEDLES CAN HIT IT. A GHOST LAMP LURES IT, AND A FED STINKHORN BAITS IT INTO CIRCLING.",
    moth = "A FLIER THAT COMES OUT AT NIGHT. IT GOES FOR THE BRIGHTEST LIGHT IT CAN SEE, A LIT GHOST LAMP OR ELSE THE "
        .. "NEAREST GLOWING TOWER, AND NIBBLES IT TO NOTHING. ONLY SPORE PUFFERS AND ENOKI NEEDLES CAN HIT IT.",
    brine = "A DROP OF SALT WATER. IT RUNS DOWN THE FIRST LINK IT TOUCHES, AWAY FROM THE SPROUT, SALTING WHAT IT PASSES, "
        .. "AND A POCKET IT REACHES IS STERILISED. PRUNE THE LINK AHEAD OF IT AND IT FALLS OFF AND FIZZLES.",
    slug = "HUGE AND PATIENT, AND NOTHING SLOWS IT BUT FROST. IT STOPS TO EAT ANY FRUITING BODY WITHIN 15 OF THE TRAIL, "
        .. "8 HP A SECOND. A MAT STILL DIGESTS IT AND INK STILL BLINDS IT.",
    spider = "FAST AND CUNNING. EVERY 9S IT LEAVES THE TRAIL FOR THE DEADLIEST TOWER WITHIN 56 AND WEBS IT SHUT FOR 5S. "
        .. "INK BLINDS IT, AND A LION'S MANE WITH PURGE CLEARS THE WEB.",
    knight = "A WALKING SHELL: ARMOR 9 TURNS MOST OF EVERY CHEAP HIT. ENOKI NEEDLES PIERCE IT, AND A CORDYCEPS BLOOM "
        .. "CAN TURN IT. IT CHEWS EVERY LINK IT WALKS INTO FOR 2S.",
    springtail = "EVERY 2.6S IT SPRINGS OFF ITS TAIL: OVER A SHELF, OFF A MAT, PAST WHATEVER WAS HOLDING IT. "
        .. "THE FIRST TIME IT COMES DOWN ON A LINK, THE LINK SNAPS.",
    cricket = "IT WALKS THE TRAIL UNTIL A LINK IS IN REACH, THEN SINKS AND BURROWS UNDER THE BOARD, WHERE NOTHING CAN "
        .. "TOUCH IT. IT COMES UP BESIDE THE LINK AND CUTS IT (A SHIELDED ONE TAKES 20), THEN SITS STILL AND SOFT FOR "
        .. "2.2S. TWICE, THEN BACK TO THE TRAIL. IT CANNOT COME UP IN WATER.",
    centi = "A HEAD AND A TRAIN OF 4 SEGMENTS, EACH ITS OWN ENEMY. IT DOES NOT CUT WHAT IT CROSSES BUT WEARS IT: "
        .. "EVERY BODY OF IT GNAWS EVERY LINK WITHIN 4 AT 7 A SECOND. A SPLASH HITS SEVERAL AT ONCE.",
    queen = "THE BROOD MOTHER. SHE LAYS 3 WORKER ANTS EVERY 6S AS SHE WALKS, AND GNAWS EVERY THREAD WITHIN 8 OF HER.",
    stag = "EVERY 9S IT CHARGES FOR 1.5S AT THREE TIMES ITS PACE. ITS JAWS SHEAR EVERY LINK IT PASSES, AND STUN "
        .. "EVERY TOWER WITHIN 18 FOR 3S.",
    dung = "IT WALKS BACKWARDS, PUSHING ITS BALL AHEAD. THE BALL SOAKS EVERY HIT UNTIL IT BREAKS (900 HP), AND "
        .. "FLATTENS EVERY LINK AND MAT IT ROLLS OVER. A BALL THAT REACHES THE SPROUT HITS IT FOR 20 MORE. "
        .. "ONCE THE BALL BREAKS, THE BEETLE WALKS X1.5 AS FAST.",
    click = "EVERY 7S IT ROLLS ON ITS BACK AND PLAYS DEAD FOR 2.4S: NO ARMOR, AND IT TAKES X1.5 DAMAGE. THEN IT CLICKS "
        .. "AND LEAPS DOWN THE TRAIL. WHERE IT LANDS, LINKS WITHIN 20 ARE CUT AND TOWERS WITHIN 30 STUNNED FOR 2.5S.",
    waterbug = "IT LURKS UNDER A FLOODED TRAIL TILE, WHERE NOTHING CAN SEE OR HURT IT. EVERY 7S IT LUNGES AT A TOWER "
        .. "WITHIN 44 THAT IS NOT ON HIGH GROUND AND DRAGS IT AT 30 A SECOND FOR 2.6S. A FED LION'S MANE TENDING THE "
        .. "TOWER HALVES ITS GRIP.",
    centipede = "A HEAD AND 11 ARMORED SEGMENTS, EACH ITS OWN ENEMY WITH ITS OWN HP, AND EVERY ONE CUTS THE LINKS IT "
        .. "CROSSES. BREAK A SEGMENT AND IT SPLITS: THE ONE BEHIND LEADS A TRAIN OF ITS OWN.",
    bombardier = "CHALLENGE MODE'S BOSS. AS IT WALKS IT SCALDS THE NEAREST TOWER EVERY 6S. THREE TILES FROM THE "
        .. "SPROUT IT STOPS AND SPRAYS THE SPROUT ITSELF, AND WHATEVER STANDS IN THE WAY, A SHELF OR A TOWER, "
        .. "TAKES THE SPRAY INSTEAD.",
    mole = "EVERY 10S IT STOPS AND DIGS, STILL AND OPEN TO ANYTHING, THEN BURROWS STRAIGHT ACROSS TO THE TRAIL FURTHER "
        .. "ON, THROUGH THE WALL TO THE NEXT TURN, AND COMES UP DAZED. THE TUNNEL STAYS OPEN, AND WALKERS THAT REACH "
        .. "THE HOLE FOLLOW IT. KILL IT AND THE TUNNEL CAVES IN, WITH WHATEVER IS DOWN IT.",
    diver = "A BEETLE WITH A BUBBLE OF AIR UNDER ITS WINGS. ON A FLOODED TRAIL TILE IT SWIMS UNDER, X1.6 AS FAST, "
        .. "AND NOTHING CAN SEE OR HURT IT BUT AN EARTHSTAR (AND WHAT A SEISMIC ONE SHOWS). ON DRY GROUND IT WALKS "
        .. "AND CHEWS EVERY LINK IT WALKS INTO.",
    wireworm = "A THIN, HARD GRUB. EVERY 2S IT LOOKS FOR A LINK WITHIN 90, A TRUFFLE'S BURIED ONES FIRST, BURROWS "
        .. "TO IT UNDER THE BOARD AND CUTS IT, THEN SITS SOFT FOR 1.6S AND GOES BACK TO THE TRAIL. AN EARTHSTAR HEARS "
        .. "IT UNDERGROUND.",
    leafcutter = "AN ANT WITH A JOB. IT LEAVES THE TRAIL FOR THE NEAREST LINK WITHIN 44 AND CHEWS IT AT 12 A SECOND "
        .. "UNTIL IT IS CUT, THEN CARRIES THE PIECE OFF TO THE SPROUT, SLOWER. A BLEEDING TOOTH'S SAP HURTS IT, "
        .. "AND INK BLINDS IT.",
    mold = "A RIVAL FUNGUS. IT WALKS UNTIL IT TOUCHES A LINK, THEN CREEPS UP IT TOWARDS THE SPROUT. A TOWER IT "
        .. "REACHES IS OVERGROWN AND GONE, NOTHING GROWS IN THAT POCKET FOR 12S, AND THE LINK BEHIND IT IS CUT. "
        .. "PRUNE THE LINK AHEAD OF IT AND IT DRIES UP, OR KILL IT ON THE THREAD.",
    naiad = "THE PUDDLE'S BOSS, A NYMPH THE SIZE OF A STAG BEETLE. UNDER A FLOODED TILE ONLY AN EARTHSTAR CAN HURT "
        .. "IT. EVERY 6S IT SHOOTS OUT ITS JAW AT THE NEAREST TOWER WITHIN 34 FOR 30. AT HALF ITS HEALTH IT "
        .. "CLIMBS OUT, SPLITS ITS SKIN AND FLIES ON AS A DRAGONFLY.",
    dragonfly = "WHAT THE NYMPH BECOMES: A FLIER, FAST, STRAIGHT FOR THE SPROUT. EVERY 4S IT SNATCHES AT A TOWER "
        .. "WITHIN 54, 28 AND A STUN OF 1.5S. ONLY WHAT HITS FLIERS REACHES IT, AND A FLY AGARIC DAZES IT.",
    rhino = "THE OLD STUMP'S BOSS. ARMOR 12, AND WHAT AN OYSTER STRIPS GROWS BACK THREE TIMES AS FAST; A NEEDLE "
        .. "PIERCES ONLY HALF OF IT. EVERY 7S ITS HORN TOSSES THE NEAREST TOWER WITHIN 30: 45, AND STUNNED FOR 3S.",
    hornet = "CHALLENGE MODE'S SECOND BOSS, OPEN ONCE THE COMPOST HEAP IS WON. A FLIER: EVERY 6S IT DIVES AT THE "
        .. "DEADLIEST TOWER WITHIN 90 AND STINGS IT FOR 45 AND A STUN OF 4S, THEN GOES ON FOR THE SPROUT.",
}) do D.ENEMIES[kind].about = about end

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
    diver = { "earthstar", "puffer" },
    wireworm = { "earthstar", "mane", "tooth" },
    leafcutter = { "tooth", "puffer", "inky" },
    mold = { "needle", "puffer", "mane" },
    naiad = { "earthstar", "agaric" },
    dragonfly = { "agaric", "needle" },
    rhino = { "oyster", "mortar" },
    hornet = { "agaric", "turkey", "mane" },
}

-- Weather, per wave: a wave row's `weather` names one of these, and the
-- forecast shows it before the wave starts. `flow` scales every link's flow
-- cap; `wash` is reserve a second rain takes off a tower on a low pocket (a
-- leaf, a lily pad); `clouds` is how much faster lingering clouds and ink wash
-- out; `wither` how much faster an unfed mat dries up; `lamp` and `range`
-- scale a Ghost Lamp's pull and every tower's reach; `pace` scales how fast
-- everything fires and moves, `grow` how fast links grow and regrow.
-- The first levels bring them one at a time, so each is met on its own: the
-- Crack only rain, the Flowerpot night, the Shed Floor drought and the
-- Rotting Log frost; from there on any of them comes.
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

-- Spores for the Spore Bank: a few a wave cleared, more for a win, more
-- again for a level's first win.
D.SPORES = { wave = 6, win = 12, first = 20 }

-- The encyclopedia's glossary: every status and word of the game's that wants
-- explaining. Wherever one of its `forms` is written in the encyclopedia it
-- gets a footnote with the `about`; a `skip` phrase is the same letters
-- meaning something else ("HUGE SLOW BLASTS" are not a slow), left alone.
-- Longer forms are matched first, so CUT OFF is not a CUT.
D.GLOSSARY = {
    { name = "STUNNED", forms = { "STUN", "STUNS", "STUNNED" },
        about = "DOES NOTHING: AN ENEMY STOPS WALKING, CHEWING AND WEBBING, A TOWER STOPS FIRING. IT STILL TAKES "
            .. "DAMAGE. THE LONGEST STUN WINS: THEY DO NOT ADD UP." },
    { name = "MARKED", forms = { "MARK", "MARKS", "MARKED" },
        about = "TAKES +25% DAMAGE FROM EVERYTHING (+45% FROM HUNTER'S MARK) FOR 4S, REFRESHED BY EVERY NEEDLE HIT." },
    { name = "STENCH", forms = { "STENCH", "REEK" },
        about = "INSIDE A STINKHORN'S RANGE OR ALONG ITS LINKS: SLOWED TO X0.75 OR LESS, AND NOW AND THEN TRIPPED "
            .. "FOR 0.5S. FLIERS FLY OVER IT, AND BOSSES NEVER TRIP." },
    { name = "PANIC", forms = { "PANIC", "FLEE", "FLEES" },
        about = "TURNS ROUND AND WALKS BACK THE WAY IT CAME FOR 1.2S (2S WITH TERROR), AND STOPS CHEWING. "
            .. "NOT BOSSES, BRINE OR A CENTIPEDE'S TRAIN." },
    { name = "SLOWED", forms = { "SLOW", "SLOWS", "SLOWED" },
        skip = { "SLOW BLASTS", "RUN, SLOW", "SLOW, HUGE", "TOUGH AND SLOW" },
        about = "MOVES SLOWER. SLOWS MULTIPLY: AN ANT IN INK, IN STENCH AND ON A MAT GETS ALL THREE. THE SLUG "
            .. "IGNORES EVERY SLOW BUT FROST." },
    { name = "ARMOR", forms = { "ARMOR", "ARMORED" },
        about = "TAKEN OFF EVERY HIT, BUT AT LEAST 15% OF A HIT ALWAYS GETS THROUGH: MANY SMALL HITS ARE WASTED "
            .. "ON IT. A NEEDLE PIERCES IT." },
    { name = "PIERCE", forms = { "PIERCE", "PIERCES" },
        about = "AN ENOKI NEEDLE'S SHOT IGNORES ARMOR." },
    { name = "FLIER", forms = { "FLIER", "FLIERS" },
        about = "FLIES OVER THE BOARD STRAIGHT FOR THE SPROUT: NO TRAIL, NO MATS, NO SHELVES. ONLY SPORE PUFFERS "
            .. "AND ENOKI NEEDLES CAN HIT IT." },
    { name = "BOSS", forms = { "BOSS", "BOSSES" },
        about = "A BIG BUG, THREE ON EVERY LEVEL. IT DOES NOT GET TOUGHER WAVE BY WAVE, AND IT CANNOT BE TRIPPED, "
            .. "PANICKED, LURED OR INFECTED." },
    { name = "CHEWING", forms = { "CHEW", "CHEWS", "CHEWING", "CHEWED", "GNAW", "GNAWS", "GNAWING" },
        about = "AN ENEMY ON A LINK WEARS IT DOWN: A LINK HAS 40 HP, AND AT 0 IT IS CUT. A SHELF IN ITS WAY IS "
            .. "CHEWED THROUGH THE SAME WAY." },
    { name = "CUT OFF", forms = { "CUT OFF" },
        about = "NO LIVING PATH TO THE SPROUT: A TOWER RUNS ON ITS RESERVE, CANNOT REFILL AND COUNTS AS STARVED. "
            .. "RECONNECT IT." },
    { name = "CUT", forms = { "CUT", "CUTS", "SHEAR", "SHEARS", "SNAPS" },
        about = "A CUT LINK CARRIES NOTHING, AND WHATEVER WAS BEYOND IT IS CUT OFF UNTIL IT REGROWS." },
    { name = "STARVED", forms = { "STARVED", "STARVE" },
        about = "CUT OFF, OR ITS RESERVE BELOW 30%: A SHOOTER FIRES AT HALF PACE. DRAWN ONE STEP DARKER." },
    { name = "DORMANT", forms = { "DORMANT" },
        about = "RESERVE BELOW ONE SHOT, OR A RELAY NOT CONNECTED: IT DOES NOTHING AT ALL. A LAMP GOES DARK, A "
            .. "STINKHORN'S FLIES LEAVE. FEED IT." },
    { name = "RESERVE", forms = { "RESERVE" },
        about = "WHAT A TOWER HOLDS. EACH SHOT SPENDS SOME, AND A CONNECTED TOWER REFILLS FROM THE SPROUT AS FAST "
            .. "AS ITS PATH CARRIES." },
    { name = "FLOW", forms = { "FLOW" },
        about = "WHAT A LINK CARRIES: 3 NUTRIENTS A SECOND, X2 OUT OF A RELAY, X1.5 IN RAIN, X0.7 IN DROUGHT." },
    { name = "THIRSTY", forms = { "THIRSTY" },
        about = "A PUFFBALL MORTAR WHOSE PATH CARRIES LESS THAN 5 A SECOND FIRES AT HALF PACE. FEED IT THROUGH "
            .. "A RELAY." },
    { name = "WEBBED", forms = { "WEB", "WEBS", "WEBBED" },
        about = "A TOWER UNDER A WOLF SPIDER'S WEB CANNOT FIRE FOR 5S. A LION'S MANE WITH PURGE CLEARS IT, AND "
            .. "SANCTUARY KEEPS IT OFF." },
    { name = "INKED", forms = { "INK", "INKED", "BLIND", "BLINDS" },
        about = "IN AN INKY CAP'S POOL: SLOWED TO X0.7 OR LESS, AND BLIND. IT CANNOT START CHEWING A LINK, STOPS "
            .. "ONE IT IS CHEWING, AND A SPIDER CANNOT WEB. A POOL LASTS 5S, HALF THAT IN RAIN." },
    { name = "LURED", forms = { "LURE", "LURES", "LURED", "DECOY" },
        about = "A WALKER OR FLIER IN A LIT GHOST LAMP'S GLOW LEAVES THE TRAIL AND CHEWS THE LAMP FOR 5S, OR UNTIL "
            .. "IT GOES OUT. ONCE PER ENEMY. NEVER BOSSES, BRINE, MITES OR HOSTS." },
    { name = "BAITED", forms = { "BAIT", "BAITS", "BAITED" },
        about = "A GNAT OR MOTH WITHIN 70 OF A FED STINKHORN FLIES TO IT AND CIRCLES IT FOR 6S INSTEAD OF GOING "
            .. "FOR THE SPROUT. ONCE PER FLIER." },
    { name = "INFECTED", forms = { "INFECT", "INFECTS", "INFECTED", "HOST", "HOSTS" },
        about = "A CORDYCEPS HOST WALKS BACK THE WAY IT CAME, BITING EVERY WALKER NEAR IT, AND TOWERS LEAVE IT "
            .. "BE. WHEN THE HOLD RUNS OUT IT DIES AND FRUITS. NOT FLIERS, BOSSES, BRINE OR A CENTIPEDE'S TRAIN." },
    { name = "SALTED", forms = { "SALT", "SALTED", "SALTING", "STERILISING", "STERILISED" },
        about = "A LINK A BRINE DROP RAN DOWN IS CUT FOR GOOD: IT NEVER REGROWS, SO PRUNE IT. A POCKET IT REACHES "
            .. "LOSES ITS TOWER, AND NOTHING GROWS THERE FOR 12S." },
    { name = "SHIELDED", forms = { "SHIELD", "SHIELDS", "SHIELDED" },
        about = "A LINK WITHIN 30 OF A SHELF FUNGUS TAKES A THIRD OF THE CHEWING, AND A CRUSH DOES IT 20 DAMAGE "
            .. "INSTEAD OF CUTTING IT." },
    { name = "REGROW", forms = { "REGROW", "REGROWS", "REGROWTH" },
        about = "A CUT LINK GROWS BACK: CLICK IT (40% OF ITS COST, 3S), REGROW THEM ALL AT ONCE, OR LET A LION'S "
            .. "MANE DO IT. A SALTED ONE NEVER DOES." },
    { name = "PRUNE", forms = { "PRUNE", "PRUNED" },
        about = "THE PRUNE TOOL TAKES A LINK AWAY (HALF ITS COST BACK), OR SELLS A TOWER FOR 60% OF WHAT WAS SPENT "
            .. "ON IT." },
    { name = "HOP", forms = { "HOP", "HOPS" }, skip = { "HOPS OVER" },
        about = "ONE LINK ALONG THE NETWORK. HOPS OUT ARE COUNTED FROM THE SPROUT." },
    { name = "DEAD END", forms = { "DEAD END" },
        about = "A POCKET WITH ONLY ONE LINK: THE TIP OF A BRANCH." },
    { name = "HIGH GROUND", forms = { "HIGH GROUND" },
        about = "A RAISED POCKET. A MORTAR THERE HAS NO MIN RANGE AND +20% RANGE, AND A GIANT WATER BUG CANNOT "
            .. "GRAB WHAT GROWS ON IT." },
    { name = "MIN RANGE", forms = { "MIN RANGE" },
        about = "A MORTAR CANNOT HIT ANYTHING CLOSER TO IT THAN 22." },
    { name = "FAIRY RING", forms = { "FAIRY RING", "RING", "RINGS" },
        about = "FOUR OR MORE FED POCKETS LINKED IN A LOOP (THREE ON THE ROTTING LOG). TOWERS ON IT HIT X1.25, AND "
            .. "ENEMIES INSIDE IT WADE AT X0.7." },
    { name = "SPORE PULSE", forms = { "SPORE PULSE", "PULSE", "BOOSTED" },
        about = "SENT TO A POCKET EVERY 45S: THE TOWERS ON ITS PATH FROM THE SPROUT FIRE TWICE AS OFTEN FOR X1.5 "
            .. "DAMAGE FOR 6S." },
    { name = "POISON", forms = { "POISON", "TOXIN" },
        about = "A LINGERING SPORE CLOUD KEEPS HURTING WHATEVER STANDS IN IT, EVERY SECOND IT HANGS THERE." },
    { name = "CORPSE", forms = { "CORPSE", "CORPSES", "BODY", "BODIES" },
        about = "WHAT A DEAD ENEMY LEAVES. AN INKY CAP DRINKS IT FOR NUTRIENTS, AND A WORKER ANT CAN CARRY IT OFF." },
    { name = "NUTRIENTS", forms = { "NUTRIENTS", "SUGAR" },
        about = "WHAT A RUN IS SPENT IN. THE SPROUT MAKES THEM WHILE A WAVE IS ON, EVERY CLEARED WAVE PAYS MORE, "
            .. "AND BODIES DRUNK ADD TO THEM." },
    { name = "SPORES", forms = { "SPORES" },
        about = "KEPT IN THE SPORE BANK BETWEEN RUNS, EVEN WHEN THE SPROUT FALLS: " .. D.SPORES.wave
            .. " FOR EVERY WAVE CLEARED, " .. D.SPORES.win .. " MORE FOR A WIN AND " .. D.SPORES.first
            .. " MORE AGAIN FOR A LEVEL'S FIRST. THEY GROW THE NETWORK: NEW SPECIES, SEEDS, THE SPORE PULSE." },
    { name = "MUTATION", forms = { "MUTATION", "MUTATIONS" },
        about = "AFTER SOME WAVES THE NETWORK MUTATES: PICK ONE OF THREE CHANGES FOR THE REST OF THE RUN. A SEED "
            .. "BRINGS SOME OF ITS OWN." },
    { name = "RAIN", forms = { "RAIN" }, about = D.WEATHER.rain.blurb .. "." },
    { name = "DROUGHT", forms = { "DROUGHT" }, about = D.WEATHER.drought.blurb .. "." },
    { name = "NIGHT", forms = { "NIGHT" }, about = D.WEATHER.night.blurb .. "." },
    { name = "FROST", forms = { "FROST" }, about = D.WEATHER.frost.blurb .. "." },
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
    { { "slug", 2, 10, 1, 0 }, { "mite", 2, 7, 2, 3 }, { "moth", 4, 2, 1, 4 }, { "ant", 10, 1, 1, 6 } },
    { { "spider", 3, 5, 2, 0 }, { "ant", 10, 1, 1, 2 }, { "pillbug", 2, 5, 1, 8 }, { "gnat", 5, 1.2, 2, 10 } },
    { weather = "rain", { "knight", 3, 4, 1, 0 }, { "brine", 2, 8, 2, 3 }, { "gnat", 6, 1, 1, 6 }, { "ant", 10, 0.9, 2, 8 } },
    { { "knight", 2, 6, 1, 0 }, { "stag", 1, 1, 2, 3 }, { "ant", 12, 1, 1, 6 } },
    { { "slug", 3, 7, 2, 0 }, { "spider", 4, 4, 1, 2 }, { "mite", 3, 6, 2, 6 }, { "ant", 12, 0.9, 1, 10 } },
    { weather = "rain", { "knight", 5, 3, 1, 0 }, { "pillbug", 4, 4, 2, 0 }, { "gnat", 8, 0.8, 2, 4 }, { "brine", 2, 9, 1, 6 } },
    { { "spider", 5, 3, 2, 0 }, { "slug", 3, 6, 1, 2 }, { "mite", 4, 5, 1, 6 }, { "brine", 3, 7, 2, 8 },
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
    { { "mole", 1, 1, 1, 0, MID }, { "spider", 2, 5, 1, 2 }, { "gnat", 5, 1.2, 1, 6 }, { "ant", 12, 0.9, 1, 10 },
        { "ant", 6, 1, 2, 10 } },
    { weather = "rain", { "knight", 2, 5, 1, 0 }, { "brine", 2, 7, 1, 3 }, { "pillbug", 3, 4, 2, 4 }, { "ant", 10, 0.9, 1, 8 } },
    { weather = "rain", { "pillbug", 4, 3, 1, 0 }, { "slug", 2, 7, 1, 2 }, { "mite", 3, 5, 2, 4 }, { "gnat", 6, 1, 1, 8 } },
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
    { { "pillbug", 4, 3, 1, 0 }, { "knight", 2, 5, 2, 2 }, { "springtail", 10, 0.5, 1, 6 }, { "brine", 2, 8, 2, 6 } },
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

-- The Puddle: two trails that wade the south shore, where Diving Beetles
-- swim under. Droughts dry the ford across the middle for the top trail.
-- The Dragonfly Nymph comes last, and hatches.
local PUDDLE = {
    { { "ant", 8, 1.4, 1, 0 }, { "diver", 2, 4, 2, 6 } },
    { weather = "rain", { "ant", 8, 1.3, 1, 0 }, { "diver", 3, 3, 2, 4 }, { "gnat", 3, 1.5, 1, 8 } },
    { weather = "drought", { "ant", 10, 1.1, 1, 0 }, { "pillbug", 1, 1, 1, 4 }, { "diver", 3, 2.5, 2, 6 } },
    { weather = "night", { "moth", 5, 1.6, 1, 0 }, { "diver", 5, 2, 2, 2 }, { "brine", 1, 1, 1, 6 }, { "ant", 8, 1, 2, 8 } },
    { { "ant", 10, 1, 2, 0 }, { "queen", 1, 1, 1, 4, MID }, { "diver", 4, 2, 2, 8 }, { "gnat", 5, 1.2, 1, 10 } },
    { weather = "rain", { "slug", 2, 8, 2, 0 }, { "brine", 2, 6, 1, 2 }, { "diver", 6, 1.6, 2, 4 }, { "cricket", 2, 5, 1, 8 } },
    { weather = "drought", { "knight", 2, 5, 1, 0 }, { "spider", 3, 4, 1, 3 }, { "ant", 12, 0.9, 2, 5 }, { "gnat", 6, 1, 1, 8 } },
    { weather = "night", { "moth", 8, 1.2, 1, 0 }, { "diver", 6, 1.5, 2, 2 }, { "slug", 2, 7, 2, 6 }, { "mite", 2, 6, 1, 8 } },
    { weather = "rain", { "diver", 6, 1.5, 2, 0 }, { "waterbug", 1, 1, 2, 3, 0.25 }, { "ant", 12, 0.9, 1, 6 },
        { "brine", 2, 7, 1, 10 } },
    { weather = "frost", { "pillbug", 4, 3, 1, 0 }, { "knight", 3, 5, 2, 2 }, { "diver", 6, 1.4, 2, 6 }, { "gnat", 8, 0.9, 1, 8 } },
    { weather = "drought", { "spider", 4, 4, 1, 0 }, { "knight", 4, 4, 1, 3 }, { "cricket", 3, 4, 2, 5 }, { "ant", 16, 0.7, 1, 8 },
        { "diver", 4, 2, 2, 10 } },
    { weather = "night", { "moth", 12, 0.9, 1, 0 }, { "slug", 3, 6, 2, 2 }, { "diver", 8, 1.2, 2, 4 }, { "brine", 3, 6, 1, 8 } },
    { weather = "rain", { "knight", 5, 3, 2, 0 }, { "diver", 10, 1, 2, 2 }, { "gnat", 12, 0.7, 1, 4 }, { "ant", 18, 0.6, 1, 8 } },
    { { "ant", 14, 0.8, 1, 0 }, { "naiad", 1, 1, 2, 4 }, { "diver", 8, 1.2, 2, 8 }, { "gnat", 10, 0.8, 1, 12 },
        { "knight", 3, 5, 1, 14 } },
}

-- The Old Stump: four short trails into the middle, and shells down all of
-- them. The Rhinoceros Beetle comes last.
local STUMP = {
    { { "ant", 6, 1.4, 1, 0 }, { "ant", 6, 1.4, 3, 3 } },
    { { "ant", 6, 1.3, 2, 0 }, { "ant", 6, 1.3, 4, 2 }, { "pillbug", 2, 4, 1, 6 } },
    { { "knight", 2, 5, 1, 0 }, { "ant", 8, 1.1, 3, 2 }, { "pillbug", 2, 4, 2, 6 }, { "gnat", 4, 1.4, 4, 8 } },
    { weather = "rain", { "springtail", 6, 1, 2, 0 }, { "knight", 2, 5, 4, 2 }, { "ant", 10, 1, 1, 4 }, { "brine", 1, 1, 3, 8 } },
    { { "knight", 2, 5, 3, 0 }, { "ant", 10, 1, 2, 3 }, { "spider", 2, 5, 4, 8 } },
    { weather = "night", { "moth", 6, 1.4, 2, 0 }, { "stag", 1, 1, 1, 3, 0.25 }, { "centi", 2, 6, 3, 4 }, { "ant", 10, 1, 4, 8 } },
    { weather = "drought", { "pillbug", 4, 3, 1, 0 }, { "knight", 3, 4, 3, 2 }, { "mite", 2, 6, 2, 4 }, { "springtail", 6, 0.8, 4, 8 } },
    { weather = "frost", { "knight", 4, 3, 2, 0 }, { "slug", 2, 8, 4, 2 }, { "spider", 3, 4, 1, 4 }, { "gnat", 8, 1, 3, 6 } },
    { { "knight", 3, 4, 4, 0 }, { "click", 1, 1, 2, 3, 0.25 }, { "ant", 12, 0.9, 1, 6 }, { "centi", 2, 6, 3, 8 } },
    { weather = "rain", { "knight", 5, 3, 1, 0 }, { "pillbug", 4, 3, 3, 2 }, { "brine", 2, 7, 2, 4 }, { "springtail", 8, 0.7, 4, 8 } },
    { weather = "night", { "spider", 4, 4, 2, 0 }, { "moth", 10, 1, 4, 2 }, { "knight", 4, 4, 3, 4 }, { "centi", 3, 5, 1, 8 } },
    { weather = "drought", { "knight", 6, 2.5, 4, 0 }, { "pillbug", 5, 3, 2, 2 }, { "mite", 3, 5, 1, 4 }, { "ant", 16, 0.7, 3, 8 } },
    { weather = "frost", { "knight", 6, 2.5, 1, 0 }, { "slug", 3, 6, 3, 2 }, { "springtail", 10, 0.6, 2, 4 }, { "gnat", 12, 0.7, 4, 6 },
        { "centi", 3, 4, 2, 10 } },
    { { "ant", 14, 0.8, 2, 0 }, { "rhino", 1, 1, 3, 4 }, { "knight", 5, 3, 1, 8 }, { "pillbug", 4, 3, 4, 10 },
        { "springtail", 8, 0.7, 2, 14 } },
}

-- The Compost Heap: three trails into one lane, and everything that eats the
-- network rather than the sprout: mold, leafcutters, wireworms. The Dung
-- Beetle comes last.
local COMPOST = {
    { { "ant", 8, 1.3, 1, 0 }, { "leafcutter", 3, 3, 2, 4 } },
    { { "leafcutter", 5, 2, 1, 0 }, { "ant", 8, 1.2, 3, 2 }, { "mite", 1, 1, 2, 6 } },
    { weather = "rain", { "mold", 2, 6, 2, 0 }, { "ant", 10, 1.1, 1, 2 }, { "leafcutter", 4, 2, 3, 5 } },
    { { "wireworm", 4, 2, 1, 0 }, { "slug", 1, 1, 2, 2 }, { "ant", 10, 1, 3, 4 }, { "mite", 2, 6, 1, 8 } },
    { weather = "night", { "leafcutter", 6, 1.5, 2, 0 }, { "mole", 1, 1, 1, 3, MID }, { "moth", 5, 1.6, 3, 6 }, { "ant", 10, 1, 2, 8 } },
    { weather = "rain", { "mold", 3, 5, 1, 0 }, { "wireworm", 5, 1.8, 3, 2 }, { "slug", 2, 8, 2, 4 }, { "ant", 12, 0.9, 1, 8 } },
    { weather = "drought", { "leafcutter", 8, 1.2, 1, 0 }, { "centi", 2, 6, 3, 2 }, { "mite", 3, 5, 2, 4 }, { "spider", 2, 5, 1, 8 } },
    { weather = "night", { "slug", 3, 6, 2, 0 }, { "moth", 8, 1.2, 1, 2 }, { "wireworm", 6, 1.5, 3, 4 }, { "mold", 2, 6, 2, 8 } },
    { { "knight", 3, 4, 1, 0 }, { "leafcutter", 8, 1.1, 2, 2 }, { "mite", 3, 5, 3, 4 }, { "gnat", 8, 1, 1, 8 } },
    { weather = "rain", { "mold", 4, 4, 3, 0 }, { "centipede", 1, 1, 1, 3, MID }, { "ant", 12, 0.9, 2, 6 },
        { "wireworm", 5, 1.6, 1, 8 } },
    { weather = "frost", { "slug", 4, 5, 1, 0 }, { "pillbug", 4, 3, 3, 2 }, { "leafcutter", 10, 0.9, 2, 4 }, { "mite", 3, 4, 1, 8 } },
    { weather = "night", { "spider", 4, 4, 2, 0 }, { "moth", 10, 1, 3, 2 }, { "wireworm", 8, 1.2, 1, 4 }, { "mold", 3, 5, 2, 8 } },
    { weather = "drought", { "knight", 5, 3, 1, 0 }, { "leafcutter", 12, 0.8, 3, 2 }, { "centi", 3, 5, 2, 4 }, { "mite", 4, 4, 1, 8 } },
    { weather = "rain", { "mold", 5, 3.5, 2, 0 }, { "slug", 4, 5, 3, 2 }, { "wireworm", 10, 1, 1, 4 }, { "ant", 18, 0.6, 2, 6 },
        { "gnat", 10, 0.8, 3, 10 } },
    { { "ant", 16, 0.7, 1, 0 }, { "dung", 1, 1, 2, 4 }, { "leafcutter", 10, 1, 3, 8 }, { "mold", 4, 4, 1, 10 },
        { "wireworm", 8, 1.2, 2, 14 } },
}

-- The levels, in the order they open: each is won to open the next. `map`
-- names a map in src/world.lua. Species come as the waves are cleared on
-- every level (see D.unlockAt); `unlock`, if given, overrides a species'
-- wave there. A first win opens what on the network waits on it (its rows'
-- `won`). `loadout` is the species brought the first time it is played,
-- before the player has picked their own. `growth` is how much tougher each wave's enemies are than the
-- last's, if not HP_GROWTH. `ringNodes` is how few fed nodes close a Fairy
-- Ring there, if not RING.nodes. They come in the design doc's order; the
-- Crack is its first level and has the three bosses the later ones each bring.
D.LEVELS = {
    { id = "crack", name = "THE CRACK", map = "crack", waves = CRACK, start = 110, heart = 20, growth = 0.06,
        mutateAfter = { [3] = true, [5] = true, [8] = true, [10] = true, [12] = true },
        loadout = { "puffer", "needle", "mat", "mane", "relay", "mortar" },
        idea = "A SIDEWALK CRACK. LEARN THE NETWORK", boss = "QUEEN, STAG, DUNG BEETLE" },
    { id = "flowerpot", name = "THE FLOWERPOT", map = "flowerpot", waves = FLOWERPOT, start = 130, heart = 20,
        growth = 0.42,
        mutateAfter = { [2] = true, [4] = true, [7] = true, [9] = true },
        loadout = { "puffer", "needle", "mat", "mane", "relay", "mortar" },
        idea = "A CRACKED POT. CUT AND REGROW, AND WATCH THE HOLE", boss = "DUNG, MOLE, QUEEN ANT" },
    { id = "shed", name = "THE SHED FLOOR", map = "shed", waves = SHED, start = 160, heart = 23, growth = 0.08,
        mutateAfter = { [3] = true, [5] = true, [8] = true, [10] = true, [12] = true },
        loadout = { "puffer", "needle", "mat", "mane", "shelf", "stink" },
        idea = "BOARDS AND LEGO. HOLD THE CHOKEPOINT", boss = "DUNG, QUEEN, STAG BEETLE" },
    { id = "log", name = "THE ROTTING LOG", map = "log", waves = LOG, start = 130, heart = 20, growth = 0.2,
        ringNodes = 3,
        mutateAfter = { [2] = true, [4] = true, [7] = true, [9] = true, [11] = true },
        loadout = { "puffer", "needle", "mane", "lamp", "inky", "mortar" },
        idea = "DARK AND DAMP. THREE NODES CLOSE A RING", boss = "QUEEN, MOLE, CLICK BEETLE" },
    { id = "pond", name = "THE POND EDGE", map = "pond", waves = POND, start = 150, heart = 20, growth = 0.08,
        mutateAfter = { [2] = true, [4] = true, [7] = true, [9] = true },
        loadout = { "puffer", "needle", "mat", "mane", "stink", "lamp" },
        idea = "WATER AND REEDS. BUILD ON HIGH GROUND", boss = "QUEEN, STAG, GIANT WATER BUG" },
    { id = "lawn", name = "THE LAWN", map = "lawn", waves = LAWN, start = 140, heart = 20, growth = 0.2,
        mutateAfter = { [3] = true, [5] = true, [8] = true, [10] = true, [12] = true },
        loadout = { "puffer", "needle", "mat", "mane", "mortar", "stink" },
        idea = "OPEN GRASS, THREE GATES. EVERYTHING AT ONCE", boss = "QUEEN, STAG, GIANT CENTIPEDE" },
    { id = "puddle", name = "THE PUDDLE", map = "puddle", waves = PUDDLE, start = 160, heart = 22, growth = 0.08,
        mutateAfter = { [2] = true, [4] = true, [7] = true, [9] = true, [11] = true },
        loadout = { "puffer", "needle", "mat", "mane", "earthstar", "agaric" },
        idea = "A RAIN PUDDLE. DROUGHT DRIES A SHORTCUT", boss = "QUEEN, WATER BUG, DRAGONFLY" },
    { id = "stump", name = "THE OLD STUMP", map = "stump", waves = STUMP, start = 165, heart = 26, growth = 0.285,
        mutateAfter = { [2] = true, [4] = true, [7] = true, [9] = true, [11] = true },
        loadout = { "puffer", "needle", "mat", "mane", "oyster", "mortar" },
        idea = "THE SPROUT IN THE MIDDLE, FOUR WAYS IN", boss = "STAG, CLICK, RHINOCEROS BEETLE" },
    { id = "compost", name = "THE COMPOST HEAP", map = "compost", waves = COMPOST, start = 140, heart = 20, growth = 0.5,
        mutateAfter = { [3] = true, [5] = true, [8] = true, [10] = true, [12] = true },
        loadout = { "puffer", "needle", "mane", "inky", "tooth", "mortar" },
        idea = "ROT AND RICHES. WHAT EATS THE NETWORK", boss = "MOLE, CENTIPEDE, DUNG BEETLE" },
}
D.LEVEL = {}
for _, l in ipairs(D.LEVELS) do D.LEVEL[l.id] = l end

-- The weathers a level's own waves bring, in the order D.WEATHER_ORDER has
-- them: all endless shuffles among, so a level never brings one before its time.
D.WEATHER_ORDER = { "rain", "night", "drought", "frost" }
function D.weathersOf(level)
    local has = {}
    for _, w in ipairs(level.waves) do if w.weather then has[w.weather] = true end end
    local list = {}
    for _, id in ipairs(D.WEATHER_ORDER) do if has[id] then list[#list + 1] = id end end
    return list
end

-- Challenge mode: any level with a last wave added, a boss of its own in it.
-- Each opens once its `won` level is won: the Bombardier Beetle with the
-- Lawn, the Hornet with the Compost Heap.
D.CHALLENGES = {
    { id = "bombardier", name = "BOMBARDIER", won = "lawn", blurb = "A LAST WAVE ON ANY LEVEL: THE BOMBARDIER BEETLE",
        wave = { weather = "night", { "bombardier", 1, 1, 1, 0 }, { "knight", 4, 3, 2, 3 }, { "moth", 8, 1, 2, 5 },
            { "spider", 4, 4, 1, 8 }, { "ant", 20, 0.6, 2, 10 } } },
    { id = "hornet", name = "HORNET", won = "compost", blurb = "A LAST WAVE ON ANY LEVEL: THE HORNET",
        wave = { { "hornet", 1, 1, 1, 0 }, { "gnat", 12, 0.7, 2, 3 }, { "knight", 4, 3, 1, 5 }, { "spider", 4, 4, 2, 8 },
            { "moth", 6, 1, 1, 10 }, { "ant", 20, 0.6, 2, 12 } } },
}
D.CHALLENGE = {}
for _, c in ipairs(D.CHALLENGES) do D.CHALLENGE[c.id] = c end

-- The loadout: how many species a run brings, picked before a level from all
-- of them. The rest stay home, off the toolbar. Hyphae, prune and the pulse
-- always come. A new network brings LOADOUT_START; its `slots` nodes make
-- room for more, up to LOADOUT on a full one.
D.LOADOUT, D.LOADOUT_START = 8, 4

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

--- the network --------------------------------------------------------------------------

-- What the Spore Bank pays for: a web of nodes spreading out from the sprout,
-- each bought a rank at a time with spores, and each only once the one it
-- grows from (`at`) has a rank. Everything above is the network fully grown:
-- a node's last rank brings its number up to what is written there, and the
-- ranks before it to `from` of the way, so a new player starts with less of
-- everything and one species, and a full network plays exactly the game the
-- rest of this file tunes. src/network.lua reads it.
--
--   species = id          the species can be brought (one rank)
--   seed = id             the seed can be planted (one rank)
--   tower = id, stats     those numbers of the species, `from` at none
--   up = { id, branch }   an upgrade branch: rank 1 its first tier, rank 2 both
--   world = key           one of the network's own numbers (src/network.lua's WORLD)
--   vs = { kinds }        damage to those enemies, `from` at none (two such nodes multiply)
--   loot = { kinds }      what those enemies' bodies are worth drunk, `from` at none
--   mutations = { ids }   a mutation can be offered: one a rank, in that order
--   pulse = true          the Spore Pulse
--   slots = n             n species can come on a run (one rank)
--   won = level           shut until that level is won
--   seen = { kinds }      hidden until one of them has been met
--
-- `price` is a list, a price a rank. Spores come in a few a wave cleared and
-- more for a win, the first win of a level most (D.SPORES, up with the glossary).

-- A species' branch of the network: its unlock, then what makes it as strong
-- as its row above. `m` scales every price on it, the later species dearer;
-- `extra.ease` (0 to 1) holds it back less, for the first species, which the
-- first level has to be won with.
-- `stats` names its numbers in groups, each group a node: { name, keys, from,
-- prices }; the first group is the one its next species grows from.
local NET = {
    { id = "sprout", name = "THE SPROUT", blurb = "WHERE THE NETWORK STARTS. THREE MUTATIONS COME WITH IT",
        mutations = { "thick", "quick", "cheap" }, free = true },
}
local function add(row) NET[#NET + 1] = row; return row.id end

local P3, P2, PS, PU
local function species(kind, at, price, m, groups, extra)
    local t = D.TOWER[kind]
    local row = { id = kind, at = at, name = t.name, species = kind, blurb = t.blurb,
        price = price and { price } or nil, free = price == nil }
    extra = extra or {}
    local ease = extra.ease or 1
    row.won = extra.won
    add(row)
    local function cost(list)
        local out = {}
        for n, p in ipairs(list) do out[n] = math.max(1, math.floor(p * m + 0.5)) end
        return out
    end
    local first
    for n, g in ipairs(groups) do
        local id = add({ id = kind .. "." .. g.id, at = g.at and (kind .. "." .. g.at) or kind, name = g[1],
            blurb = g[2], tower = kind, stats = g[3], from = 1 - (1 - g[4]) * ease, price = cost(g[5]) })
        if n == 1 then first = id end
    end
    for b = 1, 2 do
        local up = t.up[b]
        add({ id = kind .. ".up" .. b, at = kind .. "." .. groups[math.min(b, #groups)].id, name = up[1].name,
            blurb = "A BRANCH OF " .. t.name .. " UPGRADES, " .. up[1].name .. " FIRST", up = { kind, b }, price = cost(PU) })
    end
    return first
end

-- The prices every species' nodes start from, before its `m`: a stat node of
-- three ranks, of two, its body, and each upgrade branch.
P3, P2, PS, PU = { 2, 4, 7 }, { 3, 6 }, { 2, 4 }, { 6, 12 }

-- Damage: the puffer the network starts with, the needle off it, the
-- mortar and the Humongous Fungus further out.
local puffer = species("puffer", "sprout", nil, 1, {
    { id = "power", "SHARPER SPORES", "PUFFS HIT HARDER", { "damage", "toxin" }, 0.75, P3 },
    { id = "rate", "QUICKER PUFFS", "PUFFS COME FASTER", { "every" }, 0.8, P3 },
    { id = "body", "TOUGH CAP", "MORE HP, CHEAPER TO GROW", { "hp", "cost" }, 0.8, PS },
})
local needle = species("needle", puffer, 6, 1, {
    { id = "power", "HARDER NEEDLES", "NEEDLES HIT HARDER, AND HARDER ON A DEAD END", { "damage", "deadEnd" }, 0.75, P3 },
    { id = "rate", "STEADY AIM", "SHOOTS FASTER", { "every" }, 0.8, P3 },
    { id = "body", "STIFF STALK", "MORE HP, CHEAPER TO GROW", { "hp", "cost" }, 0.8, PS },
})
local mortar = species("mortar", needle, 45, 2.8, {
    { id = "power", "BIGGER BLASTS", "BLASTS HIT HARDER", { "damage", "clusterDamage" }, 0.75, P3 },
    { id = "rate", "QUICK RELOAD", "BLASTS COME FASTER", { "every" }, 0.8, P3 },
    { id = "body", "THICK SKIN", "MORE HP, CHEAPER TO GROW", { "hp", "cost" }, 0.8, PS },
}, { won = "shed" })
species("giant", mortar, 90, 4, {
    { id = "power", "OLD MYCELIUM", "QUAKES HIT HARDER, MORE PER NODE", { "damage", "perNode" }, 0.75, P3 },
    { id = "rate", "DEEP PULSE", "QUAKES COME FASTER", { "every" }, 0.8, P3 },
    { id = "body", "GREAT BULK", "MORE HP, CHEAPER TO GROW", { "hp", "cost" }, 0.8, PS },
}, { won = "lawn" })

-- Control: the mat, the Stinkhorn off it, the Cordyceps further out.
local mat = species("mat", "sprout", 10, 1.2, {
    { id = "power", "STICKY SLIME", "SLOWS HARDER AND DIGESTS MORE", { "slow", "digest" }, 0.75, P3 },
    { id = "life", "SLOW TO DRY", "LASTS LONGER, CHEAPER TO LAY", { "life", "cost" }, 0.8, P2 },
})
local stink = species("stink", mat, 30, 2.2, {
    { id = "power", "FOULER REEK", "SLOWS AND TRIPS MORE, ROTS HARDER", { "reek", "stumble", "rot", "panic" }, 0.75, P3 },
    { id = "bait", "CLINGING STENCH", "BAITS FLIES HARDER, HOLDS THEM LONGER", { "bait", "hold" }, 0.8, P2 },
    { id = "body", "STOUT STALK", "MORE HP, CHEAPER TO GROW", { "hp", "cost" }, 0.8, PS },
}, { won = "crack" })
species("cordyceps", stink, 60, 3.4, {
    { id = "power", "TIGHT GRIP", "HOLDS LONGER, BIGGER HOSTS, HARDER BITES", { "infect", "maxHp", "bite" }, 0.75, P3 },
    { id = "rate", "EAGER SPORES", "INFECTS MORE OFTEN", { "every" }, 0.8, P2 },
    { id = "body", "HARDY BLOOM", "MORE HP, CHEAPER TO GROW", { "hp", "cost" }, 0.8, PS },
}, { won = "pond" })

-- Support: the relay, the Lion's Mane off it, the Inky Cap further out.
local relay = species("relay", "sprout", 14, 1.4, {
    { id = "power", "OPEN CHANNELS", "MORE FLOW, MORE DAMAGE, MORE RESERVE", { "capMul", "amp", "battery" }, 0.7, P3 },
    { id = "body", "FIRM KNOT", "MORE HP, CHEAPER TO GROW", { "hp", "cost" }, 0.8, PS },
})
local mane = species("mane", relay, 18, 1.6, {
    { id = "power", "QUICK HEALING", "HEALS AND REGROWS FASTER", { "heal", "regrow", "towerHeal" }, 0.7, P3 },
    { id = "body", "THICK MANE", "MORE HP, CHEAPER TO GROW", { "hp", "cost" }, 0.8, PS },
})
local inky = species("inky", mane, 26, 2, {
    { id = "power", "DEEP DIGESTION", "DRINKS BODIES FOR MORE", { "feast" }, 0.7, P3 },
    { id = "ink", "BLACKER INK", "INK SLOWS HARDER, AND LASTS", { "inkSlow", "inkLife" }, 0.8, P2 },
    { id = "body", "SOFT GILLS", "MORE HP, CHEAPER TO GROW", { "hp", "cost" }, 0.8, PS },
})

-- Defence: the shelf, the Ghost Lamp off it.
local shelf = species("shelf", "sprout", 34, 2.4, {
    { id = "power", "HARD WOOD", "MORE WOOD, AND IT HEALS AND BITES MORE", { "hp", "regen", "thorns" }, 0.7, P3 },
    { id = "guard", "WIDE SHADE", "SHIELDS LINKS BETTER, CHEAPER TO GROW", { "shieldMul", "cost" }, 0.8, P2 },
}, { won = "flowerpot" })
species("lamp", shelf, 50, 3, {
    { id = "power", "BRIGHT GLOW", "HOLDS THEM LONGER, BURSTS HARDER", { "hold", "blast" }, 0.75, P3 },
    { id = "body", "WAXY CAP", "MORE HP, CHEAPER TO GROW", { "hp", "cost" }, 0.8, PS },
}, { won = "log" })

-- Deeper in, one off each line: the Fly Agaric and Oyster Mushroom off the
-- needle, the Earthstar off the mat, the Bleeding Tooth off the Lion's Mane,
-- the Truffle off the Inky Cap and the Turkey Tail off the relay. Each is
-- open by the level that needs it: the Lawn opens the Fly Agaric and the
-- Earthstar for the Puddle's fliers and swimmers, the Puddle the Oyster for
-- the Old Stump's shells, the Old Stump the Bleeding Tooth for the Compost
-- Heap's cutters, and the Compost Heap the Turkey Tail. The Truffle waits on
-- nothing but its branch.
species("agaric", needle, 40, 2.6, {
    { id = "power", "TOXIC WARTS", "HITS FLIERS HARDER", { "damage", "spreadDamage" }, 0.75, P3 },
    { id = "rate", "QUICK FLICK", "SHOOTS FASTER", { "every" }, 0.8, P2 },
    { id = "body", "STOUT STALK", "MORE HP, CHEAPER TO GROW", { "hp", "cost" }, 0.8, PS },
}, { won = "lawn" })
species("oyster", needle, 45, 2.8, {
    { id = "power", "STICKIER DROPS", "STRIPS MORE ARMOR, HITS HARDER", { "strip", "damage" }, 0.75, P3 },
    { id = "rate", "WET GILLS", "DRIPS FASTER", { "every" }, 0.8, P2 },
    { id = "body", "THICK FANS", "MORE HP, CHEAPER TO GROW", { "hp", "cost" }, 0.8, PS },
}, { won = "puddle" })
species("earthstar", mat, 45, 2.6, {
    { id = "power", "HEAVY THUMP", "THUMPS HARDER", { "damage" }, 0.75, P3 },
    { id = "rate", "QUICK BEAT", "THUMPS MORE OFTEN", { "every" }, 0.8, P2 },
    { id = "body", "PAPER SKIN", "MORE HP, CHEAPER TO GROW", { "hp", "cost" }, 0.8, PS },
}, { won = "lawn" })
species("tooth", mane, 40, 2.4, {
    { id = "power", "BITTER SAP", "WHAT CUTS ITS LINKS IS HURT MORE", { "sapHit", "bleed" }, 0.7, P3 },
    { id = "body", "LUMPY CAP", "MORE HP, CHEAPER TO GROW", { "hp", "cost" }, 0.8, PS },
}, { won = "stump" })
species("truffle", inky, 50, 2.8, {
    { id = "power", "RIPE SPORES", "MORE INTEREST, HIGHER CAP", { "interest", "cap" }, 0.7, P3 },
    { id = "body", "DEEP MOUND", "MORE HP, CHEAPER TO GROW", { "hp", "cost" }, 0.8, PS },
})
species("turkey", relay, 40, 2.4, {
    { id = "power", "BANDED BEAT", "MORE HASTE PER SPECIES", { "perSpecies" }, 0.7, P3 },
    { id = "body", "LEATHER BRACKETS", "MORE HP, CHEAPER TO GROW", { "hp", "cost" }, 0.8, PS },
}, { won = "compost" })

-- The threads themselves, and the pulse down them.
add({ id = "hyphae", at = "sprout", name = "HYPHAE", blurb = "THE THREADS: THICKER, WIDER, LONGER", world = "linkHp", from = 0.7,
    price = { 2, 4, 6 } })
add({ id = "hyphae.cap", at = "hyphae", name = "WIDE THREADS", blurb = "LINKS CARRY MORE FLOW", world = "linkCap", from = 0.8,
    price = { 3, 6, 9 } })
add({ id = "hyphae.cost", at = "hyphae", name = "LEAN THREADS", blurb = "LINKS COST LESS TO GROW", world = "linkCost", from = 0.85,
    price = { 3, 6 } })
add({ id = "hyphae.grow", at = "hyphae.cost", name = "FAST THREADS", blurb = "LINKS GROW FASTER", world = "linkGrow", from = 0.8,
    price = { 2, 4 } })
add({ id = "ring", at = "hyphae.cap", name = "FAIRY RINGS", blurb = "RINGS HIT HARDER AND SLOW MORE", world = "ring", from = 0.4,
    price = { 12, 22 } })
add({ id = "pulse", at = "hyphae", name = "SPORE PULSE", blurb = "SEND A SURGE DOWN THE NETWORK", pulse = true, price = { 12 } })
add({ id = "pulse.power", at = "pulse", name = "STRONG PULSE", blurb = "THE PULSE OVERCHARGES HARDER AND COMES BACK SOONER",
    world = "pulse", from = 0.5, price = { 12, 22 } })
add({ id = "lore.wild", at = "ring", name = "WILD MUTATIONS", blurb = "MORE MUTATIONS ON OFFER",
    mutations = { "rings", "reach", "pulse" }, price = { 8, 12, 16 } })

-- Room in the loadout: a species more on a run for each, down a line of
-- their own off the sprout, each waiting on a win further into the story.
local SLOTS = { { 5, "FIVE", "crack", 15 }, { 6, "SIX", "shed", 35 }, { 7, "SEVEN", "pond", 60 }, { 8, "EIGHT", "lawn", 100 } }
local slotAt = "sprout"
for _, sl in ipairs(SLOTS) do
    slotAt = add({ id = "slots." .. sl[1], at = slotAt, name = sl[2] .. " SPECIES", blurb = sl[2] .. " SPECIES CAN COME ON A RUN",
        slots = sl[1], won = sl[3], price = { sl[4] } })
end

-- The sprout: its health and sugar, its seeds and their mutations.
add({ id = "root", at = "sprout", name = "DEEP ROOT", blurb = "THE SPROUT HAS MORE HP", world = "heart", from = 0.8,
    price = { 3, 6 } })
add({ id = "sap", at = "root", name = "SWEET SAP", blurb = "MORE SUGAR A SECOND IN A WAVE", world = "income", from = 0.9,
    price = { 4, 8 } })
add({ id = "store", at = "sap", name = "STORED SUGAR", blurb = "MORE NUTRIENTS TO START", world = "start", from = 0.9,
    price = { 3, 6 } })
add({ id = "harvest", at = "sap", name = "HARVEST", blurb = "A WAVE CLEARED PAYS MORE", world = "bonus", from = 0.8,
    price = { 4, 8 } })
add({ id = "lore.soil", at = "harvest", name = "SOIL MEMORY", blurb = "MORE MUTATIONS ON OFFER",
    mutations = { "feast", "sugar", "store", "roots" }, price = { 6, 8, 10, 12 } })
local SEED_AT = { oak = "root", tomato = "sap", dandelion = "oak", sunflower = "tomato", flytrap = "sunflower" }
local SEED_PRICE = { oak = 18, tomato = 18, dandelion = 30, sunflower = 40, flytrap = 55 }
-- A first run has only the bean; each other seed waits on a win along the
-- way, one every level or two, the last two after the Lawn.
local SEED_WON = { oak = "crack", tomato = "shed", dandelion = "pond", sunflower = "puddle", flytrap = "stump" }
add({ id = "bean", at = "root", name = D.SEED.bean.name, seed = "bean", free = true, blurb = "THE PLAIN SPROUT" })
for _, sd in ipairs(D.SEEDS) do
    if sd.id ~= "bean" then
        add({ id = sd.id, at = SEED_AT[sd.id], name = sd.name, seed = sd.id, blurb = sd.blurb,
            price = { SEED_PRICE[sd.id] }, won = SEED_WON[sd.id] })
    end
end
-- Each seed's own mutations, one a rank.
for _, sd in ipairs(D.SEEDS) do
    local own = {}
    for _, m in ipairs(D.MUTATIONS) do if m.seed == sd.id then own[#own + 1] = m.id end end
    local price = {}
    local base, step = 3, 2
    if sd.id ~= "bean" then base, step = 12, 5 end
    for n = 1, #own do price[n] = base + step * (n - 1) end
    add({ id = sd.id .. ".mut", at = sd.id, name = sd.short .. " MUTATIONS", blurb = "MORE OF THE " .. sd.short .. "'S OWN MUTATIONS",
        mutations = own, price = price })
end

-- Field notes: what the network learns of each kind of enemy once it has met
-- one. Three deep for each kind: it hits them harder, then drinks more of
-- their bodies, then finds where they are weak and hits them harder again
-- (the two damage nodes multiply, the full branch to the numbers defs writes).
local NOTES = {
    { id = "ants", name = "ANTS", kinds = { "ant", "queen", "leafcutter" } },
    { id = "shells", name = "SHELLS", kinds = { "pillbug", "knight", "stag", "dung", "click", "bombardier", "diver", "rhino" } },
    { id = "crawlers", name = "CRAWLERS", kinds = { "mite", "centi", "centiseg", "centipede", "centseg" } },
    { id = "fliers", name = "FLIERS", kinds = { "gnat", "moth", "dragonfly", "hornet" } },
    { id = "diggers", name = "DIGGERS", kinds = { "cricket", "mole", "springtail", "wireworm" } },
    { id = "soft", name = "SOFT THINGS", kinds = { "slug", "brine", "spider", "waterbug", "mold", "naiad" } },
}
add({ id = "notes", at = "sprout", name = "FIELD NOTES", blurb = "WHAT THE NETWORK KNOWS OF WHAT EATS IT. EACH OPENS ONCE ONE IS MET",
    free = true })
for _, n in ipairs(NOTES) do
    local id = add({ id = "notes." .. n.id, at = "notes", name = n.name, blurb = "HIT " .. n.name .. " HARDER", vs = n.kinds,
        seen = n.kinds, from = 0.95, price = { 4, 8 } })
    id = add({ id = id .. ".bodies", at = id, name = n.name .. ": BODIES", blurb = "THEIR BODIES FEED THE NETWORK MORE",
        loot = n.kinds, seen = n.kinds, from = 0.8, price = { 5, 9 } })
    add({ id = "notes." .. n.id .. ".weak", at = id, name = n.name .. ": WEAK SPOTS", blurb = "WHERE THEY ARE WEAK: HIT " .. n.name .. " HARDER STILL",
        vs = n.kinds, seen = n.kinds, from = 0.96, price = { 7, 12 } })
end

D.NETWORK = NET
D.NET = {}
for _, row in ipairs(NET) do D.NET[row.id] = row end

return D

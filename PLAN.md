# Underfoot: the plan

Where the game stands against `DESIGN.md`, item by item. Tick a box when it is in
the game; the numbers behind every ticked item are rows in `src/defs.lua`.

## Done

### MVP (the doc's smallest playable prototype)
- [x] One map, the sever / prune / regrow loop
- [x] Heart, pockets (poor / normal / rich), hyphae, nutrients, fruiting bodies
- [x] Fairy Ring, Decomposition, Spore Pulse
- [x] Spore Puffer, Enoki Needle, Slime Mat, Lion's Mane, Mycorrhiza Relay
- [x] Worker Ant, Pillbug, Mite Swarm, Brine Drop

### MVP2
- [x] Two upgrade branches per tower, two tiers each, a new model per tier
- [x] Tower animations: idle breath / sway, firing kick, growing in
- [x] Inky Cap, Shelf Fungus, Puffball Mortar, Cordyceps Bloom (unlocked by wave)
- [x] Fungus Gnat, Slug, Wolf Spider, Beetle Knight
- [x] Bosses as big bugs: Queen Ant, Stag Beetle, Dung Beetle
- [x] Mutations between waves (10 of them)
- [x] 15 waves; boss banner and health bar; phone layout on two rows
- [x] Dev tools: `--shots`, `--sheet`, `--bot`

### MVP3
- [x] Stinkhorn (stench aura that slows and trips; flies hang about it as bait; Panic branch)
- [x] Ghost Lamp (lure for walkers and fliers; brighter far from the Heart and at night; Flare branch)
- [x] Humongous Fungus (one per run, slow to grow, a quake stronger per fed node near it or in its ring)
- [x] Giant Water Bug (the Pond Edge: untouchable under the flooded lane, drags towers under; stones are safe)
- [x] Giant Centipede (the Lawn: segments with their own HP, each cuts links, splits where broken)
- [x] Bombardier Beetle (challenge mode: scalds as it walks, sprays the sprout from the end of the trail; shelves and towers are cover)
- [x] Weather per wave: rain, drought, night, frost, each with its own board picture
- [x] Night Moth (night waves: flies to the brightest light and eats it)
- [x] Levels: a level picker, progress saved, one map and wave list a level, challenge mode once the last is won
- [x] New pockets: lily pad (low) and stone (high ground)
- [x] A build order a level for `--bot`, a generic player for new maps, `--shots pond|lawn [challenge]`

### MVP4
- [x] The Flowerpot (boss: Queen Ant): a spiral trail in from the rim, and a drainage-hole gate beside the sprout
- [x] The Shed Floor (boss: Stag Beetle): piles of bricks fix two trails into one chokepoint
- [x] The Rotting Log (boss: the new Click Beetle): dark nearly every wave, Fairy Rings of three
- [x] Springtail (hops shelves and mats; its first landing by a thread snaps it)
- [x] Click Beetle (plays dead on its back, soft; then leaps down the trail, cutting and stunning where it lands)
- [x] The picker in rows for six levels; saves from before keep what they had open
- [x] Mole Cricket (part way through the Flowerpot and the Rotting Log, for the Stag: digs a tunnel ahead that the walkers behind it take; killed, it caves in on them)

### MVP5
- [x] Loadout: six of the twelve species picked before each level, with an info panel for each, in the loadout and on the board
- [x] Three bosses on every level, the level's own last (the Crack: Queen, Stag, Dung Beetle)
- [x] Endless: play on past a level's last wave, bosses coming closer together and more of them; the most waves held is kept a level
- [x] A turn button that takes the board round the other way; a weather tooltip; the pockets a species in hand can grow on outlined
- [x] Cricket Nymph, the small Mole Cricket (the Pond Edge and the Lawn: burrows off the trail to a link, a heave in the soil, comes up beside it and cuts it, twice)
- [x] Centipede, the small one (the Lawn: a head and four segments, every one gnawing the links it runs along; splits where broken)
- [x] Species unlock by wave on every level, not just the Crack; a loadout with nothing at wave 0 gets its earliest species from the start

## Next

### Enemies
- [ ] Green Mold (grows along links, converts nodes)
- [ ] Elite modifiers: Fungicidal, Scent-masked, Armored shell, Hive-minded

### Environment
- [ ] Props: bottle caps, matchsticks, Lego bricks, magnifying glass (only if the tileset gets tiles for them)
- [ ] Pocket kinds: rotting log, leaf litter (lily pad and stone are in)

### Progression
- [x] Spore Bank: spores for waves cleared and wins, spent on the network
- [x] The network (`N`): 100-odd nodes spreading out from the sprout, bought a rank at a time; one species to start, the rest, their numbers, upgrades, the sprout, the hyphae, seeds, mutations and field notes grown on it; fully grown it is the game as defs writes it. Balanced against the bot playing a whole campaign from nothing (`B.campaign`). `--spores N`, F8 or seven taps on the spores to test it
- [x] Sprout seeds: six, picked with the loadout (bean free; the rest grown on the network, the dandelion, sunflower and flytrap once the Flowerpot, the Rotting Log and the Lawn are won), each with its own numbers, a trait and three or four mutations of its own, one of them on offer every time the network mutates
- [ ] Colony traits

### Levels
Six of the doc's seven are in, in its order: the Crack, the Flowerpot, the Shed
Floor, the Rotting Log, the Pond Edge and the Lawn. Still to come:
- [ ] 5. The Compost Heap (its own boss is the Dung Beetle, already met on other levels; needs Green Mold)

### Feel
- [x] Audio: synthesised at load (`src/sfx.lua`), a sound for every action and bug, the soil, the network's hum rising and falling with links, a loop a weather
- [x] Effects: hit sparks, stains, shock rings, motes, shot flashes, thread flashes, HUD flashes and banners
- [ ] Balance by hand: over 20 runs the bot wins the Crack 18, the Flowerpot 17, the Rotting Log 16, the Shed Floor and the Pond Edge 15, the Lawn 12; the Stag Beetle usually gets through (the Shed Floor's sprout has 23 to allow for it), and challenge mode is rarely won anywhere. These runs are from before the loadout, three bosses a level, the Mole Cricket and the small Cricket Nymph and Centipede, so they want doing again

## Open questions (as answered so far)

- Real time or pause-to-rewire? Both: a build phase between waves, rewiring during them.
- How harsh is severing? Kind: a reserve, then dormancy.
- Link to fire, or only to refill? Only to refill, for now.
- Full wave preview? Yes, gates included.

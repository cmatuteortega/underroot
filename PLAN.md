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
- [x] Ghost Lamp (lure for walkers and fliers; brighter with flow and at night; Flare branch)
- [x] Humongous Fungus (one per run, slow to grow, a quake stronger per fed node)
- [x] Giant Water Bug (the Pond Edge: untouchable under the flooded lane, drags towers under; stones are safe)
- [x] Giant Centipede (the Lawn: segments with their own HP, each cuts links, splits where broken)
- [x] Bombardier Beetle (challenge mode: scalds as it walks, sprays the sprout from the end of the trail; shelves and towers are cover)
- [x] Weather per wave: rain, drought, night, frost, each with its own board picture
- [x] Night Moth (night waves: flies to the brightest light and eats it)
- [x] Levels: a level picker, progress saved, one map and wave list a level, challenge mode once the last is won
- [x] New pockets: lily pad (low) and stone (high ground)
- [x] A build order a level for `--bot`, a generic player for new maps, `--shots pond|lawn [challenge]`

## Next

### Enemies
- [ ] Springtail (hops blockers and one link)
- [ ] Mole Cricket (burrows, surfaces beside a link)
- [ ] Centipede (segments, damages every link it runs along)
- [ ] Green Mold (grows along links, converts nodes)
- [ ] Elite modifiers: Fungicidal, Scent-masked, Armored shell, Hive-minded

### Environment
- [ ] Props: bottle caps, matchsticks, Lego bricks, magnifying glass
- [ ] Pocket kinds: rotting log, leaf litter (lily pad and stone are in)

### Progression
- [ ] Spore Bank (meta progression between levels)
- [ ] Sprout seeds: oak, tomato, dandelion, bean
- [ ] Colony traits

### Levels
The Crack, the Pond Edge and the Lawn are in; the Crack stands in for the doc's
first five levels and has their three bosses. Still to come as levels of their own:
- [ ] 2. The Flowerpot (boss: Queen Ant)
- [ ] 3. The Shed Floor (boss: Stag Beetle)
- [ ] 4. The Rotting Log
- [ ] 5. The Compost Heap (boss: Dung Beetle)

### Feel
- [ ] Audio: soil, rustles, the network's hum rising and falling with links
- [ ] Balance by hand: the bot wins the Crack and the Pond Edge 8 in 10 and the Lawn 7; the Stag Beetle usually gets through, and challenge mode on the Pond Edge is never won

## Open questions (as answered so far)

- Real time or pause-to-rewire? Both: a build phase between waves, rewiring during them.
- How harsh is severing? Kind: a reserve, then dormancy.
- Link to fire, or only to refill? Only to refill, for now.
- Full wave preview? Yes, gates included.

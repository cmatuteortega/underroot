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

## Next

### Towers
- [ ] Stinkhorn (debuff aura, draws flies as bait)
- [ ] Ghost Lamp (lure; brighter with more flow)
- [ ] Humongous Fungus (one per run, stronger per node)

### Enemies
- [ ] Springtail (hops blockers and one link)
- [ ] Mole Cricket (burrows, surfaces beside a link)
- [ ] Centipede (segments, damages every link it runs along)
- [ ] Green Mold (grows along links, converts nodes)
- [ ] Elite modifiers: Fungicidal, Scent-masked, Armored shell, Hive-minded

### Boss bugs
- [ ] Giant Water Bug (Pond Edge)
- [ ] Giant Centipede (The Lawn)
- [ ] Bombardier Beetle (challenge mode)

### Environment
- [ ] Weather per wave: rain, drought, night, frost
- [ ] Props: bottle caps, matchsticks, Lego bricks, magnifying glass
- [ ] Pocket kinds beyond the four (rotting log, leaf litter)

### Progression
- [ ] Spore Bank (meta progression between levels)
- [ ] Sprout seeds: oak, tomato, dandelion, bean
- [ ] Colony traits

### Levels
- [ ] 1. The Crack (the current map is close to this)
- [ ] 2. The Flowerpot (boss: Queen Ant)
- [ ] 3. The Shed Floor (boss: Stag Beetle)
- [ ] 4. The Rotting Log
- [ ] 5. The Compost Heap (boss: Dung Beetle)
- [ ] 6. The Pond Edge (boss: Giant Water Bug)
- [ ] 7. The Lawn (boss: Giant Centipede)

### Feel
- [ ] Audio: soil, rustles, the network's hum rising and falling with links
- [ ] Balance by hand: the bot wins about 7 in 10, and the Stag Beetle usually gets through

## Open questions (as answered so far)

- Real time or pause-to-rewire? Both: a build phase between waves, rewiring during them.
- How harsh is severing? Kind: a reserve, then dormancy.
- Link to fire, or only to refill? Only to refill, for now.
- Full wave preview? Yes, gates included.

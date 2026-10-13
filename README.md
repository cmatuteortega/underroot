# Underfoot

A tower defense where you are the mycelium under a sprout. This is the MVP of the
design doc (`DESIGN.md`, 13 oct 2026): one map, five fruiting bodies, four enemies
and the sever / prune / regrow loop, plus the two mechanics that make the network
the strategy layer, the Fairy Ring and the Spore Pulse. It is drawn isometrically
with Survive School's 3D method and the frog prototype's world painter
(sekiroclone).

```sh
love .                 # LÖVE 11.x
love . --shots         # dev: a scripted game that clicks like a player, writes
                       # screenshots to the save directory, prints a summary, quits
```

## Playing it

You start with the sprout (the Heart) and 110 nutrients. Grow hyphae out from it
to pockets (a leaf, a crumb, a pebble, a dead beetle), grow fruiting bodies on the
pockets, and start the wave. Enemies walk the pale trail from the two gates on the
left to the sprout, and chew through any thread they cross.

| input | what it does |
| --- | --- |
| drag from a fed node to a pocket (or click one, then the other) | grow a link; cost grows with length, the far end glows if it is in reach |
| `1` | grow hyphae (the default tool) |
| `2`–`6` then click a linked pocket | Spore Puffer, Enoki Needle, Lion's Mane, Relay; Slime Mat (`4`) goes on a trail tile |
| `X` then click | prune a link (half back), clear a tower (60% back), lift a mat |
| click a cut link | regrow it by hand for 40% of its cost |
| `Q` then click a fed node | Spore Pulse: every tower on the way from the sprout overcharges for 6 s (45 s cooldown, counts down during waves) |
| `Space` | start the next wave |
| `F` | game speed ×1 / ×2 / ×3 |
| `P` / `Esc` | pause (`Esc` cancels a tool first) |
| right click | cancel, back to growing |
| middle drag, arrows / WASD | pan |
| `R` | restart after a win or loss (`Shift+R` any time) |
| `F11` | fullscreen |

The bottom line always says either what is under the mouse or the next thing to
learn: the first link, the first tower, and each new enemy before the wave that
brings it.

## What is in it

**The five parts.** The Heart pays 2.2 nutrients a second while a wave is on.
Pockets are poor (pebble, −25% power), normal (leaf, crumb) or rich (dead beetle,
+30% power, and pays 0.35/s when something grows on it while it is fed). Links
cost `6 + 0.32 × length` (a tile is 16), reach at most 62, have 40 HP and carry
3 nutrients/s, and each one costs 0.04/s upkeep during a wave. Nutrients are the
only resource and the ammo: a tower holds a reserve, fires from it, and refills
from the bank at up to the narrowest flow cap on its best path to the Heart.

**Severing.** Ants and walking pillbugs stop to chew a link they walk into (once
each). A rolling pillbug crushes any link it crosses outright. Mites leave the
trail for the nearest link they can smell and gnaw it through. A cut link stops
flow at once. A tower cut off keeps firing on its reserve (it dims and shows a
red bar), then goes dormant (darker still).

**Pruning and brine.** A brine drop that touches a link runs down it away from
the Heart. Each node it reaches is sterilised: its tower dies, the pocket can't
be built on for 12 s, and the link it came down is salted (it won't regrow; prune
it). If the thread it is on is pruned or cut, it falls into the soil and fizzles.
That is the design doc's counterplay: prune the link it is on, accept the loss,
save what is downstream.

**Regrowing.** Lion's Mane heals chewed links in its reach and regrows cut ones,
faster for every link it touches. Any cut link can also be regrown by hand.

**Rerouting and the Fairy Ring.** A loop costs more links and more upkeep but
keeps flowing when one link goes. Close a loop of four or more fed nodes around
real ground and it becomes a Fairy Ring: the soil inside goes to moss, a ring of
tiny caps comes up along it, towers on or in it deal +25%, and enemies inside are
slowed to 70%. Loop it round the trail.

**Decomposition.** Kills leave bodies. A body within 14 of a fed link is drunk
for nutrients over a second and a half (you see it go). Worker ants pick up
bodies lying in their way and carry them off to the sprout. Kill the ant and it
drops the body.

**Towers.** Each has its network rule from the doc:

| tower | cost | does | network twist |
| --- | --- | --- | --- |
| Spore Puffer | 30 | lobs a spore cloud, splash damage | +1 puff per link at its node (up to 4) |
| Enoki Needle | 45 | long range, single target, ignores armor | ×1.8 damage on a dead end (one link) |
| Slime Mat | 18 | on the trail: slows to 45%, catches a rolling pillbug | doesn't wither while a link touches it |
| Lion's Mane | 40 | heals links, regrows cut ones | +50% regrowth per link it touches |
| Relay | 30 | no attack | doubles the flow cap of links in reach |

**Enemies.** Worker Ant (fast, chews, steals corpses), Pillbug (armored 3; rolls
every few seconds at armor 10 and crushes links; a mat stops the roll and leaves
it stuck and soft), Mite Swarm (ten 4-HP mites that each go for a link), Brine
Drop (above). Ten waves bring them in in that order, the brine gently at wave 6.
Each wave's enemies have 10% more HP than the last.

Every number is a row in `src/defs.lua`. The doc says they are placeholders to
tune in playtesting, and they are.

### The doc's open questions, as answered here

- **Real time or pause-to-rewire?** Both: a build phase between waves (income
  stops, a clear bonus is paid) and full rewiring during waves.
- **How harsh is severing?** Kind: a reserve, then dormancy.
- **Link to fire, or only to refill?** Only to refill. The strict version is one
  check in `Game:fire` once the kind one is known to be fun.
- **Full wave preview?** Yes: the next wave's make-up at the top and a blinking
  count at each gate it uses.

### Balance, as far as a bot can tell

A headless bot (the same `Game`, no drawing) that builds a sensible network wave
by wave and repairs and prunes when it should wins all ten waves with the sprout
at 17/20. The same build without repairing loses at wave 8. Two puffers and nothing
else lose at wave 5. So the sever / regrow loop is what decides a run, which is
the point.

### Not in yet

The other six towers, eight enemies, bosses, elites, weather, props, mutations,
the Spore Bank, sprout seeds, other levels, tower upgrade forks, Humongous Fungus,
and sound. The doc's "smallest playable prototype" line is the scope. Each of
those is a row and a model more, below.

## How it is drawn

What carries over from Survive School (`3dmethod.md`) and the frog prototype:

- **One ray per pixel, at its centre.** Every colour is *chosen* off a ramp
  (glint, lit, middle, shadow, plus the bounce-light row), never blended, so no
  colour outside the palette can appear. No alpha anywhere: the overlay is a
  picture whose pixels are fully there or not there.
- **Creases** where neighbouring normals of one material disagree, and **ink**
  round silhouettes and along depth steps onto another part.
- **Print, not geometry**, for anything that has to read: the slab joints, the
  trail's grit, the leaf's veins, the puffball's warts and pore, the pillbug's
  plates, the ant's eyes.
- **Poses are numbers.** Each model is a function from a heading and a pose
  (leg phase, squash, roll, wilt) to ellipsoids. Its picture is kept under those
  numbers rounded to a few steps, about a millisecond to paint the first time and
  free after that. A whole run keeps about forty pictures.
- **The world is painted once** (about 80 ms) with a depth buffer and the room
  position of every pixel. Anything that moves is depth-tested against it, which
  is how ants walk behind slabs and threads dip behind crumbs.
- **Shadows are a step darker**: under an enemy, the upward-facing board pixels
  in its footprint are drawn one step down the palette's `darker` column.

What is new for Underfoot:

- **The camera is isometric**: turned 45° and tilted 30°, orthographic, so a tile
  of ground is a 2:1 diamond and the board reads as a diorama, a block of soil cut
  out of the patio with its strata on the two near sides.
- **The palette** is thirteen colours for the doc's art direction: warm browns,
  moss, stone, teal for the network, a glow for nutrients, rust for enemies, and
  one bright green (`g`) that only the sprout uses. Each colour names the one a
  step darker, and that single column does the shadows, the starved and dormant
  towers (their picture one and two steps darker) and the cut-link stubs.
- **Hyphae are plotted, not traced**, the way the frog's tongue is: a thread drawn
  through the projection a pixel at a time, two pixels deep (three when a relay
  thickens it), depth-tested along its length. Flow shows as glow pulses running
  away from the Heart. A surge from the Spore Pulse runs white and fast. A cut
  link shows as two brown stubs with rust ends and closes up as it regrows.
- **The overlay is one image a frame**, written byte by byte through an FFI
  pointer and drawn once. Painter's order is the order things are put: ground
  marks, then threads, then everything standing, sorted by depth.

## Files

| file | what it is |
| --- | --- |
| `main.lua` | canvas fit, camera, compositing, the network's threads, the HUD and toolbar, mouse and keys |
| `src/game.lua` | the rules: the graph, flow, cuts, pruning, regrowth, rings, the pulse, towers firing, enemies moving, corpses, waves |
| `src/defs.lua` | every tuning number: link costs, towers, enemies, waves |
| `src/world.lua` | the map (ASCII), its solids, the one-time paint, the trail's flow field, picking |
| `src/models.lua` | the sprout, the fruiting bodies, the enemies and their bodies, as ellipsoids, kept by pose |
| `src/tracer.lua` | the isometric camera, lamp, ramps, crease and ink passes, affine maps, the ellipsoid painter |
| `src/palette.lua` | the thirteen colours and the one-step-darker column |
| `src/font.lua` | Survive School's 3x5 face |
| `src/script.lua` | dev only: the `--shots` run |

## Extending

- **A tower**: a row in `D.TOWERS` (`src/defs.lua`), a model in `src/models.lua`
  (and a line in `M.tower`), and its behaviour as a branch in `Game:fire`. It gets
  a toolbar button by being in the list.
- **An enemy**: a row in `D.ENEMIES` and `D.ENEMY_ORDER`, a model, a line in
  `enemyPicture` in `main.lua`, and a branch in `Game:move` if it does something to
  the network nothing else does. Put it in a wave in `D.WAVES`.
- **A map**: `MAP` in `src/world.lua`. `E` gates, `=` trail to `H`, pocket letters
  `p L C B`, `#` raised patio. The trail must reach the Heart from every gate (it
  asserts).
- **A pocket kind**: a row in `POCKET` and a branch in `World.new` that adds its
  solids.
- Before a new model goes in, paint it at every heading into one sheet and look
  at it (the frog prototype's `S.sheet` shows how).

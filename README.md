# Mycelio TD

(Called Underfoot until the builds went up, then Groute; the design doc and the
save directory keep the first name, and the app ids the second, so an installed
copy updates in place.)

A tower defense where you are the mycelium under a sprout, built from the design
doc (`DESIGN.md`, 13 oct 2026). Six levels, each its own map and waves (The
Crack, The Flowerpot, The Shed Floor, The Rotting Log, The Pond Edge, The Lawn),
weather that changes wave by wave, twelve fruiting bodies that each fork into two
upgrade branches of two tiers, twelve enemies, eight bosses (big bugs: a Queen Ant, a
Stag Beetle, a Dung Beetle with its ball, a Click Beetle, a Mole Cricket, a Giant
Water Bug, a Giant Centipede and, in challenge mode, a Bombardier Beetle; three
on every level, the two met part way through it at a third of their health), and
Mutations between waves. All of it sits on the MVP's sever / prune /
regrow loop, the Fairy Ring and the Spore Pulse. It is drawn isometrically with
Survive School's 3D method and the frog prototype's world painter (sekiroclone).

```sh
love .                 # LÖVE 11.x
love . --shots         # dev: a scripted game that clicks like a player, writes
                       # screenshots to the save directory, prints a summary, quits
love . --shots pond    # dev: the same for another level (flowerpot, shed, log, pond,
                       # lawn), the bot playing;
                       # add `challenge` for the challenge wave
love . --sheet         # dev: every look of every model on one sheet (sheet.png)
love . --sounds        # dev: every sound and loop written as a .wav (sounds/), to listen to
love . --bot 10        # dev: plays the Crack headless 10 times, prints how it went
love . --bot 10 lawn   # dev: another level; add `challenge`, or `generic` for the
                       # map-agnostic player instead of the level's build order,
                       # or `endless` to play on past the win until the sprout falls,
                       # or a seed (oak, tomato, dandelion, sunflower, flytrap)
```

## Playing it

It opens on the level picker. The Crack is open; winning a level opens the next
(what is won is kept in the save directory), and winning the Lawn opens challenge
mode, which adds a last wave with the Bombardier Beetle to any level.

A level won offers four ways on: the next level (`N`), endless (`E`), the same
level again (`R`) or the levels (`M`). Endless keeps the run going past the last
wave for as long as the sprout lives: each wave is one of the level's later
waves with more enemies, closer together and tougher than the last (7% a wave,
on top of the level's own growth), its weather now and then shuffled, and a
Mutation every fourth. Boss waves come every fifth wave (every fourth past 20,
every third past 40), and from wave 10 each brings an extra boss from the
level's own, one more every 10 waves. The most waves held in endless on
each level is kept in the save (`save.txt`, see `src/profile.lua`) and shown at the bottom
left of its card in the level picker.

**The Spore Bank.** A run pays a spore for every wave it clears, endless
included, and 10 more for a win; they go into the bank as they come, so a
lost run keeps them. Only the first six species (Spore Puffer, Enoki Needle,
Slime Mat, Lion's Mane, Relay, Inky Cap) can be grown at first. Each level's
first win puts one of the other six up for sale, and once it is bought it is
yours for good:

| level won | species for sale | price |
| --- | --- | --- |
| The Crack | Stinkhorn | 20 |
| The Flowerpot | Shelf Fungus | 25 |
| The Shed Floor | Puffball Mortar | 30 |
| The Rotting Log | Ghost Lamp | 35 |
| The Pond Edge | Cordyceps Bloom | 40 |
| The Lawn | Humongous Fungus | 50 |

The won screen says how many spores the run made and what went up for sale.
Whichever way on is picked, the Spore Bank comes first, showing the new species
with BUY (`B`) and LATER (`Enter`). Bought later, it is bought from its card in
the loadout picker: a species not had yet is dark there, with its price once it
is for sale (`LOCKED` before), and its panel's button buys it. The spores
and what was bought are kept in the save (`save.txt`), and the
level picker and the loadout show the spores in the bank, top left. The
prices and the pay are `price` in `src/defs.lua` and `D.SPORES`.

**Sprout seeds.** Spores buy seeds too, and each run grows from one, picked in
the loadout (the row of chips over the species). The sprout is drawn as the
plant it grew from, and some show their state: the tomato's fruit ripens as it
is hurt, a regrown dandelion is half bald, the sunflower bows its head at night
and the flytrap's jaws shut when it bites. Point at it (tap it on a phone)
and its seed's name shows over it, with what it does on the line at the bottom. Each seed changes
the sprout's numbers and brings three or four mutations of its own: one of the
three offered at every mutation is the seed's (in green) while it has any left.

| seed | price | what it does | its mutations |
| --- | --- | --- | --- |
| Bean Sprout | free | the sprout as it was | Tendrils (links out of the sprout grow at once), Nitrogen Fix (towers 2 hops from it hit as on a pocket one richer), Bean Pod (three free links) |
| Oak Sapling | 15 | sprout +50% HP, links grow 25% slower | Heartwood (30% less from leaks), Bark (links at the sprout ×3 HP), Acorn Drop (every 6 s, 30 and a stun on the bug nearest it), Rings of Growth (+1 HP a wave) |
| Tomato Seedling | 15 | sugar +10%, +10 to start, sprout −30% HP | Ripening (clear bonus +30%), Splat (a leak bursts a fruit: 15 and sticky to bugs near it), Compost (bodies left at a wave's end pay half), Overripe (+1 sugar/s, but half the clear bonus) |
| Dandelion | 25, once the Flowerpot is won | killed, it regrows once at half HP and the wave goes on | Seed Clock (one more regrow), Taproot (regrowing mends every cut link), Seed Drift (a free Spore Puffer on an empty fed pocket after each wave), Parachutes (pulse 30% sooner, 50% longer) |
| Sunflower | 35, once the Rotting Log is won | towers within 2 hops of it +15% damage, but not at night | Seed Head (+4 a sunlit tower at a wave's end), Heliotrope (3 hops, and at night too), Tall Stem (fliers near it take 8/s) |
| Venus Flytrap | 45, once the Lawn is won | sugar −10%; every 2.5 s it snaps at the nearest bug within 26: eats it whole at 40 HP or less (and heals 0.5), else bites for 20 | Digest (what it eats pays its worth again), Trigger Hairs (40% more snaps), Sundew (bugs near it at half speed), Wide Jaws (40% further, eats up to 80 HP) |

Tap a seed to plant it and read it in the side panel; one not had yet opens
its panel, whose button buys it (and plants it). The seed is remembered with
each level's loadout, and the seeds bought are kept in `save.txt`. The numbers
are `D.SEEDS` in `src/defs.lua`, and the seeds' mutations are the rows of
`D.MUTATIONS` with a `seed`.

**The encyclopedia.** The button at the top left of the level picker (`E`)
opens it: a tab each for the enemies, the species and the seeds, a tile an
entry with its model painted big, and a fourth tab, STATUSES, the glossary.
What has not been found yet is a dark cutout of its model with `???` under it:
an enemy is found by meeting it on the board, a species by having it (the
first six, or bought) and a seed the same. Click a tile for its page: the model
up to four times its size on the board (an enemy turning slowly round and
walking on the spot), and everything about it. An enemy's page has what it
does, its numbers, the levels it comes on and what answers it; a species' its
numbers, what it is good against and both upgrade branches with a picture of
each tier; a seed's its mutations. One not found yet says where to find it.
Every status or game word written on a page (STUNNED, ARMOR, SALTED, NIGHT and
the rest) gets a number after it, and the notes at the bottom of the page say
what each means. `<` and `>` (or the arrow keys) go through a tab's pages, the
mouse wheel or a drag scrolls, and `Esc` or a right click goes back. The
enemies met are kept in the save (`save.txt`); a save from before it
counts everything on the levels already won as met. The words and what they
say are `D.GLOSSARY` in `src/defs.lua`, and each enemy's page text is its
`about` there.

Before a level starts you pick the species to bring: six of the twelve. The rest
stay home and stay off the toolbar. The picker shows every enemy the level sends,
with bosses in red. Point at one (tap it on a phone) and the species that answer
it blink. The first time you play a level it suggests six; after that it starts
from what you brought last time, which is kept in the save directory. Tap a
species card to read all about it in a side panel: what it does, its network
twist, its numbers and both upgrade branches. Tap it again (or the panel's button)
to bring it or leave it (or buy it), and tap anywhere else to close the panel. A species
you bring opens when its wave is cleared (the `W` number on its card), on every
level. A run always starts with something to grow: if nothing brought comes at
wave 0, the one that comes first is there from the start.

You start with the sprout (the Heart) and 110 nutrients (more on the later
levels). Grow hyphae out from it to pockets (a leaf, a crumb, a pebble, a dead
beetle, a lily pad, a stone), grow fruiting bodies on the pockets, and start the
wave. Enemies walk the pale trail from the gates on the left to the sprout, and
chew through any thread they cross.

| input | what it does |
| --- | --- |
| drag from a fed node to a pocket | grow a link (a click on a node only selects what is on it); cost grows with length, the far end glows if it is in reach |
| `1`, or the bottom-left button | regrow every cut link, nearest the sprout first, until the nutrients run out (each at the same 40% a hand regrow costs). The button shows how many are cut and what it all costs |
| `2`–`9`, `0`, `T`, `G`, `H` then click a linked pocket (the species you brought) | Spore Puffer, Enoki Needle, Lion's Mane, Relay, Inky Cap, Puffball Mortar, Cordyceps Bloom, Stinkhorn, Ghost Lamp, Humongous Fungus; Slime Mat (`4`) and Shelf Fungus (`8`) go on a trail tile. A fruiting body planted puts the species down and selects the new tower |
| a species in hand | every pocket it could grow on now is lined in one pixel, as a selected tower is |
| click the species in hand on the toolbar again | open its panel (again to shut it); it stays in hand |
| click a tower, mat or shelf (pressed and let go on it: pulling a link from it does not select it) | select it: a panel tells about it as it has grown (live numbers, what is wrong with it, both branches), and the upgrades it can grow now are buttons in it. On a wide screen the camera eases it to a third of the way across and half way down, with the panel on the right; upright, the panel goes across the top. Click elsewhere to close it |
| click on nothing (no pocket, plant or thread, or off the board) | put everything down: the tool in hand, a thread being pulled, the selection |
| `Z` / `C`, or click an upgrade in the panel | upgrade the selection down the left / right branch (after the fork, either key goes on up it) |
| `1` `2` `3`, or click a card | pick a Mutation when the network offers them |
| `X` then click | prune a link (half back), clear a tower (60% back), lift a mat |
| click a cut link | regrow it by hand for 40% of its cost |
| `Q` then click a fed node | Spore Pulse: every tower on the way from the sprout overcharges for 6 s (45 s cooldown, counts down during waves) |
| `Space` | start the next wave |
| `E` (`Shift`+`E` back), or the button at the bottom right | turn the camera a quarter turn round the board, to see it from each of its four sides |
| `F` | game speed ×1 / ×2 / ×3 |
| `P` / `Esc` | pause (`Esc` cancels a tool first) |
| right click | cancel, back to growing |
| drag on open ground, middle drag, arrows / WASD | pan |
| `R` | restart after a win or loss (`Shift+R` any time) |
| `N` | after a win: on to the next level's loadout |
| `M` | the level picker (`Esc` there goes back to the run) |
| `1`–`6`, `C` in the picker | pick a level; challenge mode on or off |
| `E` in the picker, or its top left button | the encyclopedia: `1`–`4` or left / right for its tabs, a click for a page, left / right through the pages, wheel or up / down to scroll, `Esc` back |
| click a species in the loadout | read it in the panel; click it again to bring it or leave it (six at most) |
| a species' key in the loadout | bring it or leave it at once |
| `Enter` / `Space`, `Esc` in the loadout | grow the level with that loadout; back to the levels |
| mouse wheel, `+` / `-` | zoom in and out (whole steps) |
| `V` | sound loud / quiet / off (kept between runs; the level picker has a switch for it too) |
| `F11` / `Alt+Enter` | back to a window (it opens fullscreen) |

On a phone or tablet it plays with one finger, fullscreen, either way up (a
screen too narrow for the toolbar narrows its buttons and lifts START onto a row
of its own, and a phone held upright puts the tools on two rows), and the HUD
keeps clear of the notch and home bar:

| touch | what it does |
| --- | --- |
| drag from a node to a pocket | grow a link; letting go anywhere else cancels it. A tap on a node only selects what is on it |
| tap a tool, then tap where it goes | build, prune, lay a mat, pulse (a planted species is put down, and the new tower selected); tap a species' tool again to open its panel (again to shut it), tap the ground to put it down |
| tap a tower, mat or shelf, then an upgrade in its panel | upgrade it |
| drag on open ground | pan |
| pinch | zoom: the board follows the fingers, with the whole board drawn so nothing is cut off at the edges, then settles on the nearest sharp (whole-pixel) zoom when they lift; it starts one step in, and the toolbar keeps its size at any zoom |
| tap START / SPEED | start the next wave / game speed |
| tap the weather's name in the top bar | what the weather does, in a tip under it; tap it again (or anywhere) to shut it |
| tap the top bar | pause and resume (the game also pauses when it is sent to the background) |
| tap a level card, or the challenge switch | play it / challenge on or off |
| tap ENCYCLOPEDIA in the picker, then a tile | read about it; drag to scroll, `<` `>` for the next, BACK to go back |
| tap anywhere after a win or loss | back to the level picker |

The bottom line always says either what is under the mouse or the next thing to
learn: the first link, the first tower, and each new enemy before the wave that
brings it.

## What is in it

**The five parts.** The Heart pays 2.2 nutrients a second while a wave is on.
Pockets are poor (pebble, −25% power), normal (leaf, crumb) or rich (dead beetle,
+30% power, and pays 0.35/s when something grows on it while it is fed). Links
cost `6 + 0.32 × length` (a tile is 16), reach at most 80, have 40 HP and carry
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
A salted link lies there whole, crusted cream and grey with a rust cross on it; a
salted pocket wears a crust of salt that dries back as its 12 s run out, with a
cream bar over it counting them down.
That is the design doc's counterplay: prune the link it is on, accept the loss,
save what is downstream.

**Regrowing.** Lion's Mane tends the branch below it: it heals chewed links and
regrows cut ones on every link with an end at a node whose way to the Heart runs
through it, up to three hops further out. Any cut link can also be regrown by hand.

**Rerouting and the Fairy Ring.** A loop costs more links and more upkeep but
keeps flowing when one link goes. Close a loop of four or more fed nodes around
real ground and it becomes a Fairy Ring: the soil inside goes to moss, a ring of
tiny caps comes up along it, towers on or in it deal +25%, and enemies inside are
slowed to 70%. Loop it round the trail.

**Decomposition.** Kills leave bodies. A body within 14 of a fed link is drunk
for nutrients over a second and a half (you see it go). Worker ants pick up
bodies lying in their way and carry them off to the sprout. Kill the ant and it
drops the body.

**Towers.** Each has a network rule that asks for its own place in the graph, so
the rules pull against each other: a hub (Puffer), a dead end (Needle), the fork
at the root of a branch (Mane), the far end of a long chain (Cordyceps, Lamp), the
centre of a star (Relay), an outpost (Inky), links fanned over the trail (Mat,
Stinkhorn), a dense knot or a ring (Humongous Fungus). Each has two upgrade branches of
two tiers each. Every tier is a new model, not a recolour: a toxin puffer goes
green and grows satellites, a lance-tipped enoki clump stands a head taller than
the rest, a bramble shelf bristles. Each one breathes or sways on its own beat,
kicks when it fires and comes up out of the ground when it is grown or upgraded.
On every level the last seven species unlock as the waves are cleared.

| tower | cost | does | network twist | branch A | branch B |
| --- | --- | --- | --- | --- | --- |
| Spore Puffer | 30 | lobs spore clouds, splash; hits fliers | +1 puff per link at its node (up to 4) | Lingering Toxin, Miasma | Rapid Fire, Spore Gatling |
| Enoki Needle | 45 | long range, single target, ignores armor; hits fliers | x1.8 damage on a dead end (one link) | Skewer, Lance (runs through 2, 3 in a line) | Mark Target, Hunter's Mark (marked prey takes more from everything) |
| Slime Mat | 18 | on the trail: slows, catches a rolling pillbug | stickier for every living link draped over it (x0.82 slow and +50% digest each, up to 3); with none it withers | Glue, Amber | Digest, Stomach (dissolves what stands on it) |
| Lion's Mane | 40 | heals links, regrows cut ones | tends only the branch below it, 3 hops out (Mane at the fork, not the hub) | Fast Regrowth, Old Growth (4, 5 hops) | Purge (clears webs and stuns, heals the towers it tends), Sanctuary (they can't be webbed or stunned) |
| Relay | 30 | no attack | works on what it is linked to: its links carry x2 flow and it pumps them full however thin the way to it, and the towers linked to it hit 10% harder | Battery, Deep Battery (they hold more) | Amplifier, Resonator (they hit harder, triple flow) |
| Inky Cap (wave 2) | 35 | drinks bodies in reach for x2, drips ink pools that slow and blind (no chewing) | what it drinks tops up itself and the towers linked to it first, cut off or not, then the bank: an outpost's battery | Wide Reach, Spore Shadow | Big Ink, Ink Flood |
| Shelf Fungus (wave 4) | 35 | on the trail: blocks it, enemies must chew through | must grow beside a fed link; shields links near it from chewing and crushing | Thick Armor, Ironwood (more wood, heals) | Thorny, Bramble (bites back) |
| Puffball Mortar (wave 5) | 70 | huge slow blast, minimum range, ground only | drinks three times as much: unless a relay pumps into it, it fires at half pace. On high ground it has no minimum range and reaches 20% further | Cluster Blast, Carpet (bomblets) | Smoke, Blackout (stuns, makes carriers drop bodies) |
| Cordyceps Bloom (wave 7) | 60 | infects one enemy: it turns, walks back biting its own, then dies and fruits | holds its host 20% longer for every hop out from the Heart past the first (up to +120%) | Longer Control, Puppeteer (longer, bigger hosts) | Spreads on Death, Plague |
| Stinkhorn (wave 3) | 40 | a stench round it: everything in it wades (×0.75) and now and then trips and is stunned | the stench runs down each of its living links, a lane 8 wide along the thread: fan its links over the trail. Flies (gnats, moths) that smell it from 70 off come and hang about it for 6 s instead of flying on: bait for the puffers and needles | Wider Stench, Carrion Reek (wider, slower, rots them) | Panic (now and then they turn and flee), Terror; it becomes a red basket stinkhorn |
| Ghost Lamp (wave 6) | 35 | a glowing decoy: walkers and fliers that come into its glow leave the trail for it and chew it until it goes out or they give up (5 s); bosses, brine and mites ignore it | its glow is 30 + 5 for every hop out from the Heart past the first (up to 8), so it belongs out front; night adds 40% | Longer Glow, Will-o'-Wisp (tougher, holds them longer, heals) | Flare, Starburst (bursts when it is destroyed, and stuns) |
| Humongous Fungus (wave 9) | 150 | one per run, and slow to grow (8 s before it does anything): a quake round it every 3.2 s that hits every walker in reach | stronger for every fed node within two links of it, and every node of a Fairy Ring it stands in: +5 damage and +3 reach a node | Spreading, Armillaria (more per node, three links out) | Honey Root, Ancient (quakes stick them, mend links in reach, then stun) |

**Enemies.** Night Moth (comes out on night waves; flies to the brightest light,
a lit Ghost Lamp first, else the nearest fed fruiting body, and eats it), Worker Ant (fast, chews, steals corpses), Pillbug (armored 3; rolls
every few seconds at armor 10 and crushes links; a mat stops the roll and leaves
it stuck and soft), Mite Swarm (ten 4-HP mites that each go for a link), Brine
Drop (above), Fungus Gnat (flies straight at the sprout over everything; only
puffers and needles reach it), Slug (huge, slow, can't be slowed, stops to eat any
fruiting body it passes), Wolf Spider (leaves the trail for your deadliest tower
and webs it shut), Beetle Knight (armor 9: cheap hits glance off), Springtail
(every few seconds it springs off its tail, and at once when a shelf blocks it or
a mat is under it: over and on, two tiles down the trail; the first time it comes
down beside a thread, the thread snaps), Cricket Nymph (the Pond Edge and the
Lawn: the small Mole Cricket. Every few seconds on the trail it looks for a link
within 110; with one, it digs in for 0.8 s, then burrows under the board to it,
unseen and unhurt but for a heave of soil, comes up beside it out of the water and
cuts it, and stays still and soft for 2.2 s. It cuts two that way, then climbs
back to the trail; a fed link before a starved one), Centipede (the Lawn: the
small one, a head and four segments, each its own enemy; every body wears the
links within 4 at 7 a second as it runs along, and it splits where it is broken;
not lured, panicked or infected). Each wave's
enemies have 10% more HP than the last.

**Bosses.** The design doc's human-world bosses became big bugs (see
`DESIGN.md`). They come with a banner and a health bar across the top, and they
shake the board.

- **Queen Ant** (wave 5): lays three workers every few seconds and gnaws every
  thread in reach as she walks, without stopping.
- **Stag Beetle** (wave 10): charges every nine seconds. Its jaws shear any link
  they pass and towers beside the trail are stunned. Answer: a second route to
  the Heart, Sanctuary, and Shelf Fungus to shield the threads that cross.
- **Dung Beetle** (wave 15): walks backwards pushing its ball. The ball takes
  every hit and flattens links, mats and shelves; broken, it leaves a heap worth
  60 and the beetle runs. If the ball reaches the sprout it is 20 damage on its
  own.
- **Click Beetle** (the Rotting Log, wave 13): every seven seconds it rolls onto
  its back and plays dead for 2.4 s, and on its back it is soft (no armor, and
  it takes half as much again). Then it clicks and leaps three and a half tiles
  down the trail, over everything; where it comes down, links within 20 are cut
  and towers within 30 stunned for 2.5 s. Answer: hit it while it is on its
  back, and have a second way to the Heart (or a Lion's Mane) where it lands.
- **Mole Cricket** (part way through the Flowerpot and the Rotting Log, at the
  head of its wave): every ten seconds it stops and digs for 2.5 s, still and
  open to anything, then burrows straight across to the trail tile within six
  tiles that is the most steps nearer the sprout (5 to 14 of them: on the
  Flowerpot, through the wall to the next turn of the spiral) and comes up there.
  It digs twice. Under the soil it cannot be hurt; you see the ground heave. The
  tunnel stays open behind it: anything walking that reaches the first hole goes
  down it and climbs out of the second three seconds later, dazed for 0.8 s.
  Bosses and fliers do not use it. Kill the cricket and its tunnels cave in,
  killing whatever is still down them. Answer: kill it while it digs, and keep
  something on the far hole for what comes out.
- **Giant Water Bug** (the Pond Edge, wave 12): under the flooded lane it cannot
  be seen or hurt, only its ripples. Every seven seconds it surfaces, lunges at
  the nearest fruiting body within 44 and drags at it for 2.6 s. Answer: build on
  the stones (high ground, out of its reach), keep the towers off the stones on a fed Lion's Mane's branch
  (it halves the grip), and hit it while it is out.
- **Giant Centipede** (the Lawn, wave 15): a head and eleven segments, each its
  own enemy with its own HP and armor 5, each crushing every link it runs over.
  Break a segment and the one behind it leads the rest. Its health bar is the
  whole train's. Answer: area damage across the train, mats to bunch it, shelves
  to shield the threads that cross, and regrowing behind it.
- **Bombardier Beetle** (challenge mode, the last wave): walking, it scalds the
  nearest tower in reach every six seconds. Three tiles from the sprout it stops,
  turns its back and sprays the sprout itself every 2.5 s until it dies. The first
  thing in the line of the spray takes it instead: a Shelf Fungus on the trail, a
  fruiting body between them. Answer: cover, then burst damage.

**Levels.** Each is its own map and waves, picked from the level picker.

| level | map | waves | new | boss |
| --- | --- | --- | --- | --- |
| 1. The Crack | a sidewalk crack across a patio, two gates | 15 | everything up to the Humongous Fungus, a species at a time | Queen Ant, Stag Beetle, Dung Beetle |
| 2. The Flowerpot | inside a cracked terracotta pot: one trail spirals in from the rim to the sprout in the middle, and from wave 3 bugs come up out of the drainage hole three tiles from it | 12 | cutting and regrowing; a gate behind your lines | Queen Ant |
| 3. The Shed Floor | dusty floorboards; piles of bricks fix two trails into one chokepoint to the sprout | 13 | chokepoints and blockers, and the Springtail that hops them | Stag Beetle |
| 4. The Rotting Log | inside a hollow log, dark nearly every wave; two long straights meet at the sprout | 13 | Fairy Rings close with three nodes here; slugs and mites | Click Beetle |
| 5. The Pond Edge | the two trails meet on the west shore and wade one flooded lane across a pond; lily pads on the water, stones on the banks, reeds round it | 12 | flooding, high ground; rain often; the Cricket Nymph | Giant Water Bug |
| 6. The Lawn | open mown grass, a long dirt path, three gates | 15 | everything at once, each wave 20% tougher than the last (10% elsewhere); the small Centipede | Queen Ant, Stag Beetle, Giant Centipede |

They come in the design doc's order. The Crack, the first, also brings the
three bosses the levels after it each have one of. A save from before the
Flowerpot, the Shed Floor and the Rotting Log came in keeps every level it had
open: a level is open once the one before it is won, or it or any after it is.

The pockets past the Crack's: a **lily pad** (normal, lies low: rain washes it)
and a **stone** (normal, high ground: the Water Bug cannot reach it, and a mortar
on it has no minimum range). A leaf lies low too. Every board is built from the
tileset's tiles alone; only the pockets and the sprout's mound are modelled.

**Weather.** A wave can come with weather; the forecast says so before it starts
(and the top bar while it lasts). Point at its name there (tap it on a phone)
and a tip says what it does. Each is a row in `D.WEATHER`, and each has its
own picture of the board.

- **Rain**: flow +50%, but towers on low pockets lose 0.3 reserve a second, and
  lingering clouds and ink wash out twice as fast. Puddles on the trail, rain
  streaking down.
- **Drought**: flow −30%, so a thin link starves its towers first and relays
  matter more; unfed mats dry up twice as fast. The moss goes to straw.
- **Night**: towers reach 15% further and lamps glow 40% further; moths come out.
  The board goes a step darker, enemies are hard to see out of a lamp's light,
  and a lamp lights the ground round it.
- **Frost**: everything goes at 0.8: towers fire slower, enemies walk slower, and
  links grow and regrow at 0.6. Rime on the ground, flakes drifting.

**Mutations.** After the waves a level names (3, 5, 8, 10 and 12 on the Crack) the
game holds while you pick one of three for the rest of the run: thick hyphae, quick growth, cheaper links, bodies
worth more, more sugar, a quicker pulse, deeper roots (+5 sprout), fatter
reserves, older rings (+40%), or longer reach; or one of the seed's own (see
Sprout seeds above), always one of the three while the seed has any left.

Every number is a row in `src/defs.lua`. The doc says they are placeholders to
tune in playtesting, and they are. Upgrade tiers only name what they change:
`Game:stat` reads a number off the highest tier that sets it, then the base row.

### The doc's open questions, as answered here

- **Real time or pause-to-rewire?** Both: a build phase between waves (income
  stops, a clear bonus is paid) and full rewiring during waves.
- **How harsh is severing?** Kind: a reserve, then dormancy.
- **Link to fire, or only to refill?** Only to refill. The strict version is one
  check in `Game:fire` once the kind one is known to be fun.
- **Full wave preview?** Yes: the next wave's make-up at the top and a blinking
  count at each gate it uses.

### Balance, as far as a bot can tell

`love . --bot 10 [level]` plays a level headless with one fixed, sensible build
order written for its map: it grows the same network, upgrades along the way,
repairs cuts and prunes brine, and takes the first mutation offered. Over twenty
runs it wins the Crack 18 times, the Pond Edge 15 and the Lawn 12, usually with the sprout
badly hurt. The Stag Beetle still gets through to the sprout in most runs, because
the bot never builds a second route or a Sanctuary, and the Water Bug often
reaches the sprout nearly dead. In challenge mode it wins the Crack 4 times in 5,
the Lawn 3 and the Pond Edge never: the Bombardier is meant to be a wall. A player
who adapts should do better than a script that can't.

`generic` swaps the build order for a player that works on any map (grow to the
pocket that watches the most trail, put the next of a fixed rotation on it). It is
much weaker, losing the Crack at the Stag Beetle every time, so it is for new maps
before they have a build order, not for tuning.

### Not in yet

Green Mold; elite modifiers, props, sprout seeds and the Compost
Heap. Each of those is a row and a model more, below.

## How it sounds

There are no sound files. `src/sfx.lua` makes every sound when the game starts,
a few a frame (or the moment one is first wanted): each is a handful of
voices (sine, triangle, square, saw, white noise, or noise held at a pitch),
each swept from one pitch to another through a swept low or high pass, with
vibrato or FM, under an envelope, mixed and sometimes echoed. Chimes are tuned
to notes; thumps and crunches are pitched noise falling away.

- **The rules cue, the screen plays.** `Game:cue(name, x, z)` notes what
  happened and where (a build, a cut, a shot, a kill, a boss); `main.lua` plays it
  panned to where it is on the screen and quieter off it. One of a name a frame,
  so a dozen ants chewing is one chew.
- **Each sound has a shortest gap and a most-at-once**, and a little pitch wobble
  each time, so a barrage of puffers is a patter and not a wall.
- **The HUD has its own**: a tick on hover, a click, a buzz (and the nutrients
  flash red and shiver) for what cannot be done, a chime for a level setting off.
- **Underneath, loops**: the soil always; the network's hum, as loud as the
  living links make it and higher the more there are (and higher still during
  a Spore Pulse); and the weather's own: rain, the drought's wind, crickets at
  night, frost's high wind and a tinkle now and then.
- **A low sprout beats**: under 30% in a wave, a heartbeat, and the screen's edge
  pulses rust with it.

## How it moves

Every effect is drawn the way everything else is, a pixel at a time in the
palette and depth-tested against the board, from `Game.fx` (looks only: they
roll their own dice, so a run's rules come out the same with or without them):

- **Sparks** off every hit (grey ones, and a clink, when a shell turns most of it),
  **stains** on the ground where a bug died or a shell landed that wear away from
  the edge in, and **shock rings** running out over the ground from a build, an
  upgrade, a blast, a cut, a pulse, a boss arriving or falling.
- **Motes** drifting up: glow off a new tower or a mended thread, dust off a
  boss's footfalls and a gate a wave comes in at, sparkle round the sprout when a
  wave is cleared or a level won, caps springing up along a Fairy Ring as it
  closes.
- **Shots leave**: a puff over a puffer, a cross of light at a needle's tip,
  smoke from a mortar, a heave of soil round the Humongous Fungus.
- **Threads**: a new or regrown link flashes white and glow from the middle out,
  a cut one white then rust, and a pruned one drops to the soil and goes.
- **The HUD**: whatever was pressed lights up for a moment; a word across the
  screen when a wave comes (with its weather), is cleared, a species opens or a
  Fairy Ring closes; the screen's edge goes red when the sprout is hit.

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
  (leg phase, squash, roll, wilt) to ellipsoids. A fruiting body's pose is its
  look (branch and tier) and three small animation numbers: idle (a breath or a
  sway, four steps), fire (the kick of a shot) and grow (coming up out of the
  ground). Its picture is kept under those
  numbers rounded to a few steps, about a millisecond to paint the first time and
  free after that. A whole run keeps about forty pictures.
- **The world is painted once** (about 80 ms) with a depth buffer and the room
  position of every pixel. Anything that moves is depth-tested against it, which
  is how ants walk behind slabs and threads dip behind crumbs.
- **Shadows are a step darker**: under an enemy, the upward-facing board pixels
  in its footprint are drawn one step down the palette's `darker` column.

What is new for Underfoot:

- **Jointed legs.** `seg` lays an ellipsoid between two points, so a leg is a
  hip, a knee and a foot on the ground, and a boss's walk cycle is just where its
  feet are. The bosses are built from a few dozen of these at three times an ant's
  scale, and the crease and ink passes pick out their plates and joints.

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
| `src/game.lua` | the rules: the graph, flow, cuts, pruning, regrowth, rings, the pulse, upgrades, towers firing, enemies and bosses moving, corpses, waves, mutations |
| `src/defs.lua` | every tuning number: link costs, towers, enemies, weather, the levels and their waves |
| `src/world.lua` | the maps (ASCII), their solids, the one-time paint and its weather versions, the trail's flow field, picking |
| `src/models.lua` | the sprout, the fruiting bodies at every tier, the enemies, the bosses and their bodies, as ellipsoids, kept by pose |
| `src/tracer.lua` | the isometric camera, lamp, ramps, crease and ink passes, affine maps, the ellipsoid painter |
| `src/palette.lua` | the thirteen colours and the one-step-darker column |
| `src/font.lua` | Survive School's 3x5 face |
| `src/sfx.lua` | every sound and loop, synthesised at load; pools, gaps, panning |
| `src/script.lua` | dev only: the `--shots` run |
| `src/sheet.lua` | dev only: the `--sheet` model sheet |
| `src/bot.lua` | dev only: the `--bot` balance runs, a build order a level and the generic player |
| `assets/icon/` | the app icon at 40px, in two layers (background, foreground) and put together (`icon.png`, the window's) |
| `android/icon.py` | bakes the Android launcher icon (legacy and adaptive) out of `assets/icon/` |
| `desktop/icon.py` | bakes the `.ico`, `.icns` and AppImage icon out of `assets/icon/` |

## Builds

Two GitHub Actions workflows, the same as Survive School's, build every push
that touches more than docs; a `v*` tag also puts the files on a GitHub Release.

- `.github/workflows/android.yml`: the APK (LÖVE for Android 12.0, the game as
  `game.love`), signed with the `ANDROID_KEYSTORE_*` secrets when they are set
  (and then a Play bundle too), or a throwaway key when they are not.
- `.github/workflows/desktop.yml`: Windows (`Mycelio TD.exe`), macOS (`Mycelio TD.app`),
  Linux (`Mycelio TD.AppImage`) and the bare `game.love`, each fused onto stock
  LÖVE 11.5.

The icon is the Shelf Fungus (second tier down its first branch) on a grass
block from the tileset, ringed by a hypha, in a dusk glow. To change it, edit
the two 40px layers in `assets/icon/` and run `python3 desktop/icon.py <dir>`
to see every size.

## Extending

- **A tower**: a row in `D.TOWERS` (`src/defs.lua`) with its `up` branches, a
  look function in `src/models.lua` (in `TOWER`, with its animation steps in
  `STEPS`), and its behaviour as a branch in `Game:fire`. It gets a card in the
  loadout picker by being in the list, and a toolbar button when brought. Name it
  in `D.COUNTERS` for the enemies it answers. Check every tier with `love . --sheet`.
- **An enemy**: a row in `D.ENEMIES` and `D.ENEMY_ORDER`, a model, a line in
  `enemyPicture` in `main.lua` and in `codex.POSE` (the encyclopedia's), its page
  text as an `about`, and a branch in `Game:move` if it does something to
  the network nothing else does. Put it in a wave in `D.WAVES`, and give it its
  answers in `D.COUNTERS`.
- **A map**: a row in `MAPS` in `src/world.lua`. `E` gates (off the left edge, a
  hole in the floor), `=` trail to `H`, `~` flooded trail, `o` water, pocket
  letters `p L C P S B`, `#` raised patio or skirting, `T` the pot's rim, `X`
  the log's bark, `K` a pile of bricks, `"` grass, `Y` long grass, `r` reeds, `,` boards. The
  trail must reach the Heart from every gate (it asserts). A tiled board also
  wants a theme in `THEMES` (`src/tiled.lua`).
- **A level**: a row in `D.LEVELS` naming its map, its waves (each can carry a
  `weather`), its starting nutrients and sprout, how much tougher each wave gets
  (`growth`), how few nodes close a ring (`ringNodes`), when it mutates, and the
  `loadout` it suggests the first time. It gets a
  card in the picker by being in the list. Give it a build order in `PLANS`
  (`src/bot.lua`) to balance it with `--bot`.
- **A weather**: a row in `D.WEATHER`, read through `Game:sky()` where its numbers
  are used, and a branch in `World:variant` for its picture of the board.
- **A pocket kind**: a row in `POCKET` and a branch in `World.new` that adds its
  solids.
- Before a new model goes in, paint it at every heading into one sheet and look
  at it (the frog prototype's `S.sheet` shows how).

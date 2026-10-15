# Statuses

Every status in the game: what causes it, what it does, how long it lasts, what
ends it, and how it shows on the board. The numbers are the base values, with
upgrade values in brackets, as `src/defs.lua` has them on 15 Oct 2026. The
behaviour is in `src/game.lua` and the drawing in `main.lua` (`drawBoard`,
`drawLink`, `tooltip`, `infoLines`).

Slows multiply together: an ant in ink, in stench and on a mat gets all three.
Frost then multiplies everything, even the Slug, which ignores every other slow.

## Enemies

### Statuses you put on them

| Status | Caused by | Effect | Lasts | Ends / immune | Shows as |
| --- | --- | --- | --- | --- | --- |
| **Stunned** | Puffball Mortar SMOKE shell (1.3 s, BLACKOUT 2.3 s); Stinkhorn trip (20% chance a second in its stench, 0.5 s); Ghost Lamp STARBURST burst (1.5 s); Humongous Fungus ANCIENT quake (0.6 s) | Does nothing: no walking, chewing or webbing. Still takes damage. A smoke hit also makes it drop the corpse it is carrying | As listed; the longest stun wins, they don't add up | Times out. Bosses and brine never trip. A cordyceps host ignores stuns | Three stone-grey specks circling its head |
| **Marked** | Enoki Needle MARK TARGET hit; HUNTER'S MARK also marks everything within 16 of the target | Takes +25% damage from everything (HUNTER'S MARK +45%) | 4 s (5 s); refreshed by every hit | Times out | Glow cross with a cream centre over its head |
| **In stench** | Being inside a Stinkhorn's range (24, then 30 / 36), or within its lane (8, then 11 / 14) of any of its living links | Slowed to ×0.75 (×0.68 / ×0.6). CARRION REEK also deals 3 damage a second. Can trip (see Stunned) | While inside, plus 0.25 s | Fliers aren't affected. The Slug isn't slowed, but still rots | Green haze rising round the stinkhorn and along its links; a selected stinkhorn shows its lanes as dark-moss dashes |
| **Panicked** | Stinkhorn PANIC (1.2 s, every 8 s) / TERROR (2 s, every 6 s): fires on everything in its stench at once | Turns round and walks back the way it came; stops chewing | 1.2 s (2 s) | Times out. Not bosses, not brine | A moss, dark-moss and rust burst at the stinkhorn when it goes off; no mark on the enemy |
| **Slimed** | Standing on a Slime Mat | Slowed to ×0.55 (GLUE ×0.37, AMBER ×0.22, STOMACH ×0.46), and ×0.82 more for each link draped over the mat (up to 3). DIGEST/STOMACH dissolve it at 4/8 damage a second, +50% per drape. A rolling pillbug is uncurled and stuck for 1 s | While on it | The Slug can't be slowed (it still gets digested). Dung Beetle's ball breaks mats | The mat itself |
| **Inked** (blind) | Standing in an Inky Cap's ink pool (radius 7, BIG INK 10, INK FLOOD 13) | Slowed to ×0.7 (×0.55 / ×0.42). **Blind:** can't start chewing a link, stops one it's chewing, mites can't pick a thread to gnaw, spiders can't web | While in the pool; a pool lasts 5 s (INK FLOOD 7 s), rain halves that | The Slug isn't slowed (still blinded) | Black pool on the ground with a checkered edge |
| **Stuck** (honey) | Humongous Fungus HONEY ROOT quake | Slowed to ×0.5 (ANCIENT ×0.35) | 1.5 s (2 s) | Times out. Slug immune | Tan and cream quake ring |
| **Wading** | Being inside a closed Fairy Ring | Slowed to ×0.7 (more with the OLD RINGS mutation) | While inside | Slug immune | Moss checker inside the ring, tiny white caps along it |
| **Lured** | Walking or flying into a lit Ghost Lamp's glow (30 + 5 per hop out from the sprout, up to 8 hops; ×1.4 at night) | Leaves the trail, goes to the lamp and chews it | Hold 5 s (LONGER GLOW 7, WILL-O'-WISP 9), or until the lamp goes out | Once per enemy. Never bosses, brine, mites, hosts, a rolling pillbug or anything under water | The enemy walks off to the lamp; selecting the lamp shows its glow ring |
| **Baited** (fliers) | A fed Stinkhorn within 70 (WIDER STENCH 90) of a gnat or moth | Flies to the stinkhorn and hangs round it instead of the sprout | Hold 6 s (CARRION REEK 9) | Once per flier | The flier circling the stinkhorn |
| **Infected** (host) | Cordyceps Bloom spore, on the toughest walker in reach of up to 400 HP (LONGER CONTROL 700, PUPPETEER 1100) | Walks back the way it came at 80% speed, biting every other walker within 8 for 14 damage a second (PLAGUE 24). Towers ignore it. When the hold runs out it dies and fruits. SPREADS ON DEATH / PLAGUE pass it on 1 / 2 times | 4 s (6.5 / 9), ×(1 + 0.2 per hop the bloom grows from the sprout, up to 6 hops), ×1.5 under a Spore Pulse | Times out. Fliers, bosses and brine can't be infected | Recoloured in the fungus's colours, with tan specks blinking over it |
| **Frozen pace** | Frost weather | Everything moves ×0.8, towers fire ×0.8, links grow and regrow ×0.6 | The wave | Nothing is immune | Drifting cream flakes over the board |

### What they do on their own

| Status | Who | Effect | Shows as |
| --- | --- | --- | --- |
| **Chewing** | Ant, Pillbug, Beetle Knight | Stops on a link it walks into and chews it (5 / 4 / 6 damage a second, for 1 / 1.5 / 2 s). Once per link | Faster chewing animation |
| **Gnawing** | Mite swarm | Picks the nearest link within sniffing range and gnaws it for 6 s, then goes back to the march | Mites clustered on the thread |
| **Carrying** | Worker Ant | Picks up a corpse lying in its way. If it gets to the sprout with it, the body is gone (counts as *stolen*). Dropped if it dies or is smoked | The corpse drawn riding on the ant |
| **Rolling** | Pillbug | After 3.5 s walking it rolls for 2.6 s: armour 10, speed 36, cuts any link it crosses outright | Curled-up ball sprite |
| **Webbing** | Wolf Spider | Hunts the most dangerous tower within 56 and webs it (see Webbed) every 9 s | The spider running off the trail and back |
| **Sliding** | Brine Drop | Runs down the link it touches, away from the sprout, salting what it passes (see Salted). Falls off and fizzles if that link is cut or pruned | The drop riding the thread |
| **Under water** | Giant Water Bug on a flooded tile | Can't be seen or hurt | Rings rippling on the water |
| **Grabbing** | Giant Water Bug | Every 7 s lunges at a tower within 44 that isn't on high ground and drags it at 30 damage a second for 2.6 s (halved if a fed Lion's Mane tends it) | The bug off the trail on the tower; "IT LETS GO" when it lets go |
| **Charging** | Stag Beetle | Every 9 s charges for 1.5 s at speed 26: shears links and stuns towers within 18 for 3 s | "CHARGE!" floater, the board shakes |
| **Raged** | Dung Beetle, once its ball breaks | Walks ×1.5 faster | — |
| **Laying** | Queen Ant | Lays 3 workers every 6 s and gnaws every thread within 8 | — |
| **Siege** | Bombardier Beetle | Scalds the nearest tower every 6 s; 3 tiles from the sprout it stops and sprays the sprout (anything in the way takes it instead) | — |
| **In the dark** | Anything, at night, outside a lamp's light | Purely visual: harder to see | Drawn one step darker |
| **Hit** | Anything | — | A one-frame white flash; a red health bar once it's below full (not mites or bosses) |

## Fruiting bodies (towers)

| Status | Caused by | Effect | Ends | Shows as |
| --- | --- | --- | --- | --- |
| **Cut off** | No living path from the pocket to the sprout | Runs on its reserve; can't refill. Counts as starved | Reconnect it | Reserve bar shows, in rust; tooltip "CUT OFF, ON ITS RESERVE" |
| **Starved** | Cut off, or reserve below 30% | Shooters fire at half pace (Mane, Inky, Stinkhorn and Lamp aren't slowed) | Refill above 30% while connected | One step darker; reserve bar; panel "STARVED: HALF PACE" |
| **Dormant** | Reserve below one shot (or, for a Relay, not connected) | Does nothing at all. A Lamp goes dark, a Stinkhorn's flies leave, an Inky Cap stops drinking bodies | Feed it | Two steps darker; panel "DORMANT: LINK IT TO THE SPROUT" |
| **Thirsty** | A Puffball Mortar whose path carries less than 5 a second | Fires at half pace (on top of starved) | Feed it through a Relay, or rain (flow ×1.5) | Tooltip / panel "THIRSTY" |
| **Webbed** | Wolf Spider | Can't fire | 5 s, or a Lion's Mane PURGE clears it | A web drawn over it, one step darker; "WEBBED SHUT" |
| **Stunned** | Stag Beetle charge passing within 18 | Can't fire | 3 s, or PURGE clears it | Tan specks circling, one step darker; "STUNNED" |
| **Warded** | Tended by a fed Lion's Mane with SANCTUARY | Can't be webbed or stunned by a Stag | Leave its care | — (not shown yet) |
| **Boosted** | Spore Pulse sent through its node | Fires ×2 as often for ×1.5 damage; a cordyceps holds ×1.5 longer | 6 s | Cream specks circling |
| **Ringed** | Its pocket is on a closed Fairy Ring | ×1.25 damage (more with OLD RINGS) | Ring broken | Moss ground round it |
| **Amped / battery** | Next to a Relay | +10% damage (AMPLIFIER +20%, RESONATOR +35%); BATTERY ×1.7 reserve (DEEP BATTERY ×2.5); links ×2 flow | Relay gone | Its links drawn two pixels thick |
| **Damaged** | Slug eating, moths nibbling, lured enemies chewing a lamp, a Water Bug's grab, a Bombardier's scald | Destroyed at 0 HP ("EATEN", "DRAGGED UNDER", a lamp "SNUFFED" or, with FLARE, "FLARED") | PURGE heals it; WILL-O'-WISP heals itself | Red health bar; white flash when hit |
| **Washed** | Rain, on a low pocket (leaf, lily pad) | Loses 0.3 reserve a second | Rain ends | Rain streaks |
| **Coming up** | A new Humongous Fungus | Doesn't fire for 8 s | Grown | Rises out of the ground |
| **Pocket quality** | Where it grows | Rich +30% power and pays sugar; poor −25%. High ground: a mortar has no minimum range and +20% range | Fixed | Tooltip on the pocket |

## Links (hyphae)

| Status | Caused by | Effect | Ends | Shows as |
| --- | --- | --- | --- | --- |
| **Growing** | Just grown | Not yet part of the network | 1.2 s for a short link, longer for a long one (QUICK GROWTH ×2, frost ×0.6) | Drawn up to its growing tip, glow at the tip |
| **Fed** | A living path to the sprout | Carries flow (3 a second, ×Relay, ×weather) | — | Teal, with glow pulses running away from the sprout |
| **Unfed** | Alive, but its end isn't connected | Carries nothing | Reconnect | Dark moss on umber |
| **Damaged** | Chewing, gnawing, crush on a shielded link (−20) | Cut at 0 HP (40, THICK HYPHAE 60) | Lion's Mane heals; HONEY ROOT mends | Below 50%: rust pixels blinking along it |
| **Shielded** | Within 30 of a Shelf Fungus | Takes a third of the chewing; a crush (pillbug, centipede, dung ball) does 20 damage instead of cutting it | Shelf gone | — (not shown yet) |
| **Surging** | A Spore Pulse's path | Visual: the pulse running down it | 6 s | Fast cream dashes |
| **Cut** | Chewed to 0, crushed, sheared | No flow; whatever was beyond it is cut off | Regrow it: click (40% of cost, 3 s), regrow-all, or a Lion's Mane | Gap in the middle with rust ends. Brown while waiting, teal while regrowing; the gap closes as it regrows |
| **Salted** | A Brine Drop ran down it | Cut for good: never regrows, by hand or by Mane | Prune it | Drawn whole, crusted cream and grey with glints, a rust cross in the middle; tooltip "SALTED LINK. IT WILL NOT REGROW: PRUNE IT" |

## Pockets (nodes)

| Status | Caused by | Effect | Lasts | Shows as |
| --- | --- | --- | --- | --- |
| **Salted** (sterilised) | A Brine Drop reaching it | Kills the tower on it ("STERILISED"); nothing can grow there | 12 s | A crust of salt round it that dries back as the time runs out, a salt crystal for a knot, a cream countdown bar; tooltip ", SALTED" |
| **Fed / unfed** | Whether it's connected | — | — | Knot in teal (fed) or dark moss (unfed) |
| **On a Fairy Ring** | Four or more fed nodes in a loop | See Ringed and Wading | While the loop holds | Moss inside, white caps along it |

## Mats and shelves

| Status | Caused by | Effect | Shows as |
| --- | --- | --- | --- |
| **Draped** | Living links within 12 of a Slime Mat (up to 3 count) | Feeds it, ×0.82 slow each, +50% digest each | — |
| **Withering** | A mat with no link over it | Its life (35 s, GLUE 50, AMBER 70) runs out and it goes; drought ×2 as fast | Blinks dark in its last 8 s; panel "WITHERING: DRAPE A LINK OVER IT" |
| **Chewed** | Something blocked by a Shelf chewing through it | Loses HP; THORNY / BRAMBLE bite back 5 / 12 a second; THICK ARMOR / IRONWOOD regen paused while chewed | Blinks dark; tan health bar |

## How often they come up

Measured on 15 Oct 2026 with the headless bot (`love . --bot 4`, `--bot 4 pond`,
`--bot 4 lawn`): the share of wave time during which at least one thing on the
board had the status. This is bot play, not a person's, so take it as a rough
guide.

| Status | The Crack | The Pond Edge | The Lawn |
| --- | --- | --- | --- |
| Link damaged (below 50%) | 92% (63%) | 94% (46%) | 94% (88%) |
| Tower damaged | 11% | 51% | 63% |
| Tower thirsty (mortar) | 49% | 24% | 42% |
| Tower dormant | 66% | 6% | 36% |
| Tower cut off | 25% | 18% | 50% |
| Ant carrying a corpse | 32% | 27% | 27% |
| Link shielded | 15% | 16% | 54% |
| Tower starved | 14% | 16% | 28% |
| Enemy lured | — | 24% | 15% |
| Enemy in stench | 14% | 9% | 17% |
| Tower webbed | 16% | 7% | 8% |
| Enemy marked | 20% | 2% | — |
| Enemy chewing | 12% | 7% | 11% |
| Enemy rolling | 9% | 9% | 10% |
| Mat withering | 14% | 8% | 5% |
| Tower boosted / link surging | 5% | 4% | 4% |
| Link cut | 4% | 2% | 8% |
| Enemy stunned | 2% | 1% | 3% |
| Tower stunned | 2% | — | 1% |
| Brine sliding / salted | 0% | 0% | 0% |

# Underfoot: Tower Defense Design

13 oct 2026 · @matute

The design document this prototype is built from, kept here as written. `README.md`
says which parts of it the MVP covers and how the open questions were answered.

## Pitch

A sprout pushes up through a crack in an abandoned patio. Under it, a mycelium
network wants it to live. You are the network.

You never drop towers on a grid. You grow fruiting bodies from a living web of
hyphae rooted at the sprout, and a tower only fights while nutrients reach it.
Enemies don't just walk to the sprout, they chew through your threads. Every wave is
a topology problem: where to branch, where to loop, and which link to sacrifice.

- **Core loop:** read the wave preview, grow or rewire the network, fight, repair,
  harvest the corpses.
- **What's different:** the connection graph is the strategy layer. Most tower
  defenses ask where to place a tower; this one asks how to wire it.
- **Scale:** everything is tiny. An ant is a cow, a bottle cap is a fortress, a
  human boot is a boss.

## Core mechanics

Five parts make up the network, and everything else in the game is a variation on
them.

| Part | What it is | Rule |
| --- | --- | --- |
| Heart | The sprout's root ball, the network's source | If it dies, you lose. Trades sugar for minerals, which is your base income |
| Pockets | Fixed build spots: a leaf, a crumb, a dead beetle | Each is poor, normal or rich. Rich pockets boost the tower on them |
| Hyphae | Links you grow between the Heart, pockets and towers | Cost scales with length. Each link has HP and a flow cap |
| Nutrients | The only resource, and the ammo | Flow from the Heart along links. Every shot draws some; starved towers fire slowly, then go dormant |
| Fruiting bodies | Towers | Must connect to the Heart. After a cut they run on a short reserve, then go dormant |

- **Severing:** enemies that reach a link chew or trample it. Cut links drop flow
  instantly, so the fight is often about protecting a single thread.
- **Pruning:** you can cut your own link for a partial refund. It isolates
  infections and chemical spills at the cost of the towers downstream.
- **Rerouting:** a tree is cheap but fragile. Loops give redundancy but every link
  costs upkeep, so network density is a real tradeoff.
- **Fairy Ring:** close a loop of four or more nodes and the ground inside becomes a
  ring. Towers inside deal +25% damage and enemies inside are slowed. This rewards
  building loops, not lines.
- **Decomposition:** kills leave corpses. Any corpse within reach of a link is
  absorbed for nutrients, so where enemies die matters as much as whether they do.
- **Spore Pulse:** an active ability on a long cooldown. Send a nutrient surge down
  a chosen path to overcharge every tower on it for a few seconds.

All numbers are placeholders to tune in playtesting.

## Towers

Eleven towers, each with a network rule that changes where you want to put it.
Every tower has two upgrade branches.

| Tower | Role | What it does | Network twist | Upgrade fork |
| --- | --- | --- | --- | --- |
| Spore Puffer | Starter damage | Lobs a small spore cloud, hits groups | +1 puff per connected link | Lingering toxin / Rapid fire |
| Enoki Needle | Sniper | Long range, single target, high damage | Deals bonus damage on a dead-end node (one link only), so tips hit hardest but are the most exposed | Armor pierce / Mark target |
| Cordyceps Bloom | Control | Infects one enemy, which turns and walks back along the path, fighting its own | Strongest while rooted on a rich pocket | Longer control / Spreads on death |
| Slime Mat | Slow | Laid on the path, not on a pocket. Slows and sticks | Mats touching your links feed on them and last longer | Glue (stronger slow) / Digest (damage) |
| Puffball Mortar | Artillery | Slow, huge area blast, has a minimum range | Draws three times the nutrients, so it needs a thick link | Cluster blast / Smoke (enemies lose their target) |
| Shelf Fungus | Blocker | Armored shelf that blocks a tile. Enemies must chew through | Shields links within its radius from chewing | Thicker armor / Thorny (reflects damage) |
| Stinkhorn | Debuff aura | Stench makes enemies stumble and slows them | Flies are drawn to it, so it doubles as bait | Wider stench / Panic (enemies flee) |
| Ghost Lamp | Lure | Glowing decoy. Enemies target it before the sprout | Brighter when flow is high, so it pulls aggro harder | Longer glow / Explodes when destroyed |
| Lion's Mane | Healer | Heals towers and slowly regrows cut links | Regrowth speed scales with the links it touches | Faster regrowth / Purge debuffs |
| Inky Cap | Economy | Digests corpses in its radius for double nutrients | Ink pools blind enemies standing on them | Wider reach / Bigger ink |
| Mycorrhiza Relay | Support | No attack. Raises flow cap on links in its radius | The hub piece: place it where branches meet | Battery (stores reserve) / Amplifier |

**Late unlock: Humongous Fungus.** One per run. It gets stronger the more nodes your
network has, a nod to the real organism that covers square miles. It is slow to
grow and cripplingly expensive, so it is a bet on surviving long enough.

## Enemies

Twelve enemies, designed so that each one pressures the network in a different way
and asks for a different answer.

| Enemy | Behavior | Threat to the network | Counterplay |
| --- | --- | --- | --- |
| Worker Ant | Fast swarm that follows a scent trail and carries off corpses | Steals the nutrients a corpse would give | Any area damage; kill them before they leave with a corpse |
| Pillbug | Armored; rolls into a ball and speeds down the path | Rolling crushes any link it crosses | Slime Mat or Shelf Fungus to stop the roll, then hit it unrolled |
| Springtail | Erratic jumper, hops over blockers and one link | Skips your chokepoints | Puffball blasts, or Cordyceps to turn it |
| Mite Swarm | Hundreds of tiny, low-HP mites that gnaw links | Many small cuts at once, hard to spot | Area damage; Lion's Mane regrows what they chew |
| Mole Cricket | Burrows under the map, ignoring the path; soil bumps telegraph it | Surfaces next to a link and cuts it directly | Keep a Lion's Mane near key links; blast it when it surfaces |
| Slug | Very slow, huge HP, immune to slow and stick | Eats fruiting bodies it passes | Burst damage and Cordyceps; kill it before it reaches towers |
| Fungus Gnat | Flier that ignores the path and heads for the sprout | Bypasses the whole defense | Stinkhorn and Ghost Lamp lure it into a kill zone |
| Wolf Spider | Fast hunter, goes after your highest-damage tower, webs it shut | Silences a tower for several seconds | Lion's Mane purge, Shelf Fungus to body-block |
| Centipede | A long train of segments, each with its own HP | Damages every link it runs along | Area damage across segments; Slime Mat bunches it up |
| Beetle Knight | Heavily armored front, slow | Armor makes cheap towers useless | Enoki Needle (pierce), Cordyceps |
| Green Mold | A rival fungus that grows along your links and converts nodes | Turns your own towers against you | Prune the infected link fast, then let Lion's Mane regrow it |
| Brine Drop | A salt droplet that slides along hyphae | Sterilizes everything downstream of where it enters | Prune the link ahead of it, accepting the loss, or kill it first |

Green Mold and Brine Drop are the two enemies that make you cut your own network on
purpose. Introduce them gently, since pruning feels bad the first time.

## Bosses and elites

Bosses are the human world intruding on the tiny one. Each one breaks a different
assumption about how the network behaves.

| Boss | Mechanic | What it tests |
| --- | --- | --- |
| The Boot | A shadow telegraphs a stomp. The stomp crushes everything in a wide area, links included | Whether you have a second route to the Heart |
| Queen Ant | Spawns waves of workers and follows her own scent trail | Area damage and corpse management at scale |
| The Sprinkler | Floods the low lanes on a timer. Water washes spores away and floods low pockets | Building on high ground and timing around the flood |
| The Spray Bottle | Sweeps a cone of herbicide that hits the sprout directly | Using Shelf Fungus and leaves as cover for the sprout itself |
| Mother Mold | A giant rival colony that grows its own network toward yours | Racing it, and cutting the points where the two networks touch |
| The Lawnmower | Sweeps a blade line across the whole map in a fixed pattern | Pruning ahead of it and rebuilding behind it |

Elite modifiers can be added to any normal enemy to make waves unpredictable:

- **Fungicidal:** deals double damage to links.
- **Scent-masked:** ignores Ghost Lamps and Stinkhorns.
- **Armored shell:** takes reduced damage from clouds and area effects.
- **Hive-minded:** when killed, calls two more of its kind.

## Environment

The map itself changes the fight, in three layers.

**Pocket quality.** Leaf litter is normal, bare stone is poor, a rotting log or a
dead beetle is rich. Rich pockets are contested: they are also where enemies path
toward.

**Weather, per wave:**

- **Rain:** nutrient flow rises, but puddles wash spores off low pockets.
- **Drought:** flow caps drop, so thin links starve first and Relays matter more.
- **Night:** Ghost Lamps and glowing hyphae gain range; moths and other night
  fliers appear.
- **Frost:** growth and fire rate slow for everyone, enemies included.

**Tiny-world props, which double as terrain:**

- Bottle caps are strongholds with built-in walls.
- Matchsticks act as bridges across gaps.
- Lego bricks form fixed mazes that fix the path.
- A magnifying glass focuses a sunbeam that burns one spot on a timer.
- Footstep shadows warn of an incoming stomp.

## Economy and progression

One resource, three sources, three sinks.

- **Sources:** the sprout's steady sugar income, corpses absorbed by links, and
  pockets with rich organic matter.
- **Sinks:** growing towers, growing links (cost scales with length), and upgrades.
  Pruning refunds part of a link.

Between waves you pick one of three random Mutations for the network, such as
faster growth, cheaper links, or a free Relay. This is what makes two runs of the
same map play differently.

Meta progression is a Spore Bank filled by finishing levels:

- **New species:** unlock tower families, each with a distinct look and rule set.
- **Sprout seeds:** pick the plant at the end of the path. An oak sapling is tough,
  a tomato pays more sugar, a dandelion regrows once after dying, a bean sprout
  speeds up growth.
- **Colony traits:** small permanent bonuses, deliberately modest so skill matters
  more than grind.

## Levels and biomes

Seven levels, each teaching one new idea about the network.

| Level | Setting | New idea | Introduces | Boss |
| --- | --- | --- | --- | --- |
| 1. The Crack | Sidewalk crack | Growing links and towers | Worker Ant, Spore Puffer | None |
| 2. The Flowerpot | Cracked terracotta pot | Cutting and regrowing | Pillbug, Lion's Mane | Queen Ant |
| 3. The Shed Floor | Dusty boards, bottle caps, Lego | Chokepoints and blockers | Wolf Spider, Shelf Fungus | The Boot |
| 4. The Rotting Log | Damp, rich, dark | Fairy Rings and loops | Slug, Mite Swarm, Inky Cap | None |
| 5. The Compost Heap | Heat and decay | Economy and decomposition | Green Mold, Cordyceps | Mother Mold |
| 6. The Pond Edge | Water and reeds | Flooding, high ground | Brine Drop, Mole Cricket | The Sprinkler |
| 7. The Lawn | Open grass, human tools | Everything at once | Beetle Knight, Centipede | The Lawnmower |

The Spray Bottle is a challenge-mode boss that can appear in any level once the
story is done.

## Tone, art and open questions

**Tone:** quiet and cozy with a hint of menace, like a nature documentary shot at
ant height. No dialogue; the sprout is the emotional anchor.

**Art:** macro-photography feel. Warm browns and mossy greens for the world, teal
glowing hyphae for the network, and a bright green sprout that is always the most
saturated thing on screen. Flow should be visible: nutrients pulse along links, and
a starved tower visibly dims.

**Audio:** soil, rustles and distant human sounds. The network hums, and the pitch
rises as it grows and falls when a link is cut, so you can hear damage before you
see it.

**Open questions:**

- Real time or pause-to-rewire? Rewiring under pressure is the fantasy, but a short
  build phase between waves lowers the barrier.
- How harsh is severing? Instant dormancy is clear but brutal; a reserve timer is
  kinder.
- Do towers need a link to fire, or only to refill? The first is stricter and more
  original.
- Should the player see the full wave preview? Hidden waves add tension but weaken
  the planning layer.

**Smallest playable prototype:** one map, five towers (Puffer, Needle, Slime Mat,
Lion's Mane, Relay), four enemies (Ant, Pillbug, Mite Swarm, Brine Drop), and the
sever/prune/regrow loop. If that is fun, everything else is content.

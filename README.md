# Blood Champions

A wave-based action roguelite on the Ironwood engine. You spawn into the walled
town of Hearthstead, kit up at the Weapon Rack, and step through the Start Run
Portal into an endless run of levels. Every tenth level is a boss. The boss drops
the keys that open the armory. The run ends when the band does - the record is
how far you got.

There is no campaign to name, list or load. **PLAY** opens the one world on this
machine, resumes its save when there is one, and hosts it; **JOIN GAME** puts a
friend in the same town. The world is the lobby, and the portal is the game.

## The loop

```
Hearthstead
  ├─ Weapon Rack ......... spend keys to open a locked piece, bind ranged + melee
  ├─ vendors / stash ..... kit the bodies out
  └─ Start Run Portal .... begin level 1

levels 1..8   fight a wave
level  9      SHOP LEVEL - no enemies: the shop stall, the upgrade pedestal and
              the Weapon Rack stand together; the gates lead to the boss
level 10      BOSS - the faction's boss, and its escort
levels 11..  three gates again: the wood, the cave or the pit, as the party picks
```

A cleared level drops a reward chest (gold, one random upgrade and one piece of
armour for each body that opens it), an upgrade pedestal (every body in the run
gets its own choice of three - an AI squadmate takes one at random) and **three
gates** to the next level: the wood's grey ring for watchers, black rock and bone
for demons, red flesh and ribs for the blood clones. The chest also raises every
downed player at half health, so a party is not lost to one bad wave. The gates
open once the chest has been opened, and the gate taken is the biome the next
level is fought in. The Greed Totem stands on some levels: a free greed upgrade
for a fifth of your own health.

Every wave is a level. A depth block is ten levels and one island's worth of
ground (`stage_index`); the faction is chosen at the gates, never cycled, and the
depth curve is the same wall behind all three. Watchers are the yardstick, demons
carry far more pool and a heavier blow between crowds of spawns, and the blood
clones fight with a ranger's kit - a light one on the first levels, the great
blades and plate only once the party is deep enough to answer them. There is no
final level: a wipe ends the run and banks its deepest level on the player's
ledger.

## Upgrades, unlocks, keys

- **Upgrades are for the run.** The pedestal, the chest, the Greed Totem and the
  shop all add to the body in this run. They stack (the proc engine's linear and
  hyperbolic curves), and they are gone when the run ends.
- **Unlocks are for the player.** The Weapon Rack lists every weapon in the
  armory, locked or not. Pressing a locked row spends its key price, opens it for
  this player forever, and binds it to that hand. The twig bow and the makeshift
  hatchet are free: a new player fields the starters and nothing else. The
  rack's two hands are the pair the portal carries and the pair the run fights
  with; the character page (`I`) names the hand the body is actually holding -
  the run's pair inside a run, the rack's bound piece while it stands in the
  square - so the page and the portal never disagree about what is in hand. A
  weapon in the collective stash is a wardrobe copy the portal does not take.
- **Only bosses pay keys.** An elite pays gold. A boss pays `3 + island/2`
  keys (3 at level 10, 3 at 20, 4 at 30 ...), and the keys stay banked through a
  wipe.
- **Abilities are unlocked once and equipped.** The rack's ABILITY BOOK sells
  every combat skill for keys, permanently for that player. Open a row, then
  equip it on a body whose hands fit one of its weapon-family tags; the bar
  shows the rows the weapon in hand can use. The starter Fireball is a `staff`
  skill and the two consumables are automatic: they need no purchase, but only
  a staff draws the Fireball on the bar. The **35 active skills** include eight
  free family starters (Snap Shot, Quick Cut, Heavy Swing, Quick Stab, Shield
  Shove, Fireball, Charge, Focus); the other 27 are bought. The **60 ability
  upgrades** are separate run cards: 19 verb upgrades (throw/roll/guard/parry,
  still pending) and 41 live family rows. `scripts/roguelite/ability_index.gd`
  joins both catalogs under one `kind`/`category` lookup.
- **Arrows are unlimited.** There is no quiver to buy, count or empty; a bow is
  never refused.
- **Every skill is drawn twice.** Each of the 37 rows on the bar (the 35 skills
  and the bandage and potion) has its own icon in `assets/ui/abilities/`, and
  each plays its own signature in the world on the beat that lands it - a lance
  is a line, a bloom is a flower, a flurry is a stutter. Every upgrade's trigger
  draws its consequence where it lands, tinted by the rarity of the row that
  fired it. Fire, smoke, sparks, crescents and wards are painted textures from
  `assets/vfx/`, not primitives. The pipelines, the cue vocabulary and the
  verification gates are in [docs/vfx.md](docs/vfx.md).

## The three islands

| Island | Art | Faction | Bodies |
| --- | --- | --- | --- |
| **The Briarwood** | `TreeKit` / `WorldStyle` wood | Watchers | hollow runts, wardens, high wardens with bows |
| **The Hollow Beneath** | `CaveKit` dripstone, glow fungus | Demons | spawn, hell goats, succubi, beasts, gargoyles |
| **The Blood Pit** | stone colonnade, gibbets, cages and the camp's witch-work | Blood Clones | ranger clones, warden archers |

The three stand as gates after every cleared level: the party picks the biome it
fights next, so the faction is a choice and never a cycle. The level's budget
grows with the depth block and the level inside it, and co-op scales it by +50%
for every player past the first. Every hostile's health is multiplied by the
number of bodies in the run: two players, whether a guest or an AI squadmate,
meet waves with twice the pool.

Every island's edge is a treeline in heavy fog, not a wall: a body may walk out
past the fight ring, and the run answers with `RETURN TO THE FIGHT` and a six
second clock. A body that lets it run out is put in the middle of the map and
pays 30% of the life it has left.

## Controls

| Input | In the town / the run |
| --- | --- |
| `WASD`, mouse | walk and look |
| `Shift` | sprint |
| `Z` | bandage |
| `Space` | dodge / jump-roll |
| Left click | attack (bow draw / melee swing) |
| `1`..`0` | the ten hotbar keys: equipped skills, Bandage on 9, Healing Potion on 0 |
| Right click | guard, or quick-loot the ground |
| `TAB` | swap weapon sets in town; swap the ranged and melee hands in a run |
| `T` | throw the melee piece (throwing weapons have charges) |
| `G` | interact: the rack, a gate, a chest, a pedestal, a shop |
| `K` | loot a corpse or a drop |
| `I` | paperdoll (gear and stash) |
| `O` | warband screen |
| `ESC` | close the open window, then the menu |
| `F12` | performance overlay |

## Running it

Windows, from the repository root:

```powershell
Setup.cmd     # once: fetches the pinned Godot 4.7.2 runtime into .runtime/
Play.cmd      # opens the game
```

`Play.cmd` imports the project first, then launches it. A machine that has never
played gets a fresh world; `PLAY` makes its one save slot and seeds the starter
band. Later `PLAY` presses resume that world.

Several instances can share one desktop. The pointer is captured only after a
click in the window that is in front, and released on focus loss or `Esc`
(`scripts/pointer_gate.gd`), so an instance that merely comes up never moves the
cursor. A run that must never touch the mouse at all - an automated check beside
someone working - is launched with `Play.cmd -- --no-mouse-capture` (or
`IRONWOOD_MOUSE_CAPTURE=0`).

## Multiplayer

One player hosts; friends join the host's world and spawn in the same town. The
host owns the seed, the levels, the mobs and the reward rolls; guests send
requests (`start`, `use`, `choose`, `buy`, `rebind`, `swap`) and receive state,
props, mobs and flashes over the existing ENet session. Each player's unlocks
and keys are their own ledger on their own machine - a player who has never
fought a boss fields the starters.

The run is host-authoritative: the host's press takes the gate, and a downed
body spectates until a chest raises it.

## Verifying

```powershell
.runtime/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . `
  --script tests/roguelite_regression.gd
```

`tests/roguelite_regression.gd` covers the player ledger (no keys, starters
only, a named unlock and its price), the armory, the stacking curves, the town's
two run fixtures, a full level clear, the chest's revive, the upgrade draft, the
Greed Totem, the shop, the three gates and the biome they pick, the shop level at
9, the boss at 10 and the key it pays, the new depth block at 11, and closing back
onto the square.

The rest of the suite is:

```powershell
python tools/run_tests.py
```

## License

See [LICENSE.md](LICENSE.md).

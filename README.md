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
  ├─ Weapon Rack ......... spend keys to open a locked piece; wear it in a hand
  ├─ vendors ............. the band's medicine: bandages and healing draughts
  └─ Start Run Portal .... begin level 1

levels 1..5   fight a wave
level  6      MARKET LEVEL - no enemies: a smaller stall and a reward chest;
              the gates lead back to the road
levels 7..8   fight a wave
level  9      SHOP LEVEL - no enemies: the full stall, a reward chest and the
              Weapon Rack stand together; the gates lead to the boss
level 10      BOSS - the faction's boss, and its escort
levels 11..  three gates again: the wood, the cave or the pit, as the party picks
```

A cleared level drops a reward chest that keeps the gate's promise: a **chest
surface** and a **tier** were chosen at the gate, and every body takes what that
surface pays.

| Surface | What it pays |
| --- | --- |
| Weapons | upgrades to the weapon types your hands fit (bow, staff, sword, two-hand, dagger, shield) |
| Damage / Health / Stamina / Speed / Luck / Critical | any upgrade that acts on that, whatever its family |
| Ability | **a skill**: three offered from what you have not opened, one kept for good - and the first chest of every island is one |
| Attack | basic attacks: shots, swings, on-hit procs and the marks they leave |
| Key | a key, a tier a chest, and the rack spends them |
| Gear | armour: a piece a tier, off a set floor the tier raises |

A card surface lays out three rows a body from that surface at exactly the
promised tier, and the body keeps one. **Every chest is stood for one soul**: a
co-op level stands a box a player, each with that player's name on its plate and
its own three cards, and nobody can open anybody else's. A harder gate can
promise a **2X chest** - the same promise twice, so a party of two under a swarm
gate walks up to four boxes. Every chest pays gold. The chest is the run's only
growth surface: there is no separate upgrade node, and an AI squadmate takes one
of its cards at random off the host the moment the level clears. The first of a
level's main chests to open raises every downed player at half health, and the
gates unseal once every player has opened their own, so nobody is walked past
their reward. **Three gates** stand past the chest: each carries a contract with
a biome, a trial (open, elite or swarm) and the next chest's surface and tier.
The tier is rolled on the island's own ladder, the elite trial raises it a rung
and the swarm trial doubles the box, so the three doors are three different
rewards at three prices. The gate taken is the biome and trial the next level is
fought under. Greed rows are sold by the boss's hoard and the stall; there is no
totem to bargain with.

Every wave is a level. A depth block is ten levels and one island's worth of
ground (`stage_index`); the faction is chosen at the gates, never cycled, and the
depth curve is the same wall behind all three. Watchers are the yardstick, demons
carry far more pool and a heavier blow between crowds of spawns, and the blood
clones fight with a ranger's kit - a light one on the first levels, the great
blades and plate only once the party is deep enough to answer them. Their brain
is a dial of its own: **six clone tiers** (Very Easy, Easy, Medium, Hard, Very
Hard, Fuck you) in `scripts/clone_ai.gd`, `Hard` by default, each one setting the
swing cadence, the guard share, the reaction, the sidestep, the pace, the turn,
the sight, the bow's lead and the weight of a landed blow - and every body from
**Medium** up rolls one item skill of its own (a double slash, a barrage, a
fireball) and performs it in the fight. The band's own AI allies are on the same
table: `SquadDrive` fights on the `Hard` rung, so a hired body and a blood clone
are one duellist in two colours. Every market and shop level also stands a
**recruiter**: three bodies for sale - a ranged archer, a tank and a melee body,
re-rolled per level, kit and all - bought for gold, sworn in the gear the board
sold them and with one rolled skill. A bought body spends no place in the
deployment cap, adds nothing to the waves' pools, cannot be re-dressed, and does
not come back when it falls. **Hearthstead stands the same desk**, at level one:
three bodies in rung-0 kit (a twig bow, makeshift steel, bark and rags), bought
whole and locked whole, on the same card and the same one rolled skill. A town
oath is not a run's hire, though - it takes a place on the field and goes down on
its chest like any other name - and nothing but a better hire ever changes the
kit it was sworn in. There is no
final level: a wipe ends the run and banks its deepest level on the player's
ledger.

## Upgrades, unlocks, keys

- **Upgrades are for the run.** The chest and the shop are what add them to the
  body in this run. They stack (the proc engine's linear and hyperbolic
  curves), and they are gone when the run ends. All **172 rows** - id, tier, cap,
  effect and the engine key each one writes - are tabled in
  [docs/upgrade-pool.md](docs/upgrade-pool.md).
- **Unlocks are for the player; the kit is the inventory's.** The Weapon Rack
  lists every weapon in the armory, locked or not. Pressing a locked row spends
  its key price, opens it for this player forever and forges it into the
  collective stash; an open row wears a piece the stash already holds. The twig
  bow and the makeshift hatchet are free: a new player fields the starters and
  nothing else. **No keeper sells steel or plate**: the town's four counters
  trade in bandages and healing draughts only, bought out of the purse into a
  count the band carries (`Warband.supplies`) and spends on keys 9 and 0. A
  dressing is a purchase, not a free heal, so healing is the one thing gold still
  buys and the only reason to walk up to a counter mid-campaign. **What the body wears is what the run carries.** Each weapon set
  is one of the run's two hands, classified by the piece itself (a bow or staff
  is the ranged hand, a blade or dagger the melee hand), so the bow in one set
  and the blade in the other are exactly the pair the portal takes. Nothing is
  invented: a body whose kit does not hold a piece fights with what it has, and a
  weapon sitting in the stash that the player never wears is never carried.
- **The stash is a run's bag, not a town hoard.** The square hands over no
  spares and no counter fills one, so a fresh warband's collective stash is
  empty: it holds only what a body picked up off the ground during play - a
  dropped blade, a corpse's kit. The character screen (`I`) is four pages over
  one body: **GEAR** is the portrait, the seven worn slots and the body's own
  numbers (with the band's medicine counted beside them) - clicking a slot lists
  the pieces the warband owns for it and puts one on, never taking one off, and a
  right-click's menu is where a piece is sold; **INVENTORY** is the stash as a
  grid of the game's own rendered item icons, with a hover card that says what a
  piece is; **SKILLS** is the bar and the book; **UPGRADES** is the whole upgrade
  pool, family by family, with what every row does and what the run has taken of
  it. Seven worn slots carry the kit:
  head, chest, hands, legs, feet, main hand and off hand. There is no neck and no
  ring - accessories are the run's upgrades, so nothing worn has to be managed in
  a slot the fight never reads.
- **Only bosses pay keys, and only the rack's weapon pages spend them.** An
  elite pays gold. A boss pays `3 + island/2` keys (3 at level 10, 3 at 20,
  4 at 30 ...), and the keys stay banked through a wipe.
- **Abilities are found in chests, then equipped.** An **ABILITY chest** stands
  three combat skills and the soul keeps one, permanently for that player: it is
  a rare promise on the gates, and **the first chest of every island is one**.
  At least one of its three is a skill the body can perform with the pair it is
  wearing. The rack's ABILITY BOOK no longer sells anything - it lists the skills
  the player has opened and toggles them on and off a body whose hands fit one of
  their weapon-family tags; the bar shows the rows the weapon in hand can use. The
  starter Fireball is a `staff` skill and the two consumables are automatic, but
  only a staff draws the Fireball on the bar. The **36 active skills** include
  eight free family starters (Snap Shot, Quick Cut, Heavy Swing, Quick Stab,
  Shield Shove, Fireball, Charge, Focus); the other 28 come out of chests. The
  **60 ability upgrades** are separate run cards - 19 verb upgrades
  (throw/roll/guard/parry, still pending) and 41 live family rows - which is what
  the ability family now pays from a cache, the stall and the hoard.
  `scripts/roguelite/ability_index.gd` joins both catalogs under one
  `kind`/`category` lookup.
- **Arrows are unlimited.** There is no quiver to buy, count or empty; a bow is
  never refused.
- **Every skill is drawn twice.** Each of the 38 rows in the ability table (the
  36 skills and the two medicines) has its own icon in `assets/ui/abilities/`,
  and each plays its own signature in the world on the beat that lands it - a
  lance is a line, a bloom is a flower, a flurry is a stutter. Every upgrade's
  trigger draws its consequence where it lands, tinted by the rarity of the row
  that fired it. Fire, smoke, sparks, crescents and wards are painted textures
  from `assets/vfx/`, not primitives. The pipelines, the cue vocabulary and the
  verification gates are in [docs/vfx.md](docs/vfx.md).

## The three islands

| Island | Art | Faction | Bodies |
| --- | --- | --- | --- |
| **The Briarwood** | `TreeKit` / `WorldStyle` wood | Watchers | hollow runts, wardens, high wardens with bows (casting a random fire rite from level 2), and from level 5 a dedicated caster |
| **The Hollow Beneath** | one fight-sized chamber of the Weeping Hollow's own floor plan (`cave_room.gd`): its rock, roof, dripstone, lights and props | Demons | spawn, hell goats, succubi, beasts, gargoyles |
| **The Blood Pit** | stone colonnade, gibbets, cages and the camp's witch-work | Blood Clones | ranger clones, warden archers |

The three stand as gates after every cleared level: the party picks the biome it
fights next, so the faction is a choice and never a cycle. The level's budget
grows with the depth block and the level inside it, and co-op scales it by +50%
for every player past the first. Every hostile's health is multiplied by the
number of human players in the run - two players, whether two guests or a host
and a guest, meet waves with twice the pool - and a body the AI drives, hired
merc or recruiter recruit, adds no pool to the island.

A level's bodies arrive one at a time: the first after ten seconds, then nine,
eight, seven, six, five, four, 3.2, 2.2 and one - slow at the front, quicker at
the end - with any deeper queue's extra bodies at the one-second tail. Ten stand
on the first block at once (two more per block and per extra connected player),
and a field with nothing on it pulls the next body in immediately.

The two open islands end in a treeline in heavy fog, not a wall: a body may walk
out past the fight ring, and the run answers with `RETURN TO THE FIGHT` and a six
second clock. A body that lets it run out is put in the middle of the map and
pays 30% of the life it has left. The Hollow Beneath is a sealed chamber of the
Hollow's own cave - its rock is the wall, and there is nowhere to walk out.

## Controls

| Input | In the town / the run |
| --- | --- |
| `WASD`, mouse | walk and look |
| `Shift` | sprint |
| `Z` | bandage |
| `V` | healing potion |
| `Space` | dodge / jump-roll |
| Left click | attack (bow draw / melee swing) |
| `1`..`5` | the five skill keys (`6`..`0` while a run's upgrade has bought more) |
| Right click | guard, or quick-loot the ground |
| `TAB` | swap weapon sets in town; swap the ranged and melee hands in a run |
| `T` | throw the melee piece (throwing weapons have charges) |
| `G` | interact: the rack, a gate, a chest, a shop |
| `K` | loot a corpse or a drop |
| `I` | the character screen: GEAR, INVENTORY, SKILLS and UPGRADES |
| `O` | warband screen |
| `ESC` | close the open window, then the menu |
| `F9` | the host's admin console: kill the arena, god mode, grant upgrades, weapons and abilities, jump floors, re-stand the gates and the chest |
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

A save is a **sealed container**, not a text file: the warband, the purse, the
player's ledger and the campaign index all go through `scripts/save_file.gd` -
magic `BCSV`, a HMAC-SHA256 counter-mode keystream over a binary payload, and an
HMAC tail over the nonce and the ciphertext. Editing one in Notepad or a hex
editor is refused rather than loaded (`problem = "tampered"`), so a rewritten
purse or key count is not a win. Settings are not sealed and stay editable.

Settings are remembered per machine and shared by every world: the mix lives in
`user://audio_settings.json` and the display mode in `user://settings.json`
(see [docs/settings.md](docs/settings.md)). The title's Escape window and the
campaign's quick menu offer the same SOUND, DISPLAY and KEYS controls.

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

**A joining player brings their own character.** The host swears a body for the
name they joined with - the pair a new game opens with, a place on the field
whatever the band's cap says - and seats their soul in that and nothing else. The
mercenaries the **Gold Recruiter** sells are the host's alone: the board is the
host's desk on every other machine, and no clue or free body ever walks a guest
into one. A guest who has played this campaign before is given back the character
they left; a character that falls is not replaced on the field, and the town
square is where a replacement is sworn.

The run is host-authoritative: the host's press takes the gate. The town is the
lobby and a party may fight in it, so the square keeps its own: a body knocked
down on town ground is not finished, does not bleed out, and stands back up when
the clock runs out - or after the other soul's five seconds - for host and guest
alike. On the island a downed body waits for the level's chest, and a soul whose
character has fallen watches the party until the run is over.

## Verifying

```powershell
.runtime/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . `
  --script tests/roguelite_regression.gd
```

`tests/roguelite_regression.gd` covers the player ledger (no keys, starters
only, a named unlock and its price), the armory, the stacking curves, the town's
two run fixtures, a full level clear, the chest's revive, the upgrade draft, the
per-soul chest and its owner, the gate contracts and their trials, the typed
chest and its three offers, the 2X promise under one player and under two, the
market at 6, the full shop at 9, the three gates and the biome they pick, the
boss at 10 and the key it pays, the new depth block at 11, and closing back onto
the square.

The rest of the suite is:

```powershell
python tools/run_tests.py
```

## License

See [LICENSE.md](LICENSE.md).

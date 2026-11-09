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
              the Weapon Rack stand together; the portal leads to the boss
level 10      BOSS - the faction's boss, and its escort
levels 11..  next island (the wood, the cave and the pit cycle)
```

A cleared level drops a reward chest (crystals and one random upgrade), an
upgrade pedestal (choose one of three) and a portal to the next level. The chest
also raises every downed player at half health, so a party is not lost to one
bad wave. The portal opens once the chest has been opened. The Greed Totem
stands on some levels: a free greed upgrade for a fifth of your own health.

Every wave is a level. An island is the ten-level block its biome is dressed in,
so a run's tenth island is the wood again. There is no final level: a wipe ends
the run and banks its deepest level on the player's ledger.

## Upgrades, unlocks, keys

- **Upgrades are for the run.** The pedestal, the chest, the Greed Totem and the
  shop all add to the body in this run. They stack (the proc engine's linear and
  hyperbolic curves), and they are gone when the run ends.
- **Unlocks are for the player.** The Weapon Rack lists every weapon in the
  armory, locked or not. Pressing a locked row spends its key price, opens it for
  this player forever, and binds it to that hand. The twig bow and the makeshift
  hatchet are free: a new player fields the starters and nothing else.
- **Only bosses pay keys.** An elite pays crystals. A boss pays `3 + island/2`
  keys (3 at level 10, 3 at 20, 4 at 30 ...), and the keys stay banked through a
  wipe.
- **Arrows are unlimited.** There is no quiver to buy, count or empty; a bow is
  never refused.

## The three islands

| Island | Art | Faction | Bodies |
| --- | --- | --- | --- |
| **The Briarwood** | `TreeKit` / `WorldStyle` wood | Watchers | hollow runts, wardens, high wardens with bows |
| **The Hollow Beneath** | `CaveKit` dripstone, glow fungus | Demons | spawn, hell goats, succubi, beasts, gargoyles |
| **The Blood Pit** | stone colonnade, braziers, `RockKit` cover | Blood Clones | ranger clones, warden archers |

The three cycle every ten levels. The level's budget grows with the island and
the level inside it, and co-op scales it by +50% for every player past the first.

## Controls

| Input | In the town / the run |
| --- | --- |
| `WASD`, mouse | walk and look |
| `Shift` | sprint |
| `Z` | bandage |
| `Space` | dodge / jump-roll |
| Left click | attack (bow draw / melee swing) |
| Right click | guard, or quick-loot the ground |
| `TAB` | swap weapon sets in town; swap the ranged and melee hands in a run |
| `T` | throw the melee piece (throwing weapons have charges) |
| `G` | interact: the rack, the portal, a chest, a pedestal, a portal, a shop |
| `K` | loot a corpse or a drop |
| `P` | paperdoll (gear and stash) |
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

## Multiplayer

One player hosts; friends join the host's world and spawn in the same town. The
host owns the seed, the levels, the mobs and the reward rolls; guests send
requests (`start`, `use`, `choose`, `buy`, `rebind`, `swap`) and receive state,
props, mobs and flashes over the existing ENet session. Each player's unlocks
and keys are their own ledger on their own machine - a player who has never
fought a boss fields the starters.

The run is host-authoritative: the host's press takes the portal, and a downed
body spectates until a chest raises it.

## Verifying

```powershell
.runtime/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . `
  --script tests/roguelite_regression.gd
```

`tests/roguelite_regression.gd` covers the player ledger (no keys, starters
only, a named unlock and its price), the armory, the stacking curves, the town's
two run fixtures, a full level clear, the chest's revive, the upgrade draft, the
Greed Totem, the shop, the portal, the shop level at 9, the boss at 10 and the
key it pays, the island change at 11, and closing back onto the square.

The rest of the suite is:

```powershell
python tools/run_tests.py
```

## License

See [LICENSE.md](LICENSE.md).

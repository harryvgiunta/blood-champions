# The run — levels, shops, bosses, keys

A Blood Champions run is one endless line of levels. The town is the lobby and
the Weapon Rack is where a player decides what to carry; the Start Run Portal is
where the run begins and the level's own portal carries it on.

## The counters

| Counter | Meaning |
| --- | --- |
| `level` | the global level, 1, 2, 3 … |
| `wave` | the level inside its island, 1..10 |
| `stage_index` | the island, 0-based (`(level - 1) / 10`) |
| `shop_level` | `level % 10 == 9` - no enemies, the shop, the rack and the pedestal |
| `boss_level` | `level % 10 == 0` - the faction's boss and its escort |
| `level_cleared` | the wave is dead and the rewards stand on the ground |

An island is the ten-level block its biome is dressed in. The three biomes cycle
(`wilderness`, `caves`, `arena`), so island 4 is the wood again. The level's
budget is `10 × 1.26^island × 1.13^(wave-1)` times the co-op multiplier; the boss
level is the same budget with a ten-point boss taken out of it first.

## Level flow

1. The portal stands the party on the island and queues the wave after a 1.6 s
   beat. Mobs feed in from the queue at the live cap.
2. The queue empties and every mob is dead → `_clear_level`.
3. `_clear_level` pays crystals, stands a reward chest (a boss leaves an elite
   hoard), an upgrade pedestal, sometimes the Greed Totem, and one portal.
4. The chest raises every downed player at half health and unseals the portal.
   The portal's press is the host's and advances one level.
5. Level 9 is the shop level: a shop stall, a Weapon Rack and one extra upgrade
   pedestal stand where the wave would; the portal leads to the boss.
6. Level 10 is the boss. The boss pays `3 + island / 2` unlock keys; nothing else
   in the game pays keys.
7. The level after a boss crosses the island boundary: the next biome is built,
   the party is moved in, and level 11 begins.

There is no final level. A wipe - a live wave with nobody standing - ends the
run, books the deepest level on the player's ledger, and returns every body to
Hearthstead.

## Unlocks

`scripts/roguelite/roguelite_meta.gd` is the player's ledger
(`user://roguelite_meta.json`):

- the starters (`bow_twig`, `hatchet_makeshift`) are free and always fieldable;
- every other weapon is locked until the rack is paid its `unlock_cost`;
- the key balance is global to the player, not the run;
- the ranged and melee loadouts are the rack's two hands;
- `best_level` is the record.

The rack (`town_forge_panel.gd`) lists **every** weapon, locked or not. A locked
row is a button: it spends the piece's price and opens it, then binds it. There
is no roll, no random pool and no totem. A fresh ledger carries no keys, so a new
player fights the first boss with the starters and unlocks their first weapon
after it.

## Upgrades

The run's modifiers (`mod_catalog.gd`, `proc_engine.gd`, `run_player.gd`) are
the upgrades. They are scoped to the run, stack by the engine's own rules, and
are the only in-run growth. The altar's item-welded annointments are not part of
this game: the town has no altar, the paperdoll has no bench, and the starting
band carries no weld.

## Multiplayer

The host owns the seed, the island, the level, the queue, the props, the rolls
and every damage number. Guests receive `state`, `prop`, `prop_gone`, `mob`,
`mod`, `keys`, `crystals`, `sold`, `revived`, `unseal`, `hands`, `rebind`, `fx`
and `end`; their inputs are requests (`start`, `use`, `choose`, `buy`, `rebind`,
`swap`, `sync`). Every player's unlocks and keys are their own machine's ledger.

## Files

| File | Owns |
| --- | --- |
| `scripts/roguelite/run_director.gd` | levels, islands, waves, bosses, shops, props, portal, wire |
| `scripts/roguelite/run_player.gd` | one body's upgrades, stats, hand slot and hooks |
| `scripts/roguelite/roguelite_meta.gd` | the player's keys, unlocks, loadout and record |
| `scripts/roguelite/weapon_registry.gd` | every weapon's firing profile and unlock price |
| `scripts/roguelite/mod_catalog.gd` | the upgrade pool |
| `scripts/roguelite/proc_engine.gd` | stacking rules and the six event answers |
| `scripts/roguelite/roguelite_stage.gd` | the bounded island and its dressing |
| `scripts/roguelite/roguelite_props.gd` | chest, pedestal, Greed Totem, shop, rack, portal |
| `scripts/roguelite/roguelite_hud.gd` | the level plate, upgrade stack, draft and shop |
| `scripts/roguelite/town_forge_panel.gd` | the rack, its unlocks and the portal page |

## Verifying

```powershell
.runtime/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . `
  --script tests/roguelite_regression.gd
```

The regression walks a ledger from zero keys through a named unlock, a full
level clear, the shop at 9, the boss at 10 and its keys, the island change at 11,
and the close back onto the square.

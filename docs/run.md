# The run — levels, shops, bosses, keys

A Blood Champions run is one endless line of levels. The town is the lobby and
the Weapon Rack is where a player decides what to carry; the Start Run Portal is
where the run begins, and the level's own gates carry it on.

> **Design record:** the proposed Crab Champions-shaped loop — gate contracts,
> typed chests, trials, and the decisions behind them — is in
> [run-loop-design.md](run-loop-design.md). This file describes the loop as
> built; that file describes the loop we are considering next.
>
> **Pacing note:** our shop is level 9 of each ten-level block. Crab Champions'
> current biome is five combat islands → shop → elite/boss. The design record
> compares the two cadences and the optional mid-block shop.

## The counters

| Counter | Meaning |
| --- | --- |
| `level` | the global level, 1, 2, 3 … |
| `wave` | the level inside its depth block, 1..10 |
| `stage_index` | the depth block, 0-based (`(level - 1) / 10`) |
| `shop_level` | `level % 10 == 9` - no enemies, the shop, the rack and the pedestal |
| `boss_level` | `level % 10 == 0` - the faction's boss and its escort |
| `level_cleared` | the wave is dead and the rewards stand on the ground |

A depth block is ten levels and one island's worth of ground; the biome is no
longer a cycle. **Every cleared level stands three gates**, and the one the party
walks through is the biome it fights next: `wilderness` (watchers), `caves`
(demons), `arena` (blood clones). Level one opens in the wood because a run needs
its first door; every door after that is a choice. A gate rebuilds the island
under the party, so the dressing always matches the faction standing on it.

The level's budget is `26 × 1.26^island × 1.13^(wave-1)` times the co-op
multiplier; the boss level is the same budget with a ten-point boss taken out of
it first. A level is a crowd: the budget buys seven to twenty bodies at level one
(twelve typical), the live cap keeps twenty of them on the island at once
(`20 + 6` per extra player), and the queue feeds the rest in two at a time every
0.28 s.

## The three gates

| Gate | Biome | Faction | Pool base | Blow base | Speed base | What it fights |
| --- | --- | --- | --- | --- | --- | --- |
| Watchers | `wilderness` | watchers | ×1.00 | ×1.00 | ×1.00 | runts, wardens and bowmen: melee and ranged, few tricks |
| Demons | `caves` | demons | ×1.45 | ×1.35 | ×1.05 | spawns by the dozen, with goats, succubi, beasts and gargoyles behind them |
| Blood clones | `arena` | clones | ×0.85 | ×0.45 | ×1.00 | rangers with a rolled loadout - their damage is their kit, not a multiplier |

`FACTION_TUNING` is the base; the depth curve is one multiplier on top of it, so
the same gate gets harder as the party goes deeper and no gate is secretly a
harder island at the same level. Demons are the heavy faction - a beast carries
`130 × 1.45` before depth - and their crowd is mostly spawns (`cost 1.0`,
`weight 5` of 15) so there is chaff to crush between the brutes.

The clones are a ranger's own body, so they are priced and armed like one: a
clone costs **7** budget (a warden costs 3), its pool is 85% of a ranger's and
its blows 45% of one. `ranger_clone` issues its kit by **depth block** - one rung
per ten levels (`DEPTH_KIT`, indexed by `depth - 1`) - and **a rung is every
earlier rung plus its own additions**: a kit is never retired, so the deeper the
pit the wider the array a wave rolls from, and four bodies in block 5 can still be
a dagger, a short bow, a great sword and a fire staff:

| Depth block | Levels | Adds to the armoury | Armour |
| --- | --- | --- | --- |
| 1 | 1–10 | short bow, short sword, dagger | leather, cloth |
| 2 | 11–20 | recurve bow, arming sword, bone staff | + mail |
| 3 | 21–30 | great sword | + plate |
| 4 | 31–40 | long bow | — |
| 5+ | 41+ | fire staff | — |

Rolled 300 bodies per block: block 5 fields all nine weapons in roughly even
share (`bow_long` 9%, `sword_great` 10%, `staff_fire` 11%, the rest 10–13%) and
leather/mail/plate/cloth all in the mix, so the pit stays an array of duellists
rather than a wall of great swords. A boss clone stands **one** block ahead of the
wave, not two: its pool is already `× 3.1`, and its kit should read as the next
block's rather than as a body from twenty levels deeper than the party. A clone's
pool carries no depth term of its own either: the run's `life` is the depth, and
counting it twice made a level-two clone worth two wardens. Measured against a
body that stands still and never dodges, the pit's second wave (four clones) downs
it in about six seconds, the wood's sixteen in about twelve, the caves' twelve in
about six - the pit's edge is its kit and its AI, not its burst.

Every hostile's pool is multiplied by the number of bodies in the run
(`players.size()`, the same count the plate shows as ALIVE). Two bodies - two
guests, or a player and an AI squadmate - spawn every mob at double health. The
scale rides the same `life` dial the depth curve uses: both watcher classes take
it as `pool_scale` (applied in `_ready`, after the runt rule, so a runt is always
a third of the pool it stands beside), a devil's `apply_difficulty` and a clone's
`apply_difficulty` answer it the same way; guests read the scaled pool from the
`mob` event and the entity stream.

The dial opens 30% under its own line (`OPENING_HEALTH_SCALE`) and is back on it
by level 10, because level one is the first wave a new player swings at: level
one spawns at `0.70 × 1.055 = 0.739`, level 5 at `0.833 × 1.275 = 1.06`, and from
the second depth block on the curve is the bare formula above. The crowd's speed
and swing cadence are not eased - the opening is a shorter fight, not a slower
one.

## One currency, and it is gold

| Purse | What it is |
| --- | --- |
| `Warband.gold()` | the player's gold, kept in `PlayerState`; the town's vendors, the altar and the island's stall all spend it |
| `Roguelite.keys` | the ledger's unlock keys; a boss banks them and only the Weapon Rack spends them |

A hostile pays **gold and nothing else**. It drops no steel, wears no loot and is
not searchable: `run_director._on_enemy_defeated` books the kill, pays the
profile's reward through `world._pay_kill` (the same funnel the campaign uses, so
the band's counter is the one number) and leaves the body on the ground empty.
The Greed mods' `currency_mult` multiplies that gold, and a boss pays its keys
beside it.

## Level flow

1. The gate taken stands the party on the island and queues the wave after a
   1.6 s beat. Mobs feed in from the queue at the live cap.
2. The queue empties and every mob is dead → `_clear_level`.
3. `_clear_level` pays gold, stands a reward chest (a boss leaves an elite
   hoard), an upgrade pedestal, sometimes the Greed Totem and the extra chests -
   one cluster a few paces wide (`stage.reward_point`) - and then the three gates
   in a shallow arc one short walk past it (`_gate_point`, 9.5 m, 24° apart).
   The pedestal draws a row of three for every body in the run; the AI bodies
   take a random one as it stands, and the humans choose when they walk up.
4. The chest raises every downed player at half health and unseals the gates.
   It also hands each body that opens it one piece of armour, popped out of the
   lid (see [the chest's armour](#the-chests-armour)). A gate's press is the
   host's: it advances one level and fixes the biome that level is fought in.
5. Level 9 is the shop level: a shop stall, a Weapon Rack and one extra upgrade
   pedestal stand where the wave would, with the three gates past them; each gate
   leads to the boss, in that gate's biome.
6. Level 10 is the boss. The boss pays `3 + island / 2` unlock keys; nothing else
   in the game pays keys.
7. The level after a boss crosses into a new depth block: a new island is built
   under the gate taken, the party is moved in, and level 11 begins.

There is no final level. A wipe - a live wave with nobody standing - ends the
run, books the deepest level on the player's ledger, and returns every body to
Hearthstead.

## The island's edge

An island is a piece of ground, not a cage: `radius` is the ring it is fought
in, and the turf runs on for `OUTER_DEPTH` (12 m) past it as a darker band with a
treeline planted in it (`stage.play_radius()`). The fog is three veils deep, so
the edge of the fight is something a body can see coming; the solid wall is out at
the far side of the band where nobody stands by accident.

Walking out is allowed, once. A body outside the ring starts its own clock and
the plate reads `RETURN TO THE FIGHT` with the seconds left (one line a second).
Walking back in clears the clock and costs nothing. A body that lets it run out
is put in the middle of the island and pays `BOUNDS_COST` (30%) of the life it
has **left** - a share of the current pool, taken with no armour, dodge or ward in
the way, so the walk can never be the blow that kills somebody. The clock is per
body; `_outside` in `run_director.gd` is the whole of the state.

## The Blood Pit

The arena island is dressed from the woodland's own kit (`CampKit`): gibbets with
hung cages between the columns, clootie trees, a charm web, wicker effigies, skull
stakes, an offering stone, a cold-burning cauldron and the blood of the last
fight on the sand. Everything merges into one mesh per prop and nothing hangs
lower than a standing head - a doodad that reaches into the band above the
shoulders would fold a fighter into a crouch mid-fight.


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
are the run's growth - the pedestal, the chest, the Greed Totem and the stall are
the surfaces that deal them. The altar's item-welded annointments are not part of
this game: the town has no altar, the paperdoll has no bench, and the starting
band carries no weld.

A pedestal draws a row of cards **per body in the run** (`RunPlayer.draft`, each
on that body's own engine rng, excluding what it has already maxed): three of
them, one more per `Big Chests` stack and one per three points of the party's
best `luck`, less one for `Hoarder`. Not one row the party shares. The table
rides the pedestal's payload as `offers`, so every machine shows its own body's
cards and a guest's `choose` names its own row. A body no peer is inside is AI:
it takes a random one of its cards the moment the pedestal stands (`_ai_draft`),
books that choice like any other, and the pedestal stays until every row has been
taken. The chest's single random mod is still the opener's.

The pool is 161 rows over five families and four tiers (`mod_catalog.gd`), and a
tier is now an acquisition rule rather than a colour: `Mods.draft` rolls the
tier from the island's ladder row, filters it to the tiers the surface sells, and
shifts the weights by the party's best `luck`. The pedestal carries commons (epics
from island 2) and never a legendary; a boss's hoard always carries one; the
stall sells all four from island 3, at `22 + 5 x level` plus a per-tier
surcharge. [`upgrade-pool.md`](upgrade-pool.md) is the design record, including
the 31 rows whose keys are still pending (the mark ledger and the verb upgrades'
roll/parry/guard hooks) and which are therefore marked `ready: false` and never
offered.

### The chest's armour

Every chest also pays **one piece of armour per body that opens it**
(`armor_loot.gd`, `RunPlayer.wear_armor`). The slot is random; the set comes off
the level's ladder (makeshift and leather on island 1, mail from island 2, plate
from island 4, all of it by island 5) and is never worse than the piece the body
already wears there, so a chest is always worth the walk. Naked and cloth are
never rolled: one guards nothing and the other is the town's own robe.

The piece is the run's, not the roster's: it rides `RunPlayer.armor`, so a hand
swap re-dresses it, and `_close_run` hands the campaign's kit back through
`refresh_gear`. The rig wears the set, so the reduction is live
(`ArmorData.reduction_for`), and the pop leaves the lid, hangs with the piece's
name and level over it, and flies into the opener - the host draws it when it
rolls and every guest draws the same one from the `armor` event.

The character page (`I`, `warband_paperdoll.gd`) reads the run's armour over the
wardrobe for the body inside it: each won slot names its piece and level under
`WON THIS RUN`, the header says `RUN ARMOUR`, and the stage ranger wears the
same set. A run slot is read-only - clicking it never unequips the roster piece
it hides - and `WarbandPaperdoll.run_armour`
(`world_scene._run_armour_for`, `RunDirector.armor_for_merc`) is the one lookup.
Closing the run repaints the page back to the wardrobe's own kit.

A piece carries **one to three welded modifiers** on a chance that starts at 6%
on level 1, grows a point a level and caps at 35% (level 30); the second is
rolled at 25% and two points a level, the third only from level 10. The rows are
ordinary upgrades (`Mods.draft` on the pedestal's tiers, filtered to what the
body's hands fit and to what it has not maxed), they are taken the moment the
piece is worn, and the HUD lists them by name like any other row. A replaced
piece does not unweld what it gave: the run keeps its stacks, exactly as the
chest's own single mod is never taken back.

### The hands the page shows

The two hand rows are the same picture, for the pair: `WarbandPaperdoll.hands_for`
(`world_scene._hands_for`) answers `{main, off, source}` and the page draws it
over the wardrobe's own two hands.

- `run` - a live run owns the body: `main` is the piece the hand is holding
  (`_active_slot`) and `off` the other one `TAB` reaches. The header says
  `RUN HANDS`, the rows say `THE RUN'S HAND · TAB SWAPS` / `THE RUN'S OTHER
  HAND`, and `SWAP THE HANDS` is the world's own `TAB`.
- `rack` - the square dressed the body at its gate and it is still holding that
  piece: `main` is the ranged piece the rack bound - the piece the portal is
  about to carry - and the off hand is empty, because the square holds only
  that one. The row says `BOUND ON THE RACK · THE PORTAL CARRIES IT`.
- nothing - the road, the camp, the Hollow, and a square body the page has since
  dressed by hand: the roster's kit.

The rule is that the page names the piece the rig is actually holding, and never
a wardrobe copy the body is not carrying. `RunDirector.body_holds` is the read
that keeps the square honest: the rack's tag only stands while the rig still
carries the rack's piece. The square's dress is therefore a presentation, not a
lock - a stash weapon clicked on the page still goes into a square hand, and the
page then names that piece, exactly as the roster has it - and the portal's own
page is the one place that says what the run will carry. Clicking a hand row the
rack owns never strips the roster slot the row hides; it names the rack instead.
Walking out of the walls hands the roster's kit back through `refresh_gear`.

## Abilities

Every combat skill is a **player-level unlock**. The rack's `ABILITY BOOK` page
lists the 27 purchasable skills with their key price; a locked row opens the
skill permanently for this player. The same page equips an opened skill on the
body the soul is inside. The body's current hands decide which families can be
equipped and which equipped skills are actually on the bar:

| Family | Performs with |
| --- | --- |
| `bow` | any bow or crossbow in the main hand |
| `sword` | any one- or two-handed sword |
| `two_hand` | a two-handed blade, club or limb |
| `dagger` | a dagger |
| `staff` | a staff |
| `shield` | a shield in the off hand |
| `any` | any hands (the dash, the body wards) |
| `unarmed` | an empty main hand |

A skill may wear more than one family tag; it is on the bar when any one of its
tags fits the hands. `any` is the wildcard the body skills wear, so it shares
those skills with every weapon family.

### The 35 active abilities

The Ability Book lists these skills, grouped by the family that performs them.
**Eight are free starters** - one per family, marked `*` - and are automatic:
they are never bought, and the hands earn them. The other 27 are purchased with
keys. A body that fits more than one family draws each fitting starter.

| Family | Abilities |
| --- | --- |
| `unarmed` | Charge* |
| `bow` | Snap Shot*, Barrage, Triple Fan Volley, Long Piercing Shot, Rain of Ash, Skewer |
| `sword` | Quick Cut*, Double Slash, Lunging Thrust, Butcher's Cut, Gut Hook |
| `two_hand` | Heavy Swing*, Spinning AOE Spin, Ground Breaker, Wide Sweep, Executioner |
| `dagger` | Quick Stab*, Backstab, Knife Work |
| `staff` | Fireball*, Bone Spear, Cinder Lance, Grave Bloom, Ember Ward |
| `shield` | Shield Shove*, Headbutt, Shield Charge, Ground Shield Slam, Rebuke |
| `any` | Focus*, Dash, Energy Shield, Three Strike, Stone Skin |

### The ability upgrades

The pool's `ability` family is **60 rows**: the 19 old verb upgrades (throw, roll,
guard, parry) are still pending, and 41 live weapon-family rows upgrade the
active skills. Every live row writes a tagged key the ability runtime reads;
`ProcEngine.stat_for(family, key)` is the one lookup, so a bow row never reaches
a staff cast. The 41, by tag:

| Tag | Upgrades |
| --- | --- |
| `any` | Echo Cast, Quickening, Focused Force, Light Hands, Overcharge, Chain Cast, Battle Trance |
| `melee` | Broad Arc, Bloodletting, Bloodstorm |
| `sword` | Duelist's Grace, Serrated Edge, Cleaving Steel |
| `two_hand` | Whirling Fury, Heavy Arc, Momentum, Whirlwind Edge |
| `dagger` | Opening Vein, Quick Hands |
| `staff` | Arcane Focus, Heavy Robes, Spell Siphon, Piercing Hex, Ember Spread, Arcane Surge, Spellstorm |
| `shield` | Guardian's Instinct, Bulwark, Shield Force, Shield Wall |
| `bow` | Double Nock, Quick Draw, Piercing Points, Spiral Shot, Split Fletching, Bouncing Arrows, Homing Fletching, Magical Nock, Hunter's Focus |
| `ranged` | Long Flight, Ricochet Rounds |

Some examples: **Echo Cast** can make a Fireball cast again down the same line;
**Broad Arc** lets a melee ability reach one more body; **Ricochet Rounds** makes
a projectile fold to a second body; **Whirling Fury** can turn a two-hand hit
into a whirlwind; **Guardian's Instinct** blocks while the shield is not raised;
**Serrated Edge** opens a bleed; **Arcane Focus** raises spell damage;
**Quickening** shortens cooldowns; **Spiral Shot**, **Split Fletching**,
**Double Nock**, **Quick Draw** and **Magical Nock** change the bow itself.

The pool is now **161 rows**: 30 shot, 11 hand, 60 ability, 48 perk, 12 relic.
**130** are live; the 31 pending rows are the 19 verb upgrades and the 12 mark
rows. `scripts/roguelite/ability_index.gd` joins the two catalogs: 35 active
skills + 60 ability upgrades = 95 categorized rows, each with a `kind`
(`active` / `upgrade`), a `family`, and a `tags` or `verb` category.
`AbilityIndex.find(id)` answers which kind owns an id; ids never collide. The
Ability Book reads the active half; the pedestal and the card read the upgrade
half.

A body may store both a bow row and a sword row. The bar draws the rows its
current weapon set fits and hides the rest; swapping the set brings them back in
their stored order. The list holds at most seven equipped skills; the family
starters are drawn beside them when the hands fit. Equip is a request like every
other gear verb, so a guest's press travels to the host.

Bow skills never follow the bow's draw: the key is the shot, and a skill's whole
volley leaves on the press. The animation is the bow's own release-and-recover,
solved down the live crosshair and compressed into a quarter of a second, so the
bow always points where the player aims instead of an authored clip's fixed
direction. The key can be pressed while the string is drawn, held or still
settling from a previous shot, and the unfinished draw is dropped.

A skill row may author a **venom** (`poison_dps` / `poison_seconds`): the shaft it
looses lays that dose on the body it opens, and `warband_abilities.gd` ticks it
in quarter-second steps until the clock runs out. **Snap Shot** is the one that
does - 5 damage a second for 5 s - so the starter's cheap arrow keeps paying
after it lands. A second dose on the same body refreshes the clock and only ever
raises the rate; the figure is what the body loses each second, never a stack of
twin poisons. The dose outlives the activation that laid it, and it is laid by
the arrow's landing on the authority, so a replica never ticks one.

An **axe** doubles every blade skill it performs (`AbilityRules.AXE_ABILITY_SCALE`,
keyed on the piece's class rather than its catalog id): the hafted head carries
the weight, which is the same bargain as the double it lands when thrown. Swords
and the blunt tier are untouched, and the dagger's own backstab is never doubled
by the other hand's axe.

The ten keys are: the equipped list, then the **family starters** the hands
earn (each marked `*` above), then the **Bandage** and **Healing Potion** on keys
9 and 0. The starters are laid on the body a peer is inside - in the square, in a
run and out in the wilderness (`ability_rules.gd`; the seat dress asks
`_peer_driven`). A body dressed without `starter_ability` - a mob, a cloned
ranger, a caged soldier, an allied merc - has none; an allied AI body with no
player's list behind it is instead dressed with every skill its own hands fit
(`SeatLoadout._default_abilities`). The bare-hand Charge is the unarmed starter, so
an empty hand still has one key.

## Multiplayer

The host owns the seed, the island, the level, the queue, the props, the rolls
and every damage number. Guests receive `state`, `prop`, `prop_gone`, `mob`,
`mod`, `keys`, `gold`, `sold`, `revived`, `unseal`, `hands`, `rebind`, `fx`
and `end`; their inputs are requests (`start`, `use`, `choose`, `buy`, `rebind`,
`swap`, `sync`). A `prop` for a pedestal carries the whole party's draft table;
the `mod` event names which body took which row, AI included. Every player's
unlocks and keys are their own machine's ledger.

## The bars over a hostile

`mob_health_bars.gd` draws one bar with `health/max` beside it over every run
hostile that is **below its full pool**: a whole body is never marked, so a fresh
wave arrives clean and only the fight writes anything on the screen. It is one
`Control` and one `_draw()` for the whole island - two rectangles and a small
string per wounded mob - and it draws nothing for a body that is dead, behind the
camera, past 70 m, or on a frame where the draft or the shop is open.

## Files

| File | Owns |
| --- | --- |
| `scripts/roguelite/run_director.gd` | levels, depth blocks, waves, bosses, shops, props, gates, wire |
| `scripts/roguelite/run_player.gd` | one body's upgrades, stats, hand slot and hooks |
| `scripts/roguelite/roguelite_meta.gd` | the player's keys, unlocks, loadout and record |
| `scripts/roguelite/weapon_registry.gd` | every weapon's firing profile and unlock price |
| `scripts/roguelite/mod_catalog.gd` | the upgrade pool |
| `scripts/roguelite/ability_index.gd` | the merged active-skill + ability-upgrade index |
| `scripts/roguelite/proc_engine.gd` | stacking rules and the six event answers |
| `scripts/roguelite/roguelite_stage.gd` | the island: turf, treeline bound, fog, out-of-bounds band and its dressing |
| `scripts/roguelite/roguelite_props.gd` | chest, pedestal, Greed Totem, shop, rack, and the three gate styles |
| `scripts/roguelite/roguelite_hud.gd` | the level plate, upgrade stack, draft and shop |
| `scripts/roguelite/mob_health_bars.gd` | the thin bar and its numbers over a wounded hostile |
| `scripts/roguelite/town_forge_panel.gd` | the rack, its unlocks and the portal page |

## Verifying

```powershell
.runtime/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . `
  --script tests/roguelite_regression.gd
.runtime/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . `
  --script tests/mobile_fire_regression.gd
```

`mobile_fire_regression.gd` is the combat-on-the-move contract beside the run: a
draw started at a sprint or in the air is a draw, a draw held when the body jumps
is still a draw in the air, the shaft it looses leaves from the air, a bow draws
and looses at a run, a skill starts at a sprint and in the air, keeps the sprint
under it and survives the leap taken mid-skill, and a blade comes up to throw and
leaves the hand in the air.

The regression walks a ledger from zero keys through a named unlock, a full
level clear, the shop at 9, the boss at 10 and its keys, the island change at 11,
and the close back onto the square. It also holds the two contracts a run pays
for: a spawned wave has no town safe ring, is hunting the party from the frame it
lands and lands a blow on a standing body, and every gold figure on the plate is
the shared purse the town's vendors spend.

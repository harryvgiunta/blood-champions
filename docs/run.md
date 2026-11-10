# The run — levels, shops, bosses, keys

A Blood Champions run is one endless line of levels. The town is the lobby and
the Weapon Rack is where a player decides what to carry; the Start Run Portal is
where the run begins, and the level's own gates carry it on.

> **Design record:** the Crab Champions-shaped loop — gate contracts, typed
> chests, trials, and the decisions behind them — is in
> [run-loop-design.md](run-loop-design.md). The market cadence is now in this
> file; the gate contracts, typed chests and trials remain proposals. The wider
> feature research is in [crab-feature-backlog.md](crab-feature-backlog.md).
>
> **Pacing note:** our run now has a market at level 6 — after five combat
> levels — and the full shop at 9 of each ten-level block. Crab Champions'
> current biome is five combat islands → shop → elite/boss; the market is the
> mid-block stop that brings the rhythm closer without moving the boss.

## The counters

| Counter | Meaning |
| --- | --- |
| `level` | the global level, 1, 2, 3 … |
| `wave` | the level inside its depth block, 1..10 |
| `stage_index` | the depth block, 0-based (`(level - 1) / 10`) |
| `shop_level` | wave 6 or 9 - no enemies; the market at 6 or the full shop at 9 |
| `market_level` | wave 6 - the smaller market: stall and a reward chest, no Weapon Rack |
| `boss_level` | `level % 10 == 0` - the faction's boss and its escort |
| `level_cleared` | the wave is dead and the rewards stand on the ground |
| `active_contract` | the gate the party took: its trial, biome/faction and promised chest |

A depth block is ten levels and one island's worth of ground; the biome is no
longer a cycle. **Every cleared level stands three gates**, and the one the party
walks through is the biome it fights next: `wilderness` (watchers), `caves`
(demons), `arena` (blood clones). Level one opens in the wood because a run needs
its first door; every door after that is a choice. A gate rebuilds the island
under the party, so the dressing always matches the faction standing on it.

Each gate is a **contract**, not just a door: the biome, a trial, and the next
chest's surface and tier. The three trials:

| Trial | Enemy change | Chest promise |
| --- | --- | --- |
| `open` | none | the gate's own roll: one surface, one tier, one pick |
| `elite` | one extra elite; budget ×0.9 | the same promise, raised one rung (never below epic) |
| `swarm` | budget ×1.5, live cap +6 | the same promise, **2X** (two boxes a player) |

### The chest surfaces

A chest is a **surface** (the category) and a **tier** (the rarity), and both are
rolled per gate, so a party reads three different rewards at three prices before
it picks a door. `mod_catalog.gd` owns the table; a row belongs to every surface
it acts on, so Glass Cannon is a Damage chest's and a Health chest's at once.

| Surface | Reads | Pays |
| --- | --- | --- |
| `weapons` | rows tagged with a weapon family (bow, staff, sword, two_hand, dagger, shield, melee, ranged) | cards |
| `damage` | the damage keys: `damage_mult`, `melee_damage_mult`, `flat_damage`, the conditional and counter multipliers, splashes and bursts | cards |
| `health` | max HP, heals, lifesteal, regen, damage taken, dodge, block | cards |
| `stamina` | the cost/charge economy: ability stamina and cooldowns, the guard's price, the roll's charges, the throw's own kit, movement | cards |
| `speed` | the body's own travel: `move_mult`, the roll's `roll_distance` / `roll_speed` / `roll_charges` / `roll_regen`, the side step's `step_distance` / `step_speed` / `step_recovery`, the slide's `slide_speed` / `slide_duration` | cards |
| `luck` | luck, drops, chests, shop and gold | cards |
| `critical` | crit chance, crit multiplier, mega crit, crit bursts | cards |
| `ability` | no rows | **a skill**, three offered and one kept, permanent for that player |
| `attack` | basic attacks: the shot and hand families, shot shape, swings, on-hit procs and the marks they leave | cards |
| `key` | no rows | 1 / 2 / 3 keys by tier, to the rack's ledger |
| `gear` | no rows | 1 / 2 / 3 armour pieces by tier, off a set floor the tier raises |

The tier is rolled on the island's ladder with the party's best `luck` (island 1
is mostly commons, island 5 can promise legendaries), the elite trial raises it
and the swarm trial doubles the box. A promise is only offered when the surface
can lay out a whole hand at that tier (`Mods.SURFACE_MIN_ROWS`, 3), so a chest
never promises three cards it cannot pay. Greed is never a promise: it arrives at
a boss's hoard and the stall.

A card surface lays out three rows a body - one more per `Big Chests` stack, one
fewer per `Hoarder` - filtered to that body's hands and to what it has not maxed,
and the body keeps one.

**The ability chest is the exception on both counts.** It is not a card surface:
`PAYOUT_SKILLS` pays out of `ability_rules.gd`, so the ability family's 60 run
upgrades (the throw/roll/guard/parry kit and the weapon kit) stopped being a
promise and arrive off a cache, the stall and the hoard instead. Its three offers
are skills the player has **not opened** - never a starter, never a consumable -
and at least one of them is one the body can perform with the pair it is
wearing (`AbilityRules.fits_gear`, read over the run's own two hands), so the
choice is never a dead card. A player who has opened all 27 is promised an Attack
card chest instead: a box that could pay nothing is not a promise. The chest is
**rare** on the board (`CHEST_SURFACE_WEIGHT`, 0.5, beside the key's) and it is
**forced on the first level of every island**, whatever the door's trial rolled -
the trial still prices the tier, so a swarm gate opens a legendary one.

The `speed` surface is the one that pays on the body's feet rather than on a
weapon: `WarbandBody._tune_movement` reads its keys once a frame and writes them
into `DodgeStep.travel` / `duration` / `recovery`, `DodgeRoll.speed` and `RunningSlide`'s
duration and speeds, while `move_mult` rides the walk's own `move_scale`. What a
speed card buys is therefore measured in metres - 0.30 m of side step, 1.5 m of
roll, a fifth more slide - and the roll's clock is the one figure no card moves,
because the rig animates the roll over `DodgeRoll.DURATION`.

The level's budget is `26 × 1.26^island × 1.13^(wave-1)` times the co-op
multiplier; the contract's trial multiplies it again (`elite` ×0.9, `swarm`
×1.5), and the boss level is the same budget with a ten-point boss taken out of
it first. The budget buys the level's bodies - ten at level one - but they
arrive one at a time: the first after **ten seconds**, then **nine, eight,
seven, six, five, four, 3.2, 2.2 and one**, with every later body of a deeper
queue at the one-second tail. The live cap holds **ten** at the opening depth
block (`+2` per block and per extra connected player, `+6` on a swarm contract),
and a field with nothing on it pulls the next body in at once, so a clean fight
sets its own pace.

## The three gates

| Gate | Biome | Faction | Pool base | Blow base | Speed base | What it fights |
| --- | --- | --- | --- | --- | --- | --- |
| Watchers | `wilderness` | watchers | ×1.00 | ×1.00 | ×1.00 | runts, wardens, bowmen (casting from level 2) and, from level 5, a dedicated caster |
| Demons | `caves` | demons | ×1.45 | ×1.35 | ×1.05 | spawns by the dozen, with goats, succubi, beasts and gargoyles behind them |
| Blood clones | `arena` | clones | ×0.85 | ×0.45 | ×1.00 | rangers with a rolled loadout - their damage is their kit, not a multiplier |

From **level two**, every Hollow **archer** in a wave draws one of the **ranged
fire rites** - Fireball, Ember Rain, or the Ember Staff's **Fire Ray** - in
addition to its bow. Hellfire Breath is left to the caster: its 7 m cone never
reaches the 8-16 m ring the archer holds. The rite runs on its own 11 s clock,
behind the same windup the player can answer; its damage is booked to the wood's
own family (91), and its beam takes every party body in the line. Below level
two an archer carries only the bow. The pick is rolled on the host and carried
in the wave spec, like the caster's, so every peer dresses the same archer.

The watchers' pool also gains a dedicated **caster** from level five: one body,
one rolled fire rite, carried for the whole meet. It costs 4.5 budget (a bowman and
then some) and opens only once the run reaches level five; waves one through
four never roll it. The rite is rolled on the host and travels in the wave spec,
so a co-op guest builds the same caster with the same spell. The beam is the
same `fire_ray.gd` node the player's spell spawns: a fixed 14 m line, 5 damage
every 0.2 s for 1.2 s (30 to every party body still standing in it), booked to
the camp's own damage family (90).

`FACTION_TUNING` is the base; the depth curve is one multiplier on top of it, so
the same gate gets harder as the party goes deeper and no gate is secretly a
harder island at the same level. Demons are the heavy faction - a beast carries
`130 × 1.45` before depth - and their crowd is mostly spawns (`cost 1.0`,
`weight 5` of 15) so there is chaff to crush between the brutes.

The clones are a ranger's own body, so they are priced and armed like one: a
clone costs **14** budget (a warden costs 3), so the base 26 buys two of them,
its pool is 85% of a ranger's and its blows 45% of one. `ranger_clone`
issues its kit by **depth block** - one rung
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
body that stands still and never dodges, the wood's sixteen down it in about
twelve seconds and the caves' twelve in about six. The pit is the duel of the
three gates, and **level one is always the wood**, so the first pit a gate can
hand a party is level two: two bodies where it stood four on an open gate, two
where three on an elite one, three where six on a swarm. The same halving holds
deeper - the island-0 boss closes its block with five clones behind it where it
stood ten - and each of those bodies carries a real kit, a dodge and a guard.

A clone's body is the run's - depth picks its kit, the gate picks its pool - and
its brain is the player's. `CloneAi` (`scripts/clone_ai.gd`) holds **six tiers**,
and every clone the pit spawns is born on `CloneAi.current_tier` (`set_tier`,
`cycle_tier`, `labels`); a body built in a lab may name its own with `ai_tier`
before `configure`, or retune itself live with `set_ai_tier`. A tier touches the
brain and the blow, never the pool, the kit or the rig.

| # | Tier | Swing | Blow | Guard | Reaction | Sidestep | Pace | Turn | Sight | Lead | Cast |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Very Easy | 1.90 s | ×0.55 | 4% | 0.45 s | 3.2 s / 20% | ×0.82 | ×0.55 | ×0.70 | 0.20 | — |
| 2 | Easy | 1.55 s | ×0.72 | 8% | 0.30 s | 2.6 s / 45% | ×0.90 | ×0.70 | ×0.85 | 0.32 | — |
| 3 | Medium | 1.28 s | ×0.86 | 14% | 0.18 s | 2.0 s / 72% | ×0.95 | ×0.85 | ×0.92 | 0.44 | 11 s |
| 4 | **Hard** | 1.05 s | ×1.00 | 20% | 0.10 s | 1.6 s / 100% | ×1.00 | ×1.00 | ×1.00 | 0.55 | 8 s |
| 5 | Very Hard | 0.86 s | ×1.12 | 30% | 0.05 s | 1.25 s / 100% | ×1.06 | ×1.15 | ×1.10 | 0.68 | 6 s |
| 6 | Fuck you | 0.68 s | ×1.30 | 45% | 0.00 s | 0.9 s / 100% | ×1.12 | ×1.30 | ×1.25 | 0.85 | 4.5 s |

- **Swing** is the wait *between* committed blows. The telegraph and the strike
  are the rig's clip and stay as authored: a slow clone is a readable duellist,
  not a different animation. `Hard` sits at **1.05 s** where the pit shipped a
  flat **0.85 s** - a quarter longer between blows, because four bodies on that
  clock were the hardest melee in the game and the owner asked for a duellist's
  fight rather than a blender's.
- **Blow** multiplies what a landed hit takes off, on top of the gate's own
  `damage_scale` (×0.45 for clones). The kit is still the damage.
- **Guard** is the share of telegraphed wind-ups answered with the guard, rolled
  once per wind-up and never again while that swing is in the air, so a fast
  weapon buys no extra rolls. A pit that turned every wind-up into a block was a
  wall of blades a melee ranger could not get a sword through.
- **Reaction** is how much of an attacker's wind-up has to pass before the clone
  may answer it at all - guard or step. A body slower to notice never answers a
  short wind-up, which is what a heavy hand does to a slow opponent.
- **Sidestep** is the gap between steps and the share of answered threats spent on
  the feet rather than on the guard, one roll per telegraph.
- **Pace** scales every speed it keeps (closing run, circling walk, shot lane,
  patrol); **turn** scales how fast it comes about, which is how a shallow clone
  gets walked around; **sight** scales `aggro_range` and never the scene's leash;
  **lead** is the share of a moving target's travel its bow leads.
- **Cast** is a tier of its own: `Very Easy` and `Easy` perform no skill at all,
  and every body from `Medium` up rolls **one item skill** for itself when its kit
  is issued (11 s at `Medium`, 8 s at `Hard`, 6 s at `Very Hard`, 4.5 s at
  `Fuck you` between performances). The roll is seeded off the clone's own serial
  and depth like its kit, so a replica and a reload name the same beat, and it is
  filtered to what the body can actually perform: the kinds a mob can aim and land
  (`melee_arc`, `melee_ring`, `melee_wave`, `barrage`, `volley`,
  `piercing_shot`, `projectile`) on a hand that fits the skill (`fits_rig`), never
  a ward, a backstab or a travelling lunge. `AbilityRunner` owns the beat - its
  cooldown, its stamina, its pose and its cue clock - and the clone owns what a
  beat does: a blade beat is announced through `attacked` on the same road as its
  sword, so the ranger's guard, armour and blood stay the world's business, while
  an arrow is a real shaft and a spell a real orb, both authoritative. A ground
  beat's reach is the wider of the definition's radius and the clone's own blade.

**The band spends the same table.** `SquadDrive` (`scripts/warband/squad_drive.gd`,
the bodies the Gold Recruiter sells) fights on `FIGHT_TIER` - the `Hard` rung - so a
squadmate that has locked onto a target swings on the same 1.05 s gap, answers a
hostile wind-up with the guard on the same 20% after the same 0.10 s of reaction,
spends the rest of its answers on its feet on the same 1.6 s step clock, leads its
arrows by the same 0.55 and performs its item skill on the same 8 s cadence. What a
disposition (`tank`/`melee`/`bow`) still owns is behaviour - the shield it advances
behind, the ground it gives, the skill it reaches for first - and never a clock.

The fire staff a deep clone carries is a caster's sidearm in its hand as in a
ranger's - `STAFF_DATA` gives it **20** damage on a **3 s** clock of its own, and
every staff swing (the cut, the overhead and the stab alike) runs on that clock.

Every hostile's pool is multiplied by the number of **human souls** in the run
(`RunDirector._player_count`, the peers below `ALLY_PEER_BASE`; a body the AI
drives is filed at `ALLY_PEER_BASE` + its mercenary id and is not counted). Two
players - two guests, or a host and a guest - spawn every mob at double health;
an AI squadmate, and every body bought off a shop's recruiter board, swings for
the party without making the island any heavier. The
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

## The recruiter's board

Every market and every shop stands a **recruiter** on the fourth place of the
stop's ring, across from the stall. He sells **bodies**, not cards:
`RecruitCatalog` (`scripts/warband/recruit_catalog.gd`) rolls the row, the
purse pays it and `Warband.hire_recruit` swears it into the warband as a
mercenary the run drives.

**Hearthstead stands the same desk**, at `RecruitCatalog.TOWN_LEVEL`: three rows,
one of each trade, rung-0 kit and the one rolled skill on the card - the same
bodies the first market sells, because the town sells the body and not the
progress. `Warband.town_board()` lays them out (named around the names the band
already carries, re-rolled on every sale) and `Warband.hire` swears one. What the
town changes is what the body *is*, not what it carries: a town oath is the
band's own, so it takes a deployment place and a lethal blow puts it on its chest,
where a run's recruit takes no place and is destroyed where it stands. The kit is
locked either way, and so are the stance and the skill bar - the desk sold a tank
that fights as a tank with the one skill on its card. The oath's price is the
band's own curve (`WarbandVendor.hire_cost`: free while the desk is garrisoning,
dearer past the free places), not the card's archetype price.

| Rule | What it means |
| --- | --- |
| Three rows, always | one of each archetype, in a shuffled order: a **ranged**, a **tank** and a **melee** body. Re-rolled on every level load, off the run's own RNG (`_shop_hires`), so two level-6 markets sell three different recruits and a replayed seed sells the same three |
| Gold, and only gold | the price is the board's own (`RecruitCatalog.price_for`), not the town desk's roster-count curve |
| No deployment place | a recruit is bought *for* the run: `Warband.band_field_count` skips it, `_balance_field` never rolls it into the reserve, and it takes the field on the frame it is paid for |
| No island weight | `_player_count` counts human peers only, so a bought body never doubles a wave's pool |
| Locked kit | `Warband.is_gear_locked` (`WarbandRoster.KEY_KIT_LOCK`): a bought body fights in the hand and the armour it was sold in - no paperdoll press, no pickup, no re-kit, no weapon-set swap. The stance chip and the ability bar are the card's too (`set_disposition`, `set_hotbar_order` and the two hotbar moves all refuse a locked body). The way to a better-armed body is a better-armed hire at a deeper board |
| One skill | the rolled id is written into the roster's key list, which is what stops `SeatLoadout` handing an AI body every skill its hands fit. It is rolled from the archetype's own families, filtered to the kinds a body can land (`AbilityRules.AI_KINDS`) and to what the hands that rolled with it can fire |
| Dies for good | `WarbandBody.permadeath`: a lethal blow destroys the recruit where it stands instead of laying it on its chest, so no chest, channel or town square can stand it back up - the roster's own reap erases the name. Guests keep the downed-and-revived path; a recruit never gets it |
| Paid off | the desk that sold him can release him: `RunDirector.dismiss(merc_id)` -> `Warband.dismiss_recruit` takes the name out of the warband and `WorldScene.dismiss_body` takes the body off the field on the same press, with the run runtime. Only a recruit may be paid off (a sworn mercenary is the band's) and never while a soul is inside the body. The kit leaves with him: it was sold with the body and locked to it, so a dismissal that fed the shared stash would be a way to buy steel for a recruit's price and keep the piece |

The three archetypes are the campaign's own dispositions, so the way a recruit
fights is the squad's code, not a fourth brain: a ranged body is a `bow`
disposition (back line, gives ground when crowded), a tank is `tank` (holds the
line behind its shield, never falls back) and a melee body is `melee` (presses
the densest knot, falls back under 30% to bind a wound). All three fight on
`SquadDrive.FIGHT_TIER` - the clone ladder's `Hard` rung, see [the band spends
the same table](#the-run--levels-shops-bosses-keys).

### The ladder, levels 1 to 50

Five rungs of ten levels - the same blocks the islands are cut into - and a rung
is a *kit*, not a stat block: the same hundred-health body is a twig bow in rags
on level 6 and a longbow in leather on level 46.

| # | Levels | Ranged (leather) | Tank (mail, then plate) | Melee (mail, then plate) |
| --- | --- | --- | --- | --- |
| 0 | 1-10 | twig bow, makeshift armour | club or cleaver + wooden board, makeshift | heavy branch, or cleaver + ironwood shiv |
| 1 | 11-20 | shortbow | shortsword + buckler | shortsword + shiv, or cleaver + iron dagger |
| 2 | 21-30 | shortbow or recurve | arming sword + kite shield | arming sword + iron dagger, or shortsword + iron dagger |
| 3 | 31-40 | recurve | arming sword + kite or tower shield | greatsword, or arming sword + iron dagger |
| 4 | 41-50 | recurve or longbow | arming sword + tower shield | greatsword, or arming sword + iron dagger |

The opening is deliberately poor: rung 0 is the salvage tier a prisoner climbs
out of a cage with, because the first board a party sees is meant to sell a body
its own arming has to carry. Price is `base + step x (level - 1)` with a rung
premium on top - `120 + 9` a level for a ranged body, `140 + 10` for a tank,
`135 + 10` for a melee body - and it stops rising at level 50. A level-6 board
asks 165-190 gold a body (the rung-0 premium is zero); a level-49 board asks
about 1,770 for a bow, 2,090 for a melee body and 2,110 for a tank.

The rolled skill is one of the abilities the archetype's families own that no
hand grants for free: a ranged recruit rolls from `snap_shot`, `barrage`,
`triple_volley`, `piercing_shot`, `rain_of_ash` and `skewer`; a tank from the
sword and shield rows; a melee body from the two-hand, sword and dagger rows.

## Level flow

1. The gate taken stands the party on the island and queues the wave after a
   1.6 s beat. Mobs feed in from the queue at the live cap.
2. The queue empties and every mob is dead → `_clear_level`.
3. `_clear_level` pays gold, stands the **contracted chest** (surface and tier
   from the gate taken; a boss leaves its own hoard) and the extra chests - one
   cluster a few paces wide (`stage.reward_point`) - and then the three gates in a
   shallow arc one short walk past it (`_gate_point`, 9.5 m, 24° apart). A `2X`
   contract stands the same promise twice. A chest is stood **one a soul**: each
   player gets their own box, wearing their name on its plate, carrying their own
   three cards, and only they can open it (`_stand_chests`).
4. A card chest offers three rows from its promised surface and tier; each body
   takes one, so the chest is both the level's reward and its upgrade choice. A
   Key chest banks its keys and a Gear chest pays a piece a tier on the open, off
   a set floor the tier raises (see [the Gear chest's armour](#the-gear-chests-armour)).
   The first of the level's main chests to open raises the downed at half health;
   the gates unseal when every player has opened their own box. The AI bodies take
   a random row the moment the level clears, and the humans choose when they walk
   up to their own chest. A gate's press is the host's: it advances one level,
   fixes the biome, and applies the contract's trial to that level.
5. After five combat levels, level 6 is the **market**: a smaller stall and a
   reward chest stand where the wave would, with no Weapon Rack; the three gates
   past them lead back to the road at level 7.
6. Level 9 is the full **shop**: the stall, the Weapon Rack and a reward chest
   stand where the wave would, with the three gates past them; each gate leads to
   the boss, in that gate's biome. The stop's chest rolls its own surface and
   tier from the route, so a market or shop level still pays the run.
7. Both stops stand a **recruiter** on the fourth place of the cluster's ring,
   across from the stall: three bodies for sale, bought for gold (see [the
   recruiter's board](#the-recruiters-board)).
8. Level 10 is the boss. The boss pays `3 + island / 2` unlock keys; nothing else
   in the game pays keys.
9. The level after a boss crosses into a new depth block: a new island is built
   under the gate taken, the party is moved in, and level 11 begins.

Nothing dead follows the party: `_begin_level` clears the field through
`_free_mobs`, which frees the living **and** the corpses they left, so a
five-minute corpse lies for the level it fell on and never into the next one.
An elite's `ELITE`/`BOSS` tag is not part of that corpse - `CorpseHold`
drops it on the death itself, so the hold never keeps a rank over a body that
has stopped fighting.

There is no final level. A wipe - a live wave with nobody standing - ends the
run, books the deepest level on the player's ledger, and returns every body to
Hearthstead.

## The admin console (`F9`)

The host's debug door onto the loop, never a rule of it. `F9` raises it in the
town or on an island, `F9` or `Escape` sets it down; it is a `LedgerFrame` over
the same page every other window uses. Every press is a call the loop already
makes - the console owns the window, not the state - so a granted row is the row
a chest pays and a re-stood gate is the gate `_spawn_gates` builds.

| Board | What it does | The call behind it |
| --- | --- | --- |
| THE ARENA | `KILL EVERYTHING` kills every hostile on the field, empties the inbound queue and lets the level clear; `GOD MODE` is `WarbandBody.god_mode` - a body under it takes no blow, is never put down, and pays no bounds price; the gates' and the chest's **re-spawn** stand last level's board again, the **roll** draws a new one | `admin_kill_all`, `admin_stand_gates`, `admin_stand_chests` |
| UPGRADES | Every row in the pool, its family, tier and stacks against its cap, with `INERT` on the rows no subsystem reads yet. A click grants one stack, Shift-click fills to the cap. A row the body's hands do not fit is written anyway: the console is the one place a debug row can be read | `admin_grant_mod` |
| WEAPONS | Every piece in the armory, its hand and its key price or `OPEN`, and `IN HAND` on the pair the body carries. A click opens the piece on the player's ledger, forges it into the stash and wears it in the hand its class belongs to - on the island through the run's own re-dress, in the square on the roster | `admin_give_weapon` |
| ABILITIES | Every combat skill, its family, whether it is open and whether it is on the bar, with `HANDS:` on the rows the body's kit cannot perform. A click opens it and puts it on the bar; an already-equipped row is taken off. A skill the hands do not fit is still opened, and the refusal to equip is what the line says | `admin_give_ability` |
| TRAVEL | `TO HEARTHSTEAD` closes the run without booking a wipe; `NEXT LEVEL` and `NEXT BOSS` jump the counters; a floor box stands the party on any level. A jump across a depth block rebuilds the island, and the floor landed on carries the surface and tier the route rolls for that depth | `admin_goto_town`, `admin_goto_level` |

A re-stood chest is fresh: its books are cleared, so every box is stood again for
its soul with its own three cards and may be opened again. A **rolled** chest
re-rolls the promise itself and writes it back into `active_contract`, so the
level is paid by the box it now shows. A **rolled** gate bumps `_gate_salt`, the
one thing that moves the route board's seed, which is otherwise deterministic in
`run_seed` and the level.

The console is the **host's**: on a guest every arena press is refused with that
line rather than half-applied on a machine that does not own the level, the mobs
or the rolls. The two catalogues still read there, and the ledger grants are the
player's own.

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

The Hollow Beneath is the exception: it is not an island but a sealed chamber of
the cave (below), so `stage.contains()` is the room's own rectangle and there is
no band to walk into.

## The Hollow Beneath

The demons' island is not built from primitives on a disc. It is one room of the
Weeping Hollow's own authored cave plan, cut out and stood on the lift:
`cave_plan.gd` is the floor's data (eleven areas, every room's rectangle and
ceiling, the ways between them, the lights and props), `cave_floor.gd` the
ground, `cave_rock.gd` the wall skin and vaulted roof over its colliders, and
`cave_dressing.gd` the dripstone, fog fungus, ropes, lights and props.
`cave_room.gd` builds exactly one of the plan's halls, shuts every way out (the
rock is drawn straight on across each opening, with a collider and the rubble
that came down with it), and hands the stage the points it needs: the party's
entry line, wave posts, the reward cluster and the three gates. The room is drawn
from the run's seed when the island is rebuilt - when the biome changes or a new
depth block begins - and the same chamber holds for every level fought on it.

Only the plan's halls are drawn, never its ways through or the add-ons cut onto
them: `CaveRoom.room_ids()` keeps rooms at least `MIN_SIDE` metres across either
way, which is the party's own three-body line (`SPREAD`) plus the wall margin at
both ends and a stride of floor past each to circle round - 18 m on the built
plan. The apses, the niches and the glades come out at 6 m to 16 m across: they
are rooms a party walks through, and a line landing in one stands against the
rock with the gates on top of its own posts. Every area keeps at least one hall
in the pool, so the draw still names all eleven of them.

The room carries its own air: `stage.air()` is the camera's environment while the
party is below, and the world's sky comes back the moment the run leaves.

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

- the starters (`bow_long`, `hatchet_makeshift`) are free and always fieldable;
- every other weapon is locked until the rack is paid its `unlock_cost`;
- the key balance is global to the player, not the run;
- the two hands a run carries are the two weapon sets' worn pieces, read out of
  the warband's inventory;
- `best_level` is the record.

| `Warband.gold()` (a keeper's counter) | the band's **medicine**, kept in `Warband.supplies`: `bandage` and `potion` counts, bought at the town's counters and spent by the two consumable keys. It is not a stash row - a dressing is tied onto a body and a draught is drunk |

### What the keepers sell

The town's four counters (`PlayerState.VENDORS`' three stalls and the
quartermaster's desk) sell **medicine and nothing else**: a linen bandage and a
healing draught, each out of the shared purse and into the band's own pack
(`Warband.supplies`), where `Z` (bandage) and `V` (draught) spend them
(`WarbandBody.try_consume` - a key with an empty pack does nothing, and the GEAR
page counts what is left). There is no
steel and no plate on any board: `Warband.buy_gear` refuses any catalogue row
without a `supply`, so a weapon or a piece of armour cannot reach a hand by
purchase. A piece of steel comes from the rack's unlocks; a piece of armour comes
out of a run's chest. The square hands over **no spares** either
(`TownHub.seed_warband` seeds the body's starter pair and nothing else), so a
fresh warband's collective stash is empty - it holds only what a body gathered
during play. The character screen (`I`) shows that stash as its INVENTORY page:
a grid of the game's own rendered item icons, a hover card for the words, and a
right-click menu whose one action is SELL.

### Worn slots

Seven, and they are steel and armour: `head`, `chest`, `hands`, `legs`, `feet`,
`main`, `off` (`EquipmentRules.SLOTS`, `WarbandContracts.SlotType`). There is no
neck and no ring: an accessory is not worn any more, so a run's upgrades are the
whole of what a body grows, and the only carried passive left is the off hand's
skull (`TrinketStats.STATS`). An old save's `neck`/`ring1`/`ring2` ids read as
unknown and contribute nothing.

The rack (`town_forge_panel.gd`) lists **every** weapon, locked or not. A locked
row is a button: it spends the piece's price, opens it for the player, forges it
into the collective stash and wears it in the hand the row names. An open row
wears a piece the stash already holds - and forges one a pre-stash ledger opened
but never booked. There is no roll, no random pool and no totem, and nothing is
carried that the inventory does not own. A fresh ledger carries no keys, so a new
player fights the first boss with the starters and unlocks their first weapon
after it.

## Upgrades

The run's modifiers (`mod_catalog.gd`, `proc_engine.gd`, `run_player.gd`) are
the upgrades. They are scoped to the run, stack by the engine's own rules, and
are the run's growth - the chest and the stall are what deal them, and the chest
is the only one that deals a choice. The altar's
item-welded annointments are not part of this game: the town has no altar, the
character screen has no bench, and the starting band carries no weld.

**A chest is stood for one soul.** Clearing a level walks a box out for every
player: it wears that player's name and colour on its own plate, it carries that
player's cards, and only they can open it - another soul's press is answered with
whose box it is (`_stand_chests`, `_open_chest`'s owner check).

A box draws a row of cards **for the soul it stands for** (`RunPlayer.chest_draft`,
on that body's own engine rng, excluding what it has already maxed): three of
them, one more per `Big Chests` stack and one fewer per `Hoarder`, all from the
surface and tier the gate promised - or, at a market or shop stop, the surface
the route rolled for that level. Not one row the party shares. The table rides
the chest's payload as `offers`, so every machine shows its own body's cards and
a guest's `choose` names its own row. A body no peer is inside is AI: it has no
box of its own and takes a random one of its cards off the host the moment the
level clears (`_draft_ai`), booked like any other choice. The `2X` contract
repeats the whole box - gold and its own three cards - once more for every
player, so two players under a swarm gate walk up to four chests. A boss's hoard
keeps the old single auto-roll because a boss promises nothing, and it is stood
a soul as well.

The pool is 172 rows over five families and four tiers (`mod_catalog.gd`), and a
tier is an acquisition rule rather than a colour: a gate spends a *promise* -
`Mods.roll_promise` settles the surface and the tier, `Mods.deal` lays that tier
out and nothing else. Only an unpromised shelf rolls the ladder
(`Mods.roll_shelf`; `SOURCE_CACHE` is commons and epics, a legendary from island
4, greed from island 2), and a boss's hoard always writes one legendary down.
The stall sells all four from island 3, at `22 + 5 x level` plus a per-tier
surcharge. A piece's welded
modifiers roll on their own narrower ladder (`SOURCE_WELD`: commons, epics from
island 2, never a legendary), so a weld can never be the ceiling the chest itself
withholds. [`upgrade-pool.md`](upgrade-pool.md) is the design record, including
the 31 rows whose keys are still pending (the mark ledger and the verb upgrades'
roll/parry/guard hooks) and which are therefore marked `ready: false` and never
offered.

### The Gear chest's armour

Armour is the **Gear** surface's business (`armor_loot.gd`,
`RunPlayer.wear_armor`): a Gear chest pays one piece a tier - one on a common
promise, three on a legendary - and the tier is the set floor, so a legendary
Gear chest can put mail on a body on island 1. A surfaceless cache and a boss's
hoard still pay one piece; a card or a key chest pays none. The slot is random;
the set comes off the level's ladder (makeshift and leather on island 1, mail
from island 2, plate from island 4, all of it by island 5), raised by the
promise's own rank, and is never worse than the piece the body already wears
there. Naked and cloth are never rolled: one guards nothing and the other is the
town's own robe.

The piece is the run's, not the roster's: it rides `RunPlayer.armor`, so a hand
swap re-dresses it, and `_close_run` hands the campaign's kit back through
`refresh_gear`. The rig wears the set, so the reduction is live
(`ArmorData.reduction_for`), and the pop leaves the lid, hangs with the piece's
name and level over it, and flies into the opener - the host draws it when it
rolls and every guest draws the same one from the `armor` event.

The character screen's GEAR page (`I`, `warband_paperdoll.gd`) reads the run's
armour over the wardrobe for the body inside it: each won slot names its piece
and level, the row carries a `RUN` mark, and the portrait wears the same set. A
run slot is read-only - its menu says the piece leaves when the run ends -
and `WarbandPaperdoll.run_armour` (`world_scene._run_armour_for`,
`RunDirector.armor_for_merc`) is the one lookup. Closing the run repaints the
page back to the wardrobe's own kit.

A piece carries **one to three welded modifiers** on a chance that starts at 6%
on level 1, grows a point a level and caps at 35% (level 30); the second is
rolled at 25% and two points a level, the third only from level 10. The rows are
ordinary upgrades (`Mods.roll_shelf` on `SOURCE_WELD`, filtered to what the
body's hands fit and to what it has not maxed), they are taken the moment the
piece is worn, and the HUD lists them by name like any other row. A replaced
piece does not unweld what it gave: the run keeps its stacks, exactly as the
chest's own single mod is never taken back.

### The hands the page shows

The inventory is the one source of truth, and the run reads it directly. The
body's two weapon sets are the run's two hands: each set offers its main hand, or
its off hand when the main is bare, and `WeaponUnlockRegistry.hand_pair(roster,
merc)` classifies the pieces by what they are - a bow or staff is the ranged hand,
a blade or dagger the melee hand. A kit that does not fill both classes still
carries what it has, and a bare hand stays bare; no default pair is ever invented.

While a run owns the body, `WarbandPaperdoll.hands_for`
(`world_scene._hands_for`) answers `{main, off, slot, source}` with that same pair:
`main` is the piece the hand is holding (`_active_slot`) and `off` the other one
`TAB` reaches. The row carries a `RUN` mark, and its menu says the run's hands are
the body's kit: `TAB` on the island brings the other piece up.

Outside a run the hand rows are the roster's own worn kit, as any other slot is:
the square's body holds the piece its hands carry, and `TAB` swaps the two weapon
sets. A click on a worn slot lists the pieces the warband owns that fit it, and
choosing one wears it through `Warband.equip_merc`; the rig is dressed from the
roster on the same frame, so what the page shows is what the body holds. A hand
row inside a run is read-only: the pair comes from the kit, and `TAB` brings the
other piece up.

The rack writes the same inventory. Its ranged page wears the piece in the body's
first weapon set and its melee page in the second (`Warband.equip_hand`); an
opened row the stash does not hold yet is forged into it first (`Warband.grant_gear`),
and a piece the warband does not own is refused like any slot press. There is
no separate loadout ledger to fall out of step with what the player wears.

## Abilities

Every combat skill is a **player-level unlock** and it is **found in a chest**,
not bought: an ABILITY chest stands three skills a soul has not opened and the
soul keeps one, for good. That chest is rare on the gates and it is **the first
chest of every island** - the run opens by handing the player a skill before a
wave asks them to build a hand around one, and each new depth block starts the
same way. At least one of the three always fits the pair the body is wearing, so
the choice is never a dead card; the other two may be for hands the body does not
carry yet, which is also a reason to change them.

The rack's `ABILITY BOOK` page no longer prices anything: it lists the skills the
player has opened, and it puts one on the body's bar (or takes it off). The bar
itself is the character screen's SKILLS page: **five keys**, one assignment per
key, and a key the player leaves empty stays empty - the families the current
hands fit decide which assignments are actually drawn there. The family starters
(below) are automatic: they fill the first free keys behind the assignment and
are never assignable. Medicine is not on the bar at all - `Z` binds a wound and
`V` drinks a draught, from the band's stock, on their own cooldowns. A legendary
upgrade, **Widened Bar** (`widened_bar`, +1 per stack, five stacks), buys the run
one more key a stack, so a session's bar can reach **ten** - and never more.
`AbilityRules.SLOT_COUNT` is five, `MAX_SLOT_COUNT` is ten, and
`AbilityRules.granted(rig)` is the one layout the HUD, the runner and the
replicas read.

The screen's **UPGRADES** page is the pool itself, read straight off
`Mods.all()`: family by family (`Shot`, `Hand`, `Ability`, `Perk`, `Relic`), one
row per row the game can offer (`Mods.ready_of`), with its rarity, its ceiling
(`Mods.max_stacks`) and the sentence the pool writes as its description. The rows
the run has taken are marked `TAKEN ×n` from `RunDirector.upgrades_for_merc`, and
the census over the list counts the live rows and the taken ones. It is a
catalogue: nothing on it is pressed, and a row whose keys no subsystem reads yet
is not listed.

The body's current hands decide which families can be assigned and which
assigned skills are actually on the bar:

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

### The 36 active abilities

The Ability Book lists these skills, grouped by the family that performs them.
**Eight are free starters** - one per family, marked `*` - and are automatic:
no chest ever offers one, and the hands earn them. The other 28 are opened by
ABILITY chests. A body that fits more than one family draws each fitting
starter.

| Family | Abilities |
| --- | --- |
| `unarmed` | Charge* |
| `bow` | Snap Shot*, Barrage, Triple Fan Volley, Long Piercing Shot, Rain of Ash, Skewer |
| `sword` | Quick Cut*, Double Slash, Lunging Thrust, Butcher's Cut, Gut Hook |
| `two_hand` | Heavy Swing*, Spinning AOE Spin, Ground Breaker, Wide Sweep, Executioner |
| `dagger` | Quick Stab*, Backstab, Knife Work |
| `staff` | Fireball*, Bone Spear, Cinder Lance, Fire Ray, Grave Bloom, Ember Ward |
| `shield` | Shield Shove*, Headbutt, Shield Charge, Ground Shield Slam, Rebuke |
| `any` | Focus*, Dash, Energy Shield, Three Strike, Stone Skin |

### The ability upgrades

The pool's `ability` family is **60 rows**: the 19 old verb upgrades (throw, roll,
guard, parry) are still pending, and 41 live weapon-family rows upgrade the
active skills. Every live row writes a tagged key the ability runtime reads;
`ProcEngine.stat_for(family, key)` is the one lookup, so a bow row never reaches
a staff cast. The 41 by tag - every row's id, tier, cap and write keys is in
[`upgrade-pool.md`](upgrade-pool.md) under *Ability weapon*:

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

The pool is now **173 rows**: 30 shot, 11 hand, 61 ability, 59 perk, 12 relic.
**142** are live; the 31 pending rows are the 19 verb upgrades and the 12 mark
rows. `scripts/roguelite/ability_index.gd` joins the two catalogs: 36 active
skills + 61 ability upgrades = 97 categorized rows, each with a `kind`
(`active` / `upgrade`), a `family`, and a `tags` or `verb` category.
`AbilityIndex.find(id)` answers which kind owns an id; ids never collide. The
Ability Book reads the active half; the chest's draft and the card read the
upgrade half.

A body may store both a bow row and a sword row. Each key holds the skill the
player put on it, and the bar draws only the keys its current weapon set fits -
a bow skill waits on its key while the sword is out and comes back with the bow.
The family starters are drawn in the first free keys when the hands fit. Assign is
a request like every other gear verb, so a guest's press travels to the host.

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

**Fire Ray** is the one held spell: the cast spawns a beam that re-reads the
staff head and the live crosshair every frame, stops at terrain, and burns every
body its line crosses on a fifth-second tick. Its `damage_scale` is a share of
the staff's base **per second** rather than per hit - 50 damage a second off the
Ember Staff's 50 - for the 1.2 s the cast holds, so stepping out of the line is
what answers it. A recast from Echo Cast stands a second ray down the same line.

An **axe** doubles every blade skill it performs (`AbilityRules.AXE_ABILITY_SCALE`,
keyed on the piece's class rather than its catalog id): the hafted head carries
the weight, which is the same bargain as the double it lands when thrown. Swords
and the blunt tier are untouched, and the dagger's own backstab is never doubled
by the other hand's axe.

The bar is **five keys**: the player assigns a skill to a key from the character
screen's SKILLS page, and that skill fires from that key; the **family starters**
the hands earn (each marked `*` above) fill the first free keys behind the
assignment. The starters are laid on the body a peer is inside - in the square, in
a run and out in the wilderness (`ability_rules.gd`; the seat dress asks
`_peer_driven`). A body dressed without `starter_ability` - a mob, a cloned
ranger, a caged soldier, an allied merc - has none; an allied AI body with no
player's list behind it is instead dressed with every skill its own hands fit
(`SeatLoadout._default_abilities`). The bare-hand Charge is the unarmed starter, so
an empty hand still has one key. Medicine is not on this row: `Z` and `V` are the
body's own two keys, on their own cooldowns (`WarbandBody.consume_ready`). A
legendary upgrade, **Widened Bar**, buys the run one more key a stack, so a
session's bar can reach ten (`AbilityRules.MAX_SLOT_COUNT`) and never more.

## Multiplayer

The host owns the seed, the island, the level, the queue, the props, the rolls
and every damage number. Guests receive `state`, `prop`, `prop_gone`, `mob`,
`mod`, `keys`, `gold`, `sold`, `revived`, `unseal`, `hands`, `rebind`, `fx`
and `end`; their inputs are requests (`start`, `use`, `choose`, `buy`, `rebind`,
`swap`, `sync`). A `prop` for a chest carries its owner's draft only - a box is
stood for one soul - and the `mod` event names which body took which row, AI
included. `revived` goes out when the first of the level's main boxes opens;
`unseal` when the last one does. Every player's unlocks and keys are their own
machine's ledger.

**A joining player is their own character.** The host swears a body for the name
they joined with (`Warband.enlist_player`: the name, the pair a new game opens
with, a place on the field outside the band's deployment cap, no gold) and its
session seats that soul in it and nothing else. The mercenaries the Gold
Recruiter sells stay the host's AI allies: the board is the host's desk on every
other machine (`WarbandScreen` closes its rows on a lent warband), a guest's
`hire` is refused, and a guest's soul never cycles into one when its own body
dies (`PossessionController.cycle_on_death` -> `WarbandSession.may_cycle_from`).
A character that falls is not replaced on the field; the town square is where a
replacement is sworn (`WarbandSession._body_for_soul`).

**The town keeps its own.** A party may fight in the square, so the ground under
it has a rule of its own: a body knocked down on town ground is never finished,
its bleed clock stops killing, and when the clock runs out the town stands it back
up on the contract's revive share (`WarbandBody.home_ground`, set where the body
fell). The other soul's five-second channel still works there and is the fast way
up, and a party with every body on the floor in the square is not a wipe - the
checkpoint is not reloaded under the lobby. Off the square the campaign's rule is
unchanged: the clock kills, and the chest is the way back up on an island.

## The bars over a hostile

`mob_health_bars.gd` draws one bar with `health/max` beside it over every run
hostile that is **below its full pool**: a whole body is never marked, so a fresh
wave arrives clean and only the fight writes anything on the screen. It is one
`Control` and one `_draw()` for the whole island - two rectangles and a small
string per wounded mob - and it draws nothing for a body that is dead, behind the
camera, past 70 m, or on a frame where the draft or the shop is open.

## The furniture, and the cards

The props and the draft used to be `Geo.box` shapes with flat `StandardMaterial3D`
colours and a `Label3D` holding their name. They are now authored, textured
surfaces - two Blender pipelines, one command each.

**The chests** (`assets/props/chests/`, `python tools/build_reward_chests.py`):
three variants - `Chest_Island`, `Chest_Cache` and `Chest_Hoard` - built in
`tools/prepare_reward_chests.py` as planked bodies under a staved vault, bound
with riveted iron straps, corner brackets and ring handles, and locked under a
gilded hasp. Four materials are baked in Cycles from a dense displaced copy:
wood (2048), iron (1024, glTF metal 0.62), gilt (1024, metal 0.72) and the stone
(512) which is the only emissive surface. The maps are pigment and tangent relief
only - no light is baked into a colour map. The metals keep a dielectric floor on
purpose: a fully metallic trim has nothing but reflections to show and this wood
gives it none at night.

`scripts/roguelite/chest_visual.gd` instances the GLB, keeps the one variant the
prop asked for, tints the stone and its lamp to the promise's tier and breathes
them, so a legendary promise is readable from the entry line. Presentation only:
the director still owns the reward.

**The cards** (`assets/ui/cards/`, `python tools/build_reward_cards.py`): the
draft and the shop are one row of three `RogueliteRewardCard`s
(`scripts/roguelite/reward_card.gd`), not rows of `Button.text`. A card is the
rarity's rendered plate (9-sliced, 48 px border, edge strips averaged so a
stretched edge never smears) under the family's rendered sigil, with the name in
the display face, the hand and tier in small caps, the catalogue's description
wrapped under a rule, and the count or the price at the foot. `RogueliteCardArt`
reads `cards.json` once; a rarity with no render falls back to `neutral` rather
than drawing a blank plate.

**The gates** (`assets/props/gates/`, `python tools/build_gate_assets.py`):
the three doors the run opens - `Gate_Watchers` (coursed granite, corbels, a
keystone), `Gate_Demons` (broken basalt hung with skulls, talons and ribs,
toothed lintel) and `Gate_Clones` (a body turned inside out: swept columns, a
bone ribcage, a heart in an iron ring). Five baked materials: granite 2048,
basalt / bone / flesh / iron 1024, iron at glTF metal 0.55. The footprint is the
primitive gate's it replaced - posts on x = ±1.30, lintel at 3.4 m, an opening
2.2 × 2.9 m - so gate spacing, interaction framing and the plates above it did
not move. The sheet is not in the GLB: its colour is the biome's promise, so
`scripts/roguelite/gate_visual.gd` lays a quad in the opening and owns the lamp.

**The plaques.** Every prop hangs its name on a rendered plate
(`RogueliteProps._plaque`): the tier's `plaque_<rarity>.png` as a camera
billboard with the words laid over it in the display face, the type scaled to fit
its bar. A chest's plate is a little wider than the box it names; a gate's is two
plates, the biome over the contract.

Rebuild either pipeline with its command, then reimport (`--headless --editor
--path . --import`). Both manifests carry the Blender version, the seed and the
digest of every output.

## Files

| File | Owns |
| --- | --- |
| `scripts/roguelite/run_director.gd` | levels, depth blocks, waves, bosses, shops, props, gates, wire |
| `scripts/roguelite/run_player.gd` | one body's upgrades, stats, hand slot and hooks |
| `scripts/roguelite/roguelite_meta.gd` | the player's keys, unlocks and record |
| `scripts/roguelite/weapon_registry.gd` | every weapon's firing profile and unlock price |
| `scripts/roguelite/mod_catalog.gd` | the upgrade pool |
| `scripts/roguelite/ability_index.gd` | the merged active-skill + ability-upgrade index |
| `scripts/roguelite/proc_engine.gd` | stacking rules and the six event answers |
| `scripts/roguelite/roguelite_stage.gd` | the island: turf, treeline bound, fog, out-of-bounds band and its dressing, or the Hollow's chamber |
| `scripts/roguelite/cave_room.gd` | one room of the Hollow, cut from the plan, sealed, and every fight point on it |
| `scripts/world/cave_plan.gd` | the Hollow's authored plan: areas, rooms, shafts, dens, lights and props |
| `scripts/world/cave_floor.gd` | the cave floor's surface and its collider |
| `scripts/world/cave_rock.gd` | the rock skin, lintels and vaulted roof over a room |
| `scripts/world/cave_dressing.gd` | the dripstone, fungus, ropes, lights and props a room is dressed with |
| `scripts/roguelite/roguelite_props.gd` | chest, shop, rack, the three gate styles, and the plate every prop hangs its name on |
| `scripts/roguelite/chest_visual.gd` | the imported chest: variant, tier-tinted stone and lamp |
| `scripts/roguelite/gate_visual.gd` | the imported gate: variant, the biome's sheet and its lamp |
| `scripts/roguelite/reward_card.gd` | one upgrade or ware as a card |
| `scripts/roguelite/card_art.gd` | the card manifest: rarity frames, family sigils, world plaques |
| `scripts/roguelite/roguelite_hud.gd` | the level plate, upgrade stack, and the draft and shop card boards |
| `scripts/dodge_roll.gd`, `scripts/dodge_step.gd`, `scripts/running_slide.gd` | the roll, the grounded side step and the sprint slide, each taking the run's Speed keys through `WarbandBody._tune_movement` |
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
level clear, the gate contracts and their one-each trials, the typed chest and
its three promised offers, the market at 6, the shop at 9, the boss at 10 and
its keys, the island change at 11, and the close back onto the square. It also
holds the two contracts a run pays for: a spawned wave has no town safe ring, is
hunting the party from the frame it lands and lands a blow on a standing body,
and every gold figure on the plate is the shared purse the town's vendors spend.

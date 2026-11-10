# The upgrade pool — Crab Champions, re-cut for the warband

Production record. The pool in this document **is** the pool in
`scripts/roguelite/mod_catalog.gd`: **161 rows**, four tiers, five families, and
the tier ladder each loot surface rolls. The first 120 rows are the re-cut below;
the last 41 are the live weapon-family ability upgrades added by the ability
pass (`family: ability`, `tags` bow/sword/two_hand/dagger/staff/shield/any/melee/
ranged). Where a number here is live in that file the
row is marked **PINNED**, because `tests/roguelite_regression.gd` asserts it.

Phases 1 to 3 of the plan at the end are landed and the whole regression passes.
Phases 4 and 5 - the mark ledger and the verb rows' roll / parry / guard hooks -
are not, so the 31 rows that need them are in the pool and carry `ready: false`:
they are never offered until their keys are read. The 41 ability rows are live.
That gate, and the **130 live rows** the surfaces do offer, are the two places
this document and the code could drift, so they are pinned by the regression's
own census check.

The job was three parts: lift every upgrade off
[crabchampions.wiki.gg](https://crabchampions.wiki.gg), store it so it can be
queried, and re-cut it into a pool that fits a bow-and-hatchet roguelite in a
walled town. The source is a 295-row pool across four tiers and five families.
The original re-cut is 120 rows across the same four tiers and five equivalent families,
inheriting the source tier row for row.

## The source, and where it is stored

`tools/upgrades/fetch_crab_champions.py` pulls every upgrade on the wiki into
two committed files, and regenerates both on demand:

```powershell
python tools/upgrades/fetch_crab_champions.py          # refresh
python tools/upgrades/fetch_crab_champions.py --check  # exit 1 if the wiki moved
```

| File | What it holds |
| --- | --- |
| `tools/upgrades/crab_champions_upgrades.json` | 314 rows: 295 live, 19 the wiki files as removed |
| `tools/upgrades/crab_champions_upgrades.csv` | the same rows flat, for spreadsheets and `grep` |
| `tools/upgrades/fetch_crab_champions.py` | the extractor: five index pages, one block per upgrade |

One row, verbatim from the JSON:

```json
{
 "id": "perk:mango",
 "name": "Mango",
 "article": "Mango",
 "family": "perk",
 "section": "Health",
 "rarity": "common",
 "rarity_colour": "#14b1f5",
 "spawn_weight": 1.5,
 "buff_scaling": "linear",
 "debuff_scaling": null,
 "tag": null,
 "tagline": "Healing is more effective",
 "effects": ["Add 250 to your base max health with each level"],
 "sources": "Appears in health and random chests, as well as loot, chance, gamble, and random totems",
 "live": true,
 "source_url": "https://crabchampions.wiki.gg/wiki/Mango"
}
```

The fields that matter downstream, and how they were read:

| Field | Read from | Why it is trustworthy |
| --- | --- | --- |
| `rarity` | the colour of the `font` tag wrapping the name | the only machine-readable rarity on the page; prose calls the common tier "rare" in places, the colour does not |
| `spawn_weight` | the `Spawn weight:` bullet | the wiki states it per row, 1.0 default, 1.5-2.0 on the plainest commons, 0.2 on relics |
| `buff_scaling` / `debuff_scaling` | the `Buff scaling:` / `Debuff scaling:` bullets | `linear` for near everything, `hyperbolic` for percentage and chance effects |
| `section` | the `== Damage ==` / `== Health ==` heading it sits under | the wiki's own grouping, nine groups |
| `live` | the `Indefinitely Removed` and `Removed Weapon Mods` headings | 19 rows the game no longer fields |

Query it without loading the whole file:

```powershell
# every legendary perk, cheapest first
jq -r '.upgrades[] | select(.family=="perk" and .rarity=="legendary")
       | "\(.name)\t\(.effects[0])"' tools/upgrades/crab_champions_upgrades.json

# the rarity census
jq -r '.upgrades[] | select(.live) | "\(.family) \(.rarity)"' `
  tools/upgrades/crab_champions_upgrades.json | sort | uniq -c
```

`--check` exists because a wiki is not a repository: it fetches, compares row by
row against the committed JSON, prints what moved and returns 1. Nothing in the
game reads these files; they are the design record.

## The source system

### Four tiers, and what each one means

| Tier | Colour | Rows | Share | In their words |
| --- | --- | ---: | ---: | --- |
| common | `#14b1f5` | 116 | 39.3% | the bulk of an inventory, weak but often unique |
| epic | `#e619fc` | 95 | 32.2% | a stronger effect, always in epic and spiked chests |
| legendary | `#d4b20d` | 66 | 22.4% | run-defining, only from legendary chests and totems |
| greed | `#ba2902` | 18 | 6.1% | a bargain with a real cost; perks only, never dropped |

Their own wiki is blunt that tier is not power: "The higher the rarity, the
better the item. While true for most cases, there are some notable exceptions
(like Sharp Shot, Coral Amulet and Ring Of Parrying)". Sharp Shot — flat damage,
their best rare weapon mod by their own tips — is *common*. So the tier is a
statement about **how the item arrives**, and only loosely about what it does.

### Five families

| Family | Rows | Common | Epic | Legendary | Greed | What it modifies |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Weapon Mods | 88 | 40 | 23 | 25 | 0 | the primary weapon's shots |
| Ability Mods (filed as "Grenade Mods") | 36 | 8 | 12 | 16 | 0 | the grenade ability |
| Melee Mods | 12 | 6 | 5 | 0 | 1 | the melee weapon |
| Perks | 113 | 51 | 32 | 15 | 15 | the body: health, speed, crit, economy |
| Relics | 46 | 11 | 23 | 10 | 2 | one unique rule each |

Two facts about that table drive the whole re-cut. **Grenade mods are their
"ability" family** — the wiki redirects `Grenade Mods` to `Ability Mods` — and
**relics are de-weighted**, at `0.2` spawn weight against the usual `1.0`, so a
relic is rare in the pool as well as in the chest.

### Where their loot comes from

| Surface | What it gives | Tier behaviour |
| --- | --- | --- |
| Damage / Health / Speed / Luck / Critical / Elemental / Economy chests | 3 choices, take 1 | the chest's own group; a small epic chance |
| Epic chest | 3 choices | epic or higher; perfect parkour, waves and elite islands |
| Legendary chest | 3 choices | legendary only; **boss islands only** |
| Greed chest | **1 option** | greed perks only; cannot be dropped once taken |
| Spiked chest | 3 choices | epic-tier, costs 33% max health to open |
| Upgrade chest | 2 choices | only what you already carry |
| Relic chest | 2 choices, one fewer than the rest | the relic family |
| Lesser / Random chests | 1 choice | anything but greed, hidden on the island |
| Totems | straight into the inventory | Gold gives a legendary for 66% of max health; Greed gives a greed perk |

The lesson for us is in the right column: **their rarity is a property of the
surface, not a probability on the row.** A common can drop from anything; a
legendary has no drop chance at all outside a legendary chest, a totem or the
shop. Their `Streamer Loot` perk is the single lever that moves a tier upward.

### How their stacks add

Every row is a *level* of itself: picking it twice makes it level 2, and the
wiki records the scaling per row.

- **linear**, 237 of 295 rows — "+4 damage with each mod level" (Sharp Shot).
- **hyperbolic**, 56 rows — anywhere stacking would delete the game: chance
  effects, cooldown reductions, spread. Diminishing from the first stack.
- 18 rows carry a linear *drawback* alongside a linear buff (High Caliber: +75%
  damage, -25% clip), 16 carry a hyperbolic drawback (Steady Shot, Heavy
  Hitter).

Greed is the exception that proves the rule: all 18 greed rows have a downside,
and none is hyperbolic where the downside is money or health.

## The crossing

### What maps to what

| Crab Champions | Blood Champions | Because |
| --- | --- | --- |
| Weapon Mods | **Shot** — the ranged hand | both hang off "the shot leaving the barrel"; ours is `ProcEngine.on_weapon_fire` |
| Ability Mods (grenades) | **Ability** — 41 live weapon-family upgrades + 19 pending verb upgrades for throw/guard/roll/parry | a grenade is a cooldown-limited second source of damage that is not the shot; our throw on `T` with its charge budget is the same verb, and guard/roll/parry are the ability buttons a run body actually gets. These are **run upgrades**, not active skills |
| Melee Mods | **Hand** — the melee hand | same verb: swings |
| Perks | **Perk** | body-wide passives, same layer |
| Relics | **Relic** | one unique rule, `max_stacks` 1-2, de-weighted in the pool |
| crystals | gold | one purse, `Warband.gold()`, spent in town and at the stall |
| keys | keys | unchanged: boss-only income, rack-only spend |
| elemental stacks (fire, ice, lightning, poison, arcane) | **marks** (burn, chill, storm, bleed, hex) | see below |

The `ability` family is not the active ability catalog. The **35 active skills**
(Barrage, Fireball, the shields, the wards, and eight free family starters) live
in `ability_rules.gd` and are unlocked and equipped at the rack; the ability rows
are run upgrades. `scripts/roguelite/ability_index.gd` joins the two catalogs -
35 active + 60 ability upgrades = 95 - so a lookup can say which kind an id is
instead of treating one as the other. The ability census is **63 common / 51
epic / 33 legendary / 14 greed**.

Our run body's whole verb set is bow draw, melee swing, block/parry, roll, step,
throw, fireball, bandage, potion, jump. A run body is dressed with a *starter
ability* (`run_director.gd:_dress_weapon` asks `PlayerState.build_loadout` for
one): the fireball, a **staff-family** skill priced at 40% of the staff's 50
base - **20 damage** - on a ten-second clock in `ability_rules.gd`, then scaled
by the rig's spell channel and by the pool's damage, crit and conditional rows
(`spell_plan` is the name of that channel). Only hands that fit the staff family
draw it; the bow and the blade do not. It is why the ability family exists beside it
- the throw, the guard, the roll and the parry are the rest of the buttons a
run body gets, and the verb rows upgrade those verbs. It is the player's key
rather than the warband's: the campaign dress gives it to the body a peer is
inside and to nobody else, because the AI already casts from its own kit and a
squadmate with a free three-metre blast changes fights nobody asked to change.

### Nine groups become nine groups

The source groups rows by effect under `== Damage ==`, `== Health ==` and so on.
The re-cut keeps the grouping because it is the field a player searches:

| Group | Source rows | Re-cut rows | Kept |
| --- | ---: | ---: | ---: |
| Damage | 95 | 34 | 36% |
| Skill | 39 | 15 | 38% |
| Health | 28 | 13 | 46% |
| Greed | 18 | 12 | 67% |
| Elemental | 50 | 11 | 22% |
| Speed | 19 | 10 | 53% |
| Luck | 23 | 9 | 39% |
| Critical | 11 | 6 | 55% |
| Economy | 12 | 5 | 42% |
| *(house rows)* | — | 5 | — |

Elemental keeps the smallest share of its group (22%) because five element
flavours of the same claw, shot, aura and explosion collapse to three claws and
five shots once the stack system becomes marks. Greed keeps the largest share
(67%) because our totem shows a single greed option on six levels in ten — a
bargain about once an island — where their greed lives behind a rarer chest.

The two groups that shrink without being dropped wholesale — Skill and Luck —
are the two our game has the least machinery for: no reload to interrupt, no
destructibles to break, no combo counter. Luck does not stay dead: it comes back
as the lever on the new rarity ladder.

### What is dropped, and why

| Dropped source mechanic | Rows | Why it cannot cross |
| --- | ---: | --- |
| Magazines, reloads, reload-triggered effects | 9 | a bow has no magazine; the draw cycle is the resource and it never reloads |
| Combo counter | 5 | no combo exists on our HUD or in `ProcEngine` |
| Turrets | 4 | no turret in the pool, the armory or the run |
| Armor plates | 8 | our armour is a five-slot percentage reduction (`armor_data.gd`), not plates — and **no mob has any damage reduction at all**, so "break enemy armour" has nothing to break |
| Aiming / hipfiring as distinct stances | 2 | our bow always draws; "aiming" is the only shot |
| Water, falling, low gravity | 4 | no water volumes, no fall damage, the roll is already the traversal verb |
| Crystal rocks, destructibles, charge zones | 6 | the island's cover does not break under fire |
| Portal choice, anvils, enhancement totems | 5 | our portal has one exit and one press |
| One-shot-elimination counters | 3 | no such counter, and measuring it would mean a new per-level tally |

**115 of the 295 source rows are mirrored, 46 are dropped for missing machinery,
and the remaining 134 are siblings of a row that did cross** — their fifth claw,
their fourth storm, their third crystal perk. 115 + 46 + 134 = 295, and the
120-row pool is those 115 plus 5 house rows.

### The mark system

Five elemental stacks do not cross as elements. Our damage has no spell schools,
and a Watcher's arrow is not lightning until somebody decides it is. They cross as
**marks** — the same machinery, a stack count on a body applied by a hit and
decaying, wearing the vocabulary the setting already uses: blood, ember, rime,
the Watchers' charge, and the demons' hex.

This is the one new subsystem in the document. It is one component, one ledger,
five kinds, and every mark row in the pool below writes to it.

| Mark | Mirrors | Applies | Effect per stack | Decay |
| --- | --- | --- | --- | --- |
| **Bleed** | arcane (their DoT) | any landed blow | 0.20 damage a second | 10% of stacks a second |
| **Burn** | fire | any landed blow | 0.35 damage a second | none: the whole stack dies after 4 s |
| **Chill** | ice | any landed blow | -0.4% move and attack rate, floored at -40% | 8% a second |
| **Storm** | lightning | any landed blow | at 25 stacks, arcs 8 damage a second to one other body within 6 m; at 60, two bodies for 12 | 12% a second |
| **Hex** | poison | any landed blow | +0.5% damage taken from every source | 6% a second |

Four rules make the web behave like theirs:

- **Cap 150 stacks** a mark, fixed. Their poison caps at 250 and their arcane is
  unbounded, but they scale on thousand-point health pools; 150 is the same
  pressure on our 100-point pool and 22-to-130-point bodies. Their `Toxic` raises
  the poison cap and is deliberately not taken: a cap that moves is a number the
  player has to read off the HUD, and marks are already the busiest read in the
  game.
- **Annihilation.** One stack of Burn eats one of Chill and the reverse, exactly
  as fire and ice cancel in their game. A burn-and-chill build is not a thing.
  That is the point.
- **Hex amplifies marks as well as blows**, so a hex build is a multiplier on
  anything else somebody built. Their poison does the same for their elements.
- **Ticked at 4 Hz, one ledger for the island.** `mob_health_bars.gd` draws every
  wounded body with one `Control` and one `_draw()`; the marks follow that
  precedent — one node on the director, keyed by body instance id, ticking four
  times a second. Twelve mobs with five marks each is sixty numbers, and sixty
  numbers is one loop, not sixty nodes.

Nothing applies marks for free. A body with no mark rows carries none, and the
only sources are the 5 mark shots, the 3 mark claws and one legendary perk
(`conducting_bodies`, which marks on death). The two mark modifiers —
`mark_expert`, which scales with how many kinds a body carries, and `fire_ring`,
which trades one kind away — change what a mark does, never whether one exists.
That keeps a fresh level the same fight it is today.

## Rarity, and what it now buys

Today rarity is a colour and a line item: `draft()` weights by a flat per-row
`weight` and ignores the tier entirely, the shop adds 18 gold to anything not
common, and greed is the only tier that gates anything. That is the one part of
the source system worth importing wholesale, because their tier *is* their
acquisition model and ours is currently nothing.

### The ladder

| Surface | Offers | common | epic | legendary | greed |
| --- | ---: | --- | --- | --- | --- |
| Upgrade pedestal (every clear) | 3 | always | island 2+ | **never** | never |
| Pedestal at the shop level | 1 | always | always | never | never |
| Reward chest | 1 mod | always | always | island 4+, 4% | island 2+ |
| Warden's Hoard (boss level) | 2 mods | — | always | **1 guaranteed** | island 2+ |
| Shop stall | 3 | always | always | island 3+ | island 2+ |
| Greed Totem | 1 | — | — | — | always |

Three sentences cover it. **A pedestal is a common chest** — it is where commons
come from, and it never carries a legendary. **A legendary is a boss's, or the
stall's.** **Greed is never a choice you walk past**: it is the totem's one
offer, exactly as their greed chest shows a single option.

### The roll

Where a surface allows more than one tier, one roll picks the tier and a second
picks the row inside it:

| Island | common | epic | legendary |
| --- | ---: | ---: | ---: |
| 1 | 78 | 22 | 0 |
| 2 | 62 | 34 | 4 |
| 3 | 52 | 38 | 10 |
| 4 | 44 | 40 | 16 |
| 5+ | 38 | 40 | 22 |

`luck` shifts the roll, and nothing else does. One stack moves six points from
common into epic and four from epic into legendary; legendary is floored at 0 and
capped at 35 **after the row is normalised to a hundred**, because the cap is a
share of the finished roll and not of an intermediate pool. **Luck cannot open a
tier the surface does not sell** — a pedestal on island 9 with six stacks of
Streamer Loot still offers no legendary, because the pedestal never carries one.
That is the same rule as theirs: `Streamer Loot` improves the loot in a chest, it
does not turn a common chest into a legendary one.

The reward chest rolls the same table at a quarter of its legendary weight,
because it is one mod with no choice: 4% at island 4 and 5.5% on island 5+. A
surface that sells greed carves a **six-point greed share out of the commons and
epics in proportion**, never out of the legendary, so the chest's 4% survives the
carve. Six rules, one helper (`Mods.tier_weights`), and the regression asserts
each of them:

| Rule | Asserted by |
| --- | --- |
| the three ladder tiers sum to a hundred | `_check_ladder` |
| six luck leans the roll away from common | `_check_ladder` |
| the legendary share never passes 35 | `_check_ladder` |
| a chest's legendary is 4% on island 4, 5.5% on 5+ | `_check_ladder` |
| a pedestal never carries a legendary or greed, at any luck | `_check_ladder` |
| a boss's hoard always contains one legendary | `_check_ladder` |

Two rows move the offer count instead, which is what their `Big Chests` and
`Coral Amulet` do: `big_chests` adds a pedestal card, `coral_amulet` adds a mod
to the chest's payout, `special_delivery` adds a stall ware and `hoarder` takes a
pedestal card away.

### What a tier costs

| Tier | Shop price at level 9 | Note |
| --- | ---: | --- |
| common | 67 gold | `22 + 5 x level` |
| epic | 102 gold | +35 |
| legendary | 137 gold | +70 |
| greed | 112 gold | +45 |

This is live: `Mods.stall_price` is `22 + 5 x level` plus the tier's surcharge,
and the regression pins the common and the legendary at level 9. The stall used
to ask 82 for a common and 100 for anything else. Commons get cheaper, so a body
can actually afford two; legendary stays a decision. `ring_of_value` halves the
first ware on the shelf, which is where a player will look for it.

A level's gold is the clear award (`12 + 6 x island + 2 x wave`), the kills, and
the chest's own `38 + 10 x island` - the 14 in an earlier draft of this document
was the first level's clear alone.

### Why the tiers still do not mean "power"

The source's own wiki warns against reading tier as strength, and the re-cut
keeps that. `broadhead` is common and is the best damage-per-pick in the shot
family at the starter bow's 10 damage. `split_shot` is legendary because
Firepower is. The tier says where it lives.

## The pool

The original re-cut was 120 rows: 47 common, 36 epic, 23 legendary, 14 greed. The current pool adds 41 ability rows for 63/51/33/14. Every row names the source
row it mirrors and that row's tier; `— (house)` marks a row with no source, and
there are five of those: our crescent, our parry, our dodge and the two bargain
rows the old pool already shipped (`bloodthirst`, `cursed_arsenal`). The other
twenty-two rows of the old pool are in the tables with a source row, because the
migration moved them to the tier their source carries.

The catalog carries ids, tiers, caps, stats and flags. The `Mirrors` column lives
here, in the design record, so the code has one fewer field to drift.

Share, against the source:

| Tier | Source | Re-cut | Delta |
| --- | ---: | ---: | --- |
| common | 39.3% | 39.2% | -0.1 |
| epic | 32.2% | 30.0% | -2.2 |
| legendary | 22.4% | 19.2% | -3.2 |
| greed | 6.1% | 11.7% | +5.6 |

Greed is deliberately over-weight, and it is the only tier that is. Their greed
lives behind a chest that shows a single option; our Greed Totem shows a single
option on six levels in ten — 1, 2, 4, 5, 7 and 8 — so a body is offered a
bargain about once an island however the chests fall. Fourteen rows is the
smallest pool that keeps two visits from repeating.

Groups in family order, tiers in rarity order. `Writes` is the engine key the
row touches, with the curve where the curve is the design; `Mirrors` is the
source row and the tier the row inherits.

A row crosses a family boundary where the verb does. Their spinning-blade and
homing-blade rounds are weapon mods that fire blades; ours are thrown pieces, so
they sit in Ability.

### Shot · common (15)

| Upgrade | `id` | Max | Per stack | Writes | Mirrors |
| --- | --- | ---: | --- | --- | --- |
| **Broadhead** | `broadhead` | 6 | Each shaft carries a heavier point: +1 flat damage. Flat damage is what a light bow lacks most. | `flat_damage +1` | Sharp Shot (C) |
| **Steady Draw** | `steady_draw` | 5 | A planted shot lands true: +12% shot damage while both feet are still. | `damage_planted_mult +0.12` | Steady Shot (C) |
| **Big Shot** | `big_shot` | 4 | A fatter arrow: +40% size, +15% damage, and it flies 25% slower. | `shot_size +0.40, damage_mult +0.15, projectile_speed_mult -0.25` | Big Shot (C) |
| **Blind Fire** | `blind_fire` | 4 | Loosed without a sightline: +20% shot damage, but the fan opens by 9 degrees. | `damage_mult +0.20, spread_add +9` | Blind Fire (C) |
| **Wind Up** | `wind_up` | 3 | A hand that keeps working: +3% damage per shaft loosed in the last two seconds, up to fifteen. | `windup_per_shot +0.03, windup_cap 15` | Wind Up (C) |
| **Hot Streak** | `streak` | 3 | Hit after hit: +4% damage per body struck in a row, up to twelve, and a miss wipes it. | `streak_per_hit +0.04, streak_cap 12` | Streak Shot (C) |
| **Ricochet** | `ricochet` | 5 | A shaft that lands begins again: it hops to one more body within 12 m at 70% damage, plus one hop a stack. | `ricochet +1, hop_scale 0.70` | Bouncing Shot (C) |
| **Fast Shot** | `fast_shot` | 4 | A flat trajectory: +25% arrow speed and a quarter less drop over distance. | `projectile_speed_mult +0.25, drop_mult -0.25` | Fast Shot (C) |
| **Berserk Rate** | `rapid_fire` | 10 | PINNED ROW. +18% ranged fire rate and melee attack speed per stack. | `attack_mult +0.18` | Rapid Fire (C) |
| **Heavy Caliber** | `heavy_caliber` | 6 | PINNED ROW. +35% weapon damage and +40% knockback, but -10% fire rate. | `damage_mult +0.35, knockback_mult +0.40, attack_mult -0.10` | High Caliber (C) |
| **Sanguine Shot** | `bleed_shot` | 5 | The point opens a vein: hits apply 10 Bleed. | `mark_stacks.bleed 10` | Poison Shot (C) |
| **Cinder Shot** | `burn_shot` | 5 | The point carries an ember: hits apply 10 Burn. | `mark_stacks.burn 10` | Fire Shot (C) |
| **Rime Shot** | `chill_shot` | 5 | The point is cold enough to hurt: hits apply 10 Chill. | `mark_stacks.chill 10` | Ice Shot (C) |
| **Wardens' Shot** | `storm_shot` | 5 | The shaft carries the Watchers' charge: hits apply 10 Storm. | `mark_stacks.storm 10` | Lightning Shot (C) |
| **Hexed Shot** | `hex_shot` | 5 | The shaft is cut with a curse: hits apply 10 Hex. | `mark_stacks.hex 10` | Arcane Shot (C) |

### Shot · epic (9)

| Upgrade | `id` | Max | Per stack | Writes | Mirrors |
| --- | --- | ---: | --- | --- | --- |
| **Hatchet Arc** | `dagger_arc` | 6 | Chance on any landed blow to spin a throwing blade at a nearby body for 140% weapon damage. | `arc_chance cap .55 half 3` | Dagger Arc (E) |
| **Thorn Nova** | `arrow_nova` | 5 | A landed shaft bursts a ring of eight splinters, and a kill does it outright, at 55% weapon damage. | `nova_chance cap .55 half 3` | Spark Shot (E) |
| **Aura Shot** | `aura_shot` | 4 | The shaft drags a field of thorns: any body it passes takes 45% weapon damage a second for 3 s. | `shot_aura_damage 0.45, shot_aura_duration 3.0` | Aura Shot (E) |
| **Blood Arc** | `chain_lightning` | 6 | PINNED ROW. Chance on hit to arc to three bodies for 40% weapon damage each; a stack adds a body. | `chain_chance cap .70 half 3` (targets read `stacks_of`) | Link Shot (E) |
| **Scatter Burst** | `scatter_shot` | 5 | On impact the shaft splits into three smaller ones behind the body, each at 60% damage. | `scatter_chance cap .60 half 2.5` | Scatter Shot (E) |
| **Piercing Wave** | `piercing_wave` | 5 | A slow crescent of wind follows the shot's line: the shaft passes through one more body a stack, and every body behind the first takes 15% more. | `pierce +1, pierce_growth 0.15` | Piercing Wave (E) |
| **Mace Shot** | `mace_shot` | 4 | Chance to loose a hafted head instead: 120% damage in a 1.8 m burst and a committed stagger. | `mace_chance cap .55 half 3` | Mace Shot (E) |
| **Coin Shot** | `money_shot` | 5 | Every landed blow pays: +1 gold, flat, whatever the body was worth. | `gold_on_hit +1` | Money Shot (E) |
| **Leech Shot** | `health_shot` | 4 | A wound for a wound: the first landed blow each second restores 2 HP. | `heal_on_hit +2 (1 s gate)` | Health Shot (E) |

### Shot · legendary (6)

| Upgrade | `id` | Max | Per stack | Writes | Mirrors |
| --- | --- | ---: | --- | --- | --- |
| **Homing Bolts** | `homing_bolts` | 2 | The shaft turns in the air toward the nearest body inside the aim cone; each stack turns harder. | `homing +1 (18 units a stack)` | Homing Shot (L) |
| **Blood Charge** | `sticky_charge` | 3 | A landed shaft plants a charge that detonates after 1.2 s for 120% weapon damage in a 3 m gore burst. | `bomb_chance cap .60 half 3` | Bomb Shot (L) |
| **Arc Split** | `split_shot` | 6 | PINNED ROW. Every shot looses +1 shaft in a tight fan; the first is whole, each extra pays 85%. | `split_shots +1` | Firepower (L) |
| **Splash Damage** | `splash_shot` | 3 | What the point does not open, the pressure does: +40% of the blow in a 2.5 m spill. | `splash_frac +0.40, splash_radius 2.5` | Splash Damage (L) |
| **Spike Strike** | `spike_strike` | 3 | The ground answers the arrow: thorns erupt under the body for 70% weapon damage in 3 m. | `spike_chance cap .70 half 4` | Spike Strike (L) |
| **Double Tap** | `double_tap` | 3 | Chance a landed blow is booked twice: the whole hit again, procs and all. | `double_chance cap .70 half 4` | Double Tap (L) |

### Hand · common (6)

| Upgrade | `id` | Max | Per stack | Writes | Mirrors |
| --- | --- | ---: | --- | --- | --- |
| **Grim Harvest** | `grim_harvest` | 8 | EXISTING ROW. Killing or gibbing a body restores 1 + stack HP. | `heal_on_kill +1` | Vampire (C) |
| **Blender** | `blender` | 6 | The arm keeps turning: +15% melee attack speed only, the bow is untouched. | `melee_attack_mult +0.15` | Blender (C) |
| **Sharp Claws** | `sharp_claws` | 6 | +15% melee damage. The hatchet's answer to a warden's reach. | `melee_damage_mult +0.15` | Sharp Claws (C) |
| **Iron Claws** | `iron_claws` | 4 | +30% melee damage, but every swing takes 20% longer to come back around. | `melee_damage_mult +0.30, melee_attack_mult -0.20` | Iron Claws (C) |
| **Big Claws** | `big_claws` | 3 | The cut reaches further: +0.35 m of melee reach, so a roll-back can still be answered. | `melee_reach +0.35` | Big Claws (C) |
| **Slow Cut** | `time_claws` | 3 | +45% melee damage, but the wound pays out over 1.2 s instead of on contact. | `melee_damage_mult +0.45, melee_delay 1.2` | Time Claws (C) |

### Hand · epic (3)

| Upgrade | `id` | Max | Per stack | Writes | Mirrors |
| --- | --- | ---: | --- | --- | --- |
| **Flaying Edge** | `bleed_claws` | 5 | The blade is meant to open, not to close: melee hits apply 18 Bleed. | `mark_stacks.bleed 18 (melee)` | Poison Claws (E) |
| **Ember Edge** | `burn_claws` | 5 | A blade kept in the brazier: melee hits apply 18 Burn. | `mark_stacks.burn 18 (melee)` | Fire Claws (E) |
| **Storm Edge** | `storm_claws` | 5 | A blade that carries the wardens' charge: melee hits apply 18 Storm. | `mark_stacks.storm 18 (melee)` | Lightning Claws (E) |

### Hand · legendary (1)

| Upgrade | `id` | Max | Per stack | Writes | Mirrors |
| --- | --- | ---: | --- | --- | --- |
| **Crescent Wave** | `melee_shockwave` | 4 | PINNED ROW. HOUSE ROW. Every swing throws a short piercing crescent of wind and blood: 45% weapon damage, +15 points a stack. | `wave_damage 0.45 + 0.15/stack` | — (house) |

### Hand · greed (1)

| Upgrade | `id` | Max | Per stack | Writes | Mirrors |
| --- | --- | ---: | --- | --- | --- |
| **Brawler** | `brawler` | 3 | Both hands on the haft: +60% melee damage, -35% shot damage. | `melee_damage_mult +0.60, damage_mult -0.35` | Brawler (G) |

### Ability verb · common (6)

| Upgrade | `id` | Max | Per stack | Writes | Mirrors |
| --- | --- | ---: | --- | --- | --- |
| **Fleet Roll** | `fleet_roll` | 3 | One more roll before the ground claims you: +1 roll charge on a 1.6 s regen. | `roll_charges +1, roll_regen 1.6` | Stamina (C) |
| **Heavy Throw** | `heavy_throw` | 4 | +25% thrown damage, but the piece travels 20% slower and drops harder. | `throw_damage_mult +0.25, throw_speed_mult -0.20` | Heavy Grenade (C) |
| **Sticky Throw** | `sticky_throw` | 4 | The piece bites and waits: +45% throw damage, paid 0.6 s after it lands. | `throw_damage_mult +0.45, throw_delay 0.6` | Glue Grenade (C) |
| **Wide Burst** | `wide_burst` | 4 | +0.7 m of blast radius on every thrown piece and every burst it leaves. | `blast_radius +0.7` | Bigger Boom (C) |
| **Braced Guard** | `braced_guard` | 4 | The arm is set before the blow: guard costs 25% less stamina a second. | `guard_cost_mult -0.25` | Bulletproof (C) |
| **Throw Shove** | `throw_shove` | 4 | A thrown piece parts the crowd: +40% knockback and a 0.25 s stagger on every body it hits. | `knockback_mult +0.40, throw_stagger 0.25` | Knockback Shot (C) |

### Ability verb · epic (6)

| Upgrade | `id` | Max | Per stack | Writes | Mirrors |
| --- | --- | ---: | --- | --- | --- |
| **Burst Throw** | `throw_burst` | 4 | The landing throws sparks: an eight-splinter ring at 55% weapon damage. | `throw_burst_chance cap .55 half 3` | Spark Explosion (E) |
| **Ring of Daggers** | `throw_ring` | 3 | The piece comes apart into six blades fanned forward, 70% weapon damage each. | `throw_fan 6, throw_fan_scale 0.70` | Dagger Blast (E) |
| **Grenadier** | `grenadier` | 4 | A deeper belt: +2 throw charges. | `throw_charges_flat +2` | Grenadier (E) |
| **Triple Throw** | `triple_throw` | 3 | Chance to loose three pieces in one motion, the extras paying 70%. | `triple_throw_chance cap .55 half 3` | Triple Grenade (E) |
| **Layered Throw** | `layered_throw` | 3 | Chance the landing bursts a second time for half the first. | `double_burst_chance cap .55 half 3` | Layered Grenade (E) |
| **Repulsion** | `repulsion` | 3 | The roll turns arrows aside: enemy shafts inside 3 m are knocked off their line. | `roll_repel 3.0` | Ring Of Repulsion (E) |

### Ability verb · legendary (7)

| Upgrade | `id` | Max | Per stack | Writes | Mirrors |
| --- | --- | ---: | --- | --- | --- |
| **Black Hole** | `black_hole` | 2 | The piece opens a 2.5 m void for 1.2 s that drags bodies in and deals 30% weapon damage every 0.25 s. | `throw_void 0.30, throw_void_radius 2.5` | Black Hole (L) |
| **Ability Ring** | `ability_ring` | 2 | The belt refills itself: throw regen 40% faster. | `throw_regen_mult +0.40` | Ability Ring (L) |
| **Ammo Ring** | `ammo_ring` | 2 | A roll returns a piece to the hand: every roll restores one throw charge. | `roll_refund_throw 1` | Ammo Ring (L) |
| **Dagger Dash** | `dagger_dash` | 2 | The roll throws a fan of five blades in the look direction, 60% weapon damage each. | `roll_blades 5, roll_blade_scale 0.60` | Dagger Dash (L) |
| **Parry Master** | `parry_master` | 2 | HOUSE ROW. The parry window widens by 0.06 s, and a parry returns a throw charge and 15 stamina. | `parry_window_add +0.06, parry_refund 1` | — (house) |
| **Spinning Blade** | `spinning_blade` | 2 | A thrown piece that does not come down: it spins in place for 3 s, cutting 45% weapon damage a second in 2 m. | `throw_spin 0.45, throw_spin_radius 2.0` | Spinning Blade (L) |
| **Homing Blades** | `homing_blades` | 2 | The thrown piece decides for itself: it curves to the nearest body and strikes for 130%. | `throw_homing +1, throw_damage_mult +0.30` | Homing Blades (L) |

### Perk · common (18)

| Upgrade | `id` | Max | Per stack | Writes | Mirrors |
| --- | --- | ---: | --- | --- | --- |
| **Vitality** | `vitality` | 8 | +10 max HP. A quarter of the pool of a body that has taken four. | `max_hp_flat +10` | Mango (C) |
| **Thick Blood** | `thick_blood` | 8 | +8% max HP multiplier, which also scales the flat HP a plate gave you. | `max_hp_mult +0.08` | Banana (C) |
| **Fortified Plate** | `fortified_plate` | 8 | EXISTING ROW. +25 max HP, and 10% of the pool comes back when the island is cleared. | `max_hp_flat +25, heal_on_clear 0.10` | Fortitude (C) |
| **Field Dressing** | `field_dressing` | 5 | A bandage between islands instead of a prayer: heal 6% of the pool on every clear. | `heal_on_clear +0.06` | Endurance (C) |
| **Blood High** | `blood_high` | 5 | +20% damage while above 75% health. Reward for a body that is not being hit. | `damage_high_hp_mult +0.20` | Vitality (C) |
| **Regenerator** | `regenerator` | 5 | 0.4 HP a second while a wave is live, for the first 60 s of it. | `regen_hp_per_s +0.4, regen_window 60` | Regenerator (C) |
| **Hard Target** | `hard_target` | 5 | Incoming damage -5% a stack, toward a floor of a quarter of the blow. | `damage_taken_mult -0.05` | Hard Target (C) |
| **Speed Demon** | `speed_demon` | 5 | +5% movement speed. | `move_mult +0.05` | Speed Demon (C) |
| **Critical Sharpshooter** | `crit_sharpshooter` | 6 | PINNED ROW. +12% crit chance; a crit deals 2.0x and rolls its procs twice. | `crit_chance +0.12` | Sharpshooter (C) |
| **Anti Crit** | `anti_crit` | 4 | +18% damage and -10% crit chance: the trade for a body that never liked dice. | `damage_mult +0.18, crit_chance -0.10` | Anti Crit (C) |
| **Power Punch** | `power_punch` | 6 | +0.20 to the crit multiplier, so a crit pays 2.2x and then 2.4x. | `crit_mult_flat +0.20` | Power Punch (C) |
| **Collector's Bounty** | `collectors_bounty` | 8 | EXISTING ROW. +25% gold from every kill, chest and totem. | `currency_mult +0.25` | Paycheck (C) |
| **Special Delivery** | `special_delivery` | 2 | The stall lays out one more ware. | `shop_offers +1` | Special Delivery (C) |
| **Streamer Loot** | `streamer_loot` | 4 | +1 luck: the tier roll leans away from common and toward epic, and epic toward legendary. | `luck +1` | Streamer Loot (C) |
| **Danger Close** | `danger_close` | 5 | +15% damage to bodies inside 6 m. The hatchet's whole world. | `damage_close_mult +0.15, close_range 6` | Danger Close (C) |
| **Eagle Eye** | `eagle_eye` | 5 | +12% damage to bodies beyond 12 m. The bow's whole world. | `damage_far_mult +0.12, far_range 12` | Eagle Eye (C) |
| **Elemental Expert** | `mark_expert` | 4 | +8% damage per different mark on the body, up to four. | `damage_per_mark +0.08` | Elemental Expert (C) |
| **Featherstep** | `featherstep` | 8 | HOUSE ROW. A step that is never quite where the blow lands: +10% dodge, hyperbolic toward 60%. | `dodge_chance cap .60 half 4` | — (house) |

### Perk · epic (12)

| Upgrade | `id` | Max | Per stack | Writes | Mirrors |
| --- | --- | ---: | --- | --- | --- |
| **Health Is Power** | `health_is_power` | 4 | +1% damage per 10 HP you are carrying. | `damage_per_hp +0.01/10` | Health Is Power (E) |
| **Money Is Power** | `money_is_power` | 4 | +1% damage per 100 gold in the purse. | `damage_per_gold +0.01/100` | Money Is Power (E) |
| **Checklist** | `checklist` | 5 | +1% damage per 20 bodies put down this run. | `damage_per_kill +0.01/20` | Checklist (E) |
| **Gemstone** | `gemstone` | 5 | +10% damage for each island already cleared. A run's own momentum. | `damage_per_island +0.10` | Gemstone (E) |
| **Collector** | `collector` | 3 | +2% damage per upgrade stack you carry, whatever its family. | `damage_per_stack +0.02` | Collector (E) |
| **Damage Aura** | `damage_aura` | 5 | A standing field of blood: 6 damage a second to everything inside 3.5 m. | `aura_damage +6, aura_radius 3.5` | Damage Aura (E) |
| **Shockwave** | `shockwave` | 3 | A blow landed on you answers with a ring: 80% weapon damage in 4 m, through cover. | `shock_on_hurt 0.80, shock_radius 4` | Shockwave (E) |
| **Exploding Enemies** | `exploding_enemies` | 3 | A dying body bursts for 25% of its own max HP in a 3 m circle. | `explode_on_kill 0.25, explode_radius 3` | Exploding Enemies (E) |
| **Big Chests** | `big_chests` | 2 | The pedestal lays out one more card. | `pedestal_offers +1` | Big Chests (E) |
| **Critical Blast** | `crit_blast` | 3 | A crit bursts for 60% of the blow in 2.5 m. | `crit_burst 0.60, crit_burst_radius 2.5` | Critical Blast (E) |
| **Mega Crit** | `mega_crit` | 3 | 12% chance a crit becomes a mega crit at 3.0x instead of 2.0x. | `mega_crit_chance cap .55 half 3, mega_crit_mult 3.0` | Mega Crit (E) |
| **Buried Cache** | `bonus_chest` | 6 | EXISTING ROW. 15% chance per stack that clearing a level buries a mini-chest beside the reward. | `chest_chance cap .75 half 3` | Performance Bonus (E) |

### Perk · legendary (6)

| Upgrade | `id` | Max | Per stack | Writes | Mirrors |
| --- | --- | ---: | --- | --- | --- |
| **Rare Treasure** | `rare_treasure` | 3 | A body has a 3% chance a stack to leave an upgrade card on the ground, for whoever reaches it. | `drop_chance cap .70 half 4` | Rare Treasure (L) |
| **Level Up** | `level_up` | 2 | After every island, two carried upgrades gain a stack. The cheapest power in the pool. | `levelup_per_island +2` | Level Up (L) |
| **Bonus Chests** | `bonus_chests` | 2 | A reward chest every 25 kills, on top of the level's own. | `extra_chest_kills 25` | Bonus Chests (L) |
| **Care Package** | `care_package` | 1 | An extra chest after every third island. | `extra_chest_islands 3` | Care Package (L) |
| **Faulty Chests** | `faulty_chests` | 2 | A pedestal card you did not take stays on the ground as a pickup, once a card a stack. | `keep_offer +1` | Faulty Chests (L) |
| **Conducting Bodies** | `conducting_bodies` | 3 | A body put down discharges 25 Storm into everything within 5 m. | `death_marks.storm 25, death_mark_radius 5` | Electric Enemies (L) |

### Perk · greed (12)

| Upgrade | `id` | Max | Per stack | Writes | Mirrors |
| --- | --- | ---: | --- | --- | --- |
| **Glass Cannon** | `glass_cannon` | 5 | PINNED ROW. Deal +100% all damage and lose 40% of your max HP. | `damage_mult +1.00, max_hp_mult -0.40` | Glass Cannon (G) |
| **Rising Star** | `rising_star` | 3 | +75% gold, and a fifth again as many bodies on every level. | `currency_mult +0.75, enemy_count_mult +0.20` | Rising Star (G) |
| **Juggernaut** | `juggernaut` | 3 | +35% max HP, and the wave comes heavier: +25% bodies. | `max_hp_mult +0.35, enemy_count_mult +0.25` | Juggernaut (G) |
| **Up The Ante** | `up_the_ante` | 3 | +45% damage, +30% bodies, and the wave moves 15% faster. Brutal Pact's slot, one bargain. | `damage_mult +0.45, enemy_count_mult +0.30, enemy_speed_mult +0.15` | Up The Ante (G) |
| **Double Trouble** | `double_trouble` | 3 | +40% max HP, and every body arrives with +30% HP of its own. | `max_hp_mult +0.40, enemy_health_mult +0.30` | Double Trouble (G) |
| **Bribe** | `bribe` | 3 | +50% max HP, but a landed blow costs you 8 gold. | `max_hp_mult +0.50, gold_on_hit_taken 8` | Bribe (G) |
| **Damage Seeker** | `damage_seeker` | 3 | +60% damage, but a landed blow costs you 3 max HP for the rest of the run. | `damage_mult +0.60, max_hp_flat_on_hit -3` | Damage Seeker (G) |
| **Brute Force** | `brute_force` | 3 | +50% damage out and +30% damage in. The pool and the purse both run hotter. | `damage_mult +0.50, damage_taken_mult +0.30` | Brute Force (G) |
| **Slippery Slope** | `slippery_slope` | 3 | Mechanism live, not pinned. +100% gold, but you bleed 2% of your max HP a second while standing still in a live wave. | `currency_mult +1.00, standing_drain +0.02` | Slippery Slope (G) |
| **Hoarder** | `hoarder` | 2 | An extra chest every island, but the pedestal only lays out two cards from now on. | `extra_chest_islands 1, pedestal_offers -1` | Hoarder (G) |
| **Bloodthirst** | `bloodthirst` | 2 | HOUSE ROW. No more breathing between islands: passive heals stop and +300% melee lifesteal replaces them. | `melee_lifesteal +3.00, blocks_passive_healing` | — (house) |
| **Cursed Arsenal** | `cursed_arsenal` | 2 | HOUSE ROW. The hands lock for the run: +150% weapon damage and +50% proc coefficient on what you hold. | `damage_mult +1.50, proc_coeff_mult +0.50, hands_locked` | — (house) |

### Relic · common (2)

| Upgrade | `id` | Max | Per stack | Writes | Mirrors |
| --- | --- | ---: | --- | --- | --- |
| **Coral Amulet** | `coral_amulet` | 2 | The reward chest gives one more upgrade card, not one more choice. | `chest_mods +1` | Coral Amulet (C) |
| **Adrenaline Amulet** | `adrenaline_amulet` | 3 | +25% attack rate for 4 s after every kill. | `attack_on_kill +0.25/4s` | Adrenaline Amulet (C) |

### Relic · epic (6)

| Upgrade | `id` | Max | Per stack | Writes | Mirrors |
| --- | --- | ---: | --- | --- | --- |
| **Ring Of Defense** | `ring_of_defense` | 2 | Incoming damage -18%, stacking to a floor of a quarter of the blow. | `damage_taken_mult -0.18` | Ring Of Defense (E) |
| **Turbo Ring** | `turbo_ring` | 3 | +3% attack rate for every island cleared, kept for the run. | `attack_per_island +0.03` | Turbo Ring (E) |
| **Ring Of Fury** | `ring_of_fury` | 2 | +40% weapon damage for 4 s after every kill. | `damage_on_kill +0.40/4s` | Ring Of Fury (E) |
| **Ring Of Precision** | `ring_of_precision` | 2 | +0.75 crit multiplier. | `crit_mult_flat +0.75` | Ring Of Precision (E) |
| **Fire Ring** | `fire_ring` | 1 | Burn is 150% stronger, and Chill no longer applies to anything you touch. | `mark_potency.burn +1.50, mark_lockout.chill` | Fire Ring (E) |
| **Ring Of Value** | `ring_of_value` | 1 | The shop always keeps one ware at half price. | `shop_discount 0.50` | Ring Of Value (E) |

### Relic · legendary (3)

| Upgrade | `id` | Max | Per stack | Writes | Mirrors |
| --- | --- | ---: | --- | --- | --- |
| **Ring Of Protection** | `ring_of_protection` | 1 | Damage from marks lands on you at a quarter of its value. | `mark_damage_taken_mult -0.75` | Ring Of Protection (L) |
| **Ring Of Swiftness** | `ring_of_swiftness` | 1 | +35% movement speed, and the roll covers 2 m further. | `move_mult +0.35, roll_distance +2` | Ring Of Swiftness (L) |
| **Ring Of Luck** | `ring_of_luck` | 1 | +2 luck, and every chance in the pool rolls 20% kinder. | `luck +2, proc_coeff_mult +0.20` | Ring Of Luck (L) |

### Relic · greed (1)

| Upgrade | `id` | Max | Per stack | Writes | Mirrors |
| --- | --- | ---: | --- | --- | --- |
| **Ring Of Tankiness** | `ring_of_tankiness` | 1 | +120% max HP and -35% movement speed. A door, not a body. | `max_hp_mult +1.20, move_mult -0.35` | Ring of Tankiness (G) |

## Migration — the twenty-three rows that already ship

`mod_catalog.gd` held 23 rows. Twenty-two survive; one is absorbed. The only
tier movement is downward or upward **to match the source row**, which is the
whole point of the exercise: `ricochet` and `heavy_caliber` are commons because
Bouncing Shot and High Caliber are, and `split_shot`, `homing_bolts` and
`sticky_charge` are legendaries because Firepower, Homing Shot and Bomb Shot are.
Two of the 23 rows were **not** where this table first said they were:
`split_shot` shipped common (not epic) and `dagger_arc` shipped common (not
epic), so those two are the only rows that move two tiers or up a tier. Both are
corrected below, against the code that actually shipped.

| `id` | Ships as | Becomes | Mirrors | Pinned by the regression |
| --- | --- | --- | --- | --- |
| `split_shot` | common, 6 | legendary, 6 | Firepower (L) | yes — 2 stacks means 2 shafts |
| `homing_bolts` | epic, 4 | legendary, 2 | Homing Shot (L) | — |
| `sticky_charge` | epic, 5 | legendary, 3 | Bomb Shot (L) | — |
| `ricochet` | epic, 5 | common, 5 | Bouncing Shot (C) | — |
| `heavy_caliber` | epic, 6 | common, 6 | High Caliber (C) | yes — 1 stack is ×1.35, −0.10 rate |
| `scatter_shot` | epic | epic, 5 | Scatter Shot (E) | — |
| `piercing_wave` | epic | epic, 5 | Piercing Wave (E) | — |
| `dagger_arc` | common, 6 | epic, 6 | Dagger Arc (E) | — |
| `arrow_nova` | epic | epic, 5 | Spark Shot (E) | — |
| `chain_lightning` | epic | epic, 6 | Link Shot (E) | yes — 100 stacks stays at the .70 cap |
| `rapid_fire` | common | common, 10 | Rapid Fire (C) | yes — +0.18 a stack |
| `crit_sharpshooter` | common | common, 6 | Sharpshooter (C) | yes — 6 stacks is 0.72 |
| `grim_harvest` | common | common, 8 | Vampire (C) | — |
| `collectors_bounty` | common | common, 8 | Paycheck (C) | — |
| `fortified_plate` | common | common, 8 | Fortitude (C) | — |
| `featherstep` | common | common, 8 | — house | — |
| `bonus_chest` | epic | epic, 6 | Performance Bonus (E) | — |
| `melee_shockwave` | legendary | legendary, 4 | — house | yes — the id, and the crescent |
| `glass_cannon` | greed | greed, 5 | Glass Cannon (G) | yes — 5 stacks is ×6.0 damage |
| `slippery_slope` | greed | greed, 3 | Slippery Slope (G) | — |
| `cursed_arsenal` | greed | greed, 2 | — house | — |
| `bloodthirst` | greed | greed, 2 | — house | — |
| `brutal_pact` | greed | **retired** | absorbed by Up The Ante (G) | — |

Two scope changes follow from the crossing and break nothing:

- `grim_harvest` widens from "a melee kill heals" to *any* kill, which is what
  Vampire's source text actually says once the claws are our hand family.
- `slippery_slope` keeps our mechanism — bleed while standing in a live wave —
  and takes the source's bargain, gold for health. Their version charges at the
  start of an island; ours charges while you stand still. Same trade, one that
  reads on our plate, and it is already wired to `standing_drain`.

`brutal_pact` goes because Up The Ante does the same job one tier down with a
cleaner cost: Brutal Pact's `enemy_speed_mult` and `enemy_damage_mult` land in
Up The Ante and Brute Force instead of stacking three enemy penalties on one row.

## Curves, caps, and the ceilings

Every row writes to a key, and every key has one curve. The two rules that were in
`proc_engine.gd` are kept exactly as they were, and one was added, because a pool
this size is a pile of multipliers unless something says which keys may be summed:

- **linear** — damage, rate, crit, health, gold, lifesteal. A number a player can
  read and a designer can price.
- **hyperbolic** — every chance: `cap * n / (n + half)`, never reaching the cap.
  A row cannot author "20% a stack" for a chance key; the engine reads only the
  stack count and the curve's `cap` and `half`. The pool's tables therefore give
  chance rows as `cap … half …` and nothing else.
- **`MAX_KEYS`** — caps, ranges, radii and durations. A second copy of Splash
  Damage widens the spill's share, not its radius, so those keys aggregate by
  maximum. Summing them is the single easiest way to turn a tidy row into a broken
  one, which is why the list is a named constant and not a convention.

If every row in the pool were at its ceiling at once, these are the numbers. The
column is a sanity check, not a target — a run grants about twenty stacks by the
end of its first island (one pedestal pick and one chest mod a level), against a
ceiling that needs some five hundred.

| Key | Ceiling | Rows | Why that is the shape |
| --- | ---: | ---: | --- |
| `damage_mult` | +16.42 | 11 | ×17.4 if every damage row maxed; unreachable, and each row is a pick not spent on health |
| `max_hp_flat` | +280 | 2 | 380 HP on a 100 pool: the plate family is the game's largest single-axis growth, deliberately |
| `max_hp_mult` | +3.59 | 6 | all of it is greed or thick blood; `health_factor()` floors at 0.15 |
| `crit_chance` | +0.32 | 2 | plus Sharpshooter's 0.72, clamped at `CRIT_CAP` 0.85 |
| `crit_mult_flat` | +2.70 | 2 | 4.7x crits at the cap; the reason `Mega Crit` is only +0.12 a stack |
| `melee_damage_mult` | +5.25 | 4 | ×6.25 in the hand; the bow gets its own axis so one does not double-dip |
| `throw_damage_mult` | +3.40 | 3 | ×4.4 on a three-charge budget |
| `attack_mult` | +1.20 | 2 | ×2.2 rate on top of any weapon profile, floored at 0.25 |
| `enemy_count_mult` | +2.25 | 3 | greed only: ×3.25 bodies |
| `currency_mult` | +7.25 | 3 | ×8.25 gold; greed pays for its bargains |
| `luck` | +6 | 2 | moves 36 points of common into epic and 24 into legendary, where the surface allows legendary at all |

Three caps are new and exist for one reason each:

- **`CRIT_CAP` 0.85** stays. A crit rolls procs twice in this engine, so a
  guaranteed crit makes every chance row guaranteed too.
- **Mark cap 150 a kind.** Without it, a stack of five mark rows turns a body
  into a damage-over-time bomb with no decision in it.
- **Legendary share of the tier roll, 35%.** A run that picks Streamer Loot four
  times must not stop seeing commons; the tail of the pool is what makes the
  head worth taking.

## The stat contract

### Keys the engine already answers

No work needed — a row that writes one of these is data:

| Key | Curve | Read by |
| --- | --- | --- |
| `damage_mult` | linear | `damage_multiplier()` — shots, swings, throws, staff bolts, procs |
| `attack_mult` | linear | `attack_scale()` → `rig.run_rate_scale` |
| `crit_chance` | linear, clamp 0.85 | `crit_roll()` |
| `max_hp_flat`, `max_hp_mult` | linear | `run_player.apply_stats`, `health_factor()` |
| `heal_on_kill`, `heal_on_clear`, `melee_lifesteal` | linear | the kill, clear and lifesteal paths |
| `currency_mult` | linear | `RunPlayer.currency_multiplier()`, the kill and chest funnels |
| `knockback_mult`, `proc_coeff_mult` | linear | shot plan, swing plan |
| `split_shots`, `pierce`, `ricochet`, `homing`, `wave_damage` | linear | `on_weapon_fire`, `on_melee_swing` |
| `enemy_speed_mult`, `enemy_damage_mult` | linear | `_spawn_spec` |
| `damage_taken_mult` | linear, floored at 0.25 | `ProcEngine.damage_taken_multiplier()` in `on_player_damaged` — Hard Target, Brute Force and Ring Of Defense are its customers |
| `dodge_chance`, `arc_chance`, `nova_chance`, `chain_chance`, `bomb_chance`, `scatter_chance`, `chest_chance`, `mace_chance`, `spike_chance`, `double_chance`, `mega_crit_chance`, `drop_chance`, `throw_burst_chance`, `triple_throw_chance`, `double_burst_chance` | hyperbolic | the fifteen curves in `ProcEngine.HYPERBOLIC` |

### Keys the pool adds

Each one is here because a row writes it and each row names its key. The count is
the real cost of a pool this size; the alternative is a pool of forty rows.

| Area | Keys | Curve |
| --- | --- | --- |
| Shot shape | `flat_damage`, `shot_size`, `spread_add`, `projectile_speed_mult`, `drop_mult`, `windup_per_shot`, `windup_cap`, `streak_per_hit`, `streak_cap`, `splash_frac`, `splash_radius`, `shot_aura_damage`, `shot_aura_duration`, `shot_aura_radius`, `pierce_growth` | linear, and `windup_cap` / `streak_cap` / `pierce_growth` by maximum |
| Standing field | `aura_damage`, `aura_radius` | linear, radius by maximum |
| Shot chances | `mace_chance`, `spike_chance`, `double_chance` | hyperbolic |
| Crit | `crit_mult_flat`, `crit_burst`, `crit_burst_radius`, `mega_crit_chance`, `mega_crit_mult` | linear except `mega_crit_chance` |
| Hand | `melee_damage_mult`, `melee_attack_mult`, `melee_reach`, `melee_delay` | linear |
| Verb upgrades | `roll_charges`, `roll_regen`, `roll_repel`, `roll_refund_throw`, `roll_blades`, `roll_blade_scale`, `parry_window_add`, `parry_refund`, `guard_cost_mult`, `throw_damage_mult`, `throw_speed_mult`, `throw_delay`, `throw_charges_flat`, `throw_regen_mult`, `throw_stagger`, `throw_homing`, `blast_radius`, `throw_fan`, `throw_fan_scale`, `throw_void`, `throw_void_radius`, `throw_spin`, `throw_spin_radius` | linear |
| Verb chances | `triple_throw_chance`, `double_burst_chance` | hyperbolic |
| Marks | `mark_stacks.<kind>`, `mark_potency.<kind>`, `mark_damage_taken_mult`, `mark_lockout.<kind>`, `death_marks.<kind>`, `death_mark_radius` | linear |
| Conditional damage | `damage_high_hp_mult`, `damage_planted_mult`, `damage_close_mult`, `close_range`, `damage_far_mult`, `far_range`, `damage_per_hp`, `damage_per_gold`, `damage_per_kill`, `damage_per_island`, `damage_per_stack`, `damage_per_mark` | linear, each with its own counter; `close_range` and `far_range` by maximum |
| Bursts on an event | `shock_on_hurt`, `shock_radius`, `explode_on_kill`, `explode_radius` | linear |
| Temporary damage | `damage_on_kill`, `attack_on_kill`, `attack_per_island` | linear, timed or persistent |
| Movement | `move_mult`, `roll_distance` | linear |
| Health over time | `regen_hp_per_s`, `regen_window`, `heal_on_hit` | linear |
| Economy and loot | `luck`, `shop_offers`, `shop_discount`, `chest_mods`, `pedestal_offers`, `keep_offer`, `extra_chest_kills`, `extra_chest_islands`, `gold_on_hit`, `gold_on_hit_taken`, `drop_chance` | linear except `drop_chance` |
| Enemy pressure | `enemy_count_mult`, `enemy_health_mult`, `max_hp_flat_on_hit` | linear, greed only |
| Meta | `levelup_per_island` | linear; the only key that writes to **other** rows' stacks, which is why it is capped at 2 |

Four things in the pool's `Writes` column are not keys, and are called out so
nobody adds them to `stats()`: `hop_scale` is a multiplier the effect itself
carries, like the arc's 1.4 and the nova's 0.55, and it lives as
`ProcEngine.HOP_SCALE`; `hands_locked` and `blocks_passive_healing` are the two
existing flags read by `run_player`; `(melee)` on the three edge rows is a
`scope: "melee"` field on the row, not part of the key name, so the row applies
from a swing and never from a shaft; and a row whose target count grows with its
own stacks (`chain_lightning`) reads `stacks_of` rather than a stat, exactly as it
does today.

One omission is deliberate. Their Mango and Banana are both taken, but their
"healing is more effective" multiplier is not: a run body's heals are a bandage
and this pool's own lifesteals, so a heal multiplier would be a multiplier on the
whole health economy rather than on one upgrade. `field_dressing` covers the same
ground as a flat clear heal instead.

## Wiring the surfaces

`draft()` is the single funnel — pedestal, shop, chest, hoard and mini-chest all
call `Mods.draft(...)` and the totem calls `greed_offer`. Nothing else in the pool
touches the world:

```gdscript
# what shipped
Mods.draft(rng, count, tiers, luck, island, exclude)
# tiers: the surface's own ladder row, from Mods.surface_tiers(surface, island)
# the old three-argument call still means the pedestal: draft(rng, 3, false)
Mods.hoard(rng, count, luck, island, exclude)   # the boss's guaranteed legendary
Mods.stall_price(tier, level)                   # 22 + 5 x level + the surcharge
```

| Surface | Offer count | Ladder | Price |
| --- | ---: | --- | --- |
| Pedestal | 3, +1 per 3 `luck`, ±`pedestal_offers` | common, epic from island 2 | free |
| Shop-level pedestal | 1 | common and epic | free |
| Reward chest | 1 mod, +`chest_mods` | common, epic, legendary from island 4 at 4%, greed from island 2 | 38 + 10 an island |
| Warden's Hoard | 2 mods | epic floor, **one legendary** | 60 + 10 an island |
| Shop stall | 3 + `shop_offers` | all four, legendary from island 3, greed from island 2 | by tier, see above |
| Greed Totem | 1 | greed only | 20% of max health |

Four consequences worth stating, because they are the design:

1. **The boss level is where a run's ceiling comes from.** A legendary is the
   hoard's, once, at level 10, 20, 30. Every ten levels a body's build changes
   shape, and the nine levels between are the commons proving the shape was
   worth it.
2. **The pedestal never lies.** Three cards, free, one pick per peer, and the
   tier is visible on the card. The chest is the gamble: one mod, no choice.
3. **Greed is opt-in and already is.** The totem stands on waves 1, 2, 4, 5, 7
   and 8 — not on the shop level at 9, where the shop is the point, and not
   beside a boss at 10. The condition is `not boss_level and wave % 3 != 0`, and
   the comment above it claims "every third level", which is the opposite of what
   the code does; either way level 9 never carries one, which keeps the bargain
   off the breath-before-the-boss level.
4. **The host rolls, the guests receive.** The tier roll happens inside
   `Mods.draft` on the host and the offers travel in the prop payload, exactly as
   they do today. `luck` is per body, so a party's pedestal must roll the tier
   once and let each peer's own luck re-roll *its* card — or, simpler and what
   this design asks for, **the pedestal's ladder uses the best luck in the
   party**, so a lucky body is lucky for the warband. That is one line and it is
   the co-op answer.

## The screens

The pedestal card, the draft button and the shop row already draw the tier colour
from `Mods.RARITY_COLOUR`; 161 rows means the card must say more than a name and
a description.

- **Card**: name in the tier colour, the family as a small caps line under it
  (`SHOT · EPIC`), the description, and a `×n` badge when the body already
  carries the row. Landed: `open_draft` builds all three lines and reads the
  carried count off the local body's engine.
- **Draft list**: `open_draft` builds one button an offer, 620 × 340 for three.
  Seven offers at the ceiling — three, plus Big Chests' two, plus luck's two —
  needs two columns or a 620 × 700 panel. Landed: past four offers the cards go
  into a two-column grid and the panel grows to fit them (`_resize_overlay`).
- **Stack read-out**: twelve rows, then "…and more". Landed: grouped by family
  in `SHOT / HAND / KIT / PERK / RELIC` order with a small caps header per run.
- **Marks**: one thin bar under the health bar on a marked body, one segment a
  kind, coloured per mark. `mob_health_bars.gd` already draws the health bar with
  one `Control` and one `_draw()` for the whole island; the mark pips are one more
  rectangle loop in the same pass and no new node. **Phase 5.**
- **Luck**: shown on the plate, not the card. Landed: `LUCK n` beside the purse,
  and blank at zero.

## Implementation plan

Five phases, each leaving the game playable. No phase needs a row that is not in
the tables above.

| Phase | What lands | Files | State |
| --- | --- | --- | --- |
| 1. The data | the original 120 rows, `RARITY_COLOUR` unchanged, the 23 rows of the migration table, `brutal_pact` out | `scripts/roguelite/mod_catalog.gd` | **landed** |
| 2. The ladder | `draft()` takes a tier row, a luck figure and an island; the surface tables above; `luck` on the plate; the four ladder checks | `mod_catalog.gd`, `run_director.gd` (`_draft_for_party`, `_shop_wares`, `_open_chest`, `_stand_pedestal`), `run_player.gd`, `roguelite_hud.gd` | **landed** |
| 3. The keys that are arithmetic | conditional damage, crit, health, economy, temporary buffs, shot shape, the blast and aura requests, the deferred wound — the keys with a counter and no new node | `proc_engine.gd`, `run_player.gd`, `run_director.gd`, `combat.gd`, `warband_body.gd`, `arrow.gd`, `thrown_weapon.gd` | **landed** |
| 4. The verb upgrades | roll charges and refunds, parry window, guard cost, throw charges — the three verbs with **no run hook today** (roll, parry, guard) plus the throw, whose charges are static registry data. `Combat.defense_resolved` is emitted on every guard outcome and has no subscriber, so parry and guard are one connection each | `combat.gd`, `warband_body.gd`, `run_director.gd`, `proc_engine.gd` | pending |
| 5. The marks | the ledger, the five kinds, the application on hit, the tick, the death marks | new `scripts/roguelite/marks.gd`, `run_director.gd`, `mob_health_bars.gd` | pending |

Two things are out of scope on purpose and are not hidden: **the mark ledger is a
new subsystem**, and **the verb rows need four event hooks that do not exist**.
Both are phase 4 and 5 rather than 1 because a pool without them is still 89 rows
of working upgrades, and neither is worth blocking the ladder on.

Because phases 4 and 5 are pending, the 31 rows that need them carry
`"ready": false` in `mod_catalog.gd`: 12 mark rows (the five mark shots, the three
mark edges, `conducting_bodies`, `mark_expert`, `fire_ring`,
`ring_of_protection`) and all 19 verb rows. `Mods.ready_of` is false for those, and
`draft`, `hoard`, `greed_offer` and `take_mod` all refuse them, so a player never
sees a card that cannot act. The phase that lands a subsystem deletes its
`ready: false` lines and nothing else changes.

## Verifying

The regression pinned the old pool in 28 distinct assertions before this landed
(33 executions, counting the tier loop and the per-offer greed loop). Every one of
them is still green with the test file unchanged by phase 1, which is the gate
this document set:

```powershell
.runtime/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . `
  --script tests/roguelite_regression.gd
```

| Assertion | Kept by |
| --- | --- |
| `Mods.all().size() >= 20` | 161 rows |
| every tier in `Mods.RARITIES` has a row | 47 / 36 / 23 / 14 |
| `split_shot` ×2 means 2 shafts | `split_shots +1`, max 6 |
| `rapid_fire` ×5 + `heavy_caliber` ×1 gives ×1.8 rate and ×1.35 damage | `attack_mult +0.18`, `damage_mult +0.35`, `attack_mult -0.10` |
| `chain_lightning` at 100 stacks stays at the .70 cap | `chain_chance cap .70` |
| `glass_cannon` ×5 is ×6.0 damage and a floored pool | unchanged |
| `crit_sharpshooter` ×6 is 0.72 | `crit_chance +0.12` |
| `draft(rng, 3, false)` returns three unique, no greed | the pedestal's ladder |
| the pedestal gives 3 offers, the totem takes 20% health, the stall sells | the surface table |
| `take_mod`, `choose_draft`, the per-body draft table, the crescent on every swing | untouched |

Two of the document's own numbers were wrong and are corrected here: the rate
figure was ×3.0 for a ×1.8 stack, and the pool was pinned in "ten places" for 28.

Phases 2 and 3 add the checks the plan asked for, all of them new assertions
rather than edits to old ones:

| Check | What it proves |
| --- | --- |
| `_check_pool` census | 161 rows, 63/51/33/14, families 30/11/60/48/12, unique ids, 130 live |
| `_check_pool` ceiling | every row at its cap reads back the design's own ceiling table (+16.42 damage, +280 HP, +3.59 HP multiplier, +0.32 crit, +2.70 crit multiplier, +4.50 hand, +3.40 throw, +1.20 rate, +2.25 bodies, +7.25 gold, +6 luck) |
| `_check_ladder` shelf | an island-1 pedestal is commons, and a six-luck pedestal on island 9 still offers no legendary or greed |
| `_check_ladder` hoard | a boss's hoard always contains one legendary |
| `_check_ladder` roll | the three ladder tiers sum to a hundred, luck leans away from common, the legendary share never passes 35 |
| `_check_ladder` chest | a reward chest's legendary is 4% on island 4 and 5.5% on island 5+ |
| `_check_ladder` stall | a common is 67 and a legendary 137 at level 9 |

The fourth check the plan asked for - "a body at the pool's ceiling clears a level
no faster than the pacing table says" - is the kill-time measurement at the foot
of this document, and it is still the open number: it needs a played run, not a
unit assertion.

## Appendix A — every source row

295 live rows, in the families and tiers the wiki files them under. `Adds` is the
wiki's own `Buff scaling / Debuff scaling`. `Effect` is the row's first line that
carries a number, skipping the wiki's meta bullets ("Does not scale linearly",
"Item requires to be unlocked with the key totem"), and is otherwise verbatim —
including the `(?)` placeholders the wiki never filled in.

| Upgrade | Rarity | Group | Wt | Adds | Effect |
| --- | --- | --- | ---: | --- | --- |
| **Weapon Mods** | | | | | |
| Big Shot | common | Damage | 1 | linear / hyperbolic | Shots are 50% larger and deal 50% more damage (+(?) damage) but move 40% more slowly |
| Blind Fire | common | Damage | 1 | linear / linear | Damage increased by 75% (+(?) damage) but spread increased by 25% |
| Boomerang Shot | common | Damage | 1 | linear | Damage increased by 75% (+(?) damage) |
| Bouncing Shot | common | Damage | 1 | linear | Damage increased by 150% (+(?) damage) after each bounce (+1 bounce per level) |
| Chaotic Shot | common | Damage | 1 | linear | Damage increased by 50% (+(?) damage) |
| Glue Shot | common | Damage | 1 | linear | Damage increased by 75% (+(?) damage) |
| Heavy Hitter | common | Damage | 1 | linear / hyperbolic | Damage increased by 150% (+(?) damage) but fire rate reduced by 20% |
| Heavy Shot | common | Damage | 1 | linear / linear | Shots deal 50% more damage (+(?) damage) but are 15% heavier |
| High Caliber | common | Damage | 1 | linear / hyperbolic | Damage increased by 75% (+(?) damage) but clip size reduced by 25% |
| Mag Shot | common | Damage | 1 | linear | Damage increased by 3% for each bullet remaining in the magazine (up to a max of 100 bullets) |
| Orbiting Shot | common | Damage | 0.25 | linear | Damage increased by 100% (+(?) damage) |
| Recoil Shot | common | Damage | 1 | linear / linear | Damage increased by 75% (+(?) damage) but recoil is increased by 100% |
| Sharp Shot | common | Damage | 1 | linear | Shots deal 4 additional flat damage |
| Snake Shot | common | Damage | 1 | linear | Damage increased by 50% (+(?) damage) |
| Spiral Shot | common | Damage | 1 | linear | Damage increased by 50% (+(?) damage) |
| Steady Shot | common | Damage | 1 | linear / hyperbolic | Damage increased by 75% (+(?) damage) when aiming |
| Streak Shot | common | Damage | 1 | linear | Damage increased by 5% for each shot you hit in a row without missing (up to a max of 100 shots in a row) |
| Time Bolt | common | Damage | 1 | hyperbolic | Chance to fire bolts that deal damage over time along with your shots |
| Time Shot | common | Damage | 1 | linear | Damage increased by 100% (+(?) damage) |
| Trick Shot | common | Damage | 1 | linear / hyperbolic | Damage increased by 50% (+(?) damage) when hipfiring |
| Ultra Shot | common | Damage | 1 | hyperbolic | Chance to fire a bullet dealing 40 dmg along with your shots |
| Wind Up | common | Damage | 1 | linear | Damage increased by 5% for each shot fired until stopping fire (up to a max of 40 shots) |
| Zig Zag Shot | common | Damage | 1 | linear | Damage increased by 50% (+(?) damage) |
| Arcane Shot | common | Elemental | 1 | hyperbolic | Shots apply arcane to enemies |
| Fire Shot | common | Elemental | 1 | hyperbolic | Shots burn enemies |
| Ice Shot | common | Elemental | 1 | hyperbolic | Shots freeze enemies |
| Lightning Shot | common | Elemental | 1 | hyperbolic | Shots shock enemies |
| Poison Shot | common | Elemental | 1 | hyperbolic | Shots poison enemies |
| Random Shot | common | Elemental | 1 | hyperbolic | Shots apply random debuffs to enemies |
| Double Shot | common | Luck | 1 | hyperbolic | Chance to fire in an double shot formation |
| Efficient Shot | common | Luck | 1 | hyperbolic | Chance to fire in an double shot formation |
| Big Mag | common | Skill | 1 | linear | Mag size increased by 40% |
| Grip Tape | common | Skill | 1 | linear | Spread and recoil reduced by 25% |
| Knockback Shot | common | Skill | 1 | linear | Increases knockback by 100% |
| Reload Arc | common | Skill | 1 | linear | Each projectile deals 75 damage |
| Sonic Boom | common | Skill | 1 | linear | deals 250 damage |
| Accelerating Shot | common | Speed | 1 | linear | Damage increased by 75% (+(?) damage) |
| Escalating Shot | common | Speed | 0.25 | linear | Fire rate reduced by 33% but increases by 1% with each shot fired until stopping fire |
| Fast Shot | common | Speed | 1 | linear | Shots are 25% faster and lighter |
| Rapid Fire | common | Speed | 1 | linear | Fire rate increased by 12% |
| Aura Shot | epic | Damage | 1 | linear | Each aura deals 40 damage per second |
| Bubble Shot | epic | Damage | 1 | hyperbolic | Shots that hit enemies have a chance to spawn damaging bubbles nearby |
| Dagger Arc | epic | Damage | 1 | hyperbolic | Fires 7 daggers per activation, each dagger deals 100 per level damage per tick |
| Damage Shot | epic | Damage | 1 | linear | Damage increased by 200% (+(?) damage) |
| Drill Shot | epic | Damage | 1 | hyperbolic | Chance for shots to spawn damaging drills on impact |
| Firework Shot | epic | Damage | 1 | hyperbolic | Chance to fire fireworks along with your shots |
| Link Shot | epic | Damage | 1 | hyperbolic | Chance for shots to burst into 3 link shots on impact |
| Mace Shot | epic | Damage | 1 | hyperbolic | Fires 3 mace balls each time |
| Piercing Wave | epic | Damage | 1 | hyperbolic | Chance to fire slow damaging waves along with your shots |
| Shotgun Blast | epic | Damage | 1 | hyperbolic | Chance to fire deadly shotgun blasts along with your shots |
| Spark Shot | epic | Damage | 1 | hyperbolic | Each activation makes 5-6 sparks |
| Thorn Shot | epic | Damage | 1 | hyperbolic | Chance to fire homing thorns along with your shots that stick to enemies and deal damage over time |
| Money Shot | epic | Economy | 1 | linear | Gain 5 crystals when damaging enemies |
| Arcane Blast | epic | Elemental | 1 | hyperbolic | Fires 3 individual blasts in a sort of arc in front of you with each activation. Each ones does 150 damage per tick |
| Health Shot | epic | Health | 1 | linear | Heal 3 health when damaging enemies |
| Arc Shot | epic | Luck | 1 | hyperbolic | Chance to fire in an arc shot formation |
| Scatter Shot | epic | Luck | 1 | hyperbolic | Chance for shots to scatter into smaller shots on impact |
| Triple Shot | epic | Luck | 1 | hyperbolic | Chance to fire in a triple shot formation |
| X Shot | epic | Luck | 1 | linear | X shot formation is 5 bullets, in an X like pattern |
| Targeting Shot | epic | Skill | 1 | hyperbolic | Chance for shots to target nearby enemies on impact |
| Juiced | epic | Speed | 1 | linear | Damage, fire rate and reload speed increased by 15% |
| Piercing Shot | epic | Speed | 1 | linear | Shots pierce through 1 enemies |
| Supercharged | epic | Speed | 1 | linear | Fire rate increased by 25% |
| Bomb Shot | legendary | Damage | 1 | hyperbolic | Shots that hit enemies have a chance to spawn clusters of bombs nearby |
| Homing Blades | legendary | Damage | 1 | hyperbolic | Shots that hit enemies have a chance to spawn deadly blades that seek out nearby enemies |
| Landmine Shot | legendary | Damage | 1 | hyperbolic | Chance for shots that hit enemies to spawn landmines nearby |
| Proximity Barrage | legendary | Damage | 1 | hyperbolic | Shots that hit enemies have a chance to spawn powerful missiles that seek out nearby enemies |
| Sharpened Axe | legendary | Damage | 1 | hyperbolic | Fires three "axes" that deal 25 per level damage per tick, "axes" mean slightly bigger saw projectiles, from the weapon saw launcher |
| Spike Strike | legendary | Damage | 1 | linear | Spike strikes deal 1000 damage |
| Splash Damage | legendary | Damage | 1 | linear | Shots deal (?) splash damage in 250 unit radius |
| Spore Shot | legendary | Damage | 1 | hyperbolic | Shots have a chance to grow explosive mushrooms from enemies |
| Torpedo Shot | legendary | Damage | 1 | hyperbolic | Torpedo is a slow moving homing projectile |
| Triangle Shot | legendary | Damage | 1 | hyperbolic | Chance to fire powerful triangle projectiles along with your shots |
| Fire Storm | legendary | Elemental | 1 | linear | Fire storms deal 200 damage and apply 700 fire stacks over a 5 second period |
| Fire Strike | legendary | Elemental | 1 | linear | Fire strikes deal 500 damage and apply 400 fire stacks |
| Fireball Shot | legendary | Elemental | 1 | hyperbolic | Chance to fire fireballs along with your shots |
| Ice Storm | legendary | Elemental | 1 | linear | Ice storms deal 160 damage and apply 400 ice stacks over a 4 second period |
| Ice Strike | legendary | Elemental | 1 | linear | Ice strikes deal 500 damage and apply 400 ice stacks |
| Lightning Storm | legendary | Elemental | 1 | linear | Lightning storms deal 80 damage and apply 1200 lightning stacks over a 2 second period |
| Lightning Strike | legendary | Elemental | 1 | linear | Lightning strikes deal 500 damage and apply 500 lightning stacks |
| Poison Storm | legendary | Elemental | 1 | linear | Poison storms deal 160 damage and apply 400 poison stacks over a 400 second period |
| Poison Strike | legendary | Elemental | 1 | linear | Poison strikes deal 500 damage and apply 250 poison stacks |
| Dice Shot | legendary | Luck | 1 | linear | Square shot formation is a 3x3 of bullets, for a total of 9 bullets |
| Double Tap | legendary | Luck | 1 | hyperbolic | Chance for shots to deal damage twice |
| Split Shot | legendary | Luck | 1 | hyperbolic | Shots split into 4 shots midair when proc'd |
| Square Shot | legendary | Luck | 1 | hyperbolic | Square shot formation is a 3x3 of bullets, for a total of 9 bullets |
| Firepower | legendary | Skill | 1 | linear | Fire 1 extra shots with increased spread |
| Homing Shot | legendary | Skill | 1 | hyperbolic | Chance for shots to home towards nearby enemies |
| **Ability Mods** | | | | | |
| Big Grenade | common | Damage | 1 | linear / hyperbolic | Grenades are 50% larger and deal 50% more damage (+(?) damage) but move 15% more slowly |
| Chaotic Grenade | common | Damage | 1 | linear | Damage increased by 50% (+(?) damage) |
| Glue Grenade | common | Damage | 1 | linear | Damage increased by 66% (+(?) damage) |
| Heavy Grenade | common | Damage | 1 | linear / linear | Greandes deal 50% more damage (+(?) damage) but are 25% heavier |
| Imploding Grenade | common | Damage | 1 | linear / hyperbolic | Grenades deal 50% more damage (+(?) damage) but have a 20% smaller explosion radius |
| Snake Grenade | common | Damage | 1 | linear | Damage increased by 50% (+(?) damage) |
| Spiral Grenade | common | Damage | 1 | linear | Damage increased by 50% (+(?) damage) |
| Bigger Boom | common | Skill | 1 | linear | Grenades have a 33% larger explosion radius |
| Aura Grenade | epic | Damage | 1 | linear | Auras deal 25 damage per second |
| Barrel Explosion | epic | Damage | 1 | linear | Each barrel deals 100 damage when exploding |
| Bubble Blast | epic | Damage | 1 | linear | Each bubble deals 100 damage per second |
| Dagger Blast | epic | Damage | 1 | linear | Each dagger deals 100 damage per second |
| Damage Grenade | epic | Damage | 1 | linear | Damage increased by 150% (+(?) damage) |
| Firework Explosion | epic | Damage | 1 | linear | Each firework deals 100 damage |
| Giant Drill | epic | Damage | 1 | linear | Giant drills deal 100 damage over a Duration second period |
| Spark Explosion | epic | Damage | 1 | linear | Each spark deals 100 damage per second |
| Thorn Explosion | epic | Damage | 1 | linear | Each thorn deals 100 damage per second |
| Layered Grenade | epic | Luck | 1 | hyperbolic | 25% chance for grenades to explode twice |
| Triple Grenade | epic | Luck | 1 | hyperbolic | 25% chance to throw 3 grenades at once |
| Grenadier | epic | Skill | 1 | linear | Gain 1 extra uses of your grenade |
| Bomb Explosion | legendary | Damage | 1 | linear | Each bomb deals 100 damage |
| Crystal Barrage | legendary | Damage | 1 | linear | Crystal barrages deal 100 damage over a Duration second period |
| Crystal Strike | legendary | Damage | 1 | linear | Crystal strikes deal 100 damage |
| Energy Ring | legendary | Damage | 1 | linear | Energy rings deal 100 damage on each hit |
| Scythe Vortex | legendary | Damage | 1 | linear | Scythe vortexes deal 100 damage over a Duration second period |
| Spike Strike | legendary | Damage | 1 | linear | Spike strikes deal 100 damage |
| Spinning Blade | legendary | Damage | 1 | linear | Each blade deals 100 damage per second |
| Spore Explosion | legendary | Damage | 1 | linear | Mushrooms deal 100 damage and apply (?) poison stacks when exploding |
| Ultra Mushroom | legendary | Damage | 1 | linear | Mushrooms deal 100 damage when exploding |
| Fire Explosion | legendary | Elemental | 1 | linear | Cooldown: 10 seconds |
| Ice Explosion | legendary | Elemental | 1 | linear | Cooldown: 12 seconds |
| Lightning Explosion | legendary | Elemental | 1 | linear | Cooldown: 8 seconds |
| Poison Explosion | legendary | Elemental | 1 | linear | Cooldown: 6 seconds |
| Black Hole | legendary | Skill | 1 | linear | Black holes have a 50% larger radius |
| Clone Explosion | legendary | Skill | 1 | linear | Grenades spawn 1 more grenades when exploding |
| Homing Grenade | legendary | Skill | 1 | hyperbolic | Grenades home towards enemies with 50% speed |
| **Melee Mods** | | | | | |
| Iron Claws | common | Damage | 1 | linear / linear | Melee damage increased by 300% (+(?) damage) but melee cooldowns are increased by 50% (?) |
| Sharp Claws | common | Damage | 1 | linear | Melee damage increased by 100% (+(?) damage) |
| Time Claws | common | Damage | 1 | linear / linear | Melee damage increased by 150% (+(?) damage) but damage is done over time |
| Vampire | common | Health | 1 | linear | Heal 4 health after each melee elimination |
| Big Claws | common | Skill | 1 | linear | Melee range increased by 20% |
| Blender | common | Speed | 1 | hyperbolic | Melee cooldowns reduced by 20% |
| Arcane Claws | epic | Elemental | 1 | linear | Melee ignites enemies with 25 arcane stacks |
| Fire Claws | epic | Elemental | 1 | linear | Melee ignites enemies with 25 fire stacks |
| Ice Claws | epic | Elemental | 2 | linear | Melee freezes enemies with 50 ice stacks |
| Lightning Claws | epic | Elemental | 1 | linear | Melee ignites enemies with 25 lightning stacks |
| Poison Claws | epic | Elemental | 1 | linear | Melee ignites enemies with 25 poison stacks |
| Brawler | greed | Greed | 1 | linear / hyperbolic | Melee damage increased by 250% but weapon damage reduced by 33% |
| **Perks** | | | | | |
| Anti Crit | common | Critical | 1 | linear / linear | Damage increased by 20% but critical hit chance reduced by 20% |
| Critical Arrow | common | Critical | 2 | hyperbolic | 12% chance for critical hits to fire arrows at enemies that deal 40 damage |
| Critical Thinking | common | Critical | 2 | linear / hyperbolic | Critical hits deal 25% more damage but non critical hits deal 10% less damage |
| Hot Shot | common | Critical | 1 | linear / linear | Critical hit chance increased by 12% but incoming damage increased by 20% |
| Power Punch | common | Critical | 2 | linear | Critical hit damage increased by 40% |
| Sharpshooter | common | Critical | 1 | linear | Critical hit chance increased by 6% |
| Damage Combo | common | Damage | 1 | linear | Damage increased by 15% per combo level |
| Danger Close | common | Damage | 1 | linear | Damage increased by 30% to nearby enemies |
| Eagle Eye | common | Damage | 1 | linear | Damage increased by 30% to distant enemies |
| Enhanced Turrets | common | Damage | 1.5 | linear | Turret damage increased by 50% |
| Equalizer | common | Damage | 1 | linear | Damage increased by 30% if you currently have an even number of equipped perks |
| Explosive Armor | common | Damage | 1 | linear | Armor explosions deal 60 damage |
| Giant Slayer | common | Damage | 1 | linear | Damage increased by 12% |
| Power Armor | common | Damage | 1 | linear | Damage increased by 15% for each equipped armor plate |
| Weight lifter | common | Damage | 1 | linear | Damage increased by 30% but movement is reduced by 8% |
| Crystal Combo | common | Economy | 1 | linear | Enemies drop 20% more crystals per combo level |
| Paycheck | common | Economy | 1 | linear | Gain 20% of the price of a common pickup (currently ### crystals) after clearing each island |
| Snatcher | common | Economy | 1 | linear | Enemies eliminated at close range drop 75% more crystals |
| Special Delivery | common | Economy | 1 | linear | Shops contain 1 more goods for sale |
| Tony's Black Card | common | Economy | 1 | hyperbolic | Shop prices are discounted by 8% |
| Elemental Expert | common | Elemental | 1 | linear | Damage increased to enemies by 15% per unique debuff applied to them |
| Elemental Specialist | common | Elemental | 1 | linear | Damage increased to enemies by 50% if they have exactly one debuff applied to them |
| Firestarter | common | Elemental | 1.5 | linear | Fire strength increased by 25% |
| High Voltage | common | Elemental | 1.5 | linear | Lightning strength increased by 25% |
| Hot Steam | common | Elemental | 1.5 | linear | Enemies take a burst of 300 fire damage when ignited |
| Ice Cold | common | Elemental | 1.5 | linear | Ice strength increased by 25% |
| Poisonous Armor | common | Elemental | 1 | linear | Armor explosions apply 40 poison stacks |
| Potent Magic | common | Elemental | 1.5 | linear | Arcane strength increased by 25% |
| Toxic | common | Elemental | 1.5 | linear | Increased by 40% |
| Banana | common | Health | 1.5 | linear | Increases your max health multiplier by 20%. |
| Bulletproof | common | Health | 1 | hyperbolic | 6% chance to block incoming damage |
| Bullseye | common | Health | 1 | linear | Max health increased by 1 after every one shot (losing all health within 0.25 seconds) elimination |
| Endurance | common | Health | 1 | linear | Heal 200 health after clearing each island |
| Fortitude | common | Health | 1 | linear | Max health increased by 25 after clearing each island |
| Hard Target | common | Health | 1 | linear | Incoming damage reduced by 8% |
| Liquid Core | common | Health | 1 | linear | Heals 25 health |
| Mango | common | Health | 1.5 | linear | Add 250 to your base max health with each level |
| Personal Space | common | Health | 1 | linear | Max health increased by 1 after every close range elimination |
| Regenerator | common | Health | 1 | linear | Health rapidly regenerates for the first 60 seconds of an island |
| Scavenger | common | Health | 1 | linear | Enemies have a 10% chance (100% chance on large enemies) to drop health pickups that heal 35 health |
| Valued Customer | common | Health | 1 | linear | Max health increased by 25 when making purchases at shops |
| Vitality | common | Health | 1 | linear | Damage increased by 30% when at high health |
| Bounty Hunter | common | Luck | 1 | hyperbolic | Large enemies have a 5% chance to drop loot when eliminated |
| Charger | common | Luck | 1 | linear | 10% Spawns 3 charge zones |
| Driller | common | Luck | 1 | hyperbolic | Destroying destructible rocks has a 5% chance to spawn loot |
| Streamer Loot | common | Luck | 1 | hyperbolic | Loot drops have a 4% chance to be upgraded to a higher rarity |
| Crystal Fertilizer | common | Skill | 1 | linear | 20% more destructible crystals and health rocks spawn |
| Magnify | common | Skill | 1 | linear | Area of effect increased by 20% (affects all damage sources and is multiplicative with other increases to damage radius) |
| Slugger | common | Skill | 1 | linear | Explosive enemy explosion damage and radius increased by 100% |
| Speed Demon | common | Speed | 1 | linear | Movement speed increased by 20% |
| Stamina | common | Speed | 1 | linear | Gain 1 more dashes |
| Critical Blast | epic | Critical | 2 | hyperbolic | 15% chance for critical hits to create powerful explosions that deal 35 damage |
| Mega Crit | epic | Critical | 2 | hyperbolic | 10% chance to Mega Crit when landing critical hits |
| Assassin | epic | Damage | 1 | linear | Damage increased by 1% after every 10 one shot (losing all health within 0.25 seconds) eliminations |
| Checklist | epic | Damage | 1 | linear | Damage increased by 1% after every 25 eliminations |
| Collector | epic | Damage | 1 | linear | Damage increased by 4% for each perk level that you have |
| Crimson Haze | epic | Damage | 1 | linear | Damaging zones deal 200 damage over a 3 second period |
| Damage Aura | epic | Damage | 1 | linear | Deal 20 damage per second to nearby enemies |
| Exploding Enemies | epic | Damage | 1 | linear | Enemy explosions deal 100 damage |
| Gemstone | epic | Damage | 1 | linear | Damage increased by 4% after clearing each island |
| Orbiting Scythes | epic | Damage | 1 | linear | Each scythe deals 60 damage per second |
| Silver Lining | epic | Damage | 1 | linear | Damage increased by 2% each time you take damage greater than 5% of your max health |
| Tasty Orange | epic | Damage | 1 | linear | Damage increased by 1% for each enemy eliminated on an island |
| Bonus Crystals | epic | Economy | 1 | linear | 75% more crystals drop when eliminating enemies |
| Gold Coating | epic | Economy | 1 | linear | Gain 100% of healing as crystals (doesn't work in shops) |
| Money Is Power | epic | Economy | 1 | linear | Damage increased by 1% for every 250 crystals you have (up to a cap of 25000 crystals) |
| Fire Aura | epic | Elemental | 1 | linear | Deal 50 damage and apply 50 fire stacks to nearby enemies |
| Flammable Armor | epic | Elemental | 1 | linear | Armor explosions apply 30 fire stacks |
| Ice Aura | epic | Elemental | 1 | linear | Deal 50 damage and apply 50 ice stacks to nearby enemies |
| Lightning Aura | epic | Elemental | 1 | linear | Deal 50 damage and apply 50 lightning stacks to nearby enemies |
| Poison Aura | epic | Elemental | 1 | linear | Deal 50 damage and apply 50 poison stacks to nearby enemies |
| Amber Resin | epic | Health | 1 | linear | Healing is 40% more effective |
| Grim Reaper | epic | Health | 1 | linear | Heal 3 health after eliminating enemies. Medium enemies heal 2x more, large enemies heal 5x more and Elite + Boss enemies heal 10x more |
| Health Is Power | epic | Health | 1 | linear | Damage increased by 1% for every 25 health you have |
| Survivor | epic | Health | 1 | hyperbolic | Block chance increased and incoming damage reduced by 8% |
| Double Vision | epic | Luck | 1 | hyperbolic | 15% chance to get to double all chests after clearing each island |
| Performance Bonus | epic | Luck | 1 | linear | 30% chance to get an extra chest when flawlessly clearing an island |
| All You Can Eat | epic | Skill | 1 | hyperbolic | No ammo is used for 2 seconds after eliminating an enemy |
| Big Chests | epic | Skill | 1 | linear | Chests contain 1 more loot choices |
| Shockwave | epic | Skill | 1 | linear | Taking damage sends out a shockwave that deals 150 damage to all visible enemies |
| Sturdy Totems | epic | Skill | 1 | linear | Totems have 1 more guaranteed uses before they explode |
| Totem Enthusiast | epic | Skill | 1 | linear | 1 more totems spawn any time a natural totem spawn happens |
| Speed Is Power | epic | Speed | 1 | linear | Damage increased by 1% for every bonus movement speed % you have |
| Critical Lightning | legendary | Critical | 2 | linear | Critical hits shock random enemies with 250 lightning stacks |
| Electric Enemies | legendary | Elemental | 1 | linear | Enemies apply 50 lightning stacks when eliminated |
| Flammable Enemies | legendary | Elemental | 1 | linear | Enemies apply 75 fire stacks when eliminated |
| Freezing Enemies | legendary | Elemental | 1 | linear | Enemies apply 50 ice stacks when eliminated |
| Ice Dash | legendary | Elemental | 1 | linear | Apply 100 ice stacks to nearby enemies when dashing |
| Lightning Dash | legendary | Elemental | 1 | linear | Apply 200 lightning stacks to nearby enemies when dashing |
| Poisonous Enemies | legendary | Elemental | 1 | linear | Enemies apply 25 poison stacks when eliminated |
| Crystal Asteroids | legendary | Luck | 1 | linear | 25% chance for asteroids containing bonus loot to spawn on each island |
| Faulty Chests | legendary | Luck | 1 | hyperbolic | 15% chance for unchosen chest loot to not disappear |
| Rare Treasure | legendary | Luck | 1 | hyperbolic | Enemies have a 1% chance to drop loot when eliminated |
| Bonus Chests | legendary | Skill | 1 | linear | Get 1 extra chests after every 200 eliminations |
| Care Package | legendary | Skill | 1 | linear | Get 1 extra chests after clearing every 4th island |
| Level Up | legendary | Skill | 1 | linear | 1 random mods and perks are upgraded to the next level after clearing every 3rd island |
| Dagger Dash | legendary | Speed | 1 | linear | Each dagger deals 100 damage per second |
| Powerslide | legendary | Speed | 1 | linear | Sliding constantly deals 10 damage and applies 10 fire stacks to nearby enemies |
| Big Bones | greed | Greed | 1 | linear / linear | Max health and damage increased by 25% but you grow 10% larger |
| Bribe | greed | Greed | 1 | linear / hyperbolic | Max health increased by 200% but lose 5% crystals when taking damage |
| Brute Force | greed | Greed | 1 | linear / linear | Damage increased by 25% but incoming damage increased by 25% |
| Damage Seeker | greed | Greed | 1 | linear / hyperbolic | Damage increased by 150% but lose 1% max health when taking damage |
| Double Trouble | greed | Greed | 1 | linear / linear | Max health increased by 200% but enemy health increased by 50% |
| Glass Cannon | greed | Greed | 1 | linear / hyperbolic | Damage increased by 250% but max health decreased by 80% |
| High Roller | greed | Greed | 1 | linear / hyperbolic | (?)% chance for 1 more reward chests to spawn but also a 20% chance for no chests to spawn at all |
| Hoarder | greed | Greed | 1 | hyperbolic | 15% chance for an extra chest to spawn after each island but you can no longer drop pickups from your inventory |
| Juggernaut | greed | Greed | 1 | linear / linear | Max health increased by 50% but 15% more enemies spawn |
| Leap Of Faith | greed | Greed | 1 | linear / hyperbolic | Max health increased by 150% but 10% max health is dealt as fall damage |
| Limited Loot | greed | Greed | 1 | linear / linear | 75% more crystals drop when eliminating enemies but there are 1 less loot choices in chests |
| Rising Star | greed | Greed | 1 | linear / linear | 75% more crystals drop when eliminating enemies but 20% more enemies spawn |
| Slippery Slope | greed | Greed | 1 | linear / hyperbolic | Gain (?) crystals but lose 20% health at the start of each island |
| Up The Ante | greed | Greed | 1 | linear / linear | Damage increased by 25% but 20% more enemies spawn |
| Workaholic | greed | Greed | 1 | linear / hyperbolic | 75% more crystals drop when eliminating enemies but max health decreased by 20% |
| **Relics** | | | | | |
| Tony's Amulet | common | Economy | 0.2 | linear | Shops contain 5 more goods for sale |
| Ring Of Armor | common | Health | 0.2 | linear | Gain an armor plate if starting an island with no armor |
| Ring Of Healing | common | Health | 0.2 | linear | Health rocks are guaranteed to spawn on each island |
| Ring Of Healthy Turrets | common | Health | 0.2 | linear | Turret health increased by 200% |
| Ring Of Vigor | common | Health | 0.2 | linear | Max health multiplier increased by 3% after clearing each island. |
| Blacksmith Amulet | common | Skill | 0.2 | linear | Increases the number of anvils on Anvil islands from 3 to 5. |
| Combo Ring | common | Skill | 0.2 | linear | Max combo increased by 3 |
| Coral Amulet | common | Skill | 0.2 | linear | Chests contain 2 more loot choices |
| Portal Ring | common | Skill | 0.2 | linear | Gain an extra portal choice after each island |
| Ring Of Destruction | common | Skill | 0.2 | linear | Reset all cooldowns and reload weapons when destroying destructible rocks |
| Adrenaline Amulet | common | Speed | 0.2 | linear | Fire rate increased by 25% for 5 seconds after eliminating an enemy. |
| Ring Of Precision | epic | Critical | 0.2 | linear | Critical hit damage multiplier increased by 150% |
| Ring Of Wisdom | epic | Critical | 0.2 | linear | Critical hit chance increased by 2% after clearing each island. |
| Ring Of Fury | epic | Damage | 0.2 | linear / linear | Weapon damage increased by 50% for 5 seconds after eliminating an enemy. |
| Ring Of Power | epic | Damage | 0.2 | linear / linear | Weapon damage increased by 400% but fire rate reduced by 80% |
| Time Ring | epic | Damage | 0.2 | linear / linear | Pairs well with Time Shot (Damage increased by 100% but it is dealt over time) |
| Ring Of Dividends | epic | Economy | 0.2 | linear | Gain 10% of your total crystals as a bonus after clearing each island. |
| Ring Of Value | epic | Economy | 0.2 | linear | Shops always contain a pedestal that is discounted by 75% |
| Arcane Ring | epic | Elemental | 0.5 | linear | Arcane strength increased by 250% |
| Fire Ring | epic | Elemental | 0.5 | linear | Fire strength increased by 250% but Ice no longer has any effect |
| Ice Ring | epic | Elemental | 0.5 | linear | Ice strength increased by 250% but Fire no longer has any effect |
| Lightning Ring | epic | Elemental | 0.5 | linear | Lightning strength increased by 250% but Poison no longer has any effect |
| Poison Ring | epic | Elemental | 0.5 | linear | Poison strength increased by 250% but Lightning no longer has any effect |
| Ethereal Armor | epic | Health | 0.2 | linear | Gain 1 armor plate at the start of every 3 islands |
| Ring Of Defense | epic | Health | 0.2 | linear | Incoming damage reduced by 40% |
| Ring Of Reinforcement | epic | Health | 0.2 | linear | Gain 2 extra armor plates each time you gain armor |
| Blacksmith Ring | epic | Skill | 0.2 | linear | Pairs well with Blacksmith Amulet |
| Duplication Ring | epic | Skill | 0.2 | linear | Get an extra chest when flawlessly clearing elite or boss islands |
| Full Metal Jacket | epic | Skill | 0.2 | linear | All damage penetrates enemy armor |
| Ring Of Repulsion | epic | Skill | 0.2 | linear | Dashing repels nearby enemy projectiles |
| Ring Of Rocket Jumping | epic | Skill | 0.2 | linear | Friendly explosions cause you to rocket jump into the air |
| Skill Ring | epic | Skill | 0.2 | linear | Upgrade Epic chests to Legendary chests when flawlessly clearing an island |
| Ring Of Reloading | epic | Speed | 0.2 | linear | Reload speed increased by 60% |
| Turbo Ring | epic | Speed | 0.2 | linear | Fire rate increased by 2% after clearing each island. |
| Ring Of Protection | legendary | Health | 0.2 | linear | Incoming elemental damage reduced by 75% |
| Ring Of Regenerating Armor | legendary | Health | 0.2 | linear | Gain an armor plate at the start of each island |
| Ring Of Deflection | legendary | Luck | 0.2 | linear | 25% chance to block incoming damage |
| Ring Of Luck | legendary | Luck | 0.2 | linear | All chance based perks and totems are 75% more likely to trigger |
| Ammo Ring | legendary | Skill | 0.2 | linear | Dashing reloads your weapon |
| Portal Amulet | legendary | Skill | 0.05 | linear | Weapon shots are fired from the nearest enemy instead of from your weapon |
| Twin Ring | legendary | Skill | 0.05 | linear | All turrets spawn in pairs. |
| Ability Ring | legendary | Speed | 0.2 | linear | Ability cooldowns reduced by 50% |
| Ring Of Gravity | legendary | Speed | 0.2 | linear | Gain low gravity movement |
| Ring Of Swiftness | legendary | Speed | 0.2 | linear | Gain hugely increased movement speed |
| Hoarder's backpack | greed | Greed | 1 | none | Allows the ability to pick up all items out of a chest |
| Ring of Tankiness | greed | Greed | 1 | none | Max health increased by 2500 but movement speed reduced by 60% |

## Appendix B — the nineteen rows the wiki files as removed

Kept in the dataset under `live: false` because the extraction should hold what
the page says, not what the pool wants. They carry a tier like any other row — 15
common, 1 epic, 3 greed — so the wiki stripped them of a place in the family list,
not of their rarity.

None of them is in the re-cut. `Autoloader` and `Second Wind` would have crossed
if the machinery existed — one is a reload trigger, one is a low-health damage
bonus — and are the first two rows to look at if the dropped mechanics ever land.

| Upgrade | Family | Tier | Filed under | Effect |
| --- | --- | --- | --- | --- |
| Autoloader | perk | common | Indefinitely Removed | 10% chance to instantly reload after each elimination |
| Big Hearts | perk | common | Indefinitely Removed | Gain 100% more max health from hearts |
| Critical Claws | perk | common | Indefinitely Removed | Was a perk that was removed prior to 'Claw' perks being converted to melee mods |
| Cursed Lottery | perk | greed | Indefinitely Removed | Gain 100000 crystals but lose 99.5% max health |
| Double Edged Sword | perk | greed | Indefinitely Removed | Gain crystals worth 25% of damage dealt but lose 20% of your total crystals when taking damage |
| Finishing Move | perk | common | Indefinitely Removed | Enemies eliminated with critical hits drop 50% more crystals |
| Grave Dodger | perk | epic | Indefinitely Removed | Heal for 20% of your max health when reaching 1 health |
| Healthy Combo | perk | common | Indefinitely Removed | Heal 100 health when increasing your combo |
| Ice Cube | perk | common | Indefinitely Removed | Damage increased by 25% to frozen enemies |
| Metal Rod | perk | common | Indefinitely Removed | Damage increased by 25% to shocked enemies |
| Nourishing Salvage | perk | common | Indefinitely Removed | Heal 250 health when salvaging pickups |
| Oil Can | perk | common | Indefinitely Removed | Damage increased by 25% to burning enemies |
| Playing With Power | perk | greed | Indefinitely Removed | Needs information Added |
| Poison Vial | perk | common | Indefinitely Removed | Damage increased by 25% to poisoned enemies |
| Rigged Totems | perk | common | Indefinitely Removed | Chance based totems are 25% more likely to roll in your favor |
| Second Wind | perk | common | Indefinitely Removed | Damage increased by 25% when at low health |
| Aerial Shot | weapon | common | Removed Weapon Mods | Damage increased by 50% (+(?) damage) when airborne |
| Light Shot | weapon | common | Removed Weapon Mods | Fire rate increased by 15% but shots deal 15% less damage |
| Uppercut | weapon | common | Removed Weapon Mods | Damage increased by 250% (+(?) damage) on every fifth shot |

## Gate

Where this document stands against its own four conditions:

- **The data is current.** The 314-row dataset is committed and the census in
  *The source system* (295 live / 19 removed, five families, nine groups) was
  re-checked against it row for row: every one of the 115 mirrored rows resolves
  to a source name at the tier this document claims. `fetch_crab_champions.py
  --check` is the command that keeps that true.
- **The migration is mechanical.** Phase 1 landed with
  `tests/roguelite_regression.gd` untouched and green: the pool's 161 rows, the
  tier inheritances of the migration table and `brutal_pact` retired are data
  changes only.
- **The ladder is testable.** The checks exist and pass (`_check_pool`,
  `_check_ladder`), and they were written to fail against the old weighted
  `draft()`, which ignored the tier entirely. The kill-time check is the one still
  open, and it is open because it needs a played run.
- **The two substructures are costed, not assumed.** The mark ledger and the four
  verb hooks are phases 4 and 5, both pending, both gated: 31 rows carry
  `ready: false` and the surfaces offer the other 89. That is the number the
  implementation plan names, and it is a ceiling on what the pool can pretend to
  do until those two land.

The number to watch once the last two phases are wired is kill time, and it is not
on these tables. A run grants about twenty stacks by the end of its first island
and the wave's own pool grows by `1 + 0.13 x island + 0.055 x wave`. The pool is
balanced if kill time is flat across an island; if it is falling, the commons are
priced too high, and the fix belongs in the per-tier table at the top of *The
pool*, not in a single row.

# The Crab-shaped backlog

**What else to borrow from Crab Champions, why it works, and what it would cost
Blood Champions.** Research and prioritization, not a commitment.

The live loop is [run.md](run.md); the gate/chest design is
[run-loop-design.md](run-loop-design.md); the 172-row loot pool is
[upgrade-pool.md](upgrade-pool.md). This document is the layer above those:
what else the source does that we do not, and which of it is worth taking.

> **The thesis.** We already have Crab Champions' loot and a Crab-shaped block.
> We do not yet have the systems that make that loot *replayable*: movement
> depth, priced risk, run variety, mastery goals, and co-op friction removal.
> The next feature is not another 100 rows. It is a system that makes the
> existing 172 rows matter in a new way.

---

## 1. What Crab Champions does well

Crab Champions is in Early Access and its numbers move. The stable design
lessons are below; the exact values are snapshots.

| Driver | What the source does | Why it works |
| --- | --- | --- |
| **Movement as combat** | Slide, double jump, air dash, flip, and a dash-timed parry. Aim and movement are separate skills. | The player can dodge and keep the reticle on the target; survival and style are the same verb. Reviews consistently name movement as the game's standout. |
| **Build escalation** | Five upgrade families; duplicate picks level a row; targeted chest categories; one-off Relics; targeted Enhancements. | A build is not a pile of unrelated stats. It is a handful of rows that multiply each other, and the player can feel the power spike. |
| **Priced risk** | Spiked and Greed chests, totems, challenge modifiers, Elites, difficulty modifiers. | The player signs the cost before the reward; failure feels authored, not arbitrary. |
| **Run variety** | Arena, Horde, Demolition, Gauntlet, Parkour, Waves, Challenge, Elite, Shop, Anvil; blessings and challenge modifiers. | A run is not the same fight with a different number. The objective changes what movement and build matter. |
| **Mastery layer** | Difficulty tiers, optional modifiers, Challenge Level, per-weapon medals, looping. | Long-term goals are records, not permanent power. The player can push the same content harder instead of only unlocking more of it. |
| **Co-op friction removal** | Auto-loot, shared crystal income, portal voting, revival, pings. | Four players spend time fighting, not waiting for one person to read a menu. |

### 1.1 Movement is the first lesson

Crab's movement is not traversal; it is defense, offense and expression at once:

- **Slide** gives speed and a smaller profile.
- **Air dash / flip** gives i-frames and repositioning without losing aim.
- **Parry** is a dash timed into a blow, with a short invulnerability window.
- The review's summary is the design brief: movement is *decoupled from aim*,
  so the skill ceiling is in both at the same time.

Sources: [Game Mechanics](https://crabchampions.wiki.gg/wiki/Game_Mechanics);
[review](https://game.lb-product.com/en/games/crab-champions/guides/crab-champions_review).

### 1.2 Build escalation is the second

The source's builds are stacks, not collections:

- Duplicates level the same row, so every pick can deepen the build.
- Chest categories let the player aim the run before the fight.
- Relics are one-off rules; Enhancements target a specific row.
- The late run is a handful of absurd synergies, not fifty unrelated commons.

Sources: [Chests](https://crabchampions.wiki.gg/wiki/Chests),
[Rarities](https://crabchampions.wiki.gg/wiki/Rarities),
[The Variety Update Part 2](https://crabchampions.wiki.gg/wiki/The_Variety_Update_Part_2),
[The Anvil Update](https://crabchampions.wiki.gg/wiki/The_Anvil_Update).

### 1.3 Risk is a product, not a punishment

The source repeatedly puts a visible price on a visible reward:

- Spiked chest: health for epic loot.
- Greed chest / Greed Totem: a real downside for a strong row.
- Challenge modifiers: a harder island for an extra chest.
- Totems: health, max health or crystals for a random outcome.
- Difficulty modifiers: more danger for Challenge Level and medals.

The player is never surprised by the price; they are only surprised by whether
they can pay it.

Sources: [Totems](https://crabchampions.wiki.gg/wiki/Totems),
[Island Modifiers](https://crabchampions.wiki.gg/wiki/Island_Modifiers),
[Difficulty](https://crabchampions.wiki.gg/wiki/Difficulty).

### 1.4 Variety is objective variety, not enemy count

Crab's islands ask different questions: kill everything (Arena), survive
(Horde), destroy nests (Demolition), push a cash-out gauntlet (Gauntlet),
execute a route (Parkour), accept a modifier (Challenge). The player picks the
question at the portal.

Source: [Islands](https://crabchampions.wiki.gg/wiki/Islands),
[The Island Update](https://crabchampions.wiki.gg/wiki/The_Island_Update).

### 1.5 Mastery is records, not permanent power

Difficulty tiers plus modifiers feed Challenge Level; medals are per weapon;
Diamond requires a deep run at a high Challenge Level. The meta is thin on
permanent power (a common criticism of the source), but it is deep on
*self-set* goals.

Source: [Difficulty](https://crabchampions.wiki.gg/wiki/Difficulty),
[review](https://game.lb-product.com/en/games/crab-champions/guides/crab-champions_review).

### 1.6 Co-op removes waiting

The source's co-op quality-of-life is part of the loop: shared crystal income,
auto-loot, a portal vote that starts a countdown only when the majority has
chosen, revival zones, pings and player colours.

Sources: [The Difficulty Update](https://crabchampions.wiki.gg/wiki/The_Difficulty_Update),
[The Variety Update Part 2](https://crabchampions.wiki.gg/wiki/The_Variety_Update_Part_2),
[The Island Update](https://crabchampions.wiki.gg/wiki/The_Island_Update).

### 1.7 What the source gets wrong

Do not copy the weaknesses:

- Balance is uneven; some weapons and rows clearly outclass others.
- Long looping sessions can become repetitive and grindy.
- Permanent meta progression is comparatively thin.
- Some content (PvP, parkour) was cut or deprioritised because it did not serve
  the core loop.

The lesson is to borrow the **decision architecture and feel**, not the content
volume or the grind.

---

## 2. What we already have, and what is missing

| System | Blood Champions status | Gap |
| --- | --- | --- |
| Loot | 172 rows, five families, four tiers, stacking, per-body drafts, armour weld | The pool is deep; the surfaces that expose it are still narrow. |
| Run block | 10 levels: 1–5 combat, 6 market, 7–8 combat, 9 full shop, 10 boss | One objective: kill the wave. |
| Factions | Watchers, demons, blood clones with distinct pools/kits | No enemy affixes or per-run buffs. |
| Risk | Chest tiers; trials designed; greed on the stall and the hoard | No totem of any kind; no priced shop choice. |
| Build depth | Shot/hand/ability/perk/relic; 31 `ready:false` rows | No combo; no mark ledger; 19 verb rows are not live. |
| Meta | Keys, armory, ability book, best level | No difficulty, Challenge Level or medals. |
| Co-op | Host authority, chest revive, AI squadmates | No ally revive channel, no gate vote, no shared route agency. |
| Bosses | Faction boss + escort | Bosses are scaled bodies; no phases/armour/decay rules. |
| Movement | Sprint, dodge/jump-roll, guard, parry | No slide/air-dash layer; parry feedback is quiet. |

The cheapest unfinished content is already in the repo: **31 rows are gated
behind the mark ledger and the roll/guard/parry/throw hooks** (`ready: false`).
Nineteen of them are verb rows for buttons the game already has. Unlocking
those is a build-depth win with no new art and no new enemy.

Sources: `scripts/roguelite/mod_catalog.gd`, `docs/upgrade-pool.md`.

---

## 3. The backlog, ranked

The ranking is **fun per unit of work**, not a roadmap. “S/M/L” is a rough
effort band; “Now” means it reuses existing systems.

### Tier 1 — cheap variety

| # | Feature | Crab source | Blood Champions adaptation | Effort | Verdict |
| ---: | --- | --- | --- | --- | --- |
| 1 | **Totems** | Chance, Gold, XL, Crystal, Health, Random | A totem prop the run does not have: Chance (health for a random row), Gold (max health for an epic/legendary row), XL (next level harder, +1 chest). | M | **Next.** The prop, the per-body use and the health price would all be new. |
| 2 | **Shop reroll + Upgrade Totem** | Reroll Totem; Upgrade Totem | A reroll button with escalating gold cost; one Upgrade Totem per full shop to add a stack to an owned row. | S/M | **Now.** Turns the stall into a build decision. |
| 3 | **Enemy affixes** | Buffed Enemies (Healthy/Speedy/Angered/Frenzied/Shielded) | A small chance from island 2 for one affix; elites/bosses immune; visible tag. | M | **Now.** High variety from existing mobs. |
| 4 | **Secret chests** | Secret chests, Rare Treasure | 15% per combat level, hidden, one random row, no gate; glint to find. | S | **Now.** Exploration without a new map. |
| 5 | **Blessings** | Flawless, Rush, Knives Out, Harvest | Level goals with no downside: no-hit, kill quota, melee-kill gold. Pay an extra chest or gold. | M | **Next.** Makes every fight a mini-challenge. |
| 6 | **Unlock the 19 verb rows** | Mods that upgrade dash/melee/ability verbs | Make the ready:false roll/guard/parry/throw rows live against the existing buttons. | M | **Now.** Cheapest build depth in the repo. |

### Tier 2 — the mastery spine

| # | Feature | Crab source | Blood Champions adaptation | Effort | Verdict |
| ---: | --- | --- | --- | --- | --- |
| 7 | **Difficulty + Challenge Level + medals** | Easy/Normal/Nightmare/Ultra Chaos; red/green modifiers; per-weapon medals | A Hearthstead “Blood Oath” board: 3–4 tiers, 6 red modifiers, optional green gifts; Oath points; per-weapon depth medals. | L | **The biggest long-term win.** Do after the cheap trio. |
| 8 | **Combo meter** | Combo 1–5, reset on damage; Damage Combo / Crystal Combo | Personal kill combo, max 5, direct hits reset it, DoT ticks do not; HUD; 2–3 rows. | M | **Next.** Skill expression and a reason to chain fights. |
| 9 | **Ally revive + gate vote** | Revival zones; majority portal vote | Hold G to revive a downed ally; party pips on the gate cards, host confirms. | M | **Next.** The co-op layer. |
| 10 | **Boss/Elite decay + armour** | Bosses take reduced damage that decays; extra bosses on loop; armour | Boss starts at 40–50% damage reduction, decays over 20–30 s; armour plates; phase at 50% health. | M/L | **Next.** Makes boss fights last long enough to matter. |

### Tier 3 — deep build and pacing

| # | Feature | Crab source | Blood Champions adaptation | Effort | Verdict |
| ---: | --- | --- | --- | --- | --- |
| 11 | **Mark ledger** | Fire/Ice/Lightning/Poison/Arcane | Bleed/Burn/Chill/Storm/Hex; the design is already in `upgrade-pool.md`; unlock the remaining mark rows. | L | **Later.** The deepest build layer, but the largest. |
| 12 | **Island objectives** | Horde, Demolition, Gauntlet, Parkour | Horde (survive), Hunt (marked elite), Gauntlet (3 waves, cash out), Demolition (destroy nests). | L | **Later.** Ties directly to the gate contracts. |
| 13 | **Movement layer** | Slide, air dash, flip | Slide and/or air dash with a small i-frame; perfect-parry feedback first. | L | **Later, with a playtest.** Feel risk is high. |
| 14 | **Daily seed / practice / account XP** | Daily seed, practice, XP | Optional; only after the core loop is deep. | M | **Later.** Community layer, not the hook. |

---

## 4. The first three, in detail

### 4.1 Totems

A totem would be a new prop: the run's paid risk is the stall's prices and the
boss's hoard today, and the per-body use, the health price and the
server-authoritative roll would all have to be built with it.

| Totem | Price | Effect | Why it belongs |
| --- | --- | --- | --- |
| **Chance** | 10% current health | One roll: 50% a random ready row, 50% nothing. | A cheap gamble that can salvage a bad build. |
| **Gold** | 33% max health | One epic or legendary row (never greed). | The “pay a third of your pool for a spike” bargain. |
| **XL** | none | The next level gets +50% enemy budget and one extra chest. | The Crab XL fantasy: harder next fight, richer clear. |

Rules:

- One totem type per clear, maximum; each body may use it once.
- The price can never kill; floor at 1 health.
- The host rolls the row/effect and broadcasts it; guests see the same offer.
- The XL totem writes a `next_level` modifier, so it is visible on the gate
  card and cannot be stacked with a trial that already doubles the budget.
- Health/Random/Crystal totems can follow if the first three land; do not ship
  all six at once.

Source: [Totems](https://crabchampions.wiki.gg/wiki/Totems).

### 4.2 Shop reroll and Upgrade Totem

**Reroll.** A button in the full shop (and the market, at a smaller stock):

- Cost: base 20 + 5 × level, +50% per reroll this visit.
- Rerolls replace unsold wares only; sold wares stay sold.
- The roll is host-side; guests receive the new wares.
- Optional risk: a 10% chance the reroll totem cracks and the shop cannot
  reroll again this visit. Start without the risk; add it if reroll becomes
  automatic.

**Upgrade Totem.** One per full shop, beside the stall:

- Lists the body's owned rows that are not at max stacks.
- The player pays `35 + 10 × level + tier surcharge` and gains one stack.
- One purchase per body per shop; the totem is spent when every body has had
  its choice.
- This is Crab's targeted upgrade fantasy without adding a new row pool.

Sources: [Shop](https://crabchampions.wiki.gg/wiki/Shop),
[Totems](https://crabchampions.wiki.gg/wiki/Totems),
[The Island Update](https://crabchampions.wiki.gg/wiki/The_Island_Update).

### 4.3 Enemy affixes

Crab's Buffed Enemies modifier gives a chance for a body to spawn Healthy,
Speedy, Angered, Frenzied or Shielded. Our mobs already take `health`, `rate`
and `damage` multipliers; an affix is one more layer at spawn.

| Affix | Effect | Adaptation |
| --- | --- | --- |
| **Healthy** | +100% pool | Multiply `life` for that body. |
| **Speedy** | +30% move | Multiply move speed; no attack-rate change. |
| **Angered** | +30% damage | Multiply `damage_scale`. |
| **Frenzied** | +25% attack rate | Multiply `rate`; no move change. |
| **Shielded** | 2 armour plates | Two hits of flat reduction or a breakable shield; show a plate tag. |

Rules:

- Roll one affix at 10–15% from island 2; never on an elite or boss.
- Cap one affix per body; no two defensive affixes.
- Show the affix in the body's name/health bar; guests receive it in the `mob`
  event.
- This can be a run modifier (“Buffed Enemies”) and a random late-block
  surprise; start with the modifier so it is opt-in.

Source: [Difficulty](https://crabchampions.wiki.gg/wiki/Difficulty).

### 4.4 Blessings

Blessings are optional goals with no downside; Crab uses them on Horde and
Demolition islands. Our levels are kill-waves, so the first three are easy to
read:

| Blessing | Goal | Pay | Why |
| --- | --- | --- | --- |
| **Flawless** | No connected player takes a hit this level. | +1 chest offer / extra gold. | Rewards clean play without a new enemy. |
| **Rush** | Party reaches a kill quota before the wave ends. | +25% gold and one extra offer. | Turns a slow wave into a race. |
| **Knives Out** | Melee kills pay 2× gold this level. | Gold. | Makes the melee hand a route choice. |

Rules:

- A blessing is shown on the level's HUD and on its gate card.
- AI squadmates do not fail Flawless; only connected players count.
- A blessing is independent of the trial; a trial changes the risk, a blessing
  changes the goal.
- Harvest (capture zones) can follow when the stage has zone props.

Sources: [Island Modifiers](https://crabchampions.wiki.gg/wiki/Island_Modifiers),
[The Island Update](https://crabchampions.wiki.gg/wiki/The_Island_Update).

### 4.5 The 19 verb rows

`mod_catalog.gd` already carries 19 rows for the buttons the game has:
throw, roll, guard and parry. They are `ready: false` because the runtime does
not read their keys yet. Making them live is cheaper than any new content:

- Throw: charges, damage, radius, sticky/ burst/ triple.
- Roll: charges, regen, repel, refunds, blades.
- Guard: cost, stagger, counter.
- Parry: window, refund, heal.

This makes the existing kit deeper, gives the market/shop more reason to exist,
and does not need a new model or animation. It also unlocks the mark rows'
sibling mechanics without committing to the full element ledger.

Source: `scripts/roguelite/mod_catalog.gd`, `docs/upgrade-pool.md`.

---

## 5. The mastery layer: difficulty, Oath points, medals

This is the biggest Crab-shaped addition after the cheap trio. The source's
loop is not “unlock more permanent power”; it is “play the same run at a higher
Challenge Level and earn a better medal.” Our keys already avoid the random
Key Totem gacha; medals are the right complement.

### 5.1 The Blood Oath board

At the Start Run Portal, a board offers:

| Tier | Enemy pool | Enemy damage | Starting health | Oath points |
| --- | --- | --- | --- | ---: |
| **Skirmish** | ×0.85 | ×0.85 | ×1.10 | 0 |
| **Blood Oath** | ×1.00 | ×1.00 | ×1.00 | 3 |
| **Red Wake** | ×1.25 | ×1.15 | ×0.90 | 6 |
| **Crimson** (secret) | ×1.45 | ×1.30 | ×0.85 | 9 |

Optional **red modifiers** add points:

- **Buffed Enemies** — affixes on spawn.
- **Expensive Shops** — +50% prices.
- **No Revive** — chest does not raise the downed.
- **Random Gates** — the gate contracts are drawn without the safe/focus
  guarantees.
- **Countdown** — the wave has a timer; timeout ends the run or costs a chest.
- **Limited Heals** — healing −33%.
- **Wandering Elites** — one extra elite per block.

Optional **green modifiers** subtract points or disable medals:

- **Starting Gift** — one random common row.
- **Deep Pockets** — +50 starting gold.
- **Lucky Start** — one extra chest offer on level 1.

### 5.2 Medals

Track the deepest level reached with each ranged/melee piece and each equipped
ability. Award a medal at depth thresholds plus Oath points:

| Medal | Depth | Oath points |
| --- | ---: | ---: |
| Bronze | 10 | any |
| Silver | 20 | 3+ |
| Gold | 30 | 6+ |
| Diamond | 50 | 9+ |
| Prismatic | 70 | 12+ |

The medal is a record in the armory, not a stat. A player can chase a Diamond
with a twig bow because the weapon is the run's identity, not a power unlock.
This is the Crab mastery layer without the random Key Totem.

Sources: [Difficulty](https://crabchampions.wiki.gg/wiki/Difficulty),
[review](https://game.lb-product.com/en/games/crab-champions/guides/crab-champions_review).

---

## 6. The feel layer: combo, co-op, bosses, movement

### 6.1 Combo

- Personal combo, max 5 (a relic can raise it).
- Kills increment; direct damage resets; DoT/hazard ticks do not.
- HUD ring/number; audio cue on tier up.
- Rows: **Damage Combo** (+damage per tier), **Crystal Combo** (+gold per
  tier), **Healthy Combo** (heal on tier up). This is a small pool addition.
- Combo is per body, not party-wide; an AI squadmate's kills do not feed yours.

Source: [Game Mechanics](https://crabchampions.wiki.gg/wiki/Game_Mechanics),
[The Difficulty Update](https://crabchampions.wiki.gg/wiki/The_Difficulty_Update).

### 6.2 Co-op revive and gate vote

**Revive.** Hold `G` beside a downed ally for 2.5 s:

- Moving, guard-breaking or taking a direct hit interrupts.
- The revived body stands at 25–50% of its pool; one revive per body per level.
- The existing `revive_from_downed` is the primitive; the channel and the
  network event are new.
- The chest still revives the whole party on a clear; the ally revive is for
  mid-wave saves.

**Gate vote.** The host still takes the gate, but each body can mark one of the
three cards; a majority mark shows a crown on the card and a 5 s countdown. If
the party splits, the host breaks the tie. This is Crab's portal vote with our
host-authoritative rule.

Sources: [The Island Update](https://crabchampions.wiki.gg/wiki/The_Island_Update),
[The Variety Update Part 2](https://crabchampions.wiki.gg/wiki/The_Variety_Update_Part_2).

### 6.3 Boss and elite rules

Bosses currently die to a burst build before their patterns read. Crab gives
bosses a decaying damage reduction and extra bodies on loops. Our version:

- Start at **40–50% damage reduction**, decay to 0 over 20–30 s.
- Give the boss **2–4 armour plates**; breaking them changes the phase.
- At 50% health, add one of: an extra escort, a hazard ring, or a faster
  attack pattern.
- Elites keep their current kit but gain one affix at deep blocks.
- No boss can be one-shot by a single crit; the first hit is capped or reduced.

Source: [The Variety Update Part 1](https://crabchampions.wiki.gg/wiki/The_Variety_Update_Part_1),
[Bosses](https://crabchampions.wiki.gg/wiki/Bosses),
[Elites](https://crabchampions.wiki.gg/wiki/Elites).

### 6.4 Movement

Crab's movement is its identity; ours is guard/parry/roll. Do not add a gun
system to chase it. The smallest honest movement additions:

- **Perfect parry feedback:** a flash, a sound, a stamina/ability refund, and a
  short damage window. The parry already exists in `combat.gd`; make it read.
- **Slide:** sprint + crouch, a lower profile and a short i-frame, with a
  stamina cost. Test in `playtest/sidestep_lab.gd` first.
- **Air dash:** only if the slide test says the ground game needs it; adding
  both at once is how a movement clone becomes a janky movement clone.

Source: [Game Mechanics](https://crabchampions.wiki.gg/wiki/Game_Mechanics),
[review](https://game.lb-product.com/en/games/crab-champions/guides/crab-champions_review).

---

## 7. What not to copy

| Source thing | Why not |
| --- | --- |
| Guns, third-person crab movement | Our bow/blade/guard identity is the point; borrow the *feel*, not the firearm or the crab. |
| Random Key Totem unlocks | Our armory is a deterministic catalog. Random unlocks would fight the rack and the co-op fairness. |
| Finite four-biome run | Our run is endless; the 10-level block is the loop. |
| Crystals plus gold | We have one purse. Do not add a second currency for one feature. |
| PvP / parkour / minigames | The source cut or deprioritised modes that did not serve the core loop; do not add a mode just to match a feature list. |
| Content volume over decisions | More enemies do not fix a thin loop. The gate/chest decision is the multiplier. |
| Grind as mastery | The source's long loops can become repetitive; medals should reward depth and variety, not 50 identical clears. |

---

## 8. Recommended sequence

**If we do three things next:**

1. **Totems** (Chance, Gold, XL) — one prop, three decisions.
2. **Shop reroll + Upgrade Totem** — makes gold a build choice.
3. **Enemy affixes** — makes the existing mobs read differently.

**Then the mastery layer:** difficulty, Oath points, medals. This is the single
largest long-term replay addition and it does not need a new row pool.

**Then the build layer:** the 19 verb rows, then combo, then the mark ledger.
The verb rows are already written; combo needs a meter and 2–3 rows; marks is
the big one.

**Then the variety layer:** blessings (with the gate contracts), co-op revive
and vote, boss decay rules, secret chests.

**Last:** new objectives (Horde/Gauntlet/Hunt), movement slide/air-dash, daily
seed/practice. These are the most expensive and the most likely to be a
different game rather than a deeper one.

If the goal is “more like Crab in the first hour,” the cheap trio is the answer.
If the goal is “more like Crab after fifty hours,” the difficulty/medal layer is
the answer. They are not the same feature.

---

## 9. How to know it worked

| Metric | What it tells us |
| --- | --- |
| Pool diversity | Are all six contract pools picked? Is one family above 35%? |
| Build identity | Does a run use 3+ families by level 10? Does a duplicate row reach level 3? |
| Totem use | How often is a totem taken? Do players die to the price or the fight? |
| Shop agency | Rerolls per run; gold left at the boss; Upgrade Totem purchases. |
| Affix fairness | Do affixed mobs produce “that was hard” or “that was cheap”? |
| Difficulty/medals | Do players move up a tier after a win? Is Diamond rare but reachable? |
| Combo | Combo uptime and reset frustration; are combo rows taken without a damage build? |
| Co-op | Revives per run; gate-vote participation; time spent waiting at a chest. |

---

## Sources

**Official wiki**
- [Game Mechanics](https://crabchampions.wiki.gg/wiki/Game_Mechanics)
- [Chests](https://crabchampions.wiki.gg/wiki/Chests)
- [Rarities](https://crabchampions.wiki.gg/wiki/Rarities)
- [Islands](https://crabchampions.wiki.gg/wiki/Islands)
- [Island Modifiers](https://crabchampions.wiki.gg/wiki/Island_Modifiers)
- [Totems](https://crabchampions.wiki.gg/wiki/Totems)
- [Shop](https://crabchampions.wiki.gg/wiki/Shop)
- [Anvils](https://crabchampions.wiki.gg/wiki/Anvils)
- [Enhancements](https://crabchampions.wiki.gg/wiki/Enhancements)
- [Difficulty](https://crabchampions.wiki.gg/wiki/Difficulty)
- [Bosses](https://crabchampions.wiki.gg/wiki/Bosses)
- [Elites](https://crabchampions.wiki.gg/wiki/Elites)
- [Enemies](https://crabchampions.wiki.gg/wiki/Enemies)
- [Abilities and Melee](https://crabchampions.wiki.gg/wiki/Abilities_and_Melee)
- [Weapons](https://crabchampions.wiki.gg/wiki/Weapons)
- [The Difficulty Update](https://crabchampions.wiki.gg/wiki/The_Difficulty_Update)
- [The Variety Update Part 1](https://crabchampions.wiki.gg/wiki/The_Variety_Update_Part_1)
- [The Variety Update Part 2](https://crabchampions.wiki.gg/wiki/The_Variety_Update_Part_2)
- [The Elemental Update](https://crabchampions.wiki.gg/wiki/The_Elemental_Update)
- [The Anvil Update](https://crabchampions.wiki.gg/wiki/The_Anvil_Update)
- [The Island Update](https://crabchampions.wiki.gg/wiki/The_Island_Update)

**Steam / community**
- [Crab Champions store page](https://store.steampowered.com/app/774801/Crab_Champions/)
- [The Island Update patch notes](https://store.steampowered.com/news/app/774801/view/637948480724140705)
- [Review — movement-first roguelite](https://game.lb-product.com/en/games/crab-champions/guides/crab-champions_review)

**Blood Champions**
- [README](../README.md)
- [run.md](run.md)
- [run-loop-design.md](run-loop-design.md)
- [upgrade-pool.md](upgrade-pool.md)
- `scripts/roguelite/mod_catalog.gd`, `run_director.gd`, `run_player.gd`,
  `proc_engine.gd`

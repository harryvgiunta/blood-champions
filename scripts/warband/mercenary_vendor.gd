class_name WarbandVendor
extends RefCounted
## The town desk's price rule: what an oath at Hearthstead costs.
##
## *Who* the desk sells is not this file's business. It sells exactly what a run's
## recruiter sells - a body already inside its kit, with the one skill it will
## fire - rolled by `RecruitCatalog` at `TOWN_LEVEL` (rung 0: a twig bow, makeshift
## steel, bark and rags) and laid out by `Warband.town_board()`. The body is sworn
## whole and stays whole: its kit is locked (`Warband.is_gear_locked`), so no
## gear press, no pickup, no re-kit and no shop ever changes what the desk
## sold.
##
## What this file owns is the band's own arithmetic. Gold is the `PlayerState`
## purse, read through `Warband`, and the desk charges the purse for a body only
## once the warband is past the free oaths: the desk is garrisoning a warband, not
## selling one.

const HIRE_BASE_COST := 120
## Each mercenary already on the books makes the next one dearer, so a wipe
## costs more than a top-up and the early loop stays affordable.
const HIRE_STEP_COST := 35
## The town's first oaths are free: the recruiter is garrisoning a warband, not
## selling one, and the deployment cap is the whole roster now. Every oath that
## can be sworn is therefore free - the cap refuses a body past its third, not
## the purse - and the price curve below only bites if the cap ever grows.
const FREE_HIRES := 3

## The price of the next body, given how many are already standing. Zero while
## the desk is still filling the first free places.
static func hire_cost(roster) -> int:
	var count: int = roster.count() if roster != null else 0
	if count < FREE_HIRES:
		return 0
	return HIRE_BASE_COST + HIRE_STEP_COST * count

extends RefCounted
## How long a defeated mob stays where it fell.
##
## Every mob kind shares one lifetime so a fight leaves a battlefield instead of
## a row of four-second ghosts; the corpse keeps its settled ragdoll pose (or
## its authored collapse for procedural bodies) and its final blood pools for
## the whole five minutes, then dissolves. The dissolve shrinks a presentation
## container, never the CharacterBody root, so any late ray or loot query on
## the root keeps its identity transform.

## Five minutes by default. Callers may pass a shorter delay for a scripted
## encounter, but the shared default is what the frontier, delve and arena
## corpses use.
const SECONDS := 300.0
const DISSOLVE_SECONDS := 0.6
## The label a director hangs over a ranked body (`ELITE`, `BOSS`). The rank is
## a fact about the fight, not the ground the body falls on, so it leaves on the
## death and is never part of what the hold keeps.
const RANK_TAG := "RankTag"

## Starts a tween on `host` that holds, dissolves `shrink` and frees the body.
static func hold(host: Node, shrink: Node3D, delay: float = SECONDS) -> Tween:
	var tween := host.create_tween()
	append(tween, host, shrink, delay)
	return tween

## Adds the hold/dissolve/free steps to an existing tween, after whatever
## collapse animation the caller already queued.
static func append(tween: Tween, host: Node, shrink: Node3D,
		delay: float = SECONDS) -> void:
	drop_rank_tag(host)
	if delay > 0.0:
		tween.tween_interval(delay)
	if is_instance_valid(shrink):
		tween.tween_property(shrink, "scale", Vector3.ONE * 0.01, DISSOLVE_SECONDS)
	tween.tween_callback(host.queue_free)


## Frees the host's `RANK_TAG` child, if it carries one. Every death that leaves
## a corpse runs through `hold` or `append` - the authority's because it killed
## the body, a replica's because the snapshot said so - so the tag never outlives
## the rank it advertised by more than the frame the body died on.
static func drop_rank_tag(host: Node) -> void:
	if host == null or not is_instance_valid(host):
		return
	var tag := host.get_node_or_null(NodePath(RANK_TAG))
	if tag != null:
		tag.queue_free()

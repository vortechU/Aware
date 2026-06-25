# Navigable Verticality — Plan

**Status:** V1 (player-traversable platforms) + V2 (the "Tiers" archetype, wired into
The Stack) + V3 (player-only rewards on the caps) — DONE.
**Approach (pivoted after the V1 navmesh finding):** *Player-traversable* verticality.
Platforms + ramps are solid collision geometry the **player** climbs via the
movement kit (wall-run / vault / dash / jump); **enemies stay grounded** (the
navmesh simply routes around the platform bases). Build-alongside: additive helpers
on `room_builder.gd`; endless mode + the existing archetypes untouched.

## V1 finding — why the pivot
The original goal was enemy-navigable platforms (ramps baking into a connected
navmesh). The de-risk test proved that **does not work out of the box**: crate tops
(y≈1.75) and wall tops (y≈5.5) bake walkable, but a built platform top *never* baked
— at 1.5 m or 2.5 m, slab or solid mesa, with or without a ramp. It's a
`NavigationMesh` bake subtlety that needs hands-on, editor-visualized debugging
(agent-radius erosion / region filtering / cell params). Rather than rabbit-hole,
we pivot: the **player doesn't use the navmesh** (it moves by physics), so verticality
ships now as player-only high ground. Enemy-navigable high ground is a separate,
later navmesh investigation.

## Pass ladder
- **V1 — builders + player-traversable proof (DONE).** `_build_platform()` (a solid
  mesa) + `_build_ramp()` on RoomBuilder. The test asserts: the pieces are solid,
  grouped world geometry; the **player physically rests on the platform top** (no
  fall-through); the ramp slope is within the player's climbable range; and the room
  **stays enemy-navigable on the ground** (the platforms don't make any enemy spawn
  unreachable). → `VERTICALITY_OK`.
- **V2 — "Tiers" archetype (DONE).** An opt-in `tiers` layout (flagged `vertical`,
  so `_pick_archetype` never returns it in the endless rotation — only when a
  profile's `archetype_pool` lists it). `_build_tiers()` raises 2–3 perimeter-biased
  platforms with inward-facing ramps + a piece of high cover on each cap, all
  respecting bounds / keep-clear / L-notch; it runs FIRST in the build loop so its
  registered footprints keep the ground scatter (`_gen_tiers`) off the mesa bases
  (via a new `_footprints` check in `_try_place`, a no-op for the other archetypes).
  The existing reachability/poly-count validation guarantees the ground stays fully
  enemy-navigable. → `TIERS_OK`. **Wired into The Stack** (layer 2): its
  `archetype_pool` now lists `tiers`, so CAMPAIGN runs meet vertical rooms in the
  Stack (global rooms 7–12). Thematically apt — the Stack is literally a stack.
  `descent_test` exercises a real Stack room against the live pool; `tiers_test`
  asserts the wiring (Stack opts in, Heap does not).
- **V2.5 (done as part of V2) — wired into The Stack.** `tiers` is opted into the
  Stack's `archetype_pool`, so it's no longer dormant. Other layers can opt in the
  same one-line way.
- **V3 — player-only rewards up high (DONE).** The builder records one elevated
  reward spot per platform cap (`get_high_reward_points()`); `RunDirector._spawn_
  high_rewards()` drops a bonus premium pickup (health/armor, one per cap) on each.
  They're EXTRA pickups beyond the room's snapshot set (normal balance untouched) and
  sit above the navmesh where grounded enemies can't reach — so the climb is a real
  player-only payoff. The sightline advantage is inherent (you're up high). → `TIERS_
  REWARD_OK`. Possible later extension: Memory Fragments on caps in CAMPAIGN (left out
  for now — it would entangle the FragmentDB arc ordering).
- **V4 — tuning + (optional, separate) the enemy-navmesh deep-dive** to eventually
  let enemies take high ground; possibly lean a layer vertical.

## Files
- `scripts/run/room_builder.gd` — platform/ramp builders (V1); Tiers archetype (V2);
  elevated placement (V3).
- `tools/verticality_test.tscn` / `.gd` — `VERTICALITY_OK`.

## Notes
- Platforms are SOLID mesas (ground → top): Recast reliably bakes the ground *around*
  them, and the player stands on the *collision* top regardless of navmesh.
- Pieces are `StaticBody3D` under `GeneratedRoom` (cleared per build), like obstacles.
- Endless + the current layers are unaffected until V2 opts verticality in.

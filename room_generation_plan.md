# Procedural Room Generation — Plan

**Status:** IMPLEMENTED — all headless checks pass (`RUN_SMOKE_OK`).
**Decision:** Procedural *interior* generation. The 44×44 outer wall shell and
floor stay fixed; only the interior layout, cover, enemy spawns and pickups
vary per room. Build-alongside: no original gameplay script is rewritten.

> **Follow-up — footprint (size/shape) variation, all 3 passes DONE.**
> The "shell stays fixed" decision below is now superseded for rooms 2+:
> RoomBuilder also builds the shell. Each room 2+ picks a seeded footprint and
> builds its own shell (`GeneratedShell` under NavRegion, StaticBody3D so the
> navmesh bakes cleanly); the authored shell is retired with the authored
> interior on the first procedural build; the `PlayerSpawn` marker moves to the
> new south edge and RunDirector teleports the player onto it after `build_room`;
> `_inner_limit` (per-axis `Vector2`), min-enemy-distance and the structured
> archetype extents all derive per-axis from the chosen footprint.
> - **Pass 1 — variable square size.** `FOOTPRINTS` squares 17/21/24
>   (reproduces the authored look at 21).
> - **Pass 2 — rectangular footprints.** `FOOTPRINTS` wide/deep rects e.g.
>   27×16, 16×27; `arena_cross` corners scale per-axis, diagonal length/exclusion
>   off the short axis. Milestone rooms stay a 24×24 square.
> - **Pass 3 — L-shaped (notched) footprints.** `L_FOOTPRINTS` cut a rectangular
>   notch from a north corner (south spawn + north-centre gate stay on floor).
>   The shell builds the floor from two boxes (notch corner left bare → no
>   navmesh there) + two concave walls closing the L. Placement is geometrically
>   rejected from the notch (`_in_notch`) so nothing lands in the bare corner
>   regardless of nav-sync timing; `_rebake` `map_force_update`s the nav map so
>   validation reads the fresh room (the old mesh otherwise covers the notch for
>   a few physics frames).
>
> Verified by the run smoke test (valid-footprint / spawn-edge / in-bounds /
> out-of-notch + picker variety incl. a rectangle AND an L + determinism),
> `tools/l_room_test.tscn` (L navmesh has a real hole at the notch, playable area
> reachable, no spawn/pickup in the notch) and `tools/room_size_preview.tscn`
> (square / wide / deep / L captures).

**Resolved decisions (implementation):** room 1 stays authored; all six
archetypes shipped; elite/milestone rooms SHIPPED in a follow-up pass (every
5th room: "PROVING GROUNDS" arena, 1 elite at 5x hp / 2x dmg + half-squad of
guards, elite drops 2 health packs, double upgrade pick on clear — see
tools/elite_smoke_test.gd); mood tint + banner flavor included; the §5 pause question resolved by making the fallback primary — the
tree unpauses behind a "GENERATING..." beat while the player is externally
frozen, because the navigation map sync needs live physics frames. The
authored interior (pillars/crates/platform/ramp) is retired at runtime on the
first procedural build; the procedural rebakes parse only collision shapes,
which removed the runtime mesh-parsing warning for rooms 2+.

---

## 1. What stays fixed vs. what varies

**Fixed (never touched):**
- `NavRegion/Arena` Floor + WallN/S/E/W (the 44×44 shell).
- `PlayerSpawn` at (0, 0.1, 18), south edge.
- NavigationMesh agent settings, WorldEnvironment, Sun (mood tint is optional, see §7).

**Varies per room (regenerated):**
- Interior obstacles (pillars / crates / cover walls / platforms).
- `cover_point` group markers — placed adjacent to new obstacles.
- `enemy_spawn` group markers — valid walkable spots far from the player.
- Pickup positions — on the new walkable floor.

**Room 1 stays authored.** GameManager bakes the navmesh and spawns the first
squad on the authored arena at startup; fighting that startup sequence isn't
worth it. Room 1 is the consistent "home" room; **rooms 2+ are procedural.**
(Open question: if you'd rather room 1 also be procedural, we generate it right
after GameManager's bake instead — flagged in §11.)

---

## 2. Architecture (new node, build-alongside)

- **NEW `scripts/run/room_builder.gd`** — node `RoomBuilder`, sibling in
  main.tscn (one-line scene add). Owns all generated content under a single
  runtime container `GeneratedRoom` (with child containers `Geometry`,
  `CoverPoints`, `EnemySpawns`). Holds references to `NavRegion`, `Arena`,
  `PlayerSpawn`. Public API:
  - `build_room(room: int) -> void` (async; generates + rebakes navmesh)
  - `get_enemy_spawn_points() -> Array[Vector3]`
  - `get_pickup_points() -> Array[Dictionary]`
- **EDIT `scripts/run/run_director.gd`** (my own file from the run-system task —
  not an original script): call `RoomBuilder.build_room()` during the transition
  and source pickup/spawn positions from it for rooms 2+.
- **EDIT `scripts/run/run_manager.gd`** (also mine): add a per-run RNG seed and
  optional archetype tracking (see §6/§7).

**Why generated markers go into groups:** `enemy_ai.gd` finds cover via the
`cover_point` group and RunDirector finds spawns via the `enemy_spawn` group.
If RoomBuilder adds its generated markers to those groups, **neither enemy_ai
nor RunDirector needs to change its query logic** — the existing group lookups
just see the new markers. The authored room-1 markers are removed from the
groups (or ignored) once procedural generation takes over.

---

## 3. Geometry: use StaticBody3D, not CSG

The authored arena uses `CSGBox3D` with `use_collision = true`. At runtime this
triggers the warning we already see during bake:
`"Source geometry parsing ... had to parse RenderingServer meshes at runtime"`
(slow GPU→CPU readback).

The arena navmesh is set to `geometry_parsed_geometry_type = 1` (**static
colliders**). So generated obstacles should be **`StaticBody3D` +
`CollisionShape3D(BoxShape3D)` + `MeshInstance3D(BoxMesh)`** using the existing
`crate`/`struct` materials. This bakes cleanly from collision shapes, avoids the
mesh-parsing warning, and is cheaper than CSG. **Net improvement over the
authored approach.**

---

## 4. Generation algorithm

Per `build_room(room)`:

1. **Clear** previous content: `queue_free` the `GeneratedRoom/Geometry`,
   `CoverPoints`, `EnemySpawns` children; markers leave their groups on free.
   Authored geometry is never touched (separate container).
2. **Pick an archetype** (§6) and a seeded RNG (§6).
3. **Place obstacles** by rejection sampling within inner bounds (±19, leaving a
   margin off the walls):
   - Maintain placed-footprint circles/AABBs; reject candidates that overlap or
     sit within a min-spacing gap (player must be able to weave between them).
   - Enforce a **keep-clear radius** (~4 m) around `PlayerSpawn` so the player
     never materializes boxed in.
   - Obstacle count scales mildly with room number, capped (density ceiling).
4. **Generate cover markers**: for each obstacle, add 1–2 `cover_point` markers
   on the faces pointing away from arena center / main approach. `enemy_ai`
   already validates cover by line-of-sight and player distance, so we only
   supply plausible candidates.
5. **Generate enemy spawns**: choose points far from `PlayerSpawn`
   (min distance), not inside obstacles; add `enemy_spawn` markers. Generate at
   least `enemy_count_for_room(room)` of them.
6. **Rebake navmesh** (§5).
7. **Validate navigability** (§5): drop/relocate unreachable spawns; if the
   layout is degenerate, retry generation up to K times.
8. **Compute pickup points**: walkable spots — health/armor in exposed spots,
   ammo near cover (§8).

---

## 5. Navmesh rebake + the pause problem

GameManager's startup pattern: wait 2 physics frames (CSG collision needs them),
`nav_region.bake_navigation_mesh()`, `await nav_region.bake_finished`.

**Risk:** the room transition currently sets `get_tree().paused = true`, and a
paused tree does not step physics — so "wait physics frames" won't progress and
freshly added collision may not be registered for the baker.

**Mitigations (decide during impl, verify headless):**
- Generated geometry uses explicit `StaticBody3D` collision shapes, which exist
  in the physics space immediately (no CSG deferred build) — baking may succeed
  under pause with no physics-frame wait.
- **Fallback if pause blocks it:** keep the player frozen via an overlay +
  `player.set_physics_process(false)` and briefly **unpause only for the bake**
  (a "GENERATING…" beat), then re-freeze and bring the player in. RoomBuilder is
  `PROCESS_MODE_ALWAYS` so it drives this regardless.
- Validate reachability with `NavigationServer3D.map_get_path` /
  `map_get_closest_point` and assert `navigation_mesh.get_polygon_count()` > a
  threshold after the bake.

This is the single trickiest part; the headless test (§10) will tell us which
path works before we commit.

---

## 6. Worth adding — variety & structure

1. **Layout archetypes** — instead of pure scatter, a set of named generators,
   each with its own placement rules:
   - *Open Field* (sparse, long sightlines), *Pillar Hall* (grid of pillars),
     *Bunker* (central walled strongpoint), *Maze Lanes* (parallel cover walls),
     *Scattered Cover* (random crates), *Arena Cross* (diagonal cover walls).
   - Weighted by room number for pacing (early rooms opener, later rooms denser).
   - Recognizable variety beats noise; also gives the AI usable cover topology.
2. **Seeded generation** — RNG seed = `hash(run_seed, room_index)` stored in
   RunManager. Makes runs reproducible (debugging, future daily-run / shareable
   seeds). Logged so a bad layout can be reproduced.

## 7. Worth adding — feel & pacing

3. **Elite / milestone rooms** — every Nth room uses a distinct archetype (e.g.
   an open boss arena with one tanky elite), hooking into existing enemy scaling.
4. **Lighting/mood tint per archetype** — nudge the existing WorldEnvironment /
   Sun color per room for visual freshness. Cheap, high impact, build-alongside.
5. **Banner flavor** — `"ROOM 5 — Pillar Hall"` on the existing RunHUD banner.
6. **Spawn telegraphing** — brief spawn VFX/delay so procedurally placed enemies
   don't pop in on top of the player (matters more than with fixed spawns).

## 8. Worth adding — fairness & AI health

7. **Minimum cover guarantee** — require ≥ K *valid* (LoS-blocking) cover points
   per room, or the AI's COVER/FLANK behavior degrades to dull standing fights.
8. **Layout-driven pickup risk/reward** — health/armor in exposed positions,
   ammo near cover, so geometry shapes the risk decision.
9. **Walkable-area floor** — reject layouts that carve the arena below ~X%
   walkable (no accidental walled-off pockets).
10. **Keep-clear player zone** + **no fully-enclosed pickups** (anti-frustration).
11. **Density coupled to difficulty** — obstacle/cover counts scale with room,
    interacting with the existing `enemy_count_for_room` / stat scaling.

---

## 9. Files touched

| File | Change |
|------|--------|
| `scripts/run/room_builder.gd` | **NEW** — generator + rebake + validation |
| `scenes/main.tscn` | **+1 node** `RoomBuilder` (build-alongside) |
| `scripts/run/run_director.gd` | EDIT (mine) — call builder; source spawns/pickups from it for rooms 2+ |
| `scripts/run/run_manager.gd` | EDIT (mine) — run seed, archetype tracking, banner label |
| `scripts/ui/run_hud.gd` | EDIT (mine) — show archetype name on banner (optional, §5 flavor) |
| `tools/run_smoke_test.gd` / new `tools/room_gen_test.tscn` | EDIT/NEW — assertions (§10) |

**No original gameplay script** (player.gd, weapon_manager.gd, enemy_ai.gd,
game_manager.gd, hud.gd, pickup.gd, components) is modified.

---

## 10. Verification (headless, existing harness flow)

Order: `--import` → `script_check.tscn` → `smoke_test.tscn` → run/room test.

Room-gen assertions:
- Room 2 generated-geometry child count > 0 **and** layout differs from room 1.
- Navmesh `get_polygon_count()` > threshold after each rebake.
- Every generated enemy spawn is nav-reachable from `PlayerSpawn`.
- No obstacle within the keep-clear radius of `PlayerSpawn`.
- ≥ K cover points generated and at least some are LoS-valid.
- Walkable area ≥ X% (degenerate-layout guard).
- Re-running with the same seed reproduces the same layout.

---

## 11. Open questions before implementation

1. **Room 1 procedural too?** Default plan keeps it authored (consistent home
   room). Switch to procedural-from-room-1 if you prefer maximum variety.
2. **Archetype set** — is the §6 list good, or do you want specific layout
   styles?
3. **Elite/milestone rooms** (§7.3) — include now, or defer to a later pass?
4. **Mood tint / banner flavor** (§7.4–5) — include now, or keep visuals as-is?
5. **Pause-vs-unpause bake** (§5) — I'll pick based on the headless result;
   flagging that it may add a brief "GENERATING…" beat to the transition.

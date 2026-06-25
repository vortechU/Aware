# Aware — Shipped Systems (include only the sections relevant to the current feature)

## Roguelite run system (added)

Built so the player fights through **infinite scaling rooms**, picking an
upgrade after each, until death (permadeath; run state itself never persists —
the MetaProgression layer described below is the only thing that survives).

- **`RunManager`** (autoload, `autoloads/run_manager.gd`) — pure run *state*:
  `current_room`, `enemies_killed`, `run_active`, `current_run_modifiers`.
  Signals: `run_started`, `room_cleared`, `run_ended(won)`, plus
  `room_advanced(room)` / `modifiers_changed(modifiers)` for the HUD. Holds the
  8-upgrade pool and scaling math: **+1 enemy and +10% enemy health/damage per
  room**. `roll_upgrade_choices()` returns 3 distinct random upgrades.
- **`RunDirector`** (`scripts/run/run_director.gd`, node in main.tscn) —
  scene-side *orchestrator*. On ready it disconnects GameManager's
  `player_died`/`enemy_died` handlers at runtime and adopts the room-1 enemies
  GameManager spawned (GameManager still bakes the navmesh + does the first
  spawn). Per room-clear: pauses the tree, shows the "ROOM CLEARED" banner for
  1s, presents upgrade cards, applies the pick, then teleports the player to
  PlayerSpawn, restocks pickups from a startup snapshot, and spawns the next
  scaled room. Handles permadeath (freeze enemies, hide legacy respawn screen).
- **`PlayerUpgrades`** (`scripts/player/player_upgrades.gd`, `class_name
  PlayerUpgrades`, child of Player) — applies the 8 stacking upgrades by editing
  exported vars on Player/WeaponManager. **Duplicates the WeaponData .tres per
  run** so damage/fire-rate/ADS buffs don't leak through the resource cache into
  the next run.
- **`RunHUD`** (`scripts/ui/run_hud.gd` + `scenes/ui/run_hud.tscn`, separate
  CanvasLayer on layer 2) — room counter (top center), active-upgrade list
  (bottom left), ROOM CLEARED banner, upgrade card screen, and the "YOU DIED"
  panel with rooms/kills/upgrades stats + Try Again (reloads main.tscn) / Quit.
- **`RoomBuilder`** (`scripts/run/room_builder.gd`, node in main.tscn) —
  procedural interiors AND shell for rooms 2+. Room 1 is the authored arena; on
  the first procedural build the authored interior (pillars/crates/platform/ramp),
  cover markers AND the authored Floor + 4 walls shell are all retired at runtime.
  **Variable footprint:** each room picks a seeded footprint (inner half-extents
  x,z from `FOOTPRINTS` — squares 17/21/24 plus wide/deep rectangles like 27x16
  and 16x27; milestone rooms forced to a 24x24 square) and builds its own sized
  shell (floor + 4 walls as StaticBody3D, in a `GeneratedShell` container under
  NavRegion) so the arena is a different size AND aspect each room. `_inner_limit`
  (per-axis `Vector2`), player spawn (the live `PlayerSpawn` marker is moved to
  the new south edge; RunDirector teleports the player onto it *after*
  `build_room`), and min enemy distance all derive from the chosen footprint;
  structured archetypes scale their extents off `_inner_limit` per-axis so they
  fill any size/aspect (and reproduce the authored look at the default 21x21).
  Some rooms are **L-shaped**: an `L_FOOTPRINTS` entry cuts a rectangular notch
  from a north corner (away from the south spawn + north-centre gate). The shell
  then builds the floor from two boxes — the notch corner left bare, so the
  navmesh baker makes no floor/navmesh there — plus two extra walls closing the
  concave corner. Obstacles, cover, enemy spawns and pickups are geometrically
  rejected from the notch (`_in_notch`), so nothing lands in the bare corner
  regardless of navmesh sync timing; `_rebake` also `map_force_update`s the
  navigation map so validation reads the fresh room. Verified by
  `tools/l_room_test.tscn`.
  Six layout archetypes (Open Field, Scattered Cover, Pillar Hall — rooms 2-3;
  Bunker, Maze Lanes, Arena Cross unlock from room 4), each with a Sun mood
  tint and a banner title ("ROOM 5 - PILLAR HALL"). Obstacles are
  StaticBody3D + BoxShape3D (navmesh bakes from collision shapes — no runtime
  mesh parsing), low cover gets NavigationObstacle3D like the authored crates.
  Generated cover markers join the existing `cover_point` group so enemy_ai
  needs no changes; enemy spawns/pickup spots are validated for navmesh
  reachability (`NavigationServer3D.map_get_path`) with retry + authored-marker
  fallback. Layouts are seeded: `hash([RunManager.run_seed, room])`, so a run
  is reproducible from the seed printed at start. The rebake needs live physics
  frames, so transitions unpause behind a "GENERATING..." beat while the player
  is externally frozen (process toggles, no script edits). Pickup placement is
  risk/reward: ammo behind cover, health/armor exposed.
- **Elite / milestone rooms** — every 5th room (`RunManager.MILESTONE_INTERVAL`)
  uses the milestone-only "PROVING GROUNDS" arena (central pillar monument +
  ring cover, never in the random rotation) with **1 elite + half a squad of
  guards** instead of the regular squad. The elite is a normal enemy.tscn
  instance customized externally by RunDirector's `_outfit_elite`: 5x health /
  2x damage on top of room scaling, faster reactions, longer bursts, crimson/
  gold emissive look, broader XZ-only silhouette (head stays aligned with the
  head hitbox) and a duplicated, widened body-hitbox capsule (shape resources
  are shared — always duplicate before resizing). Elites carry
  `set_meta("elite")`; on death they always drop 2 health packs. Clearing a
  milestone room grants TWO upgrade picks (titled "1 OF 2" / "2 OF 2").

### Enemy archetypes (added — being built one kind per pass)
Variety in the regular squad via the same external **outfit-hook** pattern as the
elite (a stock `enemy.tscn` customized by RunDirector before `add_child`, **no
`enemy_ai.gd` edit** — the distinct behavior is emergent from tuning the existing
state machine). Composition is a deterministic curve on `RunManager` so spawns are
reproducible and testable.

- **Rusher** (shipped) — `RunDirector._outfit_rusher`: a fast, fragile glass
  cannon that charges in and sprays at point-blank. Tuning: high `combat_speed`
  (1.6x) + short `attack_range` (6) + halved `reaction_time` so it CHASEs hard and
  only settles to fire up close; a huge `mag_size` (never stops to reload, so it
  never takes the reload→cover path) + `cover_health_threshold = 0` (a hurt rusher
  never flees/flanks) keep it relentless; a fast wide burst (`burst_count` 4,
  `burst_shot_interval` 0.05, `aim_spread_deg` 9) with lower per-pellet damage
  reads like a shotgun. 0.7x health so it's a kill-it-fast threat. Leaner orange
  silhouette (Visual XZ 0.85, hazard-orange body + yellow head set before
  `add_child` so ToonApplicator carries the colour into the toon material, like the
  elite) with a matching narrowed body hitbox (duplicate the shared shape before
  resizing). Composition: `RunManager.rusher_count_for_room` — none before room 3
  or in milestone rooms, ramps +1 every 3 rooms, capped to ~1/3 of the squad.
  Covered by `tools/rusher_smoke_test.tscn` + `tools/rusher_preview.tscn`.
- **Sniper** (shipped) — `RunDirector._outfit_sniper` + a small, off-by-default
  `is_sniper` hook in enemy_ai.gd (a charged shot can't be expressed by tuning
  alone, so this archetype needed a core edit — kept fully gated so regular /
  rusher / elite enemies run the unchanged path). A long-range marksman: far sight
  (60) + attack range (40), deliberate movement (0.9x), near-perfect aim, one heavy
  shot (3x damage), 0.85x health. When `is_sniper`, `_state_attack` runs
  `_sniper_attack` instead — a cycle of **relocate to a perch → charge a
  telegraphed beam (locks a world aim POINT, not a direction, so a moving muzzle
  stays accurate and the player dodges by leaving the lane) → fire one accurate
  hitscan (+ a `bullet_tracer`) → cooldown → relocate**. The beam is a thin
  unshaded box (`top_level`, raycast-clipped at walls) that brightens/thickens as
  the charge nears firing. Cold-cyan, slightly taller/leaner silhouette + matching
  hitbox. Composition: `RunManager.sniper_count_for_room` — none before room 4 or
  in milestone rooms, +1 every 6 rooms, hard-capped at 2; snipers take the front
  spawn slots, rushers the back, clamped so they never overlap. Covered by
  `tools/sniper_smoke_test.tscn` + `tools/sniper_preview.tscn`.
- **Grenadier** (shipped) — `RunDirector._outfit_grenadier` + an off-by-default
  `is_grenadier` hook in enemy_ai.gd + a new sibling **`scripts/enemies/grenade.gd`**
  (`class_name Grenade`). A mid-range area-denial unit: it keeps its distance
  (attack_range 20, backs off if the player closes) and, after a brief telegraphed
  wind-up, lobs an arcing grenade at the player's position to flush them out of
  cover, never using its gun. When `is_grenadier`, `_state_attack` runs
  `_grenadier_attack` (wind-up → throw → cooldown → reposition). The grenade is a
  self-contained Node3D: a hand-integrated ballistic arc (its own gravity, so it
  lands where aimed regardless of physics settings), a ground **danger ring** at
  the target so the player is warned to move, explodes on the first world surface
  or a fuse, and deals a **falloff AoE** to the player only on a clear line (a wall
  fully shields; the grenade lands at your feet otherwise). Heavy blast (3x base
  shot damage), 1.15x health, bulky olive-green silhouette + matching widened
  hitbox. Composition: `RunManager.grenadier_count_for_room` — none before room 5
  or in milestone rooms, +1 every 7 rooms, capped at 2. Spawn slots run snipers
  (front) → grenadiers → rushers (back), each clamped so they never overlap.
  Covered by `tools/grenadier_smoke_test.tscn` + `tools/grenadier_preview.tscn`.
- **All three archetypes shipped** (Rusher, Sniper, Grenadier). The Grenadier's
  grenade explosion reuses the `bullet_impact` signal for an impact mark + emits
  `sound_emitted` for the blast.

### Enemy combat fairness (added — rewards player skill)
Two enemy_ai.gd additions that read the player's movement state without touching
player.gd, so skilful play is rewarded:

- **Movement-trick aim penalty** — `_try_fire` already widened spread by raw player
  speed; on top of that `_player_evasion_spread()` adds extra spread (degrees) while
  the player is using a movement trick: wall-running (+5), sliding (+3), dashing
  (+6), vaulting (+3), and momentum (+momentum×4). It reads `_player.move_state` /
  `_dash_time_left` / `momentum` via `.get()`. Applies to all gun-firing enemies
  (regular / rusher / elite); the sniper (dodge the locked lane) and grenadier
  (telegraphed AoE) already have movement-based counterplay. Tunables are `EVADE_*`
  consts. Covered by `tools/aim_evasion_smoke_test.tscn`.
- **Reactive dodge** — when a player shot passes within `dodge_react_radius` of an
  aware, agile enemy, it may juke sideways (`dodge_chance`, on a `dodge_cooldown`).
  Driven off `GameEvents.bullet_tracer` (filtered to player-origin shots by `from`
  being within 3 m of the player, since enemy snipers also emit a tracer); the
  enemy must already be aware (not PATROL) so there's no psychic pre-dodge. A short
  `_process_dodge` overrides movement at the top of `_physics_process` (juke lateral
  to the player line while still facing them), then normal AI resumes. **Snipers and
  grenadiers don't dodge** (heavy/deliberate; their counterplay is punishing the
  telegraph). Tunables are the `dodge_*` `@export`s. Covered by
  `tools/dodge_smoke_test.tscn`.

### Upgrade pool (8, stacking)
max health +25 · move speed +10% · damage +20% · fire rate +15% · armor +30
instant · stamina max +25 · Scavenger (kills may drop a 25HP health pack,
+35%/stack) · ADS speed +25%.

### Flow
spawn → kill all enemies → `room_cleared` → **exit gate appears** (see below) →
player roams/collects → walks through gate → 1s freeze + banner → pick 1 of 3
upgrades → teleport + scaled enemies + fresh pickups → repeat → death →
`run_ended(false)` → stats screen → Try Again / Quit.

### Exit gate (room transition, added)
Clearing a room no longer starts the next one instantly — that gave the player
no time to grab leftover pickups. Instead `room_cleared` raises an **exit gate**
and the world stays live until the player walks through it.

- **`ExitGate`** (`scripts/run/exit_gate.gd`, `class_name ExitGate`, Area3D) —
  build-alongside, mirroring Pickup: self-builds its visual (a glowing
  matrix-green rectangular doorway frame + a portal-plane mesh) and detects the
  player via `body_entered` on the player layer (mask 2). Fires `player_entered`
  **once** (sets a `_triggered` guard + `monitoring = false`), pops in via a
  `_process` scale lerp, and pulses its frame emission. `set_portal_shader()`
  injects a spatial shader onto the portal plane *before* add_child (RunDirector
  passes `matrix_spiral_portal.gdshader`; falls back to a translucent emissive
  pane if none is given). `face_toward(point)` yaws the +Z face toward the spawn.
- **RunDirector** drives it: `_on_room_cleared` now calls `_spawn_exit_gate`
  (instead of `_run_transition` directly). The gate spawns at the **far end of
  the room** — the player spawn mirrored across centre on Z, `(0,0,-spawn.z)` —
  snapped onto the current room's navmesh (`NavigationServer3D.map_get_closest_point`)
  so it always lands somewhere walkable. `player_entered` (CONNECT_ONE_SHOT) →
  `_on_gate_entered` → frees the gate, hides the hint, runs the unchanged
  `_run_transition`. The gate is also freed on permadeath (`_on_player_died`).
- **RunHUD** gained a small `GateHint` label (top-centre, under the room
  counter) with `show_hint()` / `hide_hint()`; RunDirector shows
  "ROOM CLEARED - REACH THE EXIT GATE" while the gate is up.
- **No new room_cleared listeners broke**: only RunDirector triggered the
  transition before, so moving the trigger to the gate is localised. Audio's
  room-cleared sting still plays on the last kill.

### Matrix-spiral transition (added)
Walking through the gate plays a **rotating Matrix binary-spiral** screen wipe so
the room change is a smooth cinematic cut instead of a hard freeze.

- **Shaders** (`shaders/`) — `matrix_spiral.gdshader` (**canvas_item**, the
  full-screen wipe) and `matrix_spiral_portal.gdshader` (**spatial**, the gate's
  portal pane) share one effect: screen/UV → polar coords tiled into cells, the
  angular coord twisted by radius + rotated by `TIME` so cells wind into spiral
  arms, each cell a flickering binary glyph ("1" bar / "0" ring) in matrix green,
  with a brightness head streaming outward and a glowing core. The canvas one has
  a `cover` (0..1) uniform that drives alpha (1 = opaque near-black, hides the
  game; 0 = transparent). **Gotcha: `TAU`/`PI` are built-in shader constants — do
  not redefine them** (a `const float TAU` errors with "Redefinition of 'TAU'",
  which only surfaces non-headless since `--headless` never compiles shaders).
  **Seamless across the `atan` cut**: the angular cell index is wrapped
  `mod(floor(u), floor(arms))`, so the per-cell digit/brightness hash matches on
  both sides of the a = ±PI seam (without the mod a radial join line shows where
  the pattern abruptly changes). `arms` must stay an integer for the wrap.
- **RunHUD** owns the overlay: a full-rect `Transition` ColorRect with the
  canvas ShaderMaterial, ordered before the Banner/UpgradePanel so those draw on
  top of the spiral. `cover()` / `reveal()` are awaitable fades (a `_process`
  `move_toward` on the `cover` uniform, `PROCESS_MODE_ALWAYS` so it runs while
  paused). The ColorRect is `mouse_filter = ignore` so upgrade cards stay
  clickable through it.
- **RunDirector** `_run_transition` now `await _run_hud.cover()` first (player
  crossing the gate wipes the screen), does the freeze / upgrade picks / room
  rebuild **behind** the spiral, then `await _run_hud.reveal()` to fade the new
  room in. Shader `TIME` keeps advancing during the pause, so the spiral spins
  the whole time. The death-during-clear branch reveals before returning.
- **Preview** — `tools/transition_preview.tscn` + `.gd` (NON-headless render
  harness, like the toon previews) saves `tools/transition_preview_out.png` (the
  full-screen wipe) and `tools/gate_preview_out.png` (the gate portal in 3D),
  kept on purpose so the look is eyeballable without a live run.

### Upgrade card glitch (added)
The upgrade-selection cards play a **digital glitch** with three states — a
resting **idle** shimmer, a stronger **hover**, and a sharp **click** burst —
built directly into `RunHUD` (the roguelite UI the project already extends; the
matrix `Transition`/`GateHint` were added the same way).

- **Shader** `shaders/ui_glitch.gdshader` (**canvas_item**, `hint_screen_texture`)
  — horizontal slice tears, RGB-split chromatic aberration, scanlines and an
  occasional matrix-green "data flash", all scaled by a per-pixel amount and
  animated by `TIME` (which keeps advancing while the tree is paused, like the
  matrix wipe). It reads `base_intensity` over the card-row rect (`cards_min/max`)
  for the idle shimmer on all three cards, plus `focus_rect` + `focus_intensity`
  for the hovered/clicked card; outside the card row it passes the screen
  through untouched. **Gotcha: `return` is illegal in a `fragment()` — use
  if/else** (this one DOES surface headless, unlike the TAU redefine).
- **One full-screen overlay, not three.** A single `Glitch` ColorRect sits above
  the cards under `UpgradePanel` (`mouse_filter = ignore` so clicks pass through).
  Three separate per-card overlays each sampling SCREEN_TEXTURE only get **one**
  automatic back-buffer copy between them, so the 2nd/3rd cards sample a stale
  buffer and vanish — one overlay drawn after all cards fixes it. Displacement is
  in screen-UV, so it's small (`max_shift ~0.013`).
- **Driver** (`run_hud.gd`) — per-card `_glitch_hovered[]` (from each card's
  `mouse_entered`/`mouse_exited`) and `_glitch_click_t[]` (a `button_down` burst
  that decays over `GLITCH_CLICK_TIME`). `_update_glitch` (in `_process`, which is
  `PROCESS_MODE_ALWAYS`) picks the single hovered/clicked card as the focus
  (click outranks hover; one mouse = one focus), converts the card `get_global_rect`s
  to screen-UV and feeds the uniforms. `show_upgrade_choices` resets to idle;
  `hide_upgrade_choices` stays **synchronous** (RunDirector hides → applies →
  re-shows the milestone 2nd pick in one resume, so it must not defer) and zeroes
  the uniforms. Levels: `GLITCH_IDLE/HOVER/CLICK` consts.
- **Preview** `tools/glitch_preview.tscn` + `.gd` (NON-headless, kept) saves
  `tools/glitch_preview_out.png` — idle across the row + the middle card at a full
  click burst — since `--headless` can't compile the shader.

---

## Layered world (narrative layers)

The GDD reframes the run as escaping a dying computer through **five narrative
layers** (the GDD's "5 stages"): Heap → Stack → Cache → Kernel → I/O Buffer,
ending at the Kernel Panic boss + "The Choice". This is the **finite campaign**;
the shipped flat-infinite roguelite is preserved as an **endless** mode (Hybrid).
Built pass-by-pass over the existing run system, never replacing it.

**Pass 1 — layer backbone + Heap re-skin (shipped, `HEAP_SMOKE_OK`).**
- **`LayerCatalog`** (`scripts/run/layer_catalog.gd`, `class_name`, static data —
  not an autoload). Holds the per-layer `LayerProfile` dicts and the room→layer
  mapping. **A layer owns a contiguous band of GLOBAL rooms** (Heap = rooms 1-6);
  `profile_for_room` / `layer_index_for_room` / `room_in_layer_for_room` resolve
  the band, clamping to the last defined layer past the catalog. Pass 1 fills only
  the Heap. A `LayerProfile` carries: `tag`, `room_count`, `archetype_pool` (ids
  RoomBuilder may pick), `footprint_pool` (indices into RoomBuilder's combined
  `FOOTPRINTS`+`L_FOOTPRINTS`), and mood (`mood_tint`, `mood_strength`,
  `sun_energy_factor`). The Heap = early archetypes only (open_field /
  scattered_cover / pillar_hall), large+irregular footprints (no compact/standard
  square), a cold blue-green tint, dimmed sun.
- **`RunManager`** gains `enum RunMode {ENDLESS, CAMPAIGN}`, `selected_mode` (set
  by the menu/lobby/test *before* main.tscn loads; `start_run()` copies it into
  `run_mode`; **default ENDLESS** so the legacy flow + every harness are
  untouched), and `current_layer`/`room_in_layer` — a CAMPAIGN-only *view* over
  `current_room`. The **global room counter stays the source of truth in both
  modes**, so every enemy/scaling/archetype curve is unchanged; a layer is just a
  named window. `active_layer_profile()` returns the Heap profile in CAMPAIGN, `{}`
  in ENDLESS.
- **`RoomBuilder.build_room(room, profile := {})`** threads the profile through
  `_pick_archetype` / `_pick_footprint` (via the new pure `_footprint_by_index`) /
  `_apply_mood`. **An empty profile is byte-for-byte the legacy build**, so endless
  rooms are identical to before; the Heap profile applies the pool/bias/mood.
- **`RunDirector`** passes `RunManager.active_layer_profile()` into the build and
  makes the freeze-reveal banner layer-aware ("HEAP // SECTOR 2 - PILLAR HALL" vs
  the endless "ROOM N - ..."). **`RunHUD`** room label reads "HEAP - SECTOR n" in
  CAMPAIGN, "ROOM n" in ENDLESS.
- Covered by `tools/heap_smoke_test.tscn` (harness #19); endless proven unchanged
  (run_smoke/elite/transition/lobby green).

**Pass 2 — Heap room-type taxonomy (shipped, `HEAP_ROOMS_OK`).** Not every Heap
room is a fight.
- **`LayerCatalog`** gains `enum RoomType {COMBAT, FRAGMENT, GHOST}` and each
  layer a per-sector `room_sequence` (Heap = sectors 1-6 →
  Combat/Combat/Fragment/Combat/Ghost/Combat). `room_type_for(room)` indexes the
  sector into that sequence (defaults COMBAT if absent/over-run).
- **`RunManager.current_room_type()`** returns the active room's kind (always
  COMBAT in ENDLESS). **`is_milestone_room()` now returns false in CAMPAIGN** — the
  layer-end fix: no every-5th Proving Grounds breaking the Heap; layer bosses come
  later (Pass 5). ENDLESS milestones are unchanged.
- **`RunDirector`** branches after the build: COMBAT spawns the scaled squad as
  before; **FRAGMENT/GHOST are non-combat breathers** — no enemies, the HUD counter
  cleared, a placeholder marker (`fragment_room`/`ghost_room`, both in group
  `narrative_marker`) dropped at room centre, and the exit gate raised immediately
  so *traversal* (not killing) advances the run. The banner subtitle becomes
  "MEMORY FRAGMENT" / "CORRUPTED ECHO". `_clear_narrative_markers()` sweeps the
  marker on transition (mirrors `_clear_corpses`). The real room geometry is still
  built either way. ENDLESS always reports COMBAT, so its loop is untouched.
- Covered by `tools/heap_rooms_test.tscn` (harness #20).

**Pass 3 — Fragment system (shipped, `FRAGMENT_OK`).** The Awakening Arc text now
lives in the world.
- **`FragmentDB`** (ninth autoload, `autoloads/fragment_db.gd`) — a `FRAGMENTS`
  catalog ({id, arc, header, body}; cold system-log voice from the GDD) + the
  collected set, **persisted to `user://fragments.cfg`** (like MetaProgression) so
  the story builds across runs. `pick_for_arc(arc, room)` returns the next
  uncollected entry of that arc (ordered reveal), falling back to a seeded repeat
  once all are seen; the Heap surfaces the `"awakening"` arc.
- **`MemoryFragment`** (`scripts/run/memory_fragment.gd`, `class_name`, Area3D) —
  a self-building floating data-shard + id tag, mirroring ExitGate (layer 0 / mask
  2, `body_entered` checks group `player`). Optional: the player walks into it to
  read. On first contact it records itself (`FragmentDB.mark_collected`), emits
  `GameEvents.fragment_read`, then dissolves. Joins `fragment_room` +
  `narrative_marker` (so it's swept on transition, same as the Pass-2 placeholder).
- **`FragmentReader`** (`scripts/ui/fragment_reader.gd`, `class_name`, CanvasLayer
  on layer 3) — a non-modal corner overlay (per the GDD, fragments "never interrupt
  gameplay"): fades in, holds ~7s, fades out, no pause/input capture. Self-builds
  its UI; listens to `GameEvents.fragment_read`. RunDirector instantiates one per
  run (deferred add in `_ready`).
- RunDirector's Fragment room now spawns a `MemoryFragment` (next Awakening entry)
  instead of the bare marker; Ghost rooms keep the placeholder until Pass 4.
- Adds a new bus signal `GameEvents.fragment_read(fragment)` (additive). Covered by
  `tools/fragment_test.tscn` (harness #21).

**Pass 4 — Heap generation identity (shipped, `HEAP_GHOST_OK`).** Stays within the
re-skin (no bespoke geometry yet); gives the Heap atmosphere + a real Ghost room.
- **Atmosphere debris** — `RoomBuilder._spawn_atmosphere` scatters decorative
  floating shards (group `room_debris`, **no collision** so nav/gameplay are
  untouched, children of GeneratedRoom so swept on the next build) at heights
  1.5-8 m for a vertical, drifting-data read. Count scales with the profile's
  `corruption` (0 = none, so **endless rooms are visually unchanged**).
- **Ghost rooms** are now spectral "corrupted echoes": `build_room` detects a Ghost
  sector (`LayerCatalog.room_type_for(room)`, pure) and gives its cover a
  translucent emissive `_ghost_material` (group `ghost_geometry`), a heavier debris
  swarm, and a mood pulled toward the layer's `ghost_tint` + dimmed further.
- New Heap profile fields: `corruption` (0.5) + `ghost_tint`. Threaded through
  `_instantiate_boxes(boxes, ghost)` and `_apply_mood(archetype, profile, ghost)`.
- Covered by `tools/heap_ghost_test.tscn` (harness #22); the look is eyeballed by
  playing a campaign to sector 5 (Ghost obstacles still solid — "half-materialized"
  is conveyed by the material, not by removing collision).

**Pass 5a -- layer exit -> Stack handoff (shipped, `DESCENT_OK`).** A second layer
exists and the run descends into it.
- **`LayerCatalog`** gains **Layer 02, The Stack** (global rooms 7-12): a colder,
  brighter, **rectangular-only** re-skin (grid-ish pool pillar_hall / maze_lanes /
  arena_cross, `footprint_pool` with no L-shapes), low `corruption` (0.12),
  combat-dense `room_sequence`, and the **`history`** fragment arc. Each profile now
  carries an `arc`; FragmentDB gained a second `history` entry.
- **Descent beat:** RunDirector compares `current_layer` across `advance_room()`;
  crossing a layer boundary shows a `DESCENDING // THE STACK` banner for
  `DESCENT_BEAT_SECONDS` before the build. The profile swap is automatic
  (`active_layer_profile()` reads the new global room); the Fragment room uses the
  active layer's `arc` (Heap = awakening, Stack = history).
- ENDLESS keeps `current_layer` at 0, so it never descends. Past the catalog the run
  clamps to the last layer (Stack over-run) until layers 3-5 ship.
- Covered by `tools/descent_test.tscn` (harness #23).

**Pass 5b -- lobby run-mode selector (shipped, `MODE_SELECT_OK`).** Players choose
the run mode; campaign is the default.
- The lobby builds a **`ModeToggle`** Area3D station in code (matching the
  self-building convention -- no scene edit), set beside the StartPortal. The
  selection (`_selected_mode`) **defaults to CAMPAIGN** ("ESCAPE"); interacting
  flips it CAMPAIGN <-> ENDLESS and pushes it **live** to `RunManager.selected_mode`,
  with the pylon label + the portal prompt tracking it.
- **`_ready` never touches `RunManager.selected_mode`**, and the live push only
  happens on interacting with the toggle -- so `lobby_smoke` (which never touches
  it) keeps the ENDLESS default and its milestone payout, and any harness that
  drives RunManager directly is unaffected. `start_run()` sets the mode from
  `_selected_mode` as a backstop, so an untouched lobby still launches CAMPAIGN.
- Covered by `tools/mode_select_test.tscn` (harness #24).

**The Heap track is complete (Passes 1-5b).** A full campaign run now: pick mode in
the lobby (campaign default) -> Heap (typed rooms, Awakening fragments, ghost echoes,
corrupted-vertical atmosphere) -> descend -> Stack (orderly, History arc). **Next:**
layers 3-5 (Cache / Kernel / I/O Buffer) + the Kernel Panic boss + The Choice
ending; and the deferred bespoke Heap geometry (irregular / multi-level). Room 1
stays the authored "home" arena.

---

## Main menu & settings (added)

- **`scenes/ui/main_menu.tscn`** + `scripts/ui/main_menu.gd` — the project's
  **main scene** (project.godot `run/main_scene` points here now; PLAY loads
  the Lobby, which in turn loads main.tscn). PLAY / SETTINGS / QUIT, with a
  tabbed settings screen (Graphics / Controls / Mouse). The run-end screen's
  second button is now "MAIN MENU" (returns here) instead of quitting the app.
- **`SettingsManager`** (third autoload, `autoloads/settings_manager.gd`) —
  loads/saves `user://settings.cfg` and applies everything immediately:
  - *Graphics*: fullscreen, VSync (DisplayServer), render scale
    (root viewport `scaling_3d_scale`), shadow quality Off/Low/Medium/High
    (directional shadow atlas size + soft-shadow filter + per-light
    `shadow_enabled`), FOV.
  - *Mouse*: sensitivity multiplier (0.2-3.0).
  - *Controls*: full key/mouse rebinding via `InputMap`; events serialize
    straight into the ConfigFile; "Reset to Defaults" restores
    project-settings bindings.
  - Player-specific values (sensitivity, FOV) are pushed onto the Player's
    exported vars via a `node_added` hook (`node is Player` → deferred apply),
    so **player.gd stays untouched**. Invert-Y was deliberately skipped: the
    player uses one sensitivity for both axes, so it can't be done without
    modifying player.gd.

---

## Meta progression: Lobby + Cores (added)

- **`MetaProgression`** (fourth autoload, `autoloads/meta_progression.gd`) —
  Cores currency + 5 permanent upgrade levels, persisted to
  `user://meta_progress.cfg` (same ConfigFile pattern as SettingsManager).
  Permanent pool (separate from the 8 in-run upgrades), 5 levels each, next
  level costs `base_cost * (level + 1)`: +10 starting max health (40) ·
  +10 starting armor (40) · +3% move speed (60) · +6% reload speed (50) ·
  +10% ammo capacity (50).
- **Cores payout** — connected to `RunManager.run_ended(won)`; on permadeath
  it pays `10 × rooms_cleared + 50 per cleared milestone room`, where
  `rooms_cleared = current_room - 1` (`current_room` is the room the player
  died *in*, matching the RunHUD summary).
- **`scenes/ui/lobby.tscn`** (`Node3D`) + `scripts/ui/lobby.gd` — pre-run hub
  as an **actual 3D space**, not a UI menu: an enclosed 24×24 room you spawn
  into as the real first-person `player.tscn`, walk around with WASD/mouse,
  and interact with at proximity. Five glowing upgrade **pedestals** (Area3D
  zones named after the upgrade ids, each with a billboard `Label3D` showing
  title/level/cost), a green **START portal**, and an amber **MAIN MENU door**.
  Standing in a zone shows a worldspace prompt; pressing **`interact` (E, new
  input action)** acts on the nearest one — buy / `start_run()` / back to menu.
  The hub's gun is silenced via the RunDirector process-toggle trick (no
  weapon_manager.gd edit). HUD overlay (`LobbyHUD` CanvasLayer) shows the Cores
  balance + the prompt + control hints. `start_run()` is public so the
  transition harness can drive it.
- **Armed-run gate** — bonuses apply (and Cores pay out) only after the
  portal's `start_run()` armed the meta layer; the flag stays set so Try Again
  reloads keep their bonuses, and lobby `_ready` disarms on entry so the hub
  player itself is always vanilla. Direct main.tscn launches (editor F5, the
  older smoke harnesses) stay vanilla too — that keeps harness assertions
  deterministic and keeps test permadeaths from writing Cores into the real save.
- **Application path** — same `node_added` hook pattern as SettingsManager:
  `node is Player` → deferred apply onto the Player's/WeaponData's exported
  vars, after PlayerUpgrades has duplicated the WeaponData .tres (so weapon
  changes hit the per-run copies, never the resource cache). Bigger magazines
  are loaded at spawn via the existing public `WeaponManager.reset_loadout()`.
  **player.gd / weapon_manager.gd / run_manager.gd / run_director.gd stay
  untouched**; the one menu edit is main_menu.gd's PLAY target (lobby instead
  of main.tscn), plus the additive `interact` input action.

## Audio (added)

- **`AudioManager`** (fifth autoload, `autoloads/audio_manager.gd`) — a sibling
  observer in the SettingsManager/MetaProgression mould: it **only listens to the
  autoload signal buses and plays the mapped sound**, never editing the gameplay
  scripts. Registered last so the buses it connects to already exist.
- **Signal sources** — `GameEvents` (`sound_emitted` gunfire, `hit_confirmed`,
  `weapon_changed`, `player_damaged`, `player_health_changed` low-HP warning,
  `player_died`, `player_respawned`, `game_won`/`game_lost`), `RunManager`
  (`run_started`, `room_cleared`, `run_ended(won)`), `MetaProgression`
  (`cores_changed`), plus a `node_added` hook (same pattern as SettingsManager)
  that connects each `EnemyAI.enemy_died` with `CONNECT_ONE_SHOT` for **positional
  3D death audio**.
- **Gunfire disambiguation** — `sound_emitted(pos, radius)` fires for both the
  player and every enemy and carries no weapon type. The manager treats a sound
  within 1.5 m of the player's own position as the player's shot (per-weapon fire,
  weapon key tracked from the last `weapon_changed`) and everything else as a
  positional enemy shot. End-of-run stings are debounced (player_died → run_ended
  can both fire) so victory/defeat never double-plays.
- **Registry, silent until filled** — `STREAMS` maps a logical key → a
  `res://audio/...` **base path with no extension**; load probes `.ogg`/`.wav`/
  `.mp3` in order. A missing file just doesn't play, so the whole system is wired
  before any asset exists (drop file → Godot imports → it plays, no code change).
  `audio/README.md` is the canonical wishlist marking which keys are live now vs
  hooked in a later pass. One-shot voices are spawn-and-free
  `AudioStreamPlayer`/`AudioStreamPlayer3D` nodes.
- **Mixing** — runtime buses `Master → {Music, SFX, UI}` created idempotently via
  `AudioServer`; volumes (0..1) persist to **`user://audio.cfg`**, deliberately
  separate from settings.cfg so the menu harness's snapshot/restore is untouched.
  `set_master/music/sfx/ui_volume()` public API awaits the settings-slider pass.
- **Headless** — `process_mode = ALWAYS` (so room-cleared / UI / stings play while
  RunDirector pauses the tree), and the whole manager goes inert when
  `DisplayServer.get_name() == "headless"`, so every harness stays green and fast.
- Wired now: player/enemy fire, weapon switch, hitmarker/headshot, enemy death,
  player hurt/death, low-health, core gained, run start, room cleared,
  victory/defeat. Deferred passes: footsteps/jump/land/dash/slide, reload +
  dry-fire, pickup grants, UI click/hover + upgrade-select, looping music, and the
  settings volume sliders.

---

## Cel-shading (added)

A toon/cel look applied across the game in **four passes**, built entirely
**alongside** the existing code: no gameplay script or scene was edited. One new
autoload plus two shaders do all the work.

- **`ToonApplicator`** (sixth autoload, `autoloads/toon_applicator.gd`) — a sibling
  observer in the SettingsManager/AudioManager mould: it listens to
  `get_tree().node_added` and swaps qualifying nodes' materials for a toon
  `ShaderMaterial`, never touching the source scripts. Branches:
  - **Enemies** (`EnemyAI`) — toonifies each `Visual/*` MeshInstance3D, copying
    albedo+emission off the active StandardMaterial3D. **Elites work for free**:
    `RunDirector._outfit_elite` sets the crimson/gold emissive override (+1.25x XZ
    scale) *before* `add_child`, so by `node_added` the applicator reads and
    preserves the glow. Outlined.
  - **Player weapon** (`WeaponManager`) — deferred (the viewmodels are built in
    `WeaponManager._ready`, just after node_added fires). Toonifies only each
    weapon-model root's direct body+barrel meshes, leaving the nested MuzzleFlash
    an unshaded emissive billboard. Thin outline (the gun sits ~0.45 m from the eye).
  - **Pickups** (`Pickup`) — deferred (self-builds its floating BoxMesh in _ready).
    Keeps the type colour + emission glow; survives the consume/respawn visibility
    toggle. Mid-weight outline.
  - **World** (`CSGShape3D` for the room-1 arena + retained Floor/walls shell;
    `StaticBody3D` for the procedural RoomBuilder boxes) — **banding-only, NO
    outline**, so the outlined characters/weapon/pickups pop against a calm world.
    CSG inherits `material_override` from GeometryInstance3D; colour is read from the
    node's `.material`, guarded by `is_root_shape()`. (Lobby geometry gets cel-shaded
    too, for free.)
- **Shaders** (`shaders/`) — `toon.gdshader`: a custom `light()` quantizes N·L into
  3 hard bands (ambient fills the dark side) plus a fresnel rim; `toon_outline.gdshader`:
  inverted-hull outline (`cull_front`, push along the normal) chained as `next_pass`.
- **Look tunables** are consts at the top of toon_applicator.gd: `BANDS`, `RIM_*`,
  `OUTLINE_WIDTH_ENEMY/WEAPON/PICKUP`, `OUTLINE_COLOR`.
- **Rim is curved-objects-only.** The fresnel rim is view-dependent, so on a big flat
  floor it draws a bright ring that *tracks the camera*. World materials are built
  with `rim = 0` to kill it — do not re-enable rim on flat world geometry.
- **Headless caveat / preview tools.** The `--headless` dummy renderer can't compile
  shaders, so the smoke harnesses only prove the materials load and the applicator
  doesn't throw — never the actual look. `tools/toon_preview.tscn` (enemies + pickups
  + world props) and `tools/weapon_preview.tscn` (a frozen `player.tscn`, using its
  camera) are NON-headless render harnesses that save reference PNGs
  (`tools/toon_preview_out.png`, `tools/weapon_preview_out.png` — kept on purpose) so
  any session can eyeball the style without re-running Godot.

---

## Weapon wall-clip fix (added)

Stops the first-person weapon viewmodel from poking through walls / crates /
pillars when the player stands close to them. Built **alongside** in the
SettingsManager/AudioManager/ToonApplicator observer mould — **no
weapon_manager.gd, player.tscn or toon_applicator.gd edit**.

**Approach: render the viewmodel ON TOP of the world** (depth test disabled), so
the gun simply *ignores* walls — it never moves. This is the standard FPS
technique and what reads correctly to the player. (A first attempt raycast every
frame and slid the model roots back toward the eye; that retraction looked wrong
and was **replaced** by this render-on-top version at Vor's request — "ignore the
walls without pushing the weapon back".)

- **`WeaponClip`** (seventh autoload, `autoloads/weapon_clip.gd`) — listens to
  `get_tree().node_added`, adopts each `WeaponManager` **once** (deferred, so its
  `_ready` has built the viewmodels *and* ToonApplicator's own deferred pass has
  cel-shaded them), and flips the viewmodel meshes to draw without a depth test.
  No per-frame work, no raycast — purely a one-time material setup.
- **Body + barrel** are cel-shaded (a toon `ShaderMaterial`), and depth test is a
  compile-time `render_mode`, not a per-material flag — so WeaponClip swaps their
  shader from `toon.gdshader` to **`shaders/toon_viewmodel.gdshader`**: the
  identical cel look with `depth_test_disabled` baked in. The material's uniforms
  and its outline `next_pass` carry over untouched (swap is just
  `ShaderMaterial.shader = VIEWMODEL_SHADER`).
- **`toon_viewmodel.gdshader`** — a copy of `toon.gdshader`; **only** the
  `render_mode` differs: `cull_back, depth_test_disabled, depth_draw_opaque`. The
  `depth_draw_opaque` is load-bearing: the fill still *writes* depth, so the gun
  self-sorts (barrel over body) and the inverted-hull outline (`next_pass`, still
  depth-tested) reads as a clean silhouette instead of flooding the whole gun with
  ink. **KEEP IN SYNC with toon.gdshader** if the cel look changes.
- **Muzzle flash** keeps its unshaded `StandardMaterial3D` billboard; WeaponClip
  just sets `no_depth_test = true` on it so the flash clears walls too. Same
  `no_depth_test` path is the fallback if a body/barrel is ever left on a
  StandardMaterial3D (cel-shading off).
- **Order** — relies on autoload order (ToonApplicator 6th, WeaponClip 7th): the
  `node_added` connections fire in that order, so ToonApplicator's deferred
  `_toonify_weapon` runs before WeaponClip's deferred `_adopt` and the toon
  material is already in place to swap. Stays valid under `--headless` (shader/flag
  assignment is plain resource data — no compile needed), so the smoke harness
  checks it for free. The actual look (gun over wall, outline not flooded) is
  eyeballed via `tools/weapon_clip_preview.tscn` (NON-headless, saves
  `tools/weapon_clip_preview_out.png`), since `--headless` can't compile shaders.

---

## Bullet FX: decals + tracers (added)

Combat juice for hitscan fire — a bullet streak per shot and a persistent bullet
hole where it lands. Built **alongside** as one sibling autoload; the only edit to
existing code is two signal *emits* (wiring) in weapon_manager.

- **`BulletFX`** (eighth autoload, `autoloads/bullet_fx.gd`) — a sibling observer
  in the SettingsManager/AudioManager/ToonApplicator mould: it only listens to the
  `GameEvents` bus and spawns cosmetic nodes, never touching gameplay logic. All
  visuals are **procedural** (a code-generated bullet-hole texture, code-built
  meshes/materials), matching the project's no-art-assets style.
- **Two new `GameEvents` signals** — `bullet_tracer(from, to)` and
  `bullet_impact(position, normal)`. `weapon_manager._fire_ray` emits them: the
  tracer originates from the **muzzle** (the flash node's world position), not the
  camera, so it streaks from the gun instead of the player's face; the impact fires
  only on **world** hits (not enemy hitboxes). This is the lone weapon_manager edit
  — two emit lines, pure wiring, within the build-alongside rule.
- **Tracers** — a thin emissive `CylinderMesh` from muzzle to hit point, unshaded
  yellow, faded out over `TRACER_LIFE` (~0.06 s) via a tween then freed. Hits
  basically on the muzzle (`< TRACER_MIN_LENGTH`) are skipped.
- **Decals** — a `Decal` node at the hit point, oriented so its local +Y is the
  surface normal (it projects along -Y onto the surface), random roll + size. They
  hold at full opacity (`DECAL_HOLD`) then fade (`DECAL_FADE`), and are **capped at
  `MAX_DECALS` (96)** — oldest recycled — so they never accumulate. Enemy hits get
  no decal (the existing impact-spark particle in weapon_manager still plays for
  world hits).
- **Impact-spark origin fix** — weapon_manager's `_spawn_impact` CPUParticles3D was
  bursting at the world origin (you'd see sparks at `(0,0,0)`, which happens to be
  where `ArmorShard1` sits) because CPUParticles3D defaults to `emitting = true` and
  fired its one_shot the instant it entered the tree, *before* `global_position` was
  assigned. Fixed by creating it with `emitting = false` and only setting
  `emitting = true` after positioning at the contact point.
- Spawned nodes are parented to `get_tree().current_scene` (so they die with a room
  rebuild / scene reload) and added to groups (`bullet_decal` / `bullet_tracer`)
  for cheap lookup + the harness. Stays valid under `--headless` (node creation
  only), so harness #12 drives it through the bus and counts nodes; the actual look
  is eyeballed via `tools/bullet_fx_preview.tscn` (NON-headless, saves
  `tools/bullet_fx_preview_out.png`). Tunables are consts at the top of the file.

---

## Advanced movement (added)

Traversal mechanics built **inside `player.gd`** as first-class movement
features — an **explicit, Vor-approved exception** to the "never rewrite
player.gd" rule, because movement is intrinsic to the controller (a sibling
component would have to reach deep into player internals anyway). Being added
one mechanic at a time. **All four shipped: wall-run, dash, vault, momentum.**

- **Wall-run** (`MoveState.WALLRUN`) — jump into a wall while moving and the
  player sticks and runs along it. Mirrors how `SLIDE` already lives inline:
  a top-level branch in `_physics_process` (`_try_enter_wallrun` →
  `_process_wallrun`), with `_update_move_state` early-returning so the state
  is preserved. Detection uses the body's own `is_on_wall_only()` +
  `get_wall_normal()` (**no player.tscn edit / no extra raycasts**). The
  gravity step is gated off during wall-run; `_process_wallrun` applies its own
  near-zero `wallrun_gravity`, projects velocity onto the wall and accelerates
  along the tangent (`wall_normal × UP`, signed by look dir) toward
  `wallrun_speed`, adds a small into-wall stick force, drains stamina, and
  tilts the camera toward the wall. `jump` triggers `_wall_jump` (push off the
  wall + up, preserving along-wall momentum). Exits on timer / landing / lost
  wall / low speed / empty stamina; a `wallrun_cooldown` + `_last_wallrun_normal`
  block re-running the **same** wall, so you chain between opposite walls but
  can't spam one. All values are grouped `@export`s (`wallrun_*`). Reset in
  `respawn_at`. Arcade/Titanfall feel.

- **Dash** (`dash` input action, default **Q**, `physical_keycode 81`, kept out
  of `REBINDABLE_ACTIONS` like `interact`) — a charged burst, air **or** ground.
  Not a MoveState: the trigger (`_start_dash`) sets `_dash_time_left` /
  `_dash_dir`, and a branch in `_physics_process` (above the normal-movement
  else, below SLIDE/WALLRUN) overrides horizontal velocity to `_dash_dir *
  dash_speed` for `dash_duration`, **leaving vertical to gravity** so air-dashes
  keep their fall. Direction is the movement input, or body-forward with no
  input (always horizontal). **2 charges** (`dash_max_charges`) that refill one
  at a time every `dash_recharge_time` (`_update_dash_recharge`); each dash costs
  `dash_stamina_cost` + a brief `dash_fov_add` punch. Gated out of slide/wall-run.
  Reset in `respawn_at`. Grouped `@export`s (`dash_*`).

- **Vault** (`MoveState.VAULT`, contextual on **jump** — no new input action) —
  mantle over low obstacles (the 1.4 m crates / low cover; rejects the 2.2 m
  bunker walls and 4 m pillars). `_try_start_vault` probes the **world layer
  (`VAULT_MASK = 1`)** with three runtime `intersect_ray` queries (no scene edit,
  same space-state approach as the weapon hitscan): a low forward ray must hit an
  obstacle, a high ray (above `vault_max_height`) must be **clear**, and a
  downward ray finds the top surface and checks `rise` ∈ [`vault_min_height`,
  `vault_max_height`]. On success it switches to `VAULT` and `_process_vault`
  takes over the frame at the **top of `_physics_process`** (before gravity /
  `move_and_slide`), lerping `global_position` along a `sin`-arc
  (`vault_arc_height`) from start to a point `vault_forward_clearance` past the
  near face, on top, over `vault_duration` — so it briefly passes *through* the
  box (standard mantle), then `_exit_vault` restores `vault_exit_speed` forward.
  Falls through to a normal jump when nothing is vaultable. Grouped `@export`s
  (`vault_*`); reset in `respawn_at`.

- **Momentum** (public `var momentum` 0..1, not a MoveState) — smooth continuous
  movement builds speed up to a cap. `_update_momentum` runs every frame **after
  `move_and_slide`**: it builds (`momentum_build_rate`) while horizontal speed >
  `momentum_min_speed`, wish input is aligned with velocity (dot >
  `momentum_align_threshold`), and you're not smacking a wall head-on
  (`is_on_wall()` + opposing `get_wall_normal()`); wall-run / slide / the dash
  window always count as "in flow". Otherwise it decays faster
  (`momentum_decay_rate`). Effect: `_current_max_speed()` returns `base * (1 +
  momentum * momentum_max_bonus)` for **walk/sprint only** (crouch/prone keep
  their base), plus a `momentum_fov_add` FOV widening for a speed sense. **Scope
  choice:** momentum lifts the *running* top speed and wall-run/dash *count*
  toward it, but their own internal speeds stay fixed (keeps those mechanics +
  their tests predictable). Grouped `@export`s (`momentum_*`); reset in
  `respawn_at`.

---

## Developer tools (added)
`DevTools` (`autoloads/dev_tools.gd`, the 10th autoload) — a debug-build-only
playtest helper in the SettingsManager / ToonApplicator observer mould.
Build-alongside: it NEVER edits player.gd / enemy_ai.gd / run_director.gd; it only
reads/writes their public state from outside and routes enemy kills through the
normal HitboxComponent. Gameplay keys (inert in menus / when no player exists):
- **F1 — god mode.** Captures the player's real `max_health`/`max_armor` once, then
  raises both to a huge pool (`GOD_POOL = 1e9`) and tops them off, so no single
  `take_damage` can reach 0 (the player never calls `_die`); toggling off restores
  the captured maxima. Re-armed automatically on a fresh player (a new run reloads
  main.tscn) via the `_process` watchdog. Chosen over a per-frame health pin because
  it survives one-shots (snipers/grenades) without editing the damage path.
- **F2 — kill all enemies.** Lethal `BodyHitbox.take_hit` on every live enemy (the
  same path the smoke tests use), so deaths run the full ragdoll + `enemy_died` +
  room-clear flow → the exit gate appears, exactly as in real play.
- **F3 — refill** health, armor (`heal`/`add_armor`) + ammo (`WeaponManager.reset_loadout`).
- **F5 / F6 — jump to the next / previous room**; **F7 — jump to the next narrative
  layer's first room** (cycles; e.g. Heap→Stack→wrap). Drives `RunDirector.dev_jump_to_room(target)`,
  which sweeps the current room's leftover enemies + exit gate, wipes the screen, sets
  the room counter so the shared `_enter_next_room()` lands on the target, and rebuilds
  + repopulates it through the **same pipeline as the real gate transition** (so the
  dev warp can't drift). `_run_transition`'s build/populate tail was extracted into
  `_enter_next_room()` for this reuse; re-entrancy is guarded (`_dev_jump_active`).
A small `CanvasLayer` overlay shows the binds + god state during gameplay (hidden in
menus). Gated to `OS.is_debug_build()`, so it is inert in a release export. Verified
by `tools/dev_tools_test.tscn` → `DEV_TOOLS_OK`.

---

## Current state
Run system + procedural room generation implemented; **all headless checks
pass** (script check, base smoke test, run smoke test covering two procedural
transitions). The base game and the roguelite layer coexist; no existing
gameplay script was rewritten (only `tools/smoke_test.gd`'s final assertion
was updated from `game_won` to `room_cleared` to match the new flow).
Elite/milestone rooms shipped (every 5th room; see above). Meta progression
shipped: 3D Lobby hub (menu→PLAY→lobby→walk to portal→START RUN→main), Cores
on permadeath, 5 permanent upgrades bought at walk-up pedestals and persisted
in user://meta_progress.cfg, applied via the armed-run node_added hook.
**Audio scaffolding shipped** (silent until assets arrive): `AudioManager` fifth
autoload + runtime buses + registry wired to live signals; all headless checks
stay green (manager is inert under `--headless`); Vor sources the assets per
`audio/README.md`. **Cel-shading shipped** — all four coverage passes (enemies,
weapon viewmodel and pickups outlined; world banding-only) via the
`ToonApplicator` sixth autoload + `shaders/toon`, build-alongside (no gameplay
script or scene edited; rim disabled on flat world geo to avoid a camera-tracking
floor ring). **Advanced movement shipped** — wall-run, dash, vault and momentum,
all built inside `player.gd` as first-class `_physics_process` features (the
Vor-approved exception to the build-alongside rule; see *Advanced movement*
above), added one mechanic per pass and covered by harness #9. They compound: a
dash into a wall-run, wall-jump out, and clean continuous movement all feed the
momentum pool that raises running speed. **Exit-gate room transition shipped**
(both passes) — rooms no longer auto-advance on the last kill; a self-building
`ExitGate` (Area3D) appears at the far end of the room and the player walks
through it to start the transition, leaving time to collect pickups (pass 1, see
*Exit gate* above). **Upgrade-card glitch shipped** — the upgrade-selection cards
play a digital glitch with idle / hover / click states via a single
`shaders/ui_glitch.gdshader` overlay above the cards, driven from `run_hud.gd`
(see *Upgrade card glitch*); covered by harness #11 + `tools/glitch_preview.tscn`. Going through the gate plays a rotating **Matrix binary-spiral
shader** wipe (`shaders/matrix_spiral*`) over the freeze/upgrade/rebuild, fading
the new room in (pass 2, see *Matrix-spiral transition*; verified visually via
`tools/transition_preview.tscn`). **Weapon wall-clip fix shipped** — a seventh
autoload `WeaponClip` makes the viewmodel render ON TOP of the world (swaps the
cel fill to `toon_viewmodel.gdshader` with `depth_test_disabled`, flags the muzzle
flash `no_depth_test`), so the gun ignores walls/crates entirely instead of
pulling back; build-alongside (no weapon_manager.gd/player.tscn/toon_applicator.gd
edit), covered by harness #10 + `tools/weapon_clip_preview.tscn`. **Bullet FX
shipped** — an eighth autoload `BulletFX` draws a per-shot tracer (muzzle → impact)
and a capped, fading bullet-hole decal on world hits, via two new `GameEvents`
signals weapon_manager emits (the only weapon_manager edit: two wiring lines);
covered by harness #12 + `tools/bullet_fx_preview.tscn`. **Variable room footprint
shipped** (all 3 size+shape passes: square, rectangular, L-shaped) — RoomBuilder
now owns the shell too: each room 2+ picks a seeded footprint (square / wide-deep
rectangle / L-shape with a notched north corner) and builds its own sized floor +
walls, moves the player spawn to the new south edge, scales the structured
archetypes per-axis to fill it, and geometrically excludes the L notch from all
placement (see *RoomBuilder* above); `_rebake` `map_force_update`s the nav map so
spawn/pickup validation reads the fresh room. Build-alongside (only my own
room_builder.gd / run_director.gd edited), covered by the run smoke test, the
`tools/l_room_test.tscn` harness + `tools/room_size_preview.tscn`. **Death ragdoll
shipped** — `EnemyAI._die` replaces the old keel-over tween with a `RigidBody3D`
corpse that takes over the visual meshes, is knocked away from the shooter and
tumbles, then shrinks out (see *EnemyAI* above); core edit confined to enemy_ai.gd
(pre-approved for ragdoll), covered by `tools/ragdoll_smoke_test.tscn` +
`tools/ragdoll_preview.tscn`. **Enemy archetypes — pass 1 (Rusher) shipped** — a
fast, fragile point-blank charger added to normal squads via the elite-style
external outfit hook (`RunDirector._outfit_rusher`, no enemy_ai.gd edit; behavior
emergent from tuning the existing state machine), spawned on a deterministic
`RunManager.rusher_count_for_room` curve (room 3+, non-milestone, capped ~1/3 of
the squad); leaner orange look + matching hitbox; covered by
`tools/rusher_smoke_test.tscn` + `tools/rusher_preview.tscn` (see *Enemy
archetypes* above). **Pass 2 (Sniper) shipped** — a long-range marksman that
holds back and lands one heavy, telegraphed charged shot, then relocates; needed
a small **off-by-default `is_sniper` hook** in enemy_ai.gd (charged shot can't be
pure tuning — kept gated so all other enemies run the unchanged path), spawned via
`RunManager.sniper_count_for_room` (room 4+, capped at 2, front spawn slots, never
overlapping rushers); cyan taller look + telegraph beam; covered by
`tools/sniper_smoke_test.tscn` + `tools/sniper_preview.tscn`. **Pass 3 (Grenadier)
shipped** — a mid-range area-denial unit that lobs telegraphed arcing grenades
(ground danger ring + falloff AoE) to flush the player out of cover; off-by-default
`is_grenadier` hook in enemy_ai.gd + a new sibling `scripts/enemies/grenade.gd`,
spawned via `RunManager.grenadier_count_for_room` (room 6+, capped at 2); bulky
olive look; covered by `tools/grenadier_smoke_test.tscn` +
`tools/grenadier_preview.tscn`. **All three enemy archetypes now shipped.**
**Enemy combat fairness shipped** — enemy gunfire loses accuracy while the player
uses movement tricks (wall-run/dash/slide/vault/momentum, via
`_player_evasion_spread`), and aware agile enemies reactively dodge player shots
that pass close (off `bullet_tracer`; snipers/grenadiers excepted). Both are
enemy_ai.gd additions that read player state without touching player.gd; covered by
`tools/aim_evasion_smoke_test.tscn` + `tools/dodge_smoke_test.tscn` (see *Enemy
combat fairness*). **Death-ragdoll polish shipped** (all 3 passes) — the corpse
flies along the actual bullet (recorded per-shot through `HitboxComponent`, impulse
applied at the hit point), headshots pop the head off as its own rigid body, the
gun always drops as a separate piece, and RunDirector sweeps the corpse group on
room transition; also hardened `_player_dead()` against a player without `is_dead`.
Covered by `tools/ragdoll_polish_smoke_test.tscn` (see *EnemyAI* death ragdoll).
**Layered world — Pass 1 (layer backbone + Heap re-skin) shipped** — the GDD's
five narrative layers begin: a new `LayerCatalog` + `RunManager` run-mode/layer
state turn the flat room counter into a named "Heap = rooms 1-6" window, and
`RoomBuilder.build_room(room, profile)` re-skins generation (archetype pool /
footprint bias / cold dimmed mood) when a CAMPAIGN profile is supplied — an empty
profile leaves ENDLESS byte-for-byte unchanged (Hybrid: endless preserved). See
*Layered world* above; covered by `tools/heap_smoke_test.tscn`. **Pass 2 (Heap
room-type taxonomy) shipped** — a per-layer `room_sequence` makes Heap sectors 3 +
5 non-combat breather rooms (Fragment / Ghost: no enemies, exit gate up on arrival,
placeholder narrative marker), CAMPAIGN suppresses the every-5th milestone (the
layer-end fix), and RunDirector branches combat vs non-combat on
`RunManager.current_room_type()`; covered by `tools/heap_rooms_test.tscn`. **Pass 3
(Fragment system) shipped** — the Awakening Arc text lives in the world: a
`FragmentDB` autoload (catalog + cross-run collected save), a self-building
`MemoryFragment` data-shard that records + announces on touch, and a non-modal
`FragmentReader` overlay; Fragment rooms surface the next unseen Awakening entry;
covered by `tools/fragment_test.tscn`. **Pass 4 (Heap gen identity) shipped** — the
re-skin gains floating atmosphere debris (corruption-scaled, decorative, vertical
spread) and turns Ghost rooms into spectral "corrupted echoes" (translucent
emissive cover + heavier debris + ghost-tinted mood); endless rooms stay visually
unchanged (corruption 0); covered by `tools/heap_ghost_test.tscn`. **Pass 5a (Stack
handoff) shipped** — Layer 02 (The Stack, global rooms 7-12: rectangular-only,
grid-ish, History arc) added to LayerCatalog, and RunDirector plays a `DESCENDING //
THE STACK` beat when a campaign crosses a layer boundary; endless never descends;
covered by `tools/descent_test.tscn`. **Pass 5b (lobby mode selector) shipped** — a
code-built `ModeToggle` station lets the player pick CAMPAIGN (default) vs ENDLESS;
it pushes the mode live to RunManager only on interact and `_ready` never touches it,
so the endless-default harnesses are unaffected; covered by
`tools/mode_select_test.tscn`. **The full Heap track (Passes 1-5b) is done.**
**Navigable verticality V1 + V2 (player-traversable) shipped** — RoomBuilder gained
`_build_platform()` (a solid mesa) + `_build_ramp()`; they make solid world
geometry the *player* climbs via physics, with enemies staying grounded (baking
navmesh ONTO platforms does NOT work out-of-the-box here — a Recast tuning matter
left for later; see `verticality_plan.md`). **V2** turns those builders into an
opt-in `tiers` layout archetype (flagged `vertical`, so it never appears in the
endless rotation — only when a layer profile's `archetype_pool` lists it):
`_build_tiers()` raises 2–3 perimeter platforms with inward ramps + high cover,
runs first in the build loop so the ground scatter avoids the mesa bases, and the
existing reachability validation keeps the ground fully enemy-navigable. **Wired into
The Stack** (layer 2 / global rooms 7–12): its `archetype_pool` now lists `tiers`, so
CAMPAIGN runs meet vertical rooms there (thematically apt — the Stack is literally a
stack). Other layers can opt in the same one-line way. **V3** gives the player a
reason to climb: the builder records one elevated reward spot per platform cap
(`get_high_reward_points()`) and RunDirector drops a bonus premium pickup
(health/armor) on each — an EXTRA pickup beyond the room's snapshot set, sitting
above the navmesh where grounded enemies can't reach, so the high ground is a real
player-only payoff. Covered by `tools/verticality_test.tscn` (V1) +
`tools/tiers_test.tscn` (V2) + `tools/tiers_reward_test.tscn` (V3).
**Per-layer materials + lighting (layer identity) shipped** — each layer now resolves
its OWN floor/wall/struct surface materials + depth fog + ambient (Heap = murky
green-gray surfaces + sickly green haze + dim; Stack = clean steel-blue + faint cool
haze + bright), so the layers read as different PLACES rather than the same gray box
under a different sun tint. `RoomBuilder._resolve_palette()` (cached per layer id) +
`_apply_environment()`; ENDLESS keeps the authored gray materials + fog-off
environment byte-for-byte. The toon shader carries the per-layer albedo through.
Covered by `tools/layer_look_test.tscn`; eyeballed via `tools/layer_look_preview.tscn`.
All headless harnesses stay green (script/base/run/heap/heap-rooms/fragment/
heap-ghost/descent/mode-select/verticality/tiers/tiers-reward/layer-look/rusher/sniper/grenadier/aim-evasion/
dodge/ragdoll-polish/l-room/ragdoll/elite/menu/transition/lobby/movement/
weapon-clip/bullet-fx).
Deferred/ideas:
squad coordination (focus fire, bounding overwatch, regroup on ally death);
surface-dependent impact effects (per-material decal/spark);
spawn telegraphing VFX,
remaining audio passes (footsteps, reload, pickups, UI, music, volume sliders);
movement playtest tuning (`momentum_*` ramp, whether auto-vault-on-jump near
crates feels too eager).

# Aware — Architecture & Invariants (always include this file in every prompt)

A first-person shooter in **Godot 4.6.3 / GDScript** (Jolt physics, Forward+, D3D12
on Windows). An arena combat base game with a **roguelite run system** layered on
top. Editor binary: `V:\Apps\Godot_v4.6.3\Godot_v4.6.3.exe`.

## Core principle
New systems are built **alongside** the existing scripts, never rewriting them.
The roguelite layer takes over the game flow at runtime (via signal
disconnects) rather than editing the original FPS code.

---

## Base game architecture

- **`scenes/main.tscn`** — root scene. Driven by `game_manager.gd` (node name
  `Main`). Contains: `NavRegion` (CSG arena geometry, runtime-baked navmesh),
  `CoverPoints` (16 markers, group `cover_point`), `EnemySpawns` (5 markers,
  group `enemy_spawn`), `Pickups`, `PlayerSpawn`, `Player`, `HUD`, and now
  `RunHUD` + `RunDirector`.
- **One original autoload: `GameEvents`** (`autoloads/game_events.gd`) — global
  signal bus. All cross-system communication goes through here so player,
  weapons, enemies, HUD and managers never reference each other directly.
- **Player** (`scripts/player/player.gd`, `class_name Player`,
  CharacterBody3D) — FPS controller: movement states (walk/sprint/crouch/prone/
  slide/**wall-run**/**vault**), stamina, camera bob, health/armor/regen, death. Also a
  **double jump** (air jump while airborne, `max_air_jumps` charges, refilled on
  ground/wall contact). Armor soaks 30% of incoming damage. `try_pickup(kind, amount)`
  facade (0=ammo, 1=health, 2=armor). Weapons live in a child `WeaponManager`; active
  hotkey abilities in a child `AbilityManager` (sibling of `PlayerUpgrades`). See
  **Advanced movement** below for wall-run.
- **AbilityManager** (`scripts/player/ability_manager.gd`, `class_name AbilityManager`)
  — child of Player. Active, cooldown-only **hotkey abilities** unlocked in-run via the
  upgrade-card flow: `PlayerUpgrades.apply_upgrade` routes any non-stat id to
  `grant(id)` (first grant equips into a free slot, repeats rank up). Reads/writes the
  player's public state from the outside (no player.gd reference). **Multi-slot:**
  `MAX_SLOTS` (2) independent slots, each its own hotkey (`ability` F / `ability_2` G)
  and cooldown; the slot-indexed `ability_*` GameEvents signals let the RunHUD
  `AbilityBar` show one ring per slot. Abilities: **Stack Smash** (airborne ground-pound
  → AoE via enemy `BodyHitbox.take_hit`) and **Overclock** (slows every enemy via their
  `ai_time_scale`). Full design in `abilities_plan.md`.
- **HackManager** (`scripts/player/hack_manager.gd`, `class_name HackManager`) — child of
  Player (sibling of AbilityManager), the **environment-hacking** system: a camera raycast
  (world layer) finds the aimed `Hackable` prop; `try_hack(id)` injects an *adjective*
  whose `TraitInstance` (`scripts/world/trait_instance.gd`) snapshots the host body's
  physics state, mutates it, and restores it byte-for-byte on auto-decay (no permanent
  world mutation). **Objects only** — effects route through `BodyHitbox.take_hit`, so
  `enemy_ai.gd` is untouched. The player **holds `hack` to open a radial selector wheel**
  (`scripts/ui/hack_wheel.gd`, owned by HackManager in its own CanvasLayer): the aimed prop
  locks, slow-mo, mouse-flick/scroll picks an adjective, release injects it (look + weapon
  input suppressed via `_input` consumption, no player.gd edit). `RoomBuilder` seeds frozen
  `Hackable` cubes into generated rooms. Hackable props (`scripts/world/hackable.gd`, group
  `hackable`) are frozen RigidBody3Ds. Adjectives fall into archetypes: **mutate-body**
  (**Heavy** releases one under heavy gravity to crush enemies beneath it) and
  **attach-effect-node** (**Shocking** bolts a `ShockField` to the host that pulses
  `take_hit` to nearby enemies without touching the body; `TraitInstance._effect_node` is
  freed on expire). A **RAM** pool gates hacking (`ram_cost` to
  inject + `ram_upkeep`/sec while live, always regenerating; overdrawing collapses the
  oldest trait), surfaced by the `RunHUD` `RamMeter` via `ram_changed`. Reads player state
  from the outside (no player.gd reference), like AbilityManager. RunDirector freezes it +
  `clear_all()`s live traits on transition. Full design in `hacking_plan.md`.
- **WeaponManager** (`scripts/weapons/weapon_manager.gd`, `class_name
  WeaponManager`) — under the player camera. 3 weapons from preloaded
  `WeaponData` .tres (`data/weapons/`), hitscan firing, recoil, ADS, rig
  animation. Reads exported stats off the WeaponData resources.
- **EnemyAI** (`scripts/enemies/enemy_ai.gd`, `class_name EnemyAI`,
  CharacterBody3D) — state machine PATROL/ALERT/CHASE/ATTACK/SEARCH/COVER/FLANK/
  DEAD. NavigationAgent3D pathing, vision-cone + hearing senses. `enemy_died`
  signal. Health via child `HealthComponent`; damage via `HitboxComponent`
  areas (head = 2.0 multiplier for headshots). **Death ragdoll:** `_die` hands the
  `Visual` meshes to a `RigidBody3D` corpse (group `enemy_corpse`) launched away
  from the shooter with lift + tumble, that rests on the world (collision_layer 0
  / mask = world, so it never nudges the player), then shrinks out and frees
  itself; the now-empty husk frees shortly after. Enemies are primitive-mesh (no
  skeleton), so one rigid body reads as a ragdoll. **Polished:** the corpse is
  launched along the actual bullet direction (recorded per-shot via
  `HitboxComponent.register_hit` BEFORE damage, since death is synchronous) and the
  impulse is applied AT the hit point, so where you hit shapes the tumble; a
  **headshot pops the head off** as its own rigid body, and the **gun always drops**
  as a separate tumbling piece (both join the `enemy_corpse` group). RunDirector
  clears the group on room transition. Covered by `tools/ragdoll_smoke_test.tscn` +
  `tools/ragdoll_polish_smoke_test.tscn` + `tools/ragdoll_preview.tscn`. **Deletion VFX
  (on by default):** in real play this ragdoll is the SUBSTRATE for a computer-world
  "deletion" look — the `DeletionVFX` autoload hooks `enemy_died`, freezes the corpse
  pieces (cancelling the launch impulse → vanish in place) and glitch-dissolves them out
  (`enemy_ai.gd` untouched). The two ragdoll harnesses set `DeletionVFX.enabled = false` to
  test the raw physics; see *Enemy death: deletion VFX* in `context_systems.md`.
  **Archetype hooks:**
  off-by-default `is_sniper` / `is_grenadier` flags swap the ATTACK state for a
  charged telegraphed long-range shot (`_sniper_attack`) or an arcing-grenade lob
  (`_grenadier_attack`); a regular enemy leaves both false and behaves exactly as
  before. See *Enemy archetypes*. **Combat fairness:** enemy aim widens while the
  player pulls movement tricks, and aware agile enemies reactively dodge player
  shots that whiz past. See *Enemy combat fairness*. **Time dilation:** an off-by-default
  `ai_time_scale` (1.0 = normal) scales the whole `_physics_process` delta + locomotion,
  so the player's **Overclock** ability can slow every enemy without touching the player.
- **HUD** (`scripts/ui/hud.gd`, CanvasLayer) — vitals bars, ammo, kill feed,
  damage vignette, crosshair. Listens to GameEvents only. **Unmodified** by the
  roguelite layer.
- **Pickups** (`scripts/pickups/pickup.gd`, `class_name Pickup`, Area3D) —
  ammo/health/armor, self-building visuals, respawn after a delay.

---

## Conflict resolution with GameManager
`game_manager.gd` is **untouched**. Its 3-lives respawn and one-shot `game_won`
flow contradict infinite-room permadeath, so RunDirector disconnects those two
signal handlers at runtime and takes over. GameManager still performs the
navmesh bake and initial enemy spawn exactly as before, then goes dormant.

---

## Verification (headless harnesses in `tools/`)
Run order matters — rebuild the class cache first after adding `class_name`
scripts. On Windows the Godot exe detaches from the console, so use
`Start-Process -Wait -PassThru` and read `.ExitCode`.

1. `--headless --path . --import` — rebuilds import + class cache.
2. `res://tools/script_check.tscn` — loads every .gd/.tscn/.tres → `CHECK_OK`.
3. `res://tools/smoke_test.tscn` — base integration test → `SMOKE_OK`.
4. `res://tools/run_smoke_test.tscn` — full roguelite loop test → `RUN_SMOKE_OK`.
   Now drives each room-clear through the **exit gate**: asserts the gate spawns
   and the tree stays live (no auto-transition), then teleports the real player
   onto the gate to fire its Area3D `body_entered` (with a signal-emit fallback)
   so the freeze/upgrade flow begins. Helper: `_pass_through_gate`.
5. `res://tools/menu_smoke_test.tscn` — menu + settings test → `MENU_SMOKE_OK`
   (snapshots & restores the real user://settings.cfg so runs never pollute it).
6. `res://tools/elite_smoke_test.tscn` — milestone room test → `ELITE_SMOKE_OK`
   (fast-forwards by setting `RunManager.current_room = 4` during the first
   upgrade pick so the pending advance lands on milestone room 5). Drives the
   room-1 and milestone clears through the exit gate via `_pass_gate` (emits the
   gate's `player_entered`, like its other emit-driven steps).
7. `res://tools/transition_smoke_test.tscn` — full scene-swap test →
   `TRANSITION_OK` (menu→PLAY→lobby→START RUN→main→death→Try Again reload→
   death→Main Menu). The test node lives under `root` (not as current_scene)
   so it survives the swaps; it loads sub-scenes with a deferred add_child +
   settle frame, else adding during `_ready` throws a harness-only "parent
   busy" error cascade.
8. `res://tools/lobby_smoke_test.tscn` — 3D lobby + meta progression test →
   `LOBBY_SMOKE_OK` (Area3D proximity: walks the player onto a pedestal and
   reads `_current_station`; worldspace `_interact` buy persists to
   user://meta_progress.cfg; armed run bonuses land on a fresh Player while
   unarmed players stay vanilla; permadeath payout 10/room +50/milestone).
   Snapshots & restores the real meta_progress.cfg values.
9. `res://tools/movement_smoke_test.tscn` — wall-run + dash + vault + momentum +
   double jump test → `MOVEMENT_SMOKE_OK`. Builds a floor + one wall, drives the real player.tscn
   with `Input.action_press`. Wall-run: enters `WALLRUN` with reduced `velocity.y`
   decay, `jump` launches off (away + up) and exits, cooldown blocks same-wall
   re-entry. Dash: a charge is spent and speed jumps to ~`dash_speed` on the
   ground; charges exhaust to 0 then block; recharge over time (crank
   `dash_recharge_time` down); air-dash bursts horizontally while still falling.
   Vault: jumping into a 1.4 m crate enters `VAULT` and lands the player past the
   far face; a 3 m wall is correctly rejected (no vault). Momentum: running
   forward smoothly for ~1.5 s builds `momentum` > 0.3 and lifts speed above base
   walk; stopping decays it back down. Double jump: an airborne `jump` with a charge
   left (`_air_jumps_left`) pops `velocity.y` upward and decrements; with charges
   exhausted a further air jump does nothing; landing refills to `max_air_jumps`.
10. `res://tools/weapon_clip_smoke_test.tscn` — weapon wall-clip fix test →
    `WEAPON_CLIP_SMOKE_OK`. Instances the real (process-disabled) player.tscn and
    asserts the render-on-top material setup: the current weapon's body + barrel
    meshes draw without a depth test (swapped to `toon_viewmodel.gdshader`, or
    `no_depth_test` on a StandardMaterial3D fallback) while keeping their outline
    `next_pass`, and the muzzle flash material has `no_depth_test` set. (Shaders
    don't compile headless, but the shader/flag assignment is plain resource data;
    the *look* is eyeballed via `tools/weapon_clip_preview.tscn`.)
11. `res://tools/glitch_smoke_test.tscn` — upgrade-card glitch driver test →
    `GLITCH_SMOKE_OK`. Instances run_hud, shows the cards and asserts the overlay
    uniforms track the three states: idle `base_intensity` on show, `focus_intensity`
    → HOVER on `mouse_entered`, a >0.8 spike on `button_down`, and both cleared to
    0 on hide. (The shader look itself is eyeballed via `tools/glitch_preview.tscn`.)
12. `res://tools/bullet_fx_smoke_test.tscn` — bullet tracers + impact decals test →
    `BULLET_FX_SMOKE_OK`. Drives `BulletFX` through the `GameEvents` bus and counts
    the grouped nodes it spawns into the current scene: a `bullet_tracer` spawns one
    tracer (a sub-muzzle-length one is skipped), a `bullet_impact` spawns one decal,
    and blasting past `MAX_DECALS` caps the decal count (oldest recycled). (The look
    is eyeballed via `tools/bullet_fx_preview.tscn`.)
13. `res://tools/rusher_smoke_test.tscn` — Rusher enemy archetype test →
    `RUSHER_SMOKE_OK`. Pure layer: `RunManager.rusher_count_for_room` curve
    (none before room 3 / in milestones, ramps with depth, capped, deterministic).
    Scene layer: fast-forwards to room 3 (like elite_smoke does to room 5) and
    inspects the spawned rusher vs a plain squadmate — 1.6x speed, 6 m attack range,
    huge mag, 0 cover threshold, wide burst, 0.7x health, 0.75x per-pellet damage,
    leaner orange look (reads the toon shader's `albedo` uniform, since
    ToonApplicator has swapped material_override by then) + matching narrowed
    hitbox — and confirms it engages the player on sight. (Look eyeballed via
    `tools/rusher_preview.tscn`.)
14. `res://tools/sniper_smoke_test.tscn` — Sniper enemy archetype test →
    `SNIPER_SMOKE_OK`. Composition curve (`sniper_count_for_room`: none before
    room 4 / in milestones, capped at 2, never overlaps the rusher slots), then
    fast-forwards to room 4 and inspects the sniper vs a plain squadmate (far
    sight/range, tight aim, 3x damage, 0.85x health, cyan taller look + hitbox).
    Behaviour: on a tiny floor lofted above the room (clean LoS, no fall) it
    telegraphs a beam, does NOT fire instantly (charge delay), then lands its
    locked shot on a stationary player. GOTCHA shared with the rusher test: widen
    the enemy's `sight_half_fov_deg` to 360 before the behaviour loop, else PATROL
    wander re-faces the enemy and the player falls out of the vision cone (flaky).
    (Look + beam eyeballed via `tools/sniper_preview.tscn`.)
15. `res://tools/grenadier_smoke_test.tscn` — Grenadier enemy archetype test →
    `GRENADIER_SMOKE_OK`. Composition curve (`grenadier_count_for_room`: none
    before room 6 / in milestones, capped at 2, all three archetype slots together
    leave plain enemies), then fast-forwards to room 6 and inspects the grenadier
    vs a plain squadmate (attack range 20, 3x AoE blast, 1.15x health, bulky olive
    look + widened hitbox). Behaviour: on the lofted test floor it winds up, spawns
    a grenade (group `enemy_grenade`) that arcs + explodes, and the blast damages a
    player standing on the spot. (Look + danger ring eyeballed via
    `tools/grenadier_preview.tscn`.)
16. `res://tools/aim_evasion_smoke_test.tscn` — movement-trick aim fairness →
    `AIM_EVASION_OK`. A pure unit test (no navmesh): pokes a frozen player's
    `move_state` / `_dash_time_left` / `momentum` and asserts
    `EnemyAI._player_evasion_spread()` returns the right extra spread per trick,
    that they stack, that momentum scales linearly, and that a missing player
    yields 0 (no crash).
17. `res://tools/dodge_smoke_test.tscn` — reactive dodge → `DODGE_SMOKE_OK`. In a
    code world (floor + frozen player + one enemy), emits `bullet_tracer` and reads
    the enemy: an aware enemy jukes a near shot and translates sideways, the
    cooldown blocks an immediate second dodge, and the four no-dodge cases hold
    (far shot, enemy-origin shot, sniper, patrolling/unaware).
18. `res://tools/ragdoll_polish_smoke_test.tscn` — death-ragdoll polish →
    `RAGDOLL_POLISH_OK`. In a code world (floor + frozen player to the -Z + two
    enemies), uses instance-id tracking on the `enemy_corpse` group: a body shot
    traveling +X spawns a body corpse + a dropped gun and the body flies +X (not the
    +Z "away from shooter" fallback); a headshot spawns body + gun + a detached head
    that pops upward, leaving the body corpse headless and disarmed. (`ragdoll_smoke`
    updated for the +gun count; `run_smoke` asserts corpses are cleared on
    transition. Look eyeballed via `tools/ragdoll_preview.tscn`, now a headshot.)
19. `res://tools/heap_smoke_test.tscn` — layered-world Pass 1 (layer backbone +
    Heap re-skin) → `HEAP_SMOKE_OK`. Pure: `LayerCatalog` maps global rooms 1-6 to
    the Heap (layer 1, sector == room) and clamps rooms past the catalog. State:
    ENDLESS leaves `current_layer`/`room_in_layer` at 0 and `active_layer_profile()`
    empty (legacy path untouched); CAMPAIGN tracks the layer/sector. Re-skin: a
    room built with the Heap profile draws its archetype from the Heap pool, sizes
    to a Heap-biased footprint (no compact/standard square), and the sun takes the
    cold/dimmed Heap mood; the RunHUD room label reads "HEAP - SECTOR n", not
    "ROOM n". Endless stays flat (run_smoke still green). See *Layered world* in
    `context_systems.md`.
20. `res://tools/heap_rooms_test.tscn` — layered-world Pass 2 (Heap room-type
    taxonomy) → `HEAP_ROOMS_OK`. Pure: the Heap `room_sequence` maps sectors to
    types (3 = Fragment, 5 = Ghost, rest Combat); ENDLESS is always Combat;
    CAMPAIGN suppresses the every-5th milestone while ENDLESS keeps it. Scene: a
    real CAMPAIGN run clears a built COMBAT room 2 (a scaled 6-enemy squad spawns,
    no narrative marker) then reaches the FRAGMENT room 3 — zero enemies, the exit
    gate already up on arrival, a `fragment_room`/`narrative_marker` placeholder
    dropped, and real geometry still built. See *Layered world* in
    `context_systems.md`.
21. `res://tools/fragment_test.tscn` — layered-world Pass 3 (Fragment system) →
    `FRAGMENT_OK`. Pure: `FragmentDB` reveals the Awakening arc in order
    (`pick_for_arc` returns the first uncollected entry, advances as they're
    collected). Scene: a CAMPAIGN run reaches the Fragment room (sector 3) where a
    real `MemoryFragment` (Area3D, group `fragment_room`) sits; walking the player
    into it records the fragment (FragmentDB, persisted), fires
    `GameEvents.fragment_read`, and shows it in the `FragmentReader` overlay.
    Snapshots + restores `user://fragments.cfg` so real progress is untouched. See
    *Layered world* in `context_systems.md`.
22. `res://tools/heap_ghost_test.tscn` — layered-world Pass 4 (Heap gen identity)
    → `HEAP_GHOST_OK`. Pure: the Heap profile carries `corruption` + a `ghost_tint`
    and sector 5 is a Ghost room. Builder: a built COMBAT Heap room spawns floating
    atmosphere debris (group `room_debris`, decorative/no-collision) but no ghost
    geometry; a built GHOST room spawns MORE debris, tags spectral geometry (group
    `ghost_geometry`), and pulls the sun mood toward the ghost tint. The
    translucent/emissive look itself is eyeballed by playing a campaign to sector 5.
    See *Layered world* in `context_systems.md`.
23. `res://tools/descent_test.tscn` — layered-world Pass 5a (Heap -> Stack descent)
    → `DESCENT_OK`. Pure: a second layer (The Stack) exists; global rooms 7..12 map
    to it (sector 1 at room 7), the Heap/Stack boundary is right, the Stack is
    rectangular-only and surfaces the History fragment arc. Scene: a CAMPAIGN run
    crossing the Heap's last sector descends -- `current_layer` ticks to 2, the
    active profile becomes the Stack, the HUD reads STACK, and the built room uses a
    Stack archetype + rectangular shell. See *Layered world* in `context_systems.md`.
24. `res://tools/mode_select_test.tscn` — layered-world Pass 5b (lobby run-mode
    selector) → `MODE_SELECT_OK`. The lobby builds a `ModeToggle` Area3D station in
    code; the run selection defaults to CAMPAIGN, the lobby's `_ready` does NOT
    touch `RunManager.selected_mode` (so the endless-default harnesses stay valid),
    and interacting with the station (real Area3D proximity) flips the mode live on
    RunManager (CAMPAIGN <-> ENDLESS) with the label tracking it. `start_run()`
    applies the selection as a backstop. See *Layered world* in `context_systems.md`.
25. `res://tools/verticality_test.tscn` — navigable verticality V1 (player-traversable)
    → `VERTICALITY_OK`. RoomBuilder's `_build_platform()` (a solid mesa) + `_build_ramp()`
    make solid, grouped world geometry; the test proves the player physically rests
    on the platform top (collision, no fall-through/slide-off), the ramp slope is
    climbable, and the room stays ENEMY-navigable on the ground (platforms don't make
    any enemy spawn unreachable). NOTE: baking navmesh ONTO platforms does NOT work
    out-of-the-box here (a Recast tuning matter) — so enemies stay grounded and the
    player owns the high ground; see `verticality_plan.md`.
26. `res://tools/tiers_test.tscn` — navigable verticality V2 (the "Tiers" layout
    archetype) → `TIERS_OK`. Pure: a `tiers` archetype is registered and flagged
    `vertical`, so it's opt-in only — `_pick_archetype` NEVER returns it in the
    endless room-gated rotation (it leaks into endless only if a profile's
    `archetype_pool` lists it). Scene: forcing it via `{"archetype_pool": ["tiers"]}`
    builds a room that validates OK (so the solid mesa platforms did NOT wall off the
    ground), generates ≥1 platform (`room_platform`) + ramp (`room_ramp`) + elevated
    high cover (`room_high_cover`, y > 1.6) all solid (collision_layer 1) within
    bounds, spawns a real ground squad with every spawn reachable from the player
    spawn, and reproduces the same platform count for a fixed seed. Tiers is built
    BEFORE the ground scatter so `_try_place`'s new footprint check keeps crates off
    the mesa bases (a no-op for non-vertical archetypes — `_footprints` is empty then).
    Wired into The Stack (layer 2): the pure section asserts `tiers` is in the Stack's
    `archetype_pool` and absent from the Heap's; the scene build uses the Stack's
    rectangular footprint pool; `descent_test` builds a real Stack room against the
    live pool. Eyeballed by playing a CAMPAIGN run into the Stack (global rooms 7-12).
27. `res://tools/tiers_reward_test.tscn` — navigable verticality V3 (player-only
    rewards on the caps) → `TIERS_REWARD_OK`. The builder records one elevated reward
    spot per Tiers platform cap (`get_high_reward_points()`, empty for every other
    archetype) and `RunDirector._spawn_high_rewards()` drops a bonus pickup on each —
    the player's payoff for climbing (enemies stay grounded, so they can't contest
    it). Asserts: a plain room reports zero reward points (no-op elsewhere); a forced
    tiers room reports ≥1, each elevated (y > 1.6), in bounds, and sitting ABOVE the
    navmesh (the nearest nav point is ≥1 m below the cap — proving a grounded agent
    can't stand there, i.e. genuinely player-only); and the director spawns exactly
    one premium (HEALTH/ARMOR) pickup per cap, floating at cap height. These bonus
    pickups are EXTRA, beyond the room's snapshot set, so the normal pickup balance is
    untouched. Look eyeballed by climbing a cap in a CAMPAIGN Stack run.
28. `res://tools/layer_look_test.tscn` — per-layer materials + lighting (layer
    identity) → `LAYER_LOOK_OK`. Each narrative layer should read as a distinct
    PLACE, not just a differently-tinted gray box. Palette: `RoomBuilder._resolve_
    palette(profile)` resolves a layer's own floor/wall/struct materials from its
    `floor_color`/`wall_color`/`struct_color` (Heap != Stack != the legacy gray),
    while an empty profile (ENDLESS) returns the authored gray materials byte-for-byte.
    Environment: `_apply_environment(profile, ghost)` turns on the layer's depth fog
    (`fog_color`/`fog_density`) + `ambient_energy`, and an empty profile restores the
    authored fog-off environment. Render: the Heap is now KIT-skinned (the layer enables
    `"kit"`), so section C asserts the kit floor overlay (`GeneratedShell/KitFloor`) carries
    the Heap floor colour (colormap x palette tint) while the gray collision Floor survives
    underneath with its mesh hidden -- the build-alongside invariant. (`_albedo_of` reads
    either a toon ShaderMaterial `albedo` uniform or a StandardMaterial3D `albedo_color`.)
    The actual look is eyeballed via `tools/layer_look_preview.tscn`
    (renders the real kitted Heap + Stack rooms to PNGs, NON-headless). NOTE: `tools/layout_diag.tscn`
    is a non-asserting diagnostic that dumps the archetype + footprint picked per room
    per mode — handy for confirming generation variety.
29. `res://tools/dev_tools_test.tscn` — developer/playtest helpers → `DEV_TOOLS_OK`.
    Drives the `DevTools` autoload's actions directly (no key input): god mode raises
    the player's maxima so a lethal-sized `take_damage` does NOT kill + toggling off
    restores the authored maxima; `_refill()` tops health/armor/ammo back up;
    `_kill_all_enemies()` routes lethal `BodyHitbox.take_hit` calls so every enemy
    dies through the normal death path (which the room-clear/exit-gate flow keys off).
    Jump: `_layer_start_rooms()` == [1, 7] (Heap/Stack), and `RunDirector.dev_jump_to_room(8)`
    warps straight to room 8 (counter lands on 8, run stays active, tree unpauses, a
    fresh squad spawns) via the shared `_enter_next_room()` pipeline that the real gate
    transition also uses. See **Developer tools** in `context_systems.md`.
30. `res://tools/ability_smoke_test.tscn` — active abilities Pass 1 (AbilityManager +
    Stack Smash) → `ABILITY_SMOKE_OK`. Grant: the first `grant("stack_smash")` equips at
    rank 1 and leaves it ready, a repeat ranks up to 2 and shortens `_cooldown_total`, a
    non-ability id is rejected (so `PlayerUpgrades` still warns on a truly unknown id).
    Cast: in a code world (floor + two inert real enemies via `sight_range=0` +
    process-off + the LIVE player.tscn), an airborne `ability` press drives the player
    down and, on landing, deals AoE damage to the in-radius enemy (through
    `BodyHitbox.take_hit`) while leaving the out-of-radius enemy untouched, and arms the
    cooldown (emitting `ability_used`). Cooldown: blocks a recast even while airborne,
    then ticks down to ready. Holds the `ability` action across a few physics frames to
    catch the just_pressed edge (same trick as movement_smoke's `_do_dash`). Unlocked
    in-run via the upgrade card flow; full design in `abilities_plan.md`.
31. `res://tools/ability_hud_test.tscn` — active abilities Pass 2 (RunHUD ability
    widget) → `ABILITY_HUD_OK`. Instances `run_hud.tscn` and drives the `AbilityWidget`
    (`scripts/ui/ability_widget.gd`, a self-contained custom-drawn radial cooldown ring)
    through the `GameEvents` ability_* signals: hidden until `ability_granted` (then
    visible with the key glyph = the live `ability` bind "F" and the ability name), a
    full-remaining `ability_cooldown_changed` reads on-cooldown, `ability_used` pulses,
    and a 0-remaining change reads ready again. **Multi-slot (P4):** also asserts the
    slot-indexed signals route independently — granting slot 1 reveals the SECOND widget
    (`AbilityBar/Slot1`, key glyph "G" / `ability_2`) while slot 0 is untouched. The ring
    look itself needs a real renderer (eyeballed in play); this asserts the signal-driven
    state, the `glitch_smoke` way. RunHUD stays decoupled (GameEvents only) — no
    AbilityManager reference.
32. `res://tools/overclock_test.tscn` — active abilities Pass 3 (Overclock time-dilation)
    → `OVERCLOCK_OK`. Hook proof: `EnemyAI.ai_time_scale` (off-by-default 1.0) scales the
    whole AI update — a slowed enemy's delta-driven `_dodge_cooldown` bleeds down
    ~quarter-speed vs a control at 1.0. Ability: `AbilityManager.grant("overclock")` equips
    it (castable on the ground, no airborne requirement); an `ability` press holds every
    live enemy's `ai_time_scale` at the rank-scaled slow factor for the duration (emitting
    `ability_used` + arming the cooldown), then releases them all to 1.0 on expiry. Code
    world (floor + live player + real `sight_range=0` enemies); no navmesh.
33. `res://tools/hack_smoke_test.tscn` — environment hacking Pass 1 (HackManager +
    Hackable + TraitInstance + Heavy) → `HACK_SMOKE_OK`. Pure: `HackManager.CATALOG` has
    `heavy`, and a `TraitInstance` apply → expire round-trips the host body's mass / freeze
    / collision layer (snapshot/restore, no permanent mutation). Scene (code world: floor +
    the LIVE player.tscn + a frozen-RigidBody `Hackable` cube placed dead-centre in the
    camera ray + an inert enemy `sight_range=0`/process-off beneath it + a control enemy to
    the side): `current_target()` finds the aimed cube's Hackable, `unlock("heavy")` then
    `try_hack("heavy")` releases it (emits `trait_applied`), it falls and crushes ONLY the
    enemy under it (proximity + "below" → `BodyHitbox.take_hit`), aiming away yields no
    target + a no-op hack, and cranking the timer down decays the trait → the cube reverts
    to its snapshot (re-frozen, mass/layer restored, host's `active_trait` cleared, emits
    `trait_expired`). GOTCHA: a frozen RigidBody3D ignores a `global_position` set AFTER
    `add_child` (stays at the physics-server origin) — set the spawn transform BEFORE adding
    it to the tree. See **Environment hacking** / `hacking_plan.md`.
34. `res://tools/hack_ram_test.tscn` — environment hacking Pass 2 (RAM meter + HUD bar) →
    `HACK_RAM_OK`. `HackManager` gains a RAM pool (`ram_max`/`ram_regen` + per-adjective
    `ram_cost`/`ram_upkeep`): a hack spends `ram_cost` + emits `ram_changed`; with regen
    throttled below upkeep a live trait bleeds RAM to empty and the OLDEST force-expires
    (overdraw detected via `raw < 0`, robust to float settling); idle RAM regenerates; a
    hack below `ram_cost` is refused (no trait). The `RunHUD` `RamMeter` (label + styled
    `ProgressBar`) tracks `ram_changed` and reveals on the first `trait_applied`
    (GameEvents-driven, the `ability_hud` way). GOTCHA: `ram_changed` is global, so the
    test freezes the live HackManager (`set_physics_process(false)`) before asserting on
    manually-emitted values, else its per-frame emits overwrite them.
35. `res://tools/hack_shock_test.tscn` — environment hacking Pass 3 (Shocking, the
    attach-effect-node archetype) → `HACK_SHOCK_OK`. Unlike Heavy (mutate-body), Shocking
    attaches a `ShockField` (`scripts/world/shock_field.gd`, a Node3D) to the host that
    pulses `take_hit` to enemies in radius on its own timer (group-proximity, no Area3D
    overlap); `TraitInstance._effect_node` is freed in `expire()` before the (no-op) body
    restore. Scene (floor + live player + a frozen `Hackable` panel in the camera ray + an
    enemy inside the shock radius + one well outside): hacking the panel attaches the
    `ShockField` and leaves the host frozen + in place (NOT mutated), the field damages only
    the in-radius enemy over time, and on decay the `ShockField` is removed and the host is
    unchanged. RAM: cost 30 / upkeep 8.
36. `res://tools/hack_select_test.tscn` — environment hacking Pass 4 (selector wheel +
    targeting highlight + RoomBuilder seeding) → `HACK_SELECT_OK`. HOLD `hack` opens a radial
    wheel (`scripts/ui/hack_wheel.gd`, `HackWheel`, a custom-drawn Control owned by
    HackManager in its own CanvasLayer -- shows in runs AND the sandbox, no HUD edit); the
    aimed Hackable LOCKS, the world dips into slow-mo, mouse-flick / scroll picks a wedge
    (consumed in `HackManager._input`, before the player's `_unhandled_input`, so look +
    weapon-switch are suppressed with NO player.gd edit), release `_inject`s the picked
    adjective into the LOCKED target. `Hackable.set_highlighted()` glows the aimed prop;
    `RoomBuilder._seed_hackables()` drops 2-3 frozen `Hackable` cubes per room (overhead,
    post-bake, so they never block spawns/pathing). The test asserts: a built room seeds ≥1
    `hackable`; `_index_for_flick` maps flicks to wedges (tiny → none); aiming highlights a
    hackable + aiming away clears it; holding opens the wheel with the unlocked set + locks
    the target; cycling moves the pick; releasing injects the PICKED adjective into the
    LOCKED target even after aiming away. Wheel look eyeballed; the driver asserts the state
    machine (`glitch_smoke` way).
37. `res://tools/hack_progression_test.tscn` — environment hacking Pass 5 (progression) →
    `HACK_PROGRESSION_OK`. Cores unlock the WORD permanently: `MetaProgression` gains
    `hack_heavy`/`hack_shocking` (one-time `max_level` 1, tagged `"kind":"adjective"`); the
    lobby builds buy pedestals in code (`_build_hack_stations`); `_apply_hacks` unlocks owned
    adjectives on an armed-run player's HackManager. In-run cards RANK it: `"kind":"trait"`
    cards (ids = adjective ids) in `RunManager.UPGRADE_POOL`, routed by `PlayerUpgrades`'s
    fallback to `hack_manager.rank_up` (first pick grants rank 1, repeats rank up). Test
    (snapshots `meta_progress.cfg`): a buy persists + maxes the unlock; an armed player gets
    the owned word while an unarmed one stays vanilla; a trait card grants then ranks Heavy;
    a non-adjective id is rejected.
38. `res://tools/shape_contrast_test.tscn` — procgen variety lever "stronger shape
    contrast" → `SHAPE_CONTRAST_OK`. The rectangular `FOOTPRINTS` pool was widened from
    medium rects into a deliberate spread: a **tight** close-quarters chamber (14x14),
    **corridors** (28x11 / 11x28, ~2.5:1), and a **grand** arena (30x28), plus a bold deep
    L. Pure: the new classes exist; the combined-list index split still holds (rect indices
    have zero notch, L indices are notched); the endless picker's area spread genuinely
    widened (a tight room AND a grand room appear, max/min area ≥ 4x, ≥10 classes); and the
    layer pools point at the right SHIFTED indices (Heap skips the small/standard/tight
    squares 0/1/6 but keeps corridors+grand+L; Stack stays rectangular-only and gained the
    new rects). Scene: each new footprint is forced through the REAL `build_room` via a
    single-index `footprint_pool` and must validate OK (navmesh bakes, reachable squad +
    cover fit) — proving they're playable, not just data. **GOTCHA carried in the code:**
    `footprint_pool` values index the COMBINED `[FOOTPRINTS + L_FOOTPRINTS]` list, so new
    rectangles MUST be appended (never inserted) or every L-shape index in `LayerCatalog`
    silently shifts; `descent_test` derives the rect/L boundary from `FOOTPRINTS.size()`
    rather than hardcoding it. `maze_lanes` now runs its walls along the LONG axis in
    corridors so long walls don't choke a narrow axis.
39. `res://tools/t_room_test.tscn` — stronger shape contrast Pass 2 (the T-shaped
    footprint family) → `T_ROOM_OK`. A T is the L generalised: an L is one north-corner
    notch, a T is BOTH north corners, leaving a wide south crossbar (player spawn) + a
    narrow north stem (the exit gate). The notch system is now a LIST (`_notches`: rect=0,
    L=1, T=2) so `_in_notch` covers every bare corner uniformly; `_notch`/`_notch_min/_max`
    still mirror the first notch for the single-notch L tests (`l_room`, `run_smoke`). The
    combined footprint list gained a third segment `[FOOTPRINTS + L_FOOTPRINTS +
    T_FOOTPRINTS]`; `_footprint_by_index` returns a `shape` tag ("rect"/"L"/"T") that
    `_build_shell` dispatches on (`_build_t_shell`: 2 floor boxes + 4 outer + 4 concave
    walls, symmetric across X). Pure: T_FOOTPRINTS exists, the index split holds, the Heap
    pool opted into the T-shapes (14,15) while the Stack stayed rectangular-only. Scene:
    forces a T via a single-index pool through the REAL build_room, asserts it validates OK,
    the body centre + the north stem are both reachable from the spawn (crossbar connects to
    stem), each bare north corner is a genuine unreachable hole (sampled at the DEEP outer
    corner, clear of the walkable stem edge — wall tops bake isolated navmesh islands at
    y~5, harmless + unreachable), and no obstacle/spawn/pickup lands in either corner.
    GOTCHA: like l_room, pre-retire the authored CSG arena + settle 2 frames BEFORE
    build_room, else its 44x44 floor bakes over the notch (build_room's internal 1-frame
    retire isn't enough for CSG to clear).
40. `res://tools/plus_room_test.tscn` — stronger shape contrast Pass 3 (the plus/cross
    footprint family) → `PLUS_ROOM_OK`. A plus is the T generalised to ALL FOUR corners:
    a central crossing + four arms (south = spawn, north = gate, east/west = flanking
    sightlines). `_notches` carries 4 rects; `_build_plus_shell` = 3 floor boxes (central
    full-width band + N arm + S arm) + 4 arm-end walls + 8 concave walls (a band-edge + an
    arm-edge per corner, built in a 4-corner loop). Combined list is now FOUR segments
    `[FOOTPRINTS + L + T + PLUS]` (plus at 16,17); Heap opted in, Stack rectangular-only.
    Forces a plus via a single-index pool through the REAL build_room, asserts it validates,
    the centre + all four arms are reachable from the spawn, all four deep corners are
    unreachable holes, and nothing spawns in any corner. GOTCHAs carried: same pre-retire
    + deep-corner-sampling as t_room; PLUS the E/W flanking arms are a narrow band pocket
    that `scattered_cover` crates can carve, so the arm-reachability check samples a small
    grid and requires ANY point reachable (a single probe can land on a carved spot).
    GENERAL GOTCHA hit here: `for c in [Vector2(...), ...]` gives untyped elements, so
    `var sx := c.x` fails to parse — annotate `var sx: float = c.x`; a parse error in
    room_builder mid-test can produce a FALSE pass (the harness `_run` crashes before any
    assertion runs, leaving `fails` empty), so always check the log for SCRIPT/Parse ERROR,
    not just exit code.
41. `res://tools/kit_room_test.tscn` — modular-kit room skin Pass B+C (Kenney space-station
    kit re-skins the procedural shell, EVERY shape) → `KIT_ROOM_OK`. A layer profile carrying
    a `"kit"` key makes RoomBuilder overlay the kit's modular meshes on the shell, recoloured
    by the layer palette (`floor_color`/`wall_color` multiply the shared `colormap` atlas, so
    the Heap reads dim green and the Stack steel-blue while keeping the kit's baked detail).
    The skin is VISUAL ONLY: `_skin_shell` hides the gray shell box MeshInstances but keeps
    their `StaticBody` collision, so the navmesh (NavigationMesh `geometry_parsed_geometry_type
    = STATIC_COLLIDERS`, i.e. baked from colliders, NOT meshes) is unaffected — the kit
    MultiMesh overlays are invisible to the bake. `_skin_shell` is GENERIC over shape: it walks
    the shell's StaticBody boxes and, per box, tiles a floor (boxes named `Floor*`) or runs
    wall modules (`Wall*`) using each box's own size+pos read from its `CollisionShape`
    (`RoomKit.build_wall_box` derives the run's length/thickness/inward-facing from the box;
    inward = toward origin, which also points at the floor for concave notch walls). So rect /
    L / T / plus all skin uniformly, and the bare notch corners (no floor box) stay floorless.
    `RoomKit` (`scripts/world/room_kit.gd`, `class_name RoomKit`) tiles floor + walls as
    MultiMeshInstance3D (1 m modules, one batch each) and tints props via `tint_node`. Pure:
    the kit loads its 1 m floor/wall modules and builds the colormap-x-tint material
    (albedo_color = tint, albedo_texture kept); Heap vs Stack tints differ. Scene: a forced
    kit'd RECTANGULAR room validates OK with `KitFloor` + four `KitWall*` overlays, the gray
    `Floor` mesh hidden while its `StaticBody`+`CollisionShape3D` survive; a forced kit'd
    T-shape gets `KitFloor`+`KitFloor2` + ≥2 `KitWallNotch*` overlays with NO kit floor tile
    in its bare NE corner; an ENDLESS build (no `"kit"`) stays on the plain gray shell (the
    gate). Pass D: every cover box is skinned -- `RoomKit.skin_obstacle` fills it with a tinted
    prop CLUSTER (gray box mesh hidden, props added, collision + RVO kept).
    GATING: `build_room` only skins when `profile.has("kit")`, so ENDLESS + every
    un-kitted layer is byte-for-byte unchanged. LIVE ON REAL LAYERS: the Heap profile carries
    `"kit":"space_station"` (fine 1 m grid) and the Stack `"kit":"modular_space"` (the chunky
    4 m Kenney modular-space kit -- full-height single-piece walls + flat 4 m floor planes), so
    descending Heap->Stack swaps the WHOLE pack, not just the tint. `RoomKit` is grid-agnostic:
    it reads each piece's AABB, stacks the nearest whole wall courses then scales Y to fill
    `WALL_HEIGHT` (space-station = 5x1 m; modular = 1 course stretched), and aligns the wall's
    inner face by the mesh's local +Z extent (centred vs face-origin meshes both work).
    `layer_look_test` (#28) now asserts the kit overlay carries the layer colour (the gray
    shell mesh it used to read is hidden once a kit is on). GOTCHA fixed here: `_build_shell`
    now clears old shell boxes IMMEDIATELY (`remove_child` + free,
    not deferred `queue_free`), else the same-frame re-skin sees a lingering `Floor`/`Wall*`
    that steals the new box's name and gets mis-skinned. Look eyeballed via
    `tools/kit_preview.tscn` (Heap + Stack rect rooms) and `tools/kit_shapes_preview.tscn`
    (real generated T + plus kit'd rooms), both NON-headless. `tools/kit_measure.tscn` is a
    non-asserting diagnostic that dumps each kit piece's AABB (the module grid). See
    **Modular kit skin** in `context_systems.md`.
42. `res://tools/character_test.tscn` — rigged enemy characters Pass E (Kenney animated
    characters replace the primitive capsule/sphere) → `CHARACTER_OK`. A new autoload
    `CharacterApplicator` (`autoloads/character_applicator.gd`), a sibling of ToonApplicator
    in the same node_added-observer mould, grafts a rigged Kenney character onto each EnemyAI
    WITHOUT touching enemy.tscn / enemy_ai.gd / run_director.gd. It instances the base model
    (`characterMedium.fbx`: Root/Skeleton3D/skinned mesh) under the enemy's `Visual` as an
    `EnemyRig` (`scripts/enemies/enemy_rig.gd`, `class_name EnemyRig`), with its own
    AnimationPlayer fed a runtime AnimationLibrary that GRAFTS the separate idle/run/jump FBX
    clips (each clip's tracks are `Root/Skeleton3D:Bone`, so an AnimationPlayer rooted at the
    model resolves them — the base model ships with NO animations). VISUAL-ONLY + BUILD-ALONGSIDE:
    the rig is decorative (no collision); the capsule collider, hitboxes, navmesh and AI are
    untouched. The applicator HIDES the primitive `Body`+`Head` (replaced by the character) but
    KEEPS `Visual/Gun` visible — armed silhouette + the existing gun-drop ragdoll still fires;
    the hidden `Head` stays as the headshot head-pop's (now invisible) donor. EnemyRig glues that
    kept gun to the rig's `RightHand` bone each frame (`_drive_gun`, NOT a reparent — so the gun
    stays `Visual/Gun` and `_drop_gun` is unaffected), seating it in the hand vs floating. EnemyRig reads the
    owning enemy's `velocity` from the OUTSIDE to switch idle<->run. On `enemy_died` it pauses the
    anim and runs a **crumple**: it blends key bones (spine/neck/head curl, knees buckle, arms
    drop) from the frozen pose into a limp collapsed pose over `CRUMPLE_TIME` via
    `set_bone_pose_rotation` slerp, while the existing ragdoll (which reparents the whole `Visual`,
    rig included, onto a corpse) tumbles it -- so the body goes slack and falls rather than
    toppling as a stiff statue. (TRUE per-limb physics is blocked: the FBX imports with `Root`
    scaled 100x, so PhysicalBone3D collision shapes are sub-millimetre and Jolt explodes them --
    even the editor's own "Create Physical Skeleton" output, parked at `scenes/enemies/
    character_ragdoll.tscn`. The crumple is pose-only, so it's immune to the scale.) Archetype colour: `_archetype_tint`
    reads the Body's active albedo via `_albedo_of` (toon ShaderMaterial uniform OR
    StandardMaterial3D — order-independent vs ToonApplicator) and, if it isn't the plain-enemy
    crimson, blends the skin toward it (Rusher orange / Sniper cyan / etc. read on the rig). Pure:
    the applicator pipeline is ready + the anim lib carries looping `idle`/`run`. Scene: a plain
    enemy gets a `Visual/Rig` (EnemyRig) with a mesh + an AnimationPlayer playing `idle`, at
    `RIG_SCALE`, untinted, Body/Head hidden + Gun kept; an orange-override enemy's rig tints
    toward orange; and a REAL death (`BodyHitbox.take_hit` 99999) carries the rig onto the
    `enemy_corpse` (the corpse owns `Visual/Rig`) with its anim frozen + crumple running. The look (scale ~0.62 to
    stand the ~2.69 m-at-scale-1 model at ~1.8 m, orientation `RIG_YAW_DEG` 180 since Kenney
    faces +Z, archetype tint, kept gun) is eyeballed via `tools/character_preview.tscn`; the
    death crumple via `tools/char_ragdoll_preview.tscn` (kills an enemy, tracks the corpse,
    screenshots the fall + landing) -- both NON-headless. `tools/char_probe.tscn` is a
    non-asserting diagnostic that dumps the imported FBX tree / bone names / anim clips / node
    scales (it surfaced the 100x Root scale). **Skin variety (Pass 1)** is folded into the same
    harness: pure — `PLAIN_SKINS` are ≥3 + all distinct, each `ARCHETYPE_KEYS` maps to a skin;
    scene — two plain grunts spawned back-to-back rotate to DIFFERENT skins (deterministic by spawn
    order), and an enemy stamped with an archetype `meta` (e.g. `set_meta("sniper")`, as RunDirector
    does before add_child) wears that archetype's fixed skin (`ARCHETYPE_SKINS["sniper"]`).
    **Skin variety Pass 2 (corruption / per-layer)** is also folded in: pure — `_plain_pool_for({})`
    is the default protagonists, `_plain_pool_for({"skin_set":"corrupted"})` swaps in a survivors-pack
    zombie skin, an unknown set falls back to the default; scene — driving the live `RunManager` into a
    CAMPAIGN Heap room (which carries `"skin_set":"corrupted"`) makes a pool's worth of plain grunts
    include a zombie skin while a meta-tagged archetype KEEPS its protagonist skin (special types
    aren't corrupted); RunManager run_mode/current_room are snapshot + restored so the shared-process
    harnesses downstream stay valid. (Cheap path: the survivors `characterMedium.fbx` is byte-identical
    to the protagonists' — same UVs — so zombie skins reuse the existing rig, no new model/anim graft.)
    The preview renders a 12-wide row (4 plain + 4 archetype + 4 corrupted, the corrupted four under a
    forced Heap context) and prints `CHAR_SKIN <slot> -> <path>`.
    See **Rigged enemy characters** in `context_systems.md`.
43. `res://tools/deletion_vfx_test.tscn` — enemy death "deletion" VFX (computer-world glitch
    vanish instead of a ragdoll) → `DELETION_VFX_OK`. A new autoload `DeletionVFX`
    (`autoloads/deletion_vfx.gd`), a sibling of CharacterApplicator in the node_added-observer
    mould, hooks each enemy's `enemy_died`. enemy_ai's `_die` still spawns the physics corpse +
    drops the gun and emits `enemy_died` synchronously, SAME frame, BEFORE the next physics step —
    so the observer sets `freeze = true` on the just-spawned corpse pieces (gathered by proximity to
    the death point), cancelling the queued launch impulse → the body stays put (vanish in place),
    with ZERO `enemy_ai.gd` edits. It swaps the pieces' visible meshes to
    `shaders/deletion_dissolve.gdshader` (a blocky cell-noise dissolve + hot spectral-green emissive
    edge + RGB-split / scanline / per-vertex jitter, carrying over each mesh's own albedo
    texture+colour), spawns a glowing data-bit `CPUParticles3D` burst, tweens the shared `dissolve`
    0→1 over ~0.55 s, then frees the pieces. The ragdoll PHYSICS is the substrate, not removed:
    `DeletionVFX.enabled` (default TRUE, on every mode) just layers the visual, so `ragdoll_smoke` +
    `ragdoll_polish` set it FALSE to keep testing the launch/gun-drop (run_smoke's corpse-cleared
    assert is post-transition, which freeze doesn't block — no change needed). Pure: the autoload +
    dissolve shader load and it's enabled by default. Scene: a real kill freezes the corpse (no
    horizontal flight over 18 frames), swaps its meshes to the dissolve shader (starting at 0), the
    dissolve advances over time, and the pieces free themselves once it completes. Shaders don't
    compile headless, so the LOOK (spiky green shard-burst + data bits) is eyeballed via
    `tools/deletion_preview.tscn` (NON-headless: intact/early/mid PNGs). The EnemyRig crumple still
    runs (orthogonal — it moves bones, this swaps materials + freezes). See **Enemy death: deletion
    VFX** in `context_systems.md`.

`--check-only --script` does NOT register autoloads, so scripts referencing
`GameEvents`/`RunManager` must be checked via the in-engine .tscn harnesses.
Test nodes that survive transitions use `PROCESS_MODE_ALWAYS` (the tree pauses
during room transitions).

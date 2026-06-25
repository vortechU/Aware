# Environment Hacking ("Injection") — Plan

**Status:** **P1-P5 DONE & green** (`HACK_SMOKE_OK`, `HACK_RAM_OK`, `HACK_SHOCK_OK`,
`HACK_SELECT_OK`, `HACK_PROGRESSION_OK`). **Fully wired into the run economy**: props seeded
into rooms, lobby Cores unlock adjectives permanently, in-run cards rank them. P6+ (more
adjectives) and polish remain. This is the first *environmental* power in the game — every existing progression acts on the **player**
(stat cards, lobby Cores, the F/G cooldown abilities); this acts on the **world**. The
signature pillar for a game literally called *Aware*: the world is data, and you rewrite
a live object's properties at runtime.

**Decisions (locked — Vor, 2026-06-24):**
- **Objects only.** You hack props in the environment, never enemies. This keeps
  `enemy_ai.gd` untouched in v1 (object-targeted effects route damage through the
  existing `BodyHitbox.take_hit` path — zero enemy edits). Enemy-targeted adjectives
  are a much-later pass behind a gated additive hook, the `ai_time_scale` way.
- **Mouse/controller-only selection — never the keyboard.** The player never takes a
  hand off the mouse to type a word mid-fight. Selection is a **hold-to-open radial
  wheel** driven by mouse-flick / right-stick (scroll-cycle as a fallback). The
  "autocomplete terminal" the player sees is a **visual skin** over that wheel — the
  chosen adjective *types itself* into a `> ____` readout for fiction, but the input is
  never literal keystrokes.
- **RAM meter** is the resource model (no per-ability cooldown here). A regenerating
  pool: applying a trait spends RAM, and each *live* trait drains upkeep per second.
  Run dry → the oldest trait collapses (or a new apply is blocked). Thematically perfect
  — you're literally **allocating memory**. Every trait also auto-decays on a timer.
- **Fiction:** the world is parsed as language. You inject an **adjective** (a modifier)
  onto a **noun** (an object). `cube` → `Heavy cube`; `wall` → `Shocking wall`. Memory is
  unstable, so traits decay — which is also exactly what keeps the system technically
  safe (no permanent world mutation).

**Approach:** Build-alongside. A new `HackManager` node (child of `Player`, sibling of
`AbilityManager` / `PlayerUpgrades`) owns targeting, the RAM pool, the trait catalog, and
the active trait instances. A new `Hackable` component marks props. Every edit to an
existing file is *additive*: new `GameEvents` signals, a RAM bar + radial added to
`RunHUD` (GameEvents-driven, fully decoupled — no `HackManager` ref, the ability-widget
way), one `hack` input action, a `RoomBuilder` call that seeds hackable props, and
`RunDirector` freezing the manager + clearing active traits on transition (exactly as it
already does for `AbilityManager` and the `enemy_corpse` group).

## Why this is low-risk
Today **every** power in Aware touches the player and only the player — the in-run stat
cards, the permanent lobby Cores, and the two F/G cooldown abilities. Nothing acts on the
world. We're *adding a pillar*, not reworking one. And every trait **snapshots its host's
original state on apply and restores it on expire**, plus auto-decays — so navmesh,
procgen, and the room-transition flow are never left corrupted. Remove the new node + the
`Hackable` component + the appended signals/pool/input/seeding and the game is
byte-identical to today.

## The trait system (the heart)
A **runtime component system applied to arbitrary world props** — the same shape as the
ability `CATALOG`, generalised to external objects.

- **`Hackable`** (`scripts/world/hackable.gd`, `class_name Hackable`) — a lightweight
  child node you drop on any prop. Holds the physics body it governs, the `accepts` list
  (which adjectives this object allows; empty = any unlocked one), and its current active
  trait. Joins group `hackable` for fast targeting + highlight discovery.
- **Trait catalog** — each adjective is `{id, adjective, target_kinds, ram_cost,
  ram_upkeep, duration, effect params}`. A `const` dict in P1 (like abilities P1); promote
  to a `TraitDef` `.tres` in `data/traits/` later, mirroring `WeaponData`/`AbilityData`.
- **`TraitInstance`** — the runtime applied to a host. On apply it **snapshots** the host
  (body type, mass, gravity_scale, collision layer/mask, physics material, process mode,
  material_override) and runs `on_apply`; per frame `on_tick`; on decay/RAM-collapse/room
  change it runs `on_expire` and **restores the snapshot byte-for-byte**.
- **Three effect archetypes** every adjective falls into:
  1. **Mutate-body** — Heavy: swap the prop to a RigidBody, crank mass + gravity_scale,
     tag a crush volume that deals `take_hit` on impact.
  2. **Attach-effect-node** — Shocking: add a child Area3D that ticks `take_hit` on
     enemies in range (slow tick, not per-frame full scans).
  3. **Set-tag** — Conductive / Fragile: a flag other traits read, for combos later.
- **Signals** (`GameEvents`): `trait_applied(adjective, rank)`, `trait_expired(adjective)`,
  `ram_changed(current, maximum)` → HUD + the (silent-until-assets) `AudioManager`.

## Targeting & selection (mouse / controller, no keyboard)
- **Aim** — a camera raycast (reuse the hitscan / `BulletFX` ray pattern). When the
  crosshair is on a `hackable` within range, it highlights via the existing
  **ToonApplicator** outline.
- **Open** — hold the `hack` key (default **V**, rebindable later). The aimed target
  **locks** (so flicking the mouse to pick a wedge doesn't drag your aim off it) and a
  brief, tunable **slow-mo** kicks in (via `Engine.time_scale`, capped — and disabled
  during the RunDirector transition pause so the two never fight).
- **Pick** — a **radial wheel** of your *unlocked* adjectives at the crosshair;
  mouse-flick / right-stick selects the wedge (scroll-cycle as a no-aim-lock fallback).
  The terminal-readout skin types the highlighted word into `> HEAVY█` for fiction.
- **Apply** — release applies the picked adjective to the locked target (RAM permitting).
  Wheel closes, slow-mo releases, aim returns.

## RAM meter
- `ram_max`, `ram_regen` per second, a per-trait `ram_cost` to apply and `ram_upkeep` per
  second while live. Applying with insufficient RAM is refused (a soft buzz); if upkeep
  drives RAM to 0, the **oldest** active trait force-expires (reverts its host) to free
  memory. `ram_changed` drives a RunHUD bar (decoupled, GameEvents-only).
- Caps how many traits you can run at once *and* how aggressively — the thematic
  "allocate memory" knob. Lobby Cores can raise `ram_max` / `ram_regen` permanently later.

## Adjective bank (starter set)
All route through physics or `take_hit`, so **none need enemy edits**:

| Adjective | Effect | Archetype |
|---|---|---|
| **Heavy** | Prop becomes an anvil — drops & crushes whatever's beneath it | mutate-body |
| **Shocking** | Periodic zap to enemies in radius (the wall example) | attach-effect-node |
| **Volatile** | Primes the object to detonate (timer / on next hit) — a barrel bomb you position then shoot | attach-effect-node |
| **Repulsive** | Pulses a knockback shove — kick enemies off the Stack's ledges | attach-effect-node |
| **Floating** | Gravity flips — drifts up; lifts enemies / clears a blocker / becomes a step | mutate-body |
| **Bouncy** | High restitution — deflects grenades/projectiles, bounce pad for the movement kit | mutate-body (physics material) |

## Progression
- **Lobby Cores unlock the *word* permanently** (your adjective vocabulary grows across
  runs — persisted to `meta_progress.cfg` like the other Cores).
- **In-run upgrade cards *rank* a known adjective** (Heavy → more mass/crush, Shocking →
  more dmg/radius, all → lower `ram_upkeep`), reset each death — riding the existing
  `RunManager.UPGRADE_POOL` → `PlayerUpgrades.apply_upgrade` flow, tagged `"kind":"trait"`.
- Later: layer-gated vocabulary (the Heap teaches different adjectives than the Kernel)
  for narrative flavour.

## Pass ladder (one mechanic per pass, each tested green)
- **P1 — Core loop + Heavy (DONE).** `HackManager` (`scripts/player/hack_manager.gd`,
  child of `Player` in `player.tscn`) + `Hackable` (`scripts/world/hackable.gd`, a
  component you drop on a prop body — sets a `hackable` meta back-ref + joins the
  `hackable` group) + `TraitInstance` (`scripts/world/trait_instance.gd`, snapshots the
  host body's physics state on apply, restores it byte-for-byte on expire, auto-decays) +
  the `hack` input action (default **V**) + the `heavy` catalog entry + the three
  `GameEvents` signals (`trait_applied`, `trait_expired`, `ram_changed` — the last
  declared now, emitted from P2). Hackable props are RigidBody3Ds that start `freeze=true`
  (read as static/floating); Heavy releases one under heavy gravity and its fall crushes
  enemies beneath it (proximity + "below" check → `BodyHitbox.take_hit`, deterministic, no
  enemy edits). Targeting is a camera raycast against the world layer (walls block it).
  `RunDirector` freezes the manager + `clear_all()`s live traits at transition start. No
  UI/RAM yet — `hack` injects the selected adjective into the aimed target. Test
  `tools/hack_smoke_test.tscn` → **`HACK_SMOKE_OK`**: pure — the catalog has `heavy` and a
  `TraitInstance` apply → expire round-trips the host's mass/freeze/layer; scene — in a
  code world (floor + a `Hackable` cube in front of the live player + an inert enemy
  beneath via `sight_range=0` + process-off) aiming at the cube and injecting Heavy
  releases it, it falls and crushes the enemy below while a control enemy off to the side
  is untouched, a hack with no target is a no-op, and on decay the cube reverts to its
  snapshot (re-frozen, mass/layer restored, host cleared). GOTCHA the test hit: a frozen
  RigidBody3D ignores a `global_position` set AFTER `add_child` (stays at the physics-
  server origin) — set the spawn transform BEFORE entering the tree.
- **P2 — RAM meter + HUD bar (DONE).** `HackManager` gained the `ram` pool: `ram_max` /
  `ram_regen` (always regenerating) + per-adjective `ram_cost` (spent on inject) and
  `ram_upkeep` (drained/sec while live). `try_hack` refuses below `ram_cost`; if upkeep
  *overdraws* the pool (`raw < 0`, robust to RAM settling at a tiny float) the OLDEST trait
  collapses (its host reverts). `clear_all` refills to full per room. Emits
  `ram_changed(current, max)`. `RunHUD` got a `RamMeter` (VBox: "RAM" label + styled
  `ProgressBar`, bottom-centre above the AbilityBar), GameEvents-driven and decoupled:
  `_on_ram_changed` sets the bar even while hidden, `_on_trait_applied` reveals it on the
  first hack, hidden + reset on run start/end like the ability widgets. Test
  `tools/hack_ram_test.tscn` → **`HACK_RAM_OK`**: a hack spends `ram_cost` + emits
  `ram_changed`; with regen throttled below upkeep a live trait bleeds RAM to empty and the
  oldest force-expires (host re-frozen); idle RAM regenerates; a hack with too little RAM is
  refused (no trait); the RunHUD bar tracks `ram_changed` + reveals on the first
  `trait_applied`. GOTCHA: `ram_changed` is a global signal, so a test must freeze the live
  HackManager (`set_physics_process(false)`) before asserting on manually-emitted values,
  else its per-frame emits overwrite them.
- **P3 — Shocking (attach-effect-node archetype) (DONE).** The second effect category,
  proving the catalog handles *non-mutating* traits. Instead of touching the host's physics
  (Heavy), Shocking attaches a `ShockField` (`scripts/world/shock_field.gd`, `class_name
  ShockField`, a Node3D) to the host; on its own timer it pulses damage to every enemy in
  radius via `BodyHitbox.take_hit` (group-proximity, the Stack-Smash/Heavy-crush pattern --
  deterministic, no Area3D-overlap timing). `TraitInstance` gained a generic `_effect_node`
  that `expire()` frees first (so the host is never left with a dangling effect), then runs
  the usual snapshot restore (a no-op here since the body wasn't mutated). RAM: `ram_cost`
  30 / `ram_upkeep` 8. Test `tools/hack_shock_test.tscn` → **`HACK_SHOCK_OK`**: hacking the
  aimed panel attaches a `ShockField` and leaves the host frozen + in place (not mutated);
  the field damages only the in-radius enemy over time while one well outside is untouched;
  on decay the `ShockField` is removed and the host is unchanged.
- **P4 — Selector UI + targeting highlight + RoomBuilder seeding (DONE).** HOLD `hack`
  opens a radial wheel of your unlocked adjectives: the aimed Hackable **locks**, the world
  dips into slow-mo (`Engine.time_scale`, tunable), **mouse-flick / scroll-cycle** picks a
  wedge (consumed in `HackManager._input`, which runs before the player's `_unhandled_input`
  — so camera look + weapon switch are suppressed for the duration with **no player.gd /
  weapon edits**), and **release** injects the picked adjective into the *locked* target.
  `try_hack` was split into `try_hack` (aimed) + `_inject(target, id)` (explicit) so the
  selector targets the lock. The wheel (`scripts/ui/hack_wheel.gd`, `class_name HackWheel`,
  a custom-drawn `Control` with the "autocomplete terminal" skin) is **owned by HackManager**
  — built in code into its own `CanvasLayer`, so it shows wherever the player is (real runs
  AND the sandbox), no HUD edit. `Hackable.set_highlighted()` glows the aimed prop (a
  translucent emissive shell, non-destructive); HackManager keeps it synced to the
  crosshair. `RoomBuilder._seed_hackables()` drops 2-3 frozen `Hackable` cubes per room
  (overhead, added post-bake like the atmosphere, so they never block spawns/pathing).
  Test `tools/hack_select_test.tscn` → **`HACK_SELECT_OK`**: a built room seeds ≥1
  `hackable`; the flick-math maps a flick to the right wedge (tiny → none); aiming glows a
  hackable + aiming away clears it; holding `hack` opens the wheel with the unlocked set +
  locks the target; cycling moves the pick; releasing injects the PICKED adjective into the
  LOCKED target even after aiming away. (The wheel look is eyeballed; the driver asserts the
  state machine, the `glitch_smoke` way.)
- **P5 — Progression (DONE).** Two halves. **Cores unlock the WORD permanently:**
  `MetaProgression.META_UPGRADES` gains `hack_heavy` / `hack_shocking` (one-time, `max_level`
  1, tagged `"kind":"adjective"` + the catalog `"adjective"`); the lobby builds buy pedestals
  for them in code (`_build_hack_stations`, the ModeToggle convention -- the generic
  `_is_upgrade`/`buy` path handles the rest); on an armed run `MetaProgression._apply_hacks`
  unlocks every owned adjective on the spawned player's HackManager (so the wheel is
  populated from room 1). **In-run cards RANK it:** two `"kind":"trait"` cards (ids = the
  adjective ids `heavy` / `shocking`) appended to `RunManager.UPGRADE_POOL`; `PlayerUpgrades.
  apply_upgrade`'s fallback now tries `ability_manager.grant` then `hack_manager.rank_up`
  (first pick grants rank 1, repeats rank up; effect scales via the existing `*_per_rank`).
  Test `tools/hack_progression_test.tscn` → **`HACK_PROGRESSION_OK`** (snapshots
  `meta_progress.cfg`): a Core buy persists + maxes the 1-level unlock; an armed player gets
  the owned word unlocked while an unarmed player stays vanilla; a trait card grants Heavy at
  rank 1 then ranks it to 2; a non-adjective id is rejected.
- **P6.. — More adjectives, one per pass (DESIGNED, not built — see backlog below).**
- **Later — polish + reach (DESIGNED, not built — see backlog below).**

## P6+ adjective backlog (designed; build one per pass when we return)
The recipe per adjective (P1-P5 established it, and it's now a tight loop): add a `CATALOG`
entry in `HackManager` → an apply/expire arm in `TraitInstance` (or an attached effect node
like `ShockField`) → a `MetaProgression` `hack_<id>` unlock + a lobby pedestal in
`_build_hack_stations` → a `"kind":"trait"` rank card in `RunManager.UPGRADE_POOL` → a
`*_OK` smoke test. The RAM meter, selector wheel, highlight, room seeding, and progression
are all generic, so **no new UI / signal / lobby-wiring work is needed** — each adjective is
just its effect + its four registry lines + a test. Effects fall into the two proven
archetypes: **mutate-body** (touch the host's physics, snapshot/restore reverts it — Heavy)
or **attach-effect-node** (bolt on a child node that owns the behaviour, freed on expire —
Shocking). Each grows the effect + (optionally) shrinks `ram_upkeep` per rank.

- **Volatile — primed detonation** (attach-effect-node). Inject → a short fuse, then the
  object detonates once in an AoE blast (a barrel bomb you place then trigger). Mechanism: a
  `VolatileFuse` node (the `ShockField` shape) counts the fuse down, then on detonation deals
  a one-shot `BodyHitbox.take_hit` to every enemy in `blast_radius` + an outward impulse to
  loose RigidBody3Ds (corpses / other hacked props / grenades) + `GameEvents.sound_emitted`,
  then frees itself; the host reverts on expire as usual (the blast doesn't destroy it).
  v1 = fuse timer; a nice v2 is "detonate when shot" (route the host's bullet hits — needs a
  hook). Params: `ram_cost` 40, `ram_upkeep` ~4 (short-lived), fuse 2.0 s, `blast_radius` 5,
  `blast_damage` 100 (+30/rank). Test `HACK_VOLATILE_OK`: inject → after the fuse the
  in-radius enemy is damaged + an out-of-radius one isn't; the host reverts; the fuse node is
  gone.
- **Floating — anti-gravity** (mutate-body, Heavy's mirror). Inject → release the prop with
  a small NEGATIVE gravity so it drifts UP: lift a blocker out of the way, raise a step you
  (or an enemy) can ride up on, or carry whatever's resting on it skyward. Mechanism: like
  `_apply_heavy` but `freeze=false` + `gravity_scale` negative (e.g. -0.4) / a gentle upward
  `linear_velocity`; snapshot/restore re-freezes it at the ORIGINAL position on expire. Pure
  physics — a player or enemy CharacterBody standing on the rising prop is carried up by
  contact, **no enemy edit**. Params: `ram_cost` 25, `ram_upkeep` 5, duration 6, rise tuned
  by `gravity_scale`/`float_speed`. Test `HACK_FLOAT_OK`: inject → the prop's `y` climbs over
  time (and a body resting on it rises too); on expire it reverts to its original frozen
  transform.
- **Bouncy — restitution** (mutate-body for props + a small launch field for actors).
  Inject → the prop becomes a trampoline. Two layers: (a) a high-bounce
  `physics_material_override` (bounce ~0.9) so grenades / other rigid bodies deflect off it
  (pure physics, kept `freeze=true` as a static bouncy surface); (b) an attached `BounceField`
  that catches a CharacterBody landing on it from above (downward velocity) and reflects it
  upward — the player gets a launch pad for the movement kit, enemies get popped. The field
  finds actors via groups (`player` / `enemies`) and writes `velocity.y` from the OUTSIDE
  (the AbilityManager pattern), **no enemy/player edit**. Snapshot/restore strips the
  material + the field on expire. Params: `ram_cost` 25, `ram_upkeep` 5, `bounce_velocity`
  ~14 (+/rank), duration 7. Test `HACK_BOUNCE_OK`: a body dropped onto the prop is launched
  upward; a rigid body deflects; on expire the material + field are gone.
- **Repulsive — knockback shove** (attach-effect-node; the one that touches the boundary).
  Inject → the object pulses a shove that pushes things AWAY from it — clear a crowd, kick
  enemies off the Stack's ledges. Objects-only v1 shoves loose **RigidBody3Ds** outward (an
  impulse) — clean, no enemy edit, but limited. The impactful version shoves **enemies**,
  which their `enemy_ai._navigate` would otherwise overwrite each frame — so it needs a
  *gated, additive* `EnemyAI` knockback hook (the `ai_time_scale` precedent: an off-by-
  default `_knockback_vel` + timer that `_physics_process` applies and decays, suppressing
  navigation while active). That's a deliberate cross of the "objects-only" line (same shape
  as Overclock's hook), so decide at build time; Stack Smash's "knockback" could share it.
  Params: `ram_cost` 30, `ram_upkeep` 6, `shove_radius` 5, `shove_force` ~12, pulse period or
  one-shot. Test `HACK_REPULSE_OK`: a body/enemy in radius is pushed outward; one outside
  isn't; host reverts.

## Later — polish & reach backlog (designed; not built)
- **Enemy-targeted adjectives** (Stunned / Confused→friendly-fire) — the first adjectives
  that act ON an enemy, behind a gated additive `EnemyAI` hook (off by default, the
  `ai_time_scale` way). Stunned = freeze its state machine for N s; Confused = retarget it at
  the nearest other enemy. Shares the knockback-hook decision above.
- **Trait stacking** — allow >1 live trait per host (Heavy + Shocking = a shocking anvil).
  Today `_inject` replaces the host's single `active_trait`; this means a small list per host
  + layered snapshot/restore (innermost-last) so reverts unwind cleanly.
- **Layer-gated vocabulary** — the Heap teaches different adjectives than the Cache / Kernel;
  gate which `hack_<id>` unlocks/cards appear per narrative layer (ties into LayerCatalog).
- **Cast / impact SFX** → `AudioManager` (inject, decay, crush, zap, detonate) — the registry
  is wired + silent today, so it's just signal hookups.
- **Impact VFX** — a BulletFX-style flash/decal on crush + detonation, a spark mesh for the
  shock field, a dissolve when a host reverts instead of the hard snap-back.
- **`hack` + the wheel in the rebind UI** — fold the `hack` action (and a future controller
  bind) into `SettingsManager`'s rebind list so it's remappable like the rest.
- **Catalog → `TraitDef` `.tres`** — promote the `CATALOG` const dict to authored resources
  in `data/traits/`, mirroring `WeaponData` (and the abilities' planned `AbilityData`).
- **RunHUD-in-sandbox** (small) — instance the RunHUD (or just its RAM bar + ability bar) in
  `sandbox.tscn` so RAM + ability cooldowns are visible while free-testing (today only the
  wheel + base HUD show there).

## Build-alongside guarantee (what stays untouched)
`game_manager.gd`, `weapon_manager.gd`, `enemy_ai.gd` (objects-only v1), the HUD, the
run/transition flow, ENDLESS mode, and `MetaProgression` are all unchanged. `RunDirector`
additively freezes `HackManager` during transitions and clears active traits on a room
change (reverting every host), the same discipline it uses for `AbilityManager` +
`enemy_corpse`. Removing the new node, the `Hackable` component, the appended
signals/pool/input, and the seeding call leaves the game exactly as it is today.

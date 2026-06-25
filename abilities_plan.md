# Active Abilities — Plan

**Status:** P1 (core + Stack Smash, `ABILITY_SMOKE_OK`) + P2 (RunHUD ability widget,
`ABILITY_HUD_OK`) + P3 (Overclock time-dilation, `OVERCLOCK_OK`) + P4 (multi-slot, 2
hotkeys) — DONE & green. First active-power system in the game; P5+ (more abilities)
ahead.
**Decisions (locked):** Active **hotkey** powers · unlocked via the existing **in-run
upgrade cards** (reset each death) · **cooldown-only** (no new resource meter).
**Approach:** Build-alongside. A new `AbilityManager` node (child of `Player`, sibling
of `PlayerUpgrades`) owns the equipped ability, its cooldown, the input, and the
effect. The only edits to existing files are *additive*: a fallback branch in
`PlayerUpgrades.apply_upgrade`, ability entries appended to `RunManager.UPGRADE_POOL`,
two new `GameEvents` signals, and one `ability` input action. `player.gd` is touched
only if an ability needs a movement hook — the first one (Stack Smash) just writes
`velocity`/`global_position` directly, the way the smoke tests already do.

## Why this is low-risk
Today **every** progression in Aware is a passive stat modifier — the in-run cards
(`RunManager.UPGRADE_POOL` → `PlayerUpgrades.apply_upgrade`) and the permanent lobby
Cores (`MetaProgression`). There is no active/triggered ability anywhere. We are
*adding a pillar*, not reworking one, so nothing existing has to change behaviour.

## How it rides the existing card flow
1. Each ability has a catalog entry (id, title, desc, `cooldown`, effect params) held
   by `AbilityManager` (const dict in P1; promote to `AbilityData` `.tres` in
   `data/abilities/` later, mirroring `WeaponData`).
2. Ability **cards** are appended to `RunManager.UPGRADE_POOL` tagged `"kind": "ability"`
   (existing stat cards default to `"kind": "stat"`). `roll_upgrade_choices` is
   unchanged except an optional guard so at most one ability card shows per offer (so
   abilities never crowd out stat picks).
3. When a card is taken, `PlayerUpgrades.apply_upgrade(id)` runs its normal `match`;
   ids it doesn't recognise as stats fall through to
   `ability_manager.grant(id)`. **First grant = unlock + equip; a repeat grant = rank
   up** (lower cooldown / more potency), exactly like stat stacks ranking up today.
   `RunManager.record_upgrade` already logs the pick — no change.
4. Cooldown-only: `AbilityManager` ticks the active cooldown, blocks recast until
   ready, and emits `GameEvents.ability_cooldown_changed(id, remaining, total)` for the
   HUD + the (silent-until-assets) `AudioManager`. Casting emits
   `GameEvents.ability_used(id)`.

## Slot / input model
- One primary ability slot, bound to a new `ability` input action (default key TBD,
  e.g. `Q` or `F`). Reserve `ability_2` for a possible second slot later.
- Add the action to `project.godot`; fold it into the SettingsManager rebind UI in a
  later pass so it's remappable like the rest.

## Starter ability catalog (cooldown-only, themed to the memory-layers world)
Abilities read as *exploits / subroutines* the player injects.
- **Stack Smash** — air-slam ground-pound (only castable airborne): drives the player
  down, and on landing emits an AoE shock that damages + knocks back enemies in radius.
  Pairs directly with the new double jump. *First ability — see P1.*
- **Overclock** — brief time-dilation: enemies slow, the player doesn't.
- **Segfault** — short-range blink/teleport (the dash's cousin).
- **Fork Bomb** — spawns a decoy clone that draws enemy fire for a few seconds.
- **Garbage Collect** — vacuums nearby pickups toward the player + a small heal.

## Pass ladder (one mechanic per pass, each tested green)
- **P1 — Core + Stack Smash (DONE).** `AbilityManager` (`scripts/player/ability_manager.gd`,
  `class_name AbilityManager`) added as a child of `Player` in `player.tscn`; the
  `ability` input action (default **F**); four `GameEvents` signals (`ability_granted`,
  `ability_used`, `ability_impact`, `ability_cooldown_changed`); the `apply_upgrade`
  fallback routing unknown ids to `ability_manager.grant(id)`; and the Stack Smash card
  in `RunManager.UPGRADE_POOL` (tagged `"kind":"ability"`). `RunDirector._set_player_frozen`
  also freezes the AbilityManager during transitions. Stack Smash drives the player down
  and, on landing, routes AoE damage through enemy `BodyHitbox.take_hit` (the path
  `DevTools` kill-all uses) + emits `sound_emitted` so enemies hear it. Test
  `tools/ability_smoke_test.tscn` → **`ABILITY_SMOKE_OK`**: grant equips at rank 1 / a
  repeat ranks up + shortens cooldown / a non-ability id is rejected; in a code world
  (floor + two inert enemies + the live player) an airborne cast damages the in-radius
  enemy on landing, leaves the out-of-radius enemy untouched, and the cooldown blocks a
  recast then ticks to ready.
- **P2 — HUD ability widget (DONE).** `AbilityWidget` (`scripts/ui/ability_widget.gd`,
  `class_name AbilityWidget`) — a self-contained, asset-free **radial cooldown ring**
  (custom `_draw`, no textures) added to `run_hud.tscn` bottom-centre with a key glyph
  ("F") + ability name. RunHUD drives it from `ability_granted` (label + reveal),
  `ability_cooldown_changed` (ring sweep, with a smooth local bleed-down re-synced by the
  AbilityManager's ready signal), and `ability_used` (a brief cast pulse); hidden until an
  ability is granted and reset per-run. The key glyph reads the live `ability` bind via
  `InputMap` (tracks rebinds). Verified the `glitch_smoke` way (the driver tracks the
  signals) → **`ABILITY_HUD_OK`**; the ring look is eyeballed in play.
- **P3 — Overclock (DONE).** Time-dilation: every enemy slows for a few seconds, the
  player does not. The mechanism is a single gated hook on `EnemyAI` —
  `@export var ai_time_scale := 1.0` (inert by default, like `is_sniper`/`is_grenadier`):
  `_physics_process` scales its whole delta by it (so every delta-driven timer — senses,
  firing cadence, reload, sniper charge, grenade wind-up, dodge, state timers — slows),
  and `_navigate` / `_process_dodge` scale locomotion by it. AbilityManager's Overclock
  holds every live enemy's `ai_time_scale` at the rank-scaled slow factor for the
  duration, then releases them to 1.0. Castable anywhere (no positional requirement).
  Test `tools/overclock_test.tscn` → **`OVERCLOCK_OK`**: a behavioural proof that a
  slowed enemy's timer bleeds down ~quarter-speed vs a normal one, plus grant/cast/expiry
  (every enemy held at the slow factor during, restored to 1.0 after, cooldown armed).
- **P4 — Multi-slot (DONE).** `AbilityManager` now holds `MAX_SLOTS` (2) independent
  slots, each its own hotkey (`SLOT_ACTIONS` = `ability` F / `ability_2` G) and its own
  cooldown. `grant(id)` ranks the slot already holding the id, else fills the first empty
  slot, else replaces slot 0. The `ability_*` GameEvents signals now carry a leading
  `slot` arg so the HUD routes each event to the right widget; `RunHUD` has an
  `AbilityBar` (HBox) with one `AbilityWidget` per slot, and `AbilityManager` exposes
  per-slot accessors (`equipped_id(slot)`, `rank_of(slot)`, `cooldown_left/total(slot)`,
  `is_ready(slot)`, `can_cast(slot)`, `slot_of(id)`). Effects (slam / overclock) stay
  manager-level and independent, so you can run both. Verified by `ABILITY_HUD_OK` (now
  asserts slot 0 + slot 1 reveal independently with their own key glyphs) + the refreshed
  `ABILITY_SMOKE_OK` / `OVERCLOCK_OK`. Now you can carry **both** Stack Smash and Overclock.
- **P5..Pn — More abilities, one per pass (DESIGNED, not built — see backlog below).**
- **Later — polish.** Promote the catalog to `AbilityData` `.tres`; wire cast/impact
  SFX into `AudioManager`; BulletFX-style shock decal for Stack Smash; add `ability` /
  `ability_2` to the rebind UI; bump `MAX_SLOTS` / add an `ability_3` bind if a third+
  ability should be carried simultaneously (today a 3rd grant replaces slot 0).

## P5+ ability backlog (designed; build one per pass when we return)
The recipe per ability (P1-P4 established it): add a `CATALOG` entry → a `can_cast` +
`_cast` arm in `AbilityManager` → the effect fn → a card in `RunManager.UPGRADE_POOL`
(`"kind":"ability"`) → a `*_OK` smoke test. The HUD widget + cooldown + slots are
already generic, so no HUD/signal work is needed. Each grows the effect + shrinks the
cooldown per rank, like the shipped two.

- **Segfault — short-range blink** (movement; the dash's instant cousin). Cast: teleport
  the player ~6 m along the move/look direction (horizontal, to avoid floor/ceiling
  clipping). Mechanism: shapecast the player capsule forward through the world layer and
  drop them at the last clear point minus a skin (so it never tunnels into geometry).
  *Try external first* — `AbilityManager` sets `player.global_position` after its own
  shapecast (uses `player.get_world_3d()`), no `player.gd` edit; add a `player.gd`
  `blink()` hook only if the feel needs momentum/camera handling (player.gd is the
  movement exception). Castable anywhere. Params: distance 6 (+1/rank), cooldown 5 s
  (×0.85/rank). Test `SEGFAULT_OK` (code world floor + wall): cast moves the player ~6 m
  along facing; a wall blocks the blink short (no tunneling); cooldown arms + blocks recast.
- **Fork Bomb — decoy clone** (summon; draws fire). Cast: spawn a short-lived decoy at
  the player's feet that enemies attack instead of the player. Mechanism: a small scene
  (mesh + `HealthComponent` + `HitboxComponent`) in group `player_decoy`, reusing the
  damage path. Needs a *gated, additive* `EnemyAI` hook (like `ai_time_scale`): when a
  `player_decoy` exists in sight/range, the enemy aims at it instead of `_player` for its
  lifetime; the decoy soaks `take_hit` and despawns on death or timeout. This is the most
  involved of the three (touches `enemy_ai.gd` again, but additively + off by default).
  Params: decoy HP 60 (+/rank), lifetime 5 s, cooldown 14 s. Test `FORKBOMB_OK`: a hooked
  enemy targets/shoots the decoy not the player; the decoy takes damage + despawns;
  cooldown.
- **Garbage Collect — vacuum + heal** (utility; reclaim the room). Cast: pull every
  pickup within ~12 m to the player (auto-collect) + a small instant heal. Mechanism:
  enumerate `Pickup` nodes in radius and apply each via `player.try_pickup(type, amount)`,
  freeing consumed ones; then `player.heal(~20)`. NOTE: pickups aren't grouped today — add
  a `pickups` group tag to the Pickup scene (tiny additive change) so the manager can find
  them without knowing the `Pickups` parent node. Params: radius 12, heal 20 (+/rank),
  cooldown 16 s. Test `GC_OK`: in-radius pickups are consumed (player ammo/health rise,
  nodes freed) while out-of-radius ones are untouched, the heal lands, cooldown arms.

## Build-alongside guarantee (what stays untouched)
`game_manager.gd`, `weapon_manager.gd`, `enemy_ai.gd`, the HUD, the run/transition
flow, ENDLESS mode, and `MetaProgression` are all unchanged. Removing the appended
pool entries + the `apply_upgrade` fallback + the new node would leave the game exactly
as it is today.

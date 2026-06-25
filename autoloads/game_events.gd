extends Node
## Global event bus. All cross-system communication goes through here so the
## player, weapons, enemies, HUD and game manager never reference each other
## directly.

# --- Combat / weapons ---
## A loud sound happened in the world (gunshots). Enemies use this for hearing.
signal sound_emitted(position: Vector3, radius: float)
## The player's shot connected with an enemy hitbox.
signal hit_confirmed(headshot: bool, killed: bool)
## Current weapon ammo changed (fire / reload / switch / pickup).
signal ammo_changed(in_mag: int, reserve: int)
## The player switched weapons.
signal weapon_changed(weapon_name: String)
## A bullet streak should be drawn from the muzzle to where the shot landed.
## Cosmetic only; BulletFX renders it.
signal bullet_tracer(from: Vector3, to: Vector3)
## A bullet hit world geometry (not an enemy). BulletFX places a decal here.
signal bullet_impact(position: Vector3, normal: Vector3)

# --- Player state ---
signal player_health_changed(health: float, max_health: float)
signal player_armor_changed(armor: float, max_armor: float)
signal player_stamina_changed(stamina: float, max_stamina: float)
## Player took damage; source_position is where it came from (world space).
signal player_damaged(amount: float, source_position: Vector3)
signal player_died
signal player_respawned

# --- Enemies / score ---
signal enemy_killed(enemy_name: String, headshot: bool, weapon_name: String)
signal enemies_remaining_changed(count: int)

# --- Game flow ---
signal game_won
signal game_lost

# --- Abilities (active, hotkey powers; AbilityManager drives these) ---
## `slot` is the ability slot (0 = primary "ability", 1 = "ability_2", ...) so the
## HUD can route each event to the right widget.
## An ability was unlocked / ranked up via the upgrade-card flow.
signal ability_granted(slot: int, id: String, rank: int)
## The player triggered an ability (cast moment) -- for SFX / VFX / HUD pulse.
signal ability_used(slot: int, id: String)
## An ability's area effect landed at `position` (e.g. a Stack Smash shockwave).
## Slot-agnostic (world FX only).
signal ability_impact(id: String, position: Vector3, radius: float)
## Cooldown state changed; the RunHUD ability widget tracks remaining vs total.
signal ability_cooldown_changed(slot: int, id: String, remaining: float, total: float)

# --- Environment hacking ("Injection"); HackManager drives these ---
## An adjective was injected into a world prop (cast moment) -- for SFX / VFX / HUD.
signal trait_applied(adjective: String, rank: int)
## An injected adjective decayed or was cleared; the host reverted to its original state.
signal trait_expired(adjective: String)
## The hack RAM pool changed (current vs maximum). Declared now; emitted from P2 onward.
signal ram_changed(current: float, maximum: float)

# --- Narrative ---
## A Memory Fragment was reached in the world; the FragmentReader displays it.
signal fragment_read(fragment: Dictionary)

# Aware

First-person arena shooter in Godot 4.6.3 / GDScript, extended into an
infinite-room roguelite. **Prime directive: build alongside, never rewrite the
original gameplay scripts** (`player.gd` is the one approved exception, and only
for first-class movement mechanics).

The always-true invariants — engine info, base architecture, the GameManager
hand-off, and how to verify changes headlessly — follow inline:

@context_architecture.md

---

## Shipped-systems reference — read on demand, don't bulk-load

Detailed per-feature docs live in `context_systems.md`, split by `## ` heading.
**When a task touches a feature below, read only that heading's section** (grep
the heading in `context_systems.md`, then read from there). If a task touches
none of them, skip the file entirely. Loading only what's relevant is the whole
point — it keeps context small so the model's recall stays accurate.

Headings in `context_systems.md`:

- **Roguelite run system** — RunManager, RunDirector, PlayerUpgrades, RunHUD,
  RoomBuilder, elite/milestone rooms, procedural footprints. Contains these
  nested subsections: *Enemy archetypes* (Rusher/Sniper/Grenadier) ·
  *Enemy combat fairness* (aim penalty + reactive dodge) · *Upgrade pool + Flow* ·
  *Exit gate* · *Matrix-spiral transition* · *Upgrade card glitch*.
- **Layered world (narrative layers)** — the GDD's 5 "stages" (Heap/Stack/Cache/
  Kernel/I-O Buffer) as a finite campaign layered over the run system; LayerCatalog
  + RunManager run-mode/layer backbone + RoomBuilder profile re-skin + per-sector
  room types (combat/fragment/ghost) + the Fragment system (FragmentDB autoload,
  MemoryFragment, FragmentReader) + Heap gen identity (atmosphere debris, spectral
  Ghost rooms) + Layer 02 The Stack & the descent beat + lobby run-mode selector
  (campaign default). Endless mode preserved (Hybrid). **Full Heap track (Passes
  1-5b) shipped; next: layers 3-5 (Cache/Kernel/I-O) + Kernel Panic boss + The Choice.**
- **Main menu & settings** — SettingsManager, key/mouse rebinding.
- **Meta progression: Lobby + Cores** — 3D lobby hub, permanent upgrades, payout.
- **Audio** — AudioManager registry, signal-driven SFX (silent until assets land).
- **Cel-shading** — ToonApplicator + toon shaders.
- **Weapon wall-clip fix** — WeaponClip render-on-top.
- **Bullet FX: decals + tracers** — BulletFX autoload.
- **Advanced movement** — wall-run / dash / vault / momentum / double jump (inside player.gd).
- **Speed-line / wind overlay** — `SpeedLines` (child of Player, sibling of HackManager): a
  screen-edge radial "wind streak" VFX that fades in when the player moves fast. Build-alongside
  in code (its own CanvasLayer + full-rect ColorRect with `shaders/speed_lines.gdshader`, no HUD
  edit, no player.gd edit) — reads the player's public `velocity` from the OUTSIDE and smoothstep-maps
  horizontal speed → a 0..1 shader `intensity` (faint at a brisk sprint, dramatic at dash / high
  momentum), temporally smoothed; centre stays clear so the crosshair reads; decays out while the
  tree is paused / on death. Shows in every run AND the sandbox. `SPEED_LINES_OK` (#44); look
  eyeballed via `tools/speed_lines_preview.tscn` (non-headless). Tunables = `@export`s on the node
  (`speed_start`/`speed_full`/rates) + shader uniforms (tint/density/sharpness/edge mask).
- **Active abilities** — AbilityManager (child of Player): cooldown-only hotkey powers
  unlocked in-run via upgrade cards. P1-P4 done (Stack Smash, RunHUD widget, Overclock,
  2-slot loadout: F + G). Plan: `abilities_plan.md`.
- **Environment hacking ("Injection")** — HackManager (child of Player, sibling of
  AbilityManager): aim at a world prop (a `Hackable`) and inject an *adjective* that
  rewrites it for a few seconds. Objects-only (effects route through `BodyHitbox.take_hit`,
  no enemy_ai edits); each host is snapshot+restored by a `TraitInstance` (auto-decay, no
  permanent mutation). P1-P5 done (HOLD **V** → radial wheel, flick/scroll to pick, release
  injects): **Heavy** (mutate-body crush) + **RAM** meter (RunHUD bar) + **Shocking**
  (attach-effect `ShockField` zap) + selector wheel/highlight + RoomBuilder seeds props +
  progression (lobby Cores unlock adjectives, in-run cards rank them). Fully in the run
  economy. Coming: more adjectives. Plan: `hacking_plan.md`.
- **Modular kit skin (Kenney)** — real visuals over the procgen layout: `RoomKit` skins the
  generated shell with a Kenney modular kit (floor/wall tiles via MultiMesh, props instanced),
  recoloured per-layer by multiplying the shared colormap atlas. Visual-only over the tested
  collision (navmesh bakes from colliders, untouched). Gated on profile `"kit"`. Grid-agnostic:
  the **Heap** uses the space-station kit (fine 1 m grid), the **Stack** the modular-space kit
  (chunky 4 m grid) → descending swaps the whole pack (major-transition variety). Cover boxes
  furnished with tinted prop clusters (Pass D). Pass A+B+C + live-on-real-layers + D done
  (`KIT_ROOM_OK`, generic over rect/L/T/plus). Next: prop variety,
  hero rooms (Pass F); deeper layers can remix the packs. Assets in `Assets/kenney_*`.
- **Rigged enemy characters (Kenney)** — Pass E: living enemies are animated Kenney characters
  instead of capsule+sphere+box. `CharacterApplicator` autoload (ToonApplicator-style node_added
  observer) grafts an `EnemyRig` (model + runtime AnimationLibrary built from the separate
  idle/run/jump FBX clips) under the enemy's `Visual`, hides the primitive Body+Head (keeps the
  Gun for the armed look + gun-drop), tints the rig by the archetype body colour, and drives
  idle/run from velocity. The kept gun is glued to the `RightHand` bone each frame (still
  Visual-parented, so the gun-drop ragdoll is unchanged). Visual-only over the tested
  collider/hitboxes/AI (enemy_ai.gd untouched); on death the body **crumples** (bones blend limp:
  spine curl / knees buckle / arms drop) over the existing corpse tumble. True per-limb physics is
  blocked by the FBX's 100x `Root` import scale (sub-mm physics shapes → Jolt explodes, even the
  editor's own ragdoll); the crumple is the pose-only, scale-proof stand-in. Always-on, every mode.
  **Skin variety (Pass 1+2, done):** one model, swappable skin textures. Pass 1 — plain grunts rotate
  the protagonist set (criminal/skater♂/skater♀/cyborg) deterministically by spawn order, and each
  archetype reads its own fixed skin (rusher=skater♂, grenadier=criminal, sniper=skater♀,
  elite=cyborg), keyed by the `meta` RunDirector already stamps (decoupled, no enemy_ai/run_director
  edit) and still tinted toward its archetype hue. Pass 2 — **per-layer corruption**: the layer profile
  carries a `skin_set` key (declarative, like `kit`/palette); the Heap (corruption 0.5) sets
  `"corrupted"`, which mixes survivors-pack **zombie** skins into the plain rotation so a decayed memory
  reads as half-rotted (the survivors `characterMedium.fbx` is byte-identical to the protagonists' →
  zombie skins drop on the same rig, no new model/anim). Archetypes stay intact (their fixed skin +
  tint); ENDLESS/un-tagged layers unchanged. **Cel-shaded (done):** the rig now wears the toon
  material instead of a flat StandardMaterial3D — `_skin_model` builds it via
  `ToonApplicator.make_character_material(skin, tint)`, so the characters get the same hard-banded
  cel look + ink outline as the rest of the game. Two earlier blockers solved: `toon.gdshader` gained
  a back-compat (default-white) `albedo_texture` so the skin survives banding, and a new
  `toon_outline_scaled.gdshader` divides the outline offset by the model's world scale so the rig's
  ~62x scale no longer balloons the hull (width `0.03`). `CHARACTER_OK` (#42), all 44 harness scenes
  green. Next: deeper layers can opt into the ready `"zombies"` set; true physics if the FBX scale is
  fixed. See **Rigged enemy characters** in `context_systems.md`.
- **Enemy death: deletion VFX (computer-world)** — instead of a physics ragdoll, a dead enemy is
  DELETED: a glitch-dissolve wipes it out in place. `DeletionVFX` autoload (node_added observer like
  CharacterApplicator) hooks `enemy_died`, **freezes** the just-spawned corpse pieces (cancels the
  launch impulse before physics integrates → vanish in place, ZERO `enemy_ai.gd` edits), swaps their
  meshes to `shaders/deletion_dissolve.gdshader` (blocky cell dissolve + hot spectral-green emissive
  edge + RGB-split / scanline / vertex jitter, carrying over each enemy's own albedo), spawns a glowing
  data-bit burst, tweens the dissolve out (~0.55 s) and frees them. The ragdoll PHYSICS stays as the
  substrate — `DeletionVFX.enabled` (default ON, every mode) just layers the visual; the ragdoll
  harnesses toggle it OFF to keep testing the launch/gun-drop. The EnemyRig crumple still runs
  (orthogonal). `DELETION_VFX_OK` (#43), all 43 harnesses green; look eyeballed via
  `tools/deletion_preview.tscn`. See **Enemy death: deletion VFX** in `context_systems.md`.
- **Cosmetic shop ("Core Exchange")** — a holographic in-world shop (Roblox "Tuck Shop"-style):
  `ShopTerminal` (code-built Control on `shaders/hologram_panel.gdshader` — title / category tabs /
  scroll grid of `ShopItemCard`s / `CORES OWNED` footer / CLOSE) + `ShopTurntable` (lit spinning
  pedestal that swaps its display model per hovered item). Build-alongside + decoupled: the terminal
  is self-contained + asset-free (catalog = plain `Array[Dictionary]` from `ShopCatalog`, currency a
  local `cores` mirror, no autoload dep). `ShopController` bridges it to the persistent economy —
  `MetaProgression` gained a cosmetic track (`owned_cosmetics` + `buy_cosmetic`/`owns_cosmetic`,
  persisted in a `[cosmetics]` cfg section) alongside the upgrade track. Wired into the lobby as a
  code-built `ShopTerminal` Area3D station (mode/hack-station convention) that opens the overlay +
  freezes the player (RunDirector-style external freeze, no player.gd edit). Pass 1 (standalone
  terminal+turntable, `SHOP_OK` #45) + Pass 2 (lobby + Cores + persistence, `SHOP_LOBBY_OK` #46) +
  Pass 3 (theme polish) + Pass 4 (equip plumbing) + Pass 5 (juice/motion) + Pass 6 (3D tilt) done.
  **3D tilt (Pass 6):** the whole panel now reacts like a tilted glass slab as the cursor moves over
  it — `ShopTerminal` renders its entire content (holo backing + edge frame + every control) into a
  `SubViewport`, shown through a `SubViewportContainer` ("TiltView") wearing `shaders/panel_tilt.gdshader`;
  a `_process` loop eases a `tilt` uniform toward the cursor's offset from the panel's centre (zero when
  the mouse isn't over the panel) via `lerp`, the SpeedLines/glitch-overlay smoothing pattern. **The shear
  is a VERTEX shader displacement, not a fragment/UV warp**: the first cut warped UV inside a frozen
  rect, so the border/glow stayed axis-aligned and just clipped the warped content underneath (looked
  like the border was "excluded" from the tilt) — the fix moves the quad's actual corners in `vertex()`
  (scaled by a `panel_size` uniform the script keeps in sync, since `VERTEX` is pixels but `UV` is 0..1),
  so the whole silhouette shears as one rigid card; `fragment()` only adds the specular glare band sliding
  opposite the lean. Purely visual — `SubViewportContainer`'s normal input forwarding keeps buttons
  clickable underneath.
  GOTCHA avoided: don't chase visual artifacts in the LOBBY preview harness without isolating first — an
  early render showed a "duplicate title" ghost, traced (by nulling the shader, then by fully bypassing
  the SubViewport) to a PRE-EXISTING characteristic unrelated to this pass: the lobby preview's very
  close camera (1.5 units from the station) lets the station's own glowing 3D prop + floating world
  label bleed through the translucent glass panel, identical with or without the tilt code. **Juice (Pass 5):**
  every state change now eases instead of snapping — `ShopItemCard` keeps one persistent `StyleBoxFlat`
  and TWEENS its bg/border/border-width toward the target state (idle/hover/selected/equipped) instead
  of swapping stylebox instances, plus a hover scale bump (~1.035x), a purchase `pulse()` (scale+color
  punch) and a denied-purchase `shake()`; `ShopTerminal` eases the Cores number via a `tween_method`-
  driven `_cores_display` float (`set_cores(amount, animate)` — `animate=false` for the open-time
  resync-to-truth, `true` for an actual spend/reward so the number visibly counts); the panel itself
  now fades+scales in/out (`ShopTerminal.animate_open`/`animate_close`, tweening the `Frame` node) —
  `ShopController.open`/`close` call these instead of snapping `.visible`. All still code-only tweens,
  no new assets. **Equip (Pass 4):** a bought cosmetic can be
  equipped into its category slot (one per category, swaps on re-equip) — `MetaProgression`
  `equipped_cosmetics` + `equip_cosmetic`/`is_equipped`/`equipped_in`, persisted in an `[equipped]`
  cfg section; the card's primary button cycles PURCHASE → EQUIP → EQUIPPED with an accent border on
  the equipped card (`ShopTerminal.attempt_equip`/`item_equipped` → `ShopController._on_equipped`
  commits). DELIBERATELY plumbing-only: an equipped cosmetic has NO in-game effect yet (items
  unplanned) — it's just the owned→equipped bookkeeping + save hook for when items are designed.
  **Theme polish (Pass 3):** a code-built holo `Theme` (`scripts/ui/shop_theme.gd`,
  `class_name ShopTheme`, set on the terminal root so it styles only that subtree) gives the buttons
  state styleboxes, the category tabs a selected-fill (toggle buttons in a ButtonGroup), a thin holo
  scrollbar, a glowing panel-edge frame, a title+subtitle+underline header, and a two-tone currency
  footer; each card shows a custom-drawn vector glyph (`scripts/ui/shop_item_icon.gd`, `ShopItemIcon`
  — chair/sphere/helmet/torus/capsule/prism/box) instead of a flat swatch, plus hover + selected
  (turntable item) highlight. Still asset-free (no fonts shipped). Look eyeballed via
  `tools/shop_preview.tscn` (standalone, interactive) + `tools/shop_lobby_preview.tscn` (in-lobby).
  GOTCHA: `set_anchors_AND_OFFSETS_preset` (anchors-only keeps offsets → 0×0 collapse). Next: design
  the actual cosmetic items + what equipping each DOES (apply to player), real meshes/icons, lobby
  turntable beside the station, SFX.
- **Developer tools** — DevTools autoload, debug-build cheats (F1 god / F2 kill all / F3 refill / F5-F6 room jump / F7 layer jump). Plus a **Sandbox** test map (main-menu **TEST MAP** → `scenes/ui/sandbox.tscn`): a kitted free-play arena (every hack adjective unlocked + both abilities granted, hackable cubes over dummies) for trying new mechanics outside the run flow.
- **Current state** — running changelog of everything shipped so far.

Canonical docs are `context_architecture.md` + `context_systems.md`. If you find
an old `context.md` or `BRIEF.md`, they're the pre-split originals — superseded
by these two; don't read them.

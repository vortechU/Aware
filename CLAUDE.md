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
  tint); ENDLESS/un-tagged layers unchanged. `CHARACTER_OK` (#42), all 42 harnesses green. Next: deeper
  layers can opt into the ready `"zombies"` set; true physics if the FBX scale is fixed. See **Rigged
  enemy characters** in `context_systems.md`.
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
- **Developer tools** — DevTools autoload, debug-build cheats (F1 god / F2 kill all / F3 refill / F5-F6 room jump / F7 layer jump). Plus a **Sandbox** test map (main-menu **TEST MAP** → `scenes/ui/sandbox.tscn`): a kitted free-play arena (every hack adjective unlocked + both abilities granted, hackable cubes over dummies) for trying new mechanics outside the run flow.
- **Current state** — running changelog of everything shipped so far.

Canonical docs are `context_architecture.md` + `context_systems.md`. If you find
an old `context.md` or `BRIEF.md`, they're the pre-split originals — superseded
by these two; don't read them.

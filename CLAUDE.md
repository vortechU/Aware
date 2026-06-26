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
- **Modular kit skin (Kenney space-station)** — real visuals over the procgen layout:
  `RoomKit` skins the generated shell with the Kenney modular kit (floor/wall tiles via
  MultiMesh, props instanced), recoloured per-layer by multiplying the shared colormap
  atlas (Heap dim-green vs Stack steel-blue → major-transition variety). Visual-only over
  the tested collision (navmesh bakes from colliders, untouched). Gated on profile `"kit"`.
  Pass A + B + C done (`KIT_ROOM_OK`, generic skin over rect/L/T/plus, capability +
  forced-test); next = enable on real Heap/Stack layers (+ update `layer_look_test`).
  Assets in `Assets/kenney_*`.
- **Developer tools** — DevTools autoload, debug-build cheats (F1 god / F2 kill all / F3 refill / F5-F6 room jump / F7 layer jump). Plus a **Sandbox** test map (main-menu **TEST MAP** → `scenes/ui/sandbox.tscn`): a kitted free-play arena (every hack adjective unlocked + both abilities granted, hackable cubes over dummies) for trying new mechanics outside the run flow.
- **Current state** — running changelog of everything shipped so far.

Canonical docs are `context_architecture.md` + `context_systems.md`. If you find
an old `context.md` or `BRIEF.md`, they're the pre-split originals — superseded
by these two; don't read them.

# Aware

> A first-person arena shooter built in **Godot 4.6.3 / GDScript**, extended into an
> infinite-room roguelite with a layered narrative campaign set inside the memory of a
> machine that is slowly becoming *aware*.

**Genre:** FPS · Roguelite · Single-player &nbsp;|&nbsp; **Engine:** Godot 4.6.3 (Forward+, Jolt Physics) &nbsp;|&nbsp; **Language:** GDScript &nbsp;|&nbsp; **Status:** In active development

---

## 🎥 About this project — an AI programming experiment

This game is being built by me as a **YouTube series** with one question driving the whole
thing: **can AI actually program an entire game, start to finish — or not?**

Rather than writing the code by hand, I direct an AI coding agent to design, implement, test,
and iterate on every system in the game. My role is the creative director and reviewer: I set
goals, make design calls, playtest, and push back — the AI does the programming. Every feature
you see in this repo was implemented through that workflow, one mechanic at a time, each one
verified before moving to the next.

So this repository is two things at once:
1. **A real game** — a playable, growing FPS roguelite.
2. **The receipts** — a transparent, version-controlled record of how far an AI can get when
   asked to build something genuinely complex.

> 📺 **Follow the series:** _link coming soon_ — watch each system get designed and built live.

If you're here from the videos: the commit history *is* the story. Read it top to bottom.

---

## 🎮 The game

**Aware** starts as a fast, movement-heavy arena shooter and turns into an infinite-room
roguelite. You fight through procedurally generated rooms, clear each one, choose an upgrade,
and push deeper — permadeath, then back to the lobby to spend what you earned.

Layered on top of the endless mode is a **finite narrative campaign** themed around the regions
of a computer's memory. You descend through named layers — **Heap → Stack → Cache → Kernel →
I/O Buffer** — piecing together the story of a consciousness waking up inside the machine through
**memory fragments** scattered in the world.

Two ways to play, selectable from the lobby:
- **Campaign** (default) — the structured, story-driven descent through the layers.
- **Endless** — the original infinite roguelite loop, preserved untouched.

The look is a clean **cel-shaded** style on primitive geometry — readable, stylized, and built
to ship fast.

---

## ✨ Features

**Core combat & movement**
- First-person controller with walk / sprint / crouch / prone / slide
- Advanced movement: **wall-running, dashing, vaulting, double-jump**, and a **momentum** system
  where chained movement raises your top speed
- 3 hitscan weapons with recoil, ADS, and rig animation
- Stamina, health + armor (armor soaks 30% of incoming damage), regen, and death

**Enemies**
- State-machine AI (patrol / alert / chase / attack / search / cover / flank) with vision cones
  and hearing
- Three **enemy archetypes** that mix into squads by depth: **Rusher** (fast, fragile charger),
  **Sniper** (telegraphed long-range marksman), **Grenadier** (arcing AoE area-denial)
- **Combat fairness** systems: enemy aim widens while you pull movement tricks, and aware agile
  enemies reactively dodge shots that whiz past
- Physics-driven **death ragdolls** — corpses fly along the actual bullet direction, headshots
  pop the head off, and the gun always drops as its own piece

**Roguelite run system**
- Procedural room generation with **variable footprints** (square / rectangular / L-shaped) and
  **navigable verticality** (climbable platforms, ramps, and elevated player-only rewards)
- Exit-gate room transitions with a Matrix-style binary-spiral shader wipe
- Upgrade-card draft between rooms (with a digital-glitch UI shader)
- Elite / milestone rooms every 5th room (endless)

**Progression & systems**
- **Meta progression** — a 3D lobby hub where you spend **Cores** earned on death for permanent
  upgrades, persisted between runs
- **Active abilities** — hotkey, cooldown-based powers unlocked in-run (Stack Smash, Overclock),
  with a 2-slot loadout
- **Environment Hacking ("Injection")** — aim at a world prop and inject an *adjective* (Heavy,
  Shocking, …) that rewrites its behavior for a few seconds, gated by a regenerating **RAM** meter
- **Narrative layers** — per-layer materials, fog, and lighting so each memory region reads as a
  distinct place; a **Fragment** system that surfaces the story in the world

**Presentation**
- Cel-shaded toon rendering with outlines (`ToonApplicator`)
- Bullet tracers + fading impact decals
- A signal-driven audio registry (scaffolded; assets pending)

**Developer tooling**
- A **Sandbox** test map (Main Menu → *TEST MAP*) — a kitted free-play arena with every hack
  adjective and both abilities unlocked, for trying mechanics outside the run flow
- Debug-build cheats: F1 god mode · F2 kill all · F3 refill · F5/F6 jump room · F7 jump layer
- **52 headless test harnesses** under `tools/` covering nearly every system (see [Testing](#-testing--verification))

---

## 🛠️ Tech stack

| | |
|---|---|
| **Engine** | Godot 4.6.3 |
| **Language** | GDScript |
| **Renderer** | Forward+ (D3D12 on Windows) |
| **Physics** | Jolt Physics (3D) |
| **Architecture** | Signal-bus driven (`GameEvents` autoload); 10 autoloads total |
| **Main scene** | `res://scenes/ui/main_menu.tscn` |

---

## 🚀 Getting started

### Prerequisites
- **Godot 4.6.3** (Standard / GDScript build) — [download here](https://godotengine.org/download/archive/)
- On Windows the project targets the **D3D12** rendering driver and **Jolt** physics (both
  bundled with Godot 4.6.3).

### Run it
```bash
# 1. Clone
git clone https://github.com/vortechU/Aware.git
cd Aware

# 2. Open in Godot
#    Launch Godot 4.6.3, "Import" this folder's project.godot, and Run (F5).
#    On first open Godot rebuilds its import cache (the ignored .godot/ folder) automatically.
```

Or open `project.godot` directly from the Godot Project Manager. The game boots to the main menu;
from there choose **PLAY** for the lobby/run flow or **TEST MAP** for the sandbox.

---

## 🎯 Controls

| Action | Bind |
|---|---|
| Move | `W` `A` `S` `D` |
| Jump / Double-jump | `Space` |
| Sprint | `Shift` |
| Crouch | `C` / `Ctrl` |
| Prone | `Z` |
| Dash | `Q` |
| Fire | `Left Mouse` |
| Aim down sights | `Right Mouse` |
| Reload | `R` |
| Switch weapon | `1` `2` `3` / `Mouse Wheel` |
| Ability 1 / Ability 2 | `F` / `G` |
| Hack (hold for radial wheel) | `V` |
| Interact | `E` |

> Wall-run, vault, and slide trigger contextually from movement — there's no dedicated key.
> Key binds are rebindable in **Settings**.

---

## 📁 Project structure

```
aware/
├── project.godot              # Godot project config (autoloads, input map, layers)
├── scenes/
│   ├── main.tscn              # Root gameplay scene (driven by game_manager.gd)
│   ├── player/                # Player scene
│   ├── enemies/ · pickups/    # Spawned entities
│   └── ui/                    # main_menu · lobby · hud · run_hud · sandbox
├── scripts/
│   ├── player/                # FPS controller, abilities, hacking
│   ├── weapons/ · enemies/    # Weapon manager, enemy AI, archetypes
│   ├── run/ · world/ · ui/    # Run system, world props, HUD/menus
│   ├── components/ · pickups/ # Health/hitbox components, pickups
│   └── game_manager.gd        # Base-game flow (left untouched by the roguelite layer)
├── autoloads/                 # 10 singletons: GameEvents, RunManager, MetaProgression,
│                              #   SettingsManager, AudioManager, ToonApplicator, WeaponClip,
│                              #   BulletFX, FragmentDB, DevTools
├── shaders/                   # toon · toon_outline · toon_viewmodel · ui_glitch · matrix_spiral
├── data/weapons/              # WeaponData .tres resources
├── audio/                     # Audio registry + sourcing notes (assets pending)
├── tools/                     # 52 headless test harnesses + visual preview scenes
└── *.md                       # Design docs (see below)
```

### Design & context docs
This repo is documented for an AI-driven workflow. The Markdown files at the root are the
working memory that keeps the build coherent across sessions:
- **`CLAUDE.md`** — the entry point: prime directives and a map of every system.
- **`context_architecture.md`** — always-true invariants: engine info, base architecture, and the
  full headless verification process.
- **`context_systems.md`** — detailed per-feature documentation (read on demand).
- **`*_plan.md`** — living design plans for in-progress systems (abilities, hacking, verticality,
  room generation).

---

## 🧪 Testing & verification

Because there's no QA team, **correctness is enforced by an automated harness suite** — 52
in-engine test scenes under `tools/`, each asserting a system's behavior and printing an `*_OK`
sentinel on success. These run **headless**, so any change can be validated without opening the
editor.

The canonical run order (Windows / PowerShell):

```powershell
$godot = "Godot_v4.6.3.exe"   # path to your Godot 4.6.3 binary

# 1. Rebuild import + class cache (run first after adding class_name scripts)
& $godot --headless --path . --import

# 2. Core checks — each should print its sentinel
& $godot --headless --path . res://tools/script_check.tscn       # CHECK_OK   (loads every .gd/.tscn/.tres)
& $godot --headless --path . res://tools/smoke_test.tscn         # SMOKE_OK   (base integration)
& $godot --headless --path . res://tools/run_smoke_test.tscn     # RUN_SMOKE_OK (full roguelite loop)
# …plus per-system harnesses: movement, abilities, hacking, enemy archetypes,
#   layered world, verticality, lobby, menu, transitions, and more.
```

> On Windows the Godot executable detaches from the console, so to read an exit code use
> `Start-Process -Wait -PassThru` and inspect `.ExitCode`. See `context_architecture.md` for the
> complete, numbered list of all harnesses and what each one proves.

---

## 🧭 Development philosophy

One rule shapes the whole codebase: **build alongside, never rewrite.** New systems are layered
on top of the original FPS scripts rather than editing them — the roguelite takes over the game
flow at runtime via signal disconnects instead of rewriting `game_manager.gd`. Cross-system
communication goes through a single global signal bus (`GameEvents`) so the player, weapons,
enemies, and managers never reference each other directly.

This keeps each addition isolated, testable, and reversible — which matters a great deal when an
AI is doing the implementation and every change needs to be verifiable in isolation.

---

## 🗺️ Roadmap

**Shipped**
- Full base FPS + roguelite run loop (procedural rooms, upgrades, permadeath)
- 3 enemy archetypes, combat-fairness AI, polished death ragdolls
- Meta progression (lobby + Cores), active abilities, environment hacking
- Cel-shading, bullet FX, navigable verticality, per-layer visual identity
- **The full Heap track** (narrative Layer 01) + **The Stack** (Layer 02) and the descent beat

**Next up**
- Narrative **Layers 3–5**: Cache, Kernel, and the I/O Buffer
- The **Kernel Panic** boss and the story's climactic **Choice**
- More hacking adjectives (Volatile, Floating, Bouncy, Repulsive)
- Remaining audio passes (footsteps, reload, pickups, UI, music) + volume sliders
- Squad coordination AI and movement playtest tuning

---

## 📄 License

No license has been chosen yet — by default this means **all rights reserved**. If you'd like to
use any of this code, please open an issue or reach out first. A license may be added as the
project matures.

---

## 🙏 Acknowledgements

- Built with [**Godot Engine**](https://godotengine.org/).
- Programmed by an AI coding agent under human direction, as documented above — the entire point
  of the experiment.

*Aware is a work in progress. Stars, issues, and feedback are all welcome — and if you're
following along on YouTube, thanks for watching the machine wake up.*

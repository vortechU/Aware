# Audio assets

`AudioManager` (`autoloads/audio_manager.gd`) looks up every sound by a logical
**key** and loads it from this folder. Drop a file at the matching path, let
Godot import it (open the editor once, or run `--import`), and it plays — no
code change needed. A missing file just stays silent.

## File format & naming

- Use the **base name** below (no extension). Any of `.ogg`, `.wav`, `.mp3`
  works; the manager probes them in that order.
- Short SFX → `.wav` or `.ogg`. Music/stings → `.ogg`.
- Keep SFX mono so 3D positioning works (enemy fire/deaths are positional).
- Aim for roughly consistent loudness; per-bus mixing is handled in code.

## Sounds wanted

`[live]` = already wired to a trigger and will play as soon as the file exists.
The rest load if present but get hooked up in a later pass.

### sfx/weapons/
| file | when it plays |
|------|---------------|
| `pistol_fire`    | `[live]` player fires the pistol |
| `rifle_fire`     | `[live]` player fires the rifle (full-auto — keep it short/tight) |
| `shotgun_fire`   | `[live]` player fires the shotgun |
| `enemy_fire`     | `[live]` any enemy gunshot (positional 3D) |
| `weapon_switch`  | `[live]` swapping weapons |
| `reload`         | later — reload start |
| `dry_fire`       | later — trying to fire on an empty mag |

### sfx/impacts/
| file | when it plays |
|------|---------------|
| `hitmarker`     | `[live]` a shot connects with an enemy body |
| `headshot`      | `[live]` a shot connects with an enemy head |
| `bullet_impact` | later — round hits geometry/walls |

### sfx/enemies/
| file | when it plays |
|------|---------------|
| `enemy_death` | `[live]` an enemy dies (positional 3D) |
| `enemy_alert` | later — enemy first spots the player |

### sfx/player/
| file | when it plays |
|------|---------------|
| `player_hurt`  | `[live]` player takes damage |
| `player_death` | `[live]` player dies |
| `low_health`   | `[live]` health drops below 25% (one-shot warning) |
| `footstep`     | later — movement |
| `jump`         | later — jump |
| `land`         | later — landing |
| `dash`         | later — dash burst |
| `slide`        | later — slide start |

### sfx/pickups/
| file | when it plays |
|------|---------------|
| `pickup_ammo`   | later — ammo crate |
| `pickup_health` | later — health pack |
| `pickup_armor`  | later — armor pack |
| `core_gained`   | `[live]` meta currency (cores) gained |

### ui/
| file | when it plays |
|------|---------------|
| `run_start`      | `[live]` a run begins |
| `room_cleared`   | `[live]` a room is cleared (short jingle) |
| `ui_click`       | later — menu button press |
| `ui_hover`       | later — menu button hover |
| `upgrade_select` | later — choosing an upgrade card |

### music/
| file | when it plays |
|------|---------------|
| `victory` | `[live]` run won / game won (sting) |
| `defeat`  | `[live]` run lost / game lost (sting) |
| `menu`    | later — looping menu track |
| `combat`  | later — looping combat track |

## Mixing buses

`Master → { Music, SFX, UI }`, created at runtime. Volumes (0..1) live in
`user://audio.cfg` and will be exposed as sliders in the settings menu in a
later pass.

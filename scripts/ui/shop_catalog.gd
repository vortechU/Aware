class_name ShopCatalog
extends RefCounted
## Single source of truth for the cosmetic shop's stock. Plain data (id / name /
## category / cost / display shape / tint) so the standalone preview, the lobby
## ShopController, and the headless tests all read the same list. Cosmetic-only
## for now (chairs/gear/effects/titles), priced in Cores; ownership is tracked
## by id in MetaProgression. Returns fresh dictionaries each call so callers can
## never mutate a shared entry.

static func items() -> Array[Dictionary]:
	return [
		{"id": "neon_chair", "name": "Neon Throne", "category": "Chairs", "cost": 1200,
			"shape": "chair", "color": Color(0.3, 1.0, 0.6)},
		{"id": "void_chair", "name": "Void Seat", "category": "Chairs", "cost": 9800,
			"shape": "chair", "color": Color(0.6, 0.4, 1.0)},
		{"id": "glitch_helm", "name": "Glitch Helm", "category": "Gear", "cost": 3400,
			"shape": "helmet", "color": Color(1.0, 0.5, 0.3)},
		{"id": "core_orb", "name": "Core Orb", "category": "Effects", "cost": 800,
			"shape": "sphere", "color": Color(0.3, 0.9, 1.0)},
		{"id": "ram_ring", "name": "Ring of RAM", "category": "Effects", "cost": 15000,
			"shape": "torus", "color": Color(1.0, 0.85, 0.3)},
		{"id": "stack_pylon", "name": "Stack Pylon", "category": "Gear", "cost": 2600,
			"shape": "prism", "color": Color(0.4, 1.0, 0.85)},
		{"id": "kernel_cell", "name": "Kernel Cell", "category": "Titles", "cost": 500,
			"shape": "capsule", "color": Color(0.9, 0.4, 0.8)},
		{"id": "data_cube", "name": "Data Cube", "category": "Titles", "cost": 4200,
			"shape": "box", "color": Color(0.5, 0.8, 1.0)},
	]

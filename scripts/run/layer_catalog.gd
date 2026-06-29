class_name LayerCatalog
extends RefCounted
## Static catalog of the game's narrative layers -- the GDD's five "stages":
## Heap -> Stack -> Cache -> Kernel -> I/O Buffer. CAMPAIGN runs walk these in
## order; each LayerProfile re-skins the SHARED RoomBuilder pipeline (mood,
## footprint bias, archetype pool) and bounds how many rooms the layer occupies.
##
## Build-alongside: this only describes how to flavour the existing generator, it
## does not replace it. RunManager.current_room keeps counting globally across the
## whole run in BOTH modes, so every enemy / scaling / archetype curve is
## unchanged; a layer simply owns a contiguous band of global rooms (Heap = 1..6).
##
## Pass 1 fills in only the Heap. The other four layers are intentionally absent
## until their own passes; profile_for_room() clamps to the last defined layer for
## any room beyond the catalog, so a campaign run never falls off the end.

## Per-sector room kind. COMBAT is a normal generated arena fight; FRAGMENT and
## GHOST are non-combat breather rooms (no enemies; the exit gate is up on arrival)
## that Pass 3/4 flesh out (Memory Fragment reader; corrupted-echo visuals). A
## layer's `room_sequence` lists one of these per sector; absent/short = COMBAT.
enum RoomType { COMBAT, FRAGMENT, GHOST }

## footprint_pool values are indices into RoomBuilder's combined footprint list
## [FOOTPRINTS (0-9) + L_FOOTPRINTS (10-13) + T_FOOTPRINTS (14-15) + PLUS_FOOTPRINTS (16-17)]:
##   0=17sq 1=21sq 2=24sq 3=27x16 4=16x27 5=26x18 6=14tight 7=28x11corridor
##   8=11x28corridor 9=30x28grand   10,11,12,13 = L-shapes (13 = bold deep L)
##   14,15 = T-shapes (wide crossbar + north stem)   16,17 = plus/cross (four arms).
## An empty/absent pool means "the full range" (the endless-mode default).
const LAYERS: Array[Dictionary] = [
	{
		"id": "heap",
		"title": "THE HEAP",
		"tag": "HEAP",                                   # short banner/label tag
		"arc": "awakening",                              # which FragmentDB arc this layer surfaces
		"room_count": 6,                                 # global rooms 1..6
		# Per-sector kind. Sector 1 is the authored "home" arena (always combat);
		# sectors 3 + 5 are non-combat breathers (a Fragment, then a Ghost echo).
		"room_sequence": [RoomType.COMBAT, RoomType.COMBAT, RoomType.FRAGMENT,
			RoomType.COMBAT, RoomType.GHOST, RoomType.COMBAT],
		"archetype_pool": ["open_field", "scattered_cover", "pillar_hall"],
		# Large + corridor + irregular; skips the small/standard/tight squares (0,1,6)
		# so the Heap reads big + oppressive. 2-5 large rects, 7/8 corridors, 9 grand,
		# 10-13 all L-shapes (incl. the bold deep L), 14-15 T-shapes, 16-17 plus/cross.
		"footprint_pool": [2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17],
		"mood_tint": Color(0.42, 0.62, 0.72),            # cold, sickly blue-green
		"mood_strength": 0.7,                            # how hard to pull the sun toward the tint
		"sun_energy_factor": 0.6,                        # dim + oppressive vs the authored arena
		"corruption": 0.5,                               # GDD Heap = 40-60%; drives atmosphere density
		"ghost_tint": Color(0.5, 0.95, 0.6),             # spectral green for Ghost (corrupted-echo) rooms
		# Surface palette + fog so the layer reads as a distinct PLACE, not just a
		# differently-tinted box. Heap = decayed organic memory: murky green-gray
		# surfaces, a sickly green depth haze, low ambient. (Empty/endless = the
		# authored gray materials + no fog, so the legacy look is untouched.)
		"floor_color": Color(0.19, 0.23, 0.21),
		"wall_color": Color(0.24, 0.29, 0.26),
		"struct_color": Color(0.28, 0.33, 0.29),
		"fog_color": Color(0.16, 0.26, 0.22),
		"fog_density": 0.020,
		"ambient_energy": 0.7,
		# Visual skin: the fine-grid Kenney space-station kit overlays the shell, recoloured
		# by the palette above (RoomBuilder._skin_shell, visual-only over the tested collision).
		"kit": "space_station",
		# Enemy skins: a decayed memory (corruption 0.5) mixes zombie grunts into the
		# protagonist rotation (CharacterApplicator.SKIN_SETS). Archetypes stay intact.
		"skin_set": "corrupted",
	},
	{
		"id": "stack",
		"title": "THE STACK",
		"tag": "STACK",
		"arc": "history",                                # the GDD's History Arc (Meridian/SYSLOG)
		"room_count": 6,                                 # global rooms 7..12
		# Order enforced: combat-dense, one History fragment mid-layer, no breathers.
		"room_sequence": [RoomType.COMBAT, RoomType.COMBAT, RoomType.COMBAT,
			RoomType.FRAGMENT, RoomType.COMBAT, RoomType.COMBAT],
		# Rigid, orthogonal layouts; the re-skin's reading of "strict grid". The Stack
		# is literally a stack -- so it's the layer that opts into the vertical "tiers"
		# archetype (raised platforms the player climbs; enemies stay grounded).
		"archetype_pool": ["pillar_hall", "maze_lanes", "arena_cross", "tiers"],
		# Rectangular only (no L-rooms): the Stack's "strict grid". Now spans the full
		# rect range -- tight chamber (6), corridors (7,8) and the grand arena (9) --
		# so a stack of memory reads as cramped cells AND long halls, not one size.
		"footprint_pool": [1, 2, 3, 4, 5, 6, 7, 8, 9],
		"mood_tint": Color(0.70, 0.78, 0.86),            # sterile steel-blue: order, not decay
		"mood_strength": 0.6,
		"sun_energy_factor": 0.85,                       # cleaner + brighter than the Heap
		"corruption": 0.12,                              # GDD Stack = 10-15%; sparse atmosphere
		# Stack = sterile order: clean steel-blue surfaces, only a faint cool haze,
		# brighter ambient. The opposite read from the Heap's organic murk.
		"floor_color": Color(0.28, 0.32, 0.38),
		"wall_color": Color(0.40, 0.45, 0.53),
		"struct_color": Color(0.34, 0.40, 0.49),
		"fog_color": Color(0.45, 0.52, 0.62),
		"fog_density": 0.005,
		"ambient_energy": 1.05,
		# Visual skin: the chunky 4 m Kenney modular-space kit -- a different pack from the
		# Heap, so descending into the Stack swaps the whole look, not just the tint.
		"kit": "modular_space",
	},
]


## The profile whose global-room band contains `room`. Beyond the last defined
## layer, clamps to the last (pass-1 behaviour until more layers + descents ship).
static func profile_for_room(room: int) -> Dictionary:
	var start := 1
	for layer in LAYERS:
		var end := start + int(layer.room_count) - 1
		if room <= end:
			return layer
		start = end + 1
	return LAYERS[LAYERS.size() - 1]


## 1-based layer number for a global room. Clamps to the last layer past the catalog.
static func layer_index_for_room(room: int) -> int:
	var start := 1
	for i in LAYERS.size():
		var end := start + int(LAYERS[i].room_count) - 1
		if room <= end:
			return i + 1
		start = end + 1
	return LAYERS.size()


## 1-based room number WITHIN its layer (the "sector"). Past the catalog it keeps
## counting on from the last layer's start so the number never goes negative.
static func room_in_layer_for_room(room: int) -> int:
	var start := 1
	for layer in LAYERS:
		var end := start + int(layer.room_count) - 1
		if room <= end:
			return room - start + 1
		start = end + 1
	return room - start + 1


## The RoomType for a global room: index this room's sector into its layer's
## `room_sequence`. Defaults to COMBAT when the layer omits a sequence or the
## sector runs past it (e.g. an over-run past the last defined layer).
static func room_type_for(room: int) -> int:
	var seq: Array = profile_for_room(room).get("room_sequence", [])
	var sector := room_in_layer_for_room(room)
	if sector >= 1 and sector <= seq.size():
		return int(seq[sector - 1])
	return RoomType.COMBAT

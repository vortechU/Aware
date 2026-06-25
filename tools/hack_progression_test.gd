extends Node
## Headless test for hacking progression, Pass 5 (HACK_PROGRESSION_OK).
## Run: godot --headless --path . res://tools/hack_progression_test.tscn
##
## Two halves, mirroring the design (Cores unlock the WORD, in-run cards RANK it):
##   - CORES UNLOCK: MetaProgression.buy("hack_heavy") is a one-time unlock that persists
##     to meta_progress.cfg; on an ARMED run that owned adjective is unlocked on the fresh
##     player's HackManager, while an UNARMED player stays vanilla.
##   - IN-RUN RANK: PlayerUpgrades.apply_upgrade("heavy") routes a trait card to the
##     HackManager -- first pick grants rank 1, a repeat ranks up; a non-adjective id is
##     rejected.
## Snapshots + restores user://meta_progress.cfg so the real save is untouched.

const META_PATH := "user://meta_progress.cfg"
const PLAYER := preload("res://scenes/player/player.tscn")

var fails: Array[String] = []
var _had_meta := false
var _meta_backup := PackedByteArray()
var _saved_cores := 0
var _saved_levels := {}


func _ready() -> void:
	_snapshot_meta()
	await _run()
	_restore_meta()
	if fails.is_empty():
		print("HACK_PROGRESSION_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("HACK_PROGRESSION_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _snapshot_meta() -> void:
	_had_meta = FileAccess.file_exists(META_PATH)
	if _had_meta:
		_meta_backup = FileAccess.get_file_as_bytes(META_PATH)
	_saved_cores = MetaProgression.cores
	_saved_levels = MetaProgression.upgrade_levels.duplicate()


func _restore_meta() -> void:
	MetaProgression.cores = _saved_cores
	MetaProgression.upgrade_levels = _saved_levels.duplicate()
	MetaProgression.run_bonuses_armed = false
	if _had_meta:
		var f := FileAccess.open(META_PATH, FileAccess.WRITE)
		f.store_buffer(_meta_backup)
		f.close()
	else:
		var d := DirAccess.open("user://")
		if d != null and d.file_exists("meta_progress.cfg"):
			d.remove("meta_progress.cfg")


func _spawn_player() -> Player:
	var p: Player = PLAYER.instantiate()
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame  # let MetaProgression._apply_player_deferred run
	return p


func _run() -> void:
	# ---- CORES UNLOCK: buy persists + maxes a 1-level unlock ----
	MetaProgression.cores = 1000
	MetaProgression.upgrade_levels["hack_heavy"] = 0
	MetaProgression.upgrade_levels["hack_shocking"] = 0
	_check(MetaProgression.buy("hack_heavy"), "buying hack_heavy should succeed with Cores")
	_check(MetaProgression.level_of("hack_heavy") == 1, "hack_heavy should be owned after buying")
	_check(MetaProgression.next_cost("hack_heavy") == -1, "a 1-level unlock is maxed after buying")
	var cfg := ConfigFile.new()
	cfg.load(META_PATH)
	_check(int(cfg.get_value("upgrades", "hack_heavy", 0)) == 1, "the unlock should persist to disk")

	# ---- APPLY ON SPAWN: armed player gets the owned word; unarmed stays vanilla ----
	MetaProgression.run_bonuses_armed = true
	var armed := await _spawn_player()
	var hm_armed: HackManager = armed.get_node("HackManager")
	_check(hm_armed.is_unlocked("heavy"), "an owned adjective should be unlocked on an armed player")
	_check(not hm_armed.is_unlocked("shocking"), "an unowned adjective should stay locked")
	armed.queue_free()
	await get_tree().process_frame

	MetaProgression.run_bonuses_armed = false
	var vanilla := await _spawn_player()
	_check(not (vanilla.get_node("HackManager") as HackManager).is_unlocked("heavy"),
			"an unarmed player should stay vanilla (no unlocks)")
	vanilla.queue_free()
	await get_tree().process_frame

	# ---- IN-RUN RANK: a trait card grants then ranks the adjective ----
	var p3 := await _spawn_player()
	var pu: PlayerUpgrades = p3.get_node("PlayerUpgrades")
	var hm3: HackManager = p3.get_node("HackManager")
	_check(not hm3.is_unlocked("heavy"), "a fresh unarmed player starts with Heavy locked")
	pu.apply_upgrade("heavy")
	_check(hm3.rank_of("heavy") == 1, "the first trait card should grant Heavy at rank 1")
	pu.apply_upgrade("heavy")
	_check(hm3.rank_of("heavy") == 2, "a repeat trait card should rank Heavy up to 2")
	_check(not hm3.rank_up("not_an_adjective"), "rank_up should reject a non-adjective id")
	p3.queue_free()
	await get_tree().process_frame

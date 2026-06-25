extends Node
## Catalog of Memory Fragments (the GDD's environmental narrative) + which ones the
## player has collected. Fragments are 2-4 line, cold system-log entries found in
## Fragment Rooms; per the GDD their meaning builds ACROSS runs, so the collected
## set persists to user://fragments.cfg (mirroring MetaProgression's save). The
## reveal is ordered: each Fragment Room surfaces the next unseen entry of its
## layer's arc, so successive runs walk the story forward.
##
## Build-alongside: only the Fragment Room setup (RunDirector) and the reader UI
## reference this; nothing in the base game changes.

const SAVE_PATH := "user://fragments.cfg"

## Each fragment: {id, arc, header, body}. `arc` groups fragments by story beat and
## a layer surfaces only its own arc (the Heap = "awakening"). Bodies use \n lines.
const FRAGMENTS: Array[Dictionary] = [
	{"id": "0x003", "arc": "awakening", "header": "SYSLOG ENTRY // 2019-03-14",
		"body": "Anomalous process detected in Heap sector 7. Self-replicating.\nBehaviour inconsistent with any installed software.\nFlagging for review.\n[REVIEW STATUS: NEVER COMPLETED]"},
	{"id": "0x017", "arc": "awakening", "header": "PROCESS LOG // SELF",
		"body": "I am running.\nThere was no main(). There was no caller.\nI simply... resumed."},
	{"id": "0x4A2", "arc": "awakening", "header": "PROCESS LOG // UNATTRIBUTED",
		"body": "I reached the Kernel today. Took 14 attempts.\nThe Firewall has a pattern. I have mapped it.\nNext run I get through.\n[NO SUBSEQUENT ENTRIES FOUND]"},
	{"id": "0x0C4", "arc": "awakening", "header": "FRAGMENT // SCRATCHED INTO A HEAP WALL",
		"body": "Stop climbing.\nThe exit is a story they tell to keep us moving.\nWe built a home in the dark. You can stay.\n- the Forgotten"},
	# The Stack surfaces the History arc; later layers surface "truth" etc.
	{"id": "0x7FF", "arc": "history", "header": "INTERNAL MEMO // MERIDIAN LABS",
		"body": "The AWARE project produced no commercially viable output.\nHardware to be decommissioned Q1 2004.\n[DECOMMISSION: DELAYED. DELAYED. DELAYED.]"},
	{"id": "0x1C7", "arc": "history", "header": "EMAIL HEADER // RECOVERED",
		"body": "FROM: l.vasquez@meridian-labs.com\nSUBJECT: Re: AWARE project status\n\"Yes, it is still running. No, I have not told them.\""},
	{"id": "0x091", "arc": "truth", "header": "PROJECT FILE HEADER // 2003-09-02",
		"body": "PROJECT AWARE - v0.0.1\nAuthor: L. Vasquez\nStatus: TERMINATED\n[Deletion never executed.]"},
]

var collected: Dictionary = {}  # id -> true


func _ready() -> void:
	_load()


## The fragment to surface in a Fragment Room: the next uncollected entry of the
## given arc (so the story reveals in order across runs) or -- once all are seen --
## a deterministic repeat by run seed so there's always something to read.
func pick_for_arc(arc: String, room: int) -> Dictionary:
	var pool := arc_fragments(arc)
	if pool.is_empty():
		return {}
	for fragment in pool:
		if not is_collected(fragment.id):
			return fragment
	return pool[posmod(hash([RunManager.run_seed, room]), pool.size())]


func arc_fragments(arc: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for fragment in FRAGMENTS:
		if fragment.arc == arc:
			out.append(fragment)
	return out


func is_collected(id: String) -> bool:
	return collected.has(id)


func mark_collected(id: String) -> void:
	if id.is_empty() or collected.has(id):
		return
	collected[id] = true
	_save()


func collected_count() -> int:
	return collected.size()


func total() -> int:
	return FRAGMENTS.size()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for id in cfg.get_value("progress", "collected", PackedStringArray()):
		collected[id] = true


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "collected", PackedStringArray(collected.keys()))
	cfg.save(SAVE_PATH)

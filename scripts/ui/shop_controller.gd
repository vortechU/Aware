class_name ShopController
extends Node
## Bridges the standalone ShopTerminal view to the persistent MetaProgression
## Cores economy, and owns the open/close + mouse handling for the in-world shop.
##
## Build-alongside: the terminal stays fully decoupled (its `cores` is a local
## display mirror, its `_owned` a local set). This adapter is the only thing that
## knows about MetaProgression -- on open it syncs the terminal FROM the save, and
## on each purchase it commits the real spend + ownership back TO the save. So the
## terminal remains reusable (preview / sandbox) with no autoload dependency.

signal opened
signal closed

const TERMINAL := preload("res://scripts/ui/shop_terminal.gd")

## Optional world display beside the panel; if set, hovering a card spins it.
var turntable: ShopTurntable
var is_open := false

var _layer: CanvasLayer
var _terminal: ShopTerminal


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # usable on a paused tree, like the run HUD
	_layer = CanvasLayer.new()
	_layer.layer = 50  # above the lobby HUD
	add_child(_layer)

	_terminal = TERMINAL.new()
	_terminal.visible = false
	_layer.add_child(_terminal)
	_terminal.set_catalog(ShopCatalog.items())
	_terminal.item_purchased.connect(_on_purchased)
	_terminal.item_equipped.connect(_on_equipped)
	_terminal.closed.connect(close)
	if turntable != null:
		_terminal.item_focused.connect(turntable.show_item)

	MetaProgression.cores_changed.connect(_on_cores_changed)


func open() -> void:
	if is_open:
		return
	is_open = true
	_sync_from_meta()
	_terminal.animate_open()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if turntable != null:
		var items := ShopCatalog.items()
		if not items.is_empty():
			turntable.show_item(items[0])
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_terminal.animate_close()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


## The wrapped view (for hosts/tests that need to drive or inspect it).
func terminal() -> ShopTerminal:
	return _terminal


func _unhandled_input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ economy bridge

## Pull the persistent save state into the terminal: real Cores + owned + equipped.
## Cores sync instantly (animate=false) -- this is a resync-to-truth on open, not
## a reward moment, so it should never play a spurious count-up/down.
func _sync_from_meta() -> void:
	_terminal.set_cores(MetaProgression.cores, false)
	for item: Dictionary in ShopCatalog.items():
		var id := String(item.get("id", ""))
		if MetaProgression.owns_cosmetic(id):
			_terminal.mark_owned(id)
		if MetaProgression.is_equipped(id):
			_terminal.mark_equipped(id, String(item.get("category", "")))


## The terminal already gated + mirrored the buy locally (and played the spend
## count-up itself); commit the real spend to MetaProgression (which persists),
## then reconcile the display to the save -- instantly, since the terminal
## already animated this same transition a moment ago.
func _on_purchased(item: Dictionary) -> void:
	var id := String(item.get("id", ""))
	MetaProgression.buy_cosmetic(id, int(item.get("cost", 0)))
	_terminal.set_cores(MetaProgression.cores, false)


## Commit an equip choice to the persistent save (no Cores cost).
func _on_equipped(item: Dictionary) -> void:
	MetaProgression.equip_cosmetic(String(item.get("id", "")), String(item.get("category", "")))


func _on_cores_changed(total: int) -> void:
	if is_open:
		_terminal.set_cores(total)

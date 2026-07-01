extends Node
## Look harness (NOT shipped game code) for shop Pass 2: loads the real lobby,
## walks the player onto the Core Exchange station, opens the shop, and saves a
## PNG -- so the panel can be eyeballed in its actual in-world context. Run
## NON-headless (the holo shader needs a real renderer):
##   Godot.exe --path . res://tools/shop_lobby_preview.tscn
## Saves res://tools/shop_lobby_preview.png.

const LOBBY := preload("res://scenes/ui/lobby.tscn")


func _ready() -> void:
	MetaProgression.cores = 12500  # in-memory only (no save) for a representative number
	var lobby: Node3D = LOBBY.instantiate()
	add_child(lobby)
	for _i in 4:
		await get_tree().process_frame

	var shop_area: Area3D = lobby.get_node("Stations/ShopTerminal")
	var player: Node3D = lobby.get_node("Player")
	player.global_position = shop_area.global_position + Vector3(0, 0.2, 1.5)
	for _i in 12:
		await get_tree().physics_frame
	lobby.call("_interact")  # nearest station == ShopTerminal -> open the overlay

	for _i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://tools/shop_lobby_preview.png"))
	print("SHOP_LOBBY_PREVIEW_SAVED")
	get_tree().quit()

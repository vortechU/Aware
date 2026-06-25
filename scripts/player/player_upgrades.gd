class_name PlayerUpgrades
extends Node
## Applies roguelite upgrades by adjusting the player's and WeaponManager's
## exported stats directly. Child of Player; every effect stacks because it is
## reapplied on top of the current values each time an upgrade is taken.

const HEALTH_PER_STACK := 25.0
const MOVE_SPEED_FACTOR := 1.10
const DAMAGE_FACTOR := 1.20
const FIRE_RATE_FACTOR := 1.15
const ARMOR_PER_STACK := 30.0
const STAMINA_PER_STACK := 25.0
const HEALTH_DROP_CHANCE_PER_STACK := 0.35
const ADS_SPEED_FACTOR := 1.25

## Chance that a kill drops a health pack. RunDirector rolls against this.
var health_drop_chance := 0.0

@onready var player: Player = get_parent() as Player
@onready var weapon_manager: WeaponManager = \
		player.get_node("Head/Bob/Recoil/Camera/WeaponManager") as WeaponManager
@onready var ability_manager: AbilityManager = \
		player.get_node_or_null("AbilityManager") as AbilityManager
@onready var hack_manager: HackManager = \
		player.get_node_or_null("HackManager") as HackManager


func _ready() -> void:
	# The weapon datas are preloaded .tres resources shared through the
	# resource cache. Swap in per-run duplicates so stat upgrades never leak
	# into the next run after a scene reload.
	for i in weapon_manager.weapon_datas.size():
		weapon_manager.weapon_datas[i] = weapon_manager.weapon_datas[i].duplicate()


func apply_upgrade(id: String) -> void:
	match id:
		"max_health":
			player.max_health += HEALTH_PER_STACK
			player.heal(HEALTH_PER_STACK)
		"move_speed":
			player.walk_speed *= MOVE_SPEED_FACTOR
			player.sprint_speed *= MOVE_SPEED_FACTOR
			player.crouch_speed *= MOVE_SPEED_FACTOR
			player.prone_speed *= MOVE_SPEED_FACTOR
			player.slide_boost_speed *= MOVE_SPEED_FACTOR
		"damage":
			for data in weapon_manager.weapon_datas:
				data.damage *= DAMAGE_FACTOR
		"fire_rate":
			for data in weapon_manager.weapon_datas:
				data.fire_rate *= FIRE_RATE_FACTOR
		"armor":
			player.add_armor(ARMOR_PER_STACK)
		"stamina":
			player.max_stamina += STAMINA_PER_STACK
			player.stamina = minf(player.stamina + STAMINA_PER_STACK, player.max_stamina)
		"health_drop":
			health_drop_chance = minf(
					health_drop_chance + HEALTH_DROP_CHANCE_PER_STACK, 1.0)
		"ads_speed":
			for data in weapon_manager.weapon_datas:
				data.ads_time = maxf(data.ads_time / ADS_SPEED_FACTOR, 0.02)
		_:
			# Not a stat upgrade -- try the AbilityManager (active ability), then the
			# HackManager (rank an environment-hacking adjective). Only a genuinely
			# unknown id falls through to the warning.
			if ability_manager != null and ability_manager.grant(id):
				return
			if hack_manager != null and hack_manager.rank_up(id):
				return
			push_warning("PlayerUpgrades: unknown upgrade id '%s'" % id)

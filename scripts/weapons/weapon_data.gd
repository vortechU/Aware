class_name WeaponData
extends Resource
## Static stats for one weapon. Instances live as .tres files in res://data/weapons.

@export var weapon_name: String = "Weapon"
@export var damage: float = 20.0
@export var fire_rate: float = 8.0  # shots per second
@export var auto: bool = true
@export var pellets: int = 1  # >1 for shotguns; damage is per pellet
@export var max_range: float = 200.0

@export_group("Ammo")
@export var mag_size: int = 30
@export var start_reserve: int = 90
@export var max_reserve: int = 180
@export var reload_time: float = 2.0

@export_group("Accuracy")
@export var hip_spread_deg: float = 2.0
@export var ads_spread_deg: float = 0.4
@export var bloom_per_shot_deg: float = 0.4
@export var max_bloom_deg: float = 4.0
## Per-shot recoil pattern: x = yaw degrees (+right), y = pitch degrees (up).
## Loops on the last entry while firing; resets after a pause.
@export var recoil_pattern: Array[Vector2] = [Vector2(0.0, 1.2)]
@export var recoil_recovery: float = 8.0

@export_group("ADS")
@export var ads_fov: float = 55.0
@export var ads_time: float = 0.18

@export_group("Presentation")
@export var model_color: Color = Color(0.25, 0.25, 0.28)
@export var model_length: float = 0.5
@export var sound_radius: float = 30.0

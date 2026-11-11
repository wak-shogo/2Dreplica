# game_state.gd
class_name GameState
extends Node

signal resources_changed
signal upgrade_purchased(upgrade_id: String)
signal phase_changed(new_phase: int)
signal threat_changed(new_threat: float)

enum Phase {
	PHASE_1_SURVIVAL = 1,
	PHASE_2_SURFACE_INDUSTRY = 2,
	PHASE_3_INTERPLANETARY = 3,
	PHASE_4_ORBITAL_WAR = 4
}

# 資源データ
var resources := {
	"iron": 30.0,
	"copper": 20.0,
	"silicon": 10.0,
	"titanium": 0.0,
	"uranium": 0.0,
	"energy": 100.0,
	"max_energy": 100.0,
	"fleet_fighters": 0,
	"fleet_frigates": 0,
	"fleet_cruisers": 0
}

# 機体アップグレード（Gen 1 ナノプリンター）
var upgrades := {
	"laser_power": 1,        # 掘削速度 & ダメージ
	"laser_range": 1,        # 掘削照射距離
	"thruster_force": 1,     # スラスター推力
	"battery_capacity": 1,   # 最大エネルギー
	"scanner_range": 1,      # スキャナー範囲
	"hull_plating": 1        # 耐久力
}

# 進行フェーズ
var current_phase: int = Phase.PHASE_1_SURVIVAL

# 敵脅威度・シグネチャ (0.0 ~ 100.0)
var threat_level: float = 0.0
var max_threat: float = 100.0
var signature_rate: float = 0.5 # 毎秒のシグネチャ増加基本値

# アンロック済みテクノロジー
var unlocked_buildings := {
	"drill": false,
	"smelter": false,
	"conveyor": false,
	"ejector": false,
	"hopper": false,
	"drone_hub": false,
	"mass_driver": false,
	"orbital_shipyard": false
}

# サウンドプレイヤーノード
var audio_players: Array[AudioStreamPlayer] = []
var next_audio_index := 0

func _init() -> void:
	pass

func setup_audio(parent: Node) -> void:
	for i in range(8):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		parent.add_child(p)
		audio_players.append(p)

func play_sfx(stream: AudioStreamWAV, volume_db: float = 0.0) -> void:
	if audio_players.is_empty():
		return
	var player = audio_players[next_audio_index]
	next_audio_index = (next_audio_index + 1) % audio_players.size()
	player.stream = stream
	player.volume_db = volume_db
	player.play()

func add_resource(res_name: String, amount: float) -> void:
	if resources.has(res_name):
		resources[res_name] += amount
		resources_changed.emit()

func has_resources(cost: Dictionary) -> bool:
	for k in cost:
		if resources.get(k, 0.0) < cost[k]:
			return false
	return true

func consume_resources(cost: Dictionary) -> bool:
	if not has_resources(cost):
		return false
	for k in cost:
		resources[k] -= cost[k]
	resources_changed.emit()
	return true

func buy_upgrade(upgrade_id: String) -> bool:
	if not upgrades.has(upgrade_id):
		return false
	var lvl: int = upgrades[upgrade_id]
	var cost := get_upgrade_cost(upgrade_id, lvl)
	if consume_resources(cost):
		upgrades[upgrade_id] += 1
		# 効果適用
		match upgrade_id:
			"battery_capacity":
				resources["max_energy"] = 100.0 + (upgrades["battery_capacity"] - 1) * 50.0
				resources["energy"] = minf(resources["energy"] + 50.0, resources["max_energy"])
		upgrade_purchased.emit(upgrade_id)
		play_sfx(SoundGenerator.create_build())
		return true
	return false

func get_upgrade_cost(upgrade_id: String, current_lvl: int) -> Dictionary:
	var multiplier := pow(1.6, current_lvl - 1)
	match upgrade_id:
		"laser_power":
			return {"iron": int(15 * multiplier), "copper": int(10 * multiplier)}
		"laser_range":
			return {"copper": int(15 * multiplier), "silicon": int(10 * multiplier)}
		"thruster_force":
			return {"iron": int(20 * multiplier), "copper": int(15 * multiplier)}
		"battery_capacity":
			return {"copper": int(20 * multiplier), "silicon": int(15 * multiplier)}
		"scanner_range":
			return {"silicon": int(20 * multiplier), "iron": int(15 * multiplier)}
		"hull_plating":
			return {"iron": int(25 * multiplier), "titanium": int(5 * (current_lvl - 1))}
	return {"iron": 10}

func set_phase(new_phase: int) -> void:
	if current_phase != new_phase:
		current_phase = new_phase
		match current_phase:
			Phase.PHASE_2_SURFACE_INDUSTRY:
				unlocked_buildings["drill"] = true
				unlocked_buildings["smelter"] = true
				unlocked_buildings["conveyor"] = true
				unlocked_buildings["ejector"] = true
				unlocked_buildings["hopper"] = true
			Phase.PHASE_3_INTERPLANETARY:
				unlocked_buildings["drone_hub"] = true
				unlocked_buildings["mass_driver"] = true
			Phase.PHASE_4_ORBITAL_WAR:
				unlocked_buildings["orbital_shipyard"] = true
		phase_changed.emit(new_phase)

func add_threat(amount: float) -> void:
	threat_level = clampf(threat_level + amount, 0.0, max_threat)
	threat_changed.emit(threat_level)

func cheat_unlock_phase(target_phase: int) -> void:
	set_phase(target_phase)
	match target_phase:
		Phase.PHASE_1_SURVIVAL:
			pass
		Phase.PHASE_2_SURFACE_INDUSTRY:
			add_resource("iron", 200.0)
			add_resource("copper", 150.0)
			add_resource("silicon", 100.0)
		Phase.PHASE_3_INTERPLANETARY:
			add_resource("iron", 800.0)
			add_resource("copper", 600.0)
			add_resource("silicon", 400.0)
			add_resource("titanium", 200.0)
		Phase.PHASE_4_ORBITAL_WAR:
			add_resource("iron", 2500.0)
			add_resource("copper", 2000.0)
			add_resource("silicon", 1500.0)
			add_resource("titanium", 1000.0)
			add_resource("uranium", 500.0)
			threat_level = 65.0

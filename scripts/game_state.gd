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

# 資源データ（ゲーム開始時は最小限の孤独なサバイバルスタート）
var resources := {
	"iron": 0.0,
	"ore": 0.0,
	"copper": 0.0,
	"silicon": 0.0,
	"titanium": 0.0,
	"uranium": 0.0,
	"nanites": 15.0,
	"nano": 15.0,
	"cargo": 0.0,
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

# 建設進捗ステージ（インクリメンタル工場建設）
# 0: 荒涼とした不毛の惑星（自機のみ、機械なし）
# 1: 溶鉱炉の建設・点火（煙と炎）
# 2: 物理物流網（地下コンベア＆イジェクター投擲砲）
# 3: 大型3Dプリンター（完全稼働工場）
# 4: 軌道ロケット打ち上げ（惑星軌道フェーズへ）
# 5: 月面マスドライバー＆小惑星造船所（大艦隊RTSへ）
var construction_stage: int = 0
signal stage_changed(new_stage: int)

# チュートリアル状態管理
enum TutorialStep {
	STEP_0_MOVE = 0,         # 移動（ジョイスティック / ドラッグ）
	STEP_1_MINE = 1,         # 採掘（岩盤タップ / 採掘ボタン）
	STEP_2_BUILD_SMELTER = 2,# 建設（精錬炉の配備）
	STEP_3_TECH_TREE = 3,    # テックツリー（3Dプリント・自己強化）
	STEP_4_PINCH_ZOOM = 4,   # ピンチズーム（惑星全景・軌道偵察）
	COMPLETED = 5            # チュートリアル完了（自由開拓モード）
}
var current_tutorial_step: int = TutorialStep.STEP_0_MOVE
var tutorial_move_time: float = 0.0
var tutorial_mined_ore: float = 0.0
var is_tutorial_visible: bool = true
signal tutorial_step_changed(step: int)

# ステージごとの建設要件
var stage_requirements := [
	{"name": "SURFACE SMELTER", "ore": 3.0, "desc": "Construct Smelter for automatic metal refining."},
	{"name": "CONVEYOR & EJECTOR", "ore": 60.0, "silicon": 30.0, "desc": "Deploy tunnel logistics & ballistic ore catapults."},
	{"name": "DUAL 3D PRINTERS", "ore": 180.0, "silicon": 100.0, "nano": 50.0, "desc": "Assemble heavy gantry 3D nano-printers."},
	{"name": "ORBITAL ROCKET", "ore": 400.0, "silicon": 200.0, "nano": 100.0, "desc": "Launch rocket into planetary orbit."},
	{"name": "LUNAR MASS DRIVER", "silicon": 600.0, "titanium": 300.0, "nano": 200.0, "desc": "Construct mass driver & asteroid shipyard."}
]

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
	if res_name == "iron":
		resources["ore"] = resources.get("ore", 0.0) + amount
	elif res_name == "ore":
		resources["iron"] = resources.get("iron", 0.0) + amount
	elif res_name == "nano":
		resources["nanites"] = resources.get("nanites", 0.0) + amount
	elif res_name == "nanites":
		resources["nano"] = resources.get("nano", 0.0) + amount
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

func can_build_next_stage() -> bool:
	if construction_stage >= stage_requirements.size():
		return false
	var req: Dictionary = stage_requirements[construction_stage]
	var current_ore: float = maxf(resources.get("ore", 0.0), resources.get("iron", 0.0))
	var current_si: float = resources.get("silicon", 0.0)
	var current_nano: float = maxf(resources.get("nanites", 0.0), resources.get("nano", 0.0))
	var current_ti: float = resources.get("titanium", 0.0)
	
	if req.get("ore", 0.0) > current_ore:
		return false
	if req.get("silicon", 0.0) > current_si:
		return false
	if req.get("nano", 0.0) > current_nano:
		return false
	if req.get("titanium", 0.0) > current_ti:
		return false
	return true

func build_next_stage() -> bool:
	if not can_build_next_stage():
		return false
	var req: Dictionary = stage_requirements[construction_stage]
	if req.has("ore"):
		var o_val: float = req["ore"]
		resources["ore"] = maxf(0.0, resources.get("ore", 0.0) - o_val)
		resources["iron"] = maxf(0.0, resources.get("iron", 0.0) - o_val)
	if req.has("silicon"):
		resources["silicon"] = maxf(0.0, resources.get("silicon", 0.0) - req["silicon"])
	if req.has("nano"):
		var n_val: float = req["nano"]
		resources["nanites"] = maxf(0.0, resources.get("nanites", 0.0) - n_val)
		resources["nano"] = maxf(0.0, resources.get("nano", 0.0) - n_val)
	if req.has("titanium"):
		resources["titanium"] = maxf(0.0, resources.get("titanium", 0.0) - req["titanium"])

	construction_stage += 1
	stage_changed.emit(construction_stage)
	resources_changed.emit()
	play_sfx(SoundGenerator.create_build())

	# チュートリアル判定
	if current_tutorial_step == TutorialStep.STEP_2_BUILD_SMELTER:
		set_tutorial_step(TutorialStep.STEP_3_TECH_TREE)

	# ステージ進行に伴うフェーズ遷移
	if construction_stage == 1:
		unlocked_buildings["smelter"] = true
	elif construction_stage == 2:
		unlocked_buildings["conveyor"] = true
		unlocked_buildings["ejector"] = true
	elif construction_stage == 3:
		unlocked_buildings["drill"] = true
	elif construction_stage == 4:
		set_phase(Phase.PHASE_3_INTERPLANETARY)
	elif construction_stage >= 5:
		set_phase(Phase.PHASE_4_ORBITAL_WAR)

	return true

func set_construction_stage(stage: int) -> void:
	construction_stage = clampi(stage, 0, 5)
	stage_changed.emit(construction_stage)
	if construction_stage < 4:
		set_phase(Phase.PHASE_1_SURVIVAL)
	elif construction_stage == 4:
		set_phase(Phase.PHASE_3_INTERPLANETARY)
	elif construction_stage >= 5:
		set_phase(Phase.PHASE_4_ORBITAL_WAR)

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

func record_move(delta: float) -> void:
	if current_tutorial_step == TutorialStep.STEP_0_MOVE:
		tutorial_move_time += delta
		if tutorial_move_time >= 1.2:
			set_tutorial_step(TutorialStep.STEP_1_MINE)

func record_mining(amount: float) -> void:
	if current_tutorial_step == TutorialStep.STEP_1_MINE:
		tutorial_mined_ore += amount
		if tutorial_mined_ore >= 3.0:
			set_tutorial_step(TutorialStep.STEP_2_BUILD_SMELTER)

func set_tutorial_step(step: int) -> void:
	if current_tutorial_step != step:
		current_tutorial_step = step
		tutorial_step_changed.emit(step)
		play_sfx(SoundGenerator.create_beep(880.0, 0.12, 0.3))

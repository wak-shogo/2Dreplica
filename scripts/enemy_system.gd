# enemy_system.gd
class_name EnemySystem
extends Node2D

signal wave_spawned(wave_num: int)
signal enemy_defeated(res_reward: Dictionary)
signal game_won

@export var solar_system: Node2D = null

var wave_count: int = 0
var wave_timer: float = 0.0
var wave_interval: float = 25.0

# ユニットリスト
# 各ユニット: {"type": "player"|"enemy", "pos": Vector2, "vel": Vector2, "hp": float, "max_hp": float, "target": Vector2, "role": String}
var fleet_units: Array[Dictionary] = []

# スペースデブリリスト
# 各デブリ: {"pos": Vector2, "vel": Vector2, "res": String, "amount": float, "rot": float}
var debris_list: Array[Dictionary] = []

# 戦闘エフェクト（ビーム・爆発）
var battle_lasers: Array[Dictionary] = []
var explosions: Array[Dictionary] = []

# 敵マザーシップ状態
var mothership_alive: bool = true
var mothership_pos: Vector2 = Vector2(3800.0, -1200.0) # 外縁カイパーベルト
var mothership_hp: float = 1000.0
var mothership_max_hp: float = 1000.0

var game_state: GameState = null

func setup(p_game_state: GameState) -> void:
	game_state = p_game_state

func _process(delta: float) -> void:
	if game_state == null:
		return
		
	# ウェーブタイマー更新
	wave_timer += delta
	# 脅威度が高いほどウェーブ間隔短縮
	var actual_interval := maxf(12.0, wave_interval - (game_state.threat_level / 100.0) * 15.0)
	if wave_timer >= actual_interval:
		wave_timer = 0.0
		_spawn_enemy_wave()
		
	# 味方艦隊の同期（GameStateの艦隊数からスポーン）
	_sync_player_fleet()
	
	# ユニット移動 & 戦闘AI
	_process_fleet_combat(delta)
	
	# デブリの物理挙動（惑星への引力・落下）
	_process_debris(delta)
	
	# エフェクト更新
	_process_effects(delta)
	
	queue_redraw()

func _spawn_enemy_wave() -> void:
	wave_count += 1
	wave_spawned.emit(wave_count)
	
	# 脅威度に応じた敵編成
	var num_enemies := int(2 + (game_state.threat_level / 20.0))
	for i in range(num_enemies):
		var spawn_offset := Vector2(randf_range(2000.0, 2600.0), randf_range(-1500.0, 1500.0))
		fleet_units.append({
			"faction": "enemy",
			"pos": spawn_offset,
			"vel": Vector2.ZERO,
			"hp": 30.0 + wave_count * 5.0,
			"max_hp": 30.0 + wave_count * 5.0,
			"role": "scout" if randf() > 0.4 else "raider",
			"fire_timer": randf_range(0.0, 1.0)
		})
	if game_state != null:
		game_state.play_sfx(SoundGenerator.create_beep(220.0, 0.4))

func _sync_player_fleet() -> void:
	var cur_p_count := 0
	for u in fleet_units:
		if u["faction"] == "player":
			cur_p_count += 1
			
	var target_count: int = game_state.resources.get("fleet_fighters", 0)
	if cur_p_count < target_count:
		# 新規味方戦闘機を軌道から出撃
		fleet_units.append({
			"faction": "player",
			"pos": Vector2(cos(randf() * TAU), sin(randf() * TAU)) * 650.0,
			"vel": Vector2.ZERO,
			"hp": 45.0,
			"max_hp": 45.0,
			"role": "fighter",
			"fire_timer": randf_range(0.0, 1.0)
		})

func _process_fleet_combat(delta: float) -> void:
	var i := 0
	while i < fleet_units.size():
		var u = fleet_units[i]
		u["fire_timer"] += delta
		
		# ターゲット索敵
		var enemy_target = null
		var min_dist := INF
		for other in fleet_units:
			if other["faction"] != u["faction"]:
				var d: float = u["pos"].distance_to(other["pos"])
				if d < min_dist:
					min_dist = d
					enemy_target = other
					
		# マザーシップへの攻撃（味方ユニット）
		if u["faction"] == "player" and mothership_alive and min_dist > 500.0:
			var d_ms: float = u["pos"].distance_to(mothership_pos)
			if d_ms < min_dist:
				min_dist = d_ms
				enemy_target = {"pos": mothership_pos, "is_mothership": true}
		
		# 移動制御
		if enemy_target != null:
			var to_enemy: Vector2 = enemy_target["pos"] - u["pos"]
			var target_dist := 120.0 if u["role"] == "fighter" else 200.0
			var desired_vel := to_enemy.normalized() * (160.0 if to_enemy.length() > target_dist else -50.0)
			u["vel"] = u["vel"].lerp(desired_vel, delta * 3.0)
			
			# 射撃
			if u["fire_timer"] >= 1.2 and min_dist <= 260.0:
				u["fire_timer"] = 0.0
				battle_lasers.append({
					"from": u["pos"],
					"to": enemy_target["pos"],
					"color": Color(0.2, 0.9, 1.0) if u["faction"] == "player" else Color(1.0, 0.25, 0.2),
					"life": 0.15
				})
				
				# ダメージ判定
				if enemy_target.get("is_mothership", false):
					mothership_hp -= 15.0
					if mothership_hp <= 0.0 and mothership_alive:
						mothership_alive = false
						game_won.emit()
						_trigger_huge_explosion(mothership_pos)
				else:
					enemy_target["hp"] -= 12.0
		else:
			# 巡回移動
			var center_dir: Vector2 = -u["pos"].normalized()
			u["vel"] = u["vel"].lerp(center_dir * 40.0, delta * 0.5)
			
		u["pos"] += u["vel"] * delta
		
		# 撃沈チェック
		if u["hp"] <= 0.0:
			_create_explosion(u["pos"])
			if u["faction"] == "enemy":
				# デブリの発生
				debris_list.append({
					"pos": u["pos"],
					"vel": Vector2(randf_range(-40, 40), randf_range(-40, 40)),
					"res": "iron" if randf() > 0.3 else "titanium",
					"amount": randf_range(3.0, 8.0),
					"rot": randf() * TAU
				})
				if game_state != null:
					game_state.add_threat(-1.0) # 敵撃退で脅威度少し低減
			fleet_units.remove_at(i)
		else:
			i += 1

func _process_debris(delta: float) -> void:
	# デブリは中心惑星へ引き寄せられる
	var i := 0
	while i < debris_list.size():
		var d = debris_list[i]
		var to_center: Vector2 = -d["pos"]
		var dist: float = to_center.length()
		var g_accel := 350000.0 / maxf(dist * dist, 1000.0)
		d["vel"] += to_center.normalized() * g_accel * delta
		d["pos"] += d["vel"] * delta
		d["rot"] += delta * 2.0
		
		# 惑星地表（400px）に着弾・回収
		if dist <= 420.0:
			if game_state != null:
				game_state.add_resource(d["res"], d["amount"])
				game_state.play_sfx(SoundGenerator.create_build(0.1, 0.2))
			debris_list.remove_at(i)
		else:
			i += 1

func _create_explosion(pos: Vector2) -> void:
	explosions.append({
		"pos": pos,
		"radius": 15.0,
		"max_radius": 25.0,
		"life": 0.35,
		"max_life": 0.35
	})
	if game_state != null:
		game_state.play_sfx(SoundGenerator.create_explosion(0.25, 0.3))

func _trigger_huge_explosion(pos: Vector2) -> void:
	for k in range(8):
		explosions.append({
			"pos": pos + Vector2(randf_range(-50, 50), randf_range(-50, 50)),
			"radius": 30.0,
			"max_radius": 70.0,
			"life": 0.8,
			"max_life": 0.8
		})
	if game_state != null:
		game_state.play_sfx(SoundGenerator.create_explosion(0.6, 0.6))

func _process_effects(delta: float) -> void:
	var i := 0
	while i < battle_lasers.size():
		var l = battle_lasers[i]
		l["life"] -= delta
		if l["life"] <= 0.0:
			battle_lasers.remove_at(i)
		else:
			i += 1
			
	var j := 0
	while j < explosions.size():
		var ex = explosions[j]
		ex["life"] -= delta
		if ex["life"] <= 0.0:
			explosions.remove_at(j)
		else:
			j += 1

func _draw() -> void:
	# 敵マザーシップは AsteroidFortress が詳細な小惑星要塞として描画するため、
	# ここでの旧プレースホルダー赤色四角形の描画は行わない

	# 艦隊ユニットの描画
	for u in fleet_units:
		var pos: Vector2 = u["pos"]
		var is_p: bool = (u["faction"] == "player")
		var col := Color(0.2, 0.9, 1.0) if is_p else Color(1.0, 0.3, 0.3)
		var forward: Vector2 = u["vel"].normalized() if u["vel"].length() > 5.0 else Vector2.UP
		var right := Vector2(-forward.y, forward.x)
		
		# 戦闘機シェイプ（三角形）
		var p1 := pos + forward * 8.0
		var p2 := pos - forward * 5.0 + right * 5.0
		var p3 := pos - forward * 5.0 - right * 5.0
		draw_polygon(PackedVector2Array([p1, p2, p3]), [col])

	# 戦闘レーザー
	for l in battle_lasers:
		draw_line(l["from"], l["to"], l["color"], 2.0)

	# 爆発
	for ex in explosions:
		var alpha: float = ex["life"] / ex["max_life"]
		var r: float = lerpf(ex["max_radius"], ex["radius"], alpha)
		var c := Color(1.0, 0.6, 0.2, alpha * 0.8)
		draw_circle(ex["pos"], r, c)

	# デブリ
	for d in debris_list:
		var d_col := Color(0.8, 0.6, 0.3, 0.8) if d["res"] == "iron" else Color(0.7, 0.85, 1.0, 0.9)
		draw_rect(Rect2(d["pos"].x - 3, d["pos"].y - 3, 6, 6), d_col)

# building.gd
class_name Building
extends Node2D

enum BuildingType {
	DRILL,
	SMELTER,
	CONVEYOR,
	EJECTOR,
	HOPPER,
	DRONE_HUB,
	MASS_DRIVER,
	ORBITAL_SHIPYARD
}

@export var type: BuildingType = BuildingType.DRILL
@export var parent_planet: CelestialBody = null
@export var surface_angle: float = 0.0 # 惑星地表における角度
@export var altitude: float = 0.0      # 地表からの高度（軌道造船所用）
@export var ejector_angle: float = -45.0 # 発射角度（法線基準の度数）
@export var ejector_power: float = 280.0 # 初速

# ベイクされたイジェクター軌道
var baked_trajectory: PackedVector2Array = []
var is_trajectory_locked: bool = false
var target_hopper: Building = null

# 設備内インベントリ / 状態
var inventory: Dictionary = {}
var production_timer: float = 0.0
var production_interval: float = 1.5

# 飛翔中アイテム（イジェクター用）
var flying_items: Array[Dictionary] = []
var impact_sparks: Array[Dictionary] = []

# ドローン用
var drones: Array[Dictionary] = []

func _ready() -> void:
	match type:
		BuildingType.DRILL:
			production_interval = 1.2
		BuildingType.SMELTER:
			production_interval = 2.0
		BuildingType.DRONE_HUB:
			production_interval = 0.5
			_init_drones()
		BuildingType.MASS_DRIVER:
			production_interval = 3.0
		BuildingType.ORBITAL_SHIPYARD:
			production_interval = 4.0

func _init_drones() -> void:
	for i in range(3):
		drones.append({
			"pos": global_position,
			"target": Vector2.ZERO,
			"cargo": "",
			"state": 0 # 0: idle, 1: gathering, 2: delivering
		})

func update_building(delta: float, game_state: GameState, all_buildings: Array[Building]) -> void:
	production_timer += delta
	
	# 設備位置の更新（惑星の公転・自転に同期）
	if parent_planet != null:
		if type == BuildingType.ORBITAL_SHIPYARD:
			# 軌道造船所：一定の軌道高度を周回または地上同期
			var r := parent_planet.base_radius + altitude
			global_position = parent_planet.global_position + Vector2(cos(surface_angle), sin(surface_angle)) * r
			rotation = surface_angle + PI * 0.5
		else:
			# 地表設備
			var r := parent_planet.is_surface_walkable_at(surface_angle)
			global_position = parent_planet.global_position + Vector2(cos(surface_angle), sin(surface_angle)) * r
			rotation = surface_angle + PI * 0.5

	# 種別ごとの動作
	match type:
		BuildingType.DRILL:
			_process_drill(game_state)
		BuildingType.SMELTER:
			_process_smelter(game_state)
		BuildingType.EJECTOR:
			_process_ejector(delta, all_buildings, game_state)
		BuildingType.DRONE_HUB:
			_process_drone_hub(delta, all_buildings, game_state)
		BuildingType.MASS_DRIVER:
			_process_mass_driver(game_state)
		BuildingType.ORBITAL_SHIPYARD:
			_process_orbital_shipyard(game_state)

	# 飛翔中アイテムの更新
	_update_flying_items(delta, game_state)
	queue_redraw()

func _process_drill(game_state: GameState) -> void:
	if production_timer >= production_interval:
		production_timer = 0.0
		if parent_planet != null:
			# 直下の鉱石を掘削
			var drill_target := global_position - Vector2(cos(surface_angle), sin(surface_angle)) * 20.0
			var res = parent_planet.mine_at_world_pos(drill_target, 5.0)
			if res.get("success", false) and res.get("broken", false):
				var r_name: String = res.get("resource", "iron")
				game_state.add_resource(r_name, res.get("amount", 2.0))
				game_state.add_threat(0.2)
			else:
				# 基礎採掘（無尽蔵の鉄・岩）
				game_state.add_resource("iron", 1.0)
				game_state.add_threat(0.1)

func _process_smelter(game_state: GameState) -> void:
	if production_timer >= production_interval:
		production_timer = 0.0
		# 鉄と銅を消費して高次パーツ（シリコンやチタン合金）を増産
		if game_state.resources.get("iron", 0.0) >= 2.0 and game_state.resources.get("copper", 0.0) >= 1.0:
			game_state.resources["iron"] -= 2.0
			game_state.resources["copper"] -= 1.0
			game_state.add_resource("silicon", 1.5)
			game_state.add_threat(0.3)

func bake_ejector_trajectory(all_buildings: Array[Building]) -> void:
	baked_trajectory.clear()
	is_trajectory_locked = false
	target_hopper = null
	
	if parent_planet == null:
		return
		
	# 発射ベクトル（惑星法線基準）
	var normal := Vector2(cos(surface_angle), sin(surface_angle))
	var tangent := Vector2(-normal.y, normal.x)
	var shoot_dir := normal.rotated(deg_to_rad(ejector_angle))
	var vel := shoot_dir * ejector_power
	var pos := global_position + normal * 10.0
	
	baked_trajectory.append(pos)
	
	var dt := 0.05
	for step in range(80):
		var g := parent_planet.get_gravity_at(pos)
		vel += g * dt
		pos += vel * dt
		baked_trajectory.append(pos)
		
		# ホッパーとの衝突判定
		for b in all_buildings:
			if b != self and b.type == BuildingType.HOPPER and b.global_position.distance_to(pos) < 30.0:
				target_hopper = b
				is_trajectory_locked = true
				break
		if is_trajectory_locked:
			break
		# 地表衝突
		if (pos - parent_planet.global_position).length() <= parent_planet.base_radius:
			break

func _process_ejector(delta: float, all_buildings: Array[Building], game_state: GameState) -> void:
	if not is_trajectory_locked:
		bake_ejector_trajectory(all_buildings)
		
	if production_timer >= production_interval:
		production_timer = 0.0
		if is_trajectory_locked and game_state.resources.get("iron", 0.0) >= 1.0:
			game_state.resources["iron"] -= 1.0
			flying_items.append({
				"step_idx": 0,
				"progress": 0.0,
				"resource": "iron"
			})

func _update_flying_items(delta: float, game_state: GameState) -> void:
	# 着弾スパークの更新
	var k := 0
	while k < impact_sparks.size():
		var sp = impact_sparks[k]
		sp["life"] -= delta
		if sp["life"] <= 0.0:
			impact_sparks.remove_at(k)
		else:
			k += 1

	if not is_trajectory_locked or baked_trajectory.size() < 2:
		flying_items.clear()
		return
		
	var speed := 400.0
	var i := 0
	while i < flying_items.size():
		var item = flying_items[i]
		var idx: int = item["step_idx"]
		if idx >= baked_trajectory.size() - 1:
			# ホッパーに着弾！
			if target_hopper != null:
				game_state.add_resource("iron", 1.5) # イジェクターボーナス
				# 着弾エフェクト
				for s in range(4):
					impact_sparks.append({
						"pos": baked_trajectory[idx] + Vector2(randf_range(-6, 6), randf_range(-6, 6)),
						"life": 0.2,
						"max_life": 0.2
					})
			flying_items.remove_at(i)
		else:
			var p1 := baked_trajectory[idx]
			var p2 := baked_trajectory[idx + 1]
			var dist := p1.distance_to(p2)
			item["progress"] += (speed * delta) / maxf(dist, 1.0)
			if item["progress"] >= 1.0:
				item["progress"] = 0.0
				item["step_idx"] += 1
			i += 1

func _process_drone_hub(delta: float, all_buildings: Array[Building], game_state: GameState) -> void:
	# ドローンが周辺のドリルからアイテムをピストン輸送
	for d in drones:
		if d["state"] == 0: # Idle
			# 近隣のドリルを探す
			for b in all_buildings:
				if b.type == BuildingType.DRILL and b.global_position.distance_to(global_position) < 400.0:
					d["target"] = b.global_position
					d["state"] = 1 # Gathering
					break
		elif d["state"] == 1: # Gathering
			var to_target: Vector2 = d["target"] - d["pos"]
			if to_target.length() < 10.0:
				d["cargo"] = "iron"
				d["state"] = 2 # Delivering
				d["target"] = global_position
			else:
				d["pos"] += to_target.normalized() * 180.0 * delta
		elif d["state"] == 2: # Delivering
			var to_base: Vector2 = d["target"] - d["pos"]
			if to_base.length() < 10.0:
				if d["cargo"] != "":
					game_state.add_resource(d["cargo"], 2.0)
					d["cargo"] = ""
				d["state"] = 0 # Idle
			else:
				d["pos"] += to_base.normalized() * 180.0 * delta

func _process_mass_driver(game_state: GameState) -> void:
	if production_timer >= production_interval:
		production_timer = 0.0
		# 惑星間カタパルト：資源を別惑星・軌道へ超高速射出
		if game_state.consume_resources({"iron": 10.0, "copper": 5.0}):
			game_state.add_resource("titanium", 3.0)
			game_state.add_threat(1.5)
			game_state.play_sfx(SoundGenerator.create_laser(0.25, 0.4))

func _process_orbital_shipyard(game_state: GameState) -> void:
	if production_timer >= production_interval:
		production_timer = 0.0
		# 自動で無人戦闘機を3Dプリント・出撃
		if game_state.consume_resources({"iron": 15.0, "silicon": 10.0}):
			game_state.resources["fleet_fighters"] += 1
			game_state.resources_changed.emit()
			game_state.add_threat(2.0)

func _draw() -> void:
	# 設備のピクセルアート風描画
	match type:
		BuildingType.DRILL:
			draw_rect(Rect2(-12, -24, 24, 24), Color(0.8, 0.5, 0.2))
			# ドリルヘッド
			var t := Time.get_ticks_msec() * 0.01
			var offset := sin(t) * 3.0
			draw_polygon(PackedVector2Array([
				Vector2(-6, 0), Vector2(6, 0), Vector2(0, 10 + offset)
			]), [Color(0.9, 0.9, 0.9)])
		BuildingType.SMELTER:
			draw_rect(Rect2(-16, -28, 32, 28), Color(0.3, 0.35, 0.4))
			# 炉心の光
			draw_circle(Vector2(0, -14), 6.0, Color(1.0, 0.5, 0.1, 0.9))
		BuildingType.CONVEYOR:
			draw_rect(Rect2(-14, -6, 28, 6), Color(0.2, 0.2, 0.25))
			draw_line(Vector2(-12, -3), Vector2(12, -3), Color(1.0, 0.8, 0.2), 1.5)
		BuildingType.EJECTOR:
			draw_rect(Rect2(-10, -16, 20, 16), Color(0.25, 0.5, 0.8))
			# 発射筒
			var shoot_v := Vector2(0, -1).rotated(deg_to_rad(ejector_angle)) * 18.0
			draw_line(Vector2(0, -8), shoot_v, Color(0.9, 0.9, 0.9), 4.0)
		BuildingType.HOPPER:
			draw_polygon(PackedVector2Array([
				Vector2(-14, -20), Vector2(14, -20), Vector2(8, 0), Vector2(-8, 0)
			]), [Color(0.2, 0.6, 0.3)])
		BuildingType.DRONE_HUB:
			draw_rect(Rect2(-18, -20, 36, 20), Color(0.4, 0.25, 0.6))
			draw_arc(Vector2(0, -22), 8.0, PI, TAU, 16, Color(0.4, 0.9, 1.0), 2.0)
		BuildingType.MASS_DRIVER:
			draw_rect(Rect2(-20, -32, 40, 32), Color(0.3, 0.3, 0.5))
			draw_line(Vector2(0, 0), Vector2(0, -50), Color(0.2, 0.9, 1.0), 5.0)
			draw_circle(Vector2(0, -50), 4.0, Color(1, 1, 1))
		BuildingType.ORBITAL_SHIPYARD:
			draw_rect(Rect2(-30, -16, 60, 32), Color(0.2, 0.3, 0.5, 0.9))
			draw_rect(Rect2(-24, -12, 48, 24), Color(0.1, 0.15, 0.25))
			# アーム
			draw_line(Vector2(-30, 0), Vector2(-42, -15), Color(0.4, 0.8, 1.0), 2.0)
			draw_line(Vector2(30, 0), Vector2(42, -15), Color(0.4, 0.8, 1.0), 2.0)

	# イジェクターのベイクされた軌道ラインの描画
	if type == BuildingType.EJECTOR and baked_trajectory.size() > 1:
		var line_col := Color(0.2, 1.0, 0.4, 0.6) if is_trajectory_locked else Color(1.0, 0.6, 0.2, 0.4)
		for j in range(baked_trajectory.size() - 1):
			var lp1 := to_local(baked_trajectory[j])
			var lp2 := to_local(baked_trajectory[j + 1])
			if j % 2 == 0:
				draw_line(lp1, lp2, line_col, 2.0)
		
		# 飛翔中アイテムの描画
		for item in flying_items:
			var s_idx: int = item["step_idx"]
			if s_idx < baked_trajectory.size() - 1:
				var wp1 := baked_trajectory[s_idx]
				var wp2 := baked_trajectory[s_idx + 1]
				var w_curr := wp1.lerp(wp2, item["progress"])
				draw_circle(to_local(w_curr), 3.5, Color(1.0, 0.8, 0.3))

		# 着弾スパークの描画
		for sp in impact_sparks:
			var alpha: float = sp["life"] / sp["max_life"]
			draw_circle(to_local(sp["pos"]), 3.0 * alpha, Color(0.3, 1.0, 0.6, alpha))

	# ドローンの描画
	if type == BuildingType.DRONE_HUB:
		for d in drones:
			var d_local := to_local(d["pos"])
			draw_circle(d_local, 3.0, Color(0.3, 0.9, 1.0))
			draw_line(d_local - Vector2(4, 0), d_local + Vector2(4, 0), Color(1, 1, 1), 1.0)

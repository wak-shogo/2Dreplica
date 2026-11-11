# celestial_body.gd
class_name CelestialBody
extends Node2D

enum BodyType {
	PLANET,
	MOON,
	ASTEROID,
	COMET
}

@export var body_type: BodyType = BodyType.PLANET
@export var body_name: String = "Terra-01"
@export var base_radius: float = 560.0
@export var core_radius: float = 200.0
@export var atmosphere_radius: float = 950.0
@export var gravity_constant: float = 420000.0
@export var atmosphere_drag: float = 0.4
@export var orbit_parent: Node2D = null
@export var orbit_distance: float = 0.0
@export var orbit_speed: float = 0.04
@export var orbit_angle: float = 0.0
@export var camera_zoom: float = 2.0

var anim_time: float = 0.0

# 軌道周回スペースシャトル
var shuttle_angle: float = 0.45
var shuttle_speed: float = 0.35

# 内部採掘レーザー
var internal_lasers: Array[Dictionary] = []

# 地殻極座標セル
var angle_steps: int = 180
var depth_steps: int = 24
var grid_cells: Array = []

# スキャン波
var scan_radius: float = 0.0
var scan_active: bool = false
var scan_max_radius: float = 650.0

# パーティクル群（煙・火花・火の粉）
var smoke_particles: Array[Dictionary] = []
var spark_particles: Array[Dictionary] = []
var ember_particles: Array[Dictionary] = []

# イジェクターの飛翔鉱石
var lobbed_ores: Array[Dictionary] = []

# 進行ステージ連携
var game_state: GameState = null
var construction_stage: int = 0

func setup(p_game_state: GameState) -> void:
	game_state = p_game_state
	if game_state != null:
		construction_stage = game_state.construction_stage
		game_state.stage_changed.connect(_on_stage_changed)

func _on_stage_changed(new_stage: int) -> void:
	construction_stage = new_stage
	queue_redraw()

func _ready() -> void:
	if body_type == BodyType.MOON:
		base_radius = 420.0
	_init_grid()
	_init_internal_lasers()
	_init_lobbed_ores()

func _init_internal_lasers() -> void:
	internal_lasers.append({"angle": -0.85, "r1": 240.0, "r2": 490.0, "col": Color(0.2, 0.85, 1.0, 0.95)})
	internal_lasers.append({"angle": -0.25, "r1": 270.0, "r2": 510.0, "col": Color(0.3, 1.0, 0.4, 0.95)})
	internal_lasers.append({"angle": 0.65, "r1": 230.0, "r2": 460.0, "col": Color(1.0, 0.85, 0.2, 0.95)})
	internal_lasers.append({"angle": 1.45, "r1": 260.0, "r2": 490.0, "col": Color(0.3, 0.9, 1.0, 0.95)})
	internal_lasers.append({"angle": 2.25, "r1": 240.0, "r2": 450.0, "col": Color(0.4, 1.0, 0.5, 0.95)})
	internal_lasers.append({"angle": -2.15, "r1": 270.0, "r2": 520.0, "col": Color(1.0, 0.6, 0.2, 0.95)})

func _init_lobbed_ores() -> void:
	for i in range(8):
		lobbed_ores.append({
			"t": float(i) / 8.0,
			"speed": 0.28
		})

func _init_grid() -> void:
	grid_cells.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(body_name) + 777

	# 1. 基礎グリッド（全岩盤）: 表層 d=0, 1 は常に完全な地表を保証
	for a in range(angle_steps):
		var column: Array = []
		for d in range(depth_steps):
			var type := 1 # 基本岩盤
			var hp := 15.0
			column.append({
				"type": type,
				"hp": hp,
				"max_hp": hp,
				"scanned_alpha": 0.0
			})
		grid_cells.append(column)

	# 2. 地下有機的洞窟・坑道の掘削（d >= 3〜4 の地下に配置し、地表を削らない）
	# Phase 1 工場直下の地下空洞システム（角度 122〜164 = ラジアン -1.8〜-1.1 付近）
	# 左洞窟チャンバー（イジェクター・ホッパー坑道：角度 124〜140、深さ 7〜13）
	for a in range(124, 140):
		var a_idx: int = a % angle_steps
		var ca_mid: float = 9.5 + sin(float(a) * 0.4) * 1.8
		for d in range(int(ca_mid - 2), int(ca_mid + 3)):
			if d >= 3 and d < depth_steps - 1:
				grid_cells[a_idx][d]["type"] = 0

	# 垂直連絡シャフト（角度 142〜143、深さ 2〜12）
	for a_idx in [142, 143]:
		for d in range(2, 13):
			grid_cells[a_idx][d]["type"] = 0

	# 右洞窟チャンバー（地下溶鉱炉室：角度 146〜162、深さ 8〜14）
	for a in range(146, 162):
		var a_idx: int = a % angle_steps
		var ca_mid: float = 11.0 + cos(float(a) * 0.35) * 1.5
		for d in range(int(ca_mid - 2), int(ca_mid + 3)):
			if d >= 3 and d < depth_steps - 1:
				grid_cells[a_idx][d]["type"] = 0

	# 斜行連絡コンベアトンネル（角度 138〜148、深さ 9〜12）
	for step in range(10):
		var a_idx: int = (138 + step) % angle_steps
		var d: int = clampi(9 + int(step * 0.3), 3, depth_steps - 1)
		grid_cells[a_idx][d]["type"] = 0

	# 他セクターの自然な地下大洞窟（角度 35〜75、深さ 10〜16）
	for a in range(35, 75):
		var a_idx: int = a % angle_steps
		var ca_mid: float = 13.0 + sin(float(a) * 0.2) * 2.5
		for d in range(int(ca_mid - 2), int(ca_mid + 3)):
			if d >= 4 and d < depth_steps - 1:
				grid_cells[a_idx][d]["type"] = 0

	# 南半球の深層空洞（角度 210〜255、深さ 12〜17）
	for a in range(210, 255):
		var a_idx: int = a % angle_steps
		var ca_mid: float = 14.5 + cos(float(a) * 0.25) * 2.0
		for d in range(int(ca_mid - 2), int(ca_mid + 3)):
			if d >= 4 and d < depth_steps - 1:
				grid_cells[a_idx][d]["type"] = 0

	# 3. 鉱脈クラスター（画像1・3のカラフルな鉱石ポケット）
	# 鉄鉱脈 (type=2, 琥珀ゴールド, 浅層〜中層)
	for seed_a in [30, 80, 128, 155, 190, 245, 310]:
		var sa: int = int(seed_a * (angle_steps / 360.0))
		var sd: int = rng.randi_range(3, 9)
		for da in range(-2, 3):
			for dd in range(-2, 3):
				if rng.randf() > 0.3:
					var target_a: int = (sa + da + angle_steps) % angle_steps
					var target_d: int = clampi(sd + dd, 2, depth_steps - 1)
					if grid_cells[target_a][target_d]["type"] != 0:
						grid_cells[target_a][target_d]["type"] = 2

	# シリコン鉱脈 (type=4, エレクトリックシアン, 中層)
	for seed_a in [50, 135, 150, 215, 290]:
		var sa: int = int(seed_a * (angle_steps / 360.0))
		var sd: int = rng.randi_range(7, 15)
		for da in range(-2, 3):
			for dd in range(-2, 3):
				if rng.randf() > 0.35:
					var target_a: int = (sa + da + angle_steps) % angle_steps
					var target_d: int = clampi(sd + dd, 3, depth_steps - 1)
					if grid_cells[target_a][target_d]["type"] != 0:
						grid_cells[target_a][target_d]["type"] = 4

	# 銅鉱脈 (type=3, カッパーオレンジ, 中層〜深層)
	for seed_a in [95, 140, 175, 275, 345]:
		var sa: int = int(seed_a * (angle_steps / 360.0))
		var sd: int = rng.randi_range(10, 18)
		for da in range(-2, 3):
			for dd in range(-2, 3):
				if rng.randf() > 0.35:
					var target_a: int = (sa + da + angle_steps) % angle_steps
					var target_d: int = clampi(sd + dd, 4, depth_steps - 1)
					if grid_cells[target_a][target_d]["type"] != 0:
						grid_cells[target_a][target_d]["type"] = 3

	# チタン・ウラン (type=5, 6, ネオングリーン/白銀, 深層マントル境界)
	for seed_a in [65, 132, 158, 230, 325]:
		var sa: int = int(seed_a * (angle_steps / 360.0))
		var sd: int = rng.randi_range(16, depth_steps - 2)
		var ore_t: int = 5 if rng.randf() > 0.5 else 6
		for da in range(-1, 2):
			for dd in range(-1, 2):
				var target_a: int = (sa + da + angle_steps) % angle_steps
				var target_d: int = clampi(sd + dd, 5, depth_steps - 1)
				if grid_cells[target_a][target_d]["type"] != 0:
					grid_cells[target_a][target_d]["type"] = ore_t

func _process(delta: float) -> void:
	anim_time += delta
	shuttle_angle += shuttle_speed * delta
	if shuttle_angle >= TAU: shuttle_angle -= TAU

	if orbit_parent != null and orbit_distance > 0.0:
		orbit_angle += orbit_speed * delta
		position = orbit_parent.position + Vector2(cos(orbit_angle), sin(orbit_angle)) * orbit_distance

	if scan_active:
		scan_radius += 700.0 * delta
		if scan_radius >= scan_max_radius:
			scan_active = false
			scan_radius = 0.0

	for ore in lobbed_ores:
		ore["t"] += ore["speed"] * delta
		if ore["t"] >= 1.0:
			ore["t"] -= 1.0

	_update_particle_list(smoke_particles, delta)
	_update_particle_list(ember_particles, delta)
	_update_particle_list(spark_particles, delta)
	queue_redraw()

func _update_particle_list(p_list: Array[Dictionary], delta: float) -> void:
	var idx := 0
	while idx < p_list.size():
		var p = p_list[idx]
		p["pos"] += p["vel"] * delta
		p["life"] -= delta
		if p["life"] <= 0.0:
			p_list.remove_at(idx)
		else:
			idx += 1

func get_gravity_at(world_pos: Vector2) -> Vector2:
	var to_center := global_position - world_pos
	var dist := to_center.length()
	if dist < 1.0: return Vector2.ZERO
	var dir := to_center / dist
	var g_accel: float = 0.0
	if dist >= base_radius:
		g_accel = gravity_constant / (dist * dist)
	else:
		var surface_g := gravity_constant / (base_radius * base_radius)
		g_accel = surface_g * (dist / base_radius)
	return dir * g_accel

func get_atmosphere_drag_at(world_pos: Vector2, vel: Vector2) -> Vector2:
	if atmosphere_radius <= base_radius: return Vector2.ZERO
	var dist := (world_pos - global_position).length()
	if dist > atmosphere_radius or dist < base_radius: return Vector2.ZERO
	var density := (atmosphere_radius - dist) / (atmosphere_radius - base_radius)
	var speed := vel.length()
	if speed < 1.0: return Vector2.ZERO
	return -vel.normalized() * (0.5 * density * atmosphere_drag * speed * speed * 0.002)

func trigger_scanner(origin_pos: Vector2, max_dist: float = 650.0) -> void:
	scan_active = true
	scan_radius = 0.0
	scan_max_radius = max_dist

func mine_at_world_pos(world_pos: Vector2, power: float) -> Dictionary:
	var local_pos := world_pos - global_position
	var dist := local_pos.length()
	if dist < core_radius: return {"success": false, "reason": "core_limit"}
	if dist > base_radius + 20.0: return {"success": false, "reason": "out_of_reach"}

	var angle := local_pos.angle()
	if angle < 0.0: angle += TAU
	var a_idx := int((angle / TAU) * float(angle_steps)) % angle_steps
	var crust_thickness := base_radius - core_radius
	var depth_step_size := crust_thickness / float(depth_steps)
	var d_idx := int((base_radius - dist) / depth_step_size)
	d_idx = clampi(d_idx, 0, depth_steps - 1)

	var cell = grid_cells[a_idx][d_idx]
	if cell["type"] == 0: return {"success": false, "reason": "empty"}

	cell["hp"] -= power
	if cell["hp"] <= 0.0:
		var m_type: int = cell["type"]
		cell["type"] = 0
		var r_name := "iron"
		match m_type:
			2: r_name = "iron"
			3: r_name = "copper"
			4: r_name = "silicon"
			5: r_name = "titanium"
			6: r_name = "uranium"
		queue_redraw()
		return {"success": true, "broken": true, "resource": r_name, "amount": 3.0}
	queue_redraw()
	return {"success": true, "broken": false}

func is_surface_walkable_at(angle_rad: float) -> float:
	if angle_rad < 0.0: angle_rad += TAU
	var a_idx := int((angle_rad / TAU) * float(angle_steps)) % angle_steps
	var crust_thickness := base_radius - core_radius
	var depth_step_size := crust_thickness / float(depth_steps)
	for d in range(depth_steps):
		if grid_cells[a_idx][d]["type"] != 0:
			return base_radius - float(d) * depth_step_size
	return core_radius

func _draw() -> void:
	if body_type == BodyType.MOON:
		_draw_moon()
		return

	# 1. 大気圏の光彩グロー
	var atmo_col := Color(0.18, 0.55, 0.95, 0.14)
	draw_circle(Vector2.ZERO, atmosphere_radius, atmo_col)
	draw_arc(Vector2.ZERO, atmosphere_radius, 0.0, TAU, 96, Color(0.28, 0.8, 1.0, 0.35), 2.5)

	# 2. 燃え盛る流体マグマコア（多層グラデーション＋対流熱波フレア）
	_draw_fluid_magma_core()

	# 3. 自然な岩盤層と同心円状坑道迷路＆鉱脈パルス
	_draw_natural_crust_and_tunnels()

	# 4. 放射状採掘レーザービーム（Stage >= 2）
	if construction_stage >= 2:
		_draw_internal_lasers()

	# 5. 地表360度全周の工場群（Stage >= 4 かつ マクロズーム時）
	if construction_stage >= 4 and camera_zoom < 1.1:
		_draw_surface_factories()

	# 6. 地上＆地下詳細工場（ミクロ視点・法線接地・LOD制御）
	_draw_phase1_2_detailed_factories()

	# 7. シアン周回軌道リング＆スペースシャトル（Stage >= 4）
	if construction_stage >= 4:
		_draw_orbital_shuttle()

	# 8. スキャンパルス
	if scan_active and scan_radius < scan_max_radius:
		draw_arc(Vector2.ZERO, scan_radius, 0.0, TAU, 64, Color(0.2, 1.0, 0.85, 1.0 - (scan_radius / scan_max_radius)), 2.5)

func _draw_fluid_magma_core() -> void:
	# 画像3完全再現：対流する超高熱プラズマコア球
	# 外層コロナ熱線
	draw_circle(Vector2.ZERO, core_radius + 36.0, Color(1.0, 0.35, 0.05, 0.18))
	draw_circle(Vector2.ZERO, core_radius + 18.0, Color(1.0, 0.45, 0.1, 0.45))
	draw_circle(Vector2.ZERO, core_radius, Color(0.96, 0.24, 0.02, 0.98))

	# 28本の対流プロミネンス・フレア噴炎
	var steps := 28
	for i in range(steps):
		var a := float(i) / float(steps) * TAU + anim_time * 0.4
		var flare_r := core_radius * 0.92 + sin(a * 6.0 + anim_time * 3.5) * 16.0
		var p := Vector2(cos(a), sin(a)) * flare_r
		draw_line(Vector2.ZERO, p, Color(1.0, 0.65, 0.15, 0.4), 12.0)

	# 粒状斑マントル球
	draw_circle(Vector2.ZERO, core_radius * 0.75, Color(1.0, 0.55, 0.1, 0.98))
	draw_circle(Vector2.ZERO, core_radius * 0.55, Color(1.0, 0.85, 0.3, 1.0))
	draw_circle(Vector2.ZERO, core_radius * 0.32, Color(1.0, 0.98, 0.88, 1.0))

func _draw_natural_crust_and_tunnels() -> void:
	var crust_thickness := base_radius - core_radius
	var depth_step_size := crust_thickness / float(depth_steps)
	var angle_slice := TAU / float(angle_steps)

	# 1. 地質地層の連続グラデーションリング
	# 深層マントル境界（玄武岩・高圧変成岩）
	draw_arc(Vector2.ZERO, core_radius + crust_thickness * 0.25, 0.0, TAU, 180, Color(0.18, 0.15, 0.19), crust_thickness * 0.5)
	# 中層堆積岩層
	draw_arc(Vector2.ZERO, core_radius + crust_thickness * 0.65, 0.0, TAU, 180, Color(0.24, 0.22, 0.25), crust_thickness * 0.4)
	# 浅層土壌層
	draw_arc(Vector2.ZERO, base_radius - 12.0, 0.0, TAU, 180, Color(0.28, 0.18, 0.13), 24.0)

	# 2. 地下空洞・坑道＆鉱脈の描画
	for a in range(angle_steps):
		var a1 := float(a) * angle_slice
		var a2 := float(a + 1) * angle_slice
		var dir1 := Vector2(cos(a1), sin(a1))
		var dir2 := Vector2(cos(a2), sin(a2))

		for d in range(depth_steps):
			var cell = grid_cells[a][d]
			var t: int = cell["type"]
			var r_out := base_radius - float(d) * depth_step_size
			var r_in := base_radius - float(d + 1) * depth_step_size

			var p1 := dir1 * r_out
			var p2 := dir2 * r_out
			var p3 := dir2 * r_in
			var p4 := dir1 * r_in

			if t == 0:
				# くり抜かれた洞窟・坑道（暗い背景）
				draw_colored_polygon(PackedVector2Array([p1, p2, p3, p4]), Color(0.06, 0.07, 0.1))
				# 木製・鉄骨支柱
				if d % 3 == 0 and a % 2 == 0:
					draw_line((p1 + p2) * 0.5, (p3 + p4) * 0.5, Color(0.38, 0.28, 0.18), 2.5)
				# 天井の鍾乳石（下向き円錐）
				if d > 0 and grid_cells[a][d - 1]["type"] != 0 and a % 3 == 0:
					var tip := ((p3 + p4) * 0.5 + (p1 + p2) * 0.5) * 0.5
					draw_colored_polygon(PackedVector2Array([p1, p2, tip]), Color(0.22, 0.2, 0.22))
			elif t >= 2:
				# 輝く鉱脈クラスター
				var ore_col := Color(1.0, 0.8, 0.25) # 鉄・ゴールド
				match t:
					3: ore_col = Color(0.9, 0.48, 0.22) # 銅
					4: ore_col = Color(0.25, 0.9, 1.0)  # シリコン
					5: ore_col = Color(0.8, 0.85, 0.98) # チタン
					6: ore_col = Color(0.35, 1.0, 0.55) # ウラン

				draw_colored_polygon(PackedVector2Array([p1, p2, p3, p4]), ore_col * 0.85)
				# 鉱脈のハイライト輝点
				var center_p := (p1 + p2 + p3 + p4) * 0.25
				draw_circle(center_p, 2.5, ore_col)
				draw_circle(center_p, 1.2, Color(1, 1, 1))

	# 3. 地表の草地ライン＆豊かな土壌
	draw_arc(Vector2.ZERO, base_radius - 2.5, 0.0, TAU, 180, Color(0.38, 0.24, 0.15), 5.0)
	draw_arc(Vector2.ZERO, base_radius, 0.0, TAU, 180, Color(0.35, 0.78, 0.24), 4.0)

	# 地表の草のフリンジ＆丸い小岩（ミクロズーム時）
	if camera_zoom > 1.2:
		for a_i in range(120, 168):
			var a_rad := float(a_i) * angle_slice
			var p_surf := Vector2(cos(a_rad), sin(a_rad)) * base_radius
			var up_v := Vector2(cos(a_rad), sin(a_rad))
			# 草の葉
			draw_line(p_surf, p_surf + up_v * (4.0 + sin(float(a_i) * 3.1) * 2.5), Color(0.42, 0.86, 0.3), 1.5)
			# 表面の小岩
			if a_i % 7 == 0:
				draw_circle(p_surf + up_v * 1.5, 3.5, Color(0.45, 0.48, 0.52))

func _draw_internal_lasers() -> void:
	for l in internal_lasers:
		var dir := Vector2(cos(l["angle"]), sin(l["angle"]))
		var p1: Vector2 = dir * float(l["r1"])
		var p2: Vector2 = dir * float(l["r2"])
		draw_line(p1, p2, l["col"], 4.5)
		draw_line(p1, p2, Color(1, 1, 1, 0.95), 1.8)
		draw_circle(p2, 7.0, l["col"])
		draw_circle(p2, 3.5, Color(1, 1, 1))

func _draw_surface_factories() -> void:
	# 画像3完全再現：地表全周の重厚なサイバー工業都市（48棟のビル、煙突、電波塔）
	var count := 48
	for i in range(count):
		var a := float(i) / float(count) * TAU
		var dir := Vector2(cos(a), sin(a))
		var perp := Vector2(-dir.y, dir.x)
		var base_p := dir * base_radius

		var b_height := 26.0 + sin(float(i) * 3.7) * 16.0
		var b_width := 15.0

		var b1 := base_p - perp * (b_width * 0.5)
		var b2 := base_p + perp * (b_width * 0.5)
		var b3 := base_p + dir * b_height + perp * (b_width * 0.5)
		var b4 := base_p + dir * b_height - perp * (b_width * 0.5)

		draw_colored_polygon(PackedVector2Array([b1, b2, b3, b4]), Color(0.18, 0.22, 0.28))
		draw_polyline(PackedVector2Array([b1, b4, b3, b2]), Color(0.35, 0.55, 0.75), 1.2)

		# 工場煙突＆もくもく煙
		if i % 3 == 0:
			var chimney_top := base_p + dir * (b_height + 16.0)
			draw_line(base_p + dir * b_height, chimney_top, Color(0.45, 0.3, 0.25), 3.5)
			draw_circle(chimney_top, 3.0, Color(1.0, 0.45, 0.1, 0.9))
			# 煙パーティクル
			for s in range(3):
				var sp := chimney_top + dir * (10.0 + s * 9.0) + perp * sin(anim_time * 2.0 + float(i) + s) * 4.0
				draw_circle(sp, 4.0 + s * 2.0, Color(0.65, 0.68, 0.72, 0.35 - s * 0.08))
		elif i % 3 == 1:
			# アンテナ尖塔＆赤色点滅ビーコン
			var pylon_top := base_p + dir * (b_height + 22.0)
			draw_line(base_p + dir * b_height, pylon_top, Color(0.6, 0.7, 0.8), 1.5)
			var blink := (sin(anim_time * 6.0 + float(i)) > 0.0)
			draw_circle(pylon_top, 3.0, Color(1.0, 0.2, 0.2, 1.0) if blink else Color(0.4, 0.1, 0.1, 0.5))
		else:
			# 冷却タワー・シアン発光窓
			draw_circle(base_p + dir * (b_height * 0.6), 3.0, Color(0.2, 0.9, 1.0, 0.95))

# 惑星表面の法線に密着配置する変換ヘルパー
func _draw_on_surface(angle: float, height_offset: float, draw_fn: Callable) -> void:
	var r := base_radius + height_offset
	var p := Vector2(cos(angle), sin(angle)) * r
	var rot := angle + PI * 0.5
	draw_set_transform(p, rot, Vector2.ONE)
	draw_fn.call()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_phase1_2_detailed_factories() -> void:
	# Stage 0: 荒野（機械一切なしのサバイバルスタート）
	if construction_stage <= 0:
		return

	# LOD制御：マクロ・恒星系ズーム時はミクロ詳細施設を非表示にして惑星スケールを保つ
	if camera_zoom < 0.85:
		return

	# -------------------------------------------------------------
	# 画像1完全再現：地上工業化と地下空洞物理物流
	# -------------------------------------------------------------

	# 1. 地上：ガントリー3Dプリンター2機（Stage >= 4、天頂左側 -1.78, -1.60 に直立接地）
	if construction_stage >= 4:
		for a_pos in [-1.78, -1.60]:
			_draw_on_surface(a_pos, 0.0, func():
				# ガントリー外枠（重機スチールフレーム＆黄色黒ハザードストライプ）
				draw_rect(Rect2(-38, -82, 76, 82), Color(0.2, 0.24, 0.3))
				draw_rect(Rect2(-30, -72, 60, 72), Color(0.05, 0.07, 0.1))
				draw_rect(Rect2(-38, -82, 76, 82), Color(0.5, 0.65, 0.8), false, 2.2)
				# 支柱トラスクロス
				draw_line(Vector2(-36, -80), Vector2(-30, -72), Color(0.4, 0.5, 0.6), 1.5)
				draw_line(Vector2(36, -80), Vector2(30, -72), Color(0.4, 0.5, 0.6), 1.5)
				# 上部プリントヘッド＆レーザー
				draw_line(Vector2(0, -72), Vector2(0, -36), Color(0.85, 0.9, 1.0), 3.5)
				draw_line(Vector2(0, -36), Vector2(0, -22), Color(1.0, 0.95, 0.4), 2.0)
				# 2本のロボット溶接アーム
				draw_line(Vector2(-24, -42), Vector2(-12, -24), Color(0.65, 0.72, 0.82), 3.0)
				draw_line(Vector2(24, -42), Vector2(12, -24), Color(0.65, 0.72, 0.82), 3.0)
				# 造形中のブルーホログラムフレーム
				draw_rect(Rect2(-18, -28, 36, 28), Color(0.2, 0.85, 1.0, 0.85), false, 1.8)
				# 超高熱レーザー着弾発光＆スパーク
				draw_circle(Vector2(0, -22), 8.0, Color(1.0, 0.95, 0.5, 0.95))
				draw_circle(Vector2(0, -22), 4.0, Color(1, 1, 1))
			)

	# 2. 地上：左エジェクターキャノン（Stage >= 3、角度 -1.48）
	if construction_stage >= 3:
		_draw_on_surface(-1.48, 0.0, func():
			# 砲台台座
			draw_rect(Rect2(-18, -18, 36, 18), Color(0.28, 0.32, 0.38))
			draw_rect(Rect2(-18, -18, 36, 18), Color(0.5, 0.6, 0.7), false, 1.5)
			# 斜め砲身（右上の空に向けて射出）
			draw_line(Vector2(-4, -8), Vector2(24, -36), Color(0.55, 0.62, 0.72), 9.0)
			draw_circle(Vector2(24, -36), 6.0, Color(1.0, 0.75, 0.25))
		)

	# 3. 地上：垂直エレベーターリフト坑口（Stage >= 2、角度 -1.40）
	if construction_stage >= 2:
		_draw_on_surface(-1.40, 0.0, func():
			# 地上リフトヘッド
			draw_rect(Rect2(-14, -32, 28, 32), Color(0.22, 0.26, 0.32))
			draw_rect(Rect2(-14, -32, 28, 32), Color(0.45, 0.6, 0.8), false, 1.5)
			draw_circle(Vector2(0, -18), 7.0, Color(0.9, 0.6, 0.2))
		)

	# 4. 地上：溶鉱炉2棟（Stage >= 1、角度 -1.30, -1.18 に接地配置）
	if construction_stage >= 1:
		_draw_on_surface(-1.30, 0.0, func():
			# 溶鉱炉A
			draw_rect(Rect2(-24, -46, 48, 46), Color(0.28, 0.22, 0.2))
			draw_rect(Rect2(-24, -46, 48, 46), Color(0.55, 0.45, 0.35), false, 2.0)
			# 煙突＆煙
			var c_top := Vector2(6, -66)
			draw_line(Vector2(6, -46), c_top, Color(0.35, 0.3, 0.25), 6.0)
			for s in range(3):
				var sp := c_top + Vector2(sin(anim_time * 2.0 + s) * 5.0, -8.0 - s * 10.0)
				draw_circle(sp, 5.0 + s * 2.5, Color(0.7, 0.72, 0.75, 0.38 - s * 0.1))
			# 燃え盛る炉口の炎
			var fw := 18.0 + sin(anim_time * 10.0) * 3.0
			draw_rect(Rect2(-fw * 0.5, -26, fw, 18), Color(1.0, 0.35, 0.05, 0.98))
			draw_circle(Vector2(0, -17), 6.0, Color(1.0, 0.92, 0.4, 1.0))
		)
		_draw_on_surface(-1.18, 0.0, func():
			# 溶鉱炉B
			draw_rect(Rect2(-22, -42, 44, 42), Color(0.26, 0.2, 0.18))
			draw_rect(Rect2(-22, -42, 44, 42), Color(0.5, 0.4, 0.3), false, 1.8)
			var c_top := Vector2(-4, -60)
			draw_line(Vector2(-4, -42), c_top, Color(0.35, 0.3, 0.25), 5.5)
			for s in range(3):
				var sp := c_top + Vector2(cos(anim_time * 2.5 + s) * 4.0, -8.0 - s * 9.0)
				draw_circle(sp, 4.5 + s * 2.0, Color(0.7, 0.72, 0.75, 0.35 - s * 0.1))
			draw_rect(Rect2(-8, -22, 16, 16), Color(1.0, 0.4, 0.08, 0.98))
			draw_circle(Vector2(0, -14), 5.0, Color(1.0, 0.85, 0.3, 1.0))
		)

	# 5. 地上：右エジェクターキャノン（Stage >= 3、角度 -1.06）
	if construction_stage >= 3:
		_draw_on_surface(-1.06, 0.0, func():
			draw_rect(Rect2(-16, -16, 32, 16), Color(0.28, 0.32, 0.38))
			draw_line(Vector2(4, -6), Vector2(-22, -34), Color(0.55, 0.62, 0.72), 8.5)
			draw_circle(Vector2(-22, -34), 5.5, Color(0.3, 0.85, 1.0))
		)

	# 6. 地上弾道：緑の点線放物線＆飛翔する赤熱鉱石（Stage >= 3）
	if construction_stage >= 3:
		var a_ej := -1.48
		var a_rc := -1.06
		var p0 := Vector2(cos(a_ej), sin(a_ej)) * (base_radius + 36.0)
		var p2 := Vector2(cos(a_rc), sin(a_rc)) * (base_radius + 34.0)
		var mid_a := (a_ej + a_rc) * 0.5
		var p1 := Vector2(cos(mid_a), sin(mid_a)) * (base_radius + 175.0)

		# 弾道スプライン
		var spline_pts := PackedVector2Array()
		var steps := 32
		for s in range(steps + 1):
			var t := float(s) / float(steps)
			var pt := (1.0 - t) * (1.0 - t) * p0 + 2.0 * (1.0 - t) * t * p1 + t * t * p2
			spline_pts.append(pt)
		for s in range(spline_pts.size() - 1):
			if s % 2 == 0:
				draw_line(spline_pts[s], spline_pts[s + 1], Color(0.2, 1.0, 0.45, 0.95), 3.0)

		# 飛翔する赤熱鉱石
		for ore in lobbed_ores:
			var t: float = ore["t"]
			var opt := (1.0 - t) * (1.0 - t) * p0 + 2.0 * (1.0 - t) * t * p1 + t * t * p2
			draw_circle(opt, 7.0, Color(1.0, 0.45, 0.1, 0.55))
			draw_circle(opt, 4.5, Color(1.0, 0.85, 0.3, 0.98))
			draw_circle(opt, 2.5, Color(1, 1, 1))

	# 7. 地下施設（左洞窟：ホッパー＆キャノン、右洞窟：地下溶鉱炉2棟、斜行コンベア）
	if construction_stage >= 2:
		# 地下リフトシャフト（垂直シャフト内部の上下動コンベア）
		var a_shaft := -1.40
		var dir_sh := Vector2(cos(a_shaft), sin(a_shaft))
		var r_top := base_radius - 2.0
		var r_bot := base_radius - 160.0
		draw_line(dir_sh * r_top, dir_sh * r_bot, Color(0.2, 0.24, 0.3), 16.0)
		draw_line(dir_sh * r_top, dir_sh * r_bot, Color(0.5, 0.6, 0.75), 16.0, false)
		for step in range(6):
			var r_step := r_top - float(step) * 26.0 - fmod(anim_time * 40.0, 26.0)
			if r_step > r_bot:
				draw_circle(dir_sh * r_step, 4.0, Color(0.95, 0.65, 0.2))

		# 地下斜行コンベア（左洞窟から垂直シャフトへ）
		var p_cave_left := Vector2(cos(-1.52), sin(-1.52)) * (base_radius - 120.0)
		var p_shaft_mid := dir_sh * (base_radius - 90.0)
		draw_line(p_cave_left, p_shaft_mid, Color(0.3, 0.35, 0.42), 6.0)
		for c_i in range(5):
			var ct := fmod(float(c_i) * 0.2 + anim_time * 0.3, 1.0)
			var cp := p_cave_left.lerp(p_shaft_mid, ct)
			draw_circle(cp, 3.5, Color(0.9, 0.6, 0.2))

		# 地下左洞窟：ホッパーと小型キャノン
		var p_hop := Vector2(cos(-1.58), sin(-1.58)) * (base_radius - 120.0)
		draw_polygon(PackedVector2Array([
			p_hop + Vector2(-12, -16), p_hop + Vector2(12, -16),
			p_hop + Vector2(6, 0), p_hop + Vector2(-6, 0)
		]), [Color(0.2, 0.75, 0.35)])

		# 地下右洞窟：地下溶鉱炉2棟（Stage >= 3）
		if construction_stage >= 3:
			for r_a in [-1.26, -1.16]:
				var p_furn := Vector2(cos(r_a), sin(r_a)) * (base_radius - 140.0)
				draw_rect(Rect2(p_furn.x - 18, p_furn.y - 32, 36, 32), Color(0.25, 0.2, 0.18))
				draw_rect(Rect2(p_furn.x - 18, p_furn.y - 32, 36, 32), Color(0.5, 0.4, 0.3), false, 1.5)
				draw_rect(Rect2(p_furn.x - 8, p_furn.y - 18, 16, 14), Color(1.0, 0.4, 0.08, 0.95))
				draw_circle(p_furn + Vector2(0, -11), 4.5, Color(1.0, 0.88, 0.3))

func _draw_orbital_shuttle() -> void:
	# シアン軌道リング
	var orbit_r := base_radius + 150.0
	draw_arc(Vector2.ZERO, orbit_r, 0.0, TAU, 128, Color(0.25, 0.88, 1.0, 0.45), 2.0)

	# 周回スペースシャトル
	var sp := Vector2(cos(shuttle_angle), sin(shuttle_angle)) * orbit_r
	var fwd := Vector2(-sin(shuttle_angle), cos(shuttle_angle))
	var perp := Vector2(-fwd.y, fwd.x)

	var p1 := sp + fwd * 16.0
	var p2 := sp - fwd * 10.0 + perp * 8.0
	var p3 := sp - fwd * 6.0
	var p4 := sp - fwd * 10.0 - perp * 8.0

	draw_colored_polygon(PackedVector2Array([p1, p2, p3, p4]), Color(0.92, 0.95, 1.0))
	draw_polyline(PackedVector2Array([p1, p2, p3, p4, p1]), Color(0.3, 0.8, 1.0), 1.5)

	# 推進火炎ジェット
	var flame_tip := sp - fwd * (14.0 + sin(anim_time * 20.0) * 8.0)
	draw_colored_polygon(PackedVector2Array([sp - perp * 4.0, sp + perp * 4.0, flame_tip]), Color(1.0, 0.5, 0.1, 0.95))
	draw_colored_polygon(PackedVector2Array([sp - perp * 2.0, sp + perp * 2.0, sp - fwd * 10.0]), Color(1.0, 0.95, 0.5))

func _draw_moon() -> void:
	# 画像4完全再現：超高精細クレーター月面・地下基地・ヘビーマスドライバー
	# 1. 3D球体陰影グラデーション（月面）
	draw_circle(Vector2.ZERO, base_radius, Color(0.72, 0.75, 0.8))

	# 球体影（左側を照らす光）
	var crescent_pts := PackedVector2Array()
	var steps := 48
	for i in range(steps + 1):
		var a := -PI * 0.5 + float(i) / float(steps) * PI
		crescent_pts.append(Vector2(cos(a), sin(a)) * base_radius)
	for i in range(steps, -1, -1):
		var a := -PI * 0.5 + float(i) / float(steps) * PI
		crescent_pts.append(Vector2(cos(a) * 0.35, sin(a)) * base_radius)
	draw_colored_polygon(crescent_pts, Color(0.42, 0.46, 0.54, 0.55))
	draw_arc(Vector2.ZERO, base_radius, 0.0, TAU, 128, Color(0.35, 0.4, 0.48), 2.5)

	# 2. 立体的な巨大クレーター群（リム発光と影）
	var craters := [
		{"pos": Vector2(-120, -90), "r": 65.0},
		{"pos": Vector2(80, -140), "r": 50.0},
		{"pos": Vector2(140, 40), "r": 78.0},
		{"pos": Vector2(-60, 110), "r": 68.0},
		{"pos": Vector2(-180, 30), "r": 42.0},
		{"pos": Vector2(25, 170), "r": 38.0}
	]
	for c in craters:
		var cp: Vector2 = c["pos"]
		var cr: float = c["r"]
		draw_circle(cp, cr, Color(0.35, 0.38, 0.45))
		draw_circle(cp + Vector2(4, 4), cr * 0.85, Color(0.28, 0.31, 0.37))
		draw_arc(cp, cr, PI * 0.8, PI * 1.8, 24, Color(0.85, 0.88, 0.95), 2.2)

	# 3. 月面地下基地の断面（同心円状の掘削迷路とミニコア）
	draw_circle(Vector2.ZERO, 90.0, Color(0.12, 0.14, 0.18))
	draw_circle(Vector2.ZERO, 55.0, Color(1.0, 0.85, 0.4, 0.9)) # ミニ溶岩コア
	draw_circle(Vector2.ZERO, 30.0, Color(1.0, 0.98, 0.85))

	# 4. ヘビーマスドライバー電磁カタパルト（画像4：右向き小惑星に向けて超長距離射出）
	var canon_pos := Vector2(base_radius - 10.0, 0)
	# 頑強な基底ガントリートラス
	draw_rect(Rect2(canon_pos.x - 20, canon_pos.y - 45, 55, 90), Color(0.22, 0.26, 0.32))
	draw_rect(Rect2(canon_pos.x - 20, canon_pos.y - 45, 55, 90), Color(0.5, 0.65, 0.8), false, 2.5)

	# 巨大電磁加速バレル
	var b_len := 260.0
	var b_h := 50.0
	draw_rect(Rect2(canon_pos.x + 35, canon_pos.y - b_h * 0.5, b_len, b_h), Color(0.26, 0.3, 0.38))
	draw_rect(Rect2(canon_pos.x + 35, canon_pos.y - b_h * 0.5, b_len, b_h), Color(0.6, 0.75, 0.95), false, 2.5)

	# 中心プラズマコアレール
	draw_line(canon_pos + Vector2(35, 0), canon_pos + Vector2(35 + b_len, 0), Color(0.2, 0.9, 1.0), 9.0)
	draw_line(canon_pos + Vector2(35, 0), canon_pos + Vector2(35 + b_len, 0), Color(1, 1, 1), 3.5)

	# 電磁加速リングコイル
	for i in range(7):
		var rx := canon_pos.x + 55.0 + i * 32.0
		draw_rect(Rect2(rx, canon_pos.y - 32, 14, 64), Color(0.3, 0.85, 1.0, 0.95))
		draw_rect(Rect2(rx, canon_pos.y - 32, 14, 64), Color(1, 1, 1), false, 1.5)

	# 砲口のマズルエネルギーフレア
	var muzzle := canon_pos + Vector2(35 + b_len, 0)
	draw_circle(muzzle, 24.0, Color(1.0, 0.6, 0.15, 0.85))
	draw_circle(muzzle, 12.0, Color(1.0, 0.95, 0.6, 0.98))
	draw_circle(muzzle, 6.0, Color(1, 1, 1))

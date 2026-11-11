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
@export var base_radius: float = 460.0
@export var core_radius: float = 160.0
@export var atmosphere_radius: float = 580.0
@export var gravity_constant: float = 380000.0
@export var atmosphere_drag: float = 0.4
@export var orbit_parent: Node2D = null
@export var orbit_distance: float = 0.0
@export var orbit_speed: float = 0.04
@export var orbit_angle: float = 0.0

var anim_time: float = 0.0

# 軌道周回スペースシャトル（画像3完全再現）
var shuttle_angle: float = 0.45
var shuttle_speed: float = 0.4

# 内部採掘レーザー（画像3完全再現：青・緑・黄）
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

func _ready() -> void:
	_init_grid()
	_init_internal_lasers()
	_init_lobbed_ores()

func _init_internal_lasers() -> void:
	internal_lasers.append({"angle": -0.85, "r1": 210.0, "r2": 410.0, "col": Color(0.2, 0.85, 1.0, 0.95)})
	internal_lasers.append({"angle": -0.25, "r1": 250.0, "r2": 430.0, "col": Color(0.3, 1.0, 0.4, 0.95)})
	internal_lasers.append({"angle": 0.65, "r1": 200.0, "r2": 390.0, "col": Color(1.0, 0.85, 0.2, 0.95)})
	internal_lasers.append({"angle": 1.45, "r1": 240.0, "r2": 420.0, "col": Color(0.3, 0.9, 1.0, 0.95)})
	internal_lasers.append({"angle": 2.25, "r1": 210.0, "r2": 380.0, "col": Color(0.4, 1.0, 0.5, 0.95)})
	internal_lasers.append({"angle": -2.15, "r1": 250.0, "r2": 440.0, "col": Color(1.0, 0.6, 0.2, 0.95)})

func _init_lobbed_ores() -> void:
	for i in range(6):
		lobbed_ores.append({
			"t": float(i) / 6.0,
			"speed": 0.32,
			"p0": Vector2(-120.0, -base_radius - 22.0),
			"p1": Vector2(60.0, -base_radius - 130.0),
			"p2": Vector2(240.0, -base_radius - 12.0)
		})

func _init_grid() -> void:
	grid_cells.clear()
	var crust_thickness := base_radius - core_radius
	var depth_step_size := crust_thickness / float(depth_steps)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(body_name)

	for a in range(angle_steps):
		var column: Array = []
		for d in range(depth_steps):
			var depth_norm := float(d) / float(depth_steps)
			var angle_norm := float(a) / float(angle_steps)
			var type := 1
			var hp := 12.0

			# 環状トンネル迷路
			var is_ring_tunnel := (d >= 5 and d <= 7 and int(a / 8) % 3 != 0) or (d >= 13 and d <= 15 and int(a / 6) % 3 != 0)
			if is_ring_tunnel:
				type = 0

			if type != 0:
				var n1 := sin(angle_norm * TAU * 8.0 + depth_norm * 5.0)
				var n2 := cos(angle_norm * TAU * 14.0 - depth_norm * 7.0)
				if depth_norm < 0.35:
					if n1 > 0.4: type = 2
					elif n2 > 0.4: type = 3
				elif depth_norm < 0.7:
					if n1 > 0.3: type = 4
					elif n2 > 0.35: type = 2
				else:
					if n1 > 0.35: type = 5
					elif n2 > 0.4: type = 6

			column.append({
				"type": type,
				"hp": hp,
				"max_hp": hp,
				"scanned_alpha": 0.0
			})
		grid_cells.append(column)

func _process(delta: float) -> void:
	anim_time += delta
	shuttle_angle += shuttle_speed * delta
	if shuttle_angle >= TAU: shuttle_angle -= TAU

	if orbit_parent != null and orbit_distance > 0.0:
		orbit_angle += orbit_speed * delta
		global_position = orbit_parent.global_position + Vector2(cos(orbit_angle), sin(orbit_angle)) * orbit_distance

	if scan_active:
		scan_radius += 380.0 * delta
		if scan_radius > scan_max_radius:
			scan_active = false

	# 飛翔鉱石
	for ore in lobbed_ores:
		ore["t"] += ore["speed"] * delta
		if ore["t"] >= 1.0:
			ore["t"] -= 1.0

	# パーティクル発生（溶鉱炉の煙、火の粉、3Dプリンター溶接火花）
	if randf() < 0.5:
		smoke_particles.append({
			"pos": Vector2(175.0, -base_radius - 40.0) + Vector2(randf_range(-4, 4), 0),
			"vel": Vector2(randf_range(-8, 8), -randf_range(40, 75)),
			"life": 1.2,
			"max_life": 1.2
		})
		ember_particles.append({
			"pos": Vector2(175.0, -base_radius - 40.0) + Vector2(randf_range(-5, 5), 0),
			"vel": Vector2(randf_range(-20, 20), -randf_range(50, 90)),
			"life": 0.6,
			"max_life": 0.6
		})
	if randf() < 0.7:
		spark_particles.append({
			"pos": Vector2(-280.0, -base_radius - 35.0) + Vector2(randf_range(-12, 12), randf_range(-10, 10)),
			"vel": Vector2(randf_range(-60, 60), randf_range(-50, 30)),
			"life": 0.25,
			"max_life": 0.25
		})

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
	var atmo_col := Color(0.2, 0.6, 1.0, 0.15)
	draw_circle(Vector2.ZERO, atmosphere_radius, atmo_col)
	draw_arc(Vector2.ZERO, atmosphere_radius, 0.0, TAU, 96, Color(0.3, 0.85, 1.0, 0.4), 2.5)

	# 2. 燃え盛る流体マグマコア（画像3中央完全再現・ウニ状トゲトゲ完全撤廃）
	_draw_fluid_magma_core()

	# 3. 自然な岩盤層と同心円状坑道迷路＆鉱脈パルス
	_draw_natural_crust_and_tunnels()

	# 4. 放射状採掘レーザービーム（画像3の青・緑・黄）
	_draw_internal_lasers()

	# 5. 地表360度全周の工場群（ビル、煙突、電波塔、マスドライバー）
	_draw_surface_factories()

	# 6. 画像1の地上＆地下詳細工場（ガントリー3Dプリンター、キャノンイジェクター、溶鉱炉、リフトコンベア）
	_draw_phase1_2_detailed_factories()

	# 7. シアン周回軌道リング＆スペースシャトル（画像3完全再現）
	_draw_orbital_shuttle()

	# 8. スキャンパルス
	if scan_active and scan_radius < scan_max_radius:
		draw_arc(Vector2.ZERO, scan_radius, 0.0, TAU, 64, Color(0.2, 1.0, 0.85, 1.0 - (scan_radius / scan_max_radius)), 2.5)

func _draw_fluid_magma_core() -> void:
	# 多層のグラデーション発光マグマ球（強烈なオレンジ〜赤のブルーム）
	draw_circle(Vector2.ZERO, core_radius + 24.0, Color(1.0, 0.35, 0.05, 0.25)) # 外層グロー
	draw_circle(Vector2.ZERO, core_radius + 10.0, Color(1.0, 0.45, 0.1, 0.6))
	draw_circle(Vector2.ZERO, core_radius, Color(0.95, 0.22, 0.02, 0.98))       # 溶岩ベース

	# 対流する熱波フレア
	var steps := 36
	for i in range(steps):
		var a := float(i) / float(steps) * TAU + anim_time * 0.5
		var flare_r := core_radius * 0.88 + sin(a * 7.0 + anim_time * 3.0) * 14.0
		var p := Vector2(cos(a), sin(a)) * flare_r
		draw_line(Vector2.ZERO, p, Color(1.0, 0.65, 0.15, 0.35), 10.0)

	# 中心高熱白色・ゴールデンコア
	draw_circle(Vector2.ZERO, core_radius * 0.62, Color(1.0, 0.82, 0.35, 0.98))
	draw_circle(Vector2.ZERO, core_radius * 0.38, Color(1.0, 0.98, 0.85, 1.0))

func _draw_natural_crust_and_tunnels() -> void:
	var crust_thickness := base_radius - core_radius
	var depth_step_size := crust_thickness / float(depth_steps)
	var angle_slice := TAU / float(angle_steps)

	for a in range(angle_steps):
		var a1 := float(a) * angle_slice
		var a2 := float(a + 1) * angle_slice
		var dir1 := Vector2(cos(a1), sin(a1))
		var dir2 := Vector2(cos(a2), sin(a2))

		for d in range(depth_steps):
			var cell = grid_cells[a][d]
			var t: int = cell["type"]
			if t == 0:
				continue # トンネル空洞（背景暗闇）

			var r_out := base_radius - float(d) * depth_step_size
			var r_in := base_radius - float(d + 1) * depth_step_size

			# 自然な暗褐色岩盤と鉱脈
			var col: Color = Color(0.2, 0.18, 0.16) # 暗褐色岩肌
			match t:
				2: col = Color(0.9, 0.6, 0.25)   # 鉄鉱脈
				3: col = Color(0.95, 0.5, 0.2)   # 銅鉱脈
				4: col = Color(0.2, 0.85, 1.0)   # シリコン
				5: col = Color(0.8, 0.85, 1.0)   # チタン
				6: col = Color(0.3, 1.0, 0.45)   # ウラン

			var p1 := dir1 * r_out
			var p2 := dir2 * r_out
			var p3 := dir2 * r_in
			var p4 := dir1 * r_in
			draw_colored_polygon(PackedVector2Array([p1, p2, p3, p4]), col)

	# 地表の緑の草地ライン（画像1, 3完全再現）
	draw_arc(Vector2.ZERO, base_radius, 0.0, TAU, 180, Color(0.35, 0.75, 0.25), 3.5)
	# 坑道の支柱・足場リング
	draw_arc(Vector2.ZERO, base_radius - depth_step_size * 6, 0.0, TAU, 96, Color(0.35, 0.38, 0.42, 0.5), 1.5)
	draw_arc(Vector2.ZERO, base_radius - depth_step_size * 14, 0.0, TAU, 96, Color(0.35, 0.38, 0.42, 0.5), 1.5)

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
	# 地表全周のビル群、煙突、電波塔（画像3完全再現）
	var count := 42
	for i in range(count):
		var a := float(i) / float(count) * TAU
		var dir := Vector2(cos(a), sin(a))
		var perp := Vector2(-dir.y, dir.x)
		var base_p := dir * base_radius

		var b_height := 24.0 + sin(float(i) * 3.7) * 14.0
		var b_width := 14.0

		var b1 := base_p - perp * (b_width * 0.5)
		var b2 := base_p + perp * (b_width * 0.5)
		var b3 := base_p + dir * b_height + perp * (b_width * 0.5)
		var b4 := base_p + dir * b_height - perp * (b_width * 0.5)

		draw_colored_polygon(PackedVector2Array([b1, b2, b3, b4]), Color(0.18, 0.22, 0.28))
		draw_polyline(PackedVector2Array([b1, b4, b3, b2]), Color(0.35, 0.55, 0.75), 1.2)

		if i % 3 == 0:
			# 煙突
			draw_line(base_p + dir * b_height, base_p + dir * (b_height + 16.0), Color(0.45, 0.3, 0.25), 3.5)
			draw_circle(base_p + dir * (b_height + 17.0), 3.0, Color(1.0, 0.45, 0.1, 0.9))
		elif i % 3 == 1:
			# 青白窓
			draw_circle(base_p + dir * (b_height * 0.65), 2.5, Color(0.2, 0.9, 1.0, 0.95))

func _draw_phase1_2_detailed_factories() -> void:
	# 画像1（巨大ガントリー3Dプリンター、キャノンイジェクター、溶鉱炉、垂直リフトシャフト）
	# 1. ガントリー3Dプリンター2機（Vector2(-280, -base_radius)）
	for p_idx in [0, 1]:
		var px: float = -320.0 + float(p_idx) * 90.0
		var py := -base_radius
		# ガントリー金属トラス
		draw_rect(Rect2(px - 32, py - 70, 64, 70), Color(0.2, 0.24, 0.3))
		draw_rect(Rect2(px - 24, py - 60, 48, 60), Color(0.06, 0.08, 0.12))
		draw_rect(Rect2(px - 32, py - 70, 64, 70), Color(0.5, 0.65, 0.8), false, 2.0)
		# 上部プリントヘッド＆レーザー
		draw_line(Vector2(px, py - 60), Vector2(px, py - 28), Color(0.9, 0.95, 1.0), 3.5)
		draw_line(Vector2(px, py - 28), Vector2(px, py - 15), Color(1.0, 0.95, 0.4), 2.0)
		# 溶接ロボットアーム
		draw_line(Vector2(px - 20, py - 30), Vector2(px - 8, py - 18), Color(0.6, 0.7, 0.8), 2.5)
		draw_line(Vector2(px + 20, py - 30), Vector2(px + 8, py - 18), Color(0.6, 0.7, 0.8), 2.5)
		# 造形中の青白ホログラムフレーム
		draw_rect(Rect2(px - 15, py - 22, 30, 22), Color(0.2, 0.85, 1.0, 0.85), false, 1.8)
		# レーザー着弾強烈発光コア
		draw_circle(Vector2(px, py - 15), 7.0, Color(1.0, 0.95, 0.5, 0.95))
		draw_circle(Vector2(px, py - 15), 3.5, Color(1, 1, 1))

	# 2. キャノン型イジェクター砲台（Vector2(-120, -base_radius)）
	var c_pos := Vector2(-120.0, -base_radius)
	draw_rect(Rect2(c_pos.x - 16, c_pos.y - 20, 32, 20), Color(0.28, 0.32, 0.38))
	draw_line(c_pos + Vector2(0, -12), c_pos + Vector2(28, -36), Color(0.55, 0.6, 0.7), 8.0)
	draw_circle(c_pos + Vector2(28, -36), 5.0, Color(1.0, 0.7, 0.2)) # 砲口発光

	# 垂直リフトシャフト（地下から地上へ物資を運ぶコンベア塔）
	draw_rect(Rect2(-50, -base_radius - 10, 16, 50), Color(0.2, 0.25, 0.3))
	draw_rect(Rect2(-50, -base_radius - 10, 16, 50), Color(0.4, 0.5, 0.6), false, 1.5)
	for ly in range(0, 45, 10):
		draw_circle(Vector2(-42, -base_radius + ly), 3.0, Color(0.9, 0.6, 0.2))

	# 緑の放物線弾道スプライン（画像1完全再現）
	var spline_pts := PackedVector2Array()
	var steps := 28
	var p0 := Vector2(-120.0, -base_radius - 22.0)
	var p1 := Vector2(60.0, -base_radius - 130.0)
	var p2 := Vector2(240.0, -base_radius - 12.0)
	for s in range(steps + 1):
		var t := float(s) / float(steps)
		var pt := (1.0 - t) * (1.0 - t) * p0 + 2.0 * (1.0 - t) * t * p1 + t * t * p2
		spline_pts.append(pt)
	for s in range(spline_pts.size() - 1):
		if s % 2 == 0:
			draw_line(spline_pts[s], spline_pts[s + 1], Color(0.2, 1.0, 0.45, 0.9), 3.0)

	# 飛翔鉱石（赤熱グロー）
	for ore in lobbed_ores:
		var t: float = ore["t"]
		var opt := (1.0 - t) * (1.0 - t) * p0 + 2.0 * (1.0 - t) * t * p1 + t * t * p2
		draw_circle(opt, 6.0, Color(1.0, 0.45, 0.1, 0.6))
		draw_circle(opt, 4.0, Color(1.0, 0.85, 0.3, 0.98))
		draw_circle(opt, 2.0, Color(1, 1, 1))

	# 3. 溶鉱炉2機（右側 Vector2(180, -base_radius)）
	for sm_idx in [0, 1]:
		var sx: float = 160.0 + float(sm_idx) * 55.0
		var sy := -base_radius
		draw_rect(Rect2(sx - 20, sy - 42, 40, 42), Color(0.28, 0.22, 0.2))
		draw_rect(Rect2(sx - 20, sy - 42, 40, 42), Color(0.55, 0.45, 0.35), false, 1.8)
		# 煙突
		draw_line(Vector2(sx + 6, sy - 42), Vector2(sx + 6, sy - 60), Color(0.35, 0.3, 0.25), 6.0)
		# 燃え盛る炉口の激しい炎
		var flame_w := 16.0 + sin(anim_time * 10.0 + float(sm_idx)) * 3.0
		draw_rect(Rect2(sx - flame_w * 0.5, sy - 24, flame_w, 16), Color(1.0, 0.35, 0.05, 0.98))
		draw_circle(Vector2(sx, sy - 16), 5.0, Color(1.0, 0.92, 0.4, 1.0))

	# 4. ホッパー（受け皿）
	draw_polygon(PackedVector2Array([
		Vector2(224, -base_radius - 24), Vector2(256, -base_radius - 24),
		Vector2(246, -base_radius), Vector2(234, -base_radius)
	]), [Color(0.2, 0.75, 0.35)])

	# パーティクル描画
	for sp in smoke_particles:
		var alpha: float = sp["life"] / sp["max_life"]
		draw_circle(sp["pos"], 7.0 * (1.8 - alpha), Color(0.25, 0.22, 0.2, alpha * 0.55))
	for ep in ember_particles:
		var alpha: float = ep["life"] / ep["max_life"]
		draw_circle(ep["pos"], 2.5, Color(1.0, 0.6, 0.1, alpha))
	for kp in spark_particles:
		var alpha: float = kp["life"] / kp["max_life"]
		draw_circle(kp["pos"], 3.0, Color(1.0, 0.95, 0.4, alpha))

func _draw_orbital_shuttle() -> void:
	# シアン周回軌道リング（画像3完全再現）
	var orbit_r := 540.0
	draw_arc(Vector2.ZERO, orbit_r, 0.0, TAU, 144, Color(0.2, 0.85, 1.0, 0.85), 2.5)

	# 軌道ロケット（大型スペースシャトル、画像3完全再現）
	var s_pos := Vector2(cos(shuttle_angle), sin(shuttle_angle)) * orbit_r
	var fwd := Vector2(-sin(shuttle_angle), cos(shuttle_angle))
	var perp := Vector2(-fwd.y, fwd.x)

	# シャトル本体（白×シアン、サイズ28px）
	var r1 := s_pos + fwd * 20.0
	var r2 := s_pos - fwd * 14.0 + perp * 11.0
	var r3 := s_pos - fwd * 14.0 - perp * 11.0
	draw_colored_polygon(PackedVector2Array([r1, r2, r3]), Color(0.95, 0.96, 1.0))
	draw_polyline(PackedVector2Array([r1, r2, r3, r1]), Color(0.4, 0.6, 0.8), 1.5)
	# コックピット窓
	draw_circle(s_pos + fwd * 6.0, 4.0, Color(0.2, 0.8, 1.0))

	# 激しい推進火炎ジェット（オレンジ〜黄色の二重コーン）
	var flame_len := 32.0 + sin(anim_time * 24.0) * 10.0
	var flame_tip := s_pos - fwd * (14.0 + flame_len)
	draw_colored_polygon(PackedVector2Array([
		s_pos - fwd * 14.0 + perp * 7.0,
		s_pos - fwd * 14.0 - perp * 7.0,
		flame_tip
	]), Color(1.0, 0.45, 0.05, 0.95))
	draw_colored_polygon(PackedVector2Array([
		s_pos - fwd * 14.0 + perp * 3.5,
		s_pos - fwd * 14.0 - perp * 3.5,
		s_pos - fwd * (14.0 + flame_len * 0.55)
	]), Color(1.0, 0.98, 0.7, 1.0))

func _draw_moon() -> void:
	# 月（球体陰影、クレーター、画像4完全再現）
	draw_circle(Vector2.ZERO, base_radius, Color(0.72, 0.75, 0.8))
	draw_arc(Vector2.ZERO, base_radius, 0.0, TAU, 96, Color(0.5, 0.55, 0.6), 2.0)
	for c_deg in [0.2, 0.9, 1.8, 2.7, 3.8, 5.0]:
		var cp := Vector2(cos(c_deg), sin(c_deg)) * (base_radius * 0.65)
		draw_circle(cp, 32.0, Color(0.56, 0.6, 0.65))
		draw_circle(cp + Vector2(4, 4), 28.0, Color(0.65, 0.68, 0.74))

	# マスドライバー電磁カタパルト砲身（画像4完全再現）
	var canon_pos := Vector2(base_radius, 0)
	draw_rect(Rect2(canon_pos.x, canon_pos.y - 12, 85, 24), Color(0.35, 0.4, 0.5))
	draw_rect(Rect2(canon_pos.x, canon_pos.y - 12, 85, 24), Color(0.6, 0.7, 0.85), false, 2.0)
	draw_line(canon_pos + Vector2(10, 0), canon_pos + Vector2(95, 0), Color(0.2, 0.9, 1.0), 6.0)
	draw_circle(canon_pos + Vector2(95, 0), 8.0, Color(0.85, 1.0, 1.0))
	draw_circle(canon_pos + Vector2(100, 0), 16.0, Color(0.3, 0.9, 1.0, 0.75))

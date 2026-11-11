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
@export var body_name: String = "Planet"
@export var base_radius: float = 400.0          # 表面半径
@export var core_radius: float = 280.0          # 不可侵コア半径（小惑星は0）
@export var atmosphere_radius: float = 560.0    # 大気圏半径（大気なしはbase_radius）
@export var gravity_constant: float = 350000.0  # G * M
@export var atmosphere_drag: float = 0.5       # 大気抵抗係数
@export var orbit_parent: Node2D = null
@export var orbit_distance: float = 0.0
@export var orbit_speed: float = 0.05
@export var orbit_angle: float = 0.0
@export var body_color: Color = Color(0.2, 0.4, 0.7)
@export var core_color: Color = Color(1.0, 0.35, 0.1, 0.9)

# 極座標グリッド定義
# 角度スライス数と深さレイヤー数
var angle_steps: int = 180
var depth_steps: int = 20

# 各セルのデータ: {"type": int, "hp": float, "max_hp": float, "scanned_alpha": float}
# 0: 空洞, 1: 岩盤(Rock), 2: 鉄(Iron), 3: 銅(Copper), 4: シリコン(Silicon), 5: チタン(Titanium), 6: ウラン(Uranium)
var grid_cells: Array = []

# スキャン波エフェクト用
var scan_radius: float = 0.0
var scan_active: bool = false
var scan_speed: float = 300.0
var scan_max_radius: float = 600.0

# 彗星用
var comet_tail_particles: Array[Dictionary] = []

func _ready() -> void:
	_init_grid()

func _process(delta: float) -> void:
	# 公転処理
	if orbit_parent != null and orbit_distance > 0.0:
		orbit_angle += orbit_speed * delta
		var offset := Vector2(cos(orbit_angle), sin(orbit_angle)) * orbit_distance
		# 彗星の楕円軌道
		if body_type == BodyType.COMET:
			var ecc := 0.6
			var r := orbit_distance * (1.0 - ecc * ecc) / (1.0 + ecc * cos(orbit_angle))
			offset = Vector2(cos(orbit_angle), sin(orbit_angle)) * r
		global_position = orbit_parent.global_position + offset

	# スキャンパルスの更新
	if scan_active:
		scan_radius += scan_speed * delta
		if scan_radius > scan_max_radius:
			scan_active = false
		queue_redraw()

	# スキャンハイライトの減衰
	var needs_redraw := false
	for a in range(angle_steps):
		for d in range(depth_steps):
			var cell = grid_cells[a][d]
			if cell["scanned_alpha"] > 0.0:
				cell["scanned_alpha"] = maxf(0.0, cell["scanned_alpha"] - delta * 0.4)
				needs_redraw = true

	# 彗星の尾エフェクト
	if body_type == BodyType.COMET:
		_update_comet_tail(delta)
		needs_redraw = true

	if needs_redraw:
		queue_redraw()

func _init_grid() -> void:
	grid_cells.clear()
	var crust_thickness := base_radius - core_radius
	var depth_step_size := crust_thickness / float(depth_steps)
	
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(body_name)

	for a in range(angle_steps):
		var column: Array = []
		for d in range(depth_steps):
			var r := base_radius - float(d) * depth_step_size
			var type := 1 # 基本岩盤
			var hp := 10.0
			
			# 鉱脈のプロシージャル生成
			var angle_norm := float(a) / float(angle_steps)
			var depth_norm := float(d) / float(depth_steps)
			
			# ノイズ風の鉱脈配置
			var n1 := sin(angle_norm * TAU * 6.0 + depth_norm * 4.0)
			var n2 := cos(angle_norm * TAU * 12.0 - depth_norm * 8.0)
			
			if body_type == BodyType.ASTEROID:
				# 小惑星はレアメタルやチタンが豊富
				if n1 > 0.35 and depth_norm > 0.2:
					type = 5 # Titanium
					hp = 25.0
				elif n2 > 0.3:
					type = 2 # Iron
					hp = 15.0
			elif body_type == BodyType.COMET:
				# 彗星はウラン・重水素・氷
				if n1 > 0.1:
					type = 6 # Uranium/Fuel
					hp = 12.0
				else:
					type = 1
					hp = 6.0
			else:
				# 通常惑星・月
				if depth_norm < 0.25:
					# 浅層：鉄・銅
					if n1 > 0.4:
						type = 2 # Iron
						hp = 12.0
					elif n2 > 0.45:
						type = 3 # Copper
						hp = 12.0
				elif depth_norm < 0.65:
					# 中層：シリコン・銅・鉄
					if n1 > 0.3:
						type = 4 # Silicon
						hp = 16.0
					elif n2 > 0.35:
						type = 2 # Iron
						hp = 15.0
					elif n1 < -0.4:
						type = 3 # Copper
						hp = 14.0
				else:
					# 深層：チタン・ウラン
					if n1 > 0.4:
						type = 5 # Titanium
						hp = 25.0
					elif n2 > 0.5:
						type = 6 # Uranium
						hp = 30.0

			column.append({
				"type": type,
				"hp": hp,
				"max_hp": hp,
				"scanned_alpha": 0.0
			})
		grid_cells.append(column)

func get_gravity_at(world_pos: Vector2) -> Vector2:
	var to_center := global_position - world_pos
	var dist := to_center.length()
	if dist < 1.0:
		return Vector2.ZERO
	
	var dir := to_center / dist
	
	# 万有引力 (外側は 1/r^2、地殻内は滑らかに減衰)
	var g_accel: float = 0.0
	if dist >= base_radius:
		g_accel = gravity_constant / (dist * dist)
	else:
		# 地表下では均質球内部のように r に比例して減衰
		var surface_g := gravity_constant / (base_radius * base_radius)
		g_accel = surface_g * (dist / base_radius)
		
	return dir * g_accel

func get_atmosphere_drag_at(world_pos: Vector2, vel: Vector2) -> Vector2:
	if atmosphere_radius <= base_radius:
		return Vector2.ZERO
	var dist := (world_pos - global_position).length()
	if dist > atmosphere_radius or dist < base_radius:
		return Vector2.ZERO
	
	# 大気密度（地表で1.0、大気圏外縁で0.0）
	var density := (atmosphere_radius - dist) / (atmosphere_radius - base_radius)
	var speed := vel.length()
	if speed < 1.0:
		return Vector2.ZERO
	# 抵抗力 F_drag = - 0.5 * density * Cd * v^2 * v_hat
	return -vel.normalized() * (0.5 * density * atmosphere_drag * speed * speed * 0.002)

func trigger_scanner(origin_pos: Vector2, max_dist: float = 500.0) -> void:
	scan_active = true
	scan_radius = 0.0
	scan_max_radius = max_dist
	
	# 範囲内のセルをハイライト
	var crust_thickness := base_radius - core_radius
	var depth_step_size := crust_thickness / float(depth_steps)
	
	for a in range(angle_steps):
		var angle := float(a) * (TAU / float(angle_steps))
		var dir := Vector2(cos(angle), sin(angle))
		for d in range(depth_steps):
			var r := base_radius - (float(d) + 0.5) * depth_step_size
			var cell_pos := global_position + dir * r
			if cell_pos.distance_to(origin_pos) <= max_dist:
				var cell = grid_cells[a][d]
				if cell["type"] > 1: # 鉱石のみ
					cell["scanned_alpha"] = 1.0
	queue_redraw()

func mine_at_world_pos(world_pos: Vector2, power: float) -> Dictionary:
	var local_pos := world_pos - global_position
	var dist := local_pos.length()
	
	# 不可侵コアチェック
	if dist < core_radius:
		return {"success": false, "reason": "core_limit"}
	
	if dist > base_radius + 15.0:
		return {"success": false, "reason": "out_of_reach"}
		
	var angle := local_pos.angle()
	if angle < 0.0:
		angle += TAU
		
	var a_idx := int((angle / TAU) * float(angle_steps)) % angle_steps
	var crust_thickness := base_radius - core_radius
	var depth_step_size := crust_thickness / float(depth_steps)
	
	var depth_from_surface := base_radius - dist
	var d_idx := int(depth_from_surface / depth_step_size)
	d_idx = clampi(d_idx, 0, depth_steps - 1)
	
	var cell = grid_cells[a_idx][d_idx]
	if cell["type"] == 0:
		return {"success": false, "reason": "empty"}
		
	cell["hp"] -= power
	queue_redraw()
	
	if cell["hp"] <= 0.0:
		var mined_type: int = cell["type"]
		cell["type"] = 0 # 掘削完了で空洞化
		queue_redraw()
		
		var res_name := "rock"
		var amount := 2.0
		match mined_type:
			1: res_name = "rock"; amount = 1.0
			2: res_name = "iron"; amount = 3.0
			3: res_name = "copper"; amount = 3.0
			4: res_name = "silicon"; amount = 2.0
			5: res_name = "titanium"; amount = 2.0
			6: res_name = "uranium"; amount = 1.5
			
		return {
			"success": true,
			"broken": true,
			"resource": res_name,
			"amount": amount,
			"pos": world_pos
		}
	else:
		return {
			"success": true,
			"broken": false,
			"hp_left": cell["hp"]
		}

func is_surface_walkable_at(angle_rad: float) -> float:
	# 指定した角度の外側表面半径を返す
	if angle_rad < 0.0:
		angle_rad += TAU
	var a_idx := int((angle_rad / TAU) * float(angle_steps)) % angle_steps
	var crust_thickness := base_radius - core_radius
	var depth_step_size := crust_thickness / float(depth_steps)
	
	for d in range(depth_steps):
		if grid_cells[a_idx][d]["type"] != 0:
			return base_radius - float(d) * depth_step_size
	return core_radius

func _update_comet_tail(delta: float) -> void:
	# 太陽方向（中心 Vector2.ZERO）からの反発
	var sun_dir := -global_position.normalized()
	if randf() < 0.4:
		comet_tail_particles.append({
			"pos": Vector2.ZERO + Vector2(randf_range(-15, 15), randf_range(-15, 15)),
			"vel": -sun_dir * randf_range(80.0, 160.0) + Vector2(randf_range(-20, 20), randf_range(-20, 20)),
			"life": 1.0,
			"max_life": randf_range(0.8, 1.5)
		})
	var i := 0
	while i < comet_tail_particles.size():
		var p = comet_tail_particles[i]
		p["pos"] += p["vel"] * delta
		p["life"] -= delta / p["max_life"]
		if p["life"] <= 0.0:
			comet_tail_particles.remove_at(i)
		else:
			i += 1

func _draw() -> void:
	# 1. 大気圏の描画
	if atmosphere_radius > base_radius:
		var atmo_color := body_color
		atmo_color.a = 0.15
		draw_circle(Vector2.ZERO, atmosphere_radius, atmo_color)
		var atmo_rim := body_color.lightened(0.3)
		atmo_rim.a = 0.3
		draw_arc(Vector2.ZERO, atmosphere_radius, 0.0, TAU, 64, atmo_rim, 2.0)

	# 2. 彗星の尾の描画
	if body_type == BodyType.COMET:
		for p in comet_tail_particles:
			var alpha: float = clampf(p["life"], 0.0, 1.0) * 0.4
			var col := Color(0.4, 0.8, 1.0, alpha)
			draw_circle(p["pos"], randf_range(3.0, 7.0), col)

	# 3. 不可侵コア（マントル）の描画
	if core_radius > 0.0:
		draw_circle(Vector2.ZERO, core_radius, core_color)
		# コアの表面グロー
		var rim_col := core_color.lightened(0.4)
		rim_col.a = 0.8
		draw_arc(Vector2.ZERO, core_radius, 0.0, TAU, 64, rim_col, 3.0)

	# 4. 地殻タイルの描画
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
				continue # 掘削済み空洞

			var r_outer := base_radius - float(d) * depth_step_size
			var r_inner := base_radius - float(d + 1) * depth_step_size
			
			var col: Color = body_color
			match t:
				1: # Rock
					col = body_color.darkened(float(d) / float(depth_steps) * 0.4)
				2: # Iron
					col = Color(0.85, 0.55, 0.3)
				3: # Copper
					col = Color(0.9, 0.45, 0.2)
				4: # Silicon
					col = Color(0.3, 0.85, 0.9)
				5: # Titanium
					col = Color(0.8, 0.85, 0.95)
				6: # Uranium
					col = Color(0.3, 1.0, 0.4)

			# スキャンハイライト
			if cell["scanned_alpha"] > 0.0:
				col = col.lerp(Color(1.0, 1.0, 0.2), cell["scanned_alpha"] * 0.8)

			var p1 := dir1 * r_outer
			var p2 := dir2 * r_outer
			var p3 := dir2 * r_inner
			var p4 := dir1 * r_inner

			draw_colored_polygon(PackedVector2Array([p1, p2, p3, p4]), col)

	# 5. 地表境界線と大気ライン
	draw_arc(Vector2.ZERO, base_radius, 0.0, TAU, 128, Color(1, 1, 1, 0.25), 1.5)

	# 6. スキャンパルスリングの描画
	if scan_active and scan_radius < scan_max_radius:
		var pulse_col := Color(0.2, 0.9, 1.0, 1.0 - (scan_radius / scan_max_radius))
		draw_arc(Vector2.ZERO, scan_radius, 0.0, TAU, 64, pulse_col, 2.5)

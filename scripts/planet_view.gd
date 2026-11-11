# planet_view.gd
class_name PlanetView
extends Node2D

var game_state: GameState = null
var backdrop_tex: Texture2D = null

# 中心座標
var planet_center: Vector2 = Vector2(640.0, 360.0)

# 周回シャトル
var shuttle_angle: float = 0.8
var shuttle_sparks: Array[Dictionary] = []

# 採掘レーザーの動的脈動＆着弾スパーク
var laser_pulse: float = 0.0
var laser_impact_sparks: Array[Dictionary] = []
var laser_intake_particles: Array[Dictionary] = []

# コア周縁の太陽プロミネンス火炎
var core_spark_timer: float = 0.0
var core_sparks: Array[Dictionary] = []

# プレイヤー操作可能プローブ
var probe_pos: Vector2 = Vector2(640.0, 110.0)
var probe_angle: float = -PI * 0.5
var probe_dist: float = 270.0
var probe_vel: float = 0.0

func setup(p_game_state: GameState) -> void:
	game_state = p_game_state
	backdrop_tex = load("res://assets/textures/tex_planet_orbit_backdrop.png")

func _process(delta: float) -> void:
	if not visible:
		return

	# 周回シャトルの移動
	shuttle_angle += delta * 0.35
	if shuttle_angle > TAU:
		shuttle_angle -= TAU

	var shuttle_r := 300.0
	var s_pos := planet_center + Vector2(cos(shuttle_angle), sin(shuttle_angle)) * shuttle_r
	var tangent := Vector2(-sin(shuttle_angle), cos(shuttle_angle))
	shuttle_sparks.append({
		"pos": s_pos - tangent * 14.0 + Vector2(randf_range(-2, 2), randf_range(-2, 2)),
		"vel": -tangent * randf_range(40, 90) + Vector2(randf_range(-10, 10), randf_range(-10, 10)),
		"col": Color(1.0, randf_range(0.5, 0.9), 0.2, 0.9),
		"life": 0.45, "max_life": 0.45, "size": randf_range(2.0, 4.0)
	})

	var keep_sparks: Array[Dictionary] = []
	for sp in shuttle_sparks:
		sp["life"] -= delta
		if sp["life"] > 0.0:
			sp["pos"] += sp["vel"] * delta
			keep_sparks.append(sp)
	shuttle_sparks = keep_sparks

	# コア周縁の紅炎プラズマ火花
	core_spark_timer += delta
	if core_spark_timer >= 0.06:
		core_spark_timer = 0.0
		var c_ang := randf_range(0, TAU)
		var c_dist := randf_range(68.0, 78.0)
		core_sparks.append({
			"pos": planet_center + Vector2(cos(c_ang), sin(c_ang)) * c_dist,
			"vel": Vector2(cos(c_ang), sin(c_ang)) * randf_range(15, 45) + Vector2(randf_range(-8, 8), randf_range(-8, 8)),
			"col": Color(1.0, randf_range(0.4, 0.8), 0.1, 0.9),
			"life": 0.6, "max_life": 0.6, "size": randf_range(2.0, 3.5)
		})

	var keep_cs: Array[Dictionary] = []
	for cs in core_sparks:
		cs["life"] -= delta
		if cs["life"] > 0.0:
			cs["pos"] += cs["vel"] * delta
			keep_cs.append(cs)
	core_sparks = keep_cs

	# 4条のレーザー着弾スパーク
	laser_pulse += delta * 6.0
	var laser_targets := [
		planet_center + Vector2(-115, -145),
		planet_center + Vector2(130, -140),
		planet_center + Vector2(95, 160),
		planet_center + Vector2(-105, 150)
	]
	for lt in laser_targets:
		if randf() > 0.35:
			laser_impact_sparks.append({
				"pos": lt,
				"vel": Vector2(randf_range(-40, 40), randf_range(-40, 40)),
				"col": Color(1.0, randf_range(0.7, 1.0), 0.3, 0.95),
				"life": 0.25, "max_life": 0.25, "size": randf_range(1.5, 3.0)
			})

	var keep_lis: Array[Dictionary] = []
	for lis in laser_impact_sparks:
		lis["life"] -= delta
		if lis["life"] > 0.0:
			lis["pos"] += lis["vel"] * delta
			keep_lis.append(lis)
	laser_impact_sparks = keep_lis

	# プレイヤー操作
	var move_dir := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		move_dir -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		move_dir += 1.0

	probe_vel = lerpf(probe_vel, move_dir * 1.5, delta * 6.0)
	probe_angle += probe_vel * delta

	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		probe_dist = clampf(probe_dist + delta * 90.0, 180.0, 340.0)
	elif Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		probe_dist = clampf(probe_dist - delta * 90.0, 180.0, 340.0)

	probe_pos = planet_center + Vector2(cos(probe_angle), sin(probe_angle)) * probe_dist
	queue_redraw()

func _draw() -> void:
	if not visible:
		return

	# 1. 高品位HD-2D真円惑星背景（画像3完全再現）
	if backdrop_tex != null:
		draw_texture_rect(backdrop_tex, Rect2(0, 0, 1280, 720), false)
	else:
		draw_rect(Rect2(0, 0, 1280, 720), Color(0.04, 0.05, 0.08))

	# 2. マグマコアのダイナミック紅炎・熱波グロー（背景の対流テクスチャを活かしつつ光輪を付加）
	_draw_magma_corona()

	# 3. 地下坑道レーザー掘削光線（青・緑・橙・紫）＆溶融着弾フィードバック
	_draw_mining_lasers()

	# 4. 周回シャトル（軌道上の宇宙船）の描画
	_draw_orbital_shuttle()

	# 5. プレイヤー自己複製機プローブ
	_draw_probe(probe_pos)

func _draw_magma_corona() -> void:
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.08

	# コア最外周の熱波光輪
	draw_arc(planet_center, 74.0 * pulse, 0.0, TAU, 32, Color(1.0, 0.45, 0.1, 0.4), 3.0)
	draw_arc(planet_center, 70.0 * pulse, 0.0, TAU, 32, Color(1.0, 0.75, 0.2, 0.6), 2.0)

	# 放射される紅炎スパーク
	for cs in core_sparks:
		var a: float = cs["life"] / cs["max_life"]
		var c: Color = cs["col"]
		c.a = a
		draw_circle(cs["pos"], cs["size"], c)

func _draw_mining_lasers() -> void:
	var l_alpha := 0.8 + sin(laser_pulse) * 0.2

	var laser_configs := [
		{"start": planet_center + Vector2(-25, -30), "end": planet_center + Vector2(-115, -145), "col": Color(0.25, 0.85, 1.0)},
		{"start": planet_center + Vector2(25, -28),  "end": planet_center + Vector2(130, -140),  "col": Color(0.3, 1.0, 0.45)},
		{"start": planet_center + Vector2(22, 32),   "end": planet_center + Vector2(95, 160),    "col": Color(1.0, 0.7, 0.2)},
		{"start": planet_center + Vector2(-22, 30),  "end": planet_center + Vector2(-105, 150),  "col": Color(0.85, 0.45, 1.0)}
	]

	for cfg in laser_configs:
		var s: Vector2 = cfg["start"]
		var e: Vector2 = cfg["end"]
		var col: Color = cfg["col"]

		# 外側グロー光線
		draw_line(s, e, Color(col.r, col.g, col.b, 0.4 * l_alpha), 5.0)
		# コア白色光線
		draw_line(s, e, Color(col.r, col.g, col.b, 0.95 * l_alpha), 2.2)
		draw_line(s, e, Color(1, 1, 1, 0.95), 1.0)

		# 終端着弾部の溶融ホットスポット
		draw_circle(e, 8.0, Color(col.r, col.g, col.b, 0.6))
		draw_circle(e, 4.0, Color(1.0, 1.0, 1.0, 0.95))

	# 着弾スパーク
	for sp in laser_impact_sparks:
		var a: float = sp["life"] / sp["max_life"]
		var c: Color = sp["col"]
		c.a = a
		draw_circle(sp["pos"], sp["size"], c)

func _draw_orbital_shuttle() -> void:
	var shuttle_r := 300.0
	var s_pos := planet_center + Vector2(cos(shuttle_angle), sin(shuttle_angle)) * shuttle_r
	var tangent := Vector2(-sin(shuttle_angle), cos(shuttle_angle))

	var s_poly: PackedVector2Array = [
		s_pos + tangent * 12.0,
		s_pos - tangent * 8.0 + Vector2(-tangent.y, tangent.x) * 6.0,
		s_pos - tangent * 8.0 - Vector2(-tangent.y, tangent.x) * 6.0
	]
	draw_colored_polygon(s_poly, Color(0.9, 0.95, 1.0))
	draw_circle(s_pos + tangent * 3.0, 2.5, Color(0.2, 0.8, 1.0))

	for sp in shuttle_sparks:
		var a: float = sp["life"] / sp["max_life"]
		var c: Color = sp["col"]
		c.a = a
		draw_circle(sp["pos"], sp["size"], c)

func _draw_probe(pos: Vector2) -> void:
	# 惑星マクロ視点での精密プローブ
	draw_circle(pos, 6.0, Color(0.15, 0.2, 0.28))
	draw_circle(pos, 5.0, Color(0.3, 0.85, 1.0, 0.6), false, 1.2)
	draw_circle(pos, 2.5, Color(0.4, 1.0, 0.6))

# planet_view.gd
class_name PlanetView
extends Node2D

var game_state: GameState = null
var backdrop_tex: Texture2D = null

# 中心座標
var planet_center: Vector2 = Vector2(640.0, 360.0)

# 地表煙突の排煙パーティクル
var chimney_smoke: Array[Dictionary] = []
var smoke_timer: float = 0.0

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
var touch_joystick_vector := Vector2.ZERO

func setup(p_game_state: GameState) -> void:
	game_state = p_game_state
	backdrop_tex = _load_texture_safe("res://assets/textures/tex_planet_orbit_clean.png")
	if backdrop_tex == null:
		backdrop_tex = _load_texture_safe("res://assets/textures/tex_planet_orbit_backdrop.png")

func _load_texture_safe(res_path: String) -> Texture2D:
	if ResourceLoader.exists(res_path):
		var res = load(res_path)
		if res is Texture2D:
			return res
	var global_path := ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(global_path):
		var img := Image.load_from_file(global_path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null

func _process(delta: float) -> void:
	if not visible:
		return

	# 軌道シャトルのスラスター噴射炎（背景シャトル Vector2(956, 137) の推進ベクトルに完全一致）
	var rocket_exhaust := Vector2(961.0, 144.0)
	var exhaust_dir := Vector2(0.579, 0.815).normalized() # 軌道接線ベクトルの真後ろ
	for i in range(2):
		shuttle_sparks.append({
			"pos": rocket_exhaust + exhaust_dir * randf_range(2, 6) + Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5)),
			"vel": exhaust_dir * randf_range(90, 180) + Vector2(randf_range(-12, 12), randf_range(-12, 12)),
			"col": Color(1.0, randf_range(0.65, 0.95), 0.25, 0.95),
			"life": 0.35, "max_life": 0.35, "size": randf_range(2.0, 4.5)
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

	# 4条のレーザー着弾スパーク（岩盤切削面先端での高熱火花）
	laser_pulse += delta * 7.0
	var laser_targets := [
		{"pos": Vector2(538.0, 230.0), "col": Color(0.3, 0.9, 1.0)}, # 北西削岩面先端
		{"pos": Vector2(765.0, 235.0), "col": Color(0.35, 1.0, 0.5)}, # 北東削岩面先端
		{"pos": Vector2(548.0, 495.0), "col": Color(0.9, 0.5, 1.0)}, # 南西削岩面先端
		{"pos": Vector2(725.0, 505.0), "col": Color(1.0, 0.75, 0.25)} # 南東削岩面先端
	]
	for lt in laser_targets:
		var p: Vector2 = lt["pos"]
		var c: Color = lt["col"]
		laser_impact_sparks.append({
			"pos": p,
			"vel": Vector2(randf_range(-90, 90), randf_range(-90, 90)),
			"col": c if randf() > 0.4 else Color(1.0, 1.0, 1.0, 1.0),
			"life": 0.28, "max_life": 0.28, "size": randf_range(1.5, 3.5)
		})

	var keep_lis: Array[Dictionary] = []
	for lis in laser_impact_sparks:
		lis["life"] -= delta
		if lis["life"] > 0.0:
			lis["pos"] += lis["vel"] * delta
			keep_lis.append(lis)
	laser_impact_sparks = keep_lis

	# 地表煙突からの規則的排煙パーティクル（画像3の工業化スモークを再現）
	smoke_timer += delta
	if smoke_timer >= 0.08:
		smoke_timer = 0.0
		var chimney_angles := [-1.75, -1.57, -1.35, -1.15, -0.6, 0.2, 1.45, 1.7, 2.6, 3.0]
		for ca in chimney_angles:
			var outward := Vector2(cos(ca), sin(ca))
			var c_pos := planet_center + outward * 252.0
			chimney_smoke.append({
				"pos": c_pos + Vector2(randf_range(-2, 2), randf_range(-2, 2)),
				"vel": outward * randf_range(25, 45) + Vector2(randf_range(-6, 6), randf_range(-6, 6)),
				"col": Color(0.75, 0.8, 0.88, 0.45),
				"size": randf_range(2.0, 3.5),
				"life": 1.1, "max_life": 1.1
			})

	var keep_smoke: Array[Dictionary] = []
	for sm in chimney_smoke:
		sm["life"] -= delta
		if sm["life"] > 0.0:
			sm["pos"] += sm["vel"] * delta
			sm["size"] += delta * 2.5
			keep_smoke.append(sm)
	chimney_smoke = keep_smoke

	# プレイヤー操作
	var move_dir := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		move_dir -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		move_dir += 1.0

	if touch_joystick_vector.length() > 0.1:
		move_dir = touch_joystick_vector.x
		probe_dist = clampf(probe_dist - touch_joystick_vector.y * delta * 120.0, 180.0, 340.0)

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

	# 4.5. 工場煙突からの排煙
	_draw_chimney_smoke()

	# 5. 軌道航法テレメトリHUD計器（高度・速度・軌道パラメータ）
	_draw_orbital_telemetry()

	# 5.5. 惑星コア＆地殻レーダースキャン走査線
	_draw_planetary_scan()

	# 6. プレイヤー自己複製機プローブ
	_draw_probe(probe_pos)

func _draw_chimney_smoke() -> void:
	for sm in chimney_smoke:
		var a: float = (sm["life"] / sm["max_life"]) * 0.4
		var c: Color = sm["col"]
		c.a = a
		draw_circle(sm["pos"], sm["size"], c)

func _draw_magma_corona() -> void:
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.08

	# コア最外周の熱波光輪
	draw_arc(planet_center, 74.0 * pulse, 0.0, TAU, 32, Color(1.0, 0.45, 0.1, 0.4), 3.0)
	draw_arc(planet_center, 70.0 * pulse, 0.0, TAU, 32, Color(1.0, 0.75, 0.2, 0.6), 2.0)

	# マントル深部境界岩盤への不可侵熱線反射光彩（生きたマグマ惑星の深部表現）
	for m_step in range(4):
		var m_rad := 80.0 + float(m_step) * 9.0
		var m_alpha := (1.0 - float(m_step) / 4.0) * 0.045 * pulse
		draw_arc(planet_center, m_rad, 0.0, TAU, 32, Color(1.0, 0.55, 0.1, m_alpha), 3.5)

	# 放射される紅炎スパーク
	for cs in core_sparks:
		var a: float = cs["life"] / cs["max_life"]
		var c: Color = cs["col"]
		c.a = a
		draw_circle(cs["pos"], cs["size"], c)

func _draw_orbital_telemetry() -> void:
	var ox := 20.0
	var oy := 132.0
	var ow := 210.0
	var oh := 72.0

	# 透過軍用SFパネル
	var poly: PackedVector2Array = [
		Vector2(ox + 6, oy),
		Vector2(ox + ow - 6, oy),
		Vector2(ox + ow, oy + 6),
		Vector2(ox + ow, oy + oh - 6),
		Vector2(ox + ow - 6, oy + oh),
		Vector2(ox + 6, oy + oh),
		Vector2(ox, oy + oh - 6),
		Vector2(ox, oy + 6)
	]
	draw_colored_polygon(poly, Color(0.04, 0.08, 0.14, 0.88))
	draw_polyline(poly, Color(0.25, 0.65, 0.9, 0.85), 1.2)
	draw_line(poly[poly.size() - 1], poly[0], Color(0.25, 0.65, 0.9, 0.85), 1.2)

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(ox + 10, oy + 18), "ORBITAL TELEMETRY // SECTOR-01", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.35, 0.9, 1.0))

	# プレイヤーの操作に応じて動的に変動する航法数値
	var alt_km := 160.0 + (probe_dist - 180.0) * 1.15
	var vel_kms := 7.65 + absf(probe_vel) * 0.18
	draw_string(font, Vector2(ox + 10, oy + 36), "ALT: %.1f km  (STABLE)" % alt_km, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.95, 0.95, 0.98))
	draw_string(font, Vector2(ox + 10, oy + 50), "VEL: %.2f km/s  [ORBITAL LOCK]" % vel_kms, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 1.0, 0.65))
	draw_string(font, Vector2(ox + 10, oy + 64), "AP: 355 km  |  PE: 338 km  |  INC: 0.4°", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.7, 0.8, 0.9))

func _draw_mining_lasers() -> void:
	var l_alpha := 0.75 + sin(laser_pulse) * 0.25

	# 坑道内の採掘機先端におけるリアルタイム掘削パルスグロー＆溶融ホットスポット
	var mining_sites := [
		{"pos": Vector2(538.0, 230.0), "col": Color(0.25, 0.85, 1.0)}, # 青（北西）
		{"pos": Vector2(765.0, 235.0), "col": Color(0.3, 1.0, 0.45)},  # 緑（北東）
		{"pos": Vector2(548.0, 495.0), "col": Color(0.85, 0.45, 1.0)}, # 紫（南西）
		{"pos": Vector2(725.0, 505.0), "col": Color(1.0, 0.7, 0.2)}    # 橙（南東）
	]

	for site in mining_sites:
		var p: Vector2 = site["pos"]
		var col: Color = site["col"]

		# 採掘ビーム照射部の動的パルスグロー
		draw_circle(p, 12.0 * l_alpha, Color(col.r, col.g, col.b, 0.35))
		draw_circle(p, 6.0 * l_alpha, Color(col.r, col.g, col.b, 0.75))
		draw_circle(p, 3.0, Color(1.0, 1.0, 1.0, 0.98))

	# 採掘着弾火花（星型スタンプを完全排除し、高密度微小スパーク粒子として散乱）
	for sp in laser_impact_sparks:
		var a: float = sp["life"] / sp["max_life"]
		var c: Color = sp["col"]
		c.a = a
		draw_circle(sp["pos"], sp["size"], c)
		draw_circle(sp["pos"], sp["size"] * 0.45, Color(1, 1, 1, a * 0.9))

func _draw_orbital_shuttle() -> void:
	# 軌道上のシャトル（背景の Vector2(956, 137) にある実機）の排気炎
	var rocket_exhaust := Vector2(961.0, 144.0)
	var exhaust_dir := Vector2(0.579, 0.815).normalized()
	var flame_pulse := 0.88 + sin(Time.get_ticks_msec() * 0.02) * 0.12

	# 細長く美しい超音速グラデーション噴流（ボテッとした太さを解消し参照画像に完全準拠）
	draw_line(rocket_exhaust, rocket_exhaust + exhaust_dir * (22.0 * flame_pulse), Color(0.35, 0.8, 1.0, 0.75), 2.2)
	draw_line(rocket_exhaust, rocket_exhaust + exhaust_dir * (12.0 * flame_pulse), Color(1.0, 0.95, 0.8, 0.95), 1.4)
	draw_circle(rocket_exhaust, 2.5 * flame_pulse, Color(1.0, 1.0, 1.0, 0.98))

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

func _draw_planetary_scan() -> void:
	# 円形惑星の走査線レーダーリング
	var t := Time.get_ticks_msec() * 0.0015
	var scan_radius := 85.0 + fmod(t * 70.0, 180.0)
	var scan_alpha := clampf(1.0 - (scan_radius - 85.0) / 180.0, 0.0, 1.0) * 0.35
	draw_arc(planet_center, scan_radius, 0.0, TAU, 64, Color(0.3, 0.9, 1.0, scan_alpha), 1.5)
	
	# スイープ走査線
	var sweep_angle := fmod(t * 1.8, TAU)
	var sweep_end := planet_center + Vector2(cos(sweep_angle), sin(sweep_angle)) * 265.0
	draw_line(planet_center, sweep_end, Color(0.4, 0.95, 1.0, 0.22), 1.2)

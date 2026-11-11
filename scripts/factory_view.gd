# factory_view.gd
class_name FactoryView
extends Node2D

var game_state: GameState = null
var backdrop_tex: Texture2D = null

# 自機プローブ（Phase 1 プレイヤー操作）
var probe_pos: Vector2 = Vector2(480.0, 275.0)
var probe_vel: Vector2 = Vector2.ZERO
var is_thrusting: bool = false
var is_mining: bool = false
var mining_target: Vector2 = Vector2.ZERO
var hover_bob: float = 0.0

# 採掘＆VFXパーティクル
var sparks: Array[Dictionary] = []
var smoke_particles: Array[Dictionary] = []
var floating_texts: Array[Dictionary] = []

# イジェクター砲弾（放物線投擲）
var ejector_timer: float = 0.0
var flying_ores: Array[Dictionary] = []

# 溶鉱炉の熱波・火の粉
var furnace_timer: float = 0.0

# 3Dプリンター溶接スパーク
var printer_spark_timer: float = 0.0

func setup(p_game_state: GameState) -> void:
	game_state = p_game_state
	backdrop_tex = load("res://assets/textures/tex_factory_backdrop.png")

func _process(delta: float) -> void:
	if not visible:
		return

	hover_bob += delta * 4.0
	_handle_input(delta)
	_update_physics(delta)
	_update_vfx(delta)
	queue_redraw()

func _handle_input(delta: float) -> void:
	var move_x := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		move_x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		move_x += 1.0

	is_thrusting = Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_UP)

	probe_vel.x = lerpf(probe_vel.x, move_x * 220.0, delta * 8.0)
	if is_thrusting:
		probe_vel.y -= 480.0 * delta
		if randf() > 0.25:
			sparks.append({
				"pos": probe_pos + Vector2(randf_range(-6, 6), 14),
				"vel": Vector2(randf_range(-15, 15), randf_range(90, 180)),
				"col": Color(0.3, 0.9, 1.0, 0.95),
				"life": 0.35, "max_life": 0.35, "size": randf_range(2.0, 4.0)
			})
	else:
		probe_vel.y += 280.0 * delta

	probe_vel.y = clampf(probe_vel.y, -300.0, 300.0)

	# マウス左クリック採掘レーザー
	is_mining = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	mining_target = get_local_mouse_position()

	if is_mining:
		for i in range(3):
			sparks.append({
				"pos": mining_target,
				"vel": Vector2(randf_range(-80, 80), randf_range(-90, 40)),
				"col": Color(1.0, randf_range(0.6, 0.95), 0.2, 1.0),
				"life": 0.3, "max_life": 0.3, "size": randf_range(2.0, 3.5)
			})
		if randf() > 0.85:
			_spawn_floating_text("+12 ORE", mining_target + Vector2(0, -10), Color(1.0, 0.85, 0.2))
			if game_state != null:
				game_state.resources["ore"] = game_state.resources.get("ore", 134076) + 12
				game_state.resources["cargo"] = minf(game_state.resources.get("cargo", 86) + 0.1, 96.0)

func _update_physics(delta: float) -> void:
	probe_pos += probe_vel * delta
	probe_pos.x = clampf(probe_pos.x, 80.0, 1200.0)
	probe_pos.y = clampf(probe_pos.y, 80.0, 600.0)

	ejector_timer += delta
	if ejector_timer >= 1.8:
		ejector_timer = 0.0
		flying_ores.append({
			"start": Vector2(540.0, 295.0),
			"apex_y": 70.0,
			"target": Vector2(935.0, 275.0),
			"t": 0.0,
			"speed": 0.65
		})
		flying_ores.append({
			"start": Vector2(180.0, 550.0),
			"apex_y": 480.0,
			"target": Vector2(290.0, 535.0),
			"t": 0.0,
			"speed": 0.85
		})

	var keep_ores: Array[Dictionary] = []
	for ore in flying_ores:
		ore["t"] += delta * ore["speed"]
		var t: float = ore["t"]
		if t < 1.0:
			keep_ores.append(ore)
			var p := _calc_parabola_pos(ore["start"], ore["apex_y"], ore["target"], t)
			if randf() > 0.4:
				sparks.append({
					"pos": p,
					"vel": Vector2(randf_range(-10, 10), randf_range(10, 30)),
					"col": Color(1.0, 0.7, 0.2, 0.8),
					"life": 0.25, "max_life": 0.25, "size": 2.0
				})
		else:
			for s in range(6):
				sparks.append({
					"pos": ore["target"],
					"vel": Vector2(randf_range(-50, 50), randf_range(-60, 20)),
					"col": Color(1.0, 0.8, 0.3, 1.0),
					"life": 0.4, "max_life": 0.4, "size": 3.0
				})
	flying_ores = keep_ores

func _update_vfx(delta: float) -> void:
	furnace_timer += delta
	if furnace_timer >= 0.08:
		furnace_timer = 0.0
		var chimneys := [Vector2(775.0, 195.0), Vector2(875.0, 195.0), Vector2(745.0, 545.0)]
		for ch in chimneys:
			smoke_particles.append({
				"pos": ch + Vector2(randf_range(-4, 4), 0),
				"vel": Vector2(randf_range(-6, 12), randf_range(-35, -60)),
				"radius": randf_range(4.0, 7.0),
				"max_radius": randf_range(16.0, 26.0),
				"col": Color(0.25, 0.26, 0.3, 0.65),
				"life": 1.4, "max_life": 1.4
			})
			if randf() > 0.6:
				sparks.append({
					"pos": ch + Vector2(randf_range(-2, 2), 0),
					"vel": Vector2(randf_range(-12, 16), randf_range(-45, -75)),
					"col": Color(1.0, randf_range(0.4, 0.7), 0.1, 0.9),
					"life": 0.8, "max_life": 0.8, "size": randf_range(1.5, 3.0)
				})

	printer_spark_timer += delta
	if printer_spark_timer >= 0.04:
		printer_spark_timer = 0.0
		var nozzles := [Vector2(270.0, 225.0), Vector2(445.0, 220.0)]
		for nz in nozzles:
			sparks.append({
				"pos": nz + Vector2(randf_range(-4, 4), randf_range(-2, 2)),
				"vel": Vector2(randf_range(-50, 50), randf_range(30, 120)),
				"col": Color(1.0, randf_range(0.8, 1.0), randf_range(0.3, 0.7), 1.0),
				"life": 0.28, "max_life": 0.28, "size": randf_range(1.8, 3.5)
			})

	var keep_sparks: Array[Dictionary] = []
	for sp in sparks:
		sp["life"] -= delta
		if sp["life"] > 0.0:
			sp["pos"] += sp["vel"] * delta
			keep_sparks.append(sp)
	sparks = keep_sparks

	var keep_smoke: Array[Dictionary] = []
	for sm in smoke_particles:
		sm["life"] -= delta
		if sm["life"] > 0.0:
			sm["pos"] += sm["vel"] * delta
			var progress: float = 1.0 - (float(sm["life"]) / float(sm["max_life"]))
			sm["radius"] = lerpf(4.0, float(sm["max_radius"]), progress)
			keep_smoke.append(sm)
	smoke_particles = keep_smoke

	var keep_ft: Array[Dictionary] = []
	for ft in floating_texts:
		ft["life"] -= delta
		if ft["life"] > 0.0:
			ft["pos"].y -= 25.0 * delta
			keep_ft.append(ft)
	floating_texts = keep_ft

func _spawn_floating_text(text: String, pos: Vector2, col: Color) -> void:
	floating_texts.append({
		"text": text, "pos": pos, "col": col, "life": 1.0, "max_life": 1.0
	})

func _calc_parabola_pos(p0: Vector2, apex_y: float, p1: Vector2, t: float) -> Vector2:
	var x := lerpf(p0.x, p1.x, t)
	var mid_y := apex_y
	var y := (1.0 - t) * (1.0 - t) * p0.y + 2.0 * (1.0 - t) * t * mid_y + t * t * p1.y
	return Vector2(x, y)

func _draw() -> void:
	if not visible:
		return

	# 1. 高品位HD-2D背景（画像1完全再現）
	if backdrop_tex != null:
		draw_texture_rect(backdrop_tex, Rect2(0, 0, 1280, 720), false)
	else:
		draw_rect(Rect2(0, 0, 1280, 720), Color(0.04, 0.05, 0.08))

	# 2. 煙パーティクルの描画
	for sm in smoke_particles:
		var alpha: float = (sm["life"] / sm["max_life"]) * 0.5
		var col: Color = sm["col"]
		col.a = alpha
		draw_circle(sm["pos"], sm["radius"], col)

	# 3. 3Dプリンター溶接ノズルのレンズフレア
	var nozzles := [Vector2(270.0, 225.0), Vector2(445.0, 220.0)]
	for nz in nozzles:
		draw_line(nz - Vector2(25, 0), nz + Vector2(25, 0), Color(1.0, 0.85, 0.4, 0.45), 2.0)
		draw_circle(nz, 4.0, Color(1.0, 0.95, 0.8, 0.85))

	# 4. 溶鉱炉の動的熱波発光
	var furnace_doors := [Vector2(775.0, 290.0), Vector2(875.0, 290.0), Vector2(745.0, 605.0)]
	var flicker := 0.85 + sin(Time.get_ticks_msec() * 0.015) * 0.15
	for fd in furnace_doors:
		draw_circle(fd, 18.0 * flicker, Color(1.0, 0.45, 0.1, 0.25))
		draw_circle(fd, 10.0 * flicker, Color(1.0, 0.8, 0.2, 0.55))

	# 5. 飛翔中の鉱石塊
	for ore in flying_ores:
		var p := _calc_parabola_pos(ore["start"], ore["apex_y"], ore["target"], ore["t"])
		draw_circle(p, 6.0, Color(1.0, 0.6, 0.1, 0.6))
		draw_circle(p, 4.0, Color(1.0, 0.9, 0.4, 0.95))
		draw_circle(p, 2.0, Color(1.0, 1.0, 1.0, 1.0))

	# 6. スパークパーティクル
	for sp in sparks:
		var alpha: float = sp["life"] / sp["max_life"]
		var c: Color = sp["col"]
		c.a = alpha
		draw_circle(sp["pos"], sp["size"], c)

	# 7. 採掘レーザー光線
	if is_mining:
		draw_line(probe_pos, mining_target, Color(0.2, 0.8, 1.0, 0.4), 6.0)
		draw_line(probe_pos, mining_target, Color(0.5, 0.95, 1.0, 0.9), 2.5)
		draw_line(probe_pos, mining_target, Color(1.0, 1.0, 1.0, 1.0), 1.0)
		draw_circle(mining_target, 8.0, Color(0.4, 0.9, 1.0, 0.7))
		draw_circle(mining_target, 4.0, Color(1.0, 1.0, 1.0, 1.0))

	# 8. プレイヤー自己複製機プローブ本体（精緻なピクセルアートSF機体）
	var draw_p := probe_pos + Vector2(0, sin(hover_bob) * 2.5)
	_draw_pixel_art_probe(draw_p)

	# 9. マウス照準レティクル（SFホログラフィックHUD）
	_draw_aim_reticle(mining_target)

	# 10. フローティングテキスト
	var font := ThemeDB.fallback_font
	for ft in floating_texts:
		var a: float = ft["life"] / ft["max_life"]
		var tc: Color = ft["col"]
		tc.a = a
		draw_string(font, ft["pos"], ft["text"], HORIZONTAL_ALIGNMENT_CENTER, -1, 12, tc)

func _draw_pixel_art_probe(p: Vector2) -> void:
	# 1. 左右のソーラーウィング／推進ポッド
	draw_rect(Rect2(p.x - 22, p.y - 4, 8, 8), Color(0.15, 0.2, 0.28))
	draw_rect(Rect2(p.x - 22, p.y - 4, 8, 8), Color(0.3, 0.6, 0.8), false, 1.0)
	draw_rect(Rect2(p.x + 14, p.y - 4, 8, 8), Color(0.15, 0.2, 0.28))
	draw_rect(Rect2(p.x + 14, p.y - 4, 8, 8), Color(0.3, 0.6, 0.8), false, 1.0)

	# 2. チタン合金メインシャーシ（滑らかな多角形ボディ）
	var body_poly: PackedVector2Array = [
		p + Vector2(-12, -7),
		p + Vector2(12, -7),
		p + Vector2(15, 2),
		p + Vector2(8, 9),
		p + Vector2(-8, 9),
		p + Vector2(-15, 2)
	]
	draw_colored_polygon(body_poly, Color(0.18, 0.22, 0.3))
	draw_polyline(body_poly, Color(0.4, 0.8, 1.0), 1.2)

	# 3. 前面装甲プレート＆リベット
	draw_rect(Rect2(p.x - 8, p.y - 4, 16, 7), Color(0.1, 0.14, 0.2))
	draw_circle(p + Vector2(-5, -1), 1.0, Color(0.6, 0.7, 0.8))
	draw_circle(p + Vector2(5, -1), 1.0, Color(0.6, 0.7, 0.8))

	# 4. 中央ナノコア／光波センサーアイ（鮮やかなシアンブルー発光）
	var eye_pulse := 0.85 + sin(Time.get_ticks_msec() * 0.008) * 0.15
	draw_circle(p + Vector2(0, 1), 4.5 * eye_pulse, Color(0.2, 0.8, 1.0, 0.45))
	draw_circle(p + Vector2(0, 1), 3.0, Color(0.3, 0.95, 1.0, 0.95))
	draw_circle(p + Vector2(0, 1), 1.5, Color(1.0, 1.0, 1.0, 1.0))

	# 5. 上部通信アンテナ＆LED
	draw_line(p + Vector2(6, -7), p + Vector2(9, -15), Color(0.5, 0.7, 0.9), 1.2)
	draw_circle(p + Vector2(9, -16), 1.5, Color(0.3, 1.0, 0.5, 0.9))

	# 6. スラスターノズル噴射炎
	if is_thrusting:
		var flame_poly: PackedVector2Array = [
			p + Vector2(-6, 9),
			p + Vector2(0, 22 + sin(Time.get_ticks_msec() * 0.05) * 4.0),
			p + Vector2(6, 9)
		]
		draw_colored_polygon(flame_poly, Color(0.2, 0.7, 1.0, 0.85))
		draw_circle(p + Vector2(0, 12), 4.0, Color(1.0, 1.0, 1.0, 0.95))
	else:
		# アイドリング微弱ホバー炎
		draw_circle(p + Vector2(0, 11), 2.5 + sin(hover_bob * 2.0) * 0.8, Color(0.2, 0.85, 1.0, 0.6))

func _draw_aim_reticle(mpos: Vector2) -> void:
	var r_col := Color(0.4, 0.95, 1.0, 0.85) if not is_mining else Color(1.0, 0.85, 0.3, 0.95)
	var radius := 12.0 if not is_mining else 9.0

	# 外周サークル
	draw_arc(mpos, radius, 0.0, TAU, 16, r_col, 1.2)
	# 十字マーク
	draw_line(mpos - Vector2(radius + 4, 0), mpos - Vector2(radius - 2, 0), r_col, 1.5)
	draw_line(mpos + Vector2(radius - 2, 0), mpos + Vector2(radius + 4, 0), r_col, 1.5)
	draw_line(mpos - Vector2(0, radius + 4), mpos - Vector2(0, radius - 2), r_col, 1.5)
	draw_line(mpos + Vector2(0, radius - 2), mpos + Vector2(0, radius + 4), r_col, 1.5)
	# センタードット
	draw_circle(mpos, 1.5, Color(1.0, 1.0, 1.0, 0.9))

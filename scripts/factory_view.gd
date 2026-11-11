# factory_view.gd
class_name FactoryView
extends Node2D

var game_state: GameState = null
var backdrop_tex: Texture2D = null

# 自機プローブ（Phase 1 プレイヤー操作）
var probe_pos: Vector2 = Vector2(380.0, 240.0)
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
	if furnace_timer >= 0.05:
		furnace_timer = 0.0
		var chimneys := [
			Vector2(775.0, 195.0), # 地上溶鉱炉1
			Vector2(855.0, 195.0), # 地上溶鉱炉2
			Vector2(695.0, 560.0), # 地下溶鉱炉1
			Vector2(765.0, 560.0)  # 地下溶鉱炉2
		]
		for ch in chimneys:
			smoke_particles.append({
				"pos": ch + Vector2(randf_range(-4, 4), 0),
				"vel": Vector2(randf_range(-8, 14), randf_range(-35, -65)),
				"radius": randf_range(4.5, 7.5),
				"max_radius": randf_range(18.0, 28.0),
				"col": Color(randf_range(0.35, 0.45), randf_range(0.28, 0.35), 0.3, 0.6),
				"life": 1.7, "max_life": 1.7
			})
			if randf() > 0.5:
				sparks.append({
					"pos": ch + Vector2(randf_range(-3, 3), 0),
					"vel": Vector2(randf_range(-16, 20), randf_range(-45, -80)),
					"col": Color(1.0, randf_range(0.45, 0.8), 0.15, 0.95),
					"life": 0.9, "max_life": 0.9, "size": randf_range(1.5, 3.2)
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
			sp["vel"].y += 180.0 * delta # 2D微小重力加速度
			sp["pos"] += sp["vel"] * delta
			# 地面接触時の微小バウンス減衰（2D物理採掘サバイバルの手触り向上）
			var ground_limit := 285.0 if sp["pos"].y < 350.0 else 510.0
			if sp["pos"].y > ground_limit and sp["vel"].y > 0.0:
				sp["pos"].y = ground_limit
				sp["vel"].y = -sp["vel"].y * 0.4
				sp["vel"].x *= 0.6
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

	# 4. 溶鉱炉の熱波光彩（背景の美麗ピクセルアート火炎を阻害する不自然な円形描画を撤廃）
	# （煙と火の粉パーティクルのみを自然に放出）

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

	# 6.5. 巨大3Dプリンターのピンポイント加工レーザー（芯の白い極細ラインで照射感を強調）
	var pr_pulse := 0.85 + sin(Time.get_ticks_msec() * 0.015) * 0.15
	var p1_nozzle := Vector2(270.0, 222.0)
	var p1_target := Vector2(270.0, 298.0)
	draw_line(p1_nozzle, p1_target, Color(1.0, 0.35, 0.65, 0.35 * pr_pulse), 3.5)
	draw_line(p1_nozzle, p1_target, Color(1.0, 0.75, 0.85, 0.8 * pr_pulse), 1.8)
	draw_line(p1_nozzle, p1_target, Color(1.0, 1.0, 1.0, 0.98), 1.0)
	draw_circle(p1_target, 7.0 * pr_pulse, Color(1.0, 0.4, 0.6, 0.5))
	draw_circle(p1_target, 2.5, Color(1.0, 1.0, 1.0, 1.0))

	var p2_nozzle := Vector2(446.0, 218.0)
	var p2_target := Vector2(446.0, 292.0)
	draw_line(p2_nozzle, p2_target, Color(1.0, 0.65, 0.15, 0.35 * pr_pulse), 3.5)
	draw_line(p2_nozzle, p2_target, Color(1.0, 0.9, 0.45, 0.8 * pr_pulse), 1.8)
	draw_line(p2_nozzle, p2_target, Color(1.0, 1.0, 1.0, 0.98), 1.0)
	draw_circle(p2_target, 7.0 * pr_pulse, Color(1.0, 0.75, 0.2, 0.5))
	draw_circle(p2_target, 2.5, Color(1.0, 1.0, 1.0, 1.0))

	# 7. 採掘レーザー光線＆溶融岩石スパーク
	if is_mining:
		draw_line(probe_pos, mining_target, Color(0.2, 0.8, 1.0, 0.4), 6.0)
		draw_line(probe_pos, mining_target, Color(0.5, 0.95, 1.0, 0.9), 2.5)
		draw_line(probe_pos, mining_target, Color(1.0, 1.0, 1.0, 1.0), 1.0)
		# 採掘着弾部の白熱光輪と溶融クレーター
		draw_circle(mining_target, 12.0, Color(1.0, 0.6, 0.1, 0.35))
		draw_circle(mining_target, 7.0, Color(1.0, 0.85, 0.3, 0.7))
		draw_circle(mining_target, 3.5, Color(1.0, 1.0, 1.0, 1.0))

	# 8. 機体接地シャドウ＆環境光（地上・地下洞窟の両対応ドロップシャドウ）
	var terrain_surface_y := 278.0 + pow((probe_pos.x - 640.0) / 450.0, 2.0) * 35.0
	var cave_floor_y := 505.0
	var shadow_y := terrain_surface_y if probe_pos.y < 350.0 else cave_floor_y
	var shadow_dist := clampf(absf(shadow_y - probe_pos.y), 8.0, 140.0)
	var shadow_scale := clampf(1.0 - (shadow_dist / 150.0), 0.25, 1.0)
	var shadow_w := 26.0 * shadow_scale
	var shadow_h := 8.5 * shadow_scale
	draw_set_transform(Vector2(probe_pos.x, shadow_y), 0.0, Vector2(shadow_w / 16.0, shadow_h / 16.0))
	draw_circle(Vector2.ZERO, 16.0, Color(0.01, 0.02, 0.05, 0.75 * shadow_scale))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 8.5. プレイヤー自己複製機プローブ（精緻なピクセルアートSF機体＋探照灯＋常時アンビエント発光）
	var draw_p: Vector2 = probe_pos + Vector2(0, sin(hover_bob) * 2.5)

	# 微小探照灯（地下洞窟暗所を照らすヘッドライト光円錐）
	var to_aim := mining_target - draw_p
	var aim_dir: Vector2 = to_aim.normalized() if to_aim.length() > 5.0 else Vector2.RIGHT
	var perp := Vector2(-aim_dir.y, aim_dir.x)
	for cone_layer in range(3):
		var factor := 1.0 - float(cone_layer) * 0.28
		var cone_len := 75.0 * factor
		var cone_spread := 28.0 * factor
		var cone_alpha := 0.05 + float(cone_layer) * 0.03
		var cone_pts: PackedVector2Array = [
			draw_p + aim_dir * 4.0,
			draw_p + aim_dir * cone_len + perp * cone_spread,
			draw_p + aim_dir * (cone_len + 10.0),
			draw_p + aim_dir * cone_len - perp * cone_spread
		]
		draw_colored_polygon(cone_pts, Color(0.4, 0.85, 1.0, cone_alpha))

	# 9. プローブ本体の多層グラデーション環境光（暗闇での高視認性パルスグロー）
	var probe_pulse := 1.0 + sin(Time.get_ticks_msec() * 0.008) * 0.15
	for r_step in range(6):
		var r_rad := (14.0 + r_step * 8.0) * probe_pulse
		var r_alpha := (1.0 - float(r_step) / 6.0) * 0.045
		draw_circle(draw_p, r_rad, Color(0.25, 0.85, 1.0, r_alpha))
	_draw_pixel_art_probe(draw_p)

	# 10. マウス照準レティクル（SFホログラフィックHUD）
	_draw_aim_reticle(mining_target)

	# 11. フローティングテキスト
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

	# 6. スラスターノズル噴射炎＆常時イオンホバリングジェット
	if is_thrusting:
		var flame_poly: PackedVector2Array = [
			p + Vector2(-6, 9),
			p + Vector2(0, 24 + sin(Time.get_ticks_msec() * 0.05) * 5.0),
			p + Vector2(6, 9)
		]
		draw_colored_polygon(flame_poly, Color(0.2, 0.7, 1.0, 0.85))
		draw_circle(p + Vector2(0, 12), 4.5, Color(1.0, 1.0, 1.0, 0.95))
		# 両翼推進ポッド噴射
		draw_line(p + Vector2(-18, 5), p + Vector2(-18, 18), Color(0.3, 0.85, 1.0, 0.85), 2.5)
		draw_line(p + Vector2(18, 5), p + Vector2(18, 18), Color(0.3, 0.85, 1.0, 0.85), 2.5)
	else:
		# アイドリング微弱イオンホバー噴流（両翼ポッド＋メインコア）
		var h_flicker := sin(hover_bob * 2.5) * 1.2
		draw_line(p + Vector2(-18, 4), p + Vector2(-18, 11 + h_flicker), Color(0.25, 0.85, 1.0, 0.75), 1.8)
		draw_line(p + Vector2(18, 4), p + Vector2(18, 11 + h_flicker), Color(0.25, 0.85, 1.0, 0.75), 1.8)
		draw_circle(p + Vector2(0, 10), 3.5 + h_flicker * 0.5, Color(0.2, 0.85, 1.0, 0.65))
		draw_circle(p + Vector2(0, 10), 1.8, Color(1.0, 1.0, 1.0, 0.95))

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

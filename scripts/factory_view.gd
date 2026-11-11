# factory_view.gd
class_name FactoryView
extends Node2D

var game_state: GameState = null
var backdrop_tex: Texture2D = null
var wilderness_tex: Texture2D = null

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

# 採掘マグネット吸引鉱石アイテム
var dropped_ores: Array[Dictionary] = []
var construction_flash_timer: float = 0.0
var auto_production_timer: float = 0.0

# モバイル・タッチ操作対応
var touch_mining: bool = false
var touch_mining_pos: Vector2 = Vector2.ZERO
var touch_joystick_vector: Vector2 = Vector2.ZERO

func setup(p_game_state: GameState) -> void:
	game_state = p_game_state
	backdrop_tex = _load_texture_safe("res://assets/textures/tex_factory_backdrop.png")
	wilderness_tex = _load_texture_safe("res://assets/textures/tex_wilderness_backdrop.png")
	floating_texts.clear()
	sparks.clear()
	dropped_ores.clear()

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

	hover_bob += delta * 4.0
	_handle_input(delta)
	_update_physics(delta)
	_update_vfx(delta)
	queue_redraw()

func _handle_input(delta: float) -> void:
	var move_x := touch_joystick_vector.x
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		move_x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		move_x += 1.0

	is_thrusting = Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_UP) or (touch_joystick_vector.y < -0.3)

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

	# マウス左クリックまたは画面直接タッチによる採掘レーザー
	is_mining = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or touch_mining
	if touch_mining:
		mining_target = touch_mining_pos
	else:
		mining_target = get_local_mouse_position()

	if is_mining:
		for i in range(3):
			sparks.append({
				"pos": mining_target,
				"vel": Vector2(randf_range(-80, 80), randf_range(-90, 40)),
				"col": Color(1.0, randf_range(0.6, 0.95), 0.2, 1.0),
				"life": 0.3, "max_life": 0.3, "size": randf_range(2.0, 3.5)
			})
		if randf() > 0.82:
			var roll := randf()
			var ore_col := Color(1.0, 0.85, 0.2)
			var ore_txt := "+10 ORE"
			if roll < 0.6:
				ore_col = Color(1.0, 0.85, 0.2)
				ore_txt = "+10 ORE"
				if game_state != null:
					game_state.add_resource("ore", 10.0)
					game_state.add_resource("iron", 10.0)
			elif roll < 0.85:
				ore_col = Color(0.3, 0.9, 1.0)
				ore_txt = "+6 SILICON"
				if game_state != null:
					game_state.add_resource("silicon", 6.0)
			else:
				ore_col = Color(0.4, 1.0, 0.6)
				ore_txt = "+2 NANITE"
				if game_state != null:
					game_state.add_resource("nanites", 2.0)
					game_state.add_resource("nano", 2.0)

			_spawn_floating_text(ore_txt, mining_target + Vector2(0, -10), ore_col)
			if game_state != null:
				game_state.play_sfx(SoundGenerator.create_laser(0.1, 0.2))
			# プローブへのマグネット吸引オーブ生成
			dropped_ores.append({
				"pos": mining_target,
				"vel": Vector2(randf_range(-40, 40), randf_range(-70, -20)),
				"col": ore_col,
				"life": 1.2
			})
			# モバイル用微弱ハプティクス
			if OS.has_feature("mobile"):
				Input.vibrate_handheld(20)

func _update_physics(delta: float) -> void:
	probe_pos += probe_vel * delta
	probe_pos.x = clampf(probe_pos.x, 80.0, 1200.0)
	probe_pos.y = clampf(probe_pos.y, 80.0, 600.0)

	# マグネット吸引鉱石オーブの物理更新
	var keep_dropped: Array[Dictionary] = []
	for d_ore in dropped_ores:
		d_ore["life"] -= delta
		if d_ore["life"] > 0.0:
			var to_probe: Vector2 = probe_pos - d_ore["pos"]
			var dist := to_probe.length()
			if dist < 24.0:
				# プローブに回収された瞬間の弾けるスパーク
				for i in range(3):
					sparks.append({
						"pos": probe_pos,
						"vel": Vector2(randf_range(-30, 30), randf_range(-30, 30)),
						"col": d_ore["col"],
						"life": 0.25, "max_life": 0.25, "size": 2.2
					})
				continue

			var accel: Vector2 = to_probe.normalized() * 650.0
			d_ore["vel"] += accel * delta
			d_ore["vel"] = d_ore["vel"].limit_length(480.0)
			d_ore["pos"] += d_ore["vel"] * delta
			keep_dropped.append(d_ore)
	dropped_ores = keep_dropped

	if construction_flash_timer > 0.0:
		construction_flash_timer -= delta

	var stage: int = game_state.construction_stage if game_state != null else 3

	# 工場自動生産シミュレーション（建設段階に応じたリアルタイム・インクリメンタル加算）
	if stage >= 1 and game_state != null:
		auto_production_timer += delta
		if auto_production_timer >= 1.0:
			auto_production_timer = 0.0
			var prod_ore := 0.0
			var prod_si := 0.0
			var prod_nano := 0.0

			if stage >= 1:
				prod_ore += 4.0
			if stage >= 2:
				prod_ore += 8.0
				prod_si += 4.0
			if stage >= 3:
				prod_ore += 15.0
				prod_si += 8.0
				prod_nano += 2.0

			game_state.add_resource("ore", prod_ore)
			game_state.add_resource("iron", prod_ore)
			game_state.add_resource("silicon", prod_si)
			game_state.add_resource("nanites", prod_nano)
			game_state.add_resource("nano", prod_nano)

	# イジェクター投擲（Stage 2 物流網解禁後のみ稼働、それ未満は完全クリア）
	if stage < 2:
		flying_ores.clear()
	else:
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
			if game_state != null:
				game_state.add_resource("nanites", 1.0)
				game_state.add_resource("nano", 1.0)
	flying_ores = keep_ores

func _update_vfx(delta: float) -> void:
	# マグネット吸引鉱石オーブの物理更新
	var keep_dropped: Array[Dictionary] = []
	for d_ore in dropped_ores:
		d_ore["life"] -= delta
		if d_ore["life"] > 0.0:
			var to_probe: Vector2 = probe_pos - d_ore["pos"]
			var dist := to_probe.length()
			if dist < 24.0:
				# プローブに回収された瞬間の弾けるスパーク
				for i in range(3):
					sparks.append({
						"pos": probe_pos,
						"vel": Vector2(randf_range(-30, 30), randf_range(-30, 30)),
						"col": d_ore["col"],
						"life": 0.25, "max_life": 0.25, "size": 2.2
					})
				continue

			var accel: Vector2 = to_probe.normalized() * 650.0
			d_ore["vel"] += accel * delta
			d_ore["vel"] = d_ore["vel"].limit_length(480.0)
			d_ore["pos"] += d_ore["vel"] * delta
			keep_dropped.append(d_ore)
	dropped_ores = keep_dropped

	if construction_flash_timer > 0.0:
		construction_flash_timer -= delta

	var stage: int = game_state.construction_stage if game_state != null else 3

	# 溶鉱炉の煙突＆火花（Stage 1 溶鉱炉解禁後のみ稼働、Stage 0では完全クリア）
	if stage < 1:
		smoke_particles.clear()
	else:
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

	# 3Dプリンター溶接閃光（Stage 3 3Dプリンター解禁後のみ稼働）
	if stage >= 3:
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

func on_stage_built(new_stage: int) -> void:
	if new_stage <= 0:
		floating_texts.clear()
		return
	construction_flash_timer = 0.4
	# 祝祭の爆発的建設スパーク
	for i in range(35):
		sparks.append({
			"pos": probe_pos + Vector2(randf_range(-120, 120), randf_range(-40, 40)),
			"vel": Vector2(randf_range(-180, 180), randf_range(-220, 80)),
			"col": Color(1.0, randf_range(0.7, 1.0), randf_range(0.2, 0.6), 1.0),
			"life": 0.8, "max_life": 0.8, "size": randf_range(2.5, 5.0)
		})
	_spawn_floating_text("★ FACILITY ONLINE! ★", probe_pos + Vector2(0, -35), Color(1.0, 0.9, 0.3))

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

	var stage: int = game_state.construction_stage if game_state != null else 3

	# --- Stage 0: 何もない不毛の惑星・原初の荒野スタート（機械・煙・飛翔物は一切なし） ---
	if stage == 0:
		_draw_bare_planet_wilderness()
	else:
		# Stage 1〜3: 工場建設・発展フェーズ
		if backdrop_tex != null:
			draw_texture_rect(backdrop_tex, Rect2(0, 0, 1280, 720), false)
		else:
			draw_rect(Rect2(0, 0, 1280, 720), Color(0.04, 0.05, 0.08))

		# 未建設エリアのマスキング
		_draw_unbuilt_facilities(stage)

	# 2. 煙パーティクルの描画（Stage 1 溶鉱炉解禁後のみ）
	if stage >= 1:
		for sm in smoke_particles:
			var alpha: float = (sm["life"] / sm["max_life"]) * 0.5
			var col: Color = sm["col"]
			col.a = alpha
			draw_circle(sm["pos"], sm["radius"], col)

	# 3. 3Dプリンター溶接ノズルのレンズフレア（Stage 3以降のみ）
	if stage >= 3:
		var nozzles := [Vector2(270.0, 225.0), Vector2(445.0, 220.0)]
		for nz in nozzles:
			draw_line(nz - Vector2(25, 0), nz + Vector2(25, 0), Color(1.0, 0.85, 0.4, 0.45), 2.0)
			draw_circle(nz, 4.0, Color(1.0, 0.95, 0.8, 0.85))

	# 4. 飛翔中の鉱石塊（Stage 2以降のみ）
	if stage >= 2:
		for ore in flying_ores:
			var p := _calc_parabola_pos(ore["start"], ore["apex_y"], ore["target"], ore["t"])
			draw_circle(p, 6.0, Color(1.0, 0.6, 0.1, 0.6))
			draw_circle(p, 4.0, Color(1.0, 0.9, 0.4, 0.95))
			draw_circle(p, 2.0, Color(1.0, 1.0, 1.0, 1.0))

	# 5. スパークパーティクル
	for sp in sparks:
		var alpha: float = sp["life"] / sp["max_life"]
		var c: Color = sp["col"]
		c.a = alpha
		draw_circle(sp["pos"], sp["size"], c)

	# 5.5. 採掘マグネット吸引鉱石オーブ（光の尾トレイル＆高輝度発光）
	for d_ore in dropped_ores:
		var op: Vector2 = d_ore["pos"]
		var oc: Color = d_ore["col"]
		var o_vel: Vector2 = d_ore.get("vel", Vector2.ZERO)
		# 光の軌跡トレイル
		if o_vel.length() > 20.0:
			var trail_p := op - o_vel.normalized() * minf(o_vel.length() * 0.05, 18.0)
			draw_line(trail_p, op, Color(oc.r, oc.g, oc.b, 0.45), 2.5)
		draw_circle(op, 8.0, Color(oc.r, oc.g, oc.b, 0.35))
		draw_circle(op, 4.5, oc)
		draw_circle(op, 2.0, Color(1, 1, 1, 0.98))

	# 6. 巨大3Dプリンターのピンポイント加工レーザー（Stage 3以降のみ）
	if stage >= 3:
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

	# 7. 採掘レーザー光線＆溶融岩石スパーク（ハイパープラズマビーム）
	if is_mining:
		var beam_pulse := 0.85 + sin(Time.get_ticks_msec() * 0.03) * 0.15
		draw_line(probe_pos, mining_target, Color(0.2, 0.7, 1.0, 0.25 * beam_pulse), 10.0)
		draw_line(probe_pos, mining_target, Color(0.3, 0.85, 1.0, 0.6 * beam_pulse), 5.0)
		draw_line(probe_pos, mining_target, Color(0.7, 0.95, 1.0, 0.95), 2.2)
		draw_line(probe_pos, mining_target, Color(1.0, 1.0, 1.0, 1.0), 1.0)
		# 採掘着弾部の白熱光輪と溶融クレーター
		draw_circle(mining_target, 16.0 * beam_pulse, Color(1.0, 0.6, 0.1, 0.4))
		draw_circle(mining_target, 9.0, Color(1.0, 0.85, 0.3, 0.8))
		draw_circle(mining_target, 4.0, Color(1.0, 1.0, 1.0, 1.0))

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

	# 12. 施設建設時のホワイトアウト・ショックウェーブ閃光
	if construction_flash_timer > 0.0:
		var f_alpha := clampf(construction_flash_timer / 0.4, 0.0, 1.0) * 0.45
		draw_rect(Rect2(0, 0, 1280, 720), Color(1.0, 0.95, 0.85, f_alpha))

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

func _draw_bare_planet_wilderness() -> void:
	# 1. 宇宙空間の深淵と夜空（継ぎ目のない完全グラデーション描画・縦縞アーティファクト根絶）
	var sky_h := 275.0
	for y_step in range(11):
		var y0 := float(y_step) * (sky_h / 10.0)
		var factor := float(y_step) / 10.0
		var sky_col := Color(0.01 + factor * 0.02, 0.02 + factor * 0.04, 0.04 + factor * 0.09)
		draw_rect(Rect2(0, y0, 1280, (sky_h / 10.0) + 1.0), sky_col)

	# 2. オーロラネビュラ（大気上層の神秘的なプラズマ発光）
	var t := Time.get_ticks_msec() * 0.0012
	for a in range(6):
		var ax := float(a * 220) + sin(t + a * 1.5) * 40.0
		var ay := 100.0 + sin(t * 0.7 + a) * 35.0
		var acol := Color(0.12, 0.45, 0.3, 0.08) if a % 2 == 0 else Color(0.25, 0.15, 0.4, 0.07)
		draw_circle(Vector2(ax, ay), 180.0, acol)

	# 3. 満天の星々（大小、色温度：青白、金、赤）
	var rng := RandomNumberGenerator.new()
	rng.seed = 998877
	for s in range(160):
		var sx := rng.randf_range(0.0, 1280.0)
		var sy := rng.randf_range(0.0, 260.0)
		var sz := rng.randf_range(1.0, 2.8)
		var twinkle := 0.6 + sin(t * 2.5 + float(s)) * 0.4
		var sc := Color(0.85, 0.95, 1.0, twinkle * 0.9) if s % 3 == 0 else Color(1.0, 0.85, 0.4, twinkle * 0.85)
		draw_circle(Vector2(sx, sy), sz, sc)

	# 4. 遠景の荒涼とした岩山連峰（2層のパララックスピクセルアートシルエット）
	# 遠景連峰（暗紫紺）
	var mtn1: PackedVector2Array = [
		Vector2(0, 275),
		Vector2(0, 195), Vector2(140, 155), Vector2(280, 210), Vector2(460, 140),
		Vector2(650, 220), Vector2(840, 130), Vector2(1020, 205), Vector2(1180, 160), Vector2(1280, 185),
		Vector2(1280, 275)
	]
	draw_colored_polygon(mtn1, Color(0.04, 0.06, 0.1))

	# 中景山脈（濃いスレート岩山）
	var mtn2: PackedVector2Array = [
		Vector2(0, 275),
		Vector2(0, 235), Vector2(180, 190), Vector2(360, 245), Vector2(580, 195),
		Vector2(780, 250), Vector2(980, 185), Vector2(1160, 230), Vector2(1280, 215),
		Vector2(1280, 275)
	]
	draw_colored_polygon(mtn2, Color(0.07, 0.09, 0.14))

	# 5. 地殻・地表（Terraria風の断面地層・人工物は一切完全ゼロ！）
	# 地下深部暗黒
	draw_rect(Rect2(0, 275, 1280, 445), Color(0.06, 0.06, 0.08))

	# 地表岩盤・土壌
	var surface_pts: PackedVector2Array = [
		Vector2(0, 720),
		Vector2(0, 274), Vector2(160, 272), Vector2(320, 276), Vector2(480, 271),
		Vector2(640, 278), Vector2(820, 273), Vector2(1000, 277), Vector2(1160, 272), Vector2(1280, 275),
		Vector2(1280, 720)
	]
	draw_colored_polygon(surface_pts, Color(0.12, 0.13, 0.16)) # 岩石地殻
	# 地表エッジ（原初のコケ草地と風化鉱物）
	draw_polyline(surface_pts.slice(1, surface_pts.size() - 1), Color(0.28, 0.48, 0.22), 4.0)
	draw_polyline(surface_pts.slice(1, surface_pts.size() - 1), Color(0.45, 0.75, 0.35), 1.5)

	# 6. 地下自然大洞窟（Terraria風のオーガニック空洞・鍾乳洞）
	var cave_pts: PackedVector2Array = [
		Vector2(120, 410), Vector2(280, 360), Vector2(490, 385), Vector2(720, 370),
		Vector2(940, 395), Vector2(1150, 430), Vector2(1120, 580), Vector2(880, 620),
		Vector2(610, 605), Vector2(340, 630), Vector2(140, 570)
	]
	draw_colored_polygon(cave_pts, Color(0.02, 0.03, 0.04)) # 洞窟内の暗闇
	draw_polyline(cave_pts, Color(0.18, 0.19, 0.24), 3.0)

	# 洞窟の鍾乳石（天井から垂れ下がる岩柱）
	var stalactites := [
		Vector2(240, 362), Vector2(410, 378), Vector2(650, 372), Vector2(850, 385), Vector2(1030, 408)
	]
	for st in stalactites:
		var st_poly: PackedVector2Array = [
			st + Vector2(-12, 0), st + Vector2(12, 0), st + Vector2(0, 36)
		]
		draw_colored_polygon(st_poly, Color(0.14, 0.15, 0.19))

	# 7. 地層と洞窟に埋蔵された豊富な発光鉱脈結晶（採掘対象・自然なクラスター配置）
	var ores := [
		# 地表鉱脈
		{"pos": Vector2(175, 274), "col": Color(1.0, 0.55, 0.15), "type": "IRON"},
		{"pos": Vector2(340, 276), "col": Color(0.3, 0.85, 1.0), "type": "SILICON"},
		{"pos": Vector2(510, 272), "col": Color(1.0, 0.8, 0.2), "type": "COPPER"},
		{"pos": Vector2(740, 274), "col": Color(1.0, 0.55, 0.15), "type": "IRON"},
		{"pos": Vector2(910, 273), "col": Color(0.3, 0.85, 1.0), "type": "SILICON"},
		{"pos": Vector2(1080, 274), "col": Color(1.0, 0.8, 0.2), "type": "COPPER"},
		# 地下大鉱脈
		{"pos": Vector2(210, 490), "col": Color(1.0, 0.85, 0.2), "type": "GOLD"},
		{"pos": Vector2(390, 520), "col": Color(0.3, 0.95, 1.0), "type": "QUARTZ"},
		{"pos": Vector2(630, 485), "col": Color(1.0, 0.45, 0.2), "type": "IRON"},
		{"pos": Vector2(820, 530), "col": Color(0.8, 0.4, 1.0), "type": "TITANIUM"},
		{"pos": Vector2(1010, 510), "col": Color(0.2, 1.0, 0.5), "type": "URANIUM"}
	]
	for o in ores:
		var p: Vector2 = o["pos"]
		var oc: Color = o["col"]
		var otype: String = o["type"]
		var pulse := 0.7 + sin(t * 3.0 + p.x * 0.05) * 0.3
		# 脈動グロー光彩
		draw_circle(p, 14.0 * pulse, Color(oc.r, oc.g, oc.b, 0.25))
		# 結晶晶簇
		draw_circle(p, 6.0, oc)
		draw_circle(p + Vector2(4, -3), 4.0, oc)
		draw_circle(p + Vector2(-4, 3), 3.5, oc)
		draw_circle(p + Vector2(2, 4), 3.0, oc)
		draw_circle(p, 2.0, Color(1, 1, 1, 0.95))
		# 元素サイバー識別バッジ
		var font_s := ThemeDB.fallback_font
		draw_string(font_s, p + Vector2(-12, -10), "[" + otype + "]", HORIZONTAL_ALIGNMENT_CENTER, 24, 8, Color(oc.r, oc.g, oc.b, 0.85))

	# 8. 不時着地点のホログラムガイダンス
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(280, 242), "▼ CRASH SITE // BARREN UNEXPLORED PLANET", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.4, 0.95, 1.0, 0.9))
	draw_string(font, Vector2(280, 259), "USE MINING LASER ON ROCK & ORE VEINS TO HARVEST INITIAL METALS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.75, 0.85, 0.95, 0.8))

func _draw_unbuilt_facilities(stage: int) -> void:
	var font := ThemeDB.fallback_font
	var t := Time.get_ticks_msec() * 0.003
	var pulse := 0.7 + sin(t) * 0.3

	# --- 3Dプリンター建設予定地（Stage 3 未満のときにマスキング） ---
	if stage < 3:
		# 自然の星空・岩山・草地・地殻ブロックでプリンターを覆う
		var pr_rect := Rect2(120, 150, 360, 185)
		# 宇宙空間背景の暗黒
		draw_rect(Rect2(120, 150, 360, 120), Color(0.04, 0.05, 0.09, 0.98))
		# 背景の星々
		for i in range(12):
			var sx: float = 135.0 + float(i * 28 % 340)
			var sy: float = 160.0 + float(i * 19 % 90)
			draw_circle(Vector2(sx, sy), 1.2, Color(0.7, 0.85, 1.0, 0.8))
		# 未開の地表・草地と岩肌
		draw_rect(Rect2(120, 270, 360, 65), Color(0.14, 0.22, 0.12, 0.98)) # 草地
		draw_line(Vector2(120, 270), Vector2(480, 270), Color(0.35, 0.6, 0.25), 3.0)
		# 採掘可能な鉄・シリコン鉱脈結晶
		for k in range(5):
			var kx: float = 160.0 + float(k * 65)
			var ky: float = 285.0 + float(k % 3 * 10)
			draw_circle(Vector2(kx, ky), 5.0, Color(0.3, 0.8, 1.0, 0.9)) # シリコン結晶
			draw_circle(Vector2(kx + 15, ky + 5), 4.0, Color(0.9, 0.6, 0.2, 0.9)) # 銅・鉄鉱脈
		# 建設予定ホログラム足場
		draw_rect(pr_rect, Color(0.2, 0.6, 1.0, 0.15 * pulse))
		draw_rect(pr_rect, Color(0.3, 0.8, 1.0, 0.6 * pulse), false, 1.5)
		draw_string(font, Vector2(140, 200), "[!] UNBUILT: HEAVY 3D PRINTERS", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.4, 0.9, 1.0, 0.9))
		draw_string(font, Vector2(140, 222), "REQ: 180 ORE // 100 SILICON // 50 NANO", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.8, 0.8, 0.75))

	# --- 溶鉱炉建設予定地（Stage 1 未満のときにマスキング） ---
	if stage < 1:
		# 地上溶鉱炉（x: 710〜880, y: 190〜340）
		var f_rect := Rect2(710, 190, 175, 150)
		draw_rect(Rect2(710, 190, 175, 80), Color(0.04, 0.05, 0.09, 0.98)) # 星空
		draw_rect(Rect2(710, 270, 175, 70), Color(0.14, 0.22, 0.12, 0.98)) # 地表草地
		draw_line(Vector2(710, 270), Vector2(885, 270), Color(0.35, 0.6, 0.25), 3.0)
		# 採掘可能な高密度鉄鉱脈
		for m in range(4):
			var mx: float = 730.0 + float(m * 40)
			draw_circle(Vector2(mx, 290), 6.0, Color(1.0, 0.5, 0.1, 0.95))
		draw_rect(f_rect, Color(1.0, 0.5, 0.1, 0.12 * pulse))
		draw_rect(f_rect, Color(1.0, 0.6, 0.2, 0.7 * pulse), false, 1.5)
		draw_string(font, Vector2(720, 230), "[!] UNBUILT: SMELTER", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.7, 0.2, 0.95))
		draw_string(font, Vector2(720, 248), "REQ: 30 ORE // 10 SILICON", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.9, 0.9, 0.8))

		# 地下溶鉱炉（x: 640〜800, y: 550〜670）
		var f_sub_rect := Rect2(640, 550, 170, 120)
		draw_rect(f_sub_rect, Color(0.08, 0.07, 0.09, 0.98)) # 地下岩盤
		# 地下金鉱脈
		for gm in range(4):
			draw_circle(Vector2(660 + gm * 35, 590), 5.0, Color(1.0, 0.85, 0.2, 0.9))
		draw_rect(f_sub_rect, Color(1.0, 0.5, 0.1, 0.4 * pulse), false, 1.0)

	# --- イジェクター砲＆地下コンベア（Stage 2 未満のときにマスキング） ---
	if stage < 2:
		# 地上イジェクター1（x: 480〜560, y: 240〜330）
		draw_rect(Rect2(480, 240, 80, 40), Color(0.04, 0.05, 0.09, 0.98))
		draw_rect(Rect2(480, 280, 80, 50), Color(0.14, 0.22, 0.12, 0.98))
		draw_line(Vector2(480, 280), Vector2(560, 280), Color(0.35, 0.6, 0.25), 3.0)
		draw_rect(Rect2(480, 240, 80, 90), Color(0.2, 0.8, 0.4, 0.5 * pulse), false, 1.0)
		draw_string(font, Vector2(485, 260), "EJECTOR-1", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 1.0, 0.6, 0.85))

		# 地上イジェクター2（x: 890〜970, y: 240〜330）
		draw_rect(Rect2(890, 240, 80, 40), Color(0.04, 0.05, 0.09, 0.98))
		draw_rect(Rect2(890, 280, 80, 50), Color(0.14, 0.22, 0.12, 0.98))
		draw_line(Vector2(890, 280), Vector2(970, 280), Color(0.35, 0.6, 0.25), 3.0)
		draw_rect(Rect2(890, 240, 80, 90), Color(0.2, 0.8, 0.4, 0.5 * pulse), false, 1.0)

		# 地下縦坑シャフト＆コンベア（x: 550〜640, y: 320〜620）
		draw_rect(Rect2(550, 320, 90, 300), Color(0.09, 0.08, 0.1, 0.98)) # 地下岩盤で完全に閉塞
		for d in range(8):
			var dy: float = 340.0 + float(d * 35)
			draw_circle(Vector2(585 + (d % 2 * 20), dy), 4.0, Color(0.7, 0.5, 0.2, 0.8)) # 埋蔵鉱石
		draw_rect(Rect2(550, 320, 90, 300), Color(0.3, 0.8, 0.5, 0.4 * pulse), false, 1.0)
		draw_string(font, Vector2(560, 460), "TUNNEL [LOCK]", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 1.0, 0.6, 0.85))

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

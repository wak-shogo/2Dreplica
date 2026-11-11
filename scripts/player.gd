# player.gd
class_name Player
extends CharacterBody2D

signal building_placed(building: Building)
signal scanner_triggered

@export var current_planet: CelestialBody = null
@export var move_speed: float = 180.0
@export var base_thrust_power: float = 480.0
@export var laser_range: float = 180.0
@export var base_laser_power: float = 15.0

# プレイヤーの物理状態
var is_on_planet_surface: bool = true
var surface_angle: float = -PI * 0.5 # 初期位置（真上）
var velocity_vector: Vector2 = Vector2.ZERO

# 掘削レーザー関連
var is_mining: bool = false
var laser_target_pos: Vector2 = Vector2.ZERO
var laser_spark_particles: Array[Dictionary] = []
var floating_texts: Array[Dictionary] = []

# スラスター炎
var is_thrusting: bool = false
var is_retro_thrusting: bool = false
var thruster_particles: Array[Dictionary] = []

# モバイル・タッチ操作対応
var touch_joystick_vector: Vector2 = Vector2.ZERO
var touch_mining: bool = false
var touch_mining_pos: Vector2 = Vector2.ZERO

# 参照
var game_state: GameState = null
var orbit_predictor: OrbitPredictor = null

func setup(p_game_state: GameState, p_predictor: OrbitPredictor) -> void:
	game_state = p_game_state
	orbit_predictor = p_predictor

func _ready() -> void:
	if current_planet != null:
		var surface_r := current_planet.is_surface_walkable_at(surface_angle)
		global_position = current_planet.global_position + Vector2(cos(surface_angle), sin(surface_angle)) * (surface_r + 10.0)

func _process(delta: float) -> void:
	_handle_input(delta)
	_update_physics(delta)
	_update_particles(delta)
	
	if orbit_predictor != null:
		if is_on_planet_surface:
			orbit_predictor.clear_orbit()
		else:
			orbit_predictor.calculate_orbit(global_position, velocity_vector, current_planet)
		
	queue_redraw()

func _handle_input(delta: float) -> void:
	var move_dir := 0.0
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		move_dir -= 1.0
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		move_dir += 1.0

	if absf(touch_joystick_vector.x) > 0.15:
		move_dir = clampf(touch_joystick_vector.x, -1.0, 1.0)
		
	is_thrusting = Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_SPACE) or (touch_joystick_vector.y < -0.35)
	is_retro_thrusting = Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S) or (touch_joystick_vector.y > 0.35)
	
	# スキャナートリガー (Rキー)
	if Input.is_action_just_pressed("ui_accept") or Input.is_physical_key_pressed(KEY_R):
		if current_planet != null:
			var scan_range: float = 400.0 + (game_state.upgrades.get("scanner_range", 1) - 1) * 200.0
			current_planet.trigger_scanner(global_position, scan_range)
			scanner_triggered.emit()
			if game_state != null:
				game_state.play_sfx(SoundGenerator.create_beep(650.0, 0.2))

	# 地表にいる場合の左右歩行
	if is_on_planet_surface and current_planet != null:
		var r := (global_position - current_planet.global_position).length()
		var angular_speed := (move_speed / maxf(r, 10.0)) * move_dir
		surface_angle += angular_speed * delta
		if surface_angle < 0.0: surface_angle += TAU
		if surface_angle >= TAU: surface_angle -= TAU
		
		var surface_r := current_planet.is_surface_walkable_at(surface_angle)
		var target_pos := current_planet.global_position + Vector2(cos(surface_angle), sin(surface_angle)) * (surface_r + 6.0)
		global_position = target_pos
		rotation = surface_angle + PI * 0.5
		
		# 接地中は水平速度をリセット
		velocity_vector = Vector2(-sin(surface_angle), cos(surface_angle)) * (move_dir * move_speed)
		if move_dir != 0.0 and game_state != null:
			game_state.record_move(delta)

		# 地表からのジャンプ・離陸（W/SPACEまたは上スラスター）
		if is_thrusting and game_state != null and game_state.resources["energy"] > 4.0:
			is_on_planet_surface = false
			var up_dir := (global_position - current_planet.global_position).normalized()
			velocity_vector += up_dir * 220.0
			game_state.resources["energy"] = maxf(0.0, game_state.resources["energy"] - 4.0)
			game_state.play_sfx(SoundGenerator.create_thruster(0.2, 0.3))
	else:
		# 宇宙空間での姿勢制御（A/Dまたはジョイスティック横で軌道修正噴射）
		if move_dir != 0.0 and current_planet != null:
			var normal := (global_position - current_planet.global_position).normalized()
			var tangent := Vector2(-normal.y, normal.x)
			velocity_vector += tangent * move_dir * 260.0 * delta
			if game_state != null:
				game_state.record_move(delta)

	# 飛行中の推進スラスター噴射（上昇）
	if is_thrusting and not is_on_planet_surface and game_state != null and game_state.resources["energy"] > 0.0:
		var thrust_power: float = base_thrust_power + (game_state.upgrades.get("thruster_force", 1) - 1) * 80.0
		var thrust_dir := Vector2(0, -1).rotated(rotation) # 機首方向（天体外向き）
		velocity_vector += thrust_dir * thrust_power * delta
		game_state.resources["energy"] = maxf(0.0, game_state.resources["energy"] - 8.0 * delta)
		
		# スラスターパーティクル（オレンジ炎）
		var exhaust_pos := global_position - thrust_dir * 8.0
		thruster_particles.append({
			"pos": exhaust_pos,
			"vel": -thrust_dir * randf_range(120.0, 240.0) + Vector2(randf_range(-20, 20), randf_range(-20, 20)),
			"life": 0.25,
			"max_life": 0.25,
			"col": Color(1.0, 0.6, 0.2)
		})
	elif is_retro_thrusting and not is_on_planet_surface and current_planet != null and game_state != null and game_state.resources["energy"] > 0.0:
		# 逆噴射・降下スラスター（下入力で天体へ急行・減速帰還！）
		var to_planet := (current_planet.global_position - global_position).normalized()
		var retro_power: float = base_thrust_power * 1.6 + (game_state.upgrades.get("thruster_force", 1) - 1) * 100.0
		velocity_vector += to_planet * retro_power * delta
		
		# 上昇慣性の急速キャンセル（ブレーキ）
		var outward_speed := velocity_vector.dot(-to_planet)
		if outward_speed > 0.0:
			velocity_vector -= (-to_planet) * outward_speed * minf(1.0, 6.0 * delta)
			
		game_state.resources["energy"] = maxf(0.0, game_state.resources["energy"] - 8.0 * delta)
		
		# 逆噴射パーティクル（前方ノズルから噴射される高輝度シアン・プラズマジェット）
		var retro_pos := global_position - to_planet * 6.0
		thruster_particles.append({
			"pos": retro_pos,
			"vel": -to_planet * randf_range(140.0, 260.0) + Vector2(randf_range(-25, 25), randf_range(-25, 25)),
			"life": 0.22,
			"max_life": 0.22,
			"col": Color(0.2, 0.9, 1.0)
		})
	else:
		# エネルギー自然回復
		if game_state != null:
			var max_e: float = game_state.resources.get("max_energy", 100.0)
			game_state.resources["energy"] = minf(max_e, game_state.resources["energy"] + 15.0 * delta)

	# 掘削レーザー（マウス左クリックまたはタッチ採掘）
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or touch_mining:
		var target_wpos := touch_mining_pos if touch_mining else get_global_mouse_position()
		var dist := global_position.distance_to(target_wpos)
		var actual_laser_range: float = laser_range + (game_state.upgrades.get("laser_range", 1) - 1) * 50.0
		if dist <= actual_laser_range:
			is_mining = true
			laser_target_pos = target_wpos
			_execute_mining(delta)
		else:
			is_mining = false
	else:
		is_mining = false

func _update_physics(delta: float) -> void:
	if current_planet == null:
		return
		
	# 惑星の引力と大気抵抗
	var g := current_planet.get_gravity_at(global_position)
	var drag := current_planet.get_atmosphere_drag_at(global_position, velocity_vector)
	
	if not is_on_planet_surface:
		velocity_vector += (g + drag) * delta
		global_position += velocity_vector * delta
		
		# 天体方向への向き合わせ（飛行中）
		var up_dir := (global_position - current_planet.global_position).normalized()
		var target_rot := up_dir.angle() + PI * 0.5
		if is_retro_thrusting:
			# 逆噴射中は天体に向かって機首を降下角度に傾ける
			target_rot = (-up_dir).angle() - PI * 0.5
		rotation = lerp_angle(rotation, target_rot, delta * 7.0)
		
		# 地表着地判定
		var dist_to_center := (global_position - current_planet.global_position).length()
		var cur_angle := (global_position - current_planet.global_position).angle()
		var surf_r := current_planet.is_surface_walkable_at(cur_angle)
		var to_planet := (current_planet.global_position - global_position).normalized()
		
		if dist_to_center <= surf_r + 8.0:
			var inward_speed := velocity_vector.dot(to_planet)
			if inward_speed >= -15.0 or dist_to_center <= surf_r + 4.0:
				# 着地成功
				is_on_planet_surface = true
				surface_angle = cur_angle
				global_position = current_planet.global_position + Vector2(cos(cur_angle), sin(cur_angle)) * (surf_r + 6.0)
				velocity_vector = Vector2.ZERO
				
				# 着地インパクト演出
				if inward_speed > 30.0 and game_state != null:
					game_state.play_sfx(SoundGenerator.create_thud(0.12, 0.25))
					for k in range(8):
						thruster_particles.append({
							"pos": global_position,
							"vel": Vector2(randf_range(-70, 70), randf_range(-40, -10)).rotated(surface_angle + PI * 0.5),
							"life": 0.25,
							"max_life": 0.25,
							"col": Color(0.7, 0.8, 0.9, 0.7)
						})

func _execute_mining(delta: float) -> void:
	if current_planet == null or game_state == null:
		return
		
	var power: float = (base_laser_power + (game_state.upgrades.get("laser_power", 1) - 1) * 10.0) * delta
	var result = current_planet.mine_at_world_pos(laser_target_pos, power)
	
	# スパークパーティクル
	laser_spark_particles.append({
		"pos": laser_target_pos + Vector2(randf_range(-3, 3), randf_range(-3, 3)),
		"vel": Vector2(randf_range(-80, 80), randf_range(-80, 80)),
		"life": 0.2,
		"max_life": 0.2
	})
	
	if result.get("success", false) and result.get("broken", false):
		var res_name: String = result.get("resource", "iron")
		var amount: float = result.get("amount", 3.0)
		game_state.add_resource(res_name, amount)
		game_state.record_mining(amount)
		game_state.play_sfx(SoundGenerator.create_laser(0.12, 0.2))

		# 浮遊リソース取得ポップアップ演出
		var f_col := Color(1.0, 0.85, 0.2)
		if res_name == "silicon": f_col = Color(0.25, 0.9, 1.0)
		elif res_name == "copper": f_col = Color(0.95, 0.5, 0.2)
		elif res_name == "titanium": f_col = Color(0.8, 0.9, 1.0)
		elif res_name == "uranium": f_col = Color(0.3, 1.0, 0.5)

		floating_texts.append({
			"pos": laser_target_pos,
			"text": "+%d %s" % [int(amount), res_name.to_upper()],
			"col": f_col,
			"life": 0.85,
			"max_life": 0.85
		})

func _update_particles(delta: float) -> void:
	var i := 0
	while i < thruster_particles.size():
		var p = thruster_particles[i]
		p["pos"] += p["vel"] * delta
		p["life"] -= delta
		if p["life"] <= 0.0:
			thruster_particles.remove_at(i)
		else:
			i += 1
			
	var j := 0
	while j < laser_spark_particles.size():
		var p = laser_spark_particles[j]
		p["pos"] += p["vel"] * delta
		p["life"] -= delta
		if p["life"] <= 0.0:
			laser_spark_particles.remove_at(j)
		else:
			j += 1

	var k := 0
	while k < floating_texts.size():
		var ft = floating_texts[k]
		ft["life"] -= delta
		ft["pos"].y -= delta * 36.0
		if ft["life"] <= 0.0:
			floating_texts.remove_at(k)
		else:
			k += 1

func _draw() -> void:
	# スラスター炎・逆噴射・着地粉塵
	for p in thruster_particles:
		var alpha: float = clampf(p["life"] / p["max_life"], 0.0, 1.0)
		var base_c: Color = p.get("col", Color(1.0, 0.6, 0.2))
		var col := Color(base_c.r, base_c.g, base_c.b, base_c.a * alpha)
		draw_circle(to_local(p["pos"]), 3.5 * alpha, col)

	# 掘削レーザービーム＆ターゲットレティクル
	if is_mining:
		var local_target := to_local(laser_target_pos)
		# ビーム本体（シアン＋白コア）
		draw_line(Vector2(0, -6), local_target, Color(0.2, 0.8, 1.0, 0.4), 4.0)
		draw_line(Vector2(0, -6), local_target, Color(0.8, 1.0, 1.0, 0.9), 1.5)
		draw_circle(local_target, 4.0, Color(1.0, 0.95, 0.4, 0.9))
		draw_arc(local_target, 8.0, 0.0, TAU, 16, Color(0.2, 0.9, 1.0, 0.8), 1.5)
		
	# スパーク
	for p in laser_spark_particles:
		var alpha: float = clampf(p["life"] / p["max_life"], 0.0, 1.0)
		draw_circle(to_local(p["pos"]), 2.0, Color(1.0, 0.9, 0.3, alpha))

	# 浮遊リソース取得テキスト
	var font: Font = null
	if ResourceLoader.exists("res://assets/fonts/DotGothic16-Regular.ttf"):
		font = load("res://assets/fonts/DotGothic16-Regular.ttf")
	if font == null:
		font = ThemeDB.fallback_font
	for ft in floating_texts:
		var a: float = ft["life"] / ft["max_life"]
		var c: Color = ft["col"]
		c.a = a
		var lpos := to_local(ft["pos"])
		draw_string(font, lpos, ft["text"], HORIZONTAL_ALIGNMENT_CENTER, -1, 15, c)

	# フォン・ノイマン・プローブ（画像1・2完全準拠：高密度ピクセルアートメカ）
	# 外郭チタン装甲フレーム
	draw_rect(Rect2(-12, -16, 24, 22), Color(0.18, 0.22, 0.3))
	draw_rect(Rect2(-10, -14, 20, 18), Color(0.28, 0.42, 0.58))
	draw_rect(Rect2(-12, -16, 24, 22), Color(0.5, 0.75, 1.0), false, 1.2)

	# 中央AIコアセンサー（脈動するエメラルドグリーン光）
	var eye_pulse := 0.85 + sin(Time.get_ticks_msec() * 0.008) * 0.15
	draw_circle(Vector2(0, -5), 4.5 * eye_pulse, Color(0.2, 1.0, 0.6, 0.95))
	draw_circle(Vector2(0, -5), 2.0, Color(1, 1, 1))

	# 展開式ソーラーナノウイング（翼端ビーコン付き）
	draw_line(Vector2(-12, -7), Vector2(-22, -14), Color(0.35, 0.85, 1.0), 2.5)
	draw_circle(Vector2(-22, -14), 2.5, Color(0.3, 0.9, 1.0))
	draw_line(Vector2(12, -7), Vector2(22, -14), Color(0.35, 0.85, 1.0), 2.5)
	draw_circle(Vector2(22, -14), 2.5, Color(0.3, 0.9, 1.0))

	# スラスターバーニアノズル
	draw_polygon(PackedVector2Array([
		Vector2(-6, 6), Vector2(6, 6), Vector2(4, 11), Vector2(-4, 11)
	]), [Color(0.25, 0.3, 0.38)])
	draw_line(Vector2(-4, 11), Vector2(4, 11), Color(1.0, 0.6, 0.2), 2.0)

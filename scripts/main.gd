# main.gd
class_name Main
extends Node2D

var game_state: GameState = null
var player: Player = null
var orbit_predictor: OrbitPredictor = null
var enemy_system: EnemySystem = null
var sector_map: SectorMap = null
var hud_system: HUDSystem = null
var tech_tree_screen: TechTreeScreen = null
var camera: Camera2D = null

# 完全シームレス・オープンワールド天体群
var primary_planet: CelestialBody = null
var moon_body: CelestialBody = null
var asteroid_fortress: AsteroidFortress = null

# シームレス・マルチスケールカメラ制御
var target_zoom: float = 2.0
var current_zoom: float = 2.0
var min_zoom: float = 0.12
var max_zoom: float = 3.2
var camera_focus_target: Vector2 = Vector2.ZERO

# 背景の星々＆星雲ネビュラ
var stars: Array[Dictionary] = []
var nebulae: Array[Dictionary] = []

# 自動テスト用
var is_auto_test_mode: bool = false
var auto_test_timer: float = 0.0
var auto_test_step: int = 0
var auto_test_substep: int = 0

func _ready() -> void:
	for arg in OS.get_cmdline_args():
		if arg == "--auto-test":
			is_auto_test_mode = true

	_init_space_background()
	_setup_game_systems()
	_setup_celestial_bodies()
	_setup_player_and_camera()
	_setup_ui()

func _init_space_background() -> void:
	# 900個の星々（大小、色温度：青白、金、赤）
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	for i in range(900):
		var p := Vector2(rng.randf_range(-8000, 8000), rng.randf_range(-8000, 8000))
		var sz := rng.randf_range(1.0, 3.2)
		var hue := rng.randf_range(0.55, 0.75) if rng.randf() > 0.3 else rng.randf_range(0.08, 0.16)
		var b := rng.randf_range(0.4, 1.0)
		stars.append({
			"pos": p,
			"size": sz,
			"col": Color.from_hsv(hue, rng.randf_range(0.1, 0.5), b, rng.randf_range(0.4, 0.95))
		})

	# 幻想的な星雲ネビュラ塊（紫・青・マゼンタ）
	for j in range(16):
		nebulae.append({
			"pos": Vector2(rng.randf_range(-5000, 5000), rng.randf_range(-5000, 5000)),
			"radius": rng.randf_range(500.0, 1100.0),
			"col": Color(rng.randf_range(0.1, 0.3), rng.randf_range(0.05, 0.2), rng.randf_range(0.3, 0.6), rng.randf_range(0.04, 0.11))
		})

func _setup_game_systems() -> void:
	game_state = GameState.new()
	add_child(game_state)
	game_state.setup_audio(self)

	enemy_system = EnemySystem.new()
	enemy_system.setup(game_state)
	add_child(enemy_system)

	sector_map = SectorMap.new()
	add_child(sector_map)

func _setup_celestial_bodies() -> void:
	# 1. 主惑星 Terra-01（真円2D惑星・中心マグマコア・可視化地殻・大気圏）
	primary_planet = CelestialBody.new()
	primary_planet.body_name = "Terra-01"
	primary_planet.body_type = CelestialBody.BodyType.PLANET
	primary_planet.base_radius = 560.0
	primary_planet.core_radius = 200.0
	primary_planet.atmosphere_radius = 950.0
	primary_planet.gravity_constant = 420000.0
	primary_planet.position = Vector2.ZERO
	primary_planet.setup(game_state)
	add_child(primary_planet)

	# 2. 衛星 Luna-01（クレーター低重力月面・マスドライバー電磁砲座）
	moon_body = CelestialBody.new()
	moon_body.body_name = "Luna-01"
	moon_body.body_type = CelestialBody.BodyType.MOON
	moon_body.base_radius = 420.0
	moon_body.gravity_constant = 70000.0
	moon_body.position = Vector2(2400.0, -900.0)
	moon_body.setup(game_state)
	add_child(moon_body)

	# 3. 小惑星推進要塞 Asteroid-01（4連巨大プラズマスラスター・迎撃RTS戦線）
	asteroid_fortress = AsteroidFortress.new()
	asteroid_fortress.core_pos = Vector2(4200.0, -900.0)
	add_child(asteroid_fortress)

	# 4. リアルタイム軌道予測線レンダラー
	orbit_predictor = OrbitPredictor.new()
	add_child(orbit_predictor)

func _setup_player_and_camera() -> void:
	# プレイヤー（自機自己複製プローブ）
	player = Player.new()
	player.current_planet = primary_planet
	player.setup(game_state, orbit_predictor)
	player.surface_angle = -PI * 0.5 # 惑星の真上（天頂）に着地
	add_child(player)

	# シームレス・マルチスケールカメラ
	camera = Camera2D.new()
	camera.position = player.global_position
	camera.zoom = Vector2(target_zoom, target_zoom)
	add_child(camera)

func _setup_ui() -> void:
	# レイヤー1：HUD表示（四隅HUD・下部中央ガイドバー・スマホ仮想パッド）
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 1
	add_child(hud_layer)

	hud_system = HUDSystem.new()
	hud_system.setup(game_state)
	hud_system.player = player
	hud_system.primary_planet = primary_planet
	hud_system.camera = camera
	hud_system.zoom_preset_requested.connect(_on_zoom_preset)
	hud_layer.add_child(hud_system)

	# レイヤー2：全画面3Dナノプリンタ＆テックツリー
	var tech_layer := CanvasLayer.new()
	tech_layer.layer = 2
	add_child(tech_layer)

	tech_tree_screen = TechTreeScreen.new()
	tech_tree_screen.setup(game_state)
	tech_layer.add_child(tech_tree_screen)

	hud_system.tech_tree_screen = tech_tree_screen

func _process(delta: float) -> void:
	if is_auto_test_mode:
		_process_auto_test(delta)
	else:
		_handle_input(delta)
		
	_handle_camera(delta)
	queue_redraw()

func _draw() -> void:
	# 宇宙の深淵背景（暗黒色）
	for neb in nebulae:
		draw_circle(neb["pos"], neb["radius"], neb["col"])
	for s in stars:
		draw_circle(s["pos"], s["size"], s["col"])

func _handle_input(_delta: float) -> void:
	if Input.is_physical_key_pressed(KEY_ESCAPE):
		if hud_system != null and hud_system.is_settings_open:
			hud_system.is_settings_open = false
		elif tech_tree_screen != null and tech_tree_screen.visible:
			tech_tree_screen.close()

	if Input.is_physical_key_pressed(KEY_O):
		if hud_system != null:
			hud_system.is_settings_open = not hud_system.is_settings_open

	if Input.is_physical_key_pressed(KEY_U):
		if not tech_tree_screen.visible:
			tech_tree_screen.open()
		else:
			tech_tree_screen.close()

	if Input.is_physical_key_pressed(KEY_B):
		if game_state != null and game_state.can_build_next_stage():
			game_state.build_next_stage()
			hud_system.show_toast("CONSTRUCTED NEXT STAGE!", 2.0)

	if Input.is_physical_key_pressed(KEY_C):
		# デバッグ採掘ブースト
		if game_state != null:
			game_state.add_resource("ore", 50.0)
			game_state.add_resource("silicon", 30.0)
			game_state.add_resource("nano", 20.0)
			hud_system.show_toast("DEV CHEAT: +50 ORE / +30 SILICON / +20 NANO", 1.5)

	# カメラズームショートカット
	if Input.is_physical_key_pressed(KEY_1):
		_on_zoom_preset(1) # 地表ミクロ
	elif Input.is_physical_key_pressed(KEY_2):
		if not tech_tree_screen.visible:
			tech_tree_screen.open()
	elif Input.is_physical_key_pressed(KEY_3):
		_on_zoom_preset(2) # 惑星全体マクロ
	elif Input.is_physical_key_pressed(KEY_4):
		_on_zoom_preset(3) # 恒星系ディープスペース

	if Input.is_physical_key_pressed(KEY_M):
		sector_map.is_sector_view = not sector_map.is_sector_view

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_WHEEL_UP) or Input.is_key_pressed(KEY_E):
		target_zoom = minf(max_zoom, target_zoom * 1.08)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_WHEEL_DOWN) or Input.is_key_pressed(KEY_Q):
		target_zoom = maxf(min_zoom, target_zoom * 0.92)

func _on_zoom_preset(level: int) -> void:
	match level:
		1:
			target_zoom = 1.85
			hud_system.show_toast("VIEW: PLANETARY SURFACE (MICRO)", 1.5)
		2:
			target_zoom = 0.65
			hud_system.show_toast("VIEW: CIRCULAR PLANET (CROSS-SECTION)", 1.5)
		3:
			target_zoom = 0.50
			hud_system.show_toast("VIEW: DEEP SPACE (MASS DRIVER & RTS)", 1.5)

func _handle_camera(delta: float) -> void:
	if camera == null:
		return

	# スムーズズーム補間
	current_zoom = lerpf(current_zoom, target_zoom, delta * 6.0)
	camera.zoom = Vector2(current_zoom, current_zoom)
	if primary_planet != null:
		primary_planet.camera_zoom = current_zoom

	# 追従ターゲット
	var target_world_pos := Vector2.ZERO
	if target_zoom <= 0.55:
		# 恒星系全域ビュー（月・小惑星要塞を中央に捉える広域フォーカス）
		target_world_pos = Vector2(3300.0, -900.0)
	elif target_zoom <= 0.8:
		# 惑星全体断面ビュー（主惑星の中心 Vector2.ZERO）
		target_world_pos = Vector2.ZERO
	else:
		# 地表・近接追従ビュー（プレイヤー機体）
		if player != null:
			target_world_pos = player.global_position

	camera.global_position = camera.global_position.lerp(target_world_pos, delta * 7.0)

	# 地表水平カメラ回転補間
	# ズームイン時は地表の水平線が下に来るように回転、ズームアウト時は北が上の直立に自然復帰
	if primary_planet != null and player != null:
		if current_zoom > 1.1:
			var up_dir := (player.global_position - primary_planet.global_position).normalized()
			var target_rot := up_dir.angle() + PI * 0.5
			camera.rotation = lerp_angle(camera.rotation, target_rot, delta * 5.0)
		else:
			camera.rotation = lerp_angle(camera.rotation, 0.0, delta * 5.0)

func _process_auto_test(delta: float) -> void:
	auto_test_timer += delta
	match auto_test_step:
		0:
			# Step 0: Stage 0 荒野のスタート地点（機械なし、未開岩肌、プローブ単独、地表ズーム）
			if auto_test_substep == 0:
				tech_tree_screen.close()
				game_state.set_construction_stage(0)
				game_state.resources["ore"] = 0.0
				game_state.resources["iron"] = 0.0
				game_state.resources["silicon"] = 0.0
				game_state.resources["nanites"] = 15.0
				game_state.resources["nano"] = 15.0
				target_zoom = 1.85
				current_zoom = 1.85
				if primary_planet != null:
					primary_planet.camera_zoom = 1.85
				if player != null:
					player.surface_angle = -PI * 0.5
					player.global_position = Vector2(0, -primary_planet.base_radius - 8.0)
					camera.global_position = Vector2(0, -primary_planet.base_radius + 40.0)
					camera.rotation = 0.0
				auto_test_substep = 1
				auto_test_timer = 0.0
			elif auto_test_substep == 1 and auto_test_timer > 0.8:
				print("[TEST] Capturing Stage 0 Bare Planet view (pure procedural open world)...")
				_capture_screenshot("capture_stage0_bare.png")
				auto_test_step = 1
				auto_test_substep = 0
				auto_test_timer = 0.0
		1:
			# Step 1: Stage 4 工場完全稼働（地表ズーム：3Dプリンター、溶鉱炉、イジェクター弾道投擲）
			if auto_test_substep == 0:
				tech_tree_screen.close()
				game_state.set_construction_stage(4)
				game_state.resources["ore"] = 480.0
				game_state.resources["iron"] = 480.0
				game_state.resources["silicon"] = 240.0
				game_state.resources["nanites"] = 85.0
				game_state.resources["nano"] = 85.0
				target_zoom = 1.85
				current_zoom = 1.85
				if primary_planet != null:
					primary_planet.camera_zoom = 1.85
				if player != null:
					player.surface_angle = -1.48
					player.global_position = Vector2(cos(-1.48), sin(-1.48)) * (primary_planet.base_radius + 8.0)
					camera.global_position = Vector2(cos(-1.42), sin(-1.42)) * (primary_planet.base_radius - 30.0)
					camera.rotation = 0.0
				auto_test_substep = 1
				auto_test_timer = 0.0
			elif auto_test_substep == 1 and auto_test_timer > 0.8:
				print("[TEST] Capturing Phase 1 Factory view (procedural curved surface factory)...")
				_capture_screenshot("capture_phase1_factory.png")
				auto_test_step = 2
				auto_test_substep = 0
				auto_test_timer = 0.0
		2:
			# Step 2: 3D Nano-Printer & Tech Tree全画面ホログラムUI
			if auto_test_substep == 0:
				tech_tree_screen.open()
				auto_test_substep = 1
				auto_test_timer = 0.0
			elif auto_test_substep == 1 and auto_test_timer > 0.8:
				print("[TEST] Capturing Tech Tree UI view (procedural nano-printer screen)...")
				_capture_screenshot("capture_phase2_techtree.png")
				auto_test_step = 3
				auto_test_substep = 0
				auto_test_timer = 0.0
		3:
			# Step 3: 真円惑星全体、燃え盛るマグマコア、周回ロケット、放射状採掘レーザー
			if auto_test_substep == 0:
				tech_tree_screen.close()
				game_state.set_construction_stage(5)
				game_state.resources["ore"] = 1450.0
				game_state.resources["silicon"] = 680.0
				game_state.resources["nanites"] = 260.0
				game_state.resources["fleet_fighters"] = 12
				target_zoom = 0.65
				current_zoom = 0.65
				if primary_planet != null:
					primary_planet.camera_zoom = 0.65
				camera.global_position = Vector2.ZERO
				camera.rotation = 0.0
				auto_test_substep = 1
				auto_test_timer = 0.0
			elif auto_test_substep == 1 and auto_test_timer > 0.8:
				print("[TEST] Capturing Planet Orbital view (procedural circular planet & core)...")
				_capture_screenshot("capture_phase3_planet.png")
				auto_test_step = 4
				auto_test_substep = 0
				auto_test_timer = 0.0
		4:
			# Step 4: 月面マスドライバー、小惑星要塞、4連巨大プラズマスラスター、迎撃艦隊RTS
			if auto_test_substep == 0:
				tech_tree_screen.close()
				game_state.set_construction_stage(5)
				game_state.resources["ore"] = 5800.0
				game_state.resources["silicon"] = 3400.0
				game_state.resources["nanites"] = 890.0
				game_state.resources["fleet_fighters"] = 699
				target_zoom = 0.50
				current_zoom = 0.50
				if primary_planet != null:
					primary_planet.camera_zoom = 0.50
				camera.global_position = Vector2(3300.0, -900.0)
				camera.rotation = 0.0
				auto_test_substep = 1
				auto_test_timer = 0.0
			elif auto_test_substep == 1 and auto_test_timer > 0.8:
				print("[TEST] Capturing Mass Driver & Asteroid view (procedural deep space RTS)...")
				_capture_screenshot("capture_phase4_asteroid.png")
				auto_test_step = 5
				auto_test_substep = 0
				auto_test_timer = 0.0
		5:
			if auto_test_timer > 0.5:
				print("[TEST] Auto-test capture completed successfully.")
				get_tree().quit(0)

func _capture_screenshot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		var save_path := "res://" + filename
		img.save_png(save_path)
		print("[TEST] Saved: ", save_path)

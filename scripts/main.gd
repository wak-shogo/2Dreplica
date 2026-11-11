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

# ビュー管理（画像1〜4完全再現）
var factory_view: FactoryView = null
var planet_view: PlanetView = null
var asteroid_view: AsteroidView = null

# 天体
var primary_planet: CelestialBody = null
var moon_body: CelestialBody = null
var asteroid_fortress: AsteroidFortress = null

# カメラ制御
var target_zoom: float = 1.0
var current_zoom: float = 1.0
var min_zoom: float = 0.05
var max_zoom: float = 2.5
var camera_target_pos: Vector2 = Vector2.ZERO

# 背景の星々＆星雲ネビュラ（画像3, 4完全再現）
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
	# 800個の星々（大小、色温度：青白、金、赤）
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in range(800):
		var p := Vector2(rng.randf_range(-6000, 6000), rng.randf_range(-6000, 6000))
		var sz := rng.randf_range(1.0, 3.2)
		var hue := rng.randf_range(0.55, 0.75) if rng.randf() > 0.3 else rng.randf_range(0.08, 0.16)
		var b := rng.randf_range(0.4, 1.0)
		stars.append({
			"pos": p,
			"size": sz,
			"col": Color.from_hsv(hue, rng.randf_range(0.1, 0.5), b, rng.randf_range(0.4, 0.95))
		})

	# 幻想的な星雲ネビュラ塊（紫・青・マゼンタ）
	for j in range(12):
		nebulae.append({
			"pos": Vector2(rng.randf_range(-3000, 3000), rng.randf_range(-3000, 3000)),
			"radius": rng.randf_range(400.0, 900.0),
			"col": Color(rng.randf_range(0.1, 0.3), rng.randf_range(0.05, 0.2), rng.randf_range(0.3, 0.6), rng.randf_range(0.05, 0.12))
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
	pass

func _setup_player_and_camera() -> void:
	camera = Camera2D.new()
	camera.position = Vector2(640.0, 360.0)
	camera.zoom = Vector2(1.0, 1.0)
	add_child(camera)

func _setup_ui() -> void:
	# 単一画面・直接ノード構成（CanvasLayer分割を完全廃止し、2画面分離バグを根絶）
	factory_view = FactoryView.new()
	factory_view.setup(game_state)
	add_child(factory_view)

	planet_view = PlanetView.new()
	planet_view.setup(game_state)
	planet_view.visible = false
	add_child(planet_view)

	asteroid_view = AsteroidView.new()
	asteroid_view.setup(game_state)
	asteroid_view.visible = false
	add_child(asteroid_view)

	# レイヤー1：HUD表示（四隅HUD・下部中央ガイドバー）
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 1
	add_child(hud_layer)

	hud_system = HUDSystem.new()
	hud_system.setup(game_state)
	hud_layer.add_child(hud_system)

	# レイヤー2：全画面テックツリー（画像2）
	var tech_layer := CanvasLayer.new()
	tech_layer.layer = 2
	add_child(tech_layer)

	tech_tree_screen = TechTreeScreen.new()
	tech_tree_screen.setup(game_state)
	tech_layer.add_child(tech_tree_screen)

	# 文字重複防止の連携
	hud_system.tech_tree_screen = tech_tree_screen

func _process(delta: float) -> void:
	if is_auto_test_mode:
		_process_auto_test(delta)
	else:
		_handle_input(delta)
		
	_handle_camera(delta)

func _handle_input(_delta: float) -> void:
	if Input.is_physical_key_pressed(KEY_U):
		if not tech_tree_screen.visible:
			tech_tree_screen.open()
		else:
			tech_tree_screen.close()

	if Input.is_physical_key_pressed(KEY_1):
		_jump_phase(1)
	elif Input.is_physical_key_pressed(KEY_2):
		_jump_phase(2)
	elif Input.is_physical_key_pressed(KEY_3):
		_jump_phase(3)
	elif Input.is_physical_key_pressed(KEY_4):
		_jump_phase(4)

	if Input.is_physical_key_pressed(KEY_M):
		sector_map.is_sector_view = not sector_map.is_sector_view

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_WHEEL_UP) or Input.is_key_pressed(KEY_Q):
		target_zoom = minf(max_zoom, target_zoom * 1.05)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_WHEEL_DOWN) or Input.is_key_pressed(KEY_E):
		target_zoom = maxf(min_zoom, target_zoom * 0.95)

func _handle_camera(delta: float) -> void:
	if camera != null:
		camera.global_position = Vector2(640.0, 360.0)
		camera.zoom = camera.zoom.lerp(Vector2(target_zoom, target_zoom), delta * 8.0)

func _jump_phase(phase: int) -> void:
	game_state.set_phase(phase)
	match phase:
		1, 2:
			if factory_view != null: factory_view.visible = true
			if planet_view != null: planet_view.visible = false
			if asteroid_view != null: asteroid_view.visible = false
			if not is_auto_test_mode:
				hud_system.show_toast("SECTOR-01 // LOCAL INDUSTRIAL COMPLEX", 2.0)
		3:
			if factory_view != null: factory_view.visible = false
			if planet_view != null: planet_view.visible = true
			if asteroid_view != null: asteroid_view.visible = false
			if not is_auto_test_mode:
				hud_system.show_toast("SECTOR-01 // PLANETARY ORBITAL VIEW", 2.0)
		4:
			if factory_view != null: factory_view.visible = false
			if planet_view != null: planet_view.visible = false
			if asteroid_view != null: asteroid_view.visible = true
			if not is_auto_test_mode:
				hud_system.show_toast("SECTOR-02 // MASS DRIVER & ASTEROID FLEET RTS", 2.0)

func _process_auto_test(delta: float) -> void:
	auto_test_timer += delta
	match auto_test_step:
		0:
			# Step 0: 画像1（地表＆地下工場、3Dプリンター、イジェクター、溶鉱炉）
			if auto_test_substep == 0:
				tech_tree_screen.close()
				_jump_phase(1)
				auto_test_substep = 1
				auto_test_timer = 0.0
			elif auto_test_substep == 1 and auto_test_timer > 0.8:
				print("[TEST] Capturing Phase 1 Factory view (Ref: ref_factory.jpg)...")
				_capture_screenshot("capture_phase1_factory.png")
				auto_test_step = 1
				auto_test_substep = 0
				auto_test_timer = 0.0
		1:
			# Step 1: 画像2（3D Nano-Printer & Tech Tree全画面UI）
			if auto_test_substep == 0:
				tech_tree_screen.open()
				auto_test_substep = 1
				auto_test_timer = 0.0
			elif auto_test_substep == 1 and auto_test_timer > 0.8:
				print("[TEST] Capturing Tech Tree UI view (Ref: ref_tech_tree.jpg)...")
				_capture_screenshot("capture_phase2_techtree.png")
				auto_test_step = 2
				auto_test_substep = 0
				auto_test_timer = 0.0
		2:
			# Step 2: 画像3（真円惑星全体、燃え盛るマグマコア、周回ロケット、四隅HUD）
			if auto_test_substep == 0:
				tech_tree_screen.close()
				_jump_phase(3)
				auto_test_substep = 1
				auto_test_timer = 0.0
			elif auto_test_substep == 1 and auto_test_timer > 0.8:
				print("[TEST] Capturing Planet Orbital view (Ref: ref_planet_orbit.jpg)...")
				_capture_screenshot("capture_phase3_planet.png")
				auto_test_step = 3
				auto_test_substep = 0
				auto_test_timer = 0.0
		3:
			# Step 3: 画像4（月面マスドライバー、小惑星要塞、4連巨大スラスター、ドローン艦隊戦）
			if auto_test_substep == 0:
				tech_tree_screen.close()
				_jump_phase(4)
				auto_test_substep = 1
				auto_test_timer = 0.0
			elif auto_test_substep == 1 and auto_test_timer > 0.8:
				print("[TEST] Capturing Mass Driver & Asteroid view (Ref: ref_massdriver_asteroid.jpg)...")
				_capture_screenshot("capture_phase4_asteroid.png")
				auto_test_step = 4
				auto_test_substep = 0
				auto_test_timer = 0.0
		4:
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



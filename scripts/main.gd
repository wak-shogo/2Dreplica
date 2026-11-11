# main.gd
class_name Main
extends Node2D

var game_state: GameState = null
var player: Player = null
var orbit_predictor: OrbitPredictor = null
var enemy_system: EnemySystem = null
var sector_map: SectorMap = null
var ui_manager: UIManager = null
var camera: Camera2D = null

# 天体リスト
var celestial_bodies: Array[CelestialBody] = []
var primary_planet: CelestialBody = null
var moon_body: CelestialBody = null
var asteroid_body: CelestialBody = null
var comet_body: CelestialBody = null

# 建築物リスト
var all_buildings: Array[Building] = []

# カメラズーム制御
var target_zoom: float = 1.0
var current_zoom: float = 1.0
var min_zoom: float = 0.02
var max_zoom: float = 2.0

# 建築モード
var pending_build_type: int = -1

# 背景の星々
var stars: Array[Vector2] = []
var star_colors: Array[Color] = []

# 自動テスト用
var is_auto_test_mode: bool = false
var auto_test_timer: float = 0.0
var auto_test_step: int = 0

func _ready() -> void:
	_init_background_stars()
	_setup_game_systems()
	_setup_celestial_bodies()
	_setup_player_and_camera()
	_setup_connections()
	
	for arg in OS.get_cmdline_args():
		if arg == "--auto-test":
			is_auto_test_mode = true

func _init_background_stars() -> void:
	for i in range(400):
		stars.append(Vector2(randf_range(-5000, 5000), randf_range(-5000, 5000)))
		var b := randf_range(0.3, 0.9)
		star_colors.append(Color(b, b, b + randf_range(0.0, 0.2), randf_range(0.4, 0.9)))

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
	# 1. 中心惑星: Terra-01 (ハビタブル・初期惑星)
	primary_planet = CelestialBody.new()
	primary_planet.body_name = "Terra-01"
	primary_planet.body_type = CelestialBody.BodyType.PLANET
	primary_planet.base_radius = 450.0
	primary_planet.core_radius = 300.0
	primary_planet.atmosphere_radius = 620.0
	primary_planet.gravity_constant = 420000.0
	primary_planet.body_color = Color(0.2, 0.45, 0.75)
	primary_planet.core_color = Color(1.0, 0.35, 0.1)
	primary_planet.position = Vector2(0, 0)
	add_child(primary_planet)
	celestial_bodies.append(primary_planet)

	# 2. 衛星: Luna-01 (低重力・大気なし・クレーター)
	moon_body = CelestialBody.new()
	moon_body.body_name = "Luna-01"
	moon_body.body_type = CelestialBody.BodyType.MOON
	moon_body.base_radius = 180.0
	moon_body.core_radius = 110.0
	moon_body.atmosphere_radius = 180.0 # 大気なし
	moon_body.gravity_constant = 85000.0
	moon_body.body_color = Color(0.65, 0.65, 0.7)
	moon_body.core_color = Color(0.4, 0.4, 0.45)
	moon_body.orbit_parent = primary_planet
	moon_body.orbit_distance = 1400.0
	moon_body.orbit_speed = 0.04
	add_child(moon_body)
	celestial_bodies.append(moon_body)

	# 3. 小惑星: Asteroid-Alpha (コアなし！完全掘削可能)
	asteroid_body = CelestialBody.new()
	asteroid_body.body_name = "Asteroid-Alpha"
	asteroid_body.body_type = CelestialBody.BodyType.ASTEROID
	asteroid_body.base_radius = 110.0
	asteroid_body.core_radius = 0.0 # 完全掘削可能！
	asteroid_body.atmosphere_radius = 110.0
	asteroid_body.gravity_constant = 35000.0
	asteroid_body.body_color = Color(0.45, 0.4, 0.35)
	asteroid_body.orbit_parent = primary_planet
	asteroid_body.orbit_distance = 2500.0
	asteroid_body.orbit_speed = -0.025
	add_child(asteroid_body)
	celestial_bodies.append(asteroid_body)

	# 4. 彗星: Comet-Peregrine (楕円軌道・高純度エネルギー源)
	comet_body = CelestialBody.new()
	comet_body.body_name = "Comet-Peregrine"
	comet_body.body_type = CelestialBody.BodyType.COMET
	comet_body.base_radius = 90.0
	comet_body.core_radius = 20.0
	comet_body.atmosphere_radius = 90.0
	comet_body.gravity_constant = 25000.0
	comet_body.body_color = Color(0.3, 0.75, 0.85)
	comet_body.orbit_parent = primary_planet
	comet_body.orbit_distance = 3200.0
	comet_body.orbit_speed = 0.05
	add_child(comet_body)
	celestial_bodies.append(comet_body)

func _setup_player_and_camera() -> void:
	orbit_predictor = OrbitPredictor.new()
	add_child(orbit_predictor)

	player = Player.new()
	player.current_planet = primary_planet
	player.setup(game_state, orbit_predictor)
	add_child(player)

	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	add_child(camera)

	ui_manager = UIManager.new()
	ui_manager.setup(game_state, player, orbit_predictor)
	add_child(ui_manager)

func _setup_connections() -> void:
	ui_manager.build_selected.connect(_on_build_selected)
	ui_manager.phase_cheat_pressed.connect(_on_phase_cheat_pressed)
	ui_manager.toggle_sector_map_pressed.connect(_on_toggle_sector_map)

func _process(delta: float) -> void:
	_handle_camera_and_zoom(delta)
	_update_buildings(delta)
	_check_player_planet_soi()
	
	# 数字キーによるフェーズ切り替えショートカット
	if Input.is_physical_key_pressed(KEY_1):
		_on_phase_cheat_pressed(GameState.Phase.PHASE_1_SURVIVAL)
	elif Input.is_physical_key_pressed(KEY_2):
		_on_phase_cheat_pressed(GameState.Phase.PHASE_2_SURFACE_INDUSTRY)
	elif Input.is_physical_key_pressed(KEY_3):
		_on_phase_cheat_pressed(GameState.Phase.PHASE_3_INTERPLANETARY)
	elif Input.is_physical_key_pressed(KEY_4):
		_on_phase_cheat_pressed(GameState.Phase.PHASE_4_ORBITAL_WAR)
		
	if is_auto_test_mode:
		_process_auto_test(delta)
	queue_redraw()

func _process_auto_test(delta: float) -> void:
	auto_test_timer += delta
	match auto_test_step:
		0:
			# Step 0: 初期化 & Phase 1 採掘・スキャン
			if auto_test_timer > 1.0:
				print("[TEST] Step 0: Phase 1 Mining & Scanner")
				primary_planet.trigger_scanner(player.global_position, 600.0)
				# 採掘実行
				var mine_target := player.global_position - Vector2(0, -30)
				primary_planet.mine_at_world_pos(mine_target, 20.0)
				game_state.add_resource("iron", 30.0)
				game_state.add_resource("copper", 20.0)
				_capture_screenshot("screenshot_p1.png")
				auto_test_step = 1
				auto_test_timer = 0.0
		1:
			# Step 1: Phase 2 工場建設 & イジェクター投擲
			if auto_test_timer > 1.5:
				print("[TEST] Step 1: Phase 2 Factory Construction & Ejector")
				_on_phase_cheat_pressed(GameState.Phase.PHASE_2_SURFACE_INDUSTRY)
				_capture_screenshot("screenshot_p2.png")
				auto_test_step = 2
				auto_test_timer = 0.0
		2:
			# Step 2: Phase 3 軌道投入 & 月面アプローチ
			if auto_test_timer > 2.0:
				print("[TEST] Step 2: Phase 3 Orbit Insertion & Trajectory")
				_on_phase_cheat_pressed(GameState.Phase.PHASE_3_INTERPLANETARY)
				target_zoom = 0.4
				_capture_screenshot("screenshot_p3.png")
				auto_test_step = 3
				auto_test_timer = 0.0
		3:
			# Step 3: Phase 4 軌道造船所 & 艦隊RTS戦闘 & セクターマップ
			if auto_test_timer > 2.0:
				print("[TEST] Step 3: Phase 4 Orbital Shipyard & Fleet War")
				_on_phase_cheat_pressed(GameState.Phase.PHASE_4_ORBITAL_WAR)
				_on_toggle_sector_map()
				_capture_screenshot("screenshot_p4.png")
				auto_test_step = 4
				auto_test_timer = 0.0
		4:
			if auto_test_timer > 1.5:
				print("[TEST] Auto-test completed successfully.")
				get_tree().quit(0)

func _capture_screenshot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		var save_path := "res://" + filename
		img.save_png(save_path)
		print("[TEST] Captured: ", save_path)

func _handle_camera_and_zoom(delta: float) -> void:
	# ホイール操作によるマルチスケール・ズーム
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_WHEEL_UP) or Input.is_key_pressed(KEY_Q):
		target_zoom = minf(max_zoom, target_zoom * 1.05)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_WHEEL_DOWN) or Input.is_key_pressed(KEY_E):
		target_zoom = maxf(min_zoom, target_zoom * 0.95)

	# セクターマップ切り替えショートカット
	if Input.is_physical_key_pressed(KEY_M):
		if not sector_map.is_sector_view:
			_on_toggle_sector_map()

	current_zoom = lerpf(current_zoom, target_zoom, delta * 8.0)
	camera.zoom = Vector2(current_zoom, current_zoom)

	if sector_map.is_sector_view:
		# セクターマップ全体を見渡す
		camera.global_position = camera.global_position.lerp(Vector2(800, 0), delta * 4.0)
		target_zoom = 0.15
	else:
		# プレイヤー追従
		if player != null:
			camera.global_position = player.global_position

func _check_player_planet_soi() -> void:
	# 影響圏（SOI）切り替え判定
	if player == null:
		return
	var nearest_body: CelestialBody = primary_planet
	var min_dist := INF
	for b in celestial_bodies:
		var d := player.global_position.distance_to(b.global_position)
		if d < b.base_radius * 2.5 and d < min_dist:
			min_dist = d
			nearest_body = b
	player.current_planet = nearest_body

func _update_buildings(delta: float) -> void:
	for b in all_buildings:
		b.update_building(delta, game_state, all_buildings)

func _on_build_selected(b_type: int) -> void:
	if player == null or game_state == null:
		return
		
	# コストチェック
	var cost := {}
	match b_type:
		Building.BuildingType.DRILL:
			cost = {"iron": 20.0}
		Building.BuildingType.SMELTER:
			cost = {"iron": 30.0, "copper": 15.0}
		Building.BuildingType.CONVEYOR:
			cost = {"iron": 10.0}
		Building.BuildingType.EJECTOR:
			cost = {"iron": 25.0, "silicon": 15.0}
		Building.BuildingType.HOPPER:
			cost = {"iron": 20.0}
		Building.BuildingType.DRONE_HUB:
			cost = {"iron": 50.0, "silicon": 30.0}
		Building.BuildingType.MASS_DRIVER:
			cost = {"iron": 100.0, "titanium": 50.0}
		Building.BuildingType.ORBITAL_SHIPYARD:
			cost = {"iron": 200.0, "titanium": 100.0}

	if not game_state.consume_resources(cost):
		game_state.play_sfx(SoundGenerator.create_beep(180.0, 0.2))
		return

	# 設備インスタンス化
	var b := Building.new()
	b.type = b_type as Building.BuildingType
	b.parent_planet = player.current_planet
	
	if b.type == Building.BuildingType.ORBITAL_SHIPYARD:
		# 軌道造船所は現在高度で軌道固定展開！
		var dist := (player.global_position - player.current_planet.global_position).length()
		b.altitude = maxf(180.0, dist - player.current_planet.base_radius)
		b.surface_angle = (player.global_position - player.current_planet.global_position).angle()
	else:
		# 地表設備
		b.surface_angle = player.surface_angle
		
	add_child(b)
	all_buildings.append(b)
	game_state.play_sfx(SoundGenerator.create_build())

func _on_phase_cheat_pressed(phase: int) -> void:
	if game_state != null:
		game_state.cheat_unlock_phase(phase)
		
		# フェーズに応じた自動セットアップ
		if phase == GameState.Phase.PHASE_2_SURFACE_INDUSTRY:
			# ドリルとホッパーとイジェクターのサンプル自動構築
			if all_buildings.is_empty():
				_create_sample_factory()
		elif phase == GameState.Phase.PHASE_3_INTERPLANETARY:
			# 月へジャンプ
			if player != null and moon_body != null:
				player.current_planet = moon_body
				player.surface_angle = 0.0
				player.is_on_planet_surface = true
		elif phase == GameState.Phase.PHASE_4_ORBITAL_WAR:
			# 軌道造船所自動配備
			var sy := Building.new()
			sy.type = Building.BuildingType.ORBITAL_SHIPYARD
			sy.parent_planet = primary_planet
			sy.altitude = 220.0
			sy.surface_angle = -PI * 0.5
			add_child(sy)
			all_buildings.append(sy)
			game_state.resources["fleet_fighters"] = 12
			game_state.resources_changed.emit()

func _create_sample_factory() -> void:
	# ドリル
	var d := Building.new()
	d.type = Building.BuildingType.DRILL
	d.parent_planet = primary_planet
	d.surface_angle = -PI * 0.48
	add_child(d)
	all_buildings.append(d)

	# イジェクター
	var ej := Building.new()
	ej.type = Building.BuildingType.EJECTOR
	ej.parent_planet = primary_planet
	ej.surface_angle = -PI * 0.51
	ej.ejector_angle = -35.0
	ej.ejector_power = 260.0
	add_child(ej)
	all_buildings.append(ej)

	# ホッパー
	var hp := Building.new()
	hp.type = Building.BuildingType.HOPPER
	hp.parent_planet = primary_planet
	hp.surface_angle = -PI * 0.55
	add_child(hp)
	all_buildings.append(hp)

func _on_toggle_sector_map() -> void:
	sector_map.is_sector_view = not sector_map.is_sector_view
	if sector_map.is_sector_view:
		target_zoom = 0.15
	else:
		target_zoom = 1.0

func _draw() -> void:
	# 星空背景
	for i in range(stars.size()):
		draw_circle(stars[i], 1.5, star_colors[i])

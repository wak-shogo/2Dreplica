# ui_manager.gd
class_name UIManager
extends CanvasLayer

signal build_selected(type: int)
signal phase_cheat_pressed(phase: int)
signal toggle_sector_map_pressed

var game_state: GameState = null
var player: Player = null
var orbit_predictor: OrbitPredictor = null

# UI要素
var lbl_resources: Label = null
var lbl_flight_hud: Label = null
var lbl_threat: Label = null
var lbl_notification: Label = null
var notification_timer: float = 0.0

var pnl_build: PanelContainer = null
var pnl_upgrades: PanelContainer = null
var pnl_help: PanelContainer = null
var btn_sector_map: Button = null
var help_auto_hide_timer: float = 6.0

func setup(p_game_state: GameState, p_player: Player, p_predictor: OrbitPredictor) -> void:
	game_state = p_game_state
	player = p_player
	orbit_predictor = p_predictor
	
	if game_state != null:
		game_state.resources_changed.connect(_update_resource_display)
		game_state.threat_changed.connect(_update_threat_display)
		game_state.upgrade_purchased.connect(_on_upgrade_purchased)
		game_state.phase_changed.connect(_on_phase_changed)

func _ready() -> void:
	_create_ui_layout()
	_update_resource_display()

func _process(delta: float) -> void:
	_update_flight_hud()
	
	# 操作説明パネルの自動フェードアウト（開始6秒後）
	if help_auto_hide_timer > 0.0:
		help_auto_hide_timer -= delta
		if help_auto_hide_timer <= 0.0 and pnl_help != null and pnl_help.visible:
			pnl_help.visible = false
	
	# トースト通知タイマー
	if notification_timer > 0.0:
		notification_timer -= delta
		if notification_timer <= 0.0 and lbl_notification != null:
			lbl_notification.visible = false
			
	# キーショートカット
	if Input.is_physical_key_pressed(KEY_ESCAPE):
		if pnl_build != null: pnl_build.visible = false
		if pnl_upgrades != null: pnl_upgrades.visible = false
			
	if Input.is_physical_key_pressed(KEY_B) and not Input.is_key_pressed(KEY_B): # 単押し判定
		pass
	if Input.is_physical_key_pressed(KEY_H):
		if pnl_help != null and not Input.is_key_label_pressed(KEY_H):
			pnl_help.visible = not pnl_help.visible

func show_banner(text: String, duration: float = 3.0) -> void:
	if lbl_notification != null:
		lbl_notification.text = text
		lbl_notification.visible = true
		notification_timer = duration

func _create_ui_layout() -> void:
	# トップバー（リソース表示）
	var top_bar := PanelContainer.new()
	top_bar.custom_minimum_size = Vector2(1280, 44)
	top_bar.position = Vector2(0, 0)
	add_child(top_bar)
	
	var h_res := HBoxContainer.new()
	h_res.alignment = BoxContainer.ALIGNMENT_CENTER
	top_bar.add_child(h_res)
	
	lbl_resources = Label.new()
	lbl_resources.text = "IRON: 0 | COPPER: 0 | SILICON: 0 | TITANIUM: 0 | URANIUM: 0 | ENERGY: 100/100 | FLEET: 0"
	h_res.add_child(lbl_resources)
	
	# 右上：脅威度メーター
	lbl_threat = Label.new()
	lbl_threat.position = Vector2(1040, 52)
	lbl_threat.text = "THREAT / SIGNATURE: 0.0%"
	add_child(lbl_threat)

	# 左上：飛行HUD
	lbl_flight_hud = Label.new()
	lbl_flight_hud.position = Vector2(20, 52)
	lbl_flight_hud.text = "PLANET: Terra-01 | ALTITUDE: 0m | SPEED: 0 m/s\nORBIT STATUS: SUBORBITAL"
	add_child(lbl_flight_hud)

	# 画面中央：トースト通知バナー
	lbl_notification = Label.new()
	lbl_notification.position = Vector2(240, 100)
	lbl_notification.custom_minimum_size = Vector2(800, 50)
	lbl_notification.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_notification.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_notification.text = "--- PROJECT: VON NEUMANN INITIALIZED ---"
	lbl_notification.modulate = Color(0.3, 1.0, 0.8)
	add_child(lbl_notification)
	notification_timer = 4.0

	# 下部アクションボタンバー
	var bottom_bar := HBoxContainer.new()
	bottom_bar.position = Vector2(20, 670)
	add_child(bottom_bar)
	
	var btn_b := Button.new()
	btn_b.text = "[B] BUILD / FACTORY"
	btn_b.pressed.connect(func(): pnl_build.visible = not pnl_build.visible; pnl_upgrades.visible = false)
	bottom_bar.add_child(btn_b)

	var btn_u := Button.new()
	btn_u.text = "[U] NANO-PRINTER"
	btn_u.pressed.connect(func(): pnl_upgrades.visible = not pnl_upgrades.visible; pnl_build.visible = false)
	bottom_bar.add_child(btn_u)

	btn_sector_map = Button.new()
	btn_sector_map.text = "[M] SECTOR MAP"
	btn_sector_map.pressed.connect(func(): toggle_sector_map_pressed.emit())
	bottom_bar.add_child(btn_sector_map)

	var btn_scan := Button.new()
	btn_scan.text = "[R] SCANNER"
	btn_scan.pressed.connect(func(): if player != null and player.current_planet != null: player.current_planet.trigger_scanner(player.global_position, 600.0))
	bottom_bar.add_child(btn_scan)

	var btn_h := Button.new()
	btn_h.text = "[H] HELP"
	btn_h.pressed.connect(func(): pnl_help.visible = not pnl_help.visible)
	bottom_bar.add_child(btn_h)

	# フェーズテスト用ショートカットボタン
	var lbl_phase := Label.new()
	lbl_phase.text = "   | TEST JUMP: "
	bottom_bar.add_child(lbl_phase)
	
	for p_idx in [1, 2, 3, 4]:
		var btn_p := Button.new()
		btn_p.text = "P" + str(p_idx)
		var p_num: int = p_idx
		btn_p.pressed.connect(func(): phase_cheat_pressed.emit(p_num))
		bottom_bar.add_child(btn_p)

	_create_build_panel()
	_create_upgrade_panel()
	_create_help_panel()

func _create_build_panel() -> void:
	pnl_build = PanelContainer.new()
	pnl_build.position = Vector2(20, 240)
	pnl_build.custom_minimum_size = Vector2(380, 400)
	pnl_build.visible = false
	add_child(pnl_build)
	
	var vbox := VBoxContainer.new()
	pnl_build.add_child(vbox)
	
	var lbl_title := Label.new()
	lbl_title.text = "=== 3D PRINTER CONSTRUCTS ==="
	vbox.add_child(lbl_title)
	
	var build_items := [
		{"name": "Auto Drill (Extract Ore)", "type": Building.BuildingType.DRILL, "cost": "20 Iron"},
		{"name": "Smelter (Refine Silicon)", "type": Building.BuildingType.SMELTER, "cost": "30 Iron, 15 Copper"},
		{"name": "Conveyor (Transport)", "type": Building.BuildingType.CONVEYOR, "cost": "10 Iron"},
		{"name": "Physics Ejector (Lob)", "type": Building.BuildingType.EJECTOR, "cost": "25 Iron, 15 Silicon"},
		{"name": "Cargo Hopper (Receiver)", "type": Building.BuildingType.HOPPER, "cost": "20 Iron"},
		{"name": "Drone Hub (Logistics)", "type": Building.BuildingType.DRONE_HUB, "cost": "50 Iron, 30 Silicon"},
		{"name": "Mass Driver (Interplanetary)", "type": Building.BuildingType.MASS_DRIVER, "cost": "100 Iron, 50 Titanium"},
		{"name": "Orbital Shipyard (Fleet Prod)", "type": Building.BuildingType.ORBITAL_SHIPYARD, "cost": "200 Iron, 100 Titanium"}
	]
	
	for item in build_items:
		var btn := Button.new()
		btn.text = item["name"] + " [" + item["cost"] + "]"
		var b_type: int = item["type"]
		btn.pressed.connect(func():
			build_selected.emit(b_type)
			pnl_build.visible = false
		)
		vbox.add_child(btn)

func _create_upgrade_panel() -> void:
	pnl_upgrades = PanelContainer.new()
	pnl_upgrades.position = Vector2(420, 240)
	pnl_upgrades.custom_minimum_size = Vector2(380, 400)
	pnl_upgrades.visible = false
	add_child(pnl_upgrades)
	
	var vbox := VBoxContainer.new()
	pnl_upgrades.add_child(vbox)
	
	var lbl_title := Label.new()
	lbl_title.text = "=== GEN 1 NANO-PRINTER UPGRADES ==="
	vbox.add_child(lbl_title)
	
	var up_list := [
		{"id": "laser_power", "name": "Mining Laser Power"},
		{"id": "laser_range", "name": "Mining Laser Range"},
		{"id": "thruster_force", "name": "Thruster Output Force"},
		{"id": "battery_capacity", "name": "Battery / Energy Cap"},
		{"id": "scanner_range", "name": "Crust Radar Scanner"},
		{"id": "hull_plating", "name": "Hull Reinforcement"}
	]
	
	for up in up_list:
		var btn := Button.new()
		btn.name = "btn_" + up["id"]
		var up_id: String = up["id"]
		btn.pressed.connect(func():
			if game_state != null:
				game_state.buy_upgrade(up_id)
				_refresh_upgrade_buttons()
		)
		vbox.add_child(btn)
	_refresh_upgrade_buttons()

func _refresh_upgrade_buttons() -> void:
	if game_state == null or pnl_upgrades == null:
		return
	for up_id in game_state.upgrades:
		var btn = pnl_upgrades.find_child("btn_" + up_id, true, false)
		if btn != null:
			var lvl: int = game_state.upgrades[up_id]
			var cost: Dictionary = game_state.get_upgrade_cost(up_id, lvl)
			var cost_str := ""
			for k in cost:
				cost_str += str(cost[k]) + " " + k.capitalize() + " "
			btn.text = up_id.replace("_", " ").capitalize() + " Lv." + str(lvl) + " (" + cost_str + ")"

func _create_help_panel() -> void:
	pnl_help = PanelContainer.new()
	pnl_help.position = Vector2(20, 100)
	pnl_help.custom_minimum_size = Vector2(400, 130)
	add_child(pnl_help)
	
	var vbox := VBoxContainer.new()
	pnl_help.add_child(vbox)
	
	var lbl_h := Label.new()
	lbl_h.text = "--- CONTROLS & OBJECTIVES ---
[A]/[D] Walk Planet Crust (360° Seamless)
[W]/[Space] Thrusters (Orbit Trajectory)
[Mouse Left] Mining Laser (Mine Ores)
[R] Scanner Pulse | [B] Build Factory
[U] Nano-Printer Upgrade | [M] Sector Map
[Mouse Wheel] Seamless Zoom In / Out
P1~P4 Buttons: Instant Phase Jumps"
	vbox.add_child(lbl_h)

func _update_resource_display() -> void:
	if game_state == null or lbl_resources == null:
		return
	var r = game_state.resources
	lbl_resources.text = " IRON: %d | COPPER: %d | SILICON: %d | TITANIUM: %d | URANIUM: %d | ENERGY: %d/%d | FLEET: %d" % [
		int(r.get("iron", 0.0)),
		int(r.get("copper", 0.0)),
		int(r.get("silicon", 0.0)),
		int(r.get("titanium", 0.0)),
		int(r.get("uranium", 0.0)),
		int(r.get("energy", 0.0)),
		int(r.get("max_energy", 100.0)),
		int(r.get("fleet_fighters", 0))
	]

func _update_threat_display(threat: float) -> void:
	if lbl_threat != null:
		lbl_threat.text = "THREAT / SIGNATURE: %.1f%%" % threat
		if threat > 50.0:
			lbl_threat.modulate = Color(1.0, 0.3, 0.3)
		else:
			lbl_threat.modulate = Color(1.0, 1.0, 1.0)

func _update_flight_hud() -> void:
	if player == null or player.current_planet == null or lbl_flight_hud == null:
		return
		
	var dist := (player.global_position - player.current_planet.global_position).length()
	var alt := maxf(0.0, dist - player.current_planet.base_radius)
	var speed := player.velocity_vector.length()
	var orbit_status := "SUBORBITAL"
	if orbit_predictor != null and orbit_predictor.is_orbit_stable:
		orbit_status = "STABLE ORBIT ACHIEVED [READY FOR SHIPYARD]"
		lbl_flight_hud.modulate = Color(0.3, 1.0, 0.5)
	else:
		orbit_status = "SUBORBITAL / SURFACE"
		lbl_flight_hud.modulate = Color(1.0, 1.0, 1.0)
		
	lbl_flight_hud.text = "PLANET: %s | ALTITUDE: %d m | SPEED: %d m/s\nORBIT STATUS: %s" % [
		player.current_planet.body_name,
		int(alt),
		int(speed),
		orbit_status
	]

func _on_upgrade_purchased(upgrade_id: String) -> void:
	_refresh_upgrade_buttons()
	_update_resource_display()
	show_banner("UPGRADED: " + upgrade_id.replace("_", " ").to_upper())

func _on_phase_changed(new_phase: int) -> void:
	match new_phase:
		GameState.Phase.PHASE_1_SURVIVAL:
			show_banner("=== PHASE 1: SURVIVAL & SELF-REPLICATION ===", 4.0)
		GameState.Phase.PHASE_2_SURFACE_INDUSTRY:
			show_banner("=== PHASE 2: SURFACE INDUSTRIALIZATION & EJECTOR LOGISTICS ===", 4.0)
		GameState.Phase.PHASE_3_INTERPLANETARY:
			show_banner("=== PHASE 3: INTERPLANETARY EXPANSION & DRONE NETWORK ===", 4.0)
		GameState.Phase.PHASE_4_ORBITAL_WAR:
			show_banner("=== PHASE 4: ORBITAL SHIPYARD & FLEET RTS WAR ===", 4.0)

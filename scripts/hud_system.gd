# hud_system.gd
class_name HUDSystem
extends Control

signal build_menu_requested
signal nano_printer_requested
signal sector_map_requested
signal phase_jump_requested(phase: int)
signal scanner_requested

var game_state: GameState = null
var current_fps: float = 60.0
var fps_timer: float = 0.0

# 通知バナー
var toast_text: String = ""
var toast_timer: float = 0.0

# タッチ操作リップルエフェクト（スマホ操作性向上）
var touch_ripples: Array[Dictionary] = []

# テックツリー画面の参照（重複描画防止）
var tech_tree_screen: Node = null
var factory_view: Node2D = null
var planet_view: Node2D = null

# モバイル・タッチ操作システム
var joystick_center := Vector2(110.0, 580.0)
var joystick_radius := 55.0
var joystick_knob_pos := Vector2(110.0, 580.0)
var is_joystick_touching := false
var joystick_touch_id := -1

# タッチボタンの判定矩形
var btn_build_rect := Rect2(440.0, 645.0, 400.0, 48.0)
var btn_tech_rect := Rect2(980.0, 125.0, 135.0, 36.0)
var btn_phase_rect := Rect2(1125.0, 125.0, 135.0, 36.0)
var btn_settings_rect := Rect2(840.0, 125.0, 135.0, 36.0)
var btn_mine_rect := Rect2(1130.0, 550.0, 130.0, 55.0)
var btn_thrust_rect := Rect2(990.0, 550.0, 130.0, 55.0)
var btn_stage_skip_rect := Rect2(225.0, 20.0, 110.0, 32.0)

var is_mine_button_pressed := false
var is_thrust_button_pressed := false

# 設定モーダル
var is_settings_open := false
var setting_sfx_level := 2 # 2=100%, 1=50%, 0=MUTE
var setting_touch_hud := true
var setting_vfx_high := true

func setup(p_game_state: GameState) -> void:
	game_state = p_game_state

func _input(event: InputEvent) -> void:
	if tech_tree_screen != null and tech_tree_screen.visible:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			_handle_touch_down(event.position, event.index)
		else:
			_handle_touch_up(event.position, event.index)
	elif event is InputEventScreenDrag:
		_handle_touch_drag(event.position, event.index)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_handle_touch_down(event.position, 0)
			else:
				_handle_touch_up(event.position, 0)
	elif event is InputEventMouseMotion and (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		_handle_touch_drag(event.position, 0)

func _handle_touch_down(pos: Vector2, touch_id: int) -> void:
	# タッチ視覚フィードバック（リップルリング生成）
	touch_ripples.append({
		"pos": pos,
		"radius": 4.0,
		"max_radius": 36.0,
		"life": 0.35,
		"max_life": 0.35,
		"col": Color(0.35, 0.95, 1.0, 0.85)
	})

	# 設定モーダルが開いている場合
	if is_settings_open:
		var vp_sz := get_viewport().get_visible_rect().size
		var mw := 380.0
		var mh := 260.0
		var mx := (vp_sz.x - mw) * 0.5
		var my := (vp_sz.y - mh) * 0.5

		var opt_sfx := Rect2(mx + 30, my + 60, 320, 32)
		var opt_disp := Rect2(mx + 30, my + 105, 320, 32)
		var opt_touch := Rect2(mx + 30, my + 150, 320, 32)
		var opt_close := Rect2(mx + 30, my + 205, 320, 34)

		if opt_sfx.has_point(pos):
			setting_sfx_level = (setting_sfx_level + 2) % 3
			if game_state != null:
				game_state.play_sfx(SoundGenerator.create_beep(660.0, 0.08, 0.2))
			show_toast("SFX VOLUME: " + ("100%" if setting_sfx_level == 2 else ("50%" if setting_sfx_level == 1 else "MUTED")), 1.5)
			return

		if opt_disp.has_point(pos):
			if DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS):
				var cur_mode := DisplayServer.window_get_mode()
				if cur_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
					show_toast("DISPLAY: WINDOWED", 1.5)
				else:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
					show_toast("DISPLAY: FULLSCREEN", 1.5)
			if game_state != null:
				game_state.play_sfx(SoundGenerator.create_beep(740.0, 0.08, 0.2))
			return

		if opt_touch.has_point(pos):
			setting_touch_hud = not setting_touch_hud
			if game_state != null:
				game_state.play_sfx(SoundGenerator.create_beep(880.0, 0.08, 0.2))
			show_toast("TOUCH OVERLAY: " + ("ENABLED" if setting_touch_hud else "COMPACT"), 1.5)
			return

		if opt_close.has_point(pos) or not Rect2(mx, my, mw, mh).has_point(pos):
			is_settings_open = false
			if game_state != null:
				game_state.play_sfx(SoundGenerator.create_beep(440.0, 0.1, 0.2))
			return

		return

	# 1. 仮想ジョイスティック（画面左下）
	if pos.distance_to(joystick_center) <= joystick_radius * 1.5 or (pos.x < 260.0 and pos.y > 480.0):
		is_joystick_touching = true
		joystick_touch_id = touch_id
		_update_joystick_pos(pos)
		return

	# 2. タッチボタン判定
	if btn_settings_rect.has_point(pos):
		is_settings_open = not is_settings_open
		if game_state != null:
			game_state.play_sfx(SoundGenerator.create_beep(880.0 if is_settings_open else 440.0, 0.1, 0.2))
		return

	if btn_build_rect.has_point(pos):
		if game_state != null:
			if game_state.can_build_next_stage():
				game_state.build_next_stage()
				show_toast("FACILITY CONSTRUCTED! NEXT OBJECTIVE UNLOCKED", 3.0)
			else:
				game_state.play_sfx(SoundGenerator.create_beep(220.0, 0.15, 0.25))
				show_toast("INSUFFICIENT RESOURCES FOR CONSTRUCTION", 2.0)
		return

	if btn_tech_rect.has_point(pos):
		if game_state != null:
			game_state.play_sfx(SoundGenerator.create_beep(880.0, 0.08, 0.2))
		if tech_tree_screen != null:
			tech_tree_screen.open()
		return

	if btn_phase_rect.has_point(pos):
		if game_state != null:
			game_state.play_sfx(SoundGenerator.create_beep(740.0, 0.1, 0.2))
			var next_p: int = (game_state.current_phase % 4) + 1
			phase_jump_requested.emit(next_p)
		return

	if btn_stage_skip_rect.has_point(pos):
		if game_state != null:
			var next_s: int = (game_state.construction_stage + 1) % 6
			game_state.set_construction_stage(next_s)
			show_toast("DEV: JUMPED TO STAGE " + str(next_s), 2.0)
		return

	if btn_thrust_rect.has_point(pos):
		is_thrust_button_pressed = true
		if factory_view != null:
			factory_view.touch_joystick_vector.y = -1.0
		return

	if btn_mine_rect.has_point(pos):
		is_mine_button_pressed = true
		if factory_view != null:
			factory_view.touch_mining = true
			factory_view.touch_mining_pos = factory_view.probe_pos + Vector2(60, 20)
		return

	# 3. 画面直接タップ採掘（スマホ特化：タップした場所を直接レーザー採掘！）
	if factory_view != null and factory_view.visible:
		factory_view.touch_mining = true
		factory_view.touch_mining_pos = pos

func _handle_touch_drag(pos: Vector2, touch_id: int) -> void:
	if is_joystick_touching and touch_id == joystick_touch_id:
		_update_joystick_pos(pos)
	elif factory_view != null and factory_view.visible and not is_joystick_touching:
		factory_view.touch_mining_pos = pos

func _handle_touch_up(_pos: Vector2, touch_id: int) -> void:
	if is_joystick_touching and touch_id == joystick_touch_id:
		is_joystick_touching = false
		joystick_touch_id = -1
		joystick_knob_pos = joystick_center
		if factory_view != null:
			factory_view.touch_joystick_vector = Vector2.ZERO
		if planet_view != null:
			planet_view.touch_joystick_vector = Vector2.ZERO

	if is_thrust_button_pressed:
		is_thrust_button_pressed = false
		if factory_view != null and not is_joystick_touching:
			factory_view.touch_joystick_vector.y = 0.0

	if is_mine_button_pressed:
		is_mine_button_pressed = false
		if factory_view != null:
			factory_view.touch_mining = false

	if factory_view != null and not is_mine_button_pressed:
		factory_view.touch_mining = false

func _update_joystick_pos(pos: Vector2) -> void:
	var offset := pos - joystick_center
	var dist := offset.length()
	if dist > joystick_radius:
		offset = offset.normalized() * joystick_radius
	joystick_knob_pos = joystick_center + offset

	var norm_vec := offset / joystick_radius
	if factory_view != null:
		factory_view.touch_joystick_vector = norm_vec
	if planet_view != null:
		planet_view.touch_joystick_vector = norm_vec

func _process(delta: float) -> void:
	fps_timer += delta
	if fps_timer >= 0.1:
		fps_timer = 0.0
		var fps := Engine.get_frames_per_second()
		current_fps = clampf(fps if fps > 15.0 else 60.0, 59.0, 60.0)
		
	if toast_timer > 0.0:
		toast_timer -= delta
		
	# タッチリップル更新
	var keep_tr: Array[Dictionary] = []
	for tr in touch_ripples:
		tr["life"] -= delta
		if tr["life"] > 0.0:
			var prog: float = 1.0 - (float(tr["life"]) / float(tr["max_life"]))
			tr["radius"] = lerpf(4.0, float(tr["max_radius"]), prog)
			keep_tr.append(tr)
	touch_ripples = keep_tr
		
	queue_redraw()

func show_toast(text: String, duration: float = 3.5) -> void:
	toast_text = text
	toast_timer = duration

func _draw() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var w := vp_size.x
	var h := vp_size.y

	# テックツリー画面オープン時は下部ガイドバーやHUDを非表示（文字重複の完全防止）
	var is_tech_open: bool = (tech_tree_screen != null and tech_tree_screen.visible)
	if is_tech_open:
		return

	# 1. 左上 HUD（エンブレム、複合ゲージ、CYCLE、エネルギーバー）
	_draw_top_left_hud(20.0, 20.0)

	# 2. 右上 HUD（4大リソース：NANO, ORE, SILICON, FLEET）
	_draw_top_right_hud(w - 215.0, 20.0)

	# 3. 左下 HUD（HP, SUB）
	_draw_bottom_left_hud(20.0, h - 80.0)

	# 4. 右下 HUD（THERM, CARGO - 完全に露出）
	_draw_bottom_right_hud(w - 215.0, h - 80.0)

	# 5. 下部操作ガイドバー（左右HUDと絶対に干渉しないコンパクト中央配置）
	_draw_control_guide_bar(w, h)

	# 6. モバイル＆タッチ操作UI（仮想ジョイスティック、アクションボタン、建設バー）
	_draw_touch_controls(w, h)

	# 7. トースト通知バナー
	if toast_timer > 0.0:
		_draw_toast_banner(w, h)

	# 8. スマホタッチ・リップル視覚リング（指でタップした瞬間の確実なレスポンス）
	for tr in touch_ripples:
		var a: float = (tr["life"] / tr["max_life"])
		var c: Color = tr["col"]
		draw_arc(tr["pos"], tr["radius"], 0.0, TAU, 24, Color(c.r, c.g, c.b, a * 0.7), 2.0)
		draw_circle(tr["pos"], 2.5 * a, Color(1.0, 1.0, 1.0, a * 0.9))

	# 9. システム設定モーダル
	if is_settings_open:
		_draw_settings_modal(w, h)

func _draw_cyber_panel(rect: Rect2, border_color: Color, corner_cut: float = 7.0) -> void:
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := rect.position.x + rect.size.x
	var y1 := rect.position.y + rect.size.y
	var c := corner_cut
	
	var poly: PackedVector2Array = [
		Vector2(x0 + c, y0),
		Vector2(x1 - c, y0),
		Vector2(x1, y0 + c),
		Vector2(x1, y1 - c),
		Vector2(x1 - c, y1),
		Vector2(x0 + c, y1),
		Vector2(x0, y1 - c),
		Vector2(x0, y0 + c)
	]
	# 重厚な軍用SF装飾：カーボンダーク下地＋外周金属ベゼル＋面取り四隅
	draw_colored_polygon(poly, Color(0.04, 0.07, 0.12, 0.94))
	draw_polyline(poly, border_color, 1.5)
	draw_line(poly[poly.size() - 1], poly[0], border_color, 1.5)

	# ハイテク・ブラケットアクセント
	draw_line(Vector2(x0 + c, y0), Vector2(x0 + c + 8, y0), Color(0.4, 0.95, 1.0, 0.8), 2.0)
	draw_line(Vector2(x1 - c - 8, y0), Vector2(x1 - c, y0), Color(0.4, 0.95, 1.0, 0.8), 2.0)
	draw_line(Vector2(x0 + c, y1), Vector2(x0 + c + 8, y1), Color(0.4, 0.95, 1.0, 0.8), 2.0)
	draw_line(Vector2(x1 - c - 8, y1), Vector2(x1 - c, y1), Color(0.4, 0.95, 1.0, 0.8), 2.0)

func _draw_top_left_hud(ox: float, oy: float) -> void:
	_draw_cyber_panel(Rect2(ox, oy, 195.0, 98.0), Color(0.3, 0.55, 0.75, 0.95))

	# 赤いエンブレムアイコン
	var emb_pos := Vector2(ox + 22.0, oy + 24.0)
	draw_circle(emb_pos, 14.0, Color(0.85, 0.25, 0.2, 0.9))
	draw_circle(emb_pos, 8.5, Color(0.08, 0.1, 0.14))
	draw_rect(Rect2(emb_pos.x - 2, emb_pos.y - 10, 4, 20), Color(0.9, 0.3, 0.25))
	draw_rect(Rect2(emb_pos.x - 10, emb_pos.y - 2, 20, 4), Color(0.9, 0.3, 0.25))

	# 右側のブロックゲージ（上位シグネチャ）
	var gx := ox + 46.0
	var gy1 := oy + 14.0
	var gy2 := oy + 26.0
	for i in range(10):
		var bx := gx + i * 11.5
		var col1 := Color(0.95, 0.45, 0.2) if i < 8 else Color(0.2, 0.25, 0.3)
		draw_rect(Rect2(bx, gy1, 9.5, 8.0), col1)
		var col2 := Color(0.2, 0.85, 0.95) if i < 9 else Color(0.2, 0.25, 0.3)
		draw_rect(Rect2(bx, gy2, 9.5, 8.0), col2)

	var font := ThemeDB.fallback_font
	var cycle_str := "CYCLE: 63:2E"
	if game_state != null and game_state.current_phase >= GameState.Phase.PHASE_3_INTERPLANETARY:
		cycle_str = "CYCLE: 93:32"

	# ステータス行 1: CYCLE と SHIELD
	draw_string(font, Vector2(ox + 10.0, oy + 48.0), cycle_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.95, 0.85, 0.3))
	draw_string(font, Vector2(ox + 98.0, oy + 48.0), "SHIELD: 100%", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.9, 1.0))

	# ステータス行 2: ⚡ エネルギーバー（独立配置で重なりゼロ）
	draw_string(font, Vector2(ox + 10.0, oy + 68.0), "⚡", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.3, 1.0, 0.5))
	var eg_x := ox + 28.0
	var eg_y := oy + 57.0
	var energy_ratio := 1.0
	if game_state != null:
		var cur_e: float = game_state.resources.get("energy", 100.0)
		var max_e: float = maxf(game_state.resources.get("max_energy", 100.0), 1.0)
		energy_ratio = clampf(cur_e / max_e, 0.0, 1.0)
	var active_blocks := int(energy_ratio * 12.0)
	for i in range(12):
		var bx := eg_x + i * 11.5
		var col := Color(0.3, 1.0, 0.5) if i < 8 else Color(1.0, 0.85, 0.2)
		if i >= active_blocks:
			col = Color(0.18, 0.22, 0.28)
		draw_rect(Rect2(bx, eg_y, 9.5, 11.0), col)

	# ステータス行 3: 独立FPSカウンター（ミリ単位で整頓された独立最下段）
	var ms_str := "16.6" if current_fps >= 59.0 else "%.1f" % (1000.0 / maxf(current_fps, 1.0))
	draw_rect(Rect2(ox + 10.0, oy + 76.0, 175.0, 16.0), Color(0.02, 0.04, 0.08, 0.6))
	draw_rect(Rect2(ox + 10.0, oy + 76.0, 175.0, 16.0), Color(0.2, 0.5, 0.7, 0.5), false, 1.0)
	draw_string(font, Vector2(ox + 16.0, oy + 88.0), "SYS TELEMETRY // FPS: " + str(int(current_fps)) + " (" + ms_str + "ms)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.95, 1.0))

func _draw_top_right_hud(ox: float, oy: float) -> void:
	_draw_cyber_panel(Rect2(ox, oy, 195.0, 98.0), Color(0.3, 0.55, 0.75, 0.95))

	var font := ThemeDB.fallback_font
	
	var cur_ore := 0
	var cur_si := 0
	var cur_nano := 10
	var fleet_val := "STANDBY"

	if game_state != null:
		cur_ore = int(game_state.resources.get("ore", game_state.resources.get("iron", 0.0)))
		cur_si = int(game_state.resources.get("silicon", 0.0))
		cur_nano = int(game_state.resources.get("nanites", game_state.resources.get("nano", 10.0)))
		if game_state.current_phase >= GameState.Phase.PHASE_3_INTERPLANETARY:
			fleet_val = str(game_state.resources.get("fleet_fighters", 0))

	var r_data := [
		{"label": "NANO", "icon": "🏺", "val": str(cur_nano), "col": Color(0.4, 1.0, 0.6)},
		{"label": "ORE", "icon": "🪙", "val": str(cur_ore), "col": Color(1.0, 0.85, 0.3)},
		{"label": "SILICON", "icon": "💠", "val": str(cur_si), "col": Color(0.3, 0.85, 1.0)},
		{"label": "FLEET", "icon": "🚀", "val": fleet_val, "col": Color(1.0, 0.55, 0.85)}
	]

	for i in range(r_data.size()):
		var ry := oy + 21.0 + i * 21.0
		var item = r_data[i]
		draw_string(font, Vector2(ox + 8.0, ry), item["icon"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, item["col"])
		draw_string(font, Vector2(ox + 26.0, ry), item["label"] + ":", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.8, 0.9))
		draw_string(font, Vector2(ox + 98.0, ry), item["val"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.98, 0.98, 0.98))

func _draw_bottom_left_hud(ox: float, oy: float) -> void:
	_draw_cyber_panel(Rect2(ox, oy, 190.0, 64.0), Color(0.3, 0.55, 0.75, 0.95))

	var font := ThemeDB.fallback_font

	# ❤️ HPバー
	draw_string(font, Vector2(ox + 8.0, oy + 26.0), "❤️ HP", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.4, 0.5))
	draw_rect(Rect2(ox + 48.0, oy + 14.0, 90.0, 15.0), Color(0.18, 0.22, 0.26))
	draw_rect(Rect2(ox + 48.0, oy + 14.0, 90.0, 15.0), Color(0.95, 0.35, 0.4))
	draw_string(font, Vector2(ox + 144.0, oy + 26.0), "56/56", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1))

	# ➕ SUBバー
	draw_string(font, Vector2(ox + 8.0, oy + 50.0), "➕ SUB", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.3, 1.0, 0.5))
	draw_rect(Rect2(ox + 48.0, oy + 38.0, 90.0, 15.0), Color(0.18, 0.22, 0.26))
	draw_rect(Rect2(ox + 48.0, oy + 38.0, 32.0, 15.0), Color(0.3, 0.9, 0.5))
	draw_string(font, Vector2(ox + 144.0, oy + 50.0), "5/15", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1))

func _draw_bottom_right_hud(ox: float, oy: float) -> void:
	_draw_cyber_panel(Rect2(ox, oy, 195.0, 64.0), Color(0.3, 0.55, 0.75, 0.95))

	var font := ThemeDB.fallback_font

	# ❄️ THERM (動的冷却率)
	var therm_val := 256
	if game_state != null and game_state.upgrades.has("laser_power"):
		therm_val = 256 + (game_state.upgrades["laser_power"] - 1) * 32
	draw_string(font, Vector2(ox + 8.0, oy + 26.0), "❄️ THERM", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.85, 1.0))
	draw_rect(Rect2(ox + 60.0, oy + 14.0, 80.0, 15.0), Color(0.18, 0.22, 0.26))
	draw_rect(Rect2(ox + 60.0, oy + 14.0, 80.0, 15.0), Color(0.2, 0.8, 0.95))
	draw_string(font, Vector2(ox + 145.0, oy + 26.0), str(therm_val) + "/256", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1))

	# 📦 CARGO (実際の所持鉱石量と100%完全同期連動！)
	var cur_ore: float = 0.0
	var cur_si: float = 0.0
	if game_state != null:
		cur_ore = game_state.resources.get("ore", game_state.resources.get("iron", 0.0))
		cur_si = game_state.resources.get("silicon", 0.0)
	var total_cargo: float = cur_ore + cur_si
	var max_cargo: float = 96.0
	var fill_ratio := clampf(total_cargo / max_cargo, 0.0, 1.0)
	var bar_width := 80.0 * fill_ratio

	draw_string(font, Vector2(ox + 8.0, oy + 50.0), "📦 CARGO", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.65, 0.2))
	draw_rect(Rect2(ox + 60.0, oy + 38.0, 80.0, 15.0), Color(0.18, 0.22, 0.26))
	if bar_width > 0.0:
		draw_rect(Rect2(ox + 60.0, oy + 38.0, bar_width, 15.0), Color(0.95, 0.6, 0.2))
	draw_string(font, Vector2(ox + 145.0, oy + 50.0), str(int(total_cargo)) + "/96", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1))

func _draw_control_guide_bar(w: float, h: float) -> void:
	var bar_w := 580.0
	var bar_h := 22.0
	var bx := (w - bar_w) * 0.5
	var by := h - 26.0

	_draw_cyber_panel(Rect2(bx, by, bar_w, bar_h), Color(0.25, 0.65, 0.85, 0.8), 4.0)

	var cur_p := game_state.current_phase if game_state != null else 1
	var guide_text := ""
	match cur_p:
		GameState.Phase.PHASE_1_SURVIVAL, GameState.Phase.PHASE_2_SURFACE_INDUSTRY:
			guide_text = "🕹️ JOYSTICK: MOVE/HOVER   |   ⛏️ TAP SCREEN: MINING LASER   |   ⚙️ BUILD FACILITY"
		GameState.Phase.PHASE_3_INTERPLANETARY:
			guide_text = "🕹️ JOYSTICK: ORBITAL BURN VECTOR   |   🚀 BURN: ADJUST ORBIT   |   📡 SCAN: CORE SURVEY"
		GameState.Phase.PHASE_4_ORBITAL_WAR:
			guide_text = "🕹️ JOYSTICK: AIM MASS DRIVER   |   💥 FIRE: LAUNCH CARGO   |   🛸 SORTIE: FLEET RTS"
		_:
			guide_text = "🕹️ TOUCH CONTROLS READY"

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(bx, by + 15.0), guide_text, HORIZONTAL_ALIGNMENT_CENTER, bar_w, 10, Color(0.4, 0.92, 1.0))

func _draw_toast_banner(w: float, _h: float) -> void:
	# 洗練されたSFコンパクト通知ピル（上部中央を遮らない）
	var tw := 360.0
	var th := 24.0
	var tx := (w - tw) * 0.5
	var ty := 18.0

	var alpha := clampf(toast_timer / 0.4, 0.0, 1.0)
	draw_rect(Rect2(tx, ty, tw, th), Color(0.04, 0.08, 0.12, 0.88 * alpha))
	draw_rect(Rect2(tx, ty, tw, th), Color(0.3, 0.75, 0.95, 0.8 * alpha), false, 1.0)

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(tx, ty + 16.0), toast_text, HORIZONTAL_ALIGNMENT_CENTER, tw, 10, Color(0.4, 0.95, 1.0, alpha))

func _draw_touch_controls(w: float, h: float) -> void:
	var font := ThemeDB.fallback_font
	var t := Time.get_ticks_msec() * 0.004
	var cur_p := game_state.current_phase if game_state != null else 1

	# 座標更新
	joystick_center = Vector2(100.0, h - 140.0)
	if not is_joystick_touching:
		joystick_knob_pos = joystick_center

	btn_mine_rect = Rect2(w - 140.0, h - 150.0, 120.0, 50.0)
	btn_thrust_rect = Rect2(w - 275.0, h - 150.0, 120.0, 50.0)
	btn_build_rect = Rect2((w - 520.0) * 0.5, h - 68.0, 520.0, 36.0)
	btn_settings_rect = Rect2(w - 325.0, 122.0, 105.0, 28.0)
	btn_tech_rect = Rect2(w - 215.0, 122.0, 100.0, 28.0)
	btn_phase_rect = Rect2(w - 110.0, 122.0, 90.0, 28.0)

	# 1. 仮想ジョイスティック（左下）
	var joy_alpha := 0.75 if is_joystick_touching else 0.4
	draw_circle(joystick_center, joystick_radius, Color(0.05, 0.12, 0.2, joy_alpha * 0.7))
	draw_arc(joystick_center, joystick_radius, 0.0, TAU, 32, Color(0.3, 0.8, 1.0, joy_alpha), 1.5)
	draw_line(joystick_center - Vector2(15, 0), joystick_center + Vector2(15, 0), Color(0.3, 0.8, 1.0, joy_alpha * 0.6), 1.0)
	draw_line(joystick_center - Vector2(0, 15), joystick_center + Vector2(0, 15), Color(0.3, 0.8, 1.0, joy_alpha * 0.6), 1.0)
	var knob_col := Color(0.4, 0.95, 1.0, 0.85) if is_joystick_touching else Color(0.3, 0.75, 0.9, 0.55)
	draw_circle(joystick_knob_pos, 22.0, knob_col)
	draw_circle(joystick_knob_pos, 8.0, Color(1.0, 1.0, 1.0, 0.9))

	var joy_label := "TOUCH MOVE"
	match cur_p:
		GameState.Phase.PHASE_3_INTERPLANETARY:
			joy_label = "ORBIT NAV"
		GameState.Phase.PHASE_4_ORBITAL_WAR:
			joy_label = "AIM DRIVER"
	draw_string(font, joystick_center + Vector2(-30, joystick_radius + 18), joy_label, HORIZONTAL_ALIGNMENT_CENTER, 60, 9, Color(0.4, 0.85, 1.0, 0.6))

	# 2. 右下タッチアクションボタン（フェーズ別専用UI）
	var btn1_text := "⛏ MINE LASER"
	var btn2_text := "🚀 THRUST"
	var btn1_col := Color(1.0, 0.85, 0.3, 0.95) if is_mine_button_pressed else Color(0.2, 0.65, 0.85, 0.75)
	var btn2_col := Color(1.0, 0.6, 0.2, 0.95) if is_thrust_button_pressed else Color(0.3, 0.7, 0.9, 0.75)

	match cur_p:
		GameState.Phase.PHASE_3_INTERPLANETARY:
			btn1_text = "📡 SCAN CORE"
			btn2_text = "🚀 ORBIT BURN"
			btn1_col = Color(0.4, 0.9, 1.0, 0.9)
			btn2_col = Color(1.0, 0.7, 0.3, 0.9)
		GameState.Phase.PHASE_4_ORBITAL_WAR:
			btn1_text = "💥 FIRE DRIVER"
			btn2_text = "🛸 SORTIE FLEET"
			btn1_col = Color(0.3, 0.95, 1.0, 0.95)
			btn2_col = Color(1.0, 0.5, 0.8, 0.95)

	draw_rect(btn_mine_rect, Color(0.04, 0.08, 0.14, 0.85))
	draw_rect(btn_mine_rect, btn1_col, false, 1.5)
	draw_string(font, Vector2(btn_mine_rect.position.x, btn_mine_rect.position.y + 30), btn1_text, HORIZONTAL_ALIGNMENT_CENTER, btn_mine_rect.size.x, 11, btn1_col)

	draw_rect(btn_thrust_rect, Color(0.04, 0.08, 0.14, 0.85))
	draw_rect(btn_thrust_rect, btn2_col, false, 1.5)
	draw_string(font, Vector2(btn_thrust_rect.position.x, btn_thrust_rect.position.y + 30), btn2_text, HORIZONTAL_ALIGNMENT_CENTER, btn_thrust_rect.size.x, 11, btn2_col)

	# 3. 画面下部：中央建設・状況バー（フェーズ別専用UI）
	if cur_p in [GameState.Phase.PHASE_1_SURVIVAL, GameState.Phase.PHASE_2_SURFACE_INDUSTRY]:
		var stage: int = game_state.construction_stage if game_state != null else 0
		var can_build: bool = game_state.can_build_next_stage() if game_state != null else false
		var b_col := Color(1.0, 0.85, 0.2, 0.95) if can_build else Color(0.3, 0.6, 0.8, 0.75)

		draw_rect(btn_build_rect, Color(0.03, 0.06, 0.1, 0.92))
		draw_rect(btn_build_rect, b_col, false, 2.0 if can_build else 1.0)

		var build_msg := ""
		if game_state != null and stage < game_state.stage_requirements.size():
			var req: Dictionary = game_state.stage_requirements[stage]
			var req_name: String = req.get("name", "FACILITY")
			var cur_ore: float = game_state.resources.get("ore", game_state.resources.get("iron", 0.0))
			var need_ore: float = req.get("ore", 0.0)
			if can_build:
				build_msg = "★ [TAP TO BUILD] " + req_name + " // READY TO CONSTRUCT! ★"
			else:
				build_msg = "OBJ: BUILD " + req_name + "  [ORE: " + str(int(cur_ore)) + "/" + str(int(need_ore)) + "]  (MINE TO GATHER)"
		else:
			build_msg = "★ MAXIMUM INDUSTRIALIZATION ACHIEVED // ALL FACILITIES ACTIVE ★"

		draw_string(font, Vector2(btn_build_rect.position.x, btn_build_rect.position.y + 23), build_msg, HORIZONTAL_ALIGNMENT_CENTER, btn_build_rect.size.x, 11, b_col)
	elif cur_p == GameState.Phase.PHASE_3_INTERPLANETARY:
		draw_rect(btn_build_rect, Color(0.03, 0.06, 0.1, 0.92))
		draw_rect(btn_build_rect, Color(0.3, 0.8, 1.0, 0.8), false, 1.0)
		var orbit_info := "ORBITAL RECON TELEMETRY // ALTITUDE: 420 km // SPEED: 7.82 km/s // CORE SIGNATURE: 100%"
		draw_string(font, Vector2(btn_build_rect.position.x, btn_build_rect.position.y + 23), orbit_info, HORIZONTAL_ALIGNMENT_CENTER, btn_build_rect.size.x, 11, Color(0.4, 0.95, 1.0))
	elif cur_p == GameState.Phase.PHASE_4_ORBITAL_WAR:
		draw_rect(btn_build_rect, Color(0.03, 0.06, 0.1, 0.92))
		draw_rect(btn_build_rect, Color(1.0, 0.45, 0.7, 0.85), false, 1.0)
		var war_info := "FLEET RTS COMMAND // SHIPYARD ACTIVE // MASS DRIVER READY // ENGAGE ENEMY SWARM"
		draw_string(font, Vector2(btn_build_rect.position.x, btn_build_rect.position.y + 23), war_info, HORIZONTAL_ALIGNMENT_CENTER, btn_build_rect.size.x, 11, Color(1.0, 0.65, 0.85))

	# 4. 上部タッチボタン：[⚙ SETTINGS] [📋 TECH] [🪐 ORBIT]
	draw_rect(btn_settings_rect, Color(0.04, 0.08, 0.14, 0.85))
	draw_rect(btn_settings_rect, Color(0.3, 0.8, 1.0, 0.8), false, 1.0)
	draw_string(font, Vector2(btn_settings_rect.position.x, btn_settings_rect.position.y + 19), "⚙ SETTINGS", HORIZONTAL_ALIGNMENT_CENTER, btn_settings_rect.size.x, 10, Color(0.4, 0.9, 1.0))

	draw_rect(btn_tech_rect, Color(0.04, 0.08, 0.14, 0.85))
	draw_rect(btn_tech_rect, Color(0.3, 0.8, 1.0, 0.8), false, 1.0)
	draw_string(font, Vector2(btn_tech_rect.position.x, btn_tech_rect.position.y + 19), "📋 TECH", HORIZONTAL_ALIGNMENT_CENTER, btn_tech_rect.size.x, 10, Color(0.4, 0.9, 1.0))

	draw_rect(btn_phase_rect, Color(0.04, 0.08, 0.14, 0.85))
	draw_rect(btn_phase_rect, Color(0.3, 0.8, 1.0, 0.8), false, 1.0)
	draw_string(font, Vector2(btn_phase_rect.position.x, btn_phase_rect.position.y + 19), "🪐 ORBIT", HORIZONTAL_ALIGNMENT_CENTER, btn_phase_rect.size.x, 10, Color(0.4, 0.9, 1.0))

func _draw_settings_modal(w: float, h: float) -> void:
	# 全画面半透明バックドロップ
	draw_rect(Rect2(0, 0, w, h), Color(0.0, 0.0, 0.0, 0.65))

	var mw := 380.0
	var mh := 260.0
	var mx := (w - mw) * 0.5
	var my := (h - mh) * 0.5

	_draw_cyber_panel(Rect2(mx, my, mw, mh), Color(0.4, 0.85, 1.0, 0.95), 8.0)

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(mx, my + 32.0), "⚙ SYSTEM SETTINGS", HORIZONTAL_ALIGNMENT_CENTER, mw, 14, Color(0.4, 0.95, 1.0))
	draw_line(Vector2(mx + 20, my + 42.0), Vector2(mx + mw - 20, my + 42.0), Color(0.3, 0.7, 0.9, 0.5), 1.0)

	# Option 1: SFX Volume
	var opt_sfx := Rect2(mx + 30, my + 56, 320, 34)
	draw_rect(opt_sfx, Color(0.08, 0.14, 0.22, 0.85))
	draw_rect(opt_sfx, Color(0.3, 0.7, 0.9, 0.8), false, 1.0)
	var sfx_txt := "🔊 SFX VOLUME: " + ("100% [HIGH]" if setting_sfx_level == 2 else ("50% [MEDIUM]" if setting_sfx_level == 1 else "OFF [MUTED]"))
	draw_string(font, Vector2(opt_sfx.position.x, opt_sfx.position.y + 22.0), sfx_txt, HORIZONTAL_ALIGNMENT_CENTER, opt_sfx.size.x, 11, Color(0.95, 0.95, 1.0))

	# Option 2: Display Mode
	var opt_disp := Rect2(mx + 30, my + 100, 320, 34)
	draw_rect(opt_disp, Color(0.08, 0.14, 0.22, 0.85))
	draw_rect(opt_disp, Color(0.3, 0.7, 0.9, 0.8), false, 1.0)
	var is_fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN if DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS) else false
	var disp_txt := "🖥 DISPLAY: " + ("FULLSCREEN [ACTIVE]" if is_fs else "WINDOWED (TAP TO SWITCH)")
	draw_string(font, Vector2(opt_disp.position.x, opt_disp.position.y + 22.0), disp_txt, HORIZONTAL_ALIGNMENT_CENTER, opt_disp.size.x, 11, Color(0.95, 0.95, 1.0))

	# Option 3: Touch Controls Overlay
	var opt_touch := Rect2(mx + 30, my + 144, 320, 34)
	draw_rect(opt_touch, Color(0.08, 0.14, 0.22, 0.85))
	draw_rect(opt_touch, Color(0.3, 0.7, 0.9, 0.8), false, 1.0)
	var touch_txt := "📱 MOBILE TOUCH CONTROLS: " + ("ENABLED [VISIBLE]" if setting_touch_hud else "COMPACT [HIDDEN]")
	draw_string(font, Vector2(opt_touch.position.x, opt_touch.position.y + 22.0), touch_txt, HORIZONTAL_ALIGNMENT_CENTER, opt_touch.size.x, 11, Color(0.95, 0.95, 1.0))

	# Option 4: Close Button
	var opt_close := Rect2(mx + 30, my + 196, 320, 36)
	draw_rect(opt_close, Color(0.12, 0.35, 0.45, 0.9))
	draw_rect(opt_close, Color(0.4, 0.95, 1.0, 0.95), false, 1.5)
	draw_string(font, Vector2(opt_close.position.x, opt_close.position.y + 23.0), "✕ CLOSE SETTINGS", HORIZONTAL_ALIGNMENT_CENTER, opt_close.size.x, 12, Color(1.0, 1.0, 1.0))

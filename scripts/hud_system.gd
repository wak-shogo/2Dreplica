# hud_system.gd
class_name HUDSystem
extends Control

signal build_menu_requested
signal nano_printer_requested
signal sector_map_requested
signal phase_jump_requested(phase: int)
signal zoom_preset_requested(level: int)
signal scanner_requested

var game_state: GameState = null
var current_fps: float = 60.0
var fps_timer: float = 0.0

# 通知トースト
var toast_text: String = ""
var toast_timer: float = 0.0

# タッチ操作リップルエフェクト（スマホ操作性向上）
var touch_ripples: Array[Dictionary] = []

# オープンワールド・プレイヤー＆カメラ参照
var main_node: Node = null
var tech_tree_screen: Node = null
var player: Player = null
var primary_planet: CelestialBody = null
var camera: Camera2D = null

# 日本語・SFピクセルアートフォント
var font: Font = null

# マルチタッチ＆ピンチイン・アウト（二本指縮尺変更）
var active_touches: Dictionary = {}
var is_pinching: bool = false
var initial_pinch_dist: float = 0.0
var initial_pinch_zoom: float = 1.0
var pinch_feedback_timer: float = 0.0
var pinch_feedback_text: String = ""

# インタラクティブ・チュートリアルガイド
var is_tutorial_open: bool = true
var btn_tutorial_rect := Rect2()

# モバイル・タッチ操作システム
var joystick_center := Vector2(80.0, 580.0)
var joystick_radius := 52.0
var joystick_knob_pos := Vector2(80.0, 580.0)
var is_joystick_touching := false
var joystick_touch_id := -1

# タッチボタンの判定矩形
var btn_build_rect := Rect2()
var btn_tech_rect := Rect2()
var btn_phase_rect := Rect2()
var btn_settings_rect := Rect2()
var btn_mine_rect := Rect2()
var btn_thrust_rect := Rect2()
var btn_stage_skip_rect := Rect2()

var is_mine_button_pressed := false
var is_thrust_button_pressed := false

# 設定モーダル
var is_settings_open := false
var setting_sfx_level := 2 # 2=100%, 1=50%, 0=MUTE
var setting_touch_hud := true
var setting_vfx_high := true

func _ready() -> void:
	if ResourceLoader.exists("res://assets/fonts/DotGothic16-Regular.ttf"):
		font = load("res://assets/fonts/DotGothic16-Regular.ttf")
	if font == null:
		font = ThemeDB.fallback_font

func setup(p_game_state: GameState) -> void:
	game_state = p_game_state

func _input(event: InputEvent) -> void:
	if tech_tree_screen != null and tech_tree_screen.visible:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			active_touches[event.index] = event.position
			if active_touches.size() >= 2:
				is_pinching = true
				var keys = active_touches.keys()
				initial_pinch_dist = active_touches[keys[0]].distance_to(active_touches[keys[1]])
				initial_pinch_zoom = main_node.target_zoom if main_node != null else 1.0
				# ピンチ操作中は自機の移動や単独採掘をキャンセル
				if player != null:
					player.touch_mining = false
					player.touch_joystick_vector = Vector2.ZERO
				is_joystick_touching = false
				joystick_touch_id = -1
				is_mine_button_pressed = false
				is_thrust_button_pressed = false
				return
			_handle_touch_down(event.position, event.index)
		else:
			active_touches.erase(event.index)
			if active_touches.size() < 2:
				is_pinching = false
			_handle_touch_up(event.position, event.index)
	elif event is InputEventScreenDrag:
		active_touches[event.index] = event.position
		if is_pinching and active_touches.size() >= 2:
			var keys = active_touches.keys()
			var cur_dist: float = active_touches[keys[0]].distance_to(active_touches[keys[1]])
			if initial_pinch_dist > 8.0 and main_node != null:
				var pinch_ratio := cur_dist / initial_pinch_dist
				var new_z := clampf(initial_pinch_zoom * pinch_ratio, main_node.min_zoom, main_node.max_zoom)
				main_node.target_zoom = new_z
				pinch_feedback_timer = 1.4
				if new_z > 1.2:
					pinch_feedback_text = "ZOOM: 250% [地上ミクロ視点]"
				elif new_z > 0.6:
					pinch_feedback_text = "ZOOM: 100% [惑星断面マクロ視点]"
				else:
					pinch_feedback_text = "ZOOM: 35% [恒星系深宇宙RTS視点]"
				if game_state != null and game_state.current_tutorial_step == GameState.TutorialStep.STEP_4_PINCH_ZOOM:
					game_state.set_tutorial_step(GameState.TutorialStep.COMPLETED)
					show_toast("全チュートリアル完了！自由な惑星開発と宇宙進出が可能になりました", 3.5)
			return
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
		var mw := minf(vp_sz.x - 24.0, 380.0)
		var mh := 260.0
		var mx := (vp_sz.x - mw) * 0.5
		var my := (vp_sz.y - mh) * 0.5
		var opt_w := mw - 40.0
		var opt_x := mx + 20.0

		var opt_sfx := Rect2(opt_x, my + 56, opt_w, 36)
		var opt_disp := Rect2(opt_x, my + 102, opt_w, 36)
		var opt_touch := Rect2(opt_x, my + 148, opt_w, 36)
		var opt_close := Rect2(opt_x, my + 202, opt_w, 40)

		if opt_sfx.has_point(pos):
			setting_sfx_level = (setting_sfx_level + 2) % 3
			if game_state != null:
				game_state.play_sfx(SoundGenerator.create_beep(660.0, 0.08, 0.2))
			show_toast("効果音音量: " + ("100%" if setting_sfx_level == 2 else ("50%" if setting_sfx_level == 1 else "ミュート")), 1.5)
			return

		if opt_disp.has_point(pos):
			if DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS):
				var cur_mode := DisplayServer.window_get_mode()
				if cur_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
					show_toast("表示: ウィンドウ表示", 1.5)
				else:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
					show_toast("表示: 全画面表示", 1.5)
			if game_state != null:
				game_state.play_sfx(SoundGenerator.create_beep(740.0, 0.08, 0.2))
			return

		if opt_touch.has_point(pos):
			setting_touch_hud = not setting_touch_hud
			if game_state != null:
				game_state.play_sfx(SoundGenerator.create_beep(880.0, 0.08, 0.2))
			show_toast("タッチ操作UI: " + ("表示" if setting_touch_hud else "非表示"), 1.5)
			return

		if opt_close.has_point(pos) or not Rect2(mx, my, mw, mh).has_point(pos):
			is_settings_open = false
			if game_state != null:
				game_state.play_sfx(SoundGenerator.create_beep(440.0, 0.1, 0.2))
			return

		return

	# 1. 仮想ジョイスティック（画面左下）
	var vp_size := get_viewport().get_visible_rect().size
	var is_portrait := vp_size.y > vp_size.x
	var joy_zone := Rect2(0.0, vp_size.y - 360.0, vp_size.x * 0.45, 360.0) if is_portrait else Rect2(0.0, vp_size.y - 240.0, 260.0, 240.0)
	if pos.distance_to(joystick_center) <= joystick_radius * 1.6 or joy_zone.has_point(pos):
		is_joystick_touching = true
		joystick_touch_id = touch_id
		_update_joystick_pos(pos)
		return

	# 2. タッチボタン判定
	if btn_tutorial_rect.has_point(pos):
		is_tutorial_open = not is_tutorial_open
		if game_state != null:
			game_state.play_sfx(SoundGenerator.create_beep(660.0, 0.08, 0.2))
		return

	if btn_settings_rect.has_point(pos):
		is_settings_open = not is_settings_open
		if game_state != null:
			game_state.play_sfx(SoundGenerator.create_beep(880.0 if is_settings_open else 440.0, 0.1, 0.2))
		return

	if btn_build_rect.has_point(pos):
		if game_state != null:
			if game_state.can_build_next_stage():
				game_state.build_next_stage()
				show_toast("施設建造完了！次の開発フェーズがアンロックされました", 3.0)
			else:
				game_state.play_sfx(SoundGenerator.create_beep(220.0, 0.15, 0.25))
				show_toast("建造資源が不足しています（地殻を採掘して鉱石を採取）", 2.0)
		return

	if btn_tech_rect.has_point(pos):
		if game_state != null:
			game_state.play_sfx(SoundGenerator.create_beep(880.0, 0.08, 0.2))
			if game_state.current_tutorial_step == GameState.TutorialStep.STEP_3_TECH_TREE:
				game_state.set_tutorial_step(GameState.TutorialStep.STEP_4_PINCH_ZOOM)
		if tech_tree_screen != null:
			tech_tree_screen.open()
		return

	if btn_phase_rect.has_point(pos):
		if game_state != null:
			game_state.play_sfx(SoundGenerator.create_beep(740.0, 0.1, 0.2))
			var next_lvl := (game_state.current_phase % 3) + 1
			zoom_preset_requested.emit(next_lvl)
			if game_state.current_tutorial_step == GameState.TutorialStep.STEP_4_PINCH_ZOOM:
				game_state.set_tutorial_step(GameState.TutorialStep.COMPLETED)
				show_toast("全チュートリアル完了！自由な惑星開発と宇宙進出が可能になりました", 3.5)
		return

	if btn_stage_skip_rect.has_point(pos):
		if game_state != null:
			var next_s: int = (game_state.construction_stage + 1) % 6
			game_state.set_construction_stage(next_s)
			show_toast("開発コマンド: ステージ " + str(next_s) + " へスキップ", 2.0)
		return

	if btn_thrust_rect.has_point(pos):
		is_thrust_button_pressed = true
		if player != null:
			player.touch_joystick_vector.y = -1.0
		return

	if btn_mine_rect.has_point(pos):
		is_mine_button_pressed = true
		if player != null:
			player.touch_mining = true
			var facing := Vector2(0, -1).rotated(player.rotation)
			player.touch_mining_pos = player.global_position + facing * 60.0
		return

	# 3. 画面直接タップ採掘（スマホ特化：タップした場所を直接レーザー採掘！）
	if player != null and camera != null:
		var w_pos := camera.get_canvas_transform().affine_inverse() * pos
		player.touch_mining = true
		player.touch_mining_pos = w_pos

func _handle_touch_drag(pos: Vector2, touch_id: int) -> void:
	if is_joystick_touching and touch_id == joystick_touch_id:
		_update_joystick_pos(pos)
	elif player != null and camera != null and not is_joystick_touching:
		var w_pos := camera.get_canvas_transform().affine_inverse() * pos
		player.touch_mining_pos = w_pos

func _handle_touch_up(_pos: Vector2, touch_id: int) -> void:
	if is_joystick_touching and touch_id == joystick_touch_id:
		is_joystick_touching = false
		joystick_touch_id = -1
		joystick_knob_pos = joystick_center
		if player != null:
			player.touch_joystick_vector = Vector2.ZERO

	if is_thrust_button_pressed:
		is_thrust_button_pressed = false
		if player != null and not is_joystick_touching:
			player.touch_joystick_vector.y = 0.0

	if is_mine_button_pressed:
		is_mine_button_pressed = false
		if player != null:
			player.touch_mining = false

	if player != null and not is_mine_button_pressed:
		player.touch_mining = false

func _update_joystick_pos(pos: Vector2) -> void:
	var offset := pos - joystick_center
	var dist := offset.length()
	if dist > joystick_radius:
		offset = offset.normalized() * joystick_radius
	joystick_knob_pos = joystick_center + offset

	var norm_vec := offset / joystick_radius
	if player != null:
		player.touch_joystick_vector = norm_vec

func _process(delta: float) -> void:
	fps_timer += delta
	if fps_timer >= 0.1:
		fps_timer = 0.0
		var fps := Engine.get_frames_per_second()
		current_fps = float(fps)
		
	if toast_timer > 0.0:
		toast_timer -= delta

	if pinch_feedback_timer > 0.0:
		pinch_feedback_timer -= delta
		
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

	var is_portrait := h > w

	if is_portrait:
		var pw := (w - 24.0) * 0.5
		# 1. 左上 HUD（エンブレム、複合ゲージ、CYCLE、エネルギーバー、FPS）
		_draw_top_left_hud(8.0, 10.0, pw)

		# 2. 右上 HUD（4大リソース：NANO, ORE, SILICON, FLEET）
		_draw_top_right_hud(w - pw - 8.0, 10.0, pw)

		# 3. 左下 HUD（HP, SUB）- タッチコントロール上段に配置
		_draw_bottom_left_hud(8.0, h - 390.0, pw)

		# 4. 右下 HUD（THERM, CARGO）
		_draw_bottom_right_hud(w - pw - 8.0, h - 390.0, pw)

		# チュートリアル・ミッションオーバーレイカード
		_draw_tutorial_overlay(w, h)
	else:
		# 1. 左上 HUD
		_draw_top_left_hud(20.0, 20.0, 235.0)

		# 2. 右上 HUD
		_draw_top_right_hud(w - 255.0, 20.0, 235.0)

		# 3. 左下 HUD
		_draw_bottom_left_hud(20.0, h - 90.0, 220.0)

		# 4. 右下 HUD
		_draw_bottom_right_hud(w - 255.0, h - 90.0, 235.0)

		# チュートリアル・ミッションカード
		_draw_tutorial_overlay(w, h)

	# 5. 下部操作ガイドバー
	_draw_control_guide_bar(w, h)

	# 6. モバイル＆タッチ操作UI（仮想ジョイスティック、アクションボタン、建設バー）
	_draw_touch_controls(w, h)

	# 7. ピンチズームHUDフィードバック
	if pinch_feedback_timer > 0.0:
		_draw_pinch_zoom_feedback(w, h)

	# 8. チュートリアル・誘導ビーコン／アニメーション矢印
	if is_tutorial_open:
		_draw_tutorial_beacon_arrows(w, h)

	# 9. トースト通知バナー
	if toast_timer > 0.0:
		_draw_toast_banner(w, h)

	# 10. スマホタッチ・リップル視覚リング
	for tr in touch_ripples:
		var a: float = (tr["life"] / tr["max_life"])
		var c: Color = tr["col"]
		draw_arc(tr["pos"], tr["radius"], 0.0, TAU, 24, Color(c.r, c.g, c.b, a * 0.7), 2.0)
		draw_circle(tr["pos"], 2.5 * a, Color(1.0, 1.0, 1.0, a * 0.9))

	# 11. システム設定モーダル
	if is_settings_open:
		_draw_settings_modal(w, h)

# ベクター描画SFアイコン（文字化け完全防止・高解像度ベクター）
func _draw_icon(icon_name: String, pos: Vector2, sz: float, col: Color) -> void:
	var hs := sz * 0.5
	match icon_name:
		"energy": # ⚡ 稲妻
			var pts: PackedVector2Array = [
				pos + Vector2(hs * 0.2, -hs),
				pos + Vector2(-hs * 0.7, hs * 0.05),
				pos + Vector2(-hs * 0.05, hs * 0.05),
				pos + Vector2(-hs * 0.2, hs),
				pos + Vector2(hs * 0.7, -hs * 0.05),
				pos + Vector2(hs * 0.05, -hs * 0.05)
			]
			draw_colored_polygon(pts, col)
		"nano": # 🏺 ナナイト（バイアル／六角カプセル）
			var hex: PackedVector2Array = []
			for i in range(6):
				var ang := float(i) * TAU / 6.0
				hex.append(pos + Vector2(cos(ang), sin(ang)) * hs)
			draw_colored_polygon(hex, Color(col.r, col.g, col.b, 0.35))
			draw_polyline(hex, col, 1.5)
			draw_line(hex[5], hex[0], col, 1.5)
			draw_circle(pos, hs * 0.35, col)
		"ore": # 🪙 鉱石ナゲット
			var oct: PackedVector2Array = [
				pos + Vector2(-hs * 0.7, -hs * 0.3),
				pos + Vector2(-hs * 0.2, -hs * 0.9),
				pos + Vector2(hs * 0.6, -hs * 0.6),
				pos + Vector2(hs * 0.9, hs * 0.1),
				pos + Vector2(hs * 0.4, hs * 0.9),
				pos + Vector2(-hs * 0.6, hs * 0.7)
			]
			draw_colored_polygon(oct, col)
			draw_circle(pos + Vector2(-hs * 0.1, -hs * 0.1), hs * 0.3, Color(1, 1, 1, 0.6))
		"silicon": # 💠 シリコン（ダイヤモンド結晶）
			var dia: PackedVector2Array = [
				pos + Vector2(0.0, -hs),
				pos + Vector2(hs, 0.0),
				pos + Vector2(0.0, hs),
				pos + Vector2(-hs, 0.0)
			]
			draw_colored_polygon(dia, Color(col.r, col.g, col.b, 0.4))
			draw_polyline(dia, col, 1.5)
			draw_line(dia[3], dia[0], col, 1.5)
			draw_line(pos + Vector2(0.0, -hs), pos + Vector2(0.0, hs), col, 1.0)
			draw_line(pos + Vector2(-hs, 0.0), pos + Vector2(hs, 0.0), col, 1.0)
		"fleet": # 🚀 / 🛸 宇宙艦艇
			var ship: PackedVector2Array = [
				pos + Vector2(0.0, -hs),
				pos + Vector2(hs * 0.8, hs * 0.9),
				pos + Vector2(0.0, hs * 0.5),
				pos + Vector2(-hs * 0.8, hs * 0.9)
			]
			draw_colored_polygon(ship, col)
		"hp": # ❤️ HPクロス
			draw_rect(Rect2(pos.x - hs * 0.3, pos.y - hs, hs * 0.6, sz), col)
			draw_rect(Rect2(pos.x - hs, pos.y - hs * 0.3, sz, hs * 0.6), col)
		"sub": # ➕ SUBシールドバッジ
			var shp: PackedVector2Array = [
				pos + Vector2(-hs * 0.8, -hs * 0.8),
				pos + Vector2(hs * 0.8, -hs * 0.8),
				pos + Vector2(hs * 0.8, hs * 0.2),
				pos + Vector2(0.0, hs * 0.9),
				pos + Vector2(-hs * 0.8, hs * 0.2)
			]
			draw_colored_polygon(shp, Color(col.r, col.g, col.b, 0.4))
			draw_polyline(shp, col, 1.5)
			draw_line(shp[4], shp[0], col, 1.5)
			draw_line(pos + Vector2(0, -hs * 0.4), pos + Vector2(0, hs * 0.4), col, 1.5)
			draw_line(pos + Vector2(-hs * 0.4, 0), pos + Vector2(hs * 0.4, 0), col, 1.5)
		"therm": # ❄️ サーマル冷却ダイヤ
			for i in range(4):
				var ang := float(i) * PI * 0.25
				var v := Vector2(cos(ang), sin(ang)) * hs
				draw_line(pos - v, pos + v, col, 1.5)
			draw_circle(pos, hs * 0.3, col)
		"cargo": # 📦 コンテナ
			draw_rect(Rect2(pos.x - hs, pos.y - hs * 0.8, sz, sz * 0.8), Color(col.r, col.g, col.b, 0.35))
			draw_rect(Rect2(pos.x - hs, pos.y - hs * 0.8, sz, sz * 0.8), col, false, 1.5)
			draw_line(pos + Vector2(0, -hs * 0.8), pos + Vector2(0, hs * 0.8), col, 1.2)
			draw_line(pos + Vector2(-hs, 0), pos + Vector2(hs, 0), col, 1.2)
		"mission": # [?] ミッション情報ダイヤ
			var dia2: PackedVector2Array = [
				pos + Vector2(0, -hs),
				pos + Vector2(hs, 0),
				pos + Vector2(0, hs),
				pos + Vector2(-hs, 0)
			]
			draw_colored_polygon(dia2, col)
			draw_circle(pos, hs * 0.35, Color(0.05, 0.1, 0.15))
		"settings": # [⚙] ギア
			draw_circle(pos, hs * 0.8, col)
			draw_circle(pos, hs * 0.4, Color(0.05, 0.1, 0.15))
			for i in range(6):
				var a := float(i) * TAU / 6.0
				var off := Vector2(cos(a), sin(a)) * hs
				draw_line(pos + off * 0.6, pos + off * 1.1, col, 2.0)
		"tech": # [📋] チップ
			draw_rect(Rect2(pos.x - hs * 0.7, pos.y - hs * 0.7, sz * 0.7, sz * 0.7), col)
			draw_circle(pos, hs * 0.3, Color(0.05, 0.1, 0.15))
			for i in range(4):
				var a := float(i) * PI * 0.5
				var off := Vector2(cos(a), sin(a)) * hs
				draw_line(pos + off * 0.6, pos + off, col, 1.5)
		"view": # [🪐] 惑星軌道
			draw_circle(pos, hs * 0.45, col)
			draw_arc(pos, hs * 0.9, 0.0, TAU, 16, Color(col.r, col.g, col.b, 0.7), 1.2)
		_:
			draw_circle(pos, hs * 0.7, col)

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
	draw_colored_polygon(poly, Color(0.04, 0.07, 0.12, 0.94))
	draw_polyline(poly, border_color, 1.5)
	draw_line(poly[poly.size() - 1], poly[0], border_color, 1.5)

	# ハイテク・ブラケットアクセント
	draw_line(Vector2(x0 + c, y0), Vector2(x0 + c + 8, y0), Color(0.4, 0.95, 1.0, 0.8), 2.0)
	draw_line(Vector2(x1 - c - 8, y0), Vector2(x1 - c, y0), Color(0.4, 0.95, 1.0, 0.8), 2.0)
	draw_line(Vector2(x0 + c, y1), Vector2(x0 + c + 8, y1), Color(0.4, 0.95, 1.0, 0.8), 2.0)
	draw_line(Vector2(x1 - c - 8, y1), Vector2(x1 - c, y1), Color(0.4, 0.95, 1.0, 0.8), 2.0)

func _draw_top_left_hud(ox: float, oy: float, pw: float = 215.0) -> void:
	var vp_sz := get_viewport().get_visible_rect().size
	var is_portrait := vp_sz.y > vp_sz.x
	var panel_h := 130.0 if is_portrait else 104.0
	_draw_cyber_panel(Rect2(ox, oy, pw, panel_h), Color(0.3, 0.55, 0.75, 0.95))

	# 赤いエンブレムアイコン
	var emb_pos := Vector2(ox + (28.0 if is_portrait else 24.0), oy + (28.0 if is_portrait else 26.0))
	draw_circle(emb_pos, 16.0 if is_portrait else 15.0, Color(0.85, 0.25, 0.2, 0.9))
	draw_circle(emb_pos, 9.0, Color(0.08, 0.1, 0.14))
	draw_rect(Rect2(emb_pos.x - 2, emb_pos.y - 11, 4, 22), Color(0.9, 0.3, 0.25))
	draw_rect(Rect2(emb_pos.x - 11, emb_pos.y - 2, 22, 4), Color(0.9, 0.3, 0.25))

	# 右側のブロックゲージ
	var gx := ox + (56.0 if is_portrait else 50.0)
	var gy1 := oy + (14.0 if is_portrait else 15.0)
	var gy2 := oy + (28.0 if is_portrait else 28.0)
	var blocks := 10
	var bw := (pw - (68.0 if is_portrait else 62.0)) / float(blocks)
	for i in range(blocks):
		var bx := gx + i * bw
		var col1 := Color(0.95, 0.45, 0.2) if i < 8 else Color(0.2, 0.25, 0.3)
		draw_rect(Rect2(bx, gy1, bw - 2.0, 10.0 if is_portrait else 9.0), col1)
		var col2 := Color(0.2, 0.85, 0.95) if i < 9 else Color(0.2, 0.25, 0.3)
		draw_rect(Rect2(bx, gy2, bw - 2.0, 10.0 if is_portrait else 9.0), col2)

	var use_font: Font = font if font != null else ThemeDB.fallback_font
	var cycle_str := "CYCLE: 63:2E"
	if game_state != null and game_state.current_phase >= GameState.Phase.PHASE_3_INTERPLANETARY:
		cycle_str = "CYCLE: 93:32"

	# ステータス行 1: CYCLE と SHIELD
	var f_sz1 := 18 if is_portrait else 13
	draw_string(use_font, Vector2(ox + 12.0, oy + (62.0 if is_portrait else 53.0)), cycle_str, HORIZONTAL_ALIGNMENT_LEFT, -1, f_sz1, Color(0.95, 0.85, 0.3))
	draw_string(use_font, Vector2(ox + (pw * 0.46 if is_portrait else 115.0), oy + (62.0 if is_portrait else 53.0)), "SHIELD: 100%", HORIZONTAL_ALIGNMENT_LEFT, -1, f_sz1, Color(0.3, 0.9, 1.0))

	# ステータス行 2: ⚡ エネルギーバー
	_draw_icon("energy", Vector2(ox + 16.0, oy + (86.0 if is_portrait else 73.0)), 16.0 if is_portrait else 14.0, Color(0.3, 1.0, 0.5))
	var eg_x := ox + (34.0 if is_portrait else 30.0)
	var eg_y := oy + (77.0 if is_portrait else 65.0)
	var energy_ratio := 1.0
	if game_state != null:
		var cur_e: float = game_state.resources.get("energy", 100.0)
		var max_e: float = maxf(game_state.resources.get("max_energy", 100.0), 1.0)
		energy_ratio = clampf(cur_e / max_e, 0.0, 1.0)
	var active_blocks := int(energy_ratio * 12.0)
	var e_block_w := (pw - (46.0 if is_portrait else 42.0)) / 12.0
	for i in range(12):
		var bx := eg_x + i * e_block_w
		var col := Color(0.3, 1.0, 0.5) if i < 8 else Color(1.0, 0.85, 0.2)
		if i >= active_blocks:
			col = Color(0.18, 0.22, 0.28)
		draw_rect(Rect2(bx, eg_y, e_block_w - 2.0, 15.0 if is_portrait else 13.0), col)

	# ステータス行 3: 独立FPSカウンター
	var ms_str := "%.1f" % (1000.0 / maxf(current_fps, 1.0))
	var fps_y := oy + (100.0 if is_portrait else 83.0)
	var fps_h := 22.0 if is_portrait else 16.0
	draw_rect(Rect2(ox + 8.0, fps_y, pw - 16.0, fps_h), Color(0.02, 0.04, 0.08, 0.6))
	draw_rect(Rect2(ox + 8.0, fps_y, pw - 16.0, fps_h), Color(0.2, 0.5, 0.7, 0.5), false, 1.0)
	draw_string(use_font, Vector2(ox + 14.0, fps_y + (16.0 if is_portrait else 12.0)), "SYS TELEMETRY // FPS: " + str(int(current_fps)) + " (" + ms_str + "ms)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14 if is_portrait else 11, Color(0.4, 0.95, 1.0))

func _draw_top_right_hud(ox: float, oy: float, pw: float = 215.0) -> void:
	var vp_sz := get_viewport().get_visible_rect().size
	var is_portrait := vp_sz.y > vp_sz.x
	var panel_h := 130.0 if is_portrait else 104.0
	_draw_cyber_panel(Rect2(ox, oy, pw, panel_h), Color(0.3, 0.55, 0.75, 0.95))

	var use_font: Font = font if font != null else ThemeDB.fallback_font
	
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
		{"label": "NANO", "icon": "nano", "val": str(cur_nano), "col": Color(0.4, 1.0, 0.6)},
		{"label": "ORE", "icon": "ore", "val": str(cur_ore), "col": Color(1.0, 0.85, 0.3)},
		{"label": "SILICON", "icon": "silicon", "val": str(cur_si), "col": Color(0.3, 0.85, 1.0)},
		{"label": "FLEET", "icon": "fleet", "val": fleet_val, "col": Color(1.0, 0.55, 0.85)}
	]

	var row_h := 28.0 if is_portrait else 23.0
	var f_lbl := 17 if is_portrait else 13
	var f_val := 19 if is_portrait else 14
	for i in range(r_data.size()):
		var ry := oy + (25.0 if is_portrait else 23.0) + i * row_h
		var item = r_data[i]
		_draw_icon(item["icon"], Vector2(ox + 16.0, ry - 6.0), 16.0 if is_portrait else 13.0, item["col"])
		draw_string(use_font, Vector2(ox + (36.0 if is_portrait else 30.0), ry), item["label"] + ":", HORIZONTAL_ALIGNMENT_LEFT, -1, f_lbl, Color(0.7, 0.8, 0.9))
		draw_string(use_font, Vector2(ox + pw - (120.0 if is_portrait else 100.0), ry), item["val"], HORIZONTAL_ALIGNMENT_RIGHT, 105 if is_portrait else 85, f_val, Color(0.98, 0.98, 0.98))

func _draw_bottom_left_hud(ox: float, oy: float, pw: float = 210.0) -> void:
	var vp_sz := get_viewport().get_visible_rect().size
	var is_portrait := vp_sz.y > vp_sz.x
	var panel_h := 80.0 if is_portrait else 70.0
	_draw_cyber_panel(Rect2(ox, oy, pw, panel_h), Color(0.3, 0.55, 0.75, 0.95))

	var use_font: Font = font if font != null else ThemeDB.fallback_font

	# HPバー
	_draw_icon("hp", Vector2(ox + 18.0, oy + (24.0 if is_portrait else 20.0)), 16.0 if is_portrait else 14.0, Color(1.0, 0.35, 0.45))
	draw_string(use_font, Vector2(ox + 36.0, oy + (28.0 if is_portrait else 24.0)), "HP", HORIZONTAL_ALIGNMENT_LEFT, -1, 16 if is_portrait else 13, Color(1.0, 0.4, 0.5))
	var bar_w := minf(pw - 130.0, 180.0) if is_portrait else minf(pw - 118.0, 95.0)
	var bar_x := ox + (70.0 if is_portrait else 60.0)
	var bar_h := 20.0 if is_portrait else 16.0
	draw_rect(Rect2(bar_x, oy + (14.0 if is_portrait else 12.0), bar_w, bar_h), Color(0.18, 0.22, 0.26))
	draw_rect(Rect2(bar_x, oy + (14.0 if is_portrait else 12.0), bar_w, bar_h), Color(0.95, 0.35, 0.4))
	draw_string(use_font, Vector2(bar_x + bar_w + 10.0, oy + (28.0 if is_portrait else 24.0)), "56/56", HORIZONTAL_ALIGNMENT_LEFT, -1, 16 if is_portrait else 12, Color(1, 1, 1))

	# SUBバー
	_draw_icon("sub", Vector2(ox + 18.0, oy + (56.0 if is_portrait else 50.0)), 16.0 if is_portrait else 14.0, Color(0.3, 1.0, 0.5))
	draw_string(use_font, Vector2(ox + 36.0, oy + (60.0 if is_portrait else 54.0)), "SUB", HORIZONTAL_ALIGNMENT_LEFT, -1, 16 if is_portrait else 13, Color(0.3, 1.0, 0.5))
	draw_rect(Rect2(bar_x, oy + (46.0 if is_portrait else 42.0), bar_w, bar_h), Color(0.18, 0.22, 0.26))
	draw_rect(Rect2(bar_x, oy + (46.0 if is_portrait else 42.0), bar_w * 0.35, bar_h), Color(0.3, 0.9, 0.5))
	draw_string(use_font, Vector2(bar_x + bar_w + 10.0, oy + (60.0 if is_portrait else 54.0)), "5/15", HORIZONTAL_ALIGNMENT_LEFT, -1, 16 if is_portrait else 12, Color(1, 1, 1))

func _draw_bottom_right_hud(ox: float, oy: float, pw: float = 215.0) -> void:
	var vp_sz := get_viewport().get_visible_rect().size
	var is_portrait := vp_sz.y > vp_sz.x
	var panel_h := 80.0 if is_portrait else 70.0
	_draw_cyber_panel(Rect2(ox, oy, pw, panel_h), Color(0.3, 0.55, 0.75, 0.95))

	var use_font: Font = font if font != null else ThemeDB.fallback_font

	# THERM
	var therm_val := 256
	if game_state != null and game_state.upgrades.has("laser_power"):
		therm_val = 256 + (game_state.upgrades["laser_power"] - 1) * 32
	var bar_w := minf(pw - 140.0, 180.0) if is_portrait else minf(pw - 128.0, 85.0)
	var bar_x := ox + (80.0 if is_portrait else 72.0)
	var bar_h := 20.0 if is_portrait else 16.0
	_draw_icon("therm", Vector2(ox + 18.0, oy + (24.0 if is_portrait else 20.0)), 16.0 if is_portrait else 14.0, Color(0.3, 0.85, 1.0))
	draw_string(use_font, Vector2(ox + 34.0, oy + (28.0 if is_portrait else 24.0)), "THERM", HORIZONTAL_ALIGNMENT_LEFT, -1, 15 if is_portrait else 12, Color(0.3, 0.85, 1.0))
	draw_rect(Rect2(bar_x, oy + (14.0 if is_portrait else 12.0), bar_w, bar_h), Color(0.18, 0.22, 0.26))
	draw_rect(Rect2(bar_x, oy + (14.0 if is_portrait else 12.0), bar_w, bar_h), Color(0.2, 0.8, 0.95))
	draw_string(use_font, Vector2(bar_x + bar_w + 10.0, oy + (28.0 if is_portrait else 24.0)), str(therm_val) + "/256", HORIZONTAL_ALIGNMENT_LEFT, -1, 15 if is_portrait else 12, Color(1, 1, 1))

	# CARGO
	var cur_ore: float = 0.0
	var cur_si: float = 0.0
	if game_state != null:
		cur_ore = game_state.resources.get("ore", game_state.resources.get("iron", 0.0))
		cur_si = game_state.resources.get("silicon", 0.0)
	var total_cargo: float = cur_ore + cur_si
	var max_cargo: float = 96.0
	if total_cargo > 96.0:
		if total_cargo > 5000.0:
			max_cargo = 10000.0
		elif total_cargo > 2000.0:
			max_cargo = 5000.0
		elif total_cargo > 1000.0:
			max_cargo = 2500.0
		elif total_cargo > 500.0:
			max_cargo = 1000.0
		else:
			max_cargo = 500.0

	var fill_ratio := clampf(total_cargo / max_cargo, 0.0, 1.0)
	var filled_width := minf(bar_w * fill_ratio, bar_w)

	_draw_icon("cargo", Vector2(ox + 18.0, oy + (56.0 if is_portrait else 50.0)), 16.0 if is_portrait else 14.0, Color(1.0, 0.65, 0.2))
	draw_string(use_font, Vector2(ox + 34.0, oy + (60.0 if is_portrait else 54.0)), "CARGO", HORIZONTAL_ALIGNMENT_LEFT, -1, 15 if is_portrait else 12, Color(1.0, 0.65, 0.2))
	draw_rect(Rect2(bar_x, oy + (46.0 if is_portrait else 42.0), bar_w, bar_h), Color(0.18, 0.22, 0.26))
	if filled_width > 0.0:
		draw_rect(Rect2(bar_x, oy + (46.0 if is_portrait else 42.0), filled_width, bar_h), Color(0.95, 0.6, 0.2))

	var cargo_str := ""
	if max_cargo >= 1000.0:
		cargo_str = "%.1fk/%.0fk" % [total_cargo / 1000.0, max_cargo / 1000.0]
	else:
		cargo_str = str(int(total_cargo)) + "/" + str(int(max_cargo))
	draw_string(use_font, Vector2(bar_x + bar_w + 10.0, oy + (60.0 if is_portrait else 54.0)), cargo_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 15 if is_portrait else 12, Color(1, 1, 1))

func _draw_tutorial_overlay(w: float, h: float) -> void:
	if not is_tutorial_open:
		return
	var use_font: Font = font if font != null else ThemeDB.fallback_font
	var is_portrait := h > w

	var card_w := w - 24.0 if is_portrait else minf(w - 16.0, 520.0)
	var card_h := 115.0 if is_portrait else 80.0
	var cx := 12.0 if is_portrait else (w - card_w) * 0.5
	var cy := 214.0 if is_portrait else 130.0

	_draw_cyber_panel(Rect2(cx, cy, card_w, card_h), Color(1.0, 0.75, 0.2, 0.95), 6.0)

	var cur_step: int = game_state.current_tutorial_step if game_state != null else 0
	var cur_phase: int = game_state.current_phase if game_state != null else 1
	var c_stage: int = game_state.construction_stage if game_state != null else 0

	var step_title := ""
	var step_desc := ""
	var step_prog := 0.0

	if cur_phase == GameState.Phase.PHASE_1_SURVIVAL and c_stage == 0 and cur_step != GameState.TutorialStep.COMPLETED:
		# 初期チュートリアル 5ステップ
		match cur_step:
			GameState.TutorialStep.STEP_0_MOVE:
				step_title = "MISSION 01: プローブの推進移動"
				var m_sec := game_state.tutorial_move_time if game_state != null else 0.0
				step_desc = "左下の仮想ジョイスティックでプローブを前進移動させよ (%.1f / 3.0秒)" % [minf(m_sec, 3.0)]
				step_prog = clampf(m_sec / 3.0, 0.0, 1.0)
			GameState.TutorialStep.STEP_1_MINE:
				step_title = "MISSION 02: 地殻の採掘"
				var mined := game_state.tutorial_mined_ore if game_state != null else 0.0
				step_desc = "地表ブロックを直接タップ/長押しして鉱石を掘り出せ (鉱石: %d / 1個)" % [int(minf(mined, 1.0))]
				step_prog = clampf(mined / 1.0, 0.0, 1.0)
			GameState.TutorialStep.STEP_2_BUILD_SMELTER:
				step_title = "MISSION 03: 最初の自動化施設建造"
				step_desc = "画面最下部の金色ボタン [★施設建設★ 製錬炉] をタップして建造せよ"
				step_prog = 0.5
			GameState.TutorialStep.STEP_3_TECH_TREE:
				step_title = "MISSION 04: 3Dナノプリント強化"
				step_desc = "上部の [開発] ボタンをタップし、機体性能を3Dプリント強化せよ"
				step_prog = 0.75
			GameState.TutorialStep.STEP_4_PINCH_ZOOM:
				step_title = "MISSION 05: 2本指ピンチズーム"
				step_desc = "2本指で画面をピンチイン/アウトして惑星断面〜深宇宙へ縮尺を変更せよ"
				step_prog = 0.9
			_:
				step_title = "MISSION: 基礎施設群の拡充"
				step_desc = "地表に地上設置型3Dプリンターと放物線イジェクターを配備せよ"
				step_prog = 1.0
	elif cur_phase in [GameState.Phase.PHASE_1_SURVIVAL, GameState.Phase.PHASE_2_SURFACE_INDUSTRY]:
		match c_stage:
			1:
				step_title = "MISSION: 地上物理物流網の確立"
				step_desc = "3Dプリンターと放物線イジェクターを連携させ、鉱石の自動投擲供給ラインを構築せよ"
				step_prog = 0.35
			2:
				step_title = "MISSION: 地下エレベーターシャフト掘削"
				step_desc = "深部地殻へ向けて垂直シャフトを掘削し、高純度シリコン鉱脈の自動輸送を開始せよ"
				step_prog = 0.55
			3:
				step_title = "MISSION: 溶鉱炉の増設と連続合金精錬"
				step_desc = "高熱溶鉱炉を稼働させ、イジェクター弾道ラインと接続して精錬合金を連続生産せよ"
				step_prog = 0.75
			4:
				step_title = "MISSION: 惑星地表の完全工業化"
				step_desc = "惑星全域に自動化ラインを展開し、周回ロケット建造の準備を整えよ"
				step_prog = 0.90
			_:
				step_title = "MISSION: 軌道進出と惑星間航行"
				step_desc = "宇宙港を起動し、惑星周回軌道へ進出して恒星系スキャンを開始せよ"
				step_prog = 1.0
	elif cur_phase == GameState.Phase.PHASE_3_INTERPLANETARY:
		step_title = "MISSION: 惑星深部探査と周回軌道進出"
		step_desc = "マントル核反応テレメトリを観測し、周回ロケットと探査スキャンで資源埋蔵地を特定せよ"
		step_prog = 0.65
	elif cur_phase == GameState.Phase.PHASE_4_ORBITAL_WAR:
		step_title = "MISSION: 月面マスドライバーと小惑星星系決戦"
		step_desc = "月面マスドライバーで弾頭コンテナを連続射出！小惑星要塞と敵性自己複製艦隊を撃滅せよ"
		step_prog = 0.85
	else:
		step_title = "全ミッション完了: 自律開発モード"
		step_desc = "惑星全域を採掘・工業化し、軌道上から敵性艦隊を駆逐せよ！"
		step_prog = 1.0

	# タイトル描画（視認性の高い22px/16px）
	var t_icon_sz := 20.0 if is_portrait else 16.0
	_draw_icon("mission", Vector2(cx + (22.0 if is_portrait else 20.0), cy + (26.0 if is_portrait else 22.0)), t_icon_sz, Color(1.0, 0.8, 0.2))
	var t_f_sz := 22 if is_portrait else 16
	draw_string(use_font, Vector2(cx + (48.0 if is_portrait else 36.0), cy + (30.0 if is_portrait else 26.0)), step_title, HORIZONTAL_ALIGNMENT_LEFT, -1, t_f_sz, Color(1.0, 0.9, 0.3))

	# 説明文描画（視認性の高い18px/14px）
	var d_f_sz := 18 if is_portrait else 14
	draw_string(use_font, Vector2(cx + (18.0 if is_portrait else 14.0), cy + (64.0 if is_portrait else 50.0)), step_desc, HORIZONTAL_ALIGNMENT_LEFT, card_w - (36.0 if is_portrait else 28.0), d_f_sz, Color(0.92, 0.96, 1.0))

	# プログレスバー描画
	var pbar_y := cy + (card_h - 14.0 if is_portrait else 64.0)
	var pbar_w := card_w - (36.0 if is_portrait else 28.0)
	var pbar_x := cx + (18.0 if is_portrait else 14.0)
	var pbar_h := 8.0 if is_portrait else 7.0
	draw_rect(Rect2(pbar_x, pbar_y, pbar_w, pbar_h), Color(0.1, 0.15, 0.2, 0.85))
	if step_prog > 0.0:
		draw_rect(Rect2(pbar_x, pbar_y, pbar_w * step_prog, pbar_h), Color(0.3, 0.95, 0.5))

func _draw_tutorial_beacon_arrows(w: float, h: float) -> void:
	if game_state == null:
		return
	var cur_step := game_state.current_tutorial_step
	var t := Time.get_ticks_msec() * 0.005
	var pulse := (sin(t) + 1.0) * 0.5
	var beacon_col := Color(1.0, 0.85, 0.2, 0.85 + pulse * 0.15)

	match cur_step:
		GameState.TutorialStep.STEP_0_MOVE:
			# ジョイスティックへの誘導矢印
			var j_target := joystick_center + Vector2(0.0, -joystick_radius - 12.0 - pulse * 8.0)
			_draw_pointer_beacon(j_target, Vector2(0, 1), beacon_col)
		GameState.TutorialStep.STEP_1_MINE:
			# プレイヤー正面地殻への誘導サークル
			if player != null:
				var f_dir := Vector2(0, -1).rotated(player.rotation)
				var rock_world_pos := player.global_position + f_dir * 55.0
				if camera != null:
					var rock_scr_pos := camera.get_canvas_transform() * rock_world_pos
					draw_arc(rock_scr_pos, 22.0 + pulse * 6.0, 0.0, TAU, 24, beacon_col, 2.0)
					draw_string(font if font != null else ThemeDB.fallback_font, rock_scr_pos + Vector2(-36, -26), "ここを採掘", HORIZONTAL_ALIGNMENT_CENTER, 72, 13, beacon_col)
		GameState.TutorialStep.STEP_2_BUILD_SMELTER:
			# 建設ボタンへの強烈なパルス枠
			draw_rect(btn_build_rect.grow(3.0 + pulse * 4.0), Color(1.0, 0.85, 0.2, 0.7 * pulse), false, 2.5)
		GameState.TutorialStep.STEP_3_TECH_TREE:
			# 開発ボタンへの誘導矢印
			var t_pos := Vector2(btn_tech_rect.position.x + btn_tech_rect.size.x * 0.5, btn_tech_rect.position.y + btn_tech_rect.size.y + 12.0 + pulse * 6.0)
			_draw_pointer_beacon(t_pos, Vector2(0, -1), beacon_col)
		GameState.TutorialStep.STEP_4_PINCH_ZOOM:
			# 画面中央でのピンチジェスチャーガイド
			var center := Vector2(w * 0.5, h * 0.5)
			var spread := 30.0 + (sin(t * 1.5) + 1.0) * 25.0
			draw_circle(center - Vector2(spread, 0), 12.0, Color(0.3, 0.9, 1.0, 0.7))
			draw_circle(center + Vector2(spread, 0), 12.0, Color(0.3, 0.9, 1.0, 0.7))
			draw_line(center - Vector2(spread - 12, 0), center + Vector2(spread - 12, 0), Color(0.3, 0.9, 1.0, 0.8), 2.0)

func _draw_pointer_beacon(target_pos: Vector2, dir: Vector2, col: Color) -> void:
	var norm_dir := dir.normalized()
	var perp := Vector2(-norm_dir.y, norm_dir.x)
	var tip := target_pos
	var base := tip - norm_dir * 18.0
	var p1 := base + perp * 8.0
	var p2 := base - perp * 8.0
	var arrow: PackedVector2Array = [tip, p1, p2]
	draw_colored_polygon(arrow, col)

func _draw_pinch_zoom_feedback(w: float, h: float) -> void:
	var use_font: Font = font if font != null else ThemeDB.fallback_font
	var is_portrait := h > w
	var badge_w := w - 40.0 if is_portrait else minf(w - 30.0, 360.0)
	var badge_h := 50.0 if is_portrait else 36.0
	var bx := (w - badge_w) * 0.5
	var by := h * 0.38

	var alpha := clampf(pinch_feedback_timer / 0.4, 0.0, 1.0)
	draw_rect(Rect2(bx, by, badge_w, badge_h), Color(0.04, 0.08, 0.14, 0.9 * alpha))
	draw_rect(Rect2(bx, by, badge_w, badge_h), Color(0.35, 0.9, 1.0, 0.85 * alpha), false, 1.5)
	draw_string(use_font, Vector2(bx, by + (32.0 if is_portrait else 24.0)), pinch_feedback_text, HORIZONTAL_ALIGNMENT_CENTER, badge_w, 20 if is_portrait else 15, Color(0.4, 0.98, 1.0, alpha))

func _draw_control_guide_bar(w: float, h: float) -> void:
	var is_portrait := h > w
	var bar_w := w - 24.0 if is_portrait else minf(w - 20.0, 580.0)
	var bar_h := 36.0 if is_portrait else 22.0
	var bx := (w - bar_w) * 0.5
	var by := h - (42.0 if is_portrait else 26.0)

	_draw_cyber_panel(Rect2(bx, by, bar_w, bar_h), Color(0.25, 0.65, 0.85, 0.8), 4.0)

	var cur_p := game_state.current_phase if game_state != null else 1
	var guide_text := ""
	match cur_p:
		GameState.Phase.PHASE_1_SURVIVAL, GameState.Phase.PHASE_2_SURFACE_INDUSTRY:
			guide_text = "移動: 左スティック | 採掘: 画面タップ | 建造: 下部ボタン" if is_portrait else "操作: [A/D] 移動 | [SPACE] 推進噴射 | [クリック/タップ] 採掘レーザー | 建造: 下部ボタン"
		GameState.Phase.PHASE_3_INTERPLANETARY:
			guide_text = "軌道噴射: スティック | スキャン: 右ボタン | 視点切替: 上部" if is_portrait else "軌道航行: [A/D] 姿勢 | [SPACE] 軌道噴射 | [S] 惑星スキャナー | 視点切替"
		GameState.Phase.PHASE_4_ORBITAL_WAR:
			guide_text = "照準: スティック | 射撃: 右ボタン | 艦隊出撃: 右上" if is_portrait else "星系決戦: [A/D] マスドライバー照準 | [SPACE] 弾頭射出 | 艦隊総出撃"
		_:
			guide_text = "操作待機完了"

	var use_font: Font = font if font != null else ThemeDB.fallback_font
	draw_string(use_font, Vector2(bx, by + (24.0 if is_portrait else 16.0)), guide_text, HORIZONTAL_ALIGNMENT_CENTER, bar_w, 16 if is_portrait else 12, Color(0.4, 0.92, 1.0))

func _draw_toast_banner(w: float, h: float) -> void:
	var is_portrait := h > w
	var tw := minf(w - 20.0, 420.0)
	var th := 32.0
	var tx := (w - tw) * 0.5
	var ty := 232.0 if is_portrait else 24.0

	var alpha := clampf(toast_timer / 0.4, 0.0, 1.0)
	draw_rect(Rect2(tx, ty, tw, th), Color(0.04, 0.08, 0.12, 0.92 * alpha))
	draw_rect(Rect2(tx, ty, tw, th), Color(0.3, 0.85, 1.0, 0.9 * alpha), false, 1.5)

	var use_font: Font = font if font != null else ThemeDB.fallback_font
	draw_string(use_font, Vector2(tx + 6.0, ty + 21.0), toast_text, HORIZONTAL_ALIGNMENT_CENTER, tw - 12.0, 13, Color(0.45, 0.98, 1.0, alpha))

func _draw_touch_controls(w: float, h: float) -> void:
	var use_font: Font = font if font != null else ThemeDB.fallback_font
	var cur_p := game_state.current_phase if game_state != null else 1
	var is_portrait := h > w

	# 座標更新（指の届きやすいゆったりサイズ）
	if is_portrait:
		joystick_center = Vector2(170.0, h - 220.0)
		joystick_radius = 80.0
		var act_w := minf(260.0, w * 0.36)
		var act_h := 72.0
		btn_thrust_rect = Rect2(w - act_w - 16.0, h - 310.0, act_w, act_h)
		btn_mine_rect = Rect2(w - act_w - 16.0, h - 220.0, act_w, act_h)
		btn_build_rect = Rect2(12.0, h - 130.0, w - 24.0, 72.0)

		# 上部4大ボタン
		var top_btn_w := (w - 36.0) / 4.0
		var top_btn_h := 54.0
		var top_y := 150.0
		btn_tutorial_rect = Rect2(8.0, top_y, top_btn_w, top_btn_h)
		btn_settings_rect = Rect2(8.0 + (top_btn_w + 6.0) * 1.0, top_y, top_btn_w, top_btn_h)
		btn_tech_rect = Rect2(8.0 + (top_btn_w + 6.0) * 2.0, top_y, top_btn_w, top_btn_h)
		btn_phase_rect = Rect2(8.0 + (top_btn_w + 6.0) * 3.0, top_y, top_btn_w, top_btn_h)
	else:
		joystick_center = Vector2(105.0, h - 140.0)
		joystick_radius = 52.0
		btn_mine_rect = Rect2(w - 145.0, h - 150.0, 130.0, 52.0)
		btn_thrust_rect = Rect2(w - 285.0, h - 150.0, 130.0, 52.0)
		btn_build_rect = Rect2((w - 540.0) * 0.5, h - 72.0, 540.0, 42.0)
		var top_y := 125.0
		btn_tutorial_rect = Rect2(w - 470.0, top_y, 105.0, 32.0)
		btn_settings_rect = Rect2(w - 355.0, top_y, 105.0, 32.0)
		btn_tech_rect = Rect2(w - 240.0, top_y, 110.0, 32.0)
		btn_phase_rect = Rect2(w - 120.0, top_y, 105.0, 32.0)

	if not is_joystick_touching:
		joystick_knob_pos = joystick_center

	# 1. 仮想ジョイスティック（左下）
	var joy_alpha := 0.75 if is_joystick_touching else 0.45
	draw_circle(joystick_center, joystick_radius, Color(0.05, 0.12, 0.2, joy_alpha * 0.75))
	draw_arc(joystick_center, joystick_radius, 0.0, TAU, 32, Color(0.3, 0.8, 1.0, joy_alpha), 2.5 if is_portrait else 2.0)
	draw_line(joystick_center - Vector2(24 if is_portrait else 16, 0), joystick_center + Vector2(24 if is_portrait else 16, 0), Color(0.3, 0.8, 1.0, joy_alpha * 0.6), 2.0 if is_portrait else 1.5)
	draw_line(joystick_center - Vector2(0, 24 if is_portrait else 16), joystick_center + Vector2(0, 24 if is_portrait else 16), Color(0.3, 0.8, 1.0, joy_alpha * 0.6), 2.0 if is_portrait else 1.5)
	var knob_col := Color(0.4, 0.95, 1.0, 0.85) if is_joystick_touching else Color(0.3, 0.75, 0.9, 0.6)
	draw_circle(joystick_knob_pos, 32.0 if is_portrait else 24.0, knob_col)
	draw_circle(joystick_knob_pos, 12.0 if is_portrait else 9.0, Color(1.0, 1.0, 1.0, 0.95))

	var joy_label := "移動スティック"
	match cur_p:
		GameState.Phase.PHASE_3_INTERPLANETARY:
			joy_label = "軌道制御"
		GameState.Phase.PHASE_4_ORBITAL_WAR:
			joy_label = "砲撃照準"
	draw_string(use_font, joystick_center + Vector2(-60 if is_portrait else -40, joystick_radius + (28 if is_portrait else 20)), joy_label, HORIZONTAL_ALIGNMENT_CENTER, 120 if is_portrait else 80, 16 if is_portrait else 12, Color(0.4, 0.85, 1.0, 0.8))

	# 2. 右下タッチアクションボタン
	var btn1_text := "採掘レーザー"
	var btn2_text := "スラスター噴射"
	var btn1_col := Color(1.0, 0.85, 0.3, 0.95) if is_mine_button_pressed else Color(0.2, 0.65, 0.85, 0.85)
	var btn2_col := Color(1.0, 0.6, 0.2, 0.95) if is_thrust_button_pressed else Color(0.3, 0.7, 0.9, 0.85)

	match cur_p:
		GameState.Phase.PHASE_3_INTERPLANETARY:
			btn1_text = "探査スキャン"
			btn2_text = "軌道加速噴射"
			btn1_col = Color(0.4, 0.9, 1.0, 0.9)
			btn2_col = Color(1.0, 0.7, 0.3, 0.9)
		GameState.Phase.PHASE_4_ORBITAL_WAR:
			btn1_text = "弾頭射出"
			btn2_text = "艦隊出撃"
			btn1_col = Color(0.3, 0.95, 1.0, 0.95)
			btn2_col = Color(1.0, 0.5, 0.8, 0.95)

	draw_rect(btn_mine_rect, Color(0.04, 0.08, 0.14, 0.88))
	draw_rect(btn_mine_rect, btn1_col, false, 2.0 if is_portrait else 1.8)
	draw_string(use_font, Vector2(btn_mine_rect.position.x, btn_mine_rect.position.y + (44 if is_portrait else 32)), btn1_text, HORIZONTAL_ALIGNMENT_CENTER, btn_mine_rect.size.x, 20 if is_portrait else 15, btn1_col)

	draw_rect(btn_thrust_rect, Color(0.04, 0.08, 0.14, 0.88))
	draw_rect(btn_thrust_rect, btn2_col, false, 2.0 if is_portrait else 1.8)
	draw_string(use_font, Vector2(btn_thrust_rect.position.x, btn_thrust_rect.position.y + (44 if is_portrait else 32)), btn2_text, HORIZONTAL_ALIGNMENT_CENTER, btn_thrust_rect.size.x, 20 if is_portrait else 15, btn2_col)

	# 3. 画面下部：中央建設・状況バー
	if cur_p in [GameState.Phase.PHASE_1_SURVIVAL, GameState.Phase.PHASE_2_SURFACE_INDUSTRY]:
		var stage: int = game_state.construction_stage if game_state != null else 0
		var can_build: bool = game_state.can_build_next_stage() if game_state != null else false
		var tut_s: int = game_state.current_tutorial_step if game_state != null else 0
		var b_col := Color(1.0, 0.85, 0.2, 0.98) if can_build else Color(0.3, 0.6, 0.8, 0.8)

		var build_msg := ""
		if stage == 0 and tut_s == GameState.TutorialStep.STEP_0_MOVE:
			build_msg = "【操作誘導】左下の仮想スティックでプローブを前進移動させよ"
			b_col = Color(0.3, 0.85, 1.0, 0.95)
		elif stage == 0 and tut_s == GameState.TutorialStep.STEP_1_MINE:
			var cur_ore: float = game_state.resources.get("ore", game_state.resources.get("iron", 0.0))
			build_msg = "【操作誘導】地表の岩石ブロックをタップして採掘せよ (鉱石: " + str(int(cur_ore)) + "/1)"
			b_col = Color(1.0, 0.85, 0.3, 0.95)
		elif stage == 0 and tut_s == GameState.TutorialStep.STEP_2_BUILD_SMELTER:
			build_msg = "★ [ここをタップして建造] 製錬炉 (準備完了！タップして建造) ★"
			b_col = Color(1.0, 0.85, 0.2, 0.98)
		elif game_state != null and stage < game_state.stage_requirements.size():
			var req: Dictionary = game_state.stage_requirements[stage]
			var req_name: String = req.get("name", "FACILITY")
			var cur_ore: float = game_state.resources.get("ore", game_state.resources.get("iron", 0.0))
			var need_ore: float = req.get("ore", 0.0)
			if can_build:
				build_msg = "★ [タップで建造] " + req_name + " (準備完了！) ★"
			else:
				build_msg = "目標: " + req_name + " [鉱石: " + str(int(cur_ore)) + "/" + str(int(need_ore)) + "] (地殻を採掘)"
		else:
			build_msg = "★ 惑星地表の最大工業化を達成 // 全施設稼働中 ★"

		draw_rect(btn_build_rect, Color(0.03, 0.06, 0.1, 0.94))
		draw_rect(btn_build_rect, b_col, false, 2.5 if (can_build or tut_s == GameState.TutorialStep.STEP_2_BUILD_SMELTER) else 1.5)
		draw_string(use_font, Vector2(btn_build_rect.position.x, btn_build_rect.position.y + (44 if is_portrait else 30)), build_msg, HORIZONTAL_ALIGNMENT_CENTER, btn_build_rect.size.x, 20 if is_portrait else 15, b_col)
	elif cur_p == GameState.Phase.PHASE_3_INTERPLANETARY:
		draw_rect(btn_build_rect, Color(0.03, 0.06, 0.1, 0.94))
		draw_rect(btn_build_rect, Color(0.3, 0.8, 1.0, 0.8), false, 1.5)
		var orbit_info := "軌道探査テレメトリ // 高度: 420 km // 速度: 7.82 km/s // マントル核反応: 正常"
		draw_string(use_font, Vector2(btn_build_rect.position.x, btn_build_rect.position.y + (44 if is_portrait else 30)), orbit_info, HORIZONTAL_ALIGNMENT_CENTER, btn_build_rect.size.x, 19 if is_portrait else 14, Color(0.4, 0.95, 1.0))
	elif cur_p == GameState.Phase.PHASE_4_ORBITAL_WAR:
		draw_rect(btn_build_rect, Color(0.03, 0.06, 0.1, 0.94))
		draw_rect(btn_build_rect, Color(1.0, 0.45, 0.7, 0.85), false, 1.5)
		var war_info := "艦隊戦術命令: [迎撃態勢] 全自動迎撃ドローン配備完了 // マスドライバー装填完了"
		draw_string(use_font, Vector2(btn_build_rect.position.x, btn_build_rect.position.y + (44 if is_portrait else 30)), war_info, HORIZONTAL_ALIGNMENT_CENTER, btn_build_rect.size.x, 19 if is_portrait else 14, Color(1.0, 0.65, 0.85))

	# 4. 上部タッチボタン4種：[任務] [設定] [開発] [視点]
	var tut_col := Color(1.0, 0.8, 0.2, 0.95) if is_tutorial_open else Color(0.3, 0.7, 0.9, 0.85)
	var t_btn_f := 20 if is_portrait else 14
	var t_btn_y := 35.0 if is_portrait else 24.0
	var t_btn_icon_sz := 14.0 if is_portrait else 11.0
	var t_btn_tx_off := 34.0 if is_portrait else 22.0

	draw_rect(btn_tutorial_rect, Color(0.04, 0.08, 0.14, 0.88))
	draw_rect(btn_tutorial_rect, tut_col, false, 2.0 if is_portrait else 1.5)
	_draw_icon("mission", Vector2(btn_tutorial_rect.position.x + (18.0 if is_portrait else 14.0), btn_tutorial_rect.position.y + btn_tutorial_rect.size.y * 0.5), t_btn_icon_sz, tut_col)
	draw_string(use_font, Vector2(btn_tutorial_rect.position.x + t_btn_tx_off, btn_tutorial_rect.position.y + t_btn_y), "任務", HORIZONTAL_ALIGNMENT_LEFT, -1, t_btn_f, tut_col)

	draw_rect(btn_settings_rect, Color(0.04, 0.08, 0.14, 0.88))
	draw_rect(btn_settings_rect, Color(0.3, 0.8, 1.0, 0.85), false, 2.0 if is_portrait else 1.5)
	_draw_icon("settings", Vector2(btn_settings_rect.position.x + (18.0 if is_portrait else 14.0), btn_settings_rect.position.y + btn_settings_rect.size.y * 0.5), t_btn_icon_sz, Color(0.4, 0.9, 1.0))
	draw_string(use_font, Vector2(btn_settings_rect.position.x + t_btn_tx_off, btn_settings_rect.position.y + t_btn_y), "設定", HORIZONTAL_ALIGNMENT_LEFT, -1, t_btn_f, Color(0.4, 0.9, 1.0))

	draw_rect(btn_tech_rect, Color(0.04, 0.08, 0.14, 0.88))
	draw_rect(btn_tech_rect, Color(0.3, 0.8, 1.0, 0.85), false, 2.0 if is_portrait else 1.5)
	_draw_icon("tech", Vector2(btn_tech_rect.position.x + (18.0 if is_portrait else 14.0), btn_tech_rect.position.y + btn_tech_rect.size.y * 0.5), t_btn_icon_sz, Color(0.4, 0.9, 1.0))
	draw_string(use_font, Vector2(btn_tech_rect.position.x + t_btn_tx_off, btn_tech_rect.position.y + t_btn_y), "開発", HORIZONTAL_ALIGNMENT_LEFT, -1, t_btn_f, Color(0.4, 0.9, 1.0))

	draw_rect(btn_phase_rect, Color(0.04, 0.08, 0.14, 0.88))
	draw_rect(btn_phase_rect, Color(0.3, 0.8, 1.0, 0.85), false, 2.0 if is_portrait else 1.5)
	_draw_icon("view", Vector2(btn_phase_rect.position.x + (18.0 if is_portrait else 14.0), btn_phase_rect.position.y + btn_phase_rect.size.y * 0.5), t_btn_icon_sz, Color(0.4, 0.9, 1.0))
	draw_string(use_font, Vector2(btn_phase_rect.position.x + t_btn_tx_off, btn_phase_rect.position.y + t_btn_y), "視点", HORIZONTAL_ALIGNMENT_LEFT, -1, t_btn_f, Color(0.4, 0.9, 1.0))

func _draw_settings_modal(w: float, h: float) -> void:
	draw_rect(Rect2(0, 0, w, h), Color(0.0, 0.0, 0.0, 0.7))

	var mw := minf(w - 24.0, 390.0)
	var mh := 270.0
	var mx := (w - mw) * 0.5
	var my := (h - mh) * 0.5
	var opt_w := mw - 40.0
	var opt_x := mx + 20.0

	_draw_cyber_panel(Rect2(mx, my, mw, mh), Color(0.4, 0.85, 1.0, 0.95), 8.0)

	var use_font: Font = font if font != null else ThemeDB.fallback_font
	draw_string(use_font, Vector2(mx, my + 34.0), "システム設定", HORIZONTAL_ALIGNMENT_CENTER, mw, 16, Color(0.4, 0.95, 1.0))
	draw_line(Vector2(mx + 20, my + 44.0), Vector2(mx + mw - 20, my + 44.0), Color(0.3, 0.7, 0.9, 0.5), 1.0)

	# Option 1: SFX
	var opt_sfx := Rect2(opt_x, my + 56, opt_w, 36)
	draw_rect(opt_sfx, Color(0.08, 0.14, 0.22, 0.88))
	draw_rect(opt_sfx, Color(0.3, 0.7, 0.9, 0.8), false, 1.0)
	var sfx_txt := "効果音音量: " + ("100% [高]" if setting_sfx_level == 2 else ("50% [中]" if setting_sfx_level == 1 else "OFF [消音]"))
	draw_string(use_font, Vector2(opt_sfx.position.x, opt_sfx.position.y + 24.0), sfx_txt, HORIZONTAL_ALIGNMENT_CENTER, opt_sfx.size.x, 14, Color(0.95, 0.95, 1.0))

	# Option 2: Display Mode
	var opt_disp := Rect2(opt_x, my + 102, opt_w, 36)
	draw_rect(opt_disp, Color(0.08, 0.14, 0.22, 0.88))
	draw_rect(opt_disp, Color(0.3, 0.7, 0.9, 0.8), false, 1.0)
	var is_fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN if DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS) else false
	var disp_txt := "画面表示: " + ("全画面表示" if is_fs else "ウィンドウ表示 (タップで切替)")
	draw_string(use_font, Vector2(opt_disp.position.x, opt_disp.position.y + 24.0), disp_txt, HORIZONTAL_ALIGNMENT_CENTER, opt_disp.size.x, 14, Color(0.95, 0.95, 1.0))

	# Option 3: Touch Controls
	var opt_touch := Rect2(opt_x, my + 148, opt_w, 36)
	draw_rect(opt_touch, Color(0.08, 0.14, 0.22, 0.88))
	draw_rect(opt_touch, Color(0.3, 0.7, 0.9, 0.8), false, 1.0)
	var touch_txt := "タッチ操作UI: " + ("常時表示 [有効]" if setting_touch_hud else "非表示 [無効]")
	draw_string(use_font, Vector2(opt_touch.position.x, opt_touch.position.y + 24.0), touch_txt, HORIZONTAL_ALIGNMENT_CENTER, opt_touch.size.x, 14, Color(0.95, 0.95, 1.0))

	# Option 4: Close
	var opt_close := Rect2(opt_x, my + 202, opt_w, 40)
	draw_rect(opt_close, Color(0.12, 0.35, 0.45, 0.9))
	draw_rect(opt_close, Color(0.4, 0.95, 1.0, 0.95), false, 1.5)
	draw_string(use_font, Vector2(opt_close.position.x, opt_close.position.y + 26.0), "設定を閉じる", HORIZONTAL_ALIGNMENT_CENTER, opt_close.size.x, 15, Color(1.0, 1.0, 1.0))

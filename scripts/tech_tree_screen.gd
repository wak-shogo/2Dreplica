# tech_tree_screen.gd
class_name TechTreeScreen
extends Control

signal closed

var game_state: GameState = null
var backdrop_tex: Texture2D = null
var probe_rot: float = 0.0
var wave_offset: float = 0.0
var printing_progress: float = 0.67

# テックツリーのノード定義
# 各ノード: {"id": String, "title": String, "pos": Vector2, "lvl": int, "max_lvl": int, "unlocked": bool, "icon": String, "parents": Array[String], "color_type": "orange"|"cyan"}
var tree_nodes: Array[Dictionary] = []
var selected_node_id: String = "root_thruster"
var hovered_node: Dictionary = {}

var font: Font = null

var mobile_tab: int = 1 # 0: 3D Nano-Printer, 1: Tech Tree
var tab_printer_rect: Rect2 = Rect2()
var tab_tree_rect: Rect2 = Rect2()

func _get_node_screen_pos(node: Dictionary, w: float, h: float) -> Vector2:
	if h <= w:
		return node["pos"]
	var orig_p: Vector2 = node["pos"]
	var scale_x := clampf((w - 40.0) / 580.0, 0.6, 0.95)
	var scale_y := clampf((h - 260.0) / 620.0, 0.9, 1.45)
	var x_offset := (w - 530.0 * scale_x) * 0.5
	var y_offset := 105.0
	return Vector2(x_offset + (orig_p.x - 640.0) * scale_x, y_offset + (orig_p.y - 100.0) * scale_y)

func setup(p_game_state: GameState) -> void:
	game_state = p_game_state
	_init_tree_nodes()

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

func _ready() -> void:
	visible = false
	if ResourceLoader.exists("res://assets/fonts/DotGothic16-Regular.ttf"):
		font = load("res://assets/fonts/DotGothic16-Regular.ttf")
	if font == null:
		font = ThemeDB.fallback_font

func _process(delta: float) -> void:
	if not visible:
		return
	probe_rot += delta * 1.2
	wave_offset += delta * 5.0
	
	# プログレスバーの微動アニメーション
	printing_progress = 0.60 + sin(Time.get_ticks_msec() * 0.002) * 0.08

	# マウスホバー検出
	var mpos := get_local_mouse_position()
	hovered_node.clear()
	for node in tree_nodes:
		var np: Vector2 = node["pos"]
		if mpos.distance_to(np) < 26.0:
			hovered_node = node
			break
	
	if Input.is_physical_key_pressed(KEY_ESCAPE) or Input.is_physical_key_pressed(KEY_B):
		# Uキーで開いた後に閉じる
		pass

	queue_redraw()

func open() -> void:
	visible = true

func close() -> void:
	visible = false
	if game_state != null:
		game_state.play_sfx(SoundGenerator.create_beep(440.0, 0.06, 0.2))
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_U:
			close()
			get_viewport().set_input_as_handled()
	elif (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		var mpos: Vector2 = event.position

		# 0. 右上閉じるボタンまたは下部バーのタップで閉じる
		var vp_size := get_viewport().get_visible_rect().size
		var is_portrait := vp_size.y > vp_size.x
		var close_btn_w := 90.0 if is_portrait else 115.0
		if Rect2(vp_size.x - close_btn_w - 15.0, 5, close_btn_w + 10.0, 36).has_point(mpos) or Rect2((vp_size.x - minf(vp_size.x - 20.0, 560.0)) * 0.5, vp_size.y - 40, minf(vp_size.x - 20.0, 560.0), 40).has_point(mpos):
			close()
			get_viewport().set_input_as_handled()
			return

		# モバイルポートレートタブ切り替え判定
		if is_portrait:
			if tab_printer_rect.has_point(mpos):
				mobile_tab = 0
				if game_state != null:
					game_state.play_sfx(SoundGenerator.create_beep(660.0, 0.06, 0.2))
				queue_redraw()
				get_viewport().set_input_as_handled()
				return
			elif tab_tree_rect.has_point(mpos):
				mobile_tab = 1
				if game_state != null:
					game_state.play_sfx(SoundGenerator.create_beep(880.0, 0.06, 0.2))
				queue_redraw()
				get_viewport().set_input_as_handled()
				return

		# 1. 選択中ノードのフローティングHUDバッジクリック判定（ダイレクト・アップグレード対応）
		if not is_portrait or mobile_tab == 1:
			for node in tree_nodes:
				if node["id"] == selected_node_id:
					var p := _get_node_screen_pos(node, vp_size.x, vp_size.y)
					var bx := p.x + 28.0
					var by := p.y - 14.0
					var bw := 125.0
					var bh := 28.0
					if bx + bw > vp_size.x - 10.0:
						bx = p.x - bw - 28.0
					if Rect2(bx, by, bw, bh).has_point(mpos):
						_upgrade_node(node)
						get_viewport().set_input_as_handled()
						return

			# 2. ノード本体サークルクリック判定
			for node in tree_nodes:
				var npos := _get_node_screen_pos(node, vp_size.x, vp_size.y)
				if mpos.distance_to(npos) < 24.0:
					selected_node_id = node["id"]
					_upgrade_node(node)
					get_viewport().set_input_as_handled()
					break

func _upgrade_node(node: Dictionary) -> void:
	if not node["unlocked"]:
		return
	if node["lvl"] < node["max_lvl"]:
		node["lvl"] += 1
		if game_state != null:
			game_state.play_sfx(SoundGenerator.create_build(0.15, 0.4))
			# 隣接ノードをアンロック
			for other in tree_nodes:
				if other["parents"].has(node["id"]):
					other["unlocked"] = true
			if game_state.current_tutorial_step == GameState.TutorialStep.STEP_3_TECH_TREE:
				game_state.set_tutorial_step(GameState.TutorialStep.STEP_4_PINCH_ZOOM)
		var vp_sz := get_viewport().get_visible_rect().size
		var p: Vector2 = _get_node_screen_pos(node, vp_sz.x, vp_sz.y)
		for i in range(12):
			upgrade_sparks.append({
				"pos": p,
				"vel": Vector2(randf_range(-60, 60), randf_range(-60, 60)),
				"col": Color(1.0, randf_range(0.7, 1.0), 0.3, 1.0),
				"life": 0.4, "max_life": 0.4
			})

func _init_tree_nodes() -> void:
	tree_nodes.clear()
	
	# 画像2のピクセルアート背景に100%完全一致させた幾何学的中心座標（実測補正値）
	tree_nodes.append({
		"id": "root_thruster", "title": "THRUSTERS", "pos": Vector2(683.1, 215.5),
		"lvl": 14, "max_lvl": 50, "unlocked": true, "icon": "THR", "parents": [], "color_type": "orange"
	})
	tree_nodes.append({
		"id": "thruster_eff", "title": "THRUSTER EFFICIENCY", "pos": Vector2(769.3, 115.1),
		"lvl": 14, "max_lvl": 50, "unlocked": true, "icon": "EFF", "parents": ["root_thruster"], "color_type": "orange"
	})
	tree_nodes.append({
		"id": "mining_speed", "title": "MINING SPEED", "pos": Vector2(861.9, 211.6),
		"lvl": 19, "max_lvl": 50, "unlocked": true, "icon": "MIN", "parents": ["root_thruster"], "color_type": "orange"
	})
	tree_nodes.append({
		"id": "core_drill", "title": "DEEP DRILL", "pos": Vector2(862.3, 115.6),
		"lvl": 8, "max_lvl": 50, "unlocked": true, "icon": "DRL", "parents": ["thruster_eff"], "color_type": "orange"
	})
	tree_nodes.append({
		"id": "nano_strength", "title": "NANO-MATERIAL STRENGTH", "pos": Vector2(959.8, 113.8),
		"lvl": 14, "max_lvl": 50, "unlocked": true, "icon": "MAT", "parents": ["core_drill"], "color_type": "cyan"
	})
	tree_nodes.append({
		"id": "scan_range", "title": "SCAN RANGE", "pos": Vector2(960.6, 279.9),
		"lvl": 8, "max_lvl": 50, "unlocked": true, "icon": "SCN", "parents": ["mining_speed"], "color_type": "cyan"
	})
	tree_nodes.append({
		"id": "scan_range_2", "title": "SCAN RANGE II", "pos": Vector2(1060.0, 296.4),
		"lvl": 10, "max_lvl": 50, "unlocked": true, "icon": "SCN2", "parents": ["scan_range"], "color_type": "cyan"
	})
	tree_nodes.append({
		"id": "scan_range_1", "title": "SCAN RANGE I", "pos": Vector2(1060.3, 115.5),
		"lvl": 15, "max_lvl": 50, "unlocked": true, "icon": "SCN1", "parents": ["nano_strength"], "color_type": "cyan"
	})
	
	# 下段ブランチ
	tree_nodes.append({
		"id": "mat_eff", "title": "MATERIAL EFFICIENCY", "pos": Vector2(656.0, 357.9),
		"lvl": 10, "max_lvl": 50, "unlocked": true, "icon": "MAT", "parents": ["root_thruster"], "color_type": "orange"
	})
	tree_nodes.append({
		"id": "mined_speed_1", "title": "MINING POWER I", "pos": Vector2(861.5, 360.7),
		"lvl": 10, "max_lvl": 50, "unlocked": true, "icon": "MIN1", "parents": ["mining_speed"], "color_type": "orange"
	})
	tree_nodes.append({
		"id": "nano_strength_2", "title": "NANO-ARMOR", "pos": Vector2(961.0, 363.7),
		"lvl": 14, "max_lvl": 50, "unlocked": true, "icon": "ARM", "parents": ["scan_range"], "color_type": "cyan"
	})
	tree_nodes.append({
		"id": "nano_core", "title": "NANO-CORE MATRIX", "pos": Vector2(1058.4, 425.5),
		"lvl": 11, "max_lvl": 50, "unlocked": true, "icon": "COR", "parents": ["scan_range_2"], "color_type": "cyan"
	})
	tree_nodes.append({
		"id": "plasma_cutter", "title": "PLASMA CUTTER", "pos": Vector2(861.9, 551.0),
		"lvl": 14, "max_lvl": 50, "unlocked": true, "icon": "PLZ", "parents": ["mined_speed_1"], "color_type": "orange"
	})
	tree_nodes.append({
		"id": "scan_range_sub", "title": "SUB-SCANNER", "pos": Vector2(960.9, 540.5),
		"lvl": 5, "max_lvl": 50, "unlocked": true, "icon": "SUB", "parents": ["nano_strength_2"], "color_type": "cyan"
	})
	tree_nodes.append({
		"id": "mining_speed_sub", "title": "SELF-REPLICATION", "pos": Vector2(1059.8, 554.2),
		"lvl": 9, "max_lvl": 50, "unlocked": true, "icon": "REP", "parents": ["nano_core"], "color_type": "cyan"
	})
	tree_nodes.append({
		"id": "quantum_sensor", "title": "QUANTUM SENSOR", "pos": Vector2(960.6, 649.6),
		"lvl": 1, "max_lvl": 50, "unlocked": true, "icon": "QNT", "parents": ["scan_range_sub"], "color_type": "cyan"
	})

	# 未解除ロックノード（画像2右端）
	tree_nodes.append({
		"id": "lock_1", "title": "LOCKED", "pos": Vector2(1177.2, 195.4),
		"lvl": 0, "max_lvl": 50, "unlocked": false, "icon": "LCK", "parents": ["scan_range_1"], "color_type": "cyan"
	})
	tree_nodes.append({
		"id": "lock_2", "title": "LOCKED", "pos": Vector2(1161.0, 310.0),
		"lvl": 0, "max_lvl": 50, "unlocked": false, "icon": "LCK", "parents": ["scan_range_2"], "color_type": "cyan"
	})
	tree_nodes.append({
		"id": "lock_3", "title": "LOCKED", "pos": Vector2(1161.1, 423.4),
		"lvl": 0, "max_lvl": 50, "unlocked": false, "icon": "LCK", "parents": ["nano_core"], "color_type": "cyan"
	})
	tree_nodes.append({
		"id": "lock_4", "title": "LOCKED", "pos": Vector2(1161.0, 530.0),
		"lvl": 0, "max_lvl": 50, "unlocked": false, "icon": "LCK", "parents": ["mining_speed_sub"], "color_type": "cyan"
	})

func _draw() -> void:
	if not visible:
		return
		
	var vp_size := get_viewport().get_visible_rect().size
	var w := vp_size.x
	var h := vp_size.y
	var is_portrait := h > w

	# 1. 完全プロシージャル・サイバーホログラム背景＆グリッド
	draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.04, 0.08, 1.0))

	# 背景の薄いサイバーグリッドライン
	var grid_step := 40.0
	for gx in range(0, int(w), int(grid_step)):
		draw_line(Vector2(gx, 0), Vector2(gx, h), Color(0.06, 0.12, 0.18, 0.5), 1.0)
	for gy in range(0, int(h), int(grid_step)):
		draw_line(Vector2(0, gy), Vector2(w, gy), Color(0.06, 0.12, 0.18, 0.5), 1.0)

	# 2. 上部ヘッダー（ライブリソース完全同期）
	_draw_header(w)

	if is_portrait:
		# スマホ縦画面：上部タブ [3Dプリンター] / [テックツリー]
		var use_font: Font = font if font != null else ThemeDB.fallback_font
		var tab_w := (w - 26.0) * 0.5
		tab_printer_rect = Rect2(10.0, 48.0, tab_w, 36.0)
		tab_tree_rect = Rect2(10.0 + tab_w + 6.0, 48.0, tab_w, 36.0)

		# タブ描画
		var p_col := Color(0.2, 0.8, 1.0, 0.95) if mobile_tab == 0 else Color(0.12, 0.22, 0.3, 0.8)
		var t_col := Color(1.0, 0.7, 0.2, 0.95) if mobile_tab == 1 else Color(0.12, 0.22, 0.3, 0.8)
		draw_rect(tab_printer_rect, Color(0.06, 0.1, 0.16, 0.9))
		draw_rect(tab_printer_rect, p_col, false, 2.0 if mobile_tab == 0 else 1.0)
		draw_string(use_font, Vector2(tab_printer_rect.position.x, tab_printer_rect.position.y + 24.0), "3Dナノプリンター", HORIZONTAL_ALIGNMENT_CENTER, tab_w, 14, p_col)

		draw_rect(tab_tree_rect, Color(0.06, 0.1, 0.16, 0.9))
		draw_rect(tab_tree_rect, t_col, false, 2.0 if mobile_tab == 1 else 1.0)
		draw_string(use_font, Vector2(tab_tree_rect.position.x, tab_tree_rect.position.y + 24.0), "開発テックツリー", HORIZONTAL_ALIGNMENT_CENTER, tab_w, 14, t_col)

		if mobile_tab == 0:
			_draw_nano_printer_section_portrait(w, h)
		else:
			_draw_tech_tree_section_portrait(w, h)
	else:
		var split_x := w * 0.46
		draw_line(Vector2(split_x, 48), Vector2(split_x, h - 40), Color(0.2, 0.55, 0.85, 0.7), 2.0)

		# 3. 左画面：3D Nano-Printer 造形ステーション＆回転ホログラム
		_draw_nano_printer_section(split_x, h)

		# 4. 右画面：多分岐テックツリー・ノードネットワーク
		_draw_tech_tree_section(split_x, w, h)

		# 6. オシロスコープ動的波形
		_draw_live_oscilloscope()

	# 5. 下部モバイル操作ガイド＆タッチ閉じるボタン
	_draw_mobile_footer_guide(w, h)

	# 7. 選択中＆ホバー中ノードの動的パルスグロー
	if not is_portrait or mobile_tab == 1:
		_draw_selected_node_glow()

	# 8. アップグレードパーティクル
	_draw_upgrade_sparks()

func _draw_mobile_footer_guide(w: float, h: float) -> void:
	var use_font: Font = font if font != null else ThemeDB.fallback_font
	var is_portrait := h > w

	# 最下部フッターパネル
	var fw := minf(w - 20.0, 720.0)
	var fh := 36.0
	var fx := (w - fw) * 0.5
	var fy := h - 42.0

	draw_rect(Rect2(fx, fy, fw, fh), Color(0.04, 0.07, 0.12, 1.0))
	draw_rect(Rect2(fx, fy, fw, fh), Color(0.25, 0.65, 0.9, 0.95), false, 1.5)

	var guide_txt := "ノードをタップして選択・強化 | 画面外または閉じるで戻る" if is_portrait else "ノード選択: クリック/タップ | 強化: スペース/タップ | 戻る: ESC"
	draw_string(use_font, Vector2(fx, fy + 24.0), guide_txt, HORIZONTAL_ALIGNMENT_CENTER, fw, 13 if is_portrait else 13, Color(0.4, 0.95, 1.0))

	# 右上閉じるボタン
	var cb_w := 95.0 if is_portrait else 110.0
	var close_rect := Rect2(w - cb_w - 10.0, 8.0, cb_w, 28.0)
	draw_rect(close_rect, Color(0.12, 0.04, 0.06, 1.0))
	draw_rect(close_rect, Color(1.0, 0.4, 0.4, 0.95), false, 1.5)
	draw_string(use_font, Vector2(close_rect.position.x, close_rect.position.y + 19.0), "閉じる [×]", HORIZONTAL_ALIGNMENT_CENTER, close_rect.size.x, 13, Color(1.0, 0.7, 0.7))

func _draw_live_oscilloscope() -> void:
	# 左下 EM110 モニター画面 (x: 36 to 110, y: 628 to 678)
	var ox := 36.0
	var oy := 628.0
	var ow := 74.0
	var oh := 50.0
	var mid_y := oy + oh * 0.5

	var prev_pt := Vector2(ox + 2, mid_y)
	for i in range(1, 25):
		var x := ox + 2.0 + (float(i) / 25.0) * (ow - 4.0)
		var t := (i * 0.45) + wave_offset
		var y := mid_y + (sin(t) * 0.65 + sin(t * 2.1) * 0.35) * 14.0
		var cur_pt := Vector2(x, y)
		draw_line(prev_pt, cur_pt, Color(0.25, 1.0, 0.45, 0.95), 1.5)
		prev_pt = cur_pt

func _draw_selected_node_glow() -> void:
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.18
	for node in tree_nodes:
		var vp_sz := get_viewport().get_visible_rect().size
		var p: Vector2 = _get_node_screen_pos(node, vp_sz.x, vp_sz.y)
		if node["id"] == selected_node_id:
			var col: Color = Color(1.0, 0.8, 0.2, 0.5) if node["color_type"] == "orange" else Color(0.3, 0.9, 1.0, 0.5)
			# 呼吸するように明滅する外周光輪＆二重選択リング（実測ノード中心に完全同期）
			draw_circle(p, 26.0 * pulse, col)
			draw_circle(p, 22.0 * pulse, Color(1, 1, 1, 0.9), false, 1.8)
			draw_circle(p, 18.0, Color(1, 1, 1, 0.4), false, 1.0)
		elif not hovered_node.is_empty() and hovered_node.get("id") == node["id"]:
			draw_circle(p, 24.0, Color(0.4, 0.9, 1.0, 0.45))
			draw_circle(p, 20.0, Color(1, 1, 1, 0.7), false, 1.5)

func _draw_node_hud_badge() -> void:
	var target = hovered_node if not hovered_node.is_empty() else null
	if target == null:
		for n in tree_nodes:
			if n["id"] == selected_node_id:
				target = n
				break

	if target == null:
		return

	var p: Vector2 = target["pos"]
	var font := ThemeDB.fallback_font
	var title: String = target.get("title", "")
	var lvl: int = target.get("lvl", 1)
	var max_lvl: int = target.get("max_lvl", 50)
	var is_unlocked: bool = target.get("unlocked", true)

	# 選択中ノードの真上にスマートに配置するコンパクト透過ピル（左右の隣接ノードに一切干渉しない）
	var split_x := get_viewport().get_visible_rect().size.x * 0.46
	var bw := 135.0
	var bh := 32.0
	var bx := p.x - bw * 0.5
	var by := p.y - 48.0
	if bx < split_x + 10.0:
		bx = split_x + 10.0
	elif bx + bw > 1260.0:
		bx = 1260.0 - bw

	draw_rect(Rect2(bx, by, bw, bh), Color(0.02, 0.05, 0.1, 0.92))
	draw_rect(Rect2(bx, by, bw, bh), Color(0.35, 0.9, 1.0, 0.95), false, 1.2)
	draw_line(Vector2(p.x, p.y - 18), Vector2(p.x, by + bh), Color(0.35, 0.9, 1.0, 0.8), 1.2)

	draw_string(font, Vector2(bx + 6, by + 13), title, HORIZONTAL_ALIGNMENT_LEFT, bw - 12, 9, Color(0.5, 1.0, 1.0))
	var stat_str := "LV " + str(lvl) + "/" + str(max_lvl) + " [UPGRADE]" if is_unlocked else "[LOCKED]"
	var stat_col := Color(1.0, 0.85, 0.25) if is_unlocked else Color(0.9, 0.35, 0.35)
	draw_string(font, Vector2(bx + 6, by + 26), stat_str, HORIZONTAL_ALIGNMENT_LEFT, bw - 12, 8, stat_col)

var upgrade_sparks: Array[Dictionary] = []

func _draw_upgrade_sparks() -> void:
	var delta := get_process_delta_time()
	var keep: Array[Dictionary] = []
	for sp in upgrade_sparks:
		sp["life"] -= delta
		if sp["life"] > 0.0:
			sp["pos"] += sp["vel"] * delta
			var a: float = sp["life"] / sp["max_life"]
			var c: Color = sp["col"]
			c.a = a
			draw_circle(sp["pos"], 3.0, c)
			keep.append(sp)
	upgrade_sparks = keep

func _draw_header(w: float) -> void:
	# ヘッダーバー枠
	draw_rect(Rect2(0, 0, w, 44), Color(0.06, 0.08, 0.12, 0.98))
	draw_line(Vector2(0, 44), Vector2(w, 44), Color(0.2, 0.5, 0.75), 1.5)

	var use_font: Font = font if font != null else ThemeDB.fallback_font

	var cur_e := 2025
	var max_e := 1800
	var cur_nano := 29
	var cur_data := 100
	if game_state != null:
		cur_e = int(game_state.resources.get("energy", 2025.0))
		max_e = int(game_state.resources.get("max_energy", 1800.0))
		cur_nano = int(game_state.resources.get("nanites", game_state.resources.get("nano", 29.0)))
		cur_data = int(game_state.resources.get("ore", 100.0))

	var cb_w := 85.0 if w < 600.0 else 105.0
	var cb_rect := Rect2(w - cb_w - 10.0, 10.0, cb_w, 24.0)
	draw_rect(cb_rect, Color(0.15, 0.05, 0.08, 0.9))
	draw_rect(cb_rect, Color(1.0, 0.4, 0.4, 0.9), false, 1.2)
	draw_string(use_font, Vector2(cb_rect.position.x, cb_rect.position.y + 17.0), "閉じる [×]", HORIZONTAL_ALIGNMENT_CENTER, cb_w, 12, Color(1.0, 0.65, 0.65))

	if w < 600.0:
		# スマホ縦画面：コンパクトなリソース表示
		var seg_w := (w - cb_w - 24.0) / 3.0
		draw_string(use_font, Vector2(8, 27), "電力:" + str(cur_e), HORIZONTAL_ALIGNMENT_LEFT, int(seg_w), 12, Color(1.0, 0.85, 0.2))
		draw_string(use_font, Vector2(8 + seg_w, 27), "ナナイト:" + str(cur_nano), HORIZONTAL_ALIGNMENT_LEFT, int(seg_w), 12, Color(0.3, 0.9, 0.85))
		draw_string(use_font, Vector2(8 + seg_w * 2, 27), "鉱石:" + str(cur_data), HORIZONTAL_ALIGNMENT_LEFT, int(seg_w), 12, Color(0.7, 0.5, 1.0))
	else:
		# 電力 ENERGY
		draw_string(use_font, Vector2(25, 28), "電力 ENERGY", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.85, 0.2))
		var e_str := str(cur_e) + "/" + str(max_e)
		draw_rect(Rect2(115, 13, 105, 20), Color(0.12, 0.16, 0.22))
		draw_rect(Rect2(115, 13, 105, 20), Color(0.3, 0.6, 0.8), false, 1.0)
		draw_string(use_font, Vector2(120, 27), e_str, HORIZONTAL_ALIGNMENT_CENTER, 95, 12, Color(1, 1, 1))

		# ナナイト NANITES
		draw_string(use_font, Vector2(245, 28), "ナナイト", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.3, 0.9, 0.85))
		var n_str := str(cur_nano) + "/390"
		draw_rect(Rect2(325, 13, 95, 20), Color(0.12, 0.16, 0.22))
		draw_rect(Rect2(325, 13, 95, 20), Color(0.3, 0.6, 0.8), false, 1.0)
		draw_string(use_font, Vector2(330, 27), n_str, HORIZONTAL_ALIGNMENT_CENTER, 85, 12, Color(1, 1, 1))

		# データ DATA
		draw_string(use_font, Vector2(445, 28), "鉱石/データ", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.5, 1.0))
		var d_str := str(cur_data)
		draw_rect(Rect2(530, 13, 85, 20), Color(0.12, 0.16, 0.22))
		draw_rect(Rect2(530, 13, 85, 20), Color(0.3, 0.6, 0.8), false, 1.0)
		draw_string(use_font, Vector2(535, 27), d_str, HORIZONTAL_ALIGNMENT_CENTER, 75, 12, Color(1, 1, 1))

func _draw_nano_printer_section(split_x: float, _h: float) -> void:
	var font := ThemeDB.fallback_font

	# タイトルパネル「3D Nano-Printer」
	var title_w := 240.0
	var title_x := (split_x - title_w) * 0.5
	draw_rect(Rect2(title_x, 56, title_w, 32), Color(0.08, 0.14, 0.2, 0.9))
	draw_rect(Rect2(title_x, 56, title_w, 32), Color(0.3, 0.8, 1.0), false, 1.5)
	draw_string(font, Vector2(title_x + 36, 78), "3D Nano-Printer", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.4, 0.9, 1.0))

	# 左側：UPGRADES リスト
	var list_x := 30.0
	var list_y := 110.0
	draw_rect(Rect2(list_x, list_y, 115, 230), Color(0.06, 0.1, 0.15, 0.8))
	draw_rect(Rect2(list_x, list_y, 115, 230), Color(0.2, 0.5, 0.7), false, 1.0)
	draw_string(font, Vector2(list_x + 8, list_y + 18), "UPGRADES", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.8, 1.0))

	var up_items := ["THRUSTER", "MINING LASER", "PRINTING...", "MODULE LASER", "SCANNER MODULE"]
	for i in range(up_items.size()):
		var iy := list_y + 32.0 + i * 38.0
		var is_sel := (i == 0)
		var box_col := Color(0.2, 0.7, 1.0) if is_sel else Color(0.12, 0.2, 0.28)
		draw_rect(Rect2(list_x + 5, iy, 105, 30), box_col, false, 1.0)
		draw_string(font, Vector2(list_x + 8, iy + 16), up_items[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.9, 0.9, 0.9))
		# 小プログレスバー
		draw_rect(Rect2(list_x + 8, iy + 20, 95, 5), Color(0.1, 0.15, 0.2))
		draw_rect(Rect2(list_x + 8, iy + 20, 95 * 0.7, 5), Color(0.3, 0.8, 1.0) if is_sel else Color(0.9, 0.5, 0.2))

	# 中央メイン：ホログラム投影チャンバー
	var cham_x := 155.0
	var cham_y := 105.0
	var cham_w := 240.0
	var cham_h := 240.0
	draw_rect(Rect2(cham_x, cham_y, cham_w, cham_h), Color(0.04, 0.08, 0.12, 0.9))
	draw_rect(Rect2(cham_x, cham_y, cham_w, cham_h), Color(0.2, 0.55, 0.8), false, 1.5)

	# チャンバー内のグリッドライン
	for g in range(1, 5):
		var gx := cham_x + g * (cham_w / 5.0)
		draw_line(Vector2(gx, cham_y), Vector2(gx, cham_y + cham_h), Color(0.15, 0.3, 0.45, 0.3), 1.0)
		var gy := cham_y + g * (cham_h / 5.0)
		draw_line(Vector2(cham_x, gy), Vector2(cham_x + cham_w, gy), Color(0.15, 0.3, 0.45, 0.3), 1.0)

	# 台座と円形発光リング
	var ped_center := Vector2(cham_x + cham_w * 0.5, cham_y + cham_h - 35)
	_draw_custom_ellipse(ped_center, 65.0, 18.0, Color(0.1, 0.3, 0.45, 0.8))
	_draw_custom_ellipse_arc(ped_center, 65.0, 18.0, Color(0.3, 0.9, 1.0), 2.0)

	# 中央で回転するフォン・ノイマン・プローブのホログラム（シアン）
	var probe_c := Vector2(cham_x + cham_w * 0.5, cham_y + 95)
	_draw_hologram_probe(probe_c, probe_rot)

	# 中央下部：PRINTING... 67%
	var pb_x := cham_x + 20.0
	var pb_y := cham_y + cham_h - 26.0
	var pb_w := cham_w - 40.0
	draw_rect(Rect2(pb_x, pb_y, pb_w, 20), Color(0.08, 0.15, 0.22))
	draw_rect(Rect2(pb_x, pb_y, pb_w * printing_progress, 20), Color(0.2, 0.7, 0.9, 0.8))
	draw_rect(Rect2(pb_x, pb_y, pb_w, 20), Color(0.3, 0.85, 1.0), false, 1.2)
	draw_string(font, Vector2(pb_x + 35, pb_y + 15), "PRINTING... " + str(int(printing_progress * 100)) + "%", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1))

	# 右側：THRUSTERS & MINING LASER 詳細ボックス（緑枠）
	var rbox_x := cham_x + cham_w + 12.0
	# 上段 THRUSTERS
	draw_rect(Rect2(rbox_x, 110, 120, 105), Color(0.05, 0.1, 0.08, 0.8))
	draw_rect(Rect2(rbox_x, 110, 120, 105), Color(0.3, 0.9, 0.5), false, 1.2)
	draw_string(font, Vector2(rbox_x + 6, 126), "THRUSTERS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 1.0, 0.6))
	# スラスターアイコン
	_draw_mini_thruster(Vector2(rbox_x + 55, 155))
	# プログレス
	draw_string(font, Vector2(rbox_x + 8, 185), "PRINTING...", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.8, 0.8, 0.8))
	draw_rect(Rect2(rbox_x + 8, 192, 104, 6), Color(0.1, 0.2, 0.15))
	draw_rect(Rect2(rbox_x + 8, 192, 104 * printing_progress, 6), Color(0.3, 1.0, 0.5))

	# 中段 MINING LASER
	draw_rect(Rect2(rbox_x, 225, 120, 105), Color(0.05, 0.1, 0.08, 0.8))
	draw_rect(Rect2(rbox_x, 225, 120, 105), Color(0.3, 0.9, 0.5), false, 1.2)
	draw_string(font, Vector2(rbox_x + 6, 241), "MINING LASER", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 1.0, 0.6))
	# レーザーアイコン
	_draw_mini_laser(Vector2(rbox_x + 55, 270))
	draw_string(font, Vector2(rbox_x + 8, 300), "PRINTING... 67%", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.8, 0.8, 0.8))
	draw_rect(Rect2(rbox_x + 8, 307, 104, 6), Color(0.1, 0.2, 0.15))
	draw_rect(Rect2(rbox_x + 8, 307, 104 * printing_progress, 6), Color(0.3, 1.0, 0.5))

	# 左下：オシロスコープ波形モニタ＆診断パネル（画像2左下）
	_draw_oscilloscope(30.0, 360.0, 175.0, 95.0)

	# 右下：プローブ分解モニタ
	var dg_x := 220.0
	var dg_y := 360.0
	draw_rect(Rect2(dg_x, dg_y, 250, 95), Color(0.04, 0.08, 0.12, 0.85))
	draw_rect(Rect2(dg_x, dg_y, 250, 95), Color(0.2, 0.5, 0.7), false, 1.0)
	draw_string(font, Vector2(dg_x + 8, dg_y + 16), "DIAGNOSTIC MATRIX", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.85, 1.0))
	_draw_hologram_probe(Vector2(dg_x + 60, dg_y + 55), 0.0, 0.7)
	draw_string(font, Vector2(dg_x + 125, dg_y + 38), "HULL: 100% OK", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.9, 0.6))
	draw_string(font, Vector2(dg_x + 125, dg_y + 54), "CORE: ONLINE", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.9, 0.6))
	draw_string(font, Vector2(dg_x + 125, dg_y + 70), "AI CYCLE: NORMAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.9, 0.6))

func _draw_tech_tree_section(split_x: float, _w: float, _h: float) -> void:
	var font := ThemeDB.fallback_font

	# 接続線の描画
	for node in tree_nodes:
		for p_id in node["parents"]:
			var p_node = null
			for other in tree_nodes:
				if other["id"] == p_id:
					p_node = other
					break
			if p_node != null:
				var is_both_unlocked: bool = node["unlocked"] and p_node["unlocked"]
				var line_col := Color(0.95, 0.65, 0.2, 0.8) if node["color_type"] == "orange" else Color(0.2, 0.85, 1.0, 0.8)
				if not is_both_unlocked:
					line_col = Color(0.2, 0.25, 0.35, 0.4)
				draw_line(p_node["pos"], node["pos"], line_col, 2.5)

	# ノードの描画
	for node in tree_nodes:
		var pos: Vector2 = node["pos"]
		var is_unlocked: bool = node["unlocked"]
		var is_orange: bool = (node["color_type"] == "orange")
		var is_selected: bool = (node["id"] == selected_node_id)
		
		var base_col := Color(0.95, 0.65, 0.2) if is_orange else Color(0.2, 0.85, 1.0)
		if not is_unlocked:
			base_col = Color(0.25, 0.3, 0.38)
			
		# 外輪サークル
		draw_circle(pos, 18.0, Color(0.08, 0.1, 0.14, 0.95))
		draw_circle(pos, 15.0, Color(0.15, 0.2, 0.28))
		draw_arc(pos, 18.0, 0.0, TAU, 32, base_col, 2.0)
		
		if is_selected:
			draw_arc(pos, 22.0, 0.0, TAU, 32, Color(1, 1, 1, 0.9), 1.5)

		# アイコン
		draw_string(font, Vector2(pos.x - 7, pos.y + 6), node["icon"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, base_col)

		# タイトルとレベル表示
		if is_unlocked:
			var txt_col := Color(0.9, 0.9, 0.9)
			var lvl_str := "LVL " + str(node["lvl"]) + "/" + str(node["max_lvl"])
			draw_string(font, Vector2(pos.x - 40, pos.y + 30), lvl_str, HORIZONTAL_ALIGNMENT_CENTER, 80, 9, base_col)
			draw_string(font, Vector2(pos.x - 60, pos.y - 22), node["title"], HORIZONTAL_ALIGNMENT_CENTER, 120, 8, txt_col)

func _draw_hologram_probe(center: Vector2, rot: float, scale_f: float = 1.0) -> void:
	# 画像2完全再現：3D立体等角回転ホログラムプローブ＆スキャンビーム
	var cos_r := cos(rot)
	var sin_r := sin(rot)
	var col := Color(0.35, 0.95, 1.0, 0.95)
	var dim_col := Color(0.15, 0.6, 0.85, 0.6)

	# 1. 六角柱メインボディ（3Dアイソメトリックワイヤーフレーム）
	var bw := 34.0 * scale_f
	var bh := 22.0 * scale_f
	var front_c := center + Vector2(sin_r * 18.0 * scale_f, cos_r * 8.0 * scale_f)
	var rear_c := center - Vector2(sin_r * 18.0 * scale_f, cos_r * 8.0 * scale_f)

	# 前後キャップ
	var cap_front := PackedVector2Array([
		front_c + Vector2(-bw * 0.4 * cos_r, -bh),
		front_c + Vector2(bw * 0.4 * cos_r, -bh),
		front_c + Vector2(bw * 0.7 * cos_r, 0),
		front_c + Vector2(bw * 0.4 * cos_r, bh),
		front_c + Vector2(-bw * 0.4 * cos_r, bh),
		front_c + Vector2(-bw * 0.7 * cos_r, 0)
	])
	var cap_rear := PackedVector2Array([
		rear_c + Vector2(-bw * 0.4 * cos_r, -bh),
		rear_c + Vector2(bw * 0.4 * cos_r, -bh),
		rear_c + Vector2(bw * 0.7 * cos_r, 0),
		rear_c + Vector2(bw * 0.4 * cos_r, bh),
		rear_c + Vector2(-bw * 0.4 * cos_r, bh),
		rear_c + Vector2(-bw * 0.7 * cos_r, 0)
	])

	# 接続稜線
	for i in range(6):
		draw_line(cap_front[i], cap_rear[i], dim_col, 1.2)
	draw_polyline(PackedVector2Array(Array(cap_front) + [cap_front[0]]), col, 1.8)
	draw_polyline(PackedVector2Array(Array(cap_rear) + [cap_rear[0]]), col, 1.5)

	# 2. ソーラーパネル翼（格子グリッド付き）
	var wing_span := 55.0 * scale_f * absf(cos_r)
	var w_left_tip := center + Vector2(-bw * 0.7 * absf(cos_r) - wing_span, -sin_r * 12.0)
	var w_left_root := center + Vector2(-bw * 0.7 * absf(cos_r), 0)
	draw_line(w_left_root, w_left_tip, col, 2.0)
	draw_rect(Rect2(w_left_tip.x, w_left_tip.y - 12.0 * scale_f, wing_span, 24.0 * scale_f), Color(0.2, 0.75, 1.0, 0.4), false, 1.2)
	for g in range(1, 4):
		var gx := w_left_tip.x + g * (wing_span / 4.0)
		draw_line(Vector2(gx, w_left_tip.y - 12.0 * scale_f), Vector2(gx, w_left_tip.y + 12.0 * scale_f), dim_col, 1.0)

	var w_right_tip := center + Vector2(bw * 0.7 * absf(cos_r) + wing_span, sin_r * 12.0)
	var w_right_root := center + Vector2(bw * 0.7 * absf(cos_r), 0)
	draw_line(w_right_root, w_right_tip, col, 2.0)
	draw_rect(Rect2(w_right_root.x, w_right_tip.y - 12.0 * scale_f, wing_span, 24.0 * scale_f), Color(0.2, 0.75, 1.0, 0.4), false, 1.2)
	for g in range(1, 4):
		var gx := w_right_root.x + g * (wing_span / 4.0)
		draw_line(Vector2(gx, w_right_tip.y - 12.0 * scale_f), Vector2(gx, w_right_tip.y + 12.0 * scale_f), dim_col, 1.0)

	# 3. 前部採掘レーザー砲身＆フォーカスリング
	var laser_tip := front_c + Vector2(sin_r * 26.0 * scale_f, cos_r * 12.0 * scale_f)
	draw_line(front_c, laser_tip, Color(0.4, 1.0, 0.8), 2.5)
	draw_circle(laser_tip, 3.5, Color(1, 1, 1))

	# 4. 後部ツインスラスター
	var noz_1 := rear_c + Vector2(-10.0 * cos_r, 14.0 * scale_f)
	var noz_2 := rear_c + Vector2(10.0 * cos_r, 14.0 * scale_f)
	draw_circle(noz_1, 4.0, Color(0.3, 0.9, 1.0, 0.8))
	draw_circle(noz_2, 4.0, Color(0.3, 0.9, 1.0, 0.8))

	# 5. 上下走査ホログラムスキャンレーザー
	var scan_y := center.y - 50.0 * scale_f + fmod(Time.get_ticks_msec() * 0.06, 100.0 * scale_f)
	draw_line(Vector2(center.x - 75.0 * scale_f, scan_y), Vector2(center.x + 75.0 * scale_f, scan_y), Color(0.3, 1.0, 0.8, 0.75), 1.8)

func _draw_mini_thruster(center: Vector2) -> void:
	# 画像2右側モジュールアイコン：精密メカニカルスラスター
	# マウントブラケット
	draw_rect(Rect2(center.x - 22, center.y - 16, 18, 32), Color(0.18, 0.28, 0.24))
	draw_rect(Rect2(center.x - 22, center.y - 16, 18, 32), Color(0.35, 0.9, 0.55), false, 1.5)
	# ツインノズルベル
	for ny in [-8.0, 8.0]:
		var n_base := Vector2(center.x - 4, center.y + ny)
		draw_polygon(PackedVector2Array([
			n_base + Vector2(0, -6), Vector2(center.x + 18, center.y + ny - 10),
			Vector2(center.x + 18, center.y + ny + 10), n_base + Vector2(0, 6)
		]), [Color(0.22, 0.35, 0.28)])
		draw_polyline(PackedVector2Array([
			n_base + Vector2(0, -6), Vector2(center.x + 18, center.y + ny - 10),
			Vector2(center.x + 18, center.y + ny + 10), n_base + Vector2(0, 6)
		]), Color(0.4, 1.0, 0.6), 1.5)
		draw_circle(Vector2(center.x + 18, center.y + ny), 3.0, Color(0.6, 1.0, 0.8))

func _draw_mini_laser(center: Vector2) -> void:
	# 画像2右側モジュールアイコン：高精度採掘レーザー砲塔
	# ターレットハウジング
	draw_rect(Rect2(center.x - 20, center.y - 14, 22, 28), Color(0.18, 0.28, 0.24))
	draw_rect(Rect2(center.x - 20, center.y - 14, 22, 28), Color(0.35, 0.9, 0.55), false, 1.5)
	# 延長バレル＆電磁加速コイル
	draw_line(Vector2(center.x + 2, center.y), Vector2(center.x + 26, center.y), Color(0.3, 0.45, 0.38), 7.0)
	for c_x in [8.0, 14.0, 20.0]:
		draw_line(Vector2(center.x + c_x, center.y - 5), Vector2(center.x + c_x, center.y + 5), Color(0.4, 1.0, 0.6), 2.0)
	# マズルダイオード発光
	draw_circle(Vector2(center.x + 27, center.y), 4.5, Color(1, 1, 1))
	draw_circle(Vector2(center.x + 27, center.y), 8.0, Color(0.3, 1.0, 0.6, 0.6))

func _draw_oscilloscope(ox: float, oy: float, w: float, h: float) -> void:
	draw_rect(Rect2(ox, oy, w, h), Color(0.03, 0.06, 0.08, 0.9))
	draw_rect(Rect2(ox, oy, w, h), Color(0.15, 0.4, 0.5), false, 1.0)
	
	# グリッド
	for x in range(1, 4):
		var lx := ox + x * (w / 4.0)
		draw_line(Vector2(lx, oy), Vector2(lx, oy + h), Color(0.1, 0.25, 0.3, 0.4), 1.0)
	for y in range(1, 3):
		var ly := oy + y * (h / 3.0)
		draw_line(Vector2(ox, ly), Vector2(ox + w, ly), Color(0.1, 0.25, 0.3, 0.4), 1.0)

	# オシロスコープ緑波形
	var pts := PackedVector2Array()
	var cy := oy + h * 0.5
	for i in range(int(w)):
		var t := float(i) * 0.08 + wave_offset
		var y_val := sin(t) * 18.0 + cos(t * 2.3) * 8.0
		pts.append(Vector2(ox + i, cy + y_val))
	draw_polyline(pts, Color(0.2, 1.0, 0.5, 0.9), 1.5)

func _draw_bottom_bar(w: float, h: float) -> void:
	var font := ThemeDB.fallback_font
	var by := h - 35.0
	draw_line(Vector2(0, by), Vector2(w, by), Color(0.2, 0.45, 0.65), 1.5)
	var text := "🎮 (X) / CLICK: SELECT NODE   (Y) / CLICK: UPGRADE (+1 LVL)   [B] / [U] / [ESC]: BACK TO GAME"
	draw_string(font, Vector2(w * 0.5 - 280, by + 22), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.4, 0.9, 1.0))

func _draw_custom_ellipse(center: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var steps := 32
	for i in range(steps):
		var a := float(i) / float(steps) * TAU
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)

func _draw_custom_ellipse_arc(center: Vector2, rx: float, ry: float, col: Color, width: float) -> void:
	var steps := 32
	for i in range(steps):
		var a1 := float(i) / float(steps) * TAU
		var a2 := float(i + 1) / float(steps) * TAU
		var p1 := center + Vector2(cos(a1) * rx, sin(a1) * ry)
		var p2 := center + Vector2(cos(a2) * rx, sin(a2) * ry)
		draw_line(p1, p2, col, width)

func _draw_tech_tree_section_portrait(w: float, h: float) -> void:
	var use_font: Font = font if font != null else ThemeDB.fallback_font
	var scale_x := clampf((w - 40.0) / 580.0, 0.6, 0.95)

	# 接続線の描画
	for node in tree_nodes:
		for p_id in node["parents"]:
			var p_node = null
			for other in tree_nodes:
				if other["id"] == p_id:
					p_node = other
					break
			if p_node != null:
				var is_both_unlocked: bool = node["unlocked"] and p_node["unlocked"]
				var line_col := Color(0.95, 0.65, 0.2, 0.8) if node["color_type"] == "orange" else Color(0.2, 0.85, 1.0, 0.8)
				if not is_both_unlocked:
					line_col = Color(0.2, 0.25, 0.35, 0.4)
				var p1 := _get_node_screen_pos(p_node, w, h)
				var p2 := _get_node_screen_pos(node, w, h)
				draw_line(p1, p2, line_col, 2.5)

	# ノードの描画
	for node in tree_nodes:
		var pos := _get_node_screen_pos(node, w, h)
		var is_unlocked: bool = node["unlocked"]
		var is_orange: bool = (node["color_type"] == "orange")
		var is_selected: bool = (node["id"] == selected_node_id)
		
		var base_col := Color(0.95, 0.65, 0.2) if is_orange else Color(0.2, 0.85, 1.0)
		if not is_unlocked:
			base_col = Color(0.25, 0.3, 0.38)
			
		# 外輪サークル（親指でタップしやすい20px設計）
		var r_outer := 20.0
		var r_inner := 16.0
		draw_circle(pos, r_outer, Color(0.08, 0.1, 0.14, 0.95))
		draw_circle(pos, r_inner, Color(0.15, 0.2, 0.28))
		draw_arc(pos, r_outer, 0.0, TAU, 32, base_col, 2.2)
		
		if is_selected:
			draw_arc(pos, r_outer + 4.0, 0.0, TAU, 32, Color(1, 1, 1, 0.95), 2.0)

		# アイコン文字（12px）
		draw_string(use_font, Vector2(pos.x - 14.0, pos.y + 5.0), node["icon"], HORIZONTAL_ALIGNMENT_CENTER, 28, 11, base_col)

		# レベル表示（10px）
		if is_unlocked:
			var lvl_str := "L" + str(node["lvl"])
			draw_string(use_font, Vector2(pos.x - 30.0, pos.y + 32.0), lvl_str, HORIZONTAL_ALIGNMENT_CENTER, 60, 10, base_col)

	# 選択中ノードのサマリー詳細カード（下部）
	for node in tree_nodes:
		if node["id"] == selected_node_id:
			var card_w := minf(w - 24.0, 420.0)
			var card_h := 72.0
			var card_x := (w - card_w) * 0.5
			var card_y := h - 124.0
			draw_rect(Rect2(card_x, card_y, card_w, card_h), Color(0.05, 0.1, 0.16, 0.96))
			var border_c := Color(0.95, 0.65, 0.2) if node["color_type"] == "orange" else Color(0.3, 0.85, 1.0)
			draw_rect(Rect2(card_x, card_y, card_w, card_h), border_c, false, 2.0)
			draw_string(use_font, Vector2(card_x + 14, card_y + 26), node["title"] + "  [レベル " + str(node["lvl"]) + "/" + str(node["max_lvl"]) + "]", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, border_c)
			var status_s := "★ タップして技術強化 (+1 レベル) ★" if node["unlocked"] else "未解除: 前提となる技術を開発してください"
			var status_c := Color(0.4, 0.95, 1.0) if node["unlocked"] else Color(0.9, 0.45, 0.45)
			draw_string(use_font, Vector2(card_x + 14, card_y + 52), status_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, status_c)
			break

func _draw_nano_printer_section_portrait(w: float, h: float) -> void:
	var use_font: Font = font if font != null else ThemeDB.fallback_font
	var cham_w := minf(w - 24.0, 420.0)
	var cham_h := minf(h * 0.45, 420.0)
	var cham_x := (w - cham_w) * 0.5
	var cham_y := 96.0

	# チャンバー背景
	draw_rect(Rect2(cham_x, cham_y, cham_w, cham_h), Color(0.04, 0.08, 0.12, 0.94))
	draw_rect(Rect2(cham_x, cham_y, cham_w, cham_h), Color(0.2, 0.55, 0.8), false, 1.5)

	# グリッド
	for g in range(1, 5):
		var gx := cham_x + g * (cham_w / 5.0)
		draw_line(Vector2(gx, cham_y), Vector2(gx, cham_y + cham_h), Color(0.15, 0.3, 0.45, 0.3), 1.0)
		var gy := cham_y + g * (cham_h / 5.0)
		draw_line(Vector2(cham_x, gy), Vector2(cham_x + cham_w, gy), Color(0.15, 0.3, 0.45, 0.3), 1.0)

	# 台座と円形発光リング
	var ped_center := Vector2(cham_x + cham_w * 0.5, cham_y + cham_h - 45)
	_draw_custom_ellipse(ped_center, 90.0, 24.0, Color(0.1, 0.3, 0.45, 0.8))
	_draw_custom_ellipse_arc(ped_center, 90.0, 24.0, Color(0.3, 0.9, 1.0), 2.0)

	# 中央で回転するフォン・ノイマン・プローブのホログラム（存在感のある1.3倍スケール）
	var probe_c := Vector2(cham_x + cham_w * 0.5, cham_y + cham_h * 0.45)
	_draw_hologram_probe(probe_c, probe_rot, 1.3)

	# プログレスバー
	var pb_x := cham_x + 20.0
	var pb_y := cham_y + cham_h - 32.0
	var pb_w := cham_w - 40.0
	draw_rect(Rect2(pb_x, pb_y, pb_w, 24), Color(0.08, 0.15, 0.22))
	draw_rect(Rect2(pb_x, pb_y, pb_w * printing_progress, 24), Color(0.2, 0.7, 0.9, 0.8))
	draw_rect(Rect2(pb_x, pb_y, pb_w, 24), Color(0.3, 0.85, 1.0), false, 1.5)
	draw_string(use_font, Vector2(pb_x, pb_y + 18), "造形進捗 (PRINTING): " + str(int(printing_progress * 100)) + "%", HORIZONTAL_ALIGNMENT_CENTER, pb_w, 14, Color(1, 1, 1))

	# 下段：THRUSTERS & MINING LASER 情報カード（横並び）
	var sub_y := cham_y + cham_h + 16.0
	var sub_w := (cham_w - 12.0) * 0.5
	# スラスター
	draw_rect(Rect2(cham_x, sub_y, sub_w, 115), Color(0.05, 0.1, 0.08, 0.85))
	draw_rect(Rect2(cham_x, sub_y, sub_w, 115), Color(0.3, 0.9, 0.5), false, 1.5)
	draw_string(use_font, Vector2(cham_x + 8, sub_y + 22), "推進スラスター", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.4, 1.0, 0.6))
	_draw_mini_thruster(Vector2(cham_x + sub_w * 0.5, sub_y + 56))
	draw_rect(Rect2(cham_x + 8, sub_y + 92, sub_w - 16, 8), Color(0.1, 0.2, 0.15))
	draw_rect(Rect2(cham_x + 8, sub_y + 92, (sub_w - 16) * printing_progress, 8), Color(0.3, 1.0, 0.5))

	# レーザー
	var l_x := cham_x + sub_w + 12.0
	draw_rect(Rect2(l_x, sub_y, sub_w, 115), Color(0.05, 0.1, 0.08, 0.85))
	draw_rect(Rect2(l_x, sub_y, sub_w, 115), Color(0.3, 0.9, 0.5), false, 1.5)
	draw_string(use_font, Vector2(l_x + 8, sub_y + 22), "採掘レーザー", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.4, 1.0, 0.6))
	_draw_mini_laser(Vector2(l_x + sub_w * 0.5, sub_y + 56))
	draw_rect(Rect2(l_x + 8, sub_y + 92, sub_w - 16, 8), Color(0.1, 0.2, 0.15))
	draw_rect(Rect2(l_x + 8, sub_y + 92, (sub_w - 16) * printing_progress, 8), Color(0.3, 1.0, 0.5))

	# 下段2：オシロスコープ＆診断マトリクス
	var diag_y := sub_y + 130.0
	var diag_h := minf(h - diag_y - 60.0, 240.0)
	if diag_h > 80.0:
		_draw_oscilloscope(cham_x, diag_y, cham_w * 0.5 - 6.0, diag_h)

		var mx_x := cham_x + cham_w * 0.5 + 6.0
		var mx_w := cham_w * 0.5 - 6.0
		draw_rect(Rect2(mx_x, diag_y, mx_w, diag_h), Color(0.04, 0.08, 0.12, 0.9))
		draw_rect(Rect2(mx_x, diag_y, mx_w, diag_h), Color(0.2, 0.55, 0.75), false, 1.2)
		draw_string(use_font, Vector2(mx_x + 8, diag_y + 24), "機体自己診断テレメトリ", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.3, 0.85, 1.0))
		draw_string(use_font, Vector2(mx_x + 8, diag_y + 52), "装甲完全性: 100% [正常]", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.4, 0.95, 0.6))
		draw_string(use_font, Vector2(mx_x + 8, diag_y + 76), "量子コア稼働: ONLINE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.4, 0.95, 0.6))
		draw_string(use_font, Vector2(mx_x + 8, diag_y + 100), "複製サイクル: 同期中", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.4, 0.95, 0.6))
		draw_string(use_font, Vector2(mx_x + 8, diag_y + 124), "ナノ材料供給: 安定", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.4, 0.95, 0.6))

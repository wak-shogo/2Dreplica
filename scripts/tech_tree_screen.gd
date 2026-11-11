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

func setup(p_game_state: GameState) -> void:
	game_state = p_game_state
	backdrop_tex = load("res://assets/textures/tex_tech_tree_backdrop.png")
	_init_tree_nodes()

func _ready() -> void:
	visible = false

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
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_U:
			close()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# ノードクリック判定
		var mpos: Vector2 = event.position
		for node in tree_nodes:
			var npos: Vector2 = node["pos"]
			if mpos.distance_to(npos) < 22.0:
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
		var p: Vector2 = node["pos"]
		for i in range(12):
			upgrade_sparks.append({
				"pos": p,
				"vel": Vector2(randf_range(-60, 60), randf_range(-60, 60)),
				"col": Color(1.0, randf_range(0.7, 1.0), 0.3, 1.0),
				"life": 0.4, "max_life": 0.4
			})

func _init_tree_nodes() -> void:
	tree_nodes.clear()
	var cx := 880.0
	var cy := 360.0
	
	# 画像2に完全準拠したテックツリー配置
	tree_nodes.append({
		"id": "root_thruster", "title": "THRUSTERS", "pos": Vector2(cx - 180, cy - 60),
		"lvl": 14, "max_lvl": 50, "unlocked": true, "icon": "🚀", "parents": [], "color_type": "orange"
	})
	tree_nodes.append({
		"id": "thruster_eff", "title": "THRUSTER EFFICIENCY", "pos": Vector2(cx - 100, cy - 140),
		"lvl": 14, "max_lvl": 50, "unlocked": true, "icon": "🔥", "parents": ["root_thruster"], "color_type": "orange"
	})
	tree_nodes.append({
		"id": "mining_speed", "title": "MINING SPEED", "pos": Vector2(cx - 30, cy - 40),
		"lvl": 19, "max_lvl": 50, "unlocked": true, "icon": "⚡", "parents": ["root_thruster"], "color_type": "orange"
	})
	tree_nodes.append({
		"id": "core_drill", "title": "DEEP DRILL", "pos": Vector2(cx - 30, cy - 130),
		"lvl": 8, "max_lvl": 50, "unlocked": true, "icon": "⚙️", "parents": ["thruster_eff"], "color_type": "orange"
	})
	tree_nodes.append({
		"id": "nano_strength", "title": "NANO-MATERIAL STRENGTH", "pos": Vector2(cx + 60, cy - 120),
		"lvl": 14, "max_lvl": 50, "unlocked": true, "icon": "💠", "parents": ["core_drill"], "color_type": "cyan"
	})
	tree_nodes.append({
		"id": "scan_range", "title": "SCAN RANGE", "pos": Vector2(cx + 60, cy - 40),
		"lvl": 8, "max_lvl": 50, "unlocked": true, "icon": "📡", "parents": ["mining_speed"], "color_type": "cyan"
	})
	tree_nodes.append({
		"id": "scan_range_2", "title": "SCAN RANGE II", "pos": Vector2(cx + 140, cy - 40),
		"lvl": 10, "max_lvl": 50, "unlocked": true, "icon": "🛰️", "parents": ["scan_range"], "color_type": "cyan"
	})
	tree_nodes.append({
		"id": "nano_eff", "title": "NANO-CORE", "pos": Vector2(cx + 140, cy - 120),
		"lvl": 15, "max_lvl": 50, "unlocked": true, "icon": "💎", "parents": ["nano_strength"], "color_type": "cyan"
	})
	
	# 下段ブランチ
	tree_nodes.append({
		"id": "mat_eff", "title": "MATERIAL EFFICIENCY", "pos": Vector2(cx - 180, cy + 40),
		"lvl": 10, "max_lvl": 50, "unlocked": true, "icon": "📦", "parents": ["root_thruster"], "color_type": "orange"
	})
	tree_nodes.append({
		"id": "adv_thrust", "title": "HYPER THRUSTER", "pos": Vector2(cx - 180, cy + 120),
		"lvl": 14, "max_lvl": 50, "unlocked": true, "icon": "✨", "parents": ["mat_eff"], "color_type": "orange"
	})
	tree_nodes.append({
		"id": "mined_speed_1", "title": "MINING POWER I", "pos": Vector2(cx - 30, cy + 40),
		"lvl": 10, "max_lvl": 50, "unlocked": true, "icon": "🎯", "parents": ["mining_speed"], "color_type": "orange"
	})
	tree_nodes.append({
		"id": "plasma_cutter", "title": "PLASMA CUTTER", "pos": Vector2(cx - 30, cy + 120),
		"lvl": 14, "max_lvl": 50, "unlocked": true, "icon": "💥", "parents": ["mined_speed_1"], "color_type": "orange"
	})
	tree_nodes.append({
		"id": "nano_armor", "title": "NANO-ARMOR", "pos": Vector2(cx + 60, cy + 40),
		"lvl": 14, "max_lvl": 50, "unlocked": true, "icon": "🛡️", "parents": ["scan_range"], "color_type": "cyan"
	})
	tree_nodes.append({
		"id": "quantum_sensor", "title": "QUANTUM SENSOR", "pos": Vector2(cx + 60, cy + 120),
		"lvl": 5, "max_lvl": 50, "unlocked": true, "icon": "🔍", "parents": ["nano_armor"], "color_type": "cyan"
	})
	tree_nodes.append({
		"id": "fleet_link", "title": "FLEET MATRIX", "pos": Vector2(cx + 140, cy + 40),
		"lvl": 11, "max_lvl": 50, "unlocked": true, "icon": "🛸", "parents": ["scan_range_2"], "color_type": "cyan"
	})
	tree_nodes.append({
		"id": "auto_rep", "title": "SELF-REPLICATION", "pos": Vector2(cx + 140, cy + 120),
		"lvl": 9, "max_lvl": 50, "unlocked": true, "icon": "🔄", "parents": ["fleet_link"], "color_type": "cyan"
	})

	# 未解除ロックノード（画像2右端）
	tree_nodes.append({
		"id": "lock_1", "title": "LOCKED", "pos": Vector2(cx + 220, cy - 120),
		"lvl": 0, "max_lvl": 50, "unlocked": false, "icon": "🔒", "parents": ["nano_eff"], "color_type": "cyan"
	})
	tree_nodes.append({
		"id": "lock_2", "title": "LOCKED", "pos": Vector2(cx + 220, cy - 40),
		"lvl": 0, "max_lvl": 50, "unlocked": false, "icon": "🔒", "parents": ["scan_range_2"], "color_type": "cyan"
	})
	tree_nodes.append({
		"id": "lock_3", "title": "LOCKED", "pos": Vector2(cx + 220, cy + 40),
		"lvl": 0, "max_lvl": 50, "unlocked": false, "icon": "🔒", "parents": ["fleet_link"], "color_type": "cyan"
	})
	tree_nodes.append({
		"id": "lock_4", "title": "LOCKED", "pos": Vector2(cx + 220, cy + 120),
		"lvl": 0, "max_lvl": 50, "unlocked": false, "icon": "🔒", "parents": ["auto_rep"], "color_type": "cyan"
	})

func _draw() -> void:
	if not visible:
		return
		
	var vp_size := get_viewport().get_visible_rect().size
	var w := vp_size.x
	var h := vp_size.y

	# 1. 高品位HD-2Dコックピット＆テックツリー背景（画像2完全再現）
	if backdrop_tex != null:
		draw_texture_rect(backdrop_tex, Rect2(0, 0, w, h), false)
	else:
		draw_rect(Rect2(0, 0, w, h), Color(0.04, 0.05, 0.08, 0.96))

	# 2. オシロスコープ動的波形（EM110モニター枠内に完全格納）
	_draw_live_oscilloscope()

	# 3. 選択中＆ホバー中ノードの動的パルスグロー
	_draw_selected_node_glow()

	# 4. アップグレードパーティクル
	_draw_upgrade_sparks()

	# 5. ホバー中ノードの詳細ツールチップ
	_draw_node_tooltip(w, h)

	# 6. PC操作対応の洗練された下部ガイドバー
	_draw_pc_bottom_bar(w, h)

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
		var p: Vector2 = node["pos"]
		if node["id"] == selected_node_id:
			var col: Color = Color(1.0, 0.8, 0.2, 0.5) if node["color_type"] == "orange" else Color(0.3, 0.9, 1.0, 0.5)
			# 呼吸するように明滅する外周光輪＆二重選択リング
			draw_circle(p, 28.0 * pulse, col)
			draw_circle(p, 23.0 * pulse, Color(1, 1, 1, 0.9), false, 2.0)
			draw_circle(p, 19.0, Color(1, 1, 1, 0.4), false, 1.0)
		elif not hovered_node.is_empty() and hovered_node.get("id") == node["id"]:
			draw_circle(p, 25.0, Color(0.4, 0.9, 1.0, 0.45))
			draw_circle(p, 21.0, Color(1, 1, 1, 0.7), false, 1.5)

func _draw_node_tooltip(w: float, h: float) -> void:
	var target = hovered_node if not hovered_node.is_empty() else null
	if target == null:
		for n in tree_nodes:
			if n["id"] == selected_node_id:
				target = n
				break

	if target == null:
		return

	var font := ThemeDB.fallback_font
	var bx := w * 0.49
	var by := h - 90.0
	var bw := 440.0
	var bh := 48.0

	draw_rect(Rect2(bx, by, bw, bh), Color(0.04, 0.07, 0.12, 0.98))
	draw_rect(Rect2(bx, by, bw, bh), Color(0.3, 0.75, 1.0, 0.95), false, 1.5)

	var title: String = target.get("title", "")
	var lvl: int = target.get("lvl", 1)
	var max_lvl: int = target.get("max_lvl", 50)
	var is_unlocked: bool = target.get("unlocked", true)

	draw_string(font, Vector2(bx + 14, by + 20), title + "  [LVL " + str(lvl) + "/" + str(max_lvl) + "]", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.35, 0.9, 1.0))

	var status_text := "COST: 25 NANITES, 120 ORE  |  [CLICK / (Y) TO UPGRADE]" if is_unlocked else "PREREQUISITE TECH REQUIRED [LOCKED]"
	var status_col := Color(1.0, 0.85, 0.3) if is_unlocked else Color(0.8, 0.3, 0.3)
	draw_string(font, Vector2(bx + 14, by + 38), status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, status_col)

func _draw_pc_bottom_bar(w: float, h: float) -> void:
	var bar_h := 34.0
	var by := h - bar_h
	draw_rect(Rect2(0, by, w, bar_h), Color(0.05, 0.07, 0.12, 0.98))
	draw_line(Vector2(0, by), Vector2(w, by), Color(0.2, 0.55, 0.8), 1.5)

	var font := ThemeDB.fallback_font
	var guide_text := "[L-CLICK] UPGRADE NODE   [U] / [ESC] CLOSE TECH TREE   [1~4] SWITCH VIEW   (X) SELECT  (Y) UPGRADE  (B) BACK"
	draw_string(font, Vector2(0, by + 22), guide_text, HORIZONTAL_ALIGNMENT_CENTER, w, 11, Color(0.4, 0.9, 1.0))

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

	var font := ThemeDB.fallback_font

	# ⚡ ENERGY 2025/1800
	draw_string(font, Vector2(25, 28), "⚡ ENERGY", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.85, 0.2))
	draw_rect(Rect2(100, 14, 90, 18), Color(0.15, 0.18, 0.22))
	draw_rect(Rect2(100, 14, 90, 18), Color(0.3, 0.6, 0.8), false, 1.0)
	draw_string(font, Vector2(108, 28), "2025/1800", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1))

	# ⚙ NANITES 29/390
	draw_string(font, Vector2(240, 28), "⚙ NANITES", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.3, 0.9, 0.85))
	draw_rect(Rect2(325, 14, 80, 18), Color(0.15, 0.18, 0.22))
	draw_rect(Rect2(325, 14, 80, 18), Color(0.3, 0.6, 0.8), false, 1.0)
	draw_string(font, Vector2(335, 28), "29/390", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1))

	# 💾 DATA 100
	draw_string(font, Vector2(450, 28), "💾 DATA", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.5, 1.0))
	draw_rect(Rect2(520, 14, 60, 18), Color(0.15, 0.18, 0.22))
	draw_rect(Rect2(520, 14, 60, 18), Color(0.3, 0.6, 0.8), false, 1.0)
	draw_string(font, Vector2(538, 28), "100", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1))

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
	draw_string(font, Vector2(dg_x + 125, dg_y + 40), "HULL: 100% OK\nCORE: ONLINE\nAI CYCLE: NORMAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.9, 0.6))

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
	# 3D風回転ホログラムプローブ
	var cos_r := cos(rot)
	var sin_r := sin(rot)
	var col := Color(0.3, 0.9, 1.0, 0.9)
	
	# 円筒ボディ
	var body_w := 28.0 * scale_f
	var body_h := 38.0 * scale_f
	var p1 := center + Vector2(-body_w * cos_r, -body_h)
	var p2 := center + Vector2(body_w * cos_r, -body_h)
	var p3 := center + Vector2(body_w * cos_r, body_h * 0.4)
	var p4 := center + Vector2(-body_w * cos_r, body_h * 0.4)
	draw_polyline(PackedVector2Array([p1, p2, p3, p4, p1]), col, 1.8)

	# ソーラーパネル翼
	var wing_w := 45.0 * scale_f * absf(sin_r)
	var w1 := center + Vector2(-body_w * cos_r - wing_w, -10 * scale_f)
	var w2 := center + Vector2(-body_w * cos_r, -10 * scale_f)
	var w3 := center + Vector2(-body_w * cos_r, 15 * scale_f)
	var w4 := center + Vector2(-body_w * cos_r - wing_w, 15 * scale_f)
	draw_polyline(PackedVector2Array([w1, w2, w3, w4, w1]), Color(0.4, 0.7, 1.0, 0.8), 1.2)

	# アンテナ
	draw_line(center + Vector2(0, -body_h), center + Vector2(sin_r * 15.0, -body_h - 22.0 * scale_f), Color(0.5, 1.0, 0.9), 1.5)
	draw_circle(center + Vector2(sin_r * 15.0, -body_h - 22.0 * scale_f), 3.0, Color(0.5, 1.0, 0.9))

	# スラスターノズル
	var n1 := center + Vector2(-12.0 * cos_r, body_h * 0.4)
	var n2 := center + Vector2(12.0 * cos_r, body_h * 0.4)
	var n3 := center + Vector2(8.0 * cos_r, body_h * 0.8)
	var n4 := center + Vector2(-8.0 * cos_r, body_h * 0.8)
	draw_polyline(PackedVector2Array([n1, n2, n3, n4, n1]), col, 1.5)

func _draw_mini_thruster(center: Vector2) -> void:
	draw_rect(Rect2(center.x - 14, center.y - 12, 16, 24), Color(0.2, 0.5, 0.3))
	draw_polygon(PackedVector2Array([
		Vector2(center.x + 2, center.y - 10), Vector2(center.x + 16, center.y - 16),
		Vector2(center.x + 16, center.y + 16), Vector2(center.x + 2, center.y + 10)
	]), [Color(0.3, 0.9, 0.5)])

func _draw_mini_laser(center: Vector2) -> void:
	draw_rect(Rect2(center.x - 16, center.y - 8, 18, 16), Color(0.2, 0.5, 0.3))
	draw_rect(Rect2(center.x + 2, center.y - 3, 22, 6), Color(0.4, 1.0, 0.6))
	draw_circle(Vector2(center.x + 24, center.y), 4.0, Color(1, 1, 1))

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

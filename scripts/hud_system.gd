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

# テックツリー画面の参照（重複描画防止）
var tech_tree_screen: Node = null

func setup(p_game_state: GameState) -> void:
	game_state = p_game_state

func _process(delta: float) -> void:
	fps_timer += delta
	if fps_timer >= 0.1:
		fps_timer = 0.0
		var fps := Engine.get_frames_per_second()
		current_fps = clampf(fps if fps > 15.0 else 60.0, 59.0, 60.0)
		
	if toast_timer > 0.0:
		toast_timer -= delta
		
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

	# 6. トースト通知バナー
	if toast_timer > 0.0:
		_draw_toast_banner(w, h)

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
	
	var fleet_val := "699"
	if game_state != null and game_state.current_phase < GameState.Phase.PHASE_3_INTERPLANETARY:
		fleet_val = "STANDBY"

	var r_data := [
		{"label": "NANO", "icon": "🏺", "val": "1,986", "col": Color(0.4, 1.0, 0.6)},
		{"label": "ORE", "icon": "🪙", "val": "134,076", "col": Color(1.0, 0.85, 0.3)},
		{"label": "SILICON", "icon": "💠", "val": "34,620", "col": Color(0.3, 0.85, 1.0)},
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

	# ❄️ THERM
	draw_string(font, Vector2(ox + 8.0, oy + 26.0), "❄️ THERM", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.85, 1.0))
	draw_rect(Rect2(ox + 60.0, oy + 14.0, 80.0, 15.0), Color(0.18, 0.22, 0.26))
	draw_rect(Rect2(ox + 60.0, oy + 14.0, 80.0, 15.0), Color(0.2, 0.8, 0.95))
	draw_string(font, Vector2(ox + 145.0, oy + 26.0), "256/256", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1))

	# 📦 CARGO
	draw_string(font, Vector2(ox + 8.0, oy + 50.0), "📦 CARGO", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.65, 0.2))
	draw_rect(Rect2(ox + 60.0, oy + 38.0, 80.0, 15.0), Color(0.18, 0.22, 0.26))
	draw_rect(Rect2(ox + 60.0, oy + 38.0, 72.0, 15.0), Color(0.95, 0.6, 0.2))
	draw_string(font, Vector2(ox + 145.0, oy + 50.0), "86/96", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1))

func _draw_control_guide_bar(w: float, h: float) -> void:
	# 左右のHUDと干渉せず、ゲーム内施設（溶鉱炉・コンベア）を遮らないコンパクト下部配置
	var bar_w := 640.0
	var bar_h := 24.0
	var bx := (w - bar_w) * 0.5
	var by := h - 30.0

	_draw_cyber_panel(Rect2(bx, by, bar_w, bar_h), Color(0.25, 0.65, 0.85, 0.8), 5.0)

	var cur_p := game_state.current_phase if game_state != null else 1
	var guide_text := ""
	match cur_p:
		GameState.Phase.PHASE_1_SURVIVAL, GameState.Phase.PHASE_2_SURFACE_INDUSTRY:
			guide_text = "[A/D] PROBE LOCOMOTION   [W/SPACE] PLASMA THRUST   [L-CLICK] MINING LASER   [U] TECH-TREE"
		GameState.Phase.PHASE_3_INTERPLANETARY:
			guide_text = "[A/D] ORBIT TANGENT BURN   [W/S] ALTITUDE BURN   [TAB] PLANETARY SCAN   [U] TECH-TREE"
		GameState.Phase.PHASE_4_ORBITAL_WAR:
			guide_text = "[L-CLICK] FIRE MASS DRIVER   [SPACE] THRUST IGNITION   [F] FLEET RTS SORTIE   [U] TECH-TREE"
		_:
			guide_text = "[A/D] MOVE   [W/SPACE] THRUST   [L-CLICK] LASER   [U] NANO-CORE MATRIX"

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(bx, by + 16.0), guide_text, HORIZONTAL_ALIGNMENT_CENTER, bar_w, 10, Color(0.4, 0.92, 1.0))

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

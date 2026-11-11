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
		current_fps = clampf(fps if fps > 15.0 else 60.0, 58.0, 144.0)
		
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

func _draw_top_left_hud(ox: float, oy: float) -> void:
	draw_rect(Rect2(ox, oy, 185.0, 84.0), Color(0.06, 0.09, 0.14, 0.94))
	draw_rect(Rect2(ox, oy, 185.0, 84.0), Color(0.3, 0.5, 0.7, 0.95), false, 1.5)

	# 赤いエンブレムアイコン
	var emb_pos := Vector2(ox + 22.0, oy + 26.0)
	draw_circle(emb_pos, 15.0, Color(0.85, 0.25, 0.2, 0.9))
	draw_circle(emb_pos, 9.0, Color(0.08, 0.1, 0.14))
	draw_rect(Rect2(emb_pos.x - 2, emb_pos.y - 11, 4, 22), Color(0.9, 0.3, 0.25))
	draw_rect(Rect2(emb_pos.x - 11, emb_pos.y - 2, 22, 4), Color(0.9, 0.3, 0.25))

	# 右側のブロックゲージ
	var gx := ox + 48.0
	var gy1 := oy + 16.0
	var gy2 := oy + 28.0
	for i in range(10):
		var bx := gx + i * 11.5
		var col1 := Color(0.95, 0.45, 0.2) if i < 8 else Color(0.2, 0.25, 0.3)
		draw_rect(Rect2(bx, gy1, 9.5, 8.5), col1)
		var col2 := Color(0.2, 0.85, 0.95) if i < 9 else Color(0.2, 0.25, 0.3)
		draw_rect(Rect2(bx, gy2, 9.5, 8.5), col2)

	var font := ThemeDB.fallback_font
	var cycle_str := "CYCLE: 63:2E"
	if game_state != null and game_state.current_phase >= GameState.Phase.PHASE_3_INTERPLANETARY:
		cycle_str = "CYCLE: 93:32"
	draw_string(font, Vector2(ox + 10.0, oy + 50.0), cycle_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.95, 0.85, 0.3))
	draw_string(font, Vector2(ox + 90.0, oy + 50.0), "SHIELD: 100%", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.9, 1.0))

	# ⚡ エネルギーバー
	draw_string(font, Vector2(ox + 12.0, oy + 70.0), "⚡", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.3, 1.0, 0.5))
	var eg_x := ox + 32.0
	var eg_y := oy + 58.0
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
		draw_rect(Rect2(bx, eg_y, 9.5, 14.0), col)

func _draw_top_right_hud(ox: float, oy: float) -> void:
	draw_rect(Rect2(ox, oy, 195.0, 98.0), Color(0.06, 0.09, 0.14, 0.94))
	draw_rect(Rect2(ox, oy, 195.0, 98.0), Color(0.3, 0.5, 0.7, 0.95), false, 1.5)

	var font := ThemeDB.fallback_font
	
	var r_data := [
		{"label": "NANO", "icon": "🏺", "val": "1,986", "col": Color(0.4, 1.0, 0.6)},
		{"label": "ORE", "icon": "🪙", "val": "134,076", "col": Color(1.0, 0.85, 0.3)},
		{"label": "SILICON", "icon": "💠", "val": "34,620", "col": Color(0.3, 0.85, 1.0)},
		{"label": "FLEET", "icon": "🚀", "val": "699", "col": Color(1.0, 0.55, 0.85)}
	]

	for i in range(r_data.size()):
		var ry := oy + 21.0 + i * 21.0
		var item = r_data[i]
		draw_string(font, Vector2(ox + 8.0, ry), item["icon"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, item["col"])
		draw_string(font, Vector2(ox + 26.0, ry), item["label"] + ":", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.8, 0.9))
		draw_string(font, Vector2(ox + 98.0, ry), item["val"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.98, 0.98, 0.98))

func _draw_bottom_left_hud(ox: float, oy: float) -> void:
	draw_rect(Rect2(ox, oy, 190.0, 64.0), Color(0.06, 0.09, 0.14, 0.94))
	draw_rect(Rect2(ox, oy, 190.0, 64.0), Color(0.3, 0.5, 0.7, 0.95), false, 1.5)

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
	draw_rect(Rect2(ox, oy, 195.0, 64.0), Color(0.06, 0.09, 0.14, 0.94))
	draw_rect(Rect2(ox, oy, 195.0, 64.0), Color(0.3, 0.5, 0.7, 0.95), false, 1.5)

	var font := ThemeDB.fallback_font

	# ❄️ THERM
	draw_string(font, Vector2(ox + 8.0, oy + 26.0), "❄️ THERM", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.85, 1.0))
	draw_rect(Rect2(ox + 60.0, oy + 14.0, 80.0, 15.0), Color(0.18, 0.22, 0.26))
	draw_rect(Rect2(ox + 60.0, oy + 14.0, 80.0, 15.0), Color(0.2, 0.8, 0.95))
	draw_string(font, Vector2(ox + 145.0, oy + 26.0), "256/256", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1))

	# 📦 CARGO（完全に露出！）
	draw_string(font, Vector2(ox + 8.0, oy + 50.0), "📦 CARGO", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.65, 0.2))
	draw_rect(Rect2(ox + 60.0, oy + 38.0, 80.0, 15.0), Color(0.18, 0.22, 0.26))
	draw_rect(Rect2(ox + 60.0, oy + 38.0, 72.0, 15.0), Color(0.95, 0.6, 0.2))
	draw_string(font, Vector2(ox + 145.0, oy + 50.0), "86/96", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1))

func _draw_control_guide_bar(w: float, h: float) -> void:
	# 左右のHUDと干渉しない幅700pxの中央配置、面取りベベル付きSF装飾フレーム
	var bar_w := 700.0
	var bar_h := 32.0
	var bx := (w - bar_w) * 0.5
	var by := h - 44.0

	# メイン背景パネル
	draw_rect(Rect2(bx, by, bar_w, bar_h), Color(0.05, 0.08, 0.13, 0.96))
	draw_rect(Rect2(bx, by, bar_w, bar_h), Color(0.25, 0.65, 0.85, 0.9), false, 1.5)

	# 四隅のハイテク・ブラケット装飾
	var b_len := 6.0
	draw_line(Vector2(bx, by), Vector2(bx + b_len, by), Color(0.4, 0.95, 1.0), 2.0)
	draw_line(Vector2(bx, by), Vector2(bx, by + b_len), Color(0.4, 0.95, 1.0), 2.0)
	draw_line(Vector2(bx + bar_w, by), Vector2(bx + bar_w - b_len, by), Color(0.4, 0.95, 1.0), 2.0)
	draw_line(Vector2(bx + bar_w, by), Vector2(bx + bar_w, by + b_len), Color(0.4, 0.95, 1.0), 2.0)
	draw_line(Vector2(bx, by + bar_h), Vector2(bx + b_len, by + bar_h), Color(0.4, 0.95, 1.0), 2.0)
	draw_line(Vector2(bx, by + bar_h), Vector2(bx, by + bar_h - b_len), Color(0.4, 0.95, 1.0), 2.0)
	draw_line(Vector2(bx + bar_w, by + bar_h), Vector2(bx + bar_w - b_len, by + bar_h), Color(0.4, 0.95, 1.0), 2.0)
	draw_line(Vector2(bx + bar_w, by + bar_h), Vector2(bx + bar_w, by + bar_h - b_len), Color(0.4, 0.95, 1.0), 2.0)

	var font := ThemeDB.fallback_font
	var guide_text := "[A/D] MOVE  [W/SPACE] THRUST  [L-CLICK] MINE  [U] TECH TREE  [1~4] PHASE  FPS: " + str(int(current_fps))
	draw_string(font, Vector2(bx + 16.0, by + 21.0), guide_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.92, 1.0))

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

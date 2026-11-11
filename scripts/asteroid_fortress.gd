# asteroid_fortress.gd
class_name AsteroidFortress
extends Node2D

@export var core_pos: Vector2 = Vector2(4200.0, -900.0)
@export var base_radius: float = 280.0

var thruster_time: float = 0.0

# 飛来するキューブコンテナ
var cargo_cubes: Array[Dictionary] = []

# 周囲の戦闘ドローン＆ミサイル＆爆発＆ダメージ表示
var drone_units: Array[Dictionary] = []
var battle_lasers: Array[Dictionary] = []
var explosions: Array[Dictionary] = []
var damage_numbers: Array[Dictionary] = []
var thruster_sparks: Array[Dictionary] = []

var boss_shield_hp: float = 84.0
var boss_hit_flash: float = 0.0

func _ready() -> void:
	global_position = core_pos
	_init_drones()
	_init_cargo_cubes()

func _init_drones() -> void:
	# 激戦ドローン群（味方＆敵、36機）
	for i in range(36):
		var ang := randf() * TAU
		var dist := randf_range(230.0, 420.0)
		drone_units.append({
			"pos": Vector2(cos(ang), sin(ang)) * dist,
			"vel": Vector2(-sin(ang), cos(ang)) * randf_range(60.0, 130.0),
			"faction": "player" if i % 2 == 0 else "enemy",
			"fire_timer": randf_range(0.0, 0.7)
		})

func _init_cargo_cubes() -> void:
	for i in range(8):
		cargo_cubes.append({
			"t": float(i) / 8.0,
			"speed": 0.28
		})

func _process(delta: float) -> void:
	thruster_time += delta * 18.0
	if boss_hit_flash > 0.0:
		boss_hit_flash -= delta * 3.0

	# コンテナの移動
	for c in cargo_cubes:
		c["t"] += c["speed"] * delta
		if c["t"] >= 1.0:
			c["t"] -= 1.0

	# スラスター放電スパーク
	var angles := [-0.58, 0.58, PI - 0.58, PI + 0.58]
	for a in angles:
		if randf() < 0.4:
			var dir := Vector2(cos(a), sin(a))
			var perp := Vector2(-dir.y, dir.x)
			var base_p := dir * (base_radius + 180.0) + perp * randf_range(-20, 20)
			thruster_sparks.append({
				"pos": base_p,
				"vel": dir * randf_range(80.0, 160.0) + perp * randf_range(-30, 30),
				"life": 0.25,
				"max_life": 0.25
			})

	# ドローン戦闘AI
	for d in drone_units:
		d["pos"] += d["vel"] * delta
		var dist: float = (d["pos"] as Vector2).length()
		if dist < 210.0 or dist > 440.0:
			d["vel"] = -d["vel"]
			
		d["fire_timer"] += delta
		if d["fire_timer"] >= 0.38:
			d["fire_timer"] = 0.0
			var target_pos: Vector2 = (d["pos"] as Vector2) + Vector2(randf_range(-80, 80), randf_range(-80, 80))
			battle_lasers.append({
				"from": d["pos"],
				"to": target_pos,
				"col": Color(0.3, 0.95, 1.0) if d["faction"] == "player" else Color(1.0, 0.3, 0.25),
				"life": 0.16
			})
			# 爆発＆ダメージ数値ポップアップ
			if randf() < 0.32:
				explosions.append({
					"pos": target_pos,
					"life": 0.4,
					"max_life": 0.4
				})
				var dmg_val := randi_range(120, 310)
				var is_crit := (dmg_val > 250)
				damage_numbers.append({
					"pos": target_pos,
					"text": ("-" + str(dmg_val) + " CRIT") if is_crit else ("-" + str(dmg_val)),
					"col": Color(1.0, 0.95, 0.3) if is_crit else Color(1.0, 0.45, 0.4),
					"life": 0.7,
					"max_life": 0.7
				})
				boss_hit_flash = 0.25

	# リストの更新
	_update_life_list(battle_lasers, delta)
	_update_life_list(explosions, delta)
	_update_damage_numbers(delta)
	_update_sparks(delta)

	queue_redraw()

func _update_life_list(list: Array[Dictionary], delta: float) -> void:
	var i := 0
	while i < list.size():
		var item = list[i]
		item["life"] -= delta
		if item["life"] <= 0.0:
			list.remove_at(i)
		else:
			i += 1

func _update_damage_numbers(delta: float) -> void:
	var i := 0
	while i < damage_numbers.size():
		var item = damage_numbers[i]
		item["life"] -= delta
		item["pos"].y -= delta * 24.0
		if item["life"] <= 0.0:
			damage_numbers.remove_at(i)
		else:
			i += 1

func _update_sparks(delta: float) -> void:
	var i := 0
	while i < thruster_sparks.size():
		var item = thruster_sparks[i]
		item["life"] -= delta
		item["pos"] += item["vel"] * delta
		if item["life"] <= 0.0:
			thruster_sparks.remove_at(i)
		else:
			i += 1

func _draw() -> void:
	# 1. 4基の超巨大プラズマスラスター（多層ジェット・衝撃波ノード・火炎）
	_draw_giant_thrusters()

	# 2. 小惑星の外郭岩盤（陰影・立体クレーター）
	_draw_asteroid_crust()

	# 3. くり抜かれた内部空洞＆多層フロア＆緑の3連核融合キャニスター
	_draw_interior_plant()

	# 4. 月から伸びるマスドライバー射出ライン＆光るキューブコンテナ
	_draw_cargo_transport_beam()

	# 5. 周囲の戦闘ドローン＆直線レーザー＆爆発＆ダメージ数値
	_draw_drones_and_combat()

	# 6. ボスシールドHUD
	_draw_boss_hud()

func _draw_giant_thrusters() -> void:
	var angles := [-0.58, 0.58, PI - 0.58, PI + 0.58]
	for a in angles:
		var dir := Vector2(cos(a), sin(a))
		var perp := Vector2(-dir.y, dir.x)
		var base_p := dir * (base_radius - 12.0)

		# ヘビーノズル構造（金属ベゼル・放熱フィン）
		var n1 := base_p - perp * 32.0
		var n2 := base_p + perp * 32.0
		var n3 := base_p + dir * 46.0 + perp * 48.0
		var n4 := base_p + dir * 46.0 - perp * 48.0
		draw_colored_polygon(PackedVector2Array([n1, n2, n3, n4]), Color(0.24, 0.28, 0.35))
		draw_polyline(PackedVector2Array([n1, n2, n3, n4, n1]), Color(0.55, 0.65, 0.8), 2.5)

		# 映画的プラズマ火炎ジェット
		var flame_len := 220.0 + sin(thruster_time + a * 4.0) * 45.0
		var f_tip := base_p + dir * (46.0 + flame_len)
		var f_left := base_p + dir * 46.0 - perp * 44.0
		var f_right := base_p + dir * 46.0 + perp * 44.0

		# 1. 外層広域青光グロー（コバルトブルー）
		draw_colored_polygon(PackedVector2Array([f_left, f_right, f_tip]), Color(0.12, 0.45, 1.0, 0.45))

		# 2. 中層エレクトリックシアン
		var f_mid_tip := base_p + dir * (46.0 + flame_len * 0.82)
		draw_colored_polygon(PackedVector2Array([
			base_p + dir * 46.0 - perp * 28.0,
			base_p + dir * 46.0 + perp * 28.0,
			f_mid_tip
		]), Color(0.25, 0.9, 1.0, 0.85))

		# 3. 中心白熱プラズマコア
		var f_core_tip := base_p + dir * (46.0 + flame_len * 0.58)
		draw_colored_polygon(PackedVector2Array([
			base_p + dir * 46.0 - perp * 14.0,
			base_p + dir * 46.0 + perp * 14.0,
			f_core_tip
		]), Color(0.95, 0.98, 1.0, 0.98))

		# 4. マッハ衝撃波ダイヤモンド（Mach Shock Diamonds）
		for d_idx in range(1, 4):
			var d_center := base_p + dir * (46.0 + d_idx * (flame_len * 0.18))
			var d_rad := 12.0 - d_idx * 2.5
			var diamond := PackedVector2Array([
				d_center + dir * d_rad,
				d_center + perp * (d_rad * 0.65),
				d_center - dir * d_rad,
				d_center - perp * (d_rad * 0.65)
			])
			draw_colored_polygon(diamond, Color(1, 1, 1, 0.95))
			draw_polyline(diamond, Color(0.4, 0.95, 1.0), 1.5)

	# スラスター放電スパーク
	for sp in thruster_sparks:
		var a: float = sp["life"] / sp["max_life"]
		draw_circle(sp["pos"], 2.5 * a, Color(0.3, 0.95, 1.0, a))

func _draw_asteroid_crust() -> void:
	var pts := PackedVector2Array()
	var steps := 44
	for i in range(steps):
		var a := float(i) / float(steps) * TAU
		var noise := sin(a * 6.0) * 16.0 + cos(a * 11.0) * 11.0
		var r := base_radius + noise
		pts.append(Vector2(cos(a), sin(a)) * r)
	# 立体的な陰影岩肌（左上ハイライト、右下シャドウ）
	draw_colored_polygon(pts, Color(0.18, 0.2, 0.24))
	draw_polyline(pts, Color(0.45, 0.5, 0.58), 3.5)

	# クレーター陰影
	for c_angle in [-1.2, 0.3, 1.5, 2.6]:
		var cp := Vector2(cos(c_angle), sin(c_angle)) * (base_radius * 0.75)
		draw_circle(cp, 24.0, Color(0.12, 0.13, 0.16))
		draw_arc(cp, 24.0, -PI*0.3, PI*0.6, 12, Color(0.5, 0.55, 0.65), 2.0)

	# 外殻に設置された対空タレット砲台
	for t_angle in [-0.9, 0.0, 0.9, 2.2]:
		var tp := Vector2(cos(t_angle), sin(t_angle)) * base_radius
		var t_dir := Vector2(cos(t_angle), sin(t_angle))
		draw_rect(Rect2(tp.x - 8, tp.y - 8, 16, 16), Color(0.3, 0.35, 0.42))
		draw_line(tp, tp + t_dir * 18.0, Color(0.7, 0.8, 0.95), 4.0)

func _draw_interior_plant() -> void:
	# 内部空洞
	var cav_pts := PackedVector2Array()
	var steps := 36
	for i in range(steps):
		var a := float(i) / float(steps) * TAU
		var noise := sin(a * 5.0) * 9.0
		var r := (base_radius - 48.0) + noise
		cav_pts.append(Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(cav_pts, Color(0.06, 0.08, 0.11))

	# 鉄骨足場＆多層デッキ
	for y_off in [-60.0, -10.0, 45.0]:
		draw_line(Vector2(-110, y_off), Vector2(110, y_off), Color(0.35, 0.45, 0.55), 4.0)
		# イエロー＆ブラック警告ハザードストライプ
		for hx in range(-100, 100, 18):
			draw_line(Vector2(hx, y_off - 1), Vector2(hx + 8, y_off - 1), Color(1.0, 0.85, 0.2), 2.0)
		for x_off in range(-95, 105, 26):
			draw_line(Vector2(x_off, y_off), Vector2(x_off, y_off + 26), Color(0.24, 0.32, 0.42), 2.0)

	# 3本の大型放射性緑色核融合キャニスター
	for c_idx in range(3):
		var cx := -32.0 + c_idx * 32.0
		var cy := -30.0
		# 金属フレーム
		draw_rect(Rect2(cx - 12, cy - 30, 24, 60), Color(0.12, 0.16, 0.2))
		draw_rect(Rect2(cx - 12, cy - 30, 24, 60), Color(0.45, 0.7, 0.6), false, 2.0)
		# 輝く緑の放射性液体
		draw_rect(Rect2(cx - 9, cy - 24, 18, 48), Color(0.2, 1.0, 0.45, 0.95))
		# 発光ハイライト光
		draw_line(Vector2(cx - 5, cy - 22), Vector2(cx - 5, cy + 22), Color(0.85, 1.0, 0.9), 2.5)
		draw_circle(Vector2(cx, cy - 26), 4.5, Color(0.3, 1.0, 0.6))

	# 司令ブリッジ・制御コンソールモニタ
	draw_rect(Rect2(-90, 8, 42, 34), Color(0.25, 0.3, 0.4))
	draw_circle(Vector2(-72, 24), 8.0, Color(0.2, 0.9, 1.0, 0.95))
	draw_rect(Rect2(52, 12, 45, 30), Color(0.35, 0.28, 0.24))
	draw_circle(Vector2(74, 26), 7.0, Color(1.0, 0.65, 0.2, 0.95))

func _draw_cargo_transport_beam() -> void:
	# 月から小惑星要塞への電磁搬送ビーム
	var start_p := Vector2(-1800, 0)
	var end_p := Vector2(-base_radius - 25, 0)

	# シアン点線ビームライン
	var segs := 36
	for s in range(segs):
		var t1 := float(s) / float(segs)
		var t2 := float(s + 0.5) / float(segs)
		var p1 := start_p.lerp(end_p, t1)
		var p2 := start_p.lerp(end_p, t2)
		draw_line(p1, p2, Color(0.2, 0.9, 1.0, 0.65), 2.5)

	# 軌道ロック鍵マーク
	var lock_p := start_p.lerp(end_p, 0.74)
	draw_rect(Rect2(lock_p.x - 10, lock_p.y - 6, 20, 18), Color(0.15, 0.85, 1.0))
	draw_arc(Vector2(lock_p.x, lock_p.y - 6), 8.0, PI, TAU, 16, Color(0.15, 0.85, 1.0), 2.5)

	# 光るキューブ貨物コンテナ
	for c in cargo_cubes:
		var cp := start_p.lerp(end_p, c["t"])
		draw_rect(Rect2(cp.x - 11, cp.y - 11, 22, 22), Color(0.25, 0.95, 1.0, 0.95), false, 2.5)
		draw_rect(Rect2(cp.x - 9, cp.y - 9, 18, 18), Color(0.08, 0.22, 0.35, 0.92))
		draw_circle(cp, 6.0, Color(0.85, 1.0, 1.0, 0.98))

func _draw_drones_and_combat() -> void:
	# 戦闘ドローン
	for d in drone_units:
		var pos: Vector2 = d["pos"]
		var forward := (d["vel"] as Vector2).normalized()
		var perp := Vector2(-forward.y, forward.x)
		var col := Color(0.3, 0.95, 1.0) if d["faction"] == "player" else Color(1.0, 0.35, 0.3)

		var p1 := pos + forward * 10.0
		var p2 := pos - forward * 7.0 + perp * 7.0
		var p3 := pos - forward * 7.0 - perp * 7.0
		draw_colored_polygon(PackedVector2Array([p1, p2, p3]), col)
		draw_polyline(PackedVector2Array([p1, p2, p3, p1]), Color(1, 1, 1), 1.2)

	# 直線レーザービーム
	for l in battle_lasers:
		draw_line(l["from"], l["to"], l["col"], 2.5)

	# 爆発閃光
	for ex in explosions:
		var alpha: float = ex["life"] / ex["max_life"]
		draw_circle(ex["pos"], 16.0 * (1.5 - alpha), Color(1.0, 0.6, 0.2, alpha * 0.8))
		draw_circle(ex["pos"], 7.0, Color(1.0, 0.95, 0.5, alpha))

	# 浮遊ダメージ数値
	var font := ThemeDB.fallback_font
	for dmg in damage_numbers:
		var a: float = dmg["life"] / dmg["max_life"]
		var col: Color = dmg["col"]
		col.a = a
		draw_string(font, dmg["pos"], dmg["text"], HORIZONTAL_ALIGNMENT_CENTER, 80, 11, col)

func _draw_boss_hud() -> void:
	var font := ThemeDB.fallback_font
	var bx := -180.0
	var by := -base_radius - 75.0
	var bw := 360.0

	# 敵母艦シールドHUD
	draw_rect(Rect2(bx, by, bw, 26), Color(0.08, 0.04, 0.06, 0.92))
	var border_col := Color(1.0, 0.9, 0.9) if boss_hit_flash > 0.0 else Color(0.9, 0.25, 0.3, 0.85)
	draw_rect(Rect2(bx, by, bw, 26), border_col, false, 1.5)

	draw_string(font, Vector2(bx + 12, by + 17), "⚠ HOSTILE MOTHER-HIVE: APEX SWARM", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.45, 0.45))
	draw_string(font, Vector2(bx + bw - 95, by + 17), "SHIELD: 84%", HORIZONTAL_ALIGNMENT_RIGHT, -1, 10, Color(0.3, 0.9, 1.0))

	# シールドゲージバー
	draw_rect(Rect2(bx + 4, by + 21, bw - 8, 3), Color(0.2, 0.05, 0.08))
	draw_rect(Rect2(bx + 4, by + 21, (bw - 8) * (boss_shield_hp / 100.0), 3), Color(0.3, 0.95, 1.0))

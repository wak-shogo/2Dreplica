# asteroid_fortress.gd
class_name AsteroidFortress
extends Node2D

@export var core_pos: Vector2 = Vector2(2650.0, -930.0)
@export var base_radius: float = 185.0

var thruster_time: float = 0.0

# 飛来するキューブコンテナ
var cargo_cubes: Array[Dictionary] = []

# 周囲の戦闘ドローン＆ミサイル＆爆発
var drone_units: Array[Dictionary] = []
var battle_lasers: Array[Dictionary] = []
var explosions: Array[Dictionary] = []

func _ready() -> void:
	global_position = core_pos
	_init_drones()
	_init_cargo_cubes()

func _init_drones() -> void:
	# 画像4の激戦ドローン群（味方＆敵、32機）
	for i in range(32):
		var ang := randf() * TAU
		var dist := randf_range(210.0, 360.0)
		drone_units.append({
			"pos": Vector2(cos(ang), sin(ang)) * dist,
			"vel": Vector2(-sin(ang), cos(ang)) * randf_range(50.0, 110.0),
			"faction": "player" if i % 2 == 0 else "enemy",
			"fire_timer": randf_range(0.0, 0.8)
		})

func _init_cargo_cubes() -> void:
	for i in range(8):
		cargo_cubes.append({
			"t": float(i) / 8.0,
			"speed": 0.28
		})

func _process(delta: float) -> void:
	thruster_time += delta * 18.0
	
	# コンテナの移動
	for c in cargo_cubes:
		c["t"] += c["speed"] * delta
		if c["t"] >= 1.0:
			c["t"] -= 1.0

	# ドローン戦闘AI
	for d in drone_units:
		d["pos"] += d["vel"] * delta
		var dist: float = (d["pos"] as Vector2).length()
		if dist < 200.0 or dist > 380.0:
			d["vel"] = -d["vel"]
			
		d["fire_timer"] += delta
		if d["fire_timer"] >= 0.45:
			d["fire_timer"] = 0.0
			var target_pos: Vector2 = (d["pos"] as Vector2) + Vector2(randf_range(-70, 70), randf_range(-70, 70))
			battle_lasers.append({
				"from": d["pos"],
				"to": target_pos,
				"col": Color(1.0, 0.88, 0.25) if d["faction"] == "player" else Color(1.0, 0.25, 0.2),
				"life": 0.14
			})
			# 稀に爆発
			if randf() < 0.25:
				explosions.append({
					"pos": target_pos,
					"life": 0.35,
					"max_life": 0.35
				})

	var i := 0
	while i < battle_lasers.size():
		var l = battle_lasers[i]
		l["life"] -= delta
		if l["life"] <= 0.0:
			battle_lasers.remove_at(i)
		else:
			i += 1

	var j := 0
	while j < explosions.size():
		var ex = explosions[j]
		ex["life"] -= delta
		if ex["life"] <= 0.0:
			explosions.remove_at(j)
		else:
			j += 1

	queue_redraw()

func _draw() -> void:
	# 1. 4基の超巨大プラズマスラスター（猛烈な青白いプラズマ火炎ジェット）
	_draw_giant_thrusters()

	# 2. 小惑星の外郭岩盤（ゴツゴツした岩肌・陰影）
	_draw_asteroid_crust()

	# 3. くり抜かれた内部空洞＆足場＆緑の3連核融合キャニスター
	_draw_interior_plant()

	# 4. 月から伸びるマスドライバー射出ライン＆光るキューブコンテナ
	_draw_cargo_transport_beam()

	# 5. 周囲の戦闘ドローン＆直線レーザー＆爆発閃光
	_draw_drones_and_combat()

func _draw_giant_thrusters() -> void:
	# 4基のスラスター（角度：右斜め上、右斜め下、左斜め上、左斜め下）
	var angles := [-0.58, 0.58, PI - 0.58, PI + 0.58]
	for a in angles:
		var dir := Vector2(cos(a), sin(a))
		var perp := Vector2(-dir.y, dir.x)
		var base_p := dir * (base_radius - 12.0)

		# ヘビーノズル構造
		var n1 := base_p - perp * 30.0
		var n2 := base_p + perp * 30.0
		var n3 := base_p + dir * 42.0 + perp * 45.0
		var n4 := base_p + dir * 42.0 - perp * 45.0
		draw_colored_polygon(PackedVector2Array([n1, n2, n3, n4]), Color(0.22, 0.25, 0.32))
		draw_polyline(PackedVector2Array([n1, n2, n3, n4, n1]), Color(0.5, 0.6, 0.75), 2.5)

		# 猛烈な青白いプラズマ火炎ジェット（画像4完全再現）
		var flame_len := 190.0 + sin(thruster_time + a * 4.0) * 35.0
		var f_tip := base_p + dir * (42.0 + flame_len)
		var f_left := base_p + dir * 42.0 - perp * 40.0
		var f_right := base_p + dir * 42.0 + perp * 40.0

		# 外層青光グロー
		draw_colored_polygon(PackedVector2Array([f_left, f_right, f_tip]), Color(0.15, 0.55, 1.0, 0.7))
		# 内層シアン
		var f_mid_tip := base_p + dir * (42.0 + flame_len * 0.8)
		draw_colored_polygon(PackedVector2Array([
			base_p + dir * 42.0 - perp * 26.0,
			base_p + dir * 42.0 + perp * 26.0,
			f_mid_tip
		]), Color(0.4, 0.85, 1.0, 0.9))
		# 中心高輝度白色コア＆衝撃波ダイヤモンド
		var f_core_tip := base_p + dir * (42.0 + flame_len * 0.55)
		draw_colored_polygon(PackedVector2Array([
			base_p + dir * 42.0 - perp * 14.0,
			base_p + dir * 42.0 + perp * 14.0,
			f_core_tip
		]), Color(0.95, 0.98, 1.0, 0.98))
		# 衝撃波ノード
		draw_circle(base_p + dir * (42.0 + flame_len * 0.3), 8.0, Color(1, 1, 1, 0.9))

func _draw_asteroid_crust() -> void:
	var pts := PackedVector2Array()
	var steps := 40
	for i in range(steps):
		var a := float(i) / float(steps) * TAU
		var noise := sin(a * 6.0) * 15.0 + cos(a * 11.0) * 10.0
		var r := base_radius + noise
		pts.append(Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, Color(0.16, 0.18, 0.2))
	draw_polyline(pts, Color(0.42, 0.46, 0.52), 3.5)

func _draw_interior_plant() -> void:
	# 内部空洞
	var cav_pts := PackedVector2Array()
	var steps := 32
	for i in range(steps):
		var a := float(i) / float(steps) * TAU
		var noise := sin(a * 5.0) * 9.0
		var r := (base_radius - 45.0) + noise
		cav_pts.append(Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(cav_pts, Color(0.06, 0.08, 0.1))

	# 鉄骨足場＆梁グリッド
	for y_off in [-55.0, -5.0, 48.0]:
		draw_line(Vector2(-105, y_off), Vector2(105, y_off), Color(0.32, 0.42, 0.52), 3.5)
		for x_off in range(-95, 105, 28):
			draw_line(Vector2(x_off, y_off), Vector2(x_off, y_off + 28), Color(0.22, 0.3, 0.38), 1.8)

	# 3本の大型緑色核融合キャニスター（画像4完全再現）
	for c_idx in range(3):
		var cx := -30.0 + c_idx * 30.0
		var cy := -25.0
		draw_rect(Rect2(cx - 11, cy - 28, 22, 56), Color(0.12, 0.16, 0.2))
		draw_rect(Rect2(cx - 11, cy - 28, 22, 56), Color(0.45, 0.65, 0.55), false, 2.0)
		# 輝く緑の液体
		draw_rect(Rect2(cx - 8, cy - 22, 16, 44), Color(0.2, 1.0, 0.45, 0.95))
		# 発光ハイライト光
		draw_line(Vector2(cx - 4, cy - 20), Vector2(cx - 4, cy + 20), Color(0.85, 1.0, 0.9), 2.0)
		draw_circle(Vector2(cx, cy - 24), 4.0, Color(0.3, 1.0, 0.6))

	# 制御ブロック・炉心モニタ
	draw_rect(Rect2(-85, 12, 38, 32), Color(0.28, 0.32, 0.42))
	draw_circle(Vector2(-68, 28), 7.0, Color(0.2, 0.9, 1.0, 0.9))
	draw_rect(Rect2(48, 16, 42, 28), Color(0.38, 0.28, 0.24))
	draw_circle(Vector2(68, 28), 6.0, Color(1.0, 0.65, 0.2, 0.95))

func _draw_cargo_transport_beam() -> void:
	# 月（Vector2(-1200, 0)）から小惑星要塞（Vector2(-base_radius - 20, 0)）
	var start_p := Vector2(-1200, 0)
	var end_p := Vector2(-base_radius - 25, 0)

	# 点線ビームライン
	var segs := 32
	for s in range(segs):
		var t1 := float(s) / float(segs)
		var t2 := float(s + 0.5) / float(segs)
		var p1 := start_p.lerp(end_p, t1)
		var p2 := start_p.lerp(end_p, t2)
		draw_line(p1, p2, Color(0.2, 0.9, 1.0, 0.6), 2.0)

	# 軌道ロック鍵マーク（画像4のシアンの鍵）
	var lock_p := start_p.lerp(end_p, 0.74)
	draw_rect(Rect2(lock_p.x - 9, lock_p.y - 5, 18, 16), Color(0.15, 0.85, 1.0))
	draw_arc(Vector2(lock_p.x, lock_p.y - 5), 7.0, PI, TAU, 16, Color(0.15, 0.85, 1.0), 2.5)

	# 青白く発光するキューブ貨物コンテナ
	for c in cargo_cubes:
		var cp := start_p.lerp(end_p, c["t"])
		draw_rect(Rect2(cp.x - 10, cp.y - 10, 20, 20), Color(0.25, 0.95, 1.0, 0.95), false, 2.5)
		draw_rect(Rect2(cp.x - 8, cp.y - 8, 16, 16), Color(0.08, 0.22, 0.35, 0.9))
		draw_circle(cp, 5.0, Color(0.85, 1.0, 1.0, 0.98))

func _draw_drones_and_combat() -> void:
	# 戦闘ドローン（三角形、画像4完全再現）
	for d in drone_units:
		var pos: Vector2 = d["pos"]
		var forward := (d["vel"] as Vector2).normalized()
		var perp := Vector2(-forward.y, forward.x)
		var col := Color(1.0, 0.88, 0.25) if d["faction"] == "player" else Color(1.0, 0.3, 0.3)

		var p1 := pos + forward * 9.0
		var p2 := pos - forward * 6.0 + perp * 6.0
		var p3 := pos - forward * 6.0 - perp * 6.0
		draw_colored_polygon(PackedVector2Array([p1, p2, p3]), col)

	# 直線レーザービーム
	for l in battle_lasers:
		draw_line(l["from"], l["to"], l["col"], 2.2)

	# 爆発閃光
	for ex in explosions:
		var alpha: float = ex["life"] / ex["max_life"]
		draw_circle(ex["pos"], 14.0 * (1.5 - alpha), Color(1.0, 0.6, 0.2, alpha * 0.8))
		draw_circle(ex["pos"], 6.0, Color(1.0, 0.95, 0.5, alpha))

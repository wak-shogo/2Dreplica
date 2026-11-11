# asteroid_view.gd
class_name AsteroidView
extends Node2D

var game_state: GameState = null
var backdrop_tex: Texture2D = null

# アステロイド要塞の中心
var fortress_center: Vector2 = Vector2(1060.0, 365.0)

# スラスター炎の脈動タイマー＆プラズマ火花
var flame_timer: float = 0.0
var thruster_sparks: Array[Dictionary] = []

# 戦闘ドローン艦隊戦（画像4完全再現）
var combat_drones: Array[Dictionary] = []
var combat_lasers: Array[Dictionary] = []
var combat_explosions: Array[Dictionary] = []
var scrap_debris: Array[Dictionary] = []
var battle_timer: float = 0.0

# マスドライバーエネルギーパルス
var pulse_offsets: Array[float] = [0.1, 0.35, 0.6, 0.85]

func setup(p_game_state: GameState) -> void:
	game_state = p_game_state
	backdrop_tex = load("res://assets/textures/tex_massdriver_asteroid_backdrop.png")
	_init_combat_drones()

func _init_combat_drones() -> void:
	combat_drones.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 98765

	# 味方（黄色・シアン）ドローン 8機
	for i in range(8):
		combat_drones.append({
			"pos": fortress_center + Vector2(rng.randf_range(-220, 100), rng.randf_range(-180, 180)),
			"vel": Vector2(rng.randf_range(-45, 45), rng.randf_range(-45, 45)),
			"team": "ally",
			"col": Color(1.0, 0.85, 0.3) if i % 2 == 0 else Color(0.3, 0.9, 1.0),
			"fire_cd": rng.randf_range(0.2, 1.2)
		})

	# 敵性自己複製機（赤・マゼンタ）ドローン 8機
	for j in range(8):
		combat_drones.append({
			"pos": fortress_center + Vector2(rng.randf_range(-280, -80), rng.randf_range(-220, 220)),
			"vel": Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40)),
			"team": "enemy",
			"col": Color(1.0, 0.25, 0.25),
			"fire_cd": rng.randf_range(0.3, 1.5)
		})

func _process(delta: float) -> void:
	if not visible:
		return

	flame_timer += delta * 12.0

	# マスドライバーエネルギーパルスの進行
	for i in range(pulse_offsets.size()):
		pulse_offsets[i] += delta * 0.22
		if pulse_offsets[i] > 1.0:
			pulse_offsets[i] -= 1.0

	# 4連スラスターからのプラズマ噴射スパーク
	var thruster_nozzles := [
		{"pos": Vector2(880.0, 260.0), "dir": Vector2(-1.0, -0.65).normalized()},
		{"pos": Vector2(880.0, 470.0), "dir": Vector2(-1.0, 0.65).normalized()},
		{"pos": Vector2(1170.0, 240.0), "dir": Vector2(1.0, -0.65).normalized()},
		{"pos": Vector2(1170.0, 490.0), "dir": Vector2(1.0, 0.65).normalized()}
	]
	for th in thruster_nozzles:
		if randf() > 0.4:
			thruster_sparks.append({
				"pos": th["pos"] + th["dir"] * randf_range(10, 80) + Vector2(randf_range(-12, 12), randf_range(-12, 12)),
				"vel": th["dir"] * randf_range(120, 260) + Vector2(randf_range(-25, 25), randf_range(-25, 25)),
				"col": Color(0.4, 0.85, 1.0, 0.9) if randf() > 0.3 else Color(1.0, 1.0, 1.0, 0.95),
				"life": 0.45, "max_life": 0.45, "size": randf_range(2.0, 4.0)
			})

	# スラスター火花更新
	var keep_sp: Array[Dictionary] = []
	for sp in thruster_sparks:
		sp["life"] -= delta
		if sp["life"] > 0.0:
			sp["pos"] += sp["vel"] * delta
			keep_sp.append(sp)
	thruster_sparks = keep_sp

	# 戦闘ドローンAIとレーザー発射
	battle_timer += delta
	for d in combat_drones:
		d["pos"] += d["vel"] * delta
		var to_center: Vector2 = fortress_center - d["pos"]
		if to_center.length() > 280.0:
			d["vel"] = d["vel"].lerp(to_center.normalized() * 55.0, delta * 3.0)

		d["fire_cd"] -= delta
		if d["fire_cd"] <= 0.0:
			d["fire_cd"] = randf_range(0.8, 2.2)
			var target_dir := Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
			combat_lasers.append({
				"start": d["pos"],
				"end": d["pos"] + target_dir * randf_range(60, 130),
				"col": d["col"],
				"life": 0.22, "max_life": 0.22
			})
			if randf() > 0.65:
				_spawn_explosion(d["pos"] + target_dir * randf_range(40, 80))

	# レーザー更新
	var keep_lasers: Array[Dictionary] = []
	for l in combat_lasers:
		l["life"] -= delta
		if l["life"] > 0.0:
			keep_lasers.append(l)
	combat_lasers = keep_lasers

	# 爆発更新
	var keep_exp: Array[Dictionary] = []
	for exp in combat_explosions:
		exp["life"] -= delta
		if exp["life"] > 0.0:
			exp["radius"] += delta * 35.0
			keep_exp.append(exp)
	combat_explosions = keep_exp

	# 金属スクラップ・デブリ更新
	var keep_deb: Array[Dictionary] = []
	for deb in scrap_debris:
		deb["life"] -= delta
		if deb["life"] > 0.0:
			deb["pos"] += deb["vel"] * delta
			deb["rot"] += deb["rot_speed"] * delta
			keep_deb.append(deb)
	scrap_debris = keep_deb

	queue_redraw()

func _spawn_explosion(pos: Vector2) -> void:
	combat_explosions.append({
		"pos": pos,
		"radius": 4.0,
		"max_radius": randf_range(12.0, 18.0),
		"life": 0.35,
		"max_life": 0.35
	})
	# 撃破金属片（回収可能デブリの演出）
	for i in range(5):
		scrap_debris.append({
			"pos": pos,
			"vel": Vector2(randf_range(-60, 60), randf_range(-60, 60)),
			"rot": randf_range(0, TAU),
			"rot_speed": randf_range(-8.0, 8.0),
			"size": randf_range(1.5, 3.5),
			"life": 1.4, "max_life": 1.4
		})

func _draw() -> void:
	if not visible:
		return

	# 1. 高品位HD-2D小惑星要塞＆月面背景（画像4完全再現）
	if backdrop_tex != null:
		draw_texture_rect(backdrop_tex, Rect2(0, 0, 1280, 720), false)
	else:
		draw_rect(Rect2(0, 0, 1280, 720), Color(0.04, 0.05, 0.08))

	# 2. 4連スラスターのプラズマ火花＆マッハダイヤモンド動的グロー
	_draw_thruster_vfx()

	# 3. マスドライバーの電磁誘導グローパルス（既存の美しい破線弾道に沿って移動）
	_draw_massdriver_pulses()

	# 4. 要塞内部の3連核融合キャニスター（グリーンの液体光彩）
	_draw_fusion_canisters()

	# 5. ドローン艦隊戦（レーザー軌跡＆爆発）
	_draw_fleet_battle()

func _draw_thruster_vfx() -> void:
	var pulse := 0.85 + sin(flame_timer) * 0.15

	# スラスターノズル位置と方向
	var thruster_nozzles := [
		{"pos": Vector2(880.0, 260.0), "dir": Vector2(-1.0, -0.65).normalized()},
		{"pos": Vector2(880.0, 470.0), "dir": Vector2(-1.0, 0.65).normalized()},
		{"pos": Vector2(1170.0, 240.0), "dir": Vector2(1.0, -0.65).normalized()},
		{"pos": Vector2(1170.0, 490.0), "dir": Vector2(1.0, 0.65).normalized()}
	]

	for th in thruster_nozzles:
		var p: Vector2 = th["pos"]
		var d: Vector2 = th["dir"]
		# ノズル根本の超高温ホワイトグロー
		draw_circle(p, 16.0 * pulse, Color(0.3, 0.8, 1.0, 0.35))
		draw_circle(p, 8.0 * pulse, Color(1.0, 1.0, 1.0, 0.75))

		# マッハダイヤモンド衝撃波ノード
		for md in range(1, 4):
			var node_p: Vector2 = p + d * (md * 32.0 * pulse)
			draw_circle(node_p, 5.0 * (1.0 - md * 0.2), Color(0.5, 0.9, 1.0, 0.6))
			draw_circle(node_p, 2.5, Color(1.0, 1.0, 1.0, 0.85))

	# 飛散するプラズマ火花パーティクル
	for sp in thruster_sparks:
		var a: float = sp["life"] / sp["max_life"]
		var c: Color = sp["col"]
		c.a = a
		draw_circle(sp["pos"], sp["size"], c)

func _draw_massdriver_pulses() -> void:
	# 月面マスドライバー砲口 (520, 200) から 要塞 (920, 200) へのベジェ曲線
	var p0 := Vector2(520.0, 195.0)
	var p1 := Vector2(720.0, 175.0)
	var p2 := Vector2(920.0, 200.0)

	for t in pulse_offsets:
		var p := (1.0 - t) * (1.0 - t) * p0 + 2.0 * (1.0 - t) * t * p1 + t * t * p2
		draw_circle(p, 5.0, Color(0.3, 0.95, 1.0, 0.5))
		draw_circle(p, 2.5, Color(1.0, 1.0, 1.0, 0.9))

func _draw_fusion_canisters() -> void:
	# 要塞内部の3連グリーンキャニスター (x: 1040, 1060, 1080, y: 345)
	var can_pulse := 0.75 + sin(Time.get_ticks_msec() * 0.008) * 0.25
	var xs := [1040.0, 1060.0, 1080.0]
	for cx in xs:
		draw_rect(Rect2(cx - 5, 335, 10, 22), Color(0.1, 0.9, 0.35, 0.75 * can_pulse))
		draw_circle(Vector2(cx, 346), 4.0, Color(0.5, 1.0, 0.7, can_pulse))

func _draw_fleet_battle() -> void:
	# レーザー軌跡
	for l in combat_lasers:
		var a: float = l["life"] / l["max_life"]
		var c: Color = l["col"]
		c.a = a
		draw_line(l["start"], l["end"], c, 1.5)

	# 被弾爆発
	for exp in combat_explosions:
		var a: float = exp["life"] / exp["max_life"]
		draw_circle(exp["pos"], exp["radius"], Color(1.0, 0.55, 0.1, a * 0.7))
		draw_circle(exp["pos"], exp["radius"] * 0.5, Color(1.0, 0.9, 0.3, a * 0.9))

	# 飛散する金属スクラップ・デブリ（微小回転ポリゴン）
	for deb in scrap_debris:
		var da: float = deb["life"] / deb["max_life"]
		var dp: Vector2 = deb["pos"]
		var sz: float = deb["size"]
		var drot: float = deb["rot"]
		var dpoly: PackedVector2Array = [
			dp + Vector2(cos(drot), sin(drot)) * sz,
			dp + Vector2(cos(drot + 2.0), sin(drot + 2.0)) * sz,
			dp + Vector2(cos(drot + 4.0), sin(drot + 4.0)) * sz
		]
		draw_colored_polygon(dpoly, Color(0.7, 0.75, 0.85, da * 0.9))
		draw_polyline(dpoly, Color(0.4, 0.8, 1.0, da * 0.6), 1.0)

	# 戦闘ドローン本体（戦況ハイライト・アンビエント光輪付き）
	for d in combat_drones:
		var dp: Vector2 = d["pos"]
		var c: Color = d["col"]
		var vel: Vector2 = d.get("vel", Vector2.RIGHT)
		var fwd := vel.normalized() if vel.length() > 0.1 else Vector2.RIGHT

		# 周囲のアンビエント発光（交戦視認性向上）
		draw_circle(dp, 7.5, Color(c.r, c.g, c.b, 0.28))
		# ドローン本体
		draw_circle(dp, 3.5, c)
		draw_circle(dp, 1.8, Color(1.0, 1.0, 1.0, 0.95))
		# 進行方向シェブロン・インジケータ
		draw_line(dp + fwd * 4.0, dp + fwd * 6.5, Color(c.r, c.g, c.b, 0.8), 1.2)

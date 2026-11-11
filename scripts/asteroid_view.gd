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

	# 4連超巨大スラスターからの高輝度プラズマ＆化学火炎スパーク（左側：青白プラズマ、右側：超高温オレンジ火炎）
	var thruster_nozzles := [
		{"pos": Vector2(925.0, 290.0), "dir": Vector2(-0.85, -0.52).normalized(), "is_fire": false}, # 左上：青白プラズマ
		{"pos": Vector2(935.0, 460.0), "dir": Vector2(-0.82, 0.57).normalized(), "is_fire": false},  # 左下：青白プラズマ
		{"pos": Vector2(1160.0, 240.0), "dir": Vector2(0.85, -0.52).normalized(), "is_fire": true},  # 右上：オレンジ化学火炎
		{"pos": Vector2(1160.0, 470.0), "dir": Vector2(0.82, 0.57).normalized(), "is_fire": true}   # 右下：オレンジ化学火炎
	]
	for th in thruster_nozzles:
		for k in range(3):
			var spark_col := Color(1.0, randf_range(0.45, 0.85), 0.1, 0.98) if th["is_fire"] else (Color(0.35, 0.85, 1.0, 0.95) if randf() > 0.25 else Color(1.0, 1.0, 1.0, 0.98))
			thruster_sparks.append({
				"pos": th["pos"] + th["dir"] * randf_range(10, 60) + Vector2(randf_range(-8, 8), randf_range(-8, 8)),
				"vel": th["dir"] * randf_range(240, 480) + Vector2(randf_range(-30, 30), randf_range(-30, 30)),
				"col": spark_col,
				"life": 0.35, "max_life": 0.35, "size": randf_range(2.0, 4.5)
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
	var pulse := 0.88 + sin(flame_timer) * 0.12

	# 4連超巨大スラスターノズル位置と噴射ベクトル（画像4：左2基はシアン超光速プラズマ、右2基は白熱オレンジ化学火炎）
	# 左右とも均質で滑らかなプラズマ炎コーン＋ソフトなアナモルフィック光彩で統一
	var thruster_nozzles := [
		{"pos": Vector2(925.0, 290.0), "dir": Vector2(-0.85, -0.52).normalized(), "is_fire": false}, # 左上：イオン
		{"pos": Vector2(935.0, 460.0), "dir": Vector2(-0.82, 0.57).normalized(), "is_fire": false},  # 左下：イオン
		{"pos": Vector2(1160.0, 240.0), "dir": Vector2(0.85, -0.52).normalized(), "is_fire": true},  # 右上：化学火炎
		{"pos": Vector2(1160.0, 470.0), "dir": Vector2(0.82, 0.57).normalized(), "is_fire": true}   # 右下：化学火炎
	]

	for th in thruster_nozzles:
		var p: Vector2 = th["pos"]
		var d: Vector2 = th["dir"]
		var is_fire: bool = th.get("is_fire", false)

		if is_fire:
			# 右側：太く滑らかなグラデーションの化学火炎コーン
			_draw_plasma_cone(p, d, 92.0 * pulse, 26.0 * pulse, Color(1.0, 0.45, 0.05, 0.48), Color(1.0, 0.95, 0.7, 0.95))

			# ノズル直下の白熱ホワイトコア＆高熱脈動
			draw_circle(p, 16.0 * pulse, Color(1.0, 0.45, 0.05, 0.4))
			draw_circle(p, 8.5 * pulse, Color(1.0, 0.85, 0.2, 0.75))
			draw_circle(p, 4.0, Color(1.0, 1.0, 0.9, 0.98))

			# 硬い直線を完全排除した上下減衰ソフト・アナモルフィック・グレア
			_draw_soft_anamorphic_flare(p, 120.0 * pulse, 12.0 * pulse, Color(1.0, 0.55, 0.15, 0.45))
			_draw_soft_anamorphic_flare(p, 60.0 * pulse, 6.0 * pulse, Color(1.0, 0.92, 0.65, 0.75))

			# 超音速マッハダイヤモンド衝撃波ノード（オレンジ/白）
			for md in range(1, 4):
				var node_p: Vector2 = p + d * (md * 28.0 * pulse)
				draw_circle(node_p, 4.5 * (1.0 - md * 0.2), Color(1.0, 0.65, 0.15, 0.55))
				draw_circle(node_p, 2.0, Color(1.0, 1.0, 0.9, 0.95))
		else:
			# 左側：右側と完全同一構造・密度の滑らかなシアン/ブルー極低温プラズマ炎コーン
			_draw_plasma_cone(p, d, 90.0 * pulse, 25.0 * pulse, Color(0.18, 0.72, 1.0, 0.48), Color(0.85, 0.98, 1.0, 0.95))

			# ノズル直下の白熱ホワイトコア＆イオン脈動
			draw_circle(p, 15.0 * pulse, Color(0.2, 0.7, 1.0, 0.38))
			draw_circle(p, 7.5 * pulse, Color(0.7, 0.95, 1.0, 0.72))
			draw_circle(p, 3.5, Color(1.0, 1.0, 1.0, 0.98))

			# 硬い直線を完全排除した上下減衰ソフト・アナモルフィック・グレア
			_draw_soft_anamorphic_flare(p, 115.0 * pulse, 11.5 * pulse, Color(0.25, 0.75, 1.0, 0.42))
			_draw_soft_anamorphic_flare(p, 58.0 * pulse, 5.8 * pulse, Color(0.85, 0.98, 1.0, 0.75))

			# 超音速マッハダイヤモンド衝撃波ノード（シアン/白）
			for md in range(1, 4):
				var node_p: Vector2 = p + d * (md * 28.0 * pulse)
				draw_circle(node_p, 4.2 * (1.0 - md * 0.2), Color(0.4, 0.9, 1.0, 0.52))
				draw_circle(node_p, 1.8, Color(1.0, 1.0, 1.0, 0.92))

func _draw_plasma_cone(pos: Vector2, dir: Vector2, length: float, spread: float, base_col: Color, core_col: Color) -> void:
	var perp := Vector2(-dir.y, dir.x)
	# 4層の滑らかなグラデーション・プラズマコーン（左右で同一の美しい流体光彩）
	for l in range(4):
		var factor := 1.0 - float(l) * 0.22
		var clen := length * factor
		var cspread := spread * factor
		var c_alpha := base_col.a * (0.2 + float(l) * 0.25)
		var pts: PackedVector2Array = [
			pos,
			pos + dir * (clen * 0.7) + perp * cspread,
			pos + dir * clen,
			pos + dir * (clen * 0.7) - perp * cspread
		]
		var col := core_col if l == 3 else base_col
		draw_colored_polygon(pts, Color(col.r, col.g, col.b, c_alpha))

func _draw_soft_anamorphic_flare(pos: Vector2, flare_w: float, flare_h: float, flare_col: Color) -> void:
	# 8角形ソフト減衰グラデーション（直線の突き刺さりアーティファクトを完全根絶）
	for layer in range(4):
		var factor := 1.0 - float(layer) * 0.22
		var w := flare_w * factor
		var h := flare_h * factor
		var a := flare_col.a * (0.22 + 0.22 * float(layer))
		var pts: PackedVector2Array = [
			pos + Vector2(-w, 0.0),
			pos + Vector2(-w * 0.65, -h * 0.5),
			pos + Vector2(0.0, -h),
			pos + Vector2(w * 0.65, -h * 0.5),
			pos + Vector2(w, 0.0),
			pos + Vector2(w * 0.65, h * 0.5),
			pos + Vector2(0.0, h),
			pos + Vector2(-w * 0.65, h * 0.5)
		]
		draw_colored_polygon(pts, Color(flare_col.r, flare_col.g, flare_col.b, a))

func _draw_massdriver_pulses() -> void:
	# 月面マスドライバー砲口 (515, 202) から 小惑星軌道 (810, 182) へのベジェ曲線
	var p0 := Vector2(515.0, 202.0)
	var p1 := Vector2(680.0, 172.0)
	var p2 := Vector2(810.0, 182.0)

	for i in range(pulse_offsets.size()):
		var t: float = pulse_offsets[i]
		var p := (1.0 - t) * (1.0 - t) * p0 + 2.0 * (1.0 - t) * t * p1 + t * t * p2

		# アイソメトリック（等角投影）立体ワイヤーフレーム貨物キューブ（画像4完全再現）
		_draw_isometric_cube(p, 7.5, Color(0.35, 0.95, 1.0))

func _draw_isometric_cube(pos: Vector2, size: float, col: Color) -> void:
	var hw := size * 0.866 # cos(30 deg)
	var hh := size * 0.5   # sin(30 deg)
	var h := size * 0.85

	# 1. 上面（ダイヤモンドひし形）
	var top_pts: PackedVector2Array = [
		pos + Vector2(0.0, -h),
		pos + Vector2(hw, -h + hh),
		pos + Vector2(0.0, -h + hh * 2.0),
		pos + Vector2(-hw, -h + hh)
	]
	draw_colored_polygon(top_pts, Color(col.r, col.g, col.b, 0.45))
	draw_polyline(top_pts + PackedVector2Array([top_pts[0]]), Color(col.r, col.g, col.b, 0.95), 1.3)

	# 2. 左側面
	var left_pts: PackedVector2Array = [
		pos + Vector2(-hw, -h + hh),
		pos + Vector2(0.0, -h + hh * 2.0),
		pos + Vector2(0.0, hh * 2.0),
		pos + Vector2(-hw, hh)
	]
	draw_colored_polygon(left_pts, Color(col.r * 0.8, col.g * 0.8, col.b, 0.35))
	draw_polyline(left_pts + PackedVector2Array([left_pts[0]]), Color(col.r, col.g, col.b, 0.95), 1.3)

	# 3. 右側面
	var right_pts: PackedVector2Array = [
		pos + Vector2(0.0, -h + hh * 2.0),
		pos + Vector2(hw, -h + hh),
		pos + Vector2(hw, hh),
		pos + Vector2(0.0, hh * 2.0)
	]
	draw_colored_polygon(right_pts, Color(col.r * 0.6, col.g * 0.6, col.b, 0.25))
	draw_polyline(right_pts + PackedVector2Array([right_pts[0]]), Color(col.r, col.g, col.b, 0.95), 1.3)

	# 内部高輝度コア
	draw_circle(pos + Vector2(0.0, -h * 0.1), size * 0.22, Color(1.0, 1.0, 1.0, 0.95))

func _draw_fusion_canisters() -> void:
	# 要塞内部の3連グリーンキャニスター (x: 1040, 1060, 1080, y: 345)
	var can_pulse := 0.75 + sin(Time.get_ticks_msec() * 0.008) * 0.25
	var xs := [1040.0, 1060.0, 1080.0]
	var t_sec := float(Time.get_ticks_msec()) * 0.001
	for idx in range(xs.size()):
		var cx: float = xs[idx]
		draw_rect(Rect2(cx - 5, 335, 10, 22), Color(0.1, 0.9, 0.35, 0.75 * can_pulse))
		draw_circle(Vector2(cx, 346), 4.0, Color(0.5, 1.0, 0.7, can_pulse))
		# 上昇する微小核融合気泡（マイクロバブル）
		for b in range(3):
			var b_t := fmod(t_sec * 0.8 + float(b) * 0.35 + float(idx) * 0.2, 1.0)
			var b_y := 355.0 - b_t * 18.0
			var b_x := cx + sin(b_t * 8.0 + float(b)) * 2.0
			draw_circle(Vector2(b_x, b_y), 1.0, Color(0.85, 1.0, 0.9, 0.85 * (1.0 - b_t * 0.5)))

func _draw_fleet_battle() -> void:
	# レーザー軌跡（強力なブルーム・ホワイトコア・マズルフラッシュ）
	for l in combat_lasers:
		var a: float = l["life"] / l["max_life"]
		var c: Color = l["col"]
		c.a = a
		# 外郭大気光彩ブルーム
		draw_line(l["start"], l["end"], Color(c.r, c.g, c.b, a * 0.4), 4.5)
		# 発光メインライン
		draw_line(l["start"], l["end"], c, 2.5)
		# 芯の白熱ホワイトコア
		draw_line(l["start"], l["end"], Color(1.0, 1.0, 1.0, a * 0.95), 1.2)
		# 先端閃光スパーク
		draw_circle(l["end"], 3.5, Color(c.r, c.g, c.b, a * 0.6))
		draw_circle(l["end"], 2.0, Color(1.0, 1.0, 1.0, a * 0.98))
		# 砲口マズルフラッシュ
		draw_circle(l["start"], 3.2, Color(c.r, c.g, c.b, a * 0.7))
		draw_circle(l["start"], 1.8, Color(1.0, 1.0, 1.0, a))

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

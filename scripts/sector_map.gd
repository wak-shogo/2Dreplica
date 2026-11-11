# sector_map.gd
class_name SectorMap
extends Node2D

@export var is_sector_view: bool = false

# ゾーン半径
var zone_radii := [
	800.0,   # Zone 1: 内縁
	1800.0,  # Zone 2: ハビタブル
	2800.0,  # Zone 3: 小惑星帯
	3900.0   # Zone 4: 外縁カイパーベルト
]

var route_offset := 0.0

func _process(delta: float) -> void:
	if is_sector_view:
		route_offset += delta * 40.0
		queue_redraw()

func _draw() -> void:
	if not is_sector_view:
		return
		
	# 恒星系セクターマップ（戦術ベクターオーバーレイ）
	# 中心太陽 (Sun)
	draw_circle(Vector2.ZERO, 100.0, Color(1.0, 0.8, 0.2, 0.8))
	draw_arc(Vector2.ZERO, 130.0, 0.0, TAU, 32, Color(1.0, 0.4, 0.1, 0.4), 3.0)

	# 4つのリングゾーン
	var zone_colors := [
		Color(1.0, 0.4, 0.1, 0.25), # Zone 1
		Color(0.2, 0.6, 1.0, 0.25), # Zone 2
		Color(0.8, 0.8, 0.3, 0.25), # Zone 3
		Color(0.8, 0.2, 0.3, 0.25)  # Zone 4
	]
	
	for i in range(zone_radii.size()):
		var r: float = zone_radii[i]
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, zone_colors[i], 1.5)

	# ゾーンラベル
	# 勢力ヒートマップ
	# Zone 2 は青（自軍）、Zone 4 は赤（敵軍）
	var poly_pts := PackedVector2Array()
	var num_pts := 32
	for k in range(num_pts + 1):
		var ang := float(k) / float(num_pts) * TAU
		poly_pts.append(Vector2(cos(ang), sin(ang)) * zone_radii[1])
	draw_polyline(poly_pts, Color(0.2, 0.8, 1.0, 0.4), 4.0)

	# 惑星間輸送ルート（点線アニメーション）
	var start_p := Vector2(0.0, -450.0)
	var end_p := Vector2(1000.0, -800.0) # 月または小惑星へ
	var dist := start_p.distance_to(end_p)
	var steps := int(dist / 30.0)
	for s in range(steps):
		var t1 := float(s) / float(steps)
		var t2 := float(s + 0.5) / float(steps)
		var p1 := start_p.lerp(end_p, t1)
		var p2 := start_p.lerp(end_p, t2)
		draw_line(p1, p2, Color(0.3, 1.0, 0.6, 0.8), 2.0)

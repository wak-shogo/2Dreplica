# orbit_predictor.gd
class_name OrbitPredictor
extends Node2D

@export var max_steps: int = 120
@export var step_dt: float = 0.08
@export var line_color: Color = Color(0.2, 0.9, 1.0, 0.75)
@export var orbit_stable_color: Color = Color(0.3, 1.0, 0.5, 0.9)

var trajectory_points: PackedVector2Array = []
var is_orbit_stable: bool = false
var impact_point: Vector2 = Vector2.ZERO
var has_impact: bool = false
var periapsis_dist: float = 0.0
var apoapsis_dist: float = 0.0

func calculate_orbit(start_pos: Vector2, start_vel: Vector2, celestial_body: CelestialBody) -> void:
	trajectory_points.clear()
	has_impact = false
	is_orbit_stable = false
	
	if celestial_body == null:
		queue_redraw()
		return
		
	var pos := start_pos
	var vel := start_vel
	trajectory_points.append(pos)
	
	var min_dist := INF
	var max_dist := 0.0
	var center := celestial_body.global_position
	var base_r := celestial_body.base_radius
	
	for i in range(max_steps):
		# 重力と大気抵抗の加算
		var g := celestial_body.get_gravity_at(pos)
		var drag := celestial_body.get_atmosphere_drag_at(pos, vel)
		var accel := g + drag
		
		# シンプレクティック・オイラー（またはベベル）
		vel += accel * step_dt
		var next_pos := pos + vel * step_dt
		
		var dist_to_center := (next_pos - center).length()
		min_dist = minf(min_dist, dist_to_center)
		max_dist = maxf(max_dist, dist_to_center)
		
		# 地表衝突チェック
		if dist_to_center <= base_r:
			has_impact = true
			impact_point = next_pos
			trajectory_points.append(impact_point)
			break
			
		trajectory_points.append(next_pos)
		pos = next_pos
		
	periapsis_dist = min_dist
	apoapsis_dist = max_dist
	
	# 周回軌道判定：地表にぶつからず、近点が地表以上、かつステップ末尾でも周回傾向がある
	if not has_impact and periapsis_dist > base_r + 10.0 and trajectory_points.size() >= max_steps - 5:
		is_orbit_stable = true
		
	queue_redraw()

func clear_orbit() -> void:
	if trajectory_points.size() > 0:
		trajectory_points.clear()
		has_impact = false
		is_orbit_stable = false
		queue_redraw()

func _draw() -> void:
	if trajectory_points.size() < 2:
		return
		
	var col := orbit_stable_color if is_orbit_stable else line_color
	
	# 点線またはグラデーションラインで描画
	for i in range(trajectory_points.size() - 1):
		var p1 := to_local(trajectory_points[i])
		var p2 := to_local(trajectory_points[i + 1])
		var alpha := 1.0 - (float(i) / float(trajectory_points.size())) * 0.7
		var seg_col := col
		seg_col.a *= alpha
		if i % 2 == 0:
			draw_line(p1, p2, seg_col, 2.0)
			
	# 地表着弾点のマーク
	if has_impact:
		var imp_local := to_local(impact_point)
		draw_circle(imp_local, 4.0, Color(1.0, 0.3, 0.2, 0.8))
		draw_arc(imp_local, 8.0, 0.0, TAU, 16, Color(1.0, 0.5, 0.2, 0.6), 1.5)

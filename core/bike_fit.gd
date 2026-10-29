extends RefCounted
const RIDER_FIT = preload("res://core/rider_fit.gd")
## Fit the rider to an intact bike. Only uniform scale and placement change;
## saddle, cockpit, wheels and crank retain the source model's proportions.
static func _v(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
static func _b(p: Vector3) -> Vector3:
	return Vector3(p.x, p.z, -p.y)
static func place(g: Dictionary, bj: Dictionary, size := 1.0, k_fixed := -1.0) -> Dictionary:
	var rider_seat := _v(g.seat) - _v(g.bb)
	var bike_seat := _v(bj.saddle) - _v(bj.bb)
	var k := k_fixed if k_fixed > 0.0 else size * rider_seat.length() / maxf(0.1, bike_seat.length())
	var offset := _v(g.bb) - _v(bj.bb) * k
	var geometry := g.duplicate()
	geometry.crank = float(bj.crank) * k
	geometry.ankle_up = 0.09 * float(g.size)
	geometry.ankle_back = 0.06 * float(g.size)
	var grips := {}
	for side in ["Left", "Right"]:
		grips[side] = _b(offset + _v(bj.grip_l if side == "Left" else bj.grip_r) * k)
	return {"scale": k, "position": _b(offset), "lift": -offset.z,
		"geometry": geometry, "grips": grips,
		"person": _b(offset + _v(bj.saddle) * k - _v(g.seat)),
		"saddle_raise": 0.0, "wheel": float(bj.wheel) * k,
		"crank_angle": float(bj.get("crank_angle", 0.0))}
static func choose(s: Skeleton3D, model: Node3D, person: Node3D, g: Dictionary, bj: Dictionary) -> Dictionary:
	var best := {}
	var best_score := INF
	var preferred := float(g.wheel) / float(bj.wheel)
	for fraction in [1.0, 0.975, 0.95, 0.925, 0.9, 0.875, 0.85, 0.825, 0.8, 0.775, 0.75, 0.725, 0.7, 0.675, 0.65, 0.625, 0.6]:
		var fit := place(g, bj, 1.0, preferred * fraction)
		person.position = fit.person
		s.clear_bones_global_pose_override()
		s.force_update_all_bone_transforms()
		var foot := 0.0
		var hand := 0.0
		var reach := 0.0
		for phase in [0.0, PI / 2.0, PI, 1.5 * PI]:
			for leg in RIDER_FIT.solve(s, model, fit.geometry, phase):
				foot = maxf(foot, leg.ankle.distance_to(leg.target))
			RIDER_FIT.solve_torso(s, model, fit.grips)
			for arm in RIDER_FIT.solve_arms(s, model, fit.grips):
				hand = maxf(hand, arm.hand.distance_to(arm.target))
				reach = maxf(reach, arm.reach / arm.arm)
		fit["foot"] = foot
		fit["reach"] = reach
		if foot < 0.025 and hand < 0.025 and reach <= 1.02:
			best = fit
			break
		var score := foot + hand
		if score < best_score:
			best_score = score
			best = fit
	person.position = best.person
	return best

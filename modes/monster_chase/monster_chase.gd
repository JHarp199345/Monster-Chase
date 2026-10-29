extends Node3D
## Monster Chase (blockout). Something follows you down a haunted forest path. You pick the head start; the monster's
## pace is set from your own FTP and runs on the hub's own road physics, so whether it catches you comes down to your
## power over time: a disguised interval workout. It prowls, then surges every few minutes. When it gets close it
## crouches, then lunges: escape by SPRINTING (a burst over your FTP) or by LEANING away (a tilted tablet, or a rocker
## plate with a phone on the bike; arrow keys too). Leaning just works when a sensor is there; nobody has to own one.
## Grabbed, you can't dodge: a tug-of-war meter appears and you pedal hard against its pull to break free.
## The path's slope sets the trainer's hill through the hub. Weak data only makes an easy ride; nothing to cheat.

const STEP := 5.0                     # path resolution, m
const LENGTH := 30000.0               # m of path, more than a long chase needs
const ROAD_HALF := 2.2
const LANE_MAX := 1.6                 # how far either side of the middle the rider can steer, m
const DODGE := 1.2                    # sideways distance from the lunge that counts as a dodge, m
const WARMUP := 120.0                 # s: the monster is still waking up
const RIDER_FIT = preload("res://core/rider_fit.gd")
const BIKE_FIT = preload("res://core/bike_fit.gd")
const PRESSURE = preload("res://core/chase_pressure.gd")
const WARN := 10.0
const CHASE_LIMIT := 35.0             # ceiling on one surge; even an uncaught rider earns a recovery window
const DIFFICULTY := {                 # shares of your FTP; window = seconds to escape once it lunges
	"Easy": {"prowl": 0.62, "surge": 0.95, "sprint": 1.15, "pull": 1.0, "window": 1.5},
	"Steady": {"prowl": 0.72, "surge": 1.05, "sprint": 1.3, "pull": 1.15, "window": 1.2},
	"Hard": {"prowl": 0.82, "surge": 1.15, "sprint": 1.45, "pull": 1.3, "window": 0.8},
}
const CROUCH := 1.0                   # s of warning before the lunge: time to start a sprint
const SPRINT_HOLD := 0.4              # s above the sprint line, across crouch and lunge, that counts as a sprint escape
const GRAB_LIMIT := 15.0              # s of struggle; whoever is ahead on the meter then wins
const HEAD_STARTS := [40.0, 80.0, 150.0]
const RIDERS := ["Timmy", "Olivia", "Michelle"]   # assets/riders/<name>.glb + .bike.json from tools/rider_rig.py
const SAVE := "monster_chase.cfg"                  # each rider's chosen bike (saved with the hub: HubLink.save_config)

var pts := PackedVector3Array()
var dirs := PackedVector3Array()
var sky_mat: ShaderMaterial
var rider_skeleton: Skeleton3D
var rider_model: Node3D
var rider_geometry: Dictionary
var bikes: Array = []                 # assets/bikes/index.json from tools/build_bikes.py: every rider can ride every bike
var bike_of := {}                     # rider name -> bike id, remembered between rides
var grips := {}                       # where this bike's grips are, in the rider model's space
var wheel_radius := 0.25
var crank_offset := 0.0               # the bike model's own crank angle, so its pedals meet the rider's feet
var rider: Node3D
var wheels: Array[Node3D] = []
var crank: Node3D
var pedal_anim: AnimationPlayer
var monster_skeleton: Skeleton3D
var monster_anim: AnimationPlayer
var monster_clip := ""
var last_lean_source := ""
var monster: Node3D
var cam: Camera3D
var hud: Label
var gap_bar: ProgressBar
var menu: VBoxContainer
var flash: ColorRect

var state := "menu"
var difficulty := "Steady"
var head_start := 80.0
var minutes := 20
var rider_name := "Timmy"
var t := 0.0
var rider_d := 500.0                  # start well into the path, so there is forest behind you
var monster_d := 420.0
var lane := 0.0
var attack := ""                      # "", "crouch", "lunge" or "grab"
var attack_t := 0.0                   # seconds left in the crouch or lunge; seconds spent in a grab
var lunge_lane := 0.0
var sprint_s := 0.0
var meter := 0.5                      # the struggle: 1 = you break free, 0 = it drags you down
var meter_bar: ProgressBar
var escapes := 0
var stumble := 0.0
var catches := 0
var dodges := 0
var pursuit_rng := RandomNumberGenerator.new()
var next_surge := WARMUP + 60.0
var surge_until := 0.0
var escape_grace := 0.0
var recovery_total := 0.0
var chase_effort := 0.0
var surging := false
var grade_clock := 0.0
var paused := false
var stopped_for := 0.0
var light := false                    # phones and tablets: lower resolution, a thinner forest, the rider fit every other frame
var dev := false                      # ?dev in the page address: number keys pretend to pedal (testing without a bike)
var pretend := 0.0
var dev_lean := 0.0                    # dev: Z / X lean fully left / right for 1.5 s; A makes it attack now
var dev_lean_t := 0.0
var sky_turn := 0.0                    # dev: [ and ] turn the painted sky a quarter at a time


func _ready() -> void:
	light = OS.has_feature("web_android") or OS.has_feature("web_ios")
	if OS.has_feature("web"):
		light = light or str(JavaScriptBridge.eval("location.search", true)).contains("light")   # ?light to try it anywhere
	if light:
		get_viewport().scaling_3d_scale = 0.7
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("location.search", true))
		dev = q.contains("dev")
		if dev and q.contains("sky="):
			sky_turn = q.get_slice("sky=", 1).to_int() * PI / 2.0
	pursuit_rng.randomize()
	if FileAccess.file_exists("res://assets/bikes/index.json"):
		bikes = JSON.parse_string(FileAccess.get_file_as_string("res://assets/bikes/index.json"))
	var cfg := HubLink.load_config(SAVE)
	if cfg.has_section("bikes") or cfg.has_section("ride"):
		for r in RIDERS:
			bike_of[r] = cfg.get_value("bikes", r, "")
		rider_name = cfg.get_value("ride", "rider", rider_name)
	if dev and OS.has_feature("web"):
		var chosen = JSON.parse_string(str(JavaScriptBridge.eval("JSON.stringify({rider:new URLSearchParams(location.search).get('rider'),bike:new URLSearchParams(location.search).get('bike')})", true)))
		if chosen is Dictionary:
			if chosen.get("rider") in RIDERS:
				rider_name = chosen.rider
			for b in bikes:
				if b.id == chosen.get("bike"):
					bike_of[rider_name] = b.id
	_build_path()
	_build_world()
	_build_rider()
	_build_monster()
	_build_hud()
	get_window().title = "Monster Chase"
	HubLink.connection_changed.connect(func(on: bool): if on and state == "menu": _menu())   # your FTP, not the default
	_place(0.0)
	HubLink.start_mode("monster-chase", "Monster Chase")


# --- the path ------------------------------------------------------------------------------------------------------
func grade_at(s: float) -> float:
	## The hill at s metres, %: rolling, -3 to +4, flat for the first few hundred metres.
	var g := 2.2 * sin(s / 650.0) + 1.4 * sin(s / 230.0 + 1.3) + 0.6
	return g * smoothstep(0.0, 400.0, s)


func _build_path() -> void:
	var n := int(LENGTH / STEP) + 1
	pts.resize(n)
	dirs.resize(n)
	var p := Vector3.ZERO
	for i in n:
		var s := i * STEP
		var heading := 0.9 * sin(s / 500.0) + 0.5 * sin(s / 180.0 + 2.0)
		var flat := Vector3(sin(heading), 0.0, -cos(heading))
		var d := flat + Vector3.UP * grade_at(s) / 100.0
		pts[i] = p
		dirs[i] = d.normalized()
		p += d * STEP


func sample(s: float) -> Array:
	## [position, forward] on the path at s metres.
	var f := clampf(s, 0.0, LENGTH - STEP) / STEP
	var i := int(f)
	var k := f - i
	return [pts[i].lerp(pts[i + 1], k), dirs[i].lerp(dirs[i + 1], k).normalized()]


func _right(fwd: Vector3) -> Vector3:
	return fwd.cross(Vector3.UP).normalized()


func _strip(half: float, lift: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in pts.size() - 1:
		var r0 := _right(dirs[i]) * half
		var r1 := _right(dirs[i + 1]) * half
		var a := pts[i] + Vector3.UP * lift
		var b := pts[i + 1] + Vector3.UP * lift
		var v0 := i * STEP / 8.0
		var v1 := (i + 1) * STEP / 8.0
		for q in [[a - r0, 0.0, v0], [b - r1, 0.0, v1], [a + r0, 1.0, v0], [a + r0, 1.0, v0], [b - r1, 0.0, v1], [b + r1, 1.0, v1]]:
			st.set_uv(Vector2(q[1], q[2]))
			st.add_vertex(q[0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)


func _mat(color: Color, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.95
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


func _scatter(mesh: Mesh, mat: Material, every: float, near: float, far: float, size: Vector2, sink: float, rng_seed: int) -> void:
	if light:
		every *= 2.0                               # half the trees, mushrooms and pumpkins on phones and tablets
	## Instances along both sides of the path: one every `every` metres per side, near..far metres out.
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var count := int(LENGTH / every) * 2
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	for j in count:
		var s := (j / 2) * every + rng.randf() * every
		var at := sample(s)
		var side := -1.0 if j % 2 == 0 else 1.0
		var pos: Vector3 = at[0] + _right(at[1]) * side * rng.randf_range(near, far)
		var k := rng.randf_range(size.x, size.y)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(k, k * rng.randf_range(0.85, 1.25), k))
		mm.set_instance_transform(j, Transform3D(basis, pos + Vector3.UP * (k * 0.5 - sink)))
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = mat
	add_child(node)


func _build_world() -> void:
	# sky: the painted cube map
	var faces: Array[Image] = []
	for f in ["px", "nx", "py", "ny", "pz", "nz"]:
		var img: Image = load("res://assets/sky/haunted/%s.jpg" % f).get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGB8)
		if OS.has_feature("web_android") or OS.has_feature("web_ios"):
			img.resize(1024, 1024)                 # phones and tablets: a quarter of the memory for the sky
		faces.append(img)
	var cube := Cubemap.new()
	cube.create_from_images(faces)
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://modes/monster_chase/sky.gdshader")
	sky_mat.set_shader_parameter("sky_cube", cube)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = sky_mat
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.4, 0.7)
	env.ambient_light_energy = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.32, 0.27, 0.55)
	env.fog_density = 0.0055
	env.fog_sky_affect = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-35, 40, 0)
	moon.light_color = Color(0.75, 0.75, 1.0)
	moon.light_energy = 0.8
	add_child(moon)

	# ground, path, forest
	_strip(90.0, -0.05, _mat(Color(0.17, 0.27, 0.22)))
	_strip(ROAD_HALF, 0.0, _mat(Color(0.45, 0.36, 0.3)))
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.25
	trunk.bottom_radius = 0.55
	trunk.height = 1.0
	_scatter(trunk, _mat(Color(0.32, 0.2, 0.22)), 7.0, 6.0, 45.0, Vector2(4.0, 8.0), -0.0, 1)
	var crown := SphereMesh.new()
	crown.radius = 0.5
	crown.height = 0.7
	_scatter(crown, _mat(Color(0.12, 0.3, 0.32)), 7.0, 6.0, 45.0, Vector2(4.5, 8.0), -5.5, 1)
	var cap := SphereMesh.new()
	cap.radius = 0.5
	cap.height = 0.5
	_scatter(cap, _mat(Color(1.0, 0.85, 0.35), 2.5), 14.0, 2.8, 6.0, Vector2(0.25, 0.6), 0.1, 2)
	_scatter(cap, _mat(Color(1.0, 0.45, 0.6), 2.5), 19.0, 2.8, 7.0, Vector2(0.2, 0.5), 0.1, 3)
	var pumpkin := SphereMesh.new()
	pumpkin.radius = 0.5
	pumpkin.height = 0.75
	_scatter(pumpkin, _mat(Color(1.0, 0.45, 0.08), 1.8), 110.0, 3.0, 5.0, Vector2(0.6, 1.0), 0.15, 4)


# --- the rider and the monster -------------------------------------------------------------------------------------
func _b(x: float, y: float, z: float) -> Vector3:
	## Blender metres (z up, forward -Y) as Godot's (y up); the rider model is turned to face -Z afterwards.
	return Vector3(x, z, -y)


func _tube(from: Vector3, to: Vector3, radius: float, mat: Material, parent: Node3D) -> void:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = from.distance_to(to)
	c.radial_segments = 8
	m.mesh = c
	m.material_override = mat
	m.position = (from + to) / 2.0
	var up := (to - from).normalized()
	m.basis = Basis(Quaternion(Vector3.UP, up))
	parent.add_child(m)


func _build_rider() -> void:
	## The chosen rider (Mixamo) on a bike sized to them. tools/rider_rig.py baked one crank turn as "pedal" and wrote
	## the bike's measurements; the turn plays at the real cadence.
	if rider:
		rider.queue_free()
	wheels.clear()
	var key := rider_name.to_lower()
	var g: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/riders/%s.bike.json" % key))
	var p := func(k: String) -> Vector3: return _b(g[k][0], g[k][1], g[k][2])
	rider = Node3D.new()
	add_child(rider)
	var model := Node3D.new()
	model.rotation_degrees.y = 180.0
	rider.add_child(model)
	var person: Node3D = load("res://assets/riders/%s.glb" % key).instantiate()
	model.add_child(person)
	pedal_anim = person.find_child("AnimationPlayer", true, false)
	if pedal_anim:
		var name := ""
		for n in pedal_anim.get_animation_list():
			if name == "" or n.contains("pedal"):
				name = n
		pedal_anim.get_animation(name).loop_mode = Animation.LOOP_LINEAR
		pedal_anim.play(name)
		pedal_anim.speed_scale = 0.0
	# A neutral rider light preserves the source paint colors against the purple scenery.
	var paint_light := OmniLight3D.new()
	paint_light.position = Vector3(-1.2, 1.5, 1.5)
	paint_light.light_color = Color.WHITE
	paint_light.light_energy = 2.2
	paint_light.omni_range = 6.0
	paint_light.light_cull_mask = 2
	rider.add_child(paint_light)
	rider_skeleton = person.find_child("Skeleton3D", true, false)
	rider_model = model
	rider_geometry = g
	grips = {}
	if not bikes.is_empty():
		_build_bike(model, g)

		return
	var k: float = g.size
	var paint := _mat(Color(0.95, 0.3, 0.25), 0.3)
	var dark := _mat(Color(0.12, 0.12, 0.14))
	var bb: Vector3 = p.call("bb")
	var rear: Vector3 = p.call("rear")
	var front: Vector3 = p.call("front")
	var seat: Vector3 = p.call("seat")
	var bar: Vector3 = p.call("bar")
	var head := front.lerp(bar, 0.62)
	for w in [rear, front]:
		var hub := Node3D.new()
		hub.position = w
		var tire := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = float(g.wheel) - 0.035 * k
		tor.outer_radius = float(g.wheel)
		tire.mesh = tor
		tire.material_override = dark
		tire.rotation_degrees.z = 90.0
		hub.add_child(tire)
		for j in 3:
			var spoke := Node3D.new()
			spoke.rotation.x = j * PI / 3.0
			hub.add_child(spoke)
			_tube(Vector3(0, -float(g.wheel), 0), Vector3(0, float(g.wheel), 0), 0.006 * k, _mat(Color(0.8, 0.8, 0.85)), spoke)
		model.add_child(hub)
		wheels.append(hub)
	var under_seat := seat + Vector3(0, -0.06 * k, 0)
	for t in [[bb, under_seat], [bb, head], [under_seat, head], [bb, rear], [under_seat, rear], [head, front], [head, bar]]:
		_tube(t[0], t[1], 0.022 * k, paint, model)
	_tube(bar + Vector3(-float(g.bar_w), 0, 0), bar + Vector3(float(g.bar_w), 0, 0), 0.016 * k, dark, model)
	var saddle := MeshInstance3D.new()
	saddle.mesh = BoxMesh.new()
	saddle.scale = Vector3(0.12, 0.04, 0.22) * k
	saddle.position = seat + Vector3(0, 0.02 * k, 0)
	saddle.material_override = dark
	model.add_child(saddle)
	crank = Node3D.new()
	crank.position = bb
	model.add_child(crank)
	var c: float = g.crank
	for side in [1.0, -1.0]:
		var arm_end := Vector3(side * 0.08 * k, side * c, 0)       # left arm up at the top of the turn, right down
		_tube(Vector3(side * 0.08 * k, 0, 0), arm_end, 0.012 * k, dark, crank)
		_tube(arm_end, arm_end + Vector3(side * 0.06 * k, 0, 0), 0.015 * k, dark, crank)


func _bike_id() -> String:
	var id: String = bike_of.get(rider_name, "")
	for b in bikes:
		if b.id == id:
			return id
	return bikes[0].id


func _save_choices() -> void:
	var cfg := ConfigFile.new()
	for r in bike_of:
		cfg.set_value("bikes", r, bike_of[r])
	cfg.set_value("ride", "rider", rider_name)
	HubLink.save_config(SAVE, cfg)


func _build_bike(model: Node3D, g: Dictionary) -> void:
	## A converted bike (tools/bike_web.py), sized so its saddle sits where this rider sits: bottom brackets together,
	## the tyres on the ground. Feet follow its cranks and hands its grips (core/rider_fit.gd).
	var id := _bike_id()
	var bj: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/bikes/%s.bike.json" % id))
	var person: Node3D = model.get_child(0)
	var fit: Dictionary = BIKE_FIT.choose(rider_skeleton, model, person, g, bj) if rider_skeleton else BIKE_FIT.place(g, bj)
	var bike: Node3D = load("res://assets/bikes/%s.glb" % id).instantiate()
	bike.scale = Vector3.ONE * float(fit.scale)
	bike.position = fit.position
	model.add_child(bike)
	for mesh in bike.find_children("*", "MeshInstance3D", true, false):
		mesh.layers = 3 # moonlight plus neutral paint light; avatar lighting stays unchanged
	model.position.y = fit.lift                      # the tyres touch the ground, whatever the bike's size
	for n in ["WheelF", "WheelR"]:
		var w := bike.find_child(n, true, false)
		if w:
			wheels.append(w)
	crank = bike.find_child("Crank", true, false)
	if not crank:
		crank = Node3D.new()
		bike.add_child(crank)
	wheel_radius = fit.wheel
	crank_offset = fit.crank_angle
	rider_geometry = fit.geometry
	grips = fit.grips


func _bike_name() -> String:
	var id := _bike_id()
	for b in bikes:
		if b.id == id:
			return "%s (%s)" % [b.name, b.kind]
	return id


func _build_monster() -> void:
	monster = Node3D.new()
	add_child(monster)
	var model: Node3D = load("res://assets/monster/monster-animated.glb").instantiate()
	model.scale = Vector3.ONE * 4.5            # about 3.5 m tall
	model.rotation_degrees = Vector3(0, 180, 0)  # the model faces +Z; turn it to face down the path, toward the rider
	monster.add_child(model)
	monster_skeleton = model.find_child("Skeleton3D", true, false)
	monster_anim = model.find_child("AnimationPlayer", true, false)
	if monster_anim:
		for clip in monster_anim.get_animation_list():
			monster_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR


func _animate_monster() -> void:
	if not monster_anim:
		return
	var wanted := "stumble" if stumble > 0.0 else (attack if attack != "" else "run")
	if wanted != monster_clip:
		for clip in monster_anim.get_animation_list():
			if clip.get_slice("/", clip.get_slice_count("/") - 1) == wanted:
				monster_anim.play(clip, 0.12)
				monster_clip = wanted
				break
	monster_anim.speed_scale = clampf(_speed / 5.0, 0.65, 1.6) if wanted == "run" else 1.0


func _grip_rider() -> void:
	if not monster_skeleton:
		return
	monster_skeleton.clear_bones_global_pose_override()
	monster_skeleton.force_update_all_bone_transforms()
	if attack != "grab":
		return
	var geometry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/riders/%s.bike.json" % rider_name.to_lower()))
	var shoulder_height: float = float(geometry.bar[2]) + 0.50 * float(geometry.size)
	for side in ["l", "r"]:
		var arm_index := monster_skeleton.find_bone("arm_" + side)
		var fore_index := monster_skeleton.find_bone("forearm_" + side)
		var hand_index := monster_skeleton.find_bone("hand_" + side)
		if arm_index < 0 or fore_index < 0 or hand_index < 0:
			continue
		var shoulder := monster_skeleton.get_bone_global_pose(arm_index).origin
		var rest_arm := monster_skeleton.get_bone_global_rest(arm_index).origin
		var rest_fore := monster_skeleton.get_bone_global_rest(fore_index).origin
		var rest_hand := monster_skeleton.get_bone_global_rest(hand_index).origin
		var a := rest_arm.distance_to(rest_fore)
		var b := rest_fore.distance_to(rest_hand)
		var sign_x := -1.0 if side == "l" else 1.0
		var world_target := rider.to_global(Vector3(-sign_x * 0.26 * float(geometry.size), shoulder_height, 0.05))
		var target := monster_skeleton.to_local(world_target)
		var direction := (target - shoulder).normalized()
		var reach := clampf(shoulder.distance_to(target), absf(a - b) + 0.001, a + b - 0.001)
		target = shoulder + direction * reach
		var along := (a * a - b * b + reach * reach) / (2.0 * reach)
		var bend := Vector3(sign_x, 0.0, -0.25)
		bend = (bend - direction * bend.dot(direction)).normalized()
		var elbow := shoulder + direction * along + bend * sqrt(maxf(0.0, a * a - along * along))
		var qa := Quaternion((rest_fore - rest_arm).normalized(), (elbow - shoulder).normalized())
		var qb := Quaternion((rest_hand - rest_fore).normalized(), (target - elbow).normalized())
		monster_skeleton.set_bone_global_pose_override(arm_index, Transform3D(Basis(qa), shoulder), 1.0, true)
		monster_skeleton.set_bone_global_pose_override(fore_index, Transform3D(Basis(qb), elbow), 1.0, true)
		monster_skeleton.set_bone_global_pose_override(hand_index, Transform3D(Basis(qb), target), 1.0, true)


func _place(delta: float) -> void:
	var at := sample(rider_d)
	var r := _right(at[1])
	rider.position = at[0] + r * lane
	rider.look_at(rider.position + at[1], Vector3.UP)
	rider.rotate_object_local(Vector3.FORWARD, -_steer * 0.25)
	for w in wheels:
		w.rotate_x(_speed * delta / wheel_radius)
	var phase := 0.0
	if pedal_anim:
		pedal_anim.speed_scale = _cadence / 60.0                   # the baked turn lasts one second
		phase = pedal_anim.current_animation_position / maxf(0.01, pedal_anim.current_animation_length) * TAU
		crank.rotation.x = phase - crank_offset
	_animate_monster()
	if rider_skeleton and pedal_anim and (not light or Engine.get_process_frames() % 2 == 0):
		RIDER_FIT.solve(rider_skeleton, rider_model, rider_geometry, phase)
		if not grips.is_empty():
			RIDER_FIT.solve_torso(rider_skeleton, rider_model, grips)
			RIDER_FIT.solve_arms(rider_skeleton, rider_model, grips)
			RIDER_FIT.solve_fingers(rider_skeleton, rider_model)
	var window: float = DIFFICULTY[difficulty].window
	var lunge_k := sin((1.0 - attack_t / window) * PI) if attack == "lunge" else 0.0
	var crouch_k := 1.0 if attack == "crouch" else 0.0
	var m := sample(monster_d + lunge_k * 4.0)
	var mlane := lerpf(0.0, lunge_lane, clampf(lunge_k * 2.0, 0.0, 1.0)) if attack == "lunge" else (lane if attack == "grab" else 0.0)
	var shake := sin(t * 40.0) * 0.12 if attack in ["crouch", "grab"] else 0.0
	monster.position = m[0] + _right(m[1]) * (mlane + shake) + Vector3.UP * (lunge_k * 0.45 - crouch_k * 0.10)
	monster.look_at(monster.position + m[1], Vector3.UP)
	monster.rotate_object_local(Vector3.FORWARD, (0.22 if stumble > 0.0 else 0.0))
	_grip_rider()
	if state == "menu":
		# the lobby: a three-quarter view of the rider and their bike, to choose by
		cam.position = rider.position + r * 2.6 + at[1] * 1.6 + Vector3.UP * 1.3
		cam.look_at(rider.position + Vector3.UP * 0.75, Vector3.UP)
	else:
		# camera ahead of the rider, looking back down the path at rider and monster
		var c := sample(rider_d + 8.0)
		cam.position = c[0] + Vector3.UP * 2.4
		cam.look_at(sample(rider_d - 6.0)[0] + Vector3.UP * 1.2, Vector3.UP)
	var look := -cam.global_basis.z
	sky_mat.set_shader_parameter("yaw", -atan2(look.x, look.z) + sky_turn)


# --- HUD and menu --------------------------------------------------------------------------------------------------
func _build_hud() -> void:
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 300.0 if light else 600.0           # the fog hides what's beyond
	add_child(cam)
	var ui := CanvasLayer.new()
	add_child(ui)
	flash = ColorRect.new()
	flash.color = Color(0.7, 0, 0.1, 0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(flash)
	hud = Label.new()
	hud.position = Vector2(24, 20)
	hud.add_theme_font_size_override("font_size", 24)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 6)
	ui.add_child(hud)
	gap_bar = ProgressBar.new()
	gap_bar.position = Vector2(24, 196)
	gap_bar.size = Vector2(360, 18)
	gap_bar.show_percentage = false
	gap_bar.max_value = 200
	ui.add_child(gap_bar)
	meter_bar = ProgressBar.new()
	meter_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	meter_bar.position = Vector2(-260, -90)
	meter_bar.size = Vector2(520, 34)
	meter_bar.max_value = 1.0
	meter_bar.show_percentage = false
	meter_bar.visible = false
	ui.add_child(meter_bar)
	menu = VBoxContainer.new()
	menu.set_anchors_preset(Control.PRESET_CENTER_LEFT)            # the lobby: choices on the left, rider and bike on the right
	menu.position = Vector2(28, -190)
	menu.custom_minimum_size = Vector2(340, 0)
	menu.add_theme_constant_override("separation", 10)
	ui.add_child(menu)
	_menu()


func _menu() -> void:
	for c in menu.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "MONSTER CHASE"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(title)
	_button("Monster: %s" % difficulty, func():
		var keys := DIFFICULTY.keys()
		difficulty = keys[(keys.find(difficulty) + 1) % keys.size()]
		_menu())
	_button("Rider: %s" % rider_name, func():
		rider_name = RIDERS[(RIDERS.find(rider_name) + 1) % RIDERS.size()]
		_save_choices()
		_build_rider()
		_place(0.0)
		_menu())
	if not bikes.is_empty():
		_button("Bike: %s" % _bike_name(), func():
			var ids := bikes.map(func(b): return b.id)
			bike_of[rider_name] = ids[(ids.find(_bike_id()) + 1) % ids.size()]
			_save_choices()
			_build_rider()
			_place(0.0)
			_menu())
	_button("Head start: %d m" % head_start, func():
		head_start = HEAD_STARTS[(HEAD_STARTS.find(head_start) + 1) % HEAD_STARTS.size()]
		_menu())
	var duration_row := HBoxContainer.new()
	duration_row.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_child(duration_row)
	var duration_label := Label.new()
	duration_label.text = "Survive: "
	duration_row.add_child(duration_label)
	var duration_input := SpinBox.new()
	duration_input.min_value = 1
	duration_input.max_value = 999
	duration_input.step = 1
	duration_input.value = minutes
	duration_input.suffix = "min"
	duration_input.custom_minimum_size = Vector2(180, 38)
	duration_row.add_child(duration_input)
	duration_input.value_changed.connect(func(value: float): minutes = int(value))
	var go := _button("Start riding", _start)
	go.grab_focus()
	var tip := Label.new()
	tip.text = "Pedal to stay ahead. When it lunges, escape two ways:\nSPRINT, or LEAN away: lean your body (camera),\ntilt your tablet, or a rocker plate with a phone (or arrow keys).\nGrabbed? Pedal hard to break free.%s" % [
		"\nLean: on (%s)" % HubLink.lean_source() if HubLink.lean_source() != "" else ""]
	tip.add_theme_font_size_override("font_size", 15)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(tip)


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(action)
	menu.add_child(b)
	return b


func _start() -> void:
	menu.visible = false
	state = "ride"
	paused = false
	stopped_for = 0.0
	t = 0.0
	monster_d = rider_d - head_start
	escape_grace = 0.0
	recovery_total = 0.0
	chase_effort = 0.0
	stumble = 0.0
	attack = ""
	surging = false
	surge_until = 0.0
	next_surge = WARMUP + pursuit_rng.randf_range(40.0, 75.0)
	HubLink.mark("chase started: %s, %d m head start, %d min" % [difficulty, head_start, minutes])


func _finish() -> void:
	state = "done"
	var result := "survived %d min, dodged %d, broke free %d, dragged down %d" % [minutes, dodges, escapes, catches]
	HubLink.end_mode(result)
	HubLink.set_grade(0.0)
	menu.visible = true
	for c in menu.get_children():
		c.queue_free()
	var l := Label.new()
	l.text = "You made it.\n" + result.capitalize()
	l.add_theme_font_size_override("font_size", 30)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(l)


# --- the chase -----------------------------------------------------------------------------------------------------
var _speed := 0.0
var _cadence := 0.0
var _steer := 0.0


func virtual_speed(watts: float, grade: float, mass: float) -> float:
	## The hub's road physics (bridge.virtual_speed): the speed these watts hold on this hill, m/s.
	var th := atan(grade / 100.0)
	var a := mass * 9.81 * (sin(th) + 0.005 * cos(th))
	var k := 0.5 * 1.2 * 0.40
	var lo := sqrt(-a / k) if a < 0.0 else 0.0
	var hi := 25.0
	if watts <= 0.0:
		return lo
	if hi * (a + k * hi * hi) <= watts:
		return hi
	for _i in 50:
		var mid := (lo + hi) / 2.0
		if mid * (a + k * mid * mid) < watts:
			lo = mid
		else:
			hi = mid
	return (lo + hi) / 2.0


func _mass() -> float:
	return float(HubLink.data.get("mass", 85.0))


func _monster_watts() -> float:
	var p: Dictionary = DIFFICULTY[difficulty]
	if t < WARMUP:
		return p.prowl * 0.85 * HubLink.ftp()
	var variation := 0.045 * sin(t / 9.0) + 0.025 * sin(t / 23.0 + 0.8)
	var effort := maxf(0.1, (p.surge if surging else p.prowl) + variation)
	if surging:
		# Hold the highest chase effort until an escape/reset; no hidden mid-chase easing.
		chase_effort = maxf(chase_effort, effort)
		effort = chase_effort
	return effort * HubLink.ftp()


func _process(delta: float) -> void:
	if state == "menu" and HubLink.lean_source() != last_lean_source:
		last_lean_source = HubLink.lean_source()
		_menu()
	var watts := HubLink.power()
	_speed = HubLink.speed_mps()
	_cadence = HubLink.cadence()
	if dev:
		_cadence = 80.0 if pretend > 0.0 else 0.0
		watts = pretend * HubLink.ftp()
		_speed = virtual_speed(watts, grade_at(rider_d), _mass())
	_update_pause(delta, watts > 5.0 or _cadence > 5.0)
	if state == "ride" and not paused:
		t += delta
		if attack != "grab":
			rider_d += _speed * delta
		# steering follows the screen: the camera faces the rider, so the screen's right is the rider's left
		var keys := -Input.get_axis("ui_left", "ui_right")
		dev_lean_t -= delta
		if (HubLink.lean_source() != "" or dev_lean_t > 0.0) and keys == 0.0:
			_steer = -(dev_lean if dev_lean_t > 0.0 else HubLink.lean())
			lane = move_toward(lane, _steer * LANE_MAX, 6.0 * delta)      # leaning puts you where you lean
		else:
			_steer = keys
			lane = clampf(lane + _steer * 3.0 * delta, -LANE_MAX, LANE_MAX)
		escape_grace = maxf(0.0, escape_grace - delta)
		if surging and t >= surge_until and attack == "":
			_begin_recovery("outlasted pursuit")
			HubLink.mark("outlasted pursuit; recovery window")
		if not surging and t >= next_surge and escape_grace <= 0.0:
			surging = true
			chase_effort = 0.0
			surge_until = t + CHASE_LIMIT
			HubLink.mark("monster surges")
		var vm := virtual_speed(_monster_watts(), grade_at(monster_d), _mass())
		if escape_grace > 0.0:
			vm = PRESSURE.recovery_speed(vm, escape_grace, recovery_total)
		else:
			vm = PRESSURE.speed(vm, _speed, rider_d - monster_d, t >= WARMUP, false, surging, head_start)
		if stumble > 0.0:
			stumble = maxf(0.0, stumble - delta)
		_attack(delta, watts / HubLink.ftp(), vm)
		grade_clock -= delta
		if grade_clock <= 0.0:
			grade_clock = 0.5
			HubLink.set_grade(grade_at(rider_d))
		if t >= minutes * 60.0:
			_finish()
	if state == "ride" and paused:
		grade_clock -= delta
		if grade_clock <= 0.0:
			grade_clock = 0.5
			HubLink.set_grade(0.0)
	flash.color.a = maxf(0.0, flash.color.a - delta * 0.8)
	_place(delta)
	_hud(watts)


func _attack(delta: float, effort: float, vm: float) -> void:
	## Crouch (warning) -> lunge (the escape window) -> dodged, or grabbed (the struggle).
	var p: Dictionary = DIFFICULTY[difficulty]
	if attack in ["crouch", "lunge"] and effort >= p.sprint:
		sprint_s += delta
	match attack:
		"":
			monster_d = minf(monster_d + vm * delta, rider_d - 0.5)
			if rider_d - monster_d < 8.0 and stumble <= 0.0 and escape_grace <= 0.0 and t >= WARMUP:
				attack = "crouch"
				attack_t = CROUCH
				sprint_s = 0.0
		"crouch":
			monster_d = minf(monster_d + vm * delta, rider_d - 1.0)
			attack_t -= delta
			if attack_t <= 0.0:
				attack = "lunge"
				attack_t = p.window
				lunge_lane = lane
		"lunge":
			attack_t -= delta
			if sprint_s >= SPRINT_HOLD:
				_dodged("sprint")
			elif absf(lane - lunge_lane) >= DODGE:
				_dodged("lean")
			elif attack_t <= 0.0:
				attack = "grab"
				attack_t = 0.0
				meter = 0.5
				meter_bar.visible = true
				flash.color.a = 0.35
				HubLink.mark("grabbed by the monster")
		"grab":
			attack_t += delta
			monster_d = rider_d - 0.8
			meter = clampf(meter + (effort - p.pull) * 0.3 * delta, 0.0, 1.0)      # your power against its pull
			if meter >= 1.0 or (attack_t >= GRAB_LIMIT and meter >= 0.5):
				escapes += 1
				_release(0.5, "broke free")
			elif meter <= 0.0 or attack_t >= GRAB_LIMIT:
				catches += 1
				flash.color.a = 0.6
				_release(0.3, "dragged down")


func _dodged(how: String) -> void:
	dodges += 1
	_begin_recovery("dodged")
	attack = ""
	HubLink.mark("dodged the monster (%s)" % how)


func _release(back: float, what: String) -> void:
	attack = ""
	meter_bar.visible = false
	_begin_recovery(what)
	monster_d = rider_d - head_start * back
	HubLink.mark(what)


func _begin_recovery(outcome: String) -> void:
	stumble = 2.0 if outcome == "dragged down" else 3.0
	recovery_total = PRESSURE.recovery_seconds(outcome)
	escape_grace = recovery_total
	surging = false
	chase_effort = 0.0
	surge_until = 0.0
	next_surge = t + recovery_total + pursuit_rng.randf_range(30.0, 55.0)


func _hud(watts: float) -> void:
	var gap := rider_d - monster_d
	var left := maxf(0.0, minutes * 60.0 - t)
	var mood := "waking up" if t < WARMUP else ("SURGING" if surging else "prowling")
	if state == "ride" and t >= WARMUP and not surging and next_surge - t <= WARN and escape_grace <= 0.0:
		mood = "it smells you… surge coming"
	if escape_grace > 0.0:
		mood = "stumbled!" if stumble > 0.0 else ("building speed again" if escape_grace < 4.0 else "recover — keep rolling")
	if attack == "crouch":
		mood = "IT'S CROUCHING: sprint or lean!"
	elif attack == "lunge":
		mood = "LUNGE! sprint or lean!"
	elif attack == "grab":
		mood = "GRABBED! pedal hard to break free"
		meter_bar.value = meter
		meter_bar.modulate = Color(0.4, 1, 0.6) if meter >= 0.5 else Color(1, 0.35, 0.35)
	if paused and state == "ride":
		mood = "PAUSED — pedal to resume"
	hud.text = "%s   %d:%02d left\nmonster %s\nyou %d W   %.1f km/h   hill %.1f%%\ngap %d m   dodged %d   broke free %d   dragged down %d%s" % [
		"" if HubLink.connected else "looking for the hub…", int(left) / 60, int(left) % 60,
		mood, watts, _speed * 3.6, grade_at(rider_d), int(gap), dodges, escapes, catches,
		("\n[dev: pretend %d%% FTP]" % int(pretend * 100) if dev else "") + ("\nlean %+.2f" % HubLink.lean() if HubLink.lean_source() != "" else "")]
	gap_bar.value = clampf(gap, 0.0, 200.0)
	gap_bar.modulate = Color(1, 0.3, 0.3) if gap < 25.0 else (Color(1, 0.8, 0.3) if gap < 60.0 else Color(0.4, 1, 0.6))


func _update_pause(delta: float, pedaling: bool) -> void:
	if state != "ride":
		paused = false
		stopped_for = 0.0
		return
	stopped_for = 0.0 if pedaling else stopped_for + delta
	paused = stopped_for >= 2.0


func _leave() -> void:
	if state == "ride":
		HubLink.end_mode("left the chase after %d:%02d" % [int(t) / 60, int(t) % 60])
		state = "left"
	HubLink.set_grade(0.0)
	if OS.has_feature("web"):
		# inside the Ride page: hand back to it (it opens the Ride menu); on its own: back to the Ride page
		# to the Hub page, whose address differs from the game's own; the message carries nothing, and the Hub checks
		# that it really came from this game's frame (module-host.js)
		JavaScriptBridge.eval("window.parent !== window ? window.parent.postMessage({type: 'hub-leave-mode'}, '*') : location.assign('/ride')", true)
	else:
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_leave()
		return
	if dev and event is InputEventKey and event.pressed and event.keycode >= KEY_0 and event.keycode <= KEY_9:
		pretend = (event.keycode - KEY_0) * 0.15          # 1 = 15% FTP ... 7 = 105% ... 9 = 135%
	if dev and event is InputEventKey and event.pressed and event.keycode in [KEY_Z, KEY_X]:
		dev_lean = -1.0 if event.keycode == KEY_Z else 1.0
		dev_lean_t = 1.5
	if dev and event is InputEventKey and event.pressed and event.keycode == KEY_A and state == "ride" and attack == "":
		t = maxf(t, WARMUP)
		escape_grace = 0.0
		monster_d = rider_d - 7.5
		stumble = 0.0
	if dev and event is InputEventKey and event.pressed and event.keycode == KEY_G and state == "ride":
		attack = "grab"
		attack_t = 0.0
		meter = 0.5
		meter_bar.visible = true
		stumble = 0.0
		pretend = DIFFICULTY[difficulty].pull
	if dev and event is InputEventKey and event.pressed and event.keycode in [KEY_BRACKETLEFT, KEY_BRACKETRIGHT]:
		sky_turn += PI / 2.0 if event.keycode == KEY_BRACKETRIGHT else -PI / 2.0


func _exit_tree() -> void:
	if state == "ride":                         # closed without Exit (tab closed, view changed)
		HubLink.end_mode("left the chase")
	HubLink.set_grade(0.0)

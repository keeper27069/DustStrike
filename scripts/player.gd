extends CharacterBody3D

var game: Node3D
var team = "CT"
var hp = 100.0
var armor = 100.0
var alive = true
var kills = 0
var deaths = 0
var cash = 800
var cam: Camera3D
var rig: Node3D
var gun: Node3D
var flash: MeshInstance3D
var pitch = 0.0
var sensitivity = 0.0017
var recoil = Vector2.ZERO
var recoil_speed = 0.0
var shot_count = 0
var fire_cd = 0.0
var reload_left = 0.0
var reload_total = 0.0
var flash_left = 0.0
var step_clock = 0.0
var scoped = false
var crouched = false
var equip_id = "usp"
var primary = ""
var secondary = "usp"
var ammo: Dictionary = {}
var utility = {"he": 1, "smoke": 1, "flash": 2, "fire": 1, "decoy": 1}
var selected_utility = "he"
var arm_animation = 0.0
var burst = false
var burst_remaining = 0
var suppressed = true
var body_shape: CollisionShape3D
var has_zeus = false
var zeus_charge = 0.0
var step_camera_offset = 0.0
var eye_height = 1.62

func _ready() -> void:
	collision_layer = 2
	collision_mask = 3
	floor_snap_length = 0.5
	floor_constant_speed = true
	var shape = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.78
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	body_shape = shape
	cam = Camera3D.new()
	cam.position.y = 1.62
	step_camera_offset = 0.0
	eye_height = 1.62
	cam.fov = 82
	cam.near = 0.035
	cam.far = 220
	add_child(cam)
	rig = Node3D.new()
	cam.add_child(rig)
	rig.scale = Vector3.ONE * .76
	rig.position = Vector3(0.24, -0.22, -0.35)
	flash = MeshInstance3D.new()
	var m = SphereMesh.new()
	m.radius = 0.075
	m.height = 0.12
	flash.mesh = m
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0.76, 0.23)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.45, 0.05)
	mat.emission_energy_multiplier = 3
	flash.material_override = mat
	flash.position = Vector3(0, 0.065, -0.94)
	flash.visible = false
	rig.add_child(flash)
	# Forearms and gloves stay in the viewmodel's own close-up space.
	for x in [-0.14, 0.06]:
		var arm = MeshInstance3D.new()
		var mesh = CapsuleMesh.new()
		mesh.radius = 0.053
		mesh.height = 0.34
		arm.mesh = mesh
		arm.rotation.x = PI / 2
		arm.position = Vector3(x, -0.13, -0.05 if x > 0 else -0.35)
		var material = StandardMaterial3D.new()
		material.albedo_color = Color(0.13, 0.17, 0.18)
		arm.material_override = material
		rig.add_child(arm)

func reset_round(spawn: Vector3, side: String, starting: bool) -> void:
	collision_layer = 2
	team = side
	global_position = spawn
	rotation.y = 0.0 if team == "T" else PI
	pitch = 0
	recoil = Vector2.ZERO
	velocity = Vector3.ZERO
	hp = 100
	alive = true
	cam.current = true
	cam.position.y = 1.62
	step_camera_offset = 0.0
	eye_height = 1.62
	reload_left = 0
	burst_remaining = 0
	scoped = false
	if starting:
		has_zeus = false
		armor = 0
		cash = 16000 if game.practice else 800
		primary = "ak" if game.practice and team == "T" else "m4" if game.practice else ""
		secondary = "glock" if team == "T" else "usp"
		ammo.clear()
		utility = {"he": 1, "smoke": 1, "flash": 2, "fire": 1, "decoy": 1} if game.practice else {"he": 0, "smoke": 0, "flash": 0, "fire": 0, "decoy": 0}
		if game.practice: armor = 100
	for id in [primary, secondary]:
		if id != "":
			var w: Dictionary = game.weapons[id]
			ammo[id] = [int(w.mag), int(w.reserve)]
	equip(primary if primary != "" else secondary)

func equip(id: String) -> void:
	if id == "": return
	equip_id = id
	reload_left = 0
	scoped = false
	shot_count = 0
	burst_remaining = 0
	if is_instance_valid(gun): gun.queue_free()
	gun = Node3D.new()
	rig.add_child(gun)
	if id == "knife":
		var blade = MeshInstance3D.new()
		var mesh = PrismMesh.new()
		mesh.size = Vector3(0.045, 0.012, 0.27)
		blade.mesh = mesh
		blade.position.z = -0.23
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.6, 0.62, 0.61)
		mat.metallic = 0.9
		blade.material_override = mat
		gun.add_child(blade)
	else:
		var source: Node3D = game.arsenal.find_child("W_" + ("p250" if id == "zeus" else id), true, false)
		if source:
			var model = source.duplicate() as Node3D
			gun.add_child(model)
			if id == "dual":
				var second = source.duplicate() as Node3D
				second.position.x = -.46
				gun.add_child(second)
		if not ammo.has(id):
			var w: Dictionary = game.weapons[id]
			ammo[id] = [int(w.mag), int(w.reserve)]
	arm_animation = 0.35

func _unhandled_input(event: InputEvent) -> void:
	if not game or game.state == "menu": return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and alive:
		rotation.y -= event.relative.x * sensitivity * (0.35 if scoped else 1.0)
		pitch = clampf(pitch - event.relative.y * sensitivity * (0.35 if scoped else 1.0), -1.45, 1.45)
	if game.ui_blocked() or not alive: return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT: shoot()
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if equip_id == "knife": shoot(true)
			elif game.weapons[equip_id].category == "Snipers" or equip_id in ["aug", "sg"]: scoped = not scoped
			elif equip_id in ["glock", "famas"]:
				burst = not burst
				game.notice("Режим: " + ("очередь по 3" if burst else "обычный"))
			elif equip_id in ["usp", "m4s"]:
				suppressed = not suppressed
				game.notice("Глушитель: " + ("включён" if suppressed else "снят"))
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: equip(primary if equip_id != primary and primary != "" else secondary)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: equip(secondary if equip_id != secondary else "knife")
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R: reload_weapon()
			KEY_1: equip(primary)
			KEY_2: equip(secondary)
			KEY_3: equip("knife")
			KEY_5:
				if has_zeus: equip("zeus")
			KEY_4:
				var kinds = ["he", "smoke", "flash", "fire", "decoy"]
				selected_utility = kinds[(kinds.find(selected_utility) + 1) % kinds.size()]
				game.notice("Граната: " + game.utility_names[selected_utility])
			KEY_G: throw_grenade()
			KEY_F: arm_animation = 1.6

func _physics_process(dt: float) -> void:
	if not game or game.state == "menu": return
	if game.paused: return
	if zeus_charge > 0:
		zeus_charge -= dt
		if zeus_charge <= 0 and ammo.has("zeus"): ammo.zeus[0] = 1
	fire_cd = maxf(0, fire_cd - dt)
	flash_left = maxf(0, flash_left - dt)
	flash.visible = flash_left > 0 and alive and not scoped
	arm_animation = maxf(0, arm_animation - dt)
	recoil = recoil.lerp(Vector2.ZERO, dt * 7)
	cam.rotation = Vector3(pitch + recoil.x, recoil.y, 0)
	cam.fov = lerpf(cam.fov, 28.0 if scoped else 82.0, dt * 14)
	rig.visible = alive and not scoped
	if reload_left > 0:
		reload_left -= dt
		if reload_left <= 0:
			var w: Dictionary = game.weapons[equip_id]
			var take = mini(int(w.mag) - int(ammo[equip_id][0]), int(ammo[equip_id][1]))
			ammo[equip_id][0] += take
			ammo[equip_id][1] -= take
			game.sound("reload", global_position)
	if not alive:
		cam.position.y = lerpf(cam.position.y, 0.45, dt * 2)
		return
	var can_move = game.state == "live" and not game.ui_blocked()
	crouched = Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_C)
	if not crouched and body_shape.shape.height < 1.7:
		var check = PhysicsRayQueryParameters3D.create(global_position+Vector3.UP,global_position+Vector3.UP*1.85,1)
		if not get_world_3d().direct_space_state.intersect_ray(check).is_empty(): crouched = true
	body_shape.shape.height = 1.15 if crouched else 1.78
	body_shape.position.y = 0.585 if crouched else .9
	var walking = Input.is_physical_key_pressed(KEY_SHIFT)
	var direction = Vector3.ZERO
	if can_move:
		var input = Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		direction = (basis * Vector3(input.x, 0, input.y)).normalized()
	var speed = 5.4
	if equip_id == "knife": speed = 6.25
	elif equip_id != "knife" and game.weapons[equip_id].category == "Snipers": speed = 4.5
	if walking: speed *= 0.48
	if crouched: speed *= 0.38
	var accel = 42.0 if is_on_floor() else 6.0
	velocity.x = move_toward(velocity.x, direction.x * speed, accel * dt)
	velocity.z = move_toward(velocity.z, direction.z * speed, accel * dt)
	var grounded = is_on_floor()
	var old_y = global_position.y
	var jumping = can_move and grounded and Input.is_physical_key_pressed(KEY_SPACE)
	velocity.y = -0.1 if grounded else velocity.y - 19.6 * dt
	if jumping: velocity.y = 6.4
	if grounded and not jumping and direction.length() > .1: step_up(direction)
	move_and_slide()
	if not jumping and velocity.y <= 0: apply_floor_snap()
	if grounded and not jumping and absf(global_position.y-old_y)<.51:
		step_camera_offset = clampf(step_camera_offset-(global_position.y-old_y),-.45,.45)
	step_camera_offset = move_toward(step_camera_offset,0.0,dt*2.4)
	eye_height = lerpf(eye_height,1.06 if crouched else 1.62,dt*12)
	cam.position.y = eye_height + step_camera_offset
	var moving = Vector2(velocity.x, velocity.z).length()
	if moving > 0.8 and is_on_floor():
		step_clock += dt * (0.7 if walking else 1.0)
		if step_clock > 0.38:
			step_clock = 0
			if not walking and not crouched: game.sound("step", global_position)
	rig.position = Vector3(0.23, -0.23, -0.43) + Vector3(0,0,minf(fire_cd, 0.1)*.4)
	rig.rotation = Vector3(0, 0, 0)
	if reload_left > 0:
		var f = sin((1 - reload_left / reload_total) * PI)
		rig.rotation.z = -0.7 * f
		rig.rotation.x = -0.55 * f
		rig.position.y -= 0.13 * f
	elif arm_animation > 0:
		rig.rotation.z = sin(arm_animation * 3.0) * 0.5
	if can_move and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and equip_id != "knife" and bool(game.weapons[equip_id].auto) and not (burst and equip_id == "famas"): shoot()
	if can_move and burst_remaining > 0 and fire_cd <= 0:
		shoot(false, true)
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and fire_cd <= 0: shot_count = maxi(0, shot_count - 1)

func step_up(direction: Vector3) -> void:
	var obstacle = KinematicCollision3D.new()
	if not test_move(global_transform,direction*.2,obstacle): return
	# Slopes already work through move_and_slide; other players are not steps.
	if obstacle.get_normal().y > .2: return
	var collider = obstacle.get_collider()
	if not collider is StaticBody3D: return
	var raised = global_transform.translated(Vector3.UP*.44)
	if test_move(global_transform,Vector3.UP*.44) or test_move(raised,direction*.22): return
	var landing = KinematicCollision3D.new()
	if not test_move(raised.translated(direction*.22),Vector3.DOWN*.49,landing): return
	if landing.get_normal().y < .7 or not landing.get_collider() is StaticBody3D: return
	var rise = .44 + landing.get_travel().y
	if rise > .025 and rise <= .44:
		global_position.y += rise

func shoot(heavy_slash := false, in_burst := false) -> void:
	if not alive or game.state != "live" or game.ui_blocked() or fire_cd > 0 or reload_left > 0: return
	if equip_id == "knife":
		fire_cd = 0.85 if heavy_slash else 0.45
		arm_animation = 0.4
		game.trace_shot(self, cam.global_position, -cam.global_basis.z, 65 if heavy_slash else 35, 2.2, false)
		game.sound("knife", global_position)
		return
	var w: Dictionary = game.weapons[equip_id]
	if int(ammo[equip_id][0]) <= 0:
		reload_weapon()
		return
	ammo[equip_id][0] -= 1
	if equip_id == "zeus": zeus_charge = 30
	fire_cd = 60.0 / float(w.rpm)
	if burst and equip_id in ["glock", "famas"]:
		if not in_burst: burst_remaining = 2
		else: burst_remaining -= 1
		fire_cd = 0.07 if burst_remaining > 0 else 0.35
	flash_left = 0.045
	var spread = 0.002 + minf(shot_count, 15) * 0.0008
	spread += Vector2(velocity.x, velocity.z).length() * 0.003
	if not is_on_floor(): spread += 0.045
	if crouched: spread *= 0.65
	if w.category == "Snipers" and not scoped: spread += 0.065
	if scoped: spread *= 0.3
	var pellets = 8 if equip_id in ["nova", "xm", "mag7", "sawed"] else 1
	if pellets > 1: spread += 0.048
	for i in pellets:
		var dir = (-cam.global_basis.z + cam.global_basis.x * randfn(0, spread) + cam.global_basis.y * randfn(0, spread)).normalized()
		game.trace_shot(self, cam.global_position, dir, float(w.damage), 4.0 if equip_id == "zeus" else 150.0, true)
	shot_count += 1
	recoil.x += float(w.recoil) * 0.023
	recoil.y += sin(shot_count * 1.73) * float(w.recoil) * 0.012
	pitch = clampf(pitch + float(w.recoil) * 0.0028, -1.45, 1.45)
	game.sound("sniper" if w.category == "Snipers" else "silenced" if equip_id in ["usp", "m4s", "mp5"] and suppressed else "shot", global_position)

func reload_weapon() -> void:
	if equip_id == "knife" or reload_left > 0: return
	var w: Dictionary = game.weapons[equip_id]
	if int(ammo[equip_id][0]) >= int(w.mag) or int(ammo[equip_id][1]) <= 0: return
	reload_total = float(w.reload)
	reload_left = reload_total
	scoped = false
	game.sound("reload", global_position)

func throw_grenade() -> void:
	if game.state != "live" or int(utility[selected_utility]) <= 0: return
	utility[selected_utility] -= 1
	game.throw_utility(self, selected_utility, cam.global_position - cam.global_basis.z * 0.6, -cam.global_basis.z * 15 + Vector3.UP * 3)
	arm_animation = 0.55

func take_damage(amount: float, attacker: Node, headshot := false) -> void:
	if not alive: return
	var actual = amount
	if armor > 0:
		actual *= 0.62
		armor = maxf(0, armor - amount * 0.38)
	hp -= actual
	game.hurt_alpha = 0.38
	game.sound("hit", global_position)
	if hp <= 0:
		hp = 0
		alive = false
		collision_layer = 0
		deaths += 1
		game.actor_killed(self, attacker, headshot)

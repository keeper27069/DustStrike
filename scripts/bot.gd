extends CharacterBody3D

const OperatorAnimation = preload("res://scripts/operator_animation.gd")

var game: Node3D
var team = "T"
var nick = "BOT"
var hp = 100.0
var armor = 65.0
var alive = true
var kills = 0
var deaths = 0
var model: Node3D
var operator_animation: RefCounted
var path: Array[Vector3] = []
var destination = Vector3.ZERO
var think_left = 0.0
var fire_cd = 0.0
var reaction = 0.0
var target: Node3D
var bot_index = 0
var shots = 0
var reload_left = 0.0
var goal_id = 0
var age = 0.0
var stuck = 0.0
var avoidance_left = 0.0
var avoidance_direction = Vector3.ZERO
var recovery_attempts = 0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var cs = CollisionShape3D.new()
	var cap = CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.83
	cs.shape = cap
	cs.position.y = 0.92
	add_child(cs)
	model = load("res://assets/operator_" + team.to_lower() + ".glb").instantiate()
	add_child(model)
	operator_animation = OperatorAnimation.new(model)
	reaction = randf_range(0.5, 1.0)
	think_left = randf() * 0.7
	floor_snap_length = 0.45
	floor_constant_speed = true

func _physics_process(dt: float) -> void:
	if game.paused: return
	if not alive or game.state != "live":
		operator_animation.update(dt, 0.0, false, false)
		return
	age += dt
	think_left -= dt
	fire_cd -= dt
	reload_left -= dt
	if think_left <= 0:
		think_left = randf_range(0.25, 0.45)
		find_target()
		if not is_instance_valid(target): choose_path()
	var wish = Vector3.ZERO
	if is_instance_valid(target) and target.alive:
		var to: Vector3 = target.global_position - global_position
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), dt * 9)
		reaction -= dt
		if reaction <= 0 and fire_cd <= 0 and reload_left <= 0:
			fire_cd = randf_range(0.19, 0.37)
			shots += 1
			if shots >= 24:
				shots = 0
				reload_left = 2.6
				operator_animation.play_reload(reload_left)
			else:
				var from = global_position + Vector3.UP * 1.35
				var aim: Vector3 = target.global_position + Vector3.UP * (1.0 if target == game.player and target.crouched else 1.25)
				var spread = 0.04 if target == game.player else 0.03
				if game.practice: spread *= 1.4
				var dir = (aim - from).normalized() + Vector3(randfn(0, spread), randfn(0, spread), randfn(0, spread))
				game.trace_shot(self, from, dir.normalized(), 22.0, 90, true)
				game.sound("botshot", global_position)
				game.muzzle(from - global_basis.z * 0.75)
				operator_animation.play_fire()
		# Controlled short strafes, without abandoning cover or objective.
		if to.length() > 7:
			wish = global_basis.x * sin(age * 1.7 + bot_index) * 1.5
	else:
		if path.size() > 0:
			var delta = path[0] - global_position
			delta.y = 0
			if delta.length() < 0.65: path.pop_front()
			else:
				wish = delta.normalized() * 3.7
				rotation.y = lerp_angle(rotation.y, atan2(-delta.x, -delta.z), dt * 7)
		else:
			rotation.y += sin(age * 0.7 + bot_index) * dt * 0.15
	var actual_speed = move_wish(wish, dt)
	operator_animation.update(dt, actual_speed, is_instance_valid(target) and target.alive)
	game.bot_objective(self, dt)

func move_wish(wish: Vector3, dt: float) -> float:
	# Keep ramps on Godot's floor solver; stepping is only for vertical ledges.
	if avoidance_left > 0.0:
		avoidance_left = maxf(0.0, avoidance_left - dt)
		wish = avoidance_direction * minf(wish.length(), 2.5)
	velocity.x = move_toward(velocity.x, wish.x, dt * 25)
	velocity.z = move_toward(velocity.z, wish.z, dt * 25)
	var grounded = is_on_floor()
	velocity.y = -0.1 if grounded else velocity.y - 20.0 * dt
	if grounded and wish.length() > 0.1: step_up(wish.normalized())
	var old = global_position
	move_and_slide()
	if grounded and velocity.y <= 0.0: apply_floor_snap()
	var traveled = global_position - old
	var actual_speed = Vector2(traveled.x, traveled.z).length() / maxf(dt, 0.0001)
	if wish.length() > 1.0 and actual_speed < 0.2:
		stuck += dt
		if stuck > 0.8:
			path.clear()
			think_left = 0
			avoid_obstacle(wish)
			stuck = 0
	else: stuck = 0
	return actual_speed

func step_up(direction: Vector3) -> void:
	var obstacle = KinematicCollision3D.new()
	if not test_move(global_transform, direction * 0.2, obstacle): return
	if obstacle.get_normal().y > 0.2 or not obstacle.get_collider() is StaticBody3D: return
	var raised = global_transform.translated(Vector3.UP * 0.44)
	if test_move(global_transform, Vector3.UP * 0.44) or test_move(raised, direction * 0.22): return
	var landing = KinematicCollision3D.new()
	if not test_move(raised.translated(direction * 0.22), Vector3.DOWN * 0.49, landing): return
	if landing.get_normal().y < 0.7 or not landing.get_collider() is StaticBody3D: return
	var rise = 0.44 + landing.get_travel().y
	if rise > 0.025 and rise <= 0.44: global_position.y += rise

func avoid_obstacle(wish: Vector3) -> void:
	# A blocked route triggers a new path and a short sidestep, never a jump.
	recovery_attempts += 1
	avoidance_direction = Vector3.ZERO
	for i in get_slide_collision_count():
		var normal = get_slide_collision(i).get_normal()
		if absf(normal.y) > 0.2: continue
		var tangent = Vector3(-normal.z, 0.0, normal.x).normalized()
		var alignment = tangent.dot(wish)
		if alignment < -0.1 or (absf(alignment) <= 0.1 and recovery_attempts % 2 == 0): tangent = -tangent
		if test_move(global_transform, tangent * 0.5): tangent = -tangent
		if not test_move(global_transform, tangent * 0.5): avoidance_direction = tangent
		break
	avoidance_left = 0.65 if avoidance_direction.length_squared() > 0.1 else 0.0

func find_target() -> void:
	var best: Node3D = null
	var distance = 65.0
	for actor in game.actors():
		if actor == self or not actor.alive or actor.team == team: continue
		var d: float = global_position.distance_to(actor.global_position)
		if d < distance and game.can_see(self, actor):
			best = actor
			distance = d
	if best != target: reaction = randf_range(0.5, 0.95)
	target = best

func choose_path() -> void:
	var goal: Vector3 = game.bot_goal(self)
	if destination.distance_to(goal) > 2 or path.is_empty():
		destination = goal
		path = game.find_path(global_position, goal)

func take_damage(amount: float, attacker: Node, headshot := false) -> void:
	if not alive: return
	var actual = amount
	if armor > 0:
		actual *= 0.62
		armor = maxf(0, armor - amount * 0.38)
	hp -= actual
	if is_instance_valid(attacker) and attacker != self and attacker.team != team:
		target = attacker
		reaction = 0.18
	if hp <= 0:
		hp = 0
		alive = false
		deaths += 1
		collision_layer = 0
		game.actor_killed(self, attacker, headshot)
		if not operator_animation.play_death():
			var tween = create_tween()
			tween.tween_property(model, "rotation:z", 1.5 if randf() > 0.5 else -1.5, 0.35)
			tween.parallel().tween_property(model, "position:y", 0.2, 0.35)

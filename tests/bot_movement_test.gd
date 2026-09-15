extends SceneTree

const Bot = preload("res://scripts/bot.gd")
const DT = 1.0 / 60.0
var world: Node3D
var bot: CharacterBody3D

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		push_error("BOT MOVEMENT FAILED: " + message)
		quit(1)
		assert(value, message)

func box(at: Vector3, size: Vector3) -> void:
	var body = StaticBody3D.new()
	body.position = at
	var collider = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)

func reset_bot(at: Vector3) -> void:
	bot.position = at
	bot.velocity = Vector3.ZERO
	bot.stuck = 0.0
	bot.avoidance_left = 0.0
	bot.avoidance_direction = Vector3.ZERO
	bot.recovery_attempts = 0
	bot.path.clear()
	for i in 8:
		await physics_frame
		bot.move_wish(Vector3.ZERO, DT)
	check(bot.is_on_floor(), "route starts grounded")

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	box(Vector3(25, -0.5, 0), Vector3(80, 1, 30))
	box(Vector3(12, 0.15, 0), Vector3(6, 0.3, 3))
	box(Vector3(33.5, 1.0, 0), Vector3(7, 2, 4))
	box(Vector3(50, 0.6, 0), Vector3(1, 1.2, 15))
	var ramp = StaticBody3D.new()
	var ramp_collider = CollisionShape3D.new()
	var ramp_shape = ConcavePolygonShape3D.new()
	# A continuous 20% grade: x=20 at floor level to x=30 at y=2.
	ramp_shape.set_faces(PackedVector3Array([
		Vector3(20, 0, -2), Vector3(30, 2, -2), Vector3(30, 2, 2),
		Vector3(20, 0, -2), Vector3(30, 2, 2), Vector3(20, 0, 2)]))
	ramp_collider.shape = ramp_shape
	ramp.add_child(ramp_collider)
	world.add_child(ramp)
	bot = Bot.new()
	world.add_child(bot)
	bot.set_physics_process(false)
	for i in 3: await physics_frame
	await reset_bot(Vector3(-5, 0.025, 0))
	var max_lift = 0.0
	for i in 120:
		await physics_frame
		bot.move_wish(Vector3.RIGHT * 3.7, DT)
		max_lift = maxf(max_lift, absf(bot.position.y))
		check(bot.is_on_floor(), "flat movement stays grounded")
	check(bot.position.x > 2.0 and max_lift < 0.015, "flat movement has no lift")
	print("BOT FLAT PASS: max lift=", max_lift)
	await reset_bot(Vector3(18, 0.025, 0))
	for direction in [1.0, -1.0]:
		var max_gap = 0.0
		var max_rise = 0.0
		var previous: float = bot.position.y
		for i in 245:
			await physics_frame
			bot.move_wish(Vector3.RIGHT * direction * 3.7, DT)
			var floor_y = clampf((bot.position.x - 20.0) * 0.2, 0.0, 2.0)
			max_gap = maxf(max_gap, absf(bot.position.y - floor_y))
			max_rise = maxf(max_rise, absf(bot.position.y - previous))
			previous = bot.position.y
			check(bot.is_on_floor(), "incline and descent stay grounded")
		check(bot.position.x > 32.0 if direction > 0.0 else bot.position.x < 19.0, "bot completes the entire slope")
		check(max_gap < 0.025 and max_rise < 0.025, "ramp motion follows grade without jumping")
		print("BOT RAMP ", direction, " PASS: max floor gap=", max_gap, " max y/frame=", max_rise, " end=", bot.position)
	await reset_bot(Vector3(6, 0.025, 0))
	var max_height = 0.0
	for i in 125:
		await physics_frame
		bot.move_wish(Vector3.RIGHT * 3.7, DT)
		max_height = maxf(max_height, bot.position.y)
	check(bot.position.x > 12.0 and bot.position.y > 0.27, "bot climbs a 30 cm step")
	check(max_height < 0.32 and bot.is_on_floor(), "step height is measured, with no 44 cm launch")
	print("BOT STEP PASS: height=", max_height, " end=", bot.position)
	await reset_bot(Vector3(47, 0.025, 0))
	bot.path.append(Vector3(55, 0, 0))
	bot.think_left = 10.0
	max_height = 0.0
	for i in 180:
		await physics_frame
		bot.move_wish(Vector3.RIGHT * 3.7, DT)
		max_height = maxf(max_height, bot.position.y)
		check(bot.velocity.y <= 0.01, "blocked NPC never receives jump velocity")
	check(bot.position.x < 49.25 and max_height < 0.025, "tall wall cannot be stepped onto")
	check(bot.path.is_empty() and bot.think_left == 0.0 and bot.recovery_attempts > 0, "blocked route requests a new path")
	check(absf(bot.position.z) > 0.5, "blocked NPC attempts a ground sidestep")
	print("BOT WALL / REPATH PASS: height=", max_height, " end=", bot.position)
	await reset_bot(Vector3(0, 0.025, 5))
	bot.position.y = 3.0
	bot.velocity = Vector3.ZERO
	await physics_frame
	bot.move_wish(Vector3.ZERO, DT)
	check(bot.position.y > 2.9 and not bot.is_on_floor(), "airborne bot falls normally instead of snapping to the floor")
	for i in 70:
		await physics_frame
		bot.move_wish(Vector3.ZERO, DT)
		if bot.position.y > 0.02: check(not bot.is_on_floor(), "falling bot does not snap down early")
	check(bot.is_on_floor() and absf(bot.position.y) < 0.015, "falling bot lands normally")
	if "--map" in OS.get_cmdline_user_args(): await test_map_slopes()
	print("BOT MOVEMENT PASS")
	quit(0)

func test_map_slopes() -> void:
	world.queue_free()
	await process_frame
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	while not is_instance_valid(game.hud): await process_frame
	game.set_process(false)
	game.player.set_physics_process(false)
	bot = Bot.new()
	bot.game = game
	game.add_child(bot)
	bot.set_physics_process(false)
	for i in 3: await physics_frame
	var routes = [
		{"name":"A approach", "at":Vector3(32.8, 1.4, -63.1), "direction":Vector3.FORWARD},
		{"name":"mid / B incline", "at":Vector3(-22.78, -1.98, -54.14), "direction":Vector3.LEFT}]
	for route in routes:
		await reset_bot(route.at)
		for sign_direction in [1.0, -1.0]:
			var start: Vector3 = bot.position
			var previous: float = bot.position.y
			var max_gap = 0.0
			var max_change = 0.0
			for i in 75:
				await physics_frame
				bot.move_wish(route.direction * sign_direction * 3.7, DT)
				var ray = PhysicsRayQueryParameters3D.create(bot.position + Vector3.UP, bot.position - Vector3.UP, 1)
				var floor_hit = game.get_world_3d().direct_space_state.intersect_ray(ray)
				check(not floor_hit.is_empty() and bot.is_on_floor(), "map ramp remains supported")
				max_gap = maxf(max_gap, absf(bot.position.y - floor_hit.position.y))
				max_change = maxf(max_change, absf(bot.position.y - previous))
				previous = bot.position.y
			check(Vector2(bot.position.x - start.x, bot.position.z - start.z).length() > 3.3, "bot traverses map ramp")
			check(max_gap < 0.035 and max_change < 0.035, "actual map ramps do not launch NPCs")
			print("BOT MAP ", route.name, " ", sign_direction, " PASS: max floor gap=", max_gap, " max y/frame=", max_change)

extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		push_error("GAMEPLAY FIXES FAILED: " + message)
		quit(1)
		assert(value,message)

func box(parent: Node, at: Vector3, size: Vector3) -> void:
	var body = StaticBody3D.new()
	body.position = at
	var collider = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	parent.add_child(body)

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	while not is_instance_valid(game.hud): await process_frame
	game.self_test = true
	game.set_process(false)
	for team in ["CT","T"]:
		game.selected_team = team
		game.start_match()
		for round_index in 3:
			if round_index > 0: game.start_round()
			var actors = game.actors()
			check(actors.size() == 10,"all ten players spawn")
			for i in actors.size():
				for j in range(i+1,actors.size()):
					var a: Vector3 = actors[i].position
					var b: Vector3 = actors[j].position
					check(Vector2(a.x-b.x,a.z-b.z).length() >= 1.35,"spawn capsules do not overlap")
			var start_y: float = game.player.position.y
			for i in 20: await physics_frame
			check(absf(game.player.position.y-start_y)<.1,"player stays on the ground after spawning")
			check(game.player.is_on_floor(),"spawn has a supporting floor")
	print("SPAWNS PASS: CT and T, three rounds each, ten distinct ground positions")
	var ally: Node3D
	var enemy: Node3D
	for bot in game.bots:
		bot.set_physics_process(false)
		if bot.team == game.player.team: ally = bot
		else: enemy = bot
	var kills: int = game.player.kills
	game.actor_killed(enemy,game.player,true)
	check(game.killfeed[0].killer_team == "T" and game.killfeed[0].victim_team == "CT","enemy teams are recorded separately")
	check(not game.killfeed[0].friendly and game.killfeed[0].headshot,"enemy kill is not labeled friendly")
	check(game.player.kills == kills+1,"enemy elimination is rewarded")
	kills = game.player.kills
	game.actor_killed(ally,game.player,false)
	check(game.killfeed[0].friendly and game.player.kills == kills,"actual friendly fire is labeled without kill reward")
	game.actor_killed(game.player,game.player,false)
	check(game.killfeed[0].self and not game.killfeed[0].friendly,"self elimination is distinct")
	game.spectator.stop()
	game.actor_killed(game.player,null,false)
	check(game.killfeed[0].killer_team == "","environment damage has no fake team")
	game.spectator.stop()
	game.killfeed.clear()
	game.actor_killed(enemy,game.player,true)
	game.actor_killed(ally,enemy,false)
	for kind in game.GRENADE_FUSES:
		game.throw_utility(game.player,kind,Vector3(200,5,0),Vector3.ZERO)
		check(is_equal_approx(game.grenades[0].time,game.GRENADE_FUSES[kind]),"grenade uses its fuse")
		game.update_effects(2.0)
		check(game.grenades.size() == 1,"grenade does not explode within two seconds")
		game.update_effects(float(game.GRENADE_FUSES[kind])-2.0+.01)
		check(game.grenades.is_empty(),"grenade detonates at the new deadline")
	print("FEED / FUSES PASS: separate teams, friendly/self/environment, all five grenade deadlines")
	if "--capture" in OS.get_cmdline_user_args():
		game.state = "live"
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("DUST_QA_DIR")+"/gameplay-fixes.png")
	if DisplayServer.get_name().to_lower() != "headless":
		var p = game.player
		p.set_physics_process(false)
		p.set_process_unhandled_input(false)
		box(game,Vector3(200,-.5,0),Vector3(30,1,30))
		box(game,Vector3(200,.15,-4),Vector3(4,.3,4))
		box(game,Vector3(210,.6,-4),Vector3(4,1.2,4))
		for i in 2: await physics_frame
		game.state = "live"
		game.paused = false
		game.buying = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		var key = InputEventKey.new()
		key.physical_keycode = KEY_W
		key.keycode = KEY_W
		key.pressed = true
		Input.parse_input_event(key.duplicate())
		Input.flush_buffered_events()
		check(Input.is_physical_key_pressed(KEY_W),"test drives actual physical keyboard input")
		for route in ["flat","step","wall"]:
			p.reset_round(Vector3(207 if route == "flat" else 200 if route == "step" else 210,.025,2),"T",true)
			var previous: float = p.cam.global_position.y
			var max_change = 0.0
			var max_body = 0.0
			for i in (75 if route == "step" else 95):
				await physics_frame
				Input.parse_input_event(key.duplicate())
				Input.flush_buffered_events()
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				p._physics_process(1.0/60.0)
				var eye: float = p.cam.global_position.y
				if i > 10: max_change = maxf(max_change,absf(eye-previous))
				previous = eye
				max_body = maxf(max_body,p.position.y)
				check(absf(p.rig.position.y+.23)<.001,"walking never bobs the gun")
			print("MOVEMENT ",route," end=",p.position," max body=",max_body," max camera/frame=",max_change)
			if route == "flat":
				check(p.position.z < -5 and max_change < .005,"flat walking has no camera bounce")
			elif route == "step":
				check(p.position.z < -3 and p.position.y > .27,"player climbs the actual 30 cm step")
				check(max_body < .34 and max_change <= .055,"step never launches the player and camera rise is smooth")
			else:
				check(p.position.z > -2 and p.position.z < -1 and max_body < .05,"player reaches the tall wall but cannot climb it")
		key.pressed = false
		Input.parse_input_event(key.duplicate())
		Input.flush_buffered_events()
		p.reset_round(Vector3(207,.025,2),"T",true)
		for i in 5:
			await physics_frame
			p._physics_process(1.0/60.0)
		var jump = InputEventKey.new()
		jump.keycode = KEY_SPACE
		jump.physical_keycode = KEY_SPACE
		jump.pressed = true
		Input.parse_input_event(jump.duplicate())
		Input.flush_buffered_events()
		p._physics_process(1.0/60.0)
		jump.pressed = false
		Input.parse_input_event(jump.duplicate())
		Input.flush_buffered_events()
		var apex = 0.0
		for i in 60:
			await physics_frame
			p._physics_process(1.0/60.0)
			apex = maxf(apex,p.position.y)
		check(apex > .8 and p.is_on_floor(),"intentional Space jump still rises and lands")
		print("JUMP PASS: apex=",apex)
	print("GAMEPLAY FIXES PASS")
	quit(0)

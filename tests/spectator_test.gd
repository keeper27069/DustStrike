extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		push_error("SPECTATOR TEST FAILED: " + message)
		quit(1)
		assert(value,message)

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	while not is_instance_valid(game.hud): await process_frame
	game.self_test = true
	for team in ["CT", "T"]:
		game.selected_team = team
		game.start_match()
		game.state = "live"
		game.paused = true
		var enemy: Node3D
		for bot in game.bots:
			if bot.team != team: enemy = bot; break
		game.buying = true
		game.player.take_damage(1000,enemy)
		var s = game.spectator
		check(not game.player.alive and game.player.collision_layer == 0,"dead player must not obstruct combat")
		check(s.in_death_recap() and not s.observing(),"death first shows the recap")
		game.paused = false
		s._process(s.DEATH_RECAP_SECONDS+.01)
		game.paused = true
		check(s.observing() and s.camera.current and not game.player.cam.current,"death activates spectator camera")
		check(s.target.team == team and s.target.alive,"only living teammates are selected")
		check(not game.buying,"death closes the shop")
		var first = s.target
		check(not first.model.visible,"own operator does not block first-person view")
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		s._unhandled_input(event)
		check(s.target == first,"pause blocks spectator switching")
		game.paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if DisplayServer.get_name().to_lower() == "headless": s.cycle(1)
		else: s._unhandled_input(event)
		check(s.target != first and first.model.visible,"left click switches and restores the old model")
		event.button_index = MOUSE_BUTTON_RIGHT
		if DisplayServer.get_name().to_lower() == "headless": s.cycle(-1)
		else: s._unhandled_input(event)
		check(s.target == first,"right click switches back")
		if DisplayServer.get_name().to_lower() != "headless":
			var key = InputEventKey.new()
			key.pressed = true
			for code in [KEY_RIGHT,KEY_SPACE]:
				key.physical_keycode = code
				key.shift_pressed = false
				s._unhandled_input(key)
				check(s.target != first,"Mac keyboard switches forward")
				key.physical_keycode = KEY_LEFT if code == KEY_RIGHT else KEY_SPACE
				key.shift_pressed = code == KEY_SPACE
				s._unhandled_input(key)
				check(s.target == first,"Mac keyboard switches back")
			s.cycle(1)
			event.button_index = MOUSE_BUTTON_LEFT
			event.ctrl_pressed = true
			s._unhandled_input(event)
			check(s.target == first,"Mac Control-click switches back")
		for i in s.candidates().size(): s.cycle(1)
		check(s.target == first,"cycling wraps around")
		first.take_damage(1000,enemy)
		check(s.observing() and s.target != first and first.model.visible,"target death automatically selects another ally")
		var tracked = s.target
		tracked.position += Vector3(1,.2,1)
		tracked.rotation.y += .4
		s.follow_target()
		check(s.camera.global_position.distance_to(tracked.position+Vector3.UP*1.62)<.001,"camera follows the living target")
		if team == "CT" and "--capture" in OS.get_cmdline_user_args():
			tracked.position = game.nav_closest(game.site_a+Vector3(3,0,15))+Vector3.UP*.1
			tracked.rotation.y = 0
			s.follow_target()
			for i in 5: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OS.get_environment("DUST_QA_DIR")+"/spectator.png")
		game.paused = true
		for bot in s.candidates(): bot.take_damage(1000,enemy)
		check(not s.observing() and s.target == null,"no target remains after the last ally dies")
		game.start_round()
		check(not s.active and s.target == null and game.player.cam.current,"new round restores player camera")
		check(game.player.alive and game.player.collision_layer == 2,"new round restores player control and collision")
		game.state = "live"
		game.player.take_damage(1000,null)
		s._process(s.DEATH_RECAP_SECONDS+.01)
		var departing = s.target
		game.bots.erase(departing)
		departing.queue_free()
		await process_frame
		await process_frame
		check(s.observing() and s.target != departing,"deleted target is replaced safely")
		var visible_again = s.target
		game.return_menu()
		check(not s.active and game.attract.current and visible_again.model.visible,"menu clears spectator state")
	print("SPECTATOR TEST PASS: CT/T death, input, pause, wrap, auto-switch, follow, no allies, respawn, freed target, menu")
	quit(0)

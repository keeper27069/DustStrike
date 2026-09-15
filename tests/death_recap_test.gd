extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		push_error("DEATH RECAP FAILED: "+message)
		quit(1)
		assert(value,message)

func run() -> void:
	var game=load("res://main.tscn").instantiate()
	root.add_child(game)
	while not is_instance_valid(game.hud):await process_frame
	game.self_test=true
	game.set_process(false)
	for team in ["CT","T"]:
		game.selected_team=team
		game.start_match()
		game.state="live"
		game.player.set_physics_process(false)
		var enemy: Node3D
		for bot in game.bots:
			bot.set_physics_process(false)
			if bot.team!=team:enemy=bot
		game.player.cam.fov=28
		var death_view=game.player.cam.global_transform
		var killer_name: String=enemy.nick
		var enemy_hp: int=int(ceilf(enemy.hp))
		game.buying=true
		game.player.take_damage(1000,enemy,true)
		var s=game.spectator
		check(s.in_death_recap() and not s.observing() and s.target==null,"no instant teleport to another player")
		check(s.camera.global_transform.is_equal_approx(death_view) and is_equal_approx(s.camera.fov,28),"death keeps view position, direction and zoom")
		check(not game.buying and not game.player.alive and game.player.collision_layer==0,"death closes shop and disables player collision")
		check(s.death_info.killer==killer_name and s.death_info.team!=team and s.death_info.headshot and s.death_info.health==enemy_hp,"killer recap uses a complete damage-time snapshot")
		for bot in game.bots:check(bot.model.visible,"recap does not hide any living operator")
		game.paused=true
		s._process(9.0)
		check(is_equal_approx(s.death_left,3.0),"pause freezes recap time")
		game.paused=false
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		var click=InputEventMouseButton.new()
		click.button_index=MOUSE_BUTTON_LEFT
		click.pressed=true
		s._unhandled_input(click)
		var key=InputEventKey.new()
		key.physical_keycode=KEY_SPACE
		key.pressed=true
		s._unhandled_input(key)
		check(s.in_death_recap(),"fire and an early jump press cannot skip death")
		s.cycle(1)
		check(s.target==null,"direct spectator cycling also respects recap")
		s._process(1.0)
		key.echo=true
		s._unhandled_input(key)
		check(s.in_death_recap(),"a held jump key cannot skip death")
		game.bots.erase(enemy)
		enemy.queue_free()
		await process_frame
		check(s.death_info.killer==killer_name and s.death_info.health==enemy_hp,"recap survives a removed killer")
		s._process(.8)
		check(s.in_death_recap() and s.camera.global_transform.is_equal_approx(death_view),"view stays put until recap expires")
		s._process(1.21)
		check(not s.in_death_recap() and s.observing() and s.target.team==team,"three seconds leads to a living teammate")
		check(is_equal_approx(s.camera.fov,82) and s.transition_left>0,"spectator restores normal view with a short fade")
		s._process(.2)
		check(s.transition_left==0,"transition completes")
		game.start_round()
		game.state="live"
		game.player.take_damage(1000,game.player)
		check(s.death_info.self and not s.death_info.friendly,"self damage is labeled correctly")
		game.start_round()
		check(not s.active and s.death_info.is_empty() and game.player.cam.current,"respawn cancels pending recap")
		game.state="live"
		game.player.take_damage(1000,null)
		check(s.death_info.killer=="" and s.death_info.team=="","environment damage has no invented killer")
		game.return_menu()
		check(not s.active and not s.in_death_recap(),"menu cancels pending recap")
		# No live allies: keep the death view, then wait for round results.
		game.start_match()
		game.state="live"
		game.score["T" if team=="CT" else "CT"]=5
		var ally: Node3D
		for bot in game.bots:
			bot.set_physics_process(false)
			if bot.team==team:ally=bot
		game.player.take_damage(1000,ally)
		check(s.death_info.friendly,"friendly damage is identified")
		for bot in game.bots:
			if bot.team==team:bot.take_damage(1000,null)
		game.hud._process(0)
		check(game.match_over and not game.hud.layer.visible,"match-end buttons do not cover death recap")
		s._process(3.01)
		game.hud._process(0)
		check(not s.in_death_recap() and not s.observing() and s.target==null,"last ally dying during recap is safe")
		check(game.hud.layer.visible,"match-end buttons appear after recap")
		game.start_match()
		game.state="live"
		for bot in game.bots:bot.set_physics_process(false)
		game.player.take_damage(1000,null)
		s._process(1.0)
		key.echo=false
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		if DisplayServer.get_name().to_lower()!="headless":
			s._unhandled_input(key)
			check(s.observing(),"new Space press after the guard delay skips on Mac")
		game.return_menu()
	if "--capture" in OS.get_cmdline_user_args():
		game.start_match()
		game.state="live"
		game.player.set_physics_process(false)
		var enemy: Node3D
		for bot in game.bots:
			bot.set_physics_process(false)
			if bot.team!=game.player.team:enemy=bot
		var point: Vector3=game.nav_closest(game.site_a+Vector3(0,0,4))
		game.player.position=point+Vector3(0,0,4)
		enemy.position=point
		enemy.rotation.y=PI
		game.player.cam.fov=82
		game.player.cam.look_at(enemy.position+Vector3.UP*1.3)
		game.player.take_damage(1000,enemy,true)
		game.spectator.set_process(false)
		game.spectator._process(1.0)
		for i in 5:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("DUST_QA_DIR")+"/death-recap.png")
	print("DEATH RECAP PASS: CT/T timing, frozen view and zoom, pause, input guard, snapshot, no allies, skip, respawn and menu")
	quit(0)

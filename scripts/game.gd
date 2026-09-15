extends Node3D

const PlayerScript = preload("res://scripts/player.gd")
const BotScript = preload("res://scripts/bot.gd")
const HudScript = preload("res://scripts/hud.gd")
const SpectatorScript = preload("res://scripts/spectator.gd")
const GRENADE_FUSES = {"he":3.5,"flash":3.0,"smoke":4.0,"fire":2.5,"decoy":3.0}
var spectator: Node3D
var player: CharacterBody3D
var bots: Array[CharacterBody3D] = []
var weapons: Dictionary = {}
var weapon_order: Array[String] = []
var arsenal: Node3D
var map_data: Array = []
var nav = AStarGrid2D.new()
var classic := true
var nav_mesh: NavigationMesh
var nav_graph = AStar3D.new()
var nav_region: NavigationRegion3D
var ct_spawn = Vector3(6.4,-3.1,-59.2)
var t_spawn = Vector3(-20,3.6,20)
var state = "menu"
var practice = true
var selected_team = "CT"
var paused = false
var buying = false
var round_number = 0
var score = {"CT": 0, "T": 0}
var round_clock = 115.0
var freeze_clock = 8.0
var end_clock = 0.0
var winner = ""
var win_reason = ""
var hud: Control
var attract: Camera3D
var hurt_alpha = 0.0
var hitmarker = 0.0
var flash_alpha = 0.0
var toast = ""
var toast_left = 0.0
var killfeed: Array[Dictionary] = []
var bomb_state = "carried"
var bomb_carrier: Node3D
var bomb_position = Vector3.ZERO
var bomb_mesh: Node3D
var bomb_clock = 40.0
var bomb_beep = 0.0
var action_progress = 0.0
var action_label = ""
var defuse_kit = false
var bot_progress = 0.0
var objective_bot: Node3D
var smokes: Array[Dictionary] = []
var fires: Array[Dictionary] = []
var grenades: Array[Dictionary] = []
var transient: Array[Dictionary] = []
var sound_bank: Dictionary = {}
var utility_names = {"he": "Осколочная", "smoke": "Дымовая", "flash": "Световая", "fire": "Молотов / зажигательная", "decoy": "Ложная"}
var site_a = Vector3(31, 0, -27)
var site_b = Vector3(-32, 0, -28)
var menu_time = 0.0
var total_time = 0.0
var match_over = false
var self_test = false
var total_eliminations = 0
var total_plants = 0

func _ready() -> void:
	call_deferred("initialize")

func initialize() -> void:
	seed(94821)
	self_test = "--self-test" in OS.get_cmdline_user_args()
	var raw: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/weapons.json"))
	for w in raw:
		weapons[w.id] = w
		weapon_order.append(w.id)
	weapons["zeus"] = {"id":"zeus","name":"Zeus x27","category":"Equipment","price":200,"mag":1,"reserve":0,"damage":180,"rpm":60,"recoil":.2,"reload":30,"auto":0,"team":"ALL"}
	arsenal = load("res://assets/arsenal.glb").instantiate()
	add_child(arsenal)
	arsenal.visible = false
	build_world()
	build_navigation()
	if classic:
		ct_spawn = nav_closest(ct_spawn)+Vector3.UP*.1
		t_spawn = nav_closest(t_spawn)+Vector3.UP*.1
		site_a = nav_closest(site_a)
		site_b = nav_closest(site_b)
		print("Spawns ",ct_spawn," / ",t_spawn," Sites ",site_a," / ",site_b)
	build_audio()
	player = CharacterBody3D.new()
	player.set_script(PlayerScript)
	player.game = self
	add_child(player)
	attract = Camera3D.new()
	attract.fov = 68
	add_child(attract)
	attract.current = true
	spectator = Node3D.new()
	spectator.set_script(SpectatorScript)
	spectator.game = self
	add_child(spectator)
	# Spawn clearance queries need the newly built map in the physics world.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var canvas = CanvasLayer.new()
	add_child(canvas)
	hud = Control.new()
	hud.set_script(HudScript)
	hud.game = self
	canvas.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if self_test: call_deferred("run_self_test")
	if "--visual-test" in OS.get_cmdline_user_args(): call_deferred("run_visual_test")
	if "--match-test" in OS.get_cmdline_user_args(): call_deferred("run_match_test")

func build_world() -> void:
	var world = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky = Sky.new()
	var sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.22, 0.48, 0.72)
	sky_material.sky_horizon_color = Color(0.79, 0.83, 0.81)
	sky_material.ground_bottom_color = Color(0.43, 0.38, 0.29)
	sky_material.ground_horizon_color = Color(0.8, 0.78, 0.67)
	sky_material.sun_angle_max = 2.0
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.85, 1)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.75, 0.65)
	env.fog_density = 0.0017
	env.fog_sky_affect = 0.12
	world.environment = env
	add_child(world)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -33, 0)
	sun.light_color = Color(1, 0.91, 0.75)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90
	sun.shadow_bias = 0.05
	add_child(sun)
	if classic:
		build_classic()
		return
	var map: Node3D = load("res://assets/dust_map.glb").instantiate()
	add_child(map)
	map_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/collision.json"))
	for data in map_data:
		var body = StaticBody3D.new()
		body.collision_layer = 1
		body.position = vec(data.p)
		var cs = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = vec(data.s)
		cs.shape = box
		body.add_child(cs)
		add_child(body)
	for z in [-5, 7, 18]:
		var light = OmniLight3D.new()
		light.position = Vector3(-33, 3.5, z)
		light.light_color = Color(1, 0.69, 0.36)
		light.light_energy = 1.3
		light.omni_range = 9
		add_child(light)
	# Fine grain breaks up the flat ground without adding collision clutter.
	var ground_mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = "shader_type spatial; varying vec3 wp; void vertex(){ wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; } float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);} void fragment(){float n=hash(floor(wp.xz*170.0));float m=hash(floor(wp.xz*6.0));ALBEDO=vec3(0.55,0.475,0.35)*(0.87+n*0.2+m*0.06);ROUGHNESS=0.98;}"
	ground_mat.shader = shader
	var ground_mesh = map.find_child("Ground", true, false) as MeshInstance3D
	if ground_mesh: ground_mesh.material_override = ground_mat

func build_navigation() -> void:
	if classic: return
	nav.region = Rect2i(-48, -48, 96, 96)
	nav.cell_size = Vector2.ONE
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.update()
	for data in map_data:
		var p = vec(data.p)
		var size = vec(data.s)
		if p.y + size.y / 2 < 0.35 or p.y - size.y / 2 > 1.9: continue
		for x in range(floori(p.x-size.x/2-.4), ceili(p.x+size.x/2+.4)+1):
			for z in range(floori(p.z-size.z/2-.4), ceili(p.z+size.z/2+.4)+1):
				if nav.is_in_boundsv(Vector2i(x,z)): nav.set_point_solid(Vector2i(x,z))

func nearest_open(point: Vector3) -> Vector2i:
	var p = Vector2i(clampi(roundi(point.x), -46, 46), clampi(roundi(point.z), -46, 46))
	if not nav.is_point_solid(p): return p
	for radius in range(1, 10):
		for x in range(-radius, radius+1):
			for y in range(-radius, radius+1):
				var q = p + Vector2i(x,y)
				if nav.is_in_boundsv(q) and not nav.is_point_solid(q): return q
	return p

func find_path(from: Vector3, to: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if classic:
		for p in nav_graph.get_point_path(nav_graph.get_closest_point(from),nav_graph.get_closest_point(to)): result.append(p)
		return result
	for p in nav.get_id_path(nearest_open(from), nearest_open(to)):
		result.append(Vector3(p.x, 0, p.y))
	return result

func start_match() -> void:
	score = {"CT": 0, "T": 0}
	round_number = 0
	match_over = false
	player.kills = 0
	player.deaths = 0
	killfeed.clear()
	start_round(true)

func start_round(first := false) -> void:
	spectator.stop()
	var was_alive: bool = player.alive
	var saved_cash: int = player.cash
	for b in bots: b.queue_free()
	bots.clear()
	for item in grenades:
		if is_instance_valid(item.node): item.node.queue_free()
	grenades.clear()
	for collection in [smokes, fires, transient]:
		for item in collection:
			if is_instance_valid(item.node): item.node.queue_free()
		collection.clear()
	if is_instance_valid(bomb_mesh): bomb_mesh.queue_free()
	bomb_state = "carried"
	bomb_carrier = null
	bomb_clock = 40
	bot_progress = 0
	objective_bot = null
	action_progress = 0
	flash_alpha = 0
	hurt_alpha = 0
	round_number += 1
	state = "freeze"
	freeze_clock = 8.0 if not self_test else 0.1
	round_clock = 115
	paused = false
	buying = false
	var team_spawns = {"CT": spawn_positions(ct_spawn), "T": spawn_positions(t_spawn)}
	var spawn: Vector3 = team_spawns[selected_team][0]
	player.reset_round(spawn, selected_team, first or not was_alive)
	if not first and not was_alive: player.cash = saved_cash; defuse_kit = false
	if practice: player.cash = 16000
	for side in ["CT", "T"]:
		var count = 4 if side == selected_team else 5
		for i in count:
			var b = CharacterBody3D.new()
			b.set_script(BotScript)
			b.game = self
			b.team = side
			b.bot_index = i
			b.nick = ["Kestrel", "Rook", "Sable", "Nomad", "Viper"][i] if side == "CT" else ["Yusuf", "Aziz", "Amir", "Malik", "Omar"][i]
			b.position = team_spawns[side][i+1 if side == selected_team else i]
			add_child(b)
			bots.append(b)
			if side == "T" and i == 0: bomb_carrier = b
	if selected_team == "T": bomb_carrier = player
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.rebuild()
	sound("round", player.global_position)

func spawn_positions(base: Vector3) -> Array[Vector3]:
	var chosen: Array[Vector3] = []
	var capsule = CapsuleShape3D.new()
	capsule.radius = .35
	capsule.height = 1.8
	for ring in range(0,9):
		for x in range(-ring,ring+1):
			for z in range(-ring,ring+1):
				if maxi(absi(x),absi(z)) != ring: continue
				var candidate = base+Vector3(x*1.5,0,z*1.5)
				var ray = PhysicsRayQueryParameters3D.create(candidate+Vector3.UP*.75,candidate-Vector3.UP*1.25,1)
				var floor_hit = get_world_3d().direct_space_state.intersect_ray(ray)
				if floor_hit.is_empty() or floor_hit.normal.y < .7: continue
				candidate.y = floor_hit.position.y+.025
				if classic and nav_closest(candidate).distance_to(candidate)>1.5: continue
				var blocked = false
				for other in chosen:
					if Vector2(candidate.x-other.x,candidate.z-other.z).length()<1.35: blocked = true; break
				if blocked: continue
				var query = PhysicsShapeQueryParameters3D.new()
				query.shape = capsule
				query.transform.origin = candidate+Vector3.UP*.91
				query.collision_mask = 1
				query.margin = .005
				if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): continue
				chosen.append(candidate)
				if chosen.size() == 5: return chosen
	assert(chosen.size() == 5,"Not enough clear spawn positions")
	return chosen

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE and state != "menu":
			if buying: buying = false
			else: paused = not paused
			for g in grenades: g.node.freeze = paused
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
			hud.rebuild()
		if event.physical_keycode == KEY_B and state in ["freeze", "live"] and player.alive and not paused:
			if buying:
				buying = false
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			elif can_buy():
				buying = true
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else: notice("Закупка доступна у базы в начале раунда")
			hud.rebuild()
		if event.physical_keycode == KEY_F11:
			var full = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		if event.physical_keycode == KEY_F5:
			get_viewport().get_texture().get_image().save_png("user://screenshot.png")

func _process(dt: float) -> void:
	if not is_instance_valid(attract): return
	total_time += dt
	if state == "menu":
		menu_time += dt * 0.035
		attract.position = site_a + Vector3(3+sin(menu_time)*1.5,3.6,13+cos(menu_time)*1.4)
		attract.look_at(site_a+Vector3.UP*1.5)
		return
	if paused: return
	toast_left = maxf(0, toast_left - dt)
	hurt_alpha = maxf(0, hurt_alpha - dt * 0.7)
	hitmarker = maxf(0, hitmarker - dt)
	flash_alpha = maxf(0, flash_alpha - dt * 0.3)
	for i in range(killfeed.size()-1,-1,-1):
		killfeed[i].time -= dt
		if killfeed[i].time <= 0: killfeed.remove_at(i)
	if state == "freeze":
		freeze_clock -= dt
		if freeze_clock <= 0:
			state = "live"
			sound("round", player.global_position)
			notice("Раунд начался")
	if state == "live":
		round_clock -= dt
		process_objective(dt)
		if bomb_state == "planted":
			bomb_clock -= dt
			bomb_beep -= dt
			if bomb_beep <= 0:
				bomb_beep = clampf(bomb_clock/40, 0.12, 1.0)
				sound("beep", bomb_position)
				muzzle(bomb_position+Vector3.UP*.18, Color(1,.12,.04))
			if bomb_clock <= 0:
				explosion(bomb_position, 22, null, 350)
				end_round("T", "Бомба взорвана")
		elif round_clock <= 0: end_round("CT", "Время вышло")
		check_round_end()
	if state == "ended":
		end_clock -= dt
		if end_clock <= 0 and not match_over: start_round()
	update_effects(dt)

func ui_blocked() -> bool:
	return paused or buying or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED

func can_buy() -> bool:
	if practice: return true
	return (state == "freeze" or round_clock > 100) and player.position.distance_to(ct_spawn if player.team == "CT" else t_spawn) < 10

func buy(id: String) -> void:
	if not can_buy() or not player.alive: return
	var price = 0
	if weapons.has(id):
		var w: Dictionary = weapons[id]
		if not practice and w.team != "ALL" and w.team != player.team: return
		price = int(w.price)
		if player.cash < price and not practice: notice("Недостаточно средств"); return
		if id == "zeus": player.has_zeus = true
		elif w.category == "Pistols": player.secondary = id
		else: player.primary = id
		player.ammo[id] = [int(w.mag), int(w.reserve)]
		player.equip(id)
	elif id == "armor":
		price = 1000
		if player.cash < price and not practice: notice("Недостаточно средств"); return
		player.armor = 100
	elif id == "kit":
		price = 400
		if player.team != "CT": return
		if player.cash < price and not practice: notice("Недостаточно средств"); return
		defuse_kit = true
	else:
		price = {"he": 300, "smoke": 300, "flash": 200, "fire": 400, "decoy": 50}.get(id, 300)
		if player.cash < price and not practice: notice("Недостаточно средств"); return
		if int(player.utility[id]) >= (2 if id == "flash" else 1): notice("Уже в снаряжении"); return
		player.utility[id] += 1
	if not practice: player.cash -= price
	sound("buy", player.global_position)
	hud.rebuild()

func actors() -> Array:
	var all: Array = [player]
	all.append_array(bots)
	return all

func can_see(from: Node3D, to: Node3D) -> bool:
	var a = from.global_position + Vector3.UP * 1.5
	var b = to.global_position + Vector3.UP * 1.4
	if smoke_blocks(a,b): return false
	var query = PhysicsRayQueryParameters3D.create(a, b, 3, [from.get_rid()])
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == to

func smoke_blocks(a: Vector3, b: Vector3) -> bool:
	var ab = b-a
	for smoke in smokes:
		var c: Vector3 = smoke.position
		var t = clampf((c-a).dot(ab)/maxf(ab.length_squared(),.001),0,1)
		if (a+ab*t).distance_to(c) < 4.3: return true
	return false

func trace_shot(shooter: Node3D, origin: Vector3, direction: Vector3, damage: float, reach: float, draw_trace: bool) -> void:
	var query = PhysicsRayQueryParameters3D.create(origin, origin+direction*reach, 3, [shooter.get_rid()])
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	var end = origin+direction*reach
	if not hit.is_empty():
		end = hit.position
		var body: Node = hit.collider
		if body.has_method("take_damage"):
			if body.team != shooter.team:
				var head: bool = end.y - body.global_position.y > 1.48
				body.take_damage(damage * (4.0 if head else 1.0), shooter, head)
				if shooter == player: hitmarker = 0.16
				muzzle(end, Color(.68,.19,.08))
		else:
			impact(end, hit.normal)
	if draw_trace:
		var start = origin + direction * .9
		if shooter == player: start = player.rig.global_position + direction * .7
		tracer(start, end)

func actor_killed(victim: Node3D, attacker: Node, head: bool) -> void:
	total_eliminations += 1
	if is_instance_valid(attacker) and attacker != victim and attacker.team != victim.team:
		attacker.kills += 1
		if attacker == player:
			player.cash = mini(16000, player.cash+300)
			sound("kill", player.global_position)
	var killer_name: String = "Вы" if attacker == player else str(attacker.nick) if is_instance_valid(attacker) and "nick" in attacker else "Взрыв"
	var victim_name: String = "Вы" if victim == player else str(victim.nick)
	var attacker_team = attacker.team if is_instance_valid(attacker) and "team" in attacker else ""
	killfeed.push_front({"killer":killer_name,"victim":victim_name,"killer_team":attacker_team,"victim_team":victim.team,"headshot":head,"self":attacker==victim,"friendly":attacker_team==victim.team and attacker!=victim,"time":7.0})
	if killfeed.size() > 5: killfeed.pop_back()
	if victim == bomb_carrier and bomb_state == "carried":
		bomb_carrier = null
		bomb_state = "dropped"
		bomb_position = victim.global_position + Vector3.UP * .15
		create_bomb_mesh()
	if victim == player:
		spectator.begin(attacker,head)
		toast_left = 0
	elif spectator.active and victim == spectator.target:
		spectator.cycle(1)
	check_round_end()

func check_round_end() -> void:
	if state != "live": return
	var living = {"CT":0,"T":0}
	for actor in actors():
		if actor.alive: living[actor.team] += 1
	if living.CT == 0: end_round("T", "Команда противника устранена")
	elif living.T == 0 and bomb_state != "planted": end_round("CT", "Команда противника устранена")

func end_round(side: String, reason: String) -> void:
	if state != "live": return
	winner = side
	win_reason = reason
	score[side] += 1
	state = "ended"
	end_clock = 5.5
	match_over = int(score[side]) >= 6
	buying = false
	player.cash = mini(16000, player.cash + (3250 if player.team == side else 2400))
	sound("win", player.global_position)
	if match_over:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		hud.rebuild()

func bot_goal(bot: Node3D) -> Vector3:
	if bomb_state == "dropped" and bot.team == "T": return bomb_position
	if bomb_state == "planted":
		if bot.team == "CT": return bomb_position
		return bomb_position + Vector3(-5 if bot.bot_index%2 == 0 else 5, 0, 4)
	if classic:
		if bot.team == "T":
			var routes = [
				[Vector3(-37,1.5,6),Vector3(-42,1.5,-24),site_b+Vector3(0,0,3)],
				[Vector3(11,1.5,3),Vector3(31,1.5,-6),site_a+Vector3(1,0,4)],
				[Vector3(-7,0,-6),Vector3(-5,-2,-34),site_a+Vector3(-3,0,2)]
			]
			var route: Array = routes[bot.bot_index%3]
			if bot.goal_id < route.size():
				var closest = nav_closest(route[bot.goal_id])
				if bot.position.distance_to(closest) < 3: bot.goal_id += 1
				if bot.goal_id < route.size(): return route[bot.goal_id]
			return site_b if bot.bot_index%3==0 else site_a
		var posts = [site_b+Vector3(4,0,3),site_a+Vector3(2,0,4),Vector3(-4,-3,-41),site_a+Vector3(-5,0,1),site_b+Vector3(0,0,5)]
		if round_clock > 45: return posts[bot.bot_index%5]
	if bot.team == "T":
		var routes = [
			[Vector3(-7,0,28),Vector3(-33,0,27),Vector3(-33,0,-12),Vector3(-32,0,-22)],
			[Vector3(7,0,26),Vector3(34,0,26),Vector3(35,0,16),Vector3(34,0,-18)],
			[Vector3(0,0,16),Vector3(0,0,-14),Vector3(0,0,-25),Vector3(30,0,-23)]
		]
		var route: Array = routes[bot.bot_index%3]
		if bot.goal_id < route.size():
			if bot.position.distance_to(route[bot.goal_id]) < 2.8: bot.goal_id += 1
			if bot.goal_id < route.size(): return route[bot.goal_id]
		return site_b + Vector3(2,0,4) if bot.bot_index%3 == 0 else site_a + Vector3(-2,0,4)
	var posts = [Vector3(-33,0,-20),Vector3(35,0,-16),Vector3(0,0,-25),Vector3(8,0,-17),Vector3(-25,0,-20)]
	if round_clock < 55:
		var nearest: Node3D
		var distance = INF
		for actor in actors():
			if actor.alive and actor.team != bot.team:
				var d: float = actor.global_position.distance_to(bot.global_position)
				if d < distance: nearest = actor; distance = d
		if nearest: return nearest.global_position
	return posts[bot.bot_index%posts.size()]

func process_objective(dt: float) -> void:
	action_label = ""
	if not player.alive: return
	if bomb_state == "dropped" and player.team == "T" and player.position.distance_to(bomb_position) < 1.7:
		bomb_state = "carried"
		bomb_carrier = player
		if is_instance_valid(bomb_mesh): bomb_mesh.queue_free()
		notice("Вы подобрали бомбу")
	var can_plant: bool = bomb_state == "carried" and bomb_carrier == player and at_site(player.position)
	var can_defuse: bool = bomb_state == "planted" and player.team == "CT" and player.position.distance_to(bomb_position) < 2.8
	if can_plant: action_label = "Удерживайте E — установить бомбу"
	if can_defuse: action_label = "Удерживайте E — обезвредить бомбу"
	if (can_plant or can_defuse) and Input.is_physical_key_pressed(KEY_E) and not ui_blocked() and player.velocity.length() < .5:
		action_progress += dt
		var duration = 3.2 if can_plant else 5.0 if defuse_kit else 10.0
		if action_progress >= duration:
			if can_plant: plant_bomb(player.position)
			else: end_round("CT", "Бомба обезврежена")
			action_progress = 0
	else: action_progress = 0

func at_site(p: Vector3) -> bool:
	return (Vector2(p.x-site_a.x,p.z-site_a.z).length() < 6 and absf(p.y-site_a.y)<2.0) or (Vector2(p.x-site_b.x,p.z-site_b.z).length() < 6 and absf(p.y-site_b.y)<2.0)

func bot_objective(bot: Node3D, dt: float) -> void:
	if bomb_state == "dropped" and bot.team == "T" and bot.position.distance_to(bomb_position) < 1.8:
		bomb_state = "carried"
		bomb_carrier = bot
		if is_instance_valid(bomb_mesh): bomb_mesh.queue_free()
	if bomb_state == "carried" and bomb_carrier == bot and at_site(bot.position) and not is_instance_valid(bot.target):
		if objective_bot != bot: objective_bot = bot; bot_progress = 0
		bot_progress += dt
		if bot_progress >= 3.2: plant_bomb(bot.position)
	elif bomb_state == "planted" and bot.team == "CT" and bot.position.distance_to(bomb_position) < 2.5 and not is_instance_valid(bot.target):
		if not is_instance_valid(objective_bot) or not objective_bot.alive or objective_bot.team != "CT": objective_bot = bot; bot_progress = 0
		if objective_bot == bot:
			bot_progress += dt
			if bot_progress >= 7.5: end_round("CT", "Бомба обезврежена")
	elif objective_bot == bot:
		bot_progress = 0
		objective_bot = null

func plant_bomb(p: Vector3) -> void:
	total_plants += 1
	bomb_state = "planted"
	bomb_position = p + Vector3.UP * .12
	bomb_carrier = null
	bomb_clock = 40
	bomb_beep = 0
	bot_progress = 0
	objective_bot = null
	create_bomb_mesh()
	player.cash = mini(16000,player.cash+300) if player.team == "T" else player.cash
	notice("Бомба установлена · 40 секунд")
	sound("plant", bomb_position)

func create_bomb_mesh() -> void:
	if is_instance_valid(bomb_mesh): bomb_mesh.queue_free()
	bomb_mesh = Node3D.new()
	add_child(bomb_mesh)
	bomb_mesh.position = bomb_position
	for x in [-.1,0,.1]:
		var mesh = MeshInstance3D.new()
		var cube = BoxMesh.new()
		cube.size = Vector3(.09,.13,.26)
		mesh.mesh = cube
		mesh.position.x = x
		mesh.material_override = material(Color(.3,.28,.16))
		bomb_mesh.add_child(mesh)
	var display = MeshInstance3D.new()
	var screen = BoxMesh.new()
	screen.size = Vector3(.17,.025,.10)
	display.mesh = screen
	display.position.y = .09
	display.material_override = material(Color(.15,.75,.3), true)
	bomb_mesh.add_child(display)

func throw_utility(owner_actor: Node3D, kind: String, pos: Vector3, impulse: Vector3) -> void:
	var body = RigidBody3D.new()
	body.mass = 0.4
	body.collision_layer = 4
	body.collision_mask = 1
	body.continuous_cd = true
	var physics = PhysicsMaterial.new()
	physics.bounce = 0.42
	physics.friction = 0.6
	body.physics_material_override = physics
	var cs = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = .09
	cs.shape = sphere
	body.add_child(cs)
	var mesh = MeshInstance3D.new()
	var sm = SphereMesh.new()
	sm.radius = .09
	sm.height = .18
	mesh.mesh = sm
	mesh.material_override = material(Color(.25,.3,.19) if kind == "he" else Color(.4,.43,.42))
	body.add_child(mesh)
	add_child(body)
	body.global_position = pos
	body.linear_velocity = impulse
	body.angular_velocity = Vector3(3,5,2)
	grenades.append({"node":body,"kind":kind,"time":GRENADE_FUSES.get(kind,3.5),"owner":owner_actor})
	sound("knife",pos)

func update_effects(dt: float) -> void:
	for i in range(grenades.size()-1,-1,-1):
		var g: Dictionary = grenades[i]
		g.time -= dt
		if g.time <= 0:
			var p: Vector3 = g.node.global_position
			match g.kind:
				"he": explosion(p, 8, g.owner, 110)
				"smoke": spawn_smoke(p)
				"flash":
					sound("flash",p)
					if player.alive:
						var to = p-player.cam.global_position
						var ray = PhysicsRayQueryParameters3D.create(player.cam.global_position,p,1)
						if get_world_3d().direct_space_state.intersect_ray(ray).is_empty() and to.length()<35:
							flash_alpha = clampf((1-to.length()/40)*maxf(.25,(-player.cam.global_basis.z).dot(to.normalized())),.15,1)
					for bot in bots:
						if bot.position.distance_to(p)<15: bot.reaction = 3.0
				"fire": spawn_fire(p, g.owner)
				"decoy":
					var n = Node3D.new()
					add_child(n)
					n.position = p
					fires.append({"node":n,"position":p,"time":12.0,"tick":0.0,"owner":g.owner,"decoy":true})
			g.node.queue_free()
			grenades.remove_at(i)
	for i in range(smokes.size()-1,-1,-1):
		var s: Dictionary = smokes[i]
		s.time -= dt
		s.node.scale = Vector3.ONE * clampf((18-float(s.time))*1.2,.01,1)
		if s.time < 2: s.node.scale *= maxf(.01,float(s.time)/2)
		if s.time <= 0: s.node.queue_free(); smokes.remove_at(i)
	for i in range(fires.size()-1,-1,-1):
		var f: Dictionary = fires[i]
		f.time -= dt
		f.tick -= dt
		if f.tick <= 0:
			f.tick = .4
			if f.decoy: sound("botshot",f.position); muzzle(f.position+Vector3.UP*.2)
			else:
				for actor in actors():
					if actor.alive and actor.position.distance_to(f.position)<3.7: actor.take_damage(11, f.owner)
		if f.time <= 0: f.node.queue_free(); fires.remove_at(i)
	for i in range(transient.size()-1,-1,-1):
		transient[i].time -= dt
		if transient[i].time <= 0:
			transient[i].node.queue_free()
			transient.remove_at(i)

func explosion(p: Vector3, radius: float, owner_actor: Node3D, max_damage: float) -> void:
	sound("explosion", p)
	for actor in actors():
		if not actor.alive: continue
		var distance: float = actor.position.distance_to(p)
		if distance < radius:
			var query = PhysicsRayQueryParameters3D.create(p+Vector3.UP*.2,actor.position+Vector3.UP,1)
			if get_world_3d().direct_space_state.intersect_ray(query).is_empty(): actor.take_damage(max_damage*(1-distance/radius),owner_actor)
	for i in 14:
		muzzle(p+Vector3(randf_range(-1,1),randf_range(0,2),randf_range(-1,1)),Color(1,.35,.05),.5,.4)
	# Smoke is displaced briefly by an explosion.
	for s in smokes:
		if p.distance_to(s.position)<7: s.time = minf(s.time, 2.5)

func spawn_smoke(p: Vector3) -> void:
	var root = Node3D.new()
	add_child(root)
	root.position = p
	var smat = material(Color(.57,.58,.56,.72))
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.roughness = 1
	for i in 28:
		var mesh = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = randf_range(1.3,2.1)
		sphere.height = sphere.radius*2
		sphere.radial_segments = 16
		sphere.rings = 8
		mesh.mesh = sphere
		mesh.position = Vector3(randf_range(-2.5,2.5),randf_range(.3,2.5),randf_range(-2.5,2.5))
		mesh.material_override = smat
		root.add_child(mesh)
	smokes.append({"node":root,"position":p+Vector3.UP*1.4,"time":18.0})
	for f in fires:
		if p.distance_to(f.position)<5: f.time = 0
	sound("smoke",p)

func spawn_fire(p: Vector3, owner_actor: Node3D) -> void:
	var root = Node3D.new()
	add_child(root)
	root.position = p
	for i in 35:
		var mesh = MeshInstance3D.new()
		var shape = SphereMesh.new()
		shape.radius = randf_range(.13,.35)
		shape.height = randf_range(.5,1.3)
		mesh.mesh = shape
		mesh.position = Vector3(randf_range(-2.7,2.7),.3,randf_range(-2.7,2.7))
		mesh.material_override = material(Color(1,randf_range(.25,.65),.03),true)
		root.add_child(mesh)
	fires.append({"node":root,"position":p,"time":7.0,"tick":0.0,"owner":owner_actor,"decoy":false})
	sound("explosion",p)

func material(color: Color, unshaded := false) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	if unshaded: mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

func muzzle(p: Vector3, color := Color(1,.72,.25), radius := .075, duration := .055) -> void:
	var mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius*2
	sphere.radial_segments = 8
	sphere.rings = 4
	mesh.mesh = sphere
	mesh.material_override = material(color,true)
	add_child(mesh)
	mesh.position = p
	transient.append({"node":mesh,"time":duration})

func tracer(a: Vector3, b: Vector3) -> void:
	var mesh = MeshInstance3D.new()
	var line = ImmediateMesh.new()
	line.surface_begin(Mesh.PRIMITIVE_LINES,material(Color(1,.78,.42,.65),true))
	line.surface_add_vertex(a)
	line.surface_add_vertex(b)
	line.surface_end()
	mesh.mesh = line
	add_child(mesh)
	transient.append({"node":mesh,"time":.045})

func impact(p: Vector3, normal: Vector3) -> void:
	var mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = .025
	sphere.height = .012
	mesh.mesh = sphere
	mesh.material_override = material(Color(.14,.12,.09))
	add_child(mesh)
	mesh.position = p+normal*.005
	if absf(normal.y) < .99: mesh.look_at(p+normal,Vector3.UP); mesh.rotate_object_local(Vector3.RIGHT,PI/2)
	transient.append({"node":mesh,"time":15.0})

func notice(message: String) -> void:
	toast = message
	toast_left = 3.0

func vec(a: Array) -> Vector3:
	return Vector3(float(a[0]),float(a[1]),float(a[2]))

func build_audio() -> void:
	# Original synthesized sounds. No extracted commercial game audio.
	for kind in ["shot","silenced","sniper","botshot","step","reload","knife","hit","kill","beep","round","win","plant","buy","explosion","flash","smoke"]:
		var duration = .22
		if kind == "explosion": duration = 1.1
		elif kind in ["round","win","plant"]: duration = .7
		elif kind == "smoke": duration = 1.0
		elif kind == "step": duration = .1
		var rate = 22050
		var data = PackedByteArray()
		data.resize(int(duration*rate)*2)
		var low = 0.0
		for i in int(duration*rate):
			var t = float(i)/rate
			var noise = randf_range(-1,1)
			low = lerpf(low,noise,.13)
			var sample = 0.0
			match kind:
				"shot", "botshot", "sniper": sample = (noise*.55+sin(t*(80-t*80)*TAU)*.6)*exp(-t*(23 if kind != "sniper" else 13))
				"silenced": sample = (low*.7+sin(t*160*TAU)*.3)*exp(-t*32)
				"step": sample = low*exp(-t*45)*.5
				"reload": sample = noise*exp(-fmod(t,.075)*90)*.25
				"knife": sample = noise*sin(t/duration*PI)*.23
				"hit": sample = (noise*.4+sin(t*110*TAU)*.4)*exp(-t*28)
				"explosion": sample = (low+sin(t*(45-t*10)*TAU)*.45)*exp(-t*4)
				"smoke": sample = noise*.18*sin(t*PI)
				"flash": sample = (sin(t*1700*TAU)*.12+noise*.2)*exp(-t*10)
				_:
					var freq = 950.0 if kind == "beep" else 650.0 if kind in ["buy","kill"] else 440.0 + floorf(t/.17)*110
					sample = sin(t*freq*TAU)*.2*sin(t/duration*PI)
			data.encode_s16(i*2,int(clampf(sample,-1,1)*28000))
		var wav = AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = rate
		wav.data = data
		sound_bank[kind] = wav

func sound(kind: String, pos: Vector3) -> void:
	if self_test or not sound_bank.has(kind): return
	var node = AudioStreamPlayer3D.new()
	node.stream = sound_bank[kind]
	node.max_distance = 70
	node.unit_size = 8
	node.volume_db = -5 if kind in ["shot","sniper"] else -10 if kind == "step" else -8
	node.pitch_scale = randf_range(.94,1.06) if kind in ["shot","step","botshot"] else 1.0
	add_child(node)
	node.position = pos
	node.finished.connect(node.queue_free)
	node.play()

func return_menu() -> void:
	spectator.stop()
	state = "menu"
	paused = false
	buying = false
	attract.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.rebuild()

func run_self_test() -> void:
	print("SELFTEST weapons=", weapons.size(), " colliders=", map_data.size())
	assert(weapons.size() == 35)
	for id in weapon_order: assert(arsenal.find_child("W_"+id,true,false) != null, "Missing model "+id)
	for destination in [site_a, site_b, ct_spawn]:
		var path = find_path(t_spawn,destination)
		assert(path.size() > 2, "Disconnected objective "+str(destination))
		print("SELFTEST path to ",destination," = ",path.size())
	start_match()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(bots.size() == 9)
	for bot in bots:
		var bot_path = find_path(bot.position,bot_goal(bot))
		assert(bot_path.size()>0,"Unreachable bot goal "+bot.nick)
	state = "live"
	for id in weapon_order:
		buy(id)
		assert(player.equip_id == id)
	player.equip("ak")
	player.ammo.ak = [0,90]
	player.reload_weapon()
	assert(player.reload_left > 0)
	player.reload_left = .01
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(player.ammo.ak[0] == 30)
	print("SELFTEST arsenal/reload passed")
	var victim: Node3D = bots[4]
	paused = true
	player.position = t_spawn
	for bot in bots: bot.collision_layer = 0
	victim.collision_layer = 2
	victim.position = t_spawn+Vector3(0,0,-1.4)
	await get_tree().physics_frame
	await get_tree().physics_frame
	trace_shot(player,player.position+Vector3.UP*1.6,(victim.position+Vector3.UP*1.6-(player.position+Vector3.UP*1.6)).normalized(),500,10,false)
	assert(not victim.alive)
	paused = false
	plant_bomb(Vector3(31,0,-23))
	assert(bomb_state == "planted" and is_instance_valid(bomb_mesh))
	spawn_smoke(Vector3(0,0,8))
	assert(smoke_blocks(Vector3(0,1,0),Vector3(0,1,15)))
	throw_utility(player,"he",Vector3(0,2,25),Vector3(0,2,-4))
	assert(grenades.size() == 1)
	for i in 240: await get_tree().physics_frame
	assert(grenades.size() == 0)
	end_round("CT","Test")
	assert(state == "ended")
	print("SELFTEST PASS: navigation, 34 weapon models, purchase, reload, damage, bomb, smoke, grenade fuse, round end")
	get_tree().quit(0)

func run_visual_test() -> void:
	var directory = OS.get_environment("DUST_QA_DIR")
	if directory == "": directory = OS.get_user_data_dir()
	for i in 12: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(directory+"/menu.png")
	start_match()
	player.position = site_a + Vector3(3,0.1,18)
	player.rotation.y = 0
	player.pitch = -.02
	freeze_clock = 60
	for i in 20: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(directory+"/gameplay.png")
	buying = true
	hud.rebuild()
	for i in 5: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(directory+"/buy.png")
	print("VISUAL TEST COMPLETE ", directory)
	get_tree().quit()

func build_classic() -> void:
	site_a = Vector3(31,1.6,-62)
	site_b = Vector3(-40,1.6,-61)
	var map: Node3D = load("res://assets/dust_classic.glb").instantiate()
	add_child(map)
	nav_region = NavigationRegion3D.new()
	add_child(nav_region)
	NavigationServer3D.map_set_cell_size(get_world_3d().navigation_map,.3)
	NavigationServer3D.map_set_cell_height(get_world_3d().navigation_map,.1)
	nav_mesh = NavigationMesh.new()
	nav_mesh.cell_size = .3
	nav_mesh.cell_height = .1
	nav_mesh.agent_height = 1.8
	nav_mesh.agent_radius = .3
	nav_mesh.agent_max_climb = .5
	nav_mesh.agent_max_slope = 48
	nav_mesh.region_min_size = 2
	nav_mesh.region_merge_size = 5
	nav_mesh.filter_ledge_spans = true
	var source = NavigationMeshSourceGeometryData3D.new()
	var baked = ResourceLoader.exists("res://assets/dust_navigation.tres")
	for n in map.find_children("*","MeshInstance3D",true,false):
		if not n.mesh: continue
		var body = StaticBody3D.new()
		body.collision_layer = 1
		add_child(body)
		body.global_transform = n.global_transform
		var cs = CollisionShape3D.new()
		cs.shape = n.mesh.create_trimesh_shape()
		body.add_child(cs)
		if not baked: source.add_faces(cs.shape.get_faces(),n.global_transform)
		for i in n.mesh.get_surface_count():
			var mat = n.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				mat.roughness = .88
				mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if baked: nav_mesh = load("res://assets/dust_navigation.tres")
	else:
		NavigationServer3D.bake_from_source_geometry_data(nav_mesh,source)
		ResourceSaver.save(nav_mesh,"res://assets/dust_navigation.tres")
	nav_region.navigation_mesh = nav_mesh
	nav_region.set_navigation_map(get_world_3d().navigation_map)
	NavigationServer3D.region_set_navigation_mesh(nav_region.get_rid(),nav_mesh)
	NavigationServer3D.region_set_transform(nav_region.get_rid(),Transform3D.IDENTITY)
	NavigationServer3D.region_set_enabled(nav_region.get_rid(),true)
	print("DUST II navigation polygons: ",nav_mesh.get_polygon_count())
	print("NAV vertices ",nav_mesh.get_vertices().size()," first=",nav_mesh.get_vertices()[0], " region ",nav_region.get_navigation_map()," world ",get_world_3d().navigation_map)
	build_nav_graph()

func nav_closest(p: Vector3) -> Vector3:
	return nav_graph.get_point_position(nav_graph.get_closest_point(p))

func build_nav_graph() -> void:
	var vertices = nav_mesh.get_vertices()
	var edges = {}
	var count = nav_mesh.get_polygon_count()
	for i in count:
		var poly = nav_mesh.get_polygon(i)
		var centroid = Vector3.ZERO
		for j in poly: centroid += vertices[j]
		centroid /= poly.size()
		nav_graph.add_point(i,centroid)
		for j in poly.size():
			var a = poly[j]
			var b = poly[(j+1)%poly.size()]
			var key = Vector2i(mini(a,b),maxi(a,b))
			if not edges.has(key): edges[key] = []
			edges[key].append(i)
	for edge in edges:
		var polys: Array = edges[edge]
		if polys.size() != 2: continue
		var portal = (vertices[edge.x]+vertices[edge.y])*.5
		nav_graph.add_point(count,portal)
		nav_graph.connect_points(count,polys[0])
		nav_graph.connect_points(count,polys[1])
		count += 1
	# Keep goals on the connected play space, excluding rooftops and sealed ledges.
	var seen = {}
	var queue: Array[int] = [nav_graph.get_closest_point(t_spawn)]
	seen[queue[0]] = true
	while not queue.is_empty():
		var current = queue.pop_front()
		for other in nav_graph.get_point_connections(current):
			if not seen.has(other): seen[other] = true; queue.append(other)
	for id in nav_graph.get_point_ids():
		if not seen.has(id): nav_graph.set_point_disabled(id,true)
	print("Navigation graph nodes: ",nav_graph.get_point_count())

func run_match_test() -> void:
	self_test = true
	start_match()
	freeze_clock = .1
	player.alive = false
	player.collision_layer = 0
	Engine.time_scale = 8
	await get_tree().create_timer(125.0).timeout
	print("MATCHTEST score ",score," eliminations ",total_eliminations," plants ",total_plants)
	for bot in bots: print("MATCHTEST ",bot.nick," ",bot.position," hp ",bot.hp," path ",bot.path.size())
	assert(total_eliminations > 2,"Bots did not engage")
	assert(score.CT+score.T > 0,"Round did not finish")
	print("MATCHTEST PASS")
	get_tree().quit()

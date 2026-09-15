extends Node3D

const DEATH_RECAP_SECONDS = 3.0
const SKIP_DELAY = 0.75

var game: Node3D
var target: Node3D
var camera: Camera3D
var weapon: Node3D
var active = false
var target_was_visible = true
var death_left = 0.0
var death_info: Dictionary = {}
var transition_left = 0.0

func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 82
	camera.near = .035
	camera.far = 220
	add_child(camera)

func candidates() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for bot in game.bots:
		if is_instance_valid(bot) and not bot.is_queued_for_deletion() and bot.alive and bot.team == game.player.team:
			result.append(bot)
	return result

func observing() -> bool:
	return active and is_instance_valid(target) and not target.is_queued_for_deletion() and target.alive

func in_death_recap() -> bool:
	return active and death_left > 0.0

func begin(attacker: Node = null, headshot := false) -> void:
	stop()
	active = true
	death_left = DEATH_RECAP_SECONDS
	# Keep a snapshot: an attacker can die or be freed before the recap ends.
	var attacker_team: String = str(attacker.team) if is_instance_valid(attacker) and "team" in attacker else ""
	death_info = {
		"killer":str(attacker.nick) if is_instance_valid(attacker) and "nick" in attacker else "",
		"team":attacker_team,
		"headshot":headshot,
		"self":attacker == game.player,
		"friendly":attacker_team == game.player.team and attacker != game.player,
		"health":int(ceilf(attacker.hp)) if is_instance_valid(attacker) and "hp" in attacker else -1,
	}
	camera.global_transform = game.player.cam.global_transform
	camera.fov = game.player.cam.fov
	camera.current = true
	game.buying = false
	game.action_label = ""
	game.action_progress = 0
	game.flash_alpha = 0
	game.hurt_alpha = 0
	game.hitmarker = 0
	game.player.rig.visible = false
	if not game.paused: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	game.hud.rebuild()

func finish_death_recap() -> void:
	if not in_death_recap(): return
	death_left = 0.0
	transition_left = .18
	cycle(1)
	game.hud.rebuild()

func release_target() -> void:
	if is_instance_valid(target) and is_instance_valid(target.model):
		target.model.visible = target_was_visible
	target = null
	if is_instance_valid(weapon):
		weapon.visible = false
		weapon.queue_free()
	weapon = null

func cycle(direction: int) -> void:
	if not active or in_death_recap(): return
	var live = candidates()
	var index = live.find(target) if is_instance_valid(target) else -1
	var next: Node3D = null
	if not live.is_empty():
		index = posmod(index + direction, live.size()) if index >= 0 else (0 if direction > 0 else live.size()-1)
		next = live[index]
	if next == target: return
	release_target()
	target = next
	if not observing(): return
	target_was_visible = target.model.visible
	target.model.visible = false
	camera.fov = 82
	var source = game.arsenal.find_child("W_m4" if target.team == "CT" else "W_ak", true, false)
	if source:
		weapon = source.duplicate() as Node3D
		camera.add_child(weapon)
		weapon.scale = Vector3.ONE * .76
		weapon.position = Vector3(.23, -.23, -.43)
	follow_target()

func follow_target() -> void:
	if not observing(): return
	camera.global_position = target.global_position + Vector3.UP * 1.62
	camera.global_basis = target.global_basis.orthonormalized()
	if is_instance_valid(target.target) and target.target.alive:
		var aim: Vector3 = target.target.global_position + Vector3.UP * 1.25
		if camera.global_position.distance_squared_to(aim) > .01:
			camera.look_at(aim)
	if is_instance_valid(weapon):
		weapon.rotation.z = -.55 if target.reload_left > 0 else 0.0

func _process(dt: float) -> void:
	if not active or game.paused: return
	if in_death_recap():
		if dt >= death_left:
			finish_death_recap()
		else:
			death_left -= dt
		return
	transition_left = maxf(0.0,transition_left-dt)
	if not observing(): cycle(1)
	follow_target()

func _unhandled_input(event: InputEvent) -> void:
	if not active or game.ui_blocked() or game.state not in ["live", "ended"]: return
	if in_death_recap():
		# Holding fire or jump while dying must not skip the explanation.
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE and death_left <= DEATH_RECAP_SECONDS-SKIP_DELAY:
			finish_death_recap()
			get_viewport().set_input_as_handled()
		return
	var direction = 0
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and event.ctrl_pressed: direction = -1
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_WHEEL_DOWN]: direction = 1
		elif event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL_UP]: direction = -1
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_RIGHT: direction = 1
		elif event.physical_keycode == KEY_LEFT: direction = -1
		elif event.physical_keycode == KEY_SPACE: direction = -1 if event.shift_pressed else 1
	if direction != 0:
		cycle(direction)
		get_viewport().set_input_as_handled()

func stop() -> void:
	release_target()
	active = false
	death_left = 0.0
	death_info.clear()
	transition_left = 0.0
	if is_instance_valid(camera): camera.current = false

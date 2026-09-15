extends RefCounted

# The imported skeleton owns every limb; gameplay only selects full-body clips.
var animator: AnimationPlayer
var clips: Dictionary = {}
var current_clip = ""
var action_left = 0.0
var dead = false

func _init(model: Node3D) -> void:
	animator = find_animator(model)
	if not is_instance_valid(animator): return
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for animation_name in animator.get_animation_list():
		var short_name = String(animation_name).get_file().to_lower()
		if short_name not in ["idle", "run", "aim", "fire", "reload", "death"]: continue
		clips[short_name] = animation_name
		var animation = animator.get_animation(animation_name)
		animation.loop_mode = Animation.LOOP_LINEAR if short_name in ["idle", "run", "aim"] else Animation.LOOP_NONE
	play_clip("idle", 0.0)
	animator.advance(0.0)

func find_animator(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer: return node
	for child in node.get_children():
		var found = find_animator(child)
		if found != null: return found
	return null

func update(dt: float, horizontal_speed: float, has_target: bool, can_move := true) -> void:
	if not is_instance_valid(animator): return
	if dead:
		animator.advance(dt)
		return
	if action_left > 0.0:
		animator.advance(dt)
		action_left = maxf(0.0, action_left - dt)
		return
	var locomotion = "idle"
	var playback_speed = 1.0
	if can_move and horizontal_speed > 0.3:
		locomotion = "run"
		playback_speed = clampf(horizontal_speed / 3.7, 0.55, 1.4)
	elif can_move and has_target:
		locomotion = "aim"
	play_clip(locomotion, 0.16, playback_speed)
	animator.advance(dt)

func play_fire() -> void:
	play_action("fire", 0.04)

func play_reload(duration: float) -> void:
	play_action("reload", 0.1, duration)

func play_death() -> bool:
	dead = true
	action_left = 0.0
	if not clips.has("death") or not is_instance_valid(animator): return false
	play_clip("death", 0.08, 1.0, true)
	return true

func play_action(action: String, blend: float, duration := 0.0) -> void:
	if dead or not is_instance_valid(animator) or not clips.has(action): return
	var clip_length = maxf(0.01, animator.get_animation(clips[action]).length)
	action_left = duration if duration > 0.0 else clip_length
	play_clip(action, blend, clip_length / action_left, true)

func play_clip(clip: String, blend: float, playback_speed := 1.0, restart := false) -> void:
	if not is_instance_valid(animator): return
	if not clips.has(clip): clip = "idle"
	if not clips.has(clip): return
	animator.speed_scale = playback_speed
	if current_clip == clip and not restart: return
	current_clip = clip
	animator.play(clips[clip], blend)

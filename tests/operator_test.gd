extends SceneTree
const Controller = preload("res://scripts/operator_animation.gd")

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		push_error("OPERATOR TEST FAILED: " + message)
		quit(1)
		assert(value,message)

func find_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name): return node
	for child in node.get_children():
		var result = find_type(child,type_name)
		if result: return result
	return null

func bounds(model: Node3D) -> AABB:
	var mesh: MeshInstance3D = find_type(model,"MeshInstance3D")
	var baked = mesh.bake_mesh_from_current_skeleton_pose()
	return mesh.global_transform * baked.get_aabb()

func run() -> void:
	for team in ["ct","t"]:
		var model = load("res://assets/operator_"+team+".glb").instantiate()
		root.add_child(model)
		var controller = Controller.new(model)
		check(controller.clips.size()==6,"all six imported animation clips exist")
		var skeleton: Skeleton3D = find_type(model,"Skeleton3D")
		check(skeleton != null and skeleton.get_bone_count()>=16,"real skinned skeleton")
		var mesh: MeshInstance3D = find_type(model,"MeshInstance3D")
		check(mesh.mesh.get_surface_count() <= 20,"batched operator materials")
		var rest_leg = skeleton.get_bone_pose_rotation(skeleton.find_bone("Thigh_L"))
		for i in 3: controller.update(.1,3.7,false)
		await process_frame
		skeleton.force_update_all_bone_transforms()
		check(controller.current_clip == "run","movement selects run")
		check(rest_leg.angle_to(skeleton.get_bone_pose_rotation(skeleton.find_bone("Thigh_L")))>.1,"run animates the actual leg bones")
		controller.update(.2,0.0,true)
		check(controller.current_clip == "aim","combat idle selects aiming")
		controller.play_fire()
		controller.update(.1,0.0,true)
		check(controller.current_clip == "fire","firing selects recoil")
		controller.update(.2,0.0,true)
		controller.update(.1,0.0,true)
		check(controller.current_clip == "aim","fire returns to aiming")
		controller.play_reload(2.6)
		controller.update(2.5,3.7,false)
		check(controller.current_clip == "reload","reload follows gameplay duration")
		controller.update(.11,3.7,false)
		controller.update(.01,3.7,false)
		check(controller.current_clip == "run","reload returns to locomotion")
		var position_before = controller.animator.current_animation_position
		await process_frame
		await process_frame
		check(is_equal_approx(position_before,controller.animator.current_animation_position),"pause freezes the imported animation")
		check(controller.play_death(),"death animation is present")
		controller.update(1.0,0.0,false)
		await process_frame
		controller.play_fire()
		check(controller.current_clip == "death" and controller.dead,"death pose is final")
		skeleton.force_update_all_bone_transforms()
		var root_bone = skeleton.get_bone_global_pose(skeleton.find_bone("Root"))
		var head = skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("Head")).origin
		print("MODEL ",team," surfaces=",mesh.mesh.get_surface_count()," bones=",skeleton.get_bone_count()," death head height=",head.y," root=",root_bone.origin)
		check(head.y>0 and head.y<.6,"dead operator lies at ground level")
		if DisplayServer.get_name().to_lower() != "headless":
			await RenderingServer.frame_post_draw
			var box = bounds(model)
			print("DEATH BOUNDS ",team," ",box)
			check(box.position.y>-.15 and box.end.y<1.0,"death mesh does not sink underground or remain standing")
		model.queue_free()
		await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		var game=load("res://main.tscn").instantiate()
		root.add_child(game)
		while not is_instance_valid(game.hud): await process_frame
		game.self_test=true
		game.start_match()
		game.set_process(false)
		game.player.set_physics_process(false)
		game.hud.visible=false
		var selected=[]
		for bot in game.bots:
			bot.set_physics_process(false)
			bot.visible=false
			if selected.is_empty() or (selected.size()==1 and bot.team != selected[0].team): selected.append(bot)
		var center: Vector3 = game.site_a+Vector3(0,0,4)
		var ray=PhysicsRayQueryParameters3D.create(center+Vector3.UP*2,center-Vector3.UP*3,1)
		var hit=game.get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():center.y=hit.position.y+.02
		for i in selected.size():
			selected[i].visible=true
			selected[i].position=center+Vector3((i-.5)*1.1,0,0)
			selected[i].rotation.y=PI+.18
			selected[i].operator_animation.update(.1,0.0,false,false)
		game.attract.current=true
		game.attract.global_position=center+Vector3(1.7,1.55,3.8)
		game.attract.look_at(center+Vector3.UP*.95)
		game.attract.fov=40
		for i in 6: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("DUST_QA_DIR")+"/operators-in-game.png")
	print("OPERATOR TEST PASS: two skinned models, six clips, transitions, pause, death, material budget")
	quit(0)

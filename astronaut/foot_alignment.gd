extends SkeletonModifier3D

var actor: MarsAstronaut

func _process_modification_with_delta(_delta: float) -> void:
	if actor==null or actor.state=="fallen": return
	var skel := get_skeleton()
	for foot: Dictionary in actor.feet:
		if not foot.support or not foot.planted: continue
		var pose := skel.get_bone_global_pose(foot.id)
		var world_rest := skel.global_basis*skel.get_bone_global_rest(foot.id).basis
		var aligned := Basis(Quaternion(Vector3.UP,foot.normal))*world_rest
		pose.basis=skel.global_basis.inverse()*aligned
		skel.set_bone_global_pose(foot.id,pose)

	var torso := skel.find_bone("chest")
	if torso>=0:
		var tilt: float = actor.lean
		skel.set_bone_pose_rotation(torso,skel.get_bone_pose_rotation(torso)*Quaternion(Vector3.RIGHT,tilt))

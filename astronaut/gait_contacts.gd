extends SkeletonModifier3D
var actor: MarsAstronaut
func _process_modification_with_delta(delta: float) -> void:
	if actor==null or actor.state=="fallen": return
	actor.update_ik(Vector2(actor.velocity.x,actor.velocity.z).length(),minf(delta/maxf(Engine.time_scale,0.001),0.05))

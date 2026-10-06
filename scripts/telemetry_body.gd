extends RigidBody3D

var support := 0.0
var contacts := 0
var contact_normal := Vector3.UP
var contact_point := Vector3.ZERO

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	contacts = state.get_contact_count()
	support = 0.0
	var normal := Vector3.ZERO
	for i in contacts:
		var impulse := state.get_contact_impulse(i)
		support += absf(impulse.dot(Vector3.UP)) / state.step
		# Built-in Jolt reports world-space contact data despite the API's legacy 'local' name.
		normal += state.get_contact_local_normal(i)
		contact_point = state.get_contact_local_position(i)
	contact_normal = normal.normalized() if normal.length() > 0.01 else Vector3.UP

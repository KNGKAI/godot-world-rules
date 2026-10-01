extends SceneTree

const Sedan := preload("res://modules/liberty_vehicle/vehicle/liberty_vehicle.tscn")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	floor_body.add_child(shape)
	root.add_child(floor_body)

	var car := Sedan.instantiate() as LibertyVehicle
	car.position = Vector3(0, 0.8, 0)
	root.add_child(car)
	car.possession.control_enabled = true
	for _i in 90:
		await physics_frame
	var com_y := car.to_global(car.center_of_mass).y
	if com_y < 0.35:
		push_error("center of mass is not above the tire contact patch: %.3f" % com_y)
		quit(1)
		return

	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.45, 0))
	car.linear_velocity = Vector3(0, 0, -12.0)
	car.angular_velocity = Vector3.ZERO
	car.steering = 0.0
	var yaw := 0.0
	var roll := 0.0
	var min_up := 1.0
	var samples := 0
	for frame in 150:
		var planar := Vector3(car.linear_velocity.x, 0.0, car.linear_velocity.z).length()
		var intent := LibertyVehicleControlSnapshot.new()
		intent.throttle = 0.45 if planar < 12.0 else 0.12
		intent.steering = 1.0
		car.submit_controls(intent)
		await physics_frame
		if frame < 105:
			continue
		var speed := Vector3(car.linear_velocity.x, 0.0, car.linear_velocity.z).length()
		var up := car.global_basis.y
		var forward := -car.global_basis.z
		forward.y = 0.0
		forward = forward.normalized() if forward.length() > 0.001 else Vector3(0, 0, -1)
		var right := forward.cross(Vector3.UP).normalized()
		yaw += rad_to_deg(absf(car.angular_velocity.dot(car.global_basis.y)))
		roll += rad_to_deg(asin(clampf(up.dot(right), -1.0, 1.0)))
		min_up = minf(min_up, up.y)
		samples += 1
		if speed < 8.0:
			push_error("sedan lost neighborhood speed during the held turn")
			quit(2)
			return
	yaw /= samples
	roll /= samples
	if yaw > 30.0 or yaw < 8.0:
		push_error("neighborhood yaw %.1f deg/s is outside the sedan range" % yaw)
		quit(3)
		return
	if roll < 3.0:
		push_error("held turn leaned %.2f deg; expected outward body roll" % roll)
		quit(4)
		return
	if min_up < 0.96:
		push_error("held turn unloaded the sedan, up %.3f" % min_up)
		quit(5)
		return
	print("vehicle handling feel PASS yaw=%.1f roll=%.2f" % [yaw, roll])
	quit()

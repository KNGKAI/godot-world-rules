@tool
extends RefCounted
## Derived movement figures for the inspector: a tick-by-tick replay of LibertyCharacter's
## flat-ground model (move_toward acceleration and braking, speed-lerped turn rate, sprint cap,
## gravity). Pinned against the measured Phase 1 tuning record by test_movement_metrics.gd.

const GAITS: Array[StringName] = [&"walk", &"run", &"sprint"]
const STOP_SPEED := 0.1
const TOP_FRACTION := 0.95


static func tick() -> float:
	return 1.0 / float(Engine.physics_ticks_per_second)


## Seconds from rest until planar speed reaches TOP_FRACTION of `target_speed`.
static func time_to_top(target_speed: float, acceleration: float) -> float:
	var speed := 0.0
	var ticks := 0
	while speed < target_speed * TOP_FRACTION and ticks < 100000:
		speed = move_toward(speed, target_speed, acceleration * tick())
		ticks += 1
	return ticks * tick()


## Metres travelled from `speed` until planar speed is at or below STOP_SPEED.
static func stopping_distance(speed: float, deceleration: float) -> float:
	var distance := 0.0
	var ticks := 0
	while speed > STOP_SPEED and ticks < 100000:
		speed = move_toward(speed, 0.0, deceleration * tick())
		distance += speed * tick()
		ticks += 1
	return distance


## Half the largest lateral displacement while reversing from full `gait_speed`, until facing is
## within 10 degrees of the reverse direction (the Phase 1 course definition).
static func turn_radius(gait_speed: float, values: Dictionary) -> float:
	var sprint_speed: float = values.sprint_speed
	var dt := tick()
	var yaw := 0.0
	var velocity := Vector2(0.0, -gait_speed)
	var position := Vector2.ZERO
	var widest := 0.0
	var target_yaw := atan2(-0.0, -1.0)
	for _tick in 100000:
		var ratio := clampf(velocity.length() / maxf(sprint_speed, 0.001), 0.0, 1.0)
		var rate := deg_to_rad(lerpf(values.grounded_turn_rate_degrees, values.high_speed_turn_rate_degrees, ratio))
		yaw = rotate_toward(yaw, target_yaw, rate * dt)
		var forward := Vector2(-sin(yaw), -cos(yaw))
		velocity = velocity.move_toward(forward * gait_speed, values.ground_acceleration * dt)
		velocity = velocity.limit_length(sprint_speed)
		position += velocity * dt
		widest = maxf(widest, absf(position.x))
		if forward.dot(Vector2(0.0, 1.0)) > cos(deg_to_rad(10.0)):
			break
	return widest * 0.5


## Apex height and seconds until landing back on the take-off height.
static func jump(jump_velocity: float, gravity: float) -> Dictionary:
	var dt := tick()
	var vertical := jump_velocity
	var height := vertical * dt
	var apex := height
	var ticks := 1
	while height > 0.0 and ticks < 100000 and gravity > 0.0:
		vertical -= gravity * dt
		height += vertical * dt
		apex = maxf(apex, height)
		ticks += 1
	return {"apex": apex, "air_time": ticks * dt}


## `values` holds LibertyCharacter export names; returns {gait: {top, stop, turn}, "jump": {...}}.
static func summarize(values: Dictionary) -> Dictionary:
	var result := {}
	for gait in GAITS:
		var speed: float = values["%s_speed" % gait]
		result[gait] = {
			"top": time_to_top(speed, values.ground_acceleration),
			"stop": stopping_distance(speed, values.ground_deceleration),
			"turn": turn_radius(speed, values),
		}
	result["jump"] = jump(values.jump_velocity, values.gravity)
	return result

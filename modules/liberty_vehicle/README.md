# Liberty vehicle module — Phase 9A

Driver-only sedan proof of reusable seat/possession contracts. Godot 4.7.1, Jolt, 60 physics ticks. No autoload or reference-project runtime dependency. Bikes (9B), flight (9C), and passengers/non-player occupants (9D) remain gated.

## Playable review

Open `tests/test_vehicle.tscn` and press F6. The blue sedan drives; the orange sedan is a frozen blocked-exit demonstration. Walk beside its left front door and mount with Q or ENTER. The on-foot overlay follows the existing touchscreen/force-visible policy.

| Action | Keyboard | Touch |
|---|---|---|
| Mount / exit | Q | ENTER / EXIT |
| Steering | A / D | LEFT / RIGHT |
| Throttle | W | GAS |
| Brake / reverse | S | BRAKE |
| Handbrake | Space | HANDBRAKE |
| Chase / hood | C | CAMERA |
| Reset sedan, course only | R | — |
| Remove occupied sedan, course only | Delete | REMOVE |
| Return on foot to start | — | RETURN |

The blocked car deliberately rejects EXIT and preserves occupancy. Delete or the mounted REMOVE touch control removes it and tests cached teardown placement. Seated animation is deferred: the existing mannequin Rig is hidden while driving.

The driving overlay consumes every screen touch. `add_custom_button(title, color, callback)` adds a button along the top safe edge and calls `callback` on press. `get_custom_button(title)` returns that panel. Driving actions stay in the bottom grid.

## Typed boundaries

`LibertyVehicle` delegates seat transactions to `LibertyVehiclePossession`, which depends on a vehicle Node3D, `LibertyVehicleSeat`, and `LibertyCharacter`, not sedan handling. Only `driver_front_left` is accepted.

- `request_mount(occupant: LibertyCharacter, seat_id: StringName) -> LibertyVehicleContracts.MountResult`
- `request_dismount(seat_id: StringName) -> LibertyVehicleContracts.DismountResult`
- `set_control_enabled(seat_id: StringName, enabled: bool) -> void`
- `get_camera_anchor(seat_id: StringName) -> Node3D`
- `submit_controls(value: LibertyVehicleControlSnapshot) -> void`

Results contain explicit SUCCESS/REJECTED status, reason and payload; `succeeded()` checks status. Mount payload identifies occupant, seat and camera anchor. Exit payload contains occupant, seat, transform and cause. Seat transactions do not emit character events. Interactive clients use the character's adapter `mount`, `dismount` or `request_interaction` to apply the full lifecycle.

The snapshot contains steering, throttle, brake, handbrake, reset and camera toggle. The adapter supplies it before sedan physics at priority -20. The sedan never polls input. The driver trigger is monitoring-only, mask 2, and extends beyond the chassis. Claims immediately populate `character.vehicle_possession`, preventing raw cross-vehicle duplicate claims.

Exits raycast world from 0.25 m above to 2 m below the candidate and query a separate vehicle-only capsule (radius 0.4, height 1.8, center 0.9 m up). Candidate order: marker, eight 2.6 m radial probes from the left clockwise, saved mount transform. Exit orientation is normalized to upright projected yaw before both query and placement. Feet are placed at the world floor, with no query offsets applied. Teardown uses cached placement and vehicle position only.

The camera rig owns chase/hood cameras. It sphere-casts against mask 17 excluding its own body. A last child clears current without selecting another camera before camera unregistering; the adapter restores the saved camera after character relocation and pivot snapping.

## Sedan tuning

Handling helpers started from Physics Drive. The sedan's weight and steering were then retuned: the old center of mass sat below the tire contacts, so cornering lean was about 2° and inward, and full lock did not finish reducing until 38 m/s, so neighborhood turns sat on the tire limit near 1 g.

| Group | Defaults |
|---|---|
| Body | 1320 kg; COM (0, 0.52, 0.12); linear damping 0.03 |
| Power | forward 2200 N, reverse 1100 N; top speeds 42 / 12 m/s; response 2.8; direction-change threshold 1 m/s |
| Braking | service 1800; rear handbrake 2600 |
| Steering | 28° low / 1.6° high; power 3.2, full reduction at 22 m/s; response 2.2 / return 3.6 |
| Resistance | rolling 0.35; aero 0.01; maximum drag 120 N |
| Stability | downforce 1.5, capped 3200 N; yaw stiffness 420 above 6 m/s, capped 1400 |
| Grip | rear 1.15; handbrake multiplier 0.38; recovery 2.8 |
| Wheels | radius 0.36 m; rest 0.40 m; travel 0.44 m; stiffness 11; max suspension 9000; compression 1.5 / relaxation 2.2; roll influence 0.18 |
| Camera | offset (0, 3, 7.6); position / rotation smoothing 5.5 / 7; FOV 68–74°, full at 38 m/s, smoothing 3.5 |

Vehicle layer is 16, mask 7. Character/camera masks are 17. Bone node masks remain 1; simulating RIDs use layer 4/mask 17 and idle RIDs use zero. Recovery rays remain world-only. Vehicles never occupy traversal layer 4.

Departing occupants synchronously release their claim and neutralize driver controls. Detached surviving characters restore body/Rig immediately, then snap and restore their stored camera after reattachment.

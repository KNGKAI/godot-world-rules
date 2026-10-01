# Liberty Character Module

This module owns the reusable runtime character controller. Runtime code stays under this directory; editor-only helpers belong under `res://addons/liberty_character_editor/`.

## Boundaries

- Every character instance owns a `LibertyEvents` child. No event autoload is used.
- Only `events/liberty_event_adapter.gd` may connect runtime events to external UI, audio, analytics, or game-wide systems.
- `LibertyCharacter` is the sole owner of `move_and_slide()`.
- Runtime scenes may reference rig and animation assets under `res://assets/characters/`.
- Every globally named runtime type starts with `Liberty`.

## Movement API

- `input_basis_source` supplies yaw-only movement orientation; when absent, movement uses world axes.
- `movement_state` follows movement lock, airborne status, then actual grounded planar speed. `movement_state_changed` emits only real transitions.
- `set_movement_locked()` is idempotent. Locking suppresses input and brakes naturally while gravity and collision continue; unlocking immediately derives the correct airborne or grounded speed state.
- `teleport_to(destination, preserve_velocity)` resets character interpolation, optionally clears velocity, refreshes movement state, and snaps the owned camera without a damped sweep.
- `set_scripted_locomotion(planar_direction, gait_cap, facing, has_facing)` arms a parallel intent consumed in `_physics_process`. It does not change `get_world_input_direction()`. Movement lock still brakes. Jump is suppressed, and walk/sprint keys do not change the cap. The cap is meters per second, clamped to `[0, sprint_speed]`. Direction is flattened and limited to length 1. Non-finite direction or cap, or a zero or non-finite facing vector when `has_facing` is true, returns `ERR_INVALID_PARAMETER` and leaves the current mode unchanged.
- With no facing, grounded scripted movement turns toward travel at `_current_turn_rate_degrees()` and accelerates along forward at `ground_acceleration`. Airborne scripted movement uses `air_control` and `high_speed_turn_rate_degrees` (120). With facing, yaw tracks that flat world vector at the same branch rate, and planar velocity accelerates toward `direction * gait_cap` in world space.
- `clear_scripted_locomotion()` is idempotent. `has_scripted_locomotion()` is the traversal coordinator's extra early-out: a traversal does not start while the flag is set, unless one is already locked.

## Camera API

- `LibertyCameraPivot` captures mouse motion, applies immediate yaw and pitch, and follows the character's shoulder target with frame-rate-independent damping.
- `snap_to_target()` immediately aligns the camera pivot and resets interpolation for teleport-safe presentation.
- Grounded movement uses the camera pivot's yaw. After 1.25 seconds without mouse motion, a moving grounded character softly recenters the camera toward its heading; idle and airborne characters retain the chosen orbit.
- `SpringArm3D` queries world and vehicle_body (mask 17) with a 0.3 meter sphere.

## Mobile Controls

- `LibertyMobileControls` supplies a floating left-side movement joystick, right-side drag camera control, Jump, hold-to-Sprint, hold-to-Climb, and Drop buttons.
- Movement, jump and sprint use the existing actions. Traversal uses separate unbound `liberty_touch_traverse` and `liberty_touch_drop` actions, so releasing a touch cannot release a held desktop Traverse key. Drop queues a single press across physics frames. Focus loss, hiding the overlay and tree exit release owned touches.
- The overlay appears automatically when Godot reports a touchscreen. Enable `force_visible` on `MobileControls` to preview it on desktop.
- The controls track touch indices independently, allowing movement, camera look, and an action button at the same time.
- Button placement accounts for the platform display-safe area and updates when the viewport size changes.
- The overlay consumes every screen touch, so GUI `Button`s underneath never receive taps. Scenes that need extra touch buttons call `add_custom_button(title, color, callback)`; buttons fill a row along the top-right safe edge, track their own touch index and call `callback` on press. `get_custom_button(title)` returns the panel.

## Camera Acceptance Course

Open `res://modules/liberty_character/tests/test_camera.tscn` and press F6. Use WASD to move, Left Alt to walk, Shift to sprint, Space to jump, and the mouse to orbit.

Confirm that the mouse is captured, pitch stops at both limits, soft recenter begins only after the delay, the camera does not inherit character yaw, and walls, pillars, the low ceiling, corners, and the tight orange pocket never visibly clip the camera. Teleports must not produce a delayed sweep or interpolation streak.

## Tuning Record

Values are recorded here only after their phase has been measured and approved.

### Phase 3 animation integration — approved

The default character now instances the prototype mannequin as `Rig`; the
collision capsule and feet-origin are unchanged. `LibertyAnimationDriver` owns
the AnimationTree foundation and reads movement after the character physics tick.
The tree evaluates next, followed by physics-mode skeleton modifiers.

Top-level states are `Locomotion`, `Airborne`, `Traversal`, `Recovery`, and `Performance`.
Phase 5 fills Traversal; Phase 6 fills Recovery with GetUpFront/GetUpBack. Locomotion routes
the cyclic-mutable BlendSpace1D through TimeScale. Its blend points are actual
gait speeds in m/s, not normalized input strengths. Airborne is a nested machine
with Jump, Fall, and Land; Fall begins at the apex or Jump clip completion,
whichever occurs first. A landed event selects Land; playback completion returns
to Locomotion. A fresh jump interrupts Land. Animation does not move the body.

Authored in-place stance speeds are idle **0.0**, walk **2.2**, run **5.0**, and
sprint **7.5 m/s**. These are backward planted-foot velocities, not stationary
root displacement divided by clip duration. The standalone rig test independently
checks all three moving gaits. The driver computes the neighboring-weighted
authored speed and applies `actual_speed / effective_authored_speed`; idle or
effective authored speed below `0.01` uses scale `1.0`.

Owned driver interfaces: `build_tree_root(prefix, blend_points)`,
`compute_time_scale(speed, points, authored)`, `get_playback()` (top-level
playback), `get_state()` (diagnostic state path), `get_authored_speeds()`,
`play_performance(clip)`, `stop_performance()`, and `is_performance_playing()`.
`Performance` is one `AnimationNodeAnimation`, entered with `playback.start` and
left only by `stop_performance`. While that clip is owned, `_update_state` is skipped.
`clip_prefix` defaults to the imported default animation library's empty prefix.
`configuration_error` identifies missing required clips or invalid gait ordering;
such configurations leave animation inactive without disabling character physics.
Existing tree parameter paths remain `parameters/Locomotion/BlendSpace1D/blend_position`
and `parameters/Locomotion/TimeScale/scale`. Nested airborne playback lives at
`parameters/Airborne/playback`; top-level playback cannot travel through it.

Open `res://modules/liberty_character/tests/test_animation.tscn` and press F6.
WASD moves, Left Alt walks, Shift sprints, Space jumps; mouse/touch controls are
unchanged. Esc releases/captures the mouse for the flat-ground and ledge buttons.
The course shows live speed/state/scale and straight steady-gait foot drift.
Walk off the raised platform to check Fall and Land; jump again during landing.

Quantitative checks: `test_animation_foot_drift.gd` samples world-space ankle bones
after completed 60 Hz body/tree ticks over ten complete stance windows per foot.
It excludes swing motion, discards the initial partial contact, and guards 2% of
the cycle at touchdown/toe-off. It checks maximum excursion from each planted
anchor and sums the magnitude of stance-end residuals (no cancellation).
Contact height must remain within 5 mm of the authored 0.09 m ankle height.
Results and commands are recorded in the Phase 3 report. The user approved
interactive operation after the elbow-direction correction.

### Approved movement and camera measurements

| Area | Parameter | Value | Measurement / notes |
|---|---|---:|---|
| Locomotion | Walk speed | 2.2 m/s | Approved balanced-heavy default. |
| Locomotion | Run speed | 5.0 m/s | Approved balanced-heavy default. |
| Locomotion | Sprint speed | 7.5 m/s | Hard planar speed cap. |
| Locomotion | Ground acceleration | 9.0 m/s² | Shared gait acceleration. |
| Locomotion | Ground deceleration | 6.0 m/s² | Slower than acceleration for coasting. |
| Locomotion | Turn rate | 420–120°/s | Interpolated from rest to sprint speed. |
| Locomotion | Air control | 3.0 m/s² | Preserves momentum without input. |
| Locomotion | Gravity | 24.0 m/s² | Applied while airborne, including movement lock. |
| Locomotion | Jump velocity | 7.2 m/s | Grounded jumps only. |
| Camera | Shoulder target | 1.45 m | Centered above the character's feet-origin. |
| Camera | Distance / FOV | 4.5 m / 75° | Centered chase framing. |
| Camera | Mouse sensitivity | 0.12°/pixel | Immediate orbit response. |
| Camera | Pitch limits | 70° up / 50° down | Hard clamped. |
| Camera | Follow half-life | 0.12 s | Exponential and frame-rate independent. |
| Camera | Recenter delay / half-life | 1.25 s / 0.45 s | Grounded movement only. |
| Camera | Teleport snap threshold | 3.0 m | Large discontinuities bypass damping. |
| Camera | Collision sphere | 0.3 m | Queries world and vehicle_body (mask 17). |
| Measurement | Blocked / restored arm | 1.500 m / 4.500 m | Automated close-wall and open-space course. |
| Measurement | Camera-relative alignment | 0.983 dot | Forward movement after a 90° camera orbit. |
| Measurement | 95% top-speed time | walk 0.233 s; run 0.533 s; sprint 0.800 s | Measured at 60 physics ticks/s. |
| Measurement | Stopping distance | walk 0.385 m; run 2.042 m; sprint 4.625 m | From full gait speed to ≤0.1 m/s. |
| Measurement | 180° turn radius | run 0.859 m; sprint 2.309 m | Half maximum lateral displacement before facing reverses by 170°. |

## Traversal detection API (Phase 4)

Phase 5 attaches this tested subsystem to the playable scene through the owned
`Traversal` coordinator.

- `LibertyTraversalCandidate` describes an action, source/destination feet-origin
  transforms, contact axes, collider identity, clearance, confidence, and four limb
  targets. `is_valid()` checks finite data and orthonormal surface axes;
  `has_live_static_collider()` separately checks tagged static support.
- `LibertyTraversalProbe.sample(character_transform)` returns nearby observations.
  Set `character_body` to exclude its RID. Tagged bodies must occupy layers 1 and
  4; clearance checks use layer 1. Animatable bodies are unsupported. Real top
  edges take precedence over virtual holds. Low obstacles produce vault/mantle
  opportunities; tagged walls supply holds, continuation, corners and gap targets.
- Probe defaults: forward/up/down reach 0.9/1.4/1.2 m; hand/foot spacing 0.35/0.45 m;
  capsule radius/height 0.4/1.8 m, centered 0.9 m above the transform origin; contact
  height 1.55 m, foot height 0.35 m, clearance margin 0.02 m. Wall normals require
  `abs(y) <= 0.35`; top/floor normals require `dot(UP) >= 0.7`.
- `LibertyTraversalSolver.choose(candidates, world_input_direction, delta)` scores
  direction, confidence, facing and distance with real-edge preference. Switching
  uses a 0.15 score margin and 0.12 s delay. Identity includes action and contact
  within 0.15 m, not just collider ID. Missing observations expire after 0.12 s;
  empty observations return null. `clear()` resets the cache and switch timer.
- Pipeline order is probe → `controller.filter_candidates(observations, grounded,
  jump_pressed, movement_direction)` → solver → controller update. Filtering keeps
  airborne catches from competing with grounded hangs and suppresses unintended
  jumps. Forward into the wall maps to upward climbing; backward maps downward.
  Both scoring and controller acceptance use that mapping. Opposite-direction
  sustained movement settles into Hang immediately.
- `LibertyTraversalController.update_intent(candidate, traverse_held,
  jump_pressed, drop_pressed, grounded, movement_direction, airborne_velocity,
  delta, support_observed = true)` owns transitions and movement-lock intent.
  `support_observed` refers to the currently occupied hold, independently of a
  proposed continuation: pass false when probes no longer confirm its support.
  A valid hold with no lateral continuation remains hanging at the ledge end.
  Missing support gets 0.12 s grace; stale support cannot start another action.
- Entry/continuation require held Traverse plus nonzero movement intent. A gap
  requires explicit Jump; Drop emits drop then falling and releases immediately.
  Releasing Traverse preserves Hang. Catch speed limit is 12 m/s and facing limit
  is 65 degrees. `complete_action()` is reserved for motor-confirmed completion;
  no timer pretends a physical traversal finished. `interrupt(reason)` clears
  selected support, grace, and lock intent. Connect `events` to the owning typed
  `LibertyEvents`; state signals emit only on actual changes.

Virtual horizontal holds preserve elevation; the 0.02 m floor margin is applied
as an absolute minimum, so repeated targets do not accumulate drift. Destination
bases contain yaw only, matching the upright character capsule.

Destination clearance is an eligibility check, not a proof that a complete motion
path is collision-safe. The Phase 5 motor and character check every requested displacement against the actual capsule.

## Traversal motion API (Phase 5)

`LibertyTraversalCoordinator` samples intent before the AnimationTree evaluates,
then `LibertyCharacter` consumes the root request once and owns physical movement.
Normal locomotion retains its prior processing order. Supported traversal freezes
gravity; release restores ordinary gravity. The Drop clip is visual only after release.

`LibertyTraversalMotor.prepare_action(candidate, authored_terminal)` freezes an
accepted action and checks the residual from its authored endpoint: at most 0.45 m
and 25 degrees. `compute_request(root_delta, previous_progress, progress)` adds
incremental smoothstep correction over normalized progress 0.15–0.75. Root position
deltas remain in the action's original frame. Sustained shimmy and climb use
0.35 and 0.375 m/s controller displacement, with looping animation.

All 21 named traversal clips are required. Missing clips disable traversal with
`configuration_error` while leaving locomotion operational. The nested traversal
machine extracts `Skeleton3D:Root`; anatomical Left in this asset is local +X.

Skeleton order is traversal targets, four TwoBoneIK3D limbs, neutral head LookAt,
pose capture, then the inactive physical simulator. Targets blend over 0.1 s;
`interrupt_traversal(reason)` clears support, solver, motor, body lock and all four
IK influences immediately. Moving supports and blocked motion also interrupt.
The capture modifier records the corrected pose for the later ragdoll phase.

Open `res://modules/liberty_character/tests/test_traversal.tscn` and press F6.
Hold E with movement to enter/climb; Space selects a gap jump; Ctrl releases.
Touch uses CLIMB, JUMP and DROP, plus top-right PREV/RESET/NEXT/DEBUG buttons.
On desktop, Esc exposes the Previous/Reset/Next/Debug buttons.
The 13 stations cover obstacle actions, wall holds, gaps, corners, top-out, seams,
untagged geometry and clearance/path rejection. Debug starts off and shows probe
rays, candidate contacts, actual capsule bounds and frozen action destination.
The HUD reports body alignment and correction. Graphical acceptance approved.

## Ragdoll and recovery API (Phase 6)

`LibertyRagdoll` (child `Ragdoll`) code-builds 14 `PhysicalBone3D` bodies under the
skeleton's `PhysicalBoneSimulator3D`. Simulating bodies occupy layer 3 (`ragdoll`) and query world plus vehicle_body (mask 17). Their node mask remains WORLD_MASK (1); idle physics-server layers and masks are zero. They never collide with each other or with the capsule (layer 2). The get-up floor ray remains world-only.

`LibertyCharacter.activate_ragdoll(impulse_direction, force, reason) -> bool`
forwards to the ragdoll, which:

1. calls `interrupt_traversal(reason)`;
2. suspends the body (`set_body_suspended(true)`): capsule disabled, no
   `move_and_slide()`, movement state `movement_locked`;
3. starts simulation, then places every body at the IK-corrected pose from
   `LibertyPoseCaptureModifier` and seeds it with the character's velocity;
4. applies `force * hip_impulse_share` to Hips and the remainder to Chest; the
   total equals the requested impulse;
5. points the camera at the hips (`set_follow_override`) and emits `ragdoll_started`.

Recovery starts only after hip linear and angular speed both stay below their
thresholds for 0.5 s continuously (`advance_settle`); any fast frame resets the timer.
A layer-1 ray below the hips must find floor within 1.0 m and no steeper than 45°,
otherwise the ragdoll keeps simulating and retries after settling again
(`last_rejection` is `no_floor` or `steep_floor`). Face-up is the hips belly axis
(rest toe direction, −Z) pointing up. The root is placed on the floor under the
hips with the yaw that makes the chosen clip's first Hips frame match the ragdoll
hips' spine direction. `LibertyRagdollRebaseModifier`, the last skeleton modifier,
re-expresses simulated poses once after that root move, because simulated bones
cache poses relative to the previous physics step. Then the get-up plays, simulator
influence blends 1→0 over 0.4 s, simulation stops, and when the clip ends the
body is restored and `ragdoll_recovered(face_up)` fires. Recovery always returns to
Locomotion. `cancel_ragdoll()` (also called by `teleport_to`) returns to animation
immediately without a get-up.

Skeleton order: traversal targets, four TwoBoneIK3D limbs, head LookAt, pose
capture, physical simulator, ragdoll rebase.

| Bone | Mass | Joint | Limits | Capsule (radius / segment) |
|---|---:|---|---|---|
| Hips | 12.0 kg | none (root body) | — | 0.12 m, 0.36 m across X |
| Spine | 8.0 kg | cone | swing 20°, twist 10° | 0.12 m / 0.17 m |
| Chest | 12.0 kg | cone | swing 25°, twist 15° | 0.14 m / 0.28 m |
| Head | 5.0 kg | cone | swing 40°, twist 30° | 0.10 m / 0.12 m |
| Upper arms | 2.5 kg each | cone | swing 80°, twist 40° | 0.05 m / 0.28 m |
| Lower arms | 1.5 kg each | hinge (vertical T-pose axis) | 0–140°, hand folds forward (Left −140..0, Right 0..140) | 0.045 m / 0.34 m incl. hand |
| Upper legs | 8.0 kg each | cone | swing 60°, twist 20° | 0.075 m / 0.43 m |
| Lower legs | 4.0 kg each | hinge (lateral axis) | 0–140°, shin folds backward (0..140; corrected in Phase 7) | 0.06 m / 0.40 m |
| Feet | 1.0 kg each | cone | swing 30°, twist 10° | 0.04 m / 0.15 m |

Total mass 71 kg. Bodies use friction 0.8, linear damp 0.1, angular damp 0.8, and
continuous collision detection (thin limb capsules otherwise tunnel on fast impacts).
Hinge signs were measured on the real rig (collapse test reverse-bend check). Jolt
measures a hinge angle as the negative of the child's rotation about the hinge axis
relative to its parent. Phase 6 shipped the knees as −140..0, which allowed only
hyperextension, and its knee reverse-bend metric was inverted; Phase 7 corrected both.

| Parameter | Value |
|---|---:|
| Settle linear / angular speed | 0.2 m/s / 0.6 rad/s |
| Settle time | 0.5 s |
| Recovery floor probe / max angle | 1.0 m / 45° |
| Physical influence blend | 0.4 s |
| Hip impulse share | 0.5 |

Open `res://modules/liberty_character/tests/test_ragdoll.tscn` and press F6.
R, the KNOCK button, or the touch KNOCK button (top right) knocks down with a random 120–320 N·s horizontal
impulse (the wall station always pushes toward the wall). Touch PREV/RESET/NEXT
switch stations. Stations: flat floor,
20° ramp, 55° slope, wall, traversal wall. The HUD shows ragdoll state, face-up,
settle timer, hip speeds, floor angle/rejection and simulator influence.

## Active ragdoll API (Phase 7)

Hit reactions run on top of live animation; the capsule and ordinary movement never stop.

`LibertyCharacter.receive_hit(bone_name, direction, force, fatal) -> bool` forwards to
`LibertyPhysicalAnimation`. `acquire_hit_suppression()` returns a token.
`release_hit_suppression(token)` drops it; an unknown token is a no-op.
`is_hit_suppressed()` is true while any token is held, so callers can nest.
`receive_hit` returns false immediately in that case and does not emit `hit_received`.
`activate_ragdoll` is not suppressed. A bone is resolved to its nearest simulated body ancestor:
Neck and the shoulders map to Chest, hands to forearms, toes to feet, and Root to Hips.
Unknown bones and non-finite input return false and emit nothing.

- **Fatal:** calls `activate_ragdoll(direction, force, &"hit")`, then emits
  `hit_received(..., true)`, so `ragdoll_started` comes first.
- **Non-fatal:** loosens the hit bone's chain to `hit_strength` (0.15), then smoothsteps it
  back to 1.0 over `hit_recovery_time` (0.6 s). It pushes the mapped body with a central
  impulse capped at `mass × max_hit_delta_v` (4 m/s), then emits `hit_received(..., false)`.
  Once every chain is back to full strength, the simulator influence fades out over
  `fade_out_time` (0.2 s) and the reaction ends. A hit on Hips loosens the core and
  pushes Spine.
- **While traversing:** the hit calls `interrupt_traversal(&"hit")` first, so the character
  is knocked off the wall and falls normally while the reaction plays.
- **While ragdolled:** a still-simulating passive ragdoll takes the push and the event.
  During the get-up blend or clip, the hit is rejected.

Chains and the closed subtrees they simulate (a kinematic child would pin its dynamic parent):

| Chain | Strength bones | Simulated bodies |
|---|---|---|
| core | Hips, Spine, Chest, Head | Spine, Chest, Head, both arms |
| left/right arm | UpperArm, LowerArm | UpperArm, LowerArm |
| left/right leg | UpperLeg, LowerLeg, Foot | UpperLeg, LowerLeg, Foot |

A second hit on another chain adds its subtree to the running reaction. `LibertyRagdoll`
owns the bodies through `begin_active_simulation`, `extend_active_simulation`,
`end_active_simulation`, `set_reaction_influence`, `is_reacting` and `get_reaction_bones`.
`is_active()` still means the passive ragdoll only.

- **Standby:** outside a ragdoll, the simulator stays active with influence 0 and nothing
  simulating, so every body follows the animation kinematically. An inactive simulator
  leaves stale body poses that yank joining bodies.
- **Handing over:** `teleport_to`, `cancel_ragdoll` and passive activation all end a
  reaction. Passive activation takes over the running bodies without resetting them.

**Anchor and drive (user-approved alternative to script torques).** Hips stays
kinematic and is the anchor, with the ragdoll's own cone and hinge joints holding the
chain to it. Each simulated body also gets a Generic 6DOF drive joint to its physical
parent: linear axes free, no angular limits, and angular springs that Jolt solves
implicitly. Script-computed PD torques were tried first. They either resonated at the
arm-swing frequency or went unstable once sized for the load a limb carries (see the
Phase 7 ledger). Each tick, in the modifier stack, the stage:

1. reads the captured animated parent/child pair and clamps the joint-space target into the
   ragdoll joint limits (minus 2°);
2. leads the target by `damping / stiffness × target velocity` (capped at `max_lead`) to
   cancel spring lag, then re-clamps it;
3. caps how far the target may lead the current pose at `max_torque / k`, because Jolt ignores
   motor force limits on springs;
4. sets each drive axis's spring to `stiffness × strength × multiplier ×` the inertia about
   the joint pivot of the body plus its simulated descendants. Damping scales the same
   way, by `damping × √(strength × multiplier)`;
5. sets gravity scale to `1 − strength`, so a full-strength chain holds its pose and a
   loosened one sags.

The springs take XYZ Euler equilibrium points (Jolt settles the child at
`from_euler(e).inverse()`). Arms use Z,X,Y drive axes, so the middle angle stays at or
below 29°; other bones use their own axes (≤ 4°).

- **Start pose:** new bodies start at the clamped pose with their animated velocity.
  Starting outside a limit makes Jolt snap the body back in one step.
- **Display:** `LibertyRagdollRebaseModifier` re-anchors the simulated bones each reacting
  tick by the Hips' motion since the physics step, because simulated bones otherwise
  display one step behind the kinematic hips.
- **Guards:** a non-finite state, a body faster than `max_angular_speed`
  (60 rad/s, above Jolt's own 47.1 rad/s cap), a body more than `max_relative_speed` (15 m/s)
  faster than the capsule, or a joint separated by more than `max_joint_separation` (0.1 m)
  ends the reaction with a warning. The warning names the bone, the values, the physics
  rate and the fps.

**Processing order.**
- The coordinator runs at priority −30, then the character (0), the animation driver (1),
  the AnimationTree (2) and the Skeleton3D (3). During traversal these become −20, −10
  and 10.
- Modifiers run in physics mode, in this order: traversal targets, 4× TwoBoneIK3D, head
  LookAt, PoseCapture, **PhysicalAnimation**, PhysicalBoneSimulator, RagdollRebase.
- The stage lives in the modifier stack because a node reading the capture from
  `_physics_process`, even at priority 20, sees the previous tick's capture.
- The stage reads only the capture and the physics server. It never reads the simulated
  skeleton pose and never writes bone poses.

| Parameter | Value |
|---|---:|
| Stiffness | 2 500 s⁻² × pivot inertia per drive axis |
| Damping | 20 s⁻¹ × pivot inertia |
| Max torque | 800 N·m (caps spring target lead) |
| Max lead | 1.0 rad |
| Per-bone multipliers | 1.0 (scale stiffness and max torque; damping by √) |
| Hit strength / recovery / fade | 0.15 / 0.6 s / 0.2 s |
| Max hit Δv | 4 m/s |
| Guards | 60 rad/s, 15 m/s relative, 0.1 m joint separation |

Measured at 60 Hz, headless on the development phone (see
`docs/superpowers/plans/2026-09-27-phase-7-report.md`):

| Gait | Error p95 / max | Notes |
|---|---:|---|
| Idle | 0.0° / 0.1° | |
| Run | 11.0° / 17.7° | spine 2.3° |
| Sprint | 22.0° / 27.7° | arms ≤ 28° |

- **Joint gap at the waist:** ≤ 6 mm.
- **Stability:** a sprinting leg hit drives the feet to Jolt's cap, because the clip holds the
  foot level while the shin swings, but joints stay within 0.08 m and the guards never trip.
- **Cost:** the stage costs about 1–3 ms of GDScript per reacting tick on this device.

Open `res://modules/liberty_character/tests/test_active_ragdoll.tscn` and press F6.
- **Controls:** F or HIT hits the selected bone (Target cycles through random, Head, Chest,
  Hips, hands, a thigh and a foot); R or FATAL hands over to the Phase 6 ragdoll. On touch,
  use the HIT, FATAL, TARGET, PREV, RESET and NEXT buttons at the top right.
- **Stations:** standing, a run lane, beside a wall (hits push toward it), and a traversal
  wall (knock-off).
- **HUD:** mode, last hit, influence, per-chain strength, error, ω, joint separation and PD
  cost, each current and as a peak since reset, plus any guard trip.

## Project settings and editor tooling (Phase 8)

- `LibertySettings` (`settings/liberty_settings.gd`) holds the approved `liberty_character/*` settings (see the root `README.md`). Each row is `[name, component, property, scale]`; angle settings are stored in degrees and converted with `scale`.
- `LibertySettings.apply(component, node)` runs right after each code-built component is created and before the first physics tick:
  - `LibertyTraversalCoordinator._ready`: `coordinator` (itself), then `probe`, `solver`, `controller`, `motor` before `add_child`, and `ik` before it is configured.
  - `LibertyRagdoll._ready`: `physical_animation`, before it joins the skeleton.
- The fallback is the component's current value, so an absent setting changes nothing. A bool setting can only enable a flag, so a per-node `debug_traversal = true` is kept. A Dictionary setting is merged per key, so naming one bone in `bone_multipliers` keeps the others at their own values.
- Settings are read once. Tests and courses that change component values at runtime still work.
- The runtime never references `addons/liberty_character_editor/`; `test_project_settings.gd` scans `res://modules` to keep it that way.
- Editor plugin, all editor-only:
  - Inspectors:
    - `LibertyCharacter`: derived movement figures from a tick replay of the flat-ground model (95 % speed time, stopping distance, 180° turn radius, jump apex and air time). Pinned to the measured table above.
    - `LibertyTraversalCoordinator`: traversal settings.
    - `LibertyRagdoll`: physical-animation settings, the hit-recovery strength curve and the `BONE_LAYOUT` table.
    - Edits are undoable and saved immediately.
  - Gizmos (View → Gizmos): Liberty Traversal Probe and Liberty IK Targets on the Traversal node, and Liberty Ragdoll Joints on the character. They are static, drawn from settings and the skeleton rest pose. Hinge arcs follow Jolt's sign: a configured angle θ turns the child by −θ.
  - Enabling registers the settings with their runtime defaults as initial values, so saving never writes defaults. Disabling removes only the settings still at their default, so the game reads the same values either way.

## Vehicle possession (Phase 9A)

The capsule queries world plus vehicle_body (mask 17). `LibertyEventAdapter` owns the possession lifecycle, saved camera and sole `occupancy_changed` emit. `vehicle_possession` tracks an atomic seat claim, while `set_body_suspended` handles movement/collision suspension. Mounted hits and direct ragdoll entry return false.

`LibertyMobileControls.set_suspended(bool)` releases held touches before hiding and restores `force_visible or touchscreen` policy on exit. The adapter adds ENTER and a sibling vehicle overlay; it hides only Rig while mounted. Animation continues. The character pivot ignores mounted mouse look and is snapped before the stored camera is restored.

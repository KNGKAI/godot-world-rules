# Liberty mannequin animation pack

An original low-poly, skinned humanoid with all 30 prototype clips required by
the Liberty controller design. The GLB is portable glTF 2.0: mesh, materials,
skeleton and animations are embedded in one file. No Blender installation,
textures, downloaded models, or third-party motion libraries are required.

This is a **portable asset** with a standalone preview. Phase 3 uses it as the
default playable visual while retaining the collision capsule. It does not
enable traversal, recovery, IK, or ragdoll gameplay. Motions are prototype
keyframes, not motion capture or a finished character animation production.

## Preview

Open `res://modules/liberty_character/tests/test_mannequin.tscn` in Godot 4.7.1
and press F6. Select any clip, pause, scrub the timeline, change speed, and use
the orbit/distance sliders to inspect the model. Controls work with mouse or
touch. The floor grid is spaced one meter apart.

The **Root motion** toggle displays the authored displacement and yaw. Turn it
off to inspect the action in place. The camera follows root displacement;
switching clips resets the pose and origin. One-shot clips hold their final
pose; Play restarts a completed action and resumes a paused action.

## Regenerate

From the project root:

```sh
python3 addons/liberty_character_editor/generate_mannequin.py
godot --headless --path . --import --quit
```

The generator overwrites only `liberty_mannequin.glb` and
`animation_manifest.json` in this directory. It accepts `--output-dir PATH`
for an independent export. Python's standard library is sufficient. Edit
`BONES`, geometry primitives, clip durations and pose functions in the source
to change the model or motions, then regenerate and reimport.

## Skeleton and conventions

- Height: 1.8 meters in the rest pose. Feet-origin, Y up, front at −Z.
- Neutral rest pose: T-pose; all joint rest rotations are identity.
- 23 body bones, with Godot humanoid body names. No fingers or facial bones.
- Separate `Root` supplies translation/yaw; `Hips` supplies body pose.
- The mesh uses named skin binds, inverse bind matrices and normalized weights.
- Flat-shaded teal shell, dark joints/visor, orange badge; no texture dependency.
- Quaternion and translation tracks are baked with intervals at most 1/30 s,
  including exact start/end samples. Fast gait tracks use 120 Hz samples to
  retain foot contacts between quaternion keys. Loop endpoints match.

```text
Root
└── Hips
    ├── LeftUpperLeg → LeftLowerLeg → LeftFoot → LeftToes
    ├── RightUpperLeg → RightLowerLeg → RightFoot → RightToes
    └── Spine → Chest → UpperChest
                           ├── Neck → Head
                           ├── LeftShoulder → LeftUpperArm → LeftLowerArm → LeftHand
                           └── RightShoulder → RightUpperArm → RightLowerArm → RightHand
```

glTF has no standard playback-loop flag. The sidecar manifest records the loop
policy, also repeated in each animation's glTF `extras`. This project's
`mannequin_post_import.gd` applies it at import, so loop settings work outside
the preview too. Keep the `.glb.import` file and post-import script in this
project. In another application, set the loop policy listed below yourself;
the GLB plays without the sidecar but that application may ignore `extras`.

## Animation contract

Exact names match the project design. The imported default animation library
uses these names without a prefix; `RESET` is an additional Godot rest-pose
animation, not one of the 30 action clips. If a consumer places clips in a
named library, configure its animation-driver prefix accordingly.

| Clip | Seconds | Playback |
|---|---:|---|
| idle | 2.40 | Loop |
| walk | 0.80 | Loop |
| run | 0.62 | Loop |
| sprint | 0.46 | Loop |
| jump | 0.55 | One-shot |
| fall | 1.00 | Loop |
| land | 0.42 | One-shot |
| vault_low | 0.90 | One-shot |
| vault_high | 1.15 | One-shot |
| mantle_low | 1.30 | One-shot |
| mantle_high | 1.80 | One-shot |
| climb_enter | 1.00 | One-shot |
| hang_idle | 2.00 | Loop |
| shimmy_left | 1.00 | Loop |
| shimmy_right | 1.00 | Loop |
| climb_up | 1.20 | Loop |
| climb_down | 1.20 | Loop |
| corner_inner_left / corner_inner_right | 1.00 each | One-shot |
| corner_outer_left / corner_outer_right | 1.20 each | One-shot |
| ledge_jump_up | 0.90 | One-shot |
| ledge_jump_left / ledge_jump_right | 0.95 each | One-shot |
| ledge_jump_forward | 1.10 | One-shot |
| ledge_catch | 0.65 | One-shot |
| ledge_drop | 0.60 | One-shot |
| climb_top_out | 1.65 | One-shot |
| get_up_front | 2.20 | One-shot |
| get_up_back | 2.50 | One-shot |

Locomotion, jump/fall/land, sustained climbing and recovery have stationary
roots. Gait stance motion is authored at **2.2 m/s walk, 5.0 m/s run and
7.5 m/s sprint**. Left/right refer to the character's anatomical sides: with
the mannequin facing −Z, left displacement is +X and right is −X.

The offline limb solver uses separate bend directions: elbows bend backward
(+Z), while knees bend forward (−Z). The imported-rig test checks both sides
through idle and each locomotion gait so regenerated assets retain this anatomy.

`get_up_front` begins face-down; `get_up_back` begins face-up. Both end standing.
Between the lying hold and the standing blend, get-up legs follow interpolated
world-space ankle, foot and knee-bend targets (knees splay outward only as far as
needed), so no bone passes below the floor. This Phase 6 correction keeps the
names, durations, start/end poses and every other clip unchanged.
`climb_top_out` starts hanging and ends standing; ledge jumps start and end
hanging; drop ends falling; catch starts falling and ends hanging.

### Root motion and reference geometry

Discrete actions provide reference root curves for the collision-safe Phase 5
traversal motor. Root position/yaw must be extracted and consumed by the
owning character body; playing these raw clips alone does not move collision.
The preview intentionally displays the raw curves without collision.

| Action | Reference motion / geometry |
|---|---|
| vault_low | 0.65 m obstacle height, 0.40 m depth; 1.35 m forward travel |
| vault_high | 1.05 m obstacle height, 0.40 m depth; 1.65 m forward travel |
| mantle_low | 0.75 m top height; 0.95 m forward travel |
| mantle_high / climb_top_out | 1.40 m top height; 0.95 m forward travel |
| climb_enter | 0.30 m upward, 0.40 m forward |
| inner corners | ±0.08 m lateral approach; opposite ∓90° yaw |
| outer corners | ±0.77 m lateral, 0.84 m forward; capsule-radius arc and ±90° yaw |
| ledge_jump_up | 0.65 m upward |
| ledge_jump_left / right | ±0.90 m lateral |
| ledge_jump_forward | 1.20 m forward |
| ledge_drop | 0.70 m downward, 0.20 m away from the wall |

Up/lateral jumps include a 0.24 m arc above their interpolated destination.
Forward jumps lift 1.80 m before crossing the source ledge. Vaults lift 0.25 m
above the reference roof and remain elevated until clearing its far edge.
Mantles lift before entering the face and finish on top. These Phase 5 curve
corrections preserve the original endpoints except the user-approved corner
endpoints. Full displacement,
yaw, duration, gait speed and obstacle metadata are in `animation_manifest.json`.

Handholds and foot contacts are illustrative poses. Actual obstacle placement,
collision clearance, target correction and procedural limb IK are the Phase 5
traversal system's responsibility. The reference clips are not guaranteed to
fit every obstacle or ragdoll starting pose unchanged.

## Checks

```sh
python3 -B modules/liberty_character/tests/test_mannequin_export.py
godot --headless --path . --script modules/liberty_character/tests/test_mannequin_preview.gd
python3 -B modules/liberty_character/tests/render_mannequin_contact_sheet.py
```

The first checks the actual GLB's clips, skinning, finite motion and loop/root
contracts. The second verifies imported bones, animation playback, gait foot
contacts, loop settings, timeline resume and root compensation in Godot. The
third software-renders five poses per exported clip to three PNG sheets under
`/tmp`, for inspection when no graphical display is available.

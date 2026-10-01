#!/usr/bin/env python3
"""Generate an original, portable skinned mannequin and prototype motions.

Only Python's standard library is required. Run from any working directory.
All geometry and poses are authored here; no downloaded assets are used.
"""
import argparse
import json
import math
from pathlib import Path
import struct

REPO = Path(__file__).resolve().parents[2]
DESTINATION = REPO / "assets/characters/liberty_mannequin"
TAU = math.tau
IDENTITY = (0.0, 0.0, 0.0, 1.0)


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def mul(a, s):
    return tuple(x * s for x in a)


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def unit(v):
    return mul(v, 1 / max(math.sqrt(dot(v, v)), 1e-12))


def qmul(a, b):
    xyz = add(add(mul(b[:3], a[3]), mul(a[:3], b[3])), cross(a[:3], b[:3]))
    return (*xyz, a[3] * b[3] - dot(a[:3], b[:3]))


def inverse(q):
    return (-q[0], -q[1], -q[2], q[3])


def rotate(q, v):
    return qmul(qmul(q, (*v, 0.0)), inverse(q))[:3]


def euler(x=0, y=0, z=0):
    x, y, z = (math.radians(v) / 2 for v in (x, y, z))
    return qmul(qmul((0, math.sin(y), 0, math.cos(y)), (math.sin(x), 0, 0, math.cos(x))), (0, 0, math.sin(z), math.cos(z)))


def between(a, b):
    a, b = unit(a), unit(b)
    d = dot(a, b)
    if d < -0.999999:
        axis = unit(cross(a, (0, 1, 0) if abs(a[1]) < 0.9 else (1, 0, 0)))
        return (*axis, 0.0)
    return unit((*cross(a, b), 1 + d))


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


# Global rest coordinates. Every bone has an identity rest rotation; limbs are
# in a T-pose so the skeleton remains straightforward to edit and retarget.
BONES = [
    ("Root", None, (0, 0, 0)),
    ("Hips", "Root", (0, 0.92, 0)),
    ("Spine", "Hips", (0, 1.06, 0)),
    ("Chest", "Spine", (0, 1.23, 0)),
    ("UpperChest", "Chest", (0, 1.38, 0)),
    ("Neck", "UpperChest", (0, 1.51, 0)),
    ("Head", "Neck", (0, 1.60, 0)),
]
for side, sign in (("Left", 1), ("Right", -1)):
    BONES.extend([
        (side + "Shoulder", "UpperChest", (sign * 0.15, 1.43, 0)),
        (side + "UpperArm", side + "Shoulder", (sign * 0.22, 1.43, 0)),
        (side + "LowerArm", side + "UpperArm", (sign * 0.50, 1.43, 0)),
        (side + "Hand", side + "LowerArm", (sign * 0.76, 1.43, 0)),
        (side + "UpperLeg", "Hips", (sign * 0.105, 0.92, 0)),
        (side + "LowerLeg", side + "UpperLeg", (sign * 0.105, 0.49, 0)),
        (side + "Foot", side + "LowerLeg", (sign * 0.105, 0.09, 0)),
        (side + "Toes", side + "Foot", (sign * 0.105, 0.05, -0.14)),
    ])
REST = {name: p for name, _, p in BONES}
PARENT = {name: parent for name, parent, _ in BONES}
INDEX = {name: i for i, (name, _, _) in enumerate(BONES)}
LOCAL = {name: sub(p, REST[parent]) if parent else p for name, parent, p in BONES}


def global_pose(pose, bone):
    parent = PARENT[bone]
    local = pose[bone]
    if parent is None:
        return local
    p, q = global_pose(pose, parent)
    return add(p, rotate(q, local[0])), qmul(q, local[1])


def solve_limb(pose, side, arm, target, pole=None, end_rotation=None):
    """Analytic two-link IK used offline, not a runtime skeleton modifier.

    Optional world-space pole and end rotation override the default bend and
    end orientation; every original caller omits them.
    """
    upper = side + ("UpperArm" if arm else "UpperLeg")
    lower = side + ("LowerArm" if arm else "LowerLeg")
    end = side + ("Hand" if arm else "Foot")
    parent_p, parent_q = global_pose(pose, PARENT[upper])
    origin = add(parent_p, rotate(parent_q, LOCAL[upper]))
    goal = rotate(inverse(parent_q), sub(target, origin))
    l1, l2 = (math.sqrt(dot(LOCAL[n], LOCAL[n])) for n in (lower, end))
    distance = min(l1 + l2 - 0.0001, max(abs(l1 - l2) + 0.0001, math.sqrt(dot(goal, goal))))
    direction = unit(goal)
    # Facing -Z: knees point forward, but elbows bend behind the arm axis.
    preferred = rotate(inverse(parent_q), pole if pole is not None else (0, 0, 1 if arm else -1))
    bend = unit(sub(preferred, mul(direction, dot(preferred, direction))))
    cosine = max(-1.0, min(1.0, (l1 * l1 + distance * distance - l2 * l2) / (2 * l1 * distance)))
    elbow = mul(add(mul(direction, cosine), mul(bend, math.sqrt(max(0, 1 - cosine * cosine)))), l1)
    q1 = between(LOCAL[lower], elbow)
    q2 = between(LOCAL[end], rotate(inverse(q1), sub(mul(direction, distance), elbow)))
    pose[upper] = (LOCAL[upper], q1)
    pose[lower] = (LOCAL[lower], q2)
    world_q = qmul(qmul(parent_q, q1), q2)
    desired = euler(z=-90 if side == "Left" else 90) if arm else IDENTITY
    if end_rotation is not None:
        desired = end_rotation
    pose[end] = (LOCAL[end], qmul(inverse(world_q), desired))


def body_pose(hip_y=0.92, lean=0, hip_z=0, torso=0, twist=0):
    pose = {name: (LOCAL[name], IDENTITY) for name, _, _ in BONES}
    pose["Hips"] = ((0, hip_y, hip_z), euler(x=lean))
    pose["Spine"] = (LOCAL["Spine"], euler(x=torso, y=twist))
    pose["Head"] = (LOCAL["Head"], euler(x=-lean * 0.4 - torso * 0.5))
    for side, sign in (("Left", 1), ("Right", -1)):
        solve_limb(pose, side, False, (sign * 0.105, 0.09, 0))
        solve_limb(pose, side, True, (sign * 0.29, hip_y + 0.04, -0.025))
    return pose


def gait(t, speed, duration, stance, lean):
    hip_y = {2.2: 0.79, 5.0: 0.73, 7.5: 0.70}[speed]
    bob = 0.018 if speed == 2.2 else 0.045
    hip_y += bob * (1 - math.cos(2 * TAU * t))
    targets = []
    for side, sign, phase in (("Left", 1, t), ("Right", -1, (t + 0.5) % 1)):
        phase %= 1
        extent = speed * duration * stance / 2
        if phase < stance:
            z = -extent + speed * duration * phase
            height = 0.09
        else:
            swing = (phase - stance) / (1 - stance)
            z = extent * (1 - 2 * smooth(swing))
            height = 0.09 + (0.10 if speed == 2.2 else 0.27) * math.sin(math.pi * swing)
        targets.append((side, sign, phase, (sign * 0.105, height, z)))
        # Preserve the stance foot's authored position rather than clamping the
        # IK target when stride plus bob exceeds the 0.83 m leg chain's reach.
        hip_y = min(hip_y, height + math.sqrt(max(0, 0.82 ** 2 - z ** 2)))
    pose = body_pose(hip_y, lean, torso=-4, twist=4 * math.sin(TAU * t))
    for side, sign, phase, target in targets:
        solve_limb(pose, side, False, target)
        wave = math.sin(TAU * phase)
        solve_limb(pose, side, True, (sign * 0.30, hip_y + (0.10 if speed == 2.2 else 0.26), -wave * (0.17 if speed == 2.2 else 0.30)))
    return pose


def blend_pose(a, b, weight):
    result = {}
    for name in a:
        p1, q1 = a[name]
        p2, q2 = b[name]
        if dot(q1, q2) < 0:
            q2 = mul(q2, -1)
        result[name] = (add(mul(p1, 1 - weight), mul(p2, weight)), unit(add(mul(q1, 1 - weight), mul(q2, weight))))
    return result


def keyed(t, keys):
    for (at, a), (bt, b) in zip(keys, keys[1:]):
        if t <= bt:
            return blend_pose(a, b, smooth((t - at) / (bt - at)))
    return keys[-1][1]


def hands(pose, left, right):
    solve_limb(pose, "Left", True, left)
    solve_limb(pose, "Right", True, right)
    return pose


def hang(t=0, kind="hang_idle"):
    cycle = math.sin(TAU * t)
    pose = body_pose(0.89 + 0.006 * math.cos(TAU * t), -5, 0.20, torso=-3)
    for side, sign in (("Left", 1), ("Right", -1)):
        phase = (t + (0.5 if sign < 0 else 0)) % 1
        reach = 0.5 - 0.5 * math.cos(TAU * phase)
        x, y, z = sign * 0.27, 1.91, -0.14
        if kind.startswith("shimmy"):
            direction = 1 if kind.endswith("left") else -1
            x += direction * 0.16 * math.sin(TAU * phase)
            y += 0.04 * reach
        elif kind in ("climb_up", "climb_down"):
            y += (1 if kind == "climb_up" else -1) * 0.12 * math.sin(TAU * phase)
        solve_limb(pose, side, True, (x, y, z))
        solve_limb(pose, side, False, (sign * 0.17, 0.38 + 0.12 * reach, -0.24))
    pose["Chest"] = (LOCAL["Chest"], euler(y=2 * cycle))
    return pose


def airborne(t, kind):
    ready = body_pose()
    crouch = hands(body_pose(0.65, -12, torso=-10), (0.30, 0.86, 0.22), (-0.30, 0.86, 0.22))
    launch = hands(body_pose(0.91, -5), (0.29, 1.57, -0.32), (-0.29, 1.57, -0.32))
    flying = hands(body_pose(0.90, 3), (0.41, 1.36, -0.25), (-0.41, 1.36, -0.25))
    for side, sign in (("Left", 1), ("Right", -1)):
        solve_limb(flying, side, False, (sign * 0.13, 0.32, 0.19))
    if kind == "jump":
        return keyed(t, [(0, ready), (0.20, crouch), (0.48, launch), (1, flying)])
    if kind == "land":
        return keyed(t, [(0, flying), (0.22, crouch), (1, ready)])
    return blend_pose(flying, hands(body_pose(0.91, 5), (0.44, 1.42, -0.20), (-0.44, 1.42, -0.20)), 0.08 * (1 - math.cos(TAU * t)))


def root_motion(pose, position, yaw=0):
    pose["Root"] = (position, euler(y=yaw))
    return pose


def obstacle(t, kind):
    high = kind.endswith("high")
    mantle = kind.startswith("mantle") or kind == "climb_top_out"
    height = (1.40 if high else 0.75) if mantle else (1.05 if high else 0.65)
    ready = body_pose()
    contact = hands(body_pose(0.76, -15, torso=-8), (0.24, height, -0.48), (-0.24, height, -0.48))
    tucked = hands(body_pose(0.70, -28, torso=-10), (0.25, 0.91, -0.29), (-0.25, 0.91, -0.29))
    solve_limb(tucked, "Left", False, (0.13, 0.56, -0.25))
    solve_limb(tucked, "Right", False, (-0.13, 0.44, 0.30 if not mantle else -0.12))
    finish = body_pose(0.76, -8)
    pose = keyed(t, [(0, ready), (0.22, contact), (0.52, tucked), (0.80, finish), (1, ready)])
    if mantle:
        # Lift the full upright capsule before entering the obstacle face.
        rise = height * smooth(t / 0.42)
        forward = -0.95 * smooth((t - 0.30) / 0.70)
    else:
        # Keep the capsule above the roof until its rear clears the far edge.
        rise = (height + 0.25) * smooth(t / 0.25) * (1 - smooth((t - 0.83) / 0.17))
        forward = -(1.65 if high else 1.35) * smooth(t / 0.80)
    return root_motion(pose, (0, rise, forward))


def transition(t, kind):
    if kind.startswith("corner"):
        left = kind.endswith("left")
        inner = "inner" in kind
        direction = 1 if left else -1
        pose = hang(t, "shimmy_left" if left else "shimmy_right")
        progress = smooth(t)
        if inner:
            # Approach a nearby inside face while the upright capsule turns.
            return root_motion(pose, (direction * 0.08 * progress, 0, 0), -direction * 90 * progress)
        # Clear the edge, round it at the capsule radius plus skin, then settle
        # far enough along the new face to support all four contacts.
        angle = smooth((t - 0.30) / 0.40) * math.pi / 2
        lateral = 0.35 * smooth(t / 0.30) + 0.42 * math.sin(angle)
        forward = 0.42 * (math.cos(angle) - 1) - 0.42 * smooth((t - 0.70) / 0.30)
        return root_motion(pose, (direction * lateral, 0, forward), direction * 90 * smooth((t - 0.30) / 0.40))
    if kind.startswith("ledge_jump"):
        destination = {"up": (0, 0.65, 0), "left": (0.90, 0, 0), "right": (-0.90, 0, 0), "forward": (0, 0, -1.20)}[kind.removeprefix("ledge_jump_")]
        flying = airborne(0.5, "fall")
        pose = keyed(t, [(0, hang()), (0.18, hang(0.2, "climb_up")), (0.43, flying), (0.78, flying), (1, hang())])
        progress = smooth(t)
        if kind == "ledge_jump_forward":
            # Lift from a ledge before crossing its solid face; settle outside
            # the destination face. Terminal translation remains 1.20 m.
            rise = 1.80 * smooth(t / 0.25) * (1 - smooth((t - 0.80) / 0.20))
            return root_motion(pose, (0, rise, -1.20 * smooth((t - 0.30) / 0.70)))
        return root_motion(pose, add(mul(destination, progress), (0, 0.24 * math.sin(math.pi * progress), 0)))
    if kind == "ledge_catch":
        return keyed(t, [(0, airborne(0, "fall")), (0.35, hang(0.25)), (0.62, hang(0.5)), (1, hang())])
    if kind == "ledge_drop":
        pose = keyed(t, [(0, hang()), (0.30, hang(0.4)), (0.60, airborne(0, "fall")), (1, airborne(0.3, "fall"))])
        return root_motion(pose, (0, -0.70 * smooth((t - 0.25) / 0.75), 0.20 * smooth(t)))
    # Grounded approach, reach, settle into a hanging pose.
    pose = keyed(t, [(0, body_pose()), (0.23, body_pose(0.69, -10)), (0.56, hang(0.3)), (1, hang())])
    return root_motion(pose, (0, 0.30 * smooth(t), -0.40 * smooth(t)))


def recovery(t, face_down):
    floor = body_pose()
    floor["Hips"] = ((0, 0.17, 0), euler(x=-90 if face_down else 90))
    floor["Head"] = (LOCAL["Head"], IDENTITY)
    for side, sign in (("Left", 1), ("Right", -1)):
        floor[side + "UpperLeg"] = (LOCAL[side + "UpperLeg"], IDENTITY)
        floor[side + "LowerLeg"] = (LOCAL[side + "LowerLeg"], IDENTITY)
        floor[side + "Foot"] = (LOCAL[side + "Foot"], IDENTITY)
        solve_limb(floor, side, True, (sign * 0.37, 0.12, -0.25 if face_down else 0.26))
    support = hands(body_pose(0.40, -48 if face_down else 38, torso=10 if face_down else -32), (0.30, 0.13, -0.30 if face_down else 0.30), (-0.30, 0.13, -0.30 if face_down else 0.30))
    kneel = hands(body_pose(0.55, -20, torso=-8), (0.30, 0.18, -0.25), (-0.29, 0.65, -0.22))
    solve_limb(kneel, "Left", False, (0.12, 0.09, -0.22))
    solve_limb(kneel, "Right", False, (-0.12, 0.09, 0.35))
    keys = [(0, floor), (0.16, floor), (0.43, support), (0.65, kneel), (0.85, body_pose(0.72, -9)), (1, body_pose())]
    return floor_safe_legs(t, keys, keyed(t, keys), 0.16, 0.85)


RECOVERY_ANKLE_CLEARANCE = 0.09
RECOVERY_TOE_CLEARANCE = 0.02
RECOVERY_KNEE_CLEARANCE = 0.06


def slerp(a, b, weight):
    if dot(a, b) < 0:
        b = mul(b, -1)
    return unit(add(mul(a, 1 - weight), mul(b, weight)))


def _leg_plan(t, keys, pose, side):
    """World ankle, foot rotation and bend pole interpolated between the keys at t."""
    for (at, a), (bt, b) in zip(keys, keys[1:]):
        if at <= t <= bt and bt > at:
            break
    weight = smooth((t - at) / (bt - at))
    ankle_a, foot_qa = global_pose(a, side + "Foot")
    ankle_b, foot_qb = global_pose(b, side + "Foot")
    foot_q = slerp(foot_qa, foot_qb, weight)
    ankle = add(mul(ankle_a, 1 - weight), mul(ankle_b, weight))
    toes_drop = rotate(foot_q, LOCAL[side + "Toes"])[1]
    floor_y = max(RECOVERY_ANKLE_CLEARANCE, RECOVERY_TOE_CLEARANCE - toes_drop)
    ankle = (ankle[0], max(ankle[1], floor_y), ankle[2])
    poles = []
    for key in (a, b):
        hip = global_pose(key, side + "UpperLeg")[0]
        knee = global_pose(key, side + "LowerLeg")[0]
        foot = global_pose(key, side + "Foot")[0]
        # Bend direction is the knee offset perpendicular to hip-to-ankle.
        axis = unit(sub(foot, hip))
        offset = sub(knee, hip)
        bend = sub(offset, mul(axis, dot(offset, axis)))
        poles.append(unit(bend) if dot(bend, bend) > 1e-4 else None)
    # A straight leg has no bend of its own; it adopts its neighbour's.
    poles = [p or poles[1 - i] or (0, 1, 0) for i, p in enumerate(poles)]
    pole = unit(add(mul(poles[0], 1 - weight), mul(poles[1], weight)))
    hip = global_pose(pose, side + "UpperLeg")[0]
    axis = unit(sub(ankle, hip))
    outward = (1 if side == "Left" else -1, 0, 0)

    def turned(degrees):
        half = math.radians(degrees) / 2
        return rotate((*mul(axis, math.sin(half)), math.cos(half)), pole)

    # Knees splay outward (anatomical left is +X) and never flip sides.
    sign = 1 if dot(turned(1), outward) >= dot(turned(-1), outward) else -1
    return ankle, foot_q, lambda degrees: turned(sign * degrees)


def _knee_turn_needed(t, keys, side):
    """Smallest outward bend-plane turn (degrees) keeping the knee off the floor."""
    pose = keyed(t, keys)
    ankle, foot_q, turned = _leg_plan(t, keys, pose, side)
    for degrees in range(0, 181):
        solve_limb(pose, side, False, ankle, turned(degrees), foot_q)
        if global_pose(pose, side + "LowerLeg")[0][1] >= RECOVERY_KNEE_CLEARANCE:
            return degrees
    return 180


RECOVERY_TURN_WINDOW = 0.03
RECOVERY_TURN_TAPS = 8


def floor_safe_legs(t, keys, pose, start, end):
    """Between start and end, legs follow interpolated world-space ankle, knee-pole
    and foot targets instead of slerped joint rotations, which swing feet through
    the floor while the pelvis rotates. Any knee correction is tapered over a
    short window so it eases in and out. Boundary key poses are reproduced."""
    if not start < t < end:
        return pose
    for side in ("Left", "Right"):
        turn = 0.0
        for tap in range(-RECOVERY_TURN_TAPS, RECOVERY_TURN_TAPS + 1):
            at = t + RECOVERY_TURN_WINDOW * tap / RECOVERY_TURN_TAPS
            if start < at < end:
                turn = max(turn, _knee_turn_needed(at, keys, side) * (1 - abs(tap) / RECOVERY_TURN_TAPS))
        ankle, foot_q, turned = _leg_plan(t, keys, pose, side)
        solve_limb(pose, side, False, ankle, turned(turn), foot_q)
    return pose
    for (at, a), (bt, b) in zip(keys, keys[1:]):
        if at <= t <= bt and bt > at:
            break
    weight = smooth((t - at) / (bt - at))
    for side in ("Left", "Right"):
        ankle_a, foot_qa = global_pose(a, side + "Foot")
        ankle_b, foot_qb = global_pose(b, side + "Foot")
        foot_q = slerp(foot_qa, foot_qb, weight)
        ankle = add(mul(ankle_a, 1 - weight), mul(ankle_b, weight))
        toes_drop = rotate(foot_q, LOCAL[side + "Toes"])[1]
        floor_y = max(RECOVERY_ANKLE_CLEARANCE, RECOVERY_TOE_CLEARANCE - toes_drop)
        ankle = (ankle[0], max(ankle[1], floor_y), ankle[2])
        poles = []
        for key in (a, b):
            hip = global_pose(key, side + "UpperLeg")[0]
            knee = global_pose(key, side + "LowerLeg")[0]
            foot = global_pose(key, side + "Foot")[0]
            # Bend direction is the knee offset perpendicular to hip-to-ankle.
            axis = unit(sub(foot, hip))
            offset = sub(knee, hip)
            bend = sub(offset, mul(axis, dot(offset, axis)))
            poles.append(unit(bend) if dot(bend, bend) > 1e-4 else None)
        # A straight leg has no bend of its own; it adopts its neighbour's.
        poles = [p or poles[1 - i] or (0, 1, 0) for i, p in enumerate(poles)]
        pole = unit(add(mul(poles[0], 1 - weight), mul(poles[1], weight)))
        solve_limb(pose, side, False, ankle, pole, foot_q)
        if global_pose(pose, side + "LowerLeg")[0][1] >= RECOVERY_KNEE_CLEARANCE:
            continue
        # Turn the bend plane about hip-to-ankle by the smallest angle that keeps
        # the knee off the floor, so the correction fades in continuously.
        # Knees always splay outward (anatomical left is +X), never flipping sides.
        hip = global_pose(pose, side + "UpperLeg")[0]
        axis = unit(sub(ankle, hip))
        outward = (1 if side == "Left" else -1, 0, 0)

        def turned(degrees):
            half = math.radians(degrees) / 2
            return rotate((*mul(axis, math.sin(half)), math.cos(half)), pole)

        sign = 1 if dot(turned(1), outward) >= dot(turned(-1), outward) else -1
        for degrees in range(1, 181):
            solve_limb(pose, side, False, ankle, turned(sign * degrees), foot_q)
            if global_pose(pose, side + "LowerLeg")[0][1] >= RECOVERY_KNEE_CLEARANCE:
                break
    return pose


CLIPS = [
    ("idle", 2.4, True), ("walk", 0.8, True), ("run", 0.62, True), ("sprint", 0.46, True),
    ("jump", 0.55, False), ("fall", 1.0, True), ("land", 0.42, False),
    ("vault_low", 0.9, False), ("vault_high", 1.15, False),
    ("mantle_low", 1.3, False), ("mantle_high", 1.8, False),
    ("climb_enter", 1.0, False), ("hang_idle", 2.0, True),
    ("shimmy_left", 1.0, True), ("shimmy_right", 1.0, True),
    ("climb_up", 1.2, True), ("climb_down", 1.2, True),
    ("corner_inner_left", 1.0, False), ("corner_inner_right", 1.0, False),
    ("corner_outer_left", 1.2, False), ("corner_outer_right", 1.2, False),
    ("ledge_jump_up", 0.9, False), ("ledge_jump_left", 0.95, False),
    ("ledge_jump_right", 0.95, False), ("ledge_jump_forward", 1.1, False),
    ("ledge_catch", 0.65, False), ("ledge_drop", 0.6, False),
    ("climb_top_out", 1.65, False), ("get_up_front", 2.2, False), ("get_up_back", 2.5, False),
]


def sample(name, t):
    if name == "idle":
        pose = body_pose(0.92 - 0.004 * (1 - math.cos(TAU * t)))
        pose["Chest"] = (LOCAL["Chest"], euler(x=0.8 * math.sin(TAU * t)))
        return pose
    if name in ("walk", "run", "sprint"):
        speed, duration, stance, lean = {"walk": (2.2, 0.8, 0.5, -3), "run": (5.0, 0.62, 0.35, -9), "sprint": (7.5, 0.46, 0.32, -16)}[name]
        return gait(t, speed, duration, stance, lean)
    if name in ("jump", "fall", "land"):
        return airborne(t, name)
    if name.startswith(("vault_", "mantle_")):
        return obstacle(t, name)
    if name == "climb_top_out":
        # Same obstacle convention as a high mantle, but starts hanging.
        pose = blend_pose(hang(), obstacle(t, "mantle_high"), smooth(t / 0.35))
        # Blend limb poses, but retain the capsule-safe high-mantle Root curve.
        pose["Root"] = obstacle(t, "mantle_high")["Root"]
        return pose
    if name in ("hang_idle", "shimmy_left", "shimmy_right", "climb_up", "climb_down"):
        return hang(t, name)
    if name in ("get_up_front", "get_up_back"):
        return recovery(t, name == "get_up_front")
    return transition(t, name)


class Geometry:
    def __init__(self):
        self.parts = [dict(position=[], normal=[], joints=[], weights=[], indices=[]) for _ in range(3)]

    def triangle(self, points, bone, material=0, weights=None):
        part = self.parts[material]
        normal = unit(cross(sub(points[1], points[0]), sub(points[2], points[0])))
        if dot(normal, normal) < 0.5:
            return
        for point in points:
            part["indices"].append(len(part["position"]))
            part["position"].append(point)
            part["normal"].append(normal)
            influence = weights(point) if weights else [(bone, 1.0)]
            part["joints"].append(tuple([INDEX[b] for b, _ in influence] + [0] * (4 - len(influence))))
            part["weights"].append(tuple([w for _, w in influence] + [0] * (4 - len(influence))))

    def ellipsoid(self, center, radii, bone, material=0, weights=None, segments=12, rings=8):
        def point(i, j):
            theta, phi = math.pi * i / rings, TAU * j / segments
            return add(center, (radii[0] * math.sin(theta) * math.cos(phi), radii[1] * math.cos(theta), radii[2] * math.sin(theta) * math.sin(phi)))
        for i in range(rings):
            for j in range(segments):
                a, b, c, d = point(i, j), point(i + 1, j), point(i + 1, j + 1), point(i, j + 1)
                self.triangle((a, d, b), bone, material, weights)
                self.triangle((d, c, b), bone, material, weights)

    def limb(self, a, b, r1, r2, bone, material=0):
        axis = unit(sub(b, a))
        u = unit(cross(axis, (0, 0, 1)))
        v = cross(axis, u)
        ring1, ring2 = [], []
        for j in range(8):
            radial = add(mul(u, math.cos(TAU * j / 8)), mul(v, math.sin(TAU * j / 8)))
            ring1.append(add(a, mul(radial, r1)))
            ring2.append(add(b, mul(radial, r2)))
        for j in range(8):
            k = (j + 1) % 8
            self.triangle((ring1[j], ring1[k], ring2[j]), bone, material)
            self.triangle((ring1[k], ring2[k], ring2[j]), bone, material)
            self.triangle((a, ring1[k], ring1[j]), bone, material)
            self.triangle((b, ring2[j], ring2[k]), bone, material)


def make_geometry():
    mesh = Geometry()

    def torso_weights(point):
        anchors = [("Hips", 0.95), ("Spine", 1.10), ("Chest", 1.25), ("UpperChest", 1.40)]
        for (a, ay), (b, by) in zip(anchors, anchors[1:]):
            if point[1] <= by:
                w = max(0, min(1, (point[1] - ay) / (by - ay)))
                return [(a, 1 - w), (b, w)]
        return [("UpperChest", 1)]

    mesh.ellipsoid((0, 1.19, 0), (0.225, 0.29, 0.135), "Chest", weights=torso_weights)
    mesh.ellipsoid((0, 0.94, 0), (0.175, 0.13, 0.13), "Hips", material=1)
    mesh.limb(REST["Neck"], REST["Head"], 0.058, 0.065, "Neck", 1)
    mesh.ellipsoid((0, 1.68, 0), (0.115, 0.12, 0.105), "Head")
    mesh.ellipsoid((0, 1.70, -0.093), (0.089, 0.034, 0.025), "Head", 1)
    mesh.ellipsoid((0, 1.32, -0.127), (0.065, 0.06, 0.016), "UpperChest", 2)
    for side, sign in (("Left", 1), ("Right", -1)):
        for start, end, radius1, radius2 in (("UpperArm", "LowerArm", 0.080, 0.058), ("LowerArm", "Hand", 0.058, 0.038), ("UpperLeg", "LowerLeg", 0.094, 0.068), ("LowerLeg", "Foot", 0.065, 0.040)):
            mesh.limb(REST[side + start], REST[side + end], radius1, radius2, side + start)
        for joint, radius in (("UpperArm", 0.081), ("LowerArm", 0.060), ("Hand", 0.04), ("LowerLeg", 0.065), ("Foot", 0.044)):
            mesh.ellipsoid(REST[side + joint], (radius,) * 3, side + joint, 1, segments=8, rings=6)
        mesh.ellipsoid((sign * 0.815, 1.43, 0), (0.082, 0.043, 0.054), side + "Hand", 1)
        mesh.ellipsoid((sign * 0.105, 0.065, -0.035), (0.066, 0.065, 0.135), side + "Foot", 1)
        mesh.ellipsoid((sign * 0.105, 0.046, -0.15), (0.065, 0.045, 0.060), side + "Toes", 1)
    return mesh


class GLB:
    def __init__(self):
        self.binary = bytearray()
        self.doc = {"asset": {"version": "2.0", "generator": "Liberty original mannequin generator", "copyright": "Original procedural asset; use under this project's license."}, "scene": 0, "scenes": [{"name": "LibertyMannequin", "nodes": [0, 23]}], "nodes": [], "meshes": [], "skins": [], "materials": [], "animations": [], "accessors": [], "bufferViews": []}

    def accessor(self, rows, kind, component=5126, target=None, bounds=False):
        self.binary.extend(b"\0" * (-len(self.binary) % 4))
        start = len(self.binary)
        code = {5126: "f", 5123: "H", 5125: "I"}[component]
        for row in rows:
            self.binary.extend(struct.pack("<" + code * len(row), *row))
        view = {"buffer": 0, "byteOffset": start, "byteLength": len(self.binary) - start}
        if target:
            view["target"] = target
        self.doc["bufferViews"].append(view)
        entry = {"bufferView": len(self.doc["bufferViews"]) - 1, "componentType": component, "count": len(rows), "type": kind}
        if bounds:
            entry["min"] = [min(r[i] for r in rows) for i in range(len(rows[0]))]
            entry["max"] = [max(r[i] for r in rows) for i in range(len(rows[0]))]
        self.doc["accessors"].append(entry)
        return len(self.doc["accessors"]) - 1

    def write(self, path):
        self.doc["buffers"] = [{"byteLength": len(self.binary)}]
        encoded = json.dumps(self.doc, separators=(",", ":"), allow_nan=False).encode()
        encoded += b" " * (-len(encoded) % 4)
        self.binary.extend(b"\0" * (-len(self.binary) % 4))
        header = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(encoded) + 8 + len(self.binary))
        path.write_bytes(header + struct.pack("<II", len(encoded), 0x4E4F534A) + encoded + struct.pack("<II", len(self.binary), 0x004E4942) + self.binary)


def generate(destination):
    glb = GLB()
    for name, parent, _ in BONES:
        node = {"name": name, "translation": LOCAL[name]}
        children = [INDEX[n] for n, p, _ in BONES if p == name]
        if children:
            node["children"] = children
        glb.doc["nodes"].append(node)
    glb.doc["nodes"].append({"name": "MannequinMesh", "mesh": 0, "skin": 0})
    matrices = [(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -p[0], -p[1], -p[2], 1) for _, _, p in BONES]
    glb.doc["skins"].append({"name": "LibertyHumanoid", "skeleton": 0, "joints": list(range(23)), "inverseBindMatrices": glb.accessor(matrices, "MAT4")})
    for name, color in (("Shell", [0.08, 0.42, 0.46, 1]), ("JointsAndVisor", [0.035, 0.055, 0.075, 1]), ("Badge", [1.0, 0.38, 0.075, 1])):
        glb.doc["materials"].append({"name": name, "pbrMetallicRoughness": {"baseColorFactor": color, "metallicFactor": 0.12, "roughnessFactor": 0.65}})
    primitives = []
    for material, part in enumerate(make_geometry().parts):
        attributes = {"POSITION": glb.accessor(part["position"], "VEC3", target=34962, bounds=True), "NORMAL": glb.accessor(part["normal"], "VEC3", target=34962), "JOINTS_0": glb.accessor(part["joints"], "VEC4", 5123, 34962), "WEIGHTS_0": glb.accessor(part["weights"], "VEC4", target=34962)}
        primitives.append({"attributes": attributes, "indices": glb.accessor([(i,) for i in part["indices"]], "SCALAR", 5125, 34963), "material": material})
    glb.doc["meshes"].append({"name": "LibertyMannequinSkin", "primitives": primitives})
    manifest = {"asset": "liberty_mannequin.glb", "units": "meters", "forward": "-Z", "root_bone": "Root", "sample_rate": 30, "bones": [n for n, _, _ in BONES], "clips": {}}
    for name, duration, loop in CLIPS:
        # Thirty Hz is sufficient for action poses. Fast gait IK needs denser
        # samples: quaternion interpolation at 30 Hz otherwise sinks stance feet
        # between correctly planted samples. Retain the exact loop endpoint.
        rate = 120 if name in ("walk", "run", "sprint") else 30
        count = math.ceil(duration * rate)
        poses = [sample(name, i / count) for i in range(count + 1)]
        if loop:
            poses[-1] = poses[0]
        extras = {"loop": loop, "duration": duration, "sample_rate": rate, "root_displacement": list(poses[-1]["Root"][0]), "root_yaw_degrees": 0.0}
        if name in ("walk", "run", "sprint"):
            extras["authored_speed"] = {"walk": 2.2, "run": 5.0, "sprint": 7.5}[name]
        if name.startswith("corner"):
            q = poses[-1]["Root"][1]
            extras["root_yaw_degrees"] = math.degrees(2 * math.atan2(q[1], q[3]))
        if name.startswith(("vault_", "mantle_")) or name == "climb_top_out":
            mantle = name.startswith("mantle") or name == "climb_top_out"
            high = name.endswith("high") or name == "climb_top_out"
            extras["reference_obstacle"] = {"height": (1.4 if high else 0.75) if mantle else (1.05 if high else 0.65), "depth": 0.4 if not mantle else 0.95}
        animation = {"name": name, "extras": extras, "samplers": [], "channels": []}
        time_index = glb.accessor([(duration * i / count,) for i in range(count + 1)], "SCALAR", bounds=True)
        for bone, _, _ in BONES:
            for path, element in (("translation", 0), ("rotation", 1)):
                rows = [p[bone][element] for p in poses]
                if path == "rotation":
                    for i in range(1, len(rows)):
                        if dot(rows[i - 1], rows[i]) < 0:
                            rows[i] = mul(rows[i], -1)
                value_index = glb.accessor(rows, "VEC3" if element == 0 else "VEC4")
                animation["channels"].append({"sampler": len(animation["samplers"]), "target": {"node": INDEX[bone], "path": path}})
                animation["samplers"].append({"input": time_index, "output": value_index, "interpolation": "LINEAR"})
        glb.doc["animations"].append(animation)
        manifest["clips"][name] = extras
    destination.mkdir(parents=True, exist_ok=True)
    glb.write(destination / "liberty_mannequin.glb")
    (destination / "animation_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Generated {destination / 'liberty_mannequin.glb'}: 23 bones, {len(CLIPS)} clips")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=DESTINATION)
    generate(parser.parse_args().output_dir)

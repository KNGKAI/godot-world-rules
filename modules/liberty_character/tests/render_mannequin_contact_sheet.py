"""Offline visual inspection of the exported GLB (no display/dependencies).

Usage: python3 modules/liberty_character/tests/render_mannequin_contact_sheet.py
Writes numbered PNG sheets to /tmp, five poses per clip. This software skinning
renderer is a diagnostic, not a replacement for viewing the Godot scene.
"""
import argparse
import importlib.util
import math
from pathlib import Path
import struct
import zlib

from test_mannequin_export import ASSET, ROOT, accessor, read_glb

spec = importlib.util.spec_from_file_location("mannequin", ROOT / "addons/liberty_character_editor/generate_mannequin.py")
rig = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rig)

FONT = dict(zip("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.", [
    "01110100011000111111100011000110001", "11110100011000111110100011000111110", "01111100001000010000100001000001111", "11110100011000110001100011000111110", "11111100001000011110100001000011111", "11111100001000011110100001000010000", "01111100001000010111100011000101111", "10001100011000111111100011000110001", "11111001000010000100001000010011111", "00111000100001000010000101001001100", "10001100101010011000101001001010001", "10000100001000010000100001000011111", "10001110111010110101100011000110001", "10001110011010110011100011000110001", "01110100011000110001100011000101110", "11110100011000111110100001000010000", "01110100011000110001101011001001101", "11110100011000111110101001001010001", "01111100001000001110000010000111110", "11111001000010000100001000010000100", "10001100011000110001100011000101110", "10001100011000110001100010101000100", "10001100011000110101101011101110001", "10001100010101000100010101000110001", "10001100010101000100001000010000100", "11111000010001000100010001000011111", "01110100011001110101110011000101110", "00100011000010000100001000010001110", "01110100010000100010001000100011111", "11110000010000101110000010000111110", "00010001100101010010111110001000010", "11111100001000011110000010000111110", "01110100001000011110100011000101110", "11111000010001000100010000100001000", "01110100011000101110100011000101110", "01110100011000101111000010000101110", "00000000000000000000000000000011111", "00000000000000011111000000000000000", "00000000000000000000000000010000100",
]))


def text(pixels, width, x, y, label):
    for char in label.upper():
        glyph = FONT.get(char, "0" * 35)
        for row in range(7):
            for col in range(5):
                if glyph[row * 5 + col] == "1":
                    index = ((y + row) * width + x + col) * 3
                    pixels[index:index + 3] = bytes((205, 220, 230))
        x += 6


def pose_for(doc, binary, animation, t):
    local = {i: (tuple(n.get("translation", (0, 0, 0))), tuple(n.get("rotation", (0, 0, 0, 1)))) for i, n in enumerate(doc["nodes"])}
    for channel in animation["channels"]:
        sampler = animation["samplers"][channel["sampler"]]
        times = accessor(doc, binary, sampler["input"])
        track = accessor(doc, binary, sampler["output"])
        seconds = t * times[-1][0]
        index = min(len(times) - 2, next((i for i in range(len(times) - 1) if times[i + 1][0] >= seconds), len(times) - 2))
        factor = (seconds - times[index][0]) / (times[index + 1][0] - times[index][0])
        a, b = track[index:index + 2]
        rotation = channel["target"]["path"] == "rotation"
        if rotation and rig.dot(a, b) < 0:
            b = rig.mul(b, -1)
        value = rig.add(rig.mul(a, 1 - factor), rig.mul(b, factor))
        if rotation:
            value = rig.unit(value)
        bone = channel["target"]["node"]
        p, q = local[bone]
        local[bone] = (p, value) if rotation else (value, q)
    parents = {child: i for i, n in enumerate(doc["nodes"]) for child in n.get("children", [])}
    world = {}

    def resolve(i):
        if i not in world:
            p, q = local[i]
            if i in parents:
                pp, pq = resolve(parents[i])
                p, q = rig.add(pp, rig.rotate(pq, p)), rig.qmul(pq, q)
            world[i] = p, q
        return world[i]

    for i in local:
        resolve(i)
    return world


def render_cell(doc, binary, animation, t, pixels, depths, width, x0, y0, cell_w=180, cell_h=220):
    world = pose_for(doc, binary, animation, t)
    root_p, root_q = world[0]
    camera_yaw = 0.45
    camera = rig.euler(y=math.degrees(camera_yaw))
    palette = ((36, 161, 166), (30, 43, 59), (255, 125, 38))
    light = rig.unit((-0.4, 0.8, -0.7))
    for primitive in doc["meshes"][0]["primitives"]:
        attrs = primitive["attributes"]
        positions = accessor(doc, binary, attrs["POSITION"])
        joints = accessor(doc, binary, attrs["JOINTS_0"])
        weights = accessor(doc, binary, attrs["WEIGHTS_0"])
        transformed = []
        for p, joint, weight in zip(positions, joints, weights):
            v = (0, 0, 0)
            for bone, w in zip(joint, weight):
                if w:
                    name = doc["nodes"][bone]["name"]
                    wp, wq = world[bone]
                    v = rig.add(v, rig.mul(rig.add(wp, rig.rotate(wq, rig.sub(p, rig.REST[name]))), w))
            v = rig.rotate(rig.inverse(root_q), rig.sub(v, root_p))
            transformed.append(rig.rotate(camera, v))
        indices = [i[0] for i in accessor(doc, binary, primitive["indices"])]
        for i in range(0, len(indices), 3):
            a, b, c = (transformed[j] for j in indices[i:i + 3])
            normal = rig.unit(rig.cross(rig.sub(b, a), rig.sub(c, a)))
            # View from -Z; one-sided culling also exposes incorrect winding.
            if normal[2] > 0:
                continue
            intensity = 0.40 + 0.60 * max(0, rig.dot(normal, light))
            color = bytes(int(v * intensity) for v in palette[primitive["material"]])
            points = [(x0 + cell_w / 2 + v[0] * 88, y0 + cell_h - 18 - v[1] * 88, v[2]) for v in (a, b, c)]
            pa, pb, pc = points
            denominator = (pb[1] - pc[1]) * (pa[0] - pc[0]) + (pc[0] - pb[0]) * (pa[1] - pc[1])
            if abs(denominator) < 1e-8:
                continue
            xmin = max(x0, int(min(v[0] for v in points)))
            xmax = min(x0 + cell_w - 1, math.ceil(max(v[0] for v in points)))
            ymin = max(y0 + 12, int(min(v[1] for v in points)))
            ymax = min(y0 + cell_h - 1, math.ceil(max(v[1] for v in points)))
            for y in range(ymin, ymax + 1):
                for x in range(xmin, xmax + 1):
                    u = ((pb[1] - pc[1]) * (x - pc[0]) + (pc[0] - pb[0]) * (y - pc[1])) / denominator
                    v = ((pc[1] - pa[1]) * (x - pc[0]) + (pa[0] - pc[0]) * (y - pc[1])) / denominator
                    w = 1 - u - v
                    if min(u, v, w) < 0:
                        continue
                    depth = u * pa[2] + v * pb[2] + w * pc[2]
                    at = y * width + x
                    if depth < depths[at]:
                        depths[at] = depth
                        pixels[at * 3:at * 3 + 3] = color


def png(path, width, height, pixels):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    raw = b"".join(b"\0" + pixels[y * width * 3:(y + 1) * width * 3] for y in range(height))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--page", type=int, choices=(1, 2, 3), help="render only one ten-clip sheet")
    page_choice = parser.parse_args().page
    doc, binary = read_glb(ASSET)
    for page in ([page_choice - 1] if page_choice else range(3)):
        width, height = 900, 2200
        pixels = bytearray(bytes((15, 23, 33)) * width * height)
        depths = [math.inf] * width * height
        for row, animation in enumerate(doc["animations"][page * 10:page * 10 + 10]):
            for column, t in enumerate((0, 0.25, 0.5, 0.75, 1)):
                render_cell(doc, binary, animation, t, pixels, depths, width, column * 180, row * 220)
                text(pixels, width, column * 180 + 4, row * 220 + 3, animation["name"])
                text(pixels, width, column * 180 + 4, row * 220 + 13, str(int(t * 100)))
        path = Path(f"/tmp/liberty_mannequin_poses_{page + 1}.png")
        png(path, width, height, pixels)
        print(path, flush=True)

"""Portable asset contract: catches missing clips, bad skinning and loop seams."""
import json
import math
from pathlib import Path
import struct
import unittest

ROOT = Path(__file__).resolve().parents[3]
ASSET = ROOT / "assets/characters/liberty_mannequin/liberty_mannequin.glb"
CLIPS = set("idle walk run sprint jump fall land vault_low vault_high mantle_low mantle_high climb_enter hang_idle shimmy_left shimmy_right climb_up climb_down corner_inner_left corner_inner_right corner_outer_left corner_outer_right ledge_jump_up ledge_jump_left ledge_jump_right ledge_jump_forward ledge_catch ledge_drop climb_top_out get_up_front get_up_back".split())
LOOPS = set("idle walk run sprint fall hang_idle shimmy_left shimmy_right climb_up climb_down".split())


def read_glb(path):
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data)
    assert (magic, version, length) == (b"glTF", 2, len(data))
    size, kind = struct.unpack_from("<II", data, 12)
    assert kind == 0x4E4F534A
    doc = json.loads(data[20:20 + size])
    offset = 20 + size
    size, kind = struct.unpack_from("<II", data, offset)
    assert kind == 0x004E4942
    return doc, data[offset + 8:offset + 8 + size]


def accessor(doc, binary, index):
    entry = doc["accessors"][index]
    view = doc["bufferViews"][entry["bufferView"]]
    code = {5126: "f", 5123: "H", 5125: "I"}[entry["componentType"]]
    width = {"SCALAR": 1, "VEC3": 3, "VEC4": 4, "MAT4": 16}[entry["type"]]
    offset = view.get("byteOffset", 0) + entry.get("byteOffset", 0)
    stride = view.get("byteStride", struct.calcsize("<" + code * width))
    return [struct.unpack_from("<" + code * width, binary, offset + stride * i) for i in range(entry["count"])]


class MannequinExportTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(ASSET.is_file(), "Generate the standalone mannequin GLB first")
        self.doc, self.binary = read_glb(ASSET)

    def test_all_required_clips_have_real_finite_motion(self):
        self.assertEqual({a["name"] for a in self.doc["animations"]}, CLIPS)
        signatures = set()
        for animation in self.doc["animations"]:
            with self.subTest(clip=animation["name"]):
                values = []
                moving = 0
                for sampler in animation["samplers"]:
                    times = accessor(self.doc, self.binary, sampler["input"])
                    self.assertEqual(times[0], (0.0,))
                    self.assertGreater(times[-1][0], 0)
                    self.assertTrue(all(a[0] < b[0] for a, b in zip(times, times[1:])))
                    track = accessor(self.doc, self.binary, sampler["output"])
                    self.assertEqual(len(times), len(track))
                    self.assertTrue(all(math.isfinite(v) for row in track for v in row))
                    moving += any(sum((a - b) ** 2 for a, b in zip(row, track[0])) > 1e-8 for row in track)
                    values.append(tuple(track))
                self.assertGreater(moving, 0, "clip must animate, not just hold the rest pose")
                signatures.add(tuple(values))
        self.assertEqual(len(signatures), 30, "unrelated clips must not be duplicates")

    def test_skin_and_bind_matrices_are_valid(self):
        skin = self.doc["skins"][0]
        self.assertEqual(len(skin["joints"]), 23)
        matrices = accessor(self.doc, self.binary, skin["inverseBindMatrices"])
        self.assertEqual(len(matrices), 23)
        for primitive in self.doc["meshes"][0]["primitives"]:
            attributes = primitive["attributes"]
            joints = accessor(self.doc, self.binary, attributes["JOINTS_0"])
            weights = accessor(self.doc, self.binary, attributes["WEIGHTS_0"])
            positions = accessor(self.doc, self.binary, attributes["POSITION"])
            self.assertEqual(len(joints), len(positions))
            self.assertEqual(len(weights), len(positions))
            for joint, weight in zip(joints, weights):
                self.assertTrue(all(0 <= j < 23 for j in joint))
                self.assertAlmostEqual(sum(weight), 1, places=5)
                self.assertTrue(all(w >= 0 for w in weight))
        names = {self.doc["nodes"][j]["name"] for j in skin["joints"]}
        self.assertTrue({"Root", "Hips", "Head", "LeftHand", "RightHand", "LeftFoot", "RightFoot"} <= names)

    def test_loop_seams_and_root_motion_contract(self):
        root = next(i for i, n in enumerate(self.doc["nodes"]) if n["name"] == "Root")
        for animation in self.doc["animations"]:
            name = animation["name"]
            for channel in animation["channels"]:
                sampler = animation["samplers"][channel["sampler"]]
                track = accessor(self.doc, self.binary, sampler["output"])
                if name in LOOPS:
                    self.assertLess(max(abs(a - b) for a, b in zip(track[0], track[-1])), 1e-5, name)
                if channel["target"]["node"] == root and name in LOOPS | {"jump", "land", "get_up_front", "get_up_back"}:
                    if channel["target"]["path"] == "translation":
                        self.assertTrue(all(max(abs(v) for v in row) < 1e-6 for row in track), name)
            self.assertEqual(animation["extras"]["loop"], name in LOOPS)


if __name__ == "__main__":
    unittest.main()

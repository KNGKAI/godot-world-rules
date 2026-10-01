from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class ConsumerTest(unittest.TestCase):
    def test_consumer_dependencies_exist(self):
        for path in ('project.godot', 'addons/world_manager/plugin.cfg', 'addons/rule_engine/plugin.cfg', 'modules/liberty_character/character/liberty_character.tscn', 'modules/liberty_vehicle/vehicle/liberty_vehicle.tscn'):
            self.assertTrue((ROOT / path).is_file(), path)

if __name__ == '__main__':
    unittest.main()

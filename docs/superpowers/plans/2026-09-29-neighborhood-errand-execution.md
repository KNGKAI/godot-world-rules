# Neighborhood Errand execution record

The standalone Godot 4.7.1 project was assembled from the three local sibling libraries. The main errand, sedan access, home travel, and save/load integration are implemented in `example/`.

## Verification on 2026-09-29

- `python -m unittest example.tests.test_consumer` — passed (1 test).
- `godot --headless --path . --import --quit` — exited 0, no import or script errors.
- `godot --headless --path . --script res://example/tests/test_errand.gd` — exited 0.
- `godot --headless --path . --script res://example/tests/test_world.gd` — exited 0.
- `godot --headless --path . --script res://example/tests/test_flow.gd` — `EXAMPLE_FLOW_PASS`.
- `godot --headless --path . --script res://example/tests/test_vehicle.gd` — `EXAMPLE_VEHICLE_PASS`; locked interaction denied, unlocked mount succeeded, sedan moved under throttle.
- `godot --headless --path . --script res://example/tests/test_restore.gd` — `EXAMPLE_RESTART_PASS` in a separate Godot process.
- `godot --headless --path . --script res://example/tests/test_failure.gd` — `EXAMPLE_FAILURE_PASS`; the expected missing-slot diagnostic was emitted.
- `godot --headless --path . --script addons/rule_engine/tools/validate_rules.gd -- --book=res://example/rules/errand.tres` — 0 issues.
- `godot --headless --path . --quit-after 120` — exited 0.

No display server was available (`DISPLAY` and `WAYLAND_DISPLAY` empty), so visual traversal and HUD placement were not reviewed interactively. Run the README walkthrough in the editor for that acceptance check. This directory has no Git repository, so no implementation commits were created.

## Mobile delivery update

The neighborhood and home now register a `USE` button through Liberty's `LibertyMobileControls.add_custom_button()`. It shares the keyboard F interaction logic for pickup, delivery, and home travel. The touch test sends real `InputEventScreenTouch` presses to the button and verifies all four actions.

- `godot --headless --path . --script res://example/tests/test_mobile_delivery.gd` — `EXAMPLE_MOBILE_DELIVERY_PASS`.
- Godot import, flow, vehicle, restart, and rule validation checks were rerun after the update; all exited 0. The rule validator reported 0 issues.

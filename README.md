# Neighborhood Demo

A playable Godot 4.7.1 demo of Liberty Character, World Manager, and Rule Engine. One package delivery unlocks a sedan; driving that sedan into the amber bay finishes the tour. An optional home interior shows named world travel. The integration code stays in `example/`.

## Run

Open this directory in Godot 4.7.1 and press **F5**. The project uses Jolt Physics. The first import processes the Liberty mannequin GLB and may take a moment.

## Walkthrough

1. Walk to the **gold PACKAGE** marker near the start and press **F** to pick up the package.
2. Hold **E** while moving toward the low brown wall to vault it. The **green DELIVER** marker is beyond the wall; press **F** there to deliver.
3. Walk east to the blue sedan on the street. Press **Q** near its driver door to mount. Drive with **WASD** along the road, brake or reverse with **S**, use **Space** for the handbrake, **C** to switch camera, and **Q** to exit. Park in the **amber PARK** bay on the west side of the north lot.
4. Press **F5** or the **SAVE** touch button to save to slot `example_01`. Press **F9** or **LOAD** to restore. Delivery, sedan access, and a finished tour persist. The car's physical location resets to its scene default. The same controls are on the driving overlay and inside the home.
5. Optionally visit the **blue HOME** marker near the start and press **F** to enter the home. Inside, press **F** near the doorway marked **STREET** to return to the neighborhood's `home_return` entry.

On a touchscreen, use Liberty's joystick and **CLIMB** button for the route. Tap **USE** at the gold marker to pick up the package, at the green marker to deliver it, and at the blue marker or home doorway to travel. Liberty's **ENTER/EXIT** touch button handles the sedan. **SAVE** and **LOAD** sit with those buttons on foot, and along the top of the driving overlay while mounted. They call the same `example_01` slot as **F5** and **F9**.

The block is a short residential street: houses, a vault wall across the yard, and an open road north of that wall. The wall uses both the `world` and `interactable` collision layers, which lets Liberty detect it for traversal. The sedan driver seat has monitoring disabled until the unlock, so Liberty's normal interaction path cannot mount it early. A second authored rule accepts `sedan_parked` only after that unlock and asks the project to record the finished tour.

## Integration map

| Responsibility | Example file | Library API |
|---|---|---|
| Delivery unlock and parked-sedan tour | `example/rules/errand.tres` | Rule Engine `RERuleBook`, `RECompareCondition`, `REEmitEventAction` |
| Pickup, delivery, durable unlock and tour | `example/integration/errand_coordinator.gd` | `RERuleEngine.emit_event`, `World.state` |
| Sedan access, parking bay, and playable route | `example/integration/neighborhood.gd` | Liberty character adapter and sedan scene |
| Street, houses, and markers | `example/integration/neighborhood_block.gd` | Scene presentation around those integration points |
| Named worlds and entry placement | `example/integration/world_setup.gd` | `World.scenes`, `World.events.world_loaded` |
| Optional home | `example/integration/home.gd` | `World.travel_to` |
| Save/load controls | `example/integration/neighborhood.gd`, `home.gd`, `save_touch.gd` | `World.save_game`, `World.load_game`, terminal events |

`World.travel_to`, `save_game`, and `load_game` return acceptance immediately. Their completion/failure signals determine the outcome. Rule Engine blackboard is memory-only, so the unlock and the finished tour are written to World state. All three libraries stay independent; the example scripts provide the connection.

## Checks

```sh
python -m unittest example.tests.test_consumer
godot --headless --path . --import --quit
godot --headless --path . --script res://example/tests/test_errand.gd
godot --headless --path . --script res://example/tests/test_world.gd
godot --headless --path . --script res://example/tests/test_flow.gd
godot --headless --path . --script res://example/tests/test_vehicle.gd
godot --headless --path . --script res://example/tests/test_restore.gd
godot --headless --path . --script res://example/tests/test_failure.gd
godot --headless --path . --script res://example/tests/test_mobile_delivery.gd
godot --headless --path . --script res://example/tests/test_mobile_save.gd
godot --headless --path . --script res://example/tests/test_tour.gd
godot --headless --path . --script res://example/tests/test_vault.gd
godot --headless --path . --script addons/rule_engine/tools/validate_rules.gd -- --book=res://example/rules/errand.tres
```

The flow check saves to `example_test`. The user-facing controls use `example_01`.

## Copied library versions

This standalone project copies local sibling sources at these revisions:

- `../godot-liberty` — `230853a` plus its local, uncommitted change to `modules/liberty_character/character/liberty_character.gd`: character, vehicle, editor addon, and mannequin asset.
- `../godot-world` — `d7147c1`: `addons/world_manager/`.
- `../godot-rules` — `380cff7`: `addons/rule_engine/`.

The World Manager and Rule Engine MIT notices are in `licenses/`; Rule Engine's addon also includes its own notice. The Liberty source tree did not contain a license file at the copied revision; check its licensing before redistributing the copied module or mannequin outside this local example.

# Neighborhood Errand Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a compact Godot integration example where a package delivery unlocks a drivable sedan and an optional home doorway demonstrates world travel.

**Architecture:** Vendor the three sibling addons/modules into one standalone consumer project. Project-owned scripts translate interactions to rule events, rule outcomes to World state, and World state to scene presentation. The main loop lives in one neighborhood scene; a small home scene is a separate registered world.

**Tech Stack:** Godot 4.7.1, GDScript, Jolt Physics, Liberty Character and Vehicle, World Manager, Rule Engine.

**Spec:** `docs/superpowers/specs/2026-09-29-neighborhood-errand-design.md`

## Global Constraints

- Use the existing driver-only sedan and public Liberty interaction/possession path.
- Keep all library-to-library integration in example-owned code; do not alter the sibling libraries.
- Store delivery and unlock progress in World state; Rule Engine blackboard is memory-only.
- Treat `World.travel_to`, `save_game`, and `load_game` returning `OK` as acceptance; react to their terminal events.
- A home trip is optional and does not gate delivery or driving.
- This directory currently has no Git repository. Do not invent commit steps or initialize Git without deciding repository ownership at execution time.

## Review Focus

- Duplicate delivery: the unlock fires once and preserves existing progress (Task 3).
- Pre-unlock mount: the project rejects access through the normal interaction path (Task 4).
- Load after restart: delivery and unlock presentation are reconstructed from World state (Task 4).
- Failed home travel: door controls recover and allow another attempt (Task 2).
- Failed save/load: UI reports failure only after terminal event and gameplay remains usable (Task 5).

## File map

- `project.godot`, `addons/`, `modules/`, `assets/`: standalone Godot consumer and copied library runtime assets.
- `example/rules/`: authored rule book and rules.
- `example/integration/errand_coordinator.gd`: package, delivery, Rule Engine, and World state bridge.
- `example/integration/vehicle_gate.gd`: locked/unlocked sedan interaction.
- `example/integration/world_setup.gd`: world definitions and entry points.
- `example/integration/travel_door.gd`: optional home travel and terminal-event handling.
- `example/integration/save_panel.gd`: save/load controls and terminal feedback.
- `example/scenes/`: neighborhood and home scenes with focused interactables.
- `example/tests/`: focused integration checks; `README.md`: setup, controls, loop, and dependency map.

---

### Task 1: Standalone consumer boots

**Files:** Create `project.godot`, `README.md`, `addons/world_manager/`, `addons/rule_engine/`, `modules/liberty_character/`, `modules/liberty_vehicle/`, required `assets/characters/`, `example/scenes/neighborhood.tscn`.

**Interfaces:** Produces a Godot project with the World and Rules plugins enabled and a Liberty character in a minimal neighborhood. Copy only runtime/editor pieces needed for a valid consumer, preserving resource paths and `.uid` sidecars. Pin the exact sibling revisions in README.

- [ ] Create the consumer skeleton and copy the required library trees and character assets.
- [ ] Add project settings, input actions, collision layers, Jolt and plugin registration required by the copied modules.
- [ ] Run `godot --headless --path . --import --quit`; expect exit 0 and no script parse errors.
- [ ] Run `godot --headless --path . --quit-after 3`; expect exit 0 and an initialized `World`.

### Task 2: Register and travel between worlds

**Files:** Create `example/integration/world_setup.gd`, `example/integration/travel_door.gd`, `example/scenes/home.tscn`, `example/tests/test_travel.gd`; modify `example/scenes/neighborhood.tscn`.

**Interfaces:** `world_setup.gd` registers `neighborhood` and `home` with named entries `street_start`, `home_return`, and `home_entry`. `travel_door.gd` exposes `request_travel() -> Error` and observes transition terminal events.

- [ ] Write a failing integration check for neighborhood → home → neighborhood entry placement and a rejected travel request that restores door usability.
- [ ] Run the focused check; expect failure before world definitions and door behavior exist.
- [ ] Implement definitions, entry markers, both doors, and terminal-event handling through the public World API.
- [ ] Run the focused check; expect pass, then manually enter and leave the home in Godot.

### Task 3: Delivery rule and durable progress

**Files:** Create `example/rules/errand.tres`, rule resources, `example/integration/errand_coordinator.gd`, `example/tests/test_errand.gd`; modify `example/scenes/neighborhood.tscn`.

**Interfaces:** Coordinator exposes `pick_up_package() -> bool`, `deliver_package() -> bool`, and `sync_from_world_state() -> void`. It uses World keys `errand.package_collected`, `errand.delivered`, and `errand.vehicle_unlocked`. The rule responds to `package_delivered` and emits `vehicle_unlock_requested`.

- [ ] Write a failing check for pickup, delivery, unlock, and a duplicate delivery that changes no durable state.
- [ ] Run it; expect failure before the coordinator/rule exists.
- [ ] Implement package/contact interactions, load the authored rule book, translate its emitted unlock request into World state, and report rule-book load failure at startup.
- [ ] Run the focused check; expect pass. Validate the book with `godot --headless --path . --script addons/rule_engine/tools/validate_rules.gd -- --book=res://example/rules/errand.tres`.

### Task 4: Unlock and drive the sedan

**Files:** Create `example/integration/vehicle_gate.gd`, `example/tests/test_vehicle_unlock.gd`; modify `example/scenes/neighborhood.tscn` and `example/integration/errand_coordinator.gd`.

**Interfaces:** `vehicle_gate.gd` exposes `can_mount() -> bool` from `World.state.get_value(&"errand.vehicle_unlocked", false)` and applies that gate before calling the Liberty character adapter's normal mount interaction.

- [ ] Write a failing check that pre-unlock mount is denied, post-delivery mount succeeds, and state restoration recreates the unlocked presentation.
- [ ] Run it; expect failure before the gate exists.
- [ ] Place the existing driver-only sedan and garage access; wire the gate and call the Liberty adapter for successful mount/dismount.
- [ ] Run the focused check; expect pass. In a display-backed run, drive and exit the sedan.

### Task 5: Save/load and restored presentation

**Files:** Create `example/integration/save_panel.gd`, `example/tests/test_save_load.gd`; modify `example/integration/errand_coordinator.gd`, `example/scenes/neighborhood.tscn`.

**Interfaces:** `save_panel.gd` exposes `request_save() -> Error` and `request_load() -> Error` for slot `example_01`, then reports completion/failure from World terminal events. The coordinator calls `sync_from_world_state()` after restoration.

- [ ] Write a failing check for a save/load round trip of package, delivery, and unlock; include terminal failure feedback and continued interaction after failure.
- [ ] Run it; expect failure before controls and restore wiring exist.
- [ ] Implement the controls, terminal feedback, and scene presentation refresh after load.
- [ ] Run the focused check; expect pass. Verify a separate Godot process restores the unlock.

### Task 6: Playable walkthrough and final verification

**Files:** Modify `README.md`, `example/scenes/neighborhood.tscn`, `example/scenes/home.tscn`.

**Interfaces:** README documents pinned source revisions, controls, the main loop, optional travel, save/load, and a map of the project-owned integration points.

- [ ] Write the walkthrough and ensure the neighborhood has one obvious tagged traversal obstacle between pickup and delivery.
- [ ] Run headless import, focused checks, and rule validation; expect all pass.
- [ ] Perform a display-backed full loop: pickup, traverse, deliver, mount, drive, save/load, home travel, and return.
- [ ] Record exact commands and observed results in README or an execution report; disclose any display-backed step unavailable in the environment.

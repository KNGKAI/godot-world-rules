# Neighborhood Errand Integration Example

## Purpose

Create a small Godot 4.7.1 project that teaches developers how to integrate the sibling `godot-liberty`, `godot-world`, and `godot-rules` libraries. A player completes one delivery, unlocks a sedan, and drives it. A home interior provides an optional example of World Manager travel. The project favors readable integration code and a short walkthrough over game content.

## Player flow

1. Start on foot in one compact neighborhood. The garage sedan is present but unavailable to mount.
2. Pick up a package and cross a tagged traversal obstacle to reach a contact.
3. Deliver the package. The rule engine evaluates the delivery event and requests the vehicle unlock once.
4. The garage becomes accessible; the player mounts and drives the existing Liberty driver-only sedan.
5. Save and load. Delivery completion and vehicle access remain restored.
6. Optionally enter a home, travel to a small interior, and use its exit to return to a named neighborhood entry point.

## Ownership and integration

- **Liberty** owns on-foot movement, traversal, camera, vehicle possession, and sedan driving. Use its public character adapter for interaction and the existing Phase 9A sedan; do not modify the library to implement the errand.
- **World Manager** owns the registered neighborhood and home worlds, entry points, world state, coordinated travel, and save/load. The project records durable delivery and unlock facts in World state. A scene load or save completion is observed through its terminal events, since command acceptance does not mean completion.
- **Rule Engine** owns the data-authored condition that a delivered package unlocks the sedan. A project-owned engine or its optional autoload loads a rule book and receives a `package_delivered` event. Its emitted unlock request is handled by project code. The rule blackboard is not used as the sole durable record, because it is memory-only.
- **Project adapters** translate interactions into rule events, rule outcomes into World state changes, and restored World state into scene presentation. They are the example's main teaching surface; none of the three libraries imports another.

## Scenes and data

- `neighborhood`: a small traversable route, package pickup, contact, garage, sedan, home doorway, and named return entry.
- `home`: a single-room interior with an exit back to the neighborhood.
- One rule book: package delivery requires the package to be held and the vehicle to remain locked; its action emits `vehicle_unlock_requested`.
- Durable World state keys represent package collected, delivery completed, and vehicle unlocked. The project documents their meaning and restores interactable visibility and availability from them.

The package and contact can be simple project-owned interactables. The route should require one obvious Liberty traversal action, but failure to traverse must not corrupt progress. The home trip is optional and never gates the delivery or sedan drive.

## Behavior and failure handling

- Interactions guard against duplicate pickup and delivery. Replaying the delivery event cannot unlock twice or reset other progress.
- The sedan cannot be mounted before the unlock. After unlock, project code enables the normal Liberty mounting path; it does not bypass possession checks.
- Travel doors disable repeated requests while a travel operation is active and react to completion or failure events. A failed trip leaves the player able to try again.
- Save/load controls report the terminal result. A failed save or load leaves the current scene playable and does not claim progress was stored.
- If the rule book fails to load, the example reports an explicit startup error instead of silently leaving the sedan locked.

## Verification and documentation

Verify the full loop in the Godot editor: pickup, traversal, delivery, unlock, mount, drive, save/load, and optional travel in both directions. Include focused integration checks for duplicate delivery, locked mount, restored unlock, and failed travel handling. A README gives setup steps, controls, the expected loop, and a map of the three library boundaries. Keep the example small enough that a developer can find each integration point without searching through unrelated gameplay systems.

## Scope limits

Use the existing driver-only sedan. No passengers, vehicle persistence of physical position, quest framework, dialogue system, cinematic sequence, or second district is required. The saved progression is the unlock and delivery state; driving position may reset when loading.

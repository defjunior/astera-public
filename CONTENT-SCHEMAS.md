# Content shapes and integration boundaries

Authored records, palettes, geography, assets and tuned values are not bundled. This page names broad input/output responsibilities only, not the private optimization recipe.

## Dungeon

The retained layout/build modules consume room, archetype and asset descriptions. Those descriptions need the owner's private data. WFC, Vegetation and dungeon Progression are removed from the current tree. Decor remains by request but still references removed utility modules. No substitute solver or progression/vegetation data is supplied.

## World generation

The interface archive accepts terrain/feature requests and exposes query, planning and lifecycle boundaries. The internal representations, query composition, cache identity, execution order, budgets, thresholds and fixture values used by the optimized runtime are withheld. Remaining standalone geometry/structure modules do not close that dependency graph. See ARCHITECTURE.md rather than reconstructing missing behavior from empty interfaces.

## Movement

CharacterController requires the original BaseController, ClientStateStore, RemoteBridge, character/status hierarchy and Roblox input/render services. AsteraMovementController requires EntityTime and Roblox motion/constraint services. EntityTime is bundled from the earlier pass; client bootstrap/state/remotes are not. Game-specific status-forced movement is stubbed.

## Time, codec and transition

Time adapters expose clock/history/presentation responsibilities without private actor/AI implementations. The codec consumes structured values and produces binary packets, but has not been fuzzed here. Transition contracts carry caller-supplied destinations/runtime state; authored place/realm defaults remain absent. PersistenceService is removed, so capture/restoration integration still needs the original private service. No player records, access codes or production IDs are bundled.

This is a private inspection archive, not a runnable place. Empty methods and unresolved dependencies are deliberate exclusions. No license is granted.

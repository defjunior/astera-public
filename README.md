# Astera systems source

## World-gen organization (October 9)

Reviewed implementations now sit under Runtime, Sampling/Modifiers, Terrain, Structures, Topology, Decoration/Legacy, Streaming, Authoring and Diagnostics. The 23 old module paths are compatibility wrappers, matching the original project's migration pattern. Features and WorldGenerationScheduler keep their existing locations. New debug/verification/config content is not imported merely because it exists in the private tree.

This is a layout update, not a sync of private implementation changes. The 21 reviewed production implementations still contain 66 real of 134 declared functions (49.3%); wrappers are not counted. Omitted bodies still say "full method is omitted". Relative script dependencies were adjusted for folder depth and continue through compatibility entries; no runnable dependency-closure claim is made. See `reorganization-manifest.json` for old/new paths and hashes.

Public mixed source and architecture showcase. The exact world-generation optimization pipeline is intentionally withheld. This is no longer a full algorithm dump or a runnable game.

- Dungeon: layout, room/spec and build-management source. The owner removed the inactive WFC and Vegetation folders and dungeon Progression planning. Decor stays, as requested; some retained callers/Decor modules still reference removed utilities.
- World generation: marked real excerpts plus explanation/interface boundaries for startup, scheduling/streaming, terrain generation, sampling/caches, parallel placement, feature planning/emission, authoring previews and related verification recipes. Sites now includes read-side lookup/deduplication and placement transforms; other restored excerpts cover containment/cleanup, scheduler status, math, part materialization/cancellation and statistics. 66 of 134 declared functions across the 21 revised world-gen production files have real bodies (49.3%). Anonymous callbacks and original hidden helpers are not counted. Core orchestration/tuning/cache specifics remain omitted. Other selected geometry and structure modules remain real source. See [architecture](ARCHITECTURE.md).
- Local movement: `src/ReplicatedFirst/Client/Controllers/CharacterController.lua` handles client input and character lifecycle; `src/ReplicatedStorage/Modules/Utility/AsteraMovementController.lua` handles time-aware momentum and constraint lifecycle. Status/combat-forced enemy movement is stubbed. Framework/client state/remotes remain external.
- Entity-time, packet serialization and transition source from the earlier pass remain. PersistenceService is removed at the owner's request. Transition references to persistence are unresolved integration boundaries, not a bundled implementation.
- Player component mount/unmount/binding infrastructure and movement wiring remain partial. Gameplay-heavy player components are still held pending the owner's sensitivity decision.

## Status

The owner identifies WFC and Vegetation as inactive/nonworking decoration systems. World generation remains work in progress. No Roblox execution, gameplay, performance or security validation is claimed here. Marked real excerpts are copied source, while named empty methods describe integration surfaces, not drop-in implementations. This is a mix of code and explanation, not a literal promise that half the original lines are disclosed. The owner will review this balance before any history cleanup/public release. Original game repositories were not edited.

See [extraction boundaries](EXTRACTION.md), [content shapes](CONTENT-SCHEMAS.md), `source-manifest.json`, `additional-source-manifest.json`, `component-source-manifest.json` and `boundary-revision-manifest.json` for scope and provenance. Earlier full implementations remain recoverable in commit history. The owner approved the Oct 8 public release after a local root cleanup. New organization commits follow that root. Prior briefly exposed full-code objects/copies/caches are not guaranteed erased by force-push. No license is granted.

# Architecture without the optimization recipe

## World-gen organization (October 9)

Reviewed implementations now sit under Runtime, Sampling/Modifiers, Terrain, Structures, Topology, Decoration/Legacy, Streaming, Authoring and Diagnostics. The 23 old module paths are compatibility wrappers, matching the original project's migration pattern. Features and WorldGenerationScheduler keep their existing locations. New debug/verification/config content is not imported merely because it exists in the private tree.

This is a layout update, not a sync of private implementation changes. The 21 reviewed production implementations still contain 66 real of 134 declared functions (49.3%); wrappers are not counted. Omitted bodies still say "full method is omitted". Relative script dependencies were adjusted for folder depth and continue through compatibility entries; no runnable dependency-closure claim is made. See `reorganization-manifest.json` for old/new paths and hashes.

This archive mixes marked original source excerpts with responsibilities and interface stubs. It deliberately does not disclose the implementation order, worker coordination, budgets, cache structure, thresholds, placement decisions or tests needed to reproduce Astera's optimized world-generation pipeline.

## World generation

**Runtime boundary.** The entry script connects world-generation work to the game's startup/lifecycle. Its implementation is withheld. The archive must not start generation merely because this script is present.

**Work and residency boundaries.** Scheduler and streaming modules represent two different responsibilities: managing ongoing work, and managing which world content should exist for the current environment. The scheduler stop/status methods are real lifecycle/reporting excerpts. Other names and callable interfaces remain; prioritization, reuse, synchronization and resource policy do not.

**Terrain queries and geometry.** Height/map/biome interfaces separate requests for environmental information from consumers that create geometry. Containment and cleanup/tag helpers are real excerpts. Terrain generation, detail and placement entry points remain visible, but the query composition and optimized production path are withheld. Retained spline/geometry utilities illustrate local mathematical work, not the private runtime recipe.

**Features and structures.** Feature planning describes proposed content; emission owns its materialization and lifetime. Terrain adapters connect that work to terrain and protected structures. Part materialization and cancellation/failure cleanup are real excerpts; production staging/publication, planning and recipe construction are withheld. Selected standalone feature geometry, spatial queries and persistent-structure contracts remain as source; they do not complete the missing system.

**Tools and diagnostics.** Audit percentile/summary helpers are real, while production audit/authoring entry points are retained as names only, since previews and assertions can reveal the same recipe as production code. Related world-generation tests/fixtures are intentionally empty; they are not claimed as passing.

## Sites: a concrete mixed example

`Modules/Structures/Sites.lua` retains actual read-side lookup: nearby chunk buckets refer to site records, and a local seen set prevents the same record being returned twice. `GetPlacementCFrame` places a resolved record at its pad height; the footprint extent helper shows a simple circle/rectangle distinction. The registration code that populates those tables is withheld. No candidate rolls, deduplication signatures, cache layout, reconciliation order, separation thresholds or terrain-flattening composition are revealed. These snippets explain what a resolved site is used for without providing a complete placement system.

## How to read the code/explanation balance

The 21 production boundaries contain 66 real declared functions and 68 omitted declarations: 66/134, or 49.3%. This counts named local helpers and nested declarations currently shown, not anonymous callbacks or every original hidden helper. 20 of the 21 files include real excerpts; the other production boundaries remain explanation/interface-only. The nine test/fixture files stay withheld. This is a balance by responsibility, not a literal half of the original line count. Revealing a percentage of every method would expose the very algorithm the owner wants kept private.

The omission-body comment is exactly `full method is omitted`. Small local operations are shown: bounds checks, model scaling, queue/status reporting, box-to-part materialization, cancellation cleanup and percentile aggregation. The missing pieces are the decisions that connect those operations into the private runtime. Some snippets rely on omitted state/types/config; they are inspection excerpts, not a repaired dependency graph. No formal guarantee against all reconstruction paths is claimed. Owner review is required before cleanup/public release.

## Dungeon

The retained layout/build modules separate room requests, spatial construction and build bookkeeping. The owner removed WFC and Vegetation as inactive/nonworking decoration systems and asked to remove dungeon progression planning. Decor is kept by explicit instruction. Retained Decor/DungeonSystem/generator callers still contain references to removed modules. This is an honest source archive, not a repaired runnable dungeon. No substitute solver, vegetation or progression implementation is supplied.

## Local movement

CharacterController owns local input, sprint/slide requests and character attachment. It depends on the original BaseController, ClientStateStore, RemoteBridge and replicated status/character setup. Game-specific status-driven enemy movement is excluded.

AsteraMovementController owns motion handles and velocity constraints, including lifecycle cleanup and entity-time-aware motion. It is shared utility code used by the local layer, not a complete client bootstrap. EntityTime is included from the earlier pass; Roblox services and original integration remain required. Source inspection is not evidence of working input, replication or collision behavior.

## Other retained systems

Entity-time modules separate clocks/history from presentation. The packet codec separates structured values from binary representation. Transition contracts separate handoff data from runtime orchestration. PersistenceService is removed; transition-to-persistence references remain external/unresolved. The component base separates method exposure and lifetime from gameplay components, which are still incomplete here.

## Reading this archive

A responsibility comment says what a boundary owns, not how it achieves it. A named stub says an integration surface exists, not that it returns valid data. Excluded authored data and unresolved dependencies must not be filled with guessed production values. Private/no-license and the full-history audit gate apply to every retained file.

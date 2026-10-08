# Source and extraction boundaries

## October 8 partial-reveal revision

The owner asked for both real code and explanations, explicitly allowing Sites while keeping the exact recipe private. 20 production boundaries now contain real source excerpts. The 21-file production slice contains 66 real declared functions of 134 visible declarations (49.3%); 68 bodies remain omitted. The denominator includes named local/nested helpers, excludes anonymous callbacks and original hidden helpers. The related nine tests/fixtures remain withheld. Existing standalone geometry/source and local movement remain unchanged. Selection is by responsibility rather than mechanically publishing half of every function. The original orchestration, tuning, caches, placement policy, generation composition and recipe construction remain omitted. Additional excerpts cover coordinate transforms, bounds helpers, tag/config read-side getters, collection cleanup, profiling wrappers, metadata queries, explicit-input spacing checks and spline construction. Empty omitted bodies use exactly "full method is omitted". No policy/caches/tuning/recipe implementations were restored. Source excerpts are checked against live Astera originals, with selected comment/type-only adjustments recorded.

Astera remains private for owner review. No history squash or public flip has happened. Earlier full implementations remain in history.

## October 7 boundary revision (superseded only by the selected excerpts above)

The owner now identifies the exact world-generation optimization pipelines as proprietary and asks for explanations without a copyable recipe. This instruction replaces the earlier full-algorithm extraction for that slice. At that revision, thirty world-generation files contained responsibility comments and named interfaces only: production orchestration, scheduling/streaming, terrain generation/culling, query/cache composition, parallel placement, feature planning/emission/clipping/recipe construction, authoring/audit paths and associated tests/fixtures. Private orchestration/tuning/cache policies and fixture values remain withheld; the October 8 section records the local source excerpts now shown.

Other selected source remains real. This distinction is recorded file-by-file in boundary-revision-manifest.json. No claim is made that all conceivable reconstruction paths have been formally proven absent; the complete source/history review remains a release gate.

The owner asked to remove the inactive/nonworking dungeon WFC and Vegetation systems, dungeon Progression planning and PersistenceService. These are removed from the current extraction tree. Decor remains by explicit instruction. Retained callers and Decor modules reference some removed utilities; those dependencies are documented, not silently rebuilt. The original Astera repository is untouched.

The requested local movement layer is added at its original client/shared-utility paths. CharacterController excludes status/combat-forced enemy movement via named stubs. The shared movement utility remains real source. No game-specific AI, skill/reward implementation or authored content tables were added.

Authored game-content/config tables, assets, secrets, credentials, private player records and AI/learning/strategy/dialogue implementations remain excluded under the earlier boundary. Named interfaces and data shapes are not production substitutes. See ARCHITECTURE.md and CONTENT-SCHEMAS.md.

## Validation and release

Current outputs are checked against live pre-edit extraction source or live movement originals, then destination readbacks. Manifests distinguish removals, interface-only substitutions and real-source additions. Parsing is not Roblox execution or a guarantee of dependency closure, geometry, input, replication, gameplay, security or performance. Some intentional omissions prevent modules from loading.

Earlier implementations and removed files remain recoverable in this extraction's history. No history rewrite was performed. Before any public release, the owner must approve a full history audit and any cleanup/recreation plan. Current-tree deletion is not secret erasure. The repository remains private and grants no license.

## Additional approved systems (October 6, 2026)

The owner selected entity-time/history, binary serialization and transition/runtime-state restoration. The Hitori solver and party/matchmaking systems were not selected and were not copied. Ten earlier additional system files remain after removal of PersistenceService on October 7; their paths and existing cuts are preserved. See additional-source-manifest.json.

EntityTime, Timeline, EffectTime and Presentation are unchanged. TimeControlService retains registration, control selection, replicated state, interpolation/seek, history, physics restoration and adapters. Authored sound playback, stop-parry/cancel-window abilities and combat hit bookkeeping are omitted with comments. TickService keeps clocks, scheduling, action generations and replay mechanics; AI-specific cancellation telemetry and bot stunned-action policy are removed. GameObjects.TimeStop, movement StopMotion, VisualOwnership, actor/runtime hierarchy and client presentation controller remain external integration requirements. Adapters expose only their interface, not private actor/AI implementations. Native particles cannot rewind; source warns about that limitation.

RemotePacketCodec is unchanged. Its fixed-width lengths, recursive decoding, nil-count handling and input limits require round-trip, malformed-buffer, cyclic/deep-payload and fuzz tests. No transport integration or bandwidth benchmark is asserted.

TransitionService retains normalization, contract validation, metadata, snapshot attachment, target selection, private-server handoff, retry plans and failure/removal cleanup. Removed: literal destination IDs, authored runtime defaults, realm-specific fallback, default dungeon-template ID, carry/grip release glue and menu/Starlink visual effects. Empty/no-op omissions are labeled and are not replacement implementations. TeleportContract retains protocol enums and constructors; authored realm catalog/default is excluded. PersistenceService is now removed at the owner's request. Its former capture/restore implementation is not part of the current tree. Runtime snapshot fields and bar-key maps describe data structure, not copied player records or authored content. No actual access codes/player records were copied; fields accepting live access codes remain part of the algorithm interface.

Framework, ServerModeService, ServerListService, DungeonInstanceRegistry, Realms, IslandLayout content, runtime player objects and Roblox place hierarchy are not bundled. Missing configs and removed combat/effect glue mean this is inspection source, not drop-in game code. No live teleport, replay, simulation, recovery/security or exactly-once guarantee was verified. No original game files were modified. Private/no-license and full-history audit before release remain unchanged.

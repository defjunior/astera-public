-- DungeonBuildState.lua
-- Shared runtime state for dungeon generation + build telemetry.
-- Replaces the previous pattern of using workspace attributes as a
-- cross-script blackboard for stats, progress, and diagnostic counters.
--
-- Writers:
--   - DungeonBuildService.lua         (geometry, roofs, walls, decor, ...)
--   - DungeonGenerator.lua            (phase timings, parameter map, ...)
--   - DungeonGenTest.server.lua       (test-harness internal state)
-- Readers:
--   - DungeonGenTest.server.lua       (post-build assertions, progress polling)
--
-- Everything goes through `set` / `get`; keys use the same `Dungeon*`
-- names that were previously workspace attributes so the diff is mechanical.
-- Both scripts run on the main server thread (no actors), so a plain module
-- table is sufficient — there's a single shared instance per server.

local DungeonBuildState = {}

local state = {}

function DungeonBuildState.set(name, value)
	state[name] = value
end

function DungeonBuildState.get(name)
	return state[name]
end

function DungeonBuildState.clear()
	for k in pairs(state) do
		state[k] = nil
	end
end

function DungeonBuildState.snapshot()
	local out = {}
	for k, v in pairs(state) do
		out[k] = v
	end
	return out
end

return DungeonBuildState

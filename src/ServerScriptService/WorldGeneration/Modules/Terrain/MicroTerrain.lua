-- Partial source showcase, revised October 8, 2026.
-- Local terrain-detail interface. Accepts a chunk context; detail emission and resource policy are private.
-- This boundary shows where requests enter and results leave the subsystem.
-- The private policy decides what work to accept and when to publish it; no execution recipe is exposed.
-- Real local helpers are shown; remaining interfaces are documentation stubs, not a working replacement.

local MicroTerrain = {}

local RUNS_IN_ACTOR = script:GetActor() ~= nil

-- Real source excerpt: synchronizeActor
local function synchronizeActor()
	if RUNS_IN_ACTOR then
		task.synchronize()
	end
end

-- Real source excerpt: desynchronizeActor
local function desynchronizeActor()
	if RUNS_IN_ACTOR then
		task.desynchronize()
	end
end

-- Contract: Local terrain-detail interface. Implementation intentionally unavailable.
function MicroTerrain.PlaceChunkMicroTerrain(parentModel, chunkCenter, surfaceY, config, chunkState, heightStats, terrainMods, biomeName, decorationWeight, propLayerCount, layerProfile)
	-- full method is omitted
end

return MicroTerrain

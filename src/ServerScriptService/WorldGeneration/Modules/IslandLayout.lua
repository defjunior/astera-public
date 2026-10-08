--!strict
-- Actual island lookup, signed-distance and scatter algorithms.
-- EXCLUDED: authored geography commentary and mainland configuration.
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local IslandLayout = {}

export type IslandSpec = {
	index: number,              -- global island id, 1-based
	seriesIndex: number,        -- 1..7 astral series
	indexInSeries: number,      -- 1..7 position within the series
	name: string,               -- island identifier
	label: string,              -- UI display label
	biome: string,              -- matches BiomeConfig keys

	-- Mainland footprint in world space. Center is XZ only; Y comes from
	-- the heightfield / layer profile at sample time.
	center: Vector2,
	radius: number,             -- studs, approximate mainland extent

	-- Edge deformation: the island SDF is a circle of `radius` warped by
	-- Perlin noise so silhouettes are organic, not perfect disks.
	shapeSeed: number,          -- seed for noise deformation (WorldSeed-derived)
	shapeNoiseScale: number,    -- wavelength of edge noise (studs)
	shapeNoiseAmplitude: number,-- fraction of radius the edge can wobble (0..1)

	-- Starlink anchor in island-local XZ. World position is
	-- center + starlinkAnchorLocal. The actual teleport-in structure is
	-- placed here during Phase 2 (reservations) / Phase 8 (progression).
	starlinkAnchorLocal: Vector2,

	-- Skylist sub-island fields (nil/false for mainlands).
	isSkylist: boolean?,
	parentIslandIndex: number?,

	-- Progression gate. If set, StarlinkService.canUseStarlink checks that
	-- the player's profile has `unlockFlag` set to true before letting them
	-- travel here. nil means the island is open by default (the initial island).
	unlockFlag: string?,
}

local CHUNK_STUDS = 50

local SKYLIST_CONFIG = {
 -- EXCLUDED: authored content/settings table, at the owner's request.
 -- General structure: skylist scatter settings: count/radius ranges, ring bounds and noise ranges
 -- Intentionally empty, not a runnable replacement. See CONTENT-SCHEMAS.md.
}

local ISLANDS: { IslandSpec } = {
 -- EXCLUDED: authored mainland records and derived geography constants.
 -- Shape: IslandSpec[]; see the retained type and CONTENT-SCHEMAS.md.
}

-- Realm dispatch. Non-Reality realms supply their own island mask via
-- RealmConfigs/<realm>/IslandData.lua, and can opt out of skylist scatter
-- entirely (the wasteland is one vast contiguous mask, for example).
-- ServerBootService writes ServerBootRealm before WorldGeneration boots,
-- so the attribute is reliably set by the time this module is required.
local SKIP_SKYLISTS = false
do
	local bootRealm = Workspace:GetAttribute("ServerBootRealm")
	if RunService:IsStudio() and (
		Workspace:GetAttribute("StudioForcedRealm") == "DarkDimension"
		or Workspace:GetAttribute("StudioRunProfileActive") == "dark_realm"
	) then
		bootRealm = "DarkDimension"
	end
	if bootRealm == "DarkDimension" then
		local realmData = require(script.Parent.RealmConfigs.DarkDimension.IslandData) :: any
		if type(realmData) == "table" and type(realmData.islands) == "table" then
			table.clear(ISLANDS)
			for _, spec in ipairs(realmData.islands) do
				ISLANDS[#ISLANDS + 1] = spec
			end
		end
		if realmData and realmData.skipSkylists == true then
			SKIP_SKYLISTS = true
		end
	end
end

local generatedSkylistSeed: number? = nil

-- Flat lookup tables — rebuilt whenever skylist generation runs.
local BY_INDEX: { [number]: IslandSpec } = {}
local BY_NAME: { [string]: IslandSpec } = {}

local function rebuildLookups()
	table.clear(BY_INDEX)
	table.clear(BY_NAME)
	for _, spec in ipairs(ISLANDS) do
		BY_INDEX[spec.index] = spec
		BY_NAME[spec.name] = spec
	end
end
rebuildLookups()

IslandLayout.CHUNK_STUDS = CHUNK_STUDS
IslandLayout.Islands = ISLANDS

-- Returns the raw list. Read-only — mutating it will break determinism.
function IslandLayout.list(): { IslandSpec }
	return ISLANDS
end

-- Returns only mainland islands (not skylist sub-islands).
function IslandLayout.mainlands(): { IslandSpec }
	local result = {}
	for _, spec in ipairs(ISLANDS) do
		if not spec.isSkylist then
			result[#result + 1] = spec
		end
	end
	return result
end

function IslandLayout.getByIndex(index: number): IslandSpec?
	return BY_INDEX[index]
end

function IslandLayout.getByName(name: string): IslandSpec?
	return BY_NAME[name]
end

-- Generate skylist sub-islands around each mainland after the ServerSeed is
-- known. Repeated calls for the same seed are no-ops; changing seeds replaces
-- the generated skylists instead of appending another set.
function IslandLayout.generateSkylists(serverSeed: number)
	if SKIP_SKYLISTS then
		print("[IslandLayout] Skylist generation skipped for current realm")
		return
	end
	local resolvedSeed = math.floor(serverSeed)
	if generatedSkylistSeed == resolvedSeed then
		return
	end
	for index = #ISLANDS, 1, -1 do
		if ISLANDS[index].isSkylist then
			table.remove(ISLANDS, index)
		end
	end

	local rng = Random.new(resolvedSeed)
	local nextIndex = #ISLANDS + 1

	-- Snapshot mainlands before we start appending
	local mainlands = {}
	for _, spec in ipairs(ISLANDS) do
		if not spec.isSkylist then
			mainlands[#mainlands + 1] = spec
		end
	end

	for _, mainland in ipairs(mainlands) do
		local count = rng:NextInteger(SKYLIST_CONFIG.countMin, SKYLIST_CONFIG.countMax)
		-- Golden-angle scatter for even distribution around the ring
		local goldenAngle = math.pi * (3 - math.sqrt(5)) -- ~2.399 rad
		local baseAngle = rng:NextNumber() * math.pi * 2

		for i = 1, count do
			local angle = baseAngle + goldenAngle * i
			local radius = SKYLIST_CONFIG.radiusMin + rng:NextNumber() * (SKYLIST_CONFIG.radiusMax - SKYLIST_CONFIG.radiusMin)
			local noiseAmplitude = SKYLIST_CONFIG.noiseAmplitudeMin + rng:NextNumber() * (SKYLIST_CONFIG.noiseAmplitudeMax - SKYLIST_CONFIG.noiseAmplitudeMin)
			local minDistance = mainland.radius * (1 + mainland.shapeNoiseAmplitude)
				+ radius * (1 + noiseAmplitude) + CHUNK_STUDS * 2
			local innerDistance = math.max(mainland.radius * SKYLIST_CONFIG.ringInner, minDistance)
			local outerDistance = math.max(mainland.radius * SKYLIST_CONFIG.ringOuter, innerDistance)
			local dist = innerDistance + rng:NextNumber() * (outerDistance - innerDistance)
			local cx = mainland.center.X + math.cos(angle) * dist
			local cz = mainland.center.Y + math.sin(angle) * dist

			local spec: IslandSpec = {
				index = nextIndex,
				seriesIndex = mainland.seriesIndex,
				indexInSeries = mainland.indexInSeries,
				name = mainland.name .. "_Sky" .. i,
				label = mainland.label .. " Skylist " .. i,
				biome = mainland.biome,
				center = Vector2.new(cx, cz),
				radius = radius,
				shapeSeed = resolvedSeed + nextIndex * 7,
				shapeNoiseScale = SKYLIST_CONFIG.noiseScaleMin + rng:NextNumber() * (SKYLIST_CONFIG.noiseScaleMax - SKYLIST_CONFIG.noiseScaleMin),
				shapeNoiseAmplitude = noiseAmplitude,
				starlinkAnchorLocal = Vector2.new(0, 0),
				isSkylist = true,
				parentIslandIndex = mainland.index,
			}

			ISLANDS[#ISLANDS + 1] = spec
			nextIndex += 1
		end
	end

	generatedSkylistSeed = resolvedSeed
	rebuildLookups()

	local skyCount = #ISLANDS - #mainlands
	print(string.format("[IslandLayout] Generated %d skylist sub-islands across %d mainlands", skyCount, #mainlands))
end

-- Signed distance from (worldX, worldZ) to the edge of `spec`.
-- Negative = inside the island, 0 = on the edge, positive = outside.
-- The edge is a Perlin-warped circle so silhouettes are organic.
local function signedDistanceTo(spec: IslandSpec, worldX: number, worldZ: number): number
	local dx = worldX - spec.center.X
	local dz = worldZ - spec.center.Y
	local dist = math.sqrt(dx * dx + dz * dz)

	-- Edge warp: Perlin noise in [-1, 1] scaled to ±amplitude * radius.
	-- Sampled in island-local space so the warp is stable per-island.
	local nx = dx / spec.shapeNoiseScale
	local nz = dz / spec.shapeNoiseScale
	local warp = math.noise(nx, nz, spec.shapeSeed * 0.01)
	local effectiveRadius = spec.radius * (1 + spec.shapeNoiseAmplitude * warp)

	return dist - effectiveRadius
end

IslandLayout.signedDistanceTo = signedDistanceTo

-- Samples every island and returns the one whose signed distance is
-- smallest (most "inside", or least "outside" if not inside any).
-- Returns (spec, signedDistance). spec may be nil only if the island
-- table is empty.
--
-- Callers that only care about inside/outside should check `sd < 0`.
function IslandLayout.sampleAt(worldX: number, worldZ: number): (IslandSpec?, number)
	local bestSpec: IslandSpec? = nil
	local bestSd = math.huge
	for _, spec in ipairs(ISLANDS) do
		local sd = signedDistanceTo(spec, worldX, worldZ)
		if sd < bestSd then
			bestSd = sd
			bestSpec = spec
		end
	end
	return bestSpec, bestSd
end

-- Fast yes/no query: is the point inside *any* island mask?
function IslandLayout.isInsideAny(worldX: number, worldZ: number): boolean
	for _, spec in ipairs(ISLANDS) do
		if signedDistanceTo(spec, worldX, worldZ) < 0 then
			return true
		end
	end
	return false
end

-- Cheap early-out: does a chunk-sized square at (worldX, worldZ) with
-- side `chunkStuds` intersect any island's bounding disk? Used by
-- streaming to skip whole chunks that can't possibly contain land.
function IslandLayout.chunkIntersectsAny(worldX: number, worldZ: number, chunkStuds: number): boolean
	local half = chunkStuds * 0.5
	-- Worst-case edge expansion from noise warp.
	for _, spec in ipairs(ISLANDS) do
		local maxRadius = spec.radius * (1 + spec.shapeNoiseAmplitude)
		local dx = math.max(0, math.abs(worldX - spec.center.X) - half)
		local dz = math.max(0, math.abs(worldZ - spec.center.Y) - half)
		if dx * dx + dz * dz <= maxRadius * maxRadius then
			return true
		end
	end
	return false
end

return IslandLayout

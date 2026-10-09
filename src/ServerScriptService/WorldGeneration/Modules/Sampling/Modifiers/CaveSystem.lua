-- CaveSystem.lua
-- Determines cave voids inside terrain columns using 3D ridge-noise intersection.
-- Two layers: rare large cave systems + occasional small tunnels.
-- All parameters are configurable per-biome.

local noise = math.noise
local abs = math.abs
local min = math.min
local max = math.max
local clamp = math.clamp
local floor = math.floor
local sqrt = math.sqrt

local CaveSystem = {}

---------------------------------------------------------------------
-- Default configuration
---------------------------------------------------------------------
CaveSystem.DefaultConfig = {
 -- EXCLUDED: authored content/settings table, at the owner's request.
 -- General structure: cave settings: enablement, vertical sampling, solid thickness, Large/Small noise channels, height limits and entrance settings
 -- Intentionally empty, not a runnable replacement. See CONTENT-SCHEMAS.md.
}

---------------------------------------------------------------------
-- 3D ridge noise: peaks along zero-crossings of Perlin noise
-- The intersection of two perpendicular ridge surfaces = tube-shaped caves
---------------------------------------------------------------------
local function ridgeSample3D(wx, wy, wz, scaleA, scaleB, seedA, seedB, ySquish)
	local sy = wy * ySquish
	-- Important: include wz in both samples so caves are truly 3D. The old
	-- version only varied in X/Y and produced sheet-like hollow mountains.
	local n1 = noise(
		(wx + seedA * 0.13) / scaleA,
		(sy + 19.7) / scaleA,
		(wz + seedA * 0.29) / scaleA
	)
	local n2 = noise(
		(wx + 71.3 + seedB * 0.17) / scaleB,
		(sy + 43.7) / scaleB,
		(wz + 11.9 + seedB * 0.31) / scaleB
	)
	-- Ridge: 1 at zero-crossing, 0 at extremes
	local ridge1 = 1 - abs(n1) * 2
	local ridge2 = 1 - abs(n2) * 2
	-- Intersection: cave exists where BOTH ridges are high
	return min(ridge1, ridge2)
end

local function entranceRoll(wx, wz, seed, cfg)
	local scale = cfg.NoiseScale or 220
	local n = noise(
		(wx + seed * 0.11) / scale,
		(wz - seed * 0.07) / scale,
		seed * 0.0031
	)
	return (n + 1) * 0.5
end

---------------------------------------------------------------------
-- 2D enablement check: is this (x,z) column eligible for caves?
---------------------------------------------------------------------
local function isEnabled(wx, wz, enableScale, enableThreshold, enableSeed)
	local n = noise(wx / enableScale, wz / enableScale, enableSeed * 0.0037)
	-- Map [-1,1] -> [0,1]
	return (n + 1) * 0.5 > enableThreshold
end

---------------------------------------------------------------------
-- Sample whether a 3D point is inside a cave
-- Returns: density value (> threshold = cave), and which layer triggered it
---------------------------------------------------------------------
function CaveSystem.sampleDensity(wx, wy, wz, seed, config)
	config = config or CaveSystem.DefaultConfig
	if not config.Enabled then return -1, nil end

	-- Height restriction
	if wy < config.MinCaveY or wy > config.MaxCaveY then
		return -1, nil
	end

	local bestDensity = -1
	local bestLayer = nil

	-- Large cave systems
	if config.Large and config.Large.Enabled then
		local lg = config.Large
		if isEnabled(wx, wz, lg.EnableScale, lg.EnableThreshold, seed + lg.EnableSeed) then
			local d = ridgeSample3D(wx, wy, wz, lg.ScaleA, lg.ScaleB, seed + lg.SeedA, seed + lg.SeedB, lg.YSquish)
			if d > bestDensity then
				bestDensity = d
				bestLayer = "large"
			end
		end
	end

	-- Small tunnels
	if config.Small and config.Small.Enabled then
		local sm = config.Small
		if isEnabled(wx, wz, sm.EnableScale, sm.EnableThreshold, seed + sm.EnableSeed) then
			local d = ridgeSample3D(wx, wy, wz, sm.ScaleA, sm.ScaleB, seed + sm.SeedA, seed + sm.SeedB, sm.YSquish)
			if d > bestDensity then
				bestDensity = d
				bestLayer = "small"
			end
		end
	end

	return bestDensity, bestLayer
end

---------------------------------------------------------------------
-- Core: scan a terrain column and return the solid segments.
--
-- Input:
--   wx, wz       : world X, Z of the column center
--   columnBottom  : Y coordinate of the bottom of the terrain part
--   columnTop     : Y coordinate of the top of the terrain part
--   seed          : world seed
--   config        : CaveSystem config (or nil for defaults)
--
-- Returns: array of {bottom: number, top: number, isTopSegment: boolean}
--   Each entry is a solid vertical span. Gaps between entries are caves.
--   If no caves intersect, returns a single span covering the whole column.
---------------------------------------------------------------------
function CaveSystem.scanColumn(wx, wz, columnBottom, columnTop, seed, config)
	config = config or CaveSystem.DefaultConfig
	if not config.Enabled then
		return {{ bottom = columnBottom, top = columnTop, isTopSegment = true }}
	end

	local columnHeight = columnTop - columnBottom
	if columnHeight < config.MinCaveHeight + config.MinSolidThickness * 2 then
		-- Column too short for any cave
		return {{ bottom = columnBottom, top = columnTop, isTopSegment = true }}
	end

	-- Compute protected zones (top and bottom solid caps)
	local topSolid = columnTop - columnHeight * config.TopSolidFraction
	local bottomSolid = columnBottom + columnHeight * config.BottomSolidFraction

	-- Quick enablement check: avoid sampling the full column if no caves are possible here
	local anyEnabled = false
	if config.Large and config.Large.Enabled then
		anyEnabled = anyEnabled or isEnabled(wx, wz, config.Large.EnableScale, config.Large.EnableThreshold, seed + config.Large.EnableSeed)
	end
	if config.Small and config.Small.Enabled then
		anyEnabled = anyEnabled or isEnabled(wx, wz, config.Small.EnableScale, config.Small.EnableThreshold, seed + config.Small.EnableSeed)
	end
	if not anyEnabled then
		return {{ bottom = columnBottom, top = columnTop, isTopSegment = true }}
	end

	local step = config.SampleStep
	local threshold_large = config.Large and config.Large.Threshold or 1
	local threshold_small = config.Small and config.Small.Threshold or 1

	-- Sample the column at regular intervals
	-- State: true = solid, false = cave
	local samples = {}
	local sampleCount = 0
	local startY = bottomSolid
	local endY = topSolid

	local y = startY
	while y <= endY do
		local density, layer = CaveSystem.sampleDensity(wx, y, wz, seed, config)
		local isCave = false
		if layer == "large" and density > threshold_large then
			isCave = true
		elseif layer == "small" and density > threshold_small then
			isCave = true
		end
		sampleCount += 1
		samples[sampleCount] = { y = y, cave = isCave }
		y += step
	end

	-- If no cave samples found, return whole column
	local anyCave = false
	for _, s in ipairs(samples) do
		if s.cave then anyCave = true; break end
	end
	if not anyCave then
		return {{ bottom = columnBottom, top = columnTop, isTopSegment = true }}
	end

	-- Deliberate surface entrances:
	-- 1) preserve natural openings if cave reaches near topSolid
	-- 2) otherwise occasionally force a vertical connector from topSolid down
	--    to the highest nearby cave body.
	local surfaceCfg = config.SurfaceEntrances
	local surfaceOpen = false
	if surfaceCfg and surfaceCfg.Enabled ~= false then
		local naturalTopSamples = math.max(1, surfaceCfg.NaturalTopSamples or 2)
		for i = sampleCount, math.max(1, sampleCount - naturalTopSamples + 1), -1 do
			if samples[i] and samples[i].cave then
				surfaceOpen = true
				break
			end
		end

		if not surfaceOpen then
			local highestCaveIdx = nil
			for i = sampleCount, 1, -1 do
				if samples[i] and samples[i].cave then
					highestCaveIdx = i
					break
				end
			end

			if highestCaveIdx then
				local highestCaveY = samples[highestCaveIdx].y
				local maxDepth = math.max(step * 3, surfaceCfg.MaxDepth or 56)
				local entranceFloorY = topSolid - maxDepth
				if highestCaveY >= entranceFloorY then
					local chance = math.clamp(surfaceCfg.Chance or 0.38, 0, 1)
					if entranceRoll(wx, wz, seed, surfaceCfg) <= chance then
						local carveDownTo = math.max(entranceFloorY, highestCaveY)
						for i = sampleCount, 1, -1 do
							local s = samples[i]
							if s.y >= carveDownTo then
								s.cave = true
							else
								break
							end
						end
						surfaceOpen = true
					end
				end
			end
		end
	end

	-- Build solid segments from the sample array
	-- Walk bottom to top, tracking transitions between solid and cave
	local segments = {}
	local segStart = columnBottom -- current solid segment starts at column bottom
	local inCave = false

	-- Add the bottom protected zone as always-solid
	for _, s in ipairs(samples) do
		if s.y < bottomSolid then continue end
		if s.y > topSolid then break end

		if s.cave and not inCave then
			-- Transition: solid -> cave
			-- End current solid segment
			local segTop = s.y
			if segTop - segStart >= config.MinSolidThickness then
				segments[#segments + 1] = { bottom = segStart, top = segTop, isTopSegment = false }
			end
			inCave = true
		elseif not s.cave and inCave then
			-- Transition: cave -> solid
			segStart = s.y
			inCave = false
		end
	end

	-- Close final segment up to column top
	if not inCave then
		if columnTop - segStart >= config.MinSolidThickness then
			segments[#segments + 1] = { bottom = segStart, top = columnTop, isTopSegment = true }
		end
	else
		-- Was in a cave at the top boundary.
		-- Keep it open only when a natural/forced entrance was chosen.
		if not surfaceOpen then
			segments[#segments + 1] = { bottom = topSolid, top = columnTop, isTopSegment = true }
		end
	end

	-- If somehow we ended up with no segments, return the whole column
	if #segments == 0 then
		return {{ bottom = columnBottom, top = columnTop, isTopSegment = true }}
	end

	-- Validate: merge segments that are too thin
	local merged = {}
	for _, seg in ipairs(segments) do
		local thickness = seg.top - seg.bottom
		if thickness >= config.MinSolidThickness then
			merged[#merged + 1] = seg
		end
	end

	if #merged == 0 then
		return {{ bottom = columnBottom, top = columnTop, isTopSegment = true }}
	end

	-- Mark the highest segment as the top segment (gets grass), unless this
	-- column was opened to the surface for an entrance.
	merged[#merged].isTopSegment = not surfaceOpen

	return merged
end

---------------------------------------------------------------------
-- Convenience: is there any cave at this world position?
---------------------------------------------------------------------
function CaveSystem.hasCaveAt(wx, wy, wz, seed, config)
	local density, layer = CaveSystem.sampleDensity(wx, wy, wz, seed, config)
	if not layer then return false end
	config = config or CaveSystem.DefaultConfig
	local threshold
	if layer == "large" then
		threshold = config.Large and config.Large.Threshold or 1
	else
		threshold = config.Small and config.Small.Threshold or 1
	end
	return density > threshold
end

---------------------------------------------------------------------
-- Get merged cave config from biome overrides
---------------------------------------------------------------------
function CaveSystem.mergeConfig(overrides)
	if not overrides then return CaveSystem.DefaultConfig end
	local merged = {}
	-- Shallow-copy defaults
	for k, v in pairs(CaveSystem.DefaultConfig) do
		if type(v) == "table" then
			merged[k] = {}
			for k2, v2 in pairs(v) do
				merged[k][k2] = v2
			end
		else
			merged[k] = v
		end
	end
	-- Apply overrides
	for k, v in pairs(overrides) do
		if type(v) == "table" and type(merged[k]) == "table" then
			for k2, v2 in pairs(v) do
				merged[k][k2] = v2
			end
		else
			merged[k] = v
		end
	end
	return merged
end

return CaveSystem

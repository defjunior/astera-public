-- TerrainFeatures.lua
-- Additional terrain feature samplers for world generation.
-- Each feature has a DefaultConfig table and a sample() function.
-- Follows the same pattern as RiverCarver and PillarMountains.

local noise = math.noise
local abs = math.abs
local clamp = math.clamp
local floor = math.floor
local sqrt = math.sqrt
local exp = math.exp
local sin = math.sin
local cos = math.cos
local max = math.max
local min = math.min
local pi = math.pi

local TerrainFeatures = {}

---------------------------------------------------------------------
-- Utility
---------------------------------------------------------------------
local function hash2(ix, iy, seed)
	local h = noise(ix * 127.1 + seed * 0.01, iy * 311.7 + seed * 0.01, seed * 0.73)
	return (h + 0.5)
end

local function ridgeNoise2D(x, y, scale, seed)
	local v = noise(x / scale, y / scale, seed)
	return 1 - abs(v) * 2
end

local function multiRidge2D(x, y, scale, seed, octaves)
	octaves = octaves or 3
	local value = 0
	local amp = 1
	local freq = 1
	local totalAmp = 0
	for _ = 1, octaves do
		value += amp * ridgeNoise2D(x * freq, y * freq, scale, seed)
		totalAmp += amp
		freq *= 2.0
		amp *= 0.5
	end
	return value / totalAmp
end

---------------------------------------------------------------------
-- 1. CLIFFS
-- Creates vertical cliff faces by noise-gated height snapping.
-- In cliff zones, height is quantized to large steps, producing
-- dramatic vertical walls. Transition is blended smoothly.
---------------------------------------------------------------------
-- NOTE on scales: x, y passed in are CHUNK indices (cellSize ≈ 50 studs).
-- A scale of N here means a noise wavelength of N chunks ≈ N*50 studs.
-- Keep scales in the 30-120 chunk range for features that should be visible
-- across a typical play area (a few thousand studs).

TerrainFeatures.CliffsConfig = {
 -- EXCLUDED: authored content/settings table, at the owner's request.
 -- General structure: feature-specific enablement/noise/scale/strength/height/seed settings
 -- Intentionally empty, not a runnable replacement. See CONTENT-SCHEMAS.md.
}

function TerrainFeatures.sampleCliffs(x, y, seed, config, surfaceY)
	config = config or TerrainFeatures.CliffsConfig
	if not config.Enabled then return surfaceY end
	if surfaceY < config.MinHeight then return surfaceY end

	local gate = noise(x / config.NoiseScale, y / config.NoiseScale, seed + config.NoiseSeed)
	gate = (gate + 1) * 0.5
	if gate < config.NoiseThreshold then return surfaceY end

	local t = (gate - config.NoiseThreshold) / (1 - config.NoiseThreshold)
	t = clamp(t, 0, 1)

	local snapped = floor(surfaceY / config.SnapHeight + 0.5) * config.SnapHeight
	return surfaceY + (snapped - surfaceY) * t * config.Blend
end

---------------------------------------------------------------------
-- 2. FJORDS
-- Deep narrow inlets carved into coastline terrain.
-- Uses domain-warped ridge noise, active only in coastal regions
-- (moderate continentalness).
---------------------------------------------------------------------
TerrainFeatures.FjordsConfig = {
 -- EXCLUDED: authored content/settings table, at the owner's request.
 -- General structure: feature-specific enablement/noise/scale/strength/height/seed settings
 -- Intentionally empty, not a runnable replacement. See CONTENT-SCHEMAS.md.
}

function TerrainFeatures.sampleFjords(x, y, seed, config, surfaceY, continentEval)
	config = config or TerrainFeatures.FjordsConfig
	if not config.Enabled then return 0 end
	if surfaceY < config.MinTerrainHeight then return 0 end

	if continentEval < config.MinContinentEval or continentEval > config.MaxContinentEval then
		return 0
	end

	local seedOff = seed + config.SeedOffset

	local warpX = noise(x / config.WarpScale, y / config.WarpScale, seedOff + 100) * config.WarpStrength
	local warpY = noise(x / config.WarpScale, y / config.WarpScale, seedOff + 200) * config.WarpStrength
	local wx = x + warpX
	local wy = y + warpY

	local ridge = multiRidge2D(wx, wy, config.PrimaryScale, seedOff, 3)
	local sharpRidge = clamp(ridge, 0, 1) ^ config.Sharpness

	if sharpRidge < config.FjordThreshold then return 0 end

	local t = (sharpRidge - config.FjordThreshold) / (1 - config.FjordThreshold)
	t = clamp(t, 0, 1)
	local falloff = 1 - exp(-t / config.EdgeFalloff)

	local coastCenter = (config.MinContinentEval + config.MaxContinentEval) / 2
	local coastRange = (config.MaxContinentEval - config.MinContinentEval) / 2
	local coastDist = abs(continentEval - coastCenter) / max(coastRange, 0.01)
	local coastFactor = clamp(1 - coastDist, 0.3, 1)

	return config.MaxCarveDepth * falloff * coastFactor
end

---------------------------------------------------------------------
-- 3. FLOATING ISLANDS
-- Terrain suspended in air on upper z-layers.
-- Uses grid-based deterministic placement like PillarMountains.
---------------------------------------------------------------------
TerrainFeatures.FloatingIslandsConfig = {
 -- EXCLUDED: authored content/settings table, at the owner's request.
 -- General structure: feature-specific enablement/noise/scale/strength/height/seed settings
 -- Intentionally empty, not a runnable replacement. See CONTENT-SCHEMAS.md.
}

function TerrainFeatures.sampleFloatingIslands(x, y, z, seed, config, terrainStats)
	config = config or TerrainFeatures.FloatingIslandsConfig
	if not config.Enabled then return 0 end
	if z < config.MinZ then return 0 end

	if terrainStats and (terrainStats.peaksEval or 0) < config.MinPeaksEval then
		return 0
	end

	local seedOff = seed + config.SeedOffset
	if config.Mode == "NoiseField" then
		-- A domain-warped 3D density field. X/Y are chunk coordinates and Z
		-- is the generation stratum, so connected positive-density samples
		-- become broad shelves, arches, and hanging masses instead of a grid
		-- of unrelated circular islands.
		local scale = max(1, config.NoiseScale or 34)
		local warpScale = max(1, config.WarpScale or 90)
		local warpStrength = config.WarpStrength or 9
		local verticalScale = max(0.1, config.VerticalScale or 1.8)
		local seedCoord = seedOff * 0.0001
		local warpX = noise(x / warpScale, y / warpScale, seedCoord + 11.7) * warpStrength
		local warpY = noise(x / warpScale, y / warpScale, seedCoord + 29.3) * warpStrength
		local nx = (x + warpX) / scale
		local ny = (y + warpY) / scale
		local nz = (z - config.MinZ) / verticalScale

		local primary = noise(nx, ny, nz + seedCoord)
		local detail = noise(nx * 2.35 + 17.1, ny * 2.35 - 8.4, nz * 1.7 + seedCoord + 41.9)
		local ridgeSource = noise(nx * 0.62 - 31.2, ny * 0.62 + 22.8, nz * 0.8 + seedCoord + 73.1)
		local ridge = 1 - abs(ridgeSource) * 2
		local density = primary
			+ detail * (config.DetailWeight or 0.28)
			+ ridge * (config.RidgeWeight or 0.18)

		local threshold = config.DensityThreshold or 0.08
		local densityCeiling = max(threshold + 0.01, config.DensityCeiling or 0.62)
		local normalized = clamp((density - threshold) / (densityCeiling - threshold), 0, 1)
		if normalized <= 0 then
			return 0, normalized, 0, 0, false
		end

		normalized = normalized ^ (config.DensityExponent or 0.72)
		local macro = (noise(nx * 0.34, ny * 0.34, seedCoord + 101.3) + 0.5)
		local minHeight = config.MinHeight or 110
		local maxHeight = max(minHeight, config.MaxHeight or 360)
		local bonus = minHeight + (maxHeight - minHeight) * clamp(normalized * 0.78 + macro * 0.22, 0, 1)

		local minThickness = config.MinThickness or 28
		local maxThickness = max(minThickness, config.MaxThickness or 135)
		local thickness = minThickness + (maxThickness - minThickness) * normalized
		local yJitter = noise(nx * 1.45 + 5.2, ny * 1.45 - 12.6, nz + seedCoord + 131.7)
			* (config.BaseYVariation or 38)
		return bonus, normalized, thickness, yJitter, true
	end

	local cs = config.CellSize

	local cellX = floor(x / cs)
	local cellY = floor(y / cs)
	local bestHeight = 0

	for dx = -1, 1 do
		for dy = -1, 1 do
			local cx = cellX + dx
			local cy = cellY + dy

			local spawnRoll = hash2(cx, cy, seedOff)
			if spawnRoll > config.SpawnChance then continue end

			local jx = hash2(cx, cy, seedOff + 1) * 2 - 1
			local jy = hash2(cx, cy, seedOff + 2) * 2 - 1
			local centerX = (cx + 0.5 + jx * config.Jitter) * cs
			local centerY = (cy + 0.5 + jy * config.Jitter) * cs

			local ddx = x - centerX
			local ddy = y - centerY
			local dist = sqrt(ddx * ddx + ddy * ddy)

			local radiusHash = hash2(cx, cy, seedOff + 3)
			local radius = config.MinRadius + (config.MaxRadius - config.MinRadius) * radiusHash

			if dist > radius * 1.5 then continue end

			local heightHash = hash2(cx, cy, seedOff + 4)
			local islandY = config.MinHeight + (config.MaxHeight - config.MinHeight) * heightHash

			local t = dist / radius
			local bonus
			if t <= 1.0 then
				bonus = islandY * (1 - t ^ config.FalloffExponent)
			else
				local outerT = (t - 1.0) / 0.5
				bonus = islandY * exp(-outerT * 3)
				if bonus < 1 then bonus = 0 end
			end

			if bonus > bestHeight then
				bestHeight = bonus
			end
		end
	end

	return bestHeight
end

---------------------------------------------------------------------
-- 4. EROSION
-- Natural weathering that smooths terrain toward a regional baseline.
-- In high-erosion zones, surfaceY is pulled toward the broad-scale
-- height (approximated from continentalness), reducing local detail.
---------------------------------------------------------------------
TerrainFeatures.ErosionConfig = {
 -- EXCLUDED: authored content/settings table, at the owner's request.
 -- General structure: feature-specific enablement/noise/scale/strength/height/seed settings
 -- Intentionally empty, not a runnable replacement. See CONTENT-SCHEMAS.md.
}

function TerrainFeatures.sampleErosion(x, y, seed, config, surfaceY, continentEval, contStrength)
	config = config or TerrainFeatures.ErosionConfig
	if not config.Enabled then return 0 end

	local n = noise(x / config.NoiseScale, y / config.NoiseScale, seed + config.NoiseSeed)
	n = (n + 1) * 0.5
	if n < config.NoiseThreshold then return 0 end

	local t = (n - config.NoiseThreshold) / (1 - config.NoiseThreshold)
	t = clamp(t, 0, 1)

	local baseline = max(5, continentEval * (contStrength or 250) * config.BaselineFactor)
	local diff = surfaceY - baseline
	return diff * t * config.Strength
end

---------------------------------------------------------------------
-- 5. DELTAS
-- Fan-shaped sediment deposits where rivers meet low terrain.
-- Flattens height toward sea level using noise-generated fan fingers.
---------------------------------------------------------------------
TerrainFeatures.DeltasConfig = {
 -- EXCLUDED: authored content/settings table, at the owner's request.
 -- General structure: feature-specific enablement/noise/scale/strength/height/seed settings
 -- Intentionally empty, not a runnable replacement. See CONTENT-SCHEMAS.md.
}

function TerrainFeatures.sampleDeltas(x, y, seed, config, surfaceY, riverCarve)
	config = config or TerrainFeatures.DeltasConfig
	if not config.Enabled then return surfaceY end
	if surfaceY > config.MaxTerrainHeight then return surfaceY end

	if config.RequiresRiver and (not riverCarve or riverCarve < 1) then
		return surfaceY
	end

	local fan = 0
	local amp = 1
	local freq = 1
	local totalAmp = 0
	for _ = 1, config.FanOctaves do
		fan += amp * noise(x * freq / config.FanScale, y * freq / config.FanScale, seed + config.FanSeed)
		totalAmp += amp
		freq *= 2.2
		amp *= 0.4
	end
	fan = (fan / totalAmp + 1) * 0.5

	local strength = config.FlattenStrength * fan
	return surfaceY + (config.TargetHeight - surfaceY) * strength
end

---------------------------------------------------------------------
-- 6. MOUNTAIN RANGES
-- Connected chains of mountains using directional/anisotropic
-- ridge noise. Produces elongated ridges along a preferred direction.
---------------------------------------------------------------------
TerrainFeatures.MountainRangesConfig = {
 -- EXCLUDED: authored content/settings table, at the owner's request.
 -- General structure: feature-specific enablement/noise/scale/strength/height/seed settings
 -- Intentionally empty, not a runnable replacement. See CONTENT-SCHEMAS.md.
}

function TerrainFeatures.sampleMountainRanges(x, y, seed, config, continentEval)
	config = config or TerrainFeatures.MountainRangesConfig
	if not config.Enabled then return 0 end

	if continentEval < config.MinContinentEval then return 0 end

	local seedOff = seed + config.SeedOffset
	local ca = cos(config.DirectionAngle)
	local sa = sin(config.DirectionAngle)

	local rx = (x * ca + y * sa) / config.Anisotropy
	local ry = (-x * sa + y * ca)

	local ridge1 = ridgeNoise2D(rx, ry, config.PrimaryScale, seedOff)
	local ridge2 = ridgeNoise2D(rx * 1.5 + 100, ry * 1.5 + 100, config.SecondaryScale, seedOff + 1)

	local combined = ridge1 * 0.7 + ridge2 * 0.3

	if combined < config.RidgeThreshold then return 0 end

	local t = (combined - config.RidgeThreshold) / (1 - config.RidgeThreshold)
	t = clamp(t, 0, 1) ^ config.BlendPower

	local rampWidth = config.ContinentRampWidth or 0.5
	local contScale = clamp((continentEval - config.MinContinentEval) / rampWidth, 0, 1)

	return (config.MinHeightBonus + (config.MaxHeightBonus - config.MinHeightBonus) * t) * contScale
end

---------------------------------------------------------------------
-- 7. PLATEAUS
-- Flat-topped elevated terrain (mesas/buttes).
-- Uses a core/edge split: the interior is fully flat at the plateau
-- cap height, and a narrow cliff band at the boundary ramps steeply
-- from surrounding terrain up to the mesa top.
---------------------------------------------------------------------
TerrainFeatures.PlateausConfig = {
 -- EXCLUDED: authored content/settings table, at the owner's request.
 -- General structure: feature-specific enablement/noise/scale/strength/height/seed settings
 -- Intentionally empty, not a runnable replacement. See CONTENT-SCHEMAS.md.
}

function TerrainFeatures.samplePlateaus(x, y, seed, config, surfaceY, continentEval)
	config = config or TerrainFeatures.PlateausConfig
	if not config.Enabled then return surfaceY end

	if continentEval < config.MinContinentEval then return surfaceY end

	local n = noise(x / config.NoiseScale, y / config.NoiseScale, seed + config.NoiseSeed)
	n = (n + 1) * 0.5

	if n < config.NoiseThreshold then return surfaceY end

	-- Height: very slow-varying so the flat top is uniform across the plateau
	local hMult = config.HeightScaleMult or 4
	local heightN = noise(x / (config.NoiseScale * hMult), y / (config.NoiseScale * hMult), seed + config.NoiseSeed + 50)
	heightN = (heightN + 1) * 0.5
	local plateauHeight = config.MinPlateauHeight + (config.MaxPlateauHeight - config.MinPlateauHeight) * heightN

	-- Distance from boundary, normalized [0 = at boundary, 1 = deep inside]
	local edgeT = (n - config.NoiseThreshold) / (1 - config.NoiseThreshold)
	edgeT = clamp(edgeT, 0, 1)

	-- Core/edge split: narrow cliff ramp at the boundary, flat top inside
	local edgeWidth = config.EdgeWidth or 0.15
	local sharpness = config.EdgeSharpness or 3.0
	local blend
	if edgeT >= edgeWidth then
		blend = 1.0 -- flat mesa top
	else
		-- Cliff ramp: concave rise (steep wall, quick to reach the top)
		local ramp = edgeT / edgeWidth
		blend = ramp ^ (1 / max(sharpness, 0.01))
	end

	-- Flatten toward plateauHeight in both directions: lift valleys AND
	-- push down mountain peaks so the mesa top is truly flat.
	return surfaceY + (plateauHeight - surfaceY) * blend * (config.BlendStrength or 1.0)
end

---------------------------------------------------------------------
-- 8. DUNES
-- Sand dune formations using asymmetric directional waves.
-- Gentle windward slope, steep leeward face, with noise perturbation.
---------------------------------------------------------------------
TerrainFeatures.DunesConfig = {
 -- EXCLUDED: authored content/settings table, at the owner's request.
 -- General structure: feature-specific enablement/noise/scale/strength/height/seed settings
 -- Intentionally empty, not a runnable replacement. See CONTENT-SCHEMAS.md.
}

function TerrainFeatures.sampleDunes(x, y, seed, config, moisture)
	config = config or TerrainFeatures.DunesConfig
	if not config.Enabled then return 0 end

	if moisture and moisture > config.MaxMoisture then return 0 end

	local seedOff = seed + config.SeedOffset
	local ca = cos(config.WindAngle)
	local sa = sin(config.WindAngle)

	local windX = x * ca + y * sa
	local crossX = -x * sa + y * ca

	local pertX = noise(x / config.PerturbScale, y / config.PerturbScale, seedOff) * config.PerturbStrength
	local pertY = noise(x / config.PerturbScale, y / config.PerturbScale, seedOff + 1) * config.PerturbStrength
	windX = windX + pertX
	crossX = crossX + pertY

	local phase1 = (windX / config.PrimaryWavelength) * 2 * pi
	local wave1 = sin(phase1)
	if wave1 > 0 then
		wave1 = wave1 ^ (1 - config.Asymmetry * 0.5)
	else
		wave1 = -(abs(wave1) ^ (1 + config.Asymmetry))
	end

	local phase2 = (crossX / config.SecondaryWavelength) * 2 * pi
	local wave2 = sin(phase2)

	return wave1 * config.PrimaryAmplitude + wave2 * config.SecondaryAmplitude
end

---------------------------------------------------------------------
-- 9. SOUNDS
-- Narrow water passages carved between landmasses.
-- Directional ridge noise channels along coastlines.
---------------------------------------------------------------------
TerrainFeatures.SoundsConfig = {
 -- EXCLUDED: authored content/settings table, at the owner's request.
 -- General structure: feature-specific enablement/noise/scale/strength/height/seed settings
 -- Intentionally empty, not a runnable replacement. See CONTENT-SCHEMAS.md.
}

function TerrainFeatures.sampleSounds(x, y, seed, config, surfaceY, continentEval)
	config = config or TerrainFeatures.SoundsConfig
	if not config.Enabled then return 0 end
	if surfaceY < config.MinTerrainHeight then return 0 end

	if continentEval < config.MinContinentEval or continentEval > config.MaxContinentEval then
		return 0
	end

	local seedOff = seed + config.SeedOffset

	local ca = cos(config.DirectionAngle)
	local sa = sin(config.DirectionAngle)
	local rx = x * ca + y * sa
	local ry = (-x * sa + y * ca) * config.Anisotropy

	local warpX = noise(rx / config.WarpScale, ry / config.WarpScale, seedOff + 100) * config.WarpStrength
	local warpY = noise(rx / config.WarpScale, ry / config.WarpScale, seedOff + 200) * config.WarpStrength
	local wx = rx + warpX
	local wy = ry + warpY

	local ridge = multiRidge2D(wx, wy, config.PrimaryScale, seedOff, 3)
	local sharpRidge = clamp(ridge, 0, 1) ^ config.Sharpness

	if sharpRidge < config.SoundThreshold then return 0 end

	local t = (sharpRidge - config.SoundThreshold) / (1 - config.SoundThreshold)
	t = clamp(t, 0, 1)
	local falloff = 1 - exp(-t / config.EdgeFalloff)

	local coastCenter = (config.MinContinentEval + config.MaxContinentEval) / 2
	local coastRange = (config.MaxContinentEval - config.MinContinentEval) / 2
	local coastDist = abs(continentEval - coastCenter) / max(coastRange, 0.01)
	local coastFactor = clamp(1 - coastDist, 0.2, 1)

	return config.MaxCarveDepth * falloff * coastFactor
end

---------------------------------------------------------------------
-- Config lookup helper for BiomeResolver merging
---------------------------------------------------------------------
local CONFIG_MAP = {
	cliffs = "CliffsConfig",
	fjords = "FjordsConfig",
	floatingIslands = "FloatingIslandsConfig",
	erosion = "ErosionConfig",
	deltas = "DeltasConfig",
	mountainRanges = "MountainRangesConfig",
	plateaus = "PlateausConfig",
	dunes = "DunesConfig",
	sounds = "SoundsConfig",
}

function TerrainFeatures.getDefaultConfig(featureName)
	local key = CONFIG_MAP[featureName]
	return key and TerrainFeatures[key] or nil
end

return TerrainFeatures

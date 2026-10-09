-- PillarMountains.lua
-- Generates tall narrow pillar/karst mountains using Voronoi cell distance.
-- Each pillar center is deterministically placed on a jittered grid.
-- Height bonus decays sharply with distance from center, producing steep columns.

local noise = math.noise
local abs = math.abs
local clamp = math.clamp
local floor = math.floor
local sqrt = math.sqrt
local exp = math.exp

local PillarMountains = {}

PillarMountains.DefaultConfig = {
 -- EXCLUDED: authored content/settings table, at the owner's request.
 -- General structure: pillar noise settings: enablement, scale, thresholds, strength and seed offsets
 -- Intentionally empty, not a runnable replacement. See CONTENT-SCHEMAS.md.
}

-- Deterministic hash for pillar properties per cell
local function hash2(ix, iy, seed)
	-- Use math.noise as a hash (it's deterministic)
	local h = noise(ix * 127.1 + seed * 0.01, iy * 311.7 + seed * 0.01, seed * 0.73)
	return (h + 0.5) -- shift to ~[0, 1]
end

-- Sample pillar height bonus at world position (x, y)
-- terrainStats should contain peaksEval and continentEval from HeightSampler
function PillarMountains.sample(x, y, seed, config, terrainStats)
	config = config or PillarMountains.DefaultConfig
	local seedOff = seed + config.SeedOffset
	local cs = config.CellSize

	-- Check if terrain conditions allow pillars
	if terrainStats then
		if (terrainStats.peaksEval or 0) < config.MinPeaksEval then
			return 0
		end
		if (terrainStats.continentEval or 0) < config.MinContinentEval then
			return 0
		end
	end

	-- Find which grid cell we're in
	local cellX = floor(x / cs)
	local cellY = floor(y / cs)

	-- Check 3x3 neighborhood (a pillar in an adjacent cell might reach here)
	local bestHeight = 0

	for dx = -1, 1 do
		for dy = -1, 1 do
			local cx = cellX + dx
			local cy = cellY + dy

			-- Deterministic spawn check
			local spawnRoll = hash2(cx, cy, seedOff)
			if spawnRoll > config.SpawnChance then
				continue
			end

			-- Jittered pillar center
			local jx = hash2(cx, cy, seedOff + 1) * 2 - 1 -- [-1, 1]
			local jy = hash2(cx, cy, seedOff + 2) * 2 - 1
			local centerX = (cx + 0.5 + jx * config.Jitter) * cs
			local centerY = (cy + 0.5 + jy * config.Jitter) * cs

			-- Distance from this point to pillar center
			local ddx = x - centerX
			local ddy = y - centerY
			local dist = sqrt(ddx * ddx + ddy * ddy)

			-- Per-pillar height variation
			local heightHash = hash2(cx, cy, seedOff + 3)
			local pillarHeight = config.MinHeight + (config.MaxHeight - config.MinHeight) * heightHash

			-- Per-pillar radius variation
			local radiusHash = hash2(cx, cy, seedOff + 4)
			local pillarRadius = config.BaseRadius * (0.6 + radiusHash * 0.8)

			-- Compute height falloff
			local t = dist / pillarRadius
			if t > 2.0 then continue end -- too far, skip

			local heightBonus
			if t <= 1.0 then
				-- Inside the pillar: mostly flat top with slight dome
				local plateauT = t * (1 - config.PlateauWidening) + config.PlateauWidening
				heightBonus = pillarHeight * (1 - plateauT ^ config.FalloffExponent)
			else
				-- Outside: steep falloff
				local outerT = (t - 1.0)
				heightBonus = pillarHeight * exp(-outerT * config.FalloffExponent * 2)
				-- Rapid decay past the edge
				if heightBonus < 1 then heightBonus = 0 end
			end

			if heightBonus > bestHeight then
				bestHeight = heightBonus
			end
		end
	end

	return bestHeight
end

-- Is this point on top of a pillar? (for decoration decisions)
function PillarMountains.isOnPillar(x, y, seed, config, terrainStats)
	return PillarMountains.sample(x, y, seed, config, terrainStats) > 20
end

return PillarMountains

-- RiverCarver.lua
-- Generates river channels by domain-warped ridge noise.
-- Returns a carve depth at any (x, y) world position.
-- Rivers follow valleys naturally because the carve is strongest
-- where the base height is low (blended with erosion).

local noise = math.noise
local abs = math.abs
local clamp = math.clamp
local exp = math.exp

local RiverCarver = {}

-- Default river config (can be overridden per-biome)
RiverCarver.DefaultConfig = {
 -- EXCLUDED: authored content/settings table, at the owner's request.
 -- General structure: river settings: enablement, scale, width/depth, warp and seed offsets
 -- Intentionally empty, not a runnable replacement. See CONTENT-SCHEMAS.md.
}

-- Compute a ridge noise value (sharp peaks along zero-crossings)
local function ridgeNoise(x, y, scale, seed)
	local v = noise(x / scale, y / scale, seed)
	-- Fold into ridge: 1 at zero-crossings, 0 at extremes
	return 1 - abs(v) * 2
end

-- Multi-octave ridge noise for river path
local function riverRidge(x, y, scale, seed, octaves)
	octaves = octaves or 3
	local value = 0
	local amp = 1
	local freq = 1
	local totalAmp = 0
	for _ = 1, octaves do
		value += amp * ridgeNoise(x * freq, y * freq, scale, seed)
		totalAmp += amp
		freq *= 2.1
		amp *= 0.45
	end
	return value / totalAmp
end

-- Sample the river carve depth at world position (x, y)
-- Returns: carveDepth (0 = no river, >0 = dig this many studs)
function RiverCarver.sample(x, y, seed, config, terrainHeight)
	config = config or RiverCarver.DefaultConfig
	local seedOff = seed + config.SeedOffset

	-- Skip if terrain is too low for rivers
	if terrainHeight and terrainHeight < config.MinTerrainHeight then
		return 0
	end

	-- Domain warp: offset sampling position to create meandering paths
	local warpX = noise(x / config.WarpScale, y / config.WarpScale, seedOff + 100) * config.WarpStrength
	local warpY = noise(x / config.WarpScale, y / config.WarpScale, seedOff + 200) * config.WarpStrength
	local wx = x + warpX
	local wy = y + warpY

	-- Primary river ridge
	local ridge = riverRidge(wx, wy, config.PrimaryScale, seedOff, 3)

	-- Sharpen the ridge into a thin channel
	local sharpRidge = clamp(ridge, 0, 1)
	sharpRidge = sharpRidge ^ config.Sharpness

	-- Only carve where ridge exceeds threshold
	if sharpRidge < config.RiverThreshold then
		return 0
	end

	-- Normalize to [0, 1] above threshold
	local t = (sharpRidge - config.RiverThreshold) / (1 - config.RiverThreshold)
	t = clamp(t, 0, 1)

	-- Smooth falloff at edges
	local falloff = 1 - exp(-t / config.EdgeFalloff)

	-- Scale carve depth by terrain height (deeper rivers in higher terrain)
	local heightScale = 1
	if terrainHeight then
		heightScale = clamp(terrainHeight / 100, 0.3, 1.5)
	end

	return config.MaxCarveDepth * falloff * heightScale
end

-- Convenience: does a river exist at this position? (for decoration decisions)
function RiverCarver.isRiver(x, y, seed, config, terrainHeight)
	return RiverCarver.sample(x, y, seed, config, terrainHeight) > 2
end

return RiverCarver

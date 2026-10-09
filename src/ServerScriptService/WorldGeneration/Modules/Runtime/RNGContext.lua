--!strict
-- Hierarchical seeded RNG for world generation.
--
-- Every random draw in the gen pipeline should flow from a named path so that
-- (1) mainland terrain is bit-identical across servers from a shared WorldSeed
-- and (2) skylist / prop variation flows from a per-server ServerSeed without
-- ever contaminating mainland determinism. See memory/project_worldgen_direction.md.
--
-- Usage:
--   local root = RNGContext.new(state.WorldSeed, "world")
--   local islandCtx = root:derive("series", 3):derive("island", 2)
--   local heightCtx = islandCtx:derive("mainland", "heightfield")
--   local r = heightCtx:random()           -- Random instance, cached
--   local y = r:NextNumber(0, 1)
--   local noiseSeed = heightCtx:seed()     -- raw int for sampleMap / Perlin
--
-- Path labels may be strings or integers. Strings are hashed via djb2 with
-- bit32 clamping so results stay inside the safe double range.

local RNGContext = {}
RNGContext.__index = RNGContext

local INT_MIN = -2147483648
local INT_MAX = 2147483647
local U32_MASK = 0xFFFFFFFF

local function hashLabel(label: any): number
	if type(label) == "number" then
		return bit32.band(math.floor(label), U32_MASK)
	end
	if type(label) ~= "string" then
		error("RNGContext: label must be string or number, got " .. type(label), 3)
	end
	local acc = 5381
	for i = 1, #label do
		acc = bit32.band(acc * 33 + string.byte(label, i), U32_MASK)
	end
	return acc
end

local function mixSeed(seed: number, label: any): number
	local labelHash = hashLabel(label)
	-- Two-step mix via Roblox's own deterministic RNG. Platform-stable and
	-- avoids hand-rolled 64-bit arithmetic that would overflow doubles.
	local step1 = Random.new(seed):NextInteger(INT_MIN, INT_MAX)
	return Random.new(step1 + labelHash):NextInteger(INT_MIN, INT_MAX)
end

function RNGContext.new(rootSeed: number, rootPath: string?)
	local self = setmetatable({}, RNGContext)
	self._seed = bit32.band(math.floor(rootSeed), U32_MASK)
	self._path = rootPath or "root"
	self._random = nil
	return self
end

function RNGContext:derive(...)
	local seed = self._seed
	local path = self._path
	local n = select("#", ...)
	for i = 1, n do
		local label = select(i, ...)
		seed = mixSeed(seed, label)
		path = path .. "/" .. tostring(label)
	end
	local child = setmetatable({}, RNGContext)
	child._seed = seed
	child._path = path
	child._random = nil
	return child
end

function RNGContext:seed(): number
	return self._seed
end

function RNGContext:path(): string
	return self._path
end

function RNGContext:random(): Random
	if not self._random then
		self._random = Random.new(self._seed)
	end
	return self._random
end

function RNGContext:nextNumber(min: number?, max: number?): number
	if min == nil then
		return self:random():NextNumber()
	end
	return self:random():NextNumber(min, max or 1)
end

function RNGContext:nextInteger(min: number, max: number): number
	return self:random():NextInteger(min, max)
end

-- Reseeds the cached Random instance. Use sparingly — e.g. if a loop needs
-- a fresh stream from the same logical path, derive a child with an index
-- instead of rewinding.
function RNGContext:reset()
	self._random = nil
end

return RNGContext

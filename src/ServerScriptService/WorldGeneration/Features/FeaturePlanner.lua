-- Partial source showcase, revised October 8, 2026.
-- Feature planning interface. Accepts regional requests; candidate policy and cached planning are private.
-- Basic finite-value, rectangle-overlap and region-bounds helpers are real. Candidate generation, ranking, rejection, indexing and caches remain private.
-- Real excerpts are marked. Other named interfaces are non-working stubs, not a replacement pipeline.

local FeaturePlanner = {}

-- Real source excerpt: finiteNumber
local function finiteNumber(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

-- Real source excerpt: intersects
local function intersects(a, b): boolean
	return a.min.X < b.max.X and a.max.X > b.min.X
		and a.min.Y < b.max.Y and a.max.Y > b.min.Y
		and a.min.Z < b.max.Z and a.max.Z > b.min.Z
end

-- Real source excerpt: regionBounds
local function regionBounds(x: number, z: number, size: number)
	local min = Vector3.new(x * size, -FeatureConfig.Geometry.MaxPartAxisStuds * 16, z * size)
	local max = Vector3.new((x + 1) * size, FeatureConfig.Geometry.MaxPartAxisStuds * 16, (z + 1) * size)
	return { min = min, max = max }
end

-- Contract: Feature planning interface. Implementation intentionally unavailable.
function FeaturePlanner.PlanRegion(regionX, regionZ, context)
	-- full method is omitted
end

return table.freeze(FeaturePlanner)

-- Partial source showcase, revised October 8, 2026.
-- Map-sampling interface. Provides named sampler families; exact sampling implementations are private.
-- Small interpolation/clamping helpers are real. Sampler families remain named boundaries: this does not reveal seeded noise composition, defaults or how world elevation combines them.
-- Real excerpts are marked. Other named interfaces are non-working stubs, not a replacement pipeline.

local Maps = {}

-- Real source excerpt: lerp
local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Real source excerpt: clamp
local function clamp(x: number, a: number, b: number): number
	if x < a then return a end
	if x > b then return b end
	return x
end

-- Real source excerpt: isign
local function isign(x: number): number
	return (x < 0) and -1 or 1
end

-- Contract: Map-sampling interface. Implementation intentionally unavailable.
function Maps.Perlin2D(params)
	-- full method is omitted
end

-- Contract: Map-sampling interface. Implementation intentionally unavailable.
function Maps.Perlin3D(params)
	-- full method is omitted
end

-- Contract: Map-sampling interface. Implementation intentionally unavailable.
function Maps.Gaussian2D(params)
	-- full method is omitted
end

-- Contract: Map-sampling interface. Implementation intentionally unavailable.
function Maps.Worms2D(params)
	-- full method is omitted
end

-- Contract: Map-sampling interface. Implementation intentionally unavailable.
function Maps.Cellular2D(params)
	-- full method is omitted
end

-- Contract: Map-sampling interface. Implementation intentionally unavailable.
function Maps.DiamondSquare2D(params)
	-- full method is omitted
end

-- Contract: Map-sampling interface. Implementation intentionally unavailable.
function Maps.Maze2D(params)
	-- full method is omitted
end

return Maps

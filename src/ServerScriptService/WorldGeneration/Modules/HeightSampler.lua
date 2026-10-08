-- Partial source showcase, revised October 8, 2026.
-- Elevation query interface. Returns terrain-height information; sampling composition and caching are private.
-- This boundary shows where requests enter and results leave the subsystem.
-- The private policy decides what work to accept and when to publish it; no execution recipe is exposed.
-- Real local helpers are shown; remaining interfaces are documentation stubs, not a working replacement.

local HeightSampler = {}

local Spline = require(script.Parent.Spline) -- source dependency

-- Real source excerpt: buildSplines
local function buildSplines(curves)
	local continentalCurve = curves and curves.Continentalness or {}
	local erosionCurve = curves and curves.Erosion or {}
	local peaksCurve = curves and curves.PeaksValleys or {}

	return {
		continent = Spline.new(continentalCurve),
		erosion = Spline.new(erosionCurve),
		peaks = Spline.new(peaksCurve),
	}
end

-- Contract: Elevation query interface. Implementation intentionally unavailable.
function HeightSampler.clearCache()
	-- full method is omitted
end

-- Contract: Elevation query interface. Implementation intentionally unavailable.
function HeightSampler.computeSurfaceY(x, y, z, state, config, surfaceYManager)
	-- full method is omitted
end

return HeightSampler

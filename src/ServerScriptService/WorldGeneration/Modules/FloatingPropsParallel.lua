-- Partial source showcase, revised October 8, 2026.
-- Floating decoration interface. Accepts placement requests; parallel placement implementation is private.
-- This boundary shows where requests enter and results leave the subsystem.
-- The private policy decides what work to accept and when to publish it; no execution recipe is exposed.
-- Real local helpers are shown; remaining interfaces are documentation stubs, not a working replacement.

local FloatingProps = {}

local placedPositions = {} -- placement lifecycle omitted

-- Real source excerpt: isTooClose
local function isTooClose(pos, spacing)
	if type(placedPositions) ~= "table" then
		placedPositions = _G.PlacedFloating
	end
	if type(placedPositions) ~= "table" then
		placedPositions = {}
		_G.PlacedFloating = placedPositions
	end
	for _, p in ipairs(placedPositions) do
		if (p - pos).Magnitude < spacing * 2 then
			return true
		end
	end
	return false
end

-- Real source excerpt: addPlacedPosition
local function addPlacedPosition(pos)
	table.insert(placedPositions, pos)
end

-- Contract: Floating decoration interface. Implementation intentionally unavailable.
function FloatingProps.placeFloatingDecoration(propsTable, originPosition, searchRadius, verticalOffset, shouldRotate, spacing, config)
	-- full method is omitted
end

return FloatingProps

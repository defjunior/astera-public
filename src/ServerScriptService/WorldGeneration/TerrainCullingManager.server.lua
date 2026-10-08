-- Partial source showcase, revised October 8, 2026.
-- Terrain lifecycle boundary. Controls visibility/lifetime integration; culling policy is private.
-- This boundary shows where requests enter and results leave the subsystem.
-- The private policy decides what work to accept and when to publish it; no execution recipe is exposed.
-- Real local helpers are shown; remaining interfaces are documentation stubs, not a working replacement.

-- Original runtime script intentionally does not start generation here.
-- Real source excerpt: preservesFeatureGeometry
local function preservesFeatureGeometry(part: Instance): boolean
	local ancestor = part.Parent
	while ancestor do
		if ancestor:GetAttribute("WorldFeatureCarved") == true
			or ancestor:GetAttribute("WorldFeatureServiceOwned") == true then
			return true
		end
		ancestor = ancestor.Parent
	end
	return false
end

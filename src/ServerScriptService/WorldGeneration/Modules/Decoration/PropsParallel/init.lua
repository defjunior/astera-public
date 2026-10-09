-- Partial source showcase, revised October 8, 2026.
-- Prop placement interface. Connects placement requests to world geometry; worker and placement implementation is private.
-- Model scaling and a tagged-part query are real. Worker dispatch, point sampling, reservations, synchronization policy and variant recoloring remain omitted.
-- Real excerpts are marked. Other named interfaces are non-working stubs, not a replacement pipeline.

local PropBrush = {}

-- Real source excerpt: scaleModel
local function scaleModel(model, scaleFactor)

	model:ScaleTo(scaleFactor)
end

-- Real source excerpt: isMicroTerrainPart
local function isMicroTerrainPart(instance)
	while instance do
		if instance:GetAttribute("MicroTerrain") == true then
			return true
		end
		instance = instance.Parent
	end
	return false
end

-- Real source excerpt: parseChunkName
local function parseChunkName(cname)
	if type(cname) ~= "string" then
		return nil
	end
	local split = string.split(cname, ".")
	if #split < 3 then
		return nil
	end
	local x = tonumber(split[1])
	local y = tonumber(split[2])
	local z = tonumber(split[3])
	if x == nil or y == nil or z == nil then
		return nil
	end
	return x, y, z
end

-- Real source excerpt: isTooClose
local function isTooClose(pos, spacing, placedPositions)
	for _, p in ipairs(placedPositions) do
		if (p - pos).Magnitude < spacing * 1 then
			return true
		end
	end
	return false
end

-- Real source excerpt: addPlacedPosition
local function addPlacedPosition(pos, placedPositions)
	table.insert(placedPositions, pos)
end

-- Contract: Prop placement interface. Implementation intentionally unavailable.
function PropBrush.GenerateCandidatePoints(center, brushRadius, spacing, cluster)
	-- full method is omitted
end

-- Contract: Prop placement interface. Implementation intentionally unavailable.
function PropBrush.PlaceProps(cname, random, models, brushSettings, candidatePoints, offset, z, terrainModel, variantCfg)
	-- full method is omitted
end

-- Contract: Prop placement interface. Implementation intentionally unavailable.
function PropBrush.FullPlace(cname, parent, random, center, brushRadius, spacing, mTerms, offset, zHeight, variantCfg)
	-- full method is omitted
end

return PropBrush

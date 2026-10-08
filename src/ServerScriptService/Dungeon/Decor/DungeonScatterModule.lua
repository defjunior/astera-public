local DungeonSurfacePlacementModule = require(script.Parent.DungeonSurfacePlacementModule)

local DungeonScatterModule = {}

local function shuffle(rng, list)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

local function farEnough(placed, candidate, minSpacing)
	for _, pos in ipairs(placed) do
		local dx = pos.x - candidate.x
		local dz = pos.z - candidate.z
		if (dx * dx + dz * dz) < (minSpacing * minSpacing) then
			return false
		end
	end
	return true
end

local function buildPlacement(profile, cell, spec)
	local mapped = profile.localToGrid(cell)
	local offsetX = (mapped.localOffset and mapped.localOffset.x) or 0
	local offsetZ = (mapped.localOffset and mapped.localOffset.z) or 0
	if spec.localOffset then
		offsetX += spec.localOffset.x
		offsetZ += spec.localOffset.z
	end
	local placement = {
		tileId = spec.tileId,
		tileCategory = spec.tileCategory,
		tags = spec.tags,
		prefabId = spec.prefabId,
		prefabCandidates = spec.prefabCandidates,
		localPos = { x = cell.x, z = cell.z },
		gridPos = {
			x = mapped.x,
			y = mapped.y,
			z = mapped.z,
		},
		localOffset = {
			x = offsetX,
			z = offsetZ,
		},
		subgridPos = {
			x = (mapped.subgrid and mapped.subgrid.x) or cell.x,
			z = (mapped.subgrid and mapped.subgrid.z) or cell.z,
		},
		orientation = spec.orientation or "North",
		yawDegrees = spec.yawDegrees,
		allowCellSharing = spec.allowCellSharing == true,
		footprint = spec.footprint,
	}
	if type(spec.surfaceSnap) == "string" then
		placement.surfaceSnap = spec.surfaceSnap
	end
	if spec.instanceAttributes then
		placement.instanceAttributes = spec.instanceAttributes
	end
	if spec.visual then
		placement.visual = spec.visual
	end
	return placement
end

function DungeonScatterModule.PlaceScatter(state, rng, profile, spec)
	local countMin = math.max(0, math.floor(spec.countMin or 0))
	local countMax = math.max(countMin, math.floor(spec.countMax or countMin))
	local targetCount = rng:NextInteger(countMin, countMax)
	if targetCount <= 0 then
		return {}
	end

	local footprint = spec.footprint or { w = 1, d = 1 }
	local rules = spec.rules or {}
	local candidates = DungeonSurfacePlacementModule.FindCandidates(state, footprint, rules)
	if #candidates == 0 then
		return {}
	end

	shuffle(rng, candidates)

	local placedLocal = {}
	local out = {}
	local minSpacing = math.max(0, tonumber(spec.minSpacing) or 0)

	for _, candidate in ipairs(candidates) do
		if #out >= targetCount then
			break
		end
		if minSpacing <= 0 or farEnough(placedLocal, candidate, minSpacing) then
			local localOffset = nil
			if spec.allowCellSharing == true then
				local jitter = tonumber(spec.jitter) or 0.28
				localOffset = {
					x = rng:NextNumber(-jitter, jitter),
					z = rng:NextNumber(-jitter, jitter),
				}
			end

			local placement = buildPlacement(profile, candidate, {
				tileId = spec.tileId,
				tileCategory = spec.tileCategory,
				tags = spec.tags,
				prefabId = spec.prefabId,
				prefabCandidates = spec.prefabCandidates,
				footprint = footprint,
				orientation = spec.orientation,
				yawDegrees = (type(spec.yawDegrees) == "number" and spec.yawDegrees)
					or (type(spec.yawDegrees) == "table" and rng:NextNumber(spec.yawDegrees.min or 0, spec.yawDegrees.max or 360))
					or nil,
				localOffset = localOffset,
				allowCellSharing = spec.allowCellSharing == true,
				surfaceSnap = spec.surfaceSnap,
				instanceAttributes = spec.instanceAttributes,
				visual = spec.visual,
			})
			DungeonSurfacePlacementModule.AddPlacement(state, placement, footprint, spec.reserveTag or "scatter")
			out[#out + 1] = placement
			placedLocal[#placedLocal + 1] = candidate
		end
	end

	return out
end

return DungeonScatterModule

local DungeonSurfacePlacementModule = require(script.Parent.DungeonSurfacePlacementModule)

local DungeonMessPileModule = {}

local function buildPlacement(profile, x, z, spec, localOffset)
	local placement = {
		tileId = spec.tileId,
		tileCategory = spec.tileCategory,
		tags = spec.tags,
		prefabId = spec.prefabId,
		prefabCandidates = spec.prefabCandidates,
		localPos = { x = x, z = z },
		gridPos = profile.localToGrid({ x = x, z = z }),
		orientation = spec.orientation or "North",
		allowCellSharing = spec.allowCellSharing == true,
	}
	if localOffset then
		placement.localOffset = localOffset
	end
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

local function chooseAnchor(state, rng, anchorCandidates)
	if type(anchorCandidates) == "table" and #anchorCandidates > 0 then
		return anchorCandidates[rng:NextInteger(1, #anchorCandidates)]
	end
	local available = DungeonSurfacePlacementModule.FindCandidates(state, { w = 1, d = 1 }, {
		requireSurface = "floor",
		allowNavigation = false,
		allowDoors = false,
	})
	if #available == 0 then
		return nil
	end
	return available[rng:NextInteger(1, #available)]
end

local function canPlaceAt(
	state,
	x,
	z,
	allowCellSharing,
	requireSurface,
	allowNavigation,
	navigationClearanceSubcells,
	doorClearanceSubcells
)
	return DungeonSurfacePlacementModule.CanPlace(state, x, z, { w = 1, d = 1 }, {
		requireSurface = requireSurface or "floor",
		allowNavigation = allowNavigation == true,
		allowDoors = false,
		allowSoftOverlap = allowCellSharing == true,
		navigationClearanceSubcells = navigationClearanceSubcells,
		doorClearanceSubcells = doorClearanceSubcells,
	})
end

local function buildClusterCandidates(
	state,
	anchor,
	radius,
	allowCellSharing,
	requireSurface,
	allowNavigation,
	navigationClearanceSubcells,
	doorClearanceSubcells
)
	local out = {}
	local maxRadius = math.max(1, math.ceil(tonumber(radius) or 1))
	for x = math.max(1, anchor.x - maxRadius), math.min(state.width, anchor.x + maxRadius) do
		for z = math.max(1, anchor.z - maxRadius), math.min(state.depth, anchor.z + maxRadius) do
			local dx = x - anchor.x
			local dz = z - anchor.z
			local dist2 = (dx * dx) + (dz * dz)
			if dist2 <= (maxRadius * maxRadius)
				and canPlaceAt(
					state,
					x,
					z,
					allowCellSharing,
					requireSurface,
					allowNavigation,
					navigationClearanceSubcells,
					doorClearanceSubcells
				)
			then
				-- Heavy center bias to keep piles coherent and avoid flat, uniform spread.
				local weight = 1 / (1 + dist2)
				out[#out + 1] = {
					x = x,
					z = z,
					weight = weight,
				}
			end
		end
	end
	return out
end

local function pickWeightedIndex(rng, candidates)
	local total = 0
	for _, item in ipairs(candidates) do
		total += math.max(0.0001, tonumber(item.weight) or 0.0001)
	end
	if total <= 0 then
		return nil
	end

	local roll = rng:NextNumber(0, total)
	local cursor = 0
	for i, item in ipairs(candidates) do
		cursor += math.max(0.0001, tonumber(item.weight) or 0.0001)
		if roll <= cursor then
			return i
		end
	end
	return #candidates
end

local function placeFillers(state, rng, profile, anchor, filler)
	local placements = {}
	local countMin = math.max(0, math.floor(tonumber(filler.countMin) or 0))
	local countMax = math.max(countMin, math.floor(tonumber(filler.countMax) or countMin))
	local targetCount = (countMax > 0) and rng:NextInteger(countMin, countMax) or 0
	if targetCount <= 0 then
		return placements
	end

	local allowCellSharing = filler.allowCellSharing == true
	local radius = tonumber(filler.radius) or 1
	local candidates = buildClusterCandidates(
		state,
		anchor,
		radius,
		allowCellSharing,
		filler.requireSurface,
		filler.allowNavigation,
		filler.navigationClearanceSubcells,
		filler.doorClearanceSubcells
	)
	if #candidates <= 0 then
		return placements
	end

	local jitter = tonumber(filler.jitter) or 0
	for _ = 1, targetCount do
		if #candidates <= 0 then
			break
		end
		local pickIndex = pickWeightedIndex(rng, candidates)
		if not pickIndex then
			break
		end
		local pick = table.remove(candidates, pickIndex)
		local localOffset = nil
		if allowCellSharing and jitter > 0 then
			localOffset = {
				x = rng:NextNumber(-jitter, jitter),
				z = rng:NextNumber(-jitter, jitter),
			}
		end

		local placement = buildPlacement(profile, pick.x, pick.z, filler, localOffset)
		placement.role = "mess_fill"
		if type(filler.surfaceSnap) == "string" then
			placement.surfaceSnap = filler.surfaceSnap
		end

		DungeonSurfacePlacementModule.AddPlacement(state, placement, { w = 1, d = 1 }, "mess_fill")
		placements[#placements + 1] = placement
	end

	return placements
end

function DungeonMessPileModule.BuildPile(state, rng, profile, spec)
	local anchor = chooseAnchor(state, rng, spec.anchorCandidates)
	if not anchor then
		return {}
	end

	local placements = {}
	local dominant = spec.dominant or {}
	if dominant.tileId and DungeonSurfacePlacementModule.CanPlace(state, anchor.x, anchor.z, { w = 1, d = 1 }, {
		requireSurface = dominant.requireSurface or "floor",
		allowNavigation = dominant.allowNavigation == true,
		allowDoors = false,
		navigationClearanceSubcells = dominant.navigationClearanceSubcells,
		doorClearanceSubcells = dominant.doorClearanceSubcells,
	}) then
		local p = buildPlacement(profile, anchor.x, anchor.z, dominant)
		p.role = "mess_anchor"
		DungeonSurfacePlacementModule.AddPlacement(state, p, { w = 1, d = 1 }, "mess_anchor")
		placements[#placements + 1] = p
	end

	local fillers = spec.fillers or {}
	for _, filler in ipairs(fillers) do
		if type(filler) ~= "table" or not filler.tileId then
			continue
		end
		local clustered = placeFillers(state, rng, profile, anchor, filler)
		for _, placed in ipairs(clustered) do
			placements[#placements + 1] = placed
		end
	end

	return placements
end

return DungeonMessPileModule

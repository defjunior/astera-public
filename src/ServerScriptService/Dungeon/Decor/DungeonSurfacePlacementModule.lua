local WFCTypes = require(script.Parent.Parent.WFC.WFCTypes)

local DungeonSurfacePlacementModule = {}

local function key2(x, z)
	return WFCTypes.Key2D(x, z)
end

local function isMasked(maskSet, x, z)
	return maskSet and maskSet[key2(x, z)] == true
end

local function copyPos(x, z)
	return { x = x, z = z }
end

local function isNearMask(mask, x, z, radius)
	if type(mask) ~= "table" then
		return false
	end
	local r = math.max(0, math.floor(tonumber(radius) or 0))
	for ox = -r, r do
		for oz = -r, r do
			if mask[key2(x + ox, z + oz)] == true then
				return true
			end
		end
	end
	return false
end

function DungeonSurfacePlacementModule.BuildState(profile, baseBlueprint, roomContext)
	local width = profile.dimensions.x
	local depth = profile.dimensions.z
	local masks = profile.reservedMasks or {}

	local state = {
		width = width,
		depth = depth,
		profile = profile,
		roomContext = roomContext,
		occupancy = {},
		anchors = {},
		placements = {},
		_scanYieldCounter = 0,
		_scanYieldInterval = math.max(
			64,
			math.floor(
				tonumber(roomContext and roomContext.surfaceScanYieldInterval)
					or tonumber(profile and profile.surfaceScanYieldInterval)
					or 512
			)
		),
		surfaces = {
			floor = {},
			wall = {},
			perimeter = {},
			center = {},
			corners = {},
			doors = {},
			navigation = {},
		},
	}

	for x = 1, width do
		for z = 1, depth do
			local k = key2(x, z)
			state.surfaces.floor[k] = true
			if isMasked(masks.perimeter, x, z) then
				state.surfaces.perimeter[k] = true
				state.surfaces.wall[k] = not isMasked(masks.doors, x, z)
			end
			if isMasked(masks.center, x, z) then
				state.surfaces.center[k] = true
			end
			if isMasked(masks.corners, x, z) then
				state.surfaces.corners[k] = true
			end
			if isMasked(masks.doors, x, z) then
				state.surfaces.doors[k] = true
			end
			if isMasked(masks.navigation, x, z) then
				state.surfaces.navigation[k] = true
			end
		end
	end

	for _, placement in ipairs((baseBlueprint and baseBlueprint.placements) or {}) do
		if placement.localPos then
			local x = placement.localPos.x
			local z = placement.localPos.z
			local k = key2(x, z)
			local tags = placement.tags or {}
			local hardBlock = false
			for _, tag in ipairs(tags) do
				if tag == "central_focus" or tag == "cover" or tag == "doorway" then
					hardBlock = true
					break
				end
			end
			if not hardBlock then
				local category = tostring(placement.tileCategory or "")
				hardBlock = (category == "Feature" or category == "Structure")
			end
			if hardBlock then
				DungeonSurfacePlacementModule.Reserve(
					state,
					x,
					z,
					placement.footprint or { w = 1, d = 1 },
					"base_blocked"
				)
			end
		end
	end

	return state
end

local function maybeYieldScan(state)
	if not state then
		return
	end
	state._scanYieldCounter = (state._scanYieldCounter or 0) + 1
	local interval = state._scanYieldInterval or 0
	if interval > 0 and (state._scanYieldCounter % interval == 0) then
		task.wait()
	end
end

function DungeonSurfacePlacementModule.IsInBounds(state, x, z)
	return x >= 1 and x <= state.width and z >= 1 and z <= state.depth
end

function DungeonSurfacePlacementModule.IsOccupied(state, x, z)
	return state.occupancy[key2(x, z)] ~= nil
end

function DungeonSurfacePlacementModule.CanPlace(state, x, z, footprint, rules)
	local w = math.max(1, math.floor((footprint and footprint.w) or 1))
	local d = math.max(1, math.floor((footprint and footprint.d) or 1))
	local allowNavigation = rules and rules.allowNavigation == true
	local allowDoors = rules and rules.allowDoors == true
	local requireSurface = rules and rules.requireSurface
	local navClearance = math.max(0, math.floor((rules and rules.navigationClearanceSubcells) or 0))
	local doorClearance = math.max(0, math.floor((rules and rules.doorClearanceSubcells) or 0))

	for ox = 0, w - 1 do
		for oz = 0, d - 1 do
			local cx = x + ox
			local cz = z + oz
			if not DungeonSurfacePlacementModule.IsInBounds(state, cx, cz) then
				return false
			end

			local k = key2(cx, cz)
			if state.occupancy[k] and not (rules and rules.allowSoftOverlap == true) then
				return false
			end

			if (not allowNavigation) and state.surfaces.navigation[k] then
				return false
			end
			if (not allowDoors) and state.surfaces.doors[k] then
				return false
			end
			if (not allowNavigation) and navClearance > 0 and isNearMask(state.surfaces.navigation, cx, cz, navClearance) then
				return false
			end
			if (not allowDoors) and doorClearance > 0 and isNearMask(state.surfaces.doors, cx, cz, doorClearance) then
				return false
			end

			if type(requireSurface) == "string" then
				local mask = state.surfaces[requireSurface]
				if mask and mask[k] ~= true then
					return false
				end
			end
		end
	end
	return true
end

function DungeonSurfacePlacementModule.Reserve(state, x, z, footprint, reserveTag)
	local w = math.max(1, math.floor((footprint and footprint.w) or 1))
	local d = math.max(1, math.floor((footprint and footprint.d) or 1))
	for ox = 0, w - 1 do
		for oz = 0, d - 1 do
			local cx = x + ox
			local cz = z + oz
			if DungeonSurfacePlacementModule.IsInBounds(state, cx, cz) then
				state.occupancy[key2(cx, cz)] = {
					tag = reserveTag or "reserved",
				}
			end
		end
	end
end

function DungeonSurfacePlacementModule.FindCandidates(state, footprint, rules)
	local candidates = {}
	for z = 1, state.depth do
		for x = 1, state.width do
			maybeYieldScan(state)
			if DungeonSurfacePlacementModule.CanPlace(state, x, z, footprint, rules) then
				candidates[#candidates + 1] = copyPos(x, z)
			end
		end
	end
	return candidates
end

function DungeonSurfacePlacementModule.AddPlacement(state, placement, footprint, reserveTag, reserveOrigin)
	state.placements[#state.placements + 1] = placement
	if reserveOrigin and type(reserveOrigin) == "table" then
		DungeonSurfacePlacementModule.Reserve(
			state,
			math.floor(tonumber(reserveOrigin.x) or 0),
			math.floor(tonumber(reserveOrigin.z) or 0),
			footprint,
			reserveTag
		)
	elseif placement and placement.localPos then
		DungeonSurfacePlacementModule.Reserve(
			state,
			placement.localPos.x,
			placement.localPos.z,
			footprint,
			reserveTag
		)
	end
end

function DungeonSurfacePlacementModule.MarkAnchor(state, anchor)
	state.anchors[#state.anchors + 1] = anchor
end

function DungeonSurfacePlacementModule.NearestAnchors(state, x, z, maxDistance)
	local out = {}
	local limit = tonumber(maxDistance) or math.huge
	for _, anchor in ipairs(state.anchors) do
		local dist = math.abs(anchor.localPos.x - x) + math.abs(anchor.localPos.z - z)
		if dist <= limit then
			out[#out + 1] = {
				anchor = anchor,
				dist = dist,
			}
		end
	end
	table.sort(out, function(a, b)
		if a.dist ~= b.dist then
			return a.dist < b.dist
		end
		return (a.anchor.role or "") < (b.anchor.role or "")
	end)
	return out
end

return DungeonSurfacePlacementModule

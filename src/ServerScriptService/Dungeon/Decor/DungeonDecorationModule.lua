local WFCTileVocabulary = require(script.Parent.Parent.WFC.WFCTileVocabulary)
local DungeonVariantModule = require(script.Parent.DungeonVariantModule)
local DungeonData = require(script.Parent.Parent.Data.DungeonData)
local DungeonArchetypeModule = require(script.Parent.DungeonArchetypeModule)
local DungeonSurfacePlacementModule = require(script.Parent.DungeonSurfacePlacementModule)
local DungeonScatterModule = require(script.Parent.DungeonScatterModule)
local DungeonMessPileModule = require(script.Parent.DungeonMessPileModule)
local DungeonStructuralPropPlanner = require(script.Parent.DungeonStructuralPropPlanner)
local DungeonWritingVariantModule = require(script.Parent.DungeonWritingVariantModule)

local DungeonDecorationModule = {}
local STRUCTURAL_RULES = DungeonData.Decor.StructuralPropRules or {}
local LAYOUT_RULES = DungeonData.Decor.LayoutRules or {}
local pickVariant

-- Current room purpose, set at the top of DecorateRoom. Decoration runs single-threaded
-- per room (sequential loop in DungeonSystem.DecoratePlacedRooms), so module-level context
-- is safe and lets buildVariants apply per-purpose roomRoleSuitability without threading the
-- purpose through every pickVariant call site.
local currentRoomPurpose = nil

local function suitabilityForPurpose(tile)
	if currentRoomPurpose == nil then
		return 1
	end
	local suitability = tile and tile.roomRoleSuitability
	if type(suitability) ~= "table" then
		return 1
	end
	local value = suitability[currentRoomPurpose]
	if value == nil then
		-- Props with no suitability map are neutral; props that DO declare suitabilities but
		-- omit this purpose are mildly discouraged (keeps a themed prop from bleeding into
		-- unrelated rooms without ever hard-excluding it).
		if next(suitability) == nil then
			return 1
		end
		return 0.35
	end
	return math.max(0, tonumber(value) or 0)
end

local function profileBegin(label)
	pcall(debug.profilebegin, label)
end

local function profileEnd()
	pcall(debug.profileend)
end

local function containsTag(tags, wanted)
	for _, tag in ipairs(tags or {}) do
		if tag == wanted then
			return true
		end
	end
	return false
end

local function cloneTags(tags)
	local out = {}
	for i, tag in ipairs(tags or {}) do
		out[i] = tag
	end
	return out
end

local function cloneFootprint(footprint)
	return {
		w = math.max(1, math.floor((footprint and footprint.w) or 1)),
		d = math.max(1, math.floor((footprint and footprint.d) or 1)),
		h = math.max(1, math.floor((footprint and footprint.h) or 1)),
	}
end

local function deepCopyTable(source)
	if type(source) ~= "table" then
		return source
	end
	local out = {}
	for key, value in pairs(source) do
		out[key] = deepCopyTable(value)
	end
	return out
end

local function mergeTable(into, source)
	if type(source) ~= "table" then
		return into
	end
	for key, value in pairs(source) do
		if type(value) == "table" then
			if type(into[key]) ~= "table" then
				into[key] = {}
			end
			mergeTable(into[key], value)
		else
			into[key] = value
		end
	end
	return into
end

local function hasAnyTag(tags, accepted)
	for _, tag in ipairs(tags or {}) do
		if accepted[tag] == true then
			return true
		end
	end
	return false
end

local function hasNeedle(text, needle)
	if type(text) ~= "string" then
		return false
	end
	return string.find(string.lower(text), string.lower(needle), 1, true) ~= nil
end

local function resolveLayoutProfile(roomContext, roomTypeRecord)
	local resolved = deepCopyTable(LAYOUT_RULES.Default or {})
	local purpose = tostring(roomContext and roomContext.purpose or "")
	local purposeOverride = LAYOUT_RULES.PurposeOverrides and LAYOUT_RULES.PurposeOverrides[purpose]
	mergeTable(resolved, purposeOverride)

	local roomTypeId = tostring(roomTypeRecord and roomTypeRecord.id or "")
	local roomTypeOverride = LAYOUT_RULES.RoomTypeOverrides and LAYOUT_RULES.RoomTypeOverrides[roomTypeId]
	mergeTable(resolved, roomTypeOverride)

	for _, tag in ipairs((roomTypeRecord and roomTypeRecord.tags) or {}) do
		local tagOverride = LAYOUT_RULES.TagOverrides and LAYOUT_RULES.TagOverrides[tag]
		mergeTable(resolved, tagOverride)
	end

	local navClear = tonumber(resolved.NavigationClearanceSubcells)
	if navClear == nil then
		navClear = 1
	end
	resolved.NavigationClearanceSubcells = math.max(0, math.floor(navClear))
	return resolved
end

local function listTileIds(requiredTags, forbiddenTags)
	local out = {}
	for _, tileId in ipairs(WFCTileVocabulary.ListTileIds()) do
		local ok = true
		for _, tag in ipairs(requiredTags or {}) do
			if not WFCTileVocabulary.TileHasTag(tileId, tag) then
				ok = false
				break
			end
		end
		if ok then
			for _, tag in ipairs(forbiddenTags or {}) do
				if WFCTileVocabulary.TileHasTag(tileId, tag) then
					ok = false
					break
				end
			end
		end
		if ok then
			out[#out + 1] = tileId
		end
	end
	return out
end

local function buildVariants(tileIds, extraWeight)
	local variants = {}
	for _, tileId in ipairs(tileIds) do
		local tile = WFCTileVocabulary.GetTile(tileId) or {}
		local suitability = suitabilityForPurpose(tile)
		if suitability > 0 then
		local weight = (tile.baseWeight or 1) * (extraWeight or 1) * suitability
		variants[#variants + 1] = {
			id = tileId,
			tileId = tileId,
			weight = weight,
			tags = cloneTags(tile.tags),
			footprint = cloneFootprint(tile.footprint),
			category = tile.category,
			walkable = tile.walkable == true,
			collision = tile.collision or "None",
			navCost = tile.navCost or 1,
			prefabId = tile.prefabId,
			prefabCandidates = WFCTileVocabulary.GetPrefabCandidates(tileId),
			randomYaw = tile.randomYaw == true,
		}
		end
	end
	return variants
end

local function placementFromVariant(profile, pos, variant, orientation, opts)
	local mapped = profile.localToGrid(pos)
	local offsetX = (mapped.localOffset and mapped.localOffset.x) or 0
	local offsetZ = (mapped.localOffset and mapped.localOffset.z) or 0
	if opts and opts.localOffset then
		offsetX += opts.localOffset.x
		offsetZ += opts.localOffset.z
	end
	local placement = {
		tileId = variant.tileId,
		tileCategory = variant.category,
		tags = variant.tags,
		prefabId = variant.prefabId,
		prefabCandidates = variant.prefabCandidates,
		localPos = { x = pos.x, z = pos.z },
		gridPos = {
			x = mapped.x,
			y = mapped.y,
			z = mapped.z,
		},
		subgridPos = {
			x = (mapped.subgrid and mapped.subgrid.x) or pos.x,
			z = (mapped.subgrid and mapped.subgrid.z) or pos.z,
		},
		localOffset = {
			x = offsetX,
			z = offsetZ,
		},
		orientation = orientation or "North",
		yawDegrees = opts and opts.yawDegrees or nil,
		allowCellSharing = opts and opts.allowCellSharing == true,
		walkable = variant.walkable == true,
		collision = variant.collision,
		navCost = variant.navCost,
		footprint = cloneFootprint(variant.footprint),
	}
	return placement
end

local function centerOfProfile(profile)
	return {
		x = math.floor((profile.dimensions.x + 1) * 0.5),
		z = math.floor((profile.dimensions.z + 1) * 0.5),
	}
end

local function orientationTowardCenter(profile, pos)
	return WFCTileVocabulary.GetDirectionToward(pos, centerOfProfile(profile))
end

local function orientationTowardTarget(pos, targetPos)
	return WFCTileVocabulary.GetDirectionToward(pos, targetPos)
end

local function footprintForVariant(variant)
	return cloneFootprint(variant and variant.footprint)
end

local function normalizedRoomArea(profile)
	local width = math.max(1, math.floor((profile.dimensions and profile.dimensions.x) or 1))
	local depth = math.max(1, math.floor((profile.dimensions and profile.dimensions.z) or 1))
	local subgrid = math.max(1, math.floor(tonumber(profile.subgridScale) or 1))
	return math.max(1, math.floor((width * depth) / (subgrid * subgrid)))
end

local function asNumber(v, fallback)
	local n = tonumber(v)
	if n == nil then
		return fallback
	end
	return n
end

local function startsWith(value, prefix)
	if type(value) ~= "string" or type(prefix) ~= "string" then
		return false
	end
	return string.sub(value, 1, #prefix) == prefix
end

local function hasAnyTagSet(tags, wanted)
	for _, tag in ipairs(tags or {}) do
		if wanted[tag] == true then
			return true
		end
	end
	return false
end

local function isStructuralDecorPlacement(placement)
	if type(placement) ~= "table" then
		return false
	end
	local role = tostring(placement.role or "")
	if startsWith(role, "structural_") then
		return true
	end
	return hasAnyTagSet(placement.tags, {
		structural_prop = true,
		pillar_support = true,
		wall_support = true,
		pillar = true,
	})
end

local function isClusterDecorPlacement(placement)
	if type(placement) ~= "table" then
		return false
	end
	local role = tostring(placement.role or "")
	if role == "anchor_cluster" or role == "mess_anchor" or role == "mess_fill" then
		return true
	end
	return hasAnyTagSet(placement.tags, {
		cluster = true,
		mess_cluster = true,
		debris = true,
		rubble = true,
	})
end

local function isMicroDecorPlacement(placement)
	if type(placement) ~= "table" then
		return false
	end
	local role = tostring(placement.role or "")
	if role == "tabletop" then
		return true
	end
	local tags = placement.tags or {}
	if hasAnyTagSet(tags, {
		micro = true,
		paper = true,
		writing = true,
	}) then
		return true
	end
	if containsTag(tags, "books")
		and not hasAnyTagSet(tags, {
			furniture = true,
			wall_prop = true,
			cluster = true,
			mess_cluster = true,
		})
	then
		return true
	end
	return false
end

local function isMajorDecorPlacement(placement)
	if type(placement) ~= "table" then
		return false
	end
	local role = tostring(placement.role or "")
	if role == "bookshelf_wall"
		or role == "bookshelf_row"
		or role == "table_anchor"
		or role == "table_seat"
		or role == "desk_cluster"
		or role == "focus_anchor"
		or role == "reward_anchor"
		or role == "generic_anchor"
		or role == "secondary_furniture"
	then
		return true
	end
	return hasAnyTagSet(placement.tags, {
		furniture = true,
		wall_prop = true,
		storage = true,
		central_focus = true,
	})
end

local function classifyDecorPlacement(placement)
	if isStructuralDecorPlacement(placement) then
		return "structural"
	end
	if isClusterDecorPlacement(placement) then
		return "cluster"
	end
	if isMicroDecorPlacement(placement) then
		return "micro"
	end
	if isMajorDecorPlacement(placement) then
		return "major"
	end
	return "major"
end

local function computeScaledBudget(rule, area, fallbackMin, fallbackMax)
	local r = (type(rule) == "table") and rule or {}
	local minCount = math.max(0, math.floor(asNumber(r.Min, fallbackMin)))
	local maxCount = math.max(minCount, math.floor(asNumber(r.Max, fallbackMax)))
	local areaScale = math.max(0, asNumber(r.AreaScale, 0))
	local scaled = math.floor((area * areaScale) + 0.5)
	return math.clamp(scaled, minCount, maxCount)
end

local function resolvePassBudgets(layoutProfile, profile, structuralStats)
	local rules = (layoutProfile and layoutProfile.PassBudgets) or {}
	local area = normalizedRoomArea(profile)
	local plannedStructural = math.max(
		0,
		math.floor(asNumber(structuralStats and structuralStats.structuralPlacementCount, 0))
	)
	local budgets = {
		structural = computeScaledBudget(rules.Structural, area, 0, math.max(6, plannedStructural)),
		major = computeScaledBudget(rules.Major, area, 6, 28),
		cluster = computeScaledBudget(rules.Cluster, area, 1, 16),
		micro = computeScaledBudget(rules.Micro, area, 0, 12),
		total = computeScaledBudget(rules.Total, area, 10, 64),
	}
	-- Never trim placed structural supports in cleanup; structural pass owns those decisions.
	budgets.structural = math.max(budgets.structural, plannedStructural)
	budgets.total = math.max(
		budgets.total,
		math.min(
			96,
			budgets.structural + budgets.major + budgets.cluster + budgets.micro
		)
	)
	return budgets
end

local function appendPassPlacements(target, placements, passName, passCounts)
	for _, placement in ipairs(placements or {}) do
		target[#target + 1] = placement
		passCounts[passName] += 1
	end
end

local function applyDecorCleanup(placements, passBudgets)
	local cleaned = {}
	local counts = {
		structural = 0,
		major = 0,
		cluster = 0,
		micro = 0,
		total = 0,
		trimmedByBudget = 0,
		trimmedMicroFloor = 0,
		trimmedOverlap = 0,
	}
	local occupied = {}

	for _, placement in ipairs(placements or {}) do
		local passName = classifyDecorPlacement(placement)
		local role = tostring(placement.role or "")
		if passName == "micro" and role ~= "tabletop" then
			counts.trimmedMicroFloor += 1
			continue
		end
		if counts.total >= passBudgets.total then
			counts.trimmedByBudget += 1
			continue
		end
		if counts[passName] >= (passBudgets[passName] or 0) then
			counts.trimmedByBudget += 1
			continue
		end

		local fp = placement.footprint or { w = 1, d = 1 }
		local w = math.max(1, math.floor(asNumber(fp.w, 1)))
		local d = math.max(1, math.floor(asNumber(fp.d, 1)))
		local originX = math.floor(asNumber(placement.localPos and placement.localPos.x, 0))
		local originZ = math.floor(asNumber(placement.localPos and placement.localPos.z, 0))
		local overlaps = false
		if placement.allowCellSharing ~= true then
			for ox = 0, w - 1 do
				for oz = 0, d - 1 do
					local k = string.format("%d,%d", originX + ox, originZ + oz)
					if occupied[k] == true then
						overlaps = true
						break
					end
				end
				if overlaps then
					break
				end
			end
			if overlaps then
				counts.trimmedOverlap += 1
				continue
			end
		end

		cleaned[#cleaned + 1] = placement
		counts[passName] += 1
		counts.total += 1
		if placement.allowCellSharing ~= true then
			for ox = 0, w - 1 do
				for oz = 0, d - 1 do
					local k = string.format("%d,%d", originX + ox, originZ + oz)
					occupied[k] = true
				end
			end
		end
	end

	return cleaned, counts
end

local function isNearMask(mask, x, z, radius)
	if type(mask) ~= "table" then
		return false
	end
	local r = math.max(0, math.floor(asNumber(radius, 0)))
	for ox = -r, r do
		for oz = -r, r do
			local k = string.format("%d,%d", x + ox, z + oz)
			if mask[k] == true then
				return true
			end
		end
	end
	return false
end

local function canPlaceWithClearance(state, x, z, footprint, rules, layoutProfile)
	if not DungeonSurfacePlacementModule.CanPlace(state, x, z, footprint, rules) then
		return false
	end

	local navMask = state and state.surfaces and state.surfaces.navigation
	local doorMask = state and state.surfaces and state.surfaces.doors
	local navClearance = math.max(
		0,
		math.floor(
			asNumber(
				rules and rules.navigationClearanceSubcells,
				layoutProfile and layoutProfile.NavigationClearanceSubcells or 0
			)
		)
	)
	local doorClearance = math.max(0, math.floor(asNumber(rules and rules.doorClearanceSubcells, 0)))
	if navClearance <= 0 and doorClearance <= 0 then
		return true
	end

	local w = math.max(1, math.floor((footprint and footprint.w) or 1))
	local d = math.max(1, math.floor((footprint and footprint.d) or 1))
	for ox = 0, w - 1 do
		for oz = 0, d - 1 do
			local cx = x + ox
			local cz = z + oz
			if navClearance > 0 and isNearMask(navMask, cx, cz, navClearance) then
				return false
			end
			if doorClearance > 0 and isNearMask(doorMask, cx, cz, doorClearance) then
				return false
			end
		end
	end

	return true
end

local function findCandidatesWithClearance(state, footprint, rules, layoutProfile)
	local candidates = DungeonSurfacePlacementModule.FindCandidates(state, footprint, rules or {})
	if #candidates <= 0 then
		return candidates
	end
	local filtered = {}
	for _, candidate in ipairs(candidates) do
		if canPlaceWithClearance(state, candidate.x, candidate.z, footprint, rules, layoutProfile) then
			filtered[#filtered + 1] = candidate
		end
	end
	return filtered
end

local function isLibraryLikeRoom(roomContext, roomTypeRecord)
	if tostring(roomContext and roomContext.purpose or "") == "lore" then
		return true
	end
	local tags = roomTypeRecord and roomTypeRecord.tags or {}
	if hasAnyTag(tags, {
		lore = true,
		library = true,
		archive = true,
		quiet = true,
	}) then
		return true
	end
	local id = tostring(roomTypeRecord and roomTypeRecord.id or "")
	return hasNeedle(id, "library") or hasNeedle(id, "archive")
end

local function tagSetContainsAll(tags, required)
	for _, tag in ipairs(required or {}) do
		if not containsTag(tags, tag) then
			return false
		end
	end
	return true
end

local function addUniqueTag(tags, value)
	for _, tag in ipairs(tags) do
		if tag == value then
			return
		end
	end
	tags[#tags + 1] = value
end

local function minDistanceToPlaced(list, x, z)
	local best = math.huge
	for _, pos in ipairs(list) do
		local dx = pos.x - x
		local dz = pos.z - z
		local dist = math.sqrt((dx * dx) + (dz * dz))
		if dist < best then
			best = dist
		end
	end
	return best
end

local function runAxisForFacing(orientation)
	if orientation == "East" or orientation == "West" then
		return { x = 0, z = 1 }
	end
	return { x = 1, z = 0 }
end

local function runStepForFootprint(footprint)
	local fp = footprint or { w = 1, d = 1 }
	return math.max(1, math.max(math.floor(fp.w or 1), math.floor(fp.d or 1)))
end

local function collectAnchorPositionsByRole(state, acceptedRoles)
	local out = {}
	local seen = {}
	for _, anchor in ipairs(state.anchors or {}) do
		local role = tostring(anchor.role or "")
		if acceptedRoles[role] == true and type(anchor.localPos) == "table" then
			local x = math.floor(tonumber(anchor.localPos.x) or 0)
			local z = math.floor(tonumber(anchor.localPos.z) or 0)
			local key = string.format("%d,%d", x, z)
			if not seen[key] then
				seen[key] = true
				out[#out + 1] = { x = x, z = z }
			end
		end
	end
	return out
end

local function collectMessAnchorCandidates(state)
	return collectAnchorPositionsByRole(state, {
		bookshelf_wall = true,
		bookshelf_row = true,
		table_anchor = true,
		desk_cluster = true,
		structural_wall_prop = true,
		structural_pillar = true,
	})
end

local function nearestDistanceToAnchors(anchors, point)
	if type(anchors) ~= "table" or #anchors <= 0 then
		return math.huge
	end
	local best = math.huge
	for _, anchor in ipairs(anchors) do
		local dx = anchor.x - point.x
		local dz = anchor.z - point.z
		local dist = math.sqrt((dx * dx) + (dz * dz))
		if dist < best then
			best = dist
		end
	end
	return best
end

local function centerPointForRect(x, z, w, d)
	return {
		x = x + ((math.max(1, w) - 1) * 0.5),
		z = z + ((math.max(1, d) - 1) * 0.5),
	}
end

local function pickTableCandidate(rng, candidates, tableFootprint, shelfAnchors, nearDistanceCap, strictCap)
	if #candidates <= 0 then
		return nil
	end
	if type(shelfAnchors) ~= "table" or #shelfAnchors <= 0 then
		return candidates[rng:NextInteger(1, #candidates)]
	end

	local scored = {}
	for _, candidate in ipairs(candidates) do
		local center = centerPointForRect(candidate.x, candidate.z, tableFootprint.w, tableFootprint.d)
		local dist = nearestDistanceToAnchors(shelfAnchors, center)
		scored[#scored + 1] = {
			candidate = candidate,
			dist = dist,
		}
	end
	table.sort(scored, function(a, b)
		if a.dist ~= b.dist then
			return a.dist < b.dist
		end
		if a.candidate.z ~= b.candidate.z then
			return a.candidate.z < b.candidate.z
		end
		return a.candidate.x < b.candidate.x
	end)

	local near = {}
	for _, entry in ipairs(scored) do
		if entry.dist <= nearDistanceCap then
			near[#near + 1] = entry.candidate
		end
	end
	if #near > 0 then
		local pickTop = math.max(1, math.floor(#near * 0.6))
		return near[rng:NextInteger(1, pickTop)]
	end
	if strictCap == true then
		return nil
	end

	local topCount = math.max(1, math.floor(#scored * 0.2))
	return scored[rng:NextInteger(1, topCount)].candidate
end

local function buildSeatSlots(tablePlacement, tableFootprint, seatFootprint)
	local slots = {}
	local seen = {}
	local tableX = tablePlacement.localPos.x
	local tableZ = tablePlacement.localPos.z
	local minX = tableX
	local maxX = tableX + tableFootprint.w - 1
	local minZ = tableZ
	local maxZ = tableZ + tableFootprint.d - 1
	local spacing = math.max(1, math.max(seatFootprint.w, seatFootprint.d))
	local pad = math.max(1, math.ceil(math.max(seatFootprint.w, seatFootprint.d) * 0.5))

	local function push(x, z)
		local key = string.format("%d,%d", x, z)
		if not seen[key] then
			seen[key] = true
			slots[#slots + 1] = { x = x, z = z }
		end
	end

	for x = minX, maxX, spacing do
		push(x, minZ - pad)
		push(x, maxZ + pad)
	end
	for z = minZ, maxZ, spacing do
		push(minX - pad, z)
		push(maxX + pad, z)
	end

	local center = centerPointForRect(tableX, tableZ, tableFootprint.w, tableFootprint.d)
	table.sort(slots, function(a, b)
		local da = math.abs(a.x - center.x) + math.abs(a.z - center.z)
		local db = math.abs(b.x - center.x) + math.abs(b.z - center.z)
		if da ~= db then
			return da < db
		end
		if a.z ~= b.z then
			return a.z < b.z
		end
		return a.x < b.x
	end)

	return slots, center
end

local function orientationFromWall(anchor, profile)
	local wall = tostring(anchor and anchor.wall or "")
	if wall == "North" then
		return "South"
	elseif wall == "South" then
		return "North"
	elseif wall == "East" then
		return "West"
	elseif wall == "West" then
		return "East"
	end
	return orientationTowardCenter(profile, anchor)
end

local function key2(x, z)
	return string.format("%d,%d", x, z)
end

local function cardinalStep(direction)
	if direction == "South" then
		return 0, 1
	elseif direction == "East" then
		return 1, 0
	elseif direction == "West" then
		return -1, 0
	end
	return 0, -1
end

local function oppositeCardinal(direction)
	if direction == "North" then
		return "South"
	elseif direction == "South" then
		return "North"
	elseif direction == "East" then
		return "West"
	elseif direction == "West" then
		return "East"
	end
	return nil
end

local function nearestBoundaryWall(state, pos)
	if type(state) ~= "table" or type(pos) ~= "table" then
		return nil
	end
	local width = math.max(1, math.floor(asNumber(state.width, 1)))
	local depth = math.max(1, math.floor(asNumber(state.depth, 1)))
	local x = math.clamp(math.floor(asNumber(pos.x, 1)), 1, width)
	local z = math.clamp(math.floor(asNumber(pos.z, 1)), 1, depth)

	local distNorth = z - 1
	local distSouth = depth - z
	local distWest = x - 1
	local distEast = width - x

	local bestWall = "North"
	local bestDist = distNorth
	if distSouth < bestDist then
		bestWall = "South"
		bestDist = distSouth
	end
	if distWest < bestDist then
		bestWall = "West"
		bestDist = distWest
	end
	if distEast < bestDist then
		bestWall = "East"
	end
	return bestWall
end

local function pickDirectionByScore(scores, tieBreak)
	local bestDirection = nil
	local bestScore = -math.huge
	for _, direction in ipairs({ "North", "South", "East", "West" }) do
		local score = tonumber(scores and scores[direction]) or 0
		if score > bestScore then
			bestScore = score
			bestDirection = direction
		elseif score == bestScore and tieBreak == direction then
			bestDirection = direction
		end
	end
	if bestScore <= 0 then
		return nil
	end
	return bestDirection
end

local function wallScoreAtCell(state, wallMask, perimeterMask, x, z)
	if x < 1 or x > state.width or z < 1 or z > state.depth then
		return 3
	end
	local k = key2(x, z)
	if wallMask[k] == true then
		return 3
	end
	if perimeterMask[k] == true then
		return 2
	end
	return 0
end

local function detectWallNormalForFootprint(state, pos, footprint)
	if type(state) ~= "table" or type(pos) ~= "table" then
		return nil
	end
	local w = math.max(1, math.floor(asNumber(footprint and footprint.w, 1)))
	local d = math.max(1, math.floor(asNumber(footprint and footprint.d, 1)))
	local x0 = math.clamp(math.floor(asNumber(pos.x, 1)), 1, math.max(1, math.floor(asNumber(state.width, 1))))
	local z0 = math.clamp(math.floor(asNumber(pos.z, 1)), 1, math.max(1, math.floor(asNumber(state.depth, 1))))
	local wallMask = (state.surfaces and state.surfaces.wall) or {}
	local perimeterMask = (state.surfaces and state.surfaces.perimeter) or {}
	local scores = {
		North = 0,
		South = 0,
		East = 0,
		West = 0,
	}

	for x = x0, (x0 + w - 1) do
		scores.North += wallScoreAtCell(state, wallMask, perimeterMask, x, z0 - 1)
		scores.South += wallScoreAtCell(state, wallMask, perimeterMask, x, z0 + d)
	end
	for z = z0, (z0 + d - 1) do
		scores.West += wallScoreAtCell(state, wallMask, perimeterMask, x0 - 1, z)
		scores.East += wallScoreAtCell(state, wallMask, perimeterMask, x0 + w, z)
	end

	-- Normalize scores by scan width so asymmetric footprints (e.g. w=2, d=1)
	-- don't bias toward directions with more scanned cells.
	if w > 0 then
		scores.North /= w
		scores.South /= w
	end
	if d > 0 then
		scores.West /= d
		scores.East /= d
	end

	return pickDirectionByScore(scores, nearestBoundaryWall(state, pos))
end

local function inwardOrientationForWallCell(state, profile, pos, footprint)
	local wallNormal = detectWallNormalForFootprint(state, pos, footprint)
	if wallNormal then
		local inward = oppositeCardinal(wallNormal)
		if inward then
			return inward
		end
	end
	local wall = nearestBoundaryWall(state, pos)
	local inward = oppositeCardinal(wall)
	if inward then
		return inward
	end
	return orientationTowardCenter(profile, pos)
end

local function orientedFootprintForOrientation(baseFootprint, orientation)
	local fp = cloneFootprint(baseFootprint)
	if orientation == "East" or orientation == "West" then
		local t = fp.w
		fp.w = fp.d
		fp.d = t
	end
	return fp
end

local function isWithinBoundsForFootprint(state, x, z, footprint)
	local w = math.max(1, math.floor(asNumber(footprint and footprint.w, 1)))
	local d = math.max(1, math.floor(asNumber(footprint and footprint.d, 1)))
	if x < 1 or z < 1 then
		return false
	end
	if (x + w - 1) > state.width or (z + d - 1) > state.depth then
		return false
	end
	return true
end

local function roundedCell(v)
	return math.floor(v + 0.5)
end

local function isValidWallBookshelfFit(state, pos, orientation, footprint, layoutProfile)
	if type(state) ~= "table" or type(pos) ~= "table" then
		return false
	end
	if not isWithinBoundsForFootprint(state, pos.x, pos.z, footprint) then
		return false
	end

	local rules = (layoutProfile and layoutProfile.WallShelf) or {}
	local frontClearance = math.max(1, math.floor(asNumber(rules.FrontClearanceSubcells, 1)))
	local cornerInset = math.max(0, math.floor(asNumber(rules.CornerInsetSubcells, 1)))
	local sideClearance = math.max(0, math.floor(asNumber(rules.SideClearanceSubcells, 0)))

	local w = math.max(1, math.floor(asNumber(footprint and footprint.w, 1)))
	local d = math.max(1, math.floor(asNumber(footprint and footprint.d, 1)))
	local centerX = pos.x + ((w - 1) * 0.5)
	local centerZ = pos.z + ((d - 1) * 0.5)
	local dx, dz = cardinalStep(orientation)

	local wallMask = (state.surfaces and state.surfaces.wall) or {}
	local perimeterMask = (state.surfaces and state.surfaces.perimeter) or {}
	local navMask = (state.surfaces and state.surfaces.navigation) or {}
	local expectedWallNormal = detectWallNormalForFootprint(state, pos, footprint)
	if expectedWallNormal then
		local expectedOrientation = oppositeCardinal(expectedWallNormal)
		if expectedOrientation and tostring(orientation or "") ~= expectedOrientation then
			return false
		end
	end

	local backX = roundedCell(centerX - dx)
	local backZ = roundedCell(centerZ - dz)
	if backX < 1 or backX > state.width or backZ < 1 or backZ > state.depth then
		return false
	end
	local backKey = key2(backX, backZ)
	if wallMask[backKey] ~= true and perimeterMask[backKey] ~= true then
		return false
	end

	for step = 1, frontClearance do
		local fx = roundedCell(centerX + (dx * step))
		local fz = roundedCell(centerZ + (dz * step))
		if fx < 1 or fx > state.width or fz < 1 or fz > state.depth then
			return false
		end
		local fk = key2(fx, fz)
		if wallMask[fk] == true or state.occupancy[fk] ~= nil then
			return false
		end
	end

	if cornerInset > 0 then
		local minWallDistX = math.min(pos.x - 1, state.width - (pos.x + w - 1))
		local minWallDistZ = math.min(pos.z - 1, state.depth - (pos.z + d - 1))
		if minWallDistX <= cornerInset and minWallDistZ <= cornerInset then
			return false
		end
	end

	if sideClearance > 0 then
		local sx = -dz
		local sz = dx
		for side = -1, 1, 2 do
			for step = 1, sideClearance do
				local tx = roundedCell(centerX + (sx * step * side))
				local tz = roundedCell(centerZ + (sz * step * side))
				if tx >= 1 and tx <= state.width and tz >= 1 and tz <= state.depth then
					local k = key2(tx, tz)
					if wallMask[k] == true and navMask[k] ~= true then
						return false
					end
				end
			end
		end
	end

	return true
end

local function pillarReservationForAnchor(anchor, pillarFootprint, pillarRules)
	local reserveW = math.max(
		math.floor((pillarFootprint and pillarFootprint.w) or 1),
		math.floor(asNumber(anchor and anchor.reserveW, asNumber(pillarRules and pillarRules.CellReservationSubcells, 4)))
	)
	local reserveD = math.max(
		math.floor((pillarFootprint and pillarFootprint.d) or 1),
		math.floor(asNumber(anchor and anchor.reserveD, asNumber(pillarRules and pillarRules.CellReservationSubcells, 4)))
	)
	local reserveX = math.floor(asNumber(anchor and anchor.reserveOriginX, anchor and anchor.x))
	local reserveZ = math.floor(asNumber(anchor and anchor.reserveOriginZ, anchor and anchor.z))
	return {
		x = reserveX,
		z = reserveZ,
		w = math.max(1, reserveW),
		d = math.max(1, reserveD),
	}
end

local function computeStructuralCountBudget(rules, roomArea, roomTypeRecord, archetypeRecord, maxHardCap)
	local baseMin = math.max(0, math.floor(asNumber(rules and rules.BaseCountMin, 0)))
	local baseMax = math.max(baseMin, math.floor(asNumber(rules and rules.BaseCountMax, baseMin)))
	local areaScale = math.max(0, asNumber(rules and rules.AreaScale, 0))
	local category = tostring(roomTypeRecord and roomTypeRecord.category or "Room")
	local categoryMul = asNumber(rules and rules.CategoryCountMultiplier and rules.CategoryCountMultiplier[category], 1)
	local archetypeId = tostring(archetypeRecord and archetypeRecord.id or "")
	local archetypeMul = asNumber(rules and rules.ArchetypeCountMultiplier and rules.ArchetypeCountMultiplier[archetypeId], 1)
	local scaled = math.floor((roomArea * areaScale * categoryMul * archetypeMul) + 0.5)
	local budget = math.clamp(scaled, baseMin, baseMax)
	if maxHardCap ~= nil then
		budget = math.min(budget, math.max(0, math.floor(maxHardCap)))
	end
	return budget
end

local function placeStructuralSupports(state, rng, profile, roomContext, memory, roomTypeRecord, archetypeRecord)
	local out = {}
	local stats = {
		structuralPlacementCount = 0,
		structuralPillarCount = 0,
		structuralWallPropCount = 0,
		structuralAnchorPlanPillars = 0,
		structuralAnchorPlanWallProps = 0,
		structuralAnchorCandidatesTotal = 0,
		structuralAnchorCandidatesPillars = 0,
		structuralAnchorCandidatesWallProps = 0,
		structuralSkippedByBudget = 0,
		structuralSkippedByOccupancy = 0,
		structuralSkippedByVariant = 0,
		structuralSkippedBySpacing = 0,
		structuralSkippedNearDoor = 0,
		structuralSkippedNearNavigation = 0,
		structuralPillarLayoutPattern = "none",
		structuralPillarReserveSizeSubcells = 0,
		structuralPillarSupportCols = 0,
		structuralPillarSupportRows = 0,
		structuralDoorBlockedNorthCells = 0,
		structuralDoorBlockedSouthCells = 0,
		structuralDoorBlockedEastCells = 0,
		structuralDoorBlockedWestCells = 0,
		structuralFallbackRelaxedAttempted = 0,
		structuralFallbackRelaxedPlaced = 0,
	}

	if STRUCTURAL_RULES.Enabled ~= true then
		return out, stats
	end

	local plan = DungeonStructuralPropPlanner.BuildPlan({
		profile = profile,
		state = state,
		roomContext = roomContext,
		roomTypeRecord = roomTypeRecord,
		archetypeRecord = archetypeRecord,
		rules = STRUCTURAL_RULES,
	})
	stats.structuralAnchorPlanPillars = #plan.pillarAnchors
	stats.structuralAnchorPlanWallProps = #plan.wallAnchors
	stats.structuralSkippedNearDoor = asNumber(plan.stats and plan.stats.skippedNearDoor, 0)
	stats.structuralSkippedNearNavigation = asNumber(plan.stats and plan.stats.skippedNearNavigation, 0)
	stats.structuralPillarLayoutPattern = tostring(plan.stats and plan.stats.pillarLayoutPattern or "none")
	stats.structuralPillarReserveSizeSubcells = asNumber(plan.stats and plan.stats.pillarReserveSizeSubcells, 0)
	stats.structuralPillarSupportCols = asNumber(plan.stats and plan.stats.pillarSupportCols, 0)
	stats.structuralPillarSupportRows = asNumber(plan.stats and plan.stats.pillarSupportRows, 0)
	stats.structuralAnchorCandidatesTotal = asNumber(plan.stats and plan.stats.candidateAnchorCount, 0)
	stats.structuralAnchorCandidatesPillars = asNumber(plan.stats and plan.stats.candidatePillarAnchors, 0)
	stats.structuralAnchorCandidatesWallProps = asNumber(plan.stats and plan.stats.candidateWallAnchors, 0)
	stats.structuralDoorBlockedNorthCells = asNumber(plan.stats and plan.stats.doorBlockedNorthCells, 0)
	stats.structuralDoorBlockedSouthCells = asNumber(plan.stats and plan.stats.doorBlockedSouthCells, 0)
	stats.structuralDoorBlockedEastCells = asNumber(plan.stats and plan.stats.doorBlockedEastCells, 0)
	stats.structuralDoorBlockedWestCells = asNumber(plan.stats and plan.stats.doorBlockedWestCells, 0)

	local roomArea = normalizedRoomArea(profile)
	local globalBudget = math.max(0, math.floor(asNumber(STRUCTURAL_RULES.MaxStructuralPlacementsPerRoom, 0)))
	local pillarRules = STRUCTURAL_RULES.Pillars or {}
	local wallRules = STRUCTURAL_RULES.WallProps or {}
	local pillarBudget = computeStructuralCountBudget(
		pillarRules,
		roomArea,
		roomTypeRecord,
		archetypeRecord,
		STRUCTURAL_RULES.MaxPillarPlacementsPerRoom
	)
	if pillarRules.UseLayoutAnchorCount ~= false then
		local planned = math.max(0, #plan.pillarAnchors)
		local hardCap = math.max(0, math.floor(asNumber(STRUCTURAL_RULES.MaxPillarPlacementsPerRoom, planned)))
		if hardCap > 0 then
			pillarBudget = math.min(planned, hardCap)
		else
			pillarBudget = planned
		end
	end
	local wallBudget = computeStructuralCountBudget(
		wallRules,
		roomArea,
		roomTypeRecord,
		archetypeRecord,
		STRUCTURAL_RULES.MaxWallPropPlacementsPerRoom
	)
	if globalBudget > 0 then
		globalBudget = math.max(globalBudget, pillarBudget)
	end

	local pillarVariant = pickVariant(
		memory,
		profile.roomId,
		rng,
		pillarRules.RequiredTags or { "pillar" },
		pillarRules.ForbiddenTags or { "doorway" },
		{
			pillar = 1.35,
			landmark = 1.15,
			cover = 1.1,
		}
	)

	local wallVariantPool = buildVariants(
		listTileIds(wallRules.RequiredTags or { "wall_prop" }, wallRules.ForbiddenTags or { "doorway", "pillar" }),
		1
	)

	local usedWallAnchors = {}
	local minWallSpacing = math.max(0, asNumber(wallRules.MinSpacingSubcells, 0))
	local function canPlaceGlobal()
		return globalBudget <= 0 or stats.structuralPlacementCount < globalBudget
	end

	if pillarVariant then
		local pillarFootprint = footprintForVariant(pillarVariant)
		local pillarNavClearance = math.max(
			0,
			math.floor(asNumber(pillarRules.NavigationClearanceSubcells, STRUCTURAL_RULES.NavigationClearanceSubcells or 0))
		)
		local pillarDoorClearance = math.max(
			0,
			math.floor(asNumber(pillarRules.DoorClearanceSubcells, STRUCTURAL_RULES.DoorClearanceSubcells or 0))
		)
		local function tryPlacePillarAnchor(anchor, allowNavigation, navClearance)
			if stats.structuralPillarCount >= pillarBudget then
				stats.structuralSkippedByBudget += 1
				return false
			end
			if not canPlaceGlobal() then
				stats.structuralSkippedByBudget += 1
				return false
			end

			local x = anchor.x
			local z = anchor.z
			local reservation = pillarReservationForAnchor(anchor, pillarFootprint, pillarRules)
			local reserveFootprint = {
				w = reservation.w,
				d = reservation.d,
				h = math.max(1, math.floor((pillarFootprint and pillarFootprint.h) or 1)),
			}
			local canPlace = DungeonSurfacePlacementModule.CanPlace(state, reservation.x, reservation.z, reserveFootprint, {
				requireSurface = "floor",
				allowNavigation = allowNavigation == true,
				allowDoors = false,
				navigationClearanceSubcells = math.max(0, math.floor(asNumber(navClearance, 0))),
				doorClearanceSubcells = pillarDoorClearance,
			})
			if not canPlace then
				stats.structuralSkippedByOccupancy += 1
				return false
			end

			-- Structural pillars should align deterministically to support rhythm.
			local placement = placementFromVariant(profile, { x = x, z = z }, pillarVariant, "North", nil)
			placement.role = "structural_pillar"
			addUniqueTag(placement.tags, "structural_prop")
			addUniqueTag(placement.tags, "pillar_support")
			placement.structuralReason = anchor.reason
			placement.footprint = cloneFootprint(reserveFootprint)
			placement.structuralReserve = {
				x = reservation.x,
				z = reservation.z,
				w = reservation.w,
				d = reservation.d,
			}
			DungeonSurfacePlacementModule.AddPlacement(
				state,
				placement,
				reserveFootprint,
				"structural_pillar",
				{ x = reservation.x, z = reservation.z }
			)
			DungeonSurfacePlacementModule.MarkAnchor(state, {
				role = "structural_pillar",
				localPos = { x = x, z = z },
				tileId = placement.tileId,
				footprint = cloneFootprint(reserveFootprint),
				reserveOrigin = { x = reservation.x, z = reservation.z },
				layoutPattern = anchor.layoutPattern,
			})
			out[#out + 1] = placement
			stats.structuralPillarCount += 1
			stats.structuralPlacementCount += 1
			return true
		end

		for _, anchor in ipairs(plan.pillarAnchors) do
			if stats.structuralPillarCount >= pillarBudget or not canPlaceGlobal() then
				break
			end
			tryPlacePillarAnchor(anchor, false, pillarNavClearance)
		end

		local relaxedFallbackMinArea = math.max(10, math.floor(asNumber(pillarRules.RelaxedFallbackMinAreaCells, 10)))
		local relaxedFallbackLimit = math.max(1, math.floor(asNumber(pillarRules.RelaxedFallbackMaxPlacements, 2)))
		local relaxedPlaced = 0
		if stats.structuralPillarCount <= 0 and #plan.pillarAnchors > 0 and roomArea >= relaxedFallbackMinArea then
			stats.structuralFallbackRelaxedAttempted = #plan.pillarAnchors
			for _, anchor in ipairs(plan.pillarAnchors) do
				if relaxedPlaced >= relaxedFallbackLimit then
					break
				end
				if stats.structuralPillarCount >= pillarBudget or not canPlaceGlobal() then
					break
				end
				if tryPlacePillarAnchor(anchor, true, 0) then
					relaxedPlaced += 1
				end
			end
			stats.structuralFallbackRelaxedPlaced = relaxedPlaced
		end
	else
		stats.structuralSkippedByVariant += #plan.pillarAnchors
	end

	if #wallVariantPool > 0 then
		for _, anchor in ipairs(plan.wallAnchors) do
			if stats.structuralWallPropCount >= wallBudget then
				stats.structuralSkippedByBudget += 1
				break
			end
			if not canPlaceGlobal() then
				stats.structuralSkippedByBudget += 1
				break
			end
			local x = anchor.x
			local z = anchor.z
			if minWallSpacing > 0 and minDistanceToPlaced(usedWallAnchors, x, z) < minWallSpacing then
				stats.structuralSkippedBySpacing += 1
				continue
			end

			local wallVariant = DungeonVariantModule.SelectVariant(memory, profile.roomId, wallVariantPool, rng, {
				tagBias = {
					wall_prop = 1.3,
					furniture = roomContext.furnitureBias or 1,
					storage = roomContext.clutterBias or 1,
				},
			})
			if not wallVariant or not tagSetContainsAll(wallVariant.tags, wallRules.RequiredTags or { "wall_prop" }) then
				stats.structuralSkippedByVariant += 1
				continue
			end

			local fp = footprintForVariant(wallVariant)
			local canPlace = DungeonSurfacePlacementModule.CanPlace(state, x, z, fp, {
				requireSurface = "wall",
				allowNavigation = false,
				allowDoors = false,
			})
			if not canPlace then
				stats.structuralSkippedByOccupancy += 1
				continue
			end

			local orient = orientationFromWall(anchor, profile)
			local placement = placementFromVariant(profile, { x = x, z = z }, wallVariant, orient, {
				yawDegrees = nil,
			})
			placement.role = "structural_wall_prop"
			addUniqueTag(placement.tags, "structural_prop")
			addUniqueTag(placement.tags, "wall_support")
			placement.structuralReason = anchor.reason
			DungeonSurfacePlacementModule.AddPlacement(state, placement, fp, "structural_wall_prop")
			DungeonSurfacePlacementModule.MarkAnchor(state, {
				role = "structural_wall_prop",
				localPos = { x = x, z = z },
				tileId = placement.tileId,
			})
			out[#out + 1] = placement
			stats.structuralWallPropCount += 1
			stats.structuralPlacementCount += 1
			usedWallAnchors[#usedWallAnchors + 1] = { x = x, z = z }
		end
	else
		stats.structuralSkippedByVariant += #plan.wallAnchors
	end

	return out, stats
end

pickVariant = function(memory, roomId, rng, requiredTags, forbiddenTags, tagBias)
	local tileIds = listTileIds(requiredTags, forbiddenTags)
	if #tileIds == 0 then
		return nil
	end
	local variants = buildVariants(tileIds, 1)
	return DungeonVariantModule.SelectVariant(memory, roomId, variants, rng, {
		tagBias = tagBias,
	})
end

local function placeSingle(state, rng, profile, variant, rules, reserveTag, layoutProfile, placementOptions)
	local baseFootprint = footprintForVariant(variant)
	local resolved = {}
	local rulesTable = rules or {}
	local resolveOrientation = type(placementOptions) == "table" and placementOptions.resolveOrientation
	local resolveFootprint = type(placementOptions) == "table" and placementOptions.resolveFootprint
	local validateCandidate = type(placementOptions) == "table" and placementOptions.validateCandidate
	local useResolvedSweep = (type(resolveOrientation) == "function")
		or (type(resolveFootprint) == "function")
		or (type(validateCandidate) == "function")

	if useResolvedSweep then
		for z = 1, state.depth do
			for x = 1, state.width do
				local pos = { x = x, z = z }
				local orientation = orientationTowardCenter(profile, pos)
				if type(resolveOrientation) == "function" then
					orientation = tostring(resolveOrientation(pos, baseFootprint) or orientation)
				end
				local footprint = baseFootprint
				if type(resolveFootprint) == "function" then
					footprint = cloneFootprint(resolveFootprint(pos, orientation, baseFootprint) or footprint)
				end
				if canPlaceWithClearance(state, x, z, footprint, rulesTable, layoutProfile) then
					local valid = true
					if type(validateCandidate) == "function" then
						valid = (validateCandidate(pos, orientation, footprint) ~= false)
					end
					if valid then
						resolved[#resolved + 1] = {
							x = x,
							z = z,
							orientation = orientation,
							footprint = footprint,
						}
					end
				end
			end
		end
	else
		local candidates = findCandidatesWithClearance(state, baseFootprint, rulesTable, layoutProfile)
		for _, c in ipairs(candidates) do
			resolved[#resolved + 1] = {
				x = c.x,
				z = c.z,
				orientation = orientationTowardCenter(profile, c),
				footprint = baseFootprint,
			}
		end
	end
	if #resolved == 0 then
		return nil
	end

	local pick = resolved[(rng and rng:NextInteger(1, #resolved)) or 1]
	local orientation = tostring(pick.orientation or orientationTowardCenter(profile, pick))
	local chosenFootprint = cloneFootprint(pick.footprint or baseFootprint)
	local wallAnchored = (placementOptions and placementOptions.disableRandomYaw == true) == true
	local yawDegrees = nil
	if variant and variant.randomYaw == true and not wallAnchored then
		yawDegrees = rng:NextNumber(0, 360)
	end
	-- Natural placement: cell-based occupancy stays intact (collision/nav safety), but the
	-- world transform reads localOffset (fraction of a cell) and yawDegrees. Free-standing
	-- props get a small seeded sub-cell nudge + slight rotation so they don't sit dead-center
	-- on the grid. Wall-anchored props are left exactly seated + inward-facing.
	local localOffset = nil
	if not wallAnchored and rng then
		-- Keep a single-cell footprint well within its cell; scale the nudge down for larger
		-- footprints so multi-cell props never drift into a neighbouring reserved cell.
		local fpW = math.max(1, (chosenFootprint and chosenFootprint.w) or 1)
		local fpD = math.max(1, (chosenFootprint and chosenFootprint.d) or 1)
		local jitterX = 0.22 / fpW
		local jitterZ = 0.22 / fpD
		localOffset = {
			x = rng:NextNumber(-jitterX, jitterX),
			z = rng:NextNumber(-jitterZ, jitterZ),
		}
		if yawDegrees == nil then
			-- Props that are not fully random-yaw still get a subtle lean off the cardinal so
			-- rows of identical props stop looking machine-aligned.
			yawDegrees = rng:NextNumber(-9, 9)
		end
	end
	local placement = placementFromVariant(profile, { x = pick.x, z = pick.z }, variant, orientation, {
		yawDegrees = yawDegrees,
		localOffset = localOffset,
	})
	placement.footprint = cloneFootprint(chosenFootprint)
	DungeonSurfacePlacementModule.AddPlacement(state, placement, chosenFootprint, reserveTag or "placed")
	return placement
end

local function computeWallShelfTarget(profile, layoutProfile)
	local rules = (layoutProfile and layoutProfile.WallShelf) or {}
	local minTargets = math.max(1, math.floor(asNumber(rules.MinTargets, 2)))
	local maxTargets = math.max(minTargets, math.floor(asNumber(rules.MaxTargets, minTargets)))
	local areaScale = math.max(0, asNumber(rules.AreaScale, 0.08))
	local scaled = math.floor((normalizedRoomArea(profile) * areaScale) + 0.5)
	return math.clamp(scaled, minTargets, maxTargets)
end

local function buildAnchorPlan(roomContext, roomTypeRecord, profile, layoutProfile)
	local purpose = tostring(roomContext and roomContext.purpose or "")
	local tags = (roomTypeRecord and roomTypeRecord.tags) or {}
	local roomTypeId = tostring(roomTypeRecord and roomTypeRecord.id or "")
	local isLibraryLike = isLibraryLikeRoom(roomContext, roomTypeRecord)
	local isRitualLike = hasAnyTag(tags, { ritual = true, shrine = true }) or hasNeedle(roomTypeId, "shrine")
	local isBarracksLike = hasNeedle(roomTypeId, "barracks")
	local isStorageLike = hasAnyTag(tags, { utility = true, storage = true }) or hasNeedle(roomTypeId, "storage")

	if isLibraryLike then
		return {
			requiredTags = { "library", "wall_prop", "furniture" },
			fallbackTags = { "wall_prop", "furniture" },
			surface = "wall",
			role = "bookshelf_wall",
			target = computeWallShelfTarget(profile, layoutProfile),
		}
	elseif isRitualLike or purpose == "ritual" or purpose == "landmark" then
		return {
			requiredTags = { "central_focus" },
			fallbackTags = { "landmark", "wall_prop" },
			surface = "center",
			role = "focus_anchor",
			target = 1,
		}
	elseif isBarracksLike then
		return {
			requiredTags = { "furniture" },
			fallbackTags = { "storage", "wall_prop" },
			surface = "perimeter",
			role = "desk_cluster",
			target = 2,
		}
	elseif isStorageLike or purpose == "utility" or purpose == "hub" then
		return {
			requiredTags = { "storage", "wall_prop" },
			fallbackTags = { "storage", "furniture" },
			surface = "perimeter",
			role = "desk_cluster",
			target = 2,
		}
	elseif purpose == "reward" then
		return {
			requiredTags = { "reward" },
			fallbackTags = { "storage", "clutter" },
			surface = "corners",
			role = "reward_anchor",
			target = 1,
		}
	end
	return {
		requiredTags = { "wall_prop" },
		fallbackTags = { "clutter" },
		surface = "wall",
		role = "generic_wall",
		target = 1,
	}
end

local function placeAnchorSet(state, rng, profile, roomContext, roomTypeRecord, memory, layoutProfile)
	local plan = buildAnchorPlan(roomContext, roomTypeRecord, profile, layoutProfile)
	local placed = {}

	for _ = 1, plan.target do
		local variant = pickVariant(memory, profile.roomId, rng, plan.requiredTags, { "doorway", "pillar" }, {
			library = roomContext.shelfBias,
			furniture = roomContext.furnitureBias,
			central_focus = roomContext.importance,
		})
		if not variant then
			variant = pickVariant(memory, profile.roomId, rng, plan.fallbackTags, { "doorway", "pillar" }, nil)
		end
		if variant then
			local rules = {
				requireSurface = plan.surface,
				allowNavigation = false,
				allowDoors = false,
				navigationClearanceSubcells = layoutProfile and layoutProfile.NavigationClearanceSubcells or 0,
				doorClearanceSubcells = 1,
			}
			local wallAnchored = plan.surface == "wall" or plan.role == "bookshelf_wall"
			local bookshelfWallFit = plan.role == "bookshelf_wall"
			local placement = placeSingle(state, rng, profile, variant, rules, "anchor", layoutProfile, {
				disableRandomYaw = wallAnchored,
				resolveOrientation = wallAnchored and function(pos, baseFootprint)
					return inwardOrientationForWallCell(state, profile, pos, baseFootprint)
				end or nil,
				resolveFootprint = wallAnchored and function(_, orientation, baseFootprint)
					return orientedFootprintForOrientation(baseFootprint, orientation)
				end or nil,
				validateCandidate = bookshelfWallFit and function(pos, orientation, footprint)
					return isValidWallBookshelfFit(state, pos, orientation, footprint, layoutProfile)
				end or nil,
			})
			if placement then
				placement.role = plan.role
				if wallAnchored then
					placement.orientation = inwardOrientationForWallCell(state, profile, placement.localPos, placement.footprint)
					placement.yawDegrees = nil
				end
				placed[#placed + 1] = placement
				DungeonSurfacePlacementModule.MarkAnchor(state, {
					role = plan.role,
					localPos = { x = placement.localPos.x, z = placement.localPos.z },
					tileId = placement.tileId,
					orientation = placement.orientation,
					wall = wallAnchored and nearestBoundaryWall(state, placement.localPos) or nil,
					footprint = cloneFootprint(placement.footprint),
				})
			end
		end
	end

	return placed
end

local function extendBookshelfRuns(state, rng, profile, memory, roomContext, layoutProfile)
	local runRules = (layoutProfile and layoutProfile.BookshelfRuns) or {}
	if runRules.Enabled ~= true then
		return {}
	end
	if roomContext.shelfBias < 1.1 then
		return {}
	end
	local out = {}
	local shelfVariant = pickVariant(memory, profile.roomId, rng, { "library", "wall_prop", "furniture" }, { "doorway" }, {
		library = roomContext.shelfBias,
	})
	if not shelfVariant then
		return out
	end
	local shelfFootprint = footprintForVariant(shelfVariant)
	local runStep = runStepForFootprint(shelfFootprint)
	local runChance = math.clamp(0.46 * roomContext.shelfBias, 0.35, 0.96)
	local maxRunLength = math.max(
		1,
		math.floor(asNumber(runRules.MaxRunLength, math.floor(1 + (roomContext.shelfBias * 1.7))))
	)
	local allowBidirectional = runRules.AllowBidirectional ~= false
	local placementRules = {
		requireSurface = "wall",
		allowNavigation = false,
		allowDoors = false,
		navigationClearanceSubcells = layoutProfile and layoutProfile.NavigationClearanceSubcells or 0,
		doorClearanceSubcells = 1,
	}

	for _, anchor in ipairs(state.anchors) do
		if anchor.role == "bookshelf_wall" then
			local origin = anchor.localPos
			local orientation = tostring(anchor.orientation or orientationTowardCenter(profile, origin))
			local runFootprint = orientedFootprintForOrientation(shelfFootprint, orientation)
			local axis = runAxisForFacing(orientation)
			local signs = { 1, -1 }
			if rng:NextNumber() < 0.5 then
				signs[1], signs[2] = signs[2], signs[1]
			end
			if not allowBidirectional then
				signs = { signs[1] }
			end

			for _, sign in ipairs(signs) do
				if rng:NextNumber() > runChance then
					continue
				end
				local runLength = rng:NextInteger(1, maxRunLength)
				for step = 1, runLength do
					local tx = origin.x + (axis.x * runStep * step * sign)
					local tz = origin.z + (axis.z * runStep * step * sign)
					if not canPlaceWithClearance(state, tx, tz, runFootprint, placementRules, layoutProfile)
						or not isValidWallBookshelfFit(
							state,
							{ x = tx, z = tz },
							orientation,
							runFootprint,
							layoutProfile
						)
					then
						-- Collapse behavior: stop extending this side at first obstruction to avoid gaps.
						break
					end

					local p = placementFromVariant(profile, { x = tx, z = tz }, shelfVariant, orientation, nil)
					p.role = "bookshelf_wall"
					p.footprint = cloneFootprint(runFootprint)
					DungeonSurfacePlacementModule.AddPlacement(state, p, runFootprint, "shelf_run")
					DungeonSurfacePlacementModule.MarkAnchor(state, {
						role = "bookshelf_wall",
						localPos = { x = tx, z = tz },
						tileId = p.tileId,
						orientation = orientation,
						footprint = cloneFootprint(runFootprint),
					})
					out[#out + 1] = p
				end
			end
		end
	end

	return out
end

local function buildRowCoordinates(shortMin, shortMax, center, spacing, maxRows)
	local possible = {}
	for coord = shortMin, shortMax, spacing do
		possible[#possible + 1] = coord
	end
	if #possible <= 0 then
		return {}
	end

	table.sort(possible, function(a, b)
		local da = math.abs(a - center)
		local db = math.abs(b - center)
		if da ~= db then
			return da < db
		end
		return a < b
	end)

	local picked = {}
	for _, coord in ipairs(possible) do
		local ok = true
		for _, other in ipairs(picked) do
			if math.abs(other - coord) < spacing then
				ok = false
				break
			end
		end
		if ok then
			picked[#picked + 1] = coord
			if #picked >= maxRows then
				break
			end
		end
	end
	table.sort(picked)
	return picked
end

local function placeBookshelfRows(state, rng, profile, memory, roomContext, roomTypeRecord, layoutProfile)
	if not isLibraryLikeRoom(roomContext, roomTypeRecord) and roomContext.shelfBias < 1.2 then
		return {}
	end
	local rowRules = (layoutProfile and layoutProfile.BookshelfRows) or {}
	if rowRules.Enabled ~= true then
		return {}
	end

	local width = math.max(1, math.floor(asNumber(profile and profile.dimensions and profile.dimensions.x, 1)))
	local depth = math.max(1, math.floor(asNumber(profile and profile.dimensions and profile.dimensions.z, 1)))
	local longEdge = math.max(width, depth)
	local minLongEdge = math.max(1, math.floor(asNumber(rowRules.MinLongEdgeSubcells, 20)))
	if longEdge < minLongEdge then
		return {}
	end

	local shelfVariant = pickVariant(memory, profile.roomId, rng, { "library", "wall_prop", "furniture" }, { "doorway" }, {
		library = roomContext.shelfBias + 0.4,
		wall_prop = 1.2,
	})
	if not shelfVariant then
		return {}
	end

	local shelfFootprint = footprintForVariant(shelfVariant)
	local step = math.max(1, math.floor(asNumber(rowRules.StepSubcells, runStepForFootprint(shelfFootprint))))
	local margin = math.max(1, math.floor(asNumber(rowRules.MarginSubcells, 3)))
	local rowSpacing = math.max(step + 1, math.floor(asNumber(rowRules.RowSpacingSubcells, 5)))
	local maxRows = math.max(1, math.floor(asNumber(rowRules.MaxRows, 4)))
	local longAxisX = width >= depth
	local shortSize = longAxisX and depth or width
	local longSize = longAxisX and width or depth
	local shortMin = 1 + margin
	local shortMax = shortSize - margin
	local longMin = 1 + margin
	local longMax = longSize - margin
	if shortMax < shortMin or longMax < longMin then
		return {}
	end

	local rowCoords = buildRowCoordinates(
		shortMin,
		shortMax,
		math.floor((shortMin + shortMax) * 0.5),
		rowSpacing,
		maxRows
	)
	if #rowCoords <= 0 then
		return {}
	end

	local placementRules = {
		requireSurface = "floor",
		allowNavigation = false,
		allowDoors = false,
		navigationClearanceSubcells = layoutProfile and layoutProfile.NavigationClearanceSubcells or 0,
		doorClearanceSubcells = 1,
	}

	local out = {}
	for rowIndex, shortCoord in ipairs(rowCoords) do
		local orientation
		if longAxisX then
			orientation = (rowIndex % 2 == 0) and "North" or "South"
		else
			orientation = (rowIndex % 2 == 0) and "West" or "East"
		end
		local rowFootprint = orientedFootprintForOrientation(shelfFootprint, orientation)
		local seedLong = math.floor((longMin + longMax) * 0.5)
		local seedPlaced = false
		local seedCoord = nil
		for offset = 0, (longMax - longMin) do
			local tries = {}
			if offset == 0 then
				tries[1] = seedLong
			else
				tries[1] = seedLong + offset
				tries[2] = seedLong - offset
			end
			for _, longCoord in ipairs(tries) do
				if longCoord >= longMin and longCoord <= longMax and ((longCoord - longMin) % step == 0) then
					local x = longAxisX and longCoord or shortCoord
					local z = longAxisX and shortCoord or longCoord
					if canPlaceWithClearance(state, x, z, rowFootprint, placementRules, layoutProfile) then
						local p = placementFromVariant(profile, { x = x, z = z }, shelfVariant, orientation, nil)
						p.role = "bookshelf_row"
						p.footprint = cloneFootprint(rowFootprint)
						DungeonSurfacePlacementModule.AddPlacement(state, p, rowFootprint, "shelf_row")
						DungeonSurfacePlacementModule.MarkAnchor(state, {
							role = "bookshelf_row",
							localPos = { x = x, z = z },
							tileId = p.tileId,
							orientation = orientation,
							footprint = cloneFootprint(rowFootprint),
						})
						out[#out + 1] = p
						seedPlaced = true
						seedCoord = longCoord
						break
					end
				end
			end
			if seedPlaced then
				break
			end
		end

		if seedPlaced and seedCoord then
			for _, sign in ipairs({ 1, -1 }) do
				local longCoord = seedCoord + (step * sign)
				while longCoord >= longMin and longCoord <= longMax do
					local x = longAxisX and longCoord or shortCoord
					local z = longAxisX and shortCoord or longCoord
					if not canPlaceWithClearance(state, x, z, rowFootprint, placementRules, layoutProfile) then
						-- Collapse row extension at the first obstruction to avoid disjoint fragments.
						break
					end
					local p = placementFromVariant(profile, { x = x, z = z }, shelfVariant, orientation, nil)
					p.role = "bookshelf_row"
					p.footprint = cloneFootprint(rowFootprint)
					DungeonSurfacePlacementModule.AddPlacement(state, p, rowFootprint, "shelf_row")
					DungeonSurfacePlacementModule.MarkAnchor(state, {
						role = "bookshelf_row",
						localPos = { x = x, z = z },
						tileId = p.tileId,
						orientation = orientation,
						footprint = cloneFootprint(rowFootprint),
					})
					out[#out + 1] = p
					longCoord += step * sign
				end
			end
		end
	end

	return out
end

-- Purposes where free-standing dining furniture (tables + chairs) reads as out of place.
-- Arenas, corridors and stairwells should not be furnished like a dining hall.
local FURNITURE_EXCLUDED_PURPOSES = {
	combat = true,
	boss = true,
	connector = true,
	vertical = true,
}

local function tableAndChairPass(state, rng, profile, memory, roomContext, layoutProfile)
	local out = {}
	if FURNITURE_EXCLUDED_PURPOSES[tostring(roomContext.purpose or "")] then
		return out, {}
	end
	local tableRules = (layoutProfile and layoutProfile.TableLayout) or {}
	local tableVariant = pickVariant(memory, profile.roomId, rng, { "furniture", "surface" }, { "doorway", "library" }, {
		furniture = roomContext.furnitureBias,
		central_focus = roomContext.importance,
	})
	if not tableVariant then
		return out, {}
	end

	local tableFootprint = footprintForVariant(tableVariant)
	local tableCountBase = math.max(1, math.floor(normalizedRoomArea(profile) / 12))
	local tableCount = math.max(1, math.floor(tableCountBase * math.clamp(roomContext.furnitureBias, 0.75, 2.4)))
	tableCount = math.min(tableCount, math.max(1, math.floor(asNumber(tableRules.MaxTables, tableCount))))
	if roomContext.shelfBias >= 1.15 then
		tableCount = math.max(2, tableCount)
	end
	local shelfAnchors = collectAnchorPositionsByRole(state, {
		bookshelf_wall = true,
		bookshelf_row = true,
		structural_wall_prop = true,
	})
	local pillarAnchors = collectAnchorPositionsByRole(state, {
		structural_pillar = true,
	})
	local preferShelfAdjacency = #shelfAnchors > 0
	local nearShelfDistanceCap = math.max(
		4,
		math.floor(asNumber(tableRules.MaxDistanceToShelf, (tableFootprint.w + tableFootprint.d) * 2))
	)
	local strictAnchorDistance = tableRules.StrictAnchorDistance == true

	local shelfRules = {
		requireSurface = "perimeter",
		allowNavigation = false,
		allowDoors = false,
		navigationClearanceSubcells = layoutProfile and layoutProfile.NavigationClearanceSubcells or 0,
		doorClearanceSubcells = 1,
	}
	local centerRules = {
		requireSurface = "center",
		allowNavigation = false,
		allowDoors = false,
		navigationClearanceSubcells = layoutProfile and layoutProfile.NavigationClearanceSubcells or 0,
		doorClearanceSubcells = 1,
	}
	local perimeterRules = {
		requireSurface = "perimeter",
		allowNavigation = false,
		allowDoors = false,
		navigationClearanceSubcells = layoutProfile and layoutProfile.NavigationClearanceSubcells or 0,
		doorClearanceSubcells = 1,
	}

	local tablePlacements = {}
	for _ = 1, tableCount do
		local rules = nil
		if preferShelfAdjacency then
			rules = shelfRules
		else
			rules = (#tablePlacements == 0) and centerRules or perimeterRules
		end
		local candidates = findCandidatesWithClearance(state, tableFootprint, rules, layoutProfile)
		if #candidates == 0 and preferShelfAdjacency then
			candidates = findCandidatesWithClearance(state, tableFootprint, perimeterRules, layoutProfile)
		end
		if #candidates == 0 and rules ~= perimeterRules then
			candidates = findCandidatesWithClearance(state, tableFootprint, perimeterRules, layoutProfile)
		end
		if #candidates == 0 then
			break
		end
		if #pillarAnchors > 0 then
			local minTableToPillar = math.max(2, math.floor(asNumber(tableRules.MinDistanceToPillar, 3)))
			local pillarFiltered = {}
			for _, candidate in ipairs(candidates) do
				local center = centerPointForRect(candidate.x, candidate.z, tableFootprint.w, tableFootprint.d)
				if nearestDistanceToAnchors(pillarAnchors, center) >= minTableToPillar then
					pillarFiltered[#pillarFiltered + 1] = candidate
				end
			end
			if #pillarFiltered > 0 then
				candidates = pillarFiltered
			end
		end

		local pick = pickTableCandidate(
			rng,
			candidates,
			tableFootprint,
			shelfAnchors,
			nearShelfDistanceCap,
			strictAnchorDistance
		)
		if not pick then
			if strictAnchorDistance then
				break
			end
			pick = candidates[rng:NextInteger(1, #candidates)]
		end
		if preferShelfAdjacency and strictAnchorDistance then
			local pickCenter = centerPointForRect(pick.x, pick.z, tableFootprint.w, tableFootprint.d)
			if nearestDistanceToAnchors(shelfAnchors, pickCenter) > nearShelfDistanceCap then
				break
			end
		end
		local placement = placementFromVariant(profile, pick, tableVariant, orientationTowardCenter(profile, pick), {
			yawDegrees = tableVariant.randomYaw == true and rng:NextNumber(0, 360) or nil,
		})
		placement.role = "table_anchor"
		DungeonSurfacePlacementModule.AddPlacement(state, placement, tableFootprint, "table")
		DungeonSurfacePlacementModule.MarkAnchor(state, {
			role = "table_anchor",
			localPos = { x = pick.x, z = pick.z },
			tileId = placement.tileId,
			orientation = placement.orientation,
			footprint = cloneFootprint(tableFootprint),
		})
		tablePlacements[#tablePlacements + 1] = placement
		out[#out + 1] = placement
	end

	local chairVariant = pickVariant(
		memory,
		profile.roomId,
		rng,
		{ "furniture" },
		{ "doorway", "library", "surface", "wall_prop", "storage" },
		{ furniture = roomContext.furnitureBias }
	)
	if not chairVariant then
		return out, tablePlacements
	end
	local chairFootprint = footprintForVariant(chairVariant)
	local globalSeatPositions = {}
	for _, tablePlacement in ipairs(tablePlacements) do
		local tableFp = footprintForVariant(tablePlacement)
		local seatSlots, toward = buildSeatSlots(tablePlacement, tableFp, chairFootprint)
		local placedAround = {}
		local perimeterEstimate = (tableFp.w * 2) + (tableFp.d * 2)
		local maxSeats = math.clamp(math.floor(perimeterEstimate / math.max(1, math.max(chairFootprint.w, chairFootprint.d))), 2, 8)
		local seatsPlacedCount = 0
		for _, pos in ipairs(seatSlots) do
			if seatsPlacedCount >= maxSeats then
				break
			end
			if minDistanceToPlaced(placedAround, pos.x, pos.z) < math.max(1, math.max(chairFootprint.w, chairFootprint.d)) then
				continue
			end
			if minDistanceToPlaced(globalSeatPositions, pos.x, pos.z) < 1 then
				continue
			end
			if canPlaceWithClearance(state, pos.x, pos.z, chairFootprint, {
				requireSurface = "floor",
				allowNavigation = false,
				allowDoors = false,
				navigationClearanceSubcells = layoutProfile and layoutProfile.NavigationClearanceSubcells or 0,
				doorClearanceSubcells = 1,
			}, layoutProfile) then
				local chairPlacement = placementFromVariant(
					profile,
					pos,
					chairVariant,
					orientationTowardTarget(pos, toward),
					{
						yawDegrees = chairVariant.randomYaw == true and rng:NextNumber(0, 360) or nil,
					}
				)
				chairPlacement.role = "table_seat"
				DungeonSurfacePlacementModule.AddPlacement(state, chairPlacement, chairFootprint, "table_seat")
				out[#out + 1] = chairPlacement
				placedAround[#placedAround + 1] = { x = pos.x, z = pos.z }
				globalSeatPositions[#globalSeatPositions + 1] = { x = pos.x, z = pos.z }
				seatsPlacedCount += 1
			end
		end
	end

	return out, tablePlacements
end

local function tabletopScatterPass(state, rng, profile, memory, roomContext, tablePlacements)
	local out = {}
	if type(tablePlacements) ~= "table" or #tablePlacements == 0 then
		return out
	end

	local bookVariant = pickVariant(memory, profile.roomId, rng, { "books" }, { "furniture", "doorway", "cluster" }, {
		books = roomContext.shelfBias,
	})
	local paperVariant = pickVariant(memory, profile.roomId, rng, { "paper" }, { "furniture", "doorway", "cluster" }, {
		paper = roomContext.writingBias,
		writing = roomContext.writingBias,
	})
	if not bookVariant and not paperVariant then
		return out
	end

	for _, tablePlacement in ipairs(tablePlacements) do
		local tableFp = footprintForVariant(tablePlacement)
		local cells = {}
		for ox = 0, tableFp.w - 1 do
			for oz = 0, tableFp.d - 1 do
				cells[#cells + 1] = {
					x = tablePlacement.localPos.x + ox,
					z = tablePlacement.localPos.z + oz,
				}
			end
		end
		local dropCount = rng:NextInteger(1, math.max(2, math.floor(2 + roomContext.writingBias)))
		for _ = 1, dropCount do
			local variant = nil
			if bookVariant and paperVariant then
				variant = (rng:NextNumber() < 0.58) and paperVariant or bookVariant
			else
				variant = bookVariant or paperVariant
			end
			if not variant then
				continue
			end
			local pick = cells[rng:NextInteger(1, #cells)]
			if DungeonSurfacePlacementModule.CanPlace(state, pick.x, pick.z, { w = 1, d = 1 }, {
				allowNavigation = true,
				allowDoors = false,
				allowSoftOverlap = true,
			}) then
				local tabletopPlacement = placementFromVariant(profile, pick, variant, "North", {
					allowCellSharing = true,
					localOffset = {
						x = rng:NextNumber(-0.22, 0.22),
						z = rng:NextNumber(-0.22, 0.22),
					},
					yawDegrees = variant.randomYaw == true and rng:NextNumber(0, 360) or nil,
				})
				tabletopPlacement.surfaceSnap = "raycast"
				tabletopPlacement.role = "tabletop"
				if containsTag(tabletopPlacement.tags, "paper") or containsTag(tabletopPlacement.tags, "writing") then
					DungeonWritingVariantModule.ApplyToPlacement(
						tabletopPlacement,
						DungeonWritingVariantModule.BuildVariant(rng, roomContext)
					)
				end
				DungeonSurfacePlacementModule.AddPlacement(state, tabletopPlacement, { w = 1, d = 1 }, "tabletop")
				out[#out + 1] = tabletopPlacement
			end
		end
	end

	return out
end

-- Purposes that should not receive a rack of storage furniture.
local STORAGE_EXCLUDED_PURPOSES = {
	connector = true,
	vertical = true,
}

local function secondaryFurniturePass(state, rng, profile, memory, roomContext, layoutProfile)
	local out = {}
	if STORAGE_EXCLUDED_PURPOSES[tostring(roomContext.purpose or "")] then
		return out
	end

	local utilityVariant = pickVariant(memory, profile.roomId, rng, { "storage" }, { "doorway", "library" }, nil)
	if utilityVariant then
		local footprint = footprintForVariant(utilityVariant)
		local target = math.max(
			2,
			math.floor((normalizedRoomArea(profile) / 20) * math.clamp(roomContext.clutterBias, 0.8, 2.0))
		)
		local targetMin = math.max(2, math.floor(target * 0.8))
		local targetMax = math.max(targetMin, math.floor(target * 1.2))
		local placed = DungeonScatterModule.PlaceScatter(state, rng, profile, {
			tileId = utilityVariant.tileId,
			tileCategory = utilityVariant.category,
			tags = utilityVariant.tags,
			prefabId = utilityVariant.prefabId,
			prefabCandidates = utilityVariant.prefabCandidates,
			countMin = targetMin,
			countMax = targetMax,
			footprint = footprint,
			allowCellSharing = false,
			rules = {
				requireSurface = "perimeter",
				allowNavigation = false,
				allowDoors = false,
				navigationClearanceSubcells = layoutProfile and layoutProfile.NavigationClearanceSubcells or 0,
				doorClearanceSubcells = 1,
			},
			minSpacing = math.max(1, footprint.w),
		})
		for _, p in ipairs(placed) do
			p.role = "secondary_furniture"
			out[#out + 1] = p
		end
	end

	return out
end

local function shuffleList(rng, list)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

local function pickWeightedIndex(rng, list)
	local total = 0
	for _, item in ipairs(list) do
		total += math.max(0.0001, tonumber(item.weight) or 0.0001)
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber(0, total)
	local cursor = 0
	for i, item in ipairs(list) do
		cursor += math.max(0.0001, tonumber(item.weight) or 0.0001)
		if roll <= cursor then
			return i
		end
	end
	return #list
end

local function buildAnchorClusterCandidates(state, anchor, radius, footprint, rules, layoutProfile)
	local out = {}
	local maxRadius = math.max(1, math.floor(asNumber(radius, 1)))
	for x = math.max(1, anchor.x - maxRadius), math.min(state.width, anchor.x + maxRadius) do
		for z = math.max(1, anchor.z - maxRadius), math.min(state.depth, anchor.z + maxRadius) do
			local dx = x - anchor.x
			local dz = z - anchor.z
			local dist2 = (dx * dx) + (dz * dz)
			if dist2 <= (maxRadius * maxRadius) and canPlaceWithClearance(state, x, z, footprint, rules, layoutProfile) then
				local k = string.format("%d,%d", x, z)
				local perimeterBias = (state.surfaces.perimeter[k] and 1.18) or 1.0
				local cornerBias = (state.surfaces.corners[k] and 1.1) or 1.0
				local centerBias = 1 / (1 + dist2)
				out[#out + 1] = {
					x = x,
					z = z,
					weight = centerBias * perimeterBias * cornerBias,
				}
			end
		end
	end
	return out
end

local function anchorClutterPass(state, rng, profile, memory, roomContext, roomTypeRecord, layoutProfile)
	local out = {}
	local clusterRules = (layoutProfile and layoutProfile.AnchorClutter) or {}
	if clusterRules.Enabled ~= true then
		return out
	end

	local bookVariant = pickVariant(
		memory,
		profile.roomId,
		rng,
		{ "cluster", "books" },
		{ "doorway", "wall_prop", "furniture", "central_focus", "storage", "pillar" },
		{
			cluster = roomContext.clutterBias,
			books = roomContext.shelfBias + 0.4,
			library = roomContext.shelfBias + 0.2,
		}
	)
	local debrisVariant = pickVariant(
		memory,
		profile.roomId,
		rng,
		{ "cluster", "debris" },
		{ "doorway", "wall_prop", "furniture", "central_focus", "storage", "pillar" },
		{
			cluster = roomContext.clutterBias + 0.15,
			debris = roomContext.clutterBias,
		}
	)
	local rubbleVariant = pickVariant(
		memory,
		profile.roomId,
		rng,
		{ "cluster", "rubble" },
		{ "doorway", "wall_prop", "furniture", "central_focus", "storage", "pillar" },
		{
			cluster = roomContext.clutterBias + 0.15,
			rubble = roomContext.ruinLevel + 0.2,
		}
	)
	local fallbackClusterVariant = pickVariant(
		memory,
		profile.roomId,
		rng,
		{ "cluster" },
		{ "doorway", "wall_prop", "furniture", "central_focus", "storage", "pillar" },
		{
			cluster = roomContext.clutterBias,
		}
	)
	local variants = {}
	local seenTileId = {}
	local function pushVariant(variant)
		if not variant or seenTileId[variant.tileId] then
			return
		end
		seenTileId[variant.tileId] = true
		variants[#variants + 1] = variant
	end
	if isLibraryLikeRoom(roomContext, roomTypeRecord) then
		pushVariant(bookVariant)
	end
	pushVariant(debrisVariant)
	pushVariant(rubbleVariant)
	pushVariant(fallbackClusterVariant)
	if #variants <= 0 then
		return out
	end

	local anchors = collectAnchorPositionsByRole(state, {
		bookshelf_wall = true,
		bookshelf_row = true,
		table_anchor = true,
		desk_cluster = true,
		structural_wall_prop = true,
	})
	if #anchors <= 0 then
		return out
	end
	shuffleList(rng, anchors)

	local maxClusters = math.max(1, math.floor(asNumber(clusterRules.MaxClusters, 10)))
	local clustersPerAnchor = math.max(1, math.floor(asNumber(clusterRules.ClustersPerAnchor, 1)))
	local itemsPerClusterMin = math.max(1, math.floor(asNumber(clusterRules.ItemsPerClusterMin, 1)))
	local itemsPerClusterMax = math.max(itemsPerClusterMin, math.floor(asNumber(clusterRules.ItemsPerClusterMax, itemsPerClusterMin)))
	local radiusMin = math.max(1, math.floor(asNumber(clusterRules.RadiusMin, 1)))
	local radiusMax = math.max(radiusMin, math.floor(asNumber(clusterRules.RadiusMax, radiusMin)))
	local placedClusters = 0
	local placementRules = {
		requireSurface = "floor",
		allowNavigation = false,
		allowDoors = false,
		navigationClearanceSubcells = layoutProfile and layoutProfile.NavigationClearanceSubcells or 0,
		doorClearanceSubcells = 1,
	}

	for _, anchor in ipairs(anchors) do
		for _ = 1, clustersPerAnchor do
			if placedClusters >= maxClusters then
				break
			end
			local radius = rng:NextInteger(radiusMin, radiusMax)
			local itemCount = rng:NextInteger(itemsPerClusterMin, itemsPerClusterMax)
			-- One dominant variant per cluster so a pile reads as a pile of one thing, not a
			-- random interleave of books + debris + rubble. Shared yaw keeps the cluster coherent.
			local clusterVariant = variants[rng:NextInteger(1, #variants)]
			local clusterYaw = clusterVariant.randomYaw == true and rng:NextNumber(0, 360) or nil
			for _ = 1, itemCount do
				local variant = clusterVariant
				local footprint = footprintForVariant(variant)
				local candidates = buildAnchorClusterCandidates(
					state,
					anchor,
					radius,
					footprint,
					placementRules,
					layoutProfile
				)
				if #candidates <= 0 then
					break
				end
				local pickIndex = pickWeightedIndex(rng, candidates)
				if not pickIndex then
					break
				end
				local pick = candidates[pickIndex]
				local itemYaw = clusterYaw
				if itemYaw ~= nil then
					itemYaw = (itemYaw + rng:NextNumber(-18, 18)) % 360
				end
				local p = placementFromVariant(profile, { x = pick.x, z = pick.z }, variant, "North", {
					allowCellSharing = false,
					localOffset = {
						x = rng:NextNumber(-0.1, 0.1),
						z = rng:NextNumber(-0.1, 0.1),
					},
					yawDegrees = itemYaw,
				})
				p.role = "anchor_cluster"
				p.surfaceSnap = "raycast"
				DungeonSurfacePlacementModule.AddPlacement(state, p, footprint, "anchor_clutter")
				out[#out + 1] = p
			end
			placedClusters += 1
		end
		if placedClusters >= maxClusters then
			break
		end
	end

	return out
end

local function microWritingPass(state, rng, profile, memory, roomContext, layoutProfile)
	-- Micro details are surface-attached only (tabletop/shelf), never floor-scattered.
	return {}
end

local function messAndRuinPass(state, rng, profile, memory, roomContext, roomTypeRecord, layoutProfile)
	local out = {}
	local ruinLevel = roomContext.ruinLevel or 0
	if ruinLevel < 0.2 then
		return out
	end

	local dominant = pickVariant(
		memory,
		profile.roomId,
		rng,
		{ "cluster", "books" },
		{ "doorway", "wall_prop", "furniture", "surface", "central_focus", "pillar" },
		{ cluster = roomContext.clutterBias, books = roomContext.shelfBias + 0.35 }
	)
	if not dominant then
		dominant = pickVariant(
			memory,
			profile.roomId,
			rng,
			{ "cluster", "debris" },
			{ "doorway", "wall_prop", "furniture", "surface", "central_focus", "pillar" },
			{ cluster = roomContext.clutterBias + 0.15, debris = roomContext.clutterBias }
		)
	end
	if not dominant then
		dominant = pickVariant(
			memory,
			profile.roomId,
			rng,
			{ "cluster", "rubble" },
			{ "doorway", "wall_prop", "furniture", "surface", "central_focus", "library", "pillar" },
			{ cluster = roomContext.clutterBias, rubble = roomContext.ruinLevel + 0.2 }
		)
	end
	local fillerA = pickVariant(
		memory,
		profile.roomId,
		rng,
		{ "cluster", "debris" },
		{ "doorway", "wall_prop", "furniture", "surface", "central_focus", "pillar" },
		{ cluster = roomContext.clutterBias }
	)
	local fillerB = pickVariant(
		memory,
		profile.roomId,
		rng,
		{ "cluster", "rubble" },
		{ "doorway", "central_focus", "wall_prop", "furniture", "surface", "library", "pillar" },
		{ cluster = roomContext.clutterBias }
	)

	if not dominant then
		return out
	end

	local anchorCandidates = collectMessAnchorCandidates(state)
	if #anchorCandidates <= 0 then
		-- Do not fall back to random floor anchors; mess must reinforce existing compositions.
		return out
	end
	local messNavClearance = math.max(
		0,
		math.floor(asNumber(layoutProfile and layoutProfile.NavigationClearanceSubcells, 0))
	)
	local pileCount = math.max(1, math.floor(1 + (ruinLevel * 4)))
	for _ = 1, pileCount do
		local fillers = {}
		if fillerA then
			fillers[#fillers + 1] = {
				tileId = fillerA.tileId,
				tileCategory = fillerA.category,
				tags = fillerA.tags,
				prefabId = fillerA.prefabId,
				prefabCandidates = fillerA.prefabCandidates,
				countMin = 0,
				countMax = 2,
				allowCellSharing = false,
				radius = 2,
				jitter = 0.14,
				surfaceSnap = "raycast",
				navigationClearanceSubcells = messNavClearance,
				doorClearanceSubcells = 1,
			}
		end
		if fillerB then
			fillers[#fillers + 1] = {
				tileId = fillerB.tileId,
				tileCategory = fillerB.category,
				tags = fillerB.tags,
				prefabId = fillerB.prefabId,
				prefabCandidates = fillerB.prefabCandidates,
				countMin = 0,
				countMax = 1,
				allowCellSharing = false,
				radius = 3,
				jitter = 0.14,
				surfaceSnap = "raycast",
				navigationClearanceSubcells = messNavClearance,
				doorClearanceSubcells = 1,
			}
		end

		local pilePlacements = DungeonMessPileModule.BuildPile(state, rng, profile, {
			dominant = {
				tileId = dominant.tileId,
				tileCategory = dominant.category,
				tags = dominant.tags,
				prefabId = dominant.prefabId,
				prefabCandidates = dominant.prefabCandidates,
				requireSurface = "floor",
				surfaceSnap = "raycast",
				navigationClearanceSubcells = messNavClearance,
				doorClearanceSubcells = 1,
			},
			anchorCandidates = anchorCandidates,
			fillers = fillers,
		})
		for _, p in ipairs(pilePlacements) do
			out[#out + 1] = p
		end
	end

	return out
end

function DungeonDecorationModule.DecorateRoom(input)
	local profile = input.profile
	local baseBlueprint = input.baseBlueprint
	local roomTypeRecord = input.roomTypeRecord or {}
	local archetypeRecord = input.archetypeRecord or {}
	local seed = tonumber(input.seed) or 1
	local rng = input.rng or Random.new(seed)
	local sharedMemory = input.sharedMemory or DungeonVariantModule.NewMemory()

	local roomContext = input.roomContext or DungeonArchetypeModule.BuildRoomContext({
		roomTypeRecord = roomTypeRecord,
		archetypeRecord = archetypeRecord,
		profile = profile,
		seed = seed + 171,
		rng = rng,
	})
	roomContext.surfaceScanYieldInterval = math.max(
		64,
		math.floor(asNumber(STRUCTURAL_RULES.ScanYieldInterval, roomContext.surfaceScanYieldInterval or 320))
	)
	local layoutProfile = resolveLayoutProfile(roomContext, roomTypeRecord)
	currentRoomPurpose = roomContext.purpose and tostring(roomContext.purpose) or nil

	local state = DungeonSurfacePlacementModule.BuildState(profile, baseBlueprint, roomContext)
	local additions = {}
	local passCounts = {
		structural = 0,
		major = 0,
		cluster = 0,
		micro = 0,
	}
	profileBegin("WorldGeneration_Pillars")
	local structural, structuralStats = placeStructuralSupports(
		state,
		rng,
		profile,
		roomContext,
		sharedMemory,
		roomTypeRecord,
		archetypeRecord
	)
	profileEnd()
	appendPassPlacements(additions, structural, "structural", passCounts)

	local passBudgets = resolvePassBudgets(layoutProfile, profile, structuralStats)

	-- Major layout pass: anchors + shelves + table clusters + secondary furniture.
	local anchors = placeAnchorSet(state, rng, profile, roomContext, roomTypeRecord, sharedMemory, layoutProfile)
	appendPassPlacements(additions, anchors, "major", passCounts)

	profileBegin("WorldGeneration_Bookshelves")
	local shelfRuns = extendBookshelfRuns(state, rng, profile, sharedMemory, roomContext, layoutProfile)
	appendPassPlacements(additions, shelfRuns, "major", passCounts)

	local shelfRows = placeBookshelfRows(state, rng, profile, sharedMemory, roomContext, roomTypeRecord, layoutProfile)
	appendPassPlacements(additions, shelfRows, "major", passCounts)
	profileEnd()

	local tableCluster, tablePlacements = tableAndChairPass(state, rng, profile, sharedMemory, roomContext, layoutProfile)
	appendPassPlacements(additions, tableCluster, "major", passCounts)

	local secondary = secondaryFurniturePass(state, rng, profile, sharedMemory, roomContext, layoutProfile)
	appendPassPlacements(additions, secondary, "major", passCounts)

	-- Cluster pass: anchor-driven piles and ruin pockets.
	local anchorClutter = anchorClutterPass(state, rng, profile, sharedMemory, roomContext, roomTypeRecord, layoutProfile)
	appendPassPlacements(additions, anchorClutter, "cluster", passCounts)

	local ruined = messAndRuinPass(state, rng, profile, sharedMemory, roomContext, roomTypeRecord, layoutProfile)
	appendPassPlacements(additions, ruined, "cluster", passCounts)

	-- Micro detail pass: surface-attached only (tabletop/shelves), never floor scatter.
	local tableSurface = tabletopScatterPass(state, rng, profile, sharedMemory, roomContext, tablePlacements)
	appendPassPlacements(additions, tableSurface, "micro", passCounts)

	local micro = microWritingPass(state, rng, profile, sharedMemory, roomContext, layoutProfile)
	appendPassPlacements(additions, micro, "micro", passCounts)

	-- Final cleanup pass: enforce pass budgets, remove floor micro leaks, remove non-sharing overlaps.
	local cleanedPlacements, cleanupStats = applyDecorCleanup(additions, passBudgets)
	currentRoomPurpose = nil

	return {
		roomContext = roomContext,
		anchors = state.anchors,
		placements = cleanedPlacements,
		stats = {
			additionalPlacements = #cleanedPlacements,
			additionalPlacementsBeforeCleanup = #additions,
			anchorCount = #state.anchors,
			structuralPlacementCount = structuralStats.structuralPlacementCount,
			structuralPillarCount = structuralStats.structuralPillarCount,
			structuralWallPropCount = structuralStats.structuralWallPropCount,
			structuralAnchorPlanPillars = structuralStats.structuralAnchorPlanPillars,
			structuralAnchorPlanWallProps = structuralStats.structuralAnchorPlanWallProps,
			structuralAnchorCandidatesTotal = structuralStats.structuralAnchorCandidatesTotal,
			structuralAnchorCandidatesPillars = structuralStats.structuralAnchorCandidatesPillars,
			structuralAnchorCandidatesWallProps = structuralStats.structuralAnchorCandidatesWallProps,
			structuralSkippedByBudget = structuralStats.structuralSkippedByBudget,
			structuralSkippedByOccupancy = structuralStats.structuralSkippedByOccupancy,
			structuralSkippedByVariant = structuralStats.structuralSkippedByVariant,
			structuralSkippedBySpacing = structuralStats.structuralSkippedBySpacing,
			structuralSkippedNearDoor = structuralStats.structuralSkippedNearDoor,
			structuralSkippedNearNavigation = structuralStats.structuralSkippedNearNavigation,
			structuralPillarLayoutPattern = structuralStats.structuralPillarLayoutPattern,
			structuralPillarReserveSizeSubcells = structuralStats.structuralPillarReserveSizeSubcells,
			structuralPillarSupportCols = structuralStats.structuralPillarSupportCols,
			structuralPillarSupportRows = structuralStats.structuralPillarSupportRows,
			structuralDoorBlockedNorthCells = structuralStats.structuralDoorBlockedNorthCells,
			structuralDoorBlockedSouthCells = structuralStats.structuralDoorBlockedSouthCells,
			structuralDoorBlockedEastCells = structuralStats.structuralDoorBlockedEastCells,
			structuralDoorBlockedWestCells = structuralStats.structuralDoorBlockedWestCells,
			structuralFallbackRelaxedAttempted = structuralStats.structuralFallbackRelaxedAttempted,
			structuralFallbackRelaxedPlaced = structuralStats.structuralFallbackRelaxedPlaced,
			grammarNavClearance = layoutProfile.NavigationClearanceSubcells,
			grammarPurpose = roomContext.purpose,
			grammarRoomType = roomTypeRecord and roomTypeRecord.id or nil,
			purpose = roomContext.purpose,
			condition = roomContext.condition,
			passBudgetStructural = passBudgets.structural,
			passBudgetMajor = passBudgets.major,
			passBudgetCluster = passBudgets.cluster,
			passBudgetMicro = passBudgets.micro,
			passBudgetTotal = passBudgets.total,
			passGeneratedStructural = passCounts.structural,
			passGeneratedMajor = passCounts.major,
			passGeneratedCluster = passCounts.cluster,
			passGeneratedMicro = passCounts.micro,
			passKeptStructural = cleanupStats.structural,
			passKeptMajor = cleanupStats.major,
			passKeptCluster = cleanupStats.cluster,
			passKeptMicro = cleanupStats.micro,
			cleanupTrimmedByBudget = cleanupStats.trimmedByBudget,
			cleanupTrimmedMicroFloor = cleanupStats.trimmedMicroFloor,
			cleanupTrimmedOverlap = cleanupStats.trimmedOverlap,
		},
	}
end

return DungeonDecorationModule

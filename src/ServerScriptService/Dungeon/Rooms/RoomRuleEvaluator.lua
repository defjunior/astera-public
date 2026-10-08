local RoomTypeDB = require(script.Parent.RoomTypeDB)
local RoomPatternLibrary = require(script.Parent.RoomPatternLibrary)

local RoomRuleEvaluator = {}

local function tableCount(value)
	if type(value) ~= "table" then
		return 0
	end
	local count = 0
	for _ in pairs(value) do
		count += 1
	end
	return count
end

local function contains(list, needle)
	if type(list) ~= "table" then
		return false
	end
	for _, item in ipairs(list) do
		if item == needle then
			return true
		end
	end
	return false
end

local function listToSet(list)
	local out = {}
	if type(list) == "table" then
		for _, v in ipairs(list) do
			out[v] = true
		end
	end
	return out
end

local function centerOfBounds(bounds)
	return {
		x = (bounds.min.x + bounds.max.x) * 0.5,
		y = (bounds.min.y + bounds.max.y) * 0.5,
		z = (bounds.min.z + bounds.max.z) * 0.5,
	}
end

local function manhattan(a, b)
	return math.abs(a.x - b.x) + math.abs(a.y - b.y) + math.abs(a.z - b.z)
end

local function candidateCenter(candidate)
	if candidate.center then
		return candidate.center
	end
	if candidate.bounds then
		return centerOfBounds(candidate.bounds)
	end
	return candidate.position or { x = 0, y = 0, z = 0 }
end

local function isLandmark(roomType)
	return roomType and (roomType.category == "Landmark" or contains(roomType.tags, "landmark"))
end

local function getTypeCount(context, roomTypeId)
	if not context or not context.counts or not context.counts.byType then
		return 0
	end
	return context.counts.byType[roomTypeId] or 0
end

local function getFloorTypeCount(context, floor, roomTypeId)
	if not context or not context.counts or not context.counts.byFloor then
		return 0
	end
	local floorMap = context.counts.byFloor[floor]
	if not floorMap then
		return 0
	end
	return floorMap[roomTypeId] or 0
end

local function evaluateBoundsRule(result, roomType, candidate, context)
	if not context or not context.bounds or not candidate or not candidate.bounds then
		return
	end

	if roomType.placementRules.allowEdgeOfMap then
		return
	end

	local bounds = context.bounds
	local c = candidate.bounds
	if c.min.x <= bounds.minX or c.max.x >= bounds.maxX or c.min.z <= bounds.minZ or c.max.z >= bounds.maxZ then
		result.ok = false
		result.reasons[#result.reasons + 1] = "Rejected: room type disallows edge-of-map placement"
	end
end

local function evaluateFrequencyRule(result, roomType, candidate, context)
	local frequency = roomType.frequency or {}
	local currentTypeCount = getTypeCount(context, roomType.id)

	if frequency.maxPerDungeon and currentTypeCount >= frequency.maxPerDungeon then
		result.ok = false
		result.reasons[#result.reasons + 1] = "Rejected: maxPerDungeon reached"
		return
	end

	if frequency.maxPerFloor and candidate.floor ~= nil then
		local perFloorCount = getFloorTypeCount(context, candidate.floor, roomType.id)
		if perFloorCount >= frequency.maxPerFloor then
			result.ok = false
			result.reasons[#result.reasons + 1] = "Rejected: maxPerFloor reached"
			return
		end
	end
end

local function evaluateStackingSupportRule(result, roomType, candidate, context)
	local placementRules = roomType.placementRules or {}

	if not placementRules.allowStacking and candidate and candidate.floor and candidate.floor > 0 then
		result.ok = false
		result.reasons[#result.reasons + 1] = "Rejected: stacking disallowed for this room type"
		return
	end

	if placementRules.requiresSupportBelow and context and type(context.hasSupportBelow) == "function" then
		if not context.hasSupportBelow(candidate) then
			result.ok = false
			result.reasons[#result.reasons + 1] = "Rejected: support-below rule failed"
		end
	end
end

local function evaluateDistanceRules(result, roomType, candidate, context)
	if not context or type(context.placedRooms) ~= "table" then
		return
	end

	local placementRules = roomType.placementRules or {}
	local minSameType = placementRules.minDistanceFromSameType or 0
	local minLandmark = placementRules.minDistanceFromLandmark or 0
	local candidatePos = candidateCenter(candidate)

	for _, placed in ipairs(context.placedRooms) do
		local placedType = RoomTypeDB.Get(placed.typeId)
		local dist = manhattan(candidatePos, candidateCenter(placed))
		if placed.typeId == roomType.id and dist < minSameType then
			result.ok = false
			result.reasons[#result.reasons + 1] = "Rejected: too close to same room type"
			return
		end
		if isLandmark(placedType) and dist < minLandmark then
			result.ok = false
			result.reasons[#result.reasons + 1] = "Rejected: too close to landmark"
			return
		end
	end
end

local function evaluateAdjacencyRules(result, roomType, context)
	if not context or type(context.neighborTypeIds) ~= "table" then
		return
	end

	local connectivityRules = roomType.connectivityRules or {}
	local forbidden = listToSet(connectivityRules.forbiddenNeighbors)
	local preferred = listToSet(connectivityRules.preferredNeighbors)

	local degree = #context.neighborTypeIds
	local minDegree = connectivityRules.minDegree or 0
	local maxDegree = connectivityRules.maxDegree or 999

	if degree < minDegree then
		result.score -= 1.5
		result.reasons[#result.reasons + 1] = "Penalty: below preferred minDegree"
	end
	if degree > maxDegree then
		result.score -= 2.0
		result.reasons[#result.reasons + 1] = "Penalty: above allowed maxDegree"
	end

	local preferredHits = 0
	for _, neighborTypeId in ipairs(context.neighborTypeIds) do
		if forbidden[neighborTypeId] then
			result.ok = false
			result.reasons[#result.reasons + 1] = string.format("Rejected: forbidden neighbor '%s'", neighborTypeId)
			return
		end
		if preferred[neighborTypeId] then
			preferredHits += 1
		end
	end

	if preferredHits > 0 then
		result.score += 0.35 * preferredHits
	end
end

local function evaluatePatternCompatibility(result, roomType, candidate)
	if not candidate then
		return
	end

	if candidate.patternId and not contains(roomType.allowedPatterns, candidate.patternId) then
		result.ok = false
		result.reasons[#result.reasons + 1] = string.format("Rejected: pattern '%s' not allowed for room type", tostring(candidate.patternId))
		return
	end

	if candidate.patternId then
		local pattern = RoomPatternLibrary.Get(candidate.patternId)
		if not pattern then
			result.ok = false
			result.reasons[#result.reasons + 1] = "Rejected: unknown candidate pattern"
			return
		end

		local sb = roomType.sizeBias or {}
		local d = pattern.dimensions or {}
		if sb.minCellsX and d.x < sb.minCellsX then
			result.ok = false
			result.reasons[#result.reasons + 1] = "Rejected: pattern too small on X"
			return
		end
		if sb.maxCellsX and d.x > sb.maxCellsX then
			result.ok = false
			result.reasons[#result.reasons + 1] = "Rejected: pattern too large on X"
			return
		end
		if sb.minCellsY and d.y < sb.minCellsY then
			result.ok = false
			result.reasons[#result.reasons + 1] = "Rejected: pattern too small on Y"
			return
		end
		if sb.maxCellsY and d.y > sb.maxCellsY then
			result.ok = false
			result.reasons[#result.reasons + 1] = "Rejected: pattern too large on Y"
			return
		end
		if sb.minCellsZ and d.z < sb.minCellsZ then
			result.ok = false
			result.reasons[#result.reasons + 1] = "Rejected: pattern too small on Z"
			return
		end
		if sb.maxCellsZ and d.z > sb.maxCellsZ then
			result.ok = false
			result.reasons[#result.reasons + 1] = "Rejected: pattern too large on Z"
			return
		end
	end
end

local function evaluateGridPatternScore(result, archetype, candidate, context)
	if not archetype or not archetype.placementBias then
		return
	end

	local position = candidate and (candidate.position or candidateCenter(candidate))
	if not position then
		return
	end

	local gridPattern = archetype.placementBias.gridPattern
	if gridPattern == "AxisAlignedClusters" then
		local stride = archetype.placementBias.floorStridePreference or 1
		if stride > 0 and (math.abs(position.x) % (stride + 1) == 0 or math.abs(position.z) % (stride + 1) == 0) then
			result.score += 0.35
		end
	elseif gridPattern == "CheckerLattice" then
		if ((position.x + position.z) % 2) == 0 then
			result.score += 0.45
		else
			result.score -= 0.1
		end
	elseif gridPattern == "ConcentricBands" then
		local center
		if context and context.bounds then
			center = {
				x = (context.bounds.minX + context.bounds.maxX) * 0.5,
				y = position.y,
				z = (context.bounds.minZ + context.bounds.maxZ) * 0.5,
			}
		else
			center = { x = 0, y = position.y, z = 0 }
		end
		local radius = math.abs(position.x - center.x) + math.abs(position.z - center.z)
		local band = radius % 4
		if band == 1 or band == 2 then
			result.score += 0.4
		end
	elseif gridPattern == "SoftClusters" then
		local anchors = context and context.clusterAnchors
		if type(anchors) == "table" and #anchors > 0 then
			local best = math.huge
			for _, anchor in ipairs(anchors) do
				local dist = math.abs(position.x - anchor.x) + math.abs(position.z - anchor.z)
				if dist < best then
					best = dist
				end
			end
			result.score += math.max(-0.4, 0.6 - (best * 0.08))
		end
	end
end

function RoomRuleEvaluator.ResolvePatternOptions(roomType, archetype)
	local resolved = {}
	local patternBias = (archetype and archetype.roomPatternBias) or {}

	for _, patternId in ipairs(roomType.allowedPatterns or {}) do
		local pattern = RoomPatternLibrary.Get(patternId)
		if pattern then
			resolved[#resolved + 1] = {
				patternId = patternId,
				weight = (patternBias[patternId] or 1.0),
				pattern = pattern,
			}
		end
	end

	table.sort(resolved, function(a, b)
		if a.weight ~= b.weight then
			return a.weight > b.weight
		end
		return a.patternId < b.patternId
	end)

	return resolved
end

function RoomRuleEvaluator.EvaluateCandidate(input)
	local result = {
		ok = true,
		score = 0,
		reasons = {},
	}

	if type(input) ~= "table" then
		result.ok = false
		result.reasons[#result.reasons + 1] = "Invalid input"
		return result
	end

	local roomType = input.roomType or RoomTypeDB.Get(input.roomTypeId)
	if not roomType then
		result.ok = false
		result.reasons[#result.reasons + 1] = "Missing roomType"
		return result
	end

	local candidate = input.candidate or {}
	local context = input.context or {}

	evaluatePatternCompatibility(result, roomType, candidate)
	if not result.ok then
		return result
	end

	evaluateBoundsRule(result, roomType, candidate, context)
	if not result.ok then
		return result
	end

	evaluateFrequencyRule(result, roomType, candidate, context)
	if not result.ok then
		return result
	end

	evaluateStackingSupportRule(result, roomType, candidate, context)
	if not result.ok then
		return result
	end

	evaluateDistanceRules(result, roomType, candidate, context)
	if not result.ok then
		return result
	end

	evaluateAdjacencyRules(result, roomType, context)
	if not result.ok then
		return result
	end

	result.score += (roomType.frequency and roomType.frequency.baseWeight) or 1.0
	if input.archetype and input.archetype.roomTypeWeights then
		result.score *= (input.archetype.roomTypeWeights[roomType.id] or 0.2)
	end
	evaluateGridPatternScore(result, input.archetype, candidate, context)

	local patternOptions = RoomRuleEvaluator.ResolvePatternOptions(roomType, input.archetype)
	if #patternOptions == 0 then
		result.ok = false
		result.reasons[#result.reasons + 1] = "Rejected: no available pattern options"
		return result
	end

	result.patternOptions = patternOptions
	return result
end

function RoomRuleEvaluator.ScoreRoomTypeForArchetype(archetype, roomTypeId)
	local roomType = RoomTypeDB.Get(roomTypeId)
	if not roomType then
		return 0
	end

	local weight = 1.0
	if archetype and archetype.roomTypeWeights then
		weight = archetype.roomTypeWeights[roomTypeId] or 0
	end

	local base = (roomType.frequency and roomType.frequency.baseWeight) or 1.0
	return base * weight
end

function RoomRuleEvaluator.ListEligibleRoomTypes(archetype, context)
	local out = {}
	for _, roomTypeId in ipairs(RoomTypeDB.ListIds()) do
		local eval = RoomRuleEvaluator.EvaluateCandidate({
			archetype = archetype,
			roomTypeId = roomTypeId,
			context = context,
			candidate = context and context.candidate or {},
		})
		if eval.ok then
			out[#out + 1] = {
				roomTypeId = roomTypeId,
				score = eval.score,
				patternOptions = eval.patternOptions,
			}
		end
	end

	table.sort(out, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.roomTypeId < b.roomTypeId
	end)

	return out
end

function RoomRuleEvaluator.ValidateReferenceIntegrity(archetype)
	local issues = {}

	if archetype and archetype.roomTypeWeights then
		for roomTypeId in pairs(archetype.roomTypeWeights) do
			local roomType = RoomTypeDB.Get(roomTypeId)
			if not roomType then
				issues[#issues + 1] = string.format("Archetype references unknown roomType '%s'", roomTypeId)
			else
				for _, patternId in ipairs(roomType.allowedPatterns or {}) do
					if not RoomPatternLibrary.Get(patternId) then
						issues[#issues + 1] = string.format("RoomType '%s' references unknown pattern '%s'", roomTypeId, patternId)
					end
				end
			end
		end
	end

	return #issues == 0, issues
end

return RoomRuleEvaluator

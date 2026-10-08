local DungeonArchetypeDB = require(script.Parent.Archetypes.DungeonArchetypeDB)
local RoomTypeDB = require(script.Parent.Rooms.RoomTypeDB)
local RoomPatternLibrary = require(script.Parent.Rooms.RoomPatternLibrary)
local RoomRuleEvaluator = require(script.Parent.Rooms.RoomRuleEvaluator)
local ProgressionPlanner = require(script.Parent.Progression.ProgressionPlanner)
local WFCThemeDB = require(script.Parent.WFC.WFCThemeDB)
local WFCTileVocabulary = require(script.Parent.WFC.WFCTileVocabulary)
local WFCRoomDecorator = require(script.Parent.WFC.WFCRoomDecorator)
local DungeonVariantModule = require(script.Parent.Decor.DungeonVariantModule)

local DungeonSystem = {}

local function shallowCopy(source)
	local out = {}
	for key, value in pairs(source or {}) do
		out[key] = value
	end
	return out
end

local function sortedArchetypeIds()
	return DungeonArchetypeDB.ListIds()
end

local function sortedRoomTypeIds()
	return RoomTypeDB.ListIds()
end

local function isTableEmpty(t)
	if type(t) ~= "table" then
		return true
	end
	return next(t) == nil
end

local function contains(list, needle)
	for _, item in ipairs(list or {}) do
		if item == needle then
			return true
		end
	end
	return false
end

local function roomSizeX(room)
	return room.max.x - room.min.x + 1
end

local function roomSizeZ(room)
	return room.max.z - room.min.z + 1
end

local function roomArea(room)
	return roomSizeX(room) * roomSizeZ(room)
end

local function roomAreaAscending(a, b)
	local areaA = roomArea(a)
	local areaB = roomArea(b)
	if areaA ~= areaB then
		return areaA < areaB
	end
	local aId = tonumber(a.id)
	local bId = tonumber(b.id)
	if aId and bId and aId ~= bId then
		return aId < bId
	end
	return tostring(a.id) < tostring(b.id)
end

local function distanceFromRange(value, minValue, maxValue)
	if minValue ~= nil and value < minValue then
		return (minValue - value)
	end
	if maxValue ~= nil and value > maxValue then
		return (value - maxValue)
	end
	return 0
end

local function roomIdSortTuple(id)
	local n = tonumber(id)
	if n ~= nil then
		return 0, n, tostring(id)
	end
	return 1, 0, tostring(id)
end

local function roomIdLess(a, b)
	local aType, aNum, aStr = roomIdSortTuple(a)
	local bType, bNum, bStr = roomIdSortTuple(b)
	if aType ~= bType then
		return aType < bType
	end
	if aNum ~= bNum then
		return aNum < bNum
	end
	return aStr < bStr
end

local function weightedPick(rng, weightedItems, fallback)
	local total = 0
	for _, item in ipairs(weightedItems) do
		total += (item.weight or 0)
	end
	if total <= 0 then
		return fallback
	end

	local roll = rng:NextNumber(0, total)
	local cursor = 0
	for _, item in ipairs(weightedItems) do
		cursor += (item.weight or 0)
		if roll <= cursor then
			return item
		end
	end
	return weightedItems[#weightedItems] or fallback
end

local function pickInRange(rng, rangeDef, fallback)
	if type(rangeDef) ~= "table" then
		return fallback
	end
	local minValue = tonumber(rangeDef.min)
	local maxValue = tonumber(rangeDef.max)
	if not minValue or not maxValue then
		return fallback
	end
	minValue = math.floor(minValue)
	maxValue = math.floor(maxValue)
	if maxValue < minValue then
		minValue, maxValue = maxValue, minValue
	end
	return rng:NextInteger(minValue, maxValue)
end

local function choosePatternAndRotation(roomType, archetype, rng)
	local patternOptions = RoomRuleEvaluator.ResolvePatternOptions(roomType, archetype)
	if #patternOptions == 0 then
		return nil
	end

	local pickedPattern = weightedPick(rng, patternOptions, patternOptions[1])
	local variants = RoomPatternLibrary.EnumerateVariants(pickedPattern.patternId, {
		includeSymmetricDuplicates = false,
	})
	if #variants == 0 then
		return nil
	end

	local pickedVariant = variants[rng:NextInteger(1, #variants)]
	return {
		patternId = pickedPattern.patternId,
		patternWeight = pickedPattern.weight,
		variantRotation = pickedVariant.rotation,
		variantRotationKey = pickedVariant.rotationKey,
		dimensions = shallowCopy(pickedVariant.dimensions),
		family = pickedVariant.family,
	}
end

local function pickFloorForBeat(rng, beat, floorCount, verticalProfile)
	if floorCount <= 1 then
		return 1
	end

	if verticalProfile == "Flat" then
		return 1
	elseif verticalProfile == "Layered" then
		if beat.stage == "Early" then
			return rng:NextInteger(1, math.max(1, math.floor(floorCount * 0.5)))
		elseif beat.stage == "Mid" then
			return rng:NextInteger(1, floorCount)
		end
		return rng:NextInteger(math.max(1, math.ceil(floorCount * 0.5)), floorCount)
	elseif verticalProfile == "Stacked" then
		if beat.stage == "Early" then
			return 1
		elseif beat.stage == "Mid" then
			return math.min(floorCount, 2)
		end
		return floorCount
	elseif verticalProfile == "SpiralBias" then
		local base = ((beat.index - 1) % floorCount) + 1
		return base
	end

	return rng:NextInteger(1, floorCount)
end

local function fallbackRoomTypeId(archetype)
	local bestId = nil
	local bestWeight = -math.huge
	for roomTypeId, weight in pairs(archetype.roomTypeWeights or {}) do
		if weight > bestWeight then
			bestWeight = weight
			bestId = roomTypeId
		end
	end
	return bestId or "small_combat_cell"
end

local function buildGenerationPreset(rng, archetype)
	local preset = archetype.parameterPreset or {}
	local roomCount = pickInRange(rng, preset.roomCountRange, 24)
	local floorCount = pickInRange(rng, preset.floorCountRange, 2)

	return {
		roomCount = roomCount,
		gridHeight = floorCount,
		maxRoomEntrances = preset.maxRoomEntrances or 2,
		minInterFloorEdges = preset.minInterFloorEdges or 0,
		minFlatStepsBetweenStairs = preset.minFlatStepsBetweenStairs or 2,
		targetLoopCount = preset.targetLoopCount or 0,
	}
end

local function buildDegreeByRoomId(finalEdges)
	local degreeByRoomId = {}
	for _, edge in ipairs(finalEdges or {}) do
		degreeByRoomId[edge.roomAId] = (degreeByRoomId[edge.roomAId] or 0) + 1
		degreeByRoomId[edge.roomBId] = (degreeByRoomId[edge.roomBId] or 0) + 1
	end
	return degreeByRoomId
end

local function buildRoomById(rooms)
	local roomById = {}
	for _, room in ipairs(rooms or {}) do
		roomById[room.id] = room
	end
	return roomById
end

local function sortedRoomIds(rooms)
	local ids = {}
	for _, room in ipairs(rooms or {}) do
		ids[#ids + 1] = room.id
	end
	table.sort(ids, roomIdLess)
	return ids
end

local function scoreRoomForIntent(room, intent, roomTypeRecord, degree, entranceCount)
	local score = 0
	local width = roomSizeX(room)
	local depth = roomSizeZ(room)
	local area = width * depth
	local floor = (room.center and room.center.y or room.min.y) + 1

	if intent.dimensions then
		score -= math.abs(width - intent.dimensions.x) * 0.9
		score -= math.abs(depth - intent.dimensions.z) * 0.9
	end

	local sizeBias = roomTypeRecord and roomTypeRecord.sizeBias or {}
	score -= distanceFromRange(width, sizeBias.minCellsX, sizeBias.maxCellsX) * 1.2
	score -= distanceFromRange(depth, sizeBias.minCellsZ, sizeBias.maxCellsZ) * 1.2

	local connectivityRules = roomTypeRecord and roomTypeRecord.connectivityRules or {}
	local minDegree = connectivityRules.minDegree or 0
	local maxDegree = connectivityRules.maxDegree or math.huge
	score -= distanceFromRange(degree, minDegree, maxDegree) * 1.35
	if degree >= minDegree and degree <= maxDegree then
		score += 0.55
	end

	local entrances = roomTypeRecord and roomTypeRecord.entrances or {}
	local minEntrances = entrances.min or 1
	local maxEntrances = entrances.max or math.huge
	score -= distanceFromRange(entranceCount, minEntrances, maxEntrances) * 0.8

	if intent.floorHint ~= nil then
		score -= math.abs(floor - intent.floorHint) * 0.8
	end

	local category = intent.roomTypeCategory
	if category == "Connector" then
		score += degree * 0.6
		if area <= 8 then
			score += 0.4
		end
	elseif category == "Hub" then
		score += (area * 0.11)
		if degree >= 2 then
			score += 0.65
		end
	elseif category == "Landmark" or category == "Special" then
		score += (area * 0.13)
	elseif category == "Utility" then
		if area <= 9 then
			score += 0.3
		end
	end

	if intent.beatType == "Boss" then
		score += (area * 0.25)
		score -= math.abs(degree - 2) * 0.9
	elseif intent.beatType == "Reward" then
		score += (area * 0.1)
		if degree <= 2 then
			score += 0.5
		end
	elseif intent.beatType == "Gate" then
		score += degree * 0.4
		if contains(intent.tags, "stairs") or contains(intent.tags, "vertical") then
			score += floor * 0.25
		end
	elseif intent.beatType == "Start" then
		score -= math.abs(floor - 1) * 0.8
		score -= math.abs(degree - 2) * 0.4
	elseif intent.beatType == "Encounter" then
		score += math.min(area, 12) * 0.08
	end

	return score
end

local function validateAllSpecs()
	local issues = {}

	local okRoom, roomIssues = RoomTypeDB.Validate()
	if not okRoom then
		for _, issue in ipairs(roomIssues) do
			issues[#issues + 1] = "[RoomTypeDB] " .. issue
		end
	end

	local okPattern, patternIssues = RoomPatternLibrary.Validate()
	if not okPattern then
		for _, issue in ipairs(patternIssues) do
			issues[#issues + 1] = "[RoomPatternLibrary] " .. issue
		end
	end

	local okTileVocabulary, tileIssues = WFCTileVocabulary.Validate()
	if not okTileVocabulary then
		for _, issue in ipairs(tileIssues) do
			issues[#issues + 1] = "[WFCTileVocabulary] " .. issue
		end
	end

	local okThemeDB, themeIssues = WFCThemeDB.Validate()
	if not okThemeDB then
		for _, issue in ipairs(themeIssues) do
			issues[#issues + 1] = "[WFCThemeDB] " .. issue
		end
	end

	local okArchetype, archetypeIssues = DungeonArchetypeDB.Validate()
	if not okArchetype then
		for _, issue in ipairs(archetypeIssues) do
			issues[#issues + 1] = "[DungeonArchetypeDB] " .. issue
		end
	end

	for _, archetypeId in ipairs(DungeonArchetypeDB.ListIds()) do
		local archetype = DungeonArchetypeDB.Get(archetypeId)
		local okRefs, refIssues = RoomRuleEvaluator.ValidateReferenceIntegrity(archetype)
		if not okRefs then
			for _, issue in ipairs(refIssues) do
				issues[#issues + 1] = string.format("[%s] %s", archetypeId, issue)
			end
		end
	end

	return #issues == 0, issues
end

function DungeonSystem.BuildContentPlan(options)
	local archetypeId = (options and options.archetypeId) or "ruined_keep"
	local archetype = DungeonArchetypeDB.Get(archetypeId)
	assert(archetype, string.format("DungeonSystem.BuildContentPlan: unknown archetype '%s'", tostring(archetypeId)))

	local seed = (options and options.seed) or 1
	local rng = Random.new(seed)
	local progressionPlan = ProgressionPlanner.BuildPlan(archetype, {
		seed = seed,
		targetRoomCount = options and options.targetRoomCount or nil,
	})

	local generationPreset = buildGenerationPreset(rng, archetype)
	local floorCount = math.max(1, generationPreset.gridHeight)
	local fallbackTypeId = fallbackRoomTypeId(archetype)

	local roomIntents = {}
	for _, beat in ipairs(progressionPlan.beats) do
		local roomTypeId = beat.selectedRoomTypeId or fallbackTypeId
		local roomType = RoomTypeDB.Get(roomTypeId) or RoomTypeDB.Get(fallbackTypeId)
		local patternPick = choosePatternAndRotation(roomType, archetype, rng)
		local floorHint = pickFloorForBeat(rng, beat, floorCount, archetype.verticalProfile)

		roomIntents[#roomIntents + 1] = {
			index = beat.index,
			stage = beat.stage,
			beatType = beat.beatType,
			roomTypeId = roomType.id,
			roomTypeCategory = roomType.category,
			patternId = patternPick and patternPick.patternId or nil,
			patternFamily = patternPick and patternPick.family or nil,
			rotation = patternPick and patternPick.variantRotation or 0,
			rotationKey = patternPick and patternPick.variantRotationKey or "r0",
			dimensions = patternPick and patternPick.dimensions or nil,
			floorHint = floorHint,
			isCompound = patternPick and patternPick.family == "Compound" or false,
			tags = shallowCopy(roomType.tags),
			requiredEntrances = roomType.entrances and roomType.entrances.min or 1,
			maxEntrances = roomType.entrances and roomType.entrances.max or 2,
		}
	end

	return {
		systemVersion = 1,
		seed = seed,
		archetypeId = archetype.id,
		archetypeName = archetype.displayName,
		progressionPlan = progressionPlan,
		roomIntents = roomIntents,
		generationPreset = generationPreset,
	}
end

function DungeonSystem.BuildGeneratorConfig(options)
	local contentPlan = (options and options.contentPlan) or DungeonSystem.BuildContentPlan(options)
	local baseConfig = shallowCopy(options and options.baseConfig or {})
	local preset = contentPlan.generationPreset or {}
	local archetype = DungeonArchetypeDB.Get(contentPlan.archetypeId)
	local preferBase = options and options.preferBaseValues == true

	local function applyNumberField(fieldName)
		if preferBase and baseConfig[fieldName] ~= nil then
			return
		end
		if preset[fieldName] ~= nil then
			baseConfig[fieldName] = preset[fieldName]
		end
	end

	applyNumberField("roomCount")
	applyNumberField("gridHeight")
	applyNumberField("maxRoomEntrances")
	applyNumberField("minInterFloorEdges")
	applyNumberField("minFlatStepsBetweenStairs")

	if (not preferBase) or baseConfig.minExtraLoopEdges == nil then
		local targetLoopCount = tonumber(preset.targetLoopCount)
		if targetLoopCount then
			targetLoopCount = math.max(0, math.floor(targetLoopCount))
			baseConfig.minExtraLoopEdges = math.max(targetLoopCount, tonumber(baseConfig.minExtraLoopEdges) or 0)
		end
	end

	if (not preferBase) or baseConfig.maxExtraLoopEdges == nil then
		local targetLoopCount = tonumber(preset.targetLoopCount)
		if targetLoopCount then
			targetLoopCount = math.max(0, math.floor(targetLoopCount))
			baseConfig.maxExtraLoopEdges = math.max(targetLoopCount, targetLoopCount * 2)
		end
	end

	if archetype and archetype.connectivity then
		if ((not preferBase) or baseConfig.extraEdgeChance == nil) and archetype.connectivity.extraLoopChance ~= nil then
			baseConfig.extraEdgeChance = archetype.connectivity.extraLoopChance
		end
		if ((not preferBase) or baseConfig.minInterFloorEdges == nil) and archetype.connectivity.crossFloorConnectorChance then
			local floorCount = tonumber(baseConfig.gridHeight) or tonumber(preset.gridHeight) or 1
			local estimated = math.floor((floorCount - 1) * archetype.connectivity.crossFloorConnectorChance * 6 + 0.5)
			baseConfig.minInterFloorEdges = math.max(tonumber(baseConfig.minInterFloorEdges) or 0, estimated)
		end
	end

	return {
		contentPlan = contentPlan,
		config = baseConfig,
	}
end

local function inferFallbackTypeForPlacedRoom(room)
	local width = room.max.x - room.min.x + 1
	local depth = room.max.z - room.min.z + 1
	local area = width * depth
	if area <= 6 then
		return "small_combat_cell"
	elseif area >= 10 then
		return "combat_chamber_medium"
	end
	return "small_combat_cell"
end

local function compactDecorateResult(decorateResult, includeSolveArtifacts)
	local compact = {
		seed = decorateResult.seed,
		profile = decorateResult.profile,
		theme = decorateResult.theme,
		blueprint = decorateResult.blueprint,
		roomContext = decorateResult.roomContext,
	}
	if includeSolveArtifacts then
		compact.model = decorateResult.model
		compact.solveResult = decorateResult.solveResult
		compact.resolvedResult = decorateResult.resolvedResult
		compact.layeredDecor = decorateResult.layeredDecor
		compact.debugSummary = decorateResult.debugSummary
	end
	return compact
end

local function isInsideRoom(room, pos)
	return pos.x >= room.min.x and pos.x <= room.max.x
		and pos.y >= room.min.y and pos.y <= room.max.y
		and pos.z >= room.min.z and pos.z <= room.max.z
end

local function findRoomIdForCell(roomById, pos)
	for roomId, room in pairs(roomById) do
		if isInsideRoom(room, pos) then
			return roomId
		end
	end
	return nil
end

function DungeonSystem.BuildEntrancesByRoomIdFromDoorways(doorwaysData, rooms)
	local roomById = {}
	for _, room in ipairs(rooms or {}) do
		roomById[room.id] = room
	end

	local entrancesByRoomId = {}
	local seenByRoomId = {}
	for _, doorway in ipairs(doorwaysData or {}) do
		local roomCell = doorway.roomCell
		if roomCell then
			local roomId = findRoomIdForCell(roomById, roomCell)
			if roomId then
				if not entrancesByRoomId[roomId] then
					entrancesByRoomId[roomId] = {}
					seenByRoomId[roomId] = {}
				end
				local key = string.format("%d,%d,%d|%s", roomCell.x, roomCell.y, roomCell.z, tostring(doorway.face))
				if not seenByRoomId[roomId][key] then
					seenByRoomId[roomId][key] = true
					entrancesByRoomId[roomId][#entrancesByRoomId[roomId] + 1] = {
						roomCell = {
							x = roomCell.x,
							y = roomCell.y,
							z = roomCell.z,
						},
						transitCell = doorway.transitCell and {
							x = doorway.transitCell.x,
							y = doorway.transitCell.y,
							z = doorway.transitCell.z,
						} or nil,
						dir = doorway.face,
					}
				end
			end
		end
	end

	return entrancesByRoomId
end

function DungeonSystem.AssignRoomIntentsToPlacedRooms(options)
	assert(type(options) == "table", "DungeonSystem.AssignRoomIntentsToPlacedRooms requires options")
	assert(type(options.placedRooms) == "table", "DungeonSystem.AssignRoomIntentsToPlacedRooms requires placedRooms")

	local roomIntents = options.roomIntents or {}
	local fallbackTypeId = options.fallbackRoomTypeId or "small_combat_cell"
	local degreeByRoomId = options.degreeByRoomId or buildDegreeByRoomId(options.finalEdges)
	local entrancesByRoomId = options.entrancesByRoomId or {}

	local roomById = buildRoomById(options.placedRooms)
	local unassignedRoomIds = sortedRoomIds(options.placedRooms)
	local roomTypeByRoomId = shallowCopy(options.roomTypeByRoomId or {})
	local assignments = {}
	local unmatchedIntentIndices = {}

	local function consumeRoom(roomId)
		for i, id in ipairs(unassignedRoomIds) do
			if id == roomId then
				table.remove(unassignedRoomIds, i)
				return true
			end
		end
		return false
	end

	for roomId in pairs(roomTypeByRoomId) do
		consumeRoom(roomId)
	end

	for _, intent in ipairs(roomIntents) do
		local roomTypeRecord = RoomTypeDB.Get(intent.roomTypeId) or RoomTypeDB.Get(fallbackTypeId)
		local bestRoomId = nil
		local bestScore = -math.huge

		for _, roomId in ipairs(unassignedRoomIds) do
			local room = roomById[roomId]
			local score = scoreRoomForIntent(
				room,
				intent,
				roomTypeRecord,
				degreeByRoomId[roomId] or 0,
				#(entrancesByRoomId[roomId] or {})
			)

			if score > bestScore or (score == bestScore and (bestRoomId == nil or roomIdLess(roomId, bestRoomId))) then
				bestScore = score
				bestRoomId = roomId
			end
		end

		if bestRoomId ~= nil then
			roomTypeByRoomId[bestRoomId] = roomTypeRecord.id
			assignments[#assignments + 1] = {
				intentIndex = intent.index,
				roomId = bestRoomId,
				roomTypeId = roomTypeRecord.id,
				score = bestScore,
			}
			consumeRoom(bestRoomId)
		else
			unmatchedIntentIndices[#unmatchedIntentIndices + 1] = intent.index
		end
	end

	for _, roomId in ipairs(unassignedRoomIds) do
		local room = roomById[roomId]
		local fallbackId = inferFallbackTypeForPlacedRoom(room)
		roomTypeByRoomId[roomId] = fallbackId
		assignments[#assignments + 1] = {
			intentIndex = nil,
			roomId = roomId,
			roomTypeId = fallbackId,
			score = -math.huge,
		}
	end

	table.sort(assignments, function(a, b)
		return roomIdLess(a.roomId, b.roomId)
	end)

	return {
		roomTypeByRoomId = roomTypeByRoomId,
		assignments = assignments,
		unmatchedIntentIndices = unmatchedIntentIndices,
	}
end

function DungeonSystem.DecoratePlacedRooms(options)
	assert(type(options) == "table", "DungeonSystem.DecoratePlacedRooms requires options")
	assert(type(options.placedRooms) == "table", "DungeonSystem.DecoratePlacedRooms requires placedRooms")

	local archetypeId = options.archetypeId or "ruined_keep"
	local archetypeRecord = DungeonArchetypeDB.Get(archetypeId)
	assert(archetypeRecord, string.format("Unknown archetype '%s'", tostring(archetypeId)))

	local seed = options.seed or 1
	local entrancesByRoomId = options.entrancesByRoomId or {}
	local roomTypeByRoomId = shallowCopy(options.roomTypeByRoomId or {})
	local assignmentMeta = nil

	if isTableEmpty(roomTypeByRoomId) and type(options.roomIntents) == "table" then
		assignmentMeta = DungeonSystem.AssignRoomIntentsToPlacedRooms({
			placedRooms = options.placedRooms,
			roomIntents = options.roomIntents,
			finalEdges = options.finalEdges,
			entrancesByRoomId = entrancesByRoomId,
			fallbackRoomTypeId = options.fallbackRoomTypeId,
		})
		roomTypeByRoomId = assignmentMeta.roomTypeByRoomId
	end

	local fallbackTypeId = options.fallbackRoomTypeId or "small_combat_cell"
	local roomLimit = math.max(0, tonumber(options.roomLimit) or 0)
	local yieldInterval = math.max(1, math.floor(tonumber(options.yieldInterval) or 4))
	local innerSolveYieldInterval = math.max(1, math.floor(tonumber(options.solveYieldInterval) or yieldInterval))
	local innerCollapseYieldInterval = math.max(
		1,
		math.floor(tonumber(options.collapseYieldInterval) or math.max(1, math.floor(innerSolveYieldInterval * 0.5)))
	)
	local maxWfcCellsPerRoom = math.max(64, math.floor(tonumber(options.maxWfcCellsPerRoom) or 1600))
	local maxWfcSolveSeconds = tonumber(options.maxWfcSolveSeconds) or 1.25
	local includeSolveArtifacts = options.includeSolveArtifacts == true
	local results = {}
	local failures = {}
	local blueprintsByRoomId = {}
	local decorMemory = DungeonVariantModule.NewMemory()

	local sortedRooms = {}
	for _, room in ipairs(options.placedRooms) do
		sortedRooms[#sortedRooms + 1] = room
	end
	table.sort(sortedRooms, roomAreaAscending)

	WFCTileVocabulary.RefreshDynamicTiles()

	local processed = 0
	for _, room in ipairs(sortedRooms) do
		if roomLimit > 0 and processed >= roomLimit then
			break
		end
		processed += 1
		local roomTypeId = roomTypeByRoomId[room.id] or room.roomTypeId or inferFallbackTypeForPlacedRoom(room) or fallbackTypeId
		local roomTypeRecord = RoomTypeDB.Get(roomTypeId) or RoomTypeDB.Get(fallbackTypeId)
		local roomEntrances = entrancesByRoomId[room.id] or {}
		local roomSeed = (seed + (room.id * 104729)) % 2147483646
		if roomSeed <= 0 then
			roomSeed = 1
		end

		local ok, decorateResult = pcall(function()
			return WFCRoomDecorator.DecorateRoom({
				room = room,
				roomTypeRecord = roomTypeRecord,
				archetypeRecord = archetypeRecord,
				entrances = roomEntrances,
				cellSize = options.cellSize,
				decorDensityScale = options.decorDensityScale,
				decorSubgridScale = options.decorSubgridScale,
				maxWfcCells = maxWfcCellsPerRoom,
				maxSolveSeconds = maxWfcSolveSeconds,
				seed = roomSeed,
			}, {
				seed = roomSeed,
				sharedMemory = decorMemory,
				maxWfcCells = maxWfcCellsPerRoom,
				maxSolveSeconds = maxWfcSolveSeconds,
				yieldInterval = innerSolveYieldInterval,
				collapseYieldInterval = innerCollapseYieldInterval,
			})
		end)

		if ok and decorateResult and decorateResult.blueprint then
			local storedResult = compactDecorateResult(decorateResult, includeSolveArtifacts)
			results[#results + 1] = storedResult
			blueprintsByRoomId[room.id] = storedResult.blueprint
		else
			failures[#failures + 1] = {
				roomId = room.id,
				roomTypeId = roomTypeId,
				error = ok and "Unknown decoration failure" or tostring(decorateResult),
			}
		end

		if processed % yieldInterval == 0 then
			task.wait()
		end
	end

	local roomDecorations = {}
	for _, decorateResult in ipairs(results) do
		local profile = decorateResult.profile or {}
		local roomId = tonumber(profile.roomId) or profile.roomId
		roomDecorations[#roomDecorations + 1] = {
			roomId = roomId,
			roomTypeId = profile.roomType,
			decor = decorateResult,
		}
	end

	return {
		archetypeId = archetypeRecord.id,
		results = results,
		roomDecorations = roomDecorations, -- Backward-compatible shape expected by older builders/tests.
		blueprintsByRoomId = blueprintsByRoomId,
		failures = failures,
		processedRoomCount = processed,
		requestedRoomLimit = roomLimit,
		assignments = assignmentMeta and assignmentMeta.assignments or nil,
	}
end

function DungeonSystem.BuildDungeonSpec(options)
	local contentPlan = DungeonSystem.BuildContentPlan(options)
	local out = {
		contentPlan = contentPlan,
	}
	local shouldDecorate = not (options and options.decorate == false)

	if options and type(options.placedRooms) == "table" then
		local entrancesByRoomId = options.entrancesByRoomId
		if type(entrancesByRoomId) ~= "table" and type(options.doorwaysData) == "table" then
			entrancesByRoomId = DungeonSystem.BuildEntrancesByRoomIdFromDoorways(options.doorwaysData, options.placedRooms)
		end
		entrancesByRoomId = entrancesByRoomId or {}

		local assignmentMeta = DungeonSystem.AssignRoomIntentsToPlacedRooms({
			placedRooms = options.placedRooms,
			roomIntents = contentPlan.roomIntents,
			finalEdges = options.finalEdges,
			entrancesByRoomId = entrancesByRoomId,
		})
		local roomTypeByRoomId = assignmentMeta.roomTypeByRoomId

		local hasAssignmentByRoomId = {}
		for _, assignment in ipairs(assignmentMeta.assignments) do
			hasAssignmentByRoomId[assignment.roomId] = assignment
		end

		for roomId, roomTypeId in pairs(options.roomTypeByRoomId or {}) do
			roomTypeByRoomId[roomId] = roomTypeId
			if hasAssignmentByRoomId[roomId] then
				hasAssignmentByRoomId[roomId].roomTypeId = roomTypeId
			else
				assignmentMeta.assignments[#assignmentMeta.assignments + 1] = {
					intentIndex = nil,
					roomId = roomId,
					roomTypeId = roomTypeId,
					score = math.huge,
				}
			end
		end
		table.sort(assignmentMeta.assignments, function(a, b)
			return roomIdLess(a.roomId, b.roomId)
		end)
		out.roomAssignments = assignmentMeta

		if shouldDecorate then
			out.decor = DungeonSystem.DecoratePlacedRooms({
				archetypeId = contentPlan.archetypeId,
				seed = contentPlan.seed + 911,
				placedRooms = options.placedRooms,
				entrancesByRoomId = entrancesByRoomId,
				roomTypeByRoomId = roomTypeByRoomId,
				roomIntents = contentPlan.roomIntents,
				finalEdges = options.finalEdges,
				roomLimit = options.decorRoomLimit,
				yieldInterval = options.decorYieldInterval,
				solveYieldInterval = options.decorSolveYieldInterval or options.decorYieldInterval,
				collapseYieldInterval = options.decorCollapseYieldInterval or options.decorYieldInterval,
				cellSize = options.cellSize,
				decorDensityScale = options.decorDensityScale,
				decorSubgridScale = options.decorSubgridScale,
				maxWfcCellsPerRoom = options.maxWfcCellsPerRoom,
				maxWfcSolveSeconds = options.maxWfcSolveSeconds,
			})
		end
	end

	return out
end

function DungeonSystem.ValidateAll()
	return validateAllSpecs()
end

function DungeonSystem.ListArchetypeIds()
	return sortedArchetypeIds()
end

function DungeonSystem.ListRoomTypeIds()
	return sortedRoomTypeIds()
end

function DungeonSystem.GetArchetype(archetypeId)
	return DungeonArchetypeDB.Get(archetypeId)
end

function DungeonSystem.GetRoomType(roomTypeId)
	return RoomTypeDB.Get(roomTypeId)
end

return DungeonSystem

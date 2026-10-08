local DungeonTypes = require(script.Parent.DungeonTypes)
local Grid3D = require(script.Parent.Grid3D)
local RoomPlacer = require(script.Parent.RoomPlacer)
local RoomGraphBuilder = require(script.Parent.RoomGraphBuilder)
local HallwayCarver = require(script.Parent.HallwayCarver)
local StairPlanner = require(script.Parent.StairPlanner)
local LayoutBuilder = require(script.Parent.LayoutBuilder)
local DungeonSystem = require(script.Parent.Parent.DungeonSystem)
local DungeonRoofModule = require(script.Parent.Parent.Decor.DungeonRoofModule)
local DungeonData = require(script.Parent.Parent.Data.DungeonData)
local DungeonGenerationContracts = require(script.Parent.DungeonGenerationContracts)
local DungeonParameterMap = require(script.Parent.DungeonParameterMap)
local DungeonBuildState = require(script.Parent.DungeonBuildState)

local DungeonGenerator = {}
DungeonGenerator.__index = DungeonGenerator
DungeonGenerator.Contracts = DungeonGenerationContracts
DungeonGenerator.ParameterMap = DungeonParameterMap

local DEFAULT_CONFIG = DungeonData.DungeonGenerator.DefaultConfig

local function profileBegin(label)
	pcall(debug.profilebegin, label)
end

local function profileEnd()
	pcall(debug.profileend)
end

local PHASE_STEP_NAME = {
	config_normalization = "init",
	content_config = "build_generator_config",
	room_placement = "place_rooms",
	graph_construction = "build_room_graph",
	hallway_carving = "carve_hallways",
	layout_finalization = "build_layout",
	decor_spec = "build_dungeon_spec",
	roof_candidates = "build_roof_plan",
}

local didValidateParameterMap = false

local function shallowCopy(source)
	local out = {}
	for key, value in pairs(source or {}) do
		out[key] = value
	end
	return out
end

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, child in pairs(value) do
		out[key] = deepCopy(child)
	end
	return out
end

local function toNumber(value, fallback)
	if type(value) == "number" and value == value then
		return value
	end
	return fallback
end

local function toInteger(value, fallback, minValue)
	local n = math.floor(toNumber(value, fallback))
	if minValue ~= nil and n < minValue then
		n = minValue
	end
	return n
end

local function toBoolean(value, fallback)
	if value == nil then
		return fallback
	end
	return value == true
end

local function normalizeOrigin(origin)
	if type(origin) == "table" then
		if origin.x and origin.y and origin.z then
			return {
				x = origin.x,
				y = origin.y,
				z = origin.z,
			}
		end
		if origin.X and origin.Y and origin.Z then
			return {
				x = origin.X,
				y = origin.Y,
				z = origin.Z,
			}
		end
	end
	return {
		x = 0,
		y = 0,
		z = 0,
	}
end

local function applyOverworldStyleBias(config)
	local bias = math.clamp(toNumber(config.overworldStyleBias, 0), 0, 1)
	if bias <= 0 then
		return
	end

	config.gridHeight = math.max(1, math.floor((config.gridHeight * (1 - bias)) + 0.5))
	config.minRoomHeight = 1
	config.maxRoomHeight = 1
	config.minInterFloorEdges = math.max(0, math.floor((config.minInterFloorEdges or 0) * (1 - bias)))
	config.graphVerticalWeight = math.max(0.1, (config.graphVerticalWeight or 1) * (1 - (0.55 * bias)))
	config.allowSameFloorStairDetours = false

	local addedPadding = math.floor((bias * 2) + 0.5)
	if addedPadding > 0 then
		config.roomPadding = math.max(config.roomPadding or 0, (DEFAULT_CONFIG.roomPadding or 0) + addedPadding)
	end

	if bias >= 0.25 then
		config.buildingPerimeterHallwayWidth = math.max(config.buildingPerimeterHallwayWidth or 0, 1)
	end
	if bias >= 0.8 then
		config.buildingPerimeterHallwayWidth = math.max(config.buildingPerimeterHallwayWidth or 0, 2)
	end

	local boundaryWindowTarget = (config.windowWallChance or 0) * (0.6 + (0.8 * bias))
	config.roomBoundaryWindowWallChance = math.max(config.roomBoundaryWindowWallChance or 0, boundaryWindowTarget)
end

local function normalizeConfig(configOrRoomCount, minSize, maxSize, maxPosition, floors)
	if type(configOrRoomCount) ~= "table" then
		local legacyRoomCount = toInteger(configOrRoomCount, DEFAULT_CONFIG.roomCount, 0)
		local legacyMinSize = toInteger(minSize, DEFAULT_CONFIG.minRoomSize, 1)
		local legacyMaxSize = toInteger(maxSize, DEFAULT_CONFIG.maxRoomSize, legacyMinSize)
		local legacyMaxPosition = toInteger(maxPosition, DEFAULT_CONFIG.gridWidth, legacyMaxSize)
		local legacyFloors = toInteger(floors, DEFAULT_CONFIG.gridHeight, 1)

		return normalizeConfig({
			roomCount = legacyRoomCount,
			minRoomSize = legacyMinSize,
			maxRoomSize = legacyMaxSize,
			gridWidth = legacyMaxPosition,
			gridDepth = legacyMaxPosition,
			gridHeight = legacyFloors,
			minRoomHeight = 1,
			maxRoomHeight = 1,
		})
	end

	local out = shallowCopy(DEFAULT_CONFIG)
	for key, value in pairs(configOrRoomCount) do
		out[key] = value
	end

	out.roomCount = toInteger(out.roomCount, DEFAULT_CONFIG.roomCount, 0)
	out.minRoomSize = toInteger(out.minRoomSize, DEFAULT_CONFIG.minRoomSize, 1)
	out.maxRoomSize = toInteger(out.maxRoomSize, DEFAULT_CONFIG.maxRoomSize, out.minRoomSize)

	out.gridWidth = toInteger(out.gridWidth, DEFAULT_CONFIG.gridWidth, 1)
	out.gridHeight = toInteger(out.gridHeight, DEFAULT_CONFIG.gridHeight, 1)
	out.gridDepth = toInteger(out.gridDepth, DEFAULT_CONFIG.gridDepth, 1)

	out.minRoomHeight = toInteger(out.minRoomHeight, DEFAULT_CONFIG.minRoomHeight, 1)
	out.maxRoomHeight = toInteger(out.maxRoomHeight, DEFAULT_CONFIG.maxRoomHeight, out.minRoomHeight)

	out.roomPadding = toInteger(out.roomPadding, DEFAULT_CONFIG.roomPadding, 0)
	out.roomPaddingY = toInteger(out.roomPaddingY, DEFAULT_CONFIG.roomPaddingY, 0)
	out.graphNeighborCount = toInteger(out.graphNeighborCount, DEFAULT_CONFIG.graphNeighborCount, 1)
	out.minInterFloorEdges = toInteger(out.minInterFloorEdges, DEFAULT_CONFIG.minInterFloorEdges, 0)
	out.maxRoomEntrances = toInteger(out.maxRoomEntrances, DEFAULT_CONFIG.maxRoomEntrances, 1)
	out.maxRoomPlacementAttempts = toInteger(out.maxRoomPlacementAttempts, DEFAULT_CONFIG.maxRoomPlacementAttempts, 1)
	out.maxPathIterations = toInteger(out.maxPathIterations, DEFAULT_CONFIG.maxPathIterations, 1)
	out.maxVisitedStates = toInteger(out.maxVisitedStates, DEFAULT_CONFIG.maxVisitedStates, 1)
	out.pathYieldInterval = toInteger(out.pathYieldInterval, DEFAULT_CONFIG.pathYieldInterval, 1)
	out.edgeYieldInterval = toInteger(out.edgeYieldInterval, DEFAULT_CONFIG.edgeYieldInterval, 1)
	out.minFlatStepsBetweenStairs = toInteger(out.minFlatStepsBetweenStairs, DEFAULT_CONFIG.minFlatStepsBetweenStairs, 0)
	out.retryMinFlatStepsBetweenStairs = toInteger(
		out.retryMinFlatStepsBetweenStairs,
		DEFAULT_CONFIG.retryMinFlatStepsBetweenStairs,
		0
	)
	out.hallwayCarveRetryCount = toInteger(out.hallwayCarveRetryCount, DEFAULT_CONFIG.hallwayCarveRetryCount, 1)
	out.maxEntranceCandidatesPerRoom = toInteger(
		out.maxEntranceCandidatesPerRoom,
		DEFAULT_CONFIG.maxEntranceCandidatesPerRoom,
		1
	)
	out.maxEntranceCandidatesPerFace = toInteger(
		out.maxEntranceCandidatesPerFace,
		DEFAULT_CONFIG.maxEntranceCandidatesPerFace,
		1
	)
	out.maxEntrancePairAttempts = toInteger(out.maxEntrancePairAttempts, DEFAULT_CONFIG.maxEntrancePairAttempts, 1)
	out.maxEntrancePairAttemptsOnRetry = toInteger(
		out.maxEntrancePairAttemptsOnRetry,
		DEFAULT_CONFIG.maxEntrancePairAttemptsOnRetry,
		1
	)
	out.maxEntrancePairAttemptsOnLastRetry = toInteger(
		out.maxEntrancePairAttemptsOnLastRetry,
		DEFAULT_CONFIG.maxEntrancePairAttemptsOnLastRetry,
		1
	)
	out.dungeonSeedOffset = toInteger(out.dungeonSeedOffset, DEFAULT_CONFIG.dungeonSeedOffset, 0)
	out.decorSeedOffset = toInteger(out.decorSeedOffset, DEFAULT_CONFIG.decorSeedOffset, 0)
	out.decorRoomLimit = toInteger(out.decorRoomLimit, DEFAULT_CONFIG.decorRoomLimit, 0)
	out.decorYieldInterval = toInteger(out.decorYieldInterval, DEFAULT_CONFIG.decorYieldInterval, 1)
	out.decorSolveYieldInterval = toInteger(
		out.decorSolveYieldInterval,
		DEFAULT_CONFIG.decorSolveYieldInterval,
		1
	)
	out.decorCollapseYieldInterval = toInteger(
		out.decorCollapseYieldInterval,
		DEFAULT_CONFIG.decorCollapseYieldInterval,
		1
	)
	out.decorDensityScale = math.max(0.1, toNumber(out.decorDensityScale, DEFAULT_CONFIG.decorDensityScale))
	out.decorSubgridScale = toInteger(out.decorSubgridScale, DEFAULT_CONFIG.decorSubgridScale, 1)
	out.maxWfcCellsPerRoom = toInteger(out.maxWfcCellsPerRoom, DEFAULT_CONFIG.maxWfcCellsPerRoom, 64)
	out.maxWfcSolveSeconds = math.max(0.1, toNumber(out.maxWfcSolveSeconds, DEFAULT_CONFIG.maxWfcSolveSeconds))

	out.cellSize = toNumber(out.cellSize, DEFAULT_CONFIG.cellSize)
	out.extraEdgeChance = math.clamp(toNumber(out.extraEdgeChance, DEFAULT_CONFIG.extraEdgeChance), 0, 1)
	out.windowWallChance = math.clamp(toNumber(out.windowWallChance, DEFAULT_CONFIG.windowWallChance), 0, 1)
	out.roomBoundaryWindowWallChance = math.clamp(
		toNumber(out.roomBoundaryWindowWallChance, DEFAULT_CONFIG.roomBoundaryWindowWallChance),
		0,
		1
	)
	out.buildingPerimeterHallwayWidth = toInteger(
		out.buildingPerimeterHallwayWidth,
		DEFAULT_CONFIG.buildingPerimeterHallwayWidth,
		0
	)
	out.overworldStyleBias = math.clamp(toNumber(out.overworldStyleBias, DEFAULT_CONFIG.overworldStyleBias), 0, 1)
	out.labyrinthBias = math.clamp(toNumber(out.labyrinthBias, DEFAULT_CONFIG.labyrinthBias), 0, 1)
	out.loopChanceBoostPerBias = math.max(0, toNumber(out.loopChanceBoostPerBias, DEFAULT_CONFIG.loopChanceBoostPerBias))
	out.minExtraLoopEdges = toInteger(out.minExtraLoopEdges, DEFAULT_CONFIG.minExtraLoopEdges, 0)
	if out.maxExtraLoopEdges ~= nil then
		out.maxExtraLoopEdges = toInteger(out.maxExtraLoopEdges, 0, 0)
	end
	out.graphVerticalWeight = math.max(0.1, toNumber(out.graphVerticalWeight, DEFAULT_CONFIG.graphVerticalWeight))
	out.walkCost = math.max(0.1, toNumber(out.walkCost, DEFAULT_CONFIG.walkCost))
	out.stairCost = math.max(0.1, toNumber(out.stairCost, DEFAULT_CONFIG.stairCost))
	out.useGlobalStairReservations = toBoolean(out.useGlobalStairReservations, DEFAULT_CONFIG.useGlobalStairReservations)
	out.useGlobalStairReservationsOnLastRetry = toBoolean(
		out.useGlobalStairReservationsOnLastRetry,
		DEFAULT_CONFIG.useGlobalStairReservationsOnLastRetry
	)
	out.allowHallwayDownStairs = toBoolean(out.allowHallwayDownStairs, DEFAULT_CONFIG.allowHallwayDownStairs)
	out.allowHallwayDownStairsOnRetry = toBoolean(
		out.allowHallwayDownStairsOnRetry,
		DEFAULT_CONFIG.allowHallwayDownStairsOnRetry
	)
	out.enforceNearbyStairClearance = toBoolean(
		out.enforceNearbyStairClearance,
		DEFAULT_CONFIG.enforceNearbyStairClearance
	)
	out.enforceNearbyStairClearanceOnRetry = toBoolean(
		out.enforceNearbyStairClearanceOnRetry,
		DEFAULT_CONFIG.enforceNearbyStairClearanceOnRetry
	)
	out.allowSameFloorStairDetours = toBoolean(
		out.allowSameFloorStairDetours,
		DEFAULT_CONFIG.allowSameFloorStairDetours
	)
	out.enableDungeonContentSystem = toBoolean(
		out.enableDungeonContentSystem,
		DEFAULT_CONFIG.enableDungeonContentSystem
	)
	out.enableWFCDecor = toBoolean(out.enableWFCDecor, DEFAULT_CONFIG.enableWFCDecor)
	out.enableRoof = toBoolean(out.enableRoof, DEFAULT_CONFIG.enableRoof)
	if (configOrRoomCount and configOrRoomCount.dungeonArchetypeId == nil) and type(out.decorArchetypeId) == "string" then
		out.dungeonArchetypeId = out.decorArchetypeId
	end
	if type(out.dungeonArchetypeId) ~= "string" or out.dungeonArchetypeId == "" then
		out.dungeonArchetypeId = DEFAULT_CONFIG.dungeonArchetypeId
	end
	if type(out.decorArchetypeId) ~= "string" or out.decorArchetypeId == "" then
		out.decorArchetypeId = DEFAULT_CONFIG.decorArchetypeId
	end
	out.worldOrigin = normalizeOrigin(out.worldOrigin)
	applyOverworldStyleBias(out)

	return out
end

local function normalizeSeed(seedValue)
	local seed = math.floor(tonumber(seedValue) or 1) % 2147483646
	if seed <= 0 then
		seed = 1
	end
	return seed
end

local function countArray(source)
	if type(source) ~= "table" then
		return 0
	end
	return #source
end

local function countMap(source)
	if type(source) ~= "table" then
		return 0
	end
	local count = 0
	for _ in pairs(source) do
		count += 1
	end
	return count
end

local function buildDerivedConfig(config, runSeed)
	local labyrinthBias = math.clamp(toNumber(config.labyrinthBias, DEFAULT_CONFIG.labyrinthBias), 0, 1)
	local loopBoost = math.max(0, toNumber(config.loopChanceBoostPerBias, DEFAULT_CONFIG.loopChanceBoostPerBias))
	local loopChance = math.clamp(toNumber(config.extraEdgeChance, DEFAULT_CONFIG.extraEdgeChance) + (loopBoost * labyrinthBias), 0, 1)
	local gridCellBudget = math.max(1, config.gridWidth * config.gridHeight * config.gridDepth)

	return {
		seeds = {
			runSeed = runSeed,
			systemSeed = normalizeSeed(runSeed + config.dungeonSeedOffset),
			decorSeed = normalizeSeed(runSeed + (config.decorSeedOffset or 0)),
			roofSeed = normalizeSeed(runSeed + (config.decorSeedOffset or 0) + 2971),
		},
		looping = {
			labyrinthBias = labyrinthBias,
			effectiveExtraEdgeChance = loopChance,
		},
		runtimeToggles = {
			shouldBuildDungeonSpec = config.enableDungeonContentSystem or config.enableWFCDecor,
			shouldBuildDecor = config.enableWFCDecor == true,
			shouldBuildRoof = config.enableRoof ~= false,
		},
		cellMetrics = {
			gridCellBudget = gridCellBudget,
			cellSize = config.cellSize,
			worldBoundsStuds = {
				x = config.gridWidth * config.cellSize,
				y = config.gridHeight * config.cellSize,
				z = config.gridDepth * config.cellSize,
			},
		},
	}
end

local function buildEmptyRunContext(config, runSeed, setGenerateStep, startedAt)
	return {
		seed = runSeed,
		startedAt = startedAt,
		setGenerateStep = setGenerateStep,
		inputConfig = config,
		derivedConfig = {},
		generationState = {},
		outputModel = {},
		buildData = {},
		debugInstrumentation = {
			phaseOrder = {},
			phaseTimingsSeconds = {},
			phaseStats = {},
			tableSizes = {},
			parameterValuesUsed = {},
			parameterMapCoverageOk = true,
			parameterMapCoverageMissing = {},
		},
	}
end

local function runPhase(context, phaseId, callback)
	local stepName = PHASE_STEP_NAME[phaseId] or phaseId
	local totalElapsed = os.clock() - context.startedAt
	context.setGenerateStep(stepName, totalElapsed)

	local phaseStartedAt = os.clock()
	context.debugInstrumentation.phaseOrder[#context.debugInstrumentation.phaseOrder + 1] = phaseId

	local packed = table.pack(pcall(callback))
	local phaseElapsed = os.clock() - phaseStartedAt
	context.debugInstrumentation.phaseTimingsSeconds[phaseId] = phaseElapsed

	if not packed[1] then
		error(packed[2])
	end

	return table.unpack(packed, 2, packed.n)
end

local function updateWorkspaceGenerationStats(debugInstrumentation)
	for phaseId, seconds in pairs(debugInstrumentation.phaseTimingsSeconds or {}) do
		DungeonBuildState.set("DungeonGenPhaseSec_" .. tostring(phaseId), tonumber(seconds) or 0)
	end

	local phaseStats = debugInstrumentation.phaseStats or {}
	DungeonBuildState.set("DungeonGenRoomsPlaced", tonumber((phaseStats.room_placement or {}).roomsPlaced) or 0)
	DungeonBuildState.set("DungeonGenRoomsRequested", tonumber((phaseStats.room_placement or {}).roomsRequested) or 0)
	DungeonBuildState.set("DungeonGenGraphEdgesFinal", tonumber((phaseStats.graph_construction or {}).finalEdges) or 0)
	DungeonBuildState.set("DungeonGenHallwayEdgesSucceeded", tonumber((phaseStats.hallway_carving or {}).edgesSucceeded) or 0)
	DungeonBuildState.set("DungeonGenDoorwayCount", tonumber((phaseStats.layout_finalization or {}).doorways) or 0)
	DungeonBuildState.set("DungeonGenDecorRoomsProcessed", tonumber((phaseStats.decor_spec or {}).decorRoomsProcessed) or 0)
	DungeonBuildState.set("DungeonGenRoofPlacementCount", tonumber((phaseStats.roof_candidates or {}).roofPlacements) or 0)
end

local function validateParameterMapCoverageOnce()
	if didValidateParameterMap then
		return true, {}
	end
	didValidateParameterMap = true

	local ok, missing = DungeonParameterMap.ValidateCoverage()
	if not ok then
		warn(
			"[DungeonGenerator] DungeonParameterMap is missing explicit mappings for: " .. table.concat(missing, ", ")
		)
	end
	return ok, missing
end

function DungeonGenerator.new(configOrRoomCount, minSize, maxSize, maxPosition, floors)
	local self = setmetatable({}, DungeonGenerator)
	self.config = normalizeConfig(configOrRoomCount, minSize, maxSize, maxPosition, floors)
	return self
end

function DungeonGenerator:GridToWorld(cell)
	local size = self.config.cellSize
	local origin = self.config.worldOrigin
	return {
		x = origin.x + ((cell.x + 0.5) * size),
		y = origin.y + ((cell.y + 0.5) * size),
		z = origin.z + ((cell.z + 0.5) * size),
	}
end

function DungeonGenerator:WorldToGrid(world)
	local size = self.config.cellSize
	local origin = self.config.worldOrigin
	local wx = world.x or world.X
	local wy = world.y or world.Y
	local wz = world.z or world.Z

	return DungeonTypes.Vector3i(
		(wx - origin.x) / size,
		(wy - origin.y) / size,
		(wz - origin.z) / size
	)
end

function DungeonGenerator:Generate(seed)
	local function setGenerateStep(step, elapsed)
		DungeonBuildState.set("DungeonBuildGenerateStep", tostring(step))
		if elapsed ~= nil then
			DungeonBuildState.set("DungeonBuildGenerateStepElapsed", tonumber(elapsed) or 0)
		end
		local writer = _G and _G.DungeonWriteStep
		if type(writer) == "function" then
			writer(
				"DungeonGenerator",
				"step." .. tostring(step),
				string.format("elapsed=%.2fs", tonumber(elapsed) or 0)
			)
		end
	end

	local runSeed = seed
	if type(runSeed) ~= "number" then
		runSeed = os.time()
	end
	runSeed = math.floor(runSeed)

	local startedAt = os.clock()
	local context = buildEmptyRunContext(shallowCopy(self.config), runSeed, setGenerateStep, startedAt)
	local parameterMapCoverageOk, missingMappings = validateParameterMapCoverageOnce()
	context.debugInstrumentation.parameterMapCoverageOk = parameterMapCoverageOk
	context.debugInstrumentation.parameterMapCoverageMissing = missingMappings

	runPhase(context, "config_normalization", function()
		context.inputConfig = normalizeConfig(context.inputConfig)
		context.derivedConfig = buildDerivedConfig(context.inputConfig, context.seed)
		context.debugInstrumentation.phaseStats.config_normalization = {
			gridWidth = context.inputConfig.gridWidth,
			gridHeight = context.inputConfig.gridHeight,
			gridDepth = context.inputConfig.gridDepth,
			roomCount = context.inputConfig.roomCount,
		}
	end)

	local contentPlan = nil
	runPhase(context, "content_config", function()
		local config = shallowCopy(context.inputConfig)
		if config.enableDungeonContentSystem then
			local generatorConfigData = DungeonSystem.BuildGeneratorConfig({
				archetypeId = config.dungeonArchetypeId,
				seed = context.derivedConfig.seeds.systemSeed,
				targetRoomCount = config.roomCount,
				baseConfig = config,
				preferBaseValues = true,
			})
			contentPlan = generatorConfigData.contentPlan
			config = generatorConfigData.config
		end

		context.inputConfig = normalizeConfig(config)
		context.derivedConfig = buildDerivedConfig(context.inputConfig, context.seed)
		context.debugInstrumentation.parameterValuesUsed = DungeonParameterMap.BuildUsedValueSnapshot(context.inputConfig)
		context.debugInstrumentation.phaseStats.content_config = {
			contentSystemEnabled = context.inputConfig.enableDungeonContentSystem == true,
			contentPlanGenerated = contentPlan ~= nil,
			targetRoomCount = context.inputConfig.roomCount,
			dungeonArchetypeId = tostring(context.inputConfig.dungeonArchetypeId),
		}
	end)

	local rng = Random.new(context.seed)
	local config = context.inputConfig

	runPhase(context, "room_placement", function()
		profileBegin("WorldGeneration_Rooms")
		local rooms, placementMeta = RoomPlacer.PlaceRooms(config, rng)
		profileEnd()
		context.generationState.roomPlacement = {
			rooms = rooms,
			placementMeta = placementMeta,
		}
		context.outputModel.roomDefinitions = rooms
		context.debugInstrumentation.phaseStats.room_placement = {
			roomsRequested = placementMeta.requested,
			roomsPlaced = placementMeta.placed,
			placementAttempts = placementMeta.attempts,
			roomsDropped = math.max(0, (placementMeta.requested or 0) - (placementMeta.placed or 0)),
		}
	end)

	runPhase(context, "graph_construction", function()
		local rooms = context.generationState.roomPlacement.rooms
		local graph = RoomGraphBuilder.Build(rooms, config, rng)

		local activeSet = {}
		for _, roomId in ipairs(graph.activeRoomIds or {}) do
			activeSet[roomId] = true
		end

		local activeRooms = {}
		for _, room in ipairs(rooms) do
			if activeSet[room.id] then
				activeRooms[#activeRooms + 1] = room
			end
		end

		local roomById = {}
		for _, room in ipairs(activeRooms) do
			roomById[room.id] = room
		end

		context.generationState.roomLookupById = roomById
		context.outputModel.roomPlacements = activeRooms
		context.outputModel.graph = graph
		context.debugInstrumentation.phaseStats.graph_construction = {
			graphEdges = countArray(graph.graphEdges),
			mstEdges = countArray(graph.mstEdges),
			extraEdges = countArray(graph.extraEdges),
			finalEdges = countArray(graph.finalEdges),
			activeRooms = countArray(activeRooms),
			culledRooms = countArray(graph.culledRoomIds),
		}
	end)

	runPhase(context, "hallway_carving", function()
		local grid = Grid3D.new(config.gridWidth, config.gridHeight, config.gridDepth)
		profileBegin("WorldGeneration_Cells")
		RoomPlacer.RasterizeRooms(grid, context.outputModel.roomPlacements)
		profileEnd()

		local carvedPaths, hallwayStats = HallwayCarver.Carve(
			grid,
			context.generationState.roomLookupById,
			context.outputModel.graph.finalEdges,
			config
		)

		context.generationState.grid = grid
		context.generationState.hallwayStats = hallwayStats
		context.outputModel.hallways = carvedPaths
		context.outputModel.occupancy = grid
		-- Validate stair transitions and auto-repair direction mismatches.
		local stairValidation = StairPlanner.ValidateAllTransitions(grid, true)
		if not stairValidation.valid then
			for _, issue in ipairs(stairValidation.issues) do
				warn("[DungeonGenerator] Stair issue: " .. tostring(issue.message))
			end
		end

		context.debugInstrumentation.phaseStats.hallway_carving = {
			edgesAttempted = tonumber(hallwayStats and hallwayStats.edgesAttempted) or 0,
			edgesSucceeded = tonumber(hallwayStats and hallwayStats.edgesSucceeded) or 0,
			edgesFailed = tonumber(hallwayStats and hallwayStats.edgesFailed) or 0,
			pathfindCalls = tonumber(hallwayStats and hallwayStats.pathfindCalls) or 0,
			pathfindSuccesses = tonumber(hallwayStats and hallwayStats.pathfindSuccesses) or 0,
			entrancePairsGenerated = tonumber(hallwayStats and hallwayStats.entrancePairsGenerated) or 0,
			carveRollbackFailures = tonumber(hallwayStats and hallwayStats.carveRollbackFailures) or 0,
			perimeterCellsCarved = tonumber(hallwayStats and hallwayStats.perimeterCellsCarved) or 0,
			stairValidationIssues = #stairValidation.issues,
			stairValidationRepaired = stairValidation.repaired,
		}
	end)

	runPhase(context, "layout_finalization", function()
		local cellsData, wallsData, doorwaysData, layoutStats = LayoutBuilder.Build(context.generationState.grid, {
			roomById = context.generationState.roomLookupById,
			carvedPaths = context.outputModel.hallways,
			maxRoomEntrances = config.maxRoomEntrances,
		})

		context.outputModel.cellTags = cellsData
		context.outputModel.wallTopologyByCell = wallsData
		context.outputModel.doorways = doorwaysData

		context.buildData.layout = {
			cellsData = cellsData,
			wallsData = wallsData,
			doorwaysData = doorwaysData,
		}

		context.debugInstrumentation.phaseStats.layout_finalization = {
			occupiedCells = tonumber(layoutStats and layoutStats.occupiedCellCount) or countArray(cellsData),
			doorways = tonumber(layoutStats and layoutStats.doorwayCount) or countArray(doorwaysData),
			allowedRoomEntrances = tonumber(layoutStats and layoutStats.allowedRoomEntranceCount) or 0,
			forcedOpenings = tonumber(layoutStats and layoutStats.forcedOpeningCount) or 0,
			wallFaceCounts = deepCopy(layoutStats and layoutStats.wallFaceCounts or {}),
		}
	end)

	runPhase(context, "decor_spec", function()
		context.buildData.dungeonSpec = nil
		context.buildData.decorData = nil

		if not context.derivedConfig.runtimeToggles.shouldBuildDungeonSpec then
			return
		end

		local okSpec, specOrErr = pcall(function()
			return DungeonSystem.BuildDungeonSpec({
				archetypeId = config.dungeonArchetypeId,
				seed = context.derivedConfig.seeds.systemSeed,
				targetRoomCount = config.roomCount,
				placedRooms = context.outputModel.roomPlacements,
				finalEdges = context.outputModel.graph.finalEdges,
				doorwaysData = context.outputModel.doorways,
				decorRoomLimit = config.decorRoomLimit,
				decorYieldInterval = config.decorYieldInterval,
				decorSolveYieldInterval = config.decorSolveYieldInterval,
				decorCollapseYieldInterval = config.decorCollapseYieldInterval,
				decorDensityScale = config.decorDensityScale,
				decorSubgridScale = config.decorSubgridScale,
				maxWfcCellsPerRoom = config.maxWfcCellsPerRoom,
				maxWfcSolveSeconds = config.maxWfcSolveSeconds,
				cellSize = config.cellSize,
				decorate = config.enableWFCDecor,
			})
		end)

		if okSpec then
			context.buildData.dungeonSpec = specOrErr
		else
			context.buildData.dungeonSpec = nil
			warn("[DungeonGenerator] BuildDungeonSpec failed, continuing without decor spec: " .. tostring(specOrErr))
		end

		if contentPlan ~= nil and context.buildData.dungeonSpec ~= nil then
			context.buildData.dungeonSpec.contentPlan = contentPlan
		end
		if config.enableWFCDecor and context.buildData.dungeonSpec ~= nil then
			context.buildData.decorData = context.buildData.dungeonSpec.decor
		end

		local decorData = context.buildData.decorData
		context.debugInstrumentation.phaseStats.decor_spec = {
			decorEnabled = config.enableWFCDecor == true,
			dungeonSpecBuilt = context.buildData.dungeonSpec ~= nil,
			decorRoomsProcessed = tonumber((decorData and decorData.processedRoomCount) or 0) or 0,
			decorFailures = countArray(decorData and decorData.failures),
			decorResults = countArray(decorData and decorData.results),
		}
	end)

	runPhase(context, "roof_candidates", function()
		local emptyRoofData = {
			seed = context.derivedConfig.seeds.roofSeed,
			placements = {},
			count = 0,
			stats = {
				scannedCells = 0,
				eligibleCells = 0,
				blockedByTallDecor = 0,
				collapsedSkipped = 0,
				blockedScanProcessed = 0,
			},
		}

		if not context.derivedConfig.runtimeToggles.shouldBuildRoof then
			context.buildData.roofData = emptyRoofData
			context.outputModel.roofCandidates = {}
			context.debugInstrumentation.phaseStats.roof_candidates = {
				roofEnabled = false,
				roofPlacements = 0,
				eligibleCells = 0,
			}
			return
		end

		local okRoof, roofOrErr = pcall(function()
			return DungeonRoofModule.BuildRoofPlan({
				seed = context.derivedConfig.seeds.roofSeed,
				cellsData = context.outputModel.cellTags,
				wallsData = context.outputModel.wallTopologyByCell,
				decorData = context.buildData.decorData,
				yieldInterval = tonumber(config.geometryYieldInterval) or tonumber(config.decorYieldInterval) or 300,
			})
		end)

		if okRoof then
			context.buildData.roofData = roofOrErr
		else
			context.buildData.roofData = emptyRoofData
			warn("[DungeonGenerator] BuildRoofPlan failed, continuing without roof data: " .. tostring(roofOrErr))
		end

		context.outputModel.roofCandidates = context.buildData.roofData.placements or {}
		local roofStats = context.buildData.roofData.stats or {}
		context.debugInstrumentation.phaseStats.roof_candidates = {
			roofEnabled = true,
			roofPlacements = countArray(context.outputModel.roofCandidates),
			eligibleCells = tonumber(roofStats.eligibleCells) or 0,
			collapsedSkipped = tonumber(roofStats.collapsedSkipped) or 0,
		}
	end)

	setGenerateStep("done", os.clock() - startedAt)

	context.debugInstrumentation.tableSizes = {
		roomDefinitions = countArray(context.outputModel.roomDefinitions),
		roomPlacements = countArray(context.outputModel.roomPlacements),
		graphEdges = countArray(context.outputModel.graph and context.outputModel.graph.graphEdges),
		finalEdges = countArray(context.outputModel.graph and context.outputModel.graph.finalEdges),
		carvedPaths = countArray(context.outputModel.hallways),
		cellsData = countArray(context.outputModel.cellTags),
		wallsData = countMap(context.outputModel.wallTopologyByCell),
		doorwaysData = countArray(context.outputModel.doorways),
		decorResults = countArray(context.buildData.decorData and context.buildData.decorData.results),
		roofPlacements = countArray(context.outputModel.roofCandidates),
	}

	local generationStateSummary = {
		roomPlacement = {
			attempts = tonumber((((context.generationState or {}).roomPlacement or {}).placementMeta or {}).attempts) or 0,
			placed = tonumber((((context.generationState or {}).roomPlacement or {}).placementMeta or {}).placed) or 0,
			requested = tonumber((((context.generationState or {}).roomPlacement or {}).placementMeta or {}).requested) or 0,
		},
		hallway = deepCopy(context.generationState.hallwayStats or {}),
	}

	updateWorkspaceGenerationStats(context.debugInstrumentation)

	return {
		seed = context.seed,
		config = shallowCopy(context.inputConfig),
		rooms = context.outputModel.roomPlacements or {},
		activeRoomIds = (context.outputModel.graph and context.outputModel.graph.activeRoomIds) or {},
		graphEdges = (context.outputModel.graph and context.outputModel.graph.graphEdges) or {},
		mstEdges = (context.outputModel.graph and context.outputModel.graph.mstEdges) or {},
		extraEdges = (context.outputModel.graph and context.outputModel.graph.extraEdges) or {},
		finalEdges = (context.outputModel.graph and context.outputModel.graph.finalEdges) or {},
		culledRoomIds = (context.outputModel.graph and context.outputModel.graph.culledRoomIds) or {},
		carvedPaths = context.outputModel.hallways or {},
		grid = context.generationState.grid,
		cellsData = context.outputModel.cellTags or {},
		wallsData = context.outputModel.wallTopologyByCell or {},
		doorwaysData = context.outputModel.doorways or {},
		decorData = context.buildData.decorData,
		roofData = context.buildData.roofData,
		dungeonSpec = context.buildData.dungeonSpec,
		placementMeta = ((context.generationState.roomPlacement or {}).placementMeta) or {
			attempts = 0,
			placed = 0,
			requested = 0,
		},

		-- New explicit layered model for tuning/editability/debugging.
		pipeline = {
			inputConfig = shallowCopy(context.inputConfig),
			derivedConfig = deepCopy(context.derivedConfig),
			generationState = generationStateSummary,
			outputModel = {
				roomDefinitions = context.outputModel.roomDefinitions or {},
				roomPlacements = context.outputModel.roomPlacements or {},
				graph = context.outputModel.graph or {},
				hallways = context.outputModel.hallways or {},
				cellTags = context.outputModel.cellTags or {},
				wallTopologyByCell = context.outputModel.wallTopologyByCell or {},
				doorways = context.outputModel.doorways or {},
				roofCandidates = context.outputModel.roofCandidates or {},
			},
			buildData = {
				layout = context.buildData.layout or {
					cellsData = {},
					wallsData = {},
					doorwaysData = {},
				},
				dungeonSpec = context.buildData.dungeonSpec,
				decorData = context.buildData.decorData,
				roofData = context.buildData.roofData,
			},
			phaseContracts = DungeonGenerationContracts.Phases,
			phaseOrder = DungeonGenerationContracts.PhaseOrder,
		},
		debugInstrumentation = context.debugInstrumentation,
	}
end

return DungeonGenerator

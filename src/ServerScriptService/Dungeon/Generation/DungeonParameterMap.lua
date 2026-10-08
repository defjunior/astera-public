--[[
	DungeonParameterMap

	Documents every generation config parameter: which phase consumes it,
	what domain it affects (room sizing, graph connectivity, hallway routing, etc.),
	and whether the value is raw input or derived. Used for tooling validation
	and designer-facing parameter introspection.
]]

local DungeonData = require(script.Parent.Parent.Data.DungeonData)

local DungeonParameterMap = {}

local DEFAULT_CONFIG = DungeonData.DungeonGenerator.DefaultConfig or {}

local raw = {}

local function copyList(source)
	local out = {}
	for i, value in ipairs(source or {}) do
		out[i] = value
	end
	return out
end

local function assign(keys, spec)
	for _, key in ipairs(keys) do
		raw[key] = spec
	end
end

local PHASES = {
	CONFIG = "config_normalization",
	CONTENT = "content_config",
	ROOMS = "room_placement",
	GRAPH = "graph_construction",
	HALLWAYS = "hallway_carving",
	LAYOUT = "layout_finalization",
	DECOR = "decor_spec",
	ROOF = "roof_candidates",
}

assign({
	"roomCount",
	"minRoomSize",
	"maxRoomSize",
	"roomPadding",
	"roomPaddingY",
	"maxRoomPlacementAttempts",
}, {
	category = "topology",
	phases = { PHASES.ROOMS },
	usage = "direct",
	affects = "Room count/shape candidate generation and overlap acceptance.",
	impactDomains = { "shape", "topology", "performance" },
	readBy = { "DungeonGenerator.normalizeConfig", "RoomPlacer.PlaceRooms" },
	derivedInto = { "placementMeta.requested", "placementMeta.placed" },
})

assign({ "minRoomHeight", "maxRoomHeight" }, {
	category = "verticality",
	phases = { PHASES.ROOMS },
	usage = "direct",
	affects = "Vertical span and floor distribution of placed rooms.",
	impactDomains = { "shape", "topology" },
	readBy = { "DungeonGenerator.normalizeConfig", "RoomPlacer.PlaceRooms" },
	derivedInto = { "room.size.y", "room.min.y", "room.max.y" },
})

assign({ "gridWidth", "gridHeight", "gridDepth" }, {
	category = "geometry",
	phases = { PHASES.CONFIG, PHASES.ROOMS, PHASES.HALLWAYS },
	usage = "direct",
	affects = "Dungeon volume bounds for room placement and pathing.",
	impactDomains = { "shape", "topology", "performance" },
	readBy = { "DungeonGenerator.normalizeConfig", "RoomPlacer.PlaceRooms", "Grid3D.new" },
	derivedInto = { "DungeonDerivedConfig.gridCellBudget" },
})

assign({ "cellSize", "worldOrigin" }, {
	category = "geometry",
	phases = { PHASES.CONFIG, PHASES.LAYOUT, PHASES.DECOR },
	usage = "direct",
	affects = "Grid/world transforms and spatial placement offsets.",
	impactDomains = { "visuals", "debugging" },
	readBy = { "DungeonGenerator.GridToWorld", "DungeonGenerator.WorldToGrid", "DungeonSystem.BuildDungeonSpec" },
	derivedInto = { "DungeonDerivedConfig.worldBoundsStuds" },
})

assign({ "extraEdgeChance", "labyrinthBias", "loopChanceBoostPerBias", "minExtraLoopEdges", "maxExtraLoopEdges" }, {
	category = "topology",
	phases = { PHASES.GRAPH },
	usage = "direct",
	affects = "Loop density and branching in final room connectivity graph.",
	impactDomains = { "topology" },
	readBy = { "RoomGraphBuilder.Build" },
	derivedInto = { "effectiveExtraEdgeChance", "targetExtraLoops" },
})

assign({ "graphNeighborCount", "graphVerticalWeight", "minInterFloorEdges" }, {
	category = "topology",
	phases = { PHASES.GRAPH },
	usage = "direct",
	affects = "Edge candidate set and vertical graph connectivity bias.",
	impactDomains = { "topology", "verticality" },
	readBy = { "RoomGraphBuilder.Build" },
	derivedInto = { "proximityEdges", "finalEdges", "interFloorEdgeCount" },
})

assign({ "maxRoomEntrances" }, {
	category = "traversal_pathing",
	phases = { PHASES.LAYOUT },
	usage = "direct",
	affects = "Maximum room-to-hallway entrances kept after carving.",
	impactDomains = { "traversal", "topology" },
	readBy = { "LayoutBuilder.Build", "LayoutBuilder.buildAllowedRoomEntrances" },
	derivedInto = { "allowedRoomEntrances" },
})

assign({ "maxPathIterations", "maxVisitedStates", "pathYieldInterval", "walkCost", "stairCost" }, {
	category = "traversal_pathing",
	phases = { PHASES.HALLWAYS },
	usage = "direct",
	affects = "A* search runtime limits and movement scoring.",
	impactDomains = { "traversal", "performance" },
	readBy = { "HallwayCarver.resolvePathConfig", "HallwayCarver.FindPath" },
	derivedInto = { "pathConfig" },
})

assign({
	"minFlatStepsBetweenStairs",
	"retryMinFlatStepsBetweenStairs",
	"hallwayCarveRetryCount",
	"useGlobalStairReservations",
	"useGlobalStairReservationsOnLastRetry",
	"allowHallwayDownStairs",
	"allowHallwayDownStairsOnRetry",
	"enforceNearbyStairClearance",
	"enforceNearbyStairClearanceOnRetry",
	"allowSameFloorStairDetours",
}, {
	category = "verticality",
	phases = { PHASES.HALLWAYS },
	usage = "direct",
	affects = "Stair transition policy, retries, and cross-floor traversal strictness.",
	impactDomains = { "traversal", "verticality", "performance" },
	readBy = { "HallwayCarver.buildAttemptProfiles", "HallwayCarver.addStairNeighbors", "StairPlanner.CanPlaceTransition" },
	derivedInto = { "attemptProfiles", "pathConfigOverride", "globalReservedStairCells" },
})

assign({
	"maxEntranceCandidatesPerRoom",
	"maxEntranceCandidatesPerFace",
	"maxEntrancePairAttempts",
	"maxEntrancePairAttemptsOnRetry",
	"maxEntrancePairAttemptsOnLastRetry",
}, {
	category = "traversal_pathing",
	phases = { PHASES.HALLWAYS },
	usage = "direct",
	affects = "Entrance candidate breadth and retry pair search cost.",
	impactDomains = { "traversal", "performance" },
	readBy = { "HallwayCarver.buildEntranceCandidates", "HallwayCarver.buildEntrancePairs", "HallwayCarver.getPairAttemptLimit" },
	derivedInto = { "entrancePairs", "pairLimit" },
})

assign({ "edgeYieldInterval" }, {
	category = "performance_limits",
	phases = { PHASES.HALLWAYS },
	usage = "direct",
	affects = "Cooperative yielding frequency while carving graph edges.",
	impactDomains = { "performance", "debugging" },
	readBy = { "HallwayCarver.Carve" },
	derivedInto = { "carveEdgeYieldInterval" },
})

assign({ "buildingPerimeterHallwayWidth" }, {
	category = "topology",
	phases = { PHASES.HALLWAYS },
	usage = "direct",
	affects = "Additional hallway ring carved around room perimeters.",
	impactDomains = { "shape", "traversal" },
	readBy = { "HallwayCarver.carvePerimeterHallways" },
	derivedInto = { "perimeterCellsCarved" },
})

assign({ "enableDungeonContentSystem", "dungeonArchetypeId", "dungeonSeedOffset" }, {
	category = "content_decor",
	phases = { PHASES.CONTENT, PHASES.DECOR },
	usage = "direct",
	affects = "Content plan generation, room intent assignment, and archetype-driven config overrides.",
	impactDomains = { "topology", "visuals" },
	readBy = { "DungeonGenerator.Generate", "DungeonSystem.BuildGeneratorConfig", "DungeonSystem.BuildDungeonSpec" },
	derivedInto = { "contentPlan", "systemSeed", "specSeed" },
})

assign({
	"enableWFCDecor",
	"decorArchetypeId",
	"decorSeedOffset",
	"decorRoomLimit",
	"decorYieldInterval",
	"decorSolveYieldInterval",
	"decorCollapseYieldInterval",
	"decorDensityScale",
	"decorSubgridScale",
	"maxWfcCellsPerRoom",
	"maxWfcSolveSeconds",
}, {
	category = "content_decor",
	phases = { PHASES.DECOR },
	usage = "direct",
	affects = "Decor solve scope, WFC limits, and layered placement density.",
	impactDomains = { "visuals", "performance" },
	readBy = { "DungeonGenerator.Generate", "DungeonSystem.BuildDungeonSpec", "DungeonSystem.DecoratePlacedRooms", "WFCRoomDecorator.DecorateRoom" },
	derivedInto = { "decorData.results", "roomDecorations" },
})

assign({ "enableRoof" }, {
	category = "roof",
	phases = { PHASES.ROOF },
	usage = "direct",
	affects = "Whether roof candidate generation runs.",
	impactDomains = { "visuals", "performance" },
	readBy = { "DungeonGenerator.Generate" },
	derivedInto = { "roofData.placements" },
})

assign({ "windowWallChance", "roomBoundaryWindowWallChance" }, {
	category = "visuals",
	phases = { PHASES.CONFIG, PHASES.LAYOUT },
	usage = "direct",
	affects = "Window/solid wall class mix during build-time wall spawning.",
	impactDomains = { "visuals" },
	readBy = { "DungeonGenerator.normalizeConfig", "DungeonBuildService._buildGeometry" },
	derivedInto = { "runtime wall asset selection weights" },
})

assign({ "overworldStyleBias" }, {
	category = "visuals",
	phases = { PHASES.CONFIG },
	usage = "indirect",
	affects = "Applies broad style transform toward flatter, perimeter-focused layouts.",
	impactDomains = { "shape", "topology", "visuals" },
	readBy = { "DungeonGenerator.applyOverworldStyleBias" },
	derivedInto = {
		"gridHeight",
		"minRoomHeight",
		"maxRoomHeight",
		"minInterFloorEdges",
		"graphVerticalWeight",
		"roomPadding",
		"buildingPerimeterHallwayWidth",
		"roomBoundaryWindowWallChance",
	},
})

assign({ "floorLiftStuds", "ceilingDropStuds" }, {
	category = "geometry",
	phases = { PHASES.LAYOUT },
	usage = "direct",
	affects = "Vertical placement offset for built floor/ceiling geometry.",
	impactDomains = { "visuals" },
	readBy = { "DungeonBuildService._buildGeometry" },
	derivedInto = { "built floor/ceiling part transforms" },
})

local function makeFallbackEntry(name, defaultValue)
	return {
		name = name,
		defaultValue = defaultValue,
		category = "uncategorized",
		phases = { PHASES.CONFIG },
		usage = "direct",
		affects = "Parameter is normalized but not yet documented in DungeonParameterMap.",
		impactDomains = { "debugging" },
		readBy = { "DungeonGenerator.normalizeConfig" },
		derivedInto = {},
		documentationState = "missing_specific_mapping",
	}
end

local function buildEntries()
	local entries = {}
	for key, defaultValue in pairs(DEFAULT_CONFIG) do
		local spec = raw[key]
		local entry
		if spec then
			entry = {
				name = key,
				defaultValue = defaultValue,
				category = spec.category,
				phases = copyList(spec.phases),
				usage = spec.usage,
				affects = spec.affects,
				impactDomains = copyList(spec.impactDomains),
				readBy = copyList(spec.readBy),
				derivedInto = copyList(spec.derivedInto),
			}
		else
			entry = makeFallbackEntry(key, defaultValue)
		end
		entries[#entries + 1] = entry
	end
	table.sort(entries, function(a, b)
		return a.name < b.name
	end)
	return entries
end

local ENTRIES = buildEntries()
local BY_NAME = {}
for _, entry in ipairs(ENTRIES) do
	BY_NAME[entry.name] = entry
end

function DungeonParameterMap.List()
	return ENTRIES
end

function DungeonParameterMap.Get(parameterName)
	return BY_NAME[parameterName]
end

function DungeonParameterMap.BuildUsedValueSnapshot(config)
	local snapshot = {}
	for _, entry in ipairs(ENTRIES) do
		snapshot[entry.name] = config and config[entry.name] or entry.defaultValue
	end
	return snapshot
end

function DungeonParameterMap.ValidateCoverage()
	local missing = {}
	for _, entry in ipairs(ENTRIES) do
		if entry.documentationState == "missing_specific_mapping" then
			missing[#missing + 1] = entry.name
		end
	end
	return #missing == 0, missing
end

return DungeonParameterMap

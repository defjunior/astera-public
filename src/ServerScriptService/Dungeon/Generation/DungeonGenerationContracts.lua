--[[
	DungeonGenerationContracts

	Defines the generation pipeline's phase contracts and data layer schemas.
	Each phase declares its inputs, outputs, and invariants so that the
	generator can validate state transitions between phases. Data layers
	(InputConfig, DerivedConfig, GenerationState, OutputModel, BuildData)
	document what data exists at each stage of the pipeline.
]]

local DungeonGenerationContracts = {}

DungeonGenerationContracts.DataLayers = {
	InputConfig = {
		name = "DungeonInputConfig",
		description = "Raw generation parameters and explicit designer inputs.",
	},
	DerivedConfig = {
		name = "DungeonDerivedConfig",
		description = "Computed once from InputConfig for normalization, seeds, and convenience thresholds.",
	},
	GenerationState = {
		name = "DungeonGenerationState",
		description = "Disposable scratch state used while generating rooms/paths/layout.",
	},
	OutputModel = {
		name = "DungeonOutputModel",
		description = "Stable dungeon topology/layout outputs consumed by later systems.",
	},
	BuildData = {
		name = "DungeonBuildData",
		description = "Build/runtime visualization payloads (roof plan, decor plan, prefab-facing data).",
	},
}

DungeonGenerationContracts.PhaseOrder = {
	"config_normalization",
	"content_config",
	"room_placement",
	"graph_construction",
	"hallway_carving",
	"layout_finalization",
	"decor_spec",
	"roof_candidates",
}

DungeonGenerationContracts.Phases = {
	config_normalization = {
		name = "Config Normalization",
		inputs = { "DungeonInputConfig" },
		outputs = { "DungeonInputConfig", "DungeonDerivedConfig" },
		scratch = {},
		mutates = { "DungeonInputConfig", "DungeonDerivedConfig" },
		invariants = {
			"All numeric/boolean config fields are clamped and normalized.",
			"Derived seeds and derived feature toggles are computed once.",
		},
	},
	content_config = {
		name = "Content Preset Merge",
		inputs = { "DungeonInputConfig", "DungeonDerivedConfig" },
		outputs = { "DungeonInputConfig", "DungeonDerivedConfig" },
		scratch = { "contentPlan" },
		mutates = { "DungeonInputConfig", "DungeonDerivedConfig" },
		invariants = {
			"Content-driven overrides are applied exactly once when enabled.",
		},
	},
	room_placement = {
		name = "Room Placement",
		inputs = { "DungeonInputConfig" },
		outputs = { "DungeonGenerationState.roomPlacement", "DungeonOutputModel.roomDefinitions" },
		scratch = { "room placement attempts" },
		mutates = { "DungeonGenerationState", "DungeonOutputModel" },
		invariants = {
			"Placed rooms respect bounds and buffered overlap constraints.",
		},
	},
	graph_construction = {
		name = "Graph Construction",
		inputs = { "DungeonOutputModel.roomDefinitions", "DungeonInputConfig" },
		outputs = { "DungeonGenerationState.roomLookupById", "DungeonOutputModel.graph", "DungeonOutputModel.roomPlacements" },
		scratch = { "active room set" },
		mutates = { "DungeonGenerationState", "DungeonOutputModel" },
		invariants = {
			"Final edge set always includes spanning connectivity for active rooms.",
		},
	},
	hallway_carving = {
		name = "Hallway Carving",
		inputs = { "DungeonOutputModel.roomPlacements", "DungeonOutputModel.graph", "DungeonInputConfig" },
		outputs = { "DungeonGenerationState.grid", "DungeonOutputModel.hallways", "DungeonOutputModel.occupancy" },
		scratch = { "pathfinder state", "stair reservation maps", "retry profiles" },
		mutates = { "DungeonGenerationState", "DungeonOutputModel" },
		invariants = {
			"Carved paths and stair transitions are reflected in occupancy grid state.",
		},
	},
	layout_finalization = {
		name = "Layout Finalization",
		inputs = { "DungeonGenerationState.grid", "DungeonOutputModel.hallways", "DungeonInputConfig" },
		outputs = { "DungeonOutputModel.cellTags", "DungeonOutputModel.doorways", "DungeonBuildData.layout" },
		scratch = { "allowed room entrances", "forced opening lookup" },
		mutates = { "DungeonOutputModel", "DungeonBuildData" },
		invariants = {
			"Doorway data aligns with open room/transit boundaries.",
			"Per-cell wall topology is resolved for all occupied cells.",
		},
	},
	decor_spec = {
		name = "Decor/Content Spec",
		inputs = { "DungeonOutputModel", "DungeonInputConfig", "DungeonDerivedConfig" },
		outputs = { "DungeonBuildData.dungeonSpec", "DungeonBuildData.decorData" },
		scratch = { "room assignment scoring" },
		mutates = { "DungeonBuildData" },
		invariants = {
			"Decor spec is optional and does not block layout generation on failure.",
		},
	},
	roof_candidates = {
		name = "Roof Candidate Generation",
		inputs = { "DungeonOutputModel.cellTags", "DungeonOutputModel.doorways", "DungeonBuildData.decorData", "DungeonDerivedConfig" },
		outputs = { "DungeonOutputModel.roofCandidates", "DungeonBuildData.roofData" },
		scratch = { "roof blocked lookup", "cell position lookup" },
		mutates = { "DungeonOutputModel", "DungeonBuildData" },
		invariants = {
			"Roof plan generation is optional and falls back to empty placements on failure.",
		},
	},
}

return DungeonGenerationContracts

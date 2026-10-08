--[[
	Decor

	Traditional (non-WFC) room decoration system.
	Handles prop placement, scatter, mess piles, structural supports,
	surface analysis, variant selection, and writing generation.

	WFC tile decoration lives in Dungeon.WFC.
	Vegetation lives in Dungeon.Vegetation.
]]

return {
	DungeonDecorationModule = require(script.DungeonDecorationModule),
	DungeonRoofModule = require(script.DungeonRoofModule),
	DungeonVariantModule = require(script.DungeonVariantModule),
	DungeonArchetypeModule = require(script.DungeonArchetypeModule),
	DungeonAssetRegistry = require(script.DungeonAssetRegistry),
	DungeonSurfacePlacementModule = require(script.DungeonSurfacePlacementModule),
	DungeonScatterModule = require(script.DungeonScatterModule),
	DungeonMessPileModule = require(script.DungeonMessPileModule),
	DungeonStructuralPropPlanner = require(script.DungeonStructuralPropPlanner),
	DungeonWritingVariantModule = require(script.DungeonWritingVariantModule),
}

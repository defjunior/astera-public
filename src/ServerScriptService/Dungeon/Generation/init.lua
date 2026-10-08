--[[
	Generation

	Core procedural dungeon layout engine.
	Handles room placement, graph construction, hallway carving,
	and layout finalization across multiple floors.

	require() returns the DungeonGenerator module directly,
	preserving the same interface as the old top-level DungeonGeneration module.
]]

return require(script.DungeonGenerator)

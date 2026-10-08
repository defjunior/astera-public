local DungeonArchetypeTypes = require(script.Parent.DungeonArchetypeTypes)

local DungeonArchetypeDB = {}

local L = DungeonArchetypeTypes.LayoutStyle
local V = DungeonArchetypeTypes.VerticalProfile
local D = DungeonArchetypeTypes.DensityProfile

local archetypes = {
 -- EXCLUDED: authored content/settings table, at the owner's request.
 -- General structure: map<string, archetype record>: id/displayName/tags; layout, spacing, connectivity, progression and parameter settings
 -- Intentionally empty, not a runnable replacement. See CONTENT-SCHEMAS.md.
}

function DungeonArchetypeDB.Get(archetypeId)
	return archetypes[archetypeId]
end

function DungeonArchetypeDB.GetAll()
	return archetypes
end

function DungeonArchetypeDB.ListIds()
	local ids = {}
	for id in pairs(archetypes) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	return ids
end

function DungeonArchetypeDB.Validate()
	local issues = {}
	for _, archetype in pairs(archetypes) do
		local ok, archetypeIssues = DungeonArchetypeTypes.Validate(archetype)
		if not ok then
			for _, issue in ipairs(archetypeIssues) do
				issues[#issues + 1] = issue
			end
		end
	end
	return #issues == 0, issues
end

return DungeonArchetypeDB

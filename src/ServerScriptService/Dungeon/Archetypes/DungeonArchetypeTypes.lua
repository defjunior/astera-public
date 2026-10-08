local DungeonArchetypeTypes = {}

DungeonArchetypeTypes.LayoutStyle = {
	Clustered = "Clustered",
	Branching = "Branching",
	HubAndSpoke = "HubAndSpoke",
	Linear = "Linear",
	Ring = "Ring",
}

DungeonArchetypeTypes.VerticalProfile = {
	Flat = "Flat",
	Layered = "Layered",
	Stacked = "Stacked",
	SpiralBias = "SpiralBias",
}

DungeonArchetypeTypes.DensityProfile = {
	Sparse = "Sparse",
	Medium = "Medium",
	Dense = "Dense",
}

local function isTable(value)
	return type(value) == "table"
end

local function isPositiveNumber(value)
	return type(value) == "number" and value > 0
end

local function appendIssue(issues, message)
	issues[#issues + 1] = message
end

function DungeonArchetypeTypes.Validate(definition)
	local issues = {}

	if not isTable(definition) then
		appendIssue(issues, "Archetype definition must be a table")
		return false, issues
	end

	if type(definition.id) ~= "string" or definition.id == "" then
		appendIssue(issues, "Archetype missing id")
	end

	if type(definition.displayName) ~= "string" or definition.displayName == "" then
		appendIssue(issues, string.format("Archetype '%s' missing displayName", tostring(definition.id)))
	end

	if not isTable(definition.roomGrid) then
		appendIssue(issues, string.format("Archetype '%s' missing roomGrid", tostring(definition.id)))
	else
		if not isPositiveNumber(definition.roomGrid.width) then
			appendIssue(issues, string.format("Archetype '%s' roomGrid.width must be > 0", tostring(definition.id)))
		end
		if not isPositiveNumber(definition.roomGrid.height) then
			appendIssue(issues, string.format("Archetype '%s' roomGrid.height must be > 0", tostring(definition.id)))
		end
		if not isPositiveNumber(definition.roomGrid.depth) then
			appendIssue(issues, string.format("Archetype '%s' roomGrid.depth must be > 0", tostring(definition.id)))
		end
	end

	if not DungeonArchetypeTypes.LayoutStyle[definition.layoutStyle] then
		appendIssue(issues, string.format("Archetype '%s' has unknown layoutStyle '%s'", tostring(definition.id), tostring(definition.layoutStyle)))
	end

	if not DungeonArchetypeTypes.VerticalProfile[definition.verticalProfile] then
		appendIssue(issues, string.format("Archetype '%s' has unknown verticalProfile '%s'", tostring(definition.id), tostring(definition.verticalProfile)))
	end

	if not DungeonArchetypeTypes.DensityProfile[definition.densityProfile] then
		appendIssue(issues, string.format("Archetype '%s' has unknown densityProfile '%s'", tostring(definition.id), tostring(definition.densityProfile)))
	end

	if not isTable(definition.roomTypeWeights) then
		appendIssue(issues, string.format("Archetype '%s' missing roomTypeWeights", tostring(definition.id)))
	end

	if not isTable(definition.connectivity) then
		appendIssue(issues, string.format("Archetype '%s' missing connectivity", tostring(definition.id)))
	end

	if not isTable(definition.progression) then
		appendIssue(issues, string.format("Archetype '%s' missing progression", tostring(definition.id)))
	end

	if not isTable(definition.specialStructures) then
		appendIssue(issues, string.format("Archetype '%s' missing specialStructures", tostring(definition.id)))
	end

	if not isTable(definition.parameterPreset) then
		appendIssue(issues, string.format("Archetype '%s' missing parameterPreset", tostring(definition.id)))
	end

	return #issues == 0, issues
end

return DungeonArchetypeTypes

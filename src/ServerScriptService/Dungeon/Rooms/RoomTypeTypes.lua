local RoomTypeTypes = {}

RoomTypeTypes.Category = {
	Room = "Room",
	Hub = "Hub",
	Connector = "Connector",
	Landmark = "Landmark",
	Special = "Special",
	Utility = "Utility",
}

RoomTypeTypes.FootprintFamily = {
	Rectangular = "Rectangular",
	Cross = "Cross",
	Ring = "Ring",
	Corridor = "Corridor",
	Compound = "Compound",
	StairCore = "StairCore",
}

local function isTable(value)
	return type(value) == "table"
end

local function appendIssue(issues, message)
	issues[#issues + 1] = message
end

function RoomTypeTypes.Validate(definition)
	local issues = {}

	if not isTable(definition) then
		appendIssue(issues, "Room type definition must be a table")
		return false, issues
	end

	if type(definition.id) ~= "string" or definition.id == "" then
		appendIssue(issues, "Room type missing id")
	end

	if type(definition.displayName) ~= "string" or definition.displayName == "" then
		appendIssue(issues, string.format("Room type '%s' missing displayName", tostring(definition.id)))
	end

	if not RoomTypeTypes.Category[definition.category] then
		appendIssue(issues, string.format("Room type '%s' has unknown category '%s'", tostring(definition.id), tostring(definition.category)))
	end

	if not RoomTypeTypes.FootprintFamily[definition.footprintFamily] then
		appendIssue(issues, string.format("Room type '%s' has unknown footprintFamily '%s'", tostring(definition.id), tostring(definition.footprintFamily)))
	end

	if not isTable(definition.allowedPatterns) or #definition.allowedPatterns == 0 then
		appendIssue(issues, string.format("Room type '%s' has no allowedPatterns", tostring(definition.id)))
	end

	if not isTable(definition.sizeBias) then
		appendIssue(issues, string.format("Room type '%s' missing sizeBias", tostring(definition.id)))
	end

	if not isTable(definition.entrances) then
		appendIssue(issues, string.format("Room type '%s' missing entrances", tostring(definition.id)))
	end

	if not isTable(definition.placementRules) then
		appendIssue(issues, string.format("Room type '%s' missing placementRules", tostring(definition.id)))
	end

	if not isTable(definition.connectivityRules) then
		appendIssue(issues, string.format("Room type '%s' missing connectivityRules", tostring(definition.id)))
	end

	if not isTable(definition.progressionRole) then
		appendIssue(issues, string.format("Room type '%s' missing progressionRole", tostring(definition.id)))
	end

	if not isTable(definition.frequency) then
		appendIssue(issues, string.format("Room type '%s' missing frequency", tostring(definition.id)))
	end

	return #issues == 0, issues
end

return RoomTypeTypes

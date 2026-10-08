local DungeonArchetypeDB = require(script.Parent.Parent.Archetypes.DungeonArchetypeDB)
local RoomTypeDB = require(script.Parent.Parent.Rooms.RoomTypeDB)
local ProgressionPlanner = require(script.Parent.Parent.Progression.ProgressionPlanner)
local DungeonSystem = require(script.Parent.Parent.DungeonSystem)

local DungeonSpecDebug = {}

local function joinLines(lines)
	return table.concat(lines, "\n")
end

function DungeonSpecDebug.ValidateAll()
	return DungeonSystem.ValidateAll()
end

function DungeonSpecDebug.SummarizeRoomType(roomTypeId)
	local roomType = RoomTypeDB.Get(roomTypeId)
	if not roomType then
		return string.format("Room type '%s' not found", tostring(roomTypeId))
	end

	local lines = {
		string.format("RoomType: %s (%s)", roomType.displayName, roomType.id),
		string.format("  Category: %s", roomType.category),
		string.format("  Tags: %s", table.concat(roomType.tags or {}, ", ")),
		string.format("  Patterns: %s", table.concat(roomType.allowedPatterns or {}, ", ")),
		string.format("  Entrances: %d-%d", roomType.entrances.min or 0, roomType.entrances.max or 0),
		string.format("  Degree: %d-%d", roomType.connectivityRules.minDegree or 0, roomType.connectivityRules.maxDegree or 0),
	}
	return joinLines(lines)
end

function DungeonSpecDebug.SummarizeArchetype(archetypeId)
	local archetype = DungeonArchetypeDB.Get(archetypeId)
	if not archetype then
		return string.format("Archetype '%s' not found", tostring(archetypeId))
	end

	local weighted = {}
	for roomTypeId, weight in pairs(archetype.roomTypeWeights or {}) do
		weighted[#weighted + 1] = { roomTypeId = roomTypeId, weight = weight }
	end
	table.sort(weighted, function(a, b)
		if a.weight ~= b.weight then
			return a.weight > b.weight
		end
		return a.roomTypeId < b.roomTypeId
	end)

	local top = {}
	for i = 1, math.min(8, #weighted) do
		top[#top + 1] = string.format("%s(%.2f)", weighted[i].roomTypeId, weighted[i].weight)
	end

	local lines = {
		string.format("Archetype: %s (%s)", archetype.displayName, archetype.id),
		string.format("  Layout: %s | Vertical: %s | Density: %s", archetype.layoutStyle, archetype.verticalProfile, archetype.densityProfile),
		string.format("  Grid: %dx%dx%d", archetype.roomGrid.width, archetype.roomGrid.height, archetype.roomGrid.depth),
		string.format("  Top RoomType Weights: %s", table.concat(top, ", ")),
		string.format("  LoopChance: %.2f | TargetDegree: %.2f", archetype.connectivity.extraLoopChance, archetype.connectivity.targetAverageDegree),
		string.format("  Progression Profile: %s", archetype.progression.profileId),
	}

	return joinLines(lines)
end

function DungeonSpecDebug.BuildProgressionPreview(archetypeId, seed, options)
	local archetype = DungeonArchetypeDB.Get(archetypeId)
	if not archetype then
		return nil, string.format("Archetype '%s' not found", tostring(archetypeId))
	end

	local plan = ProgressionPlanner.BuildPlan(archetype, {
		seed = seed or 1,
		targetRoomCount = options and options.targetRoomCount or nil,
	})

	local lines = {
		string.format("Progression Plan: %s (seed=%d)", archetypeId, plan.seed),
		string.format("  Profile: %s", plan.profileId),
	}

	for _, beat in ipairs(plan.beats) do
		lines[#lines + 1] = string.format(
			"  %02d [%s/%s] -> %s",
			beat.index,
			beat.stage,
			beat.beatLabel,
			beat.selectedRoomTypeId or "<none>"
		)
	end

	return plan, joinLines(lines)
end

function DungeonSpecDebug.GetArchetypeOverviewTable()
	local rows = {}
	for _, archetypeId in ipairs(DungeonArchetypeDB.ListIds()) do
		local a = DungeonArchetypeDB.Get(archetypeId)
		rows[#rows + 1] = {
			id = a.id,
			name = a.displayName,
			layout = a.layoutStyle,
			vertical = a.verticalProfile,
			density = a.densityProfile,
			grid = string.format("%dx%dx%d", a.roomGrid.width, a.roomGrid.height, a.roomGrid.depth),
			progression = a.progression.profileId,
		}
	end
	return rows
end

function DungeonSpecDebug.BuildSystemPreview(archetypeId, seed, options)
	local decorate = true
	if options and options.decorate == false then
		decorate = false
	end

	local spec = DungeonSystem.BuildDungeonSpec({
		archetypeId = archetypeId,
		seed = seed or 1,
		targetRoomCount = options and options.targetRoomCount or nil,
		decorate = decorate,
	})

	local contentPlan = spec.contentPlan
	local lines = {
		string.format("DungeonSystem Preview: %s (seed=%d)", contentPlan.archetypeId, contentPlan.seed),
		string.format("  GenerationPreset: rooms=%d floors=%d maxEntrances=%d",
			contentPlan.generationPreset.roomCount,
			contentPlan.generationPreset.gridHeight,
			contentPlan.generationPreset.maxRoomEntrances),
		string.format("  Progression Beats: %d", #contentPlan.progressionPlan.beats),
		string.format("  Room Intents: %d", #contentPlan.roomIntents),
	}

	local previewCount = math.min(12, #contentPlan.roomIntents)
	for i = 1, previewCount do
		local intent = contentPlan.roomIntents[i]
		lines[#lines + 1] = string.format(
			"  %02d [%s/%s] type=%s pattern=%s rot=%s floor=%d",
			intent.index,
			intent.stage,
			intent.beatType,
			intent.roomTypeId,
			tostring(intent.patternId),
			tostring(intent.rotationKey),
			intent.floorHint
		)
	end

	if spec.roomAssignments and spec.roomAssignments.assignments then
		lines[#lines + 1] = string.format("  Room Assignments: %d", #spec.roomAssignments.assignments)
	end
	if spec.decor then
		lines[#lines + 1] = string.format(
			"  Decor: rooms=%d failures=%d",
			#(spec.decor.results or {}),
			#(spec.decor.failures or {})
		)
	end

	return spec, joinLines(lines)
end

return DungeonSpecDebug

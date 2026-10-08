--[[
	DungeonArchetypeModule

	Builds high-level decoration context for a room from:
	- room type metadata
	- dungeon archetype metadata
	- structural profile information

	All editable balancing/tuning values live in:
	`Dungeon/Data/DungeonData.lua`
]]

local DungeonData = require(script.Parent.Parent.Data.DungeonData)
local DungeonArchetypeDecorData = DungeonData.Decor.ArchetypeDecorData

local DungeonArchetypeModule = {}

-- === Utility ===============================================================

local function containsTag(tags, wanted)
	if type(tags) ~= "table" then
		return false
	end
	for _, tag in ipairs(tags) do
		if tag == wanted then
			return true
		end
	end
	return false
end

local function weightedPick(rng, weights)
	local total = 0
	for _, weight in pairs(weights) do
		total += math.max(0, tonumber(weight) or 0)
	end
	if total <= 0 then
		return "dusty"
	end

	local roll = rng:NextNumber(0, total)
	local cursor = 0
	local keys = {}
	for key in pairs(weights) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		cursor += math.max(0, tonumber(weights[key]) or 0)
		if roll <= cursor then
			return key
		end
	end
	return keys[#keys] or "dusty"
end

-- === Data-Driven Resolution ===============================================

local function inferPurpose(roomTypeRecord)
	local tags = (roomTypeRecord and roomTypeRecord.tags) or {}
	for _, tag in ipairs(tags) do
		local purpose = DungeonArchetypeDecorData.PURPOSE_BY_TAG[tag]
		if purpose then
			return purpose
		end
	end
	return DungeonArchetypeDecorData.DEFAULT_PURPOSE_BY_CATEGORY[(roomTypeRecord and roomTypeRecord.category) or "Room"] or "combat"
end

local function purposeDecorProfile(purpose)
	return DungeonArchetypeDecorData.PURPOSE_DECOR_PROFILE[purpose] or DungeonArchetypeDecorData.PURPOSE_DECOR_PROFILE.combat
end

-- === Public API ============================================================

function DungeonArchetypeModule.BuildRoomContext(input)
	local roomTypeRecord = input.roomTypeRecord or {}
	local archetypeRecord = input.archetypeRecord or {}
	local profile = input.profile or {}
	local seed = tonumber(input.seed) or 1
	local rng = input.rng or Random.new(seed)

	local purpose = inferPurpose(roomTypeRecord)
	local conditionWeights = DungeonArchetypeDecorData.CONDITION_WEIGHTS_BY_ARCHETYPE[archetypeRecord.id]
		or DungeonArchetypeDecorData.CONDITION_WEIGHTS_BY_ARCHETYPE.default
	local condition = weightedPick(rng, conditionWeights)
	local decorProfile = purposeDecorProfile(purpose)

	-- Runtime-derived tuning that depends on both authored data and room state.
	local ruinLevelByCondition = {
		intact = 0.02,
		dusty = 0.12,
		neglected = 0.26,
		partially_ruined = 0.45,
		collapsed = 0.78,
		arcane_disturbed = 0.34,
	}

	local wallRoleWeights = {
		structural = 1.0,
		furniture_support = 0.9 + (decorProfile.shelfBias * 0.35),
		focal_decor = 0.65 + (decorProfile.writingBias * 0.28),
		broken_ruined = 0.25 + (ruinLevelByCondition[condition] or 0) * 1.35,
	}

	local roofProfile = DungeonArchetypeDecorData.ROOF_PROFILE_BY_PURPOSE[purpose]
		or DungeonArchetypeDecorData.ROOF_PROFILE_BY_PURPOSE.combat
	if condition == "collapsed" then
		roofProfile = {
			flat = 0.15,
			ribbed = 0.15,
			beam = 0.2,
			collapsed = 0.5,
		}
	elseif condition == "partially_ruined" then
		roofProfile = {
			flat = roofProfile.flat * 0.7,
			ribbed = roofProfile.ribbed * 0.8,
			beam = roofProfile.beam * 1.1,
			collapsed = math.max(0.15, roofProfile.collapsed * 2),
		}
	end

	local arcaneBias = 0.06
	if containsTag(roomTypeRecord.tags, "ritual") or containsTag(roomTypeRecord.tags, "arcane") then
		arcaneBias += 0.16
	end
	if condition == "arcane_disturbed" then
		arcaneBias += 0.24
	end

	local profileArea = ((profile.dimensions and profile.dimensions.x) or 1) * ((profile.dimensions and profile.dimensions.z) or 1)
	local importance = 0.45
	if containsTag(roomTypeRecord.tags, "boss") or containsTag(roomTypeRecord.tags, "landmark") then
		importance = 0.9
	elseif containsTag(roomTypeRecord.tags, "reward") then
		importance = 0.72
	elseif profileArea >= 10 then
		importance = 0.6
	end

	return {
		purpose = purpose,
		condition = condition,
		importance = importance,
		narrativeAnchor = DungeonArchetypeDecorData.ANCHOR_BY_PURPOSE[purpose] or "generic_anchor",
		roofProfile = roofProfile,
		wallRoleWeights = wallRoleWeights,
		ruinLevel = ruinLevelByCondition[condition] or 0.2,
		clutterBias = decorProfile.clutterBias,
		shelfBias = decorProfile.shelfBias,
		furnitureBias = decorProfile.furnitureBias,
		writingBias = decorProfile.writingBias,
		lootBias = decorProfile.lootBias,
		arcaneBias = math.clamp(arcaneBias, 0, 1),
	}
end

return DungeonArchetypeModule

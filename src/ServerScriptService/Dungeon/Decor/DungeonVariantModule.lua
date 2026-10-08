local DungeonVariantModule = {}

local function weightedPick(rng, entries)
	local total = 0
	for _, entry in ipairs(entries) do
		total += math.max(0, entry.weight or 0)
	end
	if total <= 0 then
		return nil
	end

	local roll = rng:NextNumber(0, total)
	local cursor = 0
	for _, entry in ipairs(entries) do
		cursor += math.max(0, entry.weight or 0)
		if roll <= cursor then
			return entry
		end
	end
	return entries[#entries]
end

function DungeonVariantModule.NewMemory()
	return {
		globalCounts = {},
		roomCounts = {},
		recentByRoom = {},
	}
end

local function getRoomMap(memory, roomId)
	local key = tostring(roomId or "room_unknown")
	local map = memory.roomCounts[key]
	if not map then
		map = {}
		memory.roomCounts[key] = map
	end
	return map
end

local function getRecentList(memory, roomId)
	local key = tostring(roomId or "room_unknown")
	local list = memory.recentByRoom[key]
	if not list then
		list = {}
		memory.recentByRoom[key] = list
	end
	return list
end

function DungeonVariantModule.RegisterUse(memory, roomId, variantId)
	if not memory or type(variantId) ~= "string" then
		return
	end
	memory.globalCounts[variantId] = (memory.globalCounts[variantId] or 0) + 1
	local roomMap = getRoomMap(memory, roomId)
	roomMap[variantId] = (roomMap[variantId] or 0) + 1

	local recent = getRecentList(memory, roomId)
	recent[#recent + 1] = variantId
	local maxRecent = 5
	while #recent > maxRecent do
		table.remove(recent, 1)
	end
end

local function baseWeightFor(variant)
	if type(variant) ~= "table" then
		return 0
	end
	return math.max(0.0001, tonumber(variant.weight) or 1)
end

local function applyTagBias(weight, variant, tagBias)
	if type(tagBias) ~= "table" or type(variant.tags) ~= "table" then
		return weight
	end
	local out = weight
	for _, tag in ipairs(variant.tags) do
		local mul = tonumber(tagBias[tag])
		if mul then
			out *= math.max(0, mul)
		end
	end
	return out
end

local function applyRepetitionPenalty(weight, variantId, roomMap, globalCounts, recentList)
	local roomCount = roomMap[variantId] or 0
	local globalCount = globalCounts[variantId] or 0
	local recentPenalty = 0
	for _, recentId in ipairs(recentList) do
		if recentId == variantId then
			recentPenalty += 1
		end
	end

	local roomPenalty = 1 / (1 + (roomCount * 1.2))
	local globalPenalty = 1 / (1 + (globalCount * 0.35))
	local recencyPenalty = 1 / (1 + (recentPenalty * 0.8))
	return weight * roomPenalty * globalPenalty * recencyPenalty
end

function DungeonVariantModule.SelectVariant(memory, roomId, variants, rng, options)
	if type(variants) ~= "table" or #variants == 0 then
		return nil
	end
	local safeMemory = memory or DungeonVariantModule.NewMemory()
	local safeRng = rng or Random.new()
	local roomMap = getRoomMap(safeMemory, roomId)
	local recentList = getRecentList(safeMemory, roomId)
	local tagBias = options and options.tagBias or nil

	local weighted = {}
	for _, variant in ipairs(variants) do
		local variantId = tostring(variant.id or variant.tileId or "variant")
		local weight = baseWeightFor(variant)
		weight = applyTagBias(weight, variant, tagBias)
		weight = applyRepetitionPenalty(weight, variantId, roomMap, safeMemory.globalCounts, recentList)
		weighted[#weighted + 1] = {
			variant = variant,
			variantId = variantId,
			weight = weight,
		}
	end

	local picked = weightedPick(safeRng, weighted)
	if not picked then
		return variants[1]
	end

	DungeonVariantModule.RegisterUse(safeMemory, roomId, picked.variantId)
	return picked.variant
end

return DungeonVariantModule

--[[
	DungeonAssetRegistry

	Registry adapter around canonical data tables.
	This is the only source of truth for WFC decor tile/assets.
]]

local DungeonData = require(script.Parent.Parent.Data.DungeonData)
local DungeonDecorAssetRegistryData = DungeonData.Decor.DecorAssetRegistryData

local DungeonAssetRegistry = {}

local function deepCopy(source)
	if type(source) ~= "table" then
		return source
	end
	local out = {}
	for k, v in pairs(source) do
		out[k] = deepCopy(v)
	end
	return out
end

local function normalizeEntry(entry)
	local out = deepCopy(entry)
	out.footprint = out.footprint or { w = 1, d = 1, h = 1 }
	out.roomRoleSuitability = out.roomRoleSuitability or {}
	out.adjacencyProfile = out.adjacencyProfile or nil
	out.variantFamilyId = out.variantFamilyId or nil
	out.rarity = tonumber(out.rarity) or 1
	out.isStructural = (out.isStructural == true)
	out.isFurniture = (out.isFurniture == true)
	out.isClutter = (out.isClutter == true)
	return out
end

local ENTRIES = {}
for id, entry in pairs(DungeonDecorAssetRegistryData.Entries) do
	ENTRIES[id] = normalizeEntry(entry)
end
local HOOKS = DungeonDecorAssetRegistryData.Hooks

local REQUIRED_ENTRY_FIELDS = {
	"id",
	"category",
	"tags",
	"socket",
	"baseWeight",
	"walkable",
	"collision",
	"navCost",
	"allowedZones",
	"allowedSurfaces",
	"footprint",
	"roomRoleSuitability",
	"rarity",
	"isStructural",
	"isFurniture",
	"isClutter",
}

function DungeonAssetRegistry.Get(tileId)
	return ENTRIES[tileId]
end

function DungeonAssetRegistry.GetAll()
	return ENTRIES
end

function DungeonAssetRegistry.ListIds()
	local ids = {}
	for id in pairs(ENTRIES) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	return ids
end

function DungeonAssetRegistry.Has(tileId)
	return ENTRIES[tileId] ~= nil
end

function DungeonAssetRegistry.GetHooks()
	return HOOKS
end

function DungeonAssetRegistry.Validate()
	local issues = {}
	for key, entry in pairs(ENTRIES) do
		for _, fieldName in ipairs(REQUIRED_ENTRY_FIELDS) do
			if entry[fieldName] == nil then
				issues[#issues + 1] = string.format("Registry entry '%s' missing required field '%s'", tostring(key), fieldName)
			end
		end
		if type(entry.id) ~= "string" or entry.id == "" then
			issues[#issues + 1] = string.format("Registry entry '%s' has invalid id", tostring(key))
		elseif entry.id ~= key then
			issues[#issues + 1] = string.format("Registry key/id mismatch: key='%s' id='%s'", tostring(key), tostring(entry.id))
		end
		if entry.category ~= "Empty" and type(entry.assetId) ~= "string" then
			issues[#issues + 1] = string.format("Registry entry '%s' missing assetId for non-empty category", tostring(key))
		end
		if type(entry.tags) ~= "table" then
			issues[#issues + 1] = string.format("Registry entry '%s' tags must be table", tostring(key))
		end
		if type(entry.baseWeight) ~= "number" or entry.baseWeight <= 0 then
			issues[#issues + 1] = string.format("Registry entry '%s' baseWeight must be > 0", tostring(key))
		end
		if type(entry.allowedZones) ~= "table" then
			issues[#issues + 1] = string.format("Registry entry '%s' allowedZones must be table", tostring(key))
		end
	end
	return #issues == 0, issues
end

return DungeonAssetRegistry

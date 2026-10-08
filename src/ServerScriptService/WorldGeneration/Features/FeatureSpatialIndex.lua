--!strict

local FeatureGeometry = require(script.Parent.FeatureGeometry)

local FeatureSpatialIndex = {}
local IndexMetatable = {}
IndexMetatable.__index = IndexMetatable

local function key(x: number, z: number): string
	return ("%d:%d"):format(x, z)
end

local function intersects(a, b): boolean
	return a.min.X < b.max.X and a.max.X > b.min.X
		and a.min.Y < b.max.Y and a.max.Y > b.min.Y
		and a.min.Z < b.max.Z and a.max.Z > b.min.Z
end

function FeatureSpatialIndex.Build(items: { any }, cellSize: number, maxCellsPerItem: number?)
	if type(items) ~= "table" then
		return nil, "spatial index items must be a table"
	end
	if type(cellSize) ~= "number" or cellSize ~= cellSize or cellSize <= 0 or cellSize == math.huge then
		return nil, "spatial index cellSize must be finite and positive"
	end
	local perItemCap = maxCellsPerItem or 4096
	if type(perItemCap) ~= "number" or perItemCap ~= perItemCap or perItemCap == math.huge
		or perItemCap % 1 ~= 0 or perItemCap < 1
	then
		return nil, "maxCellsPerItem must be a positive integer"
	end
	local index = setmetatable({
		CellSize = cellSize,
		MaxQueryCells = perItemCap,
		Cells = {},
		ItemsById = {},
	}, IndexMetatable)
	for _, item in ipairs(items) do
		if type(item) ~= "table" or type(item.id) ~= "string" or item.id == "" then
			return nil, "each indexed item must have a non-empty id"
		end
		if index.ItemsById[item.id] then
			return nil, "duplicate spatial index item id: " .. item.id
		end
		local valid, reason = FeatureGeometry.ValidateBounds(item.bounds)
		if not valid then
			return nil, ("item %s has invalid bounds: %s"):format(item.id, reason or "unknown error")
		end
		local bounds = item.bounds
		local minCellX, maxCellX = math.floor(bounds.min.X / cellSize), math.ceil(bounds.max.X / cellSize) - 1
		local minCellZ, maxCellZ = math.floor(bounds.min.Z / cellSize), math.ceil(bounds.max.Z / cellSize) - 1
		local cellCount = (maxCellX - minCellX + 1) * (maxCellZ - minCellZ + 1)
		if cellCount > perItemCap then
			return nil, ("item %s covers %d cells, exceeding cap %d"):format(item.id, cellCount, perItemCap)
		end
		index.ItemsById[item.id] = item
		for x = minCellX, maxCellX do
			for z = minCellZ, maxCellZ do
				local cellKey = key(x, z)
				local bucket = index.Cells[cellKey]
				if not bucket then
					bucket = {}
					index.Cells[cellKey] = bucket
				end
			bucket[item.id] = true
			end
		end
	end
	return index
end

function IndexMetatable:Query(bounds): ({ any }?, string?)
	local valid, reason = FeatureGeometry.ValidateBounds(bounds)
	if not valid then
		return nil, reason
	end
	local cellSize = self.CellSize
	local minCellX, maxCellX = math.floor(bounds.min.X / cellSize), math.ceil(bounds.max.X / cellSize) - 1
	local minCellZ, maxCellZ = math.floor(bounds.min.Z / cellSize), math.ceil(bounds.max.Z / cellSize) - 1
	local queryCellCount = (maxCellX - minCellX + 1) * (maxCellZ - minCellZ + 1)
	if queryCellCount > self.MaxQueryCells then
		return nil, ("query covers %d cells, exceeding cap %d"):format(queryCellCount, self.MaxQueryCells)
	end
	local found = {}
	local ids = {}
	for x = minCellX, maxCellX do
		for z = minCellZ, maxCellZ do
			local bucket = self.Cells[key(x, z)]
			if bucket then
				for id in pairs(bucket) do
					if not found[id] then
						found[id] = true
						ids[#ids + 1] = id
					end
				end
			end
		end
	end
	table.sort(ids)
	local result = {}
	for _, id in ipairs(ids) do
		local item = self.ItemsById[id]
		if intersects(item.bounds, bounds) then
			result[#result + 1] = item
		end
	end
	return result
end

return table.freeze(FeatureSpatialIndex)

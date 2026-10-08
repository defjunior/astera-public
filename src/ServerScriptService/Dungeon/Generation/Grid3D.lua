local DungeonTypes = require(script.Parent.DungeonTypes)
local CellType = DungeonTypes.CellType

local Grid3D = {}
Grid3D.__index = Grid3D

function Grid3D.new(width, height, depth)
	assert(width > 0 and height > 0 and depth > 0, "Grid3D requires positive dimensions")

	local self = setmetatable({}, Grid3D)
	self.width = math.floor(width)
	self.height = math.floor(height)
	self.depth = math.floor(depth)
	self._data = table.create(self.width * self.height * self.depth)
	self._occupied = {} -- sparse set of occupied linear indices
	return self
end

function Grid3D:Index(x, y, z)
	return ((y * self.depth + z) * self.width) + x + 1
end

function Grid3D:InBoundsXYZ(x, y, z)
	return x >= 0 and x < self.width
		and y >= 0 and y < self.height
		and z >= 0 and z < self.depth
end

function Grid3D:InBounds(pos)
	return self:InBoundsXYZ(pos.x, pos.y, pos.z)
end

function Grid3D:GetXYZ(x, y, z)
	if not self:InBoundsXYZ(x, y, z) then
		return nil
	end
	return self._data[self:Index(x, y, z)]
end

function Grid3D:Get(pos)
	return self:GetXYZ(pos.x, pos.y, pos.z)
end

function Grid3D:SetXYZ(x, y, z, cell)
	if not self:InBoundsXYZ(x, y, z) then
		return false
	end

	local index = self:Index(x, y, z)
	if cell == nil or cell.CellType == CellType.None then
		self._data[index] = nil
		if self._occupied[index] then
			self._occupied[index] = nil
		end
	else
		self._data[index] = cell
		if not self._occupied[index] then
			self._occupied[index] = true
		end
	end

	return true
end

function Grid3D:Set(pos, cell)
	return self:SetXYZ(pos.x, pos.y, pos.z, cell)
end

function Grid3D:IsOccupied(pos)
	local cell = self:Get(pos)
	return cell ~= nil and cell.CellType ~= CellType.None
end

function Grid3D:ForEachOccupied(callback)
	local data = self._data
	local width = self.width
	local depth = self.depth
	for index in pairs(self._occupied) do
		local cell = data[index]
		if cell then
			-- Decode position from linear index: index = ((y * depth + z) * width) + x + 1
			local idx0 = index - 1
			local x = idx0 % width
			local remaining = (idx0 - x) / width
			local z = remaining % depth
			local y = (remaining - z) / depth
			callback({ x = x, y = y, z = z }, cell)
		end
	end
end

return Grid3D

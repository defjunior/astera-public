local DungeonTypes = {}

DungeonTypes.CellType = {
	None = "None",
	Room = "Room",
	Hallway = "Hallway",
	Stairs = "Stairs",
}

DungeonTypes.CellSubtype = {
	Default = "Default",
	StairBottom1 = "StairBottom1",
	StairBottom2 = "StairBottom2",
	StairAir = "StairAir",
}

DungeonTypes.Direction = {
	North = "North",
	South = "South",
	East = "East",
	West = "West",
}

local directionVectors = {
	North = { x = 0, y = 0, z = -1 },
	South = { x = 0, y = 0, z = 1 },
	East = { x = 1, y = 0, z = 0 },
	West = { x = -1, y = 0, z = 0 },
}

function DungeonTypes.Vector3i(x, y, z)
	return {
		x = math.floor(x),
		y = math.floor(y),
		z = math.floor(z),
	}
end

function DungeonTypes.Copy(pos)
	return {
		x = pos.x,
		y = pos.y,
		z = pos.z,
	}
end

function DungeonTypes.Add(a, b)
	return {
		x = a.x + b.x,
		y = a.y + b.y,
		z = a.z + b.z,
	}
end

function DungeonTypes.Sub(a, b)
	return {
		x = a.x - b.x,
		y = a.y - b.y,
		z = a.z - b.z,
	}
end

function DungeonTypes.Equals(a, b)
	return a.x == b.x and a.y == b.y and a.z == b.z
end

function DungeonTypes.ManhattanDistance(a, b)
	return math.abs(a.x - b.x) + math.abs(a.y - b.y) + math.abs(a.z - b.z)
end

function DungeonTypes.WeightedDistance(a, b, verticalWeight)
	local dx = a.x - b.x
	local dy = (a.y - b.y) * verticalWeight
	local dz = a.z - b.z
	return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

function DungeonTypes.Key(pos)
	return pos.x .. "," .. pos.y .. "," .. pos.z
end

function DungeonTypes.ParseKey(key)
	local x, y, z = string.match(key, "^(-?%d+),(-?%d+),(-?%d+)$")
	if not x or not y or not z then
		return nil
	end
	return {
		x = tonumber(x),
		y = tonumber(y),
		z = tonumber(z),
	}
end

function DungeonTypes.DirectionVector(direction)
	local vec = directionVectors[direction]
	if not vec then
		return nil
	end
	return DungeonTypes.Copy(vec)
end

function DungeonTypes.MakeCell(cellType, cellSubtype, direction, roomId)
	return {
		CellType = cellType,
		CellSubtype = cellSubtype,
		Direction = direction,
		RoomId = roomId,
	}
end

function DungeonTypes.MakeRoom(id, min, size)
	local max = {
		x = min.x + size.x - 1,
		y = min.y + size.y - 1,
		z = min.z + size.z - 1,
	}

	local center = {
		x = min.x + math.floor((size.x - 1) / 2),
		y = min.y + math.floor((size.y - 1) / 2),
		z = min.z + math.floor((size.z - 1) / 2),
	}

	return {
		id = id,
		center = center,
		size = DungeonTypes.Copy(size),
		min = DungeonTypes.Copy(min),
		max = max,
	}
end

return DungeonTypes

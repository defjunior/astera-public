local DungeonTypes = require(script.Parent.DungeonTypes)
local CellType = DungeonTypes.CellType

local RoomPlacer = {}

local function rangesOverlap(minA, maxA, minB, maxB)
	return minA <= maxB and minB <= maxA
end

local function roomsOverlapBuffered(roomA, roomB, paddingXZ, paddingY)
	local aMinX = roomA.min.x - paddingXZ
	local aMaxX = roomA.max.x + paddingXZ
	local aMinY = roomA.min.y - paddingY
	local aMaxY = roomA.max.y + paddingY
	local aMinZ = roomA.min.z - paddingXZ
	local aMaxZ = roomA.max.z + paddingXZ

	return rangesOverlap(aMinX, aMaxX, roomB.min.x, roomB.max.x)
		and rangesOverlap(aMinY, aMaxY, roomB.min.y, roomB.max.y)
		and rangesOverlap(aMinZ, aMaxZ, roomB.min.z, roomB.max.z)
end

function RoomPlacer.PlaceRooms(config, rng)
	local rooms = {}
	local attempts = 0
	local maxAttempts = config.maxRoomPlacementAttempts
	local paddingXZ = config.roomPadding
	local paddingY = config.roomPaddingY
	local maxRoomSizeX = math.min(config.maxRoomSize, config.gridWidth)
	local maxRoomSizeY = math.min(config.maxRoomHeight, config.gridHeight)
	local maxRoomSizeZ = math.min(config.maxRoomSize, config.gridDepth)

	if config.minRoomSize > maxRoomSizeX or config.minRoomSize > maxRoomSizeZ or config.minRoomHeight > maxRoomSizeY then
		return rooms, {
			attempts = attempts,
			placed = #rooms,
			requested = config.roomCount,
		}
	end

	while #rooms < config.roomCount and attempts < maxAttempts do
		attempts = attempts + 1

		local roomSizeX = rng:NextInteger(config.minRoomSize, maxRoomSizeX)
		local roomSizeY = rng:NextInteger(config.minRoomHeight, maxRoomSizeY)
		local roomSizeZ = rng:NextInteger(config.minRoomSize, maxRoomSizeZ)

		local minX = rng:NextInteger(0, config.gridWidth - roomSizeX)
		local minY = rng:NextInteger(0, config.gridHeight - roomSizeY)
		local minZ = rng:NextInteger(0, config.gridDepth - roomSizeZ)

		local candidate = DungeonTypes.MakeRoom(#rooms + 1, {
			x = minX,
			y = minY,
			z = minZ,
		}, {
			x = roomSizeX,
			y = roomSizeY,
			z = roomSizeZ,
		})

		local overlaps = false
		for _, existing in ipairs(rooms) do
			if roomsOverlapBuffered(candidate, existing, paddingXZ, paddingY) then
				overlaps = true
				break
			end
		end

		if not overlaps then
			table.insert(rooms, candidate)
		end
	end

	return rooms, {
		attempts = attempts,
		placed = #rooms,
		requested = config.roomCount,
	}
end

function RoomPlacer.RasterizeRooms(grid, rooms)
	-- Hot path: inline Grid3D writes and share one cell table per room.
	-- Rooms are guaranteed in-bounds by PlaceRooms, so bounds checks are skipped.
	-- Cells are never mutated after creation, so sharing is safe.
	local data = grid._data
	local occupied = grid._occupied
	local width = grid.width
	local depth = grid.depth
	for _, room in ipairs(rooms) do
		local cell = DungeonTypes.MakeCell(CellType.Room, nil, nil, room.id)
		local minX, maxX = room.min.x, room.max.x
		local minY, maxY = room.min.y, room.max.y
		local minZ, maxZ = room.min.z, room.max.z
		for y = minY, maxY do
			local yBase = y * depth
			for z = minZ, maxZ do
				local rowBase = (yBase + z) * width + 1
				for x = minX, maxX do
					local index = rowBase + x
					data[index] = cell
					occupied[index] = true
				end
			end
		end
	end
end

return RoomPlacer

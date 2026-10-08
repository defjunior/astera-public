local DungeonTypes = require(script.Parent.DungeonTypes)

local CellType = DungeonTypes.CellType
local CellSubtype = DungeonTypes.CellSubtype

local LayoutBuilder = {}

local neighbors = {
	North = { x = 0, y = 0, z = -1 },
	South = { x = 0, y = 0, z = 1 },
	East = { x = 1, y = 0, z = 0 },
	West = { x = -1, y = 0, z = 0 },
	Top = { x = 0, y = 1, z = 0 },
	Bottom = { x = 0, y = -1, z = 0 },
}

local function add(a, b)
	return {
		x = a.x + b.x,
		y = a.y + b.y,
		z = a.z + b.z,
	}
end

local function countTrueEntries(map)
	local count = 0
	for _, value in pairs(map or {}) do
		if value == true then
			count += 1
		end
	end
	return count
end

local function isOccupied(cell)
	return cell ~= nil and cell.CellType ~= CellType.None
end

local function isTransitCell(cell)
	if not cell then
		return false
	end
	return cell.CellType == CellType.Hallway or cell.CellType == CellType.Stairs
end

local function isInsideRoom(room, pos)
	return pos.x >= room.min.x and pos.x <= room.max.x
		and pos.y >= room.min.y and pos.y <= room.max.y
		and pos.z >= room.min.z and pos.z <= room.max.z
end

local function manhattanDistance(a, b)
	return math.abs(a.x - b.x) + math.abs(a.y - b.y) + math.abs(a.z - b.z)
end

local function pairKey(a, b)
	local ax, ay, az = a.x, a.y, a.z
	local bx, by, bz = b.x, b.y, b.z
	-- Deterministic ordering: compare components directly instead of building
	-- two key strings and using lexicographic comparison
	local aFirst
	if ax ~= bx then
		aFirst = ax < bx
	elseif ay ~= by then
		aFirst = ay < by
	elseif az ~= bz then
		aFirst = az < bz
	else
		aFirst = true
	end
	if aFirst then
		return ax .. "," .. ay .. "," .. az .. "|" .. bx .. "," .. by .. "," .. bz
	end
	return bx .. "," .. by .. "," .. bz .. "|" .. ax .. "," .. ay .. "," .. az
end

local oppositeFace = {
	North = "South",
	South = "North",
	East = "West",
	West = "East",
	Top = "Bottom",
	Bottom = "Top",
}

local oppositeDirection = {
	North = "South",
	South = "North",
	East = "West",
	West = "East",
}

local function findExitForward(steps, room)
	for i = 2, #steps do
		local prevPos = steps[i - 1].position
		local curPos = steps[i].position
		if isInsideRoom(room, prevPos) and not isInsideRoom(room, curPos) then
			return prevPos, curPos
		end
	end
	return nil, nil
end

local function findExitBackward(steps, room)
	for i = #steps, 2, -1 do
		local curPos = steps[i].position
		local prevPos = steps[i - 1].position
		if isInsideRoom(room, curPos) and not isInsideRoom(room, prevPos) then
			return curPos, prevPos
		end
	end
	return nil, nil
end

local horizontalFaces = { "North", "South", "East", "West" }

local function hallwayCanAccessStair(stairCell, faceFromStair)
	if not stairCell or stairCell.CellType ~= CellType.Stairs then
		return false
	end

	if stairCell.CellSubtype == CellSubtype.StairAir then
		return false
	end
	if stairCell.CellSubtype == CellSubtype.StairBottom1 then
		return faceFromStair == oppositeDirection[stairCell.Direction]
	end
	if stairCell.CellSubtype == CellSubtype.StairBottom2 then
		return false
	end

	return false
end

local function buildNearestStairDistanceByHallwayCell(grid)
	local distances = {}
	local queue = {}
	local head = 1

	grid:ForEachOccupied(function(pos, cell)
		if cell.CellType ~= CellType.Hallway then
			return
		end

		local px, py, pz = pos.x, pos.y, pos.z
		for _, face in ipairs(horizontalFaces) do
			local d = neighbors[face]
			local neighborPos = { x = px + d.x, y = py + d.y, z = pz + d.z }
			local neighborCell = grid:Get(neighborPos)
			if hallwayCanAccessStair(neighborCell, oppositeFace[face]) then
				local key = px .. "," .. py .. "," .. pz
				if distances[key] == nil then
					distances[key] = 0
					queue[#queue + 1] = { x = px, y = py, z = pz }
				end
				break
			end
		end
	end)

	while head <= #queue do
		local pos = queue[head]
		head += 1
		local px, py, pz = pos.x, pos.y, pos.z
		local key = px .. "," .. py .. "," .. pz
		local currentDistance = distances[key] or 0

		for _, face in ipairs(horizontalFaces) do
			local d = neighbors[face]
			local nx, ny, nz = px + d.x, py + d.y, pz + d.z
			local nextCell = grid:GetXYZ(nx, ny, nz)
			if nextCell and nextCell.CellType == CellType.Hallway then
				local nextKey = nx .. "," .. ny .. "," .. nz
				if distances[nextKey] == nil then
					distances[nextKey] = currentDistance + 1
					queue[#queue + 1] = { x = nx, y = ny, z = nz }
				end
			end
		end
	end

	return distances
end

local function buildAllowedRoomEntrances(grid, options)
	if not options then
		return {}
	end

	local carvedPaths = options.carvedPaths or {}
	local roomById = options.roomById or {}
	local maxRoomEntrances = math.max(1, options.maxRoomEntrances or 2)
	local candidatesByRoom = {}
	local nearestStairDistanceByHallway = buildNearestStairDistanceByHallwayCell(grid)

	local function addCandidate(roomId, roomPos, transitPos)
		if not roomPos or not transitPos then
			return
		end
		if manhattanDistance(roomPos, transitPos) ~= 1 then
			return
		end
		local transitCell = grid:Get(transitPos)
		if not transitCell or transitCell.CellType ~= CellType.Hallway then
			return
		end

		local roomCandidates = candidatesByRoom[roomId]
		if not roomCandidates then
			roomCandidates = {}
			candidatesByRoom[roomId] = roomCandidates
		end

		local key = pairKey(roomPos, transitPos)
		if not roomCandidates[key] then
			roomCandidates[key] = {
				key = key,
				count = 0,
				nearestStairDistance = nil,
			}
		end
		local candidate = roomCandidates[key]
		candidate.count += 1
		local transitKey = DungeonTypes.Key(transitPos)
		local stairDistance = nearestStairDistanceByHallway[transitKey]
		if stairDistance ~= nil
			and (candidate.nearestStairDistance == nil or stairDistance < candidate.nearestStairDistance)
		then
			candidate.nearestStairDistance = stairDistance
		end
	end

	for _, carved in ipairs(carvedPaths) do
		if carved.success and carved.steps and #carved.steps > 1 then
			local roomA = roomById[carved.roomAId]
			local roomB = roomById[carved.roomBId]
			if roomA then
				local roomPos, transitPos = findExitForward(carved.steps, roomA)
				addCandidate(roomA.id, roomPos, transitPos)
			end
			if roomB then
				local roomPos, transitPos = findExitBackward(carved.steps, roomB)
				addCandidate(roomB.id, roomPos, transitPos)
			end
		end
	end

	local allowedEntrances = {}
	for _, roomCandidates in pairs(candidatesByRoom) do
		local ordered = {}
		for _, entry in pairs(roomCandidates) do
			table.insert(ordered, entry)
		end
		table.sort(ordered, function(a, b)
			local aHasStairPath = a.nearestStairDistance ~= nil
			local bHasStairPath = b.nearestStairDistance ~= nil
			if aHasStairPath ~= bHasStairPath then
				return aHasStairPath
			end
			if aHasStairPath and bHasStairPath and a.nearestStairDistance ~= b.nearestStairDistance then
				return a.nearestStairDistance < b.nearestStairDistance
			end
			if a.count ~= b.count then
				return a.count > b.count
			end
			return a.key < b.key
		end)

		local limit = math.min(maxRoomEntrances, #ordered)
		for i = 1, limit do
			allowedEntrances[ordered[i].key] = true
		end
	end

	return allowedEntrances
end

local function buildForcedOpenings(options)
	local forced = {}
	if not options then
		return forced
	end

	local carvedPaths = options.carvedPaths or {}

	local function forcePair(a, b)
		if not a or not b then
			return
		end
		if manhattanDistance(a, b) ~= 1 then
			return
		end
		forced[pairKey(a, b)] = true
	end

	for _, carved in ipairs(carvedPaths) do
		if carved.success and carved.steps and #carved.steps > 1 then
			for i = 2, #carved.steps do
				local prevStep = carved.steps[i - 1]
				local step = carved.steps[i]
				local action = step.action
				if action then
					if action.kind == "walk" then
						forcePair(prevStep.position, step.position)
					elseif action.kind == "stair" then
						local t = action.transition
						if t then
							forcePair(t.bottom1, t.bottom2)
							forcePair(t.air1, t.air2)
							forcePair(t.bottom1, t.air1)
							forcePair(t.bottom2, t.air2)

							if action.dy == 1 then
								forcePair(prevStep.position, t.bottom1)
								forcePair(t.air2, t.landing)
							else
								forcePair(prevStep.position, t.air1)
								forcePair(t.bottom2, t.landing)
							end
						end
					end
				end
			end
		end
	end

	return forced
end

local function shouldOpenVertical(cell, neighbor)
	if not isOccupied(cell) or not isOccupied(neighbor) then
		return false
	end
	if cell.CellSubtype == CellSubtype.StairAir or neighbor.CellSubtype == CellSubtype.StairAir then
		return true
	end
	if (cell.CellType == CellType.Room and isTransitCell(neighbor)) or (isTransitCell(cell) and neighbor.CellType == CellType.Room) then
		return false
	end
	return true
end

local function cellSort(a, b)
	if a.Position.y ~= b.Position.y then
		return a.Position.y < b.Position.y
	end
	if a.Position.z ~= b.Position.z then
		return a.Position.z < b.Position.z
	end
	return a.Position.x < b.Position.x
end

local function shouldKeepMisalignedStairDivider(cell, neighbor)
	if not cell or not neighbor then
		return false
	end
	if cell.CellType ~= CellType.Stairs or neighbor.CellType ~= CellType.Stairs then
		return false
	end
	if not cell.Direction or not neighbor.Direction then
		return false
	end
	return cell.Direction ~= neighbor.Direction
end

local function stairAllowsHallwayAccess(stairCell, faceFromStair)
	return hallwayCanAccessStair(stairCell, faceFromStair)
end

local function shouldKeepStairHallwayDivider(cell, neighbor, face)
	local stairCell
	local faceFromStair

	if cell and neighbor and cell.CellType == CellType.Stairs and neighbor.CellType == CellType.Hallway then
		stairCell = cell
		faceFromStair = face
	elseif cell and neighbor and cell.CellType == CellType.Hallway and neighbor.CellType == CellType.Stairs then
		stairCell = neighbor
		faceFromStair = oppositeFace[face]
	else
		return false
	end

	return not stairAllowsHallwayAccess(stairCell, faceFromStair)
end

local function isRoomHallwayBoundary(cell, neighbor)
	return (cell.CellType == CellType.Room and neighbor.CellType == CellType.Hallway)
		or (cell.CellType == CellType.Hallway and neighbor.CellType == CellType.Room)
end

local function isRoomStairBoundary(cell, neighbor)
	return (cell.CellType == CellType.Room and neighbor.CellType == CellType.Stairs)
		or (cell.CellType == CellType.Stairs and neighbor.CellType == CellType.Room)
end

local function shouldKeepCrossSetStairAirDivider(cell, neighbor, edgeKey, forcedOpenings)
	if not cell or not neighbor then
		return false
	end
	if cell.CellType ~= CellType.Stairs or neighbor.CellType ~= CellType.Stairs then
		return false
	end

	local cellAir = (cell.CellSubtype == CellSubtype.StairAir)
	local neighborAir = (neighbor.CellSubtype == CellSubtype.StairAir)
	if cellAir == neighborAir then
		return false
	end

	-- If this edge is part of an explicitly carved stair transition, keep it open.
	if forcedOpenings and forcedOpenings[edgeKey] then
		return false
	end

	-- Only separate stair-air/block adjacency when runs are misaligned.
	if not cell.Direction or not neighbor.Direction then
		return false
	end
	return cell.Direction ~= neighbor.Direction
end

local function enforceStairStartWalls(grid, pos, record, walls)
	if record.CellSubtype ~= CellSubtype.StairBottom1 or not record.Direction then
		return
	end

	local accessFace = oppositeDirection[record.Direction]
	local forwardFace = record.Direction

	for _, face in ipairs({ "North", "South", "East", "West" }) do
		local neighborPos = add(pos, neighbors[face])
		local neighborCell = grid:Get(neighborPos)

		local shouldKeepOpen = false
		if face == accessFace then
			shouldKeepOpen = neighborCell ~= nil and neighborCell.CellType == CellType.Hallway
		elseif face == forwardFace then
			shouldKeepOpen = neighborCell ~= nil and neighborCell.CellType == CellType.Stairs
		elseif neighborCell
			and neighborCell.CellType == CellType.Stairs
			and neighborCell.CellSubtype == CellSubtype.StairBottom1
			and neighborCell.Direction == record.Direction
		then
			-- Support side-by-side "double stairs" starts that flow in parallel.
			shouldKeepOpen = true
		end

		if not shouldKeepOpen then
			if isOccupied(neighborCell) then
				walls[face] = "StairDivider"
			else
				walls[face] = "Solid"
			end
		end
	end
end

local function enforceStairWallCompatibility(grid, pos, record, walls)
	if record.CellType ~= CellType.Stairs then
		return
	end
	for _, face in ipairs(horizontalFaces) do
		if walls[face] == "Solid" then
			local neighborPos = add(pos, neighbors[face])
			local neighborCell = grid:Get(neighborPos)
			if not neighborCell or neighborCell.CellType ~= CellType.Stairs then
				-- Keep stairs enclosed with non-arch-capable wall class.
				walls[face] = "StairDivider"
			end
		end
	end
end

function LayoutBuilder.Build(grid, options)
	local cellsData = {}
	local wallsData = {}
	local doorwaysData = {}
	local allowedRoomEntrances = buildAllowedRoomEntrances(grid, options)
	local forcedOpenings = buildForcedOpenings(options)
	local stats = {
		occupiedCellCount = 0,
		allowedRoomEntranceCount = countTrueEntries(allowedRoomEntrances),
		forcedOpeningCount = countTrueEntries(forcedOpenings),
		doorwayCount = 0,
		wallFaceCounts = {
			open = 0,
			Solid = 0,
			RoomBoundary = 0,
			StairDivider = 0,
			GuardRail = 0,
		},
	}
	local doorwaySeen = {}

	grid:ForEachOccupied(function(pos, cell)
		local record = {
			Position = DungeonTypes.Copy(pos),
			CellType = cell.CellType,
			CellSubtype = cell.CellSubtype,
			Direction = cell.Direction,
			RoomId = cell.RoomId,
		}
		table.insert(cellsData, record)
		stats.occupiedCellCount += 1

		wallsData[DungeonTypes.Key(pos)] = {
			North = "Solid",
			South = "Solid",
			East = "Solid",
			West = "Solid",
			Top = "Solid",
			Bottom = "Solid",
		}
	end)

	table.sort(cellsData, cellSort)

	for _, record in ipairs(cellsData) do
		local pos = record.Position
		local key = DungeonTypes.Key(pos)
		local cell = grid:Get(pos)
		local walls = wallsData[key]

		for face, delta in pairs(neighbors) do
			local neighborPos = add(pos, delta)
			local neighborCell = grid:Get(neighborPos)
			if isOccupied(neighborCell) then
				local edgeKey = pairKey(pos, neighborPos)
				local roomHallwayBoundary = isRoomHallwayBoundary(cell, neighborCell)
				local roomStairBoundary = isRoomStairBoundary(cell, neighborCell)
				local blockedStairHallwayBoundary = shouldKeepStairHallwayDivider(cell, neighborCell, face)
				local crossSetStairAirDivider = shouldKeepCrossSetStairAirDivider(cell, neighborCell, edgeKey, forcedOpenings)

				if forcedOpenings[edgeKey] then
					if roomStairBoundary then
						walls[face] = "RoomBoundary"
					elseif shouldKeepMisalignedStairDivider(cell, neighborCell) then
						walls[face] = "StairDivider"
					elseif crossSetStairAirDivider then
						walls[face] = "StairDivider"
					else
						walls[face] = false
						if roomHallwayBoundary and not doorwaySeen[edgeKey] then
							doorwaySeen[edgeKey] = true
							table.insert(doorwaysData, {
								roomCell = DungeonTypes.Copy((cell.CellType == CellType.Room) and pos or neighborPos),
								transitCell = DungeonTypes.Copy((cell.CellType == CellType.Room) and neighborPos or pos),
								face = (cell.CellType == CellType.Room) and face or oppositeFace[face],
							})
						end
					end
				elseif face == "Top" or face == "Bottom" then
					if crossSetStairAirDivider then
						walls[face] = "StairDivider"
					elseif shouldOpenVertical(cell, neighborCell) then
						walls[face] = false
					end
				else
					if roomStairBoundary then
						walls[face] = "RoomBoundary"
					elseif crossSetStairAirDivider then
						walls[face] = "StairDivider"
					elseif shouldKeepMisalignedStairDivider(cell, neighborCell) then
						walls[face] = "StairDivider"
					elseif blockedStairHallwayBoundary then
						walls[face] = "StairDivider"
					elseif roomHallwayBoundary then
						local entranceKey = pairKey(pos, neighborPos)
						if allowedRoomEntrances[entranceKey] then
							walls[face] = false
							if not doorwaySeen[entranceKey] then
								doorwaySeen[entranceKey] = true
								table.insert(doorwaysData, {
									roomCell = DungeonTypes.Copy((cell.CellType == CellType.Room) and pos or neighborPos),
									transitCell = DungeonTypes.Copy((cell.CellType == CellType.Room) and neighborPos or pos),
									face = (cell.CellType == CellType.Room) and face or oppositeFace[face],
								})
							end
						else
							walls[face] = "RoomBoundary"
						end
					else
						walls[face] = false
					end
				end
			end
		end

		enforceStairStartWalls(grid, pos, record, walls)
		enforceStairWallCompatibility(grid, pos, record, walls)

		if record.CellSubtype == CellSubtype.StairBottom1 or record.CellSubtype == CellSubtype.StairBottom2 then
			walls.Top = false
		end

		if record.CellSubtype == CellSubtype.StairAir then
			if walls.Top == "Solid" then
				walls.Top = false
			end
			if walls.Bottom == "Solid" then
				walls.Bottom = false
			end
			for _, face in ipairs({ "North", "South", "East", "West" }) do
				local neighborPos = add(pos, neighbors[face])
				local neighborCell = grid:Get(neighborPos)
				if not isOccupied(neighborCell) then
					walls[face] = "GuardRail"
				elseif walls[face] == "Solid" then
					-- Keep any previously assigned divider/boundary rule; only clear untouched solid faces.
					walls[face] = false
				end
			end
		end

		for _, face in ipairs({ "North", "South", "East", "West", "Top", "Bottom" }) do
			local wallKind = walls[face]
			if wallKind == false then
				stats.wallFaceCounts.open += 1
			elseif type(wallKind) == "string" then
				stats.wallFaceCounts[wallKind] = (stats.wallFaceCounts[wallKind] or 0) + 1
			else
				stats.wallFaceCounts.Solid += 1
			end
		end
	end

	stats.doorwayCount = #doorwaysData

	return cellsData, wallsData, doorwaysData, stats
end

return LayoutBuilder

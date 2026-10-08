local BinaryHeap = require(script.Parent.BinaryHeap)
local DungeonTypes = require(script.Parent.DungeonTypes)
local StairPlanner = require(script.Parent.StairPlanner)

local CellType = DungeonTypes.CellType
local CellSubtype = DungeonTypes.CellSubtype

local HallwayCarver = {}

local ORTHOGONAL_DIRECTIONS = {
	{ name = DungeonTypes.Direction.East, delta = { x = 1, y = 0, z = 0 } },
	{ name = DungeonTypes.Direction.West, delta = { x = -1, y = 0, z = 0 } },
	{ name = DungeonTypes.Direction.South, delta = { x = 0, y = 0, z = 1 } },
	{ name = DungeonTypes.Direction.North, delta = { x = 0, y = 0, z = -1 } },
}

local DIRECTION_DELTA = {
	North = { x = 0, y = 0, z = -1 },
	South = { x = 0, y = 0, z = 1 },
	East = { x = 1, y = 0, z = 0 },
	West = { x = -1, y = 0, z = 0 },
}

local OPPOSITE_FACE = {
	North = "South",
	South = "North",
	East = "West",
	West = "East",
}

-- Shared hallway cell: all carved hallway cells carry identical data
-- (CellType=Hallway, nil everything else) and cells are never mutated after
-- creation, so a single shared table avoids per-voxel allocation.
local SHARED_HALLWAY_CELL = DungeonTypes.MakeCell(CellType.Hallway, nil, nil, nil)

local STAIR_DY = { 1, -1 }

local function resolvePathConfig(config, override)
	local minFlatStepsBetweenStairs = (override and override.minFlatStepsBetweenStairs)
		or (config and config.minFlatStepsBetweenStairs)
		or 2

	return {
		walkCost = (config and config.walkCost) or 10,
		stairCost = (config and config.stairCost) or 24,
		maxPathIterations = (override and override.maxPathIterations) or (config and config.maxPathIterations) or 14000,
		minFlatStepsBetweenStairs = math.max(0, math.floor(minFlatStepsBetweenStairs)),
		allowSameFloorStairDetours = (config and config.allowSameFloorStairDetours) == true,
		maxVisitedStates = (config and config.maxVisitedStates) or 28000,
		pathYieldInterval = (config and config.pathYieldInterval) or 500,
	}
end

local function boolFromConfig(value, fallback)
	if value == nil then
		return fallback
	end
	return value == true
end

local function numberFromConfig(value, fallback, minValue)
	local n = fallback
	if type(value) == "number" and value == value then
		n = value
	end
	n = math.floor(n)
	if minValue ~= nil and n < minValue then
		n = minValue
	end
	return n
end

local function add(a, b)
	return {
		x = a.x + b.x,
		y = a.y + b.y,
		z = a.z + b.z,
	}
end

local function copyPos(pos)
	return {
		x = pos.x,
		y = pos.y,
		z = pos.z,
	}
end

local function clamp(value, minValue, maxValue)
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function heuristic(a, b)
	local dx = math.abs(a.x - b.x)
	local dz = math.abs(a.z - b.z)
	local dy = math.abs(a.y - b.y)
	return dx + dz + (dy * 4)
end

local function pathSort(a, b)
	if math.abs(a.weight - b.weight) > 1e-6 then
		return a.weight < b.weight
	end
	if a.roomAId ~= b.roomAId then
		return a.roomAId < b.roomAId
	end
	return a.roomBId < b.roomBId
end

local function isWalkableCell(cell, isGoalCell)
	if not cell then
		return true
	end
	if cell.CellType == CellType.Room then
		return true
	end
	if cell.CellType == CellType.Hallway then
		return true
	end
	if cell.CellType == CellType.Stairs then
		-- Existing stair runs are not generic hallway walk space for A* walk moves.
		-- Vertical movement should be represented by explicit stair transitions.
		return false
	end
	return isGoalCell
end

local function isValidBottom1EntryFromHallway(stairCell, movementDirection)
	if not stairCell or stairCell.CellType ~= CellType.Stairs then
		return false
	end
	if stairCell.CellSubtype ~= CellSubtype.StairBottom1 then
		return false
	end
	if not stairCell.Direction then
		return false
	end
	-- movementDirection is hallway->stairs; valid entry is along stair direction.
	return movementDirection == stairCell.Direction
end

local function isValidBottom1ExitToHallway(stairCell, movementDirection)
	if not stairCell or stairCell.CellType ~= CellType.Stairs then
		return false
	end
	if stairCell.CellSubtype ~= CellSubtype.StairBottom1 then
		return false
	end
	if not stairCell.Direction then
		return false
	end
	-- movementDirection is stairs->hallway; valid exit is opposite stair direction.
	return movementDirection == OPPOSITE_FACE[stairCell.Direction]
end

local function canWalkBetween(currentCell, nextCell, movementDirection)
	if not currentCell or not nextCell then
		return true
	end

	if currentCell.CellType == CellType.Stairs and nextCell.CellType == CellType.Stairs then
		return false
	end

	if currentCell.CellType == CellType.Hallway and nextCell.CellType == CellType.Stairs then
		return isValidBottom1EntryFromHallway(nextCell, movementDirection)
	end

	if currentCell.CellType == CellType.Stairs and nextCell.CellType == CellType.Hallway then
		return isValidBottom1ExitToHallway(currentCell, movementDirection)
	end

	return true
end

local function isEntranceOutsideCellValid(cell)
	if not cell then
		return true
	end
	if cell.CellType == CellType.Hallway then
		return true
	end
	return false
end

local function traversalCost(cell, isGoalCell)
	if not cell then
		return 1
	end
	if cell.CellType == CellType.Hallway then
		return 0.4
	end
	if cell.CellType == CellType.Room then
		if isGoalCell then
			return 1
		end
		return 5
	end
	if cell.CellType == CellType.Stairs then
		if cell.CellSubtype == CellSubtype.StairAir then
			return math.huge
		end
		return 1
	end
	return 1
end

local function compareEntranceCandidates(a, b)
	if math.abs(a.score - b.score) > 1e-6 then
		return a.score < b.score
	end
	if a.inside.y ~= b.inside.y then
		return a.inside.y < b.inside.y
	end
	if a.inside.z ~= b.inside.z then
		return a.inside.z < b.inside.z
	end
	if a.inside.x ~= b.inside.x then
		return a.inside.x < b.inside.x
	end
	return a.face < b.face
end

local function getFaceOrderTowardTarget(room, targetRoom)
	local dx = targetRoom.center.x - room.center.x
	local dz = targetRoom.center.z - room.center.z
	local order = {}
	local seen = {}

	local function push(face)
		if not seen[face] then
			seen[face] = true
			order[#order + 1] = face
		end
	end

	if math.abs(dx) >= math.abs(dz) then
		push((dx >= 0) and "East" or "West")
		push((dz >= 0) and "South" or "North")
	else
		push((dz >= 0) and "South" or "North")
		push((dx >= 0) and "East" or "West")
	end

	for _, face in ipairs({ "North", "South", "East", "West" }) do
		push(face)
	end

	return order
end

local function getBoundaryCellsForFace(room, face, y, targetRoom)
	local cells = {}
	if face == "North" then
		for x = room.min.x, room.max.x do
			cells[#cells + 1] = { x = x, y = y, z = room.min.z }
		end
		table.sort(cells, function(a, b)
			local da = math.abs(a.x - targetRoom.center.x)
			local db = math.abs(b.x - targetRoom.center.x)
			if da ~= db then
				return da < db
			end
			return a.x < b.x
		end)
	elseif face == "South" then
		for x = room.min.x, room.max.x do
			cells[#cells + 1] = { x = x, y = y, z = room.max.z }
		end
		table.sort(cells, function(a, b)
			local da = math.abs(a.x - targetRoom.center.x)
			local db = math.abs(b.x - targetRoom.center.x)
			if da ~= db then
				return da < db
			end
			return a.x < b.x
		end)
	elseif face == "East" then
		for z = room.min.z, room.max.z do
			cells[#cells + 1] = { x = room.max.x, y = y, z = z }
		end
		table.sort(cells, function(a, b)
			local da = math.abs(a.z - targetRoom.center.z)
			local db = math.abs(b.z - targetRoom.center.z)
			if da ~= db then
				return da < db
			end
			return a.z < b.z
		end)
	elseif face == "West" then
		for z = room.min.z, room.max.z do
			cells[#cells + 1] = { x = room.min.x, y = y, z = z }
		end
		table.sort(cells, function(a, b)
			local da = math.abs(a.z - targetRoom.center.z)
			local db = math.abs(b.z - targetRoom.center.z)
			if da ~= db then
				return da < db
			end
			return a.z < b.z
		end)
	end
	return cells
end

local function buildEntranceCandidates(grid, room, targetRoom, config)
	local maxCandidates = numberFromConfig(config and config.maxEntranceCandidatesPerRoom, 10, 1)
	local maxPerFace = numberFromConfig(config and config.maxEntranceCandidatesPerFace, 3, 1)
	local orderedFaces = getFaceOrderTowardTarget(room, targetRoom)
	local y = clamp(targetRoom.center.y, room.min.y, room.max.y)
	local candidates = {}

	for _, face in ipairs(orderedFaces) do
		local delta = DIRECTION_DELTA[face]
		local boundaryCells = getBoundaryCellsForFace(room, face, y, targetRoom)
		local pushedOnFace = 0

		for _, inside in ipairs(boundaryCells) do
			if pushedOnFace >= maxPerFace or #candidates >= maxCandidates then
				break
			end

			local outside = add(inside, delta)
			if grid:InBounds(outside) then
				local outsideCell = grid:Get(outside)
				if isEntranceOutsideCellValid(outsideCell) then
					candidates[#candidates + 1] = {
						face = face,
						inside = copyPos(inside),
						outside = copyPos(outside),
						score = heuristic(outside, targetRoom.center),
					}
					pushedOnFace += 1
				end
			end
		end

		if #candidates >= maxCandidates then
			break
		end
	end

	table.sort(candidates, compareEntranceCandidates)
	return candidates
end

local function buildEntrancePairs(grid, roomA, roomB, config)
	local maxPairs = numberFromConfig(config and config.maxEntrancePairAttempts, 16, 1)
	local candidatesA = buildEntranceCandidates(grid, roomA, roomB, config)
	local candidatesB = buildEntranceCandidates(grid, roomB, roomA, config)
	local pairs = {}

	for _, startCandidate in ipairs(candidatesA) do
		for _, goalCandidate in ipairs(candidatesB) do
			pairs[#pairs + 1] = {
				start = startCandidate,
				goal = goalCandidate,
				score = heuristic(startCandidate.outside, goalCandidate.outside)
					+ startCandidate.score
					+ goalCandidate.score,
			}
		end
	end

	table.sort(pairs, function(a, b)
		if math.abs(a.score - b.score) > 1e-6 then
			return a.score < b.score
		end
		local aStart = a.start.inside
		local bStart = b.start.inside
		if aStart.y ~= bStart.y then
			return aStart.y < bStart.y
		end
		if aStart.z ~= bStart.z then
			return aStart.z < bStart.z
		end
		return aStart.x < bStart.x
	end)

	if #pairs > maxPairs then
		local trimmed = {}
		for i = 1, maxPairs do
			trimmed[i] = pairs[i]
		end
		return trimmed
	end

	return pairs
end

local function prependAppendRoomAnchors(pathSteps, startPortal, goalPortal)
	if not pathSteps or #pathSteps == 0 then
		return nil
	end

	local out = {}
	out[#out + 1] = {
		position = copyPos(startPortal.inside),
		action = nil,
	}

	for index, step in ipairs(pathSteps) do
		local action = step.action
		if index == 1 then
			action = {
				kind = "walk",
				direction = startPortal.face,
			}
		end

		out[#out + 1] = {
			position = copyPos(step.position),
			action = action,
		}
	end

	out[#out + 1] = {
		position = copyPos(goalPortal.inside),
		action = {
			kind = "walk",
			direction = OPPOSITE_FACE[goalPortal.face],
		},
	}

	return out
end

local function stateKey(pos, stairCooldown)
	return pos.x .. "," .. pos.y .. "," .. pos.z .. "|" .. stairCooldown
end

local function reconstructPath(cameFrom, stateToPosition, goalStateKey)
	local sequence = {}
	local cursor = goalStateKey
	local count = 0

	while cursor do
		count += 1
		local stepPos = stateToPosition[cursor]
		local link = cameFrom[cursor]
		sequence[count] = {
			position = stepPos,
			action = link and link.action or nil,
		}
		cursor = link and link.prev or nil
	end

	-- Reverse in place (O(n) instead of O(n²) from table.insert(1))
	local half = math.floor(count / 2)
	for i = 1, half do
		local j = count - i + 1
		sequence[i], sequence[j] = sequence[j], sequence[i]
	end

	return sequence
end

local function addWalkNeighbors(neighbors, grid, currentPos, goalPos, currentCooldown, config)
	local nextCooldown = math.max(0, currentCooldown - 1)
	local currentCell = grid:Get(currentPos)
	local cx, cy, cz = currentPos.x, currentPos.y, currentPos.z
	local gx, gy, gz = goalPos.x, goalPos.y, goalPos.z

	for _, direction in ipairs(ORTHOGONAL_DIRECTIONS) do
		local d = direction.delta
		local nx, ny, nz = cx + d.x, cy + d.y, cz + d.z
		if grid:InBoundsXYZ(nx, ny, nz) then
			local isGoalCell = (nx == gx and ny == gy and nz == gz)
			local nextCell = grid:GetXYZ(nx, ny, nz)

			if isWalkableCell(nextCell, isGoalCell) and canWalkBetween(currentCell, nextCell, direction.name) then
				neighbors[#neighbors + 1] = {
					pos = { x = nx, y = ny, z = nz },
					stairCooldown = nextCooldown,
					key = nx .. "," .. ny .. "," .. nz .. "|" .. nextCooldown,
					cost = config.walkCost + traversalCost(nextCell, isGoalCell),
					action = {
						kind = "walk",
						direction = direction.name,
					},
				}
			end
		end
	end
end

local function addStairNeighbors(
	neighbors,
	grid,
	currentPos,
	goalPos,
	currentCooldown,
	config,
	reservedStairCells,
	stairOptions,
	stairCheckCache
)
	if currentCooldown > 0 then
		return
	end
	if not config.allowSameFloorStairDetours and currentPos.y == goalPos.y then
		return
	end

	local nextCooldown = config.minFlatStepsBetweenStairs
	local currentPosKey = currentPos.x .. "," .. currentPos.y .. "," .. currentPos.z
	local goalDy = goalPos.y - currentPos.y

	for _, direction in ipairs(ORTHOGONAL_DIRECTIONS) do
		for _, dy in ipairs(STAIR_DY) do
			if goalDy ~= 0 and ((goalDy > 0 and dy < 0) or (goalDy < 0 and dy > 0)) then
				continue
			end
			local checkKey = currentPosKey .. "|" .. direction.name .. "|" .. dy
			local cached = stairCheckCache[checkKey]
			local ok
			local transition
			if cached ~= nil then
				ok = cached.ok
				transition = cached.transition
			else
				ok, transition = StairPlanner.CanPlaceTransition(grid, currentPos, direction.name, dy, reservedStairCells, stairOptions)
				stairCheckCache[checkKey] = {
					ok = ok,
					transition = transition,
				}
			end

			if ok and transition then
				local landing = transition.landing
				local key = stateKey(landing, nextCooldown)
				local isGoalCell = DungeonTypes.Equals(landing, goalPos)
				local landingCell = grid:Get(landing)
				if isWalkableCell(landingCell, isGoalCell) then
					table.insert(neighbors, {
						pos = landing,
						stairCooldown = nextCooldown,
						key = key,
						cost = config.stairCost + traversalCost(landingCell, isGoalCell),
						action = {
							kind = "stair",
							direction = direction.name,
							dy = dy,
							transition = transition,
						},
					})
				end
			end
		end
	end
end

function HallwayCarver.FindPath(grid, startPos, goalPos, config, reservedStairCells, stairOptions, pathConfigOverride)
	local pathConfig = resolvePathConfig(config, pathConfigOverride)

	if not grid:InBounds(startPos) or not grid:InBounds(goalPos) then
		return nil
	end

	local open = BinaryHeap:new()
	local closed = {}
	local cameFrom = {}
	local gScore = {}
	local stateToPosition = {}
	local stateToCooldown = {}
	local stairCheckCache = {}

	local startStateKey = stateKey(startPos, 0)

	stateToPosition[startStateKey] = DungeonTypes.Copy(startPos)
	stateToCooldown[startStateKey] = 0
	gScore[startStateKey] = 0

	local insertionSerial = 0
	open:insert(startStateKey, heuristic(startPos, goalPos))

	-- Cache goal coordinates for inline equality checks
	local goalX, goalY, goalZ = goalPos.x, goalPos.y, goalPos.z

	local iterations = 0
	local visitedCount = 0
	local pathYieldInterval = numberFromConfig(pathConfig.pathYieldInterval, 500, 1)
	local maxVisitedStates = numberFromConfig(pathConfig.maxVisitedStates, 28000, 1)

	-- Reusable neighbor buffer to reduce GC pressure
	local neighbors = {}

	while not open:isEmpty() and iterations < pathConfig.maxPathIterations do
		iterations = iterations + 1
		if iterations % pathYieldInterval == 0 then
			task.wait()
		end

		local currentKey = open:pop()
		if closed[currentKey] then
			continue
		end
		closed[currentKey] = true
		visitedCount += 1
		if visitedCount > maxVisitedStates then
			return nil
		end

		local currentPos = stateToPosition[currentKey]
		if not currentPos then
			continue
		end

		-- Inline goal check (avoids function call overhead)
		if currentPos.x == goalX and currentPos.y == goalY and currentPos.z == goalZ then
			return reconstructPath(cameFrom, stateToPosition, currentKey)
		end

		local currentCooldown = stateToCooldown[currentKey] or 0
		table.clear(neighbors)
		addWalkNeighbors(neighbors, grid, currentPos, goalPos, currentCooldown, pathConfig)
		addStairNeighbors(
			neighbors,
			grid,
			currentPos,
			goalPos,
			currentCooldown,
			pathConfig,
			reservedStairCells,
			stairOptions,
			stairCheckCache
		)

		local currentG = gScore[currentKey]
		for _, neighbor in ipairs(neighbors) do
			local neighborKey = neighbor.key
			if not closed[neighborKey] then
				local tentative = currentG + neighbor.cost
				if tentative < (gScore[neighborKey] or math.huge) then
					gScore[neighborKey] = tentative
					cameFrom[neighborKey] = {
						prev = currentKey,
						action = neighbor.action,
					}
					stateToPosition[neighborKey] = neighbor.pos
					stateToCooldown[neighborKey] = neighbor.stairCooldown or 0
					insertionSerial = insertionSerial + 1
					local h = heuristic(neighbor.pos, goalPos)
					local tieBreaker = insertionSerial * 1e-7
					open:insert(neighborKey, tentative + h + tieBreaker)
				end
			end
		end
	end

	return nil
end

local function markHallwayIfNeeded(grid, pos)
	local cell = grid:Get(pos)
	if not cell then
		grid:Set(pos, SHARED_HALLWAY_CELL)
		return
	end

	local ct = cell.CellType
	if ct == CellType.Room or ct == CellType.Hallway or ct == CellType.Stairs then
		return
	end

	grid:Set(pos, SHARED_HALLWAY_CELL)
end

local function carvePerimeterHallways(grid, roomById, config)
	local width = numberFromConfig(config and config.buildingPerimeterHallwayWidth, 0, 0)
	if width <= 0 then
		return 0
	end

	local carved = 0
	local roomIds = {}
	for roomId in pairs(roomById or {}) do
		roomIds[#roomIds + 1] = roomId
	end
	table.sort(roomIds, function(a, b)
		local an = tonumber(a)
		local bn = tonumber(b)
		if an ~= nil and bn ~= nil and an ~= bn then
			return an < bn
		end
		return tostring(a) < tostring(b)
	end)

	local function carveIfEmpty(x, y, z)
		if not grid:InBoundsXYZ(x, y, z) then
			return
		end
		local pos = { x = x, y = y, z = z }
		local cell = grid:Get(pos)
		if cell and (cell.CellType == CellType.Room or cell.CellType == CellType.Stairs or cell.CellType == CellType.Hallway) then
			return
		end
		markHallwayIfNeeded(grid, pos)
		carved += 1
	end

	for _, roomId in ipairs(roomIds) do
		local room = roomById[roomId]
		if room then
			for y = room.min.y, room.max.y do
				for ring = 1, width do
					local minX = room.min.x - ring
					local maxX = room.max.x + ring
					local minZ = room.min.z - ring
					local maxZ = room.max.z + ring

					for x = minX, maxX do
						carveIfEmpty(x, y, minZ)
						carveIfEmpty(x, y, maxZ)
					end
					for z = minZ + 1, maxZ - 1 do
						carveIfEmpty(minX, y, z)
						carveIfEmpty(maxX, y, z)
					end
				end
			end
		end
	end

	return carved
end

local function uniquePush(resultList, seen, pos)
	local key = DungeonTypes.Key(pos)
	if not seen[key] then
		seen[key] = true
		table.insert(resultList, DungeonTypes.Copy(pos))
	end
end

local function copyCell(cell)
	if not cell then
		return nil
	end
	return {
		CellType = cell.CellType,
		CellSubtype = cell.CellSubtype,
		Direction = cell.Direction,
		RoomId = cell.RoomId,
	}
end

local function buildReservationOverlay(baseReserved, pendingReserved)
	if not baseReserved and not pendingReserved then
		return nil
	end

	local merged = {}
	if baseReserved then
		for key, value in pairs(baseReserved) do
			if value then
				merged[key] = true
			end
		end
	end
	if pendingReserved then
		for key, value in pairs(pendingReserved) do
			if value then
				merged[key] = true
			end
		end
	end
	return merged
end

local function markTransitionReserved(map, transition)
	map[DungeonTypes.Key(transition.bottom1)] = true
	map[DungeonTypes.Key(transition.bottom2)] = true
	map[DungeonTypes.Key(transition.air1)] = true
	map[DungeonTypes.Key(transition.air2)] = true
	map[DungeonTypes.Key(transition.landing)] = true
end

local function buildAttemptProfiles(config)
	local retryCount = numberFromConfig(config and config.hallwayCarveRetryCount, 3, 1)
	local strictMinFlat = numberFromConfig(config and config.minFlatStepsBetweenStairs, 2, 0)
	local retryMinFlat = numberFromConfig(config and config.retryMinFlatStepsBetweenStairs, math.max(0, strictMinFlat - 1), 0)
	local strictUseGlobal = boolFromConfig(config and config.useGlobalStairReservations, true)
	local finalUseGlobal = boolFromConfig(config and config.useGlobalStairReservationsOnLastRetry, false)

	local strictStairOptions = {
		allowHallwayDownStairs = boolFromConfig(config and config.allowHallwayDownStairs, false),
		enforceNearbyStairClearance = boolFromConfig(config and config.enforceNearbyStairClearance, true),
	}

	local relaxedStairOptions = {
		allowHallwayDownStairs = boolFromConfig(config and config.allowHallwayDownStairsOnRetry, true),
		enforceNearbyStairClearance = boolFromConfig(config and config.enforceNearbyStairClearanceOnRetry, false),
	}

	local profiles = {}
	for attempt = 1, retryCount do
		if attempt == 1 then
			table.insert(profiles, {
				name = "strict",
				useGlobalStairReservations = strictUseGlobal,
				stairOptions = strictStairOptions,
				pathConfigOverride = {
					minFlatStepsBetweenStairs = strictMinFlat,
				},
			})
		elseif attempt == retryCount then
			table.insert(profiles, {
				name = "relaxed",
				useGlobalStairReservations = finalUseGlobal,
				stairOptions = relaxedStairOptions,
				pathConfigOverride = {
					minFlatStepsBetweenStairs = 0,
				},
			})
		else
			table.insert(profiles, {
				name = "retry",
				useGlobalStairReservations = strictUseGlobal,
				stairOptions = relaxedStairOptions,
				pathConfigOverride = {
					minFlatStepsBetweenStairs = retryMinFlat,
				},
			})
		end
	end

	return profiles
end

local function getPairAttemptLimit(config, attemptIndex, profileCount, totalPairs)
	local baseLimit = numberFromConfig(config and config.maxEntrancePairAttempts, 16, 1)
	local retryLimit = numberFromConfig(config and config.maxEntrancePairAttemptsOnRetry, math.max(4, math.floor(baseLimit * 0.5)), 1)
	local relaxedLimit = numberFromConfig(config and config.maxEntrancePairAttemptsOnLastRetry, retryLimit, 1)

	local limit = baseLimit
	if attemptIndex == profileCount then
		limit = relaxedLimit
	elseif attemptIndex > 1 then
		limit = retryLimit
	end

	return math.min(limit, totalPairs)
end

local function carvePath(grid, pathSteps, baseReservedStairCells, stairOptions)
	local carvedCells = {}
	local seen = {}
	local snapshots = {}
	local pendingReserved = {}

	local function snapshot(pos)
		local key = DungeonTypes.Key(pos)
		if snapshots[key] == nil then
			snapshots[key] = {
				pos = DungeonTypes.Copy(pos),
				cell = copyCell(grid:Get(pos)),
			}
		end
	end

	local function rollback()
		for _, snapshotRecord in pairs(snapshots) do
			grid:Set(snapshotRecord.pos, snapshotRecord.cell)
		end
	end

	for index, step in ipairs(pathSteps) do
		if index > 1 and step.action then
			if step.action.kind == "walk" then
				snapshot(step.position)
				markHallwayIfNeeded(grid, step.position)
				uniquePush(carvedCells, seen, step.position)
			elseif step.action.kind == "stair" then
				local prevPos = pathSteps[index - 1].position
				local reservedOverlay = buildReservationOverlay(baseReservedStairCells, pendingReserved)
				local valid, preview = StairPlanner.CanPlaceTransition(
					grid,
					prevPos,
					step.action.direction,
					step.action.dy,
					reservedOverlay,
					stairOptions
				)
				if not valid or not preview then
					rollback()
					return nil, false, nil
				end

				snapshot(preview.bottom1)
				snapshot(preview.bottom2)
				snapshot(preview.air1)
				snapshot(preview.air2)
				snapshot(step.position)

				local applied, transition = StairPlanner.ApplyTransition(
					grid,
					prevPos,
					step.action.direction,
					step.action.dy,
					reservedOverlay,
					stairOptions
				)
				if not applied or not transition then
					rollback()
					return nil, false, nil
				end

				markTransitionReserved(pendingReserved, transition)
				uniquePush(carvedCells, seen, transition.bottom1)
				uniquePush(carvedCells, seen, transition.bottom2)
				uniquePush(carvedCells, seen, transition.air1)
				uniquePush(carvedCells, seen, transition.air2)

				markHallwayIfNeeded(grid, step.position)
				uniquePush(carvedCells, seen, step.position)
			end
		end
	end

	return carvedCells, true, pendingReserved
end

function HallwayCarver.Carve(grid, roomById, edges, config)
	local carvedPaths = {}
	local globalReservedStairCells = {}
	local attemptProfiles = buildAttemptProfiles(config)
	local stats = {
		edgesAttempted = 0,
		edgesSucceeded = 0,
		edgesFailed = 0,
		attemptProfileCount = #attemptProfiles,
		entrancePairsGenerated = 0,
		pathfindCalls = 0,
		pathfindSuccesses = 0,
		carveRollbackFailures = 0,
		perimeterCellsCarved = 0,
	}
	local sortedEdges = {}
	for _, edge in ipairs(edges) do
		table.insert(sortedEdges, edge)
	end
	table.sort(sortedEdges, pathSort)
	local edgeYieldInterval = numberFromConfig(config and config.edgeYieldInterval, 2, 1)
	stats.edgesAttempted = #sortedEdges

	for edgeIndex, edge in ipairs(sortedEdges) do
		if edgeIndex % edgeYieldInterval == 0 then
			task.wait()
		end
		local roomA = roomById[edge.roomAId]
		local roomB = roomById[edge.roomBId]
		if roomA and roomB then
			local entrancePairs = buildEntrancePairs(grid, roomA, roomB, config)
			stats.entrancePairsGenerated += #entrancePairs
			local successRecord = nil
			local lastSteps = {}
			local lastStart = roomA.center
			local lastGoal = roomB.center
			local lastStartOutside = roomA.center
			local lastGoalOutside = roomB.center

			for attemptIndex, profile in ipairs(attemptProfiles) do
				local reservationBase = profile.useGlobalStairReservations and globalReservedStairCells or nil
				local pairLimit = getPairAttemptLimit(config, attemptIndex, #attemptProfiles, #entrancePairs)
				for pairIndex = 1, pairLimit do
					local pair = entrancePairs[pairIndex]
					local startOutside = pair.start.outside
					local goalOutside = pair.goal.outside
					stats.pathfindCalls += 1
					local pathOutside = HallwayCarver.FindPath(
						grid,
						startOutside,
						goalOutside,
						config,
						reservationBase,
						profile.stairOptions,
						profile.pathConfigOverride
					)

					lastStart = pair.start.inside
					lastGoal = pair.goal.inside
					lastStartOutside = startOutside
					lastGoalOutside = goalOutside

					if pathOutside then
						stats.pathfindSuccesses += 1
						local steps = prependAppendRoomAnchors(pathOutside, pair.start, pair.goal)
						lastSteps = steps or {}
						local carvedCells, carvedOk, pendingReserved = carvePath(grid, steps, reservationBase, profile.stairOptions)
						if carvedOk and carvedCells then
							if pendingReserved then
								for key, value in pairs(pendingReserved) do
									if value then
										globalReservedStairCells[key] = true
									end
								end
							end

							successRecord = {
								roomAId = edge.roomAId,
								roomBId = edge.roomBId,
								success = true,
								start = pair.start.inside,
								goal = pair.goal.inside,
								startOutside = startOutside,
								goalOutside = goalOutside,
								startFace = pair.start.face,
								goalFace = pair.goal.face,
								steps = steps,
								cells = carvedCells,
								attempt = attemptIndex,
								profile = profile.name,
							}
							break
						else
							stats.carveRollbackFailures += 1
						end
					end
				end

				if successRecord then
					break
				end
			end

			if successRecord then
				table.insert(carvedPaths, successRecord)
				stats.edgesSucceeded += 1
			else
				table.insert(carvedPaths, {
					roomAId = edge.roomAId,
					roomBId = edge.roomBId,
					success = false,
					start = lastStart,
					goal = lastGoal,
					startOutside = lastStartOutside,
					goalOutside = lastGoalOutside,
					steps = lastSteps,
					cells = {},
					attempt = #attemptProfiles,
					profile = "failed",
				})
				stats.edgesFailed += 1
			end
		end
	end

	stats.perimeterCellsCarved = carvePerimeterHallways(grid, roomById, config)

	return carvedPaths, stats
end

return HallwayCarver

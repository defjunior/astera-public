--[[
	StairPlanner

	Plans multi-level staircase placement between dungeon floors.
	Validates landing clearance, detects floor transition cells, and
	ensures stairs connect properly across vertical layers without
	overlapping rooms or hallways.
]]

local DungeonTypes = require(script.Parent.DungeonTypes)
local CellType = DungeonTypes.CellType
local CellSubtype = DungeonTypes.CellSubtype

local StairPlanner = {}

local directionVectors = {
	North = { x = 0, y = 0, z = -1 },
	South = { x = 0, y = 0, z = 1 },
	East = { x = 1, y = 0, z = 0 },
	West = { x = -1, y = 0, z = 0 },
}

local oppositeDirection = {
	North = "South",
	South = "North",
	East = "West",
	West = "East",
}

local lateralOffsets = {
	{ x = 1, y = 0, z = 0 },
	{ x = -1, y = 0, z = 0 },
	{ x = 0, y = 0, z = 1 },
	{ x = 0, y = 0, z = -1 },
}

local function add(a, b)
	return {
		x = a.x + b.x,
		y = a.y + b.y,
		z = a.z + b.z,
	}
end

local function scale(vec, scalar)
	return {
		x = vec.x * scalar,
		y = vec.y * scalar,
		z = vec.z * scalar,
	}
end

local function isBlockedForBottom(cell)
	if not cell then
		return false
	end
	if cell.CellType == CellType.Stairs then
		return true
	end
	if cell.CellType == CellType.Room then
		return true
	end
	return false
end

local function isBlockedForAir(cell)
	if not cell then
		return false
	end
	if cell.CellType == CellType.Stairs and cell.CellSubtype == CellSubtype.StairAir then
		return false
	end
	return true
end

local function isBlockedForLanding(cell)
	if not cell then
		return false
	end
	-- Stair transitions must land onto flat walkable space (empty/hallway),
	-- not into an existing stair run.
	if cell.CellType == CellType.Stairs then
		return true
	end
	return false
end

function StairPlanner.GetTransitionCells(fromCell, direction, dy)
	local forward = directionVectors[direction]
	if not forward or (dy ~= 1 and dy ~= -1) then
		return nil
	end

	local lowerY
	local upperY
	local landingY
	if dy == 1 then
		lowerY = fromCell.y
		upperY = fromCell.y + 1
		landingY = upperY
	else
		lowerY = fromCell.y - 1
		upperY = fromCell.y
		landingY = lowerY
	end

	local forward1 = add(fromCell, scale(forward, 1))
	local forward2 = add(fromCell, scale(forward, 2))
	local forward3 = add(fromCell, scale(forward, 3))

	return {
		bottom1 = { x = forward1.x, y = lowerY, z = forward1.z },
		bottom2 = { x = forward2.x, y = lowerY, z = forward2.z },
		air1 = { x = forward1.x, y = upperY, z = forward1.z },
		air2 = { x = forward2.x, y = upperY, z = forward2.z },
		landing = { x = forward3.x, y = landingY, z = forward3.z },
		direction = direction,
		ascentDirection = (dy == 1) and direction or oppositeDirection[direction],
		dy = dy,
	}
end

local function hasReserved(reservedKeys, pos)
	if not reservedKeys then
		return false
	end
	return reservedKeys[DungeonTypes.Key(pos)] == true
end

local function normalizeOptions(options)
	return {
		allowHallwayDownStairs = (options and options.allowHallwayDownStairs) == true,
		enforceNearbyStairClearance = (options == nil) or (options.enforceNearbyStairClearance ~= false),
		enforceReservations = (options == nil) or (options.enforceReservations ~= false),
	}
end

local function isStairBottomCell(cell)
	return cell and cell.CellType == CellType.Stairs and (cell.CellSubtype == CellSubtype.StairBottom1 or cell.CellSubtype == CellSubtype.StairBottom2)
end

local function conflictsWithNearbyStairs(grid, pos, localTransitionKeys, reservedKeys)
	for _, offset in ipairs(lateralOffsets) do
		local neighborPos = add(pos, offset)
		local key = DungeonTypes.Key(neighborPos)
		if not localTransitionKeys[key] then
			if reservedKeys and reservedKeys[key] then
				return true
			end
			local neighborCell = grid:Get(neighborPos)
			if isStairBottomCell(neighborCell) then
				return true
			end
		end
	end
	return false
end

function StairPlanner.CanPlaceTransition(grid, fromCell, direction, dy, reservedKeys, options)
	local resolvedOptions = normalizeOptions(options)
	local transition = StairPlanner.GetTransitionCells(fromCell, direction, dy)
	if not transition then
		return false, nil
	end

	if not grid:InBounds(transition.bottom1)
		or not grid:InBounds(transition.bottom2)
		or not grid:InBounds(transition.air1)
		or not grid:InBounds(transition.air2)
		or not grid:InBounds(transition.landing)
	then
		return false, nil
	end

	local fromData = grid:Get(fromCell)
	if fromData and fromData.CellType == CellType.Stairs and fromData.CellSubtype == CellSubtype.StairAir then
		return false, nil
	end
	if fromData and fromData.CellType == CellType.Stairs and fromData.Direction and fromData.Direction ~= transition.ascentDirection then
		return false, nil
	end
	if fromData and fromData.CellType == CellType.Room then
		return false, nil
	end
	if dy == -1 and fromData and fromData.CellType == CellType.Hallway and not resolvedOptions.allowHallwayDownStairs then
		return false, nil
	end

	local bottom1 = grid:Get(transition.bottom1)
	local bottom2 = grid:Get(transition.bottom2)
	local air1 = grid:Get(transition.air1)
	local air2 = grid:Get(transition.air2)
	local landing = grid:Get(transition.landing)
	if landing and landing.CellType == CellType.Room then
		return false, nil
	end
	if landing and landing.CellType == CellType.Stairs and landing.Direction and landing.Direction ~= transition.ascentDirection then
		return false, nil
	end

	if isBlockedForBottom(bottom1) or isBlockedForBottom(bottom2) then
		return false, nil
	end

	if isBlockedForAir(air1) or isBlockedForAir(air2) then
		return false, nil
	end

	if isBlockedForLanding(landing) then
		return false, nil
	end

	if resolvedOptions.enforceReservations then
		if hasReserved(reservedKeys, transition.bottom1)
			or hasReserved(reservedKeys, transition.bottom2)
			or hasReserved(reservedKeys, transition.air1)
			or hasReserved(reservedKeys, transition.air2)
			or hasReserved(reservedKeys, transition.landing)
		then
			return false, nil
		end
	end

	local localTransitionKeys = {
		[DungeonTypes.Key(transition.bottom1)] = true,
		[DungeonTypes.Key(transition.bottom2)] = true,
		[DungeonTypes.Key(transition.air1)] = true,
		[DungeonTypes.Key(transition.air2)] = true,
		[DungeonTypes.Key(transition.landing)] = true,
	}

	if resolvedOptions.enforceNearbyStairClearance then
		if conflictsWithNearbyStairs(grid, transition.bottom1, localTransitionKeys, reservedKeys)
			or conflictsWithNearbyStairs(grid, transition.bottom2, localTransitionKeys, reservedKeys)
			or conflictsWithNearbyStairs(grid, transition.landing, localTransitionKeys, reservedKeys)
		then
			return false, nil
		end
	end

	return true, transition
end

local function setStairCell(grid, pos, subtype, direction)
	local existing = grid:Get(pos)
	if existing and existing.CellType == CellType.Stairs then
		return false
	end
	grid:Set(pos, DungeonTypes.MakeCell(CellType.Stairs, subtype, direction, nil))
	return true
end

function StairPlanner.ApplyTransition(grid, fromCell, direction, dy, reservedKeys, options)
	local ok, transition = StairPlanner.CanPlaceTransition(grid, fromCell, direction, dy, reservedKeys, options)
	if not ok then
		return false, nil
	end

	-- Keep subtype ordering consistent with ascent direction so rendered stairs remain traversable.
	local placements
	if dy == 1 then
		placements = {
			{ pos = transition.bottom1, subtype = CellSubtype.StairBottom1 },
			{ pos = transition.bottom2, subtype = CellSubtype.StairBottom2 },
			{ pos = transition.air1, subtype = CellSubtype.StairAir },
			{ pos = transition.air2, subtype = CellSubtype.StairAir },
		}
	else
		placements = {
			{ pos = transition.bottom1, subtype = CellSubtype.StairBottom2 },
			{ pos = transition.bottom2, subtype = CellSubtype.StairBottom1 },
			{ pos = transition.air1, subtype = CellSubtype.StairAir },
			{ pos = transition.air2, subtype = CellSubtype.StairAir },
		}
	end

	for _, placement in ipairs(placements) do
		if not setStairCell(grid, placement.pos, placement.subtype, transition.ascentDirection) then
			return false, nil
		end
	end

	return true, transition
end

--[[
	ValidateAllTransitions

	Scans every stair cell in the grid and validates that each StairBottom1 /
	StairBottom2 pair forms a properly connected, traversable transition.

	Checks performed per pair:
		1. Direction consistency  – both halves share the same Direction.
		2. Spatial ordering       – StairBottom2 is exactly one step in the
		                            ascent Direction from StairBottom1.
		3. Air cell alignment     – StairAir cells exist one Y-level above
		                            each bottom cell with matching Direction.
		4. Orphan detection       – StairBottom2 cells that have no matching
		                            StairBottom1 behind them.

	Returns a table:
		{
			valid   = true/false,
			issues  = { { kind, position, message, ... }, ... },
			repaired = number,  -- cells corrected when autoRepair is true
		}
]]
function StairPlanner.ValidateAllTransitions(grid, autoRepair)
	local issues = {}
	local repaired = 0

	-- Collect every stair cell.
	local stairCells = {}
	grid:ForEachOccupied(function(pos, cell)
		if cell.CellType == CellType.Stairs then
			stairCells[DungeonTypes.Key(pos)] = {
				pos = DungeonTypes.Copy(pos),
				cell = cell,
			}
		end
	end)

	-- Determine which direction vector connects two adjacent positions.
	local function inferDirection(from, to)
		local dx = to.x - from.x
		local dz = to.z - from.z
		if dx == 1 and dz == 0 then return "East" end
		if dx == -1 and dz == 0 then return "West" end
		if dx == 0 and dz == 1 then return "South" end
		if dx == 0 and dz == -1 then return "North" end
		return nil
	end

	local visited = {}

	-- ── Pass 1: validate every StairBottom1 and its expected partner ──
	for key, entry in pairs(stairCells) do
		if visited[key] then continue end
		local cell = entry.cell
		local pos  = entry.pos

		if cell.CellSubtype ~= CellSubtype.StairBottom1 then
			continue
		end
		visited[key] = true

		-- 1a. Direction must exist
		local dir = cell.Direction
		if not dir or not directionVectors[dir] then
			issues[#issues + 1] = {
				kind     = "missing_direction",
				position = pos,
				message  = "StairBottom1 at " .. key .. " has no valid Direction",
			}
			continue
		end

		local forward = directionVectors[dir]

		-- 1b. StairBottom2 should be one step in Direction from StairBottom1
		local pairPos = add(pos, forward)
		local pairKey = DungeonTypes.Key(pairPos)
		local pairEntry = stairCells[pairKey]

		if not pairEntry or pairEntry.cell.CellSubtype ~= CellSubtype.StairBottom2 then
			issues[#issues + 1] = {
				kind           = "missing_pair",
				position       = pos,
				expectedPairAt = pairPos,
				direction      = dir,
				message        = "StairBottom1 at " .. key
					.. " has no StairBottom2 at " .. pairKey,
			}
			continue
		end

		visited[pairKey] = true
		local pairCell = pairEntry.cell

		-- 2. Direction consistency
		if pairCell.Direction ~= dir then
			issues[#issues + 1] = {
				kind             = "direction_mismatch",
				position         = pos,
				pairPosition     = pairPos,
				bottom1Direction = dir,
				bottom2Direction = pairCell.Direction,
				message          = "Direction mismatch at "
					.. key .. "(" .. dir .. ") vs "
					.. pairKey .. "(" .. tostring(pairCell.Direction) .. ")",
			}
			if autoRepair then
				grid:Set(pairPos, DungeonTypes.MakeCell(
					CellType.Stairs,
					CellSubtype.StairBottom2,
					dir,
					nil
				))
				repaired += 1
			end
		end

		-- 3. Air cells one Y-level above the bottom cells
		local airPositions = {
			{ pos = { x = pos.x,     y = pos.y + 1, z = pos.z },     label = "StairBottom1" },
			{ pos = { x = pairPos.x, y = pairPos.y + 1, z = pairPos.z }, label = "StairBottom2" },
		}
		for _, airInfo in ipairs(airPositions) do
			local airPos = airInfo.pos
			local airKey = DungeonTypes.Key(airPos)
			if not grid:InBounds(airPos) then
				continue
			end
			local airCell = grid:Get(airPos)
			if not airCell or airCell.CellType ~= CellType.Stairs
				or airCell.CellSubtype ~= CellSubtype.StairAir then
				issues[#issues + 1] = {
					kind           = "missing_air_cell",
					position       = airPos,
					bottomPosition = airInfo.label == "StairBottom1" and pos or pairPos,
					message        = "Missing StairAir above " .. airInfo.label
						.. " at " .. airKey,
				}
			elseif airCell.Direction ~= dir then
				issues[#issues + 1] = {
					kind              = "air_direction_mismatch",
					position          = airPos,
					expectedDirection = dir,
					actualDirection   = airCell.Direction,
					message           = "StairAir direction mismatch at "
						.. airKey .. " (expected " .. dir
						.. ", got " .. tostring(airCell.Direction) .. ")",
				}
				if autoRepair then
					grid:Set(airPos, DungeonTypes.MakeCell(
						CellType.Stairs,
						CellSubtype.StairAir,
						dir,
						nil
					))
					repaired += 1
				end
			end
		end
	end

	-- ── Pass 2: detect orphan StairBottom2 cells not reached by pass 1 ──
	for key, entry in pairs(stairCells) do
		if visited[key] then continue end
		local cell = entry.cell
		local pos  = entry.pos

		if cell.CellSubtype ~= CellSubtype.StairBottom2 then
			continue
		end

		local dir = cell.Direction
		if not dir or not directionVectors[dir] then
			issues[#issues + 1] = {
				kind     = "orphan_bottom2",
				position = pos,
				message  = "Orphan StairBottom2 at " .. key .. " with no valid Direction",
			}
			continue
		end

		-- The matching StairBottom1 should be one step BEHIND (opposite dir).
		local behind = directionVectors[oppositeDirection[dir]]
		local ownerPos = add(pos, behind)
		local ownerKey = DungeonTypes.Key(ownerPos)
		local ownerEntry = stairCells[ownerKey]

		if not ownerEntry
			or ownerEntry.cell.CellSubtype ~= CellSubtype.StairBottom1
			or ownerEntry.cell.Direction ~= dir then
			-- Attempt to infer the correct direction from any adjacent StairBottom1.
			local inferredDir = nil
			for candidateDir, vec in pairs(directionVectors) do
				local behindCandidate = directionVectors[oppositeDirection[candidateDir]]
				local candidateOwner = add(pos, behindCandidate)
				local candidateKey = DungeonTypes.Key(candidateOwner)
				local candidateEntry = stairCells[candidateKey]
				if candidateEntry
					and candidateEntry.cell.CellSubtype == CellSubtype.StairBottom1 then
					inferredDir = inferDirection(candidateOwner, pos)
					break
				end
			end

			issues[#issues + 1] = {
				kind        = "orphan_bottom2",
				position    = pos,
				direction   = dir,
				inferredFix = inferredDir,
				message     = "Orphan StairBottom2 at " .. key
					.. " (Direction=" .. dir
					.. ") has no matching StairBottom1 behind it",
			}

			if autoRepair and inferredDir and directionVectors[inferredDir] then
				grid:Set(pos, DungeonTypes.MakeCell(
					CellType.Stairs,
					CellSubtype.StairBottom2,
					inferredDir,
					nil
				))
				repaired += 1
			end
		end
	end

	return {
		valid    = #issues == 0,
		issues   = issues,
		repaired = repaired,
	}
end

return StairPlanner

local DungeonRoofModule = {}

local function shallowCopy(source)
	local out = {}
	for key, value in pairs(source or {}) do
		out[key] = value
	end
	return out
end

local function cellKey(pos)
	return string.format("%d,%d,%d", pos.x, pos.y, pos.z)
end

local function weightedPick(rng, weights)
	local total = 0
	for _, weight in pairs(weights or {}) do
		total += math.max(0, tonumber(weight) or 0)
	end
	if total <= 0 then
		return "flat"
	end
	local roll = rng:NextNumber(0, total)
	local cursor = 0
	local keys = {}
	for key in pairs(weights or {}) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		cursor += math.max(0, tonumber(weights[key]) or 0)
		if roll <= cursor then
			return key
		end
	end
	return keys[#keys] or "flat"
end

local function roofTileIdFromKind(kind)
	if kind == "ribbed" then
		return "roof_ribbed"
	elseif kind == "beam" then
		return "roof_beam_supported"
	elseif kind == "collapsed" then
		return "roof_collapsed"
	end
	return "roof_flat"
end

local function buildContextByRoomId(options)
	local out = {}
	local decorData = options.decorData
	if type(decorData) ~= "table" or type(decorData.results) ~= "table" then
		return out
	end
	for _, entry in ipairs(decorData.results) do
		local profile = entry.profile or {}
		local roomId = tonumber(profile.roomId) or profile.roomId
		local roomContext = entry.roomContext
		if roomId ~= nil and type(roomContext) == "table" then
			out[roomId] = roomContext
		end
	end
	return out
end

local function buildRoofBlockedByTallDecor(options)
	local blocked = {}
	local decorData = options.decorData
	local yieldInterval = math.max(50, math.floor(tonumber(options.yieldInterval) or 300))
	local processed = 0
	if type(decorData) ~= "table" or type(decorData.results) ~= "table" then
		return blocked, processed
	end

	local function placementBlocksRoof(placement)
		if type(placement) ~= "table" then
			return false
		end
		if placement.blocksRoof == true then
			return true
		end
		local role = tostring(placement.role or "")
		if role == "structural_pillar" or role == "structural_tall_support" then
			return true
		end
		for _, tag in ipairs(placement.tags or {}) do
			if tag == "roof_blocker" or tag == "blocks_roof" then
				return true
			end
		end
		return false
	end

	for _, entry in ipairs(decorData.results) do
		local blueprint = entry.blueprint
		if type(blueprint) == "table" and type(blueprint.placements) == "table" then
			for _, placement in ipairs(blueprint.placements) do
				processed += 1
				if processed % yieldInterval == 0 then
					task.wait()
				end
				local isTall = placementBlocksRoof(placement)
				if isTall and placement.gridPos then
					local roofPos = {
						x = placement.gridPos.x,
						y = placement.gridPos.y + 1,
						z = placement.gridPos.z,
					}
					blocked[cellKey(roofPos)] = true
				end
			end
		end
	end
	return blocked, processed
end

local function buildCellByPosition(cellsData)
	local byPosition = {}
	for _, cell in ipairs(cellsData or {}) do
		if type(cell) == "table" and type(cell.Position) == "table" then
			byPosition[cellKey(cell.Position)] = cell
		end
	end
	return byPosition
end

local function canUseCollapsedRoof(cell, cellByPosition, wallsData)
	local pos = cell and cell.Position
	if type(pos) ~= "table" then
		return false
	end
	if tostring(cell.CellType or "") ~= "Room" then
		return false
	end
	if cell.RoomId == nil then
		return false
	end

	-- Partial roof openings should only exist when there is a real upper room
	-- cell that can plausibly drop into this room.
	local abovePos = { x = pos.x, y = pos.y + 1, z = pos.z }
	local aboveCell = cellByPosition[cellKey(abovePos)]
	if type(aboveCell) ~= "table" then
		return false
	end
	local aboveType = tostring(aboveCell.CellType or "")
	if aboveType ~= "Room" then
		return false
	end
	if aboveCell.RoomId == nil then
		return false
	end

	-- If wall topology is available, require an open vertical connection.
	if type(wallsData) == "table" then
		local walls = wallsData[cellKey(pos)]
		local aboveWalls = wallsData[cellKey(abovePos)]
		if type(walls) ~= "table" or walls.Top ~= false then
			return false
		end
		if type(aboveWalls) ~= "table" or aboveWalls.Bottom ~= false then
			return false
		end
	end

	return true
end

function DungeonRoofModule.BuildRoofPlan(options)
	options = options or {}
	local rng = options.rng or Random.new(tonumber(options.seed) or 1)
	local cellsData = options.cellsData or {}
	local wallsData = options.wallsData
	local cellByPosition = buildCellByPosition(cellsData)
	local yieldInterval = math.max(50, math.floor(tonumber(options.yieldInterval) or 300))
	local roomContextByRoomId = buildContextByRoomId(options)
	-- Full coverage mode: roof plan does not exclude cells due to tall decor.
	local blockedScanProcessed = 0
	local blockedCount = 0

	local roofPlacements = {}
	local seen = {}
	local scannedCells = 0
	local eligibleCells = 0
	local collapsedSkipped = 0

	for _, cell in ipairs(cellsData) do
		scannedCells += 1
		if scannedCells % yieldInterval == 0 then
			task.wait()
		end
		local pos = cell.Position
		local cellType = cell.CellType
		local roofEligible = (cellType == "Room")
			or (cellType == "Hallway")
		if not roofEligible then
			continue
		end

		local roofPos = {
			x = pos.x,
			y = pos.y + 1,
			z = pos.z,
		}
		local k = cellKey(roofPos)
		if seen[k] then
			continue
		end
		local aboveCell = cellByPosition[k]
		if aboveCell and tostring(aboveCell.CellType or "") == "Stairs" then
			continue
		end
		seen[k] = true

		local roomContext = roomContextByRoomId[cell.RoomId] or {}
		local roofProfile = shallowCopy(roomContext.roofProfile or {})
		if next(roofProfile) == nil then
			if cellType == "Hallway" then
				roofProfile = { flat = 0.2, ribbed = 0.56, beam = 0.18, collapsed = 0.06 }
			else
				roofProfile = { flat = 0.55, ribbed = 0.2, beam = 0.15, collapsed = 0.1 }
			end
		end

		eligibleCells += 1

		local kind = weightedPick(rng, roofProfile)
		if kind == "collapsed" and not canUseCollapsedRoof(cell, cellByPosition, wallsData) then
			collapsedSkipped += 1
			kind = "flat"
		end
		roofPlacements[#roofPlacements + 1] = {
			gridPos = roofPos,
			tileId = roofTileIdFromKind(kind),
			roofKind = kind,
			orientation = (cell.Direction or "North"),
			roomId = cell.RoomId,
			cellType = cellType,
		}
	end

	return {
		placements = roofPlacements,
		count = #roofPlacements,
		stats = {
			scannedCells = scannedCells,
			eligibleCells = eligibleCells,
			blockedByTallDecor = blockedCount,
			collapsedSkipped = collapsedSkipped,
			blockedScanProcessed = blockedScanProcessed,
		},
	}
end

return DungeonRoofModule

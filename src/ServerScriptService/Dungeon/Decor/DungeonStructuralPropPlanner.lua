local WFCTypes = require(script.Parent.Parent.WFC.WFCTypes)

local DungeonStructuralPropPlanner = {}

local WALL_NORTH = "North"
local WALL_SOUTH = "South"
local WALL_EAST = "East"
local WALL_WEST = "West"

local function clamp(v, minV, maxV)
	if v < minV then
		return minV
	end
	if v > maxV then
		return maxV
	end
	return v
end

local function asNumber(v, fallback)
	local n = tonumber(v)
	if n == nil then
		return fallback
	end
	return n
end

local function key2(x, z)
	return WFCTypes.Key2D(x, z)
end

local function sortAnchors(anchors)
	table.sort(anchors, function(a, b)
		if a.priority ~= b.priority then
			return a.priority > b.priority
		end
		if a.z ~= b.z then
			return a.z < b.z
		end
		if a.x ~= b.x then
			return a.x < b.x
		end
		return tostring(a.kind or "") < tostring(b.kind or "")
	end)
end

local function normalizeSubgridScale(profile)
	return math.max(1, math.floor(asNumber(profile and profile.subgridScale, 1)))
end

local function normalizeRoomCells(profile, subgridScale)
	local widthSubcells = math.max(1, math.floor(asNumber(profile and profile.dimensions and profile.dimensions.x, 1)))
	local depthSubcells = math.max(1, math.floor(asNumber(profile and profile.dimensions and profile.dimensions.z, 1)))
	local widthCells = math.max(1, math.floor(widthSubcells / subgridScale))
	local depthCells = math.max(1, math.floor(depthSubcells / subgridScale))
	return widthSubcells, depthSubcells, widthCells, depthCells
end

local function roomCellCenterToLocal(index, subgridScale, maxSubcells)
	local startSubcell = ((index - 1) * subgridScale) + 1
	local center = startSubcell + math.floor((subgridScale - 1) * 0.5)
	return clamp(center, 1, maxSubcells)
end

local function entranceToWallCellIndex(entrance, subgridScale)
	local dir = entrance and entrance.dir
	if dir == WALL_NORTH or dir == WALL_SOUTH then
		return math.max(1, math.ceil(asNumber(entrance.x, 1) / subgridScale))
	elseif dir == WALL_EAST or dir == WALL_WEST then
		return math.max(1, math.ceil(asNumber(entrance.z, 1) / subgridScale))
	end
	return nil
end

local function addBlockedRange(blocked, minIdx, maxIdx, fromIdx, toIdx)
	for idx = fromIdx, toIdx do
		if idx >= minIdx and idx <= maxIdx then
			blocked[idx] = true
		end
	end
end

local function buildDoorBlockedByWall(profile, subgridScale, doorClearanceCells, widthCells, depthCells)
	local blocked = {
		[WALL_NORTH] = {},
		[WALL_SOUTH] = {},
		[WALL_EAST] = {},
		[WALL_WEST] = {},
	}
	local clearRadius = math.max(0, math.floor(asNumber(doorClearanceCells, 0)))
	for _, entrance in ipairs(profile.entrances or {}) do
		local wall = entrance.dir
		local idx = entranceToWallCellIndex(entrance, subgridScale)
		if idx and blocked[wall] then
			local minIdx = (wall == WALL_NORTH or wall == WALL_SOUTH) and 1 or 1
			local maxIdx = (wall == WALL_NORTH or wall == WALL_SOUTH) and widthCells or depthCells
			addBlockedRange(blocked[wall], minIdx, maxIdx, idx - clearRadius, idx + clearRadius)
		end
	end
	return blocked
end

local function countBlockedCellsByWall(blockedByWall)
	local counts = {
		[WALL_NORTH] = 0,
		[WALL_SOUTH] = 0,
		[WALL_EAST] = 0,
		[WALL_WEST] = 0,
	}
	for wall, blocked in pairs(blockedByWall or {}) do
		local total = 0
		for _, value in pairs(blocked or {}) do
			if value == true then
				total += 1
			end
		end
		counts[wall] = total
	end
	return counts
end

local function buildWallSegments(lengthCells, blocked)
	local segments = {}
	local idx = 1
	while idx <= lengthCells do
		if blocked[idx] then
			idx += 1
		else
			local startIdx = idx
			while idx <= lengthCells and not blocked[idx] do
				idx += 1
			end
			local endIdx = idx - 1
			segments[#segments + 1] = {
				startIdx = startIdx,
				endIdx = endIdx,
				length = endIdx - startIdx + 1,
			}
		end
	end
	return segments
end

local function isNearMask(mask, x, z, radius)
	if type(mask) ~= "table" then
		return false
	end
	local r = math.max(0, math.floor(asNumber(radius, 0)))
	for ox = -r, r do
		for oz = -r, r do
			local k = key2(x + ox, z + oz)
			if mask[k] == true then
				return true
			end
		end
	end
	return false
end

local function buildAnchorCollector(widthSubcells, depthSubcells)
	local list = {}
	local seen = {}
	local function push(kind, x, z, reason, priority, wall, meta)
		local cx = clamp(math.floor(x), 1, widthSubcells)
		local cz = clamp(math.floor(z), 1, depthSubcells)
		local k = string.format("%s:%d,%d", tostring(kind), cx, cz)
		if seen[k] then
			return false
		end
		seen[k] = true
		local anchor = {
			kind = kind,
			x = cx,
			z = cz,
			reason = reason,
			priority = priority or 0,
			wall = wall,
		}
		if type(meta) == "table" then
			for key, value in pairs(meta) do
				anchor[key] = value
			end
		end
		list[#list + 1] = anchor
		return true
	end
	return list, push
end

local function applyPerimeterSupportPattern(
	pushAnchor,
	widthSubcells,
	depthSubcells,
	widthCells,
	depthCells,
	subgridScale,
	doorBlockedByWall,
	rules
)
	if not (rules and rules.Enabled == true) then
		return
	end
	local minPerimeter = math.max(0, math.floor(asNumber(rules.MinRoomPerimeterCells, 0)))
	local perimeter = (widthCells * 2) + (depthCells * 2)
	if perimeter < minPerimeter then
		return
	end
	local interval = math.max(1, math.floor(asNumber(rules.IntervalCells, 3)))
	local startOffset = math.max(0, math.floor(asNumber(rules.StartOffsetCells, 1)))
	local minSpan = math.max(1, math.floor(asNumber(rules.MinSpanCells, 1)))
	local wallInset = math.max(0, math.floor(asNumber(rules.WallInsetSubcells, 1)))

	local function emitWallSupports(wall, lengthCells, constantSubcell, isXAxis)
		local segments = buildWallSegments(lengthCells, doorBlockedByWall[wall] or {})
		for _, segment in ipairs(segments) do
			if segment.length >= minSpan then
				local idx = segment.startIdx + startOffset
				if idx > segment.endIdx then
					idx = segment.startIdx
				end
				while idx <= segment.endIdx do
					local variableSubcell
					if isXAxis then
						variableSubcell = roomCellCenterToLocal(idx, subgridScale, widthSubcells)
						pushAnchor(
							"pillar",
							variableSubcell,
							constantSubcell,
							"perimeter_interval",
							65,
							wall
						)
					else
						variableSubcell = roomCellCenterToLocal(idx, subgridScale, depthSubcells)
						pushAnchor(
							"pillar",
							constantSubcell,
							variableSubcell,
							"perimeter_interval",
							65,
							wall
						)
					end
					idx += interval
				end
			end
		end
	end

	emitWallSupports(WALL_NORTH, widthCells, clamp(1 + wallInset, 1, depthSubcells), true)
	emitWallSupports(WALL_SOUTH, widthCells, clamp(depthSubcells - wallInset, 1, depthSubcells), true)
	emitWallSupports(WALL_WEST, depthCells, clamp(1 + wallInset, 1, widthSubcells), false)
	emitWallSupports(WALL_EAST, depthCells, clamp(widthSubcells - wallInset, 1, widthSubcells), false)
end

local function applyCornerSupportPattern(pushAnchor, widthSubcells, depthSubcells, widthCells, depthCells, rules)
	if not (rules and rules.Enabled == true) then
		return
	end
	local minCellsX = math.max(1, math.floor(asNumber(rules.MinRoomCellsX, 1)))
	local minCellsZ = math.max(1, math.floor(asNumber(rules.MinRoomCellsZ, 1)))
	if widthCells < minCellsX or depthCells < minCellsZ then
		return
	end
	local inset = math.max(0, math.floor(asNumber(rules.InsetSubcells, 1)))
	local minX = clamp(1 + inset, 1, widthSubcells)
	local maxX = clamp(widthSubcells - inset, 1, widthSubcells)
	local minZ = clamp(1 + inset, 1, depthSubcells)
	local maxZ = clamp(depthSubcells - inset, 1, depthSubcells)
	pushAnchor("pillar", minX, minZ, "corner_support", 90, "corner")
	pushAnchor("pillar", maxX, minZ, "corner_support", 90, "corner")
	pushAnchor("pillar", minX, maxZ, "corner_support", 90, "corner")
	pushAnchor("pillar", maxX, maxZ, "corner_support", 90, "corner")
end

local function applyCenterlinePattern(pushAnchor, widthSubcells, depthSubcells, widthCells, depthCells, subgridScale, rules)
	if not (rules and rules.Enabled == true) then
		return
	end
	local areaCells = widthCells * depthCells
	local minArea = math.max(1, math.floor(asNumber(rules.MinAreaCells, 1)))
	local minLongEdge = math.max(1, math.floor(asNumber(rules.MinLongEdgeCells, 1)))
	if areaCells < minArea or math.max(widthCells, depthCells) < minLongEdge then
		return
	end

	local interval = math.max(1, math.floor(asNumber(rules.IntervalCells, 3)))
	local maxLines = math.max(1, math.floor(asNumber(rules.MaxLines, 1)))
	local alongX = widthCells >= depthCells
	local baseCrossCount = alongX and depthCells or widthCells
	local crossLineCount = math.min(maxLines, baseCrossCount >= 10 and 2 or 1)

	local crossIndices = {}
	if crossLineCount == 1 then
		crossIndices[1] = math.floor((baseCrossCount + 1) * 0.5)
	else
		local left = math.floor((baseCrossCount + 1) * 0.35)
		local right = math.floor((baseCrossCount + 1) * 0.65)
		crossIndices[1] = clamp(left, 1, baseCrossCount)
		crossIndices[2] = clamp(right, 1, baseCrossCount)
	end

	if alongX then
		for _, crossZ in ipairs(crossIndices) do
			for idx = 1, widthCells, interval do
				pushAnchor(
					"pillar",
					roomCellCenterToLocal(idx, subgridScale, widthSubcells),
					roomCellCenterToLocal(crossZ, subgridScale, depthSubcells),
					"centerline_support",
					70,
					"centerline_x"
				)
			end
		end
	else
		for _, crossX in ipairs(crossIndices) do
			for idx = 1, depthCells, interval do
				pushAnchor(
					"pillar",
					roomCellCenterToLocal(crossX, subgridScale, widthSubcells),
					roomCellCenterToLocal(idx, subgridScale, depthSubcells),
					"centerline_support",
					70,
					"centerline_z"
				)
			end
		end
	end
end

local function applyArchetypePatterns(
	pushAnchor,
	widthSubcells,
	depthSubcells,
	widthCells,
	depthCells,
	subgridScale,
	archetypeId,
	rules
)
	local patternsByArchetype = rules and rules.ArchetypePatterns
	if type(patternsByArchetype) ~= "table" then
		return
	end
	local patterns = patternsByArchetype[tostring(archetypeId)]
	if type(patterns) ~= "table" then
		return
	end
	local areaCells = widthCells * depthCells
	for _, pattern in ipairs(patterns) do
		if type(pattern) ~= "table" then
			continue
		end
		local minArea = math.max(0, math.floor(asNumber(pattern.minAreaCells, 0)))
		if areaCells < minArea then
			continue
		end

		local patternType = tostring(pattern.type or "")
		if patternType == "normalized_points" and type(pattern.points) == "table" then
			for _, point in ipairs(pattern.points) do
				local px = clamp(asNumber(point and point.x, 0.5), 0, 1)
				local pz = clamp(asNumber(point and point.z, 0.5), 0, 1)
				local x = clamp(math.floor((widthSubcells - 1) * px + 1.5), 1, widthSubcells)
				local z = clamp(math.floor((depthSubcells - 1) * pz + 1.5), 1, depthSubcells)
				pushAnchor("pillar", x, z, "archetype_pattern", 75, "pattern")
			end
		elseif patternType == "centerline_cross" then
			local interval = math.max(1, math.floor(asNumber(pattern.intervalCells, 2)))
			local cx = math.floor((widthCells + 1) * 0.5)
			local cz = math.floor((depthCells + 1) * 0.5)
			for xCell = 1, widthCells, interval do
				pushAnchor(
					"pillar",
					roomCellCenterToLocal(xCell, subgridScale, widthSubcells),
					roomCellCenterToLocal(cz, subgridScale, depthSubcells),
					"archetype_pattern",
					75,
					"pattern_cross"
				)
			end
			for zCell = 1, depthCells, interval do
				pushAnchor(
					"pillar",
					roomCellCenterToLocal(cx, subgridScale, widthSubcells),
					roomCellCenterToLocal(zCell, subgridScale, depthSubcells),
					"archetype_pattern",
					75,
					"pattern_cross"
				)
			end
		end
	end
end

local function isWallCell(state, x, z)
	local surfaces = state and state.surfaces
	local walls = surfaces and surfaces.wall
	if type(walls) ~= "table" then
		return false
	end
	return walls[key2(x, z)] == true
end

local function collectWallAnchorCandidates(
	profile,
	state,
	subgridScale,
	widthSubcells,
	depthSubcells,
	widthCells,
	depthCells,
	doorBlockedByWall,
	rules,
	pushAnchor
)
	if not (rules and rules.Enabled == true) then
		return
	end
	local interval = math.max(1, math.floor(asNumber(rules.IntervalCells, 2)))
	local minSpan = math.max(1, math.floor(asNumber(rules.MinSpanCells, 2)))

	local function emitWall(wall, lengthCells, isXAxis, constantSubcell)
		local segments = buildWallSegments(lengthCells, doorBlockedByWall[wall] or {})
		for _, segment in ipairs(segments) do
			if segment.length >= minSpan then
				for idx = segment.startIdx, segment.endIdx, interval do
					if isXAxis then
						local x = roomCellCenterToLocal(idx, subgridScale, widthSubcells)
						local z = constantSubcell
						if isWallCell(state, x, z) then
							pushAnchor("wall_prop", x, z, "wall_span_interval", 55, wall)
						end
					else
						local x = constantSubcell
						local z = roomCellCenterToLocal(idx, subgridScale, depthSubcells)
						if isWallCell(state, x, z) then
							pushAnchor("wall_prop", x, z, "wall_span_interval", 55, wall)
						end
					end
				end
			end
		end
	end

	emitWall(WALL_NORTH, widthCells, true, 1)
	emitWall(WALL_SOUTH, widthCells, true, depthSubcells)
	emitWall(WALL_WEST, depthCells, false, 1)
	emitWall(WALL_EAST, depthCells, false, widthSubcells)
end

local function normalizePillarReservationSubcells(pillarRules, subgridScale)
	local reserve = math.max(1, math.floor(asNumber(pillarRules and pillarRules.CellReservationSubcells, 4)))
	local maxReserve = math.max(1, math.floor(asNumber(pillarRules and pillarRules.MaxReservationSubcells, subgridScale)))
	return clamp(reserve, 1, maxReserve)
end

local function buildPillarSupportGridContext(widthSubcells, depthSubcells, pillarRules, subgridScale)
	local reserveSize = normalizePillarReservationSubcells(pillarRules, subgridScale)
	local cols = math.max(1, math.floor(widthSubcells / reserveSize))
	local rows = math.max(1, math.floor(depthSubcells / reserveSize))
	local usedWidth = cols * reserveSize
	local usedDepth = rows * reserveSize
	local offsetX = math.max(0, math.floor((widthSubcells - usedWidth) * 0.5))
	local offsetZ = math.max(0, math.floor((depthSubcells - usedDepth) * 0.5))
	return {
		reserveSize = reserveSize,
		cols = cols,
		rows = rows,
		offsetX = offsetX,
		offsetZ = offsetZ,
		widthSubcells = widthSubcells,
		depthSubcells = depthSubcells,
		subgridScale = subgridScale,
		roomWidthCells = math.max(1, math.floor(widthSubcells / math.max(1, subgridScale))),
		roomDepthCells = math.max(1, math.floor(depthSubcells / math.max(1, subgridScale))),
	}
end

local function supportCellOrigin(context, supportX, supportZ)
	local originX = context.offsetX + ((supportX - 1) * context.reserveSize) + 1
	local originZ = context.offsetZ + ((supportZ - 1) * context.reserveSize) + 1
	return originX, originZ
end

local function supportCellCenter(context, supportX, supportZ)
	local originX, originZ = supportCellOrigin(context, supportX, supportZ)
	local centerOffset = math.floor((context.reserveSize - 1) * 0.5)
	return originX + centerOffset, originZ + centerOffset
end

local function pushSupportCellPillar(pushAnchor, context, supportX, supportZ, reason, priority, layoutPattern, wall)
	if supportX < 1 or supportX > context.cols or supportZ < 1 or supportZ > context.rows then
		return false
	end
	local centerX, centerZ = supportCellCenter(context, supportX, supportZ)
	local reserveX, reserveZ = supportCellOrigin(context, supportX, supportZ)
	return pushAnchor("pillar", centerX, centerZ, reason, priority, wall, {
		supportCellX = supportX,
		supportCellZ = supportZ,
		reserveOriginX = reserveX,
		reserveOriginZ = reserveZ,
		reserveW = context.reserveSize,
		reserveD = context.reserveSize,
		layoutPattern = layoutPattern,
	})
end

local function buildCenteredIndices(minIdx, maxIdx, interval, maxCount)
	if maxIdx < minIdx then
		return {}
	end
	local step = math.max(1, math.floor(asNumber(interval, 1)))
	local limit = math.max(1, math.floor(asNumber(maxCount, (maxIdx - minIdx + 1))))
	local center = math.floor((minIdx + maxIdx) * 0.5)
	local base = center - ((center - minIdx) % step)
	if base < minIdx then
		base = base + step
	end

	local out = {}
	local seen = {}
	local function push(idx)
		if idx >= minIdx and idx <= maxIdx and not seen[idx] and ((idx - minIdx) % step == 0) then
			seen[idx] = true
			out[#out + 1] = idx
			return true
		end
		return false
	end

	local wave = 0
	while #out < limit do
		local addedAny = false
		if wave == 0 then
			addedAny = push(base) or addedAny
		else
			addedAny = push(base - (wave * step)) or addedAny
			addedAny = push(base + (wave * step)) or addedAny
		end
		if not addedAny then
			break
		end
		wave += 1
	end

	table.sort(out)
	return out
end

local function applyCornerPillarSupports(pushAnchor, context, reason, priority, layoutPattern)
	if context.cols < 2 or context.rows < 2 then
		return
	end
	pushSupportCellPillar(pushAnchor, context, 1, 1, reason, priority, layoutPattern, "corner")
	pushSupportCellPillar(pushAnchor, context, context.cols, 1, reason, priority, layoutPattern, "corner")
	pushSupportCellPillar(pushAnchor, context, 1, context.rows, reason, priority, layoutPattern, "corner")
	pushSupportCellPillar(
		pushAnchor,
		context,
		context.cols,
		context.rows,
		reason,
		priority,
		layoutPattern,
		"corner"
	)
end

local function applyPerimeterPillarSupports(pushAnchor, context, intervalCells, insetCells, reason, priority, layoutPattern)
	if context.cols < 2 or context.rows < 2 then
		return
	end
	local interval = math.max(1, math.floor(asNumber(intervalCells, 1)))
	local inset = math.max(0, math.floor(asNumber(insetCells, 0)))
	local minX = clamp(1 + inset, 1, context.cols)
	local maxX = clamp(context.cols - inset, 1, context.cols)
	local minZ = clamp(1 + inset, 1, context.rows)
	local maxZ = clamp(context.rows - inset, 1, context.rows)
	if maxX < minX or maxZ < minZ then
		return
	end

	for sx = minX, maxX, interval do
		pushSupportCellPillar(pushAnchor, context, sx, minZ, reason, priority, layoutPattern, WALL_NORTH)
		pushSupportCellPillar(pushAnchor, context, sx, maxZ, reason, priority, layoutPattern, WALL_SOUTH)
	end
	for sz = minZ, maxZ, interval do
		pushSupportCellPillar(pushAnchor, context, minX, sz, reason, priority, layoutPattern, WALL_WEST)
		pushSupportCellPillar(pushAnchor, context, maxX, sz, reason, priority, layoutPattern, WALL_EAST)
	end
end

local function applyInteriorGridPillarSupports(pushAnchor, context, layout)
	local margin = math.max(0, math.floor(asNumber(layout and layout.GridMarginCells, 1)))
	local minX = clamp(1 + margin, 1, context.cols)
	local maxX = clamp(context.cols - margin, 1, context.cols)
	local minZ = clamp(1 + margin, 1, context.rows)
	local maxZ = clamp(context.rows - margin, 1, context.rows)
	if maxX < minX or maxZ < minZ then
		return 0, 0
	end

	local colInterval = math.max(1, math.floor(asNumber(layout and layout.GridColumnIntervalCells, 2)))
	local rowInterval = math.max(1, math.floor(asNumber(layout and layout.GridRowIntervalCells, 2)))
	local maxCols = math.max(1, math.floor(asNumber(layout and layout.GridMaxColumns, maxX - minX + 1)))
	local maxRows = math.max(1, math.floor(asNumber(layout and layout.GridMaxRows, maxZ - minZ + 1)))

	local cols = buildCenteredIndices(minX, maxX, colInterval, maxCols)
	local rows = buildCenteredIndices(minZ, maxZ, rowInterval, maxRows)
	for _, sx in ipairs(cols) do
		for _, sz in ipairs(rows) do
			pushSupportCellPillar(pushAnchor, context, sx, sz, "layout_grid", 85, "large_grid", "grid")
		end
	end
	return #cols, #rows
end

local function pushUniqueSortedIndex(out, seen, idx, minIdx, maxIdx)
	local clamped = clamp(math.floor(idx + 0.5), minIdx, maxIdx)
	if not seen[clamped] then
		seen[clamped] = true
		out[#out + 1] = clamped
	end
end

local function buildEdgeDistributedIndices(minIdx, maxIdx, requestedCount)
	if maxIdx < minIdx then
		return {}
	end
	local available = (maxIdx - minIdx) + 1
	local count = math.max(1, math.floor(asNumber(requestedCount, 1)))
	count = math.min(count, available)
	if count <= 1 then
		return { math.floor((minIdx + maxIdx) * 0.5) }
	end

	local out = {}
	local seen = {}
	local span = maxIdx - minIdx
	for i = 0, count - 1 do
		local t = i / (count - 1)
		pushUniqueSortedIndex(out, seen, minIdx + (span * t), minIdx, maxIdx)
	end

	if #out <= 1 then
		pushUniqueSortedIndex(out, seen, minIdx, minIdx, maxIdx)
		pushUniqueSortedIndex(out, seen, maxIdx, minIdx, maxIdx)
	end
	table.sort(out)
	return out
end

local function stringContainsCI(haystack, needle)
	if type(haystack) ~= "string" or type(needle) ~= "string" then
		return false
	end
	return string.find(string.lower(haystack), string.lower(needle), 1, true) ~= nil
end

local function hasTagCI(tags, wanted)
	if type(tags) ~= "table" then
		return false
	end
	for _, tag in ipairs(tags) do
		if string.lower(tostring(tag)) == string.lower(wanted) then
			return true
		end
	end
	return false
end

local function isHallLikeRoom(context, layout)
	local widthCells = math.max(1, math.floor(asNumber(context and context.roomWidthCells, context and context.cols or 1)))
	local depthCells = math.max(1, math.floor(asNumber(context and context.roomDepthCells, context and context.rows or 1)))
	local longEdge = math.max(widthCells, depthCells)
	local shortEdge = math.max(1, math.min(widthCells, depthCells))
	local aspect = longEdge / shortEdge
	local minAspect = math.max(1.2, asNumber(layout and layout.LongHallAspectRatio, 1.75))
	if aspect >= minAspect then
		return true
	end

	local category = string.lower(tostring(context and context.roomCategory or ""))
	if category == "connector" then
		return true
	end

	local roomTypeId = tostring(context and context.roomTypeId or "")
	if stringContainsCI(roomTypeId, "hall")
		or stringContainsCI(roomTypeId, "corridor")
		or stringContainsCI(roomTypeId, "connector")
	then
		return true
	end

	local tags = context and context.roomTags or {}
	return hasTagCI(tags, "hallway") or hasTagCI(tags, "corridor") or hasTagCI(tags, "connector")
end

local function resolvePrimaryPattern(layoutPattern, roomClass)
	local raw = string.lower(tostring(layoutPattern or ""))
	if raw == "" then
		return nil
	end
	if raw == "none" then
		return "none"
	elseif raw == "corner" or raw == "corner_supports" then
		return "corner_supports"
	elseif raw == "span" or raw == "axial_span" then
		return "axial_span"
	elseif raw == "grid" or raw == "interior_grid" then
		return "interior_grid"
	elseif raw == "perimeter" or raw == "perimeter_band" then
		return "perimeter_band"
	end
	if roomClass == "small" then
		return nil
	elseif roomClass == "medium" then
		return nil
	end
	return nil
end

local function choosePrimaryPillarPattern(context, pillarRules)
	local layout = pillarRules and pillarRules.Layout or {}
	local supportArea = context.cols * context.rows
	local smallMaxArea = math.max(1, math.floor(asNumber(layout.SmallRoomMaxAreaCells, 12)))
	local mediumMaxArea = math.max(smallMaxArea, math.floor(asNumber(layout.MediumRoomMaxAreaCells, 28)))
	local disableCornerWrap = (layout.DisableCornerWrap ~= false)
	local hallLike = isHallLikeRoom(context, layout)

	local roomClass = "large"
	if supportArea <= smallMaxArea then
		roomClass = "small"
	elseif supportArea <= mediumMaxArea then
		roomClass = "medium"
	end

	local explicit = nil
	if roomClass == "small" then
		explicit = resolvePrimaryPattern(layout.SmallPrimaryPattern, roomClass)
	elseif roomClass == "medium" then
		explicit = resolvePrimaryPattern(layout.MediumPrimaryPattern, roomClass)
	else
		explicit = resolvePrimaryPattern(layout.LargePrimaryPattern, roomClass)
	end
	if explicit then
		return explicit, roomClass, hallLike
	end

	if roomClass == "small" then
		if layout.SmallCornerSupports == true then
			return "corner_supports", roomClass, hallLike
		end
		return "none", roomClass, hallLike
	end

	if roomClass == "medium" then
		if hallLike and layout.MediumUseAxialSpans ~= false then
			return "axial_span", roomClass, hallLike
		end
		if layout.MediumUseAxialSpans ~= false then
			return "axial_span", roomClass, hallLike
		end
		if (not disableCornerWrap) and layout.MediumPerimeterSupports == true then
			return "perimeter_band", roomClass, hallLike
		end
		if (not disableCornerWrap) and layout.MediumCornerSupports == true then
			return "corner_supports", roomClass, hallLike
		end
		return "none", roomClass, hallLike
	end

	-- Large rooms: choose one dominant family only.
	if hallLike and layout.LargeUseAxialSpans ~= false then
		return "axial_span", roomClass, hallLike
	end
	if layout.LargeGridSupports ~= false then
		return "interior_grid", roomClass, hallLike
	end
	if (not disableCornerWrap) and layout.LargePerimeterSupports == true then
		return "perimeter_band", roomClass, hallLike
	end
	if layout.LargeUseAxialSpans ~= false then
		return "axial_span", roomClass, hallLike
	end
	if (not disableCornerWrap) and layout.LargeCornerSupports == true then
		return "corner_supports", roomClass, hallLike
	end
	return "none", roomClass, hallLike
end

local function applyAxialSpanPillarSupports(pushAnchor, context, layout, patternLabel, reason, priority)
	local cols = math.max(1, context.cols)
	local rows = math.max(1, context.rows)
	local longAxisX = cols >= rows

	local spanInset = math.max(0, math.floor(asNumber(layout and layout.SpanInsetCells, 0)))
	local lineCount = math.max(1, math.floor(asNumber(layout and layout.SpanLineCount, longAxisX and 2 or 1)))
	local interval = math.max(1, math.floor(asNumber(layout and layout.SpanIntervalCells, 2)))

	local minX = clamp(1 + spanInset, 1, cols)
	local maxX = clamp(cols - spanInset, 1, cols)
	local minZ = clamp(1 + spanInset, 1, rows)
	local maxZ = clamp(rows - spanInset, 1, rows)
	if maxX < minX or maxZ < minZ then
		return 0
	end

	local longMin = longAxisX and minX or minZ
	local longMax = longAxisX and maxX or maxZ
	local crossMin = longAxisX and minZ or minX
	local crossMax = longAxisX and maxZ or maxX
	local crossIndices
	if lineCount <= 1 then
		crossIndices = { math.floor((crossMin + crossMax) * 0.5) }
	else
		crossIndices = buildEdgeDistributedIndices(crossMin, crossMax, lineCount)
	end
	local emitted = 0

	for _, cross in ipairs(crossIndices) do
		local lastLong = nil
		for long = longMin, longMax, interval do
			local sx = longAxisX and long or cross
			local sz = longAxisX and cross or long
			if pushSupportCellPillar(
				pushAnchor,
				context,
				sx,
				sz,
				reason,
				priority,
				patternLabel,
				longAxisX and "span_x" or "span_z"
			) then
				emitted += 1
			end
			lastLong = long
		end
		-- Force terminal support so spans read wall-to-wall within the chosen support grid.
		if lastLong ~= longMax then
			local sx = longAxisX and longMax or cross
			local sz = longAxisX and cross or longMax
			if pushSupportCellPillar(
				pushAnchor,
				context,
				sx,
				sz,
				reason,
				priority,
				patternLabel,
				longAxisX and "span_x" or "span_z"
			) then
				emitted += 1
			end
		end
	end

	return emitted
end

local function applySinglePillarPattern(pushAnchor, context, pillarRules, primaryPattern, roomClass)
	local layout = pillarRules and pillarRules.Layout or {}
	local labelPrefix = tostring(roomClass or "room")
	if primaryPattern == "corner_supports" then
		applyCornerPillarSupports(
			pushAnchor,
			context,
			"layout_" .. labelPrefix .. "_corner",
			95,
			labelPrefix .. "_corner_supports"
		)
		return labelPrefix .. "_corner_supports"
	elseif primaryPattern == "axial_span" then
		if roomClass == "medium" then
			applyAxialSpanPillarSupports(
				pushAnchor,
				context,
				{
					SpanInsetCells = layout.MediumSpanInsetCells,
					SpanLineSpacingCells = layout.MediumSpanLineSpacingCells or layout.SpanLineSpacingCells,
					SpanLineCount = layout.MediumSpanLineCount or 1,
					SpanIntervalCells = layout.MediumSpanIntervalCells or layout.SpanIntervalCells,
				},
				labelPrefix .. "_axial_span",
				"layout_medium_span",
				92
			)
		else
			applyAxialSpanPillarSupports(
				pushAnchor,
				context,
				{
					SpanInsetCells = layout.LargeSpanInsetCells,
					SpanLineSpacingCells = layout.LargeSpanLineSpacingCells or layout.SpanLineSpacingCells,
					SpanLineCount = layout.LargeSpanLineCount or 2,
					SpanIntervalCells = layout.LargeSpanIntervalCells or layout.SpanIntervalCells,
				},
				labelPrefix .. "_axial_span",
				"layout_large_span",
				90
			)
		end
		return labelPrefix .. "_axial_span"
	elseif primaryPattern == "interior_grid" then
		applyInteriorGridPillarSupports(pushAnchor, context, layout)
		return labelPrefix .. "_interior_grid"
	elseif primaryPattern == "perimeter_band" then
		applyPerimeterPillarSupports(
			pushAnchor,
			context,
			layout.PerimeterIntervalCells,
			layout.PerimeterInsetCells,
			"layout_" .. labelPrefix .. "_perimeter",
			86,
			labelPrefix .. "_perimeter_band"
		)
		return labelPrefix .. "_perimeter_band"
	end
	return "none"
end

local function applyDeterministicPillarLayout(pushAnchor, context, pillarRules)
	local layout = pillarRules and pillarRules.Layout or {}
	local supportArea = context.cols * context.rows
	local primaryPattern, roomClass, hallLike = choosePrimaryPillarPattern(context, pillarRules)
	local layoutPattern = applySinglePillarPattern(pushAnchor, context, pillarRules, primaryPattern, roomClass)

	-- Secondary families are opt-in only by archetype.
	if layout.EnableSecondaryByArchetype == true then
		local byArch = layout.SecondaryPatternsByArchetype
		local archId = tostring(context and context.archetypeId or "")
		local secondaryList = type(byArch) == "table" and byArch[archId] or nil
		if type(secondaryList) == "table" then
			for _, secondaryPattern in ipairs(secondaryList) do
				local normalized = resolvePrimaryPattern(secondaryPattern, roomClass)
				if normalized and normalized ~= "none" and normalized ~= primaryPattern then
					applySinglePillarPattern(pushAnchor, context, pillarRules, normalized, roomClass)
				end
			end
		end
	end

	return {
		layoutPattern = layoutPattern,
		supportCols = context.cols,
		supportRows = context.rows,
		supportArea = supportArea,
		reserveSize = context.reserveSize,
		supportOffsetX = context.offsetX,
		supportOffsetZ = context.offsetZ,
		hallLike = hallLike == true,
		primaryPattern = tostring(primaryPattern or "none"),
		roomClass = tostring(roomClass or "unknown"),
	}
end

function DungeonStructuralPropPlanner.BuildPlan(input)
	local plannerInput = {
		profile = input.profile,
		state = input.state,
		roomTypeRecord = input.roomTypeRecord or {},
		archetypeRecord = input.archetypeRecord or {},
		rules = input.rules or {},
	}
	local profile = plannerInput.profile
	local state = plannerInput.state
	local roomTypeRecord = plannerInput.roomTypeRecord
	local archetypeRecord = plannerInput.archetypeRecord
	local rules = plannerInput.rules

	local derived = {}
	derived.subgridScale = normalizeSubgridScale(profile)
	derived.widthSubcells, derived.depthSubcells, derived.widthCells, derived.depthCells =
		normalizeRoomCells(profile, derived.subgridScale)

	local plan = {
		pillarAnchors = {},
		wallAnchors = {},
		stats = {
			plannedPillarAnchors = 0,
			plannedWallAnchors = 0,
			candidatePillarAnchors = 0,
			candidateWallAnchors = 0,
			candidateAnchorCount = 0,
			skippedNearDoor = 0,
			skippedNearNavigation = 0,
			pillarLayoutPattern = "none",
			pillarPrimaryPattern = "none",
			pillarRoomClass = "unknown",
			pillarHallLike = false,
			pillarSupportCols = 0,
			pillarSupportRows = 0,
			pillarSupportArea = 0,
			pillarReserveSizeSubcells = 0,
			pillarSupportOffsetX = 0,
			pillarSupportOffsetZ = 0,
			doorBlockedNorthCells = 0,
			doorBlockedSouthCells = 0,
			doorBlockedEastCells = 0,
			doorBlockedWestCells = 0,
		},
	}
	local surfaces = (state and state.surfaces) or {}
	local doorMask = (type(surfaces.doors) == "table") and surfaces.doors or {}
	local navigationMask = (type(surfaces.navigation) == "table") and surfaces.navigation or {}

	if rules.Enabled ~= true then
		return plan
	end

	local allAnchors, pushAny = buildAnchorCollector(derived.widthSubcells, derived.depthSubcells)

	local pillarRules = rules.Pillars or {}
	local wallRules = rules.WallProps or {}
	local supportContext = buildPillarSupportGridContext(
		derived.widthSubcells,
		derived.depthSubcells,
		pillarRules,
		derived.subgridScale
	)
	supportContext.roomCategory = roomTypeRecord.category or "Room"
	supportContext.roomTypeId = roomTypeRecord.id or profile.roomType
	supportContext.roomTags = roomTypeRecord.tags or {}
	supportContext.archetypeId = archetypeRecord.id or profile.archetype
	local pillarLayoutStats = applyDeterministicPillarLayout(pushAny, supportContext, pillarRules)
	plan.stats.pillarLayoutPattern = pillarLayoutStats.layoutPattern
	plan.stats.pillarPrimaryPattern = pillarLayoutStats.primaryPattern
	plan.stats.pillarRoomClass = pillarLayoutStats.roomClass
	plan.stats.pillarHallLike = pillarLayoutStats.hallLike
	plan.stats.pillarSupportCols = pillarLayoutStats.supportCols
	plan.stats.pillarSupportRows = pillarLayoutStats.supportRows
	plan.stats.pillarSupportArea = pillarLayoutStats.supportArea
	plan.stats.pillarReserveSizeSubcells = pillarLayoutStats.reserveSize
	plan.stats.pillarSupportOffsetX = pillarLayoutStats.supportOffsetX
	plan.stats.pillarSupportOffsetZ = pillarLayoutStats.supportOffsetZ

	local doorBlockedByWall = buildDoorBlockedByWall(
		profile,
		derived.subgridScale,
		asNumber(wallRules.DoorClearanceCells, 1),
		derived.widthCells,
		derived.depthCells
	)
	local doorBlockedCounts = countBlockedCellsByWall(doorBlockedByWall)
	plan.stats.doorBlockedNorthCells = doorBlockedCounts[WALL_NORTH] or 0
	plan.stats.doorBlockedSouthCells = doorBlockedCounts[WALL_SOUTH] or 0
	plan.stats.doorBlockedEastCells = doorBlockedCounts[WALL_EAST] or 0
	plan.stats.doorBlockedWestCells = doorBlockedCounts[WALL_WEST] or 0

	collectWallAnchorCandidates(
		profile,
		state,
		derived.subgridScale,
		derived.widthSubcells,
		derived.depthSubcells,
		derived.widthCells,
		derived.depthCells,
		doorBlockedByWall,
		wallRules,
		pushAny
	)

	local doorClearance = math.max(0, math.floor(asNumber(rules.DoorClearanceSubcells, 0)))
	local navClearance = math.max(0, math.floor(asNumber(rules.NavigationClearanceSubcells, 0)))
	local wallNavClearance = math.max(0, math.floor(asNumber(wallRules.NavigationClearanceSubcells, navClearance)))

	sortAnchors(allAnchors)
	plan.stats.candidateAnchorCount = #allAnchors
	for _, anchor in ipairs(allAnchors) do
		if anchor.kind == "pillar" then
			plan.stats.candidatePillarAnchors += 1
		elseif anchor.kind == "wall_prop" then
			plan.stats.candidateWallAnchors += 1
		end
		local navRadius = navClearance
		if anchor.kind == "wall_prop" then
			navRadius = wallNavClearance
		end
		if isNearMask(doorMask, anchor.x, anchor.z, doorClearance) then
			plan.stats.skippedNearDoor += 1
		elseif navRadius > 0 and isNearMask(navigationMask, anchor.x, anchor.z, navRadius) then
			plan.stats.skippedNearNavigation += 1
		else
			if anchor.kind == "pillar" then
				plan.pillarAnchors[#plan.pillarAnchors + 1] = anchor
			elseif anchor.kind == "wall_prop" then
				plan.wallAnchors[#plan.wallAnchors + 1] = anchor
			end
		end
	end

	plan.stats.plannedPillarAnchors = #plan.pillarAnchors
	plan.stats.plannedWallAnchors = #plan.wallAnchors
	plan.stats.roomAreaCells = derived.widthCells * derived.depthCells
	plan.stats.roomWidthCells = derived.widthCells
	plan.stats.roomDepthCells = derived.depthCells
	plan.stats.roomCategory = roomTypeRecord.category or "Room"
	plan.stats.archetypeId = archetypeRecord.id or profile.archetype

	return plan
end

return DungeonStructuralPropPlanner

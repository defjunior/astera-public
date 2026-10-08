local RoomPatternLibrary = {}

local patterns = {
 -- EXCLUDED: authored content/settings table, at the owner's request.
 -- General structure: map<string, pattern record>: id/family, dimensions/cells, directional socket cells, rotatable boolean
 -- Intentionally empty, not a runnable replacement. See CONTENT-SCHEMAS.md.
}

local CARDINAL_DIRECTIONS = { "North", "East", "South", "West" }
local variantCache = {}

local function normalizeTurns(turns)
	return ((turns or 0) % 4 + 4) % 4
end

local function copyCell(cell)
	return { x = cell.x, y = cell.y, z = cell.z }
end

local function copyCells(cells)
	local out = {}
	for i, cell in ipairs(cells or {}) do
		out[i] = copyCell(cell)
	end
	return out
end

local function cellKey(cell)
	return string.format("%d,%d,%d", cell.x, cell.y, cell.z)
end

local function copyCellSet(cellSet)
	local out = {}
	for key, value in pairs(cellSet or {}) do
		if value then
			out[key] = true
		end
	end
	return out
end

local function copySockets(sockets)
	local out = {}
	for _, direction in ipairs(CARDINAL_DIRECTIONS) do
		out[direction] = copyCells(sockets and sockets[direction] or {})
	end
	return out
end

local function copyBounds(bounds)
	return {
		min = copyCell(bounds.min),
		max = copyCell(bounds.max),
	}
end

local function rotateCell(cell, turns)
	local x, z = cell.x, cell.z
	if turns == 1 then
		return { x = -z, y = cell.y, z = x }
	elseif turns == 2 then
		return { x = -x, y = cell.y, z = -z }
	elseif turns == 3 then
		return { x = z, y = cell.y, z = -x }
	end
	return { x = x, y = cell.y, z = z }
end

local function rotateDirection(direction, turns)
	local indexByDirection = {
		North = 1,
		East = 2,
		South = 3,
		West = 4,
	}
	local baseIndex = indexByDirection[direction]
	if not baseIndex then
		return direction
	end
	local rotatedIndex = ((baseIndex - 1 + turns) % 4) + 1
	return CARDINAL_DIRECTIONS[rotatedIndex]
end

local function buildBounds(cells)
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge

	for _, cell in ipairs(cells) do
		if cell.x < minX then
			minX = cell.x
		end
		if cell.y < minY then
			minY = cell.y
		end
		if cell.z < minZ then
			minZ = cell.z
		end
		if cell.x > maxX then
			maxX = cell.x
		end
		if cell.y > maxY then
			maxY = cell.y
		end
		if cell.z > maxZ then
			maxZ = cell.z
		end
	end

	return {
		min = { x = minX, y = minY, z = minZ },
		max = { x = maxX, y = maxY, z = maxZ },
	}
end

local function normalizeCells(cells)
	local rawBounds = buildBounds(cells)
	local offset = {
		x = rawBounds.min.x,
		y = rawBounds.min.y,
		z = rawBounds.min.z,
	}

	local normalized = {}
	for i, cell in ipairs(cells) do
		normalized[i] = {
			x = cell.x - offset.x,
			y = cell.y - offset.y,
			z = cell.z - offset.z,
		}
	end

	return normalized, offset
end

local function sortCells(cells)
	table.sort(cells, function(a, b)
		if a.y ~= b.y then
			return a.y < b.y
		end
		if a.z ~= b.z then
			return a.z < b.z
		end
		return a.x < b.x
	end)
end

local function buildCellSet(cells)
	local set = {}
	for _, cell in ipairs(cells) do
		set[cellKey(cell)] = true
	end
	return set
end

local function cellsSignature(cells)
	local parts = {}
	for i, cell in ipairs(cells) do
		parts[i] = cellKey(cell)
	end
	return table.concat(parts, ";")
end

local function cloneVariant(variant)
	return {
		id = variant.id,
		patternId = variant.patternId,
		family = variant.family,
		rotation = variant.rotation,
		rotationKey = variant.rotationKey,
		rotatable = variant.rotatable,
		dimensions = copyCell(variant.dimensions),
		bounds = copyBounds(variant.bounds),
		normalizationOffset = copyCell(variant.normalizationOffset),
		cells = copyCells(variant.cells),
		cellSet = copyCellSet(variant.cellSet),
		sockets = copySockets(variant.sockets),
	}
end

local function buildVariant(patternId, turns)
	local pattern = patterns[patternId]
	if not pattern then
		return nil
	end

	local effectiveTurns = normalizeTurns(turns)
	if pattern.rotatable ~= true then
		effectiveTurns = 0
	end

	local cacheKey = string.format("%s:%d", patternId, effectiveTurns)
	if variantCache[cacheKey] then
		return variantCache[cacheKey]
	end

	local rotatedCells = {}
	for i, cell in ipairs(pattern.cells) do
		rotatedCells[i] = rotateCell(cell, effectiveTurns)
	end

	local normalizedCells, offset = normalizeCells(rotatedCells)
	sortCells(normalizedCells)
	local bounds = buildBounds(normalizedCells)
	local dimensions = {
		x = bounds.max.x - bounds.min.x + 1,
		y = bounds.max.y - bounds.min.y + 1,
		z = bounds.max.z - bounds.min.z + 1,
	}

	local sockets = {}
	for _, direction in ipairs(CARDINAL_DIRECTIONS) do
		sockets[direction] = {}
	end

	for direction, socketCells in pairs(pattern.sockets or {}) do
		local rotatedDirection = rotateDirection(direction, effectiveTurns)
		local target = sockets[rotatedDirection]
		if target then
			for _, socketCell in ipairs(socketCells) do
				target[#target + 1] = {
					x = rotateCell(socketCell, effectiveTurns).x - offset.x,
					y = rotateCell(socketCell, effectiveTurns).y - offset.y,
					z = rotateCell(socketCell, effectiveTurns).z - offset.z,
				}
			end
		end
	end

	for _, direction in ipairs(CARDINAL_DIRECTIONS) do
		sortCells(sockets[direction])
	end

	local variant = {
		id = pattern.id,
		patternId = pattern.id,
		family = pattern.family,
		rotation = effectiveTurns,
		rotationKey = string.format("r%d", effectiveTurns),
		rotatable = pattern.rotatable == true,
		dimensions = dimensions,
		bounds = bounds,
		normalizationOffset = offset,
		cells = normalizedCells,
		cellSet = buildCellSet(normalizedCells),
		sockets = sockets,
	}

	variantCache[cacheKey] = variant
	return variant
end

local function shiftedCells(cells, origin)
	local out = {}
	for i, cell in ipairs(cells) do
		out[i] = {
			x = cell.x + origin.x,
			y = cell.y + origin.y,
			z = cell.z + origin.z,
		}
	end
	return out
end

local function shiftedSockets(sockets, origin)
	local out = {}
	for _, direction in ipairs(CARDINAL_DIRECTIONS) do
		out[direction] = shiftedCells(sockets[direction] or {}, origin)
	end
	return out
end

function RoomPatternLibrary.Get(patternId)
	return patterns[patternId]
end

function RoomPatternLibrary.GetAll()
	return patterns
end

function RoomPatternLibrary.ListIds()
	local ids = {}
	for id in pairs(patterns) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	return ids
end

function RoomPatternLibrary.GetVariant(patternId, turns)
	local variant = buildVariant(patternId, turns)
	if not variant then
		return nil
	end
	return cloneVariant(variant)
end

function RoomPatternLibrary.GetCellsWithRotation(patternId, turns)
	local variant = RoomPatternLibrary.GetVariant(patternId, turns)
	return variant and variant.cells or nil
end

function RoomPatternLibrary.GetSocketsWithRotation(patternId, turns)
	local variant = RoomPatternLibrary.GetVariant(patternId, turns)
	return variant and variant.sockets or nil
end

function RoomPatternLibrary.EnumerateVariants(patternId, options)
	local pattern = patterns[patternId]
	if not pattern then
		return {}
	end

	local includeSymmetricDuplicates = options and options.includeSymmetricDuplicates == true
	local maxTurns = (pattern.rotatable == true) and 4 or 1

	local variants = {}
	local seen = {}
	for t = 0, maxTurns - 1 do
		local variant = buildVariant(patternId, t)
		local signature = cellsSignature(variant.cells)
		if includeSymmetricDuplicates or not seen[signature] then
			seen[signature] = true
			variants[#variants + 1] = cloneVariant(variant)
		end
	end

	table.sort(variants, function(a, b)
		if a.rotation ~= b.rotation then
			return a.rotation < b.rotation
		end
		return a.patternId < b.patternId
	end)

	return variants
end

function RoomPatternLibrary.Instantiate(patternId, turns, origin)
	local variant = buildVariant(patternId, turns)
	if not variant then
		return nil
	end

	local o = origin or { x = 0, y = 0, z = 0 }
	local absCells = shiftedCells(variant.cells, o)
	local absSockets = shiftedSockets(variant.sockets, o)
	local absBounds = {
		min = {
			x = variant.bounds.min.x + o.x,
			y = variant.bounds.min.y + o.y,
			z = variant.bounds.min.z + o.z,
		},
		max = {
			x = variant.bounds.max.x + o.x,
			y = variant.bounds.max.y + o.y,
			z = variant.bounds.max.z + o.z,
		},
	}

	return {
		id = variant.id,
		patternId = variant.patternId,
		family = variant.family,
		rotation = variant.rotation,
		rotationKey = variant.rotationKey,
		origin = copyCell(o),
		dimensions = copyCell(variant.dimensions),
		bounds = absBounds,
		cells = absCells,
		cellSet = buildCellSet(absCells),
		sockets = absSockets,
	}
end

function RoomPatternLibrary.FitsInBounds(patternId, turns, origin, bounds)
	local instance = RoomPatternLibrary.Instantiate(patternId, turns, origin)
	if not instance or type(bounds) ~= "table" then
		return false
	end

	return instance.bounds.min.x >= bounds.minX
		and instance.bounds.max.x <= bounds.maxX
		and instance.bounds.min.y >= bounds.minY
		and instance.bounds.max.y <= bounds.maxY
		and instance.bounds.min.z >= bounds.minZ
		and instance.bounds.max.z <= bounds.maxZ
end

function RoomPatternLibrary.Validate()
	local issues = {}

	for id, pattern in pairs(patterns) do
		if pattern.id ~= id then
			issues[#issues + 1] = string.format("Pattern '%s' id mismatch", id)
		end

		if type(pattern.cells) ~= "table" or #pattern.cells == 0 then
			issues[#issues + 1] = string.format("Pattern '%s' has no cells", id)
		else
			local seen = {}
			for _, cell in ipairs(pattern.cells) do
				local key = cellKey(cell)
				if seen[key] then
					issues[#issues + 1] = string.format("Pattern '%s' has duplicate cell '%s'", id, key)
				end
				seen[key] = true
			end

			local bounds = buildBounds(pattern.cells)
			local dims = {
				x = bounds.max.x - bounds.min.x + 1,
				y = bounds.max.y - bounds.min.y + 1,
				z = bounds.max.z - bounds.min.z + 1,
			}
			if not pattern.dimensions
				or pattern.dimensions.x ~= dims.x
				or pattern.dimensions.y ~= dims.y
				or pattern.dimensions.z ~= dims.z
			then
				issues[#issues + 1] = string.format(
					"Pattern '%s' dimensions mismatch; expected %dx%dx%d",
					id,
					dims.x,
					dims.y,
					dims.z
				)
			end

			if type(pattern.sockets) ~= "table" then
				issues[#issues + 1] = string.format("Pattern '%s' missing sockets", id)
			else
				local cellSet = buildCellSet(pattern.cells)
				for _, direction in ipairs(CARDINAL_DIRECTIONS) do
					local socketCells = pattern.sockets[direction]
					if type(socketCells) ~= "table" then
						issues[#issues + 1] = string.format("Pattern '%s' missing '%s' sockets", id, direction)
					else
						for _, socketCell in ipairs(socketCells) do
							if not cellSet[cellKey(socketCell)] then
								issues[#issues + 1] = string.format(
									"Pattern '%s' has socket outside footprint (%s at %s)",
									id,
									direction,
									cellKey(socketCell)
								)
							end
						end
					end
				end
			end
		end

		local variant = buildVariant(id, 0)
		if not variant then
			issues[#issues + 1] = string.format("Pattern '%s' failed to build base variant", id)
		end
	end

	return #issues == 0, issues
end

return RoomPatternLibrary

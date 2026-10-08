--!strict

local FeatureGeometry = {}
local FeatureConfig = require(script.Parent.FeatureConfig)

type Bounds = {
	min: Vector3,
	max: Vector3,
}

type BoxSpec = {
	id: string,
	bounds: Bounds,
	material: Enum.Material,
	color: Color3,
	transparency: number,
	canCollide: boolean,
	canQuery: boolean,
	canTouch: boolean,
	castShadow: boolean,
	role: string,
	sectionId: string,
}

local AXES = { "X", "Y", "Z" }

local function finiteNumber(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function validBounds(bounds: Bounds): boolean
	if type(bounds) ~= "table" or typeof(bounds.min) ~= "Vector3" or typeof(bounds.max) ~= "Vector3" then
		return false
	end
	for _, axis in ipairs(AXES) do
		local low = bounds.min[axis]
		local high = bounds.max[axis]
		if not finiteNumber(low) or not finiteNumber(high) or low >= high then
			return false
		end
	end
	return true
end

local function copyBounds(bounds: Bounds): Bounds
	return { min = bounds.min, max = bounds.max }
end

local function copyBox(box: BoxSpec): BoxSpec
	local result = table.clone(box)
	result.bounds = copyBounds(box.bounds)
	return result
end

local function createBox(id: string, template: BoxSpec, min: Vector3, max: Vector3): BoxSpec
	local result = copyBox(template)
	result.id = id
	result.bounds = { min = min, max = max }
	return result
end

local function makeVector(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function boundsKey(bounds: Bounds): string
	return string.format(
		"%.17g,%.17g,%.17g,%.17g,%.17g,%.17g",
		bounds.min.X,
		bounds.min.Y,
		bounds.min.Z,
		bounds.max.X,
		bounds.max.Y,
		bounds.max.Z
	)
end

local function positiveBox(id: string, template: BoxSpec, min: Vector3, max: Vector3): BoxSpec?
	if min.X >= max.X or min.Y >= max.Y or min.Z >= max.Z then
		return nil
	end
	return createBox(id, template, min, max)
end

function FeatureGeometry.ValidateBounds(bounds: Bounds): (boolean, string?)
	if not validBounds(bounds) then
		return false, "bounds must contain finite Vector3 min/max values with positive dimensions"
	end
	return true
end

function FeatureGeometry.CreateBox(id: string, bounds: Bounds, properties: { [string]: any }): (BoxSpec?, string?)
	if type(id) ~= "string" or id == "" then
		return nil, "box id must be a non-empty string"
	end
	local ok, reason = FeatureGeometry.ValidateBounds(bounds)
	if not ok then
		return nil, reason
	end
	local size = bounds.max - bounds.min
	local maxAxis = FeatureConfig.Geometry.MaxPartAxisStuds
	if size.X > maxAxis or size.Y > maxAxis or size.Z > maxAxis then
		return nil, ("box exceeds Roblox's %d-stud per-axis part size; use CreateBoxes to split it"):format(maxAxis)
	end
	if type(properties) ~= "table" then
		return nil, "box properties must be a table"
	end
	if typeof(properties.material) ~= "EnumItem" or properties.material.EnumType ~= Enum.Material then
		return nil, "box material must be an Enum.Material"
	end
	if typeof(properties.color) ~= "Color3" then
		return nil, "box color must be a Color3"
	end
	if type(properties.role) ~= "string" or properties.role == "" then
		return nil, "box role must be a non-empty string"
	end
	if type(properties.sectionId) ~= "string" or properties.sectionId == "" then
		return nil, "box sectionId must be a non-empty string"
	end
	local transparency = properties.transparency
	if transparency == nil then
		transparency = 0
	end
	if type(transparency) ~= "number" or not finiteNumber(transparency) or transparency < 0 or transparency > 1 then
		return nil, "box transparency must be finite and between 0 and 1"
	end
	for _, flag in ipairs({ "canCollide", "canQuery", "canTouch", "castShadow" }) do
		if type(properties[flag]) ~= "boolean" then
			return nil, "box " .. flag .. " must be a boolean"
		end
	end

	return {
		id = id,
		bounds = copyBounds(bounds),
		material = properties.material,
		color = properties.color,
		transparency = transparency,
		canCollide = properties.canCollide,
		canQuery = properties.canQuery,
		canTouch = properties.canTouch,
		castShadow = properties.castShadow,
		role = properties.role,
		sectionId = properties.sectionId,
	}
end

function FeatureGeometry.CreateBoxes(
	id: string,
	bounds: Bounds,
	properties: { [string]: any }
): ({ BoxSpec }?, string?)
	if type(id) ~= "string" or id == "" then
		return nil, "box id must be a non-empty string"
	end
	local ok, reason = FeatureGeometry.ValidateBounds(bounds)
	if not ok then
		return nil, reason
	end
	local maxAxis = FeatureConfig.Geometry.MaxPartAxisStuds
	local size = bounds.max - bounds.min
	local countX = math.ceil(size.X / maxAxis)
	local countY = math.ceil(size.Y / maxAxis)
	local countZ = math.ceil(size.Z / maxAxis)
	local partCount = countX * countY * countZ
	if partCount > FeatureConfig.Geometry.MaxSplitPartsPerBox then
		return nil, ("box split requires %d parts, exceeding cap %d"):format(
			partCount,
			FeatureConfig.Geometry.MaxSplitPartsPerBox
		)
	end

	local parts = table.create(partCount)
	for xIndex = 0, countX - 1 do
		local minX = bounds.min.X + xIndex * maxAxis
		local maxX = math.min(minX + maxAxis, bounds.max.X)
		for yIndex = 0, countY - 1 do
			local minY = bounds.min.Y + yIndex * maxAxis
			local maxY = math.min(minY + maxAxis, bounds.max.Y)
			for zIndex = 0, countZ - 1 do
				local minZ = bounds.min.Z + zIndex * maxAxis
				local maxZ = math.min(minZ + maxAxis, bounds.max.Z)
				local part, partReason = FeatureGeometry.CreateBox(
					("%s:x%d:y%d:z%d"):format(id, xIndex, yIndex, zIndex),
					{
						min = Vector3.new(minX, minY, minZ),
						max = Vector3.new(maxX, maxY, maxZ),
					},
					properties
				)
				if not part then
					return nil, partReason
				end
				parts[#parts + 1] = part
			end
		end
	end
	return parts
end

local function intersection(a: Bounds, b: Bounds): Bounds?
	local min = Vector3.new(
		math.max(a.min.X, b.min.X),
		math.max(a.min.Y, b.min.Y),
		math.max(a.min.Z, b.min.Z)
	)
	local max = Vector3.new(
		math.min(a.max.X, b.max.X),
		math.min(a.max.Y, b.max.Y),
		math.min(a.max.Z, b.max.Z)
	)
	if min.X >= max.X or min.Y >= max.Y or min.Z >= max.Z then
		return nil
	end
	return { min = min, max = max }
end

function FeatureGeometry.SubtractBox(solid: BoxSpec, cut: Bounds): ({ BoxSpec }?, string?)
	if type(solid) ~= "table" or type(solid.id) ~= "string" or not validBounds(solid.bounds) then
		return nil, "solid must be a valid box descriptor"
	end
	local cutOk, cutReason = FeatureGeometry.ValidateBounds(cut)
	if not cutOk then
		return nil, cutReason
	end

	local overlap = intersection(solid.bounds, cut)
	if not overlap then
		return { copyBox(solid) }
	end

	local s = solid.bounds
	local i = overlap
	local fragments = {}
	local xMin, xMax = s.min.X, s.max.X
	local yMin, yMax = s.min.Y, s.max.Y
	local zMin, zMax = s.min.Z, s.max.Z
	local ixMin, ixMax = i.min.X, i.max.X
	local iyMin, iyMax = i.min.Y, i.max.Y
	local izMin, izMax = i.min.Z, i.max.Z
	local function add(label: string, min: Vector3, max: Vector3)
		local fragment = positiveBox(solid.id .. ":cut:" .. boundsKey(cut) .. ":" .. label, solid, min, max)
		if fragment then
			fragments[#fragments + 1] = fragment
		end
	end

	-- Peel disjoint slabs in a fixed order: X sides, Z sides in the overlap X,
	-- then Y caps in the overlap XZ. Their interiors cannot overlap.
	add("leftX", makeVector(xMin, yMin, zMin), makeVector(ixMin, yMax, zMax))
	add("rightX", makeVector(ixMax, yMin, zMin), makeVector(xMax, yMax, zMax))
	add("frontZ", makeVector(ixMin, yMin, zMin), makeVector(ixMax, yMax, izMin))
	add("backZ", makeVector(ixMin, yMin, izMax), makeVector(ixMax, yMax, zMax))
	add("bottomY", makeVector(ixMin, yMin, izMin), makeVector(ixMax, iyMin, izMax))
	add("topY", makeVector(ixMin, iyMax, izMin), makeVector(ixMax, yMax, izMax))

	table.sort(fragments, function(a, b)
		return a.id < b.id
	end)
	return fragments
end

local function mergePropertiesEqual(a: BoxSpec, b: BoxSpec): boolean
	return a.material == b.material
		and a.color == b.color
		and a.transparency == b.transparency
		and a.canCollide == b.canCollide
		and a.canQuery == b.canQuery
		and a.canTouch == b.canTouch
		and a.castShadow == b.castShadow
		and a.role == b.role
		and a.sectionId == b.sectionId
end

local function mergePair(a: BoxSpec, b: BoxSpec): BoxSpec?
	if not mergePropertiesEqual(a, b) then
		return nil
	end
	local am, ax = a.bounds.min, a.bounds.max
	local bm, bx = b.bounds.min, b.bounds.max
	local min, max
	if am.Y == bm.Y and ax.Y == bx.Y and am.Z == bm.Z and ax.Z == bx.Z then
		if ax.X == bm.X or bx.X == am.X then
			min = makeVector(math.min(am.X, bm.X), am.Y, am.Z)
			max = makeVector(math.max(ax.X, bx.X), ax.Y, ax.Z)
		end
	elseif am.X == bm.X and ax.X == bx.X and am.Z == bm.Z and ax.Z == bx.Z then
		if ax.Y == bm.Y or bx.Y == am.Y then
			min = makeVector(am.X, math.min(am.Y, bm.Y), am.Z)
			max = makeVector(ax.X, math.max(ax.Y, bx.Y), ax.Z)
		end
	elseif am.X == bm.X and ax.X == bx.X and am.Y == bm.Y and ax.Y == bx.Y then
		if ax.Z == bm.Z or bx.Z == am.Z then
			min = makeVector(am.X, am.Y, math.min(am.Z, bm.Z))
			max = makeVector(ax.X, ax.Y, math.max(ax.Z, bx.Z))
		end
	end
	if not min or not max then
		return nil
	end
	local mergedSize = max - min
	local maxAxis = FeatureConfig.Geometry.MaxPartAxisStuds
	if mergedSize.X > maxAxis or mergedSize.Y > maxAxis or mergedSize.Z > maxAxis then
		return nil
	end
	local firstId, secondId = a.id, b.id
	if secondId < firstId then
		firstId, secondId = secondId, firstId
	end
	return createBox("merge(" .. firstId .. "," .. secondId .. ")", a, min, max)
end

function FeatureGeometry.MergeAdjacent(parts: { BoxSpec }): ({ BoxSpec }, { inputCount: number, outputCount: number })
	local merged = table.create(#parts)
	for _, part in ipairs(parts) do
		merged[#merged + 1] = copyBox(part)
	end
	table.sort(merged, function(a, b)
		return a.id < b.id
	end)

	local didMerge = true
	while didMerge do
		didMerge = false
		for first = 1, #merged do
			for second = first + 1, #merged do
				local replacement = mergePair(merged[first], merged[second])
				if replacement then
					merged[first] = replacement
					table.remove(merged, second)
					table.sort(merged, function(a, b)
						return a.id < b.id
					end)
					didMerge = true
					break
				end
			end
			if didMerge then
				break
			end
		end
	end

	return merged, { inputCount = #parts, outputCount = #merged }
end

return table.freeze(FeatureGeometry)

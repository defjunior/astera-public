--!strict

local PersistentStructureResolver = {}

export type SurfaceSample = {
	y: number,
	isVoid: boolean?,
	biomeName: string?,
}

export type ResolveContext = {
	islandLayout: any,
	cellSize: number,
	sampleSurface: (worldX: number, worldZ: number) -> SurfaceSample,
}

export type ResolvedDefinition = {
	id: string,
	sourceName: string,
	targetIsland: string,
	worldCFrame: CFrame,
	worldX: number,
	worldZ: number,
	padY: number,
	yawDegrees: number,
	terrainMode: "preserve" | "flatten",
	suppressProps: boolean,
	footprint: {
		shape: "rect" | "circle",
		rx: number?,
		rz: number?,
		r: number?,
		falloffStuds: number,
		yawDegrees: number,
	},
	diagnostics: {
		isVoid: boolean,
		minY: number,
		maxY: number,
		heightDelta: number,
		slopeDegrees: number,
		sampleCount: number,
		biomeName: string?,
		overlaps: { string },
	},
}

local VALID_SAMPLE_MODES = {
	center = true,
	highest = true,
	average = true,
}

function PersistentStructureResolver.ComputePivotForOrigin(
	sourcePivot: CFrame,
	sourceOrigin: CFrame,
	targetOrigin: CFrame
): CFrame
	return targetOrigin * sourceOrigin:Inverse() * sourcePivot
end

function PersistentStructureResolver.ComputeNormalizedPivot(sourcePivot: CFrame, sourceOrigin: CFrame): CFrame
	return sourceOrigin:Inverse() * sourcePivot
end

local function finiteNumber(value: any, fallback: number): number
	if type(value) == "number" and value == value and value > -math.huge and value < math.huge then
		return value
	end
	return fallback
end

local function normalizeFootprint(raw: any)
	raw = if type(raw) == "table" then raw else {}
	local shape = if raw.shape == "circle" then "circle" else "rect"
	local falloffStuds = math.max(0, finiteNumber(raw.falloffStuds, 50))
	if shape == "circle" then
		return {
			shape = "circle",
			r = math.max(1, finiteNumber(raw.radius or raw.r, 25)),
			falloffStuds = falloffStuds,
		}
	end

	local size = raw.size
	local sizeX = 50
	local sizeZ = 50
	if typeof(size) == "Vector2" then
		sizeX = size.X
		sizeZ = size.Y
	elseif type(size) == "table" then
		sizeX = finiteNumber(size.X or size.x or size[1], sizeX)
		sizeZ = finiteNumber(size.Y or size.y or size[2], sizeZ)
	end
	return {
		shape = "rect",
		rx = math.max(0.5, sizeX * 0.5),
		rz = math.max(0.5, sizeZ * 0.5),
		falloffStuds = falloffStuds,
	}
end

local function footprintSampleOffsets(footprint, yawDegrees: number): { Vector2 }
	local localOffsets = { Vector2.zero }
	if footprint.shape == "circle" then
		local r = footprint.r or 1
		localOffsets = {
			Vector2.zero,
			Vector2.new(r, 0),
			Vector2.new(-r, 0),
			Vector2.new(0, r),
			Vector2.new(0, -r),
			Vector2.new(r * 0.70710678, r * 0.70710678),
			Vector2.new(-r * 0.70710678, r * 0.70710678),
			Vector2.new(r * 0.70710678, -r * 0.70710678),
			Vector2.new(-r * 0.70710678, -r * 0.70710678),
		}
	else
		local rx = footprint.rx or 1
		local rz = footprint.rz or 1
		localOffsets = {
			Vector2.zero,
			Vector2.new(rx, rz),
			Vector2.new(rx, -rz),
			Vector2.new(-rx, rz),
			Vector2.new(-rx, -rz),
			Vector2.new(rx, 0),
			Vector2.new(-rx, 0),
			Vector2.new(0, rz),
			Vector2.new(0, -rz),
		}
	end

	local radians = math.rad(yawDegrees)
	local cosYaw = math.cos(radians)
	local sinYaw = math.sin(radians)
	local worldOffsets = table.create(#localOffsets)
	for index, offset in ipairs(localOffsets) do
		worldOffsets[index] = Vector2.new(
			offset.X * cosYaw - offset.Y * sinYaw,
			offset.X * sinYaw + offset.Y * cosYaw
		)
	end
	return worldOffsets
end

function PersistentStructureResolver.CreateWorldgenContext(state, islandLayout, heightSampler, worldGenConfig): ResolveContext
	local cellSize = math.max(1, finiteNumber(state and state.CellSize, 50))
	local gridSize = state and state.GridSize or Vector2.new(5000, 5000)
	local gridWidth = finiteNumber(gridSize.X, 5000)
	local gridHeight = finiteNumber(gridSize.Z or gridSize.Y, 5000)
	local islandPosition = state and state.IslandPosition or Vector3.zero

	return {
		islandLayout = islandLayout,
		cellSize = cellSize,
		sampleSurface = function(worldX: number, worldZ: number): SurfaceSample
			local chunkX = math.floor(((worldX - islandPosition.X) / cellSize) + gridWidth * 0.5 + 0.5)
			local chunkZ = math.floor(((worldZ - islandPosition.Z) / cellSize) + gridHeight * 0.5 + 0.5)
			local surfaceY, stats = heightSampler.computeSurfaceY(
				chunkX,
				chunkZ,
				1,
				state,
				worldGenConfig,
				nil
			)
			return {
				y = surfaceY,
				isVoid = stats and stats.isVoid == true,
				biomeName = stats and stats.biomeName or nil,
			}
		end,
	}
end

function PersistentStructureResolver.Resolve(definition: any, context: ResolveContext): (ResolvedDefinition?, string?)
	if type(definition) ~= "table" then
		return nil, "definition must be a table"
	end
	if type(definition.id) ~= "string" or definition.id == "" then
		return nil, "definition.id must be a non-empty string"
	end
	if type(definition.sourceName) ~= "string" or definition.sourceName == "" then
		return nil, ("definition '%s' has no sourceName"):format(definition.id)
	end
	if definition.enabled == false then
		return nil, "disabled"
	end

	local targetIsland = if type(definition.targetIsland) == "string" and definition.targetIsland ~= ""
		then definition.targetIsland
		else "Elydris"
	local islandSpec = context.islandLayout and context.islandLayout.getByName
		and context.islandLayout.getByName(targetIsland)
	if not islandSpec or typeof(islandSpec.center) ~= "Vector2" then
		return nil, ("definition '%s' targets unknown island '%s'"):format(definition.id, targetIsland)
	end

	local localXZ = definition.localXZ
	if typeof(localXZ) ~= "Vector2" then
		localXZ = Vector2.zero
	end
	local yawDegrees = finiteNumber(definition.yawDegrees, 0)
	local worldX = islandSpec.center.X + localXZ.X
	local worldZ = islandSpec.center.Y + localXZ.Y
	local footprint = normalizeFootprint(definition.footprint)
	local vertical = if type(definition.vertical) == "table" then definition.vertical else {}
	local verticalMode = if vertical.mode == "fixed" then "fixed" else "surface"
	local sampleMode = if VALID_SAMPLE_MODES[vertical.sample] then vertical.sample else "center"
	local offsetY = finiteNumber(vertical.offsetY, 0)

	local samples = {}
	local minY = math.huge
	local maxY = -math.huge
	local totalY = 0
	local anyVoid = false
	local biomeName = nil
	for _, offset in ipairs(footprintSampleOffsets(footprint, yawDegrees)) do
		local sample = context.sampleSurface(worldX + offset.X, worldZ + offset.Y)
		local sampleY = finiteNumber(sample and sample.y, 0)
		samples[#samples + 1] = sampleY
		minY = math.min(minY, sampleY)
		maxY = math.max(maxY, sampleY)
		totalY += sampleY
		anyVoid = anyVoid or (sample and sample.isVoid == true) or false
		biomeName = biomeName or (sample and sample.biomeName or nil)
	end

	local padY
	if verticalMode == "fixed" then
		padY = finiteNumber(vertical.fixedY, 0) + offsetY
	elseif sampleMode == "highest" then
		padY = maxY + offsetY
	elseif sampleMode == "average" then
		padY = (totalY / math.max(1, #samples)) + offsetY
	else
		padY = samples[1] + offsetY
	end

	local resolvedFootprint = {
		shape = footprint.shape,
		rx = footprint.rx,
		rz = footprint.rz,
		r = footprint.r,
		falloffStuds = footprint.falloffStuds,
		yawDegrees = yawDegrees,
	}
	local terrainMode = if definition.terrainMode == "flatten" then "flatten" else "preserve"
	local footprintSpan = if footprint.shape == "circle"
		then math.max(1, (footprint.r or 1) * 2)
		else math.max(1, math.min((footprint.rx or 1) * 2, (footprint.rz or 1) * 2))

	return {
		id = definition.id,
		sourceName = definition.sourceName,
		targetIsland = targetIsland,
		worldCFrame = CFrame.new(worldX, padY, worldZ) * CFrame.Angles(0, math.rad(yawDegrees), 0),
		worldX = worldX,
		worldZ = worldZ,
		padY = padY,
		yawDegrees = yawDegrees,
		terrainMode = terrainMode,
		suppressProps = definition.suppressProps ~= false,
		footprint = resolvedFootprint,
		diagnostics = {
			isVoid = anyVoid,
			minY = minY,
			maxY = maxY,
			heightDelta = maxY - minY,
			slopeDegrees = math.deg(math.atan((maxY - minY) / footprintSpan)),
			sampleCount = #samples,
			biomeName = biomeName,
			overlaps = {},
		},
	}, nil
end

function PersistentStructureResolver.ResolveAll(definitions: { any }, context: ResolveContext)
	local resolved = {}
	local diagnostics = {}
	local occupiedIds = {}

	for _, definition in ipairs(definitions or {}) do
		local item, err = PersistentStructureResolver.Resolve(definition, context)
		if item then
			if occupiedIds[item.id] then
				diagnostics[#diagnostics + 1] = ("duplicate definition id '%s'"):format(item.id)
			else
				occupiedIds[item.id] = true
				resolved[#resolved + 1] = item
			end
		elseif err ~= "disabled" then
			diagnostics[#diagnostics + 1] = err or "unknown resolver failure"
		end
	end

	table.sort(resolved, function(a, b)
		return a.id < b.id
	end)
	for firstIndex = 1, #resolved do
		local first = resolved[firstIndex]
		local firstRadius = if first.footprint.shape == "circle"
			then first.footprint.r or 1
			else math.sqrt((first.footprint.rx or 1) ^ 2 + (first.footprint.rz or 1) ^ 2)
		for secondIndex = firstIndex + 1, #resolved do
			local second = resolved[secondIndex]
			local secondRadius = if second.footprint.shape == "circle"
				then second.footprint.r or 1
				else math.sqrt((second.footprint.rx or 1) ^ 2 + (second.footprint.rz or 1) ^ 2)
			local deltaX = first.worldX - second.worldX
			local deltaZ = first.worldZ - second.worldZ
			if deltaX * deltaX + deltaZ * deltaZ < (firstRadius + secondRadius) ^ 2 then
				first.diagnostics.overlaps[#first.diagnostics.overlaps + 1] = second.id
				second.diagnostics.overlaps[#second.diagnostics.overlaps + 1] = first.id
				diagnostics[#diagnostics + 1] = ("definitions '%s' and '%s' have overlapping footprints"):format(
					first.id,
					second.id
				)
			end
		end
	end
	return resolved, diagnostics
end

function PersistentStructureResolver.ToFixedSite(resolved: ResolvedDefinition, state: any?)
	local chunkWorldOffsetX = nil
	local chunkWorldOffsetZ = nil
	if state then
		local cellSize = finiteNumber(state.CellSize, 50)
		local gridSize = state.GridSize or Vector3.new(5000, 5000, 5000)
		local islandPosition = state.IslandPosition or Vector3.zero
		chunkWorldOffsetX = islandPosition.X - finiteNumber(gridSize.X, 5000) * 0.5 * cellSize
		chunkWorldOffsetZ = islandPosition.Z - finiteNumber(gridSize.Y, 5000) * 0.5 * cellSize
	end
	return {
		id = resolved.id,
		wx = resolved.worldX,
		wz = resolved.worldZ,
		padY = resolved.padY,
		footprint = resolved.footprint,
		hardness = 3,
		priority = 1000,
		terrainMode = resolved.terrainMode,
		suppressProps = resolved.suppressProps,
		yawDegrees = resolved.yawDegrees,
		chunkWorldOffsetX = chunkWorldOffsetX,
		chunkWorldOffsetZ = chunkWorldOffsetZ,
	}
end

return PersistentStructureResolver

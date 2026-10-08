-- Partial source showcase, revised October 8, 2026.
-- Terrain generation interface. Creates and maintains terrain geometry; generation/merge/culling implementation is private.
-- Containment transforms a point into volume-local coordinates, then checks extents. Part containment tests corners. Cleanup/tag utilities are real; merge/cull/render/accessory policy is omitted.
-- Real excerpts are marked. Other named interfaces are non-working stubs, not a replacement pipeline.

local TerrainModule = {}

local abs, min, max = math.abs, math.min, math.max

-- Real source excerpt: aabbFromPart
local function aabbFromPart(p: BasePart)
	local cf, sz = p.CFrame, p.Size
	local hx, hy, hz = sz.X*0.5, sz.Y*0.5, sz.Z*0.5
	local rx, ry, rz = cf.RightVector.X, cf.RightVector.Y, cf.RightVector.Z
	local ux, uy, uz = cf.UpVector.X,    cf.UpVector.Y,    cf.UpVector.Z
	local lx, ly, lz = cf.LookVector.X,  cf.LookVector.Y,  cf.LookVector.Z
	local ex = abs(rx)*hx + abs(ux)*hy + abs(lx)*hz
	local ey = abs(ry)*hx + abs(uy)*hy + abs(ly)*hz
	local ez = abs(rz)*hx + abs(uz)*hy + abs(lz)*hz
	local cx, cy, cz = cf.X, cf.Y, cf.Z
	return Vector3.new(cx-ex, cy-ey, cz-ez), Vector3.new(cx+ex, cy+ey, cz+ez), Vector3.new(ex*2, ey*2, ez*2)
end

-- Real source excerpt: aabbOverlap
local function aabbOverlap(minA: Vector3, maxA: Vector3, minB: Vector3, maxB: Vector3)
	local ox = max(0, min(maxA.X, maxB.X) - max(minA.X, minB.X))
	local oy = max(0, min(maxA.Y, maxB.Y) - max(minA.Y, minB.Y))
	local oz = max(0, min(maxA.Z, maxB.Z) - max(minA.Z, minB.Z))
	return ox, oy, oz, (ox>0 and oy>0 and oz>0)
end

-- Real source excerpt: allCornersInside
local function allCornersInside(minS: Vector3, maxS: Vector3, minB: Vector3, maxB: Vector3, eps: number)
	local corners = {
		Vector3.new(minS.X, minS.Y, minS.Z), Vector3.new(minS.X, minS.Y, maxS.Z),
		Vector3.new(minS.X, maxS.Y, minS.Z), Vector3.new(minS.X, maxS.Y, maxS.Z),
		Vector3.new(maxS.X, minS.Y, minS.Z), Vector3.new(maxS.X, minS.Y, maxS.Z),
		Vector3.new(maxS.X, maxS.Y, minS.Z), Vector3.new(maxS.X, maxS.Y, maxS.Z),
	}
	local bx0, by0, bz0 = minB.X - eps, minB.Y - eps, minB.Z - eps
	local bx1, by1, bz1 = maxB.X + eps, maxB.Y + eps, maxB.Z + eps
	for _,c in ipairs(corners) do
		if c.X < bx0 or c.X > bx1 or c.Y < by0 or c.Y > by1 or c.Z < bz0 or c.Z > bz1 then
			return false
		end
	end
	return true
end

-- Real source excerpt: hasAnyTag
local function hasAnyTag(inst: Instance, tags: {string}?): boolean
	if not tags or #tags == 0 then return false end
	for _,t in ipairs(tags) do if CollectionService:HasTag(inst, t) then return true end end
	return false
end

-- Contract: Terrain generation interface. Implementation intentionally unavailable.
local CollectionService = game:GetService("CollectionService")

-- Real source excerpt: TerrainModule.IsPointInVolume
function TerrainModule.IsPointInVolume(point: Vector3, volumeCenter: CFrame, volumeSize: Vector3): boolean
	local volumeSpacePoint = volumeCenter:PointToObjectSpace(point)
	return volumeSpacePoint.X >= -volumeSize.X / 2
		and volumeSpacePoint.X <= volumeSize.X / 2
		and volumeSpacePoint.Y >= -volumeSize.Y / 2
		and volumeSpacePoint.Y <= volumeSize.Y / 2
		and volumeSpacePoint.Z >= -volumeSize.Z / 2
		and volumeSpacePoint.Z <= volumeSize.Z / 2
end

-- Real source excerpt: TerrainModule.IsPartInBoundary
function TerrainModule.IsPartInBoundary(part: BasePart, boundaryPart: BasePart, addedZone: Vector3 | nil): boolean
	for x = -1, 1, 2 do
		for z = -1, 1, 2 do
			for y = -1, 1, 2 do
				local corner = part.Position
					+ part.Size.X / 2 * x * part.CFrame.RightVector
					+ part.Size.Y / 2 * y * part.CFrame.UpVector
					+ part.Size.Z / 2 * z * part.CFrame.LookVector

				if not TerrainModule.IsPointInVolume(corner, boundaryPart.CFrame, boundaryPart.Size + (addedZone or Vector3.new())) then
					return false
				end
			end
		end
	end
	return true
end

-- Contract: Terrain generation interface. Implementation intentionally unavailable.
function TerrainModule.GetRandomPointAlongRandomEdge(random, pointA, pointB, pointC, pointD, edgeToAvoid, neighborSurfaceY, layerY, exposureThreshold)
	-- full method is omitted
end

-- Contract: Terrain generation interface. Implementation intentionally unavailable.
function TerrainModule.CreateRockDressingPart(state)
	-- full method is omitted
end

-- Contract: Terrain generation interface. Implementation intentionally unavailable.
function TerrainModule.UpdateTerrainAccessories(random, main, state, accessories, recursion_depth, edgeToAvoid, parents)
	-- full method is omitted
end

-- Contract: Terrain generation interface. Implementation intentionally unavailable.
function TerrainModule.CreateTerrainAccessories(main, state, old_state, group)
	-- full method is omitted
end

-- Real source excerpt: TerrainModule.ClearTerrainAccessories
function TerrainModule.ClearTerrainAccessories(model: Model)
	local accessories = model:FindFirstChild("Accessories")

	if accessories then
		for _, accessory in ipairs(accessories:GetChildren()) do
			accessory:Destroy()
		end
	end
end

-- Real source excerpt: TerrainModule.SolidifyTerrain
function TerrainModule.SolidifyTerrain(selections)
	for _, selection in pairs(selections) do
		local model = selection.Parent
		if not model or not model:IsA("Model") then continue end

		for _, part in ipairs(model:GetChildren()) do
			if CollectionService:HasTag(part, "Terrain") then
				CollectionService:RemoveTag(part, "Terrain")
			end
		end

		CollectionService:RemoveTag(model, "Terrain")
		model.PrimaryPart = nil
	end
end

-- Contract: Terrain generation interface. Implementation intentionally unavailable.
function TerrainModule.CullGroup(group, opts)
	-- full method is omitted
end

-- Contract: Terrain generation interface. Implementation intentionally unavailable.
function TerrainModule.GreedyMergeGroup(group, opts)
	-- full method is omitted
end

-- Contract: Terrain generation interface. Implementation intentionally unavailable.
function TerrainModule.RenderTerrainChunk(startPos, endPos, state, height, caveConfig, renderRandom, renderParent, deferPublish)
	-- full method is omitted
end

-- Contract: Terrain generation interface. Implementation intentionally unavailable.
function TerrainModule.GenerateCavesPerlinWorms(islandModel, state)
	-- full method is omitted
end

-- Contract: Terrain generation interface. Implementation intentionally unavailable.
function TerrainModule.CreateCaveAtPosition(position, radius, parentModel)
	-- full method is omitted
end

return TerrainModule

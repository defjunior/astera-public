-- Partial source showcase, revised October 8, 2026.
-- World-generation entrypoint. Owns startup and integration boundaries; orchestration implementation is private.
-- This boundary shows where requests enter and results leave the subsystem.
-- The private policy decides what work to accept and when to publish it; no execution recipe is exposed.
-- Real local helpers are shown; remaining interfaces are documentation stubs, not a working replacement.

-- Original runtime script intentionally does not start generation here.
local abs, min, max = math.abs, math.min, math.max

-- Real source excerpt: aabbFromPart
local function aabbFromPart(p: BasePart)
	-- Compute world AABB from oriented part quickly:
	-- extents = |R|*hx + |U|*hy + |L|*hz (componentwise)
	local cf, sz = p.CFrame, p.Size
	local hx, hy, hz = sz.X*0.5, sz.Y*0.5, sz.Z*0.5
	local rx, ry, rz = cf.RightVector.X, cf.RightVector.Y, cf.RightVector.Z
	local ux, uy, uz = cf.UpVector.X,    cf.UpVector.Y,    cf.UpVector.Z
	local lx, ly, lz = cf.LookVector.X,  cf.LookVector.Y,  cf.LookVector.Z
	local ex = abs(rx)*hx + abs(ux)*hy + abs(lx)*hz
	local ey = abs(ry)*hx + abs(uy)*hy + abs(ly)*hz
	local ez = abs(rz)*hx + abs(uz)*hy + abs(lz)*hz
	local cx, cy, cz = cf.X, cf.Y, cf.Z
	return
		Vector3.new(cx - ex, cy - ey, cz - ez), -- min
	Vector3.new(cx + ex, cy + ey, cz + ez), -- max
	ex, ey, ez
end

-- Real source excerpt: aabbOverlap
local function aabbOverlap(minA: Vector3, maxA: Vector3, minB: Vector3, maxB: Vector3)
	local ox = math.max(0, math.min(maxA.X, maxB.X) - math.max(minA.X, minB.X))
	local oy = math.max(0, math.min(maxA.Y, maxB.Y) - math.max(minA.Y, minB.Y))
	local oz = math.max(0, math.min(maxA.Z, maxB.Z) - math.max(minA.Z, minB.Z))
	return ox, oy, oz, (ox>0 and oy>0 and oz>0)
end

-- Real source excerpt: GetRandomPointInArea
local function GetRandomPointInArea(areaSize, centerPosition, random)
	local x = random:NextNumber(centerPosition.X - areaSize.X/2, centerPosition.X + areaSize.X/2)
	local z = random:NextNumber(centerPosition.Z - areaSize.Z/2, centerPosition.Z + areaSize.Z/2)
	return Vector3.new(x, centerPosition.Y, z)
end

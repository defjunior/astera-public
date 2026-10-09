--!strict

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local PersistentStructureReservations = {}

local RESERVATION_FOLDER_NAME = "SiteReservations"
local RESERVATION_ATTRIBUTE = "PersistentStructureReservation"

local function ensureReservationFolder(): Folder
	local ignore = Workspace:FindFirstChild("Ignore")
	if not ignore then
		ignore = Instance.new("Folder")
		ignore.Name = "Ignore"
		ignore.Parent = Workspace
	end

	local existing = ignore:FindFirstChild(RESERVATION_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = RESERVATION_FOLDER_NAME
	folder.Parent = ignore
	return folder
end

function PersistentStructureReservations.Clear()
	local ignore = Workspace:FindFirstChild("Ignore")
	local folder = ignore and ignore:FindFirstChild(RESERVATION_FOLDER_NAME)
	if not folder then
		return
	end
	for _, child in ipairs(folder:GetChildren()) do
		if child:GetAttribute(RESERVATION_ATTRIBUTE) == true then
			child:Destroy()
		end
	end
end

function PersistentStructureReservations.CreateMarkers(
	folder: Instance,
	resolvedDefinitions: { any },
	archivable: boolean?
)
	local placed = 0

	for _, resolved in ipairs(resolvedDefinitions or {}) do
		if resolved.suppressProps ~= false then
			local footprint = resolved.footprint or {}
			local sizeX
			local sizeZ
			if footprint.shape == "circle" then
				local radius = math.max(0, tonumber(footprint.r) or 0)
				sizeX = radius * 2
				sizeZ = radius * 2
			else
				sizeX = math.max(0, tonumber(footprint.rx) or 0) * 2
				sizeZ = math.max(0, tonumber(footprint.rz) or 0) * 2
			end

			if sizeX > 0 and sizeZ > 0 then
				local marker = Instance.new("Part")
				marker.Name = "Persistent_" .. tostring(resolved.id)
				marker.Anchored = true
				marker.CanCollide = false
				marker.CanQuery = true
				marker.CanTouch = false
				marker.CastShadow = false
				marker.Transparency = 1
				marker.Archivable = archivable ~= false
				marker.Size = Vector3.new(sizeX, 400, sizeZ)
				marker.CFrame = CFrame.new(resolved.worldX, resolved.padY, resolved.worldZ)
					* CFrame.Angles(0, math.rad(resolved.yawDegrees or 0), 0)
				marker:SetAttribute(RESERVATION_ATTRIBUTE, true)
				marker:SetAttribute("SiteID", resolved.id)
				marker:SetAttribute("FootprintShape", footprint.shape)
				marker:SetAttribute("FootprintRadius", footprint.r)
				marker:SetAttribute("FootprintHalfX", footprint.rx)
				marker:SetAttribute("FootprintHalfZ", footprint.rz)
				CollectionService:AddTag(marker, "SiteReservation")
				marker.Parent = folder
				placed += 1
			end
		end
	end

	return placed
end

function PersistentStructureReservations.Refresh(resolvedDefinitions: { any })
	PersistentStructureReservations.Clear()
	local folder = ensureReservationFolder()
	return PersistentStructureReservations.CreateMarkers(folder, resolvedDefinitions, true)
end

return PersistentStructureReservations

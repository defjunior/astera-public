local RoomTypeTypes = require(script.Parent.RoomTypeTypes)

local RoomTypeDB = {}

local C = RoomTypeTypes.Category
local F = RoomTypeTypes.FootprintFamily

local roomTypes = {
 -- EXCLUDED: authored content/settings table, at the owner's request.
 -- General structure: map<string, room-type record>: id/category/tags, pattern identifiers, placement/connectivity rules, progression roles and frequency settings
 -- Intentionally empty, not a runnable replacement. See CONTENT-SCHEMAS.md.
}

function RoomTypeDB.Get(roomTypeId)
	return roomTypes[roomTypeId]
end

function RoomTypeDB.GetAll()
	return roomTypes
end

function RoomTypeDB.ListIds()
	local ids = {}
	for id in pairs(roomTypes) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	return ids
end

function RoomTypeDB.Validate()
	local issues = {}
	for _, roomType in pairs(roomTypes) do
		local ok, roomIssues = RoomTypeTypes.Validate(roomType)
		if not ok then
			for _, issue in ipairs(roomIssues) do
				issues[#issues + 1] = issue
			end
		end
	end
	return #issues == 0, issues
end

return RoomTypeDB

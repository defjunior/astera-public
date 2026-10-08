local DungeonDebug = {}

function DungeonDebug.BuildRoomBoxes(rooms)
	local boxes = {}
	for _, room in ipairs(rooms) do
		table.insert(boxes, {
			id = room.id,
			min = room.min,
			max = room.max,
			center = room.center,
		})
	end
	return boxes
end

function DungeonDebug.BuildGraphLines(edges, roomById)
	local lines = {}
	for _, edge in ipairs(edges) do
		local roomA = roomById[edge.roomAId]
		local roomB = roomById[edge.roomBId]
		if roomA and roomB then
			table.insert(lines, {
				roomAId = edge.roomAId,
				roomBId = edge.roomBId,
				from = roomA.center,
				to = roomB.center,
				weight = edge.weight,
			})
		end
	end
	return lines
end

function DungeonDebug.BuildPathLines(carvedPaths)
	local lines = {}
	for _, path in ipairs(carvedPaths) do
		if path.success and #path.steps > 1 then
			for i = 2, #path.steps do
				table.insert(lines, {
					from = path.steps[i - 1].position,
					to = path.steps[i].position,
					roomAId = path.roomAId,
					roomBId = path.roomBId,
				})
			end
		end
	end
	return lines
end

return DungeonDebug

local DungeonTypes = require(script.Parent.DungeonTypes)

local RoomGraphBuilder = {}

local EPSILON = 1e-6

local function edgeKey(roomAId, roomBId)
	if roomAId < roomBId then
		return roomAId .. ":" .. roomBId
	end
	return roomBId .. ":" .. roomAId
end

local function edgeSort(a, b)
	if math.abs(a.weight - b.weight) > EPSILON then
		return a.weight < b.weight
	end
	if a.roomAId ~= b.roomAId then
		return a.roomAId < b.roomAId
	end
	return a.roomBId < b.roomBId
end

local function makeUnionFind(roomIds)
	local parent = {}
	local rank = {}
	for _, id in ipairs(roomIds) do
		parent[id] = id
		rank[id] = 0
	end

	local function find(id)
		local current = id
		while parent[current] ~= current do
			parent[current] = parent[parent[current]]
			current = parent[current]
		end
		return current
	end

	local function union(a, b)
		local rootA = find(a)
		local rootB = find(b)
		if rootA == rootB then
			return false
		end

		if rank[rootA] < rank[rootB] then
			parent[rootA] = rootB
		elseif rank[rootA] > rank[rootB] then
			parent[rootB] = rootA
		else
			parent[rootB] = rootA
			rank[rootA] = rank[rootA] + 1
		end

		return true
	end

	return {
		find = find,
		union = union,
	}
end

local function weightedRoomDistance(a, b, verticalWeight)
	return DungeonTypes.WeightedDistance(a.center, b.center, verticalWeight)
end

local function buildAllPairEdges(rooms, verticalWeight)
	local edges = {}
	for i = 1, #rooms do
		for j = i + 1, #rooms do
			local roomA = rooms[i]
			local roomB = rooms[j]
			table.insert(edges, {
				roomAId = roomA.id,
				roomBId = roomB.id,
				weight = weightedRoomDistance(roomA, roomB, verticalWeight),
			})
		end
	end
	table.sort(edges, edgeSort)
	return edges
end

local function buildProximityEdges(rooms, config)
	if #rooms <= 1 then
		return {}
	end

	local k = math.max(1, math.min(config.graphNeighborCount, #rooms - 1))
	local edgeMap = {}

	for i, room in ipairs(rooms) do
		local neighbors = {}
		for j, other in ipairs(rooms) do
			if i ~= j then
				table.insert(neighbors, {
					roomAId = room.id,
					roomBId = other.id,
					weight = weightedRoomDistance(room, other, config.graphVerticalWeight),
					otherRoomId = other.id,
				})
			end
		end

		table.sort(neighbors, function(a, b)
			if math.abs(a.weight - b.weight) > EPSILON then
				return a.weight < b.weight
			end
			return a.otherRoomId < b.otherRoomId
		end)

		for n = 1, math.min(k, #neighbors) do
			local candidate = neighbors[n]
			local key = edgeKey(candidate.roomAId, candidate.roomBId)
			if not edgeMap[key] then
				local minId = math.min(candidate.roomAId, candidate.roomBId)
				local maxId = math.max(candidate.roomAId, candidate.roomBId)
				edgeMap[key] = {
					roomAId = minId,
					roomBId = maxId,
					weight = candidate.weight,
				}
			end
		end
	end

	local keys = {}
	for key in pairs(edgeMap) do
		table.insert(keys, key)
	end
	table.sort(keys)

	local edges = {}
	for _, key in ipairs(keys) do
		table.insert(edges, edgeMap[key])
	end

	table.sort(edges, edgeSort)
	return edges
end

local function buildRoomById(rooms)
	local roomById = {}
	for _, room in ipairs(rooms) do
		roomById[room.id] = room
	end
	return roomById
end

local function isInterFloorEdge(edge, roomById)
	local roomA = roomById[edge.roomAId]
	local roomB = roomById[edge.roomBId]
	if not roomA or not roomB then
		return false
	end
	return roomA.center.y ~= roomB.center.y
end

function RoomGraphBuilder.Build(rooms, config, rng)
	if #rooms <= 1 then
		return {
			graphEdges = {},
			mstEdges = {},
			extraEdges = {},
			finalEdges = {},
			activeRoomIds = {},
			culledRoomIds = (#rooms == 1) and { rooms[1].id } or {},
		}
	end

	local roomIds = {}
	for _, room in ipairs(rooms) do
		table.insert(roomIds, room.id)
	end
	table.sort(roomIds)

	local proximityEdges = buildProximityEdges(rooms, config)
	local allPairEdges = buildAllPairEdges(rooms, config.graphVerticalWeight)

	local graphEdgeMap = {}
	for _, edge in ipairs(proximityEdges) do
		graphEdgeMap[edgeKey(edge.roomAId, edge.roomBId)] = edge
	end

	local uf = makeUnionFind(roomIds)
	local mstEdges = {}

	for _, edge in ipairs(proximityEdges) do
		if uf.union(edge.roomAId, edge.roomBId) then
			table.insert(mstEdges, edge)
		end
	end

	if #mstEdges < (#rooms - 1) then
		for _, edge in ipairs(allPairEdges) do
			if uf.union(edge.roomAId, edge.roomBId) then
				table.insert(mstEdges, edge)
				local key = edgeKey(edge.roomAId, edge.roomBId)
				if not graphEdgeMap[key] then
					graphEdgeMap[key] = edge
				end
				if #mstEdges >= (#rooms - 1) then
					break
				end
			end
		end
	end

	local graphEdges = {}
	local graphKeys = {}
	for key in pairs(graphEdgeMap) do
		table.insert(graphKeys, key)
	end
	table.sort(graphKeys)
	for _, key in ipairs(graphKeys) do
		table.insert(graphEdges, graphEdgeMap[key])
	end
	table.sort(graphEdges, edgeSort)

	local mstEdgeMap = {}
	for _, edge in ipairs(mstEdges) do
		mstEdgeMap[edgeKey(edge.roomAId, edge.roomBId)] = true
	end

	local nonMstEdges = {}
	for _, edge in ipairs(graphEdges) do
		if not mstEdgeMap[edgeKey(edge.roomAId, edge.roomBId)] then
			table.insert(nonMstEdges, edge)
		end
	end
	table.sort(nonMstEdges, edgeSort)

	local labyrinthBias = math.clamp(config.labyrinthBias or 0, 0, 1)
	local loopChanceBoost = (config.loopChanceBoostPerBias or 0.35) * labyrinthBias
	local effectiveExtraEdgeChance = math.clamp(config.extraEdgeChance + loopChanceBoost, 0, 1)

	local targetExtraLoops = math.max(0, math.floor((#rooms - 1) * labyrinthBias * 0.75 + 0.5))
	if type(config.minExtraLoopEdges) == "number" then
		targetExtraLoops = math.max(targetExtraLoops, math.max(0, math.floor(config.minExtraLoopEdges)))
	end
	local maxExtraLoopEdges = math.huge
	if type(config.maxExtraLoopEdges) == "number" then
		maxExtraLoopEdges = math.max(0, math.floor(config.maxExtraLoopEdges))
	end
	targetExtraLoops = math.min(targetExtraLoops, maxExtraLoopEdges)
	targetExtraLoops = math.min(targetExtraLoops, #nonMstEdges)

	local extraEdges = {}
	local extraEdgeSet = {}
	for _, edge in ipairs(nonMstEdges) do
		if #extraEdges >= maxExtraLoopEdges then
			break
		end
		if rng:NextNumber() < effectiveExtraEdgeChance then
			table.insert(extraEdges, edge)
			extraEdgeSet[edgeKey(edge.roomAId, edge.roomBId)] = true
		end
	end

	if #extraEdges < targetExtraLoops then
		for _, edge in ipairs(nonMstEdges) do
			if #extraEdges >= targetExtraLoops then
				break
			end
			local key = edgeKey(edge.roomAId, edge.roomBId)
			if not extraEdgeSet[key] then
				table.insert(extraEdges, edge)
				extraEdgeSet[key] = true
			end
		end
	end

	table.sort(extraEdges, edgeSort)

	local finalEdges = {}
	for _, edge in ipairs(mstEdges) do
		table.insert(finalEdges, edge)
	end
	for _, edge in ipairs(extraEdges) do
		table.insert(finalEdges, edge)
	end

	local minInterFloorEdges = math.max(0, math.floor(config.minInterFloorEdges or 0))
	if minInterFloorEdges > 0 then
		local roomById = buildRoomById(rooms)
		local existing = {}
		local interFloorCount = 0

		for _, edge in ipairs(finalEdges) do
			existing[edgeKey(edge.roomAId, edge.roomBId)] = true
			if isInterFloorEdge(edge, roomById) then
				interFloorCount += 1
			end
		end

		if interFloorCount < minInterFloorEdges then
			local candidateMap = {}

			local function pushCandidate(edge)
				local key = edgeKey(edge.roomAId, edge.roomBId)
				if existing[key] then
					return
				end
				if not isInterFloorEdge(edge, roomById) then
					return
				end
				if not candidateMap[key] then
					candidateMap[key] = edge
				end
			end

			for _, edge in ipairs(graphEdges) do
				pushCandidate(edge)
			end
			for _, edge in ipairs(allPairEdges) do
				pushCandidate(edge)
			end

			local candidates = {}
			for _, edge in pairs(candidateMap) do
				table.insert(candidates, edge)
			end
			table.sort(candidates, edgeSort)

			for _, edge in ipairs(candidates) do
				if interFloorCount >= minInterFloorEdges then
					break
				end
				local key = edgeKey(edge.roomAId, edge.roomBId)
				if not existing[key] then
					existing[key] = true
					table.insert(finalEdges, edge)
					interFloorCount += 1
				end
			end
		end
	end

	table.sort(finalEdges, edgeSort)

	local degree = {}
	for _, edge in ipairs(finalEdges) do
		degree[edge.roomAId] = (degree[edge.roomAId] or 0) + 1
		degree[edge.roomBId] = (degree[edge.roomBId] or 0) + 1
	end

	local activeRoomIds = {}
	local culledRoomIds = {}
	for _, id in ipairs(roomIds) do
		if (degree[id] or 0) > 0 then
			table.insert(activeRoomIds, id)
		else
			table.insert(culledRoomIds, id)
		end
	end

	return {
		graphEdges = graphEdges,
		mstEdges = mstEdges,
		extraEdges = extraEdges,
		finalEdges = finalEdges,
		activeRoomIds = activeRoomIds,
		culledRoomIds = culledRoomIds,
	}
end

return RoomGraphBuilder

--[[
	BinaryHeap

	Min-heap priority queue used by the A* pathfinder in HallwayCarver.
	Uses parallel arrays (keys + priorities) to avoid per-element table
	allocation, and iterative sift operations to avoid recursion overhead.
]]

local BinaryHeap = {}
BinaryHeap.__index = BinaryHeap

function BinaryHeap:new()
	local obj = {
		_keys = {},
		_priorities = {},
		_size = 0,
	}
	return setmetatable(obj, self)
end

function BinaryHeap:insert(key, priority)
	local size = self._size + 1
	self._size = size
	local keys = self._keys
	local priorities = self._priorities

	-- Iterative sift-up: bubble the new element toward the root
	local index = size
	while index > 1 do
		local parentIndex = math.floor(index / 2)
		if priority < priorities[parentIndex] then
			keys[index] = keys[parentIndex]
			priorities[index] = priorities[parentIndex]
			index = parentIndex
		else
			break
		end
	end
	keys[index] = key
	priorities[index] = priority
end

function BinaryHeap:pop()
	local size = self._size
	if size == 0 then
		return nil
	end

	local keys = self._keys
	local priorities = self._priorities
	local rootKey = keys[1]

	if size == 1 then
		keys[1] = nil
		priorities[1] = nil
		self._size = 0
		return rootKey
	end

	-- Move last element into root slot
	local lastKey = keys[size]
	local lastPriority = priorities[size]
	keys[size] = nil
	priorities[size] = nil
	size -= 1
	self._size = size

	-- Iterative sift-down: push the replacement toward the leaves
	local index = 1
	while true do
		local leftIndex = 2 * index
		if leftIndex > size then
			break
		end

		local rightIndex = leftIndex + 1
		local smallestIndex = leftIndex
		local smallestPriority = priorities[leftIndex]

		if rightIndex <= size then
			local rightPriority = priorities[rightIndex]
			if rightPriority < smallestPriority then
				smallestIndex = rightIndex
				smallestPriority = rightPriority
			end
		end

		if lastPriority <= smallestPriority then
			break
		end

		keys[index] = keys[smallestIndex]
		priorities[index] = priorities[smallestIndex]
		index = smallestIndex
	end

	keys[index] = lastKey
	priorities[index] = lastPriority
	return rootKey
end

function BinaryHeap:isEmpty()
	return self._size == 0
end

return BinaryHeap

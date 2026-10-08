-- Bounded history and deterministic control selection. No engine dependencies.
local Timeline = {}
Timeline.__index = Timeline

function Timeline.new(capacity)
	assert(capacity >= 2, "history needs at least two samples")
	return setmetatable({ capacity = capacity, count = 0, head = 0, samples = {} }, Timeline)
end

function Timeline:Record(time, value)
	local latest = self.samples[self.head]
	assert(not latest or time >= latest.time, "history timestamps must be monotonic")
	self.head = self.head % self.capacity + 1
	self.samples[self.head] = { time = time, value = value }
	self.count = math.min(self.count + 1, self.capacity)
end

function Timeline:Sample(time)
	if self.count == 0 then return nil end
	local oldest = (self.head - self.count) % self.capacity + 1
	local previous = self.samples[oldest]
	if time <= previous.time then return previous.value, previous.value, 0, previous.time end
	for offset = 1, self.count - 1 do
		local sample = self.samples[(oldest + offset - 1) % self.capacity + 1]
		if sample.time >= time then
			local span = sample.time - previous.time
			return previous.value, sample.value, span > 0 and (time - previous.time) / span or 0, time
		end
		previous = sample
	end
	return previous.value, previous.value, 0, previous.time
end

function Timeline:Truncate(time)
	local kept = {}
	for offset = 1, self.count do
		local sample = self.samples[(self.head - self.count + offset - 1) % self.capacity + 1]
		if sample.time <= time then table.insert(kept, sample) end
	end
	self.samples, self.count, self.head = kept, #kept, #kept
end

function Timeline.Select(controls, now, matches)
	local winner
	for _, control in pairs(controls) do
		if now < control.endsAt and matches(control) then
			if not winner or control.priority > winner.priority
				or (control.priority == winner.priority and control.rate == 0 and winner.rate ~= 0)
				or (control.priority == winner.priority and (control.rate == 0) == (winner.rate == 0) and control.id > winner.id) then
				winner = control
			end
		end
	end
	return winner
end

return Timeline

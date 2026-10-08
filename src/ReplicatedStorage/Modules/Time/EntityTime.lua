-- Gameplay clocks advance only forwards. Rewind is history playback, never negative task time.
local EntityTime = {}
local named = setmetatable({}, { __mode = "v" })
local clocks = setmetatable({}, { __mode = "k" })
local owners = setmetatable({}, { __mode = "k" })
local visualRates = setmetatable({}, { __mode = "k" })
local visualClocks = setmetatable({}, { __mode = "k" })

function EntityTime.Resolve(entity)
	if type(entity) == "string" then return named[entity] end
	if type(entity) == "table" then entity = entity.CharacterObject end
	while typeof(entity) == "Instance" do
		if entity:GetAttribute("TimeEntity") == true then return entity end
		if owners[entity] then
			local owner = owners[entity]
			if type(owner) == "string" then return named[owner] end
			return owner
		end
		entity = entity.Parent
	end
	return nil
end

function EntityTime.Bind(instance, owner)
	owners[instance] = EntityTime.Resolve(owner) or owner
end

function EntityTime.GetRate(entity)
	entity = EntityTime.Resolve(entity)
	if not entity then return 1 end
	return entity:GetAttribute("TimeRate") or 1
end

function EntityTime.Now(entity)
	local now = workspace:GetServerTimeNow()
	entity = EntityTime.Resolve(entity)
	if not entity then return now end
	local anchor = entity:GetAttribute("TimeClockAnchor")
	local clock = clocks[entity]
	if anchor and (not clock or clock.anchor ~= anchor) then
		local logical, wall, rate = string.match(anchor, "^([^,]+),([^,]+),([^,]+)$")
		if tonumber(logical) and tonumber(wall) and tonumber(rate) then
			clock = { time = tonumber(logical), wall = tonumber(wall), rate = math.max(0, tonumber(rate)), anchor = anchor }
			clocks[entity] = clock
		end
	end
	if not clock then return now end
	return clock.time + math.max(0, now - clock.wall) * clock.rate
end

function EntityTime.SetRate(entity, rate)
	local logical = EntityTime.Now(entity)
	local now = workspace:GetServerTimeNow()
	entity:SetAttribute("TimeRate", rate)
	-- One atomic replicated value avoids mixing a new rate with an old clock origin.
	entity:SetAttribute("TimeClockAnchor", string.format("%.9f,%.9f,%.9f", logical, now, math.max(0, rate)))
end

function EntityTime.GetVisualRate(entity)
	entity = EntityTime.Resolve(entity)
	return entity and (visualRates[entity] or EntityTime.GetRate(entity)) or 1
end

function EntityTime.VisualNow(entity)
	local now = workspace:GetServerTimeNow()
	entity = EntityTime.Resolve(entity)
	if not entity then return now end
	local clock = visualClocks[entity]
	if not clock then clock = { wall = now, time = now, rate = EntityTime.GetVisualRate(entity) }; visualClocks[entity] = clock end
	clock.time += math.max(0, now - clock.wall) * math.max(0, clock.rate)
	clock.wall, clock.rate = now, EntityTime.GetVisualRate(entity)
	return clock.time
end

function EntityTime.SetVisualRate(entity, rate)
	EntityTime.VisualNow(entity)
	visualRates[entity] = rate
	local clock = visualClocks[entity]
	if clock then clock.rate = EntityTime.GetVisualRate(entity) end
end

function EntityTime.Register(model)
	named[model.Name] = model
end

function EntityTime.Wait(entity, duration, visual)
	local clock = visual and EntityTime.VisualNow or EntityTime.Now
	local started = clock(entity)
	local deadline = started + math.max(0, duration or 1 / 60)
	repeat task.wait() until clock(entity) >= deadline
	return clock(entity) - started
end

return EntityTime

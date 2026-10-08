-- Omitted: authored time-control sound asset dependency.
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EntityTime = require(ReplicatedStorage.Modules.Time.EntityTime)
local VisualOwnership = require(ReplicatedStorage.Modules.Utility.VisualOwnership)
local EffectTime = require(ReplicatedStorage.Modules.Time.EffectTime)
local Timeline = require(ReplicatedStorage.Modules.Time.Timeline)
local Presentation = require(ReplicatedStorage.Modules.Time.Presentation)
local TickService = require(game.ServerScriptService.Services.Core.TickService)
local Movement = require(ReplicatedStorage.Modules.Utility.AsteraMovementController)

local Service = { Name = "TimeControlService", entities = {}, controls = {}, sequence = 0 }
local HISTORY_HZ, HISTORY_SECONDS = 30, 10
local DEFAULT_RADIUS, MAX_RATE, MAX_DURATION = 40, 4, 30

local function modelOf(entity)
	return type(entity) == "table" and entity.CharacterObject or entity
end

local function rootOf(model)
	if typeof(model) ~= "Instance" or not model.Parent or not (model:IsA("Model") or model:IsA("BasePart")) then return nil end
	return model:IsA("BasePart") and model or model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

local function number(value, fallback, low, high)
	if value == nil then return fallback end
	assert(type(value) == "number" and value == value and math.abs(value) < math.huge, "TimeControl expects finite numbers")
	return math.clamp(value, low, high)
end

local function instanceSet(list)
	local set = {}
	for _, entity in ipairs(list or {}) do
		local model = modelOf(entity)
		assert(typeof(model) == "Instance", "TimeControl target must be an entity or instance")
		set[model] = true
	end
	return set
end

function Service:Register(entity, owner, adapter)
	local model = modelOf(entity)
	local root = rootOf(model)
	if not root then return nil end
	local entry = self.entities[model]
	if not entry then
		entry = { model = model, root = root, owner = modelOf(owner), history = Timeline.new(HISTORY_HZ * HISTORY_SECONDS), rate = 1, nextSample = 0 }
		self.entities[model] = entry
		model:SetAttribute("TimeEntity", true)
		model:SetAttribute("TimeRate", 1)
		EntityTime.Register(model)
		CollectionService:AddTag(model, "TimeEntity")
	end
	if adapter and entry.adapter ~= adapter then
		entry.adapter = adapter
		entry.history = Timeline.new(HISTORY_HZ * HISTORY_SECONDS)
		entry.nextSample = 0
	end
	if type(entity) == "table" then entry.actor = entity end
	return entry
end

function Service:_matches(control, entry)
	local model = entry.model
	if control.exempt[model] or (entry.owner and control.exempt[entry.owner]) then return false end
	if control.scope == "Targets" then return control.targets[model] == true or (entry.owner and control.targets[entry.owner] == true) end
	if control.scope == "World" then return true end
	local sourceRoot = rootOf(control.source)
	local center = control.center or (sourceRoot and sourceRoot.Position)
	if not center then return false end
	return (entry.root.Position - center).Magnitude <= control.radius
end

function Service:_playTimeSound(name, position, radius)
	-- full method is omitted
end

-- Omitted: ability-specific stop-parry/cancel windows and BreakStop mechanics.

function Service:Apply(spec)
	assert(type(spec) == "table", "TimeControl.Apply requires a specification")
	Service.init()
	local source = modelOf(spec.Source)
	assert(not source or rootOf(source), "TimeControl Source needs a live entity root")
	local scope = spec.Scope or (spec.Targets and "Targets" or "Radius")
	assert(scope == "Radius" or scope == "Targets" or scope == "World", "unknown time scope")
	assert(scope ~= "Radius" or source or typeof(spec.Center) == "Vector3", "radial time control requires Source or Center")
	assert(spec.Center == nil or typeof(spec.Center) == "Vector3", "Center must be Vector3")
	local targets, exempt = instanceSet(spec.Targets), instanceSet(spec.Exempt)
	if source and spec.ExemptSource ~= false then exempt[source] = true end
	for model in pairs(targets) do self:Register(model) end
	if source then self:Register(spec.Source) end
	self.sequence += 1
	local control = {
		id = self.sequence, scope = scope, source = source, center = spec.Center,
		radius = number(spec.Radius, DEFAULT_RADIUS, 0, 100000), targets = targets, exempt = exempt,
		rate = number(spec.Rate, 0, -MAX_RATE, MAX_RATE), priority = number(spec.Priority, 0, -1000, 1000),
		endsAt = workspace:GetServerTimeNow() + number(spec.Duration, 1, 0.01, MAX_DURATION),
		historySeconds = number(spec.Seconds, HISTORY_SECONDS, 0, HISTORY_SECONDS),
		audience = spec.Audience, -- optional array of Players: presentation only
	}
	if control.audience then
		for _, player in ipairs(control.audience) do assert(typeof(player) == "Instance" and player:IsA("Player"), "Audience must contain Players") end
	end
	self.controls[control.id] = control
	self:_step(0)
	if control.rate == 0 and not control.audience then
		local root = rootOf(control.source)
		control.soundPosition = control.center or (root and root.Position)
		self:_playTimeSound(control.endsAt - workspace:GetServerTimeNow() < 1 and "FastTimeStop" or "TimeStop", control.soundPosition, control.radius)
	end
	return control.id
end

function Service:Release(handle)
	if handle == nil then return end
	local control = self.controls[handle]
	if control and control.rate == 0 and not control.audience then
		local root = rootOf(control.source)
		self:_playTimeSound("TimeResume", control.center or (root and root.Position) or control.soundPosition, control.radius)
	end
	self.controls[handle] = nil
	self:_step(0)
end

function Service:_publish(entry, control, audience, action, extra)
	if not self.eventService then return end
	self.packetSequence = (self.packetSequence or 0) + 1
	local payload = {
		entity = entry.model, action = action or "State", sequence = self.packetSequence,
		rate = control and control.rate or 1, id = control and control.id or 0,
		endsAt = control and control.endsAt or 0, seconds = control and control.historySeconds or 0,
		t = workspace:GetServerTimeNow(), presentationOnly = audience ~= nil,
	}
	if extra then for key, value in pairs(extra) do payload[key] = value end end
	if audience then
		for _, player in ipairs(audience) do
			if player.Parent then self.eventService:FireClient(player, "Server/TimeControl/State", payload) end
		end
	else
		self.eventService:FireAll("Server/TimeControl/State", payload)
	end
end

function Service:_restore(entry)
	if entry.presentation then entry.presentation:Restore(); entry.presentation = nil end
	local root = entry.root
	if entry.gravity then entry.gravity:Destroy(); entry.gravityAttachment:Destroy(); entry.gravity = nil; entry.gravityAttachment = nil end
	if entry.physicsRate and root.Parent and not root.Anchored then
		root.AssemblyLinearVelocity /= entry.physicsRate
		root.AssemblyAngularVelocity /= entry.physicsRate
	end
	entry.physicsRate = nil
	if entry.held and root.Parent then
		root.Anchored = entry.held.anchored
		root.AssemblyLinearVelocity = entry.velocity or entry.held.velocity
		root.AssemblyAngularVelocity = entry.angular or entry.held.angular
		entry.held = nil
	end
	entry.velocity, entry.angular = nil, nil
end

function Service:_interrupt(entry)
	local actor = entry.actor
	if actor then
		TickService:CancelActions(actor, "time_rewind")
		-- Omitted: combat hit-generation bookkeeping.
	end
	Movement.StopMotion(entry.root)
	-- Hitboxes compare this generation even when their callbacks have no actor context.
	entry.model:SetAttribute("TimeRevision", (entry.model:GetAttribute("TimeRevision") or 0) + 1)
end

function Service:Rewind(targets, seconds, options)
	local spec = table.clone(options or {})
	if targets then spec.Targets = targets end
	spec.Seconds = seconds
	spec.Rate = -math.abs(spec.Rate or 1)
	spec.Duration = spec.Duration or seconds / math.abs(spec.Rate)
	return self:Apply(spec)
end

function Service:JumpBack(targets, seconds, options)
	local spec = table.clone(options or {})
	if targets then spec.Targets = targets end
	spec.Seconds, spec.Rate = seconds, 0
	spec.Duration = spec.Audience and (spec.Duration or 0.2) or 0.01
	local handle = self:Apply(spec)
	local control = self.controls[handle]
	local now = workspace:GetServerTimeNow()
	for _, entry in pairs(self.entities) do
		if self:_matches(control, entry) then
			local a, b, alpha, sampled = entry.history:Sample(now - control.historySeconds)
			if a then
				if not control.audience then
					self:_interrupt(entry)
					entry.model:PivotTo(a.cframe:Lerp(b.cframe, alpha))
					entry.velocity, entry.angular = a.velocity:Lerp(b.velocity, alpha), a.angular:Lerp(b.angular, alpha)
					entry.history:Truncate(sampled)
					if entry.adapter and entry.adapter.Seek then entry.adapter.Seek(entry.model, a.custom, b.custom, alpha) end
				end
				self:_publish(entry, control, control.audience, "Jump", { cframe = a.cframe:Lerp(b.cframe, alpha), sampleTime = sampled })
			end
		end
	end
	if not control.audience then self:Release(handle) end
	return handle
end

function Service:_step(dt)
	local now = workspace:GetServerTimeNow()
	for _, actor in pairs(_G.Players or {}) do
		if actor.CharacterObject and actor.IsAlive ~= false then self:Register(actor) end
	end
	for id, control in pairs(self.controls) do
		if now >= control.endsAt or (control.source and not control.source.Parent) then
			self.controls[id] = nil
			if control.rate == 0 and not control.audience then
				local root = rootOf(control.source)
				self:_playTimeSound("TimeResume", control.center or (root and root.Position) or control.soundPosition, control.radius)
			end
		end
	end
	for model, entry in pairs(self.entities) do
		if not model.Parent or not entry.root.Parent or (entry.actor and (entry.actor.CharacterObject ~= model or entry.actor.IsAlive == false)) then
			self:_restore(entry)
			EntityTime.SetRate(model, 1)
			CollectionService:RemoveTag(model, "TimeEntity")
			model:SetAttribute("TimeEntity", nil)
			-- Omitted: ability-specific stop-cancel attribute cleanup.
			self.entities[model] = nil
			continue
		end
		-- Omitted: ability-specific stop-cancel expiry.
		local control = Timeline.Select(self.controls, now, function(candidate)
			return not candidate.audience and self:_matches(candidate, entry)
		end)
		local id, rate = control and control.id or 0, control and control.rate or 1
		if entry.controlId ~= id then
			-- Omitted: ability-specific stop-cancel reset.
			if entry.rate < 0 and entry.cursor then entry.history:Truncate(entry.cursor) end
			self:_restore(entry)
			entry.controlId, entry.rate = id, rate
			EntityTime.SetRate(model, rate)
			model:SetAttribute("TimeControlStart", now)
			model:SetAttribute("TimeControlEnd", control and control.endsAt or 0)
			model:SetAttribute("TimeHistorySeconds", control and control.historySeconds or 0)
			if rate < 0 then self:_interrupt(entry); entry.cursor = now; entry.reverseStart = now end
			self:_publish(entry, control)
		end
		if entry.adapter and entry.adapter.Step and rate > 0 then entry.adapter.Step(model, dt * rate) end
		if rate ~= 1 then
			entry.presentation = entry.presentation or Presentation.new(model)
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid then
				entry.presentation:Scale(humanoid, "WalkSpeed", math.max(0, rate))
				entry.presentation:Scale(humanoid, "JumpPower", math.max(0, rate))
				entry.presentation:Scale(humanoid, "JumpHeight", math.max(0, rate)^2)
				if rate <= 0 then entry.presentation:Scale(humanoid, "AutoRotate", nil, false) end
			end
			if not humanoid and rate > 0 and not entry.root.Anchored and not entry.adapter then
				local root = entry.root
				if not entry.physicsRate then
					entry.physicsRate = rate
					root.AssemblyLinearVelocity *= rate
					root.AssemblyAngularVelocity *= rate
					entry.gravityAttachment = Instance.new("Attachment")
					entry.gravityAttachment.Name = "TimeGravityAttachment"
					entry.gravityAttachment.Parent = root
					entry.gravity = Instance.new("VectorForce")
					entry.gravity.Name = "TimeGravity"
					entry.gravity.RelativeTo = Enum.ActuatorRelativeTo.World
					entry.gravity.ApplyAtCenterOfMass = true
					entry.gravity.Attachment0 = entry.gravityAttachment
					entry.gravity.Parent = root
				end
				entry.gravity.Force = Vector3.new(0, workspace.Gravity * root.AssemblyMass * (1 - rate^2), 0)
			end
		end
		if rate <= 0 then
			local root = entry.root
			if not entry.held then entry.held = { anchored = root.Anchored, velocity = root.AssemblyLinearVelocity, angular = root.AssemblyAngularVelocity, cframe = model:GetPivot() } end
			root.Anchored = true
			root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
			if rate < 0 then
				entry.cursor = math.max(entry.reverseStart - control.historySeconds, entry.cursor + dt * rate)
				local a, b, alpha = entry.history:Sample(entry.cursor)
				if a then
					model:PivotTo(a.cframe:Lerp(b.cframe, alpha))
					entry.velocity, entry.angular = a.velocity:Lerp(b.velocity, alpha), a.angular:Lerp(b.angular, alpha)
					if entry.adapter and entry.adapter.Seek then entry.adapter.Seek(model, a.custom, b.custom, alpha) end
				end
			else model:PivotTo(entry.held.cframe) end
		elseif now >= entry.nextSample then
			local snapshot = Presentation.Capture(model)
			if snapshot then
				if entry.physicsRate then snapshot.velocity /= entry.physicsRate; snapshot.angular /= entry.physicsRate end
				if entry.adapter and entry.adapter.Capture then snapshot.custom = entry.adapter.Capture(model) end
				entry.history:Record(now, snapshot)
			end
			entry.nextSample = now + 1 / HISTORY_HZ
		end
		-- Cosmetic controls are resolved independently per audience member.
		local viewers = {}
		for _, candidate in pairs(self.controls) do
			if candidate.audience then for _, player in ipairs(candidate.audience) do viewers[player] = true end end
		end
		for player in pairs(entry.viewers or {}) do viewers[player] = true end
		entry.viewers = entry.viewers or {}
		for player in pairs(viewers) do
			local visual = Timeline.Select(self.controls, now, function(candidate)
				return candidate.audience and table.find(candidate.audience, player) ~= nil and self:_matches(candidate, entry)
			end)
			if entry.viewers[player] ~= (visual and visual.id) then
				self:_publish(entry, visual, { player })
				entry.viewers[player] = visual and visual.id or nil
			end
		end
	end
end

function Service:RegisterEndpoints(eventService)
	self.eventService = eventService
	eventService:EnsureRemote("Server/TimeControl/State", "RemoteEvent")
	Service.init()
end

function Service.init()
	if Service.connection then return end
	_G.TimeControlService = Service
	VisualOwnership.ConfigureTime(EntityTime, EffectTime)
	Service.connection = RunService.PreSimulation:Connect(function(dt) Service:_step(dt) end)
end

return Service

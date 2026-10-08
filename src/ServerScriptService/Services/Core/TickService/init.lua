local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local EntityTime = require(game.ReplicatedStorage.Modules.Time.EntityTime)
local TickService = {}
TickService.__index = TickService

-- Configuration
TickService.TickRate = 60
local TICK_RATE = TickService.TickRate -- ticks per second
local MAX_TICKS = TICK_RATE * 30 -- store last 30 seconds of ticks

-- Internal state
local TickBuffer = table.create(MAX_TICKS)
local CurrentTick = 0
local Recording = false
local SessionID = nil
local Initialized = false
local ReplayLog = nil
local ScheduledTasks = {}
local ScheduleSequence = 0
local ThreadActorStack = setmetatable({}, { __mode = "k" })
local ActorActionGeneration = setmetatable({}, { __mode = "k" })
local TS = game.ReplicatedStorage.GameObjects.TimeStop
local TimeStopAccumulated = 0
local TimeStopStart = nil
local ACTION_CANCELLED_ERROR = "[TickService:ActionCancelled]"

local function actorModel(actor)
	if type(actor) == "table" then return actor.CharacterObject end
	if typeof(actor) == "Instance" then return actor end
	return nil
end

local function getActorGeneration(actor)
	if actor == nil then
		return 0
	end
	return tonumber(ActorActionGeneration[actor]) or 0
end

local function isActionCancellation(err)
	return string.find(tostring(err), ACTION_CANCELLED_ERROR, 1, true) ~= nil
end

local function refreshTimeStopState(now)
	if TS.Value == true then
		if TimeStopStart == nil then
			TimeStopStart = now
		end
	elseif TimeStopStart ~= nil then
		TimeStopAccumulated += math.max(0, now - TimeStopStart)
		TimeStopStart = nil
	end
end

function TickService:StartSession(id)
	if not Initialized then
		Initialized = true
		TickService:init()
	end

	SessionID = id
	CurrentTick = TickService.ByTick(workspace:GetServerTimeNow())
	Recording = true
	TickBuffer = table.create(MAX_TICKS)
	TimeStopAccumulated = 0
	TimeStopStart = nil
end

function TickService:StopSession()
	Recording = false
end

function TickService:GetTick(entity)
	entity = entity or self:GetActor()
	if entity then return TickService.ByTick(EntityTime.Now(entity)) end
	return CurrentTick
end

function TickService:GetEntityTime(entity)
	return EntityTime.Now(entity or self:GetActor())
end

function TickService:GetSession()
	return SessionID
end

function TickService.ByTick(timeVal)
	if not timeVal then
		timeVal = 0
	end
	return math.floor(timeVal * TICK_RATE)
end

function TickService.ByTime(tickVal)
		if not tickVal then
		tickVal = 0
	end
	return (tickVal/TICK_RATE)
end
function TickService.GetDifferenceInTicks(v1,v2)
	return TickService.ByTick(v1) - TickService.ByTick(v2)
end

function TickService.GetDifferenceInTime(v1,v2)
	return TickService.ByTime(v1) - TickService.ByTime(v2)
end

function TickService:Schedule(delayInSeconds, fn, entity)
	local actor = entity or self:GetActor()
	local duration = tonumber(delayInSeconds) or 0
	assert(duration == duration and math.abs(duration) < math.huge, "invalid schedule duration")
	ScheduleSequence += 1
	local entry = { actor = actor, sequence = ScheduleSequence, deadline = actor and EntityTime.Now(actor) + math.max(0, duration)
		or TickService.ByTime(CurrentTick) + math.max(0, duration), callback = fn,
		character = actorModel(actor),
		revision = actorModel(actor) and (actorModel(actor):GetAttribute("TimeRevision") or 0) }
	table.insert(ScheduledTasks, entry)
	return entry
end

function TickService:SetActor(actor, actionGeneration, timeRevision, character)
	local thread = coroutine.running()
	if thread == nil then
		return
	end
	local stack = ThreadActorStack[thread]
	if stack == nil then
		stack = {}
		ThreadActorStack[thread] = stack
	end
	local resolvedGeneration = actionGeneration
	if resolvedGeneration == nil then
		local parentContext = stack[#stack]
		if parentContext and parentContext.actor == actor then
			-- A nested combat dispatch belongs to the action that invoked it. Inheriting
			-- that generation prevents stale work from rebinding itself as current after
			-- it resumes through an ordinary task.wait and calls Combat.Fire again.
			resolvedGeneration = parentContext.actionGeneration
		else
			resolvedGeneration = getActorGeneration(actor)
		end
	end
	local parent = stack[#stack]
	stack[#stack + 1] = {
		actor = actor,
		character = character or (parent and parent.actor == actor and parent.character) or actorModel(actor),
		actionGeneration = resolvedGeneration,
		timeRevision = timeRevision or (parent and parent.actor == actor and parent.timeRevision)
			or (actorModel(actor) and (actorModel(actor):GetAttribute("TimeRevision") or 0)),
	}
end

function TickService:ClearActor()
	local thread = coroutine.running()
	if thread == nil then
		return
	end
	local stack = ThreadActorStack[thread]
	if stack == nil then
		return
	end
	stack[#stack] = nil
	if #stack == 0 then
		ThreadActorStack[thread] = nil
	end
end

function TickService:GetActor()
	local thread = coroutine.running()
	if thread == nil then
		return nil
	end
	local stack = ThreadActorStack[thread]
	if stack == nil then
		return nil
	end
	local context = stack[#stack]
	return context and context.actor or nil
end

function TickService:GetBoundTimeRevision()
	local stack = ThreadActorStack[coroutine.running()]
	local context = stack and stack[#stack]
	return context and context.timeRevision
end

function TickService:IsTemporalActionCurrent()
	local actor = self:GetActor()
	local stack = ThreadActorStack[coroutine.running()]
	local context = stack and stack[#stack]
	local model = actorModel(actor)
	if actor and context and context.character ~= model then return false end
	local revision = self:GetBoundTimeRevision()
	return not actor or not model or revision == nil
		or revision == (model:GetAttribute("TimeRevision") or 0)
end

function TickService:GetBoundActionGeneration()
	local thread = coroutine.running()
	if thread == nil then
		return nil
	end
	local stack = ThreadActorStack[thread]
	local context = stack and stack[#stack] or nil
	return context and context.actionGeneration or nil
end

function TickService:GetActionGeneration(actor)
	return getActorGeneration(actor)
end

function TickService:IsActionCurrent(actor, actionGeneration)
	if actor == nil or actionGeneration == nil then
		return true
	end
	return getActorGeneration(actor) == actionGeneration
end

function TickService:CancelActions(actor, reason)
	if actor == nil then
		return 0
	end
	local nextGeneration = getActorGeneration(actor) + 1
	ActorActionGeneration[actor] = nextGeneration

	-- Omitted: AI-specific cancellation telemetry.

	return nextGeneration
end

function TickService:IsActionCancellation(err)
	return isActionCancellation(err)
end

function TickService:AssertActionCurrent()
	local actor = TickService:GetActor()
	local actionGeneration = TickService:GetBoundActionGeneration()
	if not self:IsTemporalActionCurrent() or not TickService:IsActionCurrent(actor, actionGeneration) then
		error(ACTION_CANCELLED_ERROR, 0)
	end
end

function TickService:Wait(duration, entity)
	duration = tonumber(duration) or 0
	assert(duration == duration and math.abs(duration) < math.huge, "invalid wait duration")
	local actor = entity or self:GetActor()
	local generation = self:GetBoundActionGeneration()
	local remaining = math.max(0, duration)
	local previous = actor and EntityTime.Now(actor) or TickService.ByTime(CurrentTick)
	self:AssertActionCurrent()
	while remaining > 0 do
		task.wait()
		self:AssertActionCurrent()
		local now = actor and EntityTime.Now(actor) or TickService.ByTime(CurrentTick)
		local stunned = type(actor) == "table" and type(actor.IsStunned) == "function" and actor:IsStunned()
		-- Omitted: bot-specific stunned-action policy.
		if not stunned then remaining -= math.max(0, now - previous) end
		previous = now
	end
end

function TickService:RecordEvent(eventData)
	if not Recording then return end
	local tickData = TickBuffer[CurrentTick % MAX_TICKS + 1]
	if not tickData or tickData.Tick ~= CurrentTick then
		tickData = {
			Tick = CurrentTick,
			PlayerStates = {},
			Events = {},
		}
		TickBuffer[CurrentTick % MAX_TICKS + 1] = tickData
	end
	table.insert(tickData.Events, eventData)
end

function TickService:RecordState(playerName, state)
	if not Recording then return end
	local tickData = TickBuffer[CurrentTick % MAX_TICKS + 1]
	if not tickData or tickData.Tick ~= CurrentTick then
		tickData = {
			Tick = CurrentTick,
			PlayerStates = {},
			Events = {},
		}
		TickBuffer[CurrentTick % MAX_TICKS + 1] = tickData
	end
	tickData.PlayerStates[playerName] = state
end

function TickService:ExportReplay()
	return HttpService:JSONEncode(ReplayLog)
end

function TickService:LoadReplay(jsonString)
	ReplayLog = HttpService:JSONDecode(jsonString)
	TickBuffer = {} -- optional: populate buffer if resimulating
	for i, tickData in ipairs(ReplayLog) do
		TickBuffer[i % MAX_TICKS + 1] = tickData
	end
end


function TickService:GetSnapshot(tickNumber)
	local snapshot = TickBuffer[tickNumber % MAX_TICKS + 1]
	return snapshot and snapshot.Tick == tickNumber and snapshot or nil
end

function TickService:Step(targetTick)
	local now = workspace:GetServerTimeNow()
	refreshTimeStopState(now)
	if targetTick == nil then
		targetTick = TickService.ByTick(now - TimeStopAccumulated - (TimeStopStart and now - TimeStopStart or 0))
	end
	CurrentTick = math.max(CurrentTick, targetTick)
	local due = {}
	-- Remove before execution: callbacks may schedule callbacks, yield, or fail.
	for index = #ScheduledTasks, 1, -1 do
		local entry = ScheduledTasks[index]
		local clock = entry.actor and EntityTime.Now(entry.actor) or TickService.ByTime(CurrentTick)
		if clock >= entry.deadline then
			table.remove(ScheduledTasks, index)
			table.insert(due, 1, entry)
		end
	end
	table.sort(due, function(a, b)
		return a.deadline < b.deadline or (a.deadline == b.deadline and a.sequence < b.sequence)
	end)
	for _, entry in ipairs(due) do
		task.spawn(function()
			if entry.actor then self:SetActor(entry.actor, nil, entry.revision, entry.character) end
			local ok, err = xpcall(entry.callback, debug.traceback)
			if entry.actor then self:ClearActor() end
			if not ok then warn("[TickService] Scheduled callback failed: " .. tostring(err)) end
		end)
	end
end

-- Run on heartbeat

function TickService.init()
	if TickService._connection then return end
	TickService._connection = RunService.PreSimulation:Connect(function()
		TickService:Step()
	end)
end


-- Explicit adapters preserve actor identity across Roblox's coroutine/task boundaries.
function TickService:Bind(callback)
	local actor = self:GetActor()
	local generation = self:GetBoundActionGeneration()
	local revision = self:GetBoundTimeRevision()
	local stack = ThreadActorStack[coroutine.running()]
	local context = stack and stack[#stack]
	local character = context and context.character or actorModel(actor)
	return function(...)
		if actor then self:SetActor(actor, generation, revision, character) end
		local result = table.pack(pcall(callback, ...))
		if actor then self:ClearActor() end
		if not result[1] then
			if self:IsActionCancellation(result[2]) then return nil end
			error(result[2], 0)
		end
		return table.unpack(result, 2, result.n)
	end
end

function TickService:Connect(signal, callback)
	local actor = self:GetActor()
	local generation = self:GetBoundActionGeneration()
	local stack = ThreadActorStack[coroutine.running()]
	local context = stack and stack[#stack]
	local character = context and context.character or actorModel(actor)
	local bound = self:Bind(callback)
	local connection
	connection = signal:Connect(function(...)
		if actor and (actorModel(actor) ~= character or not self:IsActionCurrent(actor, generation)) then
			connection:Disconnect()
			return
		end
		local rate = EntityTime.GetRate(actor)
		if rate <= 0 then return end
		local args = table.pack(...)
		local deltaIndex = signal == RunService.Stepped and 2 or 1
		if type(args[deltaIndex]) == "number" then args[deltaIndex] *= rate end
		bound(table.unpack(args, 1, args.n))
	end)
	return connection
end

TickService.Task = setmetatable({
	spawn = function(callback, ...) return task.spawn(TickService:Bind(callback), ...) end,
	defer = function(callback, ...) return task.defer(TickService:Bind(callback), ...) end,
	delay = function(duration, callback, ...)
		local actor = TickService:GetActor()
		local args, bound = table.pack(...), TickService:Bind(callback)
		return task.spawn(function()
			EntityTime.Wait(actor, duration)
			bound(table.unpack(args, 1, args.n))
		end)
	end,
	wait = function(duration)
		local actor = TickService:GetActor()
		local started = EntityTime.Now(actor)
		TickService:Wait(duration or 1 / 60, actor)
		return EntityTime.Now(actor) - started
	end,
}, { __index = task })
TickService.Coroutine = setmetatable({
	wrap = function(callback) return coroutine.wrap(TickService:Bind(callback)) end,
	create = function(callback) return coroutine.create(TickService:Bind(callback)) end,
}, { __index = coroutine })

return TickService

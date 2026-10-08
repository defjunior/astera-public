-- Local movement layer: time-aware momentum/constraint lifecycle; not world-generation optimization.
local EntityTime = require(game.ReplicatedStorage.Modules.Time.EntityTime)
local RunService = game:GetService("RunService")

local Controller = {}

local CONTROLLER_BV_NAME = "AsteraMovementControllerLV"
local CONTROLLER_OWNED_ATTR = "AsteraMovementControllerOwned"
local CONTROLLER_ATTACHMENT_NAME = "AsteraMovementControllerAttachment"
local stateByPart = setmetatable({}, { __mode = "k" })
local heartbeatConnection = nil
local DEFAULT_ACCELERATION = 1400
local MAX_FAILSAFE_MOTION_DURATION = 3.5
local motionCounter = 0

local function nextMotionId()
	motionCounter += 1
	return motionCounter
end

local function nowTick()
	return os.clock()
end

local function stampConstraintState(state, phase)
	local bv = state and state.bv
	if not (bv and bv.Parent) then
		return
	end
	bv:SetAttribute("AsteraMotionId", tonumber(state.motionId) or 0)
	bv:SetAttribute("AsteraMotionPhase", tostring(phase or state.phase or "idle"))
	bv:SetAttribute("AsteraMotionStartedAt", tonumber(state.startedAt) or 0)
	bv:SetAttribute("AsteraMotionExpectedEndAt", tonumber(state.expectedEndAt) or 0)
	bv:SetAttribute("AsteraMotionPhaseEndAt", tonumber(state.phaseEndAt) or 0)
	bv:SetAttribute("AsteraMotionEndedAt", tonumber(state.endedAt) or 0)
	bv:SetAttribute("AsteraMotionEndReason", tostring(state.endReason or ""))
end

local function resetStateMotion(state, reason)
	if not state then
		return
	end
	state.endedAt = nowTick()
	state.endReason = tostring(reason or "completed")
	state.phase = "idle"
	state.phaseEndAt = state.endedAt
	state.time = 0
	state.elapsed = 0
	state.currentVelocity = Vector3.zero
	state.lastVelocity = Vector3.zero
	state.slideStartVelocity = Vector3.zero
	state.wallStallTime = 0
	if state.bv and state.bv.Parent then
		state.bv.VectorVelocity = Vector3.zero
		state.bv.MaxAxesForce = Vector3.zero
	end
	stampConstraintState(state, "idle")
end

local function moveTowardsVector(current, target, maxDelta)
	local delta = target - current
	local magnitude = delta.Magnitude
	if magnitude <= 1e-4 or maxDelta <= 0 then
		return target
	end
	if magnitude <= maxDelta then
		return target
	end
	return current + (delta / magnitude) * maxDelta
end

local function horizontalMagnitude(vector)
	if typeof(vector) ~= "Vector3" then
		return 0
	end
	return Vector3.new(vector.X, 0, vector.Z).Magnitude
end

local function steerHorizontalTowardsLook(part, velocity, steeringControl)
	if not part or not part.Parent then
		return velocity
	end
	local control = math.clamp(tonumber(steeringControl) or 0, 0, 1)
	if control <= 0 then
		return velocity
	end

	local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
	local horizontalSpeed = horizontal.Magnitude
	if horizontalSpeed <= 1e-4 then
		return velocity
	end

	local currentDir = horizontal.Unit
	local look = Vector3.new(part.CFrame.LookVector.X, 0, part.CFrame.LookVector.Z)
	if look.Magnitude <= 1e-4 then
		return velocity
	end
	local lookDir = look.Unit
	local steeredDir = currentDir:Lerp(lookDir, control)
	if steeredDir.Magnitude <= 1e-4 then
		return velocity
	end
	steeredDir = steeredDir.Unit
	return Vector3.new(steeredDir.X * horizontalSpeed, velocity.Y, steeredDir.Z * horizontalSpeed)
end

local function ensureHeartbeat()
	if heartbeatConnection then
		return
	end
	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		for part, state in pairs(stateByPart) do
			local realDt = dt
			local rate = math.max(0, EntityTime.GetRate(part))
			local dt = realDt * rate
			if not part or not part.Parent then
				stateByPart[part] = nil
				continue
			end
			local bv = state.bv
			if not bv or not bv.Parent then
				stateByPart[part] = nil
				continue
			end

			state.time = tonumber(state.time) or 0
			state.elapsed = tonumber(state.elapsed) or 0
			state.failSafeDuration = tonumber(state.failSafeDuration) or MAX_FAILSAFE_MOTION_DURATION

			-- Hitstop: while frozen, hold the motion in place. Don't advance the
			-- phase timers or integrate velocity, and push the phase/failsafe
			-- deadlines forward by dt so the frozen span isn't consumed. The
			-- assembly velocity is pinned to zero by the hitstop watcher itself.
			if state.frozen == true or rate == 0 then
				if state.phase ~= "idle" then
					state.phaseEndAt = (tonumber(state.phaseEndAt) or 0) + realDt
					state.expectedEndAt = (tonumber(state.expectedEndAt) or 0) + realDt
				end
				bv.VectorVelocity = Vector3.zero
				continue
			end

			if state.phase ~= "idle" then
				state.phaseEndAt = (state.phaseEndAt or 0) + realDt - dt
				state.expectedEndAt = (state.expectedEndAt or 0) + realDt - dt
			end
			state.time += dt
			state.elapsed += dt
			local currentClock = nowTick()
			local phase = state.phase
			local velocity = Vector3.zero
			local maxForce = Vector3.zero

			if phase ~= "idle" and tonumber(state.expectedEndAt) and currentClock >= state.expectedEndAt then
				resetStateMotion(state, "deadline")
				continue
			end
			if phase ~= "idle" and tonumber(state.phaseEndAt) and currentClock >= state.phaseEndAt then
				if phase == "impulse" or phase == "sequence" then
					state.phase = state.slide and "slide" or "idle"
					state.time = 0
					state.slideStartVelocity = state.lastVelocity
					if state.phase == "slide" then
						state.phaseEndAt = currentClock + math.max(0.05, state.slideDuration)
						stampConstraintState(state, "slide")
					else
						resetStateMotion(state, "phase-timeout")
						continue
					end
				else
					resetStateMotion(state, "phase-timeout")
					continue
				end
			end
			if phase ~= "idle" and state.elapsed >= state.failSafeDuration then
				resetStateMotion(state, "failsafe")
				continue
			end

			if phase == "sequence" then
				maxForce = state.maxForce
				local duration = math.max(0.05, state.duration)
				local alpha = math.clamp(state.time / duration, 0, 1)
				local samples = state.samples
				local count = #samples
				if count == 1 then
					velocity = samples[1]
				else
					local scaled = math.clamp(alpha * (count - 1), 0, count - 1)
					local i0 = math.floor(scaled) + 1
					local i1 = math.min(count, i0 + 1)
					local localAlpha = scaled - math.floor(scaled)
					velocity = samples[i0]:Lerp(samples[i1], localAlpha)
				end
				velocity = steerHorizontalTowardsLook(part, velocity, state.steeringControl)
				state.currentVelocity = moveTowardsVector(
					state.currentVelocity,
					velocity,
					math.max(0, state.sequenceAcceleration) * dt
				)
				velocity = state.currentVelocity
				state.lastVelocity = velocity
				if alpha >= 1 and (state.currentVelocity - state.targetVelocity).Magnitude <= 0.25 then
					state.phase = state.slide and "slide" or "idle"
					state.time = 0
					state.slideStartVelocity = state.lastVelocity
					if state.phase == "slide" then
						state.phaseEndAt = currentClock + math.max(0.05, state.slideDuration)
						stampConstraintState(state, "slide")
					else
						resetStateMotion(state, "sequence-complete")
						continue
					end
				end
			elseif phase == "impulse" then
				maxForce = state.maxForce
				local duration = math.max(0.05, state.duration)
				local alpha = math.clamp(state.time / duration, 0, 1)
				local rampAlpha = math.min(1, alpha / math.max(0.001, state.accelFraction))
				local desiredVelocity = state.targetVelocity * rampAlpha
				desiredVelocity = steerHorizontalTowardsLook(part, desiredVelocity, state.steeringControl)
				state.currentVelocity = moveTowardsVector(
					state.currentVelocity,
					desiredVelocity,
					math.max(0, state.impulseAcceleration) * dt
				)
				velocity = state.currentVelocity
				state.lastVelocity = velocity
				if alpha >= 1 then
					state.phase = state.slide and "slide" or "idle"
					state.time = 0
					state.slideStartVelocity = state.lastVelocity
					if state.phase == "slide" then
						state.phaseEndAt = currentClock + math.max(0.05, state.slideDuration)
						stampConstraintState(state, "slide")
					else
						resetStateMotion(state, "impulse-complete")
						continue
					end
				end
			elseif phase == "slide" then
				maxForce = state.maxForce
				local slideDuration = math.max(0.05, state.slideDuration)
				local alpha = math.clamp(state.time / slideDuration, 0, 1)
				local floor = state.slideFloor
				local decay = math.max(floor, 1 - (alpha * alpha))
				local start = state.slideStartVelocity
				velocity = Vector3.new(
					start.X * state.slideStartMultiplier * decay,
					start.Y * state.slideVerticalDamp * decay,
					start.Z * state.slideStartMultiplier * decay
				)
				if alpha >= 1 then
					resetStateMotion(state, "slide-complete")
					continue
				end
			end

			if velocity.Magnitude ~= velocity.Magnitude then
				resetStateMotion(state, "nan-velocity")
				continue
			end

			if state.stopOnWall == true then
				local desiredHorizontal = horizontalMagnitude(velocity)
				local actualHorizontal = horizontalMagnitude(part.AssemblyLinearVelocity)
				local wallTargetThreshold = math.max(1, tonumber(state.wallTargetThreshold) or 18)
				local wallSpeedThreshold = math.max(0, tonumber(state.wallSpeedThreshold) or 3)
				local wallStallDuration = math.max(0.03, tonumber(state.wallStallDuration) or 0.06)
				local canStall = state.elapsed >= math.max(0.08, math.min(0.15, state.duration * 0.4))
				if canStall and desiredHorizontal >= wallTargetThreshold and actualHorizontal <= wallSpeedThreshold then
					state.wallStallTime = (tonumber(state.wallStallTime) or 0) + dt
					if state.wallStallTime >= wallStallDuration then
						resetStateMotion(state, "wall-stall")
						continue
					end
				else
					state.wallStallTime = 0
				end
			end

			bv.VectorVelocity = velocity * rate
			bv.MaxAxesForce = maxForce
		end
	end)
end

local function ensureState(part, velocityName, maxForce)
	local existingOwned = nil
	local existingAttachment = nil
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Attachment") and child.Name == CONTROLLER_ATTACHMENT_NAME then
			if existingAttachment == nil then
				existingAttachment = child
			else
				child:Destroy()
			end
		elseif child:IsA("LinearVelocity")
			and child.Name == CONTROLLER_BV_NAME
			and child:GetAttribute(CONTROLLER_OWNED_ATTR) == true
		then
			if existingOwned == nil then
				existingOwned = child
			else
				child:Destroy()
			end
		elseif child:IsA("BodyVelocity")
			and child.Name == CONTROLLER_BV_NAME
			and child:GetAttribute(CONTROLLER_OWNED_ATTR) == true
		then
			child:Destroy()
		end
	end

	if not existingAttachment then
		existingAttachment = Instance.new("Attachment")
		existingAttachment.Name = CONTROLLER_ATTACHMENT_NAME
		existingAttachment.Parent = part
	end

	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("LinearVelocity")
			and child.Name == CONTROLLER_BV_NAME
			and child:GetAttribute(CONTROLLER_OWNED_ATTR) == true
			and child ~= existingOwned
		then
			child:Destroy()
		end
	end

	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("BodyVelocity")
			and child:GetAttribute(CONTROLLER_OWNED_ATTR) == true
		then
			child:Destroy()
		end
	end

	local state = stateByPart[part]
	if state and state.bv and state.bv.Parent then
		state.time = tonumber(state.time) or 0
		state.elapsed = tonumber(state.elapsed) or 0
		state.duration = tonumber(state.duration) or 0.1
		state.failSafeDuration = tonumber(state.failSafeDuration) or MAX_FAILSAFE_MOTION_DURATION
		state.accelFraction = tonumber(state.accelFraction) or 0.4
		state.impulseAcceleration = tonumber(state.impulseAcceleration) or DEFAULT_ACCELERATION
		state.sequenceAcceleration = tonumber(state.sequenceAcceleration) or DEFAULT_ACCELERATION
		state.slideDuration = tonumber(state.slideDuration) or 0.2
		state.slideFloor = tonumber(state.slideFloor) or 0.03
		state.slideStartMultiplier = tonumber(state.slideStartMultiplier) or 0.45
		state.slideVerticalDamp = tonumber(state.slideVerticalDamp) or 0.2
		state.motionId = tonumber(state.motionId) or 0
		state.startedAt = tonumber(state.startedAt) or 0
		state.phaseEndAt = tonumber(state.phaseEndAt) or 0
		state.expectedEndAt = tonumber(state.expectedEndAt) or 0
		state.endedAt = tonumber(state.endedAt) or 0
		state.endReason = tostring(state.endReason or "")
		if existingOwned and state.bv ~= existingOwned then
			state.bv:Destroy()
			state.bv = existingOwned
		end
		state.motionName = velocityName
		state.maxForce = maxForce
		state.bv.Name = CONTROLLER_BV_NAME
		state.bv:SetAttribute(CONTROLLER_OWNED_ATTR, true)
		state.bv:SetAttribute("AsteraMotionName", tostring(velocityName))
		state.bv.Attachment0 = existingAttachment
		state.bv.RelativeTo = Enum.ActuatorRelativeTo.World
		state.bv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		state.bv.ForceLimitsEnabled = true
		state.bv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
		stampConstraintState(state, state.phase)
		return state
	end

	local bv = existingOwned
	if not bv then
		bv = Instance.new("LinearVelocity")
		bv.Name = CONTROLLER_BV_NAME
		bv:SetAttribute(CONTROLLER_OWNED_ATTR, true)
		bv:SetAttribute("AsteraMotionName", tostring(velocityName))
		bv.Attachment0 = existingAttachment
		bv.RelativeTo = Enum.ActuatorRelativeTo.World
		bv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		bv.ForceLimitsEnabled = true
		bv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
		bv.MaxAxesForce = Vector3.zero
		bv.VectorVelocity = Vector3.zero
		bv.Parent = part
	else
		bv.Name = CONTROLLER_BV_NAME
		bv:SetAttribute(CONTROLLER_OWNED_ATTR, true)
		bv:SetAttribute("AsteraMotionName", tostring(velocityName))
		bv.Attachment0 = existingAttachment
		bv.RelativeTo = Enum.ActuatorRelativeTo.World
		bv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		bv.ForceLimitsEnabled = true
		bv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	end

	state = {
		bv = bv,
		phase = "idle",
		phaseEndAt = 0,
		time = 0,
		elapsed = 0,
		duration = 0.1,
		accelFraction = 0.4,
		targetVelocity = Vector3.zero,
		samples = nil,
		currentVelocity = Vector3.zero,
		lastVelocity = Vector3.zero,
		slide = false,
		slideDuration = 0.2,
		slideFloor = 0.03,
		slideStartMultiplier = 0.45,
		slideVerticalDamp = 0.2,
		slideStartVelocity = Vector3.zero,
		stopOnWall = false,
		wallStallTime = 0,
		wallStallDuration = 0.06,
		wallSpeedThreshold = 3,
		wallTargetThreshold = 18,
		impulseAcceleration = DEFAULT_ACCELERATION,
		sequenceAcceleration = DEFAULT_ACCELERATION,
		maxForce = maxForce,
		motionName = velocityName,
		failSafeDuration = MAX_FAILSAFE_MOTION_DURATION,
		motionId = 0,
		startedAt = 0,
		expectedEndAt = 0,
		endedAt = 0,
		endReason = "",
	}
	stampConstraintState(state, "idle")
	stateByPart[part] = state
	ensureHeartbeat()
	return state
end

local function buildHandle(state)
	local proxy = {}
	local mt = {
		__index = function(_, key)
			if key == "Destroy" then
				return function()
					if state then
						resetStateMotion(state, "manual-destroy")
					end
				end
			elseif key == "Velocity" then
				local bv = state and state.bv
				return bv and bv.VectorVelocity or nil
			elseif key == "MaxForce" then
				local bv = state and state.bv
				return bv and bv.MaxAxesForce or nil
			elseif key == "P" then
				return nil
			end
			local bv = state and state.bv
			if bv and bv.Parent then
				return bv[key]
			end
			return nil
		end,
		__newindex = function(_, key, value)
			local bv = state and state.bv
			if bv and bv.Parent then
				if key == "Velocity" then
					bv.VectorVelocity = value
				elseif key == "MaxForce" then
					bv.MaxAxesForce = value
				elseif key ~= "P" then
					bv[key] = value
				end
				if key == "Velocity" and typeof(value) == "Vector3" then
					state.currentVelocity = value
					state.targetVelocity = value
					state.lastVelocity = value
				elseif key == "MaxForce" and typeof(value) == "Vector3" then
					state.maxForce = value
				end
			end
		end,
	}
	return setmetatable(proxy, mt)
end

function Controller.ClearExternalBodyVelocities(part, names)
	if not part then
		return
	end
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("BodyVelocity") and child:GetAttribute(CONTROLLER_OWNED_ATTR) ~= true then
			if names == nil or names[child.Name] then
				child:Destroy()
			end
		elseif child:IsA("LinearVelocity") and child:GetAttribute(CONTROLLER_OWNED_ATTR) ~= true then
			if names == nil or names[child.Name] then
				child:Destroy()
			end
		end
	end
end

function Controller.StopMotion(part)
	if not part then
		return
	end
	local state = stateByPart[part]
	if state and state.bv and state.bv.Parent then
		resetStateMotion(state, "stop-motion")
	end
end

-- Hitstop pause/resume. Freezing holds any active controller motion in place
-- (the Heartbeat loop shifts phase deadlines forward and pins velocity to zero)
-- so the frozen span isn't consumed. No-op safe when the part has no motion.
function Controller.SetFrozen(part, frozen)
	if not part then
		return
	end
	local state = stateByPart[part]
	if not state then
		return
	end
	state.frozen = frozen == true or nil
end

function Controller.GetMotionState(part)
	local state = part and stateByPart[part]
	if not state then
		return nil
	end
	return {
		motionId = state.motionId,
		phase = state.phase,
		startedAt = state.startedAt,
		phaseEndAt = state.phaseEndAt,
		expectedEndAt = state.expectedEndAt,
		endedAt = state.endedAt,
		endReason = state.endReason,
		duration = state.duration,
		slideDuration = state.slideDuration,
		failSafeDuration = state.failSafeDuration,
	}
end

function Controller.ApplyMomentum(part, velocity, duration, opts)
	if _G.TickService and not _G.TickService:IsTemporalActionCurrent() then return nil end
	if not part or not part.Parent then
		return nil
	end
	opts = opts or {}
	local maxForce = opts.maxForce or Vector3.new(4000000, 4500000, 4000000)
	local velocityName = tostring(opts.velocityName or CONTROLLER_BV_NAME)
	local state = ensureState(part, velocityName, maxForce)

	state.phase = "impulse"
	state.motionId = nextMotionId()
	state.startedAt = nowTick()
	state.time = 0
	state.elapsed = 0
	state.duration = math.max(tonumber(duration) or 0, 0.05)
	state.phaseEndAt = state.startedAt + state.duration
	state.accelFraction = math.clamp((tonumber(opts.accelerationTime) or math.min(0.08, state.duration * 0.4)) / state.duration, 0.01, 1)
	state.impulseAcceleration = math.max(0, tonumber(opts.acceleration) or DEFAULT_ACCELERATION)
	state.targetVelocity = velocity
	state.steeringControl = math.clamp(tonumber(opts.steeringControl) or 0, 0, 1)
	state.samples = nil
	state.currentVelocity = Vector3.new(part.AssemblyLinearVelocity.X, math.abs(velocity.Y) > 0.05 and part.AssemblyLinearVelocity.Y or 0, part.AssemblyLinearVelocity.Z)
	state.lastVelocity = Vector3.zero
	state.endedAt = 0
	state.endReason = ""

	local slide = opts.slide
	state.slide = slide and slide.enabled == true or false
	state.slideDuration = math.max(0.05, tonumber(slide and slide.duration) or 0.3)
	state.slideFloor = math.max(0, math.min(0.25, tonumber(slide and slide.floor) or 0.03))
	state.slideStartMultiplier = tonumber(slide and slide.startMultiplier) or 0.45
	state.slideVerticalDamp = tonumber(slide and slide.verticalDamp) or 0.2
	state.stopOnWall = opts.stopOnWall == true
	state.wallStallTime = 0
	state.wallStallDuration = math.max(0.03, tonumber(opts.wallStallDuration) or 0.06)
	state.wallSpeedThreshold = math.max(0, tonumber(opts.wallSpeedThreshold) or 3)
	state.wallTargetThreshold = math.max(1, tonumber(opts.wallTargetThreshold) or 18)
	state.failSafeDuration = math.max(
		0.2,
		math.min(
			MAX_FAILSAFE_MOTION_DURATION,
			state.duration + (state.slide and state.slideDuration or 0) + 0.35
		)
	)
	state.expectedEndAt = state.startedAt + state.failSafeDuration
	stampConstraintState(state, "impulse")
	if state.bv and state.bv.Parent then
		state.bv.VectorVelocity = state.targetVelocity
		state.bv.MaxAxesForce = state.maxForce
	end

	return buildHandle(state)
end

function Controller.ApplyMomentumSequence(part, velocities, duration, opts)
	if _G.TickService and not _G.TickService:IsTemporalActionCurrent() then return nil end
	if not part or not part.Parent then
		return nil
	end
	if type(velocities) ~= "table" or #velocities == 0 then
		return nil
	end
	opts = opts or {}
	local maxForce = opts.maxForce or Vector3.new(4000000, 4500000, 4000000)
	local velocityName = tostring(opts.velocityName or CONTROLLER_BV_NAME)
	local state = ensureState(part, velocityName, maxForce)

	state.phase = "sequence"
	state.motionId = nextMotionId()
	state.startedAt = nowTick()
	state.time = 0
	state.elapsed = 0
	state.duration = math.max(tonumber(duration) or 0, 0.05)
	state.phaseEndAt = state.startedAt + state.duration
	state.accelFraction = 1
	state.sequenceAcceleration = math.max(0, tonumber(opts.acceleration) or DEFAULT_ACCELERATION)
	state.samples = velocities
	state.steeringControl = math.clamp(tonumber(opts.steeringControl) or 0, 0, 1)
	state.targetVelocity = velocities[#velocities]
	state.currentVelocity = Vector3.new(part.AssemblyLinearVelocity.X, 0, part.AssemblyLinearVelocity.Z)
	state.lastVelocity = Vector3.zero
	state.endedAt = 0
	state.endReason = ""

	local slide = opts.slide
	state.slide = slide and slide.enabled == true or false
	state.slideDuration = math.max(0.05, tonumber(slide and slide.duration) or 0.3)
	state.slideFloor = math.max(0, math.min(0.25, tonumber(slide and slide.floor) or 0.03))
	state.slideStartMultiplier = tonumber(slide and slide.startMultiplier) or 0.45
	state.slideVerticalDamp = tonumber(slide and slide.verticalDamp) or 0.2
	state.stopOnWall = opts.stopOnWall == true
	state.wallStallTime = 0
	state.wallStallDuration = math.max(0.03, tonumber(opts.wallStallDuration) or 0.06)
	state.wallSpeedThreshold = math.max(0, tonumber(opts.wallSpeedThreshold) or 3)
	state.wallTargetThreshold = math.max(1, tonumber(opts.wallTargetThreshold) or 18)
	state.failSafeDuration = math.max(
		0.2,
		math.min(
			MAX_FAILSAFE_MOTION_DURATION,
			state.duration + (state.slide and state.slideDuration or 0) + 0.35
		)
	)
	state.expectedEndAt = state.startedAt + state.failSafeDuration
	stampConstraintState(state, "sequence")
	if state.bv and state.bv.Parent then
		state.bv.VectorVelocity = state.samples[1] or state.targetVelocity
		state.bv.MaxAxesForce = state.maxForce
	end

	return buildHandle(state)
end

return Controller

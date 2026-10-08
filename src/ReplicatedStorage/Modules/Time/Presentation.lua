local Presentation = {}
Presentation.__index = Presentation

function Presentation.new(model)
	return setmetatable({ model = model, properties = {}, tracks = {}, sounds = {} }, Presentation)
end

-- Preserve writes made by movement/status/VFX systems while a control is active.
function Presentation:Scale(object, property, scale, forced)
	local fields = self.properties[object]
	if not fields then fields = {}; self.properties[object] = fields end
	local field = fields[property]
	local current = object[property]
	if not field then field = { base = current }; fields[property] = field end
	if field.last ~= nil and current ~= field.last then field.base = current end
	local value = forced
	if value == nil then
		if typeof(field.base) == "NumberRange" then value = NumberRange.new(field.base.Min * scale, field.base.Max * scale)
		else value = field.base * scale end
	end
	object[property] = value
	-- Engine properties may quantize floats/NumberRanges. Compare subsequent
	-- writes against the stored value, not our higher-precision Lua calculation.
	field.last = object[property]
end

function Presentation:Apply(rate, physics)
	local model = self.model
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			local state = self.tracks[track]
			if not state then state = { base = track.Speed }; self.tracks[track] = state end
			if state.last ~= nil and track.Speed ~= state.last then state.base = track.Speed end
			-- History seeks drive reverse poses; animation markers must not be replayed.
			state.last = state.base * math.max(0, rate)
			track:AdjustSpeed(state.last)
			state.last = track.Speed
		end
	end
	if physics and humanoid then
		self:Scale(humanoid, "WalkSpeed", math.max(0, rate))
		self:Scale(humanoid, "JumpPower", math.max(0, rate))
		self:Scale(humanoid, "JumpHeight", math.max(0, rate)^2)
		if rate <= 0 then self:Scale(humanoid, "AutoRotate", nil, false) end
	end
	self:ApplyEffects(model, rate)
end

function Presentation:ApplyEffects(instance, rate)
	local objects = instance:GetDescendants()
	table.insert(objects, instance)
	for _, object in ipairs(objects) do
		if object:IsA("ParticleEmitter") then
			self:Scale(object, "TimeScale", math.clamp(rate, 0, 1))
			-- Existing native particles cannot be fast-forwarded; new emissions use scaled authored parameters.
			local emissionRate = math.max(1, rate)
			self:Scale(object, "Rate", emissionRate)
			self:Scale(object, "Lifetime", 1 / emissionRate)
			self:Scale(object, "Speed", emissionRate)
			self:Scale(object, "Acceleration", emissionRate^2)
			if rate < 0 and not self.warnedParticles then
				self.warnedParticles = true
				warn("[TimeControl] Native particles cannot rewind; held during reverse. Supply an authored replay adapter for " .. instance.Name)
			end
		elseif object:IsA("Sound") then
			self:Scale(object, "PlaybackSpeed", math.max(0.01, rate))
			if rate <= 0 then
				-- A newly replicated sound may begin playing after the first frozen frame.
				if object.Playing then self.sounds[object] = true end
				object:Pause()
			elseif self.sounds[object] then
				object:Resume()
				self.sounds[object] = nil
			end
		elseif object:IsA("Beam") then
			self:Scale(object, "TextureSpeed", rate)
		elseif object:IsA("Trail") then
			self:Scale(object, "Lifetime", rate <= 0 and 1 or 1 / rate, rate <= 0 and 20 or nil)
		end
	end
end

function Presentation:Restore()
	for object, fields in pairs(self.properties) do
		if object.Parent then
			for property, field in pairs(fields) do
				if object[property] == field.last then object[property] = field.base end
			end
		end
	end
	for track, state in pairs(self.tracks) do
		pcall(function()
			if track.IsPlaying and track.Speed == state.last then track:AdjustSpeed(state.base) end
		end)
	end
	for sound, playing in pairs(self.sounds) do if sound.Parent and playing then sound:Resume() end end
	table.clear(self.sounds)
	table.clear(self.properties)
	table.clear(self.tracks)
end

function Presentation.Capture(model)
	local root = model:IsA("BasePart") and model or model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not root then return nil end
	local snapshot = { cframe = model:GetPivot(), velocity = root.AssemblyLinearVelocity, angular = root.AssemblyAngularVelocity, tracks = {} }
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			snapshot.tracks[track] = { time = track.TimePosition, weight = track.WeightCurrent, speed = track.Speed }
		end
	end
	return snapshot
end

function Presentation.Seek(model, a, b, alpha, move, presentation)
	if not a then return end
	if move then model:PivotTo(a.cframe:Lerp(b.cframe, alpha)) end
	for track, pose in pairs(a.tracks) do
		pcall(function()
			local nextPose = b.tracks[track] or pose
			if presentation and not presentation.tracks[track] then presentation.tracks[track] = { base = pose.speed or 1, last = 0 } end
			if not track.IsPlaying then track:Play(0, pose.weight, 0) end
			track:AdjustSpeed(0)
			track.TimePosition = pose.time + (nextPose.time - pose.time) * alpha
			track:AdjustWeight(pose.weight, 0)
		end)
	end
end

function Presentation.CaptureEffects(instances, character)
	local snapshot = {}
	for _, instance in ipairs(instances) do
		local objects = instance:GetDescendants()
		table.insert(objects, instance)
		for _, object in ipairs(objects) do
			if object:IsA("BasePart") and not object:IsDescendantOf(character) then
				snapshot[object] = { cframe = object.CFrame, size = object.Size, color = object.Color }
			end
		end
	end
	return snapshot
end

function Presentation.SeekEffects(a, b, alpha)
	for object, state in pairs(a or {}) do
		if object.Parent then
			local nextState = b and b[object] or state
			object.CFrame = state.cframe:Lerp(nextState.cframe, alpha)
			object.Size = state.size:Lerp(nextState.size, alpha)
			object.Color = state.color:Lerp(nextState.color, alpha)
		end
	end
end

return Presentation

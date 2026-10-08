-- Adapters for authored effects: entity-aware lifetimes, waits, and seekable tweens.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local EntityTime = require(script.Parent.EntityTime)
local EffectTime = {}

function EffectTime.Tween(instance, info, goals, owner)
	owner = EntityTime.Resolve(owner) or EntityTime.Resolve(instance)
	if not owner then return TweenService:Create(instance, info, goals) end
	local base = {}
	for property in pairs(goals) do base[property] = instance[property] end
	local completed = Instance.new("BindableEvent")
	local elapsed, connection = 0, nil
	local tween = { Completed = completed.Event, PlaybackState = Enum.PlaybackState.Begin }
	local function disconnect()
		if connection then connection:Disconnect(); connection = nil end
	end
	function tween:Play()
		if connection then return end
		if self.PlaybackState == Enum.PlaybackState.Completed or self.PlaybackState == Enum.PlaybackState.Cancelled then elapsed = 0 end
		self.PlaybackState = Enum.PlaybackState.Playing
		connection = RunService.Heartbeat:Connect(function(dt)
			if not instance.Parent then self:Cancel(); return end
			elapsed = math.max(0, elapsed + dt * EntityTime.GetVisualRate(owner))
			local leg = math.max(info.Time, 0.0001)
			local cycle = info.DelayTime + leg * (info.Reverses and 2 or 1)
			local finished = info.RepeatCount >= 0 and elapsed >= cycle * (info.RepeatCount + 1)
			local phase = finished and cycle or elapsed % cycle
			local alpha = math.clamp((phase - info.DelayTime) / leg, 0, info.Reverses and 2 or 1)
			if alpha > 1 then alpha = 2 - alpha end
			alpha = TweenService:GetValue(alpha, info.EasingStyle, info.EasingDirection)
			for property, goal in pairs(goals) do
				local start = base[property]
				if type(start) == "number" then instance[property] = start + (goal - start) * alpha
				elseif typeof(start) == "boolean" or typeof(start) == "EnumItem" then instance[property] = alpha >= 1 and goal or start
				else instance[property] = start:Lerp(goal, alpha) end
			end
			if finished then
				disconnect()
				self.PlaybackState = Enum.PlaybackState.Completed
				completed:Fire(self.PlaybackState)
			end
		end)
	end
	function tween:Pause()
		disconnect()
		self.PlaybackState = Enum.PlaybackState.Paused
	end
	function tween:Cancel()
		disconnect()
		elapsed = 0
		self.PlaybackState = Enum.PlaybackState.Cancelled
		completed:Fire(self.PlaybackState)
	end
	function tween:Destroy()
		disconnect()
		completed:Destroy()
	end
	return tween
end

return EffectTime

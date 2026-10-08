local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ComponentBase = require(script.Parent.Parent.Base)
local Framework = require(ReplicatedStorage.Modules.Framework)
local GlobalEnum = require(ReplicatedStorage.Modules.Data.GlobalEnum)
local AsteraComponentConstants = require(ReplicatedStorage.Modules.Data.AsteraComponentConstants)
local ReverseSkillEnum = GlobalEnum.ReverseEnum(GlobalEnum.SkillIDs)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MOVEMENT_CONSTANTS = AsteraComponentConstants.MovementComponent

local IsServer = RunService:IsServer()
local BOT_FLOOR_CAST_MARGIN = 0.75
local BOT_FLOOR_MIN_NORMAL_Y = 0.5
local BOT_FLOOR_CROSSING_TOLERANCE = 0.2
local BOT_FLOOR_MIN_SWEEP_DISTANCE = 0.75
local BOT_FLOOR_EMBED_CHECK_INTERVAL = 1
local BOT_FLOOR_EMBED_TOLERANCE = 0.2
local BOT_FLOOR_EMBED_MAX_UPWARD_SPEED = 0.5
local BOT_GROUND_RECOVERY_BLOCKED_STATES = {
	knock = true,
	knocked = true,
	carry = true,
	carried = true,
	grip = true,
	gripped = true,
	ragdoll = true,
	ragdolled = true,
}
local MovementComponent = ComponentBase:Extend()
MovementComponent.__index = MovementComponent
MovementComponent.Name = "AsteraMovementComponent"

---Resolves InjuryService from the runtime global first and Framework second.
local function resolveInjuryService()
	local service = _G.InjuryService
	if service then
		return service
	end
	local ok, resolved = pcall(Framework.GetService, "InjuryService")
	if ok then
		return resolved
	end
	return nil
end

---Maintains bot collision shape and corrects floor tunneling or shallow embedding outside incapacitated states.
function MovementComponent:StartBotGroundSafety()
	-- full method is omitted
end

---Reapplies the player's authoritative jump value to a live humanoid.
function MovementComponent:UpdateJump(SpeedType)
	if self.player.CharacterObject:FindFirstChild("Humanoid") then

		self.player:SetJump(self.player.Jump)
	end
end

---Recalculates live humanoid speed from the player's authoritative movement state.
function MovementComponent:UpdateWalkSpeed(SpeedType)
	if self.player.CharacterObject:FindFirstChild("Humanoid") then
		self.player:SetWalkSpeed(self.player.Speed)
	end
end

---Updates movement modifier value or mode and immediately recalculates walk speed.
function MovementComponent:SetModifier(Type,Value)
	if Type == "Mod" then
		self.player:SetValue("SpeedModifier",Value)
	elseif Type == "Type" then
		self.player:SetValue("SpeedModifierType",Value)
	end
	self.player:UpdateWalkSpeed()
end

---Records previous humanoid jump power and updates the authoritative jump value.
function MovementComponent:SetJump(Speed)
	if self.player.CharacterObject:FindFirstChild("Humanoid") then
		local Hum = self.player.CharacterObject.Humanoid
		self.player.UserData.PreviousVertical = Hum.JumpPower

		self.player:SetValue("Jump",Speed)

	end
end


---Applies additive, blocking, slowed, and injury movement modifiers to humanoid walk speed.
function MovementComponent:SetWalkSpeed(Speed)
	if self.player.CharacterObject:FindFirstChild("Humanoid") then
		local Hum = self.player.CharacterObject.Humanoid
		local Sum
		self.player.PreviousWalkspeed = Hum.WalkSpeed
		if self.player.SpeedModifierType == 1 then
			if self.player.CanMove == true then
				self.player.PreviousWalkspeed = Speed + self.player.SpeedModifier	
			end
			Sum = Speed + self.player.SpeedModifier	
			--self.player:SetValue("Speed", Sum)

		end
		local BlockDeduction = self.player.StatusEffects.Block.Value and -MOVEMENT_CONSTANTS.BlockSpeedPenalty or 0
		local SlowedDeduction = self.player.StatusEffects.Slowed.Stack * -MOVEMENT_CONSTANTS.SlowedStackSpeedPenalty
		local InjuryMultiplier = 1
		local injuryService = resolveInjuryService()
		if injuryService and type(injuryService.GetInjuryModifiers) == "function" then
			local derived = injuryService:GetInjuryModifiers(self.player)
			local modifiers = derived and derived.modifiers
			InjuryMultiplier = tonumber(modifiers and modifiers.movementSpeedMultiplier) or 1
		end
		if Hum then
			Hum.WalkSpeed = (Sum + (BlockDeduction + SlowedDeduction)) * InjuryMultiplier
		end

	end
end



return MovementComponent

-- Local movement layer: client input/lifecycle; state/remote dependencies remain external.
local EntityTime = require(game.ReplicatedStorage.Modules.Time.EntityTime)
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Client = ReplicatedFirst:WaitForChild("Client")

local BaseController = require(Client.Modules.BaseController)
local ClientStateStore = require(Client.Repository.Shared.ClientStateStore)
local RemoteBridge = require(Client.Repository.Shared.RemoteBridge)

local CharacterController = {}
CharacterController.__index = CharacterController
setmetatable(CharacterController, BaseController)

local FORCED_MOVEMENT_MAX_DISTANCE = 180
local FALLBACK_FORWARD = Vector3.new(0, 0, -1)
local FALLBACK_RIGHT = Vector3.new(1, 0, 0)

local function isStringBoolTrue(value)
	if type(value) == "boolean" then
		return value
	end
	local normalized = string.lower(tostring(value))
	return normalized == "true" or normalized == "1"
end

local function flattenAndNormalize(vector, fallback)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude <= 0.001 then
		return fallback
	end
	return flat.Unit
end

local function isIncapacitatedState(character)
	if not character then
		return false
	end
	local state = tostring(character:GetAttribute("CombatState") or "")
	return state == "knocked" or state == "carried" or state == "gripped"
end

local function applyHumanoidStateGates(humanoid, character)
	if not humanoid then
		return
	end
	local incapacitated = isIncapacitatedState(character)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, incapacitated)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, incapacitated)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, incapacitated)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, incapacitated)
end

function CharacterController.new()
	local self = BaseController.new("CharacterController")
	self.StateStore = ClientStateStore:GetSingleton()
	self.RemoteBridge = RemoteBridge.new("CharacterController")
	self.Player = Players.LocalPlayer
	self.IsSprinting = false
	self.CanSprintTick = tick()
	self.CurrentCharacter = nil
	self._inputBound = false
	return setmetatable(self, CharacterController)
end

function CharacterController:_getStatusNode(statusName)
	local playerData = self.StateStore:GetPlayerData()
	local statusFolder = playerData and playerData:FindFirstChild("StatusEffects")
	return statusFolder and statusFolder:FindFirstChild(statusName) or nil
end

function CharacterController:_isStatusActive(statusName)
	local statusNode = self:_getStatusNode(statusName)
	local valueNode = statusNode and statusNode:FindFirstChild("Value")
	return valueNode and isStringBoolTrue(valueNode.Value) or false
end

function CharacterController:_resolveNearestEnemyDirection(character, runAway)
	-- full method is omitted
end

function CharacterController:_getDesiredMoveDirectionFromKeys()
	local camera = workspace.CurrentCamera
	local forward = camera and camera.CFrame.LookVector or FALLBACK_FORWARD
	local right = camera and camera.CFrame.RightVector or FALLBACK_RIGHT
	forward = flattenAndNormalize(forward, FALLBACK_FORWARD)
	right = flattenAndNormalize(right, FALLBACK_RIGHT)

	local desiredDirection = Vector3.zero
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		desiredDirection += forward
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		desiredDirection -= forward
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		desiredDirection += right
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		desiredDirection -= right
	end

	if desiredDirection.Magnitude <= 0.001 then
		return nil
	end

	return desiredDirection.Unit
end

function CharacterController:_applyIllusoryMovement(character, humanoid, canMove)
	-- full method is omitted
end

function CharacterController:_setSprintState(character, sprinting)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local speed = self.StateStore:GetNumber("Speed", 16)
	local jump = self.StateStore:GetNumber("Jump", 50)
	self.IsSprinting = sprinting
	_G.IsSprinting = sprinting
	humanoid.JumpPower = jump * math.max(0, EntityTime.GetRate(humanoid))
	if sprinting then
		humanoid.WalkSpeed = math.clamp(speed * (30 / 21), 0, 50) * math.max(0, EntityTime.GetRate(humanoid))
	else
		humanoid.WalkSpeed = math.clamp(speed, 0, 21) * math.max(0, EntityTime.GetRate(humanoid))
	end
end

function CharacterController:_bindSprintSliding(character)
	self:Track(character:GetAttributeChangedSignal("TimeRate"):Connect(function()
		self:_setSprintState(character, self.IsSprinting)
	end))
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	self.CurrentCharacter = character

	local stateStore = self.StateStore
	local function canMove()
		local canMoveNode = stateStore:GetValueNode("CanMove")
		if not canMoveNode then
			return true
		end
		return tostring(canMoveNode.Value) == "true"
	end

	_G.BeginSprinting = function()
		if self.IsSprinting then
			return
		end
		if self.CanSprintTick > tick() then
			return
		end
		self:_setSprintState(character, true)
	end
	_G.StopSprinting = function()
		self:_setSprintState(character, false)
	end
	_G.BeginSliding = function()
		self.RemoteBridge:Invoke("Client/Slide", nil, true)
	end
	_G.StopSliding = function()
		self.RemoteBridge:Invoke("Client/Slide", nil, false)
	end

	local lastPressedW = tick()
	if not self._inputBound then
		self._inputBound = true
		self:Track(UserInputService.InputBegan:Connect(function(input, sunk)
			if sunk then
				return
			end

			if input.KeyCode == Enum.KeyCode.W and canMove() then
				if tick() - lastPressedW <= 0.25 then
					_G.BeginSprinting()
				end
				lastPressedW = tick()
			elseif input.KeyCode == Enum.KeyCode.LeftControl and canMove() then
				_G.BeginSliding()
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
				_G.StopSprinting()
				_G.StopSliding()
			end
		end))

		self:Track(UserInputService.InputEnded:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.LeftShift then
				_G.StopSliding()
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
				_G.StopSprinting()
				_G.StopSliding()
			end
		end))
	end

	self:Track(humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		if camera.CFrame.LookVector:Dot(humanoid.MoveDirection) < 0.25 and self.IsSprinting and canMove() then
			_G.StopSprinting()
		end
	end))

	self:Track(RunService.RenderStepped:Connect(function()
		if self.CurrentCharacter ~= character or not character.Parent then
			return
		end
		self:_applyIllusoryMovement(character, humanoid, canMove)
	end))
end

function CharacterController:_onCharacterAdded(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		applyHumanoidStateGates(humanoid, character)
		self:Track(character:GetAttributeChangedSignal("CombatState"):Connect(function()
			applyHumanoidStateGates(humanoid, character)
		end))
	end
	self:_bindSprintSliding(character)
end

function CharacterController:Start()
	if self:IsStarted() then
		return
	end

	self.StateStore:Load()
	if self.Player.Character then
		self:_onCharacterAdded(self.Player.Character)
	end
	self:Track(self.Player.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(character)
	end))

	BaseController.Start(self)
end

return CharacterController

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Class = require(ReplicatedStorage.Modules.Class)

local ComponentBase = Class:Extend()
ComponentBase.__index = ComponentBase
ComponentBase.Name = "ComponentBase"

---Creates an inactive component bound to its owning player and optional context.
function ComponentBase:New(player, ctx)
	local instance = setmetatable({}, self)
	instance.player = player
	instance.ctx = ctx
	instance.isActive = false
	return instance
end

---Lifecycle hook for component-specific initialization before Start is called.
function ComponentBase:Init(player, ctx)
	-- override if necessary
end

---Marks the component active after initialization.
function ComponentBase:Start()
	self.isActive = true
end

---Marks the component inactive without destroying it.
function ComponentBase:Stop()
	self.isActive = false
end

---Performs the base destruction contract by stopping the component.
function ComponentBase:Destroy()
	self:Stop()
end

return ComponentBase

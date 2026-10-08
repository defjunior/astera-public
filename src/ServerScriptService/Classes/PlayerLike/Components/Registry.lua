local ComponentRegistry = {}
ComponentRegistry.__index = ComponentRegistry
ComponentRegistry._registry = {}

---Registers a component class by name, warning when an existing registration is replaced.
function ComponentRegistry:Register(name, componentClass)
	if not name or not componentClass then
		error("[ComponentRegistry] Name and component class required.", 2)
	end
	if self._registry[name] then
		warn(("[ComponentRegistry] Component '%s' is already registered; overwriting."):format(name))
	end
	self._registry[name] = componentClass
end

function ComponentRegistry:Get(name)
	return self._registry[name]
end

function ComponentRegistry:IsRegistered(name)
	return self._registry[name] ~= nil
end

---Returns the live component registry table.
function ComponentRegistry:GetAll()
	return self._registry
end

return ComponentRegistry

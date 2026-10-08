local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TeleportContract = require(ReplicatedStorage.Modules.Data.TeleportContract)

local ContractValidator = {}
ContractValidator.Name = "ContractValidator"
ContractValidator.CurrentVersion = TeleportContract.Version

local ValidKinds = {}
for _, kind in pairs(TeleportContract.Kind) do
	ValidKinds[kind] = true
end

local ValidServerTypes = {}
for _, serverType in pairs(TeleportContract.ServerType) do
	ValidServerTypes[serverType] = true
end

local function isNonEmptyString(value)
	return type(value) == "string" and value ~= ""
end

local function isCompatibleVersion(v)
	return type(v) == "number" and v == ContractValidator.CurrentVersion
end

function ContractValidator:IsCompatibleVersion(v)
	return isCompatibleVersion(v)
end

function ContractValidator:Validate(contract)
	if type(contract) ~= "table" then
		return false, "Contract must be a table"
	end

	if not isCompatibleVersion(contract.v) then
		return false, ("Unsupported contract version (%s)"):format(tostring(contract.v))
	end

	if not isNonEmptyString(contract.kind) or not ValidKinds[contract.kind] then
		return false, ("Unknown contract kind (%s)"):format(tostring(contract.kind))
	end

	if not isNonEmptyString(contract.serverType) or not ValidServerTypes[contract.serverType] then
		return false, ("Unknown serverType (%s)"):format(tostring(contract.serverType))
	end

	if contract.from ~= nil and type(contract.from) ~= "table" then
		return false, "from metadata must be a table when present"
	end

	local kind = contract.kind
	local serverType = contract.serverType

	if kind == TeleportContract.Kind.MenuJoin then
		if serverType ~= TeleportContract.ServerType.Menu then
			return false, "MenuJoin must target serverType=Menu"
		end
		return true
	end

	if kind == TeleportContract.Kind.QuickJoinGame or kind == TeleportContract.Kind.JoinGameShard then
		if serverType ~= TeleportContract.ServerType.Game then
			return false, (kind .. " must target serverType=Game")
		end
		if not isNonEmptyString(contract.series) then
			return false, "Game contract requires series"
		end
		if not isNonEmptyString(contract.section) then
			return false, "Game contract requires section"
		end
		return true
	end

	if kind == TeleportContract.Kind.JoinRealm then
		if serverType ~= TeleportContract.ServerType.Game then
			return false, "JoinRealm must target serverType=Game"
		end
		if not isNonEmptyString(contract.realm) then
			return false, "JoinRealm requires realm"
		end
		return true
	end

	if kind == TeleportContract.Kind.CreateDungeon or kind == TeleportContract.Kind.JoinDungeon then
		if serverType ~= TeleportContract.ServerType.Dungeon then
			return false, (kind .. " must target serverType=Dungeon")
		end
		if not isNonEmptyString(tostring(contract.dungeonInstanceId or "")) then
			return false, "Dungeon contract requires dungeonInstanceId"
		end

		if kind == TeleportContract.Kind.CreateDungeon then
			if not isNonEmptyString(tostring(contract.dungeonTemplateId or "")) then
				return false, "CreateDungeon requires dungeonTemplateId"
			end
			if contract.seed == nil then
				return false, "CreateDungeon requires seed"
			end
		end

		return true
	end

	return false, "Unhandled contract kind"
end

return ContractValidator

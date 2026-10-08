local TeleportContract = {}

TeleportContract.Version = 1

TeleportContract.ServerType = {
	Menu = "Menu",
	Game = "Game",
	Dungeon = "Dungeon",
}

-- Omitted: authored realm catalog and default. Caller supplies Realm and DefaultRealm.
TeleportContract.Realm = {}
TeleportContract.DefaultRealm = nil

TeleportContract.Kind = {
	MenuJoin = "MenuJoin",
	QuickJoinGame = "QuickJoinGame",
	JoinGameShard = "JoinGameShard",
	CreateDungeon = "CreateDungeon",
	JoinDungeon = "JoinDungeon",
	JoinRealm = "JoinRealm",
}

local function applyOptions(contract, options)
	if type(options) ~= "table" then
		return contract
	end

	for key, value in pairs(options) do
		if value ~= nil then
			contract[key] = value
		end
	end
	return contract
end

local function buildBase(kind, serverType, options)
	local contract = {
		v = TeleportContract.Version,
		kind = kind,
		serverType = serverType,
		-- Realm default is supplied by the caller; options.realm may override.
		-- or the dedicated NewJoinRealm constructor.
		realm = TeleportContract.DefaultRealm,
	}
	return applyOptions(contract, options)
end

function TeleportContract.NewMenuJoin(options)
	-- Menus are realm-agnostic; blank the realm so ServerModeService doesn't
	-- accidentally pin a menu server to a specific realm's partition key.
	local contract = buildBase(TeleportContract.Kind.MenuJoin, TeleportContract.ServerType.Menu, options)
	contract.realm = contract.realm or TeleportContract.DefaultRealm
	return contract
end

function TeleportContract.NewQuickJoinGame(series, section, options)
	local contract = buildBase(TeleportContract.Kind.QuickJoinGame, TeleportContract.ServerType.Game, options)
	contract.series = series
	contract.section = section
	return contract
end

function TeleportContract.NewJoinGameShard(series, section, options)
	local contract = buildBase(TeleportContract.Kind.JoinGameShard, TeleportContract.ServerType.Game, options)
	contract.series = series
	contract.section = section
	return contract
end

-- Cross-realm jump. Used when a player falls into the void, triggers a
-- realm portal, or a quest sends them to another realm. The realm's
-- default series/section are used unless the caller overrides via options.
function TeleportContract.NewJoinRealm(realmName, options)
	local contract = buildBase(TeleportContract.Kind.JoinRealm, TeleportContract.ServerType.Game, options)
	contract.realm = realmName or TeleportContract.DefaultRealm
	return contract
end

function TeleportContract.NewCreateDungeon(dungeonTemplateId, dungeonInstanceId, options)
	local contract = buildBase(TeleportContract.Kind.CreateDungeon, TeleportContract.ServerType.Dungeon, options)
	contract.dungeonTemplateId = dungeonTemplateId
	contract.dungeonInstanceId = dungeonInstanceId
	return contract
end

function TeleportContract.NewJoinDungeon(dungeonTemplateId, dungeonInstanceId, options)
	local contract = buildBase(TeleportContract.Kind.JoinDungeon, TeleportContract.ServerType.Dungeon, options)
	contract.dungeonTemplateId = dungeonTemplateId
	contract.dungeonInstanceId = dungeonInstanceId
	return contract
end

return TeleportContract

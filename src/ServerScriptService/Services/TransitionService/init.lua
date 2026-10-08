local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

local Framework = require(ReplicatedStorage.Modules.Framework)
-- Omitted: game-specific transition effect dependency.
local TeleportContract = require(ReplicatedStorage.Modules.Data.TeleportContract)
local ContractValidator = require(script.ContractValidator)

local TransitionService = {}
TransitionService.Name = "TransitionService"

local function ensureStarted()
	if not TransitionService._started then
		TransitionService:Start()
	end
end

-- Omitted: destination IDs, authored series/section defaults and retry tuning.
-- Supply a reviewed runtime config through ServerModeService.
local DefaultRuntimeConfig = {}

local islandCatalogByName = nil
local layoutModule = nil
local getIslandCatalog

local function ordinal(n)
	local value = math.max(1, math.floor(tonumber(n) or 1))
	local twoDigits = value % 100
	if twoDigits >= 11 and twoDigits <= 13 then
		return tostring(value) .. "th"
	end
	local last = value % 10
	if last == 1 then
		return tostring(value) .. "st"
	elseif last == 2 then
		return tostring(value) .. "nd"
	elseif last == 3 then
		return tostring(value) .. "rd"
	end
	return tostring(value) .. "th"
end

local function seriesNameFromIndex(seriesIndex)
	return ("%s Astral Series"):format(ordinal(seriesIndex))
end

local function getLayout()
	if layoutModule then
		return layoutModule
	end
	local okLayout, islandLayout = pcall(function()
		return require(ServerScriptService.WorldGeneration.Modules.IslandLayout)
	end)
	if not okLayout or type(islandLayout) ~= "table" then
		return nil
	end
	layoutModule = islandLayout
	return layoutModule
end

local function getMainlands()
	local islandLayout = getLayout()
	if not islandLayout then
		return {}
	end

	local list = nil
	if type(islandLayout.mainlands) == "function" then
		list = islandLayout.mainlands()
	elseif type(islandLayout.list) == "function" then
		list = islandLayout.list()
	end
	if type(list) ~= "table" then
		return {}
	end

	local mainlands = {}
	for _, spec in ipairs(list) do
		if type(spec) == "table" and spec.name and not spec.isSkylist then
			mainlands[#mainlands + 1] = spec
		end
	end
	table.sort(mainlands, function(a, b)
		return (tonumber(a.index) or 0) < (tonumber(b.index) or 0)
	end)
	return mainlands
end

local function getFirstMainland()
	local mainlands = getMainlands()
	return mainlands[1]
end

local function applyIslandDefaults(runtimeConfig)
	if type(runtimeConfig) ~= "table" then
		return runtimeConfig
	end

	local firstMainland = getFirstMainland()
	if firstMainland then
		local islands = getIslandCatalog()
		local sectionText = tostring(runtimeConfig.DefaultGameSection or "")
		local island = sectionText ~= "" and islands[string.lower(sectionText)] or nil
		if not island then
			runtimeConfig.DefaultGameSection = tostring(firstMainland.name)
			island = islands[string.lower(runtimeConfig.DefaultGameSection)]
		end
		if island and island.seriesName then
			runtimeConfig.DefaultGameSeries = island.seriesName
		elseif type(runtimeConfig.DefaultGameSeries) ~= "string" or runtimeConfig.DefaultGameSeries == "" then
			runtimeConfig.DefaultGameSeries = seriesNameFromIndex(firstMainland.seriesIndex)
		end
	end

	if type(runtimeConfig.DefaultGameSeries) ~= "string" or runtimeConfig.DefaultGameSeries == "" then
		runtimeConfig.DefaultGameSeries = DefaultRuntimeConfig.DefaultGameSeries
	end
	if type(runtimeConfig.DefaultGameSection) ~= "string" or runtimeConfig.DefaultGameSection == "" then
		runtimeConfig.DefaultGameSection = DefaultRuntimeConfig.DefaultGameSection
	end

	return runtimeConfig
end

local function buildLegacySectionAliases()
	local aliases = {}
	for i, spec in ipairs(getMainlands()) do
		aliases["section" .. tostring(i)] = tostring(spec.name)
		aliases[tostring(i)] = tostring(spec.name)
	end
	return aliases
end

local function rebuildIslandCatalog()
	local byName = {}
	for _, spec in ipairs(getMainlands()) do
		byName[string.lower(tostring(spec.name))] = {
			name = tostring(spec.name),
			seriesIndex = tonumber(spec.seriesIndex) or 1,
			seriesName = seriesNameFromIndex(spec.seriesIndex),
		}
	end
	return byName
end

getIslandCatalog = function()
	if islandCatalogByName ~= nil and next(islandCatalogByName) ~= nil then
		return islandCatalogByName
	end
	local rebuilt = rebuildIslandCatalog() or {}
	if islandCatalogByName == nil or next(rebuilt) ~= nil then
		islandCatalogByName = rebuilt
	end
	return islandCatalogByName
end

local function canonicalSection(section, fallbackSection)
	local text = tostring(section or "")
	if text == "" then
		text = tostring(fallbackSection or "")
	end
	local lowered = string.lower(text)
	local legacyAliases = buildLegacySectionAliases()
	if legacyAliases[lowered] then
		text = legacyAliases[lowered]
	end

	local islands = getIslandCatalog()
	local match = islands[string.lower(text)]
	if match then
		return match.name, match
	end

	local defaultMatch = islands[string.lower(tostring(fallbackSection or ""))]
	if defaultMatch then
		return defaultMatch.name, defaultMatch
	end

	return text, nil
end

local function canonicalSeries(series, fallbackSeries, matchedIsland)
	if matchedIsland and matchedIsland.seriesName then
		return matchedIsland.seriesName
	end

	local text = tostring(series or "")
	if text == "" then
		text = tostring(fallbackSeries or "")
	end
	return text
end

local function resolveSeriesSection(runtimeConfig, requestedSeries, requestedSection)
	runtimeConfig = applyIslandDefaults(runtimeConfig)
	local fallbackSeries = runtimeConfig and runtimeConfig.DefaultGameSeries or DefaultRuntimeConfig.DefaultGameSeries
	local fallbackSection = runtimeConfig and runtimeConfig.DefaultGameSection or DefaultRuntimeConfig.DefaultGameSection
	local sectionName, island = canonicalSection(requestedSection, fallbackSection)
	local seriesName = canonicalSeries(requestedSeries, fallbackSeries, island)
	return seriesName, sectionName, island
end

local function resolveSlotSeriesSection(player, slotId)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil, nil, nil
	end

	local resolvedSlotId = tonumber(slotId)
	if not resolvedSlotId then
		return nil, nil, nil
	end

	local gPlayer = _G.Players and _G.Players[player.UserId] or nil
	if type(gPlayer) ~= "table" then
		return nil, nil, nil
	end
	local savedData = gPlayer.SavedData
	if type(savedData) ~= "table" or type(savedData.CharacterSlots) ~= "table" then
		return nil, nil, nil
	end
	local slotData = savedData.CharacterSlots[resolvedSlotId]
	if type(slotData) ~= "table" then
		return nil, nil, nil
	end
	local currentPosition = slotData.CurrentPosition
	if type(currentPosition) ~= "table" then
		return nil, nil, nil
	end

	local islandLayout = getLayout()
	if not islandLayout then
		return nil, nil, nil
	end

	local spec = nil
	local islandIndex = tonumber(currentPosition.Island)
	if islandIndex and islandIndex > 0 and type(islandLayout.getByIndex) == "function" then
		spec = islandLayout.getByIndex(islandIndex)
	end
	if type(spec) ~= "table" and type(currentPosition.Island) == "string" and currentPosition.Island ~= "" then
		if type(islandLayout.getByName) == "function" then
			spec = islandLayout.getByName(currentPosition.Island)
		end
	end
	if type(spec) ~= "table" then
		return nil, nil, nil
	end
	if spec.isSkylist == true and spec.parentIslandIndex and type(islandLayout.getByIndex) == "function" then
		local parentSpec = islandLayout.getByIndex(spec.parentIslandIndex)
		if type(parentSpec) == "table" then
			spec = parentSpec
		end
	end

	local section = tostring(spec.name or "")
	if section == "" then
		return nil, nil, nil
	end
	return seriesNameFromIndex(spec.seriesIndex), section, spec
end

local function isPlayer(value)
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function copyTable(input)
	if type(input) ~= "table" then
		return nil
	end

	local output = {}
	for key, value in pairs(input) do
		if type(value) == "table" then
			output[key] = copyTable(value)
		else
			output[key] = value
		end
	end
	return output
end

local function getRuntimeConfig()
	local ok, serverModeService = pcall(Framework.GetService, "ServerModeService")
	if ok and serverModeService and type(serverModeService.GetRuntimeConfig) == "function" then
		local runtimeConfig = serverModeService:GetRuntimeConfig()
		if type(runtimeConfig) == "table" then
			return applyIslandDefaults(runtimeConfig)
		end
	end
	return applyIslandDefaults(DefaultRuntimeConfig)
end

-- Omitted: carry/grip release and authored menu-fade/effect glue.
local function releaseCombatStateForTeleport(players) end
local function playMenuReturnFade(players) return false end

local function attachRuntimeSnapshotToContract(contract, players, reason)
	if type(contract) ~= "table" then
		return contract
	end

	if type(contract.runtimeByUserId) == "table" then
		return contract
	end

	local persistenceService = nil
	pcall(function()
		persistenceService = Framework.GetService("PersistenceService")
	end)
	if persistenceService and type(persistenceService.BuildTeleportRuntimePayload) == "function" then
		local ok, payload = pcall(function()
			return persistenceService:BuildTeleportRuntimePayload(players, reason)
		end)
		if ok and type(payload) == "table" and next(payload) ~= nil then
			contract.runtimeByUserId = payload
			contract.runtimeCapturedAt = os.time()
			contract.runtimeCaptureReason = tostring(reason or "")
		end
	end

	return contract
end

function TransitionService:_normalizePlayers(playerOrParty)
	local output = {}
	local seen = {}

	local function addPlayer(entry)
		local player = nil

		if isPlayer(entry) then
			player = entry
		elseif type(entry) == "number" then
			player = Players:GetPlayerByUserId(entry)
		elseif type(entry) == "table" then
			if isPlayer(entry.PlayerObject) then
				player = entry.PlayerObject
			elseif type(entry.UserId) == "number" then
				player = Players:GetPlayerByUserId(entry.UserId)
			end
		end

		if player and player.Parent and not seen[player.UserId] then
			seen[player.UserId] = true
			table.insert(output, player)
		end
	end

	if isPlayer(playerOrParty) or type(playerOrParty) == "number" then
		addPlayer(playerOrParty)
	elseif type(playerOrParty) == "table" and playerOrParty.UserId then
		addPlayer(playerOrParty)
	elseif type(playerOrParty) == "table" then
		for _, entry in ipairs(playerOrParty) do
			addPlayer(entry)
		end
	end

	return output
end

function TransitionService:_buildFromMetadata(reason)
	local modeService = Framework.GetService("ServerModeService")
	local context = modeService:GetServerContext() or {}
	return {
		placeId = game.PlaceId,
		jobId = game.JobId,
		serverType = context.ServerType,
		partitionKey = context.PartitionKey,
		serverName = context.ServerName,
		reason = reason,
		timestamp = os.time(),
	}
end

function TransitionService:_validateContract(contract)
	local ok, err = ContractValidator:Validate(contract)
	if not ok then
		return false, "InvalidContract:" .. tostring(err)
	end
	return true
end

local function buildTeleportOptions(contract, target)
	local options = Instance.new("TeleportOptions")
	options:SetTeleportData(contract)

	if type(target) == "table" then
		if type(target.serverInstanceId) == "string" and target.serverInstanceId ~= "" then
			options.ServerInstanceId = target.serverInstanceId
		end
		if type(target.reservedServerAccessCode) == "string" and target.reservedServerAccessCode ~= "" then
			options.ReservedServerAccessCode = target.reservedServerAccessCode
		end
	end

	return options
end

function TransitionService:_teleportAsync(placeId, players, contract, target, options)
	contract = attachRuntimeSnapshotToContract(contract, players, "TeleportAsync")
	local okContract, errContract = self:_validateContract(contract)
	if not okContract then
		return false, errContract
	end
	releaseCombatStateForTeleport(players)

	local teleportDelay = 0
	local transitionOptions = type(options) == "table" and options or {}
	-- Omitted: authored Starlink teleport visual and timing.
	if teleportDelay > 0 then
		task.wait(teleportDelay)
	end

	local options = buildTeleportOptions(contract, target)
	local okTeleport, errTeleport = pcall(function()
		TeleportService:TeleportAsync(placeId, players, options)
	end)
	if not okTeleport then
		return false, errTeleport
	end

	if transitionOptions.visual == "menuReturnFade" then
		playMenuReturnFade(players)
	end

	return true
end

function TransitionService:_teleportToPlaceInstance(placeId, jobId, players, contract)
	return self:_teleportAsync(placeId, players, contract, {
		serverInstanceId = jobId,
	})
end

function TransitionService:_teleportToPrivateServer(placeId, reservedCode, players, contract)
	return self:_teleportAsync(placeId, players, contract, {
		reservedServerAccessCode = reservedCode,
	})
end

function TransitionService:_clearRetryPlan(plan)
	if not plan then
		return
	end

	self._retryPlansById[plan.id] = nil
	for _, userId in ipairs(plan.userIds) do
		self._retryPlanByUserId[userId] = nil
	end
end

function TransitionService:_runRetryPlan(plan)
	plan.index += 1
	local attempt = plan.attempts[plan.index]
	if not attempt then
		self:_clearRetryPlan(plan)
		return false, "NoAttemptsLeft"
	end

	local ok, err = attempt.fn()
	if not ok then
		warn(
			("[TransitionService] Teleport attempt failed (%s/%d) [%s]: %s"):format(
				tostring(plan.index),
				#plan.attempts,
				tostring(plan.label),
				tostring(err)
			)
		)
		if plan.index >= #plan.attempts then
			self:_clearRetryPlan(plan)
			return false, err
		end
		return self:_runRetryPlan(plan)
	end
	return ok, err
end

function TransitionService:_startRetryPlan(players, attempts, label)
	if #players == 0 then
		return false, "NoPlayers"
	end
	if #attempts == 0 then
		return false, "NoTeleportAttempts"
	end

	local planId = HttpService:GenerateGUID(false)
	local userIds = {}
	for _, player in ipairs(players) do
		table.insert(userIds, player.UserId)
	end

	local plan = {
		id = planId,
		label = label or "TeleportPlan",
		players = players,
		userIds = userIds,
		leaderUserId = userIds[1],
		attempts = attempts,
		index = 0,
		retrying = false,
		createdAt = os.clock(),
	}

	self._retryPlansById[plan.id] = plan
	for _, userId in ipairs(userIds) do
		self._retryPlanByUserId[userId] = plan
	end

	local ok, err = self:_runRetryPlan(plan)
	if not ok and plan.index >= #plan.attempts then
		self:_clearRetryPlan(plan)
		return false, err
	end

	task.delay(30, function()
		if self._retryPlansById[plan.id] then
			self:_clearRetryPlan(plan)
		end
	end)

	return ok, err
end

function TransitionService:ToMenu(playerOrParty, reason)
	ensureStarted()
	local players = self:_normalizePlayers(playerOrParty)
	if #players == 0 then
		return false, "NoPlayers"
	end
	local runtimeConfig = getRuntimeConfig()
	local contract = TeleportContract.NewMenuJoin({
		from = self:_buildFromMetadata(reason or "ToMenu"),
	})
	return self:_teleportAsync(runtimeConfig.MenuPlaceId, players, contract, nil, {
		visual = "menuReturnFade",
	})
end

function TransitionService:JoinGameShard(playerOrParty, target, opts)
	ensureStarted()
	local players = self:_normalizePlayers(playerOrParty)
	if #players == 0 then
		return false, "NoPlayers"
	end

	local options = opts or {}
	local targetTable = type(target) == "table" and target or {}
	local runtimeConfig = getRuntimeConfig()
	local targetJobId = targetTable.jobId or (type(target) == "string" and target) or options.jobId
	local reservedCode = targetTable.reservedServerCode or options.reservedServerCode
	local placeId = targetTable.placeId or options.placeId or runtimeConfig.GamePlaceId
	local requestedSeries = options.series or targetTable.series
	local requestedSection = options.section or targetTable.section or options.island or targetTable.island
	local requestedSlotId = tonumber(options.slotId)
	local series, section, island = resolveSeriesSection(runtimeConfig, requestedSeries, requestedSection)
	local slotSeries, slotSection, slotIsland = resolveSlotSeriesSection(players[1], requestedSlotId)
	if slotSeries and slotSection then
		series = slotSeries
		section = slotSection
		island = slotIsland
	end

	local contract = TeleportContract.NewJoinGameShard(series, section, {
		targetJobId = targetJobId,
		seriesIndex = island and island.seriesIndex or nil,
		islandName = section,
		slotId = requestedSlotId,
		from = self:_buildFromMetadata("JoinGameShard"),
	})

	if reservedCode then
		return self:_teleportToPrivateServer(placeId, reservedCode, players, contract)
	end

	if targetJobId then
		return self:_teleportToPlaceInstance(placeId, targetJobId, players, contract)
	end

	return self:_teleportAsync(placeId, players, contract)
end

function TransitionService:QuickJoinGame(playerOrParty, series, section, opts)
	ensureStarted()
	local players = self:_normalizePlayers(playerOrParty)
	if #players == 0 then
		return false, "NoPlayers"
	end

	local options = opts or {}
	local runtimeConfig = getRuntimeConfig()
	local requestedSeries = series or options.series
	local requestedSection = section or options.section or options.island
	local requestedSlotId = tonumber(options.slotId)
	local resolvedSeries, resolvedSection, resolvedIsland =
		resolveSeriesSection(runtimeConfig, requestedSeries, requestedSection)
	local slotSeries, slotSection, slotIsland = resolveSlotSeriesSection(players[1], requestedSlotId)
	if slotSeries and slotSection then
		resolvedSeries = slotSeries
		resolvedSection = slotSection
		resolvedIsland = slotIsland
	end
	local partySize = math.max(1, tonumber(options.partySize) or #players)

	local modeService = Framework.GetService("ServerModeService")
	local context = modeService:GetServerContext() or {}
	local realm = context.Realm or runtimeConfig.DefaultRealm or TeleportContract.DefaultRealm
	local partitionKey = modeService:BuildGamePartitionKey(resolvedSeries, resolvedSection, realm)
	local serverListService = Framework.GetService("ServerListService")
	local attempts = {}
	local maxCandidates = math.max(1, tonumber(options.maxCandidates) or runtimeConfig.QuickJoinRetryCount)
	local candidateCount = 0
	local usedJobIds = {}

	local primaryTarget = serverListService:FindQuickJoinTarget(partitionKey, partySize)
	if primaryTarget and primaryTarget.jobId then
		usedJobIds[primaryTarget.jobId] = true
		candidateCount += 1
		local candidate = copyTable(primaryTarget)
		table.insert(attempts, {
			fn = function()
				local joinContract = TeleportContract.NewJoinGameShard(resolvedSeries, resolvedSection, {
					targetJobId = candidate.jobId,
					seriesIndex = resolvedIsland and resolvedIsland.seriesIndex or nil,
					islandName = resolvedSection,
					slotId = requestedSlotId,
					from = self:_buildFromMetadata("QuickJoinGame/PrimaryShard"),
				})
				return self:_teleportToPlaceInstance(candidate.placeId or runtimeConfig.GamePlaceId, candidate.jobId, players, joinContract)
			end,
		})
	end

	local candidates = serverListService:GetServersForPartition(partitionKey)

	for _, advert in ipairs(candidates) do
		if candidateCount >= maxCandidates then
			break
		end
		local hasCapacity = ((tonumber(advert.playerCount) or 0) + partySize) <= (tonumber(advert.maxPlayers) or 0)
		local isOtherServer = advert.jobId ~= game.JobId
		local unused = advert.jobId and not usedJobIds[advert.jobId]
		if hasCapacity and isOtherServer and unused then
			candidateCount += 1
			usedJobIds[advert.jobId] = true
			local candidate = copyTable(advert)
			table.insert(attempts, {
				fn = function()
					local joinContract = TeleportContract.NewJoinGameShard(resolvedSeries, resolvedSection, {
						targetJobId = candidate.jobId,
						seriesIndex = resolvedIsland and resolvedIsland.seriesIndex or nil,
						islandName = resolvedSection,
						slotId = requestedSlotId,
						from = self:_buildFromMetadata("QuickJoinGame/JoinGameShard"),
					})
					return self:_teleportToPlaceInstance(candidate.placeId or runtimeConfig.GamePlaceId, candidate.jobId, players, joinContract)
				end,
			})
		end
	end

	table.insert(attempts, {
		fn = function()
			local quickJoinContract = TeleportContract.NewQuickJoinGame(resolvedSeries, resolvedSection, {
				seriesIndex = resolvedIsland and resolvedIsland.seriesIndex or nil,
				islandName = resolvedSection,
				slotId = requestedSlotId,
				from = self:_buildFromMetadata("QuickJoinGame/Fallback"),
			})
			return self:_teleportAsync(runtimeConfig.GamePlaceId, players, quickJoinContract)
		end,
	})

	return self:_startRetryPlan(players, attempts, "QuickJoinGame")
end

function TransitionService:CreateDungeonAndTeleport(party, dungeonTemplateId, opts)
	ensureStarted()
	local players = self:_normalizePlayers(party)
	if #players == 0 then
		return false, "NoPlayers"
	end

	local options = opts or {}
	local runtimeConfig = getRuntimeConfig()
	local placeId = options.placeId or runtimeConfig.DungeonPlaceId

	local okReserve, reserveCodeOrError = pcall(function()
		return TeleportService:ReserveServer(placeId)
	end)
	if not okReserve then
		return false, reserveCodeOrError
	end

	local reservedServerCode = reserveCodeOrError
	local dungeonInstanceId = tostring(options.dungeonInstanceId or HttpService:GenerateGUID(false))
	local seed = options.seed or Random.new():NextInteger(1, 2147483646)
	local partyId = options.partyId

	local bootContract = {
		v = runtimeConfig.ContractVersion,
		serverType = "Dungeon",
		kind = "CreateDungeon",
		dungeonTemplateId = tostring(dungeonTemplateId),
		dungeonInstanceId = dungeonInstanceId,
		reservedServerCode = reservedServerCode,
		seed = seed,
		partyId = partyId,
		difficulty = options.difficulty,
		modifiers = options.modifiers,
		createdBy = players[1].UserId,
		createdAt = os.time(),
	}

	local registry = Framework.GetService("DungeonInstanceRegistry")
	local okRegister, errRegister = registry:RegisterInstance(bootContract, options.ttlSeconds)
	if not okRegister then
		return false, errRegister
	end

	local contract = TeleportContract.NewCreateDungeon(dungeonTemplateId, dungeonInstanceId, {
		seed = seed,
		partyId = partyId,
		reservedServerCode = reservedServerCode,
		difficulty = options.difficulty,
		modifiers = options.modifiers,
		from = self:_buildFromMetadata("CreateDungeon"),
	})

	local okTeleport, errTeleport = self:_teleportToPrivateServer(placeId, reservedServerCode, players, contract)
	if not okTeleport then
		return false, errTeleport
	end

	return true, {
		dungeonInstanceId = dungeonInstanceId,
		reservedServerCode = reservedServerCode,
		seed = seed,
	}
end

-- Cross-realm teleport. Used by VoidFallService and quest-driven realm
-- portals. The contract is QuickJoin-style (no targetJobId) so players land
-- in any available server for the target realm's default series/section.
-- If the realm has no deployed PlaceId (placeId == 0), the call fails so
-- the caller can fall back to an in-place respawn.
function TransitionService:ToRealm(playerOrParty, realmName, opts)
	ensureStarted()
	local players = self:_normalizePlayers(playerOrParty)
	if #players == 0 then
		return false, "NoPlayers"
	end

	local Realms = require(game.ServerScriptService.Services.ServerBootService.Realms)
	local realmCfg = Realms.getConfig(realmName)
	if not realmCfg then
		return false, "UnknownRealm:" .. tostring(realmName)
	end

	local placeId = realmCfg.placeId or 0
	-- Omitted: realm-specific undeployed-place fallback.

	if placeId <= 0 then
		return false, "RealmPlaceNotDeployed:" .. tostring(realmName)
	end

	local options = opts or {}
	local contract = TeleportContract.NewJoinRealm(realmCfg.name or realmName, {
		series = options.series or realmCfg.defaultSeries,
		section = options.section or realmCfg.defaultSection,
		from = self:_buildFromMetadata(options.reason or "ToRealm"),
	})

	return self:_teleportAsync(placeId, players, contract)
end

function TransitionService:JoinDungeon(party, dungeonInstanceIdOrJoinCode, opts)
	ensureStarted()
	local players = self:_normalizePlayers(party)
	if #players == 0 then
		return false, "NoPlayers"
	end

	local options = opts or {}
	local runtimeConfig = getRuntimeConfig()
	local identifier = dungeonInstanceIdOrJoinCode
	local registry = Framework.GetService("DungeonInstanceRegistry")
	local bootInfo

	if type(identifier) == "table" then
		if identifier.dungeonInstanceId then
			bootInfo = registry:GetByDungeonInstanceId(identifier.dungeonInstanceId)
		elseif identifier.reservedServerCode then
			bootInfo = registry:GetByReservedCode(identifier.reservedServerCode)
		end
	elseif type(identifier) == "string" then
		bootInfo = registry:GetByDungeonInstanceId(identifier) or registry:GetByReservedCode(identifier)
	end

	if not bootInfo and type(identifier) == "table" then
		bootInfo = copyTable(identifier)
	end
	if not bootInfo then
		return false, "DungeonInstanceNotFound"
	end

	local placeId = options.placeId or runtimeConfig.DungeonPlaceId
	local contract = TeleportContract.NewJoinDungeon(bootInfo.dungeonTemplateId, bootInfo.dungeonInstanceId, {
		seed = bootInfo.seed,
		partyId = bootInfo.partyId,
		reservedServerCode = bootInfo.reservedServerCode,
		difficulty = bootInfo.difficulty,
		modifiers = bootInfo.modifiers,
		from = self:_buildFromMetadata("JoinDungeon"),
	})

	if bootInfo.reservedServerCode then
		return self:_teleportToPrivateServer(placeId, bootInfo.reservedServerCode, players, contract)
	end
	return self:_teleportAsync(placeId, players, contract)
end

local function onQuickJoinGame(ctx, seriesOrRequest, section)
	if type(seriesOrRequest) == "table" then
		local request = seriesOrRequest
		local requestedSeries = type(request.series) == "string" and request.series or nil
		local requestedSection = type(request.section) == "string" and request.section
			or (type(request.island) == "string" and request.island or nil)
		local opts = {}
		if request.slotId ~= nil then
			opts.slotId = request.slotId
		end
		return TransitionService:QuickJoinGame(ctx.player, requestedSeries, requestedSection, opts)
	end
	return TransitionService:QuickJoinGame(ctx.player, seriesOrRequest, section)
end

-- Direct-shard join. The client picks a specific server from the server
-- browser (Client/GetServerList) and asks to teleport to that jobId. We do
-- NOT trust the client's placeId — the server looks the jobId up in
-- ServerListService for the requested partition and passes the advertised
-- record to JoinGameShard. An unknown jobId fails with ShardNotFound.
local function onJoinGameShard(ctx, request)
	if type(request) ~= "table" then
		return false, "InvalidRequest"
	end
	local jobId = type(request.jobId) == "string" and request.jobId or nil
	if not jobId or jobId == "" then
		return false, "InvalidJobId"
	end

	local serverListService = Framework.GetService("ServerListService")
	if not serverListService then
		return false, "ServerListUnavailable"
	end

	local modeService = Framework.GetService("ServerModeService")
	local runtimeConfig = modeService:GetRuntimeConfig()
	local requestedSeries = type(request.series) == "string" and request.series or runtimeConfig.DefaultGameSeries
	local requestedSection = type(request.section) == "string" and request.section or runtimeConfig.DefaultGameSection
	local series, section = resolveSeriesSection(runtimeConfig, requestedSeries, requestedSection)
	local slotSeries, slotSection = resolveSlotSeriesSection(ctx.player, request.slotId)
	if slotSeries and slotSection then
		series = slotSeries
		section = slotSection
	end
	local context = modeService:GetServerContext() or {}
	local realm = context.Realm or runtimeConfig.DefaultRealm or TeleportContract.DefaultRealm
	local partitionKey = modeService:BuildGamePartitionKey(series, section, realm)

	local adverts = serverListService:GetServersForPartition(partitionKey)
	if type(adverts) == "table" then
		for _, advert in ipairs(adverts) do
			if advert and advert.jobId == jobId then
				return TransitionService:JoinGameShard(ctx.player, advert, {
					series = series,
					section = section,
					slotId = request.slotId,
				})
			end
		end
	end
	return false, "ShardNotFound"
end

local function onToMenu(ctx, reason)
	return TransitionService:ToMenu(ctx.player, reason)
end

local function onEnterDungeon(ctx, templateId)
	-- Omitted: authored default dungeon template ID.
	local defaultTemplateId = tostring(templateId)
	local partyId = tostring(ctx.player.UserId)
	return TransitionService:CreateDungeonAndTeleport({ ctx.player }, defaultTemplateId, { partyId = partyId })
end

function TransitionService:RegisterEndpoints(eventService)
	ensureStarted()
	eventService:RegisterFunction("Client/QuickJoinGame", onQuickJoinGame, {
		guard = { gp = false },
		rateLimit = { capacity = 3, refillPerSec = 1 },
	})
	eventService:RegisterFunction("Client/JoinGameShard", onJoinGameShard, {
		guard = { gp = false },
		rateLimit = { capacity = 3, refillPerSec = 1 },
	})
	eventService:RegisterFunction("Client/ToMenu", onToMenu, {
		guard = { gp = false },
		rateLimit = { capacity = 3, refillPerSec = 1 },
	})
	eventService:RegisterFunction("Client/EnterDungeon", onEnterDungeon, {
		guard = { gp = false },
		rateLimit = { capacity = 2, refillPerSec = 0.5 },
	})
end

function TransitionService:_onTeleportInitFailed(player, teleportResult, errorMessage)
	local plan = self._retryPlanByUserId[player.UserId]
	if not plan then
		return
	end

	if plan.leaderUserId ~= player.UserId then
		return
	end

	if plan.retrying then
		return
	end

	if plan.index >= #plan.attempts then
		self:_clearRetryPlan(plan)
		return
	end

	plan.retrying = true
	warn(
		("[TransitionService] TeleportInitFailed leader=%s result=%s error=%s retrying=%d/%d"):format(
			player.Name,
			tostring(teleportResult),
			tostring(errorMessage),
			plan.index,
			#plan.attempts
		)
	)

	task.delay(0.25, function()
		plan.retrying = false
		local ok = self:_runRetryPlan(plan)
		if not ok and plan.index >= #plan.attempts then
			self:_clearRetryPlan(plan)
		end
	end)
end

function TransitionService:Start()
	if self._started then
		return
	end
	self._started = true
	self._retryPlansById = {}
	self._retryPlanByUserId = {}

	TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, errorMessage)
		self:_onTeleportInitFailed(player, teleportResult, errorMessage)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local plan = self._retryPlanByUserId[player.UserId]
		if plan and plan.leaderUserId == player.UserId then
			self:_clearRetryPlan(plan)
		else
			self._retryPlanByUserId[player.UserId] = nil
		end
	end)
end

function TransitionService.init()
	if TransitionService._booted then
		return
	end
	TransitionService._booted = true
	_G.TransitionService = TransitionService
	TransitionService:Start()
end

return TransitionService

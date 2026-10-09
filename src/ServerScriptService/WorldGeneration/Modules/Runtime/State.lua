local module = {
	-- Legacy single-seed field. Retained for backcompat with call sites
	-- that still do `Random.new(state.Seed + offset)`; those will migrate
	-- to the RNGContext hierarchy during Phases 1/3. New code must read
	-- from WorldSeed / ServerSeed / RNG below.
	-- EXCLUDED: authored seed, geometry, palette and density defaults.
	-- Required shape: seeds, RNG handles, island position/size, cell/grid size, terrain/prop settings.
	-- RNG: root RNGContext for the server. Populated at boot alongside the
	-- seeds above. Consumers derive child contexts via
	-- `state.RNG:derive("series", s):derive("island", i):derive("mainland", "heightfield")`.
	-- nil until bootstrap runs.
	RNG = nil,
	WorldRNG = nil,   -- derived from WorldSeed (mainland / shared pass)
	ServerRNG = nil,  -- derived from ServerSeed (skylist / variation pass)

	-- IslandLayout: convenience handle to the world's island topology.
	-- Pinned at boot from WorldGeneration/init.server.lua. nil until then.
	IslandLayout = nil,

	GetBiomeAt = function(x,z)
		-- Falls through to BiomeResolver in HeightSampler; this remains
		-- for backwards compat with structure rules lookup
		local ok, BiomeResolver = pcall(require, script.Parent.Parent.BiomeResolver)
		if ok and BiomeResolver then
			return BiomeResolver.getBiomeName(x, z)
		end
		return "Plains"
	end,
	StructureRules = {
 -- EXCLUDED: authored content/settings table, at the owner's request.
 -- General structure: biome-indexed structure placement definitions: macro/jitter/probability, canPlace callback, weighted structures with footprint/offset/yaw/spacing settings
 -- Intentionally empty, not a runnable replacement. See CONTENT-SCHEMAS.md.
},
	ResolvePrefab = function(id)
		-- Resolve a caller-owned prefab identifier to a Model.
		return script.Parent.Parent.Parent.Prefabs:FindFirstChild(id)
	end
}
--print(module.Seed)
return module

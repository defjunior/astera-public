-- Partial source showcase, revised October 8, 2026.
-- Structure placement interface. Links placement requests to terrain; selection, reconciliation and caches are private.
-- Sites are named placement records. A neighboring-chunk lookup deduplicates references before returning records; the placement transform uses an already-resolved pad height. Candidate selection, registration, reconciliation, caches and flattening remain private.
-- Real excerpts are marked. Other named interfaces are non-working stubs, not a replacement pipeline.

local Sites = {}

local _sites = {}
local _sitesByChunk = {}
-- Registration that fills these read-side tables is omitted.

-- Real source excerpt: key
local function key(cx, cz)
	return tostring(cx) .. "," .. tostring(cz)
end

-- Real source excerpt: padRadius
local function padRadius(fp)
	if not fp then
		return 0
	end
	if fp.shape == "circle" then
		return (fp.r or 0)
	else
		-- rect: approximate by max half-extent
		local rx = fp.rx or 0
		local rz = fp.rz or 0
		return math.max(rx, rz)
	end
end

-- Contract: Structure placement interface. Implementation intentionally unavailable.
function Sites.clearCache()
	-- full method is omitted
end

-- Contract: Structure placement interface. Implementation intentionally unavailable.
function Sites.Register(seed, chunkSize, structures, baseHeightPoint, scanBounds)
	-- full method is omitted
end

-- Real source excerpt: Sites.GetSitesNearChunk
function Sites.GetSitesNearChunk(cx, cz)
	local results = {}
	local seen = {}

	for dz = -1, 1 do
		for dx = -1, 1 do
			local k = key(cx+dx, cz+dz)
			local bucket = _sitesByChunk[k]
			if bucket then
				for _, siteIndex in ipairs(bucket) do
					if not seen[siteIndex] then
						seen[siteIndex] = true
						results[#results+1] = _sites[siteIndex]
					end
				end
			end
		end
	end

	return results
end

-- Contract: Structure placement interface. Implementation intentionally unavailable.
function Sites.FlattenChunkHeight(seed, baseHeightChunk, cx, cz, chunkSize, structureRuleOrList)
	-- full method is omitted
end

-- Real source excerpt: Sites.GetPlacementCFrame
function Sites.GetPlacementCFrame(site)
	-- You want the site sitting ON its padY.
	return CFrame.new(site.wx, site.padY, site.wz)
end

return Sites

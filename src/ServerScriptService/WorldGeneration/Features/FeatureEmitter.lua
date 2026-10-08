-- Partial source showcase, revised October 8, 2026.
-- Feature emission interface. Creates cancellable build jobs; staged emission and resource policy are private.
-- A box specification becomes an anchored part with bounds-derived size/center and supplied visual fields. Failure/cancellation clean up staged models. Begin/Step retain omitted publication/budget logic; no runnable build-job claim.
-- Real excerpts are marked. Other named interfaces are non-working stubs, not a replacement pipeline.

local FeatureEmitter = {}

local BuildJobMetatable = {}

-- Real source excerpt: buildPart
local function buildPart(spec, planId: string, sectionId: string, stage: Model): BasePart
	local part = Instance.new("Part")
	part.Parent = stage
	part.Name = spec.id
	part.Anchored = true
	part.Size = spec.bounds.max - spec.bounds.min
	part.CFrame = CFrame.new((spec.bounds.max + spec.bounds.min) * 0.5)
	part.Material = spec.material
	part.Color = spec.color
	part.Transparency = spec.transparency
	part.CanCollide = spec.canCollide
	part.CanQuery = spec.canQuery
	part.CanTouch = spec.canTouch
	part.CastShadow = spec.castShadow
	part:SetAttribute("WorldFeatureId", planId)
	part:SetAttribute("WorldFeatureSectionId", sectionId)
	part:SetAttribute("WorldFeaturePartId", spec.id)
	part:SetAttribute("WorldFeatureRole", spec.role)
	return part
end

-- Real source excerpt: releaseModel
local function releaseModel(job)
	if job.Model then
		job.Model:Destroy()
	end
end

-- Real source excerpt: BuildJobMetatable:_fail
function BuildJobMetatable:_fail(message: any): (boolean, boolean, string)
	self.Status = "Failed"
	self.Error = ("FeatureEmitter feature=%s section=%s phase=emission failed: %s"):format(
		self.PlanId,
		self.SectionId,
		tostring(message)
	)
	releaseModel(self)
	return true, false, self.Error
end

-- Real source excerpt: BuildJobMetatable:Cancel
function BuildJobMetatable:Cancel(): boolean
	if self.Status == "Cancelled" or self.Status == "Failed" then
		return false
	end
	releaseModel(self)
	self.Status = "Cancelled"
	return true
end

-- Contract: Feature emission interface. Implementation intentionally unavailable.
function BuildJobMetatable:Step(deadline, operationCap)
	-- full method is omitted
end

-- Contract: Feature emission interface. Implementation intentionally unavailable.
function FeatureEmitter.Begin(plan, sectionId, parent, generationToken)
	-- full method is omitted
end

return table.freeze(FeatureEmitter)

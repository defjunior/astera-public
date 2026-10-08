-- Architecture-only boundary, revised October 7, 2026.
-- Feature detail interface. Accepts a plan/context; detail budgets and placement policy are private.
-- This boundary shows where requests enter and results leave the subsystem.
-- The private policy decides what work to accept and when to publish it; no execution recipe is exposed.
-- Named interfaces are documentation stubs, not a working replacement.

local FeatureDecoration = {}

-- Contract: Feature detail interface. Implementation intentionally unavailable.
function FeatureDecoration.Apply(plan, context)
	-- full method is omitted
end

return table.freeze(FeatureDecoration)

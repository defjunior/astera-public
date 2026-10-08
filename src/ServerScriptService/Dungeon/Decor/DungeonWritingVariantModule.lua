--[[
	DungeonWritingVariantModule

	Builds procedural writing variants for paper-like decoration assets.
	All numeric/palette tuning is driven by:
	`Dungeon/Data/DungeonData.lua`
]]

local DungeonData = require(script.Parent.Parent.Data.DungeonData)
local DungeonWritingVariantData = DungeonData.Decor.WritingVariantData

local DungeonWritingVariantModule = {}

-- === Utility ===============================================================

local function randomUnit(rng)
	return rng:NextNumber(-1, 1)
end

local function pickPaletteColor(rng, style)
	local palette = DungeonWritingVariantData.StylePalettes[style]
	if type(palette) ~= "table" or #palette == 0 then
		palette = DungeonWritingVariantData.StylePalettes.normal
	end
	return palette[rng:NextInteger(1, #palette)]
end

local function resolveConditionTuning(condition)
	local byCondition = DungeonWritingVariantData.ConditionTuning
	return byCondition[condition] or byCondition.default
end

-- === Variant Build =========================================================

function DungeonWritingVariantModule.BuildVariant(rng, roomContext)
	local context = roomContext or {}
	local tuning = DungeonWritingVariantData.Tuning

	local arcaneBias = math.clamp(tonumber(context.arcaneBias) or 0, 0, 1)
	local condition = tostring(context.condition or "dusty")
	local conditionTuning = resolveConditionTuning(condition)

	local wornBias = conditionTuning.wornBias
	arcaneBias = math.clamp(arcaneBias + (conditionTuning.arcaneBiasBoost or 0), 0, 1)

	local removedSymbols = rng:NextInteger(tuning.removedSymbolsMin, tuning.removedSymbolsMax)
	local duplicateSymbols = rng:NextInteger(tuning.duplicateSymbolsMin, tuning.duplicateSymbolsMax)
	local shiftU = randomUnit(rng) * tuning.offsetRange
	local shiftV = randomUnit(rng) * tuning.offsetRange
	local density = math.clamp(
		tuning.densityBase + randomUnit(rng) * tuning.densityRandomJitter - wornBias * tuning.densityWornPenaltyScale,
		tuning.densityMin,
		tuning.densityMax
	)
	local scribbleChance = math.clamp(
		tuning.scribbleBase + (wornBias * tuning.scribbleWornScale),
		0,
		tuning.scribbleMax
	)

	local glow = rng:NextNumber() < arcaneBias
	local glowMode = "normal"
	if glow and condition == "arcane_disturbed" and rng:NextNumber() < tuning.corruptedChanceWhenArcaneDisturbed then
		glowMode = "corrupted"
	elseif glow then
		glowMode = "arcane"
	end

	local glowBrightness = 0
	local glowColor = nil
	if glow then
		glowBrightness = tuning.glowBrightnessMin + (rng:NextNumber() * tuning.glowBrightnessRandomRange)
		glowColor = pickPaletteColor(rng, glowMode)
	end

	return {
		style = glowMode,
		instanceAttributes = {
			WritingOffsetU = shiftU,
			WritingOffsetV = shiftV,
			WritingRemovedSymbolCount = removedSymbols,
			WritingDuplicateSymbolCount = duplicateSymbols,
			WritingDensity = density,
			WritingScribbleChance = scribbleChance,
			WritingWear = wornBias,
			WritingGlow = glow,
			WritingGlowBrightness = glowBrightness,
		},
		visual = glow and {
			glow = true,
			glowBrightness = glowBrightness,
			glowColor = glowColor,
		} or nil,
	}
end

-- === Placement Mutation ====================================================

function DungeonWritingVariantModule.ApplyToPlacement(placement, variant)
	if not placement or not variant then
		return placement
	end
	placement.instanceAttributes = placement.instanceAttributes or {}
	for key, value in pairs(variant.instanceAttributes or {}) do
		placement.instanceAttributes[key] = value
	end
	if variant.visual then
		placement.visual = variant.visual
	end
	return placement
end

return DungeonWritingVariantModule

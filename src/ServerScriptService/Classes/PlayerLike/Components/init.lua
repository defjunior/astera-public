local Registry = require(script.Registry)

-- Neutral components
local DamageComponent = require(script.Astera.DamageComponent)
Registry:Register("DamageComponent", DamageComponent)
local CooldownComponent = require(script.Astera.CooldownComponent)
Registry:Register("CooldownComponent", CooldownComponent)
local CombatComponent = require(script.Astera.CombatComponent)
Registry:Register("CombatComponent", CombatComponent)
local ClashComponent = require(script.Astera.ClashComponent)
Registry:Register("ClashComponent", ClashComponent)
local StatusComponent = require(script.Astera.StatusComponent)
Registry:Register("StatusComponent", StatusComponent)
local ResourceComponent = require(script.Astera.ResourceComponent)
Registry:Register("ResourceComponent", ResourceComponent)
local StatsComponent = require(script.Astera.StatsComponent)
Registry:Register("StatsComponent", StatsComponent)
local SkillComponent = require(script.Astera.SkillComponent)
Registry:Register("SkillComponent", SkillComponent)
local EquipmentComponent = require(script.Astera.EquipmentComponent)
Registry:Register("EquipmentComponent", EquipmentComponent)
local MovementComponent = require(script.Astera.MovementComponent)
Registry:Register("MovementComponent", MovementComponent)



return Registry

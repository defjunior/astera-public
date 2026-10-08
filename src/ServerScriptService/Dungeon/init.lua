local system = require(script.DungeonSystem)
system.DungeonSystem = system

-- Core: layout generation engine
system.Generation = require(script.Generation)

-- Content: design specs, room definitions, progression
system.Archetypes = require(script.Archetypes)
system.Rooms = require(script.Rooms)
system.Progression = require(script.Progression)

-- Visual: decoration, WFC tiling, vegetation
system.Decor = require(script.Decor)
system.WFC = require(script.WFC)
system.Vegetation = require(script.Vegetation)

-- Config & debug
system.Data = require(script.Data)
system.Debug = require(script.Debug)

return system

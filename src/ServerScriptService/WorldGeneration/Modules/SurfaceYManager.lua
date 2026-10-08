local SurfaceYManager = {}
SurfaceYManager.surfaceData = {}  -- Stored as: surfaceData[x][y][z] = surfacey

--- Saves the given surfaceY for the chunk at coordinate (chunkX, chunkY, chunkZ).
function SurfaceYManager:saveSurfaceY(chunkX, chunkY, chunkZ, surfaceY)
	task.synchronize()  -- ensure thread safety
	if not self.surfaceData[chunkX] then
		self.surfaceData[chunkX] = {}
	end
	if not self.surfaceData[chunkX][chunkY] then
		self.surfaceData[chunkX][chunkY] = {}
	end
	self.surfaceData[chunkX][chunkY][chunkZ] = surfaceY
	task.desynchronize()
end

--- Retrieves the saved surfaceY for the chunk at (chunkX, chunkY, chunkZ), or nil if not present.
function SurfaceYManager:getSurfaceY(chunkX, chunkY, chunkZ)
	task.synchronize()
	local value = nil
	if self.surfaceData[chunkX] and self.surfaceData[chunkX][chunkY] then
		value = self.surfaceData[chunkX][chunkY][chunkZ]
	end
	task.desynchronize()
	return value
end

return SurfaceYManager

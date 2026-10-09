local Spline = {}
Spline.__index = Spline

-- Creates a new spline given an array of points { {x=..., y=...}, ... }
-- Points should span at least [-1,1] but can be any range. This system will work
-- best if points are sorted by x. If not sorted, we will sort them.
function Spline.new(points)
	-- Sort points by x
	table.sort(points, function(a,b) return a.x < b.x end)

	local n = #points
	assert(n >= 2, "Need at least two points to form a spline.")

	-- Extract x and y arrays
	local xs = {}
	local ys = {}
	for i, p in ipairs(points) do
		xs[i] = p.x
		ys[i] = p.y
	end

	-- Create arrays for the spline coefficients
	-- We will compute the second derivatives "y2" for a natural cubic spline
	local y2 = {}
	local u = {}

	y2[1] = 0
	y2[n] = 0
	u[1] = 0

	-- Solve tridiagonal system for second derivatives
	for i = 2, n-1 do
		local sig = (xs[i] - xs[i-1]) / (xs[i+1] - xs[i-1])
		local p = sig * y2[i-1] + 2
		y2[i] = (sig - 1) / p
		u[i] = (ys[i+1] - ys[i]) / (xs[i+1] - xs[i]) - (ys[i] - ys[i-1]) / (xs[i] - xs[i-1])
		u[i] = (6 * u[i] / (xs[i+1] - xs[i-1]) - sig * u[i-1]) / p
	end

	for i = n-1, 1, -1 do
		y2[i] = y2[i] * y2[i+1] + u[i]
	end

	local spline = {
		xs = xs,
		ys = ys,
		y2 = y2
	}
	setmetatable(spline, Spline)
	return spline
end

-- Evaluate the spline at a given x
function Spline:eval(x)
	local xs = self.xs
	local ys = self.ys
	local y2 = self.y2
	local n = #xs

	-- Binary search to find the interval [k, k+1] that contains x
	local klo = 1
	local khi = n
	while (khi - klo > 1) do
		local k = math.floor((khi + klo) / 2)
		if xs[k] > x then
			khi = k
		else
			klo = k
		end
	end

	local h = xs[khi] - xs[klo]
	if h == 0 then
		error("Duplicate x values in spline.")
	end

	local a = (xs[khi] - x) / h
	local b = (x - xs[klo]) / h
	local y = a*ys[klo] + b*ys[khi] + ((a^3 - a)*y2[klo] + (b^3 - b)*y2[khi])*(h^2/6)
	return y
end

return Spline

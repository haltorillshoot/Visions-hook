-- Minimal Vector3 stand-in for running pure Luau code under lune. Only what the Lead model and the original lead code use.
local Vector3 = {}
local methods = {}

local function new(x, y, z)
	return setmetatable({ X = x, Y = y, Z = z }, Vector3)
end

function methods.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end

Vector3.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	elseif key == "Unit" then
		local magnitude = self.Magnitude

		return new(self.X / magnitude, self.Y / magnitude, self.Z / magnitude)
	end

	return methods[key]
end

Vector3.__add = function(a, b)
	return new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end

Vector3.__sub = function(a, b)
	return new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end

Vector3.__mul = function(a, b)
	if type(a) == "number" then
		return new(a * b.X, a * b.Y, a * b.Z)
	end

	return new(a.X * b, a.Y * b, a.Z * b)
end

Vector3.__div = function(a, b)
	return new(a.X / b, a.Y / b, a.Z / b)
end

Vector3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end

local module = { new = new, zero = new(0, 0, 0), metatable = Vector3 }

---Whether two numbers are equal, counting NaN as equal to NaN.
function module.sameNumber(a, b)
	return a == b or (a ~= a and b ~= b)
end

---Whether two vectors are component-wise identical, counting NaN as equal to NaN.
function module.sameVector(a, b)
	return module.sameNumber(a.X, b.X) and module.sameNumber(a.Y, b.Y) and module.sameNumber(a.Z, b.Z)
end

return module

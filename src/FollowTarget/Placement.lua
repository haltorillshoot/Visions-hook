---Follow Target placement: the parts of where the body stands that depend on nothing but numbers (orbit shapes, Zig Zag timing, how far a style
---can put the body from the target, and Adjust's search for a place with a clear line). Pure functions, so they can be tested outside Roblox.
---The shipped script gets this file injected by tools/build/bundle.py.
local Placement = {}

local vector3New = Vector3.new

local sin, cos, pi, floor, sqrt, abs, max = math.sin, math.cos, math.pi, math.floor, math.sqrt, math.abs, math.max

-- Constants.
Placement.ZIGZAG_SWING = math.rad(55) -- degrees either side of the line to the target
Placement.ZIGZAG_TURN = math.rad(25) -- degrees the swung line turns round the target at every switch
Placement.ZIGZAG_MIN_EVERY = 0.03 -- seconds
Placement.ZIGZAG_DEFAULT_SPEED = 35 -- Zig Zag Speed setting when none is set
Placement.WALK_SPEED = 16 -- studs/s of Speed 1x

local ZIGZAG_SWING_SIN = sin(Placement.ZIGZAG_SWING)

local POLYGON_SIDES = { ["triangle"] = 3, ["square"] = 4, ["pentagon"] = 5, ["hexagon"] = 6, ["decagon"] = 10 }

-- Adjust looks for a clear place on these ways (up, the four sides, the eight corners, down) at these distances from the target.
local ADJUST_WAYS = { { 0, 1, 0 }, { 1, 0, 0 }, { -1, 0, 0 }, { 0, 0, 1 }, { 0, 0, -1 }, { 1, 1, 1 }, { -1, 1, 1 }, { 1, 1, -1 }, { -1, 1, -1 }, { 1, -1, 1 }, { -1, -1, 1 }, { 1, -1, -1 }, { -1, -1, -1 }, { 0, -1, 0 } }
local ADJUST_RADII = { 2, 3, 4, 6, 9, 14, 22, 34 }

-- Every candidate place is worked out once: { offset from the target, distance to the wanted place (set per search), radius }.
local candidatePool = {}

for _, way in ADJUST_WAYS do
	local unit = vector3New(way[1], way[2], way[3]).Unit

	for _, radius in ADJUST_RADII do
		candidatePool[#candidatePool + 1] = { unit * radius, 0, radius }
	end
end

local candidateOrder = {}

---Nearest to the wanted place first, and among the same the nearer to the target.
local function compareCandidates(a, b)
	if abs(a[2] - b[2]) > 0.5 then
		return a[2] < b[2]
	end

	return a[3] < b[3]
end

---Where `share` (0 to 1, once round) of the way along a path `radius` studs out is, flat round the middle.
---A polygon is walked from corner to corner; the heart is the usual parametric curve.
---@param shape string circle, triangle, square, pentagon, hexagon, decagon or heart
---@param share number
---@param radius number
---@return Vector3
function Placement.orbitOffset(shape, share, radius)
	local sides = POLYGON_SIDES[shape]

	if sides then
		local scaled = share * sides
		local corner = floor(scaled)
		local along = scaled - corner
		local fromAngle = corner / sides * 2 * pi
		local toAngle = (corner + 1) / sides * 2 * pi

		return vector3New(sin(fromAngle) * (1 - along) + sin(toAngle) * along, 0, cos(fromAngle) * (1 - along) + cos(toAngle) * along) * radius
	elseif shape == "heart" then
		local angle = share * 2 * pi

		return vector3New(sin(angle) ^ 3, 0, (13 * cos(angle) - 5 * cos(2 * angle) - 2 * cos(3 * angle) - cos(4 * angle)) / 16) * radius
	end

	return vector3New(sin(share * 2 * pi), 0, cos(share * 2 * pi)) * radius
end

---How long Zig Zag stays on one side. Zig Zag Speed is the same multiplier as Misc's Speed (1x = 16 studs/s): a switch comes once a body going
---that fast would have crossed from the last place to the next (2 * Distance * sin 55, plus the turn), so a faster Speed or a shorter Distance
---switches sides more often.
---@param distance number Distance setting
---@param speedSetting number Zig Zag Speed setting
---@return number seconds
function Placement.zigzagEvery(distance, speedSetting)
	local leg = 2 * distance * ZIGZAG_SWING_SIN + distance * Placement.ZIGZAG_TURN

	return max(leg / max(speedSetting * Placement.WALK_SPEED, 1), Placement.ZIGZAG_MIN_EVERY)
end

-- How far from the target each style can put the body (see Placement.reach).
local REACH = {
	["strafe"] = function(distance, heightY)
		return sqrt(distance * distance + heightY * heightY)
	end,
	["zig zag"] = function(distance, _, flags)
		local over = abs(tonumber(flags["follow_target_zigzag_height"]) or 3) + 2

		return sqrt(distance * distance + over * over)
	end,
	["randomize"] = function(_, _, flags)
		local high = max(flags["follow_target_teleport_max"] or 17, flags["follow_target_teleport_min"] or 2)

		return sqrt(high * high + 25)
	end,
	["above"] = function(_, _, flags)
		return max(flags["follow_target_sky_max"] or 20, flags["follow_target_sky_min"] or 10)
	end,
	["strafe above"] = function(distance, heightY, flags)
		local up = abs(heightY) + max(flags["follow_target_sky_max"] or 20, flags["follow_target_sky_min"] or 10)

		return sqrt(distance * distance + up * up)
	end,
	["random"] = function(distance)
		return distance * sqrt(3)
	end,
}

---How far from the target the current follow style can put the body. nil when it can go farther than the follow's own reach (Random Spam's void
---jumps), or when Adjust has moved the body somewhere else. The remote hook uses it to claim shots from next to the target.
---@param style string
---@param distance number Distance setting
---@param heightY number Y of the Height setting
---@param flags table the menu flags
---@param adjustOffset Vector3? where Adjust has put the body, if it has
---@return number?
function Placement.reach(style, distance, heightY, flags, adjustOffset)
	if flags["follow_target_adjust"] == true and adjustOffset then
		return nil
	end

	local styleReach = REACH[style]

	return styleReach and styleReach(distance, heightY, flags) or nil
end

---Adjust's search: the nearest place around the target (to the place the style wanted) with a clear line, or nil when there is none.
---@param aim Vector3 the target
---@param position Vector3 the place the style gave
---@param range number longest distance from the target worth trying (the gun's range)
---@param lift Vector3 the muzzle's height over the body
---@param clear function (from, to) -> boolean, whether the line is free
---@return Vector3?
function Placement.adjustSearch(aim, position, range, lift, clear)
	local wanted = position - aim
	local count = 0

	for index = 1, #candidatePool do
		local candidate = candidatePool[index]

		if candidate[3] <= range then
			count += 1
			candidate[2] = (candidate[1] - wanted).Magnitude
			candidateOrder[count] = candidate
		end
	end

	for index = #candidateOrder, count + 1, -1 do
		candidateOrder[index] = nil
	end

	table.sort(candidateOrder, compareCandidates)

	for index = 1, count do
		local offset = candidateOrder[index][1]

		if clear(aim + offset + lift, aim) then
			return offset
		end
	end

	return nil
end

return Placement

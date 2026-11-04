-- Golden master for the Follow Target placement module: the ORIGINAL inline code (sliced out of the backup branch, not retyped) and
-- src/FollowTarget/Placement.lua run on the same random inputs and have to give the same answers. Also the invariants of the shapes and a
-- cost comparison (time and garbage) for the two pieces that run often.
--   lune run tests/follow/golden.spec
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local V3 = require("../support/vector3")
local original = require("../support/original")

local passed, failed = 0, 0

local function check(name, condition, detail)
	if condition then
		passed += 1
	else
		failed += 1
		print("FAIL", name, detail or "")
	end
end

local environment = { vector3_new = V3.new, math = math, table = table, tonumber = tonumber }
local moduleSource = string.gsub(fs.readFile("src/FollowTarget/Placement.lua"), "\r\n", "\n")

local function loadModule(source)
	return luau.load(source, { environment = { Vector3 = V3, math = math, table = table, tonumber = tonumber } })()
end

local Placement = loadModule(moduleSource)

math.randomseed(20261104)

local function random(low, high)
	return low + math.random() * (high - low)
end

local function randomVector(scale)
	return V3.new(random(-scale, scale), random(-scale, scale), random(-scale, scale))
end

-- the original pieces -----------------------------------------------------------------------------------------------------------
local orbitSnippet = original.slice('        hide_manager["orbit_offset"] = function(shape, share, radius)\n', "\n\n        -- Visualize: a flat disc over the strafe's radius")
local originalOrbit = luau.load('local hide_manager = {}\n' .. orbitSnippet .. '\nreturn hide_manager["orbit_offset"]', { environment = environment })()

local zigzagSnippet = original.slice("        local zigzag_every = function()\n", "\n\n        -- how long the Shot Lock holds one place")
local originalZigzag = luau.load("local flags, distance, rad = ...\n" .. zigzagSnippet .. "\nreturn zigzag_every", { environment = environment })

local reachSnippet = original.slice('        hide_manager["follow_reach"] = function()\n', '\n\n        hide_manager["follow_cframe"] = function(aim, window, quiet)')
local originalReach = luau.load("local flags, adjust_state, follow_target_style, distance, height = ...\nlocal hide_manager = {}\n" .. reachSnippet .. '\nreturn hide_manager["follow_reach"]()', { environment = environment })

local adjustSnippet = original.slice("                local wanted = position - aim\n                local candidates = {}\n", '\n            end\n\n            local offset = adjust_state["offset"]\n')
local originalAdjust = luau.load('local position, aim, range, lift, clear, adjust_ways, adjust_state = ...\nadjust_state["offset"] = nil\n' .. adjustSnippet .. '\nreturn adjust_state["offset"]', { environment = environment })

check("original pieces were found", orbitSnippet ~= "" and zigzagSnippet ~= "" and reachSnippet ~= "" and adjustSnippet ~= "")

-- 1. orbit shapes ----------------------------------------------------------------------------------------------------------------
local shapes = { "circle", "triangle", "square", "pentagon", "hexagon", "decagon", "heart", "something else", "" }

local function compareOrbit(model, quiet)
	local mismatches = 0

	for _ = 1, 30000 do
		local shape = shapes[math.random(1, #shapes)]
		local share = math.random(1, 6) == 1 and random(-3, 3) or math.random()
		local radius = ({ 0, 1, 15, 89, 200 })[math.random(1, 5)]
		local expected, actual = originalOrbit(shape, share, radius), model.orbitOffset(shape, share, radius)

		if not V3.sameVector(expected, actual) then
			mismatches += 1
		end
	end

	return mismatches
end

check("orbitOffset matches the original on 30000 cases", compareOrbit(Placement) == 0)

-- 2. Zig Zag timing -----------------------------------------------------------------------------------------------------------
do
	local mismatches = 0

	for _ = 1, 30000 do
		local distance = ({ 0, 1, 5, 15, 67, 89, 200 })[math.random(1, 7)]
		local speedSetting = ({ 0, 1, 20, 35, 100, 250 })[math.random(1, 6)]
		local expected = originalZigzag({ follow_target_zigzag_speed = speedSetting }, distance, math.rad)()

		if not V3.sameNumber(expected, Placement.zigzagEvery(distance, speedSetting)) then
			mismatches += 1
		end
	end

	check("zigzagEvery matches the original on 30000 cases", mismatches == 0)
	check("zigzagEvery never goes below its minimum", Placement.zigzagEvery(0, 250) == Placement.ZIGZAG_MIN_EVERY)
	check("a faster Zig Zag Speed never switches less often", Placement.zigzagEvery(89, 100) <= Placement.zigzagEvery(89, 35))
end

-- 3. reach ----------------------------------------------------------------------------------------------------------------------
local styles = { "strafe", "zig zag", "randomize", "above", "strafe above", "random", "random spam", "nonsense", "" }

local function randomFlags()
	-- (a list with a nil at its end is shorter than it looks, so the number of choices is given)
	local function pick(count, values)
		return values[math.random(1, count)]
	end

	return {
		follow_target_adjust = pick(3, { true, false, nil }),
		follow_target_zigzag_height = pick(7, { 0, 3, 74, -20, "12", "x", nil }),
		follow_target_teleport_max = pick(4, { 2, 35, 200, nil }),
		follow_target_teleport_min = pick(4, { 1, 14, 300, nil }),
		follow_target_sky_max = pick(4, { 5, 83, 200, nil }),
		follow_target_sky_min = pick(4, { 1, 17, 90, nil }),
	}
end

local function compareReach(model)
	local mismatches = 0

	for _ = 1, 30000 do
		local style = styles[math.random(1, #styles)]
		local distance = ({ 0, 1, 15, 89, 200 })[math.random(1, 5)]
		local height = V3.new(0, ({ -50, 0, 71, 200 })[math.random(1, 4)], 0)
		local flags = randomFlags()
		local adjustOffset = math.random(1, 2) == 1 and V3.new(1, 2, 3) or nil
		local expected = originalReach(flags, { offset = adjustOffset }, style, distance, height)
		local actual = model.reach(style, distance, height.Y, flags, adjustOffset)

		if not V3.sameNumber(expected or 0 / 0, actual or 0 / 0) or (expected == nil) ~= (actual == nil) then
			mismatches += 1
		end
	end

	return mismatches
end

check("reach matches the original on 30000 cases", compareReach(Placement) == 0)
check("reach is nil for a style that can go anywhere", Placement.reach("random spam", 89, 0, {}, nil) == nil)
check("reach is nil once Adjust has moved the body", Placement.reach("strafe", 89, 0, { follow_target_adjust = true }, V3.new(1, 0, 0)) == nil)
check("reach ignores an Adjust offset while Adjust is off", Placement.reach("strafe", 3, 4, { follow_target_adjust = false }, V3.new(1, 0, 0)) == 5)

-- 4. Adjust's search ---------------------------------------------------------------------------------------------------------------
local ways = {}

for _, way in { { 0, 1, 0 }, { 1, 0, 0 }, { -1, 0, 0 }, { 0, 0, 1 }, { 0, 0, -1 }, { 1, 1, 1 }, { -1, 1, 1 }, { 1, 1, -1 }, { -1, 1, -1 }, { 1, -1, 1 }, { -1, -1, 1 }, { 1, -1, -1 }, { -1, -1, -1 }, { 0, -1, 0 } } do
	table.insert(ways, V3.new(way[1], way[2], way[3]).Unit)
end

---A deterministic stand-in for the wall check: a place is blocked or free depending on where it is. Every call is recorded.
local function makeClear(blockedShare, recorded)
	return function(from, to)
		if recorded then
			table.insert(recorded, { from, to })
		end

		local noise = math.sin(from.X * 12.9898 + from.Y * 78.233 + from.Z * 37.719) * 43758.5453

		return (noise - math.floor(noise)) >= blockedShare
	end
end

local lift = V3.new(0, 3.0208, 0)

local function compareAdjust(model)
	local mismatches, callMismatches = 0, 0

	for _ = 1, 4000 do
		local aim = randomVector(400)
		local position = aim + randomVector(math.random(1, 3) == 1 and 5 or 60)
		local range = ({ 5, 12, 30, 100, 200, 0 / 0 })[math.random(1, 6)]
		local blockedShare = ({ 0, 0.3, 0.7, 0.95, 1 })[math.random(1, 5)]
		local expectedCalls, actualCalls = {}, {}
		local expected = originalAdjust(position, aim, range, lift, makeClear(blockedShare, expectedCalls), ways, {})
		local actual = model.adjustSearch(aim, position, range, lift, makeClear(blockedShare, actualCalls))

		if (expected == nil) ~= (actual == nil) or (expected and not V3.sameVector(expected, actual)) then
			mismatches += 1
		end

		local same = #expectedCalls == #actualCalls

		for index = 1, same and #expectedCalls or 0 do
			if not (V3.sameVector(expectedCalls[index][1], actualCalls[index][1]) and V3.sameVector(expectedCalls[index][2], actualCalls[index][2])) then
				same = false
				break
			end
		end

		if not same then
			callMismatches += 1
		end
	end

	return mismatches, callMismatches
end

do
	local mismatches, callMismatches = compareAdjust(Placement)

	check("adjustSearch picks the same place as the original on 4000 cases", mismatches == 0, mismatches .. " mismatches")
	check("adjustSearch makes the same wall checks in the same order", callMismatches == 0, callMismatches .. " mismatches")
end

-- 4b. the call sites in Visions-hook.lua: the code that is actually shipped, through the same cases --------------------------------------
local shipped = string.gsub(fs.readFile("Visions-hook.lua"), "\r\n", "\n")

local function shippedSlice(startMarker, endMarker)
	local startAt = string.find(shipped, startMarker, 1, true)
	local endAt = startAt and string.find(shipped, endMarker, startAt, true)

	assert(startAt and endAt, "cannot find the shipped call site: " .. startMarker:sub(1, 60))

	return string.sub(shipped, startAt, endAt - 1)
end

local shippedOrbit = shippedSlice('        hide_manager["orbit_offset"] =', "\n\n        -- Visualize: a flat disc over the strafe's radius")
local shippedZigzag = shippedSlice("        local zigzag_every = function()\n", "\n\n        -- how long the Shot Lock holds one place")
local shippedReach = shippedSlice('        hide_manager["follow_reach"] = function()\n', '\n\n        hide_manager["follow_cframe"] = function(aim, window, quiet)')
local shippedAdjust = shippedSlice('                adjust_state["offset"] = hide_manager["follow_placement"]["adjustSearch"]', '\n            end\n\n            local offset = adjust_state["offset"]\n')

local function loadShippedOrbit(snippet)
	return luau.load("local hide_manager = { follow_placement = ... }\n" .. snippet .. '\nreturn hide_manager["orbit_offset"]', { environment = environment })(Placement)
end

local function loadShippedZigzag(snippet)
	return luau.load("local flags, distance, rad, hide_manager = ...\n" .. snippet .. "\nreturn zigzag_every", { environment = environment })
end

local function loadShippedReach(snippet)
	return luau.load("local flags, adjust_state, follow_target_style, distance, height, hide_manager = ...\n" .. snippet .. '\nreturn hide_manager["follow_reach"]()', { environment = environment })
end

local function loadShippedAdjust(snippet)
	return luau.load("local position, aim, range, lift, clear, adjust_state, hide_manager = ...\nadjust_state.offset = nil\n" .. snippet .. "\nreturn adjust_state.offset", { environment = environment })
end

local function compareShipped(orbit, zigzag, reach, adjust)
	local mismatches = { orbit = 0, zigzag = 0, reach = 0, adjust = 0 }
	local hideManager = { follow_placement = Placement }

	for _ = 1, 4000 do
		local shape = shapes[math.random(1, #shapes)]
		local share, radius = random(-3, 3), ({ 0, 1, 15, 89 })[math.random(1, 4)]

		if not V3.sameVector(originalOrbit(shape, share, radius), orbit(shape, share, radius)) then
			mismatches.orbit += 1
		end

		-- (false stands for a Zig Zag Speed that is not set, so the default is used)
		local distance, speed = ({ 0, 5, 67, 89 })[math.random(1, 4)], ({ false, 0, 1, 35, 100 })[math.random(1, 5)]
		local zigzagFlags = { follow_target_zigzag_speed = speed or nil }

		if not V3.sameNumber(originalZigzag(zigzagFlags, distance, math.rad)(), zigzag(zigzagFlags, distance, math.rad, hideManager)()) then
			mismatches.zigzag += 1
		end

		local style, flags = styles[math.random(1, #styles)], randomFlags()
		local height = V3.new(0, ({ -50, 0, 71 })[math.random(1, 3)], 0)
		local adjustOffset = math.random(1, 2) == 1 and V3.new(1, 2, 3) or nil
		local expected = originalReach(flags, { offset = adjustOffset }, style, distance, height)
		local actual = reach(flags, { offset = adjustOffset }, style, distance, height, hideManager)

		if not V3.sameNumber(expected or 0 / 0, actual or 0 / 0) or (expected == nil) ~= (actual == nil) then
			mismatches.reach += 1
		end

		local aim = randomVector(300)
		local position = aim + randomVector(40)
		local range = ({ 5, 30, 200 })[math.random(1, 3)]
		local blocked = ({ 0, 0.5, 0.95 })[math.random(1, 3)]
		local expectedOffset = originalAdjust(position, aim, range, lift, makeClear(blocked), ways, {})
		local actualOffset = adjust(position, aim, range, lift, makeClear(blocked), {}, hideManager)

		if (expectedOffset == nil) ~= (actualOffset == nil) or (expectedOffset and not V3.sameVector(expectedOffset, actualOffset)) then
			mismatches.adjust += 1
		end
	end

	return mismatches
end

do
	local mismatches = compareShipped(loadShippedOrbit(shippedOrbit), loadShippedZigzag(shippedZigzag), loadShippedReach(shippedReach), loadShippedAdjust(shippedAdjust))

	check("shipped orbit call site matches the original", mismatches.orbit == 0, mismatches.orbit)
	check("shipped Zig Zag timing call site matches the original", mismatches.zigzag == 0, mismatches.zigzag)
	check("shipped reach call site matches the original", mismatches.reach == 0, mismatches.reach)
	check("shipped Adjust call site matches the original", mismatches.adjust == 0, mismatches.adjust)

	local callSiteMutations = {
		{ "zigzag default speed", shippedZigzag, 'or 35)', 'or 36)', "zigzag" },
		{ "reach argument order", shippedReach, 'distance, height["Y"], flags', 'height["Y"], distance, flags', "reach" },
		{ "reach adjust offset", shippedReach, 'adjust_state["offset"])', "nil)", "reach" },
		{ "adjust range", shippedAdjust, "position, range, lift", "position, range + 1, lift", "adjust" },
		{ "adjust lift", shippedAdjust, "range, lift, clear", "range, vector3_new(0, 0, 0), clear", "adjust" },
	}

	for _, mutation in ipairs(callSiteMutations) do
		local start, finish = string.find(mutation[2], mutation[3], 1, true)
		local caught = -1

		if start then
			local mutated = string.sub(mutation[2], 1, start - 1) .. mutation[4] .. string.sub(mutation[2], finish + 1)
			local result = compareShipped(
				loadShippedOrbit(shippedOrbit),
				mutation[5] == "zigzag" and loadShippedZigzag(mutated) or loadShippedZigzag(shippedZigzag),
				mutation[5] == "reach" and loadShippedReach(mutated) or loadShippedReach(shippedReach),
				mutation[5] == "adjust" and loadShippedAdjust(mutated) or loadShippedAdjust(shippedAdjust)
			)

			caught = result[mutation[5]]
		end

		check("shipped call site mutation is caught: " .. mutation[1], caught > 0, caught == -1 and "pattern not found" or "not detected")
	end
end

-- 5. the comparison has to be able to fail ---------------------------------------------------------------------------------------------
local function replacePlain(text, find, replace)
	local start, finish = string.find(text, find, 1, true)

	if not start then
		return nil
	end

	return string.sub(text, 1, start - 1) .. replace .. string.sub(text, finish + 1)
end

local mutations = {
	{ "orbit: decagon sides", "[\"decagon\"] = 10", "[\"decagon\"] = 9", "orbit" },
	{ "orbit: heart term", "- cos(4 * angle)) / 16", "- cos(4 * angle)) / 15", "orbit" },
	{ "zigzag: swing", "Placement.ZIGZAG_SWING = math.rad(55)", "Placement.ZIGZAG_SWING = math.rad(54)", "zigzag" },
	{ "zigzag: minimum", "Placement.ZIGZAG_MIN_EVERY = 0.03", "Placement.ZIGZAG_MIN_EVERY = 0.04", "zigzag" },
	{ "reach: random", "return distance * sqrt(3)", "return distance * sqrt(2)", "reach" },
	{ "reach: above default", "flags[\"follow_target_sky_max\"] or 20, flags[\"follow_target_sky_min\"] or 10)\n\tend,\n\t[\"strafe above\"]", "flags[\"follow_target_sky_max\"] or 21, flags[\"follow_target_sky_min\"] or 10)\n\tend,\n\t[\"strafe above\"]", "reach" },
	{ "adjust: radii", "local ADJUST_RADII = { 2, 3, 4, 6, 9, 14, 22, 34 }", "local ADJUST_RADII = { 2, 3, 4, 6, 9, 14, 22, 35 }", "adjust" },
	{ "adjust: tie break", "return a[3] < b[3]", "return a[3] > b[3]", "adjust" },
	{ "adjust: tolerance", "abs(a[2] - b[2]) > 0.5", "abs(a[2] - b[2]) > 0.6", "adjust" },
}

for _, mutation in ipairs(mutations) do
	local mutated = replacePlain(moduleSource, mutation[2], mutation[3])
	local caught = -1

	if mutated then
		local model = loadModule(mutated)

		if mutation[4] == "orbit" then
			caught = compareOrbit(model)
		elseif mutation[4] == "zigzag" then
			local mismatches = 0

			for _ = 1, 2000 do
				local distance, speed = ({ 1, 5, 15, 89 })[math.random(1, 4)], ({ 0, 1, 20, 35, 250 })[math.random(1, 5)]

				if not V3.sameNumber(originalZigzag({ follow_target_zigzag_speed = speed }, distance, math.rad)(), model.zigzagEvery(distance, speed)) then
					mismatches += 1
				end
			end

			caught = mismatches
		elseif mutation[4] == "reach" then
			caught = compareReach(model)
		else
			local mismatches, callMismatches = compareAdjust(model)
			caught = mismatches + callMismatches
		end
	end

	check("mutation is caught: " .. mutation[1], caught > 0, caught == -1 and "pattern not found" or "not detected")
end

-- 6. shapes keep their geometry ----------------------------------------------------------------------------------------------------
do
	local worst = 0

	for _, shape in ipairs({ "circle", "triangle", "square", "pentagon", "hexagon", "decagon" }) do
		for step = 0, 100 do
			local offset = Placement.orbitOffset(shape, step / 100, 50)

			-- no point of a polygon is farther out than its corners
			worst = math.max(worst, offset.Magnitude - 50)
		end
	end

	check("no orbit point lies outside the radius", worst < 1e-9, worst)

	for _, shape in ipairs({ "circle", "triangle", "square", "pentagon", "hexagon", "decagon", "heart" }) do
		check("a full turn is the same place: " .. shape, (Placement.orbitOffset(shape, 0.37, 30) - Placement.orbitOffset(shape, 1.37, 30)).Magnitude < 1e-9)
	end

	local corner = Placement.orbitOffset("square", 0.25, 40)
	check("a square corner is on the radius", math.abs(corner.Magnitude - 40) < 1e-9)
	check("the orbit is flat", Placement.orbitOffset("heart", 0.3, 40).Y == 0 and Placement.orbitOffset("hexagon", 0.3, 40).Y == 0)
end

-- 7. cost: time ---------------------------------------------------------------------------------------------------------------------
-- Timing under lune with a table-based Vector3 stand-in: it shows that work was removed, not how much a Roblox client saves. Garbage cannot be
-- measured here (only collectgarbage("count") works, there is no collect or stop), so no claim is made about it.
do
	local function time(runs, work)
		local start = os.clock()

		for _ = 1, runs do
			work()
		end

		return (os.clock() - start) * 1000
	end

	local orbitRuns = 200000
	local originalMs = time(orbitRuns, function()
		originalOrbit("hexagon", 0.37, 89)
	end)
	local newMs = time(orbitRuns, function()
		Placement.orbitOffset("hexagon", 0.37, 89)
	end)

	print(string.format("orbit offset, %d calls: original %.0f ms, new %.0f ms (%.0f%% of the original)", orbitRuns, originalMs, newMs, newMs / originalMs * 100))
	check("orbitOffset is not slower than the original", newMs <= originalMs * 1.1, string.format("%.0f ms vs %.0f ms", newMs, originalMs))

	local adjustRuns = 3000
	local clear = makeClear(0.9)
	local aimSample, positionSample = V3.new(10, 5, 20), V3.new(40, 8, 20)
	local originalAdjustMs = time(adjustRuns, function()
		originalAdjust(positionSample, aimSample, 200, lift, clear, ways, {})
	end)
	local newAdjustMs = time(adjustRuns, function()
		Placement.adjustSearch(aimSample, positionSample, 200, lift, clear)
	end)

	print(string.format("adjust search, %d searches: original %.0f ms, new %.0f ms (%.0f%% of the original)", adjustRuns, originalAdjustMs, newAdjustMs, newAdjustMs / originalAdjustMs * 100))
	check("adjustSearch is not slower than the original", newAdjustMs <= originalAdjustMs * 1.1, string.format("%.0f ms vs %.0f ms", newAdjustMs, originalAdjustMs))
end

print(string.format("follow placement: %d passed, %d failed", passed, failed))

if failed > 0 then
	process.exit(1)
end

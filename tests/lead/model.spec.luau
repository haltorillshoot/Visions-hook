-- Specs for the rest of the Lead model: the pieces taken over unchanged are compared with the original code (sliced from the backup branch),
-- the two deliberate changes to the follow lead are checked as properties.
--   lune run tests/lead/model.spec
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

local Lead = luau.load(string.gsub(fs.readFile("src/Lead/LeadModel.lua"), "\r\n", "\n"), { environment = { Vector3 = V3, math = math } })()

math.randomseed(20261104)

local function random(low, high)
	return low + math.random() * (high - low)
end

local function randomVector(scale)
	return V3.new(random(-scale, scale), random(-scale, scale), random(-scale, scale))
end

local function unit(vector)
	return vector * (1 / vector.Magnitude)
end

-- 1. Steady: identical to the original expression ----------------------------------------------------------------------------
do
	local snippet = original.slice('                        hide_manager["velocity_steady"] = previous ~= nil', "\n\n                        target_velocity = velocity")
	local chunk = luau.load("local previous, velocity = ...\nlocal hide_manager = {}\n" .. snippet .. '\nreturn hide_manager["velocity_steady"]', { environment = { math = math } })
	local mismatches = 0

	for _ = 1, 20000 do
		local previous = math.random(1, 8) ~= 1 and randomVector(random(0, 200)) or nil
		local velocity = math.random(1, 3) == 1 and previous and previous * random(0.2, 1.8) or randomVector(random(0, 200))
		local expected = chunk(previous, velocity)

		if Lead.isSteady(previous, velocity) ~= expected then
			mismatches += 1
		end
	end

	check("isSteady matches the original on 20000 cases", mismatches == 0, mismatches .. " mismatches")
end

-- 2. Closing speed and Pre Fire lead: identical to the original --------------------------------------------------------------
do
	local snippet = original.slice("        local relative = theirs - mine\n", "\n    end\n\n    -- Where the shot hook starts a ragebot shot from")
	local chunk = luau.load("local way, theirs, mine, flags = ...\n" .. snippet, { environment = { math = math, tonumber = tonumber } })
	local mismatches = 0

	for _ = 1, 20000 do
		local way = unit(randomVector(1))
		local theirs, mine = randomVector(random(0, 400)), randomVector(random(0, 100))
		local ms = ({ false, 0, 30, 60, 120, 300 })[math.random(1, 6)]
		local expected = chunk(way, theirs, mine, { auto_fire_pre_fire_time = ms or nil })
		local actual = Lead.preFire(Lead.closingSpeed(way, theirs, mine), tonumber(ms or nil) or Lead.PRE_FIRE_DEFAULT_MS)

		if not V3.sameNumber(actual, expected) then
			mismatches += 1
		end
	end

	check("closingSpeed and preFire match the original on 20000 cases", mismatches == 0, mismatches .. " mismatches")
	check("preFire is capped", Lead.preFire(1e6, 60) == Lead.PRE_FIRE_CAP)
	check("preFire is 0 when not closing", Lead.preFire(0, 60) == 0 and Lead.preFire(-5, 60) == 0 and Lead.preFire(0 / 0, 60) == 0)
end

-- 3. Follow lead ---------------------------------------------------------------------------------------------------------------
do
	local snippet = original.slice("                local follow_aim = ragebot_aim_position\n", '\n                local new_cframe = hide_manager["follow_cframe"](follow_aim, false, bypass)')
	local chunk = luau.load("local flags, bypass, hide_manager, ragebot_aim_position, typeof = ...\n" .. snippet .. "\nreturn follow_aim", { environment = { math = math, tonumber = tonumber } })

	local function typeofVector()
		return "Vector3"
	end

	local function originalAhead(velocity, ms, trusted)
		local aim = V3.zero
		local flags = { follow_target_lead = true, follow_target_lead_time = ms }

		return chunk(flags, false, { aim_velocity = velocity, aim_trusted = trusted }, aim, typeofVector)
	end

	-- identical from FOLLOW_MIN_SPEED up when the aim carries no lead
	local mismatches = 0

	for _ = 1, 20000 do
		local speed = random(Lead.FOLLOW_MIN_SPEED + 1e-6, 700)
		local velocity = unit(randomVector(1)) * speed
		local ms = ({ 0, 40, 80, 110, 200, 300 })[math.random(1, 6)]
		local trusted = math.random(1, 4) ~= 1

		if not V3.sameVector(originalAhead(velocity, ms, trusted), Lead.followAhead(velocity, ms, trusted, V3.zero)) then
			mismatches += 1
		end
	end

	check("followAhead matches the original from 40 studs/s up (no aim lead)", mismatches == 0, mismatches .. " mismatches")

	-- not trusted, or not moving: no lead, as before
	check("not trusted gives no follow lead", Lead.followAhead(V3.new(100, 0, 0), 80, false, V3.zero) == V3.zero)
	check("standing still gives no follow lead", Lead.followAhead(V3.zero, 80, true, V3.zero) == V3.zero)
	check("a speed that is not a number gives no follow lead", Lead.followAhead(V3.new(0 / 0, 0, 0), 80, true, V3.zero) == V3.zero)

	-- the ramp: nothing at the start, the original value at FOLLOW_MIN_SPEED, never decreasing in between
	local direction = V3.new(1, 0, 0)
	local atStart = Lead.followAhead(direction * Lead.FOLLOW_RAMP_START, 80, true, V3.zero)
	local atMin = Lead.followAhead(direction * Lead.FOLLOW_MIN_SPEED, 80, true, V3.zero)
	local previousLength = 0
	local monotonic = true

	for speed = Lead.FOLLOW_RAMP_START, 70, 0.25 do
		local length = Lead.followAhead(direction * speed, 80, true, V3.zero).Magnitude

		if length + 1e-9 < previousLength then
			monotonic = false
		end

		previousLength = length
	end

	check("follow lead is 0 at the start of the ramp", atStart.Magnitude == 0)
	check("follow lead equals the original at 40 studs/s", V3.sameVector(atMin, originalAhead(direction * 40.0000001, 80, true)) or math.abs(atMin.Magnitude - originalAhead(direction * 40.0000001, 80, true).Magnitude) < 1e-4)
	check("follow lead never shrinks as the speed rises", monotonic)
	check("the original had a step at 40 studs/s", originalAhead(direction * 39.999, 80, true).Magnitude == 0 and originalAhead(direction * 40.001, 80, true).Magnitude > 3)

	-- the combined cap: aim lead plus body offset stay inside one trusted cap, and nothing changes while they fit
	local capBroken, changedWhenFits = 0, 0

	for _ = 1, 20000 do
		local speed = random(40, 600)
		local velocity = unit(randomVector(1)) * speed
		local aimLead = unit(randomVector(1)) * random(0, Lead.CAP_TRUSTED)
		local ms = ({ 40, 80, 110, 200, 300 })[math.random(1, 5)]
		local ahead = Lead.followAhead(velocity, ms, true, aimLead)
		local uncapped = Lead.followAhead(velocity, ms, true, V3.zero)

		if (aimLead + ahead).Magnitude > Lead.CAP_TRUSTED + 1e-6 then
			capBroken += 1
		end

		if (aimLead + uncapped).Magnitude <= Lead.CAP_TRUSTED and not V3.sameVector(ahead, uncapped) then
			changedWhenFits += 1
		end
	end

	check("aim lead plus follow lead never exceed the trusted cap", capBroken == 0, capBroken .. " cases")
	check("the combined cap changes nothing while the two fit", changedWhenFits == 0, changedWhenFits .. " cases")
	check("the original could exceed the trusted cap", (V3.new(150, 0, 0) + originalAhead(V3.new(300, 0, 0), 300, true)).Magnitude > 200)
end

-- 4. Body offset jitter around the 40 studs/s switch, original against new --------------------------------------------------
do
	local direction = V3.new(1, 0, 0)

	local function maxStep(lead, noise)
		local worst, previous = 0, nil

		for _ = 1, 5000 do
			-- a measured speed wandering around the switch, a frame at a time
			local offset = lead(direction * (40 + random(-noise, noise)))

			if previous then
				worst = math.max(worst, (offset - previous).Magnitude)
			end

			previous = offset
		end

		return worst
	end

	local function originalLead(velocity)
		if velocity.Magnitude > 40 then
			local ahead = velocity * (110 / 1000)

			return ahead.Magnitude > 60 and ahead.Unit * 60 or ahead
		end

		return V3.zero
	end

	local function newLead(velocity)
		return Lead.followAhead(velocity, 110, true, V3.zero)
	end

	for _, noise in ipairs({ 1, 2, 4, 8 }) do
		local before, after = maxStep(originalLead, noise), maxStep(newLead, noise)

		print(string.format("body offset jitter, speed noise +-%d studs/s around 40 (110 ms lead): largest frame-to-frame change %.2f studs before, %.2f after", noise, before, after))
		check("the ramp does not make the jitter worse at noise " .. noise, after <= before + 1e-9)

		if noise <= 2 then
			check("the ramp halves the jitter at small noise " .. noise, after < before * 0.5, string.format("%.2f vs %.2f", after, before))
		end
	end
end

print(string.format("lead model: %d passed, %d failed", passed, failed))

if failed > 0 then
	process.exit(1)
end

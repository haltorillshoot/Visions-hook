-- Golden master for the Lead model: runs the ORIGINAL inline prediction code (taken from the backup branch, not retyped) and src/Lead/LeadModel.lua
-- on the same random inputs and requires the same lead vector and the same trust flag, bit for bit (NaN counts as equal to NaN).
--   lune run tests/lead/golden.spec
-- Needs git on the PATH and the backup branch in the repository.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local V3 = require("../support/vector3")

local BACKUP_REF = "backup/pre-rewrite-2026-11-04"
local CASES = 40000

local passed, failed = 0, 0

local function check(name, condition, detail)
	if condition then
		passed += 1
	else
		failed += 1
		print("FAIL", name, detail or "")
	end
end

-- the original code, sliced out of the backup branch by its own anchors ---------------------------------------------------
local result = process.exec("git", { "show", BACKUP_REF .. ":Visions-hook.lua" })
assert(result.ok, "git show failed: " .. tostring(result.stderr))
local original = string.gsub(result.stdout, "\r\n", "\n")

local commentAt = string.find(original, "Prediction: the lead from the target's measured velocity", 1, true)
local startMarker = "                local lead = vector3_zero\n                local trusted_fast = false\n"
local endMarker = "\n                ragebot_aim_position = hitbox_position + lead\n"
local startAt = commentAt and string.find(original, startMarker, commentAt, true)
local endAt = startAt and string.find(original, endMarker, startAt, true)

check("original block found", startAt ~= nil and endAt ~= nil)
assert(startAt and endAt, "cannot slice the original prediction block")

local snippet = string.sub(original, startAt, endAt)
check("original block has the expected size", #snippet > 3500 and #snippet < 6500, #snippet)

-- environment the original code expects ------------------------------------------------------------------------------------
local floorHeight = nil
local workspace = { Gravity = 196.2 }

function workspace.Raycast(_, origin, direction)
	if floorHeight == nil or direction.Y >= 0 then
		return nil
	end

	if floorHeight <= origin.Y and floorHeight >= origin.Y + direction.Y then
		return { Position = V3.new(origin.X, floorHeight, origin.Z) }
	end

	return nil
end

local originalEnvironment = {
	vector3_zero = V3.zero,
	vector3_new = V3.new,
	math = math,
	tonumber = tonumber,
	workspace = workspace,
	Enum = { RaycastFilterType = { Exclude = "Exclude" } },
	RaycastParams = {
		new = function()
			return {}
		end,
	},
	find_first_child = function()
		return {}
	end,
}

local originalChunk = luau.load("local target_velocity, torso, hide_manager, flags, prediction, local_ping, hitbox_position, target, local_character = ...\n" .. snippet .. "\nreturn lead, trusted_fast", { environment = originalEnvironment })

local function loadModel(source)
	return luau.load(source, { environment = { Vector3 = V3, math = math } })()
end

local modelSource = string.gsub(fs.readFile("src/Lead/LeadModel.lua"), "\r\n", "\n")

local function probe(origin, direction)
	return workspace.Raycast(nil, origin, direction) and floorHeight or nil
end

-- random inputs ------------------------------------------------------------------------------------------------------------
math.randomseed(20261104)

local function random(low, high)
	return low + math.random() * (high - low)
end

local function randomDirection()
	local x, y, z = random(-1, 1), random(-1, 1), random(-1, 1)
	local length = math.sqrt(x * x + y * y + z * z)

	if length < 1e-6 then
		return V3.new(1, 0, 0)
	end

	return V3.new(x / length, y / length, z / length)
end

local function randomVelocity()
	local pick = math.random(1, 10)
	local speed

	if pick == 1 then
		speed = 0
	elseif pick == 2 then
		speed = random(0, 30)
	elseif pick <= 5 then
		speed = random(30, 80)
	elseif pick <= 8 then
		speed = random(80, 300)
	elseif pick == 9 then
		speed = random(300, 700)
	else
		speed = random(0, 5000)
	end

	local velocity = randomDirection() * speed

	if math.random(1, 25) == 1 then
		velocity = V3.new(0 / 0, velocity.Y, velocity.Z)
	end

	return velocity
end

local function randomCase()
	local velocity = randomVelocity()
	local measured = velocity
	local replicated = nil
	local kind = math.random(1, 5)

	if kind == 1 then
		replicated = nil
	elseif kind == 2 then
		replicated = velocity + randomDirection() * random(0, 20)
	elseif kind == 3 then
		replicated = randomVelocity()
	elseif kind == 4 then
		replicated = velocity
	else
		measured = randomVelocity()
		replicated = velocity
	end

	local leadFast = nil
	local leadFastPick = math.random(1, 3)

	if leadFastPick == 2 then
		leadFast = true
	elseif leadFastPick == 3 then
		leadFast = false
	end

	local strengthPick = math.random(1, 5)
	local hitbox = V3.new(random(-500, 500), random(0, 400), random(-500, 500))
	local floor = nil

	if math.random(1, 3) ~= 1 then
		floor = hitbox.Y - random(0, 120)
	end

	return {
		velocity = velocity,
		measured = measured,
		replicated = replicated,
		hasMeasured = math.random(1, 4) ~= 1,
		resolver = math.random(1, 2) == 1,
		prediction = ({ 0, 2, 0.15, 0.5, 1.2 })[math.random(1, 5)],
		ping = random(15, 400),
		leadFast = leadFast,
		steady = ({ true, false, nil })[math.random(1, 3)],
		strength = ({ false, 50, 100, 147, 200 })[strengthPick],
		hitbox = hitbox,
		floor = floor,
	}
end

---Run `count` random cases through the original and through the new code; the new code is the module itself, or the wired call site when one is given.
local function compare(model, quiet, wiredChunk)
	local mismatches, shown = 0, 0

	for index = 1, CASES do
		local case = randomCase()
		floorHeight = case.floor

		local flags = { auto_fire_defensive = case.resolver, ragebot_lead_fast = case.leadFast, prediction_strength = case.strength or nil }
		local hideManager = { target_delta_velocity = case.hasMeasured and case.measured or nil, velocity_steady = case.steady }
		local target = { nil, nil, "target character" }
		local torso = case.replicated ~= nil and { AssemblyLinearVelocity = case.replicated } or nil

		-- The original reads the replicated velocity off the torso, so a nil one means no torso property at all.
		if torso == nil then
			torso = { AssemblyLinearVelocity = nil }
		end

		local expectedLead, expectedTrusted = originalChunk(case.velocity, torso, hideManager, flags, case.prediction, case.ping, case.hitbox, target, "me")
		local lead, trusted

		if wiredChunk then
			local wiredManager = { target_delta_velocity = hideManager.target_delta_velocity, velocity_steady = hideManager.velocity_steady, lead_model = model }

			lead, trusted = wiredChunk(case.velocity, torso, wiredManager, flags, case.prediction, case.ping, case.hitbox, target, "me")
		else
			lead, trusted = model.compute(
				case.velocity,
				hideManager.target_delta_velocity or case.velocity,
				torso.AssemblyLinearVelocity,
				flags.auto_fire_defensive,
				case.prediction,
				case.ping,
				flags.ragebot_lead_fast,
				hideManager.velocity_steady,
				tonumber(flags.prediction_strength) or 100,
				workspace.Gravity,
				case.hitbox,
				probe,
				target[3]
			)
		end

		if not (V3.sameVector(lead, expectedLead) and trusted == expectedTrusted) then
			mismatches += 1

			if shown < 3 and not quiet then
				shown += 1
				print(string.format("  mismatch #%d: expected (%s, %s, %s) trusted=%s, got (%s, %s, %s) trusted=%s", index, expectedLead.X, expectedLead.Y, expectedLead.Z, tostring(expectedTrusted), lead.X, lead.Y, lead.Z, tostring(trusted)))
			end
		end
	end

	return mismatches
end

-- the real comparison ------------------------------------------------------------------------------------------------------
local mismatches = compare(loadModel(modelSource))
check("module matches the original prediction block on " .. CASES .. " random cases", mismatches == 0, mismatches .. " mismatches")

-- the call site in Visions-hook.lua: the same random cases through the code that is actually shipped ------------------------------------
local shipped = string.gsub(fs.readFile("Visions-hook.lua"), "\r\n", "\n")
local shippedCommentAt = string.find(shipped, "Prediction: the lead from the target's measured velocity", 1, true)
local shippedStart = shippedCommentAt and string.find(shipped, startMarker, shippedCommentAt, true)
local shippedEnd = shippedStart and string.find(shipped, endMarker, shippedStart, true)

check("shipped call site found", shippedStart ~= nil and shippedEnd ~= nil)
assert(shippedStart and shippedEnd, "cannot slice the shipped prediction block")

local shippedSnippet = string.sub(shipped, shippedStart, shippedEnd)
local header = "local target_velocity, torso, hide_manager, flags, prediction, local_ping, hitbox_position, target, local_character = ...\n"

local function loadWired(snippetText)
	return luau.load(header .. snippetText .. "\nreturn lead, trusted_fast", { environment = originalEnvironment })
end

local lead = loadModel(modelSource)
local wiredMismatches = compare(lead, false, loadWired(shippedSnippet))
check("shipped call site matches the original on " .. CASES .. " random cases", wiredMismatches == 0, wiredMismatches .. " mismatches")

local wiredMutations = {
	{ "strength default", 'tonumber(flags["prediction_strength"]) or 100', 'tonumber(flags["prediction_strength"]) or 101' },
	{ "lead fast flag", 'flags["ragebot_lead_fast"],', 'flags["auto_fire_defensive"],' },
	{ "replicated velocity", 'torso and torso["AssemblyLinearVelocity"],', "nil," },
	{ "measured velocity", 'hide_manager["target_delta_velocity"] or target_velocity,', "target_velocity," },
	{ "gravity", 'workspace["Gravity"],', "196," },
}

for _, mutation in ipairs(wiredMutations) do
	local start, finish = string.find(shippedSnippet, mutation[2], 1, true)
	local found = -1

	if start then
		found = compare(lead, true, loadWired(string.sub(shippedSnippet, 1, start - 1) .. mutation[3] .. string.sub(shippedSnippet, finish + 1)))
	end

	check("call site mutation is caught: " .. mutation[1], found > 0, found == -1 and "pattern not found" or "not detected")
end

-- the comparison itself must be able to fail: every mutation of the module has to be caught --------------------------------
local mutations = {
	{ "trusted cap", "Lead.CAP_TRUSTED = 150", "Lead.CAP_TRUSTED = 149" },
	{ "untrusted cap", "Lead.CAP = 60", "Lead.CAP = 61" },
	{ "trust speed", "Lead.TRUST_MIN_SPEED = 30", "Lead.TRUST_MIN_SPEED = 31" },
	{ "desync speed", "Lead.DESYNC_SPEED = 80", "Lead.DESYNC_SPEED = 81" },
	{ "display delay", "Lead.DISPLAY_DELAY = 0.16", "Lead.DISPLAY_DELAY = 0.17" },
	{ "gravity term", "0.5 * gravity * leadTime * leadTime", "0.4 * gravity * leadTime * leadTime" },
	{ "floor clearance", "Lead.FLOOR_CLEARANCE = 3.5", "Lead.FLOOR_CLEARANCE = 3.4" },
	{ "lead fast speed", "Lead.LEAD_FAST_SPEED = 60", "Lead.LEAD_FAST_SPEED = 61" },
}

---Replace the first plain text match, nil when there is none.
local function replacePlain(text, find, replace)
	local start, finish = string.find(text, find, 1, true)

	if not start then
		return nil
	end

	return string.sub(text, 1, start - 1) .. replace .. string.sub(text, finish + 1)
end

for _, mutation in ipairs(mutations) do
	local mutated = replacePlain(modelSource, mutation[2], mutation[3])
	local found = mutated and compare(loadModel(mutated), true) or -1

	check("mutation is caught: " .. mutation[1], found > 0, found == -1 and "pattern not found" or "not detected")
end

print(string.format("lead golden master: %d passed, %d failed", passed, failed))

if failed > 0 then
	process.exit(1)
end

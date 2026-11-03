-- Vanta audit harness. Run it in the executor with Vanta.lua in the workspace folder next to it:
--   loadstring(readfile("VantaAudit.lua"))()
-- It loads Vanta, then checks: the config round trip, every toggle on at once (errors and frame time), everything off again (nothing left behind),
-- unloading (nothing left behind) and repeated loads (memory). It skips the toggles that spend cash, fire at players, kick you or switch off the screen.
-- Everything it prints starts with "AUDIT".

local environment = getgenv()
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local logService = game:GetService("LogService")
local localPlayer = players.LocalPlayer

local SKIP = {
	shop_armor = true, shop_ammo = true, shop_heal = true, shop_mask = true, shop_loadout = true, shop_safe = true,
	autofire_enabled = true, fullauto_enabled = true, trigger_enabled = true, silent_enabled = true, autostomp_enabled = true,
	antibounty_enabled = true, autobounty_enabled = true, world_no_render = true, world_hide_chat = true, sorter_enabled = true,
	skins_enabled = true,
}

local function say(...)
	print("AUDIT", ...)
end

local function loadVanta()
	if environment.Vanta then
		pcall(environment.Vanta.unload)
		task.wait(1)
	end

	local chunk, compileError = loadstring(readfile("Vanta.lua"))

	assert(chunk, compileError)

	local ok, runError = xpcall(chunk, function(message)
		return tostring(message)
	end)

	assert(ok, runError)
	task.wait(2.5)

	return environment.Vanta
end

local function countDescendants(root)
	local ok, descendants = pcall(root.GetDescendants, root)

	return ok and #descendants or -1
end

local function footprint()
	local hidden = nil

	pcall(function()
		hidden = gethui()
	end)

	return {
		coreGui = countDescendants(game:GetService("CoreGui")),
		hidden = hidden and countDescendants(hidden) or 0,
		workspace = #workspace:GetChildren(),
		camera = #workspace.CurrentCamera:GetChildren(),
		lighting = #game:GetService("Lighting"):GetChildren(),
		sound = #game:GetService("SoundService"):GetChildren(),
		character = localPlayer.Character and countDescendants(localPlayer.Character) or 0,
	}
end

local function diff(before, after)
	local changes = {}

	for key, value in before do
		if after[key] ~= value then
			changes[#changes + 1] = string.format("%s %d->%d", key, value, after[key])
		end
	end

	return #changes == 0 and "identical" or table.concat(changes, ", ")
end

local errors = {}

logService.MessageOut:Connect(function(message, kind)
	if kind == Enum.MessageType.MessageError then
		errors[#errors + 1] = message:sub(1, 160)
	end
end)

local function frameTime(seconds)
	local frames, started = 0, os.clock()
	local connection = runService.Heartbeat:Connect(function()
		frames += 1
	end)

	task.wait(seconds)
	connection:Disconnect()

	return (os.clock() - started) / math.max(frames, 1) * 1000
end

-- 0. before Vanta
if environment.Vanta then
	pcall(environment.Vanta.unload)
	task.wait(1.5)
end

local clean = footprint()
local vanta = loadVanta()
local flags, setters = vanta.library.flags, vanta.library.config_flags
local loaded = footprint()
local controls = 0

for _ in flags do
	controls += 1
end

say("flags", controls, "footprint before Vanta vs after load", diff(clean, loaded))

-- 1. config round trip
local saved = vanta.library:get_config()
local changed = 0

for name, value in flags do
	if setters[name] and not SKIP[name] and type(value) == "number" then
		pcall(setters[name], value + 1)
		changed += 1
	end
end

vanta.library:load_config(saved)

local restored = vanta.library:get_config()
say("config round trip: changed", changed, "numbers, loaded the saved config, identical:", restored == saved)

-- 2. every toggle on at once
local other
for _, player in players:GetPlayers() do
	if player ~= localPlayer then
		other = player
	end
end

if other then
	vanta.target.set(other)
else
	vanta.target.player, vanta.target.character = localPlayer, localPlayer.Character
end

local baselineErrors = #errors
local baselineFrame = frameTime(2)
local toggles, turnedOn = {}, 0

for name, value in flags do
	if type(value) == "boolean" and setters[name] and not SKIP[name] then
		toggles[#toggles + 1] = { name, value }
	end
end

for _, entry in toggles do
	if entry[1] ~= "ragebot_enabled" then
		pcall(setters[entry[1]], true)
		turnedOn += 1
	end
end

pcall(setters["ragebot_enabled"], true)
task.wait(1)

local stressFrame = frameTime(5)

say("toggles switched on together", turnedOn + 1, "frame ms baseline", string.format("%.2f", baselineFrame), "all on", string.format("%.2f", stressFrame))
say("errors logged while everything was on", #errors - baselineErrors)

for index = baselineErrors + 1, math.min(#errors, baselineErrors + 8) do
	say("  error", errors[index])
end

-- 3. everything off again
for _, entry in toggles do
	pcall(setters[entry[1]], entry[2])
end

vanta.target.clear()
task.wait(2)

local afterOff = footprint()

say("everything off again, footprint vs just after load:", diff(loaded, afterOff))

-- 4. unload
vanta.unload()
task.wait(2)

local afterUnload = footprint()

say("after unload, footprint vs before Vanta:", diff(clean, afterUnload), "| Vanta global gone:", environment.Vanta == nil)

-- 5. repeated loads (the executor only allows collectgarbage("count"), so the numbers include whatever the collector has not freed yet; a leak shows as steady growth)

local memoryFirst
local cycles = 5

for cycle = 1, cycles do
	loadVanta()
	environment.Vanta.unload()
	task.wait(1)

	if cycle == 1 then
		memoryFirst = collectgarbage("count")
	end
end

local memoryLast = collectgarbage("count")

say("memory after cycle 1:", string.format("%.0f KB", memoryFirst), "after cycle " .. cycles .. ":", string.format("%.0f KB", memoryLast), "growth per later cycle:", string.format("%.0f KB", (memoryLast - memoryFirst) / (cycles - 1)))
say("hook layers installed:", (function()
	local count = 0

	for _ in environment.VantaHooks or {} do
		count += 1
	end

	return count
end)())
say("done")

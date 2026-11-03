-- Vanta: a modular HvH script for Da Hood on the Priv9 UI.
-- Layout: Util -> Settings -> Players -> Target -> Resolver -> Aim -> Body -> Follow -> VoidSpam -> AutoFire -> Ragebot -> Menu.
-- Every module reads its settings live from the UI flags, so a loaded config takes effect without any extra wiring, and each module cleans up after
-- itself when its toggle goes off or the script unloads. One Heartbeat driver (Ragebot) steps the modules in a fixed order; only Body ever moves the
-- character, and it asks Void Spam first and Follow second, so the two can never fight over the character.

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local environment = getgenv()

if environment.Vanta and environment.Vanta.unload then
	pcall(environment.Vanta.unload)
end

-- Services.
local playersService = game:GetService("Players")
local runService = game:GetService("RunService")
local userInputService = game:GetService("UserInputService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local statsService = game:GetService("Stats")

-- Constants.
local VOID_DISTANCE = 9e5
local MAX_REAL_SPEED = 80
local HISTORY_SECONDS = 3
local LIBRARY_URL = "https://raw.githubusercontent.com/i77lhm/Libraries/refs/heads/main/Priv9/Library.lua"

local localPlayer = playersService.LocalPlayer
local camera = workspace.CurrentCamera
local mouse = localPlayer:GetMouse()

---@module Util
local Util = {}

---Small connection and task bag. Everything a module creates goes in one so unloading is a single call.
local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({ tasks = {} }, Maid)
end

---Keep a connection, function or instance for cleaning later.
---@param task any
function Maid:give(task)
	self.tasks[#self.tasks + 1] = task
	return task
end

function Maid:clean()
	local tasks = self.tasks
	self.tasks = {}

	for _, task in tasks do
		local kind = typeof(task)

		if kind == "RBXScriptConnection" then
			task:Disconnect()
		elseif kind == "function" then
			pcall(task)
		elseif kind == "Instance" then
			task:Destroy()
		end
	end
end

Util.Maid = Maid

---True for a position that is out in the void rather than on the map.
---@param position Vector3
function Util.inVoid(position)
	local magnitude = position.Magnitude

	return magnitude ~= magnitude or magnitude >= VOID_DISTANCE
end

---Round-trip time in seconds.
function Util.ping()
	local ok, value = pcall(function()
		return statsService.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)

	return ok and value / 1000 or 0.05
end

---Safe flag read: the Priv9 library keeps every control's value in library.flags.
local library, notifications
local function flag(name, fallback)
	local value = library and library.flags[name]

	if value == nil then
		return fallback
	end

	return value
end

---Whether a dropdown (single or multi) has the item selected.
local function picked(name, item, fallback)
	local value = flag(name, fallback)

	if type(value) == "table" then
		return table.find(value, item) ~= nil
	end

	return value == item
end

---@module Players
local Players = {}

---@param player Player
function Players.root(player)
	local character = player and player.Character

	return character and character:FindFirstChild("HumanoidRootPart")
end

---Da Hood keeps the real state in BodyEffects; Humanoid.Health stays above 0 until the character is removed.
---@param player Player
---@return string? phase "respawning", "loading", "protected" or nil when the player can be hit
function Players.phase(player)
	local character = player.Character

	if not character then
		return "respawning"
	end

	local effects = character:FindFirstChild("BodyEffects")
	local dead = effects and effects:FindFirstChild("Dead")
	local sdeath = effects and effects:FindFirstChild("SDeath")

	if (dead and dead.Value) or (sdeath and sdeath.Value) then
		return "respawning"
	end

	if not effects or not character:FindFirstChild("HumanoidRootPart") or not character:FindFirstChild("FULLY_LOADED_CHAR") then
		return "loading"
	end

	if character:FindFirstChild("ForceField") or character:FindFirstChild("FORCEFIELD") then
		return "protected"
	end

	return nil
end

---@param player Player
function Players.knocked(player)
	local character = player.Character
	local effects = character and character:FindFirstChild("BodyEffects")
	local value = effects and effects:FindFirstChild("K.O")

	return value ~= nil and value.Value == true
end

---Health as a fraction for target selection.
---@param player Player
function Players.health(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	return humanoid and humanoid.Health or math.huge
end

---@module Target
---One selected target for every module. Nothing else keeps its own copy of "who we are shooting at".
local Target = {
	player = nil,
	character = nil,
	changed = {}, -- callbacks(newPlayer)
}

local function setTarget(player)
	if Target.player == player and (player == nil or Target.character == player.Character) then
		return
	end

	Target.player = player
	Target.character = player and player.Character or nil

	for _, callback in Target.changed do
		task.spawn(callback, player)
	end
end

---Whether a player can be picked as a target right now.
---@param player Player
function Target.eligible(player)
	if player == localPlayer or not Players.root(player) then
		return false
	end

	local phase = Players.phase(player)

	if phase == "respawning" or phase == "loading" then
		return false
	end

	if phase == "protected" and picked("target_ignore_if", "protected", { "in void", "protected", "knocked" }) then
		return false
	end

	if Players.knocked(player) and picked("target_ignore_if", "knocked", { "in void", "protected", "knocked" }) then
		return false
	end

	return true
end

local function pick()
	local mode = flag("target_priority", "closest to mouse")
	local myRoot = Players.root(localPlayer)
	local mouseLocation = userInputService:GetMouseLocation()
	local fov = flag("target_fov", 180)
	local maxDistance = flag("target_distance", 1000)
	local best, bestScore = nil, math.huge

	for _, player in playersService:GetPlayers() do
		if not Target.eligible(player) then
			continue
		end

		local root = Players.root(player)
		local position = root.Position
		local score = nil

		if Util.inVoid(position) and picked("target_ignore_if", "in void", { "in void", "protected", "knocked" }) then
			continue
		end

		if myRoot and not Util.inVoid(position) and (position - myRoot.Position).Magnitude > maxDistance then
			continue
		end

		if mode == "closest to mouse" then
			local screen, onScreen = camera:WorldToViewportPoint(position)

			if not onScreen then
				continue
			end

			score = (Vector2.new(screen.X, screen.Y) - mouseLocation).Magnitude

			if score > fov then
				continue
			end
		elseif mode == "closest to character" then
			score = myRoot and (position - myRoot.Position).Magnitude or math.huge
		elseif mode == "lowest health" then
			score = Players.health(player)
		else
			score = math.random()
		end

		if score < bestScore then
			best, bestScore = player, score
		end
	end

	return best
end

---The target key: the first press selects a target, the next one clears it.
function Target.toggle()
	if Target.player then
		setTarget(nil)
		return false
	end

	setTarget(pick())

	return Target.player ~= nil
end

function Target.clear()
	setTarget(nil)
end

Target.set = setTarget

local lastAutoPick = 0

---Keeps the target honest every frame: left the game, respawned, died or got knocked.
function Target.step(now)
	local player = Target.player

	if player then
		local gone = player.Parent ~= playersService
		local drop = false

		if not gone then
			local root = Players.root(player)

			-- the conditions the Untarget When list names; Auto Stomp keeps a knocked target so it can be finished
			drop = (picked("target_untarget_when", "dead", { "dead" }) and Players.phase(player) == "respawning")
				or (picked("target_untarget_when", "knocked", { "dead" }) and Players.knocked(player) and not flag("autostomp_enabled", false))
				or (picked("target_untarget_when", "flung", { "dead" }) and root ~= nil and root.AssemblyLinearVelocity.Magnitude > 250)
		end

		if gone or drop then
			setTarget(nil)
		elseif player.Character ~= Target.character then
			-- a new character: same player, fresh state for everything that tracks it
			Target.character = player.Character

			for _, callback in Target.changed do
				task.spawn(callback, player)
			end
		end
	end

	if not Target.player and flag("target_automatic", false) and now - lastAutoPick >= flag("target_cooldown", 0.25) then
		lastAutoPick = now
		setTarget(pick())
	end
end

---@module Resolver
---Works out where a target really is. A target that hops between spots (void spam, desync) shows up at its true place far more often than at any one
---fake one, so the spots seen on the map over the last moments are binned into a grid and the busiest bin wins. A target that moves like a player is
---simply where it shows, plus a short lead.
local Resolver = {
	samples = {},
	lastMap = nil,
	lastMapAt = 0,
	confidence = 0,
	source = "none",
	jumpedAt = nil :: number?,
	clusteredAt = -1,
	cluster = nil :: Vector3?,
	clusterShare = 0,
	velocity = Vector3.zero,
}

function Resolver.reset()
	table.clear(Resolver.samples)
	Resolver.lastMap = nil
	Resolver.lastMapAt = 0
	Resolver.confidence = 0
	Resolver.source = "none"
	Resolver.jumpedAt = nil
	Resolver.clusteredAt = -1
	Resolver.cluster = nil
	Resolver.clusterShare = 0
end

---Record where the target shows this frame.
---@param position Vector3
---@param now number
function Resolver.record(position, now)
	local samples = Resolver.samples

	samples[#samples + 1] = { position = position, time = now }

	-- drop what is older than the history window, in one pass from the front
	local keepFrom = 1

	while keepFrom < #samples and now - samples[keepFrom].time > HISTORY_SECONDS do
		keepFrom += 1
	end

	if keepFrom > 1 then
		table.move(samples, keepFrom, #samples, 1)

		for index = #samples - keepFrom + 2, #samples do
			samples[index] = nil
		end
	end

	if not Util.inVoid(position) then
		Resolver.lastMap = position
		Resolver.lastMapAt = now
	end
end

---The map sightings of the last `window` seconds.
local function recentMap(now, window)
	local found = {}

	for index = #Resolver.samples, 1, -1 do
		local sample = Resolver.samples[index]

		if now - sample.time > window then
			break
		end

		if not Util.inVoid(sample.position) then
			found[#found + 1] = sample.position
		end
	end

	return found
end

---The centre of the busiest grid bin (with its neighbours) among the points, and how big a share of them sits there.
local function busiestCluster(points, radius)
	local bins, bestKey, bestCount = {}, nil, 0

	for _, point in points do
		local key = Vector3.new(math.floor(point.X / radius), math.floor(point.Y / radius), math.floor(point.Z / radius))
		local bin = bins[key]

		if not bin then
			bin = { count = 0, sum = Vector3.zero }
			bins[key] = bin
		end

		bin.count += 1
		bin.sum += point
	end

	for key, bin in bins do
		local count = bin.count

		-- the neighbouring bins count too, so a cluster that straddles a bin edge is not split in two
		for x = -1, 1 do
			for y = -1, 1 do
				for z = -1, 1 do
					if x ~= 0 or y ~= 0 or z ~= 0 then
						local neighbour = bins[key + Vector3.new(x, y, z)]
						count += neighbour and neighbour.count or 0
					end
				end
			end
		end

		if count > bestCount then
			bestKey, bestCount = key, count
		end
	end

	if not bestKey then
		return nil, 0
	end

	local sum, total = Vector3.zero, 0

	for x = -1, 1 do
		for y = -1, 1 do
			for z = -1, 1 do
				local bin = bins[bestKey + Vector3.new(x, y, z)]

				if bin then
					sum += bin.sum
					total += bin.count
				end
			end
		end
	end

	return sum / total, total / #points
end

---Velocity over the last tenth of a second of map sightings.
local function measuredVelocity()
	local samples = Resolver.samples
	local newest = samples[#samples]

	if not newest or Util.inVoid(newest.position) then
		return Vector3.zero
	end

	for index = #samples - 1, 1, -1 do
		local older = samples[index]
		local span = newest.time - older.time

		if span >= 0.1 then
			if Util.inVoid(older.position) then
				return Vector3.zero
			end

			return (newest.position - older.position) / span
		end
	end

	return Vector3.zero
end

---@param now number
---@return Vector3? aim, number confidence
function Resolver.aim(now)
	local samples = Resolver.samples
	local newest = samples[#samples]

	if not newest then
		return nil, 0
	end

	local mode = flag("resolver_mode", "adaptive")
	local radius = flag("resolver_radius", 12)
	local window = flag("resolver_window", 1.5)
	local shows = newest.position
	local onMap = not Util.inVoid(shows)
	local velocity = measuredVelocity()

	Resolver.velocity = velocity
	local fast = velocity.Magnitude > MAX_REAL_SPEED
	local useCluster = mode == "cluster" or (mode == "adaptive" and (not onMap or fast or Resolver.jumpedAt and now - Resolver.jumpedAt < 0.75))

	-- a step between two sightings that no player could walk marks the target as a faker for a moment
	local previous = samples[#samples - 1]

	if previous and onMap and not Util.inVoid(previous.position) then
		local dt = math.max(newest.time - previous.time, 1 / 240)

		if (newest.position - previous.position).Magnitude / dt > MAX_REAL_SPEED * 2 then
			Resolver.jumpedAt = now
		end
	end

	if useCluster and mode ~= "off" then
		-- the clustering is the one expensive step, so it is redone at most 20 times a second and the answer is reused in between
		if now - Resolver.clusteredAt >= 0.05 then
			Resolver.clusteredAt = now

			local points = recentMap(now, window)

			Resolver.cluster, Resolver.clusterShare = nil, 0

			if #points >= 3 then
				Resolver.cluster, Resolver.clusterShare = busiestCluster(points, radius)
			end
		end

		if Resolver.cluster then
			Resolver.source, Resolver.confidence = "cluster", Resolver.clusterShare

			return Resolver.cluster, Resolver.clusterShare
		end

		-- nothing to cluster on yet: the last place it stood on the map, for a short while only
		if Resolver.lastMap and now - Resolver.lastMapAt < flag("resolver_hold", 1.5) then
			Resolver.source = "held"
			Resolver.confidence = 0.3

			return Resolver.lastMap, 0.3
		end

		Resolver.source, Resolver.confidence = "none", 0

		return nil, 0
	end

	if not onMap then
		Resolver.source, Resolver.confidence = "none", 0

		return nil, 0
	end

	-- a normal mover: where it shows plus the distance it covers while the shot is on its way
	local strength = flag("resolver_lead", 100) / 100
	local lead = velocity * (Util.ping() + 0.04) * strength

	if lead.Magnitude > 30 then
		lead = lead.Unit * 30
	end

	Resolver.source, Resolver.confidence = "direct", 1

	return shows + Vector3.new(lead.X, 0, lead.Z), 1
end

---@module Aim
---Silent aim for the game's own gun scripts: while an aim is set, the mouse's Hit and Target read as the aim position for scripts other than ours.
local Aim = { position = nil, part = nil, expires = 0, active = true, hooked = false }

function Aim.set(position, part, now, duration)
	Aim.position, Aim.part, Aim.expires = position, part, now + (duration or 0.15)
end

function Aim.clear()
	Aim.position, Aim.part, Aim.expires = nil, nil, 0
end

function Aim.install()
	if Aim.hooked then
		return
	end

	Aim.hooked = true

	local original
	original = hookmetamethod(game, "__index", newcclosure(function(self, key)
		if Aim.active and Aim.position and self == mouse and not checkcaller() then
			if os.clock() > Aim.expires then
				Aim.clear()
			elseif key == "Hit" then
				return CFrame.new(Aim.position)
			elseif key == "Target" and Aim.part then
				return Aim.part
			end
		end

		return original(self, key)
	end))
end

---@module Body
---The one place that moves the character. The modules above it return the CFrame they want for this frame; Body applies the first answer on Heartbeat
---(after the physics step, before replication) and puts the real CFrame back before the frame is drawn, so the camera and the player's own control are
---not disturbed.
local Body = {
	providers = {}, -- ordered { name, want(now) -> CFrame? }
	real = nil,
	applied = false,
	appliedAt = 0,
	spot = nil,
	spotAt = 0,
	lastMap = nil :: CFrame?,
}

function Body.addProvider(name, want)
	Body.providers[#Body.providers + 1] = { name = name, want = want }
end

local function bodyRoot()
	local character = localPlayer.Character

	return character and character:FindFirstChild("HumanoidRootPart")
end

---Called on Heartbeat.
function Body.apply(now)
	local root = bodyRoot()

	if not root or Body.applied then
		return
	end

	if not Util.inVoid(root.Position) then
		Body.lastMap = root.CFrame
	end

	for _, provider in Body.providers do
		local cframe = provider.want(now)

		if cframe then
			Body.real = { cframe = root.CFrame, velocity = root.AssemblyLinearVelocity }
			Body.applied = true

			-- a new place the server has to catch up with: shots wait for it (see Body.settled)
			if not Body.spot or (Body.spot - cframe.Position).Magnitude > 4 then
				Body.spotAt = now
			end

			Body.spot = cframe.Position
			root.CFrame = cframe
			root.AssemblyLinearVelocity = Vector3.zero

			return
		end
	end

	Body.spot = nil
end

---Called before the frame is drawn.
function Body.restore()
	if not Body.applied then
		return
	end

	Body.applied = false

	local root = bodyRoot()

	if root and Body.real then
		root.CFrame = Body.real.cframe
		root.AssemblyLinearVelocity = Body.real.velocity
	end

	Body.real = nil
end

---Whether the server has had the body at its current spot long enough for a shot from there to count.
function Body.settled(now)
	return Body.spot ~= nil and now - Body.spotAt >= Util.ping() + 0.04
end

---@module Follow
local Follow = { held = nil :: Vector3?, heldAt = 0, heldStyle = "", aim = nil :: Vector3? }

local function ringOffset(angle, distance)
	return Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

local POLYGON_SIDES = { triangle = 3, square = 4, pentagon = 5, hexagon = 6, decagon = 10 }

---A point on the chosen shape round the target, `phase` being how far round it is (0 to 1).
local function shapeOffset(shape, phase, radius)
	local sides = POLYGON_SIDES[shape]

	if sides then
		-- along the straight edges between the corners
		local scaled = phase * sides
		local corner = math.floor(scaled)
		local along = scaled - corner
		local from = ringOffset(corner / sides * math.pi * 2, radius)
		local to = ringOffset((corner + 1) / sides * math.pi * 2, radius)

		return from:Lerp(to, along)
	end

	if shape == "heart" then
		local t = phase * math.pi * 2
		local x = 16 * math.sin(t) ^ 3
		local z = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)

		return Vector3.new(x, 0, z) * (radius / 16)
	end

	return ringOffset(phase * math.pi * 2, radius)
end

---Follow's reasons to stand still.
local function followStopped(player)
	if picked("follow_stop_if", "target knocked", { "no gun equipped", "target knocked", "reloading" }) and player and Players.knocked(player) then
		return true
	end

	local character = localPlayer.Character

	if picked("follow_stop_if", "no gun equipped", { "no gun equipped", "target knocked", "reloading" }) and character then
		local tool = character:FindFirstChildOfClass("Tool")

		if not (tool and tool:FindFirstChild("Ammo")) then
			return true
		end
	end

	if picked("follow_stop_if", "reloading", { "no gun equipped", "target knocked", "reloading" }) and character then
		local effects = character:FindFirstChild("BodyEffects")
		local reload = effects and effects:FindFirstChild("Reload")

		if reload and reload.Value == true then
			return true
		end
	end

	return false
end

---Where the body goes for a given aim position, in the chosen style. Shared with Void Spam so a window out of the void uses the same place.
---@param aim Vector3
---@param now number
---@return CFrame
function Follow.cframeFor(aim, now)
	-- Lead: where the target will be by the time the body has been taken there (its speed times Lead Time, at most 60 studs)
	if flag("follow_lead", true) then
		local lead = Resolver.velocity * (flag("follow_lead_time", 80) / 1000)

		if lead.Magnitude > 60 then
			lead = lead.Unit * 60
		end

		aim += Vector3.new(lead.X, 0, lead.Z)
	end

	local style = flag("follow_style", "orbit")
	local shape = flag("follow_shape", "circle")
	local distance = flag("follow_distance", 15)
	local height = flag("follow_height", 0)
	local low, high = flag("follow_sky_min", 10), flag("follow_sky_max", 20)
	local reposition = flag("follow_reposition", 0.05)
	local offset

	if style == "orbit" then
		offset = shapeOffset(shape, (now * flag("follow_speed", 75) / 100) % 1, distance) + Vector3.new(0, height, 0)
	elseif style == "zigzag" then
		local side = math.floor(now * flag("follow_zigzag_speed", 35) / 5) % 2 == 0 and 1 or -1

		offset = Vector3.new(side * distance, flag("follow_zigzag_height", 3), 0)
	else
		-- the styles that hop to a new place keep it for `reposition` seconds (the server has the body about a tenth of a second late)
		if not Follow.held or now - Follow.heldAt >= reposition or Follow.heldStyle ~= style then
			local angle = math.random() * math.pi * 2

			if style == "random" then
				Follow.held = Vector3.new(math.random(-distance, distance), math.random(-distance, distance), math.random(-distance, distance))
			elseif style == "above" then
				Follow.held = Vector3.new(0, low + (high - low) * math.random(), 0)
			elseif style == "strafe above" then
				Follow.held = shapeOffset(shape, math.random(), distance) + Vector3.new(0, height + low + (high - low) * math.random(), 0)
			else
				-- "teleport": a random place round the target between Teleport Min and Teleport Max studs out, up to 5 studs over it
				local near = flag("follow_teleport_min", 2)
				local far = math.max(flag("follow_teleport_max", 17), near)

				Follow.held = ringOffset(angle, near + (far - near) * math.random()) + Vector3.new(0, math.random() * 5, 0)
			end

			Follow.heldAt, Follow.heldStyle = now, style
		end

		offset = Follow.held
	end

	return CFrame.lookAt(aim + offset, aim)
end

---Body provider: the follow's own place, whenever it is on and there is somewhere to go.
function Follow.want(now)
	if not flag("ragebot_enabled", false) or not flag("follow_enabled", false) or not Target.player then
		Follow.held = nil

		return nil
	end

	local aim = Follow.aim

	if not aim then
		return nil
	end

	if Util.inVoid(aim) and not flag("follow_into_void", true) then
		return nil
	end

	if localPlayer.Character and Players.knocked(localPlayer) then
		return nil
	end

	if followStopped(Target.player) then
		return nil
	end

	return Follow.cframeFor(aim, now)
end

---@module VoidSpam
---Cycles the body between the void and short windows at the target. A window only opens when a gun can shoot in it, because every moment out of the void
---is a moment the target can shoot back; if no gun is ready for IDLE_WINDOW seconds a window opens anyway so the cycle can never stop shooting.
local VoidSpam = { phase = "void", phaseAt = 0, spot = nil, idleSince = 0, baitUntil = 0, baitAt = 0, baitCFrame = nil :: CFrame?, deepSpot = nil :: CFrame?, deepFor = nil :: Instance? }

local IDLE_WINDOW = 2.5

local function randomVoidSpot()
	local range = 4e8

	return CFrame.new(math.random(-range, range), math.random(1e5, range), math.random(-range, range))
end

---One spot far out along a random direction, kept for the whole life (Deep Distance million studs): the body hardly moves there.
local function deepVoidSpot()
	if not VoidSpam.deepSpot or VoidSpam.deepFor ~= localPlayer.Character then
		local far = flag("voidspam_deep", 100) * 1e6
		local angle = math.random() * math.pi * 2

		VoidSpam.deepSpot = CFrame.new(math.cos(angle) * far, far * 0.5, math.sin(angle) * far)
		VoidSpam.deepFor = localPlayer.Character
	end

	return VoidSpam.deepSpot
end

local function voidSpot()
	if flag("voidspam_type", "random") == "deep" then
		return deepVoidSpot()
	end

	return randomVoidSpot()
end

---True when another player's gun reaches the spot (a bait visit there would be shot at).
local function coveredByOthers(spot)
	for _, player in playersService:GetPlayers() do
		if player ~= localPlayer and player ~= Target.player and not Players.knocked(player) then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local tool = character and character:FindFirstChildOfClass("Tool")
			local range = tool and tool:FindFirstChild("Range")

			if root and range and (root.Position - spot).Magnitude <= range.Value + 15 then
				return true
			end
		end
	end

	return false
end

---Bait: a short visit to a spot on the map every Bait Cooldown, Bait Time long, so a target that follows the body comes after it. A visit is skipped when
---another player's gun covers the spot or the body is below 40% health.
local function baitSpot(now)
	if now < VoidSpam.baitUntil and VoidSpam.baitCFrame then
		if flag("voidspam_bait_freeze", false) then
			return VoidSpam.baitCFrame
		end

		local jitter = flag("voidspam_offset", 3)

		return VoidSpam.baitCFrame + Vector3.new(math.random(-jitter, jitter), math.random(-jitter, jitter), math.random(-jitter, jitter))
	end

	if now - VoidSpam.baitAt < flag("voidspam_bait_cooldown", 0.5) then
		return nil
	end

	VoidSpam.baitAt = now

	local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")

	if humanoid and humanoid.Health < humanoid.MaxHealth * 0.4 then
		return nil
	end

	local spot

	if flag("voidspam_bait_spot", "random") == "where you stood" and Body.lastMap then
		spot = Body.lastMap
	else
		local range = flag("voidspam_bait_distance", 250)

		spot = CFrame.new(math.random(-range, range), math.random(-200, 200), math.random(-range, range))
	end

	if coveredByOthers(spot.Position) then
		return nil
	end

	VoidSpam.baitCFrame = spot
	VoidSpam.baitUntil = now + flag("voidspam_bait_time", 0.03)

	return spot
end

function VoidSpam.reset()
	VoidSpam.phase, VoidSpam.phaseAt, VoidSpam.spot, VoidSpam.idleSince = "void", 0, nil, 0
	VoidSpam.baitUntil, VoidSpam.baitAt, VoidSpam.baitCFrame = 0, 0, nil
end

---Set by AutoFire: whether any gun in hand could fire right now.
VoidSpam.gunReady = function()
	return true
end

function VoidSpam.want(now)
	if not flag("ragebot_enabled", false) or not flag("voidspam_enabled", false) then
		VoidSpam.reset()

		return nil
	end

	local aim = Follow.aim
	local valid = Target.player ~= nil and aim ~= nil

	if not valid then
		-- nobody to shoot at: stay hidden while waiting (a respawning target is waited for), otherwise leave the body alone
		if flag("voidspam_hide_waiting", true) and Target.player then
			VoidSpam.spot = VoidSpam.spot or voidSpot()

			return VoidSpam.spot
		end

		VoidSpam.reset()

		return nil
	end

	local settle = Util.ping() + 0.04
	local windowTime = math.max(flag("voidspam_window", 0.12), settle + 0.08)
	local voidTime = flag("voidspam_void", 0.35)
	local elapsed = now - VoidSpam.phaseAt

	if VoidSpam.phase == "void" then
		if elapsed >= voidTime then
			if VoidSpam.gunReady() or elapsed >= IDLE_WINDOW then
				VoidSpam.phase, VoidSpam.phaseAt, VoidSpam.spot = "window", now, nil
			end
		end
	elseif elapsed >= windowTime then
		VoidSpam.phase, VoidSpam.phaseAt, VoidSpam.spot = "void", now, nil
	end

	if VoidSpam.phase == "window" then
		local place = Follow.cframeFor(aim, now)
		local jitter = flag("voidspam_offset", 3)

		-- Offset: a little random movement on the window's place so the body is not a still target
		return place + Vector3.new(math.random(-jitter, jitter), math.random(-jitter, jitter), math.random(-jitter, jitter))
	end

	if flag("voidspam_type", "random") == "bait" then
		local visit = baitSpot(now)

		if visit then
			return visit
		end
	end

	VoidSpam.spot = VoidSpam.spot or voidSpot()

	return VoidSpam.spot
end

---@module AutoFire
---Fires the guns through the game's own tools: the gun is equipped, the aim is set for its script, and the tool is activated. Each gun keeps its own
---cooldown and ammo; a shotgun is never fired from or at the void (the server turns those calls away and counts them against its SecurityTolerance).
local AutoFire = { lastShot = {}, lastEquip = 0, lastReload = {}, current = nil, lastTool = nil :: Instance?, lastSent = 0 }

local function mainEvent()
	return replicatedStorage:FindFirstChild("MainEvent")
end

local function gunInfo(tool)
	local ammo = tool:FindFirstChild("Ammo")
	local range = tool:FindFirstChild("Range")
	local cooldown = tool:FindFirstChild("ShootingCooldown")

	if not (ammo and range and tool:FindFirstChild("Handle")) then
		return nil
	end

	return {
		tool = tool,
		ammo = ammo.Value,
		range = range.Value,
		cooldown = cooldown and cooldown.Value or 0.1,
		shotgun = tool:GetAttribute("SecurityTolerance") ~= nil,
	}
end

---Every gun the player has, equipped or in the backpack.
local function allGuns()
	local guns = {}
	local character = localPlayer.Character
	local backpack = localPlayer:FindFirstChild("Backpack")

	for _, container in { character, backpack } do
		if container then
			for _, tool in container:GetChildren() do
				if tool:IsA("Tool") then
					local info = gunInfo(tool)

					if info then
						guns[#guns + 1] = info
					end
				end
			end
		end
	end

	return guns
end

local function gunReadyAt(info, now, aim, myPosition)
	if info.ammo <= 0 then
		return false
	end

	if now - (AutoFire.lastShot[info.tool] or 0) < info.cooldown + 0.02 then
		return false
	end

	if (aim - myPosition).Magnitude > info.range then
		return false
	end

	if info.shotgun and (Util.inVoid(aim) or Util.inVoid(myPosition)) then
		return false
	end

	return true
end

---Whether anything could shoot at the current aim; Void Spam uses it to decide when a window is worth opening.
function AutoFire.anyReady()
	local aim = Follow.aim

	if not aim or Util.inVoid(aim) then
		return false
	end

	local now = os.clock()
	-- (the follow's own place is not worked out here: that would move its held spot; it stands about Distance from the aim)
	local position = aim + Vector3.new(flag("follow_distance", 15), 0, 0)

	for _, info in allGuns() do
		if gunReadyAt(info, now, aim, position) then
			return true
		end
	end

	return false
end

---Empty guns are reloaded while the body is hidden, one request per gun at a time.
local function reloadEmpty(now, guns)
	local event = mainEvent()

	if not event then
		return
	end

	for _, info in guns do
		if info.ammo <= 0 and now - (AutoFire.lastReload[info.tool] or 0) > 1.2 then
			AutoFire.lastReload[info.tool] = now
			event:FireServer("Reload", info.tool)

			return
		end
	end
end

function AutoFire.step(now)
	if not flag("autofire_enabled", false) then
		return
	end

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local aim = Follow.aim

	if not humanoid or humanoid.Health <= 0 or Players.knocked(localPlayer) then
		return
	end

	local guns = allGuns()

	if flag("autofire_reload", true) and (VoidSpam.phase == "void" or not flag("voidspam_enabled", false)) then
		reloadEmpty(now, guns)
	end

	if not aim or not Target.player or Util.inVoid(aim) then
		return
	end

	-- a shot from the void is thrown away, and one from a spot the server has not caught up with yet is refused
	if flag("voidspam_enabled", false) and VoidSpam.phase ~= "window" then
		return
	end

	if Body.spot and not Body.settled(now) then
		return
	end

	local position = Body.spot or (Players.root(localPlayer) and Players.root(localPlayer).Position)

	if not position or Util.inVoid(position) then
		return
	end

	local chosen = nil

	for _, info in guns do
		if gunReadyAt(info, now, aim, position) then
			if not chosen or info.cooldown > chosen.cooldown then
				-- the slow guns go first: a fast one would otherwise always arrive first and starve them
				chosen = info
			end
		end
	end

	if not chosen then
		return
	end

	-- Gun Gap: a different gun waits this long after the last one sent (the server takes about one shot per short window across all the guns)
	if AutoFire.lastTool and AutoFire.lastTool ~= chosen.tool and now - AutoFire.lastSent < flag("autofire_gap", 40) / 1000 then
		return
	end

	if chosen.tool.Parent ~= character then
		if now - AutoFire.lastEquip >= 0.15 then
			AutoFire.lastEquip = now
			humanoid:EquipTool(chosen.tool)
		end

		return
	end

	-- Hitboxes: the head when it is ticked (it wins over the others), otherwise the torso for body, arms and legs
	local root = Target.character and Target.character:FindFirstChild(picked("autofire_hitbox", "head", { "head" }) and "Head" or "HumanoidRootPart")

	Aim.set(aim, root, now, 0.2)
	AutoFire.lastShot[chosen.tool] = now
	AutoFire.lastTool, AutoFire.lastSent = chosen.tool, now
	chosen.tool:Activate()
end

---@module AutoStomp
---Finishes a knocked target: the body stands over its torso and asks the server to stomp. Asked before Follow and Void Spam, so a knocked target is
---stomped instead of followed.
local AutoStomp = { lastStomp = 0 }

local STOMP_OFFSET = Vector3.new(0, 3, 0)

function AutoStomp.want(now)
	if not flag("ragebot_enabled", false) or not flag("autostomp_enabled", false) then
		return nil
	end

	local player = Target.player
	local character = player and player.Character

	if not character or not Players.knocked(player) then
		return nil
	end

	-- a target that has died (or is loading again) has nothing left to stomp
	if flag("autostomp_stop_dead", true) and Players.phase(player) == "respawning" then
		return nil
	end

	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("HumanoidRootPart")

	-- a body that is being carried or flung cannot be stomped
	if not torso or character:FindFirstChild("GRABBING_CONSTRAINT") or torso.AssemblyLinearVelocity.Magnitude > 100 then
		return nil
	end

	if Util.inVoid(torso.Position) or Players.knocked(localPlayer) then
		return nil
	end

	if now - AutoStomp.lastStomp >= 0.05 then
		local event = mainEvent()

		if event then
			AutoStomp.lastStomp = now
			event:FireServer("Stomp")
		end
	end

	return CFrame.new(torso.Position + STOMP_OFFSET)
end

---@module Visuals
---Drawing-library visuals: the FOV circle, a tracer to the aim, a ring round the target, and the camera on the target. Objects are created when a
---feature is switched on and removed when it goes off, never every frame.
local Visuals = { objects = {}, ringSegments = 24, cameraSwapped = false }

local function drawing(kind, key, properties)
	local object = Visuals.objects[key]

	if not object then
		object = Drawing.new(kind)
		Visuals.objects[key] = object
	end

	for name, value in properties do
		object[name] = value
	end

	return object
end

local function removeDrawing(key)
	local object = Visuals.objects[key]

	if object then
		object:Remove()
		Visuals.objects[key] = nil
	end
end

local function pickerColor(name, fallback)
	local picker = flag(name)

	if type(picker) == "table" and picker.Color then
		return picker.Color, 1 - (picker.Transparency or 0)
	end

	return fallback, 1
end

function Visuals.clear()
	for key in Visuals.objects do
		removeDrawing(key)
	end

	if Visuals.cameraSwapped then
		Visuals.cameraSwapped = false

		local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")

		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

function Visuals.render()
	local enabled = flag("ragebot_enabled", false)
	local viewport = camera.ViewportSize
	local mouseLocation = userInputService:GetMouseLocation()
	local aim = Follow.aim
	local player = Target.player

	-- FOV circle
	if enabled and flag("fov_show", false) then
		local colour, opacity = pickerColor("fov_color", Color3.fromRGB(255, 255, 255))
		local activeColour, activeOpacity = pickerColor("fov_active_color", Color3.fromRGB(255, 80, 80))
		local active = player ~= nil

		drawing("Circle", "fov", {
			Visible = true,
			Position = mouseLocation,
			Radius = flag("target_fov", 180),
			Thickness = 1,
			NumSides = 64,
			Filled = false,
			Color = active and activeColour or colour,
			Transparency = active and activeOpacity or opacity,
		})
	else
		removeDrawing("fov")
	end

	-- Aim assist FOV circle (drawn whether or not the ragebot is on)
	if flag("aimassist_enabled", false) and flag("aimassist_show_fov", false) then
		local colour, opacity = pickerColor("aimassist_fov_color", Color3.fromRGB(255, 255, 255))

		drawing("Circle", "aafov", {
			Visible = true,
			Position = mouseLocation,
			Radius = flag("aimassist_fov", 120),
			Thickness = 1,
			NumSides = 64,
			Filled = false,
			Color = colour,
			Transparency = opacity,
		})
	else
		removeDrawing("aafov")
	end

	if flag("silent_enabled", false) and flag("silent_show_fov", false) then
		local colour, opacity = pickerColor("silent_fov_color", Color3.fromRGB(180, 180, 255))

		drawing("Circle", "safov", {
			Visible = true,
			Position = mouseLocation,
			Radius = flag("silent_fov", 120),
			Thickness = 1,
			NumSides = 64,
			Filled = false,
			Color = colour,
			Transparency = opacity,
		})
	else
		removeDrawing("safov")
	end

	-- Tracer
	if enabled and flag("tracer_show", false) and aim and not Util.inVoid(aim) then
		local screen, onScreen = camera:WorldToViewportPoint(aim)
		local colour, opacity = pickerColor("tracer_color", Color3.fromRGB(255, 255, 255))
		local origin = flag("tracer_origin", "bottom")
		local from = origin == "mouse" and mouseLocation or origin == "center" and viewport / 2 or Vector2.new(viewport.X / 2, viewport.Y)

		drawing("Line", "tracer", {
			Visible = onScreen,
			From = from,
			To = Vector2.new(screen.X, screen.Y),
			Thickness = flag("tracer_thickness", 1),
			Color = colour,
			Transparency = opacity,
		})
	else
		removeDrawing("tracer")
	end

	-- 3D ring round the target's feet
	if enabled and flag("circle_show", false) and aim and not Util.inVoid(aim) then
		local colour, opacity = pickerColor("circle_color", Color3.fromRGB(180, 120, 255))
		local radius = flag("circle_radius", 4)
		local spin = os.clock() * 1.5
		local previous

		for index = 0, Visuals.ringSegments do
			local angle = spin + index / Visuals.ringSegments * math.pi * 2
			local point, onScreen = camera:WorldToViewportPoint(aim + Vector3.new(math.cos(angle) * radius, -3, math.sin(angle) * radius))
			local current = Vector2.new(point.X, point.Y)

			if previous then
				drawing("Line", "ring" .. index, {
					Visible = onScreen and point.Z > 0,
					From = previous,
					To = current,
					Thickness = 1,
					Color = colour,
					Transparency = opacity,
				})
			end

			previous = current
		end
	else
		for index = 0, Visuals.ringSegments do
			removeDrawing("ring" .. index)
		end
	end

	-- where the follow is taking the body
	if enabled and flag("follow_visualize", false) and Body.spot and not Util.inVoid(Body.spot) then
		local point, onScreen = camera:WorldToViewportPoint(Body.spot)
		local colour, opacity = pickerColor("follow_visualize_color", Color3.fromRGB(120, 200, 255))

		drawing("Circle", "followspot", {
			Visible = onScreen and point.Z > 0,
			Position = Vector2.new(point.X, point.Y),
			Radius = 6,
			Thickness = 2,
			NumSides = 24,
			Filled = false,
			Color = colour,
			Transparency = opacity,
		})
	else
		removeDrawing("followspot")
	end

	-- the camera on the target
	local humanoid = player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")

	if enabled and flag("view_target", false) and humanoid then
		camera.CameraSubject = humanoid
		Visuals.cameraSwapped = true
	elseif Visuals.cameraSwapped then
		Visuals.cameraSwapped = false

		local own = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")

		if own then
			camera.CameraSubject = own
		end
	end
end

---@module Shop
---Buying through the game's own shop parts. Every item is a part in Workspace.Ignored.Shop named like `5 [Rifle Ammo] - $281` with a Head and a
---ClickDetector; a purchase stands the body at the part and clicks until the cash drops. The cheapest of the many copies of an item is used.
---Purchases go one at a time. A refused one is not asked again at once (the wait doubles from 0.5 s up to 8 s), and a purchase can be held back while
---other players stand near the shop. The auto buys (armor, ammo, heal, mask, loadout) only ask this module for items; none of them moves the body.
local Shop = {
	items = {},
	names = {},
	queue = {},
	current = nil,
	bought = 0,
	failures = {},
	blockedUntil = {},
	heldTool = nil,
	autoAt = 0,
	healAt = 0,
	popcorn = nil,
}

local MAX_BACKOFF = 8

local function dataFolder()
	return localPlayer:FindFirstChild("DataFolder")
end

---Cash on hand.
function Shop.cash()
	local folder = dataFolder()
	local currency = folder and folder:FindFirstChild("Currency")

	return currency and currency.Value or 0
end

---Reads the shop parts once; the cheapest copy of each item is kept.
function Shop.scan()
	table.clear(Shop.items)
	table.clear(Shop.names)

	local ignored = workspace:FindFirstChild("Ignored")
	local folder = ignored and ignored:FindFirstChild("Shop")

	if not folder then
		return 0
	end

	for _, part in folder:GetChildren() do
		local packs, name, price = part.Name:lower():match("^(%d*)%s*%[(.-)%]%s*[%-%=]%s*%$(%d+)")
		price = tonumber(price)

		if name and price and price > 0 then
			local head = part:FindFirstChild("Head")
			local detector = part:FindFirstChildOfClass("ClickDetector")

			if head and detector then
				local known = Shop.items[name]

				if not known or price < known.price then
					Shop.items[name] = { name = name, price = price, head = head, detector = detector, packSize = tonumber(packs) }
				end
			end
		end
	end

	for name in Shop.items do
		Shop.names[#Shop.names + 1] = name
	end

	table.sort(Shop.names)

	return #Shop.names
end

local function notify(text)
	if flag("shop_notify", true) and notifications then
		notifications:create_notification({ name = text })
	end
end

---Ask for an item. `packs` is how many times to click (ammo packs); returns false when the item is unknown, already waiting or backing off.
---@param name string lower case item name, e.g. "rifle ammo" or "high-medium armor"
---@param packs number?
function Shop.request(name, packs)
	local item = Shop.items[name]

	if not item or (packs and packs <= 0) then
		return false
	end

	if Shop.current and Shop.current.item == item then
		return false
	end

	for _, queued in Shop.queue do
		if queued.item == item then
			return false
		end
	end

	if os.clock() < (Shop.blockedUntil[name] or 0) then
		return false
	end

	Shop.queue[#Shop.queue + 1] = { item = item, packs = packs or 1 }

	return true
end

---True while a purchase is running (other modules leave the body alone then).
function Shop.busy()
	return Shop.current ~= nil
end

---Whether another player stands near the shop part, for Safe Purchasing.
local function shopWatched(position)
	local radius = flag("shop_safe_distance", 50)
	local mode = flag("shop_safe_avoid", "target")

	for _, player in playersService:GetPlayers() do
		if player ~= localPlayer and (mode == "anyone" or player == Target.player) and not Players.knocked(player) then
			local root = Players.root(player)

			if root and (root.Position - position).Magnitude < radius then
				return true
			end
		end
	end

	return false
end

local function finish(success)
	local current = Shop.current

	Shop.current = nil

	if not current then
		return
	end

	local name = current.item.name

	if success then
		Shop.failures[name] = nil
		-- a short breather: the item takes a moment to show up in the bag, and asking again at once bought a second mask in testing
		Shop.blockedUntil[name] = os.clock() + 1.5
		notify("bought " .. name)
	else
		local failures = (Shop.failures[name] or 0) + 1

		Shop.failures[name] = failures
		Shop.blockedUntil[name] = os.clock() + math.min(0.5 * 2 ^ (failures - 1), MAX_BACKOFF)
		notify("could not buy " .. name)
	end

	-- back to where the character was
	local root = Players.root(localPlayer)
	local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")

	if root and humanoid and humanoid.Health > 0 and current.origin then
		root.CFrame = current.origin
		root.AssemblyLinearVelocity = Vector3.zero
	end

	-- the gun that was in hand goes back
	local held = Shop.heldTool
	Shop.heldTool = nil

	if held and held.Parent == localPlayer:FindFirstChild("Backpack") and humanoid then
		humanoid:EquipTool(held)
	end
end

---Where the body stands for a purchase: beside the part, a few studs out (measured: a click from 8.8 studs below it was refused, one from 3 studs
---beside it was sold; the detector reaches 9).
local function shopSpot(item)
	return CFrame.new(item.head.Position + Vector3.new(0, 0, 3))
end

---Runs after the body has moved, so the click happens with the body at the shop.
function Shop.step(now)
	local current = Shop.current

	if not current then
		local nextRequest = table.remove(Shop.queue, 1)
		local character = localPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		if not nextRequest or not humanoid or humanoid.Health <= 0 or Players.knocked(localPlayer) then
			return
		end

		-- a pack of ammo is refused while a reload runs: ask again later
		local effects = character:FindFirstChild("BodyEffects")
		local reload = effects and effects:FindFirstChild("Reload")

		if nextRequest.item.name:find("ammo") and reload and reload.Value == true then
			return
		end

		if flag("shop_safe", false) and shopWatched(nextRequest.item.head.Position) then
			Shop.blockedUntil[nextRequest.item.name] = now + 1
			notify("held " .. nextRequest.item.name .. " (safe purchasing)")

			return
		end

		local held = character:FindFirstChildOfClass("Tool")

		if held and not nextRequest.item.name:find("armor") then
			Shop.heldTool = held
			humanoid:UnequipTools()
		end

		local root = Players.root(localPlayer)

		if not root then
			return
		end

		Shop.current = {
			item = nextRequest.item,
			packs = nextRequest.packs,
			startedAt = now,
			startBought = Shop.bought,
			origin = root.CFrame,
		}

		return
	end

	-- The character is held at the shop for the whole purchase, not just for a frame: the server only sells to a player it has standing there, and
	-- a spot that is put back before every frame never reached it.
	local root = Players.root(localPlayer)

	if root then
		root.CFrame = shopSpot(current.item)
		root.AssemblyLinearVelocity = Vector3.zero
	end

	local done = Shop.bought - current.startBought
	local timeout = Util.ping() * 2 + current.packs * 0.36 + 0.3

	if done >= current.packs then
		finish(true)
	elseif now - current.startedAt > timeout then
		finish(done > 0)
	else
		fireclickdetector(current.item.detector)
	end
end

---Counts every drop in the cash as one purchase.
function Shop.watchCash(maid)
	local folder = dataFolder()
	local currency = folder and folder:FindFirstChild("Currency")

	if not currency then
		return
	end

	local last = currency.Value

	maid:give(currency:GetPropertyChangedSignal("Value"):Connect(function()
		if currency.Value < last then
			Shop.bought += 1
		end

		last = currency.Value
	end))
end

---@param name string
local function ownsTool(name)
	local character = localPlayer.Character
	local backpack = localPlayer:FindFirstChild("Backpack")

	for _, container in { character, backpack } do
		if container then
			for _, tool in container:GetChildren() do
				if tool:IsA("Tool") and tool.Name:lower() == "[" .. name .. "]" then
					return tool
				end
			end
		end
	end

	return nil
end

local function armorValue()
	local character = localPlayer.Character
	local effects = character and character:FindFirstChild("BodyEffects")
	local armor = effects and effects:FindFirstChild("Armor")

	return armor and armor.Value or nil
end

local function heal(now, humanoid, spare)
	local fraction = flag("shop_heal_below", 50) / 100

	if humanoid.Health / humanoid.MaxHealth >= fraction then
		-- healed: the food goes back in the bag
		if Shop.popcorn and Shop.popcorn.Parent == localPlayer.Character then
			Shop.popcorn.Parent = localPlayer:FindFirstChild("Backpack")
		end

		Shop.popcorn = nil

		return
	end

	local food = ownsTool("popcorn")

	if not food then
		if spare then
			Shop.request("popcorn")
		end

		return
	end

	Shop.popcorn = food

	if food.Parent ~= localPlayer.Character then
		humanoid:EquipTool(food)

		return
	end

	if now - Shop.healAt >= flag("shop_heal_cooldown", 0.3) then
		Shop.healAt = now
		food:Activate()
	end
end

---The auto buys, checked four times a second.
function Shop.auto(now)
	if now - Shop.autoAt < 0.25 or Shop.current then
		return
	end

	Shop.autoAt = now

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if not humanoid or humanoid.Health <= 0 or Players.knocked(localPlayer) then
		return
	end

	local spare = Shop.cash() > flag("shop_keep_cash", 5000)

	if flag("shop_armor", false) then
		local armor = armorValue()

		if armor and armor < flag("shop_armor_below", 52) and spare then
			Shop.request("high-medium armor")
		end
	end

	if flag("shop_ammo", false) and #Shop.queue == 0 then
		local folder = dataFolder()
		local inventory = folder and folder:FindFirstChild("Inventory")

		for _, info in allGuns() do
			local record = inventory and inventory:FindFirstChild(info.tool.Name)
			local maxAmmo = info.tool:FindFirstChild("MaxAmmo")

			if record and maxAmmo and maxAmmo.Value > 0 then
				local clips = math.floor((tonumber(record.Value) or 0) / maxAmmo.Value)

				if clips < flag("shop_ammo_clips", 2) + 1 and spare then
					Shop.request(info.tool.Name:sub(2, -2):lower() .. " ammo", flag("shop_ammo_packs", 1))
				end
			end
		end
	end

	if flag("shop_heal", false) then
		heal(now, humanoid, spare)
	end

	if flag("shop_mask", false) and not character:FindFirstChild("In-gameMask") then
		local mask = ownsTool("mask")

		if mask then
			if mask.Parent ~= character then
				humanoid:EquipTool(mask)
			else
				mask:Activate()
			end
		elseif spare then
			Shop.request("ninja mask")
		end
	end

	if flag("shop_loadout", false) then
		local wanted = flag("shop_loadout_guns", { "rifle" })

		for _, gun in type(wanted) == "table" and wanted or { wanted } do
			local tool = ownsTool(gun)

			if not tool then
				Shop.request(gun)
			else
				-- the gun is owned: top it up when the reserve is below one magazine
				local folder = dataFolder()
				local inventory = folder and folder:FindFirstChild("Inventory")
				local record = inventory and inventory:FindFirstChild(tool.Name)
				local maxAmmo = tool:FindFirstChild("MaxAmmo")

				if record and maxAmmo and (tonumber(record.Value) or 0) < maxAmmo.Value then
					Shop.request(gun .. " ammo", flag("shop_loadout_packs", 5))
				end
			end
		end
	end
end

---@module AntiStomp
---While the character is knocked it is kept out of reach, so there is nothing for anyone to stomp. (Visions-hook also kills the character on purpose;
---this does not: the character just stands in the void until it gets up or dies.)
local AntiStomp = { spot = nil }

function AntiStomp.want()
	if not flag("antistomp_enabled", false) or not Players.knocked(localPlayer) then
		AntiStomp.spot = nil

		return nil
	end

	AntiStomp.spot = AntiStomp.spot or CFrame.new(math.random(-1e8, 1e8), 5e7, math.random(-1e8, 1e8))

	return AntiStomp.spot
end

---@module QuickDraw
---Holding a knife or nothing: takes out the gun that reaches the target when it comes in range, and puts the knife back after.
local QuickDraw = { back = nil, drawn = nil, lastSeen = 0, lastEquip = 0 }

function QuickDraw.step(now)
	if not flag("quickdraw_enabled", false) then
		QuickDraw.back, QuickDraw.drawn = nil, nil

		return
	end

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local aim = Follow.aim

	if not humanoid or humanoid.Health <= 0 or not character then
		return
	end

	local held = character:FindFirstChildOfClass("Tool")
	local heldIsGun = held and held:FindFirstChild("Ammo") ~= nil
	local myPosition = Body.spot or (Players.root(localPlayer) and Players.root(localPlayer).Position)

	if aim and myPosition and not Util.inVoid(aim) and not heldIsGun and now - QuickDraw.lastEquip > 0.2 then
		local best, bestRange = nil, math.huge

		for _, info in allGuns() do
			if info.ammo > 0 and picked("quickdraw_guns", info.tool.Name:sub(2, -2):lower(), { "rifle", "double-barrel sg", "flintlock", "revolver" })
				and (aim - myPosition).Magnitude <= info.range and info.range < bestRange then
				best, bestRange = info.tool, info.range
			end
		end

		if best then
			QuickDraw.back = held
			QuickDraw.drawn = best
			QuickDraw.lastSeen = now
			QuickDraw.lastEquip = now
			humanoid:EquipTool(best)
		end

		return
	end

	-- the target is out of every drawn gun's reach for a second: the knife (or empty hands) comes back
	if QuickDraw.drawn and heldIsGun then
		local info = gunInfo(held)

		if aim and myPosition and info and (aim - myPosition).Magnitude <= info.range then
			QuickDraw.lastSeen = now
		elseif now - QuickDraw.lastSeen > 1 then
			local back = QuickDraw.back

			QuickDraw.drawn, QuickDraw.back = nil, nil
			QuickDraw.lastEquip = now

			if back and back.Parent == localPlayer:FindFirstChild("Backpack") then
				humanoid:EquipTool(back)
			else
				humanoid:UnequipTools()
			end
		end
	end
end

---@module AdStrafe
---Taps A and D in turn while there is a target, so the character sidesteps like a player would.
local AdStrafe = { held = nil, switchedAt = 0 }

local virtualInput = nil

local function sendKey(down, key)
	if not virtualInput then
		local ok, service = pcall(game.GetService, game, "VirtualInputManager")

		virtualInput = ok and service or false
	end

	if virtualInput then
		pcall(virtualInput.SendKeyEvent, virtualInput, down, key, false, game)
	end
end

function AdStrafe.release()
	if AdStrafe.held then
		sendKey(false, AdStrafe.held)
		AdStrafe.held = nil
	end
end

function AdStrafe.step(now)
	local active = flag("adstrafe_enabled", false) and Target.player ~= nil and not Players.knocked(localPlayer)
		and userInputService:GetFocusedTextBox() == nil

	if not active then
		AdStrafe.release()

		return
	end

	if AdStrafe.held == nil or now - AdStrafe.switchedAt >= flag("adstrafe_interval", 0.22) then
		local nextKey = AdStrafe.held == Enum.KeyCode.A and Enum.KeyCode.D or Enum.KeyCode.A

		AdStrafe.release()
		AdStrafe.held = nextKey
		AdStrafe.switchedAt = now
		sendKey(true, nextKey)
	end
end

---@module FullAuto
---Hold the left mouse button to keep shooting the gun in your hands. Speed is a share of the gun's own fire rate; it never goes past the gun's cooldown,
---which the server enforces.
local FullAuto = { lastShot = 0 }

function FullAuto.step(now)
	if not flag("fullauto_enabled", false) or not userInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) or userInputService:GetFocusedTextBox() then
		return
	end

	local character = localPlayer.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	local info = tool and gunInfo(tool)

	if not info or info.ammo <= 0 then
		return
	end

	local share = math.clamp(flag("fullauto_speed", 100), 1, 100) / 100
	local interval = (info.cooldown + 0.015) / share

	if now - FullAuto.lastShot >= interval then
		FullAuto.lastShot = now
		tool:Activate()
	end
end

---@module Bounty
---Da Hood shows the one bounty there is on every poster in Workspace.MAP.BountyPosters (Texts.PlayerName, a SurfaceGui TextLabel; blank while nobody has one).
---Anti Bounty: your name on the posters, and you leave the server. Auto Bounty: whoever is on the posters becomes the target, and the features needed to
---hunt them are switched on; once nobody here has the bounty, what it switched on goes back off.
local Bounty = { turnedOn = {}, hunted = nil, left = false, checkedAt = 0 }

local BOUNTY_FLAGS = { "ragebot_enabled", "follow_enabled", "autofire_enabled", "autostomp_enabled", "autofire_reload" }

local function setFlag(name, value)
	local setter = library and library.config_flags[name]

	if setter then
		setter(value)
	end
end

---The player named on the first poster that has a name.
local function bountyPlayer()
	local map = workspace:FindFirstChild("MAP")
	local posters = map and map:FindFirstChild("BountyPosters")

	for _, poster in posters and posters:GetChildren() or {} do
		local texts = poster:FindFirstChild("Texts")
		local holder = texts and texts:FindFirstChild("PlayerName")
		local gui = holder and holder:FindFirstChildOfClass("SurfaceGui")
		local label = gui and gui:FindFirstChildOfClass("TextLabel")
		local name = label and label.Text

		if name and name ~= "" then
			return playersService:FindFirstChild(name), name
		end
	end

	return nil, nil
end

Bounty.read = bountyPlayer

function Bounty.release()
	for name in Bounty.turnedOn do
		setFlag(name, false)
	end

	Bounty.turnedOn = {}

	if Bounty.hunted and Target.player == Bounty.hunted then
		Target.clear()
	end

	Bounty.hunted = nil
end

function Bounty.step(now)
	if now - Bounty.checkedAt < 0.5 then
		return
	end

	Bounty.checkedAt = now

	local player, name = bountyPlayer()

	if flag("antibounty_enabled", false) and player == localPlayer and not Bounty.left then
		Bounty.left = true

		if notifications then
			notifications:create_notification({ name = "anti bounty: a bounty is on you, leaving" })
		end

		pcall(localPlayer.Kick, localPlayer, "Anti Bounty: a bounty was put on you, so you left the server.")

		return
	end

	if not flag("autobounty_enabled", false) or not player or player == localPlayer then
		if next(Bounty.turnedOn) or Bounty.hunted then
			Bounty.release()
		end

		return
	end

	for _, flagName in BOUNTY_FLAGS do
		if flag(flagName, false) ~= true then
			setFlag(flagName, true)
			Bounty.turnedOn[flagName] = true
		end
	end

	if Bounty.hunted ~= player then
		Bounty.hunted = player

		if notifications then
			notifications:create_notification({ name = "auto bounty: going after " .. name })
		end
	end

	if Target.player ~= player then
		Target.set(player)
	end
end

---@module Esp
---Drawing-library player ESP: box, name, distance, tool, health bar and text, armor bar. Drawings exist only for players that are on screen and the feature
---is on; they are removed when it goes off, when the player leaves, and on unload.
local Esp = { players = {}, MAX_ARMOR = 130 }

local ESP_PARTS = { "box", "name", "distance", "tool", "healthBack", "healthBar", "healthText", "armorBack", "armorBar" }

local function espDrawing(entry, key, kind)
	local object = entry[key]

	if not object then
		object = Drawing.new(kind)
		entry[key] = object
	end

	return object
end

local function hideEntry(entry)
	for _, key in ESP_PARTS do
		if entry[key] then
			entry[key].Visible = false
		end
	end
end

local function destroyEntry(player)
	local entry = Esp.players[player]

	if not entry then
		return
	end

	for _, key in ESP_PARTS do
		if entry[key] then
			entry[key]:Remove()
		end
	end

	Esp.players[player] = nil
end

function Esp.clear()
	for player in Esp.players do
		destroyEntry(player)
	end
end

---Draws one player. Returns false when nothing could be drawn (no character, in the void, off screen).
---@param player Player
function Esp.draw(player)
	local entry = Esp.players[player]

	if not entry then
		entry = {}
		Esp.players[player] = entry
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local head = character and character:FindFirstChild("Head")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if not (root and head and humanoid) or Util.inVoid(root.Position) then
		hideEntry(entry)

		return false
	end

	local top = camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.7, 0))
	local bottom = camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))

	if top.Z <= 0 or bottom.Z <= 0 then
		hideEntry(entry)

		return false
	end

	local height = math.max(bottom.Y - top.Y, 4)
	local width = height * 0.55
	local left = top.X - width / 2
	local isTarget = player == Target.player
	local mainColour = pickerColor(isTarget and "esp_target_color" or "esp_color", isTarget and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(255, 255, 255))
	local font = Drawing.Fonts and Drawing.Fonts.UI or 0
	local textY = top.Y - 15

	if flag("esp_box", true) then
		local box = espDrawing(entry, "box", "Square")

		box.Visible = true
		box.Position = Vector2.new(left, top.Y)
		box.Size = Vector2.new(width, height)
		box.Color = mainColour
		box.Thickness = 1
		box.Filled = false
	elseif entry.box then
		entry.box.Visible = false
	end

	if flag("esp_name", true) then
		local label = espDrawing(entry, "name", "Text")

		label.Visible = true
		label.Text = flag("esp_display_name", true) and player.DisplayName or player.Name
		label.Position = Vector2.new(top.X, textY)
		label.Size = 13
		label.Center = true
		label.Outline = true
		label.Font = font
		label.Color = mainColour
	elseif entry.name then
		entry.name.Visible = false
	end

	local belowY = bottom.Y + 2

	if flag("esp_distance", false) then
		local mine = Players.root(localPlayer)
		local studs = mine and (mine.Position - root.Position).Magnitude or 0
		local label = espDrawing(entry, "distance", "Text")
		local metres = flag("esp_unit", "studs") == "metres"

		label.Visible = true
		label.Text = metres and string.format("%dm", studs * 0.28) or string.format("%d st", studs)
		label.Position = Vector2.new(top.X, belowY)
		label.Size = 12
		label.Center = true
		label.Outline = true
		label.Font = font
		label.Color = mainColour
		belowY += 13
	elseif entry.distance then
		entry.distance.Visible = false
	end

	if flag("esp_tool", false) then
		local tool = character:FindFirstChildOfClass("Tool")
		local label = espDrawing(entry, "tool", "Text")
		local text = tool and tool.Name or ""

		label.Visible = text ~= ""
		label.Text = flag("esp_tool_upper", false) and text:upper() or text
		label.Position = Vector2.new(top.X, belowY)
		label.Size = 12
		label.Center = true
		label.Outline = true
		label.Font = font
		label.Color = mainColour
	elseif entry.tool then
		entry.tool.Visible = false
	end

	local fraction = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)

	if flag("esp_health_bar", true) then
		local x = left - 4
		local back = espDrawing(entry, "healthBack", "Line")
		local bar = espDrawing(entry, "healthBar", "Line")

		back.Visible = true
		back.From, back.To = Vector2.new(x, top.Y + height), Vector2.new(x, top.Y)
		back.Thickness = 3
		back.Color = Color3.new(0, 0, 0)

		bar.Visible = fraction > 0
		bar.From, bar.To = Vector2.new(x, top.Y + height), Vector2.new(x, top.Y + height * (1 - fraction))
		bar.Thickness = 1
		bar.Color = Color3.fromRGB(255, 60, 60):Lerp(Color3.fromRGB(60, 255, 90), fraction)
	else
		if entry.healthBack then entry.healthBack.Visible = false end
		if entry.healthBar then entry.healthBar.Visible = false end
	end

	if flag("esp_health_text", false) and not (flag("esp_health_hide_full", true) and fraction >= 1) then
		local label = espDrawing(entry, "healthText", "Text")

		label.Visible = true
		label.Text = tostring(math.floor(humanoid.Health))
		label.Position = Vector2.new(left - 14, top.Y + height * (1 - fraction))
		label.Size = 11
		label.Center = true
		label.Outline = true
		label.Font = font
		label.Color = Color3.new(1, 1, 1)
	elseif entry.healthText then
		entry.healthText.Visible = false
	end

	local effects = character:FindFirstChild("BodyEffects")
	local armor = effects and effects:FindFirstChild("Armor")
	local armorValue = armor and armor.Value or 0

	if flag("esp_armor_bar", false) and not (flag("esp_armor_hide_none", true) and armorValue <= 0) then
		local x = left + width + 4
		local armorFraction = math.clamp(armorValue / Esp.MAX_ARMOR, 0, 1)
		local back = espDrawing(entry, "armorBack", "Line")
		local bar = espDrawing(entry, "armorBar", "Line")

		back.Visible = true
		back.From, back.To = Vector2.new(x, top.Y + height), Vector2.new(x, top.Y)
		back.Thickness = 3
		back.Color = Color3.new(0, 0, 0)

		bar.Visible = armorFraction > 0
		bar.From, bar.To = Vector2.new(x, top.Y + height), Vector2.new(x, top.Y + height * (1 - armorFraction))
		bar.Thickness = 1
		bar.Color = Color3.fromRGB(70, 140, 255)
	else
		if entry.armorBack then entry.armorBack.Visible = false end
		if entry.armorBar then entry.armorBar.Visible = false end
	end

	return true
end

function Esp.render()
	if not flag("esp_enabled", false) then
		if next(Esp.players) then
			Esp.clear()
		end

		return
	end

	for _, player in playersService:GetPlayers() do
		if player ~= localPlayer then
			if flag("esp_only_target", false) and player ~= Target.player then
				destroyEntry(player)
			else
				Esp.draw(player)
			end
		end
	end

	-- players that left
	for player in Esp.players do
		if player.Parent ~= playersService then
			destroyEntry(player)
		end
	end
end

---@module Legit
---The legit bot: aim assist (moves your view toward a target while a key is held), silent aim (answers the game's own gun script with a position near the
---target while you shoot) and the triggerbot (clicks when the crosshair is on a player). The three share one way to find a player, `Legit.best`,
---which reads its FOV, distance, hitbox and visibility settings from the prefix of the feature that asks ("aimassist" or "silent"); the ignore options
---are shared. None of them sends anything to the server except the shot your own gun script makes.
local Legit = { target = nil, targetSince = 0, silentRoll = true, silentWasDown = false }

local function legitPart(character, prefix)
	local hitbox = flag(prefix .. "_hitbox", "head")

	if hitbox == "head" then
		return character:FindFirstChild("Head")
	elseif hitbox == "chest" then
		return character:FindFirstChild("UpperTorso") or character:FindFirstChild("HumanoidRootPart")
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function visibleFrom(origin, part, character, prefix)
	if not flag(prefix .. "_visible", true) then
		return true
	end

	local params = RaycastParams.new()

	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { localPlayer.Character, character }

	return workspace:Raycast(origin, part.Position - origin, params) == nil
end

---Whether a player is one the legit features may use right now.
local function legitUsable(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if player == localPlayer or not humanoid or humanoid.Health <= 0 or Players.phase(player) == "respawning" then
		return false
	end

	if flag("legit_ignore_knocked", true) and Players.knocked(player) then
		return false
	end

	if flag("legit_ignore_protected", true) and Players.phase(player) == "protected" then
		return false
	end

	return true
end

---Is this player inside the feature's FOV circle, range and line of sight? Returns the part to aim at.
local function inReach(player, prefix, mouseLocation)
	local part = legitPart(player.Character, prefix)

	if not part or Util.inVoid(part.Position) or (part.Position - camera.CFrame.Position).Magnitude > flag(prefix .. "_distance", 500) then
		return nil
	end

	local screen, onScreen = camera:WorldToViewportPoint(part.Position)

	if not onScreen or (Vector2.new(screen.X, screen.Y) - mouseLocation).Magnitude > flag(prefix .. "_fov", 120) then
		return nil
	end

	if not visibleFrom(camera.CFrame.Position, part, player.Character, prefix) then
		return nil
	end

	return part, (Vector2.new(screen.X, screen.Y) - mouseLocation).Magnitude
end

---The usable player closest to the mouse inside the feature's FOV.
---@param prefix string "aimassist" or "silent"
function Legit.best(prefix)
	local mouseLocation = userInputService:GetMouseLocation()
	local best, bestPart, bestScore = nil, nil, math.huge

	for _, player in playersService:GetPlayers() do
		if legitUsable(player) then
			local part, distance = inReach(player, prefix, mouseLocation)

			if part and distance < bestScore then
				best, bestPart, bestScore = player, part, distance
			end
		end
	end

	return best, bestPart
end

---Keeps the current player for `Target swap cooldown` seconds before a better one is taken (the aim does not jump between players).
local function stickyBest(prefix, now)
	local current = Legit.target

	if current and current.Parent == playersService and legitUsable(current) and now - Legit.targetSince < flag("legit_swap_cooldown", 0) then
		local part = inReach(current, prefix, userInputService:GetMouseLocation())

		if part then
			return current, part
		end
	end

	local player, part = Legit.best(prefix)

	if player ~= Legit.target then
		Legit.target, Legit.targetSince = player, now
	end

	return player, part
end

---@module AimAssist
local AimAssist = {}

function AimAssist.step()
	local bind = flag("aimassist_key")

	if not flag("aimassist_enabled", false) or type(bind) ~= "table" or not bind.active or userInputService:GetFocusedTextBox() then
		return
	end

	local _, part = stickyBest("aimassist", os.clock())

	if not part then
		return
	end

	local horizontal = math.max(flag("aimassist_h_smooth", 6), 1)
	local vertical = math.max(flag("aimassist_v_smooth", 6), 1)

	if flag("aimassist_method", "camera") == "mouse" then
		local screen = camera:WorldToViewportPoint(part.Position)
		local delta = Vector2.new(screen.X, screen.Y) - userInputService:GetMouseLocation()

		mousemoverel(delta.X / horizontal, delta.Y / vertical)

		return
	end

	local cframe = camera.CFrame
	local wanted = (part.Position - cframe.Position).Unit
	local currentYaw = math.atan2(-cframe.LookVector.X, -cframe.LookVector.Z)
	local currentPitch = math.asin(cframe.LookVector.Y)
	local wantedYaw = math.atan2(-wanted.X, -wanted.Z)
	local wantedPitch = math.asin(wanted.Y)
	local yawDelta = (wantedYaw - currentYaw + math.pi) % (math.pi * 2) - math.pi
	local pitch = math.clamp(currentPitch + (wantedPitch - currentPitch) / vertical, -1.45, 1.45)

	camera.CFrame = CFrame.new(cframe.Position) * CFrame.fromOrientation(pitch, currentYaw + yawDelta / horizontal, 0)
end

---@module SilentAim
---While the left mouse button is held, the game's gun script is answered with a position on the best player inside the silent FOV, as long as that
---position is within Max Curve degrees of where the mouse is pointing. Redirect Chance is rolled once per press. The ragebot's own shots are left alone.
local SilentAim = {}

function SilentAim.step(now)
	if not flag("silent_enabled", false) then
		return
	end

	local down = userInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) and userInputService:GetFocusedTextBox() == nil

	if down and not Legit.silentWasDown then
		Legit.silentRoll = math.random() * 100 < flag("silent_chance", 100)
	end

	Legit.silentWasDown = down

	if not down or not Legit.silentRoll or (Aim.position and now < Aim.expires) then
		return
	end

	local _, part = Legit.best("silent")

	if not part then
		return
	end

	local mouseLocation = userInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	local toward = (part.Position - ray.Origin)
	local angle = math.deg(math.acos(math.clamp(ray.Direction:Dot(toward.Unit), -1, 1)))

	if angle > flag("silent_curve", 30) then
		return
	end

	local position = part.Position

	if flag("silent_flat", false) then
		-- Dont Curve Vertically: the height stays where the mouse is pointing, only the sideways part is moved
		local along = toward.Magnitude
		local ahead = ray.Origin + ray.Direction * along

		position = Vector3.new(position.X, ahead.Y, position.Z)
	end

	Aim.set(position, part, now, 0.1)
end

---@module Triggerbot
---Clicks (activates the gun in hand) when the mouse is over a usable player's chosen hitbox: it must stay over the same part for Hover Time, clicks are
---Cooldown apart and wait Delay (and are dropped if the mouse left by then), and the check itself runs every Refresh Rate seconds.
local Triggerbot = { checkedAt = 0, lastPart = nil, hoverSince = 0, lastClick = 0, pending = false }

local TORSO_PARTS = { UpperTorso = true, LowerTorso = true, HumanoidRootPart = true, Torso = true }
local ARM_PARTS = { LeftUpperArm = true, RightUpperArm = true, LeftLowerArm = true, RightLowerArm = true, LeftHand = true, RightHand = true, ["Left Arm"] = true, ["Right Arm"] = true }
local LEG_PARTS = { LeftUpperLeg = true, RightUpperLeg = true, LeftLowerLeg = true, RightLowerLeg = true, LeftFoot = true, RightFoot = true, ["Left Leg"] = true, ["Right Leg"] = true }

local function hitboxWanted(partName)
	if partName == "Head" then
		return picked("trigger_hitboxes", "head", { "head", "body" })
	elseif TORSO_PARTS[partName] then
		return picked("trigger_hitboxes", "body", { "head", "body" })
	elseif ARM_PARTS[partName] then
		return picked("trigger_hitboxes", "arms", { "head", "body" })
	elseif LEG_PARTS[partName] then
		return picked("trigger_hitboxes", "legs", { "head", "body" })
	end

	return false
end

function Triggerbot.step(now)
	if not flag("trigger_enabled", false) then
		Triggerbot.lastPart = nil

		return
	end

	if now - Triggerbot.checkedAt < flag("trigger_refresh", 0) then
		return
	end

	Triggerbot.checkedAt = now

	local character = localPlayer.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	local info = tool and gunInfo(tool)

	if not info or info.ammo <= 0 or userInputService:GetFocusedTextBox() then
		Triggerbot.lastPart = nil

		return
	end

	local mouseLocation = userInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	local maxDistance = flag("trigger_distance", 0)

	maxDistance = maxDistance == 0 and info.range or maxDistance

	local params = RaycastParams.new()

	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local result = workspace:Raycast(ray.Origin, ray.Direction * maxDistance, params)
	local part = result and result.Instance
	local model = part and part:FindFirstAncestorOfClass("Model")
	local player = model and playersService:GetPlayerFromCharacter(model)

	if not (part and player and legitUsable(player) and hitboxWanted(part.Name)) then
		Triggerbot.lastPart = nil

		return
	end

	if Triggerbot.lastPart ~= part then
		Triggerbot.hoverSince = now
	end

	Triggerbot.lastPart = part

	if Triggerbot.pending or now - Triggerbot.lastClick < flag("trigger_cooldown", 0) or now - Triggerbot.hoverSince < flag("trigger_hover", 0) then
		return
	end

	Triggerbot.pending = true

	task.delay(flag("trigger_delay", 0), function()
		Triggerbot.pending = false

		-- the mouse left the target while the click waited
		if Triggerbot.lastPart ~= part or not flag("trigger_enabled", false) then
			return
		end

		local current = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Tool")

		if current then
			Triggerbot.lastClick = os.clock()
			current:Activate()
		end
	end)
end

---@module Movement
---Your own character's movement: extra speed, flight, noclip, jump power, anti sit. It changes the character on your client; where the server does not
---agree, the server wins. Runs before the Body step, so the position Body saves as "real" already includes the movement.
local Movement = { flying = false, jumpDefault = nil, noclipParts = {}, jumpValue = nil, humanoid = nil, hooked = false, active = true }

---Da Hood's own script writes JumpPower back every frame (measured: 50, 120 and 50 again within one frame), so a plain write never lasts. While Jump Power is on,
---the writes the game makes to your humanoid's JumpPower are given the chosen value instead; nothing else is touched.
function Movement.installHook()
	if Movement.hooked then
		return
	end

	Movement.hooked = true

	local original
	original = hookmetamethod(game, "__newindex", newcclosure(function(self, key, value)
		if Movement.active and Movement.jumpValue and key == "JumpPower" and self == Movement.humanoid and not checkcaller() then
			return original(self, key, Movement.jumpValue)
		end

		return original(self, key, value)
	end))
end

local function movementParts()
	local character = localPlayer.Character

	return character, character and character:FindFirstChildOfClass("Humanoid"), character and character:FindFirstChild("HumanoidRootPart")
end

function Movement.step(dt)
	local character, humanoid, root = movementParts()

	if not (character and humanoid and root) or humanoid.Health <= 0 then
		return
	end

	local flightOn = flag("move_flight", false) and not Players.knocked(localPlayer)

	if flightOn and userInputService:GetFocusedTextBox() == nil then
		local look = camera.CFrame
		local direction = Vector3.zero

		if userInputService:IsKeyDown(Enum.KeyCode.W) then direction += look.LookVector end
		if userInputService:IsKeyDown(Enum.KeyCode.S) then direction -= look.LookVector end
		if userInputService:IsKeyDown(Enum.KeyCode.D) then direction += look.RightVector end
		if userInputService:IsKeyDown(Enum.KeyCode.A) then direction -= look.RightVector end
		if userInputService:IsKeyDown(Enum.KeyCode.Space) then direction += Vector3.yAxis end
		if userInputService:IsKeyDown(Enum.KeyCode.LeftControl) then direction -= Vector3.yAxis end

		root.AssemblyLinearVelocity = direction.Magnitude > 0 and direction.Unit * flag("move_flight_speed", 60) or Vector3.zero
		Movement.flying = true
	elseif Movement.flying then
		Movement.flying = false
		root.AssemblyLinearVelocity = Vector3.zero
	end

	-- extra speed: the character is moved along its walking direction on top of the normal walk
	if flag("move_speed", false) and not flightOn and humanoid.MoveDirection.Magnitude > 0 then
		root.CFrame += humanoid.MoveDirection * flag("move_speed_value", 20) * dt
	end

	Movement.humanoid = humanoid

	if flag("move_jump", false) then
		Movement.jumpDefault = Movement.jumpDefault or { humanoid.UseJumpPower, humanoid.JumpPower }
		Movement.jumpValue = flag("move_jump_power", 70)
		humanoid.UseJumpPower = true
		humanoid.JumpPower = Movement.jumpValue
	elseif Movement.jumpDefault then
		Movement.jumpValue = nil
		humanoid.UseJumpPower, humanoid.JumpPower = Movement.jumpDefault[1], Movement.jumpDefault[2]
		Movement.jumpDefault = nil
	end

	if flag("move_antisit", false) then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)

		if humanoid.Sit then
			humanoid.Sit = false
		end
	end
end

---Noclip is applied on the physics step, before the character collides.
function Movement.stepped()
	if not flag("move_noclip", false) then
		return
	end

	local character = localPlayer.Character

	if not character then
		return
	end

	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") and part.CanCollide then
			part.CanCollide = false
			Movement.noclipParts[part] = true
		end
	end
end

function Movement.restore()
	Movement.jumpValue = nil
	Movement.active = false

	for part in Movement.noclipParts do
		if part.Parent then
			part.CanCollide = true
		end
	end

	Movement.noclipParts = {}

	local _, humanoid, root = movementParts()

	if humanoid and Movement.jumpDefault then
		humanoid.UseJumpPower, humanoid.JumpPower = Movement.jumpDefault[1], Movement.jumpDefault[2]
	end

	if root and Movement.flying then
		root.AssemblyLinearVelocity = Vector3.zero
	end

	Movement.jumpDefault, Movement.flying = nil, false
end

---@module Utility
---Anti AFK (answers the idle kick the way a player moving would), rejoin (back into this same server), the watermark switch.
local Utility = {}

function Utility.antiAfk()
	local ok, service = pcall(game.GetService, game, "VirtualUser")

	if not ok then
		return
	end

	service:CaptureController()
	service:ClickButton2(Vector2.new())
end

function Utility.rejoin()
	local teleport = game:GetService("TeleportService")

	if #playersService:GetPlayers() <= 1 then
		teleport:Teleport(game.PlaceId, localPlayer)
	else
		teleport:TeleportToPlaceInstance(game.PlaceId, game.JobId, localPlayer)
	end
end

---@module Feedback
---What you see and hear when you shoot. The game's own shot call is watched (read only, passed straight on) to learn where each shot was sent from and to; a drop
---in another player's health shortly after, close to where the shot was sent, counts as the hit. Every effect is a short-lived object with a life time,
---updated by one RenderStepped step and removed when it expires, when its toggle goes off, and on unload.
local Feedback = {
	shots = {},
	effects = {},
	health = {},
	sounds = {},
	hooked = false,
	active = true,
	overlay = nil,
	lastShotAt = 0,
}

local SOUND_NAMES = { "neverlose", "primordial", "sparkle", "mc bow", "break", "skeet", "rust", "agpa1", "agpa2", "Beep1", "bubble", "copperbell", "cowbell", "huhh", "quake" }
local SOUND_URL = "https://raw.githubusercontent.com/haltorillshoot/Visions-hook/main/assets/neverlose%20recode/assets/"

local function guiParent()
	local ok, hidden = pcall(function()
		return gethui()
	end)

	return ok and hidden or game:GetService("CoreGui")
end

---Adds a timed effect. `step(age, life)` returns false when it is done early; `destroy()` frees what it made.
local function addEffect(life, step, destroy)
	Feedback.effects[#Feedback.effects + 1] = { born = os.clock(), life = life, step = step, destroy = destroy }
end

local function newLine()
	local line = Drawing.new("Line")

	line.Visible = true

	return line
end

local function colourFor(name, lethalName, lethal)
	local colour = pickerColor(lethal and lethalName or name, lethal and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(255, 255, 255))

	return colour
end

---Frees every effect (unload, or a toggle going off clears only its own kind through `kind`).
function Feedback.clear()
	for _, effect in Feedback.effects do
		effect.destroy()
	end

	table.clear(Feedback.effects)

	if Feedback.overlay then
		Feedback.overlay.Parent:Destroy()
		Feedback.overlay = nil
	end
end

function Feedback.render()
	local now = os.clock()
	local index = 1

	while index <= #Feedback.effects do
		local effect = Feedback.effects[index]
		local age = now - effect.born

		if age >= effect.life or effect.step(age, effect.life) == false then
			effect.destroy()
			table.remove(Feedback.effects, index)
		else
			index += 1
		end
	end
end

-- Individual effects ------------------------------------------------------------------------------------------------------------------------

local function marker2d(lethal)
	local colour = colourFor("fb_marker2d_color", "fb_marker2d_lethal", lethal)
	local thickness = flag("fb_marker2d_thickness", 2)
	local lines = { newLine(), newLine(), newLine(), newLine() }
	local signs = { Vector2.new(1, 1), Vector2.new(-1, 1), Vector2.new(1, -1), Vector2.new(-1, -1) }

	addEffect(flag("fb_marker2d_life", 0.4), function(age, life)
		local centre = camera.ViewportSize / 2
		local spread = 3 + age / life * 4

		for index, line in lines do
			line.From = centre + signs[index] * spread
			line.To = centre + signs[index] * (spread + 6)
			line.Thickness = thickness
			line.Color = colour
			line.Transparency = 1 - age / life
		end
	end, function()
		for _, line in lines do
			line:Remove()
		end
	end)
end

local function marker3d(position, lethal)
	local colour = colourFor("fb_marker3d_color", "fb_marker3d_lethal", lethal)
	local thickness = flag("fb_marker3d_thickness", 2)
	local lines = { newLine(), newLine(), newLine(), newLine() }
	local signs = { Vector2.new(1, 1), Vector2.new(-1, 1), Vector2.new(1, -1), Vector2.new(-1, -1) }

	addEffect(flag("fb_marker3d_life", 0.6), function(age, life)
		local point, onScreen = camera:WorldToViewportPoint(position)
		local centre = Vector2.new(point.X, point.Y)
		local visible = onScreen and point.Z > 0

		for index, line in lines do
			line.Visible = visible
			line.From = centre + signs[index] * 3
			line.To = centre + signs[index] * 10
			line.Thickness = thickness
			line.Color = colour
			line.Transparency = 1 - age / life
		end
	end, function()
		for _, line in lines do
			line:Remove()
		end
	end)
end

local function damageNumber(position, damage, lethal)
	local text = Drawing.new("Text")

	text.Visible = true
	text.Text = tostring(math.floor(damage + 0.5))
	text.Size = flag("fb_damage_size", 18)
	text.Center = true
	text.Outline = true
	text.Font = Drawing.Fonts and Drawing.Fonts.UI or 0
	text.Color = colourFor("fb_damage_color", "fb_damage_lethal", lethal)

	addEffect(flag("fb_damage_life", 1), function(age, life)
		local point, onScreen = camera:WorldToViewportPoint(position + Vector3.new(0, 1.5 + age * 3, 0))

		text.Visible = onScreen and point.Z > 0
		text.Position = Vector2.new(point.X, point.Y)
		text.Transparency = 1 - age / life
	end, function()
		text:Remove()
	end)
end

local function hitOverlay(lethal)
	if not Feedback.overlay then
		local gui = Instance.new("ScreenGui")

		gui.Name = ""
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 10
		gui.Parent = guiParent()

		local frame = Instance.new("Frame")

		frame.Size = UDim2.fromScale(1, 1)
		frame.BorderSizePixel = 0
		frame.BackgroundTransparency = 1
		frame.Parent = gui
		Feedback.overlay = frame
	end

	local frame = Feedback.overlay
	local colour = colourFor("fb_overlay_color", "fb_overlay_lethal", lethal)

	frame.BackgroundColor3 = colour

	addEffect(flag("fb_overlay_life", 0.35), function(age, life)
		frame.BackgroundTransparency = 0.65 + 0.35 * (age / life)
	end, function()
		frame.BackgroundTransparency = 1
	end)
end

local function hitChams(character, lethal)
	if not character then
		return
	end

	if flag("fb_chams_last_only", true) then
		for _, effect in Feedback.effects do
			if effect.kind == "chams" then
				effect.born = -math.huge
			end
		end
	end

	local highlight = Instance.new("Highlight")

	highlight.Adornee = character
	highlight.FillColor = colourFor("fb_chams_color", "fb_chams_lethal", lethal)
	highlight.OutlineColor = highlight.FillColor
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = guiParent()

	addEffect(flag("fb_chams_life", 0.5), function(age, life)
		highlight.FillTransparency = 0.3 + 0.7 * (age / life)
		highlight.OutlineTransparency = age / life
	end, function()
		highlight:Destroy()
	end)

	Feedback.effects[#Feedback.effects].kind = "chams"
end

local function hitParticles(position, lethal)
	local anchor = Instance.new("Part")

	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	anchor.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")

	emitter.Enabled = false
	emitter.Color = ColorSequence.new(colourFor("fb_particle_color", "fb_particle_lethal", lethal))
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(8, 16)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.4, 0)
	emitter.LightEmission = 1
	emitter.Parent = anchor
	emitter:Emit(flag("fb_particle_count", 20))

	addEffect(1.2, function() end, function()
		anchor:Destroy()
	end)
end

local function hitSkeleton(character)
	if not character then
		return
	end

	local colour = pickerColor("fb_skeleton_color", Color3.fromRGB(255, 255, 255))
	local thickness = flag("fb_skeleton_thickness", 1)
	local joints = {}

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant.Part0 and descendant.Part1 then
			joints[#joints + 1] = { descendant.Part0, descendant.Part1, newLine() }
		end
	end

	addEffect(flag("fb_skeleton_life", 0.6), function(age, life)
		for _, joint in joints do
			local from, fromOn = camera:WorldToViewportPoint(joint[1].Position)
			local to, toOn = camera:WorldToViewportPoint(joint[2].Position)
			local line = joint[3]

			line.Visible = fromOn and toOn and from.Z > 0 and to.Z > 0
			line.From, line.To = Vector2.new(from.X, from.Y), Vector2.new(to.X, to.Y)
			line.Thickness = thickness
			line.Color = colour
			line.Transparency = 1 - age / life
		end
	end, function()
		for _, joint in joints do
			joint[3]:Remove()
		end
	end)
end

local function bulletTracer(origin, hit)
	local colour = pickerColor("fb_tracer_color", Color3.fromRGB(255, 255, 255))
	local line = newLine()

	addEffect(flag("fb_tracer_life", 0.5), function(age, life)
		local from, fromOn = camera:WorldToViewportPoint(origin)
		local to, toOn = camera:WorldToViewportPoint(hit)

		line.Visible = (fromOn or toOn) and (from.Z > 0 or to.Z > 0)
		line.From, line.To = Vector2.new(from.X, from.Y), Vector2.new(to.X, to.Y)
		line.Thickness = flag("fb_tracer_thickness", 1)
		line.Color = colour
		line.Transparency = 1 - age / life
	end, function()
		line:Remove()
	end)
end

local function bulletImpact(hit)
	local ball = Instance.new("Part")

	ball.Shape = Enum.PartType.Ball
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.Material = Enum.Material.Neon
	ball.Color = pickerColor("fb_impact_color", Color3.fromRGB(255, 200, 80))
	ball.Size = Vector3.one * 0.8
	ball.Position = hit
	ball.Parent = workspace

	addEffect(flag("fb_impact_life", 0.8), function(age, life)
		ball.Transparency = age / life
	end, function()
		ball:Destroy()
	end)
end

-- Hit sound ----------------------------------------------------------------------------------------------------------------------------------

---Downloads the chosen sound from the repository once (kept in the workspace folder `Vanta/sounds`) and returns an asset id for it.
---@param name string
function Feedback.soundId(name)
	if Feedback.sounds[name] then
		return Feedback.sounds[name]
	end

	local ok, id = pcall(function()
		if not isfolder("Vanta") then
			makefolder("Vanta")
		end

		if not isfolder("Vanta/sounds") then
			makefolder("Vanta/sounds")
		end

		local path = "Vanta/sounds/" .. name .. ".ogg"

		if not isfile(path) then
			writefile(path, game:HttpGet(SOUND_URL .. name:gsub(" ", "%%20") .. ".ogg"))
		end

		return getcustomasset(path)
	end)

	if ok and id then
		Feedback.sounds[name] = id

		return id
	end

	return nil
end

local function hitSound()
	local id = Feedback.soundId(flag("fb_sound_name", "neverlose"))

	if not id then
		return
	end

	local sound = Instance.new("Sound")

	sound.SoundId = id
	sound.Volume = flag("fb_sound_volume", 1)
	sound.Parent = game:GetService("SoundService")
	sound:Play()
	game:GetService("Debris"):AddItem(sound, 5)
end

-- Events -------------------------------------------------------------------------------------------------------------------------------------

---A confirmed hit: runs every effect that is on.
---@param position Vector3 where the shot was sent to
---@param character Model? the player hit
---@param damage number
---@param lethal boolean
function Feedback.hit(position, character, damage, lethal)
	if flag("fb_marker2d", false) then marker2d(lethal) end
	if flag("fb_marker3d", false) then marker3d(position, lethal) end
	if flag("fb_damage", false) then damageNumber(position, damage, lethal) end
	if flag("fb_overlay", false) then hitOverlay(lethal) end
	if flag("fb_chams", false) then hitChams(character, lethal) end
	if flag("fb_particle", false) then hitParticles(position, lethal) end
	if flag("fb_skeleton", false) then hitSkeleton(character) end
	if flag("fb_sound", false) then hitSound() end

	if flag("fb_notify_hits", false) and notifications then
		notifications:create_notification({ name = string.format("hit %s for %d", character and character.Name or "?", damage) })
	end
end

---A shot sent to the server. Pellets of one shotgun shot arrive together and count as one.
function Feedback.shot(tool, origin, hit)
	local now = os.clock()
	local last = Feedback.shots[#Feedback.shots]

	if last and last.tool == tool and now - last.at < 0.05 then
		return
	end

	local entry = { at = now, tool = tool, origin = origin, hit = hit, confirmed = false }

	Feedback.shots[#Feedback.shots + 1] = entry

	if #Feedback.shots > 8 then
		table.remove(Feedback.shots, 1)
	end

	if flag("fb_tracer", false) then bulletTracer(origin, hit) end
	if flag("fb_impact", false) then bulletImpact(hit) end

	if flag("fb_notify_miss", false) and notifications then
		task.delay(0.4 + Util.ping(), function()
			if not entry.confirmed then
				notifications:create_notification({ name = "shot: no hit" })
			end
		end)
	end
end

---Which recent shot does a health drop at `position` belong to?
local function matchShot(position)
	local now = os.clock()

	for index = #Feedback.shots, 1, -1 do
		local entry = Feedback.shots[index]

		if now - entry.at > 0.6 + Util.ping() then
			break
		end

		if not entry.confirmed and (entry.hit - position).Magnitude < 30 then
			return entry
		end
	end

	return nil
end

local function watchPlayer(player, maid)
	local function watchCharacter(character)
		local humanoid = character:WaitForChild("Humanoid", 5)

		if not humanoid then
			return
		end

		Feedback.health[humanoid] = humanoid.Health

		maid:give(humanoid.HealthChanged:Connect(function(health)
			local before = Feedback.health[humanoid] or health

			Feedback.health[humanoid] = health

			if before - health < 0.5 then
				return
			end

			local root = character:FindFirstChild("HumanoidRootPart")
			local entry = root and matchShot(root.Position)

			if entry then
				entry.confirmed = true
				Feedback.hit(entry.hit, character, before - health, health <= 5 or Players.knocked(player))
			end
		end))
	end

	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end

	maid:give(player.CharacterAdded:Connect(watchCharacter))
end

---Starts watching: other players' health, and the game's shot call.
---@param maid table
function Feedback.start(maid)
	for _, player in playersService:GetPlayers() do
		if player ~= localPlayer then
			watchPlayer(player, maid)
		end
	end

	maid:give(playersService.PlayerAdded:Connect(function(player)
		watchPlayer(player, maid)
	end))

	if not Feedback.hooked then
		Feedback.hooked = true

		local original
		original = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
			if Feedback.active and getnamecallmethod() == "FireServer" and not checkcaller() then
				local kind, handle, origin, hit = ...

				if kind == "ShootGun" and typeof(origin) == "Vector3" and typeof(hit) == "Vector3" then
					pcall(Feedback.shot, typeof(handle) == "Instance" and handle.Parent or nil, origin, hit)
				end
			end

			return original(self, ...)
		end))
	end

	maid:give(function()
		Feedback.active = false
		Feedback.clear()
	end)
end

---@module Ragebot
---The driver: one Heartbeat step, one PreRender step, same order every frame.
local Ragebot = { maid = Maid.new() }

function Ragebot.start()
	Aim.install()
	Movement.installHook()

	Target.changed[#Target.changed + 1] = function(player)
		Resolver.reset()
		VoidSpam.reset()
		Follow.held = nil
		Follow.aim = nil

		if flag("notify_target", true) and notifications then
			notifications:create_notification({ name = player and ("target: " .. player.Name) or "target cleared" })
		end
	end

	Body.addProvider("antistomp", AntiStomp.want)
	Body.addProvider("autostomp", AutoStomp.want)
	Body.addProvider("voidspam", VoidSpam.want)
	Body.addProvider("follow", Follow.want)
	VoidSpam.gunReady = AutoFire.anyReady

	Shop.watchCash(Ragebot.maid)
	Ragebot.maid:give(AdStrafe.release)
	Ragebot.maid:give(Bounty.release)

	Ragebot.maid:give(runService.Heartbeat:Connect(function(dt)
		local now = os.clock()

		-- before the body step, so the position it saves as "real" already includes the movement
		Movement.step(dt)

		-- the features that need no target: the shop, the bounty watch and the held-trigger full auto
		Shop.auto(now)
		Bounty.step(now)
		FullAuto.step(now)

		if not flag("ragebot_enabled", false) then
			Follow.aim = nil
			AdStrafe.release()

			if not Shop.busy() then
				Body.apply(now)
			end

			Shop.step(now)

			return
		end

		Target.step(now)

		local root = Target.player and Players.root(Target.player)

		if root then
			Resolver.record(root.Position, now)

			local aim = Resolver.aim(now)

			Follow.aim = aim
		else
			Follow.aim = nil
		end

		-- the body goes first so the gun script reads the spot the server will have it at when the tool is activated
		-- a purchase holds the character at the shop; nothing else moves it until the purchase is done
		if not Shop.busy() then
			Body.apply(now)
		end

		Shop.step(now)

		if not Shop.busy() then
			AutoFire.step(now)
			QuickDraw.step(now)
		end

		AdStrafe.step(now)
	end))

	Ragebot.maid:give(runService.PreRender:Connect(Body.restore))
	Ragebot.maid:give(runService.RenderStepped:Connect(Visuals.render))
	Ragebot.maid:give(runService.RenderStepped:Connect(Esp.render))
	Ragebot.maid:give(runService.RenderStepped:Connect(Feedback.render))
	Feedback.start(Ragebot.maid)
	Ragebot.maid:give(runService.RenderStepped:Connect(AimAssist.step))
	Ragebot.maid:give(runService.RenderStepped:Connect(function()
		local now = os.clock()

		SilentAim.step(now)
		Triggerbot.step(now)
	end))
	Ragebot.maid:give(runService.Stepped:Connect(Movement.stepped))
	Ragebot.maid:give(Esp.clear)
	Ragebot.maid:give(Movement.restore)
	Ragebot.maid:give(localPlayer.Idled:Connect(function()
		if flag("utility_antiafk", false) then
			Utility.antiAfk()
		end
	end))
	Ragebot.maid:give(Visuals.clear)

	Ragebot.maid:give(userInputService.InputBegan:Connect(function(input, processed)
		local bind = library.flags["target_key"]

		if processed or not flag("ragebot_enabled", false) or type(bind) ~= "table" then
			return
		end

		if input.KeyCode == bind.key then
			Target.toggle()
		end
	end))

	Ragebot.maid:give(playersService.PlayerRemoving:Connect(function(player)
		if player == Target.player then
			Target.clear()
		end
	end))
end

function Ragebot.stop()
	Body.restore()
	Aim.active = false
	Aim.clear()
	Ragebot.maid:clean()
end

-- Menu: the Priv9 window and every control, wired to the flags the modules read.
local chunk = assert(loadstring(game:HttpGet(LIBRARY_URL)), "could not compile the Priv9 library")
library, notifications = chunk()

local window = library:window({ name = "vanta" })

notifications:create_notification({ name = "loading vanta..." })

local rage = window:tab({ name = "rage" })
local ragebotColumn = rage:column({})
local mainSection = ragebotColumn:section({ name = "ragebot" })
mainSection:toggle({ name = "enabled", flag = "ragebot_enabled" })
mainSection:keybind({ name = "target key", flag = "target_key", key = Enum.KeyCode.E, mode = "Hold" })
mainSection:toggle({ name = "automatic target", flag = "target_automatic" })
mainSection:toggle({ name = "notify target changes", flag = "notify_target", default = true })

local targetSection = ragebotColumn:section({ name = "target selection" })
targetSection:dropdown({ name = "priority", flag = "target_priority", items = { "closest to mouse", "closest to character", "lowest health", "random" }, default = "closest to mouse" })
targetSection:slider({ name = "fov", flag = "target_fov", min = 10, max = 1000, default = 180, interval = 1, suffix = "px" })
targetSection:slider({ name = "max distance", flag = "target_distance", min = 50, max = 3000, default = 1000, interval = 10, suffix = " st" })
targetSection:slider({ name = "automatic cooldown", flag = "target_cooldown", min = 0.05, max = 2, default = 0.25, interval = 0.05, suffix = "s" })
targetSection:dropdown({ name = "ignore if", flag = "target_ignore_if", items = { "in void", "protected", "knocked" }, default = { "in void", "protected", "knocked" }, multi = true })
targetSection:dropdown({ name = "untarget when", flag = "target_untarget_when", items = { "dead", "knocked", "flung" }, default = { "dead" }, multi = true })

local stompSection = ragebotColumn:section({ name = "auto stomp" })
stompSection:toggle({ name = "enabled", flag = "autostomp_enabled" })
stompSection:toggle({ name = "stop when target dead", flag = "autostomp_stop_dead", default = true })

local fireColumn = rage:column({})
local fireSection = fireColumn:section({ name = "auto fire" })
fireSection:toggle({ name = "enabled", flag = "autofire_enabled" })
fireSection:dropdown({ name = "hitboxes", flag = "autofire_hitbox", items = { "head", "body", "arms", "legs" }, default = { "head" }, multi = true })
fireSection:toggle({ name = "full auto (hold mouse)", flag = "fullauto_enabled" })
fireSection:slider({ name = "full auto speed", flag = "fullauto_speed", min = 1, max = 100, default = 100, interval = 1, suffix = "%" })
fireSection:toggle({ name = "quick draw", flag = "quickdraw_enabled" })
fireSection:dropdown({ name = "quick draw guns", flag = "quickdraw_guns", items = { "rifle", "double-barrel sg", "flintlock", "revolver", "tacticalshotgun", "shotgun", "smg", "glock" }, default = { "rifle", "double-barrel sg", "flintlock", "revolver" }, multi = true })
fireSection:toggle({ name = "a/d strafe", flag = "adstrafe_enabled" })
fireSection:slider({ name = "a/d interval", flag = "adstrafe_interval", min = 0.05, max = 1, default = 0.22, interval = 0.01, suffix = "s" })
fireSection:toggle({ name = "auto reload", flag = "autofire_reload", default = true })
fireSection:slider({ name = "gun gap", flag = "autofire_gap", min = 0, max = 300, default = 40, interval = 5, suffix = "ms" })

local resolverSection = fireColumn:section({ name = "resolver" })
resolverSection:dropdown({ name = "mode", flag = "resolver_mode", items = { "off", "cluster", "adaptive" }, default = "adaptive" })
resolverSection:slider({ name = "cluster radius", flag = "resolver_radius", min = 2, max = 60, default = 12, interval = 1, suffix = " st" })
resolverSection:slider({ name = "history window", flag = "resolver_window", min = 0.25, max = 3, default = 1.5, interval = 0.05, suffix = "s" })
resolverSection:slider({ name = "hold last spot", flag = "resolver_hold", min = 0, max = 4, default = 1.5, interval = 0.1, suffix = "s" })
resolverSection:slider({ name = "lead", flag = "resolver_lead", min = 0, max = 200, default = 100, interval = 5, suffix = "%" })

local move = window:tab({ name = "movement" })
local followColumn = move:column({})
local followSection = followColumn:section({ name = "follow target" })
followSection:toggle({ name = "enabled", flag = "follow_enabled" })
followSection:dropdown({ name = "style", flag = "follow_style", items = { "orbit", "random", "above", "strafe above", "teleport", "zigzag" }, default = "orbit" })
followSection:slider({ name = "distance", flag = "follow_distance", min = 2, max = 200, default = 15, interval = 1, suffix = " st" })
followSection:slider({ name = "height", flag = "follow_height", min = -100, max = 100, default = 0, interval = 1, suffix = " st" })
followSection:slider({ name = "orbit speed", flag = "follow_speed", min = 1, max = 100, default = 75, interval = 1, suffix = "%" })
followSection:slider({ name = "reposition every", flag = "follow_reposition", min = 0, max = 2, default = 0.05, interval = 0.01, suffix = "s" })
followSection:toggle({ name = "follow into void", flag = "follow_into_void", default = true })
followSection:dropdown({ name = "stop if", flag = "follow_stop_if", items = { "no gun equipped", "target knocked", "reloading" }, default = { "no gun equipped", "target knocked", "reloading" }, multi = true })
followSection:toggle({ name = "lead", flag = "follow_lead", default = true })
followSection:slider({ name = "lead time", flag = "follow_lead_time", min = 0, max = 300, default = 80, interval = 5, suffix = "ms" })
followSection:dropdown({ name = "orbit shape", flag = "follow_shape", items = { "circle", "square", "triangle", "pentagon", "hexagon", "decagon", "heart" }, default = "circle" })

local skySection = followColumn:section({ name = "above settings" })
skySection:slider({ name = "height min", flag = "follow_sky_min", min = 1, max = 100, default = 10, interval = 1, suffix = " st" })
skySection:slider({ name = "height max", flag = "follow_sky_max", min = 2, max = 200, default = 20, interval = 1, suffix = " st" })
skySection:slider({ name = "zig zag height", flag = "follow_zigzag_height", min = -50, max = 50, default = 3, interval = 1, suffix = " st" })
skySection:slider({ name = "zig zag speed", flag = "follow_zigzag_speed", min = 1, max = 100, default = 35, interval = 1, suffix = "x" })
skySection:slider({ name = "teleport min", flag = "follow_teleport_min", min = 1, max = 100, default = 2, interval = 1, suffix = " st" })
skySection:slider({ name = "teleport max", flag = "follow_teleport_max", min = 2, max = 200, default = 17, interval = 1, suffix = " st" })

local characterColumn = move:column({})
local characterSection = characterColumn:section({ name = "character" })
characterSection:toggle({ name = "speed", flag = "move_speed" })
characterSection:slider({ name = "speed value", flag = "move_speed_value", min = 1, max = 100, default = 20, interval = 1, suffix = " st/s" })
characterSection:toggle({ name = "flight", flag = "move_flight" })
characterSection:slider({ name = "flight speed", flag = "move_flight_speed", min = 10, max = 200, default = 60, interval = 1, suffix = " st/s" })
characterSection:toggle({ name = "noclip", flag = "move_noclip" })
characterSection:toggle({ name = "jump power", flag = "move_jump" })
characterSection:slider({ name = "jump power value", flag = "move_jump_power", min = 10, max = 300, default = 70, interval = 1, suffix = "" })
characterSection:toggle({ name = "anti sit", flag = "move_antisit" })

local voidColumn = move:column({})
local voidSection = voidColumn:section({ name = "void spam" })
voidSection:toggle({ name = "enabled", flag = "voidspam_enabled" })
voidSection:slider({ name = "void time", flag = "voidspam_void", min = 0.05, max = 1.5, default = 0.35, interval = 0.01, suffix = "s" })
voidSection:slider({ name = "window time", flag = "voidspam_window", min = 0.05, max = 0.6, default = 0.12, interval = 0.01, suffix = "s" })
voidSection:toggle({ name = "hide while waiting", flag = "voidspam_hide_waiting", default = true })
voidSection:dropdown({ name = "type", flag = "voidspam_type", items = { "random", "deep", "bait" }, default = "random" })
voidSection:slider({ name = "deep distance", flag = "voidspam_deep", min = 1, max = 1000, default = 100, interval = 1, suffix = "m st" })
voidSection:slider({ name = "offset", flag = "voidspam_offset", min = 0, max = 30, default = 3, interval = 1, suffix = " st" })

local baitSection = voidColumn:section({ name = "bait" })
baitSection:slider({ name = "bait distance", flag = "voidspam_bait_distance", min = 200, max = 2500, default = 250, interval = 10, suffix = " st" })
baitSection:slider({ name = "bait cooldown", flag = "voidspam_bait_cooldown", min = 0.01, max = 1.5, default = 0.5, interval = 0.01, suffix = "s" })
baitSection:slider({ name = "bait time", flag = "voidspam_bait_time", min = 0.01, max = 1, default = 0.03, interval = 0.01, suffix = "s" })
baitSection:toggle({ name = "bait freeze", flag = "voidspam_bait_freeze" })
baitSection:dropdown({ name = "bait spot", flag = "voidspam_bait_spot", items = { "random", "where you stood" }, default = "random" })

local visuals = window:tab({ name = "visuals" })
local visualsColumn = visuals:column({})
local fovSection = visualsColumn:section({ name = "fov circle" })
fovSection:toggle({ name = "show", flag = "fov_show" })
fovSection:colorpicker({ name = "colour", flag = "fov_color", color = Color3.fromRGB(255, 255, 255) })
fovSection:colorpicker({ name = "active colour", flag = "fov_active_color", color = Color3.fromRGB(255, 80, 80) })

local tracerSection = visualsColumn:section({ name = "tracer" })
tracerSection:toggle({ name = "show", flag = "tracer_show" })
tracerSection:colorpicker({ name = "colour", flag = "tracer_color", color = Color3.fromRGB(255, 255, 255) })
tracerSection:slider({ name = "thickness", flag = "tracer_thickness", min = 1, max = 5, default = 1, interval = 1, suffix = "px" })
tracerSection:dropdown({ name = "origin", flag = "tracer_origin", items = { "bottom", "center", "mouse" }, default = "bottom" })

local targetVisualColumn = visuals:column({})
local circleSection = targetVisualColumn:section({ name = "target circle" })
circleSection:toggle({ name = "show", flag = "circle_show" })
circleSection:colorpicker({ name = "colour", flag = "circle_color", color = Color3.fromRGB(180, 120, 255) })
circleSection:slider({ name = "radius", flag = "circle_radius", min = 1, max = 20, default = 4, interval = 0.5, suffix = " st" })

local cameraSection = targetVisualColumn:section({ name = "camera" })
cameraSection:toggle({ name = "view target", flag = "view_target" })

local followVisualSection = targetVisualColumn:section({ name = "follow spot" })
followVisualSection:toggle({ name = "visualize", flag = "follow_visualize" })
followVisualSection:colorpicker({ name = "colour", flag = "follow_visualize_color", color = Color3.fromRGB(120, 200, 255) })

-- the shop parts are read before the menu is built so the manual purchase list can name them
Shop.scan()

local shopTab = window:tab({ name = "shop" })
local shopColumn = shopTab:column({})
local purchaseSection = shopColumn:section({ name = "purchasing" })
purchaseSection:toggle({ name = "safe purchasing", flag = "shop_safe" })
purchaseSection:dropdown({ name = "avoid", flag = "shop_safe_avoid", items = { "target", "anyone" }, default = "target" })
purchaseSection:slider({ name = "avoid within", flag = "shop_safe_distance", min = 10, max = 200, default = 50, interval = 1, suffix = " st" })
purchaseSection:slider({ name = "keep cash", flag = "shop_keep_cash", min = 0, max = 50000, default = 5000, interval = 100, suffix = "$" })
purchaseSection:toggle({ name = "notifications", flag = "shop_notify", default = true })
purchaseSection:dropdown({ name = "item", flag = "shop_manual_item", items = #Shop.names > 0 and Shop.names or { "none" }, default = Shop.items["popcorn"] and "popcorn" or nil, scrolling = true })
purchaseSection:button({ name = "buy item", callback = function()
	local chosen = flag("shop_manual_item")

	if type(chosen) == "string" and not Shop.request(chosen) then
		notifications:create_notification({ name = "cannot buy " .. chosen .. " right now" })
	end
end })

local autoSection = shopColumn:section({ name = "auto armor" })
autoSection:toggle({ name = "enabled", flag = "shop_armor" })
autoSection:slider({ name = "buy if below", flag = "shop_armor_below", min = 1, max = 200, default = 52, interval = 1, suffix = "" })

local ammoSection = shopColumn:section({ name = "auto ammo" })
ammoSection:toggle({ name = "enabled", flag = "shop_ammo" })
ammoSection:slider({ name = "minimum clips", flag = "shop_ammo_clips", min = 0, max = 10, default = 2, interval = 1, suffix = "" })
ammoSection:slider({ name = "packs per purchase", flag = "shop_ammo_packs", min = 1, max = 20, default = 1, interval = 1, suffix = "" })

local shopColumn2 = shopTab:column({})
local healSection = shopColumn2:section({ name = "auto heal" })
healSection:toggle({ name = "enabled", flag = "shop_heal" })
healSection:slider({ name = "heal below", flag = "shop_heal_below", min = 1, max = 100, default = 50, interval = 1, suffix = "%" })
healSection:slider({ name = "eat every", flag = "shop_heal_cooldown", min = 0.05, max = 1, default = 0.3, interval = 0.05, suffix = "s" })

local maskSection = shopColumn2:section({ name = "auto mask" })
maskSection:toggle({ name = "enabled", flag = "shop_mask" })

local loadoutSection = shopColumn2:section({ name = "auto loadout" })
loadoutSection:toggle({ name = "enabled", flag = "shop_loadout" })
loadoutSection:dropdown({ name = "guns", flag = "shop_loadout_guns", items = { "rifle", "double-barrel sg", "flintlock", "revolver", "tacticalshotgun", "shotgun", "smg", "glock", "silencer", "knife" }, default = { "rifle" }, multi = true })
loadoutSection:slider({ name = "ammo packs", flag = "shop_loadout_packs", min = 0, max = 20, default = 5, interval = 1, suffix = "" })


local espColumn = visuals:column({})
local espSection = espColumn:section({ name = "player esp" })
espSection:toggle({ name = "enabled", flag = "esp_enabled" })
espSection:toggle({ name = "only target", flag = "esp_only_target" })
espSection:toggle({ name = "box", flag = "esp_box", default = true })
espSection:toggle({ name = "name", flag = "esp_name", default = true })
espSection:toggle({ name = "use display name", flag = "esp_display_name", default = true })
espSection:toggle({ name = "distance", flag = "esp_distance" })
espSection:dropdown({ name = "unit", flag = "esp_unit", items = { "studs", "metres" }, default = "studs" })
espSection:toggle({ name = "tool text", flag = "esp_tool" })
espSection:toggle({ name = "uppercase tool", flag = "esp_tool_upper" })
espSection:toggle({ name = "health bar", flag = "esp_health_bar", default = true })
espSection:toggle({ name = "health text", flag = "esp_health_text" })
espSection:toggle({ name = "hide health text if full", flag = "esp_health_hide_full", default = true })
espSection:toggle({ name = "armor bar", flag = "esp_armor_bar" })
espSection:toggle({ name = "hide armor bar if none", flag = "esp_armor_hide_none", default = true })
espSection:colorpicker({ name = "colour", flag = "esp_color", color = Color3.fromRGB(255, 255, 255) })
espSection:colorpicker({ name = "target colour", flag = "esp_target_color", color = Color3.fromRGB(255, 80, 80) })

local legit = window:tab({ name = "legit" })
local legitColumn = legit:column({})
local aimSection = legitColumn:section({ name = "aim assist" })
aimSection:toggle({ name = "enabled", flag = "aimassist_enabled" })
aimSection:keybind({ name = "aim key", flag = "aimassist_key", key = Enum.KeyCode.Q, mode = "Hold" })
aimSection:dropdown({ name = "method", flag = "aimassist_method", items = { "camera", "mouse" }, default = "camera" })
aimSection:dropdown({ name = "hitbox", flag = "aimassist_hitbox", items = { "head", "chest", "root" }, default = "head" })
aimSection:slider({ name = "field of view", flag = "aimassist_fov", min = 10, max = 800, default = 120, interval = 1, suffix = "px" })
aimSection:slider({ name = "max distance", flag = "aimassist_distance", min = 50, max = 3000, default = 500, interval = 10, suffix = " st" })
aimSection:slider({ name = "horizontal smoothing", flag = "aimassist_h_smooth", min = 1, max = 50, default = 6, interval = 1, suffix = "" })
aimSection:slider({ name = "vertical smoothing", flag = "aimassist_v_smooth", min = 1, max = 50, default = 6, interval = 1, suffix = "" })
aimSection:toggle({ name = "visible only", flag = "aimassist_visible", default = true })
aimSection:slider({ name = "target swap cooldown", flag = "legit_swap_cooldown", min = 0, max = 2, default = 0, interval = 0.05, suffix = "s" })
aimSection:toggle({ name = "show fov", flag = "aimassist_show_fov" })
aimSection:colorpicker({ name = "fov colour", flag = "aimassist_fov_color", color = Color3.fromRGB(255, 255, 255) })

local hits = window:tab({ name = "hits" })
local hitsColumn = hits:column({})
local markerSection = hitsColumn:section({ name = "hit markers" })
markerSection:toggle({ name = "2d hit marker", flag = "fb_marker2d" })
markerSection:slider({ name = "2d lifetime", flag = "fb_marker2d_life", min = 0.1, max = 2, default = 0.4, interval = 0.05, suffix = "s" })
markerSection:slider({ name = "2d thickness", flag = "fb_marker2d_thickness", min = 1, max = 5, default = 2, interval = 1, suffix = "px" })
markerSection:colorpicker({ name = "2d colour", flag = "fb_marker2d_color", color = Color3.fromRGB(255, 255, 255) })
markerSection:colorpicker({ name = "2d lethal colour", flag = "fb_marker2d_lethal", color = Color3.fromRGB(255, 60, 60) })
markerSection:toggle({ name = "3d hit marker", flag = "fb_marker3d" })
markerSection:slider({ name = "3d lifetime", flag = "fb_marker3d_life", min = 0.1, max = 3, default = 0.6, interval = 0.05, suffix = "s" })
markerSection:slider({ name = "3d thickness", flag = "fb_marker3d_thickness", min = 1, max = 5, default = 2, interval = 1, suffix = "px" })
markerSection:colorpicker({ name = "3d colour", flag = "fb_marker3d_color", color = Color3.fromRGB(255, 255, 255) })
markerSection:colorpicker({ name = "3d lethal colour", flag = "fb_marker3d_lethal", color = Color3.fromRGB(255, 60, 60) })

local damageSection = hitsColumn:section({ name = "damage number" })
damageSection:toggle({ name = "enabled", flag = "fb_damage" })
damageSection:slider({ name = "lifetime", flag = "fb_damage_life", min = 0.2, max = 3, default = 1, interval = 0.05, suffix = "s" })
damageSection:slider({ name = "size", flag = "fb_damage_size", min = 10, max = 40, default = 18, interval = 1, suffix = "px" })
damageSection:colorpicker({ name = "colour", flag = "fb_damage_color", color = Color3.fromRGB(255, 255, 255) })
damageSection:colorpicker({ name = "lethal colour", flag = "fb_damage_lethal", color = Color3.fromRGB(255, 60, 60) })

local soundSection = hitsColumn:section({ name = "hit sound" })
soundSection:toggle({ name = "enabled", flag = "fb_sound" })
soundSection:dropdown({ name = "sound", flag = "fb_sound_name", items = SOUND_NAMES, default = "neverlose", scrolling = true })
soundSection:slider({ name = "volume", flag = "fb_sound_volume", min = 0, max = 5, default = 1, interval = 0.1, suffix = "" })

local hitsColumn2 = hits:column({})
local overlaySection = hitsColumn2:section({ name = "hit overlay" })
overlaySection:toggle({ name = "enabled", flag = "fb_overlay" })
overlaySection:slider({ name = "lifetime", flag = "fb_overlay_life", min = 0.1, max = 2, default = 0.35, interval = 0.05, suffix = "s" })
overlaySection:colorpicker({ name = "colour", flag = "fb_overlay_color", color = Color3.fromRGB(255, 255, 255) })
overlaySection:colorpicker({ name = "lethal colour", flag = "fb_overlay_lethal", color = Color3.fromRGB(255, 60, 60) })

local chamsSection = hitsColumn2:section({ name = "hit chams" })
chamsSection:toggle({ name = "enabled", flag = "fb_chams" })
chamsSection:toggle({ name = "only last hit", flag = "fb_chams_last_only", default = true })
chamsSection:slider({ name = "lifetime", flag = "fb_chams_life", min = 0.1, max = 3, default = 0.5, interval = 0.05, suffix = "s" })
chamsSection:colorpicker({ name = "colour", flag = "fb_chams_color", color = Color3.fromRGB(255, 255, 255) })
chamsSection:colorpicker({ name = "lethal colour", flag = "fb_chams_lethal", color = Color3.fromRGB(255, 60, 60) })

local particleSection = hitsColumn2:section({ name = "hit particle" })
particleSection:toggle({ name = "enabled", flag = "fb_particle" })
particleSection:slider({ name = "amount", flag = "fb_particle_count", min = 1, max = 100, default = 20, interval = 1, suffix = "" })
particleSection:colorpicker({ name = "colour", flag = "fb_particle_color", color = Color3.fromRGB(255, 255, 255) })
particleSection:colorpicker({ name = "lethal colour", flag = "fb_particle_lethal", color = Color3.fromRGB(255, 60, 60) })

local skeletonSection = hitsColumn2:section({ name = "hit skeleton" })
skeletonSection:toggle({ name = "enabled", flag = "fb_skeleton" })
skeletonSection:slider({ name = "lifetime", flag = "fb_skeleton_life", min = 0.1, max = 3, default = 0.6, interval = 0.05, suffix = "s" })
skeletonSection:slider({ name = "thickness", flag = "fb_skeleton_thickness", min = 1, max = 5, default = 1, interval = 1, suffix = "px" })
skeletonSection:colorpicker({ name = "colour", flag = "fb_skeleton_color", color = Color3.fromRGB(255, 255, 255) })

local hitsColumn3 = hits:column({})
local tracerSection2 = hitsColumn3:section({ name = "bullet tracers" })
tracerSection2:toggle({ name = "local tracers", flag = "fb_tracer" })
tracerSection2:slider({ name = "lifetime", flag = "fb_tracer_life", min = 0.1, max = 3, default = 0.5, interval = 0.05, suffix = "s" })
tracerSection2:slider({ name = "thickness", flag = "fb_tracer_thickness", min = 1, max = 5, default = 1, interval = 1, suffix = "px" })
tracerSection2:colorpicker({ name = "colour", flag = "fb_tracer_color", color = Color3.fromRGB(255, 255, 255) })

local impactSection = hitsColumn3:section({ name = "bullet impacts" })
impactSection:toggle({ name = "local impacts", flag = "fb_impact" })
impactSection:slider({ name = "lifetime", flag = "fb_impact_life", min = 0.1, max = 3, default = 0.8, interval = 0.05, suffix = "s" })
impactSection:colorpicker({ name = "colour", flag = "fb_impact_color", color = Color3.fromRGB(255, 200, 80) })

local notifySection = hitsColumn3:section({ name = "shot notifications" })
notifySection:toggle({ name = "notify hits", flag = "fb_notify_hits" })
notifySection:toggle({ name = "notify shots with no hit", flag = "fb_notify_miss" })

local legitColumn2 = legit:column({})
local sharedSection = legitColumn2:section({ name = "shared" })
sharedSection:toggle({ name = "ignore knocked", flag = "legit_ignore_knocked", default = true })
sharedSection:toggle({ name = "ignore spawn protected", flag = "legit_ignore_protected", default = true })

local silentSection = legitColumn2:section({ name = "silent aim" })
silentSection:toggle({ name = "enabled", flag = "silent_enabled" })
silentSection:dropdown({ name = "hitbox", flag = "silent_hitbox", items = { "head", "chest", "root" }, default = "head" })
silentSection:slider({ name = "field of view", flag = "silent_fov", min = 10, max = 800, default = 120, interval = 1, suffix = "px" })
silentSection:slider({ name = "max distance", flag = "silent_distance", min = 50, max = 3000, default = 500, interval = 10, suffix = " st" })
silentSection:slider({ name = "max curve", flag = "silent_curve", min = 1, max = 90, default = 30, interval = 1, suffix = "deg" })
silentSection:toggle({ name = "dont curve vertically", flag = "silent_flat" })
silentSection:slider({ name = "redirect chance", flag = "silent_chance", min = 0, max = 100, default = 100, interval = 1, suffix = "%" })
silentSection:toggle({ name = "visible only", flag = "silent_visible", default = true })
silentSection:toggle({ name = "show fov", flag = "silent_show_fov" })
silentSection:colorpicker({ name = "fov colour", flag = "silent_fov_color", color = Color3.fromRGB(180, 180, 255) })

local triggerSection = legitColumn2:section({ name = "triggerbot" })
triggerSection:toggle({ name = "enabled", flag = "trigger_enabled" })
triggerSection:dropdown({ name = "hitboxes", flag = "trigger_hitboxes", items = { "head", "body", "arms", "legs" }, default = { "head", "body" }, multi = true })
triggerSection:slider({ name = "max distance (0 = gun range)", flag = "trigger_distance", min = 0, max = 2500, default = 0, interval = 10, suffix = " st" })
triggerSection:slider({ name = "refresh rate", flag = "trigger_refresh", min = 0, max = 0.5, default = 0, interval = 0.01, suffix = "s" })
triggerSection:slider({ name = "hover time", flag = "trigger_hover", min = 0, max = 0.3, default = 0, interval = 0.01, suffix = "s" })
triggerSection:slider({ name = "cooldown", flag = "trigger_cooldown", min = 0, max = 1, default = 0, interval = 0.01, suffix = "s" })
triggerSection:slider({ name = "delay", flag = "trigger_delay", min = 0, max = 0.5, default = 0, interval = 0.01, suffix = "s" })

local misc = window:tab({ name = "misc" })
local miscColumn = misc:column({})
local miscSection = miscColumn:section({ name = "script" })
local utilitySection = miscColumn:section({ name = "utility" })
utilitySection:toggle({ name = "anti bounty", flag = "antibounty_enabled" })
utilitySection:toggle({ name = "auto bounty", flag = "autobounty_enabled" })
utilitySection:toggle({ name = "anti stomp", flag = "antistomp_enabled" })
utilitySection:toggle({ name = "anti afk", flag = "utility_antiafk" })
utilitySection:toggle({ name = "watermark", flag = "utility_watermark", default = true, callback = function(visible)
	if library.watermark_outline then
		library.watermark_outline.Visible = visible
	end
end })
utilitySection:button({ name = "rejoin", callback = function()
	notifications:create_notification({ name = "rejoining..." })
	Utility.rejoin()
end })

miscSection:button({ name = "test notification", callback = function()
	notifications:create_notification({ name = "vanta is running" })
end })

local function unload()
	Ragebot.stop()
	Resolver.reset()
	Target.clear()
	environment.Vanta = nil

	if library then
		library:unload_menu()
	end
end

miscSection:button({ name = "unload", callback = unload })

library:init_config(window)

Ragebot.start()
environment.Vanta = { unload = unload, library = library, target = Target, resolver = Resolver, body = Body, voidspam = VoidSpam, autofire = AutoFire, follow = Follow, aim = Aim, visuals = Visuals, autostomp = AutoStomp, shop = Shop, bounty = Bounty, esp = Esp, feedback = Feedback, aimassist = AimAssist, legit = Legit, silent = SilentAim, trigger = Triggerbot, movement = Movement, utility = Utility, quickdraw = QuickDraw, adstrafe = AdStrafe, fullauto = FullAuto, antistomp = AntiStomp }

notifications:create_notification({ name = "loaded vanta" })
